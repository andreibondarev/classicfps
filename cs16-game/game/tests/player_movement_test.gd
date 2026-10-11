extends SceneTree

const PlayerScript = preload("res://scripts/player.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("PLAYER MOVEMENT TEST: " + message)


func _near(actual: float, expected: float, message: String, epsilon := 0.00001) -> void:
	_check(
		is_equal_approx(actual, expected) or absf(actual - expected) <= epsilon,
		"%s (expected %.6f, got %.6f)" % [message, expected, actual],
	)


func _run() -> void:
	var player: PlayerController = PlayerScript.new()
	var classic_delta := 1.0 / PlayerController.CLASSIC_TICK_RATE

	# Imported BSP geometry uses 0.01 Godot units for one GoldSrc unit.
	_near(PlayerController.WORLD_SCALE, 0.01, "GoldSrc world scale")
	_near(PlayerController.STAND_HEIGHT, 0.72, "standing hull is 72 units high")
	_near(PlayerController.CROUCH_HEIGHT, 0.36, "CS duck movement hull is 36 units high")
	_near(PlayerController.HULL_WIDTH, 0.32, "player hull is 32 units wide")
	_near(PlayerController.STAND_EYE, 0.53, "standing eye preserves the CS view offset")
	_near(PlayerController.CROUCH_EYE, 0.30, "duck eye preserves the CS view offset")
	_near(PlayerController.STEP_HEIGHT, 0.18, "classic step height is 18 units")
	_near(PlayerController.STAIR_VIEW_SPEED, 1.50, "stair view catches up at Valve's 150 ups")
	_near(PlayerController.STAIR_VIEW_MAX_OFFSET, 0.18, "stair view trails by at most one step")

	player._build_body()
	var hull := player.collider.shape as BoxShape3D
	_check(hull != null, "player uses GoldSrc's box hull rather than a capsule")
	if hull != null:
		_near(hull.size.x, 0.32, "standing hull width")
		_near(hull.size.y, 0.72, "standing hull height")
	_near(player.camera.position.y, 0.53, "camera starts at the standing eye height")

	# playermove_t::clientmaxspeed is supplied by the current CS weapon.
	_near(player._movement_speed(false, false), 2.21, "AK-47 running max speed is 221 ups")
	_near(player._movement_speed(false, true), 2.21 * PlayerController.CL_MOVE_SPEED_KEY,
		"Shift scales the weapon-limited speed to a distinct walking pace")
	_near(
		player._movement_speed(true, false),
		2.21 * PlayerController.DUCK_SPEED_MULTIPLIER,
		"ducking scales the already-clamped command by 0.333",
	)
	_near(
		player._movement_speed(true, true),
		2.21 * PlayerController.CL_MOVE_SPEED_KEY * PlayerController.DUCK_SPEED_MULTIPLIER,
		"Shift and duck command scaling compose",
	)
	player.set_max_speed(180.0)
	_near(player._movement_speed(false, false), 1.80, "client max-speed override is honored")
	player.set_max_speed(0.0)
	_near(player._movement_speed(false, false), 2.21, "zero restores weapon max speed")

	# Duck affects collision, view and movement on the first simulation tick.
	player._movement_grounded = true
	player._update_crouch(classic_delta, true)
	_check(not player._standing, "duck press immediately enters the crouched stance")
	_near(hull.size.y, PlayerController.CROUCH_HEIGHT, "duck press immediately applies the crouch hull")
	_near(player.camera.position.y, PlayerController.CROUCH_EYE, "duck press immediately lowers the eye")
	player._update_crouch(classic_delta, false)
	_check(player._standing, "duck release immediately stands when there is clearance")

	# V_CalcNormalRefdef smooths only the rendered eye after an upward step. The
	# body has already climbed 16 HU, while the eye advances 1.5 HU this frame.
	player._update_stair_view_smoothing(classic_delta, 0.16, true)
	_near(player._stair_view_offset, -0.145, "16-HU Dust2 step receives classic eye smoothing")
	_near(player.camera.position.y, PlayerController.STAND_EYE - 0.145,
		"stair smoothing offsets the camera without moving the player")
	player._update_stair_view_smoothing(classic_delta, 0.0, true)
	_near(player._stair_view_offset, -0.13, "stair eye catches up at 150 ups")
	player._update_stair_view_smoothing(classic_delta, 0.32, true)
	_near(player._stair_view_offset, -PlayerController.STAIR_VIEW_MAX_OFFSET,
		"stacked upward movement cannot exceed the 18-HU view cap")
	player._update_stair_view_smoothing(classic_delta, -0.01, true)
	_near(player._stair_view_offset, 0.0, "descending resets upward-only stair smoothing")

	# PM_Accelerate: accel * frametime * wishspeed * player friction.
	var wish_direction := Vector3.RIGHT
	var accelerated: Vector3 = player._accelerated_velocity(
		Vector3.ZERO,
		wish_direction,
		2.21,
		PlayerController.GROUND_ACCEL,
		classic_delta,
	)
	_near(accelerated.x, 0.1105, "ground acceleration matches PM_Accelerate at 100 Hz")
	var capped: Vector3 = player._accelerated_velocity(
		Vector3(2.20, 0.0, 0.0),
		wish_direction,
		2.21,
		PlayerController.GROUND_ACCEL,
		classic_delta,
	)
	_near(capped.x, 2.21, "ground acceleration does not overshoot wishspeed")

	# PM_Friction uses sv_stopspeed below 75 ups and the current speed above it.
	var friction: Vector3 = player._friction_velocity(
		Vector3(2.21, 0.0, 0.0),
		classic_delta,
	)
	_near(friction.x, 2.1216, "ground friction matches PM_Friction above stopspeed")
	var stop_friction: Vector3 = player._friction_velocity(
		Vector3(0.50, 0.0, 0.0),
		classic_delta,
	)
	_near(stop_friction.x, 0.47, "stopspeed controls friction below 75 ups")

	# PM_AirAccelerate caps addspeed at 30 ups but deliberately computes
	# accelspeed from the original uncapped wishspeed.
	var air_velocity: Vector3 = player._air_accelerated_velocity(
		Vector3.ZERO,
		wish_direction,
		2.21,
		PlayerController.AIR_ACCEL,
		classic_delta,
	)
	_near(air_velocity.x, 0.221, "air acceleration uses uncapped wishspeed")
	air_velocity = player._air_accelerated_velocity(
		air_velocity,
		wish_direction,
		2.21,
		PlayerController.AIR_ACCEL,
		classic_delta,
	)
	_near(air_velocity.x, 0.30, "air addspeed is capped at 30 ups")
	var unchanged_air: Vector3 = player._air_accelerated_velocity(
		air_velocity,
		wish_direction,
		2.21,
		PlayerController.AIR_ACCEL,
		classic_delta,
	)
	_near(unchanged_air.x, 0.30, "air acceleration stops at the directional cap")

	# PM_Jump is edge-triggered through oldbuttons and uses a 45-unit jump height.
	_check(player._consume_jump_press(true), "first held-jump frame is pressed")
	_check(not player._consume_jump_press(true), "held jump cannot pogo")
	_check(not player._consume_jump_press(false), "jump release is not a press")
	_check(player._consume_jump_press(true), "jump can fire again after release")
	_near(
		PlayerController.JUMP_SPEED,
		sqrt(2.0 * 800.0 * 45.0) * PlayerController.WORLD_SCALE,
		"jump impulse matches sqrt(2 * 800 * 45)",
	)
	_near(
		PlayerController.JUMP_SPEED - PlayerController.GRAVITY * classic_delta * 0.5,
		2.6432815,
		"jump frame applies PM_FixupGravityVelocity's half gravity step",
	)

	player.velocity = Vector3(5.0, 0.0, 0.0)
	player._prevent_mega_bunny_jumping()
	_near(
		player.velocity.length(),
		2.21
			* PlayerController.BUNNYJUMP_MAX_SPEED_FACTOR
			* PlayerController.BUNNYJUMP_CROP_FACTOR,
		"mega-bunny prevention matches PM_PreventMegaBunnyJumping",
	)
	_near(player._spline_fraction(0.5), 0.5, "duck transition uses PM_SplineFraction")

	player.free()
	if failures.is_empty():
		print("GAME_PLAYER_MOVEMENT_TEST_PASS")
		quit(0)
	else:
		print("GAME_PLAYER_MOVEMENT_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)
