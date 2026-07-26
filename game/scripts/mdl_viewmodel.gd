class_name MdlViewModel
extends Node3D

var loaded_weapon := ""
var model_root: Node3D
var base_position := Vector3(0.34, -0.21, -0.27)


func _ready() -> void:
	position = base_position


func load_weapon(weapon: String) -> bool:
	if loaded_weapon == weapon:
		return true
	var path := "res://generated/weapons/%s/model.json" % weapon
	if not FileAccess.file_exists(path):
		push_warning("Converted viewmodel is unavailable: %s" % path)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("format", "") != "protocol47-mdl":
		push_error("Invalid viewmodel export: %s" % path)
		return false
	if is_instance_valid(model_root):
		model_root.queue_free()
	model_root = Node3D.new()
	model_root.name = "Authentic_%s" % weapon
	model_root.rotation.y = PI * 0.5
	model_root.scale = Vector3(0.72, 1.0, -1.0)
	add_child(model_root)

	var positions: Array = parsed.get("positions", [])
	var uvs: Array = parsed.get("uvs", [])
	for group_data in parsed.get("groups", []):
		var start := int(group_data.get("vert_start", 0))
		var count := int(group_data.get("vert_count", 0))
		if count <= 0:
			continue
		var vertices := PackedVector3Array()
		var texture_uvs := PackedVector2Array()
		vertices.resize(count)
		texture_uvs.resize(count)
		for local_index in range(count):
			var vertex_index := start + local_index
			vertices[local_index] = Vector3(
				float(positions[vertex_index * 3]),
				float(positions[vertex_index * 3 + 1]),
				float(positions[vertex_index * 3 + 2]),
			)
			texture_uvs[local_index] = Vector2(
				float(uvs[vertex_index * 2]),
				float(uvs[vertex_index * 2 + 1]),
			)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.no_depth_test = true
		material.render_priority = 10
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var texture_name := str(group_data.get("texture", ""))
		if not texture_name.is_empty():
			var texture_path := path.get_base_dir().path_join(texture_name)
			material.albedo_texture = load(texture_path)
		mesh.surface_set_material(0, material)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model_root.add_child(instance)
	loaded_weapon = weapon
	visible = true
	return true


func play_action(kind: String) -> void:
	var tween := create_tween()
	match kind:
		"fire":
			tween.tween_property(self, "position:z", base_position.z + 0.075, 0.035)
			tween.tween_property(self, "position:z", base_position.z, 0.075)
		"reload":
			tween.tween_property(self, "rotation:z", deg_to_rad(24.0), 0.25)
			tween.tween_property(self, "rotation:z", 0.0, 0.42).set_delay(1.15)
		"switch":
			position.y = base_position.y - 0.14
			tween.tween_property(self, "position:y", base_position.y, 0.22)
		"knife":
			tween.tween_property(self, "rotation:y", deg_to_rad(-32.0), 0.07)
			tween.tween_property(self, "rotation:y", 0.0, 0.15)
		"throw":
			tween.tween_property(self, "rotation:x", deg_to_rad(-35.0), 0.12)
			tween.tween_property(self, "rotation:x", 0.0, 0.2)


func set_bob(offset_y: float, sway_x: float) -> void:
	position.y = base_position.y + offset_y
	position.x = base_position.x + sway_x
