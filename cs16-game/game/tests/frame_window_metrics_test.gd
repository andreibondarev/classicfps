extends SceneTree

const Metrics := preload("res://tests/frame_window_metrics.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var samples: Array[float] = [40.0, 10.0, 35.0, 5.0, 6.0, 7.0]
	var ticks: Array[int] = [0, 99, 100, 101, 350, 350]
	var effects: Array[int] = [10, 12, 15, 15, 16, 2]
	var alive: Array[int] = [10, 10, 9, 8, 3, 3]
	var windows := Metrics.summarize(samples, ticks, effects, alive, 10)
	_check(windows.size() == 3, "empty time windows must not become synthetic samples")
	_check(windows[0].start_tick == 0 and windows[0].end_tick_exclusive == 100
		and windows[1].start_tick == 100 and windows[2].start_tick == 300, "exact tick boundaries")
	_check(windows[0].p95_ms == 40.0 and windows[1].max_ms == 35.0
		and windows[2].max_ms == 7.0, "quiet late frames cannot hide the opening stalls")
	_check(windows[0].frames_over_33ms == 1 and windows[1].frames_over_33ms == 1,
		"boundary-spanning stalls remain whole")
	_check(windows[1].effect_events == 3 and windows[1].alive_min == 8
		and windows[1].alive_max == 9, "window activity survives actor deaths")
	_check(windows[0].effect_events == 2 and windows[2].effect_events == 3
		and windows[2].effect_counter_resets == 1, "initial counter and counter resets")
	var count := 0
	for window: Dictionary in windows:
		count += int(window.frames)
	_check(count == samples.size() and samples == [40.0, 10.0, 35.0, 5.0, 6.0, 7.0],
		"every original frame counted once without changing chronological samples")
	_check(Metrics.summarize([], [], [], [], 0).is_empty(), "empty measurements")
	var single := Metrics.summarize([50.0], [100], [1], [1], 0)
	_check(single.size() == 1 and single[0].p99_ms == 50.0 and single[0].frames == 1,
		"partial final windows retain a single frame")
	print("GAME_FRAME_WINDOW_METRICS_PASS" if failures.is_empty() else "GAME_FRAME_WINDOW_METRICS_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
