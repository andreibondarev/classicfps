class_name PlayerController
extends Combatant

signal health_changed(health: int, armor: int)
signal ammo_changed(clip: int, reserve: int, reloading: bool)
signal weapon_changed(weapon_name: String, fire_mode: String)
signal hit_confirmed(headshot: bool)
signal died

const STAND_HEIGHT := 1.82
const CROUCH_HEIGHT := 1.22
const CAPSULE_RADIUS := 0.34
const STAND_EYE := 1.62
const CROUCH_EYE := 1.05
const RUN_SPEED := 6.35
const WALK_SPEED := 3.20
const CROUCH_SPEED := 2.75
const GROUND_ACCEL := 10.0
const AIR_ACCEL := 11.5
const GROUND_FRICTION := 5.2
const STOP_SPEED := 2.55
const GRAVITY := 20.0
const JUMP_SPEED := 6.65
const RANGE := 180.0
const ViewModelScript = preload("res://scripts/mdl_viewmodel.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const WEAPONS := {
	"ak47": {
		"name": "AK-47", "mode": "FULL AUTO", "magazine": 30, "reserve": 90,
		"damage": 34.0, "interval": 0.10, "reload": 2.25, "spread": 0.0018,
		"shot": "res://assets/sounds/ak47-1.wav",
		"reload_sound": "res://assets/sounds/ak47_clipin.wav",
	},
	"deagle": {
		"name": "DESERT EAGLE", "mode": "SEMI AUTO", "magazine": 7, "reserve": 35,
		"damage": 54.0, "interval": 0.225, "reload": 2.20, "spread": 0.0013,
		"shot": "res://assets/sounds/deagle-1.wav",
		"reload_sound": "res://assets/sounds/deagle_reload.wav",
	},
	"knife": {
		"name": "KNIFE", "mode": "MELEE", "magazine": -1, "reserve": -1,
		"damage": 65.0, "interval": 0.48, "reload": 0.0, "spread": 0.0,
		"shot": "res://assets/sounds/knife_slash1.wav", "reload_sound": "",
	},
	"hegrenade": {
		"name": "HE GRENADE", "mode": "THROW", "magazine": 1, "reserve": 0,
		"damage": 0.0, "interval": 1.0, "reload": 0.0, "spread": 0.0,
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
var _step_distance := 0.0
var _next_step_at := 1.65
var _step_index := 0
var _recoil_index := 0
var _last_shot_at := -10.0

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
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.22
	floor_stop_on_slope = true
	armor = 100
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
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_RADIUS
	shape.height = STAND_HEIGHT
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
	rotation.y = _yaw
	camera.rotation.x = _pitch


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
	rotation.y = _yaw
	camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not controls_enabled or not alive:
		velocity = Vector3.ZERO
		last_command = {}
		return

	var command := combat_controller.gather_command(delta)
	last_command = command
	var look_delta: Vector2 = command.look_delta
	if not look_delta.is_zero_approx():
		_apply_mouse_look(look_delta)
	_update_crouch(delta, command.crouch)
	_walking = command.walk and _standing
	var input: Vector2 = command.movement
	var wish_direction: Vector3 = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, _yaw)
	if wish_direction.length_squared() > 1.0:
		wish_direction = wish_direction.normalized()
	var wish_speed := _movement_speed(not _standing, _walking) * minf(1.0, input.length())

	if is_on_floor():
		if not command.jump:
			_apply_friction(delta)
		_accelerate(wish_direction, wish_speed, GROUND_ACCEL, delta)
		if command.jump and _standing:
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
		_accelerate(wish_direction, wish_speed, AIR_ACCEL, delta)

	var previous := global_position
	move_and_slide()
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


func _apply_friction(delta: float) -> void:
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var speed: float = horizontal.length()
	if speed < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var control: float = maxf(speed, STOP_SPEED)
	var drop: float = control * GROUND_FRICTION * delta
	var next_speed: float = maxf(0.0, speed - drop)
	horizontal *= next_speed / speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _accelerate(wish_direction: Vector3, wish_speed: float, acceleration: float, delta: float) -> void:
	if wish_speed <= 0.0 or wish_direction.is_zero_approx():
		return
	var current_speed: float = Vector3(velocity.x, 0.0, velocity.z).dot(wish_direction)
	var add_speed: float = wish_speed - current_speed
	if add_speed <= 0.0:
		return
	var acceleration_speed: float = minf(acceleration * wish_speed * delta, add_speed)
	velocity.x += wish_direction.x * acceleration_speed
	velocity.z += wish_direction.z * acceleration_speed


func _movement_speed(crouching: bool, walking: bool) -> float:
	if crouching:
		return CROUCH_SPEED
	return WALK_SPEED if walking else RUN_SPEED


func _update_crouch(delta: float, wants_crouch: bool) -> void:
	if not wants_crouch and not _standing:
		var probe := Transform3D(Basis.IDENTITY, Vector3(0, (STAND_HEIGHT - CROUCH_HEIGHT) * 0.5, 0))
		if test_move(global_transform, probe.origin):
			wants_crouch = true
	_standing = not wants_crouch
	var target_height := STAND_HEIGHT if _standing else CROUCH_HEIGHT
	var target_eye := STAND_EYE if _standing else CROUCH_EYE
	var shape := collider.shape as CapsuleShape3D
	shape.height = move_toward(shape.height, target_height, delta * 5.5)
	collider.position.y = shape.height * 0.5
	camera.position.y = move_toward(camera.position.y, target_eye, delta * 5.5)


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

	var movement := Vector2(velocity.x, velocity.z).length() / RUN_SPEED
	var spread: float = float(definition.spread) + movement * 0.008 + (0.006 if not is_on_floor() else 0.0)
	var direction := -camera.global_transform.basis.z
	direction += camera.global_transform.basis.x * _rng.randfn(0.0, spread)
	direction += camera.global_transform.basis.y * _rng.randfn(0.0, spread)
	direction = direction.normalized()
	var origin := camera.global_position
	var end := origin + direction * RANGE
	var query := PhysicsRayQueryParameters3D.create(origin, end, 1 | 2, [get_rid()])
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var trace_end := end
	if not hit.is_empty():
		trace_end = hit.position
		var hit_collider: Object = hit.collider
		var headshot := false
		if hit_collider and hit_collider.has_method("head_height"):
			headshot = hit.position.y >= float(hit_collider.call("head_height"))
		if hit_collider and hit_collider.has_method("apply_damage"):
			hit_collider.call(
				"apply_damage",
				float(definition.damage) * (4.0 if headshot else 1.0),
				hit.position,
				headshot,
				self,
			)
			hit_confirmed.emit(headshot)
		else:
			_spawn_impact(hit.position, hit.normal)
	_spawn_tracer(origin, trace_end, Color("#ffd46b"))

	if now - _last_shot_at > 0.34:
		_recoil_index = 0
	var recoil: Vector2 = RECOIL_PATTERN[mini(_recoil_index, RECOIL_PATTERN.size() - 1)]
	var recoil_scale := 1.36 if active_weapon == "deagle" else 1.0
	_pitch = clamp(_pitch - deg_to_rad(recoil.y * recoil_scale), deg_to_rad(-89.0), deg_to_rad(89.0))
	_yaw += deg_to_rad(recoil.x * recoil_scale)
	_recoil_index += 1
	_last_shot_at = now
	rotation.y = _yaw
	camera.rotation.x = _pitch
	viewmodel.play_action("fire")


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
	var direction := -camera.global_transform.basis.z
	grenade.launch(
		camera.global_position + direction * 0.55,
		direction * 14.5 + Vector3.UP * 2.7 + velocity * 0.35,
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
	ammo_changed.emit(clip, reserve, reloading)


func switch_weapon(weapon: String) -> void:
	if not WEAPONS.has(weapon) or weapon == active_weapon:
		return
	_store_active_ammunition()
	_reload_generation += 1
	reloading = false
	active_weapon = weapon
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
	_walking = false
	_yaw = 0.0
	_pitch = 0.0
	rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	weapon_anchor.rotation = Vector3.ZERO
	weapon_anchor.position = Vector3.ZERO
	viewmodel.load_weapon(active_weapon)
	viewmodel.position = viewmodel.base_position
	_apply_weapon_audio()
	health_changed.emit(health, armor)
	ammo_changed.emit(clip, reserve, reloading)
	weapon_changed.emit(WEAPONS[active_weapon].name, WEAPONS[active_weapon].mode)
