extends SceneTree

## Host-Game world-use/contact integration. Team admission is explicitly staged.
const GameScript = preload("res://scripts/game.gd")
const BrushScript = preload("res://scripts/cs16_brush_runtime.gd")
const RoundScript = preload("res://scripts/cs16_round_state.gd")
var failures: Array[String] = []
var game: Node
var network: Node
var sequences := {}
var input_time := 1000


class UseTarget extends Node3D:
	var users: Array[int] = []
	var move_after_use := false
	func source_use_origin() -> Vector3:
		return global_position
	func source_use_usable(actor: Node) -> bool:
		return actor.alive
	func request_source_use(actor: Node) -> bool:
		users.append(actor.get_instance_id())
		if move_after_use:
			global_position += Vector3.RIGHT * 10.0
		return true


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _input(peer_id: int, buttons: int) -> void:
	input_time += 10
	sequences[peer_id] = int(sequences.get(peer_id, 0)) + 1
	var packet: Dictionary = network.sanitize_input({"movement": Vector2.ZERO, "buttons": buttons}, sequences[peer_id])
	_check(network.accept_peer_input(peer_id, packet, input_time), "registered input accepted")
	var human: PlayerController = game.remote_roster.actor_for_peer(peer_id)
	human.last_command = human.combat_controller.gather_command(0.01)


func _stage_participant(human: PlayerController) -> void:
	var actor_id: String = game.remote_roster.id_for_actor(human)
	human.configure_identity(Combatant.TEAM_COUNTER_TERRORIST, "World Use Human")
	human.alive = true
	human.controls_enabled = true
	game.round_state.players[actor_id].team = Combatant.TEAM_COUNTER_TERRORIST
	game.round_state.players[actor_id].alive = true
	game.round_state.players[actor_id].choosing_appearance = false


func _target(human: PlayerController, position: Vector3) -> UseTarget:
	human.global_position = position
	var target := UseTarget.new()
	game.add_child(target)
	target.add_to_group("source_use_targets")
	target.global_position = position + Vector3(0.0, 0.3, -0.3)
	human.camera.look_at(target.global_position)
	return target


func _brush_tick() -> void:
	game.entity_world.advance_tick()
	game.brush_runtime.advance_tick(false)


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "world-use fixture must be silent")
	game = GameScript.new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots():
		bot.set_physics_process(false)
		bot.active = false
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	for peer_id in [99, 100]:
		network._register_input_peer(peer_id, 1000)
		game.remote_roster._on_peer_joined(peer_id)
	var first: PlayerController = game.remote_roster.actor_for_peer(99)
	var second: PlayerController = game.remote_roster.actor_for_peer(100)
	var first_id: String = game.remote_roster.id_for_actor(first)
	var second_id: String = game.remote_roster.id_for_actor(second)
	var first_target := _target(first, Vector3(0.0, 100.0, 0.0))
	var second_target := _target(second, Vector3(3.0, 100.0, 0.0))
	var local_target := _target(game.player, Vector3(6.0, 100.0, 0.0))
	var local_camera: Camera3D = root.get_camera_3d()
	_input(99, 16)
	game._process_player_world_use()
	_check(first_target.users.is_empty() and not game._live_combatants_stable().has(first), "pending remote cannot use or touch world entities")
	_stage_participant(first)
	_stage_participant(second)
	game._process_player_world_use()
	game._process_player_world_use()
	_check(first_target.users == [first.get_instance_id()], "first remote gets exactly one activation while use is held")
	_input(100, 16)
	game._process_player_world_use()
	game.player.last_command = {"use": true}
	game._process_player_world_use()
	_check(second_target.users == [second.get_instance_id()] and local_target.users == [game.player.get_instance_id()]
		and first_target.users.size() == 1, "two remotes and host have independent use edges and actor arguments")
	input_time += 240
	_input(100, 16)
	network.expire_inputs(input_time)
	first.last_command = first.combat_controller.gather_command(0.01)
	game._process_player_world_use()
	_input(99, 16)
	game._process_player_world_use()
	_check(first_target.users.size() == 2 and second_target.users.size() == 1, "input expiry releases only that peer's use edge")
	# A selected object can move itself in its handler. The round's C4 command
	# must retain that tick's selection instead of selecting a second object.
	_input(99, 0)
	game._process_player_world_use()
	game.phase = RoundScript.PHASE_BOMB
	game.bomb_planted = true
	game.bomb_position = first_target.global_position + Vector3.RIGHT * 0.2
	first._movement_grounded = true
	first_target.move_after_use = true
	_input(99, 16)
	var selected_for_tick: Dictionary = game._process_player_world_use()
	_check(game._defuse_request(first, true).use, "after target moves away a fresh selection would choose C4")
	var round_command: Dictionary = game._round_tick_command(selected_for_tick)
	_check(not round_command.get("defuse", {}).get("use", false), "one tick's consumed world use cannot also start defusing after target motion")
	game.phase = RoundScript.PHASE_LIVE
	game.bomb_planted = false
	for target in [first_target, second_target, local_target]:
		target.remove_from_group("source_use_targets")
	game.player.last_command = {}
	_input(99, 0)
	game._process_player_world_use()
	var first_activator: int = game._brush_activator_id(first)
	var second_activator: int = game._brush_activator_id(second)
	first.name = "RenamedWorldUser"
	_check(first_activator == game._brush_activator_id(first) and first_activator != second_activator
		and first_activator > 0x7fffffff and first_activator != game._brush_activator_id(game.player),
		"remote activators are distinct durable IDs, independent of node name and local namespace")
	# Actual stock button 51, with a competing planted-C4 candidate. A single
	# press must select exactly one target in both edge and held-use consumers.
	game.brush_runtime.reset_round()
	var button_origin: Vector3 = game._brush_world_aabb(51).get_center()
	first.global_position = button_origin + Vector3(0.0, -0.4, 0.25)
	first._movement_grounded = true
	first.camera.look_at(button_origin)
	game.phase = RoundScript.PHASE_BOMB
	game.bomb_planted = true
	game.bomb_position = button_origin + Vector3(0.2, 0.0, 0.0)
	_input(99, 16)
	game._process_player_world_use()
	_brush_tick()
	_check(game.brush_runtime.get_brush(51).state == BrushScript.STATE_OPEN
		and int(game.brush_runtime.get_brush(51).activator_id) == first_activator,
		"remote use opens the real Assault button during bomb phase with its own activator")
	_check(not game._defuse_request(first, true).use, "better aimed real brush prevents simultaneous C4 defuse")
	_check(game._remote_trigger_cameras.has(first_id) and not first.controls_enabled
		and second.controls_enabled and game.player.controls_enabled and root.get_camera_3d() == local_camera,
		"real cam4 target locks only activating remote and never steals host camera")
	var camera_state: Dictionary = game._remote_trigger_cameras.get(first_id, {})
	_check(camera_state.get("entity_id", -1) == 110
		and (camera_state.get("transform", Transform3D.IDENTITY) as Transform3D).origin.distance_to(Vector3(-6.88, 3.68, -15.84)) < 0.0001,
		"remote camera state retains the authored cam4 identity and world transform")
	game._set_objective_actor_frozen(first_id, false, "plant")
	game._apply_round_phase(RoundScript.PHASE_BOMB)
	_check(not first.controls_enabled, "objective unlock and live phase updates cannot bypass remote camera control lock")
	game.entity_world.advance_ticks(1000)
	game._advance_trigger_camera()
	_check(not game._remote_trigger_cameras.has(first_id) and first.controls_enabled,
		"normal security-camera deadline restores remote controls")
	game._on_trigger_camera_use({"activator_id": first_activator}, 110)
	game._apply_round_phase(RoundScript.PHASE_FREEZE)
	_check(not game._remote_trigger_cameras.has(first_id) and not first.controls_enabled,
		"freeze clears remote camera state without restoring combat input")
	game._apply_round_phase(RoundScript.PHASE_BOMB)
	game.brush_runtime.reset_round()
	_input(99, 0)
	game._process_player_world_use()
	first.camera.look_at(game.bomb_position)
	_input(99, 16)
	game._process_player_world_use()
	_brush_tick()
	_check(game.brush_runtime.get_brush(51).state == BrushScript.STATE_CLOSED and game._defuse_request(first, true).use,
		"better aimed C4 prevents simultaneous button activation")
	# Real hostage actor -> Game signal -> authoritative state and account.
	game.phase = RoundScript.PHASE_LIVE
	game.bomb_planted = false
	_input(99, 0)
	game._process_player_world_use()
	var hostage_id: String = game.hostage_actors.keys()[0]
	var hostage: CS16Hostage = game.hostage_actors[hostage_id]
	first.global_position = hostage.global_position + Vector3(0.0, 0.0, 0.4)
	first.camera.look_at(hostage.source_use_origin())
	var before_money: int = game.round_state.players[first_id].money
	_input(99, 16)
	game._process_player_world_use()
	game._process_player_world_use()
	_check(game.hostage_state.hostages[hostage_id].leader_id == first_id
		and game.hostage_state.hostages[hostage_id].following
		and game.round_state.players[first_id].money == before_money + 150,
		"remote view/use acquires actual hostage once and credits that remote's first-use reward")
	# Both bodies touching the same actual door must retain distinct contacts.
	game.brush_runtime.reset_round()
	var contact_position: Vector3 = game._brush_world_aabb(11).get_center() - Vector3.UP * 0.3
	first.global_position = contact_position
	second.global_position = contact_position
	game._queue_brush_touches()
	var first_pair := "11:%d" % first_activator
	var second_pair := "11:%d" % second_activator
	_check(game._brush_touch_pairs.has(first_pair) and game._brush_touch_pairs.has(second_pair),
		"both remote hulls independently enter the actual door touch set")
	var first_audio := first.audio_entity_id()
	game._on_trigger_camera_use({"activator_id": first_activator}, 110)
	network._remove_input_peer(99)
	network.peer_left.emit(99)
	_check(not game._human_use_was_down.has(first_id) and game._human_use_was_down.has(second_id)
		and not game._remote_trigger_cameras.has(first_id)
		and not game._brush_touch_pairs.has(first_pair) and game._brush_touch_pairs.has(second_pair)
		and not game.brush_runtime._activator_positions.has(first_activator)
		and not game._remote_brush_activator_ids.has(first_id), "departure clears only that human's edges, contacts, position and activator mapping")
	_check(not game.hostage_state.hostages[hostage_id].following, "departing real hostage user releases leadership")
	network._register_input_peer(99, input_time)
	game.remote_roster._on_peer_joined(99)
	var replacement: PlayerController = game.remote_roster.actor_for_peer(99)
	_check(replacement.audio_entity_id() == first_audio and game._brush_activator_id(replacement) != first_activator,
		"reused peer/audio slot cannot inherit old queued brush attribution")
	game._on_trigger_camera_use({"activator_id": first_activator}, 110)
	_check(game._remote_trigger_cameras.is_empty(), "late camera IO from departed activator cannot attach to replacement")
	_brush_tick()
	_check(root.get_camera_3d() == local_camera, "world interaction never takes host camera ownership")
	game.queue_free()
	await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_HUMAN_WORLD_USE_TEST_PASS")
	quit(0 if failures.is_empty() else 1)
