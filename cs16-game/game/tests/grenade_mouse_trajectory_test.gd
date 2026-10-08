extends SceneTree

const Ballistics := preload("res://scripts/cs16_ballistics.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("GRENADE MOUSE TRAJECTORY TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame

	var player: PlayerController = game.player
	_check(player.grant_item("hegrenade"), "test player receives an HE grenade")
	player.switch_weapon("hegrenade")
	player._advance_weapon_simulation_tick(75)

	# Godot uses positive pitch for looking up. Release early, then move the
	# mouse sharply before the 0.5-second pin deadline completes.
	var release_view := Vector2(deg_to_rad(25.0), deg_to_rad(35.0))
	player._apply_command_look({"view_angles": release_view})
	player._try_fire()
	var inherited_velocity: Vector3 = player.velocity
	var release_camera_position: Vector3 = player.camera.global_position
	var goldsrc_angles: Vector2 = player.grenade_goldsrc_angles(release_view)
	var expected_velocity := Ballistics.he_throw_velocity(
		goldsrc_angles.x,
		goldsrc_angles.y,
		inherited_velocity,
	)
	var expected_origin := Ballistics.he_throw_origin(
		release_camera_position,
		goldsrc_angles.x,
		goldsrc_angles.y,
	)

	player._release_held_grenade()
	player._apply_command_look({"view_angles": Vector2(deg_to_rad(-70.0), deg_to_rad(-60.0))})
	player._advance_weapon_simulation_tick(49)
	_check(game.get_node_or_null("HEGrenade") == null, "early release waits for the pin deadline")
	player._advance_weapon_simulation_tick()

	var grenade := game.get_node_or_null("HEGrenade") as HEGrenade
	_check(grenade != null, "pin deadline spawns the grenade")
	if grenade != null:
		_check(
			grenade.linear_velocity.distance_to(expected_velocity) < 0.0001,
			"throw velocity follows the mouse at release, not later camera motion",
		)
		_check(
			grenade.global_position.distance_to(expected_origin) < 0.0001,
			"throw origin is offset along the release direction",
		)
		_check(grenade.linear_velocity.y > 0.0, "looking upward produces an upward launch")
	_check(not player._grenade_release_view_latched, "completed throw clears the release latch")

	game.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	print(
		"GAME_GRENADE_MOUSE_TRAJECTORY_PASS"
		if failures.is_empty()
		else "GAME_GRENADE_MOUSE_TRAJECTORY_FAIL"
	)
	quit(0 if failures.is_empty() else 1)
