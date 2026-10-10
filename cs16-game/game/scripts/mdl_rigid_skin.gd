extends RefCounted

## Rebuilds baked vertex frames from rigid bone tapes. GoldSrc skinning is
## rigid: every vertex follows exactly one bone, so each pose is stored as one
## transform per bone and the exporter verifies that rebuilding reproduces its
## baked frames. Frames are rebuilt once per template load; the runtime samples
## them unchanged.
##   version 4, "rigid_bones":     float32 row-major 3x4 matrices (*.bones.f32)
##   version 5, "rigid_bones_q16": int16 [qx qy qz qw tx ty tz] per pose and
##     bone (*.bones.q16); about a third of the download, within 0.6 mm of the
##     baked frames (the exporter checks).

const FRAME_FORMAT := "rigid_bones"
const FRAME_FORMAT_Q16 := "rigid_bones_q16"
const Q16_CHANNELS := 7

## Byte width of Vector3 in this build (12 with single-precision real_t).
static var _vector3_byte_stride := PackedVector3Array([Vector3.ZERO]).to_byte_array().size()


## Returns {} for manifests that still carry baked vertex frames.
static func load_skin(model_path: String, parsed: Dictionary, vertex_count: int) -> Dictionary:
	if str(parsed.get("frame_format", "")) not in [FRAME_FORMAT, FRAME_FORMAT_Q16]:
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
	var owners := PackedInt32Array()
	owners.resize(vertex_count)
	bone_vertices.resize(bone_count + 1)
	bone_indices.resize(bone_count + 1)
	for bone in bone_count + 1:
		bone_vertices[bone] = PackedVector3Array()
		bone_indices[bone] = PackedInt32Array()
	for vertex in vertex_count:
		var bone := int(vertex_bones[vertex])
		if bone < 0 or bone >= bone_count:
			bone = bone_count
		owners[vertex] = bone
		bone_vertices[bone].append(Vector3(local[vertex * 3], local[vertex * 3 + 1], local[vertex * 3 + 2]))
		bone_indices[bone].append(vertex)
	# Each bone's local box: transformed with the bone, it encloses the bone's
	# vertices in every pose, so culling bounds cost one AABB per bone.
	var bone_bounds: Array[AABB] = []
	for bone in bone_count + 1:
		var points := bone_vertices[bone]
		var box := AABB(points[0], Vector3.ZERO) if not points.is_empty() else AABB()
		for point in points:
			box = box.expand(point)
		bone_bounds.append(box)
	var skinned_bones := PackedInt32Array()
	for bone in bone_count:
		if not bone_indices[bone].is_empty():
			skinned_bones.append(bone)
	return {
		"bone_bounds": bone_bounds,
		"quantized": str(parsed.frame_format) == FRAME_FORMAT_Q16,
		"translation_scale": float(parsed.get("tape_translation_scale", 16384.0)),
		"bone_count": bone_count,
		"vertex_count": vertex_count,
		"bone_vertices": bone_vertices,
		"bone_indices": bone_indices,
		# GPU skinning: bone-local positions, owning bone per vertex (bone_count
		# for unskinned vertices, which keep an identity transform) and the
		# bones that move any vertex.
		"local": local,
		"vertex_owner": owners,
		"skinned_bones": skinned_bones,
	}


## Tape size check for one animation of `pose_count` poses.
static func tape_matches(skin: Dictionary, tape: PackedByteArray, pose_count: int) -> bool:
	var per_pose := int(skin.bone_count) * (Q16_CHANNELS * 2 if bool(skin.quantized) else 48)
	return pose_count > 0 and tape.size() == pose_count * per_pose


## One pose's bone transforms (identity for bones without vertices), decoded
## exactly as rebuild()/rebuild_q16() decode them.
static func decode_pose(skin: Dictionary, tape: PackedByteArray, pose: int) -> Array[Transform3D]:
	var bone_count: int = skin.bone_count
	var transforms: Array[Transform3D] = []
	transforms.resize(bone_count + 1)
	var skinned: PackedInt32Array = skin.skinned_bones
	if bool(skin.quantized):
		var scale := 1.0 / float(skin.translation_scale)
		var pose_offset := pose * bone_count * Q16_CHANNELS * 2
		for bone in skinned:
			var read := pose_offset + bone * Q16_CHANNELS * 2
			var rotation := Quaternion(tape.decode_s16(read), tape.decode_s16(read + 2),
				tape.decode_s16(read + 4), tape.decode_s16(read + 6)).normalized()
			var origin := Vector3(tape.decode_s16(read + 8), tape.decode_s16(read + 10),
				tape.decode_s16(read + 12)) * scale
			transforms[bone] = Transform3D(Basis(rotation), origin)
		return transforms
	for bone in skinned:
		var o := (pose * bone_count + bone) * 48
		var m := tape.slice(o, o + 48).to_float32_array()
		transforms[bone] = Transform3D(
			Basis(Vector3(m[0], m[4], m[8]), Vector3(m[1], m[5], m[9]), Vector3(m[2], m[6], m[10])),
			Vector3(m[3], m[7], m[11]),
		)
	return transforms


## Expands `pose_count` poses of bone transforms into the baked frame layout:
## pose-major, vertex-major xyz floats.
## `bounds_out` receives one culling box per pose: it encloses every vertex
## but may be slightly larger than the exact vertex bounds.
static func rebuild(skin: Dictionary, tape: PackedFloat32Array, pose_count: int,
		bounds_out: Array[AABB] = []) -> PackedFloat32Array:
	var bone_count: int = skin.bone_count
	if pose_count <= 0 or tape.size() != pose_count * bone_count * 12:
		return PackedFloat32Array()
	var bone_vertices: Array[PackedVector3Array] = skin.bone_vertices
	var bone_indices: Array[PackedInt32Array] = skin.bone_indices
	var bone_bounds: Array[AABB] = skin.bone_bounds
	var unskinned_bounds := _unskinned_bounds(skin)
	var frame := _first_frame(skin)
	var result := PackedFloat32Array()
	for pose in pose_count:
		var pose_box := unskinned_bounds
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
			pose_box = _merge(pose_box, transform * bone_bounds[bone])
			var moved: PackedVector3Array = transform * bone_vertices[bone]
			for index in indices.size():
				frame[indices[index]] = moved[index]
		bounds_out.append(pose_box)
		result.append_array(_frame_floats(frame))
	return result


## rebuild() for q16 tapes, decoding each transform where it is used rather
## than through an intermediate float tape; bones without vertices are skipped.
static func rebuild_q16(skin: Dictionary, bytes: PackedByteArray, pose_count: int,
		bounds_out: Array[AABB] = []) -> PackedFloat32Array:
	var bone_count: int = skin.bone_count
	var stride := bone_count * Q16_CHANNELS
	if pose_count <= 0 or bytes.size() != pose_count * stride * 2:
		return PackedFloat32Array()
	var scale := 1.0 / float(skin.translation_scale)
	var bone_vertices: Array[PackedVector3Array] = skin.bone_vertices
	var bone_indices: Array[PackedInt32Array] = skin.bone_indices
	var bone_bounds: Array[AABB] = skin.bone_bounds
	var unskinned_bounds := _unskinned_bounds(skin)
	var frame := _first_frame(skin)
	var result := PackedFloat32Array()
	for pose in pose_count:
		var pose_box := unskinned_bounds
		var pose_offset := pose * stride * 2
		for bone in bone_count:
			var indices := bone_indices[bone]
			if indices.is_empty():
				continue
			var read := pose_offset + bone * Q16_CHANNELS * 2
			var rotation := Quaternion(bytes.decode_s16(read), bytes.decode_s16(read + 2),
				bytes.decode_s16(read + 4), bytes.decode_s16(read + 6)).normalized()
			var origin := Vector3(bytes.decode_s16(read + 8), bytes.decode_s16(read + 10),
				bytes.decode_s16(read + 12)) * scale
			var transform := Transform3D(Basis(rotation), origin)
			pose_box = _merge(pose_box, transform * bone_bounds[bone])
			var moved: PackedVector3Array = transform * bone_vertices[bone]
			for index in indices.size():
				frame[indices[index]] = moved[index]
		bounds_out.append(pose_box)
		result.append_array(_frame_floats(frame))
	return result


## Unskinned vertices never move; an empty AABB() when there are none.
static func _unskinned_bounds(skin: Dictionary) -> AABB:
	var points: PackedVector3Array = skin.bone_vertices[int(skin.bone_count)]
	return skin.bone_bounds[int(skin.bone_count)] if not points.is_empty() else AABB(Vector3.INF, Vector3.ZERO)


## Merge that treats AABB(Vector3.INF, ...) as "nothing yet".
static func _merge(box: AABB, other: AABB) -> AABB:
	return other if box.position == Vector3.INF else box.merge(other)


static func _first_frame(skin: Dictionary) -> PackedVector3Array:
	var bone_count: int = skin.bone_count
	var frame := PackedVector3Array()
	frame.resize(skin.vertex_count)
	var unskinned: PackedInt32Array = skin.bone_indices[bone_count]
	for index in unskinned.size():
		frame[unskinned[index]] = skin.bone_vertices[bone_count][index]
	return frame


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
