class_name HEGrenade
extends RigidBody3D

const Ballistics := preload("res://scripts/cs16_ballistics.gd")
const FUSE_SECONDS := Ballistics.HE_FUSE_SECONDS
const BLAST_RADIUS := Ballistics.HE_RADIUS_METERS
const MAX_DAMAGE := Ballistics.HE_BASE_DAMAGE
const BOUNCE_SOUND := preload("res://assets/sounds/he_bounce-1.wav")
const EXPLOSION_SOUND := preload("res://assets/sounds/explode3.wav")

var _exploded := false
var _bounce_audio: AudioStreamPlayer3D
var thrower: Combatant
var _ground_slowdown_armed := true


func _ready() -> void:
	name = "HEGrenade"
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp = 0.0
	angular_damp = 0.0
	var world_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	gravity_scale = Ballistics.HE_GRAVITY_METERS_PER_SECOND_SQUARED / world_gravity
	var physics_material := PhysicsMaterial.new()
	# GoldSrc uses pev->friction as inverse elasticity, not as tangential
	# friction. Godot's equivalent bounce is therefore 1 - 0.7.
	physics_material.friction = 0.0
	physics_material.bounce = 1.0 - Ballistics.HE_FRICTION
	physics_material_override = physics_material

	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	# GoldSrc gives grenades a point-sized bbox. One converted unit is the
	# smallest robust Godot approximation.
	shape.radius = Ballistics.METERS_PER_GOLDSRC_UNIT
	collider.shape = shape
	add_child(collider)
	var model := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.085
	mesh.height = 0.17
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#26352d")
	material.metallic = 0.28
	mesh.material = material
	model.mesh = mesh
	add_child(model)
	_bounce_audio = AudioStreamPlayer3D.new()
	_bounce_audio.stream = BOUNCE_SOUND
	_bounce_audio.volume_db = -7.0
	add_child(_bounce_audio)
	body_entered.connect(func(_body: Node) -> void:
		if linear_velocity.length() > 1.5 and not _bounce_audio.playing:
			_bounce_audio.pitch_scale = randf_range(0.92, 1.08)
			_bounce_audio.play()
	)
	get_tree().create_timer(FUSE_SECONDS).timeout.connect(explode)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var grounded := false
	for contact_index in range(state.get_contact_count()):
		if state.get_contact_local_normal(contact_index).y > 0.7:
			grounded = true
			break
	if grounded and _ground_slowdown_armed:
		if Ballistics.he_should_stop_after_ground_bounce(linear_velocity, Vector3.UP):
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
		else:
			linear_velocity *= Ballistics.HE_GROUND_VELOCITY_RETENTION
		_ground_slowdown_armed = false
	elif not grounded:
		_ground_slowdown_armed = true


func launch(
	origin: Vector3,
	impulse: Vector3,
	thrower_combatant: Combatant = null,
) -> void:
	thrower = thrower_combatant
	global_position = origin
	linear_velocity = impulse
	angular_velocity = Vector3.ZERO


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	freeze = true
	visible = false
	var damage_origin := Ballistics.he_damage_origin(global_position)
	for actor in get_tree().get_nodes_in_group("damageable"):
		if not actor is Combatant or not actor.has_method("receive_explosion_damage"):
			continue
		var distance: float = damage_origin.distance_to(actor.global_position)
		if distance >= BLAST_RADIUS:
			continue
		var damage_target: Vector3 = actor.aim_point()
		var query := PhysicsRayQueryParameters3D.create(
			damage_origin,
			damage_target,
			1 | 2 | 4,
			[get_rid()],
		)
		var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
		if not obstruction.is_empty() and obstruction.collider != actor:
			continue
		actor.call(
			"receive_explosion_damage",
			Ballistics.he_radius_damage(distance),
			global_position,
			thrower,
		)
	var flash := OmniLight3D.new()
	flash.light_color = Color("#ff9b3f")
	flash.light_energy = 8.0
	flash.omni_range = BLAST_RADIUS * 1.4
	add_child(flash)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = EXPLOSION_SOUND
	audio.max_distance = 45.0
	add_child(audio)
	audio.play()
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.22)
	await get_tree().create_timer(1.5).timeout
	queue_free()
