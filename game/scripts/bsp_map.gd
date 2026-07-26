class_name BspMap
extends Node3D

var entities: Array = []
var bounds_min := Vector3.ZERO
var bounds_max := Vector3.ZERO
var source_path := ""
var surface_count := 0
var collision_face_count := 0
var navigation_region: NavigationRegion3D


func load_map(map_path: String) -> bool:
	source_path = map_path
	var file := FileAccess.open(map_path, FileAccess.READ)
	if file == null:
		push_error("Could not open converted map: %s" % map_path)
		return false
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Dictionary:
		push_error("Converted map JSON is invalid: %s" % map_path)
		return false
	var data := decoded as Dictionary
	if data.get("format", "") != "protocol47-bsp" or int(data.get("version", 0)) != 1:
		push_error("Unsupported converted map format: %s" % map_path)
		return false

	var raw_positions := data.get("positions", []) as Array
	var raw_normals := data.get("normals", []) as Array
	var raw_colors := data.get("colors", []) as Array
	var raw_uvs := data.get("uvs", []) as Array
	entities = data.get("entities", []) as Array
	bounds_min = _vec3_from_dictionary(data.get("bounds_min", {}))
	bounds_max = _vec3_from_dictionary(data.get("bounds_max", {}))
	var map_root := map_path.get_base_dir()
	var collision_faces := PackedVector3Array()
	var solid_models := _solid_model_indices()
	_build_navigation_region()

	for raw_group in data.get("groups", []):
		var group := raw_group as Dictionary
		var start := int(group.get("vert_start", 0))
		var count := int(group.get("vert_count", 0))
		if count <= 0:
			continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		vertices.resize(count)
		normals.resize(count)
		colors.resize(count)
		uvs.resize(count)
		for local_index in range(count):
			var vertex_index := start + local_index
			var position_offset := vertex_index * 3
			var uv_offset := vertex_index * 2
			if position_offset + 2 >= raw_positions.size():
				break
			var vertex := Vector3(
				float(raw_positions[position_offset]),
				float(raw_positions[position_offset + 1]),
				float(raw_positions[position_offset + 2]),
			)
			vertices[local_index] = vertex
			if solid_models.has(int(group.get("model_index", -1))):
				collision_faces.append(vertex)
			normals[local_index] = Vector3(
				float(raw_normals[position_offset]),
				float(raw_normals[position_offset + 1]),
				float(raw_normals[position_offset + 2]),
			)
			colors[local_index] = Color(
				float(raw_colors[position_offset]),
				float(raw_colors[position_offset + 1]),
				float(raw_colors[position_offset + 2]),
				1.0,
			)
			uvs[local_index] = Vector2(
				float(raw_uvs[uv_offset]),
				float(raw_uvs[uv_offset + 1]),
			)

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := _material_for_group(group, map_root)
		mesh.surface_set_material(0, material)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = _safe_node_name(str(group.get("name", "surface")))
		mesh_instance.mesh = mesh
		navigation_region.add_child(mesh_instance)
		surface_count += 1

	if not collision_faces.is_empty():
		var body := StaticBody3D.new()
		body.name = "WorldCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(collision_faces)
		collision.shape = shape
		body.add_child(collision)
		navigation_region.add_child(body)
		collision_face_count = collision_faces.size() / 3
	navigation_region.bake_navigation_mesh(false)
	return get_child_count() > 0


func _build_navigation_region() -> void:
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "Navigation"
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_collision_mask = 1
	navigation_mesh.agent_height = 1.75
	navigation_mesh.agent_radius = 0.50
	navigation_mesh.agent_max_climb = 0.50
	navigation_mesh.agent_max_slope = 48.0
	navigation_mesh.cell_size = 0.25
	navigation_mesh.cell_height = 0.25
	navigation_mesh.edge_max_length = 8.0
	navigation_mesh.detail_sample_distance = 2.0
	navigation_mesh.detail_sample_max_error = 0.8
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)


func _material_for_group(group: Dictionary, map_root: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 0.86
	material.albedo_color = _fallback_color(str(group.get("name", "")))
	var raw_texture: Variant = group.get("texture")
	if raw_texture is String and not raw_texture.is_empty():
		var texture_path := raw_texture as String
		var resource_path := map_root.path_join(texture_path)
		if ResourceLoader.exists(resource_path):
			material.albedo_texture = ResourceLoader.load(resource_path) as Texture2D
	if bool(group.get("transparent", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
	if bool(group.get("liquid", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.76
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _solid_model_indices() -> Dictionary:
	var solid := {0: true}
	for raw_entity in entities:
		var entity := raw_entity as Dictionary
		var classname := str(entity.get("classname", ""))
		if classname not in [
			"func_breakable",
			"func_door",
			"func_door_rotating",
			"func_pushable",
			"func_train",
			"func_wall",
		]:
			continue
		for raw_property in entity.get("properties", []):
			var property := raw_property as Array
			if property.size() < 2 or str(property[0]) != "model":
				continue
			var model_name := str(property[1])
			if model_name.begins_with("*") and model_name.substr(1).is_valid_int():
				solid[int(model_name.substr(1))] = true
	return solid


func _fallback_color(texture_name: String) -> Color:
	var normalized := texture_name.to_lower()
	if normalized == "black":
		return Color("#111315")
	if normalized == "white" or normalized.begins_with("generic"):
		return Color("#a6a29a")
	return Color.WHITE


func spawn_points(classname: String) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for raw_entity in entities:
		var entity := raw_entity as Dictionary
		if str(entity.get("classname", "")) != classname:
			continue
		var raw_origin: Variant = entity.get("origin")
		if not raw_origin is Dictionary:
			continue
		var origin := _vec3_from_dictionary(raw_origin)
		points.append(Vector3(origin.x * 0.01, origin.z * 0.01 + 0.08, -origin.y * 0.01))
	return points


func _vec3_from_dictionary(raw: Variant) -> Vector3:
	if not raw is Dictionary:
		return Vector3.ZERO
	var data := raw as Dictionary
	return Vector3(float(data.get("x", 0)), float(data.get("y", 0)), float(data.get("z", 0)))


func _safe_node_name(value: String) -> String:
	var output := ""
	for character in value:
		output += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	return output if not output.is_empty() else "Surface"
