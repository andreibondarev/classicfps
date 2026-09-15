extends SceneTree

var failures: Array[String] = []
var game: Node
var network: Node
var stage := "initializing"


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _run() -> void:
	create_timer(30.0, true).timeout.connect(func() -> void:
		push_error("Pause fixture deadline at " + stage)
		quit(1)
	)
	_check(AudioServer.get_driver_name() == "Dummy", "pause fixture must be silent")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	stage = "presentation readiness"
	print("NETWORK_PAUSE_STAGE ", stage)
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	stage = "offline pause"
	print("NETWORK_PAUSE_STAGE ", stage)
	_check(game.map_name == "de_dust2", "pause release check is Dust2-only")
	game.start_match()
	game._begin_live()
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	network = root.get_node("NetworkSession")
	_escape()
	var tick: int = game.round_state.tick
	var weapon_tick: int = game.player.weapon_clock.tick
	_check(paused and game._pause_menu_open(), "offline Escape pauses world and opens existing menu")
	for index in range(12):
		await physics_frame
	stage = "offline resume and host startup"
	print("NETWORK_PAUSE_STAGE ", stage)
	_check(game.round_state.tick == tick, "offline round clock remains frozen")
	_check(game.player.weapon_clock.tick == weapon_tick and not game.player.can_process(), "offline pawn and weapon simulation inherit pause")
	_escape()
	_check(not paused and not game._pause_menu_open(), "offline Escape resumes")
	_escape()
	_check(network.host_game(0, "127.0.0.1") == OK, "start isolated server while offline menu is open")
	_check(not paused and game._pause_menu_open() and game.player.combat_controller.menu_input_blocked,
		"starting host releases world pause but retains local menu/input isolation")
	network._register_input_peer(99, Time.get_ticks_msec())
	game.remote_roster._on_peer_joined(99)
	_check(game.select_remote_join_team(99, "T").accepted and game.select_remote_join_class(99, 1).spawned,
		"host admits remote participant while its own menu remains open")
	var human: PlayerController = game.remote_roster.actor_for_peer(99)
	stage = "online input"
	print("NETWORK_PAUSE_STAGE ", stage)
	human._advance_weapon_simulation_tick(200)
	var origin: Vector3 = human.global_position
	var host_shots: int = game.player._shot_sequence
	var remote_shots: int = human._shot_sequence
	var yaw: float = game.player._yaw
	for action: String in ["fire", "use", "move_forward", "jump"]:
		Input.action_press(action)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 100)
	game.player._input(motion)
	tick = game.round_state.tick
	for index in range(30):
		var input: Dictionary = network.sanitize_input({"movement": Vector2(0, -1), "buttons": 1 if index == 0 else 0}, index + 1)
		_check(network.accept_peer_input(99, input, Time.get_ticks_msec()), "remote input accepted during host menu")
		await physics_frame
	_check(game.round_state.tick >= tick + 29 and game._pause_menu_open() and not paused,
		"online host menu leaves authoritative round advancing")
	_check(human.global_position.distance_to(origin) > 0.05 and human._shot_sequence == remote_shots + 1,
		"remote human moves and fires while host menu stays open")
	_check(game.player._shot_sequence == host_shots and game.player._yaw == yaw
		and game.player.last_command.movement == Vector2.ZERO and not game._human_objective_pressed(game.player, "use"),
		"host menu blocks local movement, aim, firing and raw objective input")
	# Options are still part of the local pause, even though their input state
	# differs from the main pause menu. Keep simulation and neutral input intact.
	game.hud._set_menu_state("options_video")
	_check(game.player.combat_controller.menu_input_blocked and not paused, "online options retain local input isolation")
	game._match_concluded = true
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	_check(game._match_concluded and game._pause_menu_open(), "Enter in options cannot trigger a host rematch")
	game._match_concluded = false
	for action: String in ["fire", "use", "move_forward", "jump"]:
		Input.action_release(action)
	game.hud.set_paused_visible(true)
	_escape()
	_check(not paused and not game._pause_menu_open() and not game.player.combat_controller.menu_input_blocked,
		"online Escape closes menu instead of toggling the server pause")
	_escape()
	network.disconnect_session()
	_check(paused and game._pause_menu_open(), "offline world pause is restored after host closes transport")
	game._set_paused(false)
	stage = "cleanup"
	print("NETWORK_PAUSE_STAGE ", stage)
	game.queue_free()
	await process_frame
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_PAUSE_PASS")
	quit(0 if failures.is_empty() else 1)
