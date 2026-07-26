class_name BspMap
extends Node3D

const SPAWN_FLOOR_EPSILON := 0.001

var entities: Array = []
var bounds_min := Vector3.ZERO
var bounds_max := Vector3.ZERO
var source_path := ""
var surface_count := 0
var collision_face_count := 0
var navigation_region: NavigationRegion3D
var collision_face_textures: Array[String] = []
var _collision_faces := PackedVector3Array()
var _model_bounds := {}


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
	collision_face_textures.clear()
	_model_bounds.clear()
	for raw_bounds in data.get("model_bounds", []):
		var model_bounds := raw_bounds as Dictionary
		var minimum := _vec3_from_dictionary(model_bounds.get("mins", {}))
		var maximum := _vec3_from_dictionary(model_bounds.get("maxs", {}))
		_model_bounds[int(model_bounds.get("model_index", -1))] = AABB(
			minimum,
			maximum - minimum,
		)
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
		var model_index := int(group.get("model_index", -1))
		if not vertices.is_empty():
			var group_bounds := AABB(vertices[0], Vector3.ZERO)
			for vertex: Vector3 in vertices:
				group_bounds = group_bounds.expand(vertex)
			if _model_bounds.has(model_index):
				var existing_bounds: AABB = _model_bounds[model_index]
				_model_bounds[model_index] = existing_bounds.merge(group_bounds)
			else:
				_model_bounds[model_index] = group_bounds
		if solid_models.has(int(group.get("model_index", -1))):
			var texture_name := str(group.get("name", ""))
			for ignored_face in range(int(count / 3)):
				collision_face_textures.append(texture_name)

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
		_collision_faces = collision_faces
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


func texture_name_for_face(face_index: int) -> String:
	if face_index < 0 or face_index >= collision_face_textures.size():
		return ""
	return collision_face_textures[face_index]


func brush_entity_regions(classname: String) -> Array[Dictionary]:
	## Resolves brush entities such as func_bomb_target and func_buyzone to the
	## exact AABBs of their imported BSP submodels.
	var regions: Array[Dictionary] = []
	for raw_entity in entities:
		var entity := raw_entity as Dictionary
		if str(entity.get("classname", "")) != classname:
			continue
		var properties := _entity_properties(entity)
		var model_name := str(properties.get("model", ""))
		if not model_name.begins_with("*"):
			continue
		var model_index := int(model_name.trim_prefix("*"))
		if not _model_bounds.has(model_index):
			continue
		regions.append({
			"classname": classname,
			"model_index": model_index,
			"bounds": _model_bounds[model_index],
			"team": int(properties.get("team", 0)),
			"target": str(properties.get("target", "")),
			# Source trigger contracts consumed by Game. The exported BSP model
			# bounds stay byte-for-byte derived from the map submodel; these
			# tags prevent callers from regressing to a center-point test.
			"touch_mode": "player_hull",
			"horizontal_hull_containment": classname == "func_bomb_target",
		})
	return regions


func _entity_properties(entity: Dictionary) -> Dictionary:
	var result := {}
	for raw_pair in entity.get("properties", []):
		if raw_pair is Array and raw_pair.size() >= 2:
			result[str(raw_pair[0])] = str(raw_pair[1])
	return result


func _build_navigation_region() -> void:
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "Navigation"
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_collision_mask = 1
	navigation_mesh.cell_size = 0.04
	navigation_mesh.cell_height = 0.02
	# Derive the CS hull dimensions from the raster itself so Recast receives
	# exact voxel multiples instead of ceiling a decimal approximation.
	navigation_mesh.agent_height = navigation_mesh.cell_height * 36.0
	navigation_mesh.agent_radius = navigation_mesh.cell_size * 4.0
	navigation_mesh.agent_max_climb = navigation_mesh.cell_height * 9.0
	navigation_mesh.agent_max_slope = 48.0
	navigation_mesh.edge_max_length = 8.0
	navigation_mesh.detail_sample_distance = 2.51
	navigation_mesh.detail_sample_max_error = 0.8
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)


func _material_for_group(group: Dictionary, map_root: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# GoldSrc BSP lighting is already baked into the exported vertex colors.
	# Lighting these surfaces a second time with Godot's sun/ambient pass causes
	# the blown-out, flat look visible in early captures. Render the baked light
	# directly and use filtered mipmaps to remove crawl at oblique angles.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
		# GoldSrc point entities describe a centered player origin and are dropped
		# to the BSP floor when spawned. Our CharacterBody origin is at its feet,
		# so resolve the same floor against the imported source triangles instead
		# of treating the entity origin as feet (which spawned actors 48-72 HU
		# above Dust2).
		var centered_origin := Vector3(
			origin.x * 0.01,
			origin.z * 0.01,
			-origin.y * 0.01,
		)
		var floor_y := _floor_below(centered_origin)
		if not is_nan(floor_y):
			centered_origin.y = floor_y + SPAWN_FLOOR_EPSILON
		points.append(centered_origin)
	return points


func _floor_below(point: Vector3) -> float:
	var highest_floor := -INF
	for face_offset in range(0, _collision_faces.size(), 3):
		var a := _collision_faces[face_offset]
		var b := _collision_faces[face_offset + 1]
		var c := _collision_faces[face_offset + 2]
		var normal := (b - a).cross(c - a)
		if absf(normal.y) <= 0.000001:
			continue
		var denominator := (
			(b.z - c.z) * (a.x - c.x)
			+ (c.x - b.x) * (a.z - c.z)
		)
		if absf(denominator) <= 0.000001:
			continue
		var alpha := (
			(b.z - c.z) * (point.x - c.x)
			+ (c.x - b.x) * (point.z - c.z)
		) / denominator
		var beta := (
			(c.z - a.z) * (point.x - c.x)
			+ (a.x - c.x) * (point.z - c.z)
		) / denominator
		var gamma := 1.0 - alpha - beta
		if alpha < -0.00001 or beta < -0.00001 or gamma < -0.00001:
			continue
		var plane_y := alpha * a.y + beta * b.y + gamma * c.y
		if plane_y <= point.y + 0.00001:
			highest_floor = maxf(highest_floor, plane_y)
	return highest_floor if highest_floor > -INF else NAN


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
