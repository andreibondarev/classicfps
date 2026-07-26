extends SceneTree

const AudioEventRouter := preload("res://scripts/cs16_audio_event_router.gd")
const PlaybackAdapter := preload("res://scripts/cs16_audio_playback_adapter.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _descriptor(
	channel: int,
	attenuation: float,
	volume := 1.0,
	duration_seconds := 1.0,
) -> Dictionary:
	return {
		"samples": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
		"channel": channel,
		"volume": volume,
		"attenuation": attenuation,
		"pitch_min": AudioEventRouter.PITCH_LOW,
		"pitch_max": AudioEventRouter.PITCH_HIGH,
		"duration_seconds": duration_seconds,
	}


func _deterministic_scenario(seed: int) -> String:
	var router := AudioEventRouter.new()
	router.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(router)
	router.reset(seed)
	var adapter := PlaybackAdapter.new()
	adapter.playback_enabled = false
	root.add_child(adapter)
	adapter.bind_router(router)
	adapter.set_listener_origin_hu(Vector3(128, 0, 0))
	router.emit_descriptor(
		"capture.global",
		1,
		_descriptor(
			AudioEventRouter.CHAN_AUTO,
			AudioEventRouter.ATTN_NONE,
			0.65,
			0.25,
		),
		Vector3(1024, 0, 0),
	)
	router.emit_descriptor(
		"capture.weapon.one",
		2,
		_descriptor(
			AudioEventRouter.CHAN_WEAPON,
			AudioEventRouter.ATTN_NORM,
			0.8,
			0.4,
		),
		Vector3(512, 64, -32),
	)
	router.advance_ticks(7)
	router.emit_descriptor(
		"capture.weapon.two",
		2,
		_descriptor(
			AudioEventRouter.CHAN_WEAPON,
			AudioEventRouter.ATTN_NORM,
			0.8,
			0.4,
		),
		Vector3(640, 64, -32),
	)
	router.advance_ticks(3)
	router.stop_all("capture_end")
	var output := adapter.trace_json()
	adapter.unbind_router()
	adapter.clear_pool()
	adapter.free()
	router.free()
	return output


func _run() -> void:
	var router := AudioEventRouter.new()
	router.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(router)
	router.reset(0xA771)
	var adapter := PlaybackAdapter.new()
	adapter.playback_enabled = false
	root.add_child(adapter)
	adapter.bind_router(router)

	_check(is_equal_approx(PlaybackAdapter.HU_PER_METER, 100.0), "100 HU per metre")
	_check(is_equal_approx(PlaybackAdapter.METERS_PER_HU, 0.01), "one HU is 0.01 m")
	_check(
		PlaybackAdapter.hu_to_meters(Vector3(100, -250, 12.5))
		== Vector3(1, -2.5, 0.125),
		"HU origin converts to metres",
	)
	_check(
		PlaybackAdapter.meters_to_hu(Vector3(1, -2.5, 0.125))
		== Vector3(100, -250, 12.5),
		"metre origin converts to HU",
	)

	var distances: Array[float] = [0.0, 128.0, 512.0, 1024.0, 1250.0]
	var normal_probe := PlaybackAdapter.attenuation_probe(
		AudioEventRouter.ATTN_NORM,
		distances,
	)
	var expected_normal: Array[float] = [1.0, 0.8976, 0.5904, 0.1808, 0.0]
	for index in range(distances.size()):
		_check(
			is_equal_approx(float(normal_probe[index].gain), expected_normal[index]),
			"ATTN_NORM gain at %.0f HU" % distances[index],
		)
		_check(
			is_equal_approx(
				float(normal_probe[index].distance_meters),
				distances[index] * 0.01,
			),
			"probe records metre distance at %.0f HU" % distances[index],
		)
	for attenuation: float in [
		AudioEventRouter.ATTN_NONE,
		AudioEventRouter.ATTN_NORM,
		AudioEventRouter.ATTN_STATIC,
		AudioEventRouter.ATTN_IDLE,
	]:
		var probe := PlaybackAdapter.attenuation_probe(attenuation, distances)
		for entry: Dictionary in probe:
			var expected := (
				1.0
				if attenuation == AudioEventRouter.ATTN_NONE
				else clampf(
					1.0
					- float(entry.distance_hu)
					* attenuation
					/ PlaybackAdapter.NOMINAL_CLIP_DISTANCE_HU,
					0.0,
					1.0,
				)
			)
			_check(
				is_equal_approx(float(entry.gain), expected),
				"source attenuation descriptor %.2f probe" % attenuation,
			)

	# ATTN_NONE uses a pooled 2D player and preserves source volume/pitch.
	router.emit_descriptor(
		"global.radio",
		1,
		_descriptor(
			AudioEventRouter.CHAN_AUTO,
			AudioEventRouter.ATTN_NONE,
			0.5,
		),
		Vector3(1000, 0, 0),
	)
	var global_state: Dictionary = adapter.active_playbacks()[0]
	_check(global_state.player_kind == "2d", "ATTN_NONE uses AudioStreamPlayer")
	_check(is_equal_approx(float(global_state.gain), 1.0), "ATTN_NONE gain is constant")
	_check(
		is_equal_approx(float(global_state.volume_db), linear_to_db(0.5)),
		"source volume converts to dB",
	)
	var pool_counts: Dictionary = adapter.pool_counts()
	_check(int(pool_counts.active_2d) == 1, "one active 2D player")

	# Attenuated events use a pooled 3D player at the explicit converted origin.
	router.emit_descriptor(
		"world.weapon",
		2,
		_descriptor(
			AudioEventRouter.CHAN_WEAPON,
			AudioEventRouter.ATTN_NORM,
		),
		Vector3(1000, 0, 0),
	)
	var states := adapter.active_playbacks()
	var world_state: Dictionary
	for state: Dictionary in states:
		if state.event_name == "world.weapon":
			world_state = state
			break
	_check(not world_state.is_empty(), "world playback state exists")
	_check(world_state.player_kind == "3d", "attenuated event uses AudioStreamPlayer3D")
	_check(world_state.origin_meters == [10.0, 0.0, 0.0], "3D origin is converted once")
	_check(is_equal_approx(float(world_state.gain), 0.2), "1000 HU ATTN_NORM gain")
	var found_disabled_3d := false
	for child: Node in adapter.get_children():
		if child is AudioStreamPlayer3D:
			found_disabled_3d = (
				(child as AudioStreamPlayer3D).attenuation_model
				== AudioStreamPlayer3D.ATTENUATION_DISABLED
			)
			if found_disabled_3d:
				break
	_check(found_disabled_3d, "Godot distance attenuation is disabled")

	adapter.set_listener_origin_hu(Vector3(500, 0, 0))
	states = adapter.active_playbacks()
	for state: Dictionary in states:
		if state.event_name == "world.weapon":
			world_state = state
			break
	_check(is_equal_approx(float(world_state.distance_hu), 500.0), "listener move in HU")
	_check(is_equal_approx(float(world_state.gain), 0.6), "listener move refreshes gain")

	# Router replacement stops first, returns the player, and reuses its pool slot.
	router.reset(0xA771)
	adapter.clear_trace()
	adapter.set_listener_origin_hu(Vector3.ZERO)
	var first_voice := router.emit_descriptor(
		"replacement.first",
		10,
		_descriptor(AudioEventRouter.CHAN_WEAPON, AudioEventRouter.ATTN_NORM),
		Vector3(128, 0, 0),
	)
	var first_slot := int(adapter.active_playbacks()[0].pool_slot)
	router.advance_ticks(9)
	var second_voice := router.emit_descriptor(
		"replacement.second",
		10,
		_descriptor(AudioEventRouter.CHAN_WEAPON, AudioEventRouter.ATTN_NORM),
		Vector3(256, 0, 0),
	)
	var replacement_state: Dictionary = adapter.active_playbacks()[0]
	var replacement_trace := adapter.trace()
	_check(first_voice == 1 and second_voice == 2, "replacement router voice ids")
	_check(int(replacement_trace[1].voice_id) == first_voice, "adapter stops old voice")
	_check(replacement_trace[1].reason == "replaced", "adapter replacement reason")
	_check(int(replacement_trace[1].tick) == 9, "adapter replacement tick")
	_check(int(replacement_trace[1].replaced_by) == second_voice, "adapter replacement link")
	_check(int(replacement_state.pool_slot) == first_slot, "replacement reuses pool slot")
	_check(adapter.active_playback_count() == 1, "replacement leaves one playback")

	router.emit_descriptor(
		"replacement.body",
		10,
		_descriptor(AudioEventRouter.CHAN_BODY, AudioEventRouter.ATTN_NORM),
		Vector3(256, 0, 0),
	)
	_check(adapter.active_playback_count() == 2, "different fixed channels overlap")
	pool_counts = adapter.pool_counts()
	_check(int(pool_counts.active_3d) == 2, "two active pooled 3D players")

	router.stop_all("test_stop")
	_check(adapter.active_playback_count() == 0, "router stop releases all adapter voices")
	pool_counts = adapter.pool_counts()
	_check(int(pool_counts.free_3d) >= 2, "released 3D players return to pool")
	_check(int(pool_counts.free_2d) >= 1, "released 2D player remains pooled")

	# Natural 100 Hz expiry also returns its player exactly once.
	adapter.clear_trace()
	router.emit_descriptor(
		"natural.finish",
		3,
		_descriptor(
			AudioEventRouter.CHAN_ITEM,
			AudioEventRouter.ATTN_NORM,
			1.0,
			0.1,
		),
		Vector3.ZERO,
	)
	router.advance_ticks(30)
	_check(adapter.active_playback_count() == 0, "natural finish releases playback")
	var natural_trace := adapter.trace()
	_check(natural_trace[-1].reason == "finished", "natural adapter stop reason")

	# Pool slot identities and gain probes remain deterministic across runs.
	var trace_a := _deterministic_scenario(0xD157)
	var trace_b := _deterministic_scenario(0xD157)
	var trace_c := _deterministic_scenario(0xD158)
	_check(trace_a == trace_b, "adapter trace is byte-identical for same seed")
	_check(trace_a != trace_c, "adapter trace changes with variant/pitch seed")

	adapter.unbind_router()
	adapter.clear_pool()
	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("CS16_AUDIO_PLAYBACK_ADAPTER_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return
	print(
		"CS16_AUDIO_PLAYBACK_ADAPTER_TEST_PASS "
		+ "(HU/metres, linear attenuation probes, 2D/3D pools, replacement, trace)"
	)
	quit()
