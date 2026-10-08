class_name CS16BombEscape
extends RefCounted

# Source CS bot code starts bomb escape between six and eight seconds from
# detonation according to aggression. A carried defuse kit scales that window
# to 66 percent. Combat and an active defuse take priority over escape.
const TICK_RATE := 100
const KIT_ESCAPE_SCALE := 0.66
const MIN_AGGRESSION := 0.0
const MAX_AGGRESSION := 1.0


static func threshold_seconds(aggression: float, has_defuse_kit := false) -> float:
	var source_aggression := clampf(
		aggression,
		MIN_AGGRESSION,
		MAX_AGGRESSION,
	)
	var seconds := 8.0 - 2.0 * source_aggression
	if has_defuse_kit:
		seconds *= KIT_ESCAPE_SCALE
	return seconds


static func threshold_ticks(aggression: float, has_defuse_kit := false) -> int:
	return int(round(threshold_seconds(aggression, has_defuse_kit) * TICK_RATE))


static func should_escape(
	bomb_ticks_left: int,
	aggression: float,
	has_defuse_kit := false,
	is_attacking := false,
	is_defusing := false,
) -> bool:
	if is_attacking or is_defusing:
		return false
	return bomb_ticks_left <= threshold_ticks(aggression, has_defuse_kit)
