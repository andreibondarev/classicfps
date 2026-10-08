class_name CS16PlayerUseResolver
extends RefCounted

## Source-style PlayerUse candidate selection.
##
## PlayerUse searches usable entity origins in a 64 HU sphere around the
## player's origin, rejects candidates outside the narrow view cone, and keeps
## the candidate with the greatest view dot. A nearby button or door can
## therefore beat the planted C4.

const GOLDSRC_UNIT := 0.01
const MAX_USE_RADIUS_HU := 64.0
const MAX_USE_RADIUS := MAX_USE_RADIUS_HU * GOLDSRC_UNIT
const VIEW_FIELD_NARROW := 0.7


static func select_candidate(
	user_origin: Vector3,
	eye_origin: Vector3,
	view_forward: Vector3,
	candidates: Array,
) -> Dictionary:
	if view_forward.is_zero_approx():
		return {}
	var forward := view_forward.normalized()
	var best := {}
	var best_dot := VIEW_FIELD_NARROW
	for candidate_index in candidates.size():
		var raw: Variant = candidates[candidate_index]
		if not raw is Dictionary:
			continue
		var candidate: Dictionary = raw
		if not bool(candidate.get("usable", true)):
			continue
		var raw_origin: Variant = candidate.get("origin", null)
		if not raw_origin is Vector3:
			continue
		var origin := raw_origin as Vector3
		var distance_squared := user_origin.distance_squared_to(origin)
		if distance_squared > MAX_USE_RADIUS * MAX_USE_RADIUS + 0.0000001:
			continue
		var eye_to_candidate := origin - eye_origin
		if eye_to_candidate.is_zero_approx():
			continue
		var dot := eye_to_candidate.normalized().dot(forward)
		# Strictly greater mirrors `flDot > flMaxDot`. Equal-dot candidates keep
		# the first stable entity-search result.
		if dot <= best_dot:
			continue
		best_dot = dot
		best = candidate.duplicate(true)
		best.dot = dot
		best.distance_hu = sqrt(distance_squared) / GOLDSRC_UNIT
		best.candidate_index = candidate_index
	return best


static func selected_id(
	user_origin: Vector3,
	eye_origin: Vector3,
	view_forward: Vector3,
	candidates: Array,
) -> String:
	return str(
		select_candidate(
			user_origin,
			eye_origin,
			view_forward,
			candidates,
		).get("id", ""),
	)
