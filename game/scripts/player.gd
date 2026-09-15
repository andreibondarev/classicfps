class_name PlayerController
extends Combatant

signal health_changed(health: int, armor: int)
signal ammo_changed(clip: int, reserve: int, reloading: bool)
signal weapon_changed(weapon_name: String, fire_mode: String)
signal hit_confirmed(headshot: bool)
signal flash_blinded(seconds: float)
signal weapon_drop_requested(weapon_name: String, dropped_clip: int, dropped_reserve: int)
signal died
var spawn_serial := 0

# GoldSrc BSP coordinates are imported at one Godot unit per 100 GoldSrc units.
# Keep the original values visible here so movement can be audited against
# CS 1.6/ReGameDLL pm_shared without silently mixing metres and engine units.
const WORLD_SCALE := 0.01
const CLASSIC_TICK_RATE := 100.0
const STAND_HEIGHT := 72.0 * WORLD_SCALE
const CROUCH_HEIGHT := 50.0 * WORLD_SCALE
# GoldSrc's air-duck raises the hull bottom by the duck-hull offset (18 HU).
const AIR_DUCK_FOOT_LIFT := 18.0 * WORLD_SCALE
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
# Shift applies after the weapon cap so walking is a distinct, readable pace
# rather than AK movement merely falling from 221 to 208 HU/s.
const WALK_SPEED := 130.0 * WORLD_SCALE
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
# V_CalcNormalRefdef eases the rendered eye toward an upward-moving player
# origin at 150 HU/s and never lets it trail by more than one legal step. The
# collision hull still climbs immediately; this is presentation-only.
const STAIR_VIEW_SPEED := 150.0 * WORLD_SCALE
const STAIR_VIEW_MAX_OFFSET := 18.0 * WORLD_SCALE
const MovementKernelScript = preload("res://scripts/goldsrc_movement.gd")
const WeaponClockScript = preload("res://scripts/cs16_weapon_clock.gd")
const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")
const CombatEffectsScript = preload("res://scripts/cs16_combat_effects.gd")
const ViewModelScript = preload("res://scripts/mdl_viewmodel.gd")
const CharacterModelScript = preload("res://scripts/mdl_character_model.gd")
const NetworkControllerScript = preload("res://scripts/network_human_controller.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const AudioRouterScript = preload("res://scripts/cs16_audio_event_router.gd")
const AudioCatalogScript = preload("res://scripts/cs16_audio_catalog.gd")
const AUDIO_ENTITY_ID := 1
# Internal audio namespace, not an ENet peer ID or a wire entity number.
# Keep remote voices clear of map entities, bots and grenade fallback IDs.
const REMOTE_AUDIO_ENTITY_BASE := 0x10000000
const MAX_HUMAN_SLOT := 32
const FOOTSTEP_INTERVAL_TICKS := 30
const FOOTSTEP_MINIMUM_SPEED := 220.0 * WORLD_SCALE
const HE_PIN_AUDIO_TICK := 66
const RELOAD_AUDIO_STAGES := AudioCatalogScript.RELOAD_AUDIO_STAGES
const WEAPONS := WeaponRegistryScript.WEAPONS
const RECOIL_PATTERN := [
	Vector2(0.0, 0.74), Vector2(0.18, 0.82), Vector2(-0.12, 0.91),
	Vector2(0.30, 1.02), Vector2(-0.25, 1.08), Vector2(0.38, 1.14),
	Vector2(-0.34, 1.17), Vector2(0.22, 1.22), Vector2(-0.42, 1.18),
	Vector2(0.35, 1.12),
]

var controls_enabled := false
var post_round_movement_enabled := false
# Freeze time keeps movement and weapons locked but, as in CS 1.6, the
# player can still look around.
var look_enabled := false
# While a radio menu is open, digit keys select radio lines instead of
# weapon slots (game.gd owns the menu; this flag just mutes the latches).
var radio_menu_open := false
var objective_movement_locked := false
var objective_lock_origin := Vector3.ZERO
var objective_crouch_locked := false
var active_weapon := "ak47"
var previous_weapon := ""
var clip := 30
var reserve := 90
var reloading := false
var ammunition := {}
var owned_weapons := {}
var equipment := {
	"kevlar": false, "helmet": false, "defuser": false,
	"nvgs": false, "shield": false,
}
var weapon_modes := {}
var _burst_shots_remaining := 0
var _burst_spread := 0.0
var _glock_recorded_burst := false
var _glock_trigger_consumed := false
var _next_burst_tick := -1

var _yaw := 0.0
var _pitch := 0.0
var _rng := RandomNumberGenerator.new()
var _standing := true
var _walking := false
var _duck_elapsed := 0.0
var _jump_was_down := false
var _max_speed_override_ups := 0.0
var _step_distance := 0.0
var _next_footstep_tick := 0
var _left_foot := false
var _footstep_serial := 0
var _recoil_index := 0
var _last_shot_at := -10.0
var _ak_accuracy := 0.2
var _ak_shots_fired := 0
var _accuracy_recovery_tick := -1
var _deagle_accuracy := 0.9
var _deagle_last_fire := -1.0
var _shot_sequence := 0
var _knife_swing := 0
var _recoil_direction := -1.0
var _punch_degrees := Vector2.ZERO
var _movement_grounded := false
var _stair_view_offset := 0.0
var _grenade_release_view := Vector2.ZERO
var _grenade_release_view_latched := false

var camera: Camera3D
var collider: CollisionShape3D
var movement_kernel: RefCounted
var weapon_clock: RefCounted
var combat_effects: CS16CombatEffects
var audio_router: CS16AudioEventRouter
var _audio_schedule: Array[Dictionary] = []
var weapon_anchor: Node3D
var viewmodel: MdlViewModel
var muzzle_light: OmniLight3D
var settings: Node
var character_model: MdlCharacterModel
var _remote_human_slot := 0


func configure_remote_human(human_slot: int) -> bool:
	# The host roster assigns a stable slot BEFORE adding the pawn to the tree.
	# Ownership cannot change in place: that would also require transferring
	# camera/listener state and rebuilding presentation. Peer binding is separate.
	if is_inside_tree() or is_node_ready() or human_slot < 2 or human_slot > MAX_HUMAN_SLOT:
		return false
	_remote_human_slot = human_slot
	return true


func is_local_human() -> bool:
	return _remote_human_slot == 0


func _ready() -> void:
	if team == TEAM_UNASSIGNED and is_local_human():
		configure_identity(TEAM_TERRORIST, get_node("/root/GameSettings").player_name)
	super._ready()
	add_to_group("human_players")
	if is_local_human():
		add_to_group("player")
		Input.use_accumulated_input = false
	settings = get_node("/root/GameSettings")
	collision_layer = 4 if is_local_human() else 2
	collision_mask = 1 | 2
	floor_max_angle = acos(FLOOR_NORMAL_MINIMUM)
	floor_snap_length = FLOOR_CATEGORIZE_DISTANCE
	floor_stop_on_slope = true
	armor = 100
	has_helmet = true
	_rng.seed = 0xC516
	_initialize_starting_loadout()
	if is_local_human():
		_configure_input()
		combat_controller = HumanCombatController.new()
		combat_controller.name = "HumanController"
	else:
		combat_controller = NetworkControllerScript.new()
		combat_controller.name = "NetworkHumanController"
		set_process_input(false)
	add_child(combat_controller)
	combat_controller.possess(self)
	_build_body()
	movement_kernel = MovementKernelScript.new(self)
	weapon_clock = WeaponClockScript.new()
	weapon_clock.reset(active_weapon)
	combat_effects = CombatEffectsScript.for_scene(get_tree().current_scene)
	audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	if is_local_human():
		_build_viewmodel()
		_apply_settings()
		settings.changed.connect(_apply_settings)
	else:
		character_model = CharacterModelScript.new()
		character_model.name = "PlayerModel"
		add_child(character_model)
		_refresh_character_model()
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
	_ensure_key_action("drop", KEY_G)
	_ensure_key_action("weapon_primary", KEY_1)
	_ensure_key_action("weapon_secondary", KEY_2)
	_ensure_key_action("weapon_melee", KEY_3)
	_ensure_key_action("weapon_grenade", KEY_4)
	_ensure_key_action("weapon_last", KEY_Q)
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
	camera.current = is_local_human()
	camera.fov = 74.0
	camera.near = 0.035
	add_child(camera)
	if not is_local_human():
		# Godot auto-selects the first camera even when current was false.
		camera.clear_current(false)
		camera.cull_mask = 0


func _refresh_character_model() -> void:
	if not is_instance_valid(character_model) or team not in [TEAM_TERRORIST, TEAM_COUNTER_TERRORIST]:
		return
	var skin := str(get_meta("cs16_player_skin", TargetActor.skin_for_team(team, _remote_human_slot - 1)))
	if character_model.skin_name == skin and character_model.weapon_name == active_weapon:
		character_model.reset_animation()
	elif not character_model.load_character(skin, active_weapon):
		push_error("Remote human character could not load: %s/%s" % [skin, active_weapon])
	# Removing C4 after death can switch the active inventory item. Reloading
	# that weapon presentation must not reset the corpse back into a live pose.
	if not alive:
		character_model.play_death()


func _update_character_motion() -> void:
	if is_instance_valid(character_model):
		character_model.set_locomotion(Vector2(velocity.x, velocity.z).length() > 0.01,
			not _standing, _movement_grounded)
		character_model.set_aim_pitch(camera.rotation.x)


func _play_weapon_action(first_person_action: String, world_action := "") -> void:
	if is_instance_valid(viewmodel):
		viewmodel.play_action(first_person_action)
	if is_instance_valid(character_model) and not world_action.is_empty():
		character_model.play_action(world_action)


func _build_viewmodel() -> void:
	weapon_anchor = Node3D.new()
	weapon_anchor.name = "WeaponView"
	camera.add_child(weapon_anchor)
	viewmodel = ViewModelScript.new()
	viewmodel.name = "GoldSrcViewModel"
	weapon_anchor.add_child(viewmodel)
	viewmodel.load_weapon(active_weapon)
	viewmodel.set_silenced(bool(weapon_modes.get(active_weapon, false)))

	muzzle_light = OmniLight3D.new()
	muzzle_light.name = "MuzzleFlash"
	# Matches the re-based authentic viewmodel muzzle (lower-right, converging
	# on the crosshair) instead of the old bottom-center placement.
	muzzle_light.position = Vector3(0.08, -0.03, -0.34)
	muzzle_light.light_color = Color("#ffd27a")
	muzzle_light.light_energy = 3.2
	muzzle_light.omni_range = 4.0
	muzzle_light.visible = false
	camera.add_child(muzzle_light)


func _input(event: InputEvent) -> void:
	if not is_local_human() or not alive:
		return
	if radio_menu_open and event is InputEventKey:
		return
	if controls_enabled or look_enabled:
		# Freeze time still feeds the controller: CS 1.6 locks movement and
		# firing there, but looking, switching weapons, and reloading all
		# work. The physics tick decides which command fields are honored.
		combat_controller.ingest_input(event)


func _apply_mouse_look(relative: Vector2) -> void:
	if not is_local_human():
		return
	var radians_per_pixel: float = deg_to_rad(settings.mouse_sensitivity)
	var vertical_sign := -1.0 if settings.invert_y else 1.0
	_yaw -= relative.x * radians_per_pixel
	_pitch = clamp(
		_pitch - relative.y * radians_per_pixel * vertical_sign,
		deg_to_rad(-89.0),
		deg_to_rad(89.0),
	)
	_sync_view_angles()


func input_view_angles() -> Vector2:
	# The rendered camera/body also contain authoritative recoil punch.
	return Vector2(wrapf(_yaw, -PI, PI), _pitch)


## Player input uses Godot's positive-up pitch, while GoldSrc grenade math uses
## positive-down pitch. Keep the conversion at the input/ballistics boundary so
## the shared trajectory functions can retain their original convention.
static func grenade_goldsrc_angles(view_angles_radians: Vector2) -> Vector2:
	return Vector2(
		-rad_to_deg(view_angles_radians.y),
		rad_to_deg(view_angles_radians.x) + 90.0,
	)


func _latch_grenade_release_view() -> void:
	if _grenade_release_view_latched:
		return
	_grenade_release_view = input_view_angles()
	_grenade_release_view_latched = true


func _clear_grenade_release_view() -> void:
	_grenade_release_view_latched = false


func _apply_command_look(command: Dictionary) -> void:
	if command.has("view_angles"):
		var angles: Variant = command.view_angles
		if typeof(angles) == TYPE_VECTOR2 and angles.is_finite():
			_yaw = wrapf(angles.x, -PI, PI)
			_pitch = clampf(angles.y, deg_to_rad(-89.0), deg_to_rad(89.0))
			_sync_view_angles()
		return
	var relative: Vector2 = command.get("look_delta", Vector2.ZERO)
	if not relative.is_zero_approx():
		_apply_mouse_look(relative)


func _apply_settings() -> void:
	if is_local_human() and is_instance_valid(camera):
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
		spectator_view_pitch = camera.rotation.x


func _drop_punch_angle() -> void:
	_punch_degrees = WeaponClockScript.punch_decay_tick(_punch_degrees)
	_sync_view_angles()


func can_simulate_movement() -> bool:
	return alive and (controls_enabled or (post_round_movement_enabled and look_enabled))


func _physics_process(delta: float) -> void:
	if network_read_only:
		return
	_advance_weapon_simulation_tick()
	if not can_simulate_movement():
		velocity = Vector3.ZERO
		last_command = {}
		if look_enabled and alive and is_instance_valid(combat_controller):
			var idle_command := combat_controller.gather_command(delta)
			_apply_command_look(idle_command)
			# CS 1.6 freeze time: weapon handling stays live even though the
			# feet are frozen — only movement and attacks are withheld.
			var idle_weapon := str(idle_command.get("weapon", ""))
			if not idle_weapon.is_empty():
				switch_weapon(idle_weapon)
			if bool(idle_command.get("reload", false)):
				_start_reload()
		_update_character_motion()
		return

	var command := combat_controller.gather_command(delta)
	if not bool(command.get("fire", false)) or bool(command.get("fire_pressed", false)):
		_glock_trigger_consumed = false
	if objective_movement_locked:
		command.crouch = objective_crouch_locked
	last_command = command
	_drop_punch_angle()
	_apply_command_look(command)
	var horizontal_distance := simulate_movement(command, delta)
	if _movement_grounded and horizontal_distance > 0.0:
		_step_distance += horizontal_distance
		_apply_view_bob()

	if not str(command.weapon).is_empty():
		switch_weapon(command.weapon)
	if not controls_enabled:
		# Survivors may move through the post-round countdown without reopening
		# attacks/objective actions after the round result has been finalized.
		if bool(command.get("reload", false)):
			_start_reload()
		_update_character_motion()
		return
	if bool(command.get("secondary_pressed", false)) and _try_secondary():
		# A successful secondary action wins this tick, as in ItemPostFrame.
		# Do not rely on a primary lockout to suppress simultaneous clicks.
		command.fire = false
		command.fire_pressed = false

	var active_definition: Dictionary = WEAPONS[active_weapon]
	if not command.fire and not command.fire_pressed and not command.secondary_pressed:
		_recover_weapon_accuracy()
	if active_weapon in ["hegrenade", "flashbang", "smokegrenade"]:
		if command.fire_pressed:
			_try_fire()
		if weapon_clock.state == WeaponClockScript.STATE_GRENADE_PINNED and not command.fire:
			_release_held_grenade()
	elif active_weapon == "glock18":
		# A held press that began during cooldown may fire once when ready.
		# Do not consume it merely because its first physics tick was too early.
		# Burst mode, unlike semi-auto, repeats complete bursts while held.
		if (command.fire or command.fire_pressed) and (bool(weapon_modes.get("glock18", false)) or not _glock_trigger_consumed):
			var prior_shot := _shot_sequence
			var prior_deadline: int = weapon_clock.next_primary_tick
			_try_fire()
			if _shot_sequence != prior_shot or weapon_clock.next_primary_tick != prior_deadline:
				_glock_trigger_consumed = true
	elif command.fire and bool(active_definition.automatic):
		_try_fire()
	elif command.fire_pressed:
		_try_fire()
	if command.reload:
		_start_reload()
	if bool(command.get("drop", false)):
		_try_drop_active_weapon()
	_update_character_motion()


## The shared movement step has no weapon, damage, audio, objective or input
## side effects. Client reconciliation may replay it without replaying combat.
## The caller supplies an already-applied view yaw and authoritative locks.
func simulate_movement(command: Dictionary, delta: float) -> float:
	# Categorizing ground may itself settle the hull onto a lower tread. Preserve
	# the pre-categorization origin so downward stairs cancel upward-only view
	# smoothing on the same tick instead of one frame late.
	var view_origin_y := global_position.y
	_movement_grounded = movement_kernel.categorize_ground(velocity)
	var wants_crouch := objective_crouch_locked if objective_movement_locked else bool(command.get("crouch", false))
	_update_crouch(delta, wants_crouch)
	_walking = bool(command.get("walk", false))
	var input: Vector2 = command.get("movement", Vector2.ZERO)
	var wish_direction: Vector3 = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _yaw)
	if wish_direction.length_squared() > 1.0:
		wish_direction = wish_direction.normalized()
	var wish_speed := _movement_speed(wants_crouch, _walking) * minf(1.0, input.length())

	var was_on_floor := _movement_grounded
	var jump_pressed := _consume_jump_press(bool(command.get("jump", false)))
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
	var movement_result: Dictionary = movement_kernel.move(
		velocity,
		delta,
		was_on_floor and not jumped,
	)
	velocity = movement_result.velocity
	_movement_grounded = movement_result.grounded
	if not _movement_grounded:
		velocity.y -= GRAVITY * delta * 0.5
	else:
		# PM_PlayerMove clears residual downward velocity after categorizing a landing.
		velocity.y = 0.0
	_update_stair_view_smoothing(delta, global_position.y - view_origin_y, _movement_grounded)
	return Vector2(
		global_position.x - previous.x,
		global_position.z - previous.z,
	).length()


func _advance_weapon_simulation_tick(count := 1) -> void:
	if not is_instance_valid(weapon_clock):
		return
	for ignored_tick in range(count):
		var events: Array[String] = weapon_clock.advance_tick(1)
		_consume_weapon_clock_events(events)
		_emit_due_audio()
		if _burst_shots_remaining > 0 and weapon_clock.tick >= _next_burst_tick:
			_burst_shots_remaining -= 1
			_next_burst_tick += 10
			_try_fire(true)


func _consume_weapon_clock_events(events: Array[String]) -> void:
	for event in events:
		match event:
			WeaponClockScript.EVENT_RELOAD_COMPLETE:
				_complete_reload()
			WeaponClockScript.EVENT_RELOAD_SHELL:
				_insert_reload_shell()
			WeaponClockScript.EVENT_GRENADE_THROW:
				_spawn_thrown_grenade()
			WeaponClockScript.EVENT_GRENADE_RETIRE:
				if active_weapon in ["hegrenade", "flashbang", "smokegrenade"] and clip <= 0:
					switch_weapon(_best_owned_weapon())


func _consume_jump_press(jump_down: bool) -> bool:
	var pressed := jump_down and not _jump_was_down
	_jump_was_down = jump_down
	return pressed


func _apply_friction(delta: float) -> void:
	var edge_friction := 1.0
	if is_instance_valid(movement_kernel):
		edge_friction = movement_kernel.edge_friction_multiplier(velocity)
	velocity = _friction_velocity(velocity, delta, edge_friction)


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
	if objective_movement_locked:
		# CBasePlayer::ResetMaxSpeed caps active plant/defuse actors at 1 HU/s.
		# Keeping the tiny non-zero source cap also preserves view/+use input.
		return GOLDSRC_UNIT
	var speed := _maximum_speed(walking)
	return speed * DUCK_SPEED_MULTIPLIER if crouching else speed


func _maximum_speed(walking: bool) -> float:
	var client_max_speed_ups := _max_speed_override_ups
	if client_max_speed_ups <= 0.0:
		client_max_speed_ups = float(
			WEAPONS[active_weapon].zoom_speed
			if weapon_is_zoomed()
			else WEAPONS[active_weapon].max_speed
		)
	var command_speed_ups := minf(CL_FORWARD_SPEED, minf(CL_BACK_SPEED, CL_SIDE_SPEED))
	var maximum_ups := minf(SV_MAX_SPEED, minf(client_max_speed_ups, command_speed_ups))
	# Applying +speed before the weapon clamp made common rifles almost as fast
	# as running (AK: 208 versus 221 HU/s). Scale the resolved cap so walking is
	# consistently 52% speed with every weapon and client max-speed override.
	if walking:
		maximum_ups *= CL_MOVE_SPEED_KEY
	return maximum_ups * WORLD_SCALE


func set_max_speed(max_speed_units_per_second: float) -> void:
	# Mirrors playermove_t::clientmaxspeed. Pass zero to return control to the
	# active weapon's CS 1.6 max-speed value.
	_max_speed_override_ups = maxf(0.0, max_speed_units_per_second)


func set_objective_movement_locked(locked: bool, force_crouch := false) -> void:
	if locked and not objective_movement_locked:
		objective_lock_origin = global_position
	objective_movement_locked = locked
	objective_crouch_locked = locked and force_crouch
	if locked:
		velocity.x = 0.0
		velocity.z = 0.0


func _update_crouch(delta: float, wants_crouch: bool) -> void:
	if not wants_crouch:
		if not _standing:
			if _is_air_ducking():
				# Air unduck reverses the crouch-jump leg tuck: the feet drop
				# back 18 HU, which needs clear space below and around.
				var drop := Vector3.DOWN * AIR_DUCK_FOOT_LIFT
				if not movement_kernel.can_fit_box(
					Vector3(HULL_WIDTH, STAND_HEIGHT, HULL_WIDTH), drop
				):
					return
				global_position += drop
			elif not _can_use_standing_hull():
				return
		_standing = true
		_duck_elapsed = 0.0
		_apply_hull(STAND_HEIGHT)
		_set_camera_eye(STAND_EYE)
		return

	if not _standing:
		_apply_hull(CROUCH_HEIGHT)
		_set_camera_eye(CROUCH_EYE)
		return

	# Enter the gameplay stance on the first simulated input tick. The old path
	# waited through the full 0.4 s view spline before changing the hull, speed,
	# animation and eye height, which read as input lag. Standing up still checks
	# clearance above, so the immediate duck cannot wedge the player in ceilings.
	var air_duck := _is_air_ducking()
	_duck_elapsed = DUCK_TIME
	_standing = false
	_apply_hull(CROUCH_HEIGHT)
	_set_camera_eye(CROUCH_EYE)
	if air_duck:
		# GoldSrc air-duck keeps the origin height and raises the hull bottom
		# 18 HU — the legs tuck up and preserve crouch-jump clearance.
		global_position.y += AIR_DUCK_FOOT_LIFT


## PM_CategorizePosition's two-unit sweep reports no contact for a hull that
## rests exactly on the floor, so the per-tick ground flag flickers while the
## player stands still. Applying the air-duck leg tuck in that state would
## launch a grounded player 18 HU (and abort a bomb plant), so confirm real
## airtime with an explicit floor probe. Objective actors (plant/defuse) crouch
## on the ground by definition and never air-duck.
func _is_air_ducking() -> bool:
	if _movement_grounded or objective_movement_locked or is_on_floor():
		return false
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var from := global_position + Vector3.UP * FLOOR_CATEGORIZE_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(
		from,
		from + Vector3.DOWN * FLOOR_CATEGORIZE_DISTANCE * 2.0,
	)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or float(hit.normal.y) < FLOOR_NORMAL_MINIMUM


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
	if is_instance_valid(movement_kernel):
		return movement_kernel.can_fit_box(Vector3(HULL_WIDTH, STAND_HEIGHT, HULL_WIDTH))
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
	# Server-owned remote aim must not depend on the host's accessibility settings.
	var motion_scale := 0.0 if not is_local_human() or settings.reduced_motion else 1.0
	var eye_height := STAND_EYE if _standing else CROUCH_EYE
	_set_camera_eye(
		eye_height + sin(_step_distance * 10.5) * 0.018 * speed_ratio * motion_scale
	)
	if is_instance_valid(viewmodel):
		viewmodel.set_bob(
			abs(sin(_step_distance * 10.5)) * 0.006 * speed_ratio * motion_scale,
			sin(_step_distance * 5.25) * 0.0025 * speed_ratio * motion_scale,
		)
	_update_footstep_audio()


func _set_camera_eye(eye_height: float) -> void:
	if is_instance_valid(camera):
		camera.position.y = eye_height + _stair_view_offset


func _update_stair_view_smoothing(delta: float, vertical_move: float, on_ground: bool) -> void:
	# Valve's original client stores a lagging copy of the player origin. Express
	# the same state as a local camera offset so the authoritative collision body,
	# hitboxes and network position remain untouched.
	if not on_ground or vertical_move < -0.000001:
		_stair_view_offset = 0.0
	else:
		if vertical_move > 0.000001:
			_stair_view_offset -= vertical_move
		if _stair_view_offset < 0.0:
			_stair_view_offset += maxf(0.0, delta) * STAIR_VIEW_SPEED
			_stair_view_offset = clampf(
				_stair_view_offset,
				-STAIR_VIEW_MAX_OFFSET,
				0.0,
			)
		else:
			_stair_view_offset = 0.0
	_set_camera_eye(STAND_EYE if _standing else CROUCH_EYE)


func _update_footstep_audio() -> void:
	if not is_instance_valid(weapon_clock):
		return
	var current_tick := int(weapon_clock.tick)
	if current_tick < _next_footstep_tick:
		return
	_next_footstep_tick = current_tick + FOOTSTEP_INTERVAL_TICKS
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	# ReGameDLL suppresses ordinary multiplayer steps at <= 220 ups. This
	# naturally makes shift-walking and crouch movement silent.
	if planar_speed <= FOOTSTEP_MINIMUM_SPEED:
		return
	var texture_name := _ground_texture_name()
	var descriptor := AudioCatalogScript.footstep_descriptor(
		texture_name,
		_left_foot,
		AudioCatalogScript.footstep_volume(texture_name),
	)
	if AudioCatalogScript.material_code(texture_name) == AudioCatalogScript.TILE:
		# PM_PlayStepSound picks tile5 one time in five. Keep the cadence exact
		# and deterministic while retaining ordinary alternating foot families.
		if _footstep_serial % 5 == 0:
			descriptor.variant_index = 2
		else:
			(descriptor.samples as Array).resize(2)
	_emit_audio_descriptor(
		"player.step.%s" % AudioCatalogScript.material_code(texture_name),
		descriptor,
	)
	_left_foot = not _left_foot
	_footstep_serial += 1


func _ground_texture_name() -> String:
	if not is_inside_tree() or get_world_3d() == null:
		return ""
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.08,
		global_position - Vector3.UP * 0.28,
		1,
		[get_rid()],
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var face_index := int(hit.get("face_index", -1))
	var node := hit.collider as Node
	while is_instance_valid(node):
		if node.has_method("texture_name_for_face"):
			return str(node.call("texture_name_for_face", face_index))
		node = node.get_parent()
	return str((hit.collider as Node).name) if hit.collider is Node else ""


func _emit_audio(
	event_name: String,
	channel: int,
	overrides := {},
) -> int:
	if not is_instance_valid(audio_router):
		audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	if not is_instance_valid(audio_router):
		return -1
	return audio_router.emit_catalog_event(
		event_name,
		audio_entity_id(),
		channel,
		AudioRouterScript.meters_to_hu(global_position),
		overrides,
	)


func audio_entity_id() -> int:
	return AUDIO_ENTITY_ID if is_local_human() else REMOTE_AUDIO_ENTITY_BASE + _remote_human_slot


func _emit_audio_descriptor(event_name: String, descriptor: Dictionary) -> int:
	if not is_instance_valid(audio_router):
		audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	if not is_instance_valid(audio_router):
		return -1
	return audio_router.emit_descriptor(
		event_name,
		audio_entity_id(),
		descriptor,
		AudioRouterScript.meters_to_hu(global_position),
	)


func _schedule_audio(event_name: String, offset_ticks: int) -> void:
	_audio_schedule.append({
		"event": event_name,
		"due_tick": weapon_clock.tick + offset_ticks,
		"channel": AudioRouterScript.CHAN_WEAPON,
	})


func _emit_due_audio() -> void:
	for index in range(_audio_schedule.size() - 1, -1, -1):
		var scheduled := _audio_schedule[index]
		if weapon_clock.tick < int(scheduled.due_tick):
			continue
		_emit_audio(str(scheduled.event), int(scheduled.channel))
		_audio_schedule.remove_at(index)


func _try_fire(burst_followup := false) -> void:
	if network_read_only:
		return
	if reloading and not _interrupt_shell_reload():
		return
	if active_weapon == "c4":
		# The authoritative 100 Hz round state consumes held primary attack.
		# C4 never enters FireBullets3 and never consumes a firearm clip here.
		return
	if active_weapon == "knife":
		_fire_knife()
		return
	if active_weapon in ["hegrenade", "flashbang", "smokegrenade"]:
		if clip > 0 and weapon_clock.begin_primary_attack():
			_clear_grenade_release_view()
			_play_weapon_action("pullpin")
			publish_combat_presentation("grenade_action", {"weapon": active_weapon, "action": "pullpin"})
			_schedule_audio("he.pull_pin", HE_PIN_AUDIO_TICK)
		return
	if clip <= 0:
		if reserve > 0:
			_start_reload()
		else:
			if weapon_clock.begin_empty_fire():
				_emit_audio(
					"weapon.empty_pistol"
					if str(WEAPONS[active_weapon].category) == "pistol"
					else "weapon.empty_rifle",
					AudioRouterScript.CHAN_WEAPON,
				)
		return
	if not burst_followup and not weapon_clock.begin_primary_attack():
		return
	# Some model reload tails outlast the ammo transfer deadline (e.g. G3SG1).
	# Starting a shot replaces that animation and must cancel its pending sounds.
	_audio_schedule.clear()
	var definition: Dictionary = WEAPONS[active_weapon]
	var burst_enabled := (
		str(definition.secondary) == "burst"
		and bool(weapon_modes.get(active_weapon, false))
	)
	if not burst_followup and burst_enabled:
		weapon_clock.next_primary_tick = (
			weapon_clock.tick
			+ WeaponClockScript.ticks_from_seconds(float(definition.burst_primary))
		)
		_burst_shots_remaining = mini(2, clip - 1)
		_next_burst_tick = weapon_clock.tick + (5 if active_weapon == "famas" else 10)
	if not burst_followup:
		_glock_recorded_burst = active_weapon == "glock18" and burst_enabled and clip >= 3
	var now := WeaponClockScript.seconds_from_ticks(weapon_clock.tick)
	clip -= 1
	_store_active_ammunition()
	ammo_changed.emit(clip, reserve, reloading)
	var fire_event := "%s.fire" % active_weapon
	if bool(weapon_modes.get(active_weapon, false)) and active_weapon in ["usp", "m4a1"]:
		fire_event = "%s.fire_silenced" % active_weapon
	elif burst_enabled and (active_weapon != "glock18" or _glock_recorded_burst):
		fire_event = "%s.fire_burst" % active_weapon
	# The Glock burst sample already contains three shots. Short magazines use
	# one single-shot sample per real bullet so they cannot sound a phantom third.
	if not (active_weapon == "glock18" and burst_followup and _glock_recorded_burst):
		_emit_audio(fire_event, AudioRouterScript.CHAN_WEAPON)

	var spread := _weapon_spread()
	if burst_followup:
		spread = 0.05 if active_weapon == "glock18" else _burst_spread
	elif burst_enabled:
		_burst_spread = spread
	var effect_sequence := _shot_sequence
	var direction := Ballistics.spread_direction(
		-camera.global_transform.basis.z,
		camera.global_transform.basis.x,
		camera.global_transform.basis.y,
		effect_sequence,
		spread,
	)
	_shot_sequence = (_shot_sequence + 1) & 0xff
	var origin := camera.global_position
	if is_instance_valid(combat_effects):
		combat_effects.spawn_weapon_shot(
			active_weapon,
			effect_sequence,
			first_person_shot_effect_origin() if is_local_human() else camera.global_position,
			direction,
			camera.global_transform.basis.x,
			camera.global_transform.basis.y,
		)
	var pellet_count := int(WEAPONS[active_weapon].pellets)
	if pellet_count <= 1:
		_fire_cs_bullet(origin, direction, effect_sequence)
	else:
		var cone := float(WEAPONS[active_weapon].get("cone", spread))
		for pellet_index in range(pellet_count):
			var pellet_direction := Ballistics.spread_direction(
				-camera.global_transform.basis.z,
				camera.global_transform.basis.x,
				camera.global_transform.basis.y,
				(effect_sequence * 16 + pellet_index) & 0xff,
				cone,
			)
			_fire_cs_bullet(origin, pellet_direction, effect_sequence)

	if not burst_followup:
		_record_weapon_shot(now)
		_apply_weapon_kickback()
	publish_combat_presentation("shot", {"weapon": active_weapon, "sequence": effect_sequence,
		"origin": origin, "direction": direction, "right": camera.global_basis.x,
		"up": camera.global_basis.y, "punch": _punch_degrees})
	_last_shot_at = now
	_sync_view_angles()
	if is_instance_valid(viewmodel) and active_weapon in ["usp", "m4a1"]:
		viewmodel._start_animation(
			"shoot1" if bool(weapon_modes.get(active_weapon, false)) else "shoot1_unsil",
			false,
		)
	else:
		_play_weapon_action("fire")
	if is_instance_valid(character_model):
		character_model.play_action("shoot")


func first_person_shot_effect_origin() -> Vector3:
	## Camera-space origin for the first-person shot effects. The combat
	## effects muzzle anchor is authored relative to this origin; the offset
	## re-bases it onto the authentic viewmodel barrel tip so the flash sprite
	## renders exactly at the muzzle instead of floating mid-receiver. The tip
	## itself is read from the rendered v_ model pose, so every weapon (and
	## every recoil frame) anchors its flash at its own barrel end.
	var view := camera.global_transform.basis
	var muzzle := (
		viewmodel.muzzle_point_world()
		if is_instance_valid(viewmodel)
		else camera.global_position + view.x * 0.07 + view.y * -0.04 + -view.z * 0.30
	)
	# CS16CombatEffects.spawn_weapon_shot places the flash at
	# origin + forward*0.72 + right*0.235 - up*0.155; subtract that authored
	# anchor so the sprite lands on the real barrel tip.
	return muzzle - (-view.z * 0.72 + view.x * 0.235 - view.y * 0.155)


func _try_secondary() -> bool:
	if network_read_only or reloading or not alive or not weapon_clock.can_secondary_attack():
		return false
	if active_weapon == "knife":
		_fire_knife(true)
		return true
	var definition: Dictionary = WEAPONS[active_weapon]
	var secondary := str(definition.secondary)
	if secondary == "none":
		return false
	if secondary == "zoom":
		var levels: Array = definition.zoom_levels
		var current_index := int(weapon_modes.get(active_weapon, 0))
		current_index = (current_index + 1) % levels.size()
		weapon_modes[active_weapon] = current_index
		camera.fov = float(levels[current_index])
		_emit_audio("weapon.zoom", AudioRouterScript.CHAN_ITEM)
		weapon_clock.next_primary_tick = weapon_clock.tick + 30
	elif secondary in ["burst", "silencer"]:
		weapon_modes[active_weapon] = not bool(weapon_modes.get(active_weapon, false))
		var toggle_deadline: int = (
			weapon_clock.tick
			+ WeaponClockScript.ticks_from_seconds(
				float(definition.get("secondary_seconds", 0.3))
			)
		)
		# Glock/FAMAS mode changes delay the next toggle, not the next shot.
		# Silencer attachment still locks primary attack for its animation.
		weapon_clock.next_secondary_tick = toggle_deadline
		if secondary == "silencer":
			weapon_clock.next_primary_tick = toggle_deadline
		else:
			play_fire_mode_feedback()
		weapon_changed.emit(
			str(definition.name),
			"BURST FIRE" if secondary == "burst" and bool(weapon_modes[active_weapon])
			else ("SILENCED" if secondary == "silencer" and bool(weapon_modes[active_weapon]) else str(definition.mode)),
		)
		if secondary == "silencer":
			var attaching := bool(weapon_modes[active_weapon])
			if is_instance_valid(viewmodel):
				viewmodel.set_silenced(attaching)
				viewmodel._start_animation(
					"add_silencer" if attaching else "detach_silencer",
					false,
				)
			_emit_audio(
				"%s.silencer_on" % active_weapon
				if attaching
				else "%s.silencer_off" % active_weapon,
				AudioRouterScript.CHAN_ITEM,
			)
	return true


func play_fire_mode_feedback() -> void:
	# Local confirmation only; remote players' toggles are not world sounds.
	if is_local_human():
		_emit_audio("weapon.mode_switch", AudioRouterScript.CHAN_ITEM,
			{"volume": 0.35, "attenuation": AudioRouterScript.ATTN_NONE})


func weapon_is_zoomed() -> bool:
	# Camera FOV is a display setting, not authoritative scope state. In
	# particular a remote pawn's default 74-degree camera is not a scoped AWP.
	return str(WEAPONS[active_weapon].secondary) == "zoom" and int(weapon_modes.get(active_weapon, 0)) > 0


func is_crouching() -> bool:
	return not _standing


func _weapon_spread() -> float:
	var accuracy := _ak_accuracy
	if active_weapon == "g3sg1":
		accuracy = Ballistics.sniper_accuracy(active_weapon,
			WeaponClockScript.seconds_from_ticks(weapon_clock.tick) - _deagle_last_fire if _deagle_last_fire >= 0.0 else -1.0)
	return Ballistics.weapon_spread(
		active_weapon, _movement_grounded, Vector2(velocity.x, velocity.z).length(),
		not _standing, weapon_is_zoomed(), accuracy, _deagle_accuracy,
		bool(weapon_modes.get(active_weapon, false)),
	)


func _record_weapon_shot(now: float) -> void:
	if Ballistics.AUTOMATIC_ACCURACY.has(active_weapon):
		_ak_shots_fired += 1
		_ak_accuracy = Ballistics.automatic_accuracy(active_weapon, _ak_shots_fired)
		_accuracy_recovery_tick = -1
		return
	if active_weapon in ["g3sg1", "sg550"]:
		_ak_accuracy = Ballistics.sniper_accuracy(active_weapon, now - _deagle_last_fire if _deagle_last_fire >= 0.0 else -1.0)
	if _deagle_last_fire >= 0.0:
		_deagle_accuracy = Ballistics.pistol_accuracy(active_weapon, _deagle_accuracy, now - _deagle_last_fire)
	_deagle_last_fire = now


func _reset_weapon_accuracy() -> void:
	_ak_accuracy = Ballistics.base_accuracy(active_weapon)
	_ak_shots_fired = 0
	_accuracy_recovery_tick = -1
	_deagle_accuracy = Ballistics.base_accuracy(active_weapon)
	_deagle_last_fire = -1.0


func _recover_weapon_accuracy() -> void:
	if not Ballistics.AUTOMATIC_ACCURACY.has(active_weapon) or _ak_shots_fired <= 0:
		return
	# ItemPostFrame: release clamps to 15, waits 0.4s, then loses one shot per
	# 0.0225s (observed at the next 100Hz tick), not a full reset on every tap.
	if _accuracy_recovery_tick < 0:
		_ak_shots_fired = mini(_ak_shots_fired, 15)
		_accuracy_recovery_tick = weapon_clock.tick + 40
	elif weapon_clock.tick > _accuracy_recovery_tick:
		_ak_shots_fired -= 1
		_accuracy_recovery_tick = weapon_clock.tick + 2
		if _ak_shots_fired == 0:
			_ak_accuracy = Ballistics.base_accuracy(active_weapon)


func _apply_weapon_kickback() -> void:
	if active_weapon == "glock18":
		return # Original Glock has viewmodel kick but no punch-angle recoil.
	if str(WEAPONS[active_weapon].category) == "pistol":
		_punch_degrees.x -= 2.0
		return
	var seed := (_shot_sequence - 1) & 0xff
	if active_weapon in ["m3", "xm1014"]:
		var low := (4 if _movement_grounded else 8) if active_weapon == "m3" else (3 if _movement_grounded else 7)
		var high := (6 if _movement_grounded else 11) if active_weapon == "m3" else (5 if _movement_grounded else 10)
		_punch_degrees.x -= Ballistics.shared_random_long(seed + 1, low, high)
		return
	if active_weapon in ["g3sg1", "sg550"]:
		_punch_degrees.x -= Ballistics.shared_random_float(seed + 4, 0.75, 1.75 if active_weapon == "g3sg1" else 1.25) + _punch_degrees.x * 0.25
		_punch_degrees.y += Ballistics.shared_random_float(seed + 5, -0.75, 0.75)
		return
	var parameters: Array = preload("res://scripts/cs16_weapon_recoil.gd").parameters(
		active_weapon, _movement_grounded, Vector2(velocity.x, velocity.z).length() > 0.0, not _standing)
	if parameters.is_empty():
		var item: Dictionary = WEAPONS[active_weapon]
		var category := str(item.category)
		var kick := 0.9
		if category == "pistol":
			kick = 1.4
		elif category == "sniper":
			kick = 2.0
		elif category == "shotgun":
			kick = 4.0
		elif category == "rifle" or category == "machinegun":
			kick = 1.0
		_punch_degrees.x = maxf(_punch_degrees.x - kick, -12.0)
		return
	var shot_count := maxi(_ak_shots_fired, 1)
	var kick_up: float = parameters[0] + (float(shot_count) * parameters[2] if shot_count > 1 else 0.0)
	var kick_lateral: float = parameters[1] + (float(shot_count) * parameters[3] if shot_count > 1 else 0.0)
	_punch_degrees.x = maxf(_punch_degrees.x - kick_up, -parameters[4])
	_punch_degrees.y = clampf(
		_punch_degrees.y + kick_lateral * _recoil_direction,
		-parameters[5],
		parameters[5],
	)
	if _rng.randi_range(0, int(parameters[6])) == 0:
		_recoil_direction *= -1.0


func _fire_cs_bullet(
	origin: Vector3,
	direction: Vector3,
	effect_sequence := 0,
) -> Vector3:
	var profile := Ballistics.weapon_profile(active_weapon)
	if profile.is_empty():
		return origin
	if bool(weapon_modes.get(active_weapon, false)):
		var definition: Dictionary = WEAPONS[active_weapon]
		if str(definition.secondary) == "silencer":
			profile.base_damage = int(definition.silenced_damage)
			profile.range_modifier = float(definition.silenced_range_modifier)
		elif str(definition.secondary) == "burst" and definition.has("burst_damage"):
			profile.base_damage = int(definition.burst_damage)
	var remaining_distance := float(profile.range_meters)
	var current_damage := int(profile.base_damage)
	# FireBuckshots does not penetrate, but it still performs its initial trace.
	var penetrations := maxi(int(profile.penetrations), 1)
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
			1 | 2 | 4 | 16,
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
			Ballistics.surface_for_hit(hit)
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
			var hit_group := _hit_group_for_impact(hit_collider, hit.position)
			hit_collider.call(
				"receive_bullet_damage",
				int(step.damage_at_hit),
				hit_group,
				active_weapon,
				hit.position,
				self,
			)
			if is_instance_valid(combat_effects) and (hit_collider is Combatant or hit_collider is CS16Hostage):
				combat_effects.spawn_blood_impact(
					hit.position,
					direction,
					effect_sequence,
				)
				var blood_query := PhysicsRayQueryParameters3D.create(
					hit.position + direction * 0.03,
					hit.position + direction * 2.0,
					1,
					[get_rid(), (hit_collider as CollisionObject3D).get_rid()]
					if hit_collider is CollisionObject3D
					else [get_rid()],
				)
				var blood_surface := get_world_3d().direct_space_state.intersect_ray(blood_query)
				if not blood_surface.is_empty():
					combat_effects.spawn_blood_decal(
						blood_surface.position,
						blood_surface.normal,
						effect_sequence,
					)
			hit_confirmed.emit(hit_group == Ballistics.HitGroup.HEAD)
		else:
			if is_instance_valid(combat_effects):
				combat_effects.spawn_world_impact(hit.position, hit.normal, effect_sequence, surface_type)
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


func _hit_group_for_impact(
	hit_collider: Object,
	hit_position: Vector3,
) -> int:
	if hit_collider is Combatant:
		return hit_collider.hit_group_at(hit_position)
	if (
		not hit_collider is Node3D
		or not hit_collider.has_method("head_height")
	):
		return Ballistics.HitGroup.GENERIC
	var victim := hit_collider as Node3D
	var relative_hu := (
		(hit_position - victim.global_position) / GOLDSRC_UNIT
	)
	if hit_position.y >= float(hit_collider.call("head_height")):
		return Ballistics.HitGroup.HEAD
	if relative_hu.y < 30.0:
		return (
			Ballistics.HitGroup.LEFT_LEG
			if relative_hu.x < 0.0
			else Ballistics.HitGroup.RIGHT_LEG
		)
	if relative_hu.y < 42.0:
		return Ballistics.HitGroup.STOMACH
	if absf(relative_hu.x) >= 11.0:
		return (
			Ballistics.HitGroup.LEFT_ARM
			if relative_hu.x < 0.0
			else Ballistics.HitGroup.RIGHT_ARM
		)
	return Ballistics.HitGroup.CHEST


func _fire_knife(stab := false) -> void:
	var origin := camera.global_position
	var range_units := (
		Ballistics.KNIFE_STAB_DISTANCE_UNITS
		if stab
		else Ballistics.KNIFE_SWING_DISTANCE_UNITS
	)
	var forward := -camera.global_transform.basis.z
	var end := origin + forward * range_units * WORLD_SCALE
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not weapon_clock.begin_knife_attack(stab, not hit.is_empty()):
		return
	var action := ("stab_miss" if hit.is_empty() else "stab") if stab else ("midslash1" if _knife_swing % 2 == 0 else "midslash2")
	if not stab:
		_knife_swing += 1
	_play_weapon_action(action, "shoot")
	publish_combat_presentation("knife_action", {"action": action})
	if hit.is_empty():
		_emit_audio("knife.slash", AudioRouterScript.CHAN_WEAPON)
		return
	var hit_collider: Object = hit.collider
	var base_damage := int(WEAPONS.knife.stab_damage if stab else WEAPONS.knife.damage)
	if hit_collider and hit_collider.has_method("receive_melee_damage"):
		# The knife shares the bullet damage path so armor, the knife armor
		# ratio and hit groups apply; only stabs carry the backstab bonus.
		var backstab := stab and Ballistics.is_backstab(
			forward,
			hit_collider.call("facing_direction"),
		)
		var hit_group := _hit_group_for_impact(hit_collider, hit.position)
		_emit_audio("knife.stab" if stab else "knife.hit", AudioRouterScript.CHAN_ITEM)
		hit_collider.call(
			"receive_melee_damage",
			base_damage,
			hit_group,
			"knife",
			hit.position,
			self,
			backstab,
		)
		if is_instance_valid(combat_effects):
			combat_effects.spawn_blood_impact(
				hit.position,
				forward,
				_shot_sequence,
			)
		hit_confirmed.emit(hit_group == Ballistics.HitGroup.HEAD)
	elif hit_collider and hit_collider.has_method("apply_damage"):
		# Breakables and other world props keep the generic damage entry point.
		_emit_audio("knife.stab" if stab else "knife.hit", AudioRouterScript.CHAN_ITEM)
		hit_collider.call(
			"apply_damage",
			float(base_damage),
			hit.position,
			false,
			self,
		)
		hit_confirmed.emit(false)
	else:
		_emit_audio("knife.hit_wall", AudioRouterScript.CHAN_ITEM)
		_spawn_impact(hit.position, hit.normal, _shot_sequence)
	_shot_sequence = (_shot_sequence + 1) & 0xff


func _spawn_thrown_grenade() -> void:
	if active_weapon not in ["hegrenade", "flashbang", "smokegrenade"] or clip <= 0:
		_clear_grenade_release_view()
		return
	clip -= 1
	_store_active_ammunition()
	ammo_changed.emit(clip, reserve, false)
	_play_weapon_action("throw", "throw")
	publish_combat_presentation("grenade_action", {"weapon": active_weapon, "action": "throw"})
	var grenade: HEGrenade = GrenadeScript.new()
	get_tree().current_scene.add_child(grenade)
	var release_view: Vector2 = (
		_grenade_release_view
		if _grenade_release_view_latched
		else input_view_angles()
	)
	var goldsrc_angles := grenade_goldsrc_angles(release_view)
	grenade.launch(
		Ballistics.he_throw_origin(camera.global_position, goldsrc_angles.x, goldsrc_angles.y),
		Ballistics.he_throw_velocity(goldsrc_angles.x, goldsrc_angles.y, velocity),
		self,
		active_weapon,
	)
	_clear_grenade_release_view()


func _release_held_grenade() -> void:
	if weapon_clock.state != WeaponClockScript.STATE_GRENADE_PINNED:
		return
	_latch_grenade_release_view()
	weapon_clock.release_grenade(clip <= 1)
	_consume_weapon_clock_events(weapon_clock.take_events())


func _start_reload() -> void:
	if network_read_only:
		return
	var definition: Dictionary = WEAPONS[active_weapon]
	var magazine := int(definition.magazine)
	if reloading or magazine <= 0 or clip >= magazine or reserve <= 0 or not alive:
		return
	if not weapon_clock.begin_reload():
		return
	reloading = true
	ammo_changed.emit(clip, reserve, reloading)
	_audio_schedule.clear()
	for stage: Dictionary in RELOAD_AUDIO_STAGES.get(active_weapon, []):
		_schedule_audio(str(stage.event), int(stage.offset))
	if active_weapon == "xm1014":
		# start_reload MDL event: frame 20 at 30 fps.
		_schedule_audio("xm1014.reload_start", 67)
	if weapon_clock.is_shell_reloading():
		_schedule_audio("m3.insert" if active_weapon == "m3" else "shotgun.insert",
			weapon_clock.next_primary_tick - weapon_clock.tick)
	_play_weapon_action("reload", "reload")
	publish_combat_presentation("reload", {"weapon": active_weapon})


func _complete_reload() -> void:
	if not reloading or not alive:
		return
	var definition: Dictionary = WEAPONS[active_weapon]
	var magazine := int(definition.magazine)
	var needed := magazine - clip
	var loaded: int = mini(needed, reserve)
	clip += loaded
	reserve -= loaded
	_store_active_ammunition()
	reloading = false
	_reset_weapon_accuracy()
	ammo_changed.emit(clip, reserve, reloading)


## DefaultShotgunReload seats one shell per insert interval, so the HUD ammo
## counter climbs shell by shell and the loop can end as soon as the magazine
## is full or the reserve is dry.
func _insert_reload_shell() -> void:
	if not reloading or not alive:
		return
	var magazine := int(WEAPONS[active_weapon].magazine)
	if clip < magazine and reserve > 0:
		clip += 1
		reserve -= 1
		_store_active_ammunition()
		ammo_changed.emit(clip, reserve, reloading)
	if clip >= magazine or reserve <= 0:
		_finish_shell_reload()
	else:
		# Start the next insertion as the previous shell seats, not every frame.
		_emit_audio("m3.insert" if active_weapon == "m3" else "shotgun.insert", AudioRouterScript.CHAN_WEAPON)


func _finish_shell_reload() -> void:
	weapon_clock.finish_shell_reload()
	reloading = false
	_audio_schedule.clear()
	if active_weapon == "m3":
		_emit_audio("m3.pump", AudioRouterScript.CHAN_WEAPON)
	_store_active_ammunition()
	ammo_changed.emit(clip, reserve, reloading)


## 1.6 aborts a shotgun reload the moment the player attacks with a seated
## shell; the pending shells simply stay in reserve.
func _interrupt_shell_reload() -> bool:
	if not weapon_clock.can_interrupt_reload() or clip <= 0 or not alive:
		return false
	weapon_clock.cancel_reload()
	reloading = false
	_audio_schedule.clear()
	ammo_changed.emit(clip, reserve, reloading)
	return true


func switch_weapon(weapon: String) -> void:
	if network_read_only:
		return
	if not WEAPONS.has(weapon) or not owns_weapon(weapon) or weapon == active_weapon:
		return
	_store_active_ammunition()
	reloading = false
	_audio_schedule.clear()
	_clear_grenade_release_view()
	previous_weapon = active_weapon
	active_weapon = weapon
	_knife_swing = 0
	if str(WEAPONS[active_weapon].secondary) == "zoom":
		weapon_modes[active_weapon] = 0
	_burst_shots_remaining = 0
	_glock_recorded_burst = false
	_next_burst_tick = -1
	_glock_trigger_consumed = false
	camera.fov = settings.field_of_view if is_local_human() else 74.0
	weapon_clock.begin_deploy(active_weapon)
	_reset_weapon_accuracy()
	if ammunition.has(active_weapon):
		clip = int(ammunition[active_weapon].clip)
		reserve = int(ammunition[active_weapon].reserve)
	else:
		clip = -1
		reserve = -1
	if is_instance_valid(viewmodel):
		viewmodel.load_weapon(active_weapon)
		viewmodel.set_silenced(bool(weapon_modes.get(active_weapon, false)))
		viewmodel.play_action("switch")
	_refresh_character_model()
	for stage: Dictionary in AudioCatalogScript.DEPLOY_AUDIO_STAGES.get(active_weapon, []):
		if int(stage.offset) == 0:
			_emit_audio(str(stage.event), AudioRouterScript.CHAN_WEAPON)
		else:
			_schedule_audio(str(stage.event), int(stage.offset))
	weapon_changed.emit(WEAPONS[active_weapon].name, WEAPONS[active_weapon].mode)
	ammo_changed.emit(clip, reserve, false)


func _is_droppable_gun(weapon: String) -> bool:
	if not WEAPONS.has(weapon):
		return false
	return str(WEAPONS[weapon].category) not in ["melee", "grenade", "objective"]


func _try_drop_active_weapon() -> void:
	if network_read_only:
		return
	# CS 1.6 `drop`: only guns leave the inventory; knife/grenades/C4 keep the
	# key inert (the carried C4 has its own drop contract in game.gd).
	if not _is_droppable_gun(active_weapon):
		return
	_store_active_ammunition()
	var dropped := active_weapon
	var dropped_ammo: Dictionary = ammunition.get(dropped, {})
	var dropped_clip := int(dropped_ammo.get("clip", 0))
	var dropped_reserve := int(dropped_ammo.get("reserve", 0))
	owned_weapons.erase(dropped)
	ammunition.erase(dropped)
	switch_weapon(_best_owned_weapon())
	weapon_drop_requested.emit(dropped, dropped_clip, dropped_reserve)


func death_drop_weapon() -> String:
	# CS 1.6 drops the held gun on death; a knife/grenade/C4 holder drops the
	# best carried gun instead (primary first, else pistol).
	_store_active_ammunition()
	if _is_droppable_gun(active_weapon):
		return active_weapon
	for slot in [1, 2]:
		for weapon_name: String in owned_weapons.keys():
			if (
				bool(owned_weapons[weapon_name])
				and _is_droppable_gun(weapon_name)
				and int(WEAPONS[weapon_name].slot) == slot
			):
				return weapon_name
	return ""


func owns_weapon(weapon: String) -> bool:
	return bool(owned_weapons.get(weapon.to_lower(), false))


func best_owned_weapon_in_slot(slot: int) -> String:
	# CS 1.6 slot keys select whatever the player actually carries in that
	# slot (1 primary, 2 pistol, 3 knife, 4 grenades), not a fixed weapon.
	# Repeated presses of the grenade key cycle HE -> flash -> smoke.
	var candidates: Array[String] = []
	var slot_order := (
		["hegrenade", "flashbang", "smokegrenade"]
		if slot == 4
		else owned_weapons.keys()
	)
	for weapon_name: String in slot_order:
		if not bool(owned_weapons.get(weapon_name, false)) or not WEAPONS.has(weapon_name):
			continue
		if int(WEAPONS[weapon_name].slot) != slot:
			continue
		if slot == 4:
			var grenade_ammo: Dictionary = ammunition.get(weapon_name, {})
			if int(grenade_ammo.get("clip", 0)) <= 0:
				continue
		candidates.append(weapon_name)
	if candidates.is_empty():
		return ""
	var active_index := candidates.find(active_weapon)
	if active_index >= 0:
		return candidates[(active_index + 1) % candidates.size()]
	return candidates[0]


func _best_owned_weapon() -> String:
	for slot in [1, 2, 3]:
		for weapon_name: String in owned_weapons.keys():
			if (
				bool(owned_weapons[weapon_name])
				and WEAPONS.has(weapon_name)
				and int(WEAPONS[weapon_name].slot) == slot
				and str(WEAPONS[weapon_name].category) != "grenade"
			):
				return weapon_name
	return active_weapon


func grant_item(item_id: String, amount := 1) -> bool:
	var canonical := item_id.to_lower().strip_edges()
	if canonical.begins_with("weapon_"):
		canonical = canonical.trim_prefix("weapon_")
	if WEAPONS.has(canonical):
		var definition: Dictionary = WEAPONS[canonical]
		if not owns_weapon(canonical) and str(definition.secondary) == "silencer":
			# Fresh human loadouts start suppressed; re-grants of owned guns
			# must not undo a player's deliberate mode selection.
			weapon_modes[canonical] = true
		if str(definition.category) == "grenade":
			owned_weapons[canonical] = true
			if not ammunition.has(canonical):
				ammunition[canonical] = {"clip": 0, "reserve": 0}
			var carry_max := int(definition.get("reserve_max", 1))
			ammunition[canonical].clip = mini(
				carry_max,
				int(ammunition[canonical].clip) + maxi(amount, 1),
			)
			return true
		if int(definition.slot) in [1, 2]:
			for owned_name: String in owned_weapons.keys():
				if (
					owned_name != canonical
					and WEAPONS.has(owned_name)
					and int(WEAPONS[owned_name].slot) == int(definition.slot)
				):
					owned_weapons.erase(owned_name)
		owned_weapons[canonical] = true
		if not ammunition.has(canonical):
			ammunition[canonical] = {
				"clip": int(definition.magazine),
				"reserve": 0,
			}
		return true
	var ammo_name := canonical.trim_prefix("ammo_")
	if WeaponRegistryScript.AMMO.has(ammo_name):
		var ammo_definition: Dictionary = WeaponRegistryScript.AMMO[ammo_name]
		var granted := false
		for weapon_name: String in owned_weapons.keys():
			if WEAPONS.has(weapon_name) and str(WEAPONS[weapon_name].ammo) == ammo_name:
				ammunition[weapon_name].reserve = mini(
					int(ammo_definition.reserve_max),
					int(ammunition[weapon_name].reserve)
						+ int(ammo_definition.box) * maxi(amount, 1),
				)
				granted = true
		return granted
	if canonical == "assaultsuit":
		equipment.kevlar = true
		equipment.helmet = true
		armor = 100
		has_helmet = true
		health_changed.emit(health, armor)
		return true
	if canonical in ["kevlar", "helmet", "defuser", "nvgs", "shield"]:
		equipment[canonical] = true
		if canonical == "kevlar":
			armor = 100
		elif canonical == "helmet":
			has_helmet = true
		health_changed.emit(health, armor)
		return true
	return false


func _initialize_starting_loadout() -> void:
	owned_weapons.clear()
	ammunition.clear()
	weapon_modes.clear()
	previous_weapon = ""
	for item: String in equipment:
		equipment[item] = false
	owned_weapons.knife = true
	ammunition.knife = {"clip": -1, "reserve": -1}
	var pistol := "usp" if team == TEAM_COUNTER_TERRORIST else "glock18"
	owned_weapons[pistol] = true
	if pistol == "usp":
		weapon_modes[pistol] = true
	ammunition[pistol] = {
		"clip": int(WEAPONS[pistol].magazine),
		"reserve": int(WEAPONS[pistol].reserve),
	}
	active_weapon = pistol
	clip = int(ammunition[pistol].clip)
	reserve = int(ammunition[pistol].reserve)


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


func _spawn_impact(position: Vector3, normal: Vector3, effect_sequence := 0) -> void:
	if is_instance_valid(combat_effects):
		combat_effects.spawn_world_impact(position, normal, effect_sequence, "knife")


func spawn_incoming_tracer(_from: Vector3, _to: Vector3) -> void:
	# Compatibility API: CS rifle/pistol events do not request per-shot
	# TE_TRACER lines. Source-requested tracer profiles can be added centrally.
	pass


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
	_emit_audio(last_damage_impact_audio, AudioRouterScript.CHAN_VOICE)


func _on_combatant_eliminated(_attacker: Combatant, headshot: bool) -> void:
	controls_enabled = false
	post_round_movement_enabled = false
	objective_movement_locked = false
	objective_crouch_locked = false
	reloading = false
	_audio_schedule.clear()
	_clear_grenade_release_view()
	_emit_audio(
		"player.headshot_death" if headshot else "player.death",
		AudioRouterScript.CHAN_VOICE,
	)
	weapon_clock.reset(active_weapon, weapon_clock.tick)
	if is_instance_valid(character_model):
		character_model.play_death()
	died.emit()


func reset_player(spawn_position: Vector3, keep_loadout := true) -> void:
	post_round_movement_enabled = false
	flash_blind_until_frame = -1
	flash_blind_total_seconds = 0.0
	spawn_serial += 1
	_store_active_ammunition()
	reloading = false
	var starting_armor := armor
	if not keep_loadout:
		starting_armor = 0
		_initialize_starting_loadout()
	reset_combatant(spawn_position, starting_armor)
	weapon_clock.reset(active_weapon)
	clip = int(ammunition[active_weapon].clip)
	reserve = int(ammunition[active_weapon].reserve)
	velocity = Vector3.ZERO
	objective_movement_locked = false
	objective_crouch_locked = false
	_standing = true
	_walking = false
	_duck_elapsed = 0.0
	_jump_was_down = false
	_yaw = 0.0
	_pitch = 0.0
	_punch_degrees = Vector2.ZERO
	_reset_weapon_accuracy()
	_burst_shots_remaining = 0
	_glock_recorded_burst = false
	_next_burst_tick = -1
	_last_shot_at = -10.0
	_glock_trigger_consumed = false
	_audio_schedule.clear()
	_clear_grenade_release_view()
	_next_footstep_tick = weapon_clock.tick
	_left_foot = false
	_footstep_serial = 0
	if is_instance_valid(muzzle_light):
		muzzle_light.visible = false
	_movement_grounded = false
	_stair_view_offset = 0.0
	if is_instance_valid(movement_kernel):
		movement_kernel.grounded = false
		movement_kernel.ground_normal = Vector3.UP
	rotation = Vector3.ZERO
	collider.rotation = Vector3.ZERO
	_apply_hull(STAND_HEIGHT)
	camera.rotation = Vector3.ZERO
	camera.position.y = STAND_EYE
	if is_instance_valid(weapon_anchor):
		weapon_anchor.rotation = Vector3.ZERO
		weapon_anchor.position = Vector3.ZERO
	if is_instance_valid(viewmodel):
		viewmodel.load_weapon(active_weapon)
		viewmodel.set_silenced(bool(weapon_modes.get(active_weapon, false)))
		viewmodel.position = viewmodel.base_position
	_refresh_character_model()
	health_changed.emit(health, armor)
	ammo_changed.emit(clip, reserve, reloading)
	weapon_changed.emit(WEAPONS[active_weapon].name, WEAPONS[active_weapon].mode)
