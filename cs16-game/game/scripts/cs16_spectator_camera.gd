class_name CS16SpectatorCamera
extends Node3D
## CS 1.6 death spectate: after a short delay the dead human player can watch
## living teammates in chase/first-person or use free fly. Self-contained node;
## game.gd schedules it on player death and ends it on round reset.

signal ended
signal spectate_target_changed(target: Combatant)

const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")

const MODE_CHASE := "chase"
const MODE_FIRST_PERSON := "first_person"
const MODE_FREE_FLY := "free_fly"
const ACTIVATION_DELAY := 2.0
const CHASE_DISTANCE := 1.12  # ~112 GoldSrc units behind the target.
const HEAD_HEIGHT := 0.53  # Standing eye height at this project's 0.01 scale.
const CHASE_LIFT := 0.14
const FOLLOW_RATE := 10.0
const YAW_FOLLOW_RATE := 6.0
const PITCH_MIN := deg_to_rad(-75.0)
const PITCH_MAX := deg_to_rad(60.0)
const DEFAULT_PITCH := deg_to_rad(-14.0)
const WORLD_COLLISION_MASK := 1
const CAMERA_WALL_MARGIN := 0.06
const FREE_FLY_SPEED := 4.0
const FREE_FLY_FAST_MULTIPLIER := 2.0

var camera: Camera3D
var active := false
var pending := false
var target: Combatant = null
var mode := MODE_CHASE

var _player: PlayerController
var _hud: GameHUD
var _teammate_provider := Callable()
var _activation_blocked := Callable()
var _pending_seconds := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := DEFAULT_PITCH
var _user_orbited := false
var _follow_head := Vector3.ZERO
var _settings: Node
var _default_fov := 74.0
var _hud_target_instance_id := 0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "SpectatorCamera3D"
	camera.current = false
	camera.fov = 90.0
	camera.near = 0.035
	add_child(camera)
	_settings = get_node_or_null("/root/GameSettings")
	if is_instance_valid(_player) and is_instance_valid(_player.camera):
		camera.fov = _player.camera.fov
		camera.near = _player.camera.near
	_default_fov = camera.fov


func setup(
	player: PlayerController,
	teammate_provider: Callable,
	activation_blocked := Callable(),
	hud: GameHUD = null,
) -> void:
	_player = player
	_teammate_provider = teammate_provider
	_activation_blocked = activation_blocked
	_hud = hud


func is_engaged() -> bool:
	return active or pending


func schedule(delay := ACTIVATION_DELAY) -> void:
	if active or pending:
		return
	pending = true
	_pending_seconds = delay


func stop() -> void:
	pending = false
	active = false
	target = null
	mode = MODE_CHASE
	if is_instance_valid(camera):
		camera.current = false
		camera.fov = _default_fov
	if is_instance_valid(_player) and is_instance_valid(_player.weapon_anchor):
		_player.weapon_anchor.visible = true
	if is_instance_valid(_hud):
		_hud.set_spectator_first_person(false)
		_hud.set_spectating(false)
		_restore_player_hud()
	_hud_target_instance_id = 0
	_set_hud_label("")


func cycle(direction: int) -> void:
	if not active or mode not in [MODE_CHASE, MODE_FIRST_PERSON]:
		return
	var mates := _living_teammates()
	if mates.is_empty():
		return
	var index := mates.find(target)
	if index < 0:
		index = 0 if direction >= 0 else mates.size() - 1
	else:
		index = posmod(index + direction, mates.size())
	_set_target(mates[index])


func _physics_process(delta: float) -> void:
	if pending:
		_pending_seconds -= delta
		if _pending_seconds <= 0.0:
			pending = false
			_try_activate()
		return
	if not active:
		return
	if is_instance_valid(_player) and _player.alive:
		# Round reset (or any respawn path) revived the player while we were
		# still spectating; hand the view back.
		ended.emit()
		return
	match mode:
		MODE_FREE_FLY:
			_update_free_fly(delta)
		MODE_FIRST_PERSON:
			if not _target_watchable():
				_advance_after_target_loss()
			if mode == MODE_FIRST_PERSON:
				_update_first_person()
		_:
			if not _target_watchable():
				_advance_after_target_loss()
			if mode == MODE_CHASE:
				_update_chase(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_SPACE:
			toggle_mode()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if mode in [MODE_CHASE, MODE_FREE_FLY]:
			_apply_orbit((event as InputEventMouseMotion).relative)
		if mode == MODE_FREE_FLY:
			_apply_free_fly_rotation()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_LEFT:
			cycle(1)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			cycle(-1)


func _try_activate() -> void:
	if active:
		return
	if is_instance_valid(_player) and _player.alive:
		return
	if _activation_blocked.is_valid() and bool(_activation_blocked.call()):
		return
	active = true
	if is_instance_valid(_player):
		_player.weapon_anchor.visible = false
		_player.muzzle_light.visible = false
	if is_instance_valid(_hud):
		_hud.set_spectating(true)
	# Start the chase from the death view so the cut reads continuously.
	if is_instance_valid(_player) and is_instance_valid(_player.camera):
		camera.global_transform = _player.camera.global_transform
	camera.current = true
	var mates := _living_teammates()
	if mates.is_empty():
		# No teammates left: the death view becomes a movable free camera.
		target = null
		_enter_free_fly()
	else:
		mode = MODE_CHASE
		camera.fov = _default_fov
		_set_first_person_hud(false)
		_set_target(mates[0])


func is_free_fly() -> bool:
	return active and mode == MODE_FREE_FLY


func is_first_person() -> bool:
	return active and mode == MODE_FIRST_PERSON


func toggle_mode() -> void:
	if not active:
		return
	if mode == MODE_CHASE:
		_enter_first_person()
		return
	if mode == MODE_FIRST_PERSON:
		_enter_free_fly()
		return
	var mates := _living_teammates()
	if mates.is_empty():
		return
	mode = MODE_CHASE
	camera.fov = _default_fov
	if not _target_watchable():
		_set_target(mates[0])
	else:
		_set_target(target)


func _enter_first_person() -> void:
	if not _target_watchable():
		var mates := _living_teammates()
		if mates.is_empty():
			_enter_free_fly()
			return
		_set_target(mates[0])
	mode = MODE_FIRST_PERSON
	_set_hud_label("%s (First Person)" % target.display_name)
	_set_first_person_hud(true)
	_update_first_person()


func _enter_free_fly() -> void:
	mode = MODE_FREE_FLY
	camera.fov = _default_fov
	_set_first_person_hud(false)
	# Preserve the chase/death view exactly, then let mouse look continue from
	# that orientation without a visible snap.
	var angles := camera.global_rotation
	_orbit_pitch = clampf(angles.x, PITCH_MIN, PITCH_MAX)
	_orbit_yaw = angles.y
	_apply_free_fly_rotation()
	_set_hud_label("Free Look")


func _apply_free_fly_rotation() -> void:
	camera.global_rotation = Vector3(_orbit_pitch, _orbit_yaw, 0.0)


func _update_free_fly(delta: float) -> void:
	var planar := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := camera.global_basis.x * planar.x + (-camera.global_basis.z) * -planar.y
	# Space owns the mode toggle. E/Q provide unambiguous vertical flight.
	if Input.is_key_pressed(KEY_E):
		direction += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		direction += Vector3.DOWN
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	var speed := FREE_FLY_SPEED * (FREE_FLY_FAST_MULTIPLIER if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	camera.global_position += direction * speed * delta


func _update_first_person() -> void:
	if not _target_watchable():
		return
	var view := target.spectator_view_transform()
	var target_camera := target.get_node_or_null("PlayerCamera") as Camera3D
	camera.fov = target_camera.fov if is_instance_valid(target_camera) else _default_fov
	# Move just beyond the world model's face so its head cannot occlude the
	# spectator. The offset is only eight GoldSrc units and keeps the POV at eye
	# height while avoiding a per-camera render-layer special case.
	view.origin += -view.basis.z * 0.08
	camera.global_transform = view
	_sync_first_person_hud()


func _set_first_person_hud(enabled: bool) -> void:
	if not is_instance_valid(_hud):
		return
	_hud.set_spectator_first_person(enabled)
	if not enabled:
		_hud_target_instance_id = 0
		_restore_player_hud()


func _sync_first_person_hud() -> void:
	if not is_instance_valid(_hud) or not _target_watchable():
		return
	var changed := _hud_target_instance_id != target.get_instance_id()
	_hud_target_instance_id = target.get_instance_id()
	if changed:
		_hud.reset_money_presentation()
	var weapon_id := ""
	var clip := -1
	var reserve := -1
	var reloading := false
	var mode_enabled := false
	var owns_defuser := false
	if target is PlayerController:
		var human := target as PlayerController
		weapon_id = human.active_weapon
		clip = human.clip
		reserve = human.reserve
		reloading = human.reloading
		mode_enabled = bool(human.weapon_modes.get(weapon_id, false))
		owns_defuser = bool(human.equipment.get("defuser", false))
	elif target is TargetActor:
		var bot := target as TargetActor
		weapon_id = "c4" if bot.c4_equipped else bot.active_weapon_name
		clip = -1 if bot.c4_equipped else bot.weapon_clip
		reserve = -1 if bot.c4_equipped else bot.weapon_reserve
		reloading = bot.weapon_reloading
		owns_defuser = _round_actor_has_defuser(target)
	else:
		weapon_id = str(target.get_meta("spectator_weapon", ""))
		clip = int(target.get_meta("spectator_clip", -1))
		reserve = int(target.get_meta("spectator_reserve", -1))
		reloading = bool(target.get_meta("spectator_reloading", false))
	var definition: Dictionary = WeaponRegistryScript.definition(weapon_id)
	var weapon_name := str(definition.get("name", weapon_id.to_upper()))
	var fire_mode := str(definition.get("mode", ""))
	if str(definition.get("secondary", "")) == "burst" and mode_enabled:
		fire_mode = "BURST FIRE"
	elif str(definition.get("secondary", "")) == "silencer" and mode_enabled:
		fire_mode = "SILENCED"
	_hud.update_health(target.health, target.armor, target.has_helmet)
	_hud.update_weapon(weapon_name, fire_mode)
	_hud.update_ammo(clip, reserve, reloading)
	_hud.update_defuse_kit(target.team, target.alive, owns_defuser)
	_hud.update_money(_actor_money(target))


func _round_actor_has_defuser(actor: Combatant) -> bool:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene) or not scene.has_method("_round_id_for_actor"):
		return false
	var state: Variant = scene.get("round_state")
	if not is_instance_valid(state):
		return false
	var actor_id := str(scene.call("_round_id_for_actor", actor))
	var row: Dictionary = state.players.get(actor_id, {})
	return bool(row.get("has_defuser", false))


func _actor_money(actor: Combatant) -> int:
	if actor.has_meta("spectator_money"):
		return int(actor.get_meta("spectator_money"))
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("_round_id_for_actor"):
		var state: Variant = scene.get("round_state")
		if is_instance_valid(state):
			var actor_id := str(scene.call("_round_id_for_actor", actor))
			return int(state.players.get(actor_id, {}).get("money", 0))
	return 0


func _restore_player_hud() -> void:
	if not is_instance_valid(_hud) or not is_instance_valid(_player):
		return
	var definition: Dictionary = WeaponRegistryScript.definition(_player.active_weapon)
	var mode_enabled := bool(_player.weapon_modes.get(_player.active_weapon, false))
	var fire_mode := str(definition.get("mode", ""))
	if str(definition.get("secondary", "")) == "burst" and mode_enabled:
		fire_mode = "BURST FIRE"
	elif str(definition.get("secondary", "")) == "silencer" and mode_enabled:
		fire_mode = "SILENCED"
	_hud.update_health(_player.health, _player.armor, _player.has_helmet)
	_hud.update_weapon(str(definition.get("name", _player.active_weapon.to_upper())), fire_mode)
	_hud.update_ammo(_player.clip, _player.reserve, _player.reloading)
	_hud.update_defuse_kit(_player.team, _player.alive,
		bool(_player.equipment.get("defuser", false)))
	var scene := get_tree().current_scene
	if is_instance_valid(scene):
		var current_money: Variant = scene.get("money")
		if current_money != null:
			_hud.reset_money_presentation()
			_hud.update_money(int(current_money))


func _living_teammates() -> Array[Combatant]:
	var mates: Array[Combatant] = []
	if not _teammate_provider.is_valid():
		return mates
	for mate: Variant in _teammate_provider.call():
		var combatant := mate as Combatant
		if is_instance_valid(combatant) and combatant.alive:
			mates.append(combatant)
	return mates


func _target_watchable() -> bool:
	return is_instance_valid(target) and target.alive and target.is_inside_tree()


func _advance_after_target_loss() -> void:
	var prior_mode := mode
	var mates := _living_teammates()
	if mates.is_empty():
		# Keep the last view but allow the observer to fly until round reset.
		target = null
		_enter_free_fly()
		return
	var replacement := mates[0]
	if is_instance_valid(target) and mates.has(target):
		replacement = target
	_set_target(replacement)
	if prior_mode == MODE_FIRST_PERSON:
		mode = MODE_FIRST_PERSON
		_set_hud_label("%s (First Person)" % target.display_name)


func _set_target(next_target: Combatant) -> void:
	var changed := next_target != target
	target = next_target
	if not is_instance_valid(target):
		return
	_user_orbited = false
	var forward := -target.global_transform.basis.z
	_orbit_yaw = atan2(-forward.x, -forward.z)
	_orbit_pitch = DEFAULT_PITCH
	_follow_head = _target_head()
	_set_hud_label(
		"%s (First Person)" % target.display_name
		if mode == MODE_FIRST_PERSON
		else target.display_name
	)
	if changed:
		spectate_target_changed.emit(target)


func _target_head() -> Vector3:
	return target.global_position + Vector3.UP * HEAD_HEIGHT


func _update_chase(delta: float) -> void:
	if not _target_watchable():
		return
	var head := _target_head()
	_follow_head = _follow_head.lerp(head, 1.0 - exp(-FOLLOW_RATE * delta))
	if not _user_orbited:
		# Until the spectator grabs the mouse, drift behind the target's facing
		# like the classic chase cam.
		var forward := -target.global_transform.basis.z
		var facing_yaw := atan2(-forward.x, -forward.z)
		_orbit_yaw = lerp_angle(
			_orbit_yaw,
			facing_yaw,
			1.0 - exp(-YAW_FOLLOW_RATE * delta),
		)
	var look := Basis.from_euler(Vector3(_orbit_pitch, _orbit_yaw, 0.0))
	var desired := _follow_head - (-look.z) * CHASE_DISTANCE + Vector3.UP * CHASE_LIFT
	camera.global_position = _clip_to_world(_follow_head, desired)
	var focus := _follow_head
	if camera.global_position.distance_squared_to(focus) > 0.000001:
		camera.look_at(focus, Vector3.UP)


func _clip_to_world(from_position: Vector3, to_position: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return to_position
	var query := PhysicsRayQueryParameters3D.create(
		from_position,
		to_position,
		WORLD_COLLISION_MASK,
	)
	if is_instance_valid(target):
		query.exclude = [target.get_rid()]
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to_position
	var direction: Vector3 = to_position - from_position
	if direction.is_zero_approx():
		return to_position
	return (
		Vector3(hit.position)
		- direction.normalized() * CAMERA_WALL_MARGIN
	)


func _apply_orbit(relative: Vector2) -> void:
	_user_orbited = true
	var sensitivity := 0.10
	var vertical_sign := 1.0
	if _settings != null:
		sensitivity = float(_settings.mouse_sensitivity)
		vertical_sign = -1.0 if bool(_settings.invert_y) else 1.0
	var radians_per_pixel := deg_to_rad(sensitivity)
	_orbit_yaw -= relative.x * radians_per_pixel
	_orbit_pitch = clampf(
		_orbit_pitch - relative.y * radians_per_pixel * vertical_sign,
		PITCH_MIN,
		PITCH_MAX,
	)


func _set_hud_label(target_name: String) -> void:
	if is_instance_valid(_hud) and _hud.has_method("update_spectate_target"):
		_hud.update_spectate_target(target_name)
