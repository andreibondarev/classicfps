class_name CS16Spray
extends Node3D

const TEXTURE_PATH := "res://assets/sprays/rushing_andrei.png"
const MAX_SPRAYS := 32
const RANGE := 1.28
const WIDTH := 0.96
const COOLDOWN_MS := 10000
var records: Array[Dictionary] = []
var _nodes: Dictionary = {}
var _cooldowns: Dictionary = {}
var _next_id := 1
var _material: StandardMaterial3D


static func valid_records(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_SPRAYS:
		return false
	var seen := {}
	for row: Variant in value:
		if not row is Dictionary or row.size() != 3 or not row.has_all(["id", "position", "normal"]):
			return false
		if typeof(row.id) != TYPE_INT or row.id < 1 or row.id > 0x7fffffff or seen.has(row.id):
			return false
		for key in ["position", "normal"]:
			if typeof(row[key]) != TYPE_VECTOR3 or not row[key].is_finite():
				return false
		if maxf(absf(row.position.x), maxf(absf(row.position.y), absf(row.position.z))) > 10000.0 or absf(row.normal.length() - 1.0) > 0.01:
			return false
		seen[row.id] = true
	return true


static func surface_basis(normal: Vector3) -> Basis:
	return Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.94 else Vector3.UP)


func _ready() -> void:
	var texture := load(TEXTURE_PATH) as Texture2D
	_material = StandardMaterial3D.new()
	_material.albedo_texture = texture
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED


func placement(origin: Vector3, direction: Vector3, excluded: Array[RID] = []) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * RANGE, 7, excluded)
	var hit := space.intersect_ray(query)
	if hit.is_empty() or not hit.collider is StaticBody3D or int(hit.collider.get_meta("model_index", 0)) != 0:
		return {}
	var node := hit.collider as Node
	while is_instance_valid(node):
		if node.has_method("texture_name_for_face"):
			var texture: String = node.texture_name_for_face(int(hit.get("face_index", -1)))
			if texture.to_lower().begins_with("sky") or texture.begins_with("!"):
				return {}
			break
		node = node.get_parent()
	var normal: Vector3 = hit.normal
	var basis := surface_basis(normal)
	# Require a flat supported footprint; don't float across corners/doorways.
	for x: float in [-0.5, 0.0, 0.5]:
		for y: float in [-0.5, 0.0, 0.5]:
			var point: Vector3 = hit.position + basis.x * x * WIDTH + basis.y * y * WIDTH / 3.0
			var probe := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + normal * 0.025, point - normal * 0.025, 1))
			if probe.is_empty() or probe.collider != hit.collider or probe.normal.dot(normal) < 0.99 or probe.position.distance_to(point) > 0.008:
				return {}
	return {"position": hit.position, "normal": normal}


func try_place(human: PlayerController, now_ms: int) -> bool:
	if not human.alive or human.team not in ["T", "CT"] or not human.look_enabled or now_ms < int(_cooldowns.get(human.get_instance_id(), 0)):
		return false
	var hit := placement(human.camera.global_position, -human.camera.global_basis.z, [human.get_rid()])
	if hit.is_empty():
		return false
	_cooldowns[human.get_instance_id()] = now_ms + COOLDOWN_MS
	hit.id = _next_id
	_next_id += 1
	var updated := records.duplicate(true)
	updated.append(hit)
	if updated.size() > MAX_SPRAYS:
		updated.pop_front()
	apply_records(updated)
	return true


func apply_records(value: Array) -> void:
	if not valid_records(value):
		return
	var keep := {}
	for row: Dictionary in value:
		keep[row.id] = true
		if not _nodes.has(row.id):
			var instance := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(WIDTH, WIDTH / 3.0)
			mesh.material = _material
			instance.mesh = mesh
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
			_nodes[row.id] = instance
		_nodes[row.id].global_transform = Transform3D(surface_basis(row.normal), row.position + row.normal * 0.006)
	for id: int in _nodes.keys():
		if not keep.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	records.assign(value.duplicate(true))


func clear() -> void:
	apply_records([])
	_cooldowns.clear()
