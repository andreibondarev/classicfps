extends RefCounted

## Experimental test-only broad phase; not enabled in production.
## Conservative broad phase only: false proves the translated axis-aligned
## hull misses every static triangle's bounds. True means "ask physics", not
## "blocked". No triangle collision, ray approximation, or result cache.
const LEAF_SIZE := 8
const CLEARANCE_PADDING := 0.01

class BoundsNode extends RefCounted:
	var bounds := AABB()
	var left := -1
	var right := -1
	var triangles := PackedInt32Array()

var triangle_bounds: Array[AABB] = []
var nodes: Array[BoundsNode] = []
var plane_normals := PackedVector3Array()
var plane_distances := PackedFloat64Array()
var plane_radii := PackedFloat64Array()


func build(faces: PackedVector3Array, hull_half_size: Vector3) -> void:
	triangle_bounds.clear()
	nodes.clear()
	plane_normals.clear()
	plane_distances.clear()
	plane_radii.clear()
	if faces.is_empty() or faces.size() % 3 != 0:
		return
	var expansion := hull_half_size + Vector3.ONE * CLEARANCE_PADDING
	var ids: Array[int] = []
	for offset in range(0, faces.size(), 3):
		var bounds := AABB(faces[offset], Vector3.ZERO)
		bounds = bounds.expand(faces[offset + 1]).expand(faces[offset + 2])
		triangle_bounds.append(AABB(bounds.position - expansion, bounds.size + expansion * 2.0))
		var normal := (faces[offset + 1] - faces[offset]).cross(faces[offset + 2] - faces[offset]).normalized()
		plane_normals.append(normal)
		plane_distances.append(normal.dot(faces[offset]))
		plane_radii.append(normal.abs().dot(expansion))
		ids.append(ids.size())
	_build_node(ids)


func _build_node(ids: Array[int]) -> int:
	var node := BoundsNode.new()
	node.bounds = triangle_bounds[ids[0]]
	for index in range(1, ids.size()):
		node.bounds = node.bounds.merge(triangle_bounds[ids[index]])
	var node_index := nodes.size()
	nodes.append(node)
	if ids.size() <= LEAF_SIZE:
		node.triangles = PackedInt32Array(ids)
		return node_index
	var axis := node.bounds.get_longest_axis_index()
	ids.sort_custom(func(first: int, second: int) -> bool:
		return triangle_bounds[first].get_center()[axis] < triangle_bounds[second].get_center()[axis])
	var middle := ids.size() / 2
	node.left = _build_node(ids.slice(0, middle))
	node.right = _build_node(ids.slice(middle))
	return node_index


func may_hit(start: Vector3, finish: Vector3) -> bool:
	if nodes.is_empty() or not start.is_finite() or not finish.is_finite():
		return true
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var node := nodes[pending.pop_back()]
		if not _intersects(node.bounds, start, finish):
			continue
		if node.left < 0:
			for triangle in node.triangles:
				if _intersects(triangle_bounds[triangle], start, finish):
					# A swept hull entirely on one side of the triangle's plane
					# cannot touch that triangle, even if their broad boxes overlap.
					var normal := plane_normals[triangle]
					var from := normal.dot(start) - plane_distances[triangle]
					var to := normal.dot(finish) - plane_distances[triangle]
					var radius := plane_radii[triangle]
					if (from > radius and to > radius) or (from < -radius and to < -radius):
						continue
					return true
		else:
			pending.append(node.left)
			pending.append(node.right)
	return false


func _intersects(bounds: AABB, start: Vector3, finish: Vector3) -> bool:
	return bounds.has_point(start) or bounds.has_point(finish) or bounds.intersects_segment(start, finish) != null
