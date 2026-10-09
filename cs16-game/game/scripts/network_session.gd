extends Node

signal status_changed(status: String)
signal snapshot_received(snapshot: Dictionary)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal peer_name_changed(peer_id: int, player_name: String)
signal action_result_received(result: Dictionary)
signal world_snapshot_received(snapshot: Dictionary)
signal combat_event_received(event: Dictionary)
signal chat_received(message: Dictionary)
## A relayed voice frame (one encoded Opus packet) from another player.
signal voice_received(sender_id: String, sequence: int, frame: PackedByteArray)

const WorldState = preload("res://scripts/network_world_state.gd")
const CombatEvents = preload("res://scripts/network_combat_events.gd")
const AudioCatalog = preload("res://scripts/cs16_audio_catalog.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const MultiTransportPeer = preload("res://scripts/network_multi_peer.gd")
const NAME_SEND_INTERVAL_MS := 250
var _name_peers: Dictionary = {}
var _sent_player_name := ""
var _next_name_send_ms := 0
var _combat_sequence := 0
var _last_combat_epoch := -1
var _last_combat_sequence := 0
var _chat_peers: Dictionary = {}
var _chat_request_sequence := 0
var _chat_event_sequence := 0
var _last_chat_epoch := -1
var _last_chat_sequence := 0
var _game_chat_handler := Callable()
var _voice_peers: Dictionary = {}
var _game_voice_handler := Callable()
var _voice_sequence := 0
## Host: each peer's self-reported install tag (settings.client_tag).
var _client_tags: Dictionary = {}
## Host: application-level round trip per peer (works for every transport).
const PING_INTERVAL_MS := 2000
var _peer_rtt: Dictionary = {}
var _ping_sent: Dictionary = {}
var _next_ping_ms := 0

const DEFAULT_PORT := 27447
## Path a browser build joins on the server it was loaded from; the reverse
## proxy forwards it to the dedicated server's WebSocket listener.
const WEB_SOCKET_PATH := "/ws"
const MAX_WEB_SOCKET_URL_LENGTH := 512
## WebSocket peers buffer whole messages and drop data once a buffer fills,
## which breaks reliable delivery. Browsers stall for seconds while loading
## models, and the server keeps streaming world snapshots meanwhile, so both
## ends hold far more than Godot's 64 KiB default.
const WEB_SOCKET_BUFFER_BYTES := 1 << 22
const WEB_SOCKET_MAX_QUEUED_PACKETS := 1 << 14
const MAX_CLIENTS := 10
const SNAPSHOT_HZ := 20.0
const MAX_INPUT_DISTANCE := 12.0
const ALLOWED_INPUT_BUTTONS := 0x3F
const PROTOCOL_VERSION := 1
const MAX_COUNTER := 0x7FFFFFFF
const MAX_WORLD_COORDINATE := 10000.0
const MAX_ROUND_TIME := 3600.0
const INPUT_TIMEOUT_MS := 250
const INPUT_RATE := 120.0
const INPUT_BURST := 16
const INPUT_FIELDS := ["version", "sequence", "movement", "yaw", "pitch", "buttons"]
const SNAPSHOT_FIELDS := ["version", "tick", "position", "velocity", "health", "phase", "round_time"]
const PHASES := ["deploy", "freeze", "live", "bomb", "post", "intermission"]
const ACTION_FIELDS := ["version", "sequence", "action", "value"]
const ACTION_RESULT_FIELDS := ["version", "sequence", "action", "accepted", "reason", "actor_id", "team", "class_id", "spawned"]
const ACTION_REASONS := ["", "unknown_peer", "match_not_live", "invalid_team", "already_joined",
	"invalid_replacement", "team_full", "team_stacked", "already_changed", "match_over",
	"no_spawn_slot", "invalid_class", "not_choosing_class", "no_game", "rate_limited", "internal_error", "timeout",
	"action_unavailable", "weapon_not_owned", "weapon_changed", "not_droppable",
	"item_unavailable", "wrong_team", "insufficient_funds", "already_owned_or_full",
	"unknown_player", "dead", "round_inactive", "outside_buy_zone", "buy_time_expired"]
const ACTION_RATE := 8.0
const ACTION_BURST := 8
const MAX_PENDING_ACTIONS := 16
const ACTION_TIMEOUT_MS := 5000
const CHAT_MAX_LENGTH := 120
const CHAT_RATE := 1.0
const CHAT_BURST := 4
const CHAT_REQUEST_FIELDS := ["version", "sequence", "team_only", "text"]
const CHAT_EVENT_FIELDS := ["version", "epoch", "sequence", "sender_id", "sender_name", "team", "team_only", "text"]
## Voice: 20 ms Opus frames (about 60 bytes at 24 kbps). The host relays each
## frame to the listeners the game allows, never trusting client routing.
const VOICE_MAX_FRAME_BYTES := 512
const VOICE_RATE := 60.0
const VOICE_BURST := 30
const WORLD_CHUNK_BYTES := 960
const MAX_WORLD_CHUNKS := 35
const WORLD_ASSEMBLY_TIMEOUT_MS := 1000
const CONNECTION_TIMEOUT_MS := 10000

var status := "OFFLINE"
var is_host := false
var latest_inputs: Dictionary = {}
var latest_snapshot: Dictionary = {}
var _input_sequence := 0
var _snapshot_accumulator := 0.0
var _input_peers: Dictionary = {}
var _last_snapshot_tick := -1
var _game_action_handler := Callable()
var _action_peers: Dictionary = {}
var _action_sequence := 0
var _pending_actions: Dictionary = {}
var latest_action_result: Dictionary = {}
var latest_world_snapshot: Dictionary = {}
var _world_epoch := 0
var _last_world_epoch := -1
var _last_world_tick := -1
var _world_accumulator := 0.0
var largest_world_packet_bytes := 0
var largest_world_snapshot_bytes := 0
var _world_assemblies: Dictionary = {}
var _connection_deadline_ms := 0
var _resolver_id := IP.RESOLVER_INVALID_ID
var _resolver_port := 0
var dedicated_server := false
var listen_port := DEFAULT_PORT
## WebSocket listener for browser clients; 0 disables it. The dedicated server
## defaults to the UDP port + 1.
var listen_web_socket_port := 0
var web_socket_bind_address := "*"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(func(peer_id: int) -> void:
		if is_host:
			_register_input_peer(peer_id, Time.get_ticks_msec())
		peer_joined.emit(peer_id)
	)
	multiplayer.peer_disconnected.connect(func(peer_id: int) -> void:
		_remove_input_peer(peer_id)
		peer_left.emit(peer_id)
	)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void:
		disconnect_session()
		_set_status("CONNECTION FAILED")
	)
	multiplayer.server_disconnected.connect(func() -> void:
		disconnect_session()
		_set_status("SERVER DISCONNECTED")
	)
	_start_from_command_line()


func _physics_process(_delta: float) -> void:
	_expire_connection(Time.get_ticks_msec())
	_poll_hostname()
	if is_host:
		expire_inputs(Time.get_ticks_msec())
		_send_pings(Time.get_ticks_msec())
	else:
		_publish_player_name()
		expire_actions(Time.get_ticks_msec())
		expire_world_assemblies(Time.get_ticks_msec())


func _start_from_command_line() -> void:
	var arguments := OS.get_cmdline_user_args()
	dedicated_server = OS.has_feature("dedicated_server") or arguments.has("--dedicated")
	var should_host := dedicated_server or arguments.has("--host")
	var requested_web_socket_port := ""
	for argument in arguments:
		if argument.begins_with("--port="):
			var requested_port := argument.trim_prefix("--port=")
			if requested_port.is_valid_int() and int(requested_port) in range(1, 65536):
				listen_port = int(requested_port)
			else:
				push_error("Invalid listen port: %s" % requested_port)
				if dedicated_server:
					get_tree().quit(2)
				return
		elif argument.begins_with("--ws-port="):
			requested_web_socket_port = argument.trim_prefix("--ws-port=")
		elif argument.begins_with("--ws-bind="):
			web_socket_bind_address = argument.trim_prefix("--ws-bind=")
	if not requested_web_socket_port.is_empty():
		if requested_web_socket_port.is_valid_int() and int(requested_web_socket_port) in range(0, 65536):
			listen_web_socket_port = int(requested_web_socket_port)
		else:
			push_error("Invalid WebSocket port: %s" % requested_web_socket_port)
			if dedicated_server:
				get_tree().quit(2)
			return
	elif dedicated_server and listen_port < 65535:
		listen_web_socket_port = listen_port + 1
	if should_host:
		var result := host_game(listen_port, "*", listen_web_socket_port)
		if dedicated_server:
			if result == OK:
				var web_socket := (", WebSocket %d" % listen_web_socket_port) if listen_web_socket_port > 0 else ""
				print("Classic FPS dedicated server listening on UDP %d%s (de_dust2, 10 slots)" % [listen_port, web_socket])
			else:
				push_error("Dedicated server could not bind UDP %d / WebSocket %d: %s" % [listen_port, listen_web_socket_port, error_string(result)])
				get_tree().quit(1)
		return
	for argument in arguments:
		if argument.begins_with("--join="):
			join_game(argument.trim_prefix("--join="), listen_port)
			return
	if OS.has_feature("web"):
		_join_from_web_page()


## Browser builds join the server named by ?server=<ws(s) URL>, or by default
## the server that served the page (its WebSocket path). ?offline plays
## locally against bots instead.
func _join_from_web_page() -> void:
	if web_page_query("offline") != null:
		return
	var requested = web_page_query("server")
	join_game(str(requested) if requested != null else default_web_server_url())


static func web_page_query(name: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	var value: Variant = JavaScriptBridge.eval(
		"(new URLSearchParams(window.location.search)).get(%s)" % JSON.stringify(name), true)
	return value if value is String else null


static func default_web_server_url() -> String:
	if not OS.has_feature("web"):
		return ""
	var secure := str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:"
	var host := str(JavaScriptBridge.eval("window.location.host", true))
	return "%s://%s%s" % ["wss" if secure else "ws", host, WEB_SOCKET_PATH]


static func is_web_socket_url(address: String) -> bool:
	return address.begins_with("ws://") or address.begins_with("wss://")


func host_game(port := DEFAULT_PORT, bind_address := "*", web_socket_port := 0) -> Error:
	disconnect_session()
	if OS.has_feature("web"):
		# Browsers cannot listen for UDP or WebSocket connections.
		_set_status("HOSTING IS NOT AVAILABLE IN THE BROWSER")
		return ERR_UNAVAILABLE
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_address)
	var result := peer.create_server(port, MAX_CLIENTS, 3)
	if result != OK:
		_set_status("HOST FAILED")
		return result
	var session_peer: MultiplayerPeer = peer
	if web_socket_port > 0:
		var web_socket := _new_web_socket_peer()
		result = web_socket.create_server(web_socket_port, web_socket_bind_address)
		if result != OK:
			peer.close()
			_set_status("HOST FAILED")
			return result
		var combined := MultiTransportPeer.new(MAX_CLIENTS)
		combined.add_transport(peer)
		combined.add_transport(web_socket)
		session_peer = combined
	multiplayer.multiplayer_peer = session_peer
	is_host = true
	_world_epoch += 1
	_register_input_peer(1, Time.get_ticks_msec())
	_set_status("HOST  :%d" % port)
	return OK


func join_game(address := "127.0.0.1", port := DEFAULT_PORT) -> Error:
	disconnect_session()
	_connection_deadline_ms = Time.get_ticks_msec() + CONNECTION_TIMEOUT_MS
	if is_web_socket_url(address):
		return _connect_web_socket(address)
	if OS.has_feature("web"):
		# Browsers cannot send UDP; reach the host's WebSocket listener.
		var secure := str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:"
		return _connect_web_socket("%s://%s:%d" % ["wss" if secure else "ws", address, port])
	if not address.is_valid_ip_address():
		# ENet resolves hostnames synchronously. Queue DNS first so a failed
		# lookup cannot freeze the menu or prevent cancellation and timeout.
		_resolver_id = IP.resolve_hostname_queue_item(address)
		if _resolver_id == IP.RESOLVER_INVALID_ID:
			_connection_deadline_ms = 0
			_set_status("HOSTNAME LOOKUP UNAVAILABLE")
			return ERR_CANT_RESOLVE
		_resolver_port = port
		_set_status("RESOLVING  " + address)
		return OK
	return _connect_address(address, port)


func _connect_address(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port, 3)
	if result != OK:
		_connection_deadline_ms = 0
		_set_status("JOIN FAILED")
		return result
	multiplayer.multiplayer_peer = peer
	is_host = false
	_set_status("CONNECTING  %s:%d" % [address, port])
	return OK


static func _new_web_socket_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = WEB_SOCKET_BUFFER_BYTES
	peer.outbound_buffer_size = WEB_SOCKET_BUFFER_BYTES
	peer.max_queued_packets = WEB_SOCKET_MAX_QUEUED_PACKETS
	return peer


func _connect_web_socket(url: String) -> Error:
	var peer := _new_web_socket_peer()
	var result := peer.create_client(url)
	if result != OK:
		_connection_deadline_ms = 0
		_set_status("JOIN FAILED")
		return result
	multiplayer.multiplayer_peer = peer
	is_host = false
	_set_status("CONNECTING  %s" % url)
	return OK


func disconnect_session() -> void:
	_connection_deadline_ms = 0
	if _resolver_id != IP.RESOLVER_INVALID_ID:
		IP.erase_resolve_item(_resolver_id)
		_resolver_id = IP.RESOLVER_INVALID_ID
	_resolver_port = 0
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	latest_inputs.clear()
	latest_snapshot.clear()
	_input_peers.clear()
	_name_peers.clear()
	_chat_peers.clear()
	_voice_peers.clear()
	_voice_sequence = 0
	_client_tags.clear()
	_peer_rtt.clear()
	_ping_sent.clear()
	_next_ping_ms = 0
	_sent_player_name = ""
	_next_name_send_ms = 0
	_input_sequence = 0
	_snapshot_accumulator = 0.0
	_last_snapshot_tick = -1
	_action_peers.clear()
	_action_sequence = 0
	_pending_actions.clear()
	latest_action_result.clear()
	latest_world_snapshot.clear()
	_combat_sequence = 0
	_last_combat_epoch = -1
	_last_combat_sequence = 0
	_chat_request_sequence = 0
	_chat_event_sequence = 0
	_last_chat_epoch = -1
	_last_chat_sequence = 0
	_last_world_epoch = -1
	_last_world_tick = -1
	_world_accumulator = 0.0
	largest_world_packet_bytes = 0
	largest_world_snapshot_bytes = 0
	_world_assemblies.clear()
	_set_status("OFFLINE")


func _on_connected() -> void:
	_connection_deadline_ms = 0
	_set_status("CONNECTED  #%d" % multiplayer.get_unique_id())
	_publish_player_name()
	_submit_client_tag.rpc_id(1, str(get_node("/root/GameSettings").client_tag))


@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_client_tag(tag: Variant) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if is_host and multiplayer.is_server() and has_input_peer(peer_id) \
			and not _client_tags.has(peer_id) and SettingsScript.is_valid_client_tag(tag):
		_client_tags[peer_id] = str(tag)


func _send_pings(now_ms: int) -> void:
	if not is_online() or now_ms < _next_ping_ms:
		return
	_next_ping_ms = now_ms + PING_INTERVAL_MS
	for peer_id: int in multiplayer.get_peers():
		if has_input_peer(peer_id):
			_ping_sent[peer_id] = now_ms
			_server_ping.rpc_id(peer_id, now_ms)


@rpc("authority", "call_remote", "reliable", 2)
func _server_ping(stamp: Variant) -> void:
	if not is_host and typeof(stamp) == TYPE_INT:
		_client_pong.rpc_id(1, stamp)


@rpc("any_peer", "call_remote", "reliable", 2)
func _client_pong(stamp: Variant) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	# Only the latest ping this host actually sent counts; replies are not trusted
	# to carry their own timing.
	if not is_host or typeof(stamp) != TYPE_INT or int(_ping_sent.get(peer_id, -1)) != int(stamp) \
			or now - int(stamp) > 10000:
		return
	_ping_sent.erase(peer_id)
	var sample := float(now - int(stamp))
	_peer_rtt[peer_id] = sample if not _peer_rtt.has(peer_id) else lerpf(float(_peer_rtt[peer_id]), sample, 0.3)


## Host: round trip, loss (ENet only) and payload bytes for the admin dashboard.
func peer_quality(peer_id: int) -> Dictionary:
	var quality := {"rtt_ms": roundf(float(_peer_rtt.get(peer_id, -1.0))), "loss": -1.0, "bytes_in": 0, "bytes_out": 0}
	var transport: MultiplayerPeer = multiplayer.multiplayer_peer
	if transport is MultiTransportPeer:
		var traffic: Dictionary = (transport as MultiTransportPeer).traffic().get(peer_id, {})
		quality.bytes_in = int(traffic.get("in", 0))
		quality.bytes_out = int(traffic.get("out", 0))
		transport = (transport as MultiTransportPeer).transport_for_peer(peer_id)
	if transport is ENetMultiplayerPeer:
		var packet_peer := (transport as ENetMultiplayerPeer).get_peer(peer_id)
		if packet_peer != null:
			quality.loss = packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE)
	return quality


func client_tag(peer_id: int) -> String:
	return str(_client_tags.get(peer_id, ""))


## Host: how a peer is connected. Browser peers arrive through the reverse
## proxy, so their address is the proxy's (127.0.0.1).
func peer_endpoint(peer_id: int) -> Dictionary:
	var transport: MultiplayerPeer = multiplayer.multiplayer_peer
	if transport is MultiTransportPeer:
		transport = (transport as MultiTransportPeer).transport_for_peer(peer_id)
	if transport is ENetMultiplayerPeer:
		var packet_peer := (transport as ENetMultiplayerPeer).get_peer(peer_id)
		if packet_peer != null:
			return {"transport": "udp", "address": packet_peer.get_remote_address(), "port": packet_peer.get_remote_port()}
	elif transport is WebSocketMultiplayerPeer:
		return {"transport": "ws", "address": (transport as WebSocketMultiplayerPeer).get_peer_address(peer_id),
			"port": (transport as WebSocketMultiplayerPeer).get_peer_port(peer_id)}
	return {"transport": "", "address": "", "port": 0}


func _publish_player_name() -> void:
	if is_host or not is_online() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	var now := Time.get_ticks_msec()
	var desired: String = get_node("/root/GameSettings").player_name
	if desired == _sent_player_name or now < _next_name_send_ms:
		return
	_sent_player_name = desired
	_next_name_send_ms = now + NAME_SEND_INTERVAL_MS
	_submit_player_name.rpc_id(1, desired)


@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_player_name(value: Variant) -> void:
	if is_host and multiplayer.is_server():
		accept_peer_name(multiplayer.get_remote_sender_id(), value, Time.get_ticks_msec())


func peer_player_name(peer_id: int, fallback: String) -> String:
	return str(_name_peers.get(peer_id, {}).get("name", fallback))


func accept_peer_name(peer_id: int, value: Variant, now_ms: int) -> bool:
	# A display name never changes the durable actor ID, slot, team or score.
	# Bound and validate before scanning text; only a registered sender owns it.
	if peer_id <= 1 or not has_input_peer(peer_id) or not _name_peers.has(peer_id):
		return false
	if typeof(value) != TYPE_STRING or value.length() > SettingsScript.MAX_PLAYER_NAME_LENGTH or value != SettingsScript.sanitize_player_name(value):
		return false
	var state: Dictionary = _name_peers[peer_id]
	if now_ms < int(state.token_ms):
		return false
	state.tokens = minf(8.0, float(state.tokens) + float(now_ms - int(state.token_ms)) * 0.008)
	state.token_ms = now_ms
	if float(state.tokens) < 1.0:
		return false
	state.tokens = float(state.tokens) - 1.0
	if str(state.get("name", "")) != value:
		state.name = value
		peer_name_changed.emit(peer_id, value)
	return true


static func sanitize_chat_text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var cleaned := ""
	for character: String in value:
		var code := character.unicode_at(0)
		# Newlines/control codes and bidirectional overrides must never turn one
		# bounded chat row into a deceptive multi-line or reordered message.
		if code < 32 or (code >= 127 and code <= 159) \
				or code in [0x200B, 0x200E, 0x200F, 0x2028, 0x2029, 0xFEFF] \
				or (code >= 0x202A and code <= 0x202E) \
				or (code >= 0x2066 and code <= 0x2069):
			continue
		cleaned += character
	return cleaned.strip_edges().left(CHAT_MAX_LENGTH).strip_edges()


## The game decides who hears a speaker: handler(peer_id) returns
## {"sender_id": String, "recipients": Array[int]} or {} to drop the frame.
func bind_voice(handler: Callable) -> bool:
	if not handler.is_valid():
		return false
	_game_voice_handler = handler
	return true


func unbind_voice(handler: Callable) -> void:
	if _game_voice_handler == handler:
		_game_voice_handler = Callable()


## Client: send one encoded frame to the host for relay.
func submit_voice_frame(frame: PackedByteArray) -> bool:
	if is_host or not is_online() or frame.is_empty() or frame.size() > VOICE_MAX_FRAME_BYTES \
			or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	_voice_sequence = (_voice_sequence % MAX_COUNTER) + 1
	_submit_voice.rpc_id(1, _voice_sequence, frame)
	return true


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _submit_voice(sequence: Variant, frame: Variant) -> void:
	if not is_host or not multiplayer.is_server():
		return
	accept_peer_voice(multiplayer.get_remote_sender_id(), sequence, frame, Time.get_ticks_msec())


func accept_peer_voice(peer_id: int, sequence: Variant, frame: Variant, now_ms: int) -> bool:
	if not has_input_peer(peer_id) or not _voice_peers.has(peer_id) or peer_id == 1:
		return false
	if not _valid_integer(sequence, 1, MAX_COUNTER) or typeof(frame) != TYPE_PACKED_BYTE_ARRAY \
			or (frame as PackedByteArray).is_empty() or (frame as PackedByteArray).size() > VOICE_MAX_FRAME_BYTES:
		return false
	var state: Dictionary = _voice_peers[peer_id]
	# A wrapped or restarted counter is accepted; only stale replays drop.
	if int(sequence) <= int(state.sequence) and int(state.sequence) - int(sequence) < 1000:
		return false
	state.sequence = int(sequence)
	state.tokens = minf(VOICE_BURST, float(state.tokens) + float(now_ms - int(state.token_ms)) * VOICE_RATE / 1000.0)
	state.token_ms = now_ms
	if float(state.tokens) < 1.0:
		return false
	state.tokens = float(state.tokens) - 1.0
	if not _game_voice_handler.is_valid():
		return false
	var route: Dictionary = _game_voice_handler.call(peer_id)
	if route.is_empty() or not WorldState.identifier(str(route.get("sender_id", ""))):
		return false
	var delivered := false
	for recipient: int in route.get("recipients", []):
		if recipient > 1 and recipient != peer_id and has_input_peer(recipient) and multiplayer.get_peers().has(recipient):
			_receive_voice.rpc_id(recipient, str(route.sender_id), int(sequence), frame)
			delivered = true
	return delivered


@rpc("authority", "call_remote", "unreliable_ordered", 0)
func _receive_voice(sender_id: Variant, sequence: Variant, frame: Variant) -> void:
	if is_host or typeof(sender_id) != TYPE_STRING or not WorldState.identifier(sender_id) \
			or not _valid_integer(sequence, 1, MAX_COUNTER) or typeof(frame) != TYPE_PACKED_BYTE_ARRAY \
			or (frame as PackedByteArray).is_empty() or (frame as PackedByteArray).size() > VOICE_MAX_FRAME_BYTES:
		return
	voice_received.emit(sender_id, int(sequence), frame)


func bind_chat(handler: Callable) -> bool:
	if not handler.is_valid() or (_game_chat_handler.is_valid() and _game_chat_handler != handler):
		return false
	_game_chat_handler = handler
	return true


func unbind_chat(handler: Callable) -> void:
	if _game_chat_handler == handler:
		_game_chat_handler = Callable()


func request_chat(text: Variant, team_only: bool) -> bool:
	if not is_online() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	if _chat_request_sequence >= MAX_COUNTER:
		return false
	var cleaned := sanitize_chat_text(text)
	if cleaned.is_empty():
		return false
	_chat_request_sequence += 1
	var packet := {"version": PROTOCOL_VERSION, "sequence": _chat_request_sequence,
		"team_only": team_only, "text": cleaned}
	if is_host:
		return accept_peer_chat_request(1, packet, Time.get_ticks_msec(), true)
	_submit_chat.rpc_id(1, packet)
	return true


func validate_chat_request(packet: Variant) -> Dictionary:
	if not _packet_keys(packet, CHAT_REQUEST_FIELDS) \
			or not _valid_integer(packet.version, PROTOCOL_VERSION, PROTOCOL_VERSION) \
			or not _valid_integer(packet.sequence, 1, MAX_COUNTER) \
			or typeof(packet.team_only) != TYPE_BOOL or typeof(packet.text) != TYPE_STRING:
		return {}
	var cleaned := sanitize_chat_text(packet.text)
	if cleaned.is_empty() or cleaned != packet.text:
		return {}
	return packet.duplicate()


@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_chat(packet: Variant) -> void:
	if not is_host or not multiplayer.is_server():
		return
	accept_peer_chat_request(multiplayer.get_remote_sender_id(), packet, Time.get_ticks_msec())


func accept_peer_chat_request(peer_id: int, packet: Variant, now_ms: int, trusted_local := false) -> bool:
	# ENet supplies sender identity; the request deliberately has no name, team,
	# actor ID or recipient fields for a client to spoof.
	if not has_input_peer(peer_id) or not _chat_peers.has(peer_id) \
			or (peer_id == 1 and not trusted_local):
		return false
	var request := validate_chat_request(packet)
	var state: Dictionary = _chat_peers[peer_id]
	if request.is_empty() or int(request.sequence) <= int(state.sequence) or now_ms < int(state.token_ms):
		return false
	state.sequence = int(request.sequence)
	state.tokens = minf(CHAT_BURST, float(state.tokens) + float(now_ms - int(state.token_ms)) * CHAT_RATE / 1000.0)
	state.token_ms = now_ms
	if float(state.tokens) < 1.0:
		return false
	state.tokens = float(state.tokens) - 1.0
	if not _game_chat_handler.is_valid():
		return false
	return bool(_game_chat_handler.call(peer_id, bool(request.team_only), str(request.text)))


func publish_chat(
	sender_id: String,
	sender_name: String,
	team: String,
	team_only: bool,
	text: String,
	recipient_peers: Array[int],
) -> bool:
	if not is_host or _world_epoch < 1 or _chat_event_sequence >= MAX_COUNTER:
		return false
	_chat_event_sequence += 1
	var packet := {"version": PROTOCOL_VERSION, "epoch": _world_epoch,
		"sequence": _chat_event_sequence, "sender_id": sender_id,
		"sender_name": sender_name, "team": team, "team_only": team_only, "text": text}
	if validate_chat_event(packet).is_empty():
		return false
	var delivered := false
	if recipient_peers.has(1):
		chat_received.emit(packet.duplicate())
		delivered = true
	if is_online():
		for peer_id: int in recipient_peers:
			if peer_id > 1 and has_input_peer(peer_id) and multiplayer.get_peers().has(peer_id):
				_receive_chat.rpc_id(peer_id, packet)
				delivered = true
	return delivered


func validate_chat_event(packet: Variant) -> Dictionary:
	if not _packet_keys(packet, CHAT_EVENT_FIELDS) \
			or not _valid_integer(packet.version, PROTOCOL_VERSION, PROTOCOL_VERSION) \
			or not _valid_integer(packet.epoch, 1, MAX_COUNTER) \
			or not _valid_integer(packet.sequence, 1, MAX_COUNTER):
		return {}
	if typeof(packet.sender_id) != TYPE_STRING or not WorldState.identifier(packet.sender_id):
		return {}
	if typeof(packet.sender_name) != TYPE_STRING \
			or packet.sender_name != SettingsScript.sanitize_player_name(packet.sender_name):
		return {}
	if typeof(packet.team) != TYPE_STRING or packet.team not in ["UNASSIGNED", "T", "CT"] \
			or typeof(packet.team_only) != TYPE_BOOL or typeof(packet.text) != TYPE_STRING:
		return {}
	if sanitize_chat_text(packet.text).is_empty() or sanitize_chat_text(packet.text) != packet.text \
			or var_to_bytes(packet).size() > 768:
		return {}
	return packet.duplicate()


@rpc("authority", "call_remote", "reliable", 2)
func _receive_chat(packet: Variant) -> void:
	if not is_host and is_online():
		accept_chat_event(packet)


func accept_chat_event(packet: Variant) -> bool:
	var message := validate_chat_event(packet)
	if message.is_empty() or int(message.epoch) < _last_chat_epoch \
			or (int(message.epoch) == _last_chat_epoch and int(message.sequence) <= _last_chat_sequence):
		return false
	_last_chat_epoch = int(message.epoch)
	_last_chat_sequence = int(message.sequence)
	chat_received.emit(message)
	return true


func _expire_connection(now_ms: int) -> bool:
	if _connection_deadline_ms == 0 or now_ms < _connection_deadline_ms:
		return false
	disconnect_session()
	_set_status("CONNECTION TIMED OUT")
	return true


func _poll_hostname() -> void:
	if _resolver_id == IP.RESOLVER_INVALID_ID:
		return
	var resolve_status := IP.get_resolve_item_status(_resolver_id)
	if resolve_status == IP.RESOLVER_STATUS_WAITING:
		return
	var address := IP.get_resolve_item_address(_resolver_id) if resolve_status == IP.RESOLVER_STATUS_DONE else ""
	IP.erase_resolve_item(_resolver_id)
	_resolver_id = IP.RESOLVER_INVALID_ID
	var port := _resolver_port
	_resolver_port = 0
	if address.is_valid_ip_address():
		_connect_address(address, port)
	else:
		disconnect_session()
		_set_status("HOSTNAME NOT FOUND")


func is_connecting() -> bool:
	return _connection_deadline_ms > 0


static func connection_endpoint(address: String, port_text: String) -> Dictionary:
	var trimmed := address.strip_edges()
	if is_web_socket_url(trimmed):
		# A WebSocket URL carries its own port and path; the port field is unused.
		var url_endpoint := {"valid": false, "reason": "Enter a ws:// or wss:// URL with a host.", "address": trimmed, "port": 0}
		var rest := trimmed.substr(trimmed.find("://") + 3)
		var host := rest.split("/", true, 1)[0]
		if trimmed.length() <= MAX_WEB_SOCKET_URL_LENGTH and not host.is_empty() and not host.begins_with(":") \
				and not " " in trimmed and not "@" in host:
			url_endpoint.valid = true
			url_endpoint.reason = ""
		return url_endpoint
	var endpoint := {"valid": false, "reason": "Use a UDP port from 1024 to 65535.", "address": trimmed, "port": 0}
	if port_text.is_empty() or port_text.length() > 5:
		return endpoint
	for character: String in port_text:
		if character < "0" or character > "9":
			return endpoint
	endpoint.port = port_text.to_int()
	if endpoint.port < 1024 or endpoint.port > 65535:
		return endpoint
	endpoint.reason = "Enter an IP address or hostname, without a URL or port."
	var host: String = endpoint.address
	if host.is_empty() or host.length() > 253:
		return endpoint
	if not host.is_valid_ip_address():
		for label: String in host.split("."):
			if label.is_empty() or label.length() > 63 or label.begins_with("-") or label.ends_with("-"):
				return endpoint
			for character: String in label.to_lower():
				if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character == "-"):
					return endpoint
	endpoint.valid = true
	endpoint.reason = ""
	return endpoint


func _set_status(value: String) -> void:
	status = value
	if OS.has_feature("web"):
		# The browser console is the only log a web player can share.
		print("PROTOCOL47_NET %s" % status)
	status_changed.emit(status)


func is_online() -> bool:
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func submit_local_input(command: Dictionary) -> void:
	if not is_online():
		return
	if _input_sequence >= MAX_COUNTER:
		disconnect_session()
		_set_status("INPUT SEQUENCE EXHAUSTED")
		return
	_input_sequence += 1
	var sanitized := sanitize_input(command, _input_sequence)
	if is_host:
		# Locally generated host input is not subject to remote burst policing.
		accept_peer_input(1, sanitized, Time.get_ticks_msec(), true)
	elif is_online():
		_submit_input.rpc_id(1, sanitized)


@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func _submit_input(command: Variant) -> void:
	if not is_host or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > 1:
		accept_peer_input(sender, command, Time.get_ticks_msec())


func sanitize_input(command: Dictionary, sequence: int) -> Dictionary:
	var raw: Variant = command.get("movement")
	var movement: Vector2 = raw if typeof(raw) == TYPE_VECTOR2 and raw.is_finite() else Vector2.ZERO
	return {
		"version": PROTOCOL_VERSION,
		"sequence": clampi(sequence, 0, MAX_COUNTER),
		"movement": movement.limit_length(1.0),
		"yaw": wrapf(_number(command.get("yaw")), -PI, PI),
		"pitch": clampf(_number(command.get("pitch")), -PI * 0.495, PI * 0.495),
		"buttons": _integer(command.get("buttons"), 0, MAX_COUNTER) & ALLOWED_INPUT_BUTTONS,
	}


func validate_input(packet: Variant) -> Dictionary:
	if not _packet_keys(packet, INPUT_FIELDS) or not _valid_integer(packet.version, PROTOCOL_VERSION, PROTOCOL_VERSION):
		return {}
	if not _valid_integer(packet.sequence, 1, MAX_COUNTER) or not _valid_integer(packet.buttons, 0, ALLOWED_INPUT_BUTTONS):
		return {}
	if typeof(packet.movement) != TYPE_VECTOR2 or not packet.movement.is_finite() or packet.movement.length_squared() > 1.000001:
		return {}
	if not _valid_number(packet.yaw) or absf(float(packet.yaw)) > PI:
		return {}
	if not _valid_number(packet.pitch) or absf(float(packet.pitch)) > PI * 0.495 + 0.000001:
		return {}
	return sanitize_input(packet, packet.sequence)


func _register_input_peer(peer_id: int, now_ms: int) -> bool:
	if peer_id < 1 or peer_id > MAX_COUNTER or now_ms < 0 or _input_peers.has(peer_id) or _input_peers.size() >= MAX_CLIENTS + 1:
		return false
	_input_peers[peer_id] = {"sequence": 0, "received_ms": -1, "token_ms": now_ms, "tokens": float(INPUT_BURST)}
	_action_peers[peer_id] = {"sequence": 0, "token_ms": now_ms, "tokens": float(ACTION_BURST)}
	_name_peers[peer_id] = {"token_ms": now_ms, "tokens": 8.0}
	_chat_peers[peer_id] = {"sequence": 0, "token_ms": now_ms, "tokens": float(CHAT_BURST)}
	_voice_peers[peer_id] = {"sequence": 0, "token_ms": now_ms, "tokens": float(VOICE_BURST)}
	return true


func _remove_input_peer(peer_id: int) -> void:
	_input_peers.erase(peer_id)
	latest_inputs.erase(peer_id)
	_action_peers.erase(peer_id)
	_name_peers.erase(peer_id)
	_chat_peers.erase(peer_id)
	_voice_peers.erase(peer_id)
	_client_tags.erase(peer_id)
	_peer_rtt.erase(peer_id)
	_ping_sent.erase(peer_id)


func has_input_peer(peer_id: int) -> bool:
	return is_host and _input_peers.has(peer_id)


func input_for_peer(peer_id: int) -> Dictionary:
	# Consumers may alter their command without mutating retained wire state.
	return latest_inputs.get(peer_id, {}).duplicate() if has_input_peer(peer_id) else {}


func accept_peer_input(peer_id: int, packet: Variant, now_ms: int, trusted_local := false) -> bool:
	if not _input_peers.has(peer_id):
		return false
	var state: Dictionary = _input_peers[peer_id]
	if now_ms < int(state.token_ms):
		return false
	var command := validate_input(packet)
	if command.is_empty() or int(command.sequence) <= int(state.sequence):
		return false
	state.tokens = minf(INPUT_BURST, float(state.tokens) + float(now_ms - int(state.token_ms)) * INPUT_RATE / 1000.0)
	state.token_ms = now_ms
	if not (trusted_local and peer_id == 1):
		if float(state.tokens) < 1.0:
			return false
		state.tokens = float(state.tokens) - 1.0
	state.sequence = command.sequence
	state.received_ms = now_ms
	latest_inputs[peer_id] = command
	return true


func expire_inputs(now_ms: int) -> void:
	# Keep sequence history after expiry: replaying an old held-fire command
	# must not reactivate it. Missing input is neutral, not indefinite holding.
	for peer_id: int in _input_peers:
		var state: Dictionary = _input_peers[peer_id]
		if int(state.received_ms) >= 0 and now_ms - int(state.received_ms) >= INPUT_TIMEOUT_MS:
			latest_inputs.erase(peer_id)


func bind_game_actions(handler: Callable) -> bool:
	if not handler.is_valid() or (_game_action_handler.is_valid() and _game_action_handler != handler):
		return false
	_game_action_handler = handler
	_world_epoch += 1
	return true


func unbind_game_actions(handler: Callable) -> void:
	if _game_action_handler == handler:
		_game_action_handler = Callable()


func request_join_team(team: String) -> int:
	return submit_action("join_team", team)


func request_join_class(class_id: int) -> int:
	return submit_action("join_class", class_id)


func request_weapon(weapon: String) -> int:
	return submit_action("select_weapon", weapon)


func request_secondary(weapon: String) -> int:
	return submit_action("secondary", weapon)


func request_reload(weapon: String) -> int:
	return submit_action("reload_weapon", weapon)


func request_drop(weapon: String) -> int:
	return submit_action("drop_weapon", weapon)


func request_buy(item: String) -> int:
	return submit_action("buy_item", item)


func request_radio(sample_id: String) -> int:
	return submit_action("radio", sample_id)


func submit_action(action: String, value: Variant) -> int:
	# A successful return reserves a request, not a successful gameplay action.
	# The owner receives the authoritative result on the reliable action channel.
	if is_host or not is_online() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return 0
	if _pending_actions.size() >= MAX_PENDING_ACTIONS or _action_sequence >= MAX_COUNTER:
		return 0
	var packet := {"version": PROTOCOL_VERSION, "sequence": _action_sequence + 1, "action": action, "value": value}
	if validate_action(packet).is_empty():
		return 0
	_action_sequence += 1
	_pending_actions[_action_sequence] = {"action": action, "value": value, "sent_ms": Time.get_ticks_msec()}
	_submit_action.rpc_id(1, packet)
	return _action_sequence


func validate_action(packet: Variant) -> Dictionary:
	if not _packet_keys(packet, ACTION_FIELDS) or not _valid_integer(packet.version, PROTOCOL_VERSION, PROTOCOL_VERSION):
		return {}
	if not _valid_integer(packet.sequence, 1, MAX_COUNTER) or typeof(packet.action) != TYPE_STRING:
		return {}
	match packet.action:
		"spray":
			if typeof(packet.value) != TYPE_STRING or packet.value != "":
				return {}
		"join_team":
			if typeof(packet.value) != TYPE_STRING or packet.value not in ["T", "CT"]:
				return {}
		"join_class":
			if not _valid_integer(packet.value, 1, 4):
				return {}
		"select_weapon", "secondary", "drop_weapon", "reload_weapon":
			if typeof(packet.value) != TYPE_STRING or not WorldState.Weapons.WEAPONS.has(packet.value):
				return {}
		"buy_item":
			# Only an item identifier crosses the wire: never price, amount,
			# balance, position, team or another player's identity.
			if not WorldState.identifier(packet.value):
				return {}
		"radio":
			if typeof(packet.value) != TYPE_STRING or not AudioCatalog.RADIO_MESSAGES.has(packet.value):
				return {}
		_:
			return {}
	return packet.duplicate()


@rpc("any_peer", "call_remote", "reliable", 2)
func _submit_action(packet: Variant) -> void:
	if not is_host or not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var result := accept_peer_action(peer_id, packet, Time.get_ticks_msec())
	if not result.is_empty():
		_receive_action_result.rpc_id(peer_id, result)


func accept_peer_action(peer_id: int, packet: Variant, now_ms: int) -> Dictionary:
	# Sender identity is supplied by ENet, never by fields in the packet.
	if peer_id <= 1 or not has_input_peer(peer_id) or not _action_peers.has(peer_id):
		return {}
	var command := validate_action(packet)
	var state: Dictionary = _action_peers[peer_id]
	if command.is_empty() or int(command.sequence) <= int(state.sequence) or now_ms < int(state.token_ms):
		return {}
	state.tokens = minf(ACTION_BURST, float(state.tokens) + float(now_ms - int(state.token_ms)) * ACTION_RATE / 1000.0)
	state.token_ms = now_ms
	# Even a rate-limited request is consumed exactly once and receives a reply.
	state.sequence = command.sequence
	var result := _action_reply(command, "rate_limited")
	if float(state.tokens) < 1.0:
		return result
	state.tokens = float(state.tokens) - 1.0
	if not _game_action_handler.is_valid():
		return _action_reply(command, "no_game")
	var outcome: Variant = _game_action_handler.call(peer_id, command.duplicate())
	if not outcome is Dictionary:
		return _action_reply(command, "internal_error")
	result = _action_reply(command, str(outcome.get("reason", "")))
	for key in ["accepted", "actor_id", "team", "class_id", "spawned"]:
		if outcome.has(key):
			result[key] = outcome[key]
	if validate_action_result(result).is_empty():
		return _action_reply(command, "internal_error")
	return result


func _action_reply(command: Dictionary, reason: String) -> Dictionary:
	return {"version": PROTOCOL_VERSION, "sequence": command.sequence, "action": command.action,
		"accepted": false, "reason": reason, "actor_id": "", "team": "UNASSIGNED", "class_id": 0, "spawned": false}


func validate_action_result(packet: Variant) -> Dictionary:
	if not _packet_keys(packet, ACTION_RESULT_FIELDS) or not _valid_integer(packet.version, PROTOCOL_VERSION, PROTOCOL_VERSION):
		return {}
	if not _valid_integer(packet.sequence, 1, MAX_COUNTER) or typeof(packet.action) != TYPE_STRING or packet.action not in ["join_team", "join_class", "select_weapon", "secondary", "drop_weapon", "reload_weapon", "buy_item", "radio", "spray"]:
		return {}
	if typeof(packet.accepted) != TYPE_BOOL or typeof(packet.spawned) != TYPE_BOOL:
		return {}
	if typeof(packet.reason) != TYPE_STRING or packet.reason not in ACTION_REASONS or packet.accepted != packet.reason.is_empty():
		return {}
	if typeof(packet.actor_id) != TYPE_STRING or packet.actor_id.length() > 32:
		return {}
	if not packet.actor_id.is_empty():
		var serial: String = packet.actor_id.trim_prefix("remote_human_")
		if not packet.actor_id.begins_with("remote_human_") or not serial.is_valid_int() or serial != str(serial.to_int()) or serial.to_int() < 1 or serial.to_int() > MAX_COUNTER:
			return {}
	if typeof(packet.team) != TYPE_STRING or packet.team not in ["UNASSIGNED", "T", "CT"] or not _valid_integer(packet.class_id, 0, 4):
		return {}
	if packet.accepted and (packet.actor_id.is_empty() or packet.team == "UNASSIGNED"):
		return {}
	if packet.spawned and (not packet.accepted or packet.action != "join_class"):
		return {}
	if packet.accepted and ((packet.action == "join_class" and packet.class_id == 0) or (packet.action == "join_team" and packet.class_id != 0)):
		return {}
	return packet.duplicate()


@rpc("authority", "call_remote", "reliable", 2)
func _receive_action_result(packet: Variant) -> void:
	if not is_host and is_online():
		accept_action_result(packet)


func accept_action_result(packet: Variant) -> bool:
	var result := validate_action_result(packet)
	if result.is_empty() or not _pending_actions.has(int(result.sequence)):
		return false
	var pending: Dictionary = _pending_actions[int(result.sequence)]
	if result.action != pending.action:
		return false
	if result.accepted and ((result.action == "join_team" and result.team != pending.value)
		or (result.action == "join_class" and result.class_id != pending.value)):
		return false
	_pending_actions.erase(int(result.sequence))
	latest_action_result = result
	action_result_received.emit(result.duplicate())
	return true


func expire_actions(now_ms: int) -> void:
	for sequence: int in _pending_actions.keys():
		if not _pending_actions.has(sequence):
			continue  # A prior timeout listener may have disconnected the session.
		var pending: Dictionary = _pending_actions[sequence]
		if now_ms - int(pending.sent_ms) >= ACTION_TIMEOUT_MS:
			# Timeout means outcome unknown; it never rolls back host state.
			accept_action_result(_action_reply({"sequence": sequence, "action": pending.action}, "timeout"))


func send_combat_event(actor: String, life: int, kind: String, data: Dictionary) -> void:
	if not is_host or not is_online() or multiplayer.get_peers().is_empty():
		return
	send_combat_event_to_peers(actor, life, kind, data, multiplayer.get_peers())


func send_combat_event_to_peers(
	actor: String,
	life: int,
	kind: String,
	data: Dictionary,
	recipient_peers: Array,
) -> void:
	if not is_host or not is_online() or recipient_peers.is_empty():
		return
	var recipients: Array[int] = []
	for peer_id: Variant in recipient_peers:
		if typeof(peer_id) == TYPE_INT and peer_id > 1 and has_input_peer(peer_id) \
				and multiplayer.get_peers().has(peer_id) and not recipients.has(peer_id):
			recipients.append(peer_id)
	if recipients.is_empty():
		return
	_combat_sequence += 1
	var packet := {"version": CombatEvents.VERSION, "epoch": _world_epoch,
		"sequence": _combat_sequence, "tick": Engine.get_physics_frames(),
		"actor": actor, "life": life, "kind": kind, "data": data}
	if CombatEvents.validate(packet).is_empty():
		push_error("Host produced an invalid combat presentation event: " + kind)
		return
	for peer_id: int in recipients:
		_receive_combat_event.rpc_id(peer_id, packet)


@rpc("authority", "call_remote", "reliable", 2)
func _receive_combat_event(packet: Variant) -> void:
	if not is_host and is_online():
		accept_combat_event(packet)


func accept_combat_event(packet: Variant) -> bool:
	var event := CombatEvents.validate(packet)
	if event.is_empty() or event.epoch < maxi(_last_combat_epoch, _last_world_epoch):
		return false
	if event.epoch == _last_combat_epoch and event.sequence <= _last_combat_sequence:
		return false
	_last_combat_epoch = event.epoch
	_last_combat_sequence = event.sequence
	combat_event_received.emit(event)
	return true


func world_snapshot_due(delta: float) -> bool:
	if not is_host or not is_finite(delta) or delta <= 0.0:
		return false
	_world_accumulator += delta
	if _world_accumulator < 1.0 / SNAPSHOT_HZ:
		return false
	_world_accumulator = fmod(_world_accumulator, 1.0 / SNAPSHOT_HZ)
	return true


func send_world_snapshot(peer_id: int, state: Dictionary) -> bool:
	if not is_host or peer_id <= 1 or not has_input_peer(peer_id) or not is_online():
		return false
	# Roster registration alone does not establish a live transport destination.
	if not multiplayer.get_peers().has(peer_id):
		return false
	var packet := state.duplicate()
	packet.version = WorldState.VERSION
	packet.epoch = _world_epoch
	var validated := WorldState.validate(packet)
	if validated.is_empty():
		push_error("Host produced an invalid world snapshot")
		return false
	var encoded := WorldState.encode(validated)
	if encoded.is_empty():
		push_error("Host world snapshot exceeds bounded wire size")
		return false
	largest_world_snapshot_bytes = maxi(largest_world_snapshot_bytes, encoded.size())
	var count := ceili(float(encoded.size()) / WORLD_CHUNK_BYTES)
	for index in range(count):
		var chunk := [WorldState.VERSION, _world_epoch, int(validated.tick), index, count,
			encoded.slice(index * WORLD_CHUNK_BYTES, mini((index + 1) * WORLD_CHUNK_BYTES, encoded.size()))]
		largest_world_packet_bytes = maxi(largest_world_packet_bytes, var_to_bytes(chunk).size())
		_receive_world_snapshot.rpc_id(peer_id, chunk)
	return true


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_world_snapshot(packet: Variant) -> void:
	if not is_host and is_online():
		accept_world_chunk(packet, Time.get_ticks_msec())


func accept_world_chunk(packet: Variant, now_ms: int) -> bool:
	# At most two in-flight snapshots, 35 small chunks each. Never apply a
	# partial actor/item list: loss leaves the last complete snapshot visible.
	if not packet is Array or packet.size() != 6 or now_ms < 0:
		return false
	if not _valid_integer(packet[0], WorldState.VERSION, WorldState.VERSION) or not _valid_integer(packet[1], 1, MAX_COUNTER) or not _valid_integer(packet[2], 0, MAX_COUNTER):
		return false
	if not _valid_integer(packet[4], 1, MAX_WORLD_CHUNKS) or not _valid_integer(packet[3], 0, int(packet[4]) - 1):
		return false
	if typeof(packet[5]) != TYPE_PACKED_BYTE_ARRAY or packet[5].is_empty() or packet[5].size() > WORLD_CHUNK_BYTES:
		return false
	if int(packet[3]) < int(packet[4]) - 1 and packet[5].size() != WORLD_CHUNK_BYTES:
		return false
	if int(packet[3]) == int(packet[4]) - 1 and (int(packet[4]) - 1) * WORLD_CHUNK_BYTES + packet[5].size() > WorldState.MAX_ENCODED_BYTES:
		return false
	if int(packet[1]) < _last_world_epoch or (int(packet[1]) == _last_world_epoch and int(packet[2]) <= _last_world_tick):
		return false
	expire_world_assemblies(now_ms)
	var key := "%d:%d" % [int(packet[1]), int(packet[2])]
	if not _world_assemblies.has(key):
		if _world_assemblies.size() >= 2:
			var oldest: String = _world_assemblies.keys()[0]
			for other: String in _world_assemblies:
				if int(_world_assemblies[other].created_ms) < int(_world_assemblies[oldest].created_ms):
					oldest = other
			_world_assemblies.erase(oldest)
		_world_assemblies[key] = {"created_ms": now_ms, "count": int(packet[4]), "parts": {}}
	var assembly: Dictionary = _world_assemblies[key]
	if now_ms < int(assembly.created_ms) or int(assembly.count) != int(packet[4]) or assembly.parts.has(int(packet[3])):
		return false
	assembly.parts[int(packet[3])] = (packet[5] as PackedByteArray).duplicate()
	if assembly.parts.size() < int(assembly.count):
		return false
	var encoded := PackedByteArray()
	for index in range(int(assembly.count)):
		encoded.append_array(assembly.parts[index])
	_world_assemblies.erase(key)
	var decoded := WorldState.decode(encoded)
	if decoded.is_empty() or int(decoded.epoch) != int(packet[1]) or int(decoded.tick) != int(packet[2]):
		return false
	return accept_world_snapshot(decoded)


func expire_world_assemblies(now_ms: int) -> void:
	for key: String in _world_assemblies.keys():
		if now_ms - int(_world_assemblies[key].created_ms) >= WORLD_ASSEMBLY_TIMEOUT_MS:
			_world_assemblies.erase(key)


func accept_world_snapshot(packet: Variant) -> bool:
	var snapshot := WorldState.validate(packet)
	if snapshot.is_empty() or int(snapshot.epoch) < _last_world_epoch:
		return false
	if int(snapshot.epoch) == _last_world_epoch and int(snapshot.tick) <= _last_world_tick:
		return false
	_last_world_epoch = int(snapshot.epoch)
	_last_world_tick = int(snapshot.tick)
	latest_world_snapshot = snapshot
	world_snapshot_received.emit(snapshot.duplicate(true))
	return true


func tick_snapshot(delta: float, authoritative_state: Dictionary) -> void:
	if not is_host or not is_finite(delta) or delta <= 0.0:
		return
	_snapshot_accumulator += delta
	if _snapshot_accumulator < 1.0 / SNAPSHOT_HZ:
		return
	_snapshot_accumulator = fmod(_snapshot_accumulator, 1.0 / SNAPSHOT_HZ)
	var snapshot := sanitize_snapshot(authoritative_state)
	latest_snapshot = snapshot
	_receive_snapshot.rpc(snapshot)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_snapshot(snapshot: Variant) -> void:
	if not is_host and is_online():
		accept_snapshot(snapshot)


func accept_snapshot(packet: Variant) -> bool:
	var snapshot := validate_snapshot(packet)
	if snapshot.is_empty() or int(snapshot.tick) <= _last_snapshot_tick:
		return false
	_last_snapshot_tick = snapshot.tick
	latest_snapshot = snapshot
	snapshot_received.emit(latest_snapshot.duplicate())
	return true


func sanitize_snapshot(snapshot: Dictionary) -> Dictionary:
	var raw_position: Variant = snapshot.get("position")
	var raw_velocity: Variant = snapshot.get("velocity")
	var position: Vector3 = raw_position if typeof(raw_position) == TYPE_VECTOR3 and raw_position.is_finite() else Vector3.ZERO
	var velocity: Vector3 = raw_velocity if typeof(raw_velocity) == TYPE_VECTOR3 and raw_velocity.is_finite() else Vector3.ZERO
	position = position.clamp(Vector3.ONE * -MAX_WORLD_COORDINATE, Vector3.ONE * MAX_WORLD_COORDINATE)
	var phase: Variant = snapshot.get("phase")
	return {
		"version": PROTOCOL_VERSION,
		"tick": _integer(snapshot.get("tick"), 0, MAX_COUNTER),
		"position": position,
		"velocity": velocity.limit_length(MAX_INPUT_DISTANCE),
		"health": _integer(snapshot.get("health"), 0, 100, 100),
		"phase": phase if typeof(phase) == TYPE_STRING and phase in PHASES else "live",
		"round_time": clampf(_number(snapshot.get("round_time")), 0.0, MAX_ROUND_TIME),
	}


func validate_snapshot(packet: Variant) -> Dictionary:
	if not _packet_keys(packet, SNAPSHOT_FIELDS) or not _valid_integer(packet.version, PROTOCOL_VERSION, PROTOCOL_VERSION):
		return {}
	if not _valid_integer(packet.tick, 0, MAX_COUNTER) or not _valid_integer(packet.health, 0, 100):
		return {}
	if typeof(packet.position) != TYPE_VECTOR3 or not packet.position.is_finite():
		return {}
	var position: Vector3 = packet.position
	if maxf(absf(position.x), maxf(absf(position.y), absf(position.z))) > MAX_WORLD_COORDINATE:
		return {}
	if typeof(packet.velocity) != TYPE_VECTOR3 or not packet.velocity.is_finite() or packet.velocity.length_squared() > MAX_INPUT_DISTANCE * MAX_INPUT_DISTANCE + 0.0001:
		return {}
	if typeof(packet.phase) != TYPE_STRING or packet.phase not in PHASES:
		return {}
	if not _valid_number(packet.round_time) or float(packet.round_time) < 0.0 or float(packet.round_time) > MAX_ROUND_TIME:
		return {}
	return sanitize_snapshot(packet)


func _packet_keys(packet: Variant, fields: Array) -> bool:
	if not packet is Dictionary or packet.size() != fields.size():
		return false
	for field: String in fields:
		if not packet.has(field):
			return false
	return true


func _valid_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func _number(value: Variant, fallback := 0.0) -> float:
	return float(value) if _valid_number(value) else fallback


func _valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and value >= minimum and value <= maximum


func _integer(value: Variant, minimum: int, maximum: int, fallback := 0) -> int:
	return clampi(value, minimum, maximum) if typeof(value) == TYPE_INT else fallback
