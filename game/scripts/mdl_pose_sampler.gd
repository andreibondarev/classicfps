extends RefCounted

## Native vector arithmetic over small frame slices. No retained frame cache:
## temporary storage is bounded by this surface, not by animation duration.
## Byte conversion follows the engine's real_t width; double-precision builds
## use scalar construction instead of interpreting float32 bytes as float64.
static var _vector3_byte_stride := PackedVector3Array([Vector3.ZERO]).to_byte_array().size()


static func source_bounds(positions: PackedFloat32Array, vertex_count: int) -> Array[AABB]:
	var result: Array[AABB] = []
	if vertex_count <= 0:
		return result
	var stride := vertex_count * 3
	for offset in range(0, positions.size(), stride):
		var points := _read(positions, offset, vertex_count)
		var bounds := AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points:
			bounds = bounds.expand(point)
		result.append(bounds)
	return result


static func interpolated_bounds(bounds: Array[AABB], a: int, b: int, c: int, d: int,
		frame_alpha: float, blend_alpha: float) -> AABB:
	# For each axis, a weighted minimum is <= every weighted vertex and a
	# weighted maximum is >= it. This encloses the same two-stage convex blend
	# without scanning its vertices. These are culling bounds, never grounding.
	var low := bounds[a].position.lerp(bounds[b].position, blend_alpha).lerp(
		bounds[c].position.lerp(bounds[d].position, blend_alpha), frame_alpha)
	var high := bounds[a].end.lerp(bounds[b].end, blend_alpha).lerp(
		bounds[c].end.lerp(bounds[d].end, blend_alpha), frame_alpha)
	# Include floating-point rounding at the extrema and AABB's exclusive end.
	return AABB(low, high - low).grow(0.00001)


static func sample(positions: PackedFloat32Array, start: int, count: int,
		current_low: int, current_high: int, next_low: int, next_high: int,
		frame_alpha: float, blend_alpha: float, lower_overlay: Dictionary = {}) -> PackedVector3Array:
	if not lower_overlay.is_empty():
		return _sample_composited(positions, start, count, current_low, current_high,
			next_low, next_high, frame_alpha, blend_alpha, lower_overlay)
	var offset := start * 3
	var vertices := _read(positions, current_low + offset, count)
	var single_pitch := blend_alpha == 0.0 or (current_low == current_high and next_low == next_high)
	var single_frame := frame_alpha == 0.0 or (current_low == next_low and current_high == next_high)
	if single_pitch:
		if not single_frame:
			var next := _read(positions, next_low + offset, count)
			for index in count:
				vertices[index] = vertices[index].lerp(next[index], frame_alpha)
	else:
		var high := _read(positions, current_high + offset, count)
		if single_frame:
			for index in count:
				vertices[index] = vertices[index].lerp(high[index], blend_alpha)
		else:
			var next_l := _read(positions, next_low + offset, count)
			var next_h := _read(positions, next_high + offset, count)
			for index in count:
				vertices[index] = vertices[index].lerp(high[index], blend_alpha).lerp(
					next_l[index].lerp(next_h[index], blend_alpha), frame_alpha)
	return vertices


static func _sample_composited(positions: PackedFloat32Array, start: int, count: int,
		current_low: int, current_high: int, next_low: int, next_high: int,
		frame_alpha: float, blend_alpha: float, overlay: Dictionary) -> PackedVector3Array:
	# Select the source layer before doing interpolation. Building both complete
	# poses and then replacing the legs computes and discards a whole surface's
	# worth of vertex blends every render. Source clocks and masks are unchanged.
	var offset := start * 3
	var vertices := _read(positions, current_low + offset, count)
	var single_pitch := blend_alpha == 0.0 or (current_low == current_high and next_low == next_high)
	var single_frame := frame_alpha == 0.0 or (current_low == next_low and current_high == next_high)
	var high := PackedVector3Array() if single_pitch else _read(positions, current_high + offset, count)
	var next_l := PackedVector3Array() if single_frame else _read(positions, next_low + offset, count)
	var next_h := PackedVector3Array() if single_frame or single_pitch else _read(positions, next_high + offset, count)
	var mask: PackedByteArray = overlay.mask
	var overlay_alpha := float(overlay.frame_alpha)
	var overlay_still := overlay_alpha == 0.0 or int(overlay.current_offset) == int(overlay.next_offset)
	var lower := _read(overlay.positions, int(overlay.current_offset) + offset, count)
	var next_lower := PackedVector3Array() if overlay_still else _read(overlay.positions, int(overlay.next_offset) + offset, count)
	for index in count:
		if mask[start + index] != 0:
			vertices[index] = lower[index] if overlay_still else lower[index].lerp(next_lower[index], overlay_alpha)
		elif single_pitch:
			if not single_frame:
				vertices[index] = vertices[index].lerp(next_l[index], frame_alpha)
		elif single_frame:
			vertices[index] = vertices[index].lerp(high[index], blend_alpha)
		else:
			vertices[index] = vertices[index].lerp(high[index], blend_alpha).lerp(
				next_l[index].lerp(next_h[index], blend_alpha), frame_alpha)
	return vertices


static func _read(positions: PackedFloat32Array, offset: int, count: int) -> PackedVector3Array:
	if _vector3_byte_stride == 12:
		return positions.slice(offset, offset + count * 3).to_byte_array().to_vector3_array()
	var vertices := PackedVector3Array()
	vertices.resize(count)
	for index in count:
		var source := offset + index * 3
		vertices[index] = Vector3(positions[source], positions[source + 1], positions[source + 2])
	return vertices
