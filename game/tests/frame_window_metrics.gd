extends RefCounted

## Post-measurement summaries: no sorting or percentile work in the live loop.
## A frame belongs to the window containing its ending physics tick. Empty
## windows are omitted, never synthesized as fast frames. Boundary-spanning
## stalls remain intact rather than being divided across windows.
static func summarize(samples: Array[float], ticks: Array[int], effects: Array[int],
		alive: Array[int], initial_effects: int, window_ticks: int = 100) -> Array[Dictionary]:
	assert(samples.size() == ticks.size() and samples.size() == effects.size()
		and samples.size() == alive.size() and window_ticks > 0)
	var windows: Array[Dictionary] = []
	var previous_effects := initial_effects
	for index in samples.size():
		var start_tick := (ticks[index] / window_ticks) * window_ticks
		if windows.is_empty() or int(windows[-1].start_tick) != start_tick:
			windows.append({"start_tick": start_tick, "end_tick_exclusive": start_tick + window_ticks,
				"first_sample_tick": ticks[index], "last_sample_tick": ticks[index],
				"samples": [], "effect_events": 0, "alive_min": alive[index], "alive_max": alive[index]})
		var window: Dictionary = windows[-1]
		window.samples.append(samples[index])
		window.last_sample_tick = ticks[index]
		# The production diagnostic counter is monotonic over a match. A reset
		# is recorded explicitly, not allowed to create negative activity.
		if effects[index] < previous_effects:
			window["effect_counter_resets"] = int(window.get("effect_counter_resets", 0)) + 1
		window.effect_events += effects[index] - previous_effects if effects[index] >= previous_effects else effects[index]
		previous_effects = effects[index]
		window.alive_min = mini(window.alive_min, alive[index])
		window.alive_max = maxi(window.alive_max, alive[index])
	for window: Dictionary in windows:
		var sorted: Array = window.samples
		sorted.sort()
		var count := sorted.size()
		window["frames"] = count
		window["median_ms"] = sorted[count / 2]
		window["p95_ms"] = sorted[int(count * 0.95)]
		window["p99_ms"] = sorted[int(count * 0.99)]
		window["max_ms"] = sorted[-1]
		window["frames_over_33ms"] = sorted.filter(func(ms: float) -> bool: return ms > 33.333).size()
		window.erase("samples")
	return windows
