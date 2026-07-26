class_name TargetActor
extends CharacterBody3D

signal died(actor: TargetActor, headshot: bool)
signal damaged(actor: TargetActor, health: int, headshot: bool)
signal fired

var player: PlayerController
var active := false
var health := 100
var alive := true
var index := 0
var combat_state := "idle"
var navigation_agent: NavigationAgent3D

var _anchor := Vector3.ZERO
var _phase := 0.0
var _next_shot := 0.0
var _next_path_refresh := 0.0
var _last_seen_position := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _body_material: StandardMaterial3D
var _body_mesh: MeshInstance3D
var _muzzle: OmniLight3D


func _ready() -> void:
	add_to_group("targets")
	add_to_group("damageable")
	collision_layer = 2
	collision_mask = 1
	_anchor = global_position
	_phase = float(index) * 1.13
	_rng.seed = 9701 + index * 181
	_next_shot = _rng.randf_range(0.8, 1.8)
	_build_actor()
	_build_navigation_agent()


func _build_navigation_agent() -> void:
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "NavigationAgent"
	navigation_agent.radius = 0.34
	navigation_agent.height = 1.78
	navigation_agent.path_desired_distance = 0.35
	navigation_agent.target_desired_distance = 5.5
	navigation_agent.max_speed = 3.4
	navigation_agent.avoidance_enabled = false
	add_child(navigation_agent)


func _build_actor() -> void:
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.34
	shape.height = 1.78
	shape_node.shape = shape
	shape_node.position.y = 0.89
	add_child(shape_node)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#416f9d")
	_body_material.roughness = 0.64
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	var body := CapsuleMesh.new()
	body.radius = 0.34
	body.height = 1.78
	body.material = _body_material
	_body_mesh.mesh = body
	_body_mesh.position.y = 0.89
	add_child(_body_mesh)

	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color("#151c24")
	visor_material.metallic = 0.65
	visor_material.roughness = 0.25
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.42, 0.16, 0.08)
	visor_mesh.material = visor_material
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 1.53, -0.29)
	add_child(visor)

	_muzzle = OmniLight3D.new()
	_muzzle.position = Vector3(0.24, 1.15, -0.55)
	_muzzle.light_color = Color("#ff685d")
	_muzzle.light_energy = 2.2
	_muzzle.omni_range = 3.0
	_muzzle.visible = false
	add_child(_muzzle)


func _physics_process(delta: float) -> void:
	if not active or not alive or not is_instance_valid(player) or player.is_dead():
		velocity = Vector3.ZERO
		combat_state = "idle"
		return
	_phase += delta * (0.72 + index * 0.035)
	var distance := global_position.distance_to(player.global_position)
	var sees_player := _has_line_of_sight()
	if sees_player:
		_last_seen_position = player.global_position

	if sees_player and distance <= 22.0:
		combat_state = "engage"
		_strafe_in_combat()
	else:
		combat_state = "hunt"
		_follow_navigation(delta)

	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	var look_target := player.global_position if sees_player else global_position + Vector3(velocity.x, 0, velocity.z)
	look_target.y = global_position.y
	if global_position.distance_squared_to(look_target) > 0.01:
		look_at(look_target, Vector3.UP)

	_next_shot -= delta
	if sees_player and _next_shot <= 0.0:
		_next_shot = _rng.randf_range(0.72, 1.18)
		_try_fire()


func _strafe_in_combat() -> void:
	var to_player := player.global_position - global_position
	to_player.y = 0
	var tangent := Vector3(-to_player.z, 0, to_player.x).normalized()
	var direction_sign := -1.0 if index % 2 == 0 else 1.0
	var desired_velocity := tangent * direction_sign * cos(_phase) * 1.9
	if to_player.length() > 16.0:
		desired_velocity += to_player.normalized() * 1.4
	elif to_player.length() < 8.0:
		desired_velocity -= to_player.normalized() * 1.4
	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z


func _follow_navigation(delta: float) -> void:
	_next_path_refresh -= delta
	if _next_path_refresh <= 0.0:
		_next_path_refresh = 0.28 + float(index) * 0.015
		navigation_agent.target_position = player.global_position
	if navigation_agent.is_navigation_finished():
		_fallback_strafe()
		return
	var next_position := navigation_agent.get_next_path_position()
	var planar := next_position - global_position
	planar.y = 0
	if planar.length_squared() <= 0.0025:
		_fallback_strafe()
		return
	var direction := planar.normalized()
	velocity.x = direction.x * navigation_agent.max_speed
	velocity.z = direction.z * navigation_agent.max_speed


func _fallback_strafe() -> void:
	var strafe_axis := Vector3.RIGHT if index % 2 == 0 else Vector3.FORWARD
	var desired := _anchor + strafe_axis * sin(_phase) * (1.2 + (index % 3) * 0.35)
	var planar := desired - global_position
	planar.y = 0
	var fallback: Vector3 = (
		planar.normalized() * min(1.9, planar.length() * 2.2)
		if planar.length() > 0.03
		else Vector3.ZERO
	)
	velocity.x = fallback.x
	velocity.z = fallback.z


func _has_line_of_sight() -> bool:
	if not is_instance_valid(player):
		return false
	var origin := global_position + Vector3(0, 1.45, 0)
	var target := player.camera.global_position
	if origin.distance_squared_to(target) > 48.0 * 48.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


func _try_fire() -> void:
	if not is_instance_valid(player):
		return
	var origin := global_position + Vector3(0, 1.25, 0)
	var target := player.camera.global_position
	var distance := origin.distance_to(target)
	if distance > 38.0:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != player:
		return
	_muzzle.visible = true
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		if is_instance_valid(_muzzle):
			_muzzle.visible = false
	)
	player.spawn_incoming_tracer(origin, target)
	player.apply_damage(_rng.randf_range(6.0, 10.0))
	fired.emit()


func apply_damage(amount: float, _hit_position: Vector3, headshot: bool) -> void:
	if not alive:
		return
	health = max(0, health - int(round(amount)))
	_flash_hit(headshot)
	damaged.emit(self, health, headshot)
	if health <= 0:
		alive = false
		active = false
		collision_layer = 0
		velocity = Vector3.ZERO
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "rotation:z", deg_to_rad(82.0), 0.24)
		tween.tween_property(self, "position:y", global_position.y - 0.32, 0.24)
		died.emit(self, headshot)


func _flash_hit(headshot: bool) -> void:
	var normal_color := Color("#416f9d")
	_body_material.albedo_color = Color.WHITE if headshot else Color("#ffb087")
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if is_instance_valid(_body_material):
			_body_material.albedo_color = normal_color
	)


func reset_target(spawn_position: Vector3) -> void:
	health = 100
	alive = true
	active = true
	collision_layer = 2
	global_position = spawn_position
	_anchor = spawn_position
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_next_shot = _rng.randf_range(0.8, 1.8)
	_next_path_refresh = 0.0
	combat_state = "idle"
	if is_instance_valid(navigation_agent):
		navigation_agent.target_position = spawn_position
	if is_instance_valid(_body_material):
		_body_material.albedo_color = Color("#d85b3f")


func head_height() -> float:
	return global_position.y + 1.43
