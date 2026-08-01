class_name CS16SpectatorCamera
extends Node3D
## CS 1.6 death spectate: after a short delay the dead human player chase-cams
## living teammates (fire/secondary cycles, mouse orbits). Self-contained node;
## game.gd schedules it on player death and ends it on round reset.

signal ended
signal spectate_target_changed(target: Combatant)

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

var camera: Camera3D
var active := false
var pending := false
var target: Combatant = null

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
	if is_instance_valid(camera):
		camera.current = false
	_set_hud_label("")


func cycle(direction: int) -> void:
	if not active:
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
	if not _target_watchable():
		_advance_after_target_loss()
	_update_chase(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_orbit((event as InputEventMouseMotion).relative)
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
	# Start the chase from the death view so the cut reads continuously.
	if is_instance_valid(_player) and is_instance_valid(_player.camera):
		camera.global_transform = _player.camera.global_transform
	camera.current = true
	var mates := _living_teammates()
	if mates.is_empty():
		# No teammates left: hold a static free camera at the death view.
		target = null
		_set_hud_label("")
	else:
		_set_target(mates[0])


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
	var mates := _living_teammates()
	if mates.is_empty():
		# Freeze in place as a static free camera until the round resets.
		target = null
		_set_hud_label("")
		return
	var replacement := mates[0]
	if is_instance_valid(target) and mates.has(target):
		replacement = target
	_set_target(replacement)


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
	_set_hud_label(target.display_name)
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
