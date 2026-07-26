class_name PlayerController
extends Combatant

signal health_changed(health: int, armor: int)
signal ammo_changed(clip: int, reserve: int, reloading: bool)
signal weapon_changed(weapon_name: String, fire_mode: String)
signal hit_confirmed(headshot: bool)
signal died

# GoldSrc BSP coordinates are imported at one Godot unit per 100 GoldSrc units.
# Keep the original values visible here so movement can be audited against
# CS 1.6/ReGameDLL pm_shared without silently mixing metres and engine units.
const WORLD_SCALE := 0.01
const CLASSIC_TICK_RATE := 100.0
const STAND_HEIGHT := 72.0 * WORLD_SCALE
const CROUCH_HEIGHT := 50.0 * WORLD_SCALE
const HULL_WIDTH := 32.0 * WORLD_SCALE
const CAPSULE_RADIUS := 16.0 * WORLD_SCALE # Compatibility alias; the hull is now a box.
const STAND_EYE := 53.0 * WORLD_SCALE # -36 hull minimum + CS 17-unit view offset.
const CROUCH_EYE := 30.0 * WORLD_SCALE # -18 hull minimum + CS 12-unit view offset.
const DUCK_TIME := 0.4
const DUCK_SPEED_MULTIPLIER := 0.333
const CL_FORWARD_SPEED := 400.0
const CL_BACK_SPEED := 400.0
const CL_SIDE_SPEED := 400.0
const CL_MOVE_SPEED_KEY := 0.52
const SV_MAX_SPEED := 320.0
const RUN_SPEED := 250.0 * WORLD_SCALE
const WALK_SPEED := 208.0 * WORLD_SCALE
const CROUCH_SPEED := 83.25 * WORLD_SCALE
const GROUND_ACCEL := 5.0
const AIR_ACCEL := 10.0
const AIR_WISH_SPEED_CAP := 30.0 * WORLD_SCALE
const GROUND_FRICTION := 4.0
const PLAYER_FRICTION := 1.0
const STOP_SPEED := 75.0 * WORLD_SCALE
const GRAVITY := 800.0 * WORLD_SCALE
const JUMP_SPEED := sqrt(2.0 * 800.0 * 45.0) * WORLD_SCALE
const BUNNYJUMP_MAX_SPEED_FACTOR := 1.2
const BUNNYJUMP_CROP_FACTOR := 0.8
const FLOOR_NORMAL_MINIMUM := 0.7
const FLOOR_CATEGORIZE_DISTANCE := 2.0 * WORLD_SCALE
const STEP_HEIGHT := 18.0 * WORLD_SCALE
const ViewModelScript = preload("res://scripts/mdl_viewmodel.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const WEAPONS := {
	"ak47": {
		"name": "AK-47", "mode": "FULL AUTO", "magazine": 30, "reserve": 90,
		"max_speed": 221.0,
		"damage": 36.0, "interval": 0.0955, "reload": 2.45,
		"shot": "res://assets/sounds/ak47-1.wav",
		"reload_sound": "res://assets/sounds/ak47_clipin.wav",
	},
	"deagle": {
		"name": "DESERT EAGLE", "mode": "SEMI AUTO", "magazine": 7, "reserve": 35,
		"max_speed": 250.0,
		"damage": 54.0, "interval": 0.225, "reload": 2.20,
		"shot": "res://assets/sounds/deagle-1.wav",
		"reload_sound": "res://assets/sounds/deagle_reload.wav",
	},
	"knife": {
		"name": "KNIFE", "mode": "MELEE", "magazine": -1, "reserve": -1,
		"max_speed": 250.0,
		"damage": 65.0, "interval": 0.48, "reload": 0.0,
		"shot": "res://assets/sounds/knife_slash1.wav", "reload_sound": "",
	},
	"hegrenade": {
		"name": "HE GRENADE", "mode": "THROW", "magazine": 1, "reserve": 0,
		"max_speed": 250.0,
		"damage": 0.0, "interval": 1.0, "reload": 0.0,
		"shot": "res://assets/sounds/hegrenade-1.wav", "reload_sound": "",
	},
}
const RECOIL_PATTERN := [
	Vector2(0.0, 0.74), Vector2(0.18, 0.82), Vector2(-0.12, 0.91),
	Vector2(0.30, 1.02), Vector2(-0.25, 1.08), Vector2(0.38, 1.14),
	Vector2(-0.34, 1.17), Vector2(0.22, 1.22), Vector2(-0.42, 1.18),
	Vector2(0.35, 1.12),
]

var controls_enabled := false
var active_weapon := "ak47"
var clip := 30
var reserve := 90
var reloading := false
var ammunition := {
	"ak47": {"clip": 30, "reserve": 90},
	"deagle": {"clip": 7, "reserve": 35},
	"hegrenade": {"clip": 1, "reserve": 0},
}

var _yaw := 0.0
var _pitch := 0.0
var _next_fire_at := 0.0
var _reload_generation := 0
var _rng := RandomNumberGenerator.new()
var _standing := true
var _walking := false
var _duck_elapsed := 0.0
var _jump_was_down := false
var _max_speed_override_ups := 0.0
var _step_distance := 0.0
var _next_step_at := 1.65
var _step_index := 0
var _recoil_index := 0
var _last_shot_at := -10.0
var _ak_accuracy := 0.2
var _ak_shots_fired := 0
var _deagle_accuracy := 0.9
var _deagle_last_fire := 0.0
var _shot_sequence := 0
var _recoil_direction := -1.0
var _punch_degrees := Vector2.ZERO

var camera: Camera3D
var collider: CollisionShape3D
var weapon_anchor: Node3D
var viewmodel: MdlViewModel
var muzzle_light: OmniLight3D
var shot_audio: AudioStreamPlayer
var reload_audio: AudioStreamPlayer
var footstep_audio: AudioStreamPlayer3D
var settings: Node


func _ready() -> void:
	if team == TEAM_UNASSIGNED:
		configure_identity(TEAM_TERRORIST, "Player")
	super._ready()
	add_to_group("player")
	Input.use_accumulated_input = false
	settings = get_node("/root/GameSettings")
	collision_layer = 4
	collision_mask = 1 | 2
	floor_max_angle = acos(FLOOR_NORMAL_MINIMUM)
	floor_snap_length = FLOOR_CATEGORIZE_DISTANCE
	floor_stop_on_slope = true
	armor = 100
	has_helmet = true
	_rng.seed = 0xC516
	_configure_input()
	combat_controller = HumanCombatController.new()
	combat_controller.name = "HumanController"
	add_child(combat_controller)
	combat_controller.possess(self)
	_build_body()
	_build_viewmodel()
	_load_audio()
	_apply_settings()
	settings.changed.connect(_apply_settings)
	health_changed.emit(health, armor)
	ammo_changed.emit(clip, reserve, reloading)
	weapon_changed.emit(WEAPONS[active_weapon].name, WEAPONS[active_weapon].mode)


func _configure_input() -> void:
	_ensure_key_action("move_forward", KEY_W)
	_ensure_key_action("move_back", KEY_S)
	_ensure_key_action("move_left", KEY_A)
	_ensure_key_action("move_right", KEY_D)
	_ensure_key_action("jump", KEY_SPACE)
	_ensure_key_action("crouch", KEY_CTRL)
	_ensure_key_action("walk", KEY_SHIFT)
	_ensure_key_action("reload", KEY_R)
	_ensure_key_action("use", KEY_E)
	_ensure_key_action("weapon_primary", KEY_1)
	_ensure_key_action("weapon_secondary", KEY_2)
	_ensure_key_action("weapon_melee", KEY_3)
	_ensure_key_action("weapon_grenade", KEY_4)
	_ensure_mouse_action("fire", MOUSE_BUTTON_LEFT)


func _ensure_key_action(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func _ensure_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var event := InputEventMouseButton.new()
		event.button_index = button
		InputMap.action_add_event(action, event)


func _build_body() -> void:
	collider = CollisionShape3D.new()
	collider.name = "PlayerCollider"
	var shape := BoxShape3D.new()
	shape.size = Vector3(HULL_WIDTH, STAND_HEIGHT, HULL_WIDTH)
	collider.shape = shape
	collider.position.y = STAND_HEIGHT * 0.5
	add_child(collider)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.position.y = STAND_EYE
	camera.current = true
	camera.fov = 74.0
	camera.near = 0.035
	add_child(camera)


func _build_viewmodel() -> void:
	weapon_anchor = Node3D.new()
	weapon_anchor.name = "WeaponView"
	camera.add_child(weapon_anchor)
	viewmodel = ViewModelScript.new()
	viewmodel.name = "GoldSrcViewModel"
	weapon_anchor.add_child(viewmodel)
	viewmodel.load_weapon(active_weapon)

	muzzle_light = OmniLight3D.new()
	muzzle_light.name = "MuzzleFlash"
	muzzle_light.position = Vector3(0.16, -0.10, -0.62)
	muzzle_light.light_color = Color("#ffd27a")
	muzzle_light.light_energy = 3.2
	muzzle_light.omni_range = 4.0
	muzzle_light.visible = false
	camera.add_child(muzzle_light)


func _load_audio() -> void:
	shot_audio = AudioStreamPlayer.new()
	shot_audio.name = "ShotAudio"
	shot_audio.volume_db = -5.0
	add_child(shot_audio)
	reload_audio = AudioStreamPlayer.new()
	reload_audio.name = "ReloadAudio"
	reload_audio.volume_db = -8.0
	add_child(reload_audio)
	footstep_audio = AudioStreamPlayer3D.new()
	footstep_audio.name = "FootstepAudio"
	footstep_audio.max_distance = 18.0
	footstep_audio.volume_db = -10.0
	add_child(footstep_audio)
	_apply_weapon_audio()


func _input(event: InputEvent) -> void:
	if not controls_enabled or not alive:
		return
	combat_controller.ingest_input(event)


func _apply_mouse_look(relative: Vector2) -> void:
	var radians_per_pixel: float = deg_to_rad(settings.mouse_sensitivity)
	var vertical_sign := -1.0 if settings.invert_y else 1.0
	_yaw -= relative.x * radians_per_pixel
	_pitch = clamp(
		_pitch - relative.y * radians_per_pixel * vertical_sign,
		deg_to_rad(-89.0),
		deg_to_rad(89.0),
	)
	_sync_view_angles()


func _apply_settings() -> void:
	if is_instance_valid(camera):
		camera.fov = settings.field_of_view


func face_toward(world_position: Vector3) -> void:
	var planar_direction := world_position - global_position
	planar_direction.y = 0.0
	if planar_direction.length_squared() <= 0.0001:
		return
	_yaw = atan2(-planar_direction.x, -planar_direction.z)
	_pitch = 0.0
	_sync_view_angles()


func _sync_view_angles() -> void:
	var rendered_yaw := _yaw + deg_to_rad(_punch_degrees.y)
	rotation.y = rendered_yaw
	if is_instance_valid(collider):
		# GoldSrc traces an axis-aligned player hull, regardless of view yaw.
		collider.rotation.y = -rendered_yaw
	if is_instance_valid(camera):
		camera.rotation.x = clampf(
			_pitch + deg_to_rad(_punch_degrees.x),
			deg_to_rad(-89.0),
			deg_to_rad(89.0),
		)


func _drop_punch_angle(delta: float) -> void:
	var length := _punch_degrees.length()
	if length <= 0.00001:
		_punch_degrees = Vector2.ZERO
		return
	var next_length := maxf(0.0, length - (10.0 + length * 0.5) * delta)
	_punch_degrees *= next_length / length
	_sync_view_angles()


func _physics_process(delta: float) -> void:
	if not controls_enabled or not alive:
		velocity = Vector3.ZERO
		last_command = {}
		return

	var command := combat_controller.gather_command(delta)
	last_command = command
	_drop_punch_angle(delta)
	var look_delta: Vector2 = command.look_delta
	if not look_delta.is_zero_approx():
		_apply_mouse_look(look_delta)
	_update_crouch(delta, command.crouch)
	_walking = command.walk
	var input: Vector2 = command.movement
	var wish_direction: Vector3 = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _yaw)
	if wish_direction.length_squared() > 1.0:
		wish_direction = wish_direction.normalized()
	var wish_speed := _movement_speed(not _standing, _walking) * minf(1.0, input.length())

	var was_on_floor := is_on_floor()
	var jump_pressed := _consume_jump_press(command.jump)
	var jumped := was_on_floor and jump_pressed
	if was_on_floor:
		velocity.y = 0.0
		if jumped:
			_prevent_mega_bunny_jumping()
			# PM_Jump replaces the first gravity half-step with the impulse, then
			# applies PM_FixupGravityVelocity before collision integration.
			velocity.y = JUMP_SPEED - GRAVITY * delta * 0.5
			_air_accelerate(wish_direction, wish_speed, AIR_ACCEL, delta)
		else:
			_apply_friction(delta)
			_accelerate(wish_direction, wish_speed, GROUND_ACCEL, delta)
	else:
		# GoldSrc splits gravity equally around PM_AirMove.
		velocity.y -= GRAVITY * delta * 0.5
		_air_accelerate(wish_direction, wish_speed, AIR_ACCEL, delta)

	var previous := global_position
	move_and_slide()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta * 0.5
	else:
		# PM_PlayerMove clears residual downward velocity after categorizing a landing.
		velocity.y = 0.0
	var horizontal_distance := Vector2(
		global_position.x - previous.x,
		global_position.z - previous.z,
	).length()
	if is_on_floor() and horizontal_distance > 0.0:
		_step_distance += horizontal_distance
		_apply_view_bob()

	if not str(command.weapon).is_empty():
		switch_weapon(command.weapon)

	if command.fire and active_weapon == "ak47":
		_try_fire()
	elif command.fire_pressed:
		_try_fire()
	if command.reload:
		_start_reload()


func _consume_jump_press(jump_down: bool) -> bool:
	var pressed := jump_down and not _jump_was_down
	_jump_was_down = jump_down
	return pressed


func _apply_friction(delta: float) -> void:
	velocity = _friction_velocity(velocity, delta)


func _friction_velocity(source: Vector3, delta: float, edge_friction := 1.0) -> Vector3:
	var speed: float = source.length()
	# pm_shared.c intentionally leaves velocities below 0.1 GoldSrc units/s alone.
	if speed < 0.1 * WORLD_SCALE:
		return source
	var control: float = maxf(speed, STOP_SPEED)
	var drop: float = control * GROUND_FRICTION * edge_friction * PLAYER_FRICTION * delta
	var next_speed: float = maxf(0.0, speed - drop)
	return source * (next_speed / speed)


func _accelerate(wish_direction: Vector3, wish_speed: float, acceleration: float, delta: float) -> void:
	velocity = _accelerated_velocity(velocity, wish_direction, wish_speed, acceleration, delta)


func _accelerated_velocity(
	source: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	acceleration: float,
	delta: float,
) -> Vector3:
	if wish_speed <= 0.0 or wish_direction.is_zero_approx():
		return source
	var current_speed: float = source.dot(wish_direction)
	var add_speed: float = wish_speed - current_speed
	if add_speed <= 0.0:
		return source
	var acceleration_speed: float = minf(
		acceleration * wish_speed * delta * PLAYER_FRICTION,
		add_speed,
	)
	return source + wish_direction * acceleration_speed


func _air_accelerate(
	wish_direction: Vector3,
	wish_speed: float,
	acceleration: float,
	delta: float,
) -> void:
	velocity = _air_accelerated_velocity(
		velocity,
		wish_direction,
		wish_speed,
		acceleration,
		delta,
	)


func _air_accelerated_velocity(
	source: Vector3,
	wish_direction: Vector3,
	wish_speed: float,
	acceleration: float,
	delta: float,
) -> Vector3:
	if wish_speed <= 0.0 or wish_direction.is_zero_approx():
		return source
	# GoldSrc caps only "addspeed" at 30 ups. The acceleration term uses the
	# original, uncapped wishspeed; this asymmetry is essential to air strafing.
	var capped_wish_speed := minf(wish_speed, AIR_WISH_SPEED_CAP)
	var current_speed: float = source.dot(wish_direction)
	var add_speed: float = capped_wish_speed - current_speed
	if add_speed <= 0.0:
		return source
	var acceleration_speed: float = minf(
		acceleration * wish_speed * delta * PLAYER_FRICTION,
		add_speed,
	)
	return source + wish_direction * acceleration_speed


func _prevent_mega_bunny_jumping() -> void:
	var speed := velocity.length()
	var maximum := _maximum_speed(false) * BUNNYJUMP_MAX_SPEED_FACTOR
	if maximum <= 0.0 or speed <= maximum:
		return
	velocity *= (maximum / speed) * BUNNYJUMP_CROP_FACTOR


func _movement_speed(crouching: bool, walking: bool) -> float:
	var speed := _maximum_speed(walking)
	return speed * DUCK_SPEED_MULTIPLIER if crouching else speed


func _maximum_speed(walking: bool) -> float:
	var client_max_speed_ups := _max_speed_override_ups
	if client_max_speed_ups <= 0.0:
		client_max_speed_ups = float(WEAPONS[active_weapon].max_speed)
	var command_speed_ups := CL_FORWARD_SPEED * (CL_MOVE_SPEED_KEY if walking else 1.0)
	var maximum_ups := minf(SV_MAX_SPEED, minf(client_max_speed_ups, command_speed_ups))
	return maximum_ups * WORLD_SCALE


func set_max_speed(max_speed_units_per_second: float) -> void:
	# Mirrors playermove_t::clientmaxspeed. Pass zero to return control to the
	# active weapon's CS 1.6 max-speed value.
	_max_speed_override_ups = maxf(0.0, max_speed_units_per_second)


func _update_crouch(delta: float, wants_crouch: bool) -> void:
	if not wants_crouch:
		if not _standing and not _can_use_standing_hull():
			return
		_standing = true
		_duck_elapsed = 0.0
		_apply_hull(STAND_HEIGHT)
		camera.position.y = STAND_EYE
		return

	if not _standing:
		_apply_hull(CROUCH_HEIGHT)
		camera.position.y = CROUCH_EYE
		return

	# CS completes ducking immediately in the air. On the ground it uses
	# PM_SplineFraction over TIME_TO_DUCK, changing to hull 1 at completion.
	_duck_elapsed = DUCK_TIME if not is_on_floor() else minf(DUCK_TIME, _duck_elapsed + delta)
	var fraction := _spline_fraction(_duck_elapsed / DUCK_TIME)
	camera.position.y = lerpf(STAND_EYE, CROUCH_EYE, fraction)
	if _duck_elapsed >= DUCK_TIME:
		_standing = false
		_apply_hull(CROUCH_HEIGHT)
		camera.position.y = CROUCH_EYE


func _spline_fraction(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return 3.0 * clamped * clamped - 2.0 * clamped * clamped * clamped


func _apply_hull(height: float) -> void:
	var shape := collider.shape as BoxShape3D
	shape.size = Vector3(HULL_WIDTH, height, HULL_WIDTH)
	# PlayerController's transform is feet-level. GoldSrc offsets the entity
	# origin when changing its asymmetric duck hull; keeping the feet fixed is
	# the equivalent representation in this coordinate system.
	collider.position.y = height * 0.5


func _can_use_standing_hull() -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var shape := BoxShape3D.new()
	shape.size = Vector3(HULL_WIDTH, STAND_HEIGHT, HULL_WIDTH)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * STAND_HEIGHT * 0.5)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _apply_view_bob() -> void:
	var speed_ratio: float = clampf(Vector2(velocity.x, velocity.z).length() / RUN_SPEED, 0.0, 1.0)
	var motion_scale := 0.0 if settings.reduced_motion else 1.0
	var eye_height := STAND_EYE if _standing else CROUCH_EYE
	camera.position.y = eye_height + sin(_step_distance * 10.5) * 0.018 * speed_ratio * motion_scale
	viewmodel.set_bob(
		abs(sin(_step_distance * 10.5)) * 0.006 * speed_ratio * motion_scale,
		sin(_step_distance * 5.25) * 0.0025 * speed_ratio * motion_scale,
	)
	if _step_distance >= _next_step_at:
		_next_step_at = _step_distance + (2.15 if not _standing else 1.65)
		if _walking or not _standing:
			return
		_step_index = (_step_index + 1) % 4
		footstep_audio.stream = load("res://assets/sounds/pl_step%d.wav" % (_step_index + 1))
		footstep_audio.pitch_scale = _rng.randf_range(0.96, 1.04)
		footstep_audio.play()


func _try_fire() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if reloading or now < _next_fire_at:
		return
	if active_weapon == "knife":
		_fire_knife(now)
		return
	if active_weapon == "hegrenade":
		_throw_grenade(now)
		return
	if clip <= 0:
		_start_reload()
		return
	var definition: Dictionary = WEAPONS[active_weapon]
	_next_fire_at = now + float(definition.interval)
	clip -= 1
	_store_active_ammunition()
	ammo_changed.emit(clip, reserve, reloading)
	if shot_audio.stream:
		shot_audio.pitch_scale = _rng.randf_range(0.97, 1.025)
		shot_audio.play()

	muzzle_light.visible = true
	get_tree().create_timer(0.035).timeout.connect(func() -> void:
		if is_instance_valid(muzzle_light):
			muzzle_light.visible = false
	)

	var spread := _weapon_spread()
	var direction := Ballistics.spread_direction(
		-camera.global_transform.basis.z,
		camera.global_transform.basis.x,
		camera.global_transform.basis.y,
		_shot_sequence,
		spread,
	)
	_shot_sequence = (_shot_sequence + 1) & 0xff
	var origin := camera.global_position
	var trace_end := _fire_cs_bullet(origin, direction)
	_spawn_tracer(origin, trace_end, Color("#ffd46b"))

	_record_weapon_shot(now)
	_apply_weapon_kickback()
	_last_shot_at = now
	_sync_view_angles()
	viewmodel.play_action("fire")


func _weapon_spread() -> float:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if active_weapon == "ak47":
		if not is_on_floor():
			return 0.04 + 0.4 * _ak_accuracy
		if planar_speed > 140.0 * WORLD_SCALE:
			return 0.04 + 0.07 * _ak_accuracy
		return 0.0275 * _ak_accuracy
	if not is_on_floor():
		return 1.5 * (1.0 - _deagle_accuracy)
	if planar_speed > 0.0:
		return 0.25 * (1.0 - _deagle_accuracy)
	if not _standing:
		return 0.115 * (1.0 - _deagle_accuracy)
	return 0.13 * (1.0 - _deagle_accuracy)


func _record_weapon_shot(now: float) -> void:
	if active_weapon == "ak47":
		if now - _last_shot_at > 0.4:
			_ak_shots_fired = 0
		_ak_accuracy = 0.2
		_ak_shots_fired += 1
		_ak_accuracy = minf(
			1.25,
			float(_ak_shots_fired * _ak_shots_fired * _ak_shots_fired) / 200.0 + 0.35,
		)
		return
	if _deagle_last_fire > 0.0:
		_deagle_accuracy = clampf(
			_deagle_accuracy - (0.4 - (now - _deagle_last_fire)) * 0.35,
			0.55,
			0.9,
		)
	_deagle_last_fire = now


func _apply_weapon_kickback() -> void:
	if active_weapon == "deagle":
		_punch_degrees.x -= 2.0
		return
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var parameters: Array[float]
	if planar_speed > 0.0:
		parameters = [1.5, 0.45, 0.225, 0.05, 6.5, 2.5, 7.0]
	elif not is_on_floor():
		parameters = [2.0, 1.0, 0.5, 0.35, 9.0, 6.0, 5.0]
	elif not _standing:
		parameters = [0.9, 0.35, 0.15, 0.025, 5.5, 1.5, 9.0]
	else:
		parameters = [1.0, 0.375, 0.175, 0.0375, 5.75, 1.75, 8.0]
	var shot_count := maxi(_ak_shots_fired, 1)
	var kick_up := parameters[0] + (float(shot_count) * parameters[2] if shot_count > 1 else 0.0)
	var kick_lateral := parameters[1] + (float(shot_count) * parameters[3] if shot_count > 1 else 0.0)
	_punch_degrees.x = maxf(_punch_degrees.x - kick_up, -parameters[4])
	_punch_degrees.y = clampf(
		_punch_degrees.y + kick_lateral * _recoil_direction,
		-parameters[5],
		parameters[5],
	)
	if _rng.randi_range(0, int(parameters[6])) == 0:
		_recoil_direction *= -1.0


func _fire_cs_bullet(origin: Vector3, direction: Vector3) -> Vector3:
	var profile := Ballistics.weapon_profile(active_weapon)
	if profile.is_empty():
		return origin
	var remaining_distance := float(profile.range_meters)
	var current_damage := int(profile.base_damage)
	var penetrations := int(profile.penetrations)
	var penetration_power := -1
	var damage_modifier := 0.5
	var trace_origin := origin
	var trace_end := origin + direction * remaining_distance
	var exclusions: Array[RID] = [get_rid()]
	while penetrations > 0 and remaining_distance > 0.0 and current_damage > 0:
		var end := trace_origin + direction * remaining_distance
		var query := PhysicsRayQueryParameters3D.create(
			trace_origin,
			end,
			1 | 2 | 4,
			exclusions,
		)
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			trace_end = end
			break
		trace_end = hit.position
		var hit_collider: Object = hit.collider
		var traveled := trace_origin.distance_to(hit.position)
		var damageable := hit_collider and hit_collider.has_method("receive_bullet_damage")
		var is_world_surface := not damageable
		var surface_type := (
			Ballistics.SURFACE_CONCRETE
			if is_world_surface
			else Ballistics.SURFACE_DEFAULT
		)
		var step := Ballistics.penetration_step(
			current_damage,
			float(profile.range_modifier),
			traveled,
			str(profile.bullet_type),
			surface_type,
			is_world_surface,
			penetrations,
			penetration_power,
			damage_modifier,
		)
		if damageable:
			var hit_group := Ballistics.HitGroup.CHEST
			if (
				hit_collider.has_method("head_height")
				and hit.position.y >= float(hit_collider.call("head_height"))
			):
				hit_group = Ballistics.HitGroup.HEAD
			hit_collider.call(
				"receive_bullet_damage",
				int(step.damage_at_hit),
				hit_group,
				active_weapon,
				hit.position,
				self,
			)
			hit_confirmed.emit(hit_group == Ballistics.HitGroup.HEAD)
		else:
			_spawn_impact(hit.position, hit.normal)
		if not bool(step.can_continue):
			break
		# The imported BSP uses one StaticBody for the entire world. Excluding
		# that RID would incorrectly make every later wall transparent.
		if damageable and hit_collider is CollisionObject3D:
			exclusions.append((hit_collider as CollisionObject3D).get_rid())
		remaining_distance = maxf(
			0.0,
			(remaining_distance - traveled) * float(step.remaining_distance_scale),
		)
		current_damage = int(step.next_damage)
		penetrations = int(step.penetrations_remaining)
		penetration_power = int(step.penetration_power_units)
		damage_modifier = float(step.damage_modifier)
		trace_origin = (
			hit.position
			+ direction * float(step.penetration_power_meters)
		)
	return trace_end


func _fire_knife(now: float) -> void:
	_next_fire_at = now + float(WEAPONS.knife.interval)
	if shot_audio.stream:
		shot_audio.play()
	viewmodel.play_action("knife")
	var origin := camera.global_position
	var end := origin - camera.global_transform.basis.z * 2.15
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var hit_collider: Object = hit.collider
	if hit_collider and hit_collider.has_method("apply_damage"):
		hit_collider.call("apply_damage", float(WEAPONS.knife.damage), hit.position, false, self)
		hit_confirmed.emit(false)
	else:
		_spawn_impact(hit.position, hit.normal)


func _throw_grenade(now: float) -> void:
	if clip <= 0:
		return
	_next_fire_at = now + float(WEAPONS.hegrenade.interval)
	clip -= 1
	_store_active_ammunition()
	ammo_changed.emit(clip, reserve, false)
	if shot_audio.stream:
		shot_audio.play()
	viewmodel.play_action("throw")
	var grenade: HEGrenade = GrenadeScript.new()
	get_tree().current_scene.add_child(grenade)
	var view_pitch := rad_to_deg(camera.rotation.x)
	var goldsrc_yaw := rad_to_deg(rotation.y) + 90.0
	grenade.launch(
		Ballistics.he_throw_origin(camera.global_position, view_pitch, goldsrc_yaw),
		Ballistics.he_throw_velocity(view_pitch, goldsrc_yaw, velocity),
		self,
	)
	await get_tree().create_timer(0.28).timeout
	if active_weapon == "hegrenade" and clip <= 0:
		switch_weapon("ak47")


func _start_reload() -> void:
	var definition: Dictionary = WEAPONS[active_weapon]
	var magazine := int(definition.magazine)
	if reloading or magazine <= 0 or clip >= magazine or reserve <= 0 or not alive:
		return
	reloading = true
	_reload_generation += 1
	var generation := _reload_generation
	ammo_changed.emit(clip, reserve, reloading)
	if reload_audio.stream:
		reload_audio.play()
	viewmodel.play_action("reload")
	await get_tree().create_timer(float(definition.reload)).timeout
	if generation != _reload_generation or not alive:
		return
	var needed := magazine - clip
	var loaded: int = mini(needed, reserve)
	clip += loaded
	reserve -= loaded
	_store_active_ammunition()
	reloading = false
	if active_weapon == "ak47":
		_ak_accuracy = 0.2
		_ak_shots_fired = 0
	elif active_weapon == "deagle":
		_deagle_accuracy = 0.9
	ammo_changed.emit(clip, reserve, reloading)


func switch_weapon(weapon: String) -> void:
	if not WEAPONS.has(weapon) or weapon == active_weapon:
		return
	_store_active_ammunition()
	_reload_generation += 1
	reloading = false
	active_weapon = weapon
	if active_weapon == "ak47":
		_ak_accuracy = 0.2
		_ak_shots_fired = 0
	elif active_weapon == "deagle":
		_deagle_accuracy = 0.9
	if ammunition.has(active_weapon):
		clip = int(ammunition[active_weapon].clip)
		reserve = int(ammunition[active_weapon].reserve)
	else:
		clip = -1
		reserve = -1
	_apply_weapon_audio()
	viewmodel.load_weapon(active_weapon)
	viewmodel.play_action("switch")
	weapon_changed.emit(WEAPONS[active_weapon].name, WEAPONS[active_weapon].mode)
	ammo_changed.emit(clip, reserve, false)


func _apply_weapon_audio() -> void:
	var definition: Dictionary = WEAPONS[active_weapon]
	shot_audio.stream = load(str(definition.shot)) if not str(definition.shot).is_empty() else null
	reload_audio.stream = load(str(definition.reload_sound)) if not str(definition.reload_sound).is_empty() else null


func _store_active_ammunition() -> void:
	if ammunition.has(active_weapon):
		ammunition[active_weapon].clip = clip
		ammunition[active_weapon].reserve = reserve


func refill_weapon(weapon: String) -> void:
	if not ammunition.has(weapon):
		return
	var definition: Dictionary = WEAPONS[weapon]
	ammunition[weapon].clip = int(definition.magazine)
	ammunition[weapon].reserve = int(definition.reserve)
	if weapon == active_weapon:
		clip = int(ammunition[weapon].clip)
		reserve = int(ammunition[weapon].reserve)
		ammo_changed.emit(clip, reserve, reloading)


func refill_armor() -> void:
	armor = 100
	has_helmet = true
	health_changed.emit(health, armor)


func _spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.88
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate.surface_add_vertex(from)
	immediate.surface_add_vertex(to)
	immediate.surface_end()
	var tracer := MeshInstance3D.new()
	tracer.mesh = immediate
	get_tree().current_scene.add_child(tracer)
	get_tree().create_timer(0.055).timeout.connect(func() -> void:
		if is_instance_valid(tracer):
			tracer.queue_free()
	)


func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	var impact := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.07
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#f5c46f")
	material.emission_enabled = true
	material.emission = Color("#b86a26")
	sphere.material = material
	impact.mesh = sphere
	impact.position = position + normal * 0.012
	get_tree().current_scene.add_child(impact)
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		if is_instance_valid(impact):
			impact.queue_free()
	)


func spawn_incoming_tracer(from: Vector3, to: Vector3) -> void:
	_spawn_tracer(from, to, Color("#ff625d"))


func apply_damage(
	amount: float,
	hit_position := Vector3.ZERO,
	headshot := false,
	attacker: Combatant = null,
) -> void:
	receive_damage(amount, hit_position, headshot, attacker)


func _on_combatant_damaged(
	_attacker: Combatant,
	_hit_position: Vector3,
	_headshot: bool,
) -> void:
	health_changed.emit(health, armor)


func _on_combatant_eliminated(_attacker: Combatant, _headshot: bool) -> void:
	controls_enabled = false
	died.emit()


func reset_player(spawn_position: Vector3, keep_loadout := true) -> void:
	_store_active_ammunition()
	_reload_generation += 1
	reloading = false
	var starting_armor := armor
	if not keep_loadout:
		starting_armor = 0
		ammunition = {
			"ak47": {"clip": 0, "reserve": 0},
			"deagle": {"clip": 7, "reserve": 35},
			"hegrenade": {"clip": 0, "reserve": 0},
		}
	reset_combatant(spawn_position, starting_armor)
	active_weapon = "ak47"
	clip = int(ammunition.ak47.clip)
	reserve = int(ammunition.ak47.reserve)
	velocity = Vector3.ZERO
	_standing = true
	_walking = false
	_duck_elapsed = 0.0
	_jump_was_down = false
	_yaw = 0.0
	_pitch = 0.0
	_punch_degrees = Vector2.ZERO
	_ak_accuracy = 0.2
	_ak_shots_fired = 0
	_deagle_accuracy = 0.9
	_deagle_last_fire = 0.0
	rotation = Vector3.ZERO
	collider.rotation = Vector3.ZERO
	_apply_hull(STAND_HEIGHT)
	camera.rotation = Vector3.ZERO
	camera.position.y = STAND_EYE
	weapon_anchor.rotation = Vector3.ZERO
	weapon_anchor.position = Vector3.ZERO
	viewmodel.load_weapon(active_weapon)
	viewmodel.position = viewmodel.base_position
	_apply_weapon_audio()
	health_changed.emit(health, armor)
	ammo_changed.emit(clip, reserve, reloading)
	weapon_changed.emit(WEAPONS[active_weapon].name, WEAPONS[active_weapon].mode)
