extends SceneTree

## PM_LadderMove contract: func_ladder volumes are non-solid, and a player whose
## hull touches one climbs by facing it and pressing forward. Exercised on the
## stock de_inferno ladder (its only func_ladder).

const GameScript := preload("res://scripts/game.gd")
const TICK := 1.0 / PlayerController.CLASSIC_TICK_RATE

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("LADDER MOVEMENT TEST: " + message)


func _run() -> void:
	_check_ladder_math()
	await _check_inferno_ladder()
	if failures.is_empty():
		print("GAME_LADDER_MOVEMENT_TEST_PASS")
		quit(0)
	else:
		print("GAME_LADDER_MOVEMENT_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check_ladder_math() -> void:
	var volume := AABB(Vector3(-0.16, 0.0, -0.16), Vector3(0.32, 2.0, 0.32))
	_check(
		PlayerController.ladder_face_normal(volume, Vector3(0.0, 1.0, 1.0)) == Vector3(0, 0, 1),
		"trace toward the ladder centre enters the face nearest the player",
	)
	_check(
		PlayerController.ladder_face_normal(volume, Vector3(0.0, 1.0, 0.0)) == Vector3.ZERO,
		"a start-solid trace reports no face",
	)
	var normal := Vector3(0, 0, 1)
	var level_forward := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	var speed := PlayerController.MAX_CLIMB_SPEED
	var climb := PlayerController.ladder_velocity(normal, level_forward, right, speed, 0.0, false)
	_check(climb.is_equal_approx(Vector3(0, speed, 0)), "pressing into the ladder climbs at 200 ups")
	var descend := PlayerController.ladder_velocity(normal, level_forward, right, -speed, 0.0, false)
	_check(descend.is_equal_approx(Vector3(0, -speed, 0)), "backing off the ladder descends")
	var down_look := level_forward.rotated(Vector3.RIGHT, deg_to_rad(-60.0))
	_check(
		PlayerController.ladder_velocity(normal, down_look, right, speed, 0.0, false).y < 0.0,
		"looking down while pressing forward climbs down",
	)
	var strafe := PlayerController.ladder_velocity(normal, level_forward, right, 0.0, speed, false)
	_check(strafe.is_equal_approx(Vector3(speed, 0, 0)), "strafing moves along the ladder face")
	_check(
		PlayerController.ladder_velocity(normal, level_forward, right, 0.0, 0.0, false) == Vector3.ZERO,
		"no input holds the player still on the ladder",
	)
	var off := PlayerController.ladder_velocity(normal, level_forward, right, -speed, 0.0, true)
	_check(off.z > 0.0, "backing away while standing at the bottom walks off the ladder")


func _check_inferno_ladder() -> void:
	var game := GameScript.new()
	game.map_name = "de_inferno"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	if not game.using_imported_map:
		failures.append("de_inferno must import")
		return
	game._on_team_selected(2)
	game._on_class_selected(1)
	for i in 3:
		await physics_frame
	game.set_physics_process(false)
	var player: PlayerController = game.player
	player.set_physics_process(false)
	_check(PlayerController.ladder_volumes.size() == 1, "de_inferno exposes its one func_ladder volume")
	if PlayerController.ladder_volumes.size() != 1:
		return
	var ladder: AABB = PlayerController.ladder_volumes[0]
	var hull := Vector3(PlayerController.HULL_WIDTH, PlayerController.STAND_HEIGHT, PlayerController.HULL_WIDTH)
	# Find the open side of the ladder: standing room at its foot.
	var approach := Vector3.ZERO
	var start := Vector3.ZERO
	for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var half := absf(ladder.size.dot(side)) * 0.5
		var spot := ladder.get_center() + side * (half + hull.x * 0.5 + 0.02)
		spot.y = ladder.position.y + 0.02
		player.global_position = spot
		player.velocity = Vector3.ZERO
		if player.movement_kernel.can_fit_box(hull):
			approach = side
			start = spot
			break
	_check(approach != Vector3.ZERO, "the ladder has standing room at its foot")
	if approach == Vector3.ZERO:
		return
	player.global_position = start
	player._yaw = atan2(approach.x, approach.z)
	player._pitch = deg_to_rad(30.0)
	player._sync_view_angles()
	var climb_command := {"movement": Vector2(0.0, -1.0)}
	var peak := start.y
	var fastest := 0.0
	var landed_on_top := false
	for tick in 300:
		var before := player.global_position.y
		player.simulate_movement(climb_command, TICK)
		fastest = maxf(fastest, (player.global_position.y - before) / TICK)
		peak = maxf(peak, player.global_position.y)
		if player._movement_grounded and player.global_position.y >= ladder.end.y - 0.05:
			landed_on_top = true
	_check(
		peak >= ladder.end.y - 0.1,
		"climbs the Inferno ladder to its top (from %.2f reached %.2f of %.2f)" % [start.y, peak, ladder.end.y],
	)
	_check(landed_on_top, "climbing off the top lands on the ledge beside the ladder top")
	# Looking up adds the view's vertical component to the into-ladder climb
	# (the classic "look up to climb faster"): 200 * (sin + cos) of the pitch.
	var expected_peak_speed := PlayerController.MAX_CLIMB_SPEED * (sin(player._pitch) + cos(player._pitch))
	_check(
		fastest <= expected_peak_speed * 1.01 and fastest >= expected_peak_speed * 0.9,
		"climb speed follows PM_LadderMove (%.2f, expected %.2f)" % [fastest, expected_peak_speed],
	)

	# Hold position halfway up, then jump off along the face normal.
	# `start` leaves a 2 cm gap; step into contact with the ladder volume.
	player.global_position = start - approach * 0.03 + Vector3(0.0, (ladder.size.y - hull.y) * 0.5, 0.0)
	player.velocity = Vector3.ZERO
	player.simulate_movement({"movement": Vector2.ZERO}, TICK)
	var held := player.global_position.y
	for tick in 20:
		player.simulate_movement({"movement": Vector2.ZERO}, TICK)
	_check(absf(player.global_position.y - held) < 0.001, "a player on the ladder without input does not slide")
	player.simulate_movement({"movement": Vector2.ZERO, "jump": true}, TICK)
	var away := Vector2(player.velocity.x, player.velocity.z).dot(Vector2(approach.x, approach.z))
	_check(away > PlayerController.LADDER_JUMP_SPEED * 0.9, "jumping pushes the player off the ladder")
	game.queue_free()
	await process_frame
