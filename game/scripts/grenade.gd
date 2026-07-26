class_name HEGrenade
extends RigidBody3D

const FUSE_SECONDS := 1.7
const BLAST_RADIUS := 5.8
const MAX_DAMAGE := 95.0
const BOUNCE_SOUND := preload("res://assets/sounds/he_bounce-1.wav")
const EXPLOSION_SOUND := preload("res://assets/sounds/explode3.wav")

var _exploded := false
var _bounce_audio: AudioStreamPlayer3D


func _ready() -> void:
	name = "HEGrenade"
	collision_layer = 8
	collision_mask = 1 | 2
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 3

	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.09
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


func launch(origin: Vector3, impulse: Vector3) -> void:
	global_position = origin
	linear_velocity = impulse
	angular_velocity = Vector3(8.0, 12.0, 5.0)


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	freeze = true
	visible = false
	for actor in get_tree().get_nodes_in_group("damageable"):
		if not actor is Node3D or not actor.has_method("apply_damage"):
			continue
		var distance: float = global_position.distance_to(actor.global_position)
		if distance >= BLAST_RADIUS:
			continue
		var exposure := 1.0 - distance / BLAST_RADIUS
		actor.call("apply_damage", MAX_DAMAGE * exposure * exposure, global_position, false)
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
