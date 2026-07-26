class_name CS16BotTactics
extends RefCounted

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

var _reaction_ticks := 22
var _rng := RandomNumberGenerator.new()
var _second_accumulator := 0.0
var _fire_pulse := false
var _reload_pulse := false
var _aim_target := Vector3.ZERO
var _fire_ticks: Array[int] = []
var _fire_events: Array[Dictionary] = []
var _reload_ticks: Array[int] = []


func reset(seed: int, skill := 1.0) -> void:
	tick = 0
	state = STATE_HUNT
	clip = AK_CLIP_SIZE
	reserve = AK_RESERVE_SIZE
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
	_fire_ticks.clear()
	_fire_events.clear()
	_reload_ticks.clear()
	_rng.seed = seed
	_reaction_ticks = clampi(
		int(round(34.0 - clampf(skill, 0.0, 1.0) * 18.0)),
		16,
		34,
	)


func advance_seconds(delta: float, observation: Dictionary) -> Dictionary:
	_second_accumulator += maxf(0.0, delta) * float(TICK_RATE)
	var elapsed_ticks := int(floor(_second_accumulator + 0.000001))
	if elapsed_ticks > 0:
		_second_accumulator -= float(elapsed_ticks)
	return advance_ticks(elapsed_ticks, observation)


func advance_ticks(count: int, observation: Dictionary) -> Dictionary:
	_fire_pulse = false
	_reload_pulse = false
	_fire_ticks.clear()
	_fire_events.clear()
	_reload_ticks.clear()
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
		var loaded := mini(AK_CLIP_SIZE - clip, reserve)
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
		_update_aim_target(distance_hu)

	if reload_complete_tick >= 0:
		state = STATE_RELOAD
		return

	if visible and tick < acquisition_tick:
		state = STATE_REACT
		return

	if visible:
		state = STATE_ENGAGE
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
			next_fire_tick = tick + AK_FIRE_TICKS
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


func _start_reload() -> void:
	if reserve <= 0 or reload_complete_tick >= 0:
		return
	state = STATE_RELOAD
	reload_complete_tick = tick + AK_RELOAD_TICKS
	burst_remaining = 0
	_reload_pulse = true
	_reload_ticks.append(tick)


func _burst_size(distance_hu: float) -> int:
	if distance_hu < 500.0:
		return _rng.randi_range(5, 8)
	if distance_hu < 1400.0:
		return _rng.randi_range(3, 5)
	return _rng.randi_range(1, 3)


func _update_aim_target(distance_hu: float) -> void:
	# Expert CS bots still have a small, deterministic angular error. Express
	# it as a world-space offset so TargetActor can feed the result through the
	# same spread/ballistics path as a human shot.
	var lead_seconds := clampf(distance_hu / 8000.0, 0.0, 0.12)
	var error_radius_hu := clampf(distance_hu * 0.0025, 1.5, 10.0)
	var error := Vector3(
		_rng.randf_range(-error_radius_hu, error_radius_hu),
		_rng.randf_range(-error_radius_hu * 0.65, error_radius_hu * 0.65),
		_rng.randf_range(-error_radius_hu, error_radius_hu),
	) * 0.01
	_aim_target = last_seen_position + last_seen_velocity * lead_seconds + error


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
		"last_seen_position": last_seen_position,
		"last_seen_tick": last_seen_tick,
		"clip": clip,
		"reserve": reserve,
		"shots_fired": shots_fired,
	}
