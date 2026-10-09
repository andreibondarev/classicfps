extends RefCounted

## Rebuilds baked vertex frames from rigid bone tapes (model.json version 4,
## frame_format "rigid_bones"). GoldSrc skinning is rigid: every vertex follows
## exactly one bone, so each pose is stored as one 3x4 transform per bone and
## the exporter verifies that rebuilding reproduces its baked frames. Frames
## are rebuilt once per template load; the runtime samples them unchanged.

const FRAME_FORMAT := "rigid_bones"

## Byte width of Vector3 in this build (12 with single-precision real_t).
static var _vector3_byte_stride := PackedVector3Array([Vector3.ZERO]).to_byte_array().size()


## Returns {} for manifests that still carry baked vertex frames.
static func load_skin(model_path: String, parsed: Dictionary, vertex_count: int) -> Dictionary:
	if str(parsed.get("frame_format", "")) != FRAME_FORMAT:
		return {}
	var bone_count := int(parsed.get("bone_count", 0))
	var vertex_bones: Array = parsed.get("vertex_bones", [])
	var skin_path := model_path.get_base_dir().path_join(str(parsed.get("skin_file", "")))
	var skin_file := FileAccess.open(skin_path, FileAccess.READ)
	if skin_file == null:
		push_error("Missing rigid skin: %s" % skin_path)
		return {"error": true}
	var local := skin_file.get_buffer(skin_file.get_length()).to_float32_array()
	if bone_count <= 0 or vertex_bones.size() != vertex_count or local.size() != vertex_count * 3:
		push_error("Invalid rigid skin: %s" % skin_path)
		return {"error": true}
	# Group vertices by bone so each pose transforms a bone's vertices in one
	# native Transform3D * PackedVector3Array call. Out-of-range bones keep
	# their local position, matching the exporter.
	var bone_vertices: Array[PackedVector3Array] = []
	var bone_indices: Array[PackedInt32Array] = []
	bone_vertices.resize(bone_count + 1)
	bone_indices.resize(bone_count + 1)
	for bone in bone_count + 1:
		bone_vertices[bone] = PackedVector3Array()
		bone_indices[bone] = PackedInt32Array()
	for vertex in vertex_count:
		var bone := int(vertex_bones[vertex])
		if bone < 0 or bone >= bone_count:
			bone = bone_count
		bone_vertices[bone].append(Vector3(local[vertex * 3], local[vertex * 3 + 1], local[vertex * 3 + 2]))
		bone_indices[bone].append(vertex)
	return {
		"bone_count": bone_count,
		"vertex_count": vertex_count,
		"bone_vertices": bone_vertices,
		"bone_indices": bone_indices,
	}


## Expands `pose_count` poses of bone transforms into the baked frame layout:
## pose-major, vertex-major xyz floats.
static func rebuild(skin: Dictionary, tape: PackedFloat32Array, pose_count: int) -> PackedFloat32Array:
	var bone_count: int = skin.bone_count
	var vertex_count: int = skin.vertex_count
	if pose_count <= 0 or tape.size() != pose_count * bone_count * 12:
		return PackedFloat32Array()
	var bone_vertices: Array[PackedVector3Array] = skin.bone_vertices
	var bone_indices: Array[PackedInt32Array] = skin.bone_indices
	var result := PackedFloat32Array()
	var frame := PackedVector3Array()
	frame.resize(vertex_count)
	var unskinned: PackedInt32Array = bone_indices[bone_count]
	for index in unskinned.size():
		frame[unskinned[index]] = bone_vertices[bone_count][index]
	for pose in pose_count:
		for bone in bone_count:
			var indices := bone_indices[bone]
			if indices.is_empty():
				continue
			var o := (pose * bone_count + bone) * 12
			var transform := Transform3D(
				Basis(
					Vector3(tape[o], tape[o + 4], tape[o + 8]),
					Vector3(tape[o + 1], tape[o + 5], tape[o + 9]),
					Vector3(tape[o + 2], tape[o + 6], tape[o + 10]),
				),
				Vector3(tape[o + 3], tape[o + 7], tape[o + 11]),
			)
			var moved: PackedVector3Array = transform * bone_vertices[bone]
			for index in indices.size():
				frame[indices[index]] = moved[index]
		result.append_array(_frame_floats(frame))
	return result


static func _frame_floats(frame: PackedVector3Array) -> PackedFloat32Array:
	if _vector3_byte_stride == 12:
		return frame.to_byte_array().to_float32_array()
	var floats := PackedFloat32Array()
	floats.resize(frame.size() * 3)
	for index in frame.size():
		var vertex := frame[index]
		floats[index * 3] = vertex.x
		floats[index * 3 + 1] = vertex.y
		floats[index * 3 + 2] = vertex.z
	return floats
