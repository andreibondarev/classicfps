class_name CS16BotTactics
extends RefCounted

const WeaponRegistry := preload("res://scripts/cs16_weapon_registry.gd")

## Deterministic 100 Hz combat decision clock for offline CS-style bots.
##
## Navigation and collision stay in the actor/controller layer. This class owns
## the timing-sensitive pieces which must not change with the render frame rate:
## acquisition delay, visual memory, AK bursts, inter-burst pauses and reloads.

const TICK_RATE := 100
const AK_CLIP_SIZE := 30
const AK_RESERVE_SIZE := 90
const AK_FIRE_TICKS := 10
const AK_RELOAD_TICKS := 245
const VISUAL_MEMORY_TICKS := 180
const AIM_ERROR_MIN_SECONDS := 0.40
const AIM_ERROR_MAX_SECONDS := 0.75
const MIN_AIM_ERROR_DEGREES := 0.35
const MAX_AIM_ERROR_DEGREES := 1.80
const MIN_TURN_DEGREES_PER_SECOND := 140.0
const MAX_TURN_DEGREES_PER_SECOND := 260.0

## Grenade usage window. Below the minimum a 1.6 bot shoots instead of cooking a
## grenade at its own feet; above the maximum the throw cannot reach.
const GRENADE_MIN_RANGE_HU := 450.0
const GRENADE_MAX_RANGE_HU := 1400.0
## Ticks before the same bot considers another grenade after actually throwing.
const GRENADE_COOLDOWN_TICKS := 800
## Ticks before re-evaluating an opportunity that was passed up or vetoed.
const GRENADE_RETRY_TICKS := 150
## Roll denominator for a single opportunity: grenades stay occasional.
const GRENADE_ROLL_SIDES := 4
const GRENADE_PRIORITY := ["hegrenade", "flashbang"]

const STATE_HUNT := "hunt"
const STATE_REACT := "react"
const STATE_ENGAGE := "engage"
const STATE_SEARCH := "search"
const STATE_RELOAD := "reload"

var tick := 0
var state := STATE_HUNT
var clip := AK_CLIP_SIZE
var reserve := AK_RESERVE_SIZE
var last_seen_tick := -VISUAL_MEMORY_TICKS - 1
var last_seen_position := Vector3.ZERO
var last_seen_velocity := Vector3.ZERO
var acquisition_tick := 0
var next_fire_tick := 0
var reload_complete_tick := -1
var burst_remaining := 0
var shots_fired := 0
var weapon_name := "ak47"
var magazine_size := AK_CLIP_SIZE
var initial_reserve := AK_RESERVE_SIZE
var fire_interval_ticks := AK_FIRE_TICKS
var reload_duration_ticks := AK_RELOAD_TICKS
var grenade_counts := {}

var _reaction_ticks := 22
var _skill := 1.0
var _rng := RandomNumberGenerator.new()
# Grenade decisions draw from their own stream so carrying utility can never
# shift the shooting trace of an identical replay.
var _grenade_rng := RandomNumberGenerator.new()
var _next_grenade_tick := 0
var _grenade_events: Array[Dictionary] = []
var _second_accumulator := 0.0
var _fire_pulse := false
var _reload_pulse := false
var _aim_target := Vector3.ZERO
var _aim_direction := Vector3.ZERO
var _aim_error := Vector2.ZERO
var _aim_error_goal := Vector2.ZERO
var _next_aim_error_tick := 0
var _fire_ticks: Array[int] = []
var _fire_events: Array[Dictionary] = []
var _reload_ticks: Array[int] = []


func configure_weapon(requested_weapon: String) -> bool:
	var definition := WeaponRegistry.definition(requested_weapon)
	if definition.is_empty() or str(definition.category) in ["melee", "objective"]:
		return false
	if str(definition.category) == "grenade":
		# Grenades are carried, not equipped: they join the utility inventory
		# and leave the shooting clock (magazine, cadence, reload) untouched.
		return add_grenade(str(definition.weapon))
	weapon_name = str(definition.weapon)
	magazine_size = int(definition.magazine)
	initial_reserve = int(definition.reserve)
	fire_interval_ticks = maxi(
		1,
		int(round(float(definition.primary_seconds) * float(TICK_RATE))),
	)
	reload_duration_ticks = maxi(
		1,
		int(round(float(definition.reload_seconds) * float(TICK_RATE))),
	)
	return true


func reset(seed: int, skill := 1.0) -> void:
	tick = 0
	state = STATE_HUNT
	clip = magazine_size
	reserve = initial_reserve
	last_seen_tick = -VISUAL_MEMORY_TICKS - 1
	last_seen_position = Vector3.ZERO
	last_seen_velocity = Vector3.ZERO
	acquisition_tick = 0
	next_fire_tick = 0
	reload_complete_tick = -1
	burst_remaining = 0
	shots_fired = 0
	_second_accumulator = 0.0
	_fire_pulse = false
	_reload_pulse = false
	_aim_target = Vector3.ZERO
	_aim_direction = Vector3.ZERO
	_aim_error = Vector2.ZERO
	_aim_error_goal = Vector2.ZERO
	_next_aim_error_tick = 0
	_fire_ticks.clear()
	_fire_events.clear()
	_reload_ticks.clear()
	_grenade_events.clear()
	grenade_counts.clear()
	_next_grenade_tick = 0
	_rng.seed = seed
	_grenade_rng.seed = seed ^ 0x9E3779B9
	_skill = clampf(skill, 0.0, 1.0)
	_reaction_ticks = clampi(
		int(round(34.0 - _skill * 18.0)),
		16,
		34,
	)


func advance_seconds(delta: float, observation: Dictionary) -> Dictionary:
	_second_accumulator += maxf(0.0, delta) * float(TICK_RATE)
	var elapsed_ticks := int(floor(_second_accumulator + 0.000001))
	if elapsed_ticks > 0:
		_second_accumulator -= float(elapsed_ticks)
	return advance_ticks(elapsed_ticks, observation)


func add_grenade(kind: String, count := 1) -> bool:
	if kind not in GRENADE_PRIORITY and kind != "smokegrenade":
		return false
	grenade_counts[kind] = int(grenade_counts.get(kind, 0)) + maxi(1, count)
	return true


func set_grenade_inventory(counts: Dictionary) -> void:
	grenade_counts.clear()
	for raw_kind: Variant in counts:
		var kind := str(raw_kind)
		var count := int(counts[raw_kind])
		if count > 0:
			grenade_counts[kind] = count


func confirm_grenade_throw(kind: String) -> void:
	## The controller owns the world checks, so it — not this clock — decides a
	## request became a real throw.
	if int(grenade_counts.get(kind, 0)) <= 0:
		return
	grenade_counts[kind] = int(grenade_counts[kind]) - 1
	if int(grenade_counts[kind]) <= 0:
		grenade_counts.erase(kind)
	_next_grenade_tick = tick + GRENADE_COOLDOWN_TICKS


func defer_grenade_throw() -> void:
	_next_grenade_tick = tick + GRENADE_RETRY_TICKS


func advance_ticks(count: int, observation: Dictionary) -> Dictionary:
	_fire_pulse = false
	_reload_pulse = false
	_fire_ticks.clear()
	_fire_events.clear()
	_reload_ticks.clear()
	_grenade_events.clear()
	for ignored in range(maxi(0, count)):
		_advance_tick(observation)
	return snapshot()


func _advance_tick(observation: Dictionary) -> void:
	tick += 1
	var visible := bool(observation.get("visible", false))
	var enemy_alive := bool(observation.get("enemy_alive", true))
	var enemy_position: Vector3 = observation.get("enemy_position", last_seen_position)
	var enemy_velocity: Vector3 = observation.get("enemy_velocity", Vector3.ZERO)
	var distance_hu := maxf(0.0, float(observation.get("distance_hu", INF)))

	if reload_complete_tick >= 0 and tick >= reload_complete_tick:
		var loaded := mini(magazine_size - clip, reserve)
		clip += loaded
		reserve -= loaded
		reload_complete_tick = -1

	if not enemy_alive:
		state = STATE_HUNT
		burst_remaining = 0
		return

	if visible:
		if tick - last_seen_tick > 1:
			acquisition_tick = tick + _reaction_ticks
			burst_remaining = 0
		# Perception continues every 10 ms while the enemy is visible. The
		# previous implementation only sampled on acquisition, so a moving
		# enemy left both the rendered aim and the actual shot ray stale.
		last_seen_position = enemy_position
		last_seen_velocity = enemy_velocity
		last_seen_tick = tick
		_update_aim_target(distance_hu, observation)

	if reload_complete_tick >= 0:
		state = STATE_RELOAD
		return

	if visible and tick < acquisition_tick:
		state = STATE_REACT
		return

	if visible:
		state = STATE_ENGAGE
		_request_grenade(distance_hu)
		if clip <= 0:
			_start_reload()
			return
		if tick >= next_fire_tick:
			if burst_remaining <= 0:
				burst_remaining = _burst_size(distance_hu)
			_fire_pulse = true
			_fire_ticks.append(tick)
			clip -= 1
			shots_fired += 1
			burst_remaining -= 1
			_fire_events.append({
				"tick": tick,
				"aim_target": _aim_target,
				"clip_after": clip,
				"reserve_after": reserve,
			})
			next_fire_tick = tick + fire_interval_ticks
			if burst_remaining <= 0:
				next_fire_tick += _rng.randi_range(18, 38)
		return

	if tick - last_seen_tick <= VISUAL_MEMORY_TICKS:
		state = STATE_SEARCH
		# Lead the remembered target briefly instead of snapping back to a
		# route waypoint on the first occluded tick.
		var age_seconds := minf(
			0.45,
			float(tick - last_seen_tick) / float(TICK_RATE),
		)
		_aim_target = last_seen_position + last_seen_velocity * age_seconds
	else:
		state = STATE_HUNT
		burst_remaining = 0


func _request_grenade(distance_hu: float) -> void:
	if grenade_counts.is_empty() or tick < _next_grenade_tick:
		return
	if distance_hu < GRENADE_MIN_RANGE_HU or distance_hu > GRENADE_MAX_RANGE_HU:
		return
	var kind := ""
	for candidate: String in GRENADE_PRIORITY:
		if int(grenade_counts.get(candidate, 0)) > 0:
			kind = candidate
			break
	if kind.is_empty():
		return
	if _grenade_rng.randi_range(0, GRENADE_ROLL_SIDES - 1) != 0:
		_next_grenade_tick = tick + GRENADE_RETRY_TICKS
		return
	_grenade_events.append({
		"tick": tick,
		"kind": kind,
		"target": last_seen_position,
	})
	_next_grenade_tick = tick + GRENADE_RETRY_TICKS


func _start_reload() -> void:
	if reserve <= 0 or reload_complete_tick >= 0:
		return
	state = STATE_RELOAD
	reload_complete_tick = tick + reload_duration_ticks
	burst_remaining = 0
	_reload_pulse = true
	_reload_ticks.append(tick)


func _burst_size(distance_hu: float) -> int:
	if distance_hu < 500.0:
		return _rng.randi_range(5, 8)
	if distance_hu < 1400.0:
		return _rng.randi_range(3, 5)
	return _rng.randi_range(1, 3)


func _update_aim_target(distance_hu: float, observation: Dictionary) -> void:
	# Human aim holds an error for a moment and then drifts; it does not roll a
	# fresh near-perfect offset every 10 ms. Lower skill widens that offset.
	if tick >= _next_aim_error_tick:
		var error_degrees := lerpf(MAX_AIM_ERROR_DEGREES, MIN_AIM_ERROR_DEGREES, _skill)
		_aim_error_goal = Vector2(
			_rng.randf_range(-error_degrees, error_degrees),
			_rng.randf_range(-error_degrees * 0.65, error_degrees * 0.65),
		)
		if _next_aim_error_tick == 0:
			_aim_error = _aim_error_goal
		_next_aim_error_tick = tick + _rng.randi_range(
			int(round(AIM_ERROR_MIN_SECONDS * TICK_RATE)),
			int(round(AIM_ERROR_MAX_SECONDS * TICK_RATE)),
		)
	_aim_error = _aim_error.lerp(_aim_error_goal, 0.045)

	# Estimate rather than perfectly solve target movement.
	var lead_fraction := lerpf(0.25, 0.60, _skill)
	var lead_seconds := clampf(distance_hu / 8000.0, 0.0, 0.12) * lead_fraction
	var predicted := last_seen_position + last_seen_velocity * lead_seconds
	var origin: Vector3 = observation.get("observer_origin", Vector3.INF)
	if origin == Vector3.INF:
		origin = Vector3.ZERO
	var desired := predicted - origin
	if desired.length_squared() <= 0.000001:
		return
	var forward := desired.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var distance := desired.length()
	var noisy_target := predicted + (
		right * tan(deg_to_rad(_aim_error.x))
		+ up * tan(deg_to_rad(_aim_error.y))
	) * distance
	var desired_direction := origin.direction_to(noisy_target)
	if _aim_direction.is_zero_approx():
		var observed_forward: Vector3 = observation.get("observer_forward", Vector3.ZERO)
		_aim_direction = observed_forward.normalized() if not observed_forward.is_zero_approx() else desired_direction
	var angle := _aim_direction.angle_to(desired_direction)
	var max_angle := deg_to_rad(
		lerpf(MIN_TURN_DEGREES_PER_SECOND, MAX_TURN_DEGREES_PER_SECOND, _skill)
	) / float(TICK_RATE)
	if angle > 0.000001:
		_aim_direction = _aim_direction.slerp(desired_direction, minf(1.0, max_angle / angle)).normalized()
	_aim_target = origin + _aim_direction * distance


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"state": state,
		"fire": _fire_pulse,
		"fire_count": _fire_ticks.size(),
		"fire_ticks": _fire_ticks.duplicate(),
		"fire_events": _fire_events.duplicate(true),
		"reload": _reload_pulse,
		"reload_ticks": _reload_ticks.duplicate(),
		"reloading": reload_complete_tick >= 0,
		"reload_complete_tick": reload_complete_tick,
		"aim_target": _aim_target,
		"aim_error": _aim_error,
		"aim_error_goal": _aim_error_goal,
		"last_seen_position": last_seen_position,
		"last_seen_tick": last_seen_tick,
		"clip": clip,
		"reserve": reserve,
		"shots_fired": shots_fired,
		"weapon": weapon_name,
		"grenade_events": _grenade_events.duplicate(true),
		"grenades": grenade_counts.duplicate(),
	}
