extends SceneTree

const ASSAULT_MAP := "res://generated/cs_assault/map.json"
const DUST2_MAP := "res://generated/de_dust2/map.json"
const EPSILON := 0.0001

var failures: Array[String] = []
var assault_map_path := ASSAULT_MAP
var dust2_map_path := DUST2_MAP


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--assault-map="):
			assault_map_path = argument.trim_prefix("--assault-map=")
		elif argument.begins_with("--dust2-map="):
			dust2_map_path = argument.trim_prefix("--dust2-map=")
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("DYNAMIC BSP TEST: " + message)


func _check_vector(actual: Vector3, expected: Vector3, message: String) -> void:
	_check(
		actual.distance_to(expected) <= EPSILON,
		"%s (actual=%s expected=%s)" % [message, actual, expected],
	)


func _first_mesh(root_node: Node3D) -> MeshInstance3D:
	for child in root_node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null


func _first_exported_vertex(map_path: String, model_index: int) -> Vector3:
	var file := FileAccess.open(map_path, FileAccess.READ)
	if file == null:
		return Vector3(INF, INF, INF)
	var data := JSON.parse_string(file.get_as_text()) as Dictionary
	var positions := data.get("positions", []) as Array
	for raw_group in data.get("groups", []):
		var group := raw_group as Dictionary
		if int(group.get("model_index", -1)) != model_index:
			continue
		var offset := int(group.get("vert_start", 0)) * 3
		return Vector3(
			float(positions[offset]),
			float(positions[offset + 1]),
			float(positions[offset + 2]),
		)
	return Vector3(INF, INF, INF)


func _shape_faces(body: CollisionObject3D) -> PackedVector3Array:
	if body == null or body.get_child_count() == 0:
		return PackedVector3Array()
	var collision := body.get_child(0) as CollisionShape3D
	if collision == null or not collision.shape is ConcavePolygonShape3D:
		return PackedVector3Array()
	return (collision.shape as ConcavePolygonShape3D).get_faces()


func _load_map(path: String, node_name: String) -> BspMap:
	var map := BspMap.new()
	map.name = node_name
	root.add_child(map)
	_check(map.load_map(path), "%s loads" % node_name)
	return map


func _check_dust2() -> void:
	var map := _load_map(dust2_map_path, "Dust2DynamicBspTest")
	_check(map.runtime_model_indices().size() == 42, "Dust2 creates one root per nonzero BSP model")
	_check(map.world_collision_face_count == 9476, "Dust2 model 0 owns exactly its 9476 collision faces")
	_check(map.submodel_collision_face_count == 120, "Dust2 solid brush proxies own 120 separate faces")
	_check(map.collision_face_count == 9596, "Dust2 compatibility collision total includes both partitions")
	_check(
		_shape_faces(map.model_collision_body(0)).size() / 3 == 9476,
		"Dust2 WorldCollision contains no nonzero-model faces",
	)
	_check(map.model_collision_body(1) is AnimatableBody3D, "Dust2 breakable model 1 has an independent collision body")
	_check(map.model_collision_body(4) == null, "Dust2 illusionary model 4 remains non-solid")
	_check(map.model_root(4) != null, "Dust2 non-solid model 4 still has an independent visual root")
	_check(not map.set_model_runtime_position(0, Vector3.ONE), "immutable Dust2 world model rejects runtime movement")
	map.queue_free()
	await process_frame


func _check_assault() -> void:
	var map := _load_map(assault_map_path, "AssaultDynamicBspTest")
	_check(map.runtime_model_indices().size() == 92, "Assault creates one root per nonzero BSP model")
	_check(map.world_collision_face_count == 5547, "Assault model 0 owns exactly its 5547 collision faces")
	_check(map.submodel_collision_face_count == 1168, "Assault solid brush proxies remain outside WorldCollision")
	_check(map.model_index_for_entity(11) == 11, "Assault stable entity 11 maps to BSP model 11")
	_check(map.entity_index_for_model(11) == 11, "Assault BSP model 11 maps back to stable entity 11")
	_check(map.model_classname(11) == "func_door_rotating", "Assault model 11 preserves its brush classname")

	var door_root := map.model_root_for_entity(11)
	_check(door_root != null, "Assault rotating door has a queryable runtime root")
	if door_root != null:
		_check_vector(door_root.position, Vector3(6.96, 0.48, -22.36), "rotating door uses its GoldSrc origin as pivot")
		var mesh := _first_mesh(door_root)
		_check(mesh != null, "rotating door visual is parented under its model root")
		var body := map.model_collision_body(11)
		_check(body is AnimatableBody3D, "rotating door collision is independently movable")
		_check(body != null and body.get_parent() == door_root, "rotating door visual and collision share one transform root")
		if mesh != null and body != null:
			var mesh_vertices := mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var expected_vertex := _first_exported_vertex(assault_map_path, 11)
			_check_vector(mesh_vertices[0], expected_vertex, "rotating door preserves its exported model-local vertices")
			_check_vector(_shape_faces(body)[0], expected_vertex, "rotating door collision preserves the same local vertices")
			var moved := Transform3D(
				Basis(Vector3.UP, deg_to_rad(37.0)),
				Vector3(7.5, 0.48, -22.1),
			)
			_check(map.set_model_runtime_transform(11, moved), "rotating door accepts a runtime transform")
			_check(door_root.transform.is_equal_approx(moved), "runtime transform reaches the shared model root")
			_check(body.transform.is_equal_approx(Transform3D.IDENTITY), "collision stays locally aligned below the moving root")
			_check(mesh.transform.is_equal_approx(Transform3D.IDENTITY), "visual stays locally aligned below the moving root")
			_check(map.reset_model_runtime_transform(11), "rotating door can reset to its imported transform")
			_check_vector(door_root.position, Vector3(6.96, 0.48, -22.36), "reset restores the imported pivot")

	_check(map.model_collision_body(42) is AnimatableBody3D, "Assault button model 42 has a solid proxy")
	_check(map.model_collision_body(71) is AnimatableBody3D, "Assault sliding door model 71 has a solid proxy")
	map.queue_free()
	await process_frame


func _run() -> void:
	await _check_dust2()
	await _check_assault()
	if failures.is_empty():
		print("DYNAMIC_BSP_FOUNDATION_TEST_PASS")
		quit(0)
	else:
		print("DYNAMIC_BSP_FOUNDATION_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)
