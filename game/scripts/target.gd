class_name TargetActor
extends Combatant

signal died(actor: TargetActor, headshot: bool)
signal damaged(actor: TargetActor, health: int, headshot: bool)
signal fired

var active := false
var index := 0
var combat_state := "idle"
var navigation_agent: NavigationAgent3D

var _anchor := Vector3.ZERO
var _next_shot := 0.0
var _rng := RandomNumberGenerator.new()
var _body_material: StandardMaterial3D
var _body_mesh: MeshInstance3D
var _muzzle: OmniLight3D


func _ready() -> void:
	if team == TEAM_UNASSIGNED:
		configure_identity(TEAM_COUNTER_TERRORIST, "CT Bot %02d" % (index + 1))
	super._ready()
	add_to_group("bots")
	add_to_group("targets")
	collision_layer = 2
	collision_mask = 1
	_anchor = global_position
	_rng.seed = 9701 + index * 181 + (50000 if team == TEAM_TERRORIST else 0)
	_next_shot = _rng.randf_range(0.8, 1.8)
	_build_actor()
	_build_navigation_agent()
	combat_controller = BotCombatController.new()
	combat_controller.name = "BotController"
	add_child(combat_controller)
	(combat_controller as BotCombatController).configure(self, navigation_agent, index)


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
	_body_material.albedo_color = _team_color()
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
	if not active or not alive:
		velocity = Vector3.ZERO
		last_command = {}
		combat_state = "idle"
		return
	var command := combat_controller.gather_command(delta)
	last_command = command
	combat_state = command.state
	var desired_velocity: Vector3 = command.world_velocity
	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()

	var look_target: Vector3 = command.look_target
	if look_target != Vector3.INF:
		look_target.y = global_position.y
		if global_position.distance_squared_to(look_target) > 0.01:
			look_at(look_target, Vector3.UP)

	_next_shot -= delta
	var enemy := command.enemy as Combatant
	if command.fire and is_instance_valid(enemy) and _next_shot <= 0.0:
		_next_shot = _rng.randf_range(0.72, 1.18)
		_try_fire(enemy)


func _try_fire(enemy: Combatant) -> void:
	if not is_instance_valid(enemy) or not enemy.alive:
		return
	var origin := global_position + Vector3(0, 1.25, 0)
	var target := enemy.aim_point()
	if origin.distance_to(target) > 38.0:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, target, 1 | 2 | 4, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != enemy:
		return
	_muzzle.visible = true
	get_tree().create_timer(0.04).timeout.connect(func() -> void:
		if is_instance_valid(_muzzle):
			_muzzle.visible = false
	)
	_spawn_tracer(origin, target)
	enemy.receive_damage(_rng.randf_range(6.0, 10.0), hit.position, false, self)
	fired.emit()


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.38, 0.36, 0.88)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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


func apply_damage(
	amount: float,
	hit_position: Vector3,
	headshot: bool,
	attacker: Combatant = null,
) -> void:
	receive_damage(amount, hit_position, headshot, attacker)


func _on_combatant_damaged(
	_attacker: Combatant,
	_hit_position: Vector3,
	headshot: bool,
) -> void:
	_flash_hit(headshot)
	damaged.emit(self, health, headshot)


func _on_combatant_eliminated(_attacker: Combatant, headshot: bool) -> void:
	active = false
	collision_layer = 0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:z", deg_to_rad(82.0), 0.24)
	tween.tween_property(self, "position:y", global_position.y - 0.32, 0.24)
	died.emit(self, headshot)


func _flash_hit(headshot: bool) -> void:
	var normal_color := _team_color()
	_body_material.albedo_color = Color.WHITE if headshot else Color("#ffb087")
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if is_instance_valid(_body_material):
			_body_material.albedo_color = normal_color
	)


func reset_target(spawn_position: Vector3) -> void:
	reset_combatant(spawn_position)
	active = true
	collision_layer = 2
	_anchor = spawn_position
	rotation = Vector3.ZERO
	_next_shot = _rng.randf_range(0.8, 1.8)
	combat_state = "idle"
	if is_instance_valid(navigation_agent):
		navigation_agent.target_position = spawn_position
	if is_instance_valid(combat_controller):
		(combat_controller as BotCombatController).current_enemy = null
	if is_instance_valid(_body_material):
		_body_material.albedo_color = _team_color()


func _team_color() -> Color:
	return (
		Color("#d85b3f")
		if team == TEAM_TERRORIST
		else Color("#416f9d")
	)
