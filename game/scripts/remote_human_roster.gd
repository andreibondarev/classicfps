extends Node

## Host-owned connection roster. Joining allocates an UNASSIGNED, non-solid
## human; only Game's authoritative team/class admission path may activate it.
## Peer IDs, durable actor IDs and reusable audio/player slots are separate.
signal human_added(actor_id: String, peer_id: int, actor: PlayerController)
signal human_removing(actor_id: String, peer_id: int, actor: PlayerController)

const PlayerScript = preload("res://scripts/player.gd")
const MAX_ACTOR_SERIAL := 0x7fffffff
var _session: Node
var _records: Dictionary = {}
var _peer_to_actor: Dictionary = {}
var _instance_to_actor: Dictionary = {}
var _removing: Dictionary = {}
var _next_serial := 1


func bind_session(session: Node) -> void:
	_disconnect_signals()
	_clear_humans()
	_session = session
	_session.peer_joined.connect(_on_peer_joined)
	_session.peer_left.connect(_on_peer_left)
	_session.status_changed.connect(_on_status_changed)
	if _session.has_signal("peer_name_changed"):
		_session.peer_name_changed.connect(_on_peer_name_changed)
	_on_status_changed(str(_session.status))


func _disconnect_signals() -> void:
	if is_instance_valid(_session):
		if _session.peer_joined.is_connected(_on_peer_joined):
			_session.peer_joined.disconnect(_on_peer_joined)
		if _session.peer_left.is_connected(_on_peer_left):
			_session.peer_left.disconnect(_on_peer_left)
		if _session.status_changed.is_connected(_on_status_changed):
			_session.status_changed.disconnect(_on_status_changed)
		if _session.has_signal("peer_name_changed") and _session.peer_name_changed.is_connected(_on_peer_name_changed):
			_session.peer_name_changed.disconnect(_on_peer_name_changed)
	_session = null


func _exit_tree() -> void:
	# Whole-scene teardown owns the child actors and all world state. Do not
	# emit gameplay mutations while that scene is being destroyed.
	_disconnect_signals()
	_records.clear()
	_peer_to_actor.clear()
	_instance_to_actor.clear()
	_removing.clear()


func actor_ids() -> Array[String]:
	var result: Array[String] = []
	result.assign(_records.keys())
	return result


func actor_for_id(actor_id: String) -> PlayerController:
	return _records[actor_id].actor if _records.has(actor_id) else null


func actor_for_peer(peer_id: int) -> PlayerController:
	return actor_for_id(str(_peer_to_actor.get(peer_id, "")))


func peer_ids() -> Array[int]:
	var result: Array[int] = []
	result.assign(_peer_to_actor.keys())
	return result


func id_for_actor(actor: Combatant) -> String:
	if not is_instance_valid(actor):
		return ""
	return str(_instance_to_actor.get(actor.get_instance_id(), ""))


func size() -> int:
	return _records.size()


func _on_status_changed(_status: String) -> void:
	if not is_instance_valid(_session) or not _session.is_host:
		_clear_humans()
		return
	# A Game can be loaded after the connection was established. Only actual
	# registered transport peers are eligible, including in this catch-up path.
	for peer_id: int in _session.multiplayer.get_peers():
		_on_peer_joined(peer_id)


func _on_peer_name_changed(peer_id: int, value: String) -> void:
	var actor := actor_for_peer(peer_id)
	if is_instance_valid(actor):
		actor.display_name = value


func _on_peer_joined(peer_id: int) -> void:
	if (not is_instance_valid(_session) or not _session.is_host or peer_id <= 1
			or not _session.has_input_peer(peer_id) or _peer_to_actor.has(peer_id)
			or _next_serial > MAX_ACTOR_SERIAL):
		return
	var slot := _available_slot()
	if slot == 0:
		return
	var actor_id := "remote_human_%d" % _next_serial
	_next_serial += 1
	var actor := PlayerScript.new()
	if not actor.configure_remote_human(slot):
		actor.free()
		return
	actor.name = "RemoteHuman_%d" % slot
	actor.configure_identity(Combatant.TEAM_UNASSIGNED, "Remote Human %d" % slot)
	if _session.has_method("peer_player_name"):
		actor.display_name = _session.peer_player_name(peer_id, actor.display_name)
	actor.alive = false
	actor.visible = false
	add_child(actor)
	actor.collision_layer = 0
	actor.controls_enabled = false
	actor.look_enabled = false
	actor.set_physics_process(false)
	if not actor.combat_controller.bind_input(_session, peer_id):
		remove_child(actor)
		actor.queue_free()
		return
	_records[actor_id] = {"peer_id": peer_id, "slot": slot, "actor": actor}
	_peer_to_actor[peer_id] = actor_id
	_instance_to_actor[actor.get_instance_id()] = actor_id
	human_added.emit(actor_id, peer_id, actor)


func _available_slot() -> int:
	var used := {}
	for record: Dictionary in _records.values():
		used[int(record.slot)] = true
	for slot in range(2, PlayerScript.MAX_HUMAN_SLOT + 1):
		if not used.has(slot):
			return slot
	return 0


func _on_peer_left(peer_id: int) -> void:
	# NetworkSession removes its input owner before emitting peer_left. A stale
	# notification must not evict a newly registered connection with a reused ID.
	if is_instance_valid(_session) and _session.has_input_peer(peer_id):
		return
	_remove_peer(peer_id)


func _clear_humans() -> void:
	for peer_id: int in _peer_to_actor.keys():
		_remove_peer(peer_id)


func _remove_peer(peer_id: int) -> void:
	var actor_id := str(_peer_to_actor.get(peer_id, ""))
	if actor_id.is_empty() or _removing.has(actor_id):
		return
	_removing[actor_id] = true
	var actor: PlayerController = _records[actor_id].actor
	actor.combat_controller.unbind_input()
	actor.controls_enabled = false
	actor.look_enabled = false
	actor.alive = false
	actor.collision_layer = 0
	actor.set_physics_process(false)
	# The Game consumes C4/round events while lookup and the actor's final
	# transform are still available. Release the slot only after cleanup.
	human_removing.emit(actor_id, peer_id, actor)
	_instance_to_actor.erase(actor.get_instance_id())
	_records.erase(actor_id)
	_peer_to_actor.erase(peer_id)
	_removing.erase(actor_id)
	remove_child(actor)
	actor.queue_free()
