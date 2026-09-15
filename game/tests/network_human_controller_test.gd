extends SceneTree

const PlayerScript = preload("res://scripts/player.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var player := PlayerScript.new()
	_check(player.has_method("input_view_angles"), "human pawn must expose base input angles without recoil")
	_check(player.has_method("_apply_command_look"), "human pawn must consume absolute network look without mouse settings")
	var controller_path := "res://scripts/network_human_controller.gd"
	_check(ResourceLoader.exists(controller_path), "remote human controller must consume validated peer input")
	if not failures.is_empty():
		player.free()
		_finish()
		return
	var network := root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	network._register_input_peer(2, 1000)
	network._register_input_peer(3, 1000)
	var controller = load(controller_path).new()
	root.add_child(controller)
	controller.possess(player)
	_check(not controller.bind_input(network, 99), "unknown peer must not bind a human")
	_check(controller.bind_input(network, 2), "registered remote peer can bind")
	var packet: Dictionary = network.sanitize_input({"movement": Vector2.RIGHT, "yaw": 0.7, "pitch": -0.2, "buttons": 63}, 1)
	_check(network.accept_peer_input(2, packet, 1000), "valid input accepted")
	var detached: Dictionary = network.input_for_peer(2)
	detached.buttons = 0
	_check(network.input_for_peer(2).buttons == 63, "consumer cannot mutate retained wire input")
	var command: Dictionary = controller.gather_command(0.01)
	_check(command.movement == Vector2.RIGHT and command.view_angles == Vector2(0.7, -0.2), "movement and absolute view angles are preserved")
	_check(command.fire and command.fire_pressed and command.jump and command.crouch and command.walk and command.reload and command.use,
		"version-one human buttons map to the normal command seam")
	command = controller.gather_command(0.01)
	_check(command.fire and not command.fire_pressed and not command.reload, "held packet must not repeat press/reload edges")
	packet.sequence = 2
	network.accept_peer_input(2, packet, 1010)
	command = controller.gather_command(0.01)
	_check(command.fire and not command.fire_pressed, "new sequence with held fire is not a new pistol press")
	var other: Dictionary = network.sanitize_input({"movement": Vector2.LEFT, "buttons": 0}, 1)
	network.accept_peer_input(3, other, 1010)
	_check(controller.gather_command(0.01).movement == Vector2.RIGHT, "another peer cannot steer this human")
	network._remove_input_peer(3)
	network.peer_left.emit(3)
	_check(controller.gather_command(0.01).movement == Vector2.RIGHT, "another peer leaving cannot unbind this human")
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(900, 900)
	controller.ingest_input(mouse)
	_check(controller.gather_command(0.01).look_delta == Vector2.ZERO, "host mouse events cannot steer remote input")
	packet.sequence = 3
	packet.buttons = 0
	network.accept_peer_input(2, packet, 1020)
	_check(not controller.gather_command(0.01).fire, "release clears held fire")
	packet.sequence = 4
	packet.buttons = 1
	network.accept_peer_input(2, packet, 1030)
	_check(controller.gather_command(0.01).fire_pressed, "release then press fires once")
	network.expire_inputs(1280)
	command = controller.gather_command(0.01)
	_check(command.movement == Vector2.ZERO and not command.fire and not command.use and not command.has("view_angles"), "expiry yields neutral input without snapping look")
	packet.sequence = 5
	network.accept_peer_input(2, packet, 1290)
	_check(controller.gather_command(0.01).fire_pressed, "fresh input after expiry starts a new held state")
	network._remove_input_peer(2)
	network.peer_left.emit(2)
	network._register_input_peer(2, 1300)
	packet.sequence = 1
	network.accept_peer_input(2, packet, 1300)
	_check(not controller.gather_command(0.01).fire, "reused transport ID requires explicit new ownership binding")
	_check(controller.bind_input(network, 2) and controller.gather_command(0.01).fire_pressed, "explicit rebinding resets command edge history")
	network.disconnect_session()
	_check(not controller.gather_command(0.01).fire, "disconnect neutralizes bound actor")
	_check(not controller.bind_input(network, 2), "offline/client session cannot bind server-owned human input")
	# Network look is already in radians. Local sensitivity/inversion and the
	# authoritative recoil punch must not be applied to it a second time.
	player._build_body()
	player.settings = root.get_node("GameSettings")
	var sensitivity: float = player.settings.mouse_sensitivity
	var inverted: bool = player.settings.invert_y
	player.settings.mouse_sensitivity = 0.35
	player.settings.invert_y = true
	player._punch_degrees = Vector2(2, 3)
	player._apply_command_look({"view_angles": Vector2(0.7, -0.2)})
	_check(player.input_view_angles().is_equal_approx(Vector2(0.7, -0.2)), "input angles exclude rendered recoil")
	_check(is_equal_approx(player.rotation.y, 0.7 + deg_to_rad(3.0)), "yaw punch is rendered exactly once")
	_check(is_equal_approx(player.camera.rotation.x, -0.2 + deg_to_rad(2.0)), "pitch punch is rendered exactly once")
	player._latch_grenade_release_view()
	player._apply_command_look({"view_angles": Vector2(-0.4, 0.3)})
	player._latch_grenade_release_view()
	_check(
		player._grenade_release_view.is_equal_approx(Vector2(0.7, -0.2)),
		"remote grenade release retains its exact network view while the throw animation finishes",
	)
	player._clear_grenade_release_view()
	player._apply_command_look({"view_angles": Vector2(NAN, INF)})
	_check(player.input_view_angles().is_equal_approx(Vector2(-0.4, 0.3)), "non-finite absolute look is ignored")
	player._apply_command_look({"view_angles": "invalid"})
	_check(player.input_view_angles().is_equal_approx(Vector2(-0.4, 0.3)), "wrong-type absolute look is ignored")
	player._apply_command_look({"look_delta": Vector2(5, 3)})
	_check(player.input_view_angles().is_equal_approx(Vector2(-0.4 - deg_to_rad(0.35) * 5, 0.3 + deg_to_rad(0.35) * 3)),
		"local mouse commands retain sensitivity and inversion behavior")
	player.settings.mouse_sensitivity = sensitivity
	player.settings.invert_y = inverted
	controller.free()
	player.free()
	_finish()


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("GAME_NETWORK_HUMAN_CONTROLLER_PASS" if failures.is_empty() else "GAME_NETWORK_HUMAN_CONTROLLER_FAIL")
	quit(0 if failures.is_empty() else 1)
