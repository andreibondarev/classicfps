extends Node

## Dedicated-server moderation, driven by the admin service (deploy/admin).
## Enabled with --moderation=<path>.json. The admin service rewrites that file
## when an admin kicks, bans or mutes someone; this node reloads it when it
## changes and enforces it:
##   bans   [{tag, address, until, reason}]  refuse and drop matching peers
##   mutes  [{tag, until, reason}]           drop their chat and voice
##   kicks  [{id, peer, tag, reason, ts}]    drop a connected peer once
## A ban or mute matches the persistent client tag or the IP address (bans
## only); until 0 means permanent. Times are Unix seconds.

const POLL_INTERVAL := 1.0
## A kick is only acted on shortly after it was issued, so a server restart
## does not replay old kicks against reconnecting players.
const KICK_WINDOW_SECONDS := 120.0
const MAX_REASON_LENGTH := 80

signal enforced(event: Dictionary)

## Kick ids already carried out. Static: the dedicated server rebuilds its
## game scene (and this node) when the last player leaves.
static var _done_kicks: Dictionary = {}

var network: Node
var _path := ""
var _text := ""
var _elapsed := 0.0
var _bans: Array = []
var _mutes: Array = []
var _kicks: Array = []
var _dropping: Dictionary = {}


static func requested_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--moderation="):
			return argument.trim_prefix("--moderation=")
	return ""


func start(session: Node, path: String) -> bool:
	if path.is_empty() or not path.is_absolute_path():
		push_error("Moderation needs an absolute file path: %s" % path)
		return false
	network = session
	_path = path
	process_mode = Node.PROCESS_MODE_ALWAYS
	network.peer_joined.connect(func(peer_id: int) -> void: _enforce_ban(peer_id))
	network.peer_identified.connect(func(peer_id: int, _tag: String) -> void: _enforce_ban(peer_id))
	network.peer_left.connect(func(peer_id: int) -> void: _dropping.erase(peer_id))
	reload()
	return true


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < POLL_INTERVAL:
		return
	_elapsed = 0.0
	reload()
	# Bans also cover players already connected when the ban was issued.
	for peer_id: int in network.multiplayer.get_peers():
		_enforce_ban(peer_id)
	_enforce_kicks()


func reload() -> void:
	# Compare contents, not mtime: mtime has one-second resolution and two
	# admin actions can land in the same second. The file is small.
	var text := FileAccess.get_file_as_string(_path) if FileAccess.file_exists(_path) else "{}"
	if text == _text:
		return
	_text = text
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("Moderation file is not a JSON object: %s" % _path)
		return
	_bans = _entries(data, "bans")
	_mutes = _entries(data, "mutes")
	_kicks = _entries(data, "kicks")


static func _entries(data: Dictionary, key: String) -> Array:
	var result: Array = []
	var raw: Variant = data.get(key, [])
	if not raw is Array:
		return result
	for entry: Variant in raw:
		if entry is Dictionary:
			result.append(entry)
	return result


static func _active(entry: Dictionary, now: float) -> bool:
	var until := float(entry.get("until", 0))
	return until <= 0.0 or until > now


static func _reason(entry: Dictionary) -> String:
	return str(entry.get("reason", "")).strip_edges().left(MAX_REASON_LENGTH)


func _identity(peer_id: int) -> Dictionary:
	return {"tag": str(network.client_tag(peer_id)), "address": str(network.peer_endpoint(peer_id).address)}


func ban_for(peer_id: int) -> Dictionary:
	var who := _identity(peer_id)
	var now := Time.get_unix_time_from_system()
	for ban: Dictionary in _bans:
		if not _active(ban, now):
			continue
		var tag := str(ban.get("tag", ""))
		var address := str(ban.get("address", ""))
		if (not tag.is_empty() and tag == who.tag) or (not address.is_empty() and address == who.address):
			return ban
	return {}


func is_muted(peer_id: int) -> bool:
	var tag := str(network.client_tag(peer_id))
	if tag.is_empty():
		return false
	var now := Time.get_unix_time_from_system()
	for mute: Dictionary in _mutes:
		if _active(mute, now) and str(mute.get("tag", "")) == tag:
			return true
	return false


func _enforce_ban(peer_id: int) -> void:
	if _dropping.has(peer_id):
		return
	var ban := ban_for(peer_id)
	if ban.is_empty():
		return
	var reason := _reason(ban)
	var notice := "Banned from this server" + (": " + reason if not reason.is_empty() else "")
	if network.kick_peer(peer_id, notice):
		_dropping[peer_id] = true
		enforced.emit({"type": "ban_enforced", "peer": peer_id, "tag": _identity(peer_id).tag,
			"reason": reason})


func _enforce_kicks() -> void:
	var now := Time.get_unix_time_from_system()
	for kick: Dictionary in _kicks:
		var id := str(kick.get("id", ""))
		if id.is_empty() or _done_kicks.has(id) or now - float(kick.get("ts", 0)) > KICK_WINDOW_SECONDS:
			continue
		var peer_id := int(kick.get("peer", 0))
		var tag := str(kick.get("tag", ""))
		var target := 0
		for candidate: int in network.multiplayer.get_peers():
			# The tag guards against a peer id reused by somebody else.
			if candidate == peer_id and (tag.is_empty() or str(network.client_tag(candidate)) == tag):
				target = candidate
		if target == 0:
			continue
		_done_kicks[id] = true
		var reason := _reason(kick)
		var notice := "Kicked by admin" + (": " + reason if not reason.is_empty() else "")
		if network.kick_peer(target, notice):
			_dropping[target] = true
			enforced.emit({"type": "kick_enforced", "peer": target, "tag": tag, "reason": reason, "kick": id})
