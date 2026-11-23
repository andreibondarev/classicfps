class_name GoldSrcMovementKernel
extends RefCounted

# Collision portion of ReGameDLL's pm_shared movement, expressed in the
# repository's 0.01-world-unit-per-HU coordinate system. Godot supplies the
# convex sweep; this class owns GoldSrc's plane and step resolution.
const WORLD_SCALE := 0.01
const MAX_BUMPS := 4
const MAX_CLIP_PLANES := 5
const STOP_EPSILON := 0.1 * WORLD_SCALE
const FLOOR_NORMAL_MINIMUM := 0.7
const FLOOR_CATEGORIZE_DISTANCE := 2.0 * WORLD_SCALE
const STEP_HEIGHT := 18.0 * WORLD_SCALE
const EDGE_FORWARD_DISTANCE := 16.0 * WORLD_SCALE
const EDGE_DOWN_DISTANCE := 34.0 * WORLD_SCALE
const EDGE_FRICTION := 2.0
const UPWARD_UNGROUND_SPEED := 180.0 * WORLD_SCALE
const SWEEP_MARGIN := 0.01 * WORLD_SCALE
# ReHLDS PM_RecursiveHullCheck keeps endpoints 1/32 HU off contact planes.
# Keep this separate from the engine's supporting-floor recovery margin.
const CONTACT_SEPARATION := 0.03125 * WORLD_SCALE
const MOTION_MARGIN := 0.0
const FRACTION_EPSILON := 0.000001

const BLOCKED_FLOOR := 1
const BLOCKED_WALL := 2
const BLOCKED_ALL := 4

var body: CharacterBody3D
var grounded := false
var ground_normal := Vector3.UP
var last_blocked := 0
var last_used_step := false


func _init(character_body: CharacterBody3D) -> void:
	body = character_body


static func clip_velocity(
	source: Vector3,
	normal: Vector3,
	overbounce := 1.0,
) -> Vector3:
	var output := source - normal * source.dot(normal) * overbounce
	if absf(output.x) < STOP_EPSILON:
		output.x = 0.0
	if absf(output.y) < STOP_EPSILON:
		output.y = 0.0
	if absf(output.z) < STOP_EPSILON:
		output.z = 0.0
	return output


func move(
	source_velocity: Vector3,
	delta: float,
	allow_step: bool,
) -> Dictionary:
	last_used_step = false
	if delta <= 0.0 or not is_instance_valid(body):
		return {
			"velocity": source_velocity,
			"grounded": grounded,
			"ground_normal": ground_normal,
			"blocked": 0,
			"used_step": false,
		}

	var result: Dictionary
	if allow_step and grounded and Vector2(source_velocity.x, source_velocity.z).length_squared() > 0.0:
		result = _walk_move(source_velocity, delta)
	else:
		result = _fly_move(source_velocity, delta)
	last_blocked = int(result.blocked)

	var velocity_after: Vector3 = result.velocity
	grounded = categorize_ground(velocity_after)
	if (
		not grounded
		and (last_blocked & BLOCKED_FLOOR) != 0
		and velocity_after.y <= 0.0
	):
		# A zero-margin landing sweep can finish exactly coplanar, where the
		# follow-up two-HU Godot test occasionally reports no fresh collision.
		# GoldSrc retains the floor entity from that landing trace.
		grounded = true
	if grounded and velocity_after.y < 0.0:
		velocity_after.y = 0.0
	result.velocity = velocity_after
	result.grounded = grounded
	result.ground_normal = ground_normal
	result.used_step = last_used_step
	return result


func categorize_ground(source_velocity: Vector3) -> bool:
	grounded = false
	ground_normal = Vector3.UP
	if not is_instance_valid(body) or not body.is_inside_tree():
		return false
	if source_velocity.y > UPWARD_UNGROUND_SPEED:
		return false

	var collision := body.move_and_collide(
		Vector3.DOWN * FLOOR_CATEGORIZE_DISTANCE,
		true,
		SWEEP_MARGIN,
		false,
		MAX_CLIP_PLANES,
	)
	if collision == null:
		return false
	var floor_index := _best_floor_collision(collision)
	if floor_index < 0:
		return false
	ground_normal = collision.get_normal(floor_index)
	if ground_normal.y < FLOOR_NORMAL_MINIMUM:
		return false

	# PM_CategorizePosition snaps a valid two-HU ground trace to its endpoint.
	var travel := collision.get_travel()
	body.global_position += travel
	# Keep the next tangential sweep outside Godot's contact-recovery skin.
	# GoldSrc hull traces do not report the supporting floor as a blocking
	# plane during a purely horizontal PM_FlyMove.
	body.global_position += ground_normal * SWEEP_MARGIN * 2.0
	grounded = true
	return true


func edge_friction_multiplier(source_velocity: Vector3) -> float:
	if not grounded or not is_instance_valid(body) or not body.is_inside_tree():
		return 1.0
	var planar := Vector3(source_velocity.x, 0.0, source_velocity.z)
	if planar.length_squared() <= 0.0:
		return 1.0
	var ahead := planar.normalized() * EDGE_FORWARD_DISTANCE
	var start := body.global_position + ahead + Vector3.UP * SWEEP_MARGIN
	var end := start + Vector3.DOWN * (EDGE_DOWN_DISTANCE + SWEEP_MARGIN)
	var query := PhysicsRayQueryParameters3D.create(
		start,
		end,
		body.collision_mask,
		[body.get_rid()],
	)
	query.collide_with_areas = false
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return EDGE_FRICTION if hit.is_empty() else 1.0


func can_fit_box(size: Vector3, origin_offset := Vector3.ZERO) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return true
	var shape := BoxShape3D.new()
	shape.size = size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(
		Basis.IDENTITY,
		body.global_position + origin_offset + Vector3.UP * (size.y * 0.5 + SWEEP_MARGIN),
	)
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	query.collide_with_areas = false
	return body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _fly_move(source_velocity: Vector3, delta: float) -> Dictionary:
	var velocity := source_velocity
	var primal_velocity := source_velocity
	var original_velocity := source_velocity
	var planes: Array[Vector3] = []
	var time_left := delta
	var all_fraction := 0.0
	var blocked := 0

	for _bump in range(MAX_BUMPS):
		if velocity.length_squared() <= 0.0:
			break
		var motion := velocity * time_left
		if motion.length_squared() <= 0.0:
			break
		var collision := body.move_and_collide(
			motion,
			false,
			MOTION_MARGIN,
			false,
			MAX_CLIP_PLANES,
		)
		if collision == null:
			all_fraction += 1.0
			break

		var fraction := _collision_fraction(collision, motion)
		all_fraction += fraction
		if fraction > FRACTION_EPSILON:
			original_velocity = velocity
			planes.clear()

		var normal := collision.get_normal()
		# GoldSrc hull traces stop DIST_EPSILON short of every surface. A
		# zero-margin Godot sweep finishes flush instead, and a flush hull
		# re-reports this plane at fraction 0 on all later parallel sweeps,
		# draining every bump until velocity is zeroed — the player sticks to
		# the wall. Restore the epsilon of separation along the contact normal.
		body.global_position += normal * CONTACT_SEPARATION
		if normal.y > FLOOR_NORMAL_MINIMUM:
			blocked |= BLOCKED_FLOOR
			ground_normal = normal
		if absf(normal.y) <= FRACTION_EPSILON:
			blocked |= BLOCKED_WALL

		time_left *= 1.0 - fraction
		if planes.size() >= MAX_CLIP_PLANES:
			velocity = Vector3.ZERO
			break
		planes.append(normal)

		var resolved := false
		for plane_index in range(planes.size()):
			var candidate := clip_velocity(original_velocity, planes[plane_index])
			var enters_other_plane := false
			for other_index in range(planes.size()):
				if other_index == plane_index:
					continue
				if candidate.dot(planes[other_index]) < 0.0:
					enters_other_plane = true
					break
			if not enters_other_plane:
				velocity = candidate
				resolved = true
				break

		if not resolved:
			if planes.size() != 2:
				velocity = Vector3.ZERO
				break
			var crease := planes[0].cross(planes[1])
			if crease.length_squared() <= FRACTION_EPSILON:
				velocity = Vector3.ZERO
				break
			crease = crease.normalized()
			velocity = crease * crease.dot(original_velocity)

		if velocity.dot(primal_velocity) <= 0.0:
			velocity = Vector3.ZERO
			break
		if time_left <= 0.0:
			break

	if all_fraction <= FRACTION_EPSILON:
		velocity = Vector3.ZERO
		blocked |= BLOCKED_ALL
	return {"velocity": velocity, "blocked": blocked}


func _walk_move(source_velocity: Vector3, delta: float) -> Dictionary:
	var horizontal_motion := Vector3(source_velocity.x, 0.0, source_velocity.z) * delta
	if not _test_motion(horizontal_motion):
		body.global_position += horizontal_motion
		return {"velocity": Vector3(source_velocity.x, 0.0, source_velocity.z), "blocked": 0}

	var original_transform := body.global_transform
	var original_velocity := source_velocity

	var down_result := _fly_move(source_velocity, delta)
	var down_transform := body.global_transform
	var down_velocity: Vector3 = down_result.velocity
	var down_blocked := int(down_result.blocked)

	body.global_transform = original_transform
	var up_collision := body.move_and_collide(
		Vector3.UP * STEP_HEIGHT,
		false,
		MOTION_MARGIN,
		false,
		MAX_CLIP_PLANES,
	)
	if up_collision != null and _collision_fraction(up_collision, Vector3.UP * STEP_HEIGHT) <= FRACTION_EPSILON:
		body.global_transform = down_transform
		return down_result

	var up_result := _fly_move(original_velocity, delta)
	var step_blocked := int(up_result.blocked)
	var down_motion := Vector3.DOWN * STEP_HEIGHT
	var landing := body.move_and_collide(
		down_motion,
		false,
		MOTION_MARGIN,
		false,
		MAX_CLIP_PLANES,
	)
	var landing_is_floor := landing != null and landing.get_normal().y >= FLOOR_NORMAL_MINIMUM
	if landing_is_floor:
		ground_normal = landing.get_normal()
	var up_transform := body.global_transform

	var original_position := original_transform.origin
	var down_distance := _horizontal_distance_squared(down_transform.origin, original_position)
	var up_distance := _horizontal_distance_squared(up_transform.origin, original_position)
	if not landing_is_floor or down_distance > up_distance:
		body.global_transform = down_transform
		return {
			"velocity": down_velocity,
			"blocked": down_blocked,
		}

	last_used_step = up_transform.origin.y > down_transform.origin.y + FRACTION_EPSILON
	var up_velocity: Vector3 = up_result.velocity
	up_velocity.y = down_velocity.y
	return {
		"velocity": up_velocity,
		"blocked": step_blocked | (BLOCKED_FLOOR if landing_is_floor else 0),
	}


func _test_motion(motion: Vector3) -> bool:
	return body.move_and_collide(
		motion,
		true,
		MOTION_MARGIN,
		false,
		MAX_CLIP_PLANES,
	) != null


func _collision_fraction(collision: KinematicCollision3D, motion: Vector3) -> float:
	if motion.length_squared() <= 0.0:
		return 1.0
	return clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0.0, 1.0)


func _best_floor_collision(collision: KinematicCollision3D) -> int:
	var best_index := -1
	var best_y := -INF
	for collision_index in range(collision.get_collision_count()):
		var normal: Vector3 = collision.get_normal(collision_index)
		if normal.y > best_y:
			best_y = normal.y
			best_index = collision_index
	return best_index


func _horizontal_distance_squared(first: Vector3, second: Vector3) -> float:
	var delta := Vector2(first.x - second.x, first.z - second.z)
	return delta.length_squared()
