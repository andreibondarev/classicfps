extends SceneTree

const EventLog := preload("res://scripts/bounded_event_log.gd")
const Router := preload("res://scripts/cs16_audio_event_router.gd")
const Adapter := preload("res://scripts/cs16_audio_playback_adapter.gd")
const Effects := preload("res://scripts/cs16_combat_effects.gd")
var failures: Array[String] = []
var started_count := 0
var stopped_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var log := EventLog.new(3)
	for index in range(20):
		log.append({"index": index, "nested": {"value": index}})
	var recent := log.snapshot()
	_check(recent.map(func(event: Dictionary) -> int: return event.index) == [17, 18, 19], "ring preserves chronological order across wraps")
	recent[0].nested.value = -1
	_check(log.snapshot()[0].nested.value == 17, "diagnostic readers cannot mutate retained events")
	_check(log.total_events == 20 and log._entries.size() == 3, "ring storage stays bounded while total remains accurate")
	log.clear()
	log.append({"index": 20})
	_check(log.snapshot()[0].index == 20 and log.total_events == 1, "clear resets cursor and counter")

	var router := Router.new()
	root.add_child(router)
	router.set_process(false)
	var adapter := Adapter.new()
	adapter.playback_enabled = false
	root.add_child(adapter)
	adapter.bind_router(router)
	router.event_started.connect(func(_event: Dictionary) -> void: started_count += 1)
	router.event_stopped.connect(func(_event: Dictionary) -> void: stopped_count += 1)
	var effects := Effects.new()
	root.add_child(effects)
	effects.set_physics_process(false)
	var event_count := EventLog.DEFAULT_CAPACITY * 3 + 17
	for index in range(event_count):
		router.emit_descriptor("soak.shot", 1, {
			"samples": ["weapons/ak47-1.wav"], "channel": Router.CHAN_WEAPON,
			"duration_seconds": 0.1,
		})
		effects._record("soak", {"index": index})
	router.stop_all("soak_end")
	_check(started_count == event_count and stopped_count == event_count, "all live audio signals survive diagnostic eviction")
	_check(router.trace().size() == EventLog.DEFAULT_CAPACITY and adapter.trace().size() == EventLog.DEFAULT_CAPACITY, "router and playback traces remain bounded through sustained firing")
	_check(router.trace()[-1].reason == "soak_end" and adapter.trace()[-1].reason == "soak_end", "audio traces preserve latest lifecycle event")
	_check(router.active_voices().is_empty() and adapter._active.is_empty(), "diagnostic eviction does not retain live voices")
	_check(effects.event_log.size() == EventLog.DEFAULT_CAPACITY and effects.total_effect_events == event_count, "VFX diagnostics remain bounded with exact total")
	_check(effects.event_log[0].index == event_count - EventLog.DEFAULT_CAPACITY and effects.event_log[-1].index == event_count - 1, "VFX diagnostics preserve latest ordered history")
	effects.clear_event_log()
	adapter.clear_trace()
	router.reset()
	_check(effects.event_log.is_empty() and adapter.trace().is_empty() and router.trace().is_empty(), "scene reset clears diagnostic histories")
	adapter.queue_free()
	router.queue_free()
	effects.queue_free()
	await process_frame
	print("GAME_BOUNDED_EVENT_LOG_TEST_PASS" if failures.is_empty() else "GAME_BOUNDED_EVENT_LOG_TEST_FAIL")
	quit(0 if failures.is_empty() else 1)
