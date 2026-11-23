extends SceneTree

const AudioEventRouter := preload("res://scripts/cs16_audio_event_router.gd")
const AK47_SHA256 := "76f1f571d72c1a0c30a682b7767db1d32a8282fd555498740cdadd1b7385c61e"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _descriptor(
	channel: int,
	duration_seconds := 1.0,
	attenuation := AudioEventRouter.ATTN_NORM,
	pitch_min := AudioEventRouter.PITCH_NORM,
	pitch_max := AudioEventRouter.PITCH_NORM,
) -> Dictionary:
	return {
		"samples": ["weapons/ak47-1.wav", "weapons/ak47-2.wav"],
		"channel": channel,
		"volume": AudioEventRouter.VOL_NORM,
		"attenuation": attenuation,
		"pitch_min": pitch_min,
		"pitch_max": pitch_max,
		"flags": 0,
		"duration_seconds": duration_seconds,
	}


func _seeded_trace(router: CS16AudioEventRouter, seed: int) -> String:
	router.reset(seed)
	for index in range(24):
		router.emit_descriptor(
			"seeded.fire",
			index % 3,
			_descriptor(
				AudioEventRouter.CHAN_AUTO,
				0.2,
				AudioEventRouter.ATTN_NORM,
				AudioEventRouter.PITCH_LOW,
				AudioEventRouter.PITCH_HIGH,
			),
			Vector3(index, index * 2, -index),
		)
		router.advance_ticks(1)
	router.stop_all("capture_end")
	return router.trace_json()


func _run() -> void:
	var router := AudioEventRouter.new()
	router.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(router)
	router.reset()

	# Valve common/const.h values are API, not incidental implementation detail.
	_check(AudioEventRouter.TICK_RATE_HZ == 100, "router clock is exactly 100 Hz")
	_check(AudioEventRouter.CHAN_AUTO == 0, "CHAN_AUTO value")
	_check(AudioEventRouter.CHAN_WEAPON == 1, "CHAN_WEAPON value")
	_check(AudioEventRouter.CHAN_VOICE == 2, "CHAN_VOICE value")
	_check(AudioEventRouter.CHAN_ITEM == 3, "CHAN_ITEM value")
	_check(AudioEventRouter.CHAN_BODY == 4, "CHAN_BODY value")
	_check(AudioEventRouter.CHAN_STREAM == 5, "CHAN_STREAM value")
	_check(AudioEventRouter.CHAN_STATIC == 6, "CHAN_STATIC value")
	_check(is_equal_approx(AudioEventRouter.ATTN_NONE, 0.0), "ATTN_NONE value")
	_check(is_equal_approx(AudioEventRouter.ATTN_NORM, 0.8), "ATTN_NORM value")
	_check(is_equal_approx(AudioEventRouter.ATTN_STATIC, 1.25), "ATTN_STATIC value")
	_check(is_equal_approx(AudioEventRouter.ATTN_IDLE, 2.0), "ATTN_IDLE value")
	_check(AudioEventRouter.PITCH_NORM == 100, "PITCH_NORM value")
	_check(is_equal_approx(AudioEventRouter.VOL_NORM, 1.0), "VOL_NORM value")
	_check(AudioEventRouter.SND_STOP == 1 << 5, "SND_STOP value")
	_check(AudioEventRouter.SND_CHANGE_VOL == 1 << 6, "SND_CHANGE_VOL value")
	_check(AudioEventRouter.SND_CHANGE_PITCH == 1 << 7, "SND_CHANGE_PITCH value")
	_check(AudioEventRouter.SND_SPAWNING == 1 << 8, "SND_SPAWNING value")

	var starts: Array[Dictionary] = []
	var stops: Array[Dictionary] = []
	var errors: Array[String] = []
	router.event_started.connect(func(event: Dictionary) -> void: starts.append(event))
	router.event_stopped.connect(func(event: Dictionary) -> void: stops.append(event))
	router.router_error.connect(func(message: String) -> void: errors.append(message))

	# Catalog resolution preserves App 90 path, hash, source descriptor, and origin.
	var catalog_voice := router.emit_catalog_event(
		"ak47.fire",
		7,
		AudioEventRouter.CHAN_WEAPON,
		Vector3(1.25, 2.5, -4.0),
		{
			"variant_index": 0,
			"duration_seconds": 1.0,
			"volume": 0.55,
			"attenuation": AudioEventRouter.ATTN_STATIC,
			"flags": AudioEventRouter.SND_SPAWNING,
		},
	)
	_check(catalog_voice == 1, "first voice id is deterministic")
	_check(starts.size() == 1, "event_started emitted once")
	var catalog_event: Dictionary = starts[0]
	_check(catalog_event.sample == "weapons/ak47-1.wav", "catalog variant path")
	_check(catalog_event.sample_sha256 == AK47_SHA256, "catalog sample SHA-256")
	_check(int(catalog_event.channel) == AudioEventRouter.CHAN_WEAPON, "catalog channel")
	_check(is_equal_approx(float(catalog_event.volume), 0.55), "catalog volume")
	_check(
		is_equal_approx(float(catalog_event.attenuation), AudioEventRouter.ATTN_STATIC),
		"catalog attenuation",
	)
	_check(int(catalog_event.pitch) == AudioEventRouter.PITCH_NORM, "catalog pitch")
	_check(
		int(catalog_event.flags) == AudioEventRouter.SND_SPAWNING,
		"catalog sound flags",
	)
	_check(catalog_event.origin == [1.25, 2.5, -4.0], "catalog source origin")

	# A fixed channel is replaced only for the same entity and channel.
	router.reset()
	starts.clear()
	stops.clear()
	var first_weapon := router.emit_descriptor(
		"first.weapon",
		12,
		_descriptor(AudioEventRouter.CHAN_WEAPON),
	)
	router.advance_ticks(10)
	var second_weapon := router.emit_descriptor(
		"second.weapon",
		12,
		_descriptor(AudioEventRouter.CHAN_WEAPON),
	)
	_check(first_weapon == 1 and second_weapon == 2, "replacement voice ids")
	_check(router.active_voice_count() == 1, "same entity/channel replaces")
	_check(stops.size() == 1, "replacement emits one stop")
	_check(stops[0].reason == "replaced", "replacement stop reason")
	_check(int(stops[0].tick) == 10, "replacement occurs on authoritative tick")
	_check(int(stops[0].voice_id) == first_weapon, "replaced voice identity")
	_check(int(stops[0].replaced_by) == second_weapon, "replacement link")

	router.reset()
	router.emit_descriptor("weapon", 4, _descriptor(AudioEventRouter.CHAN_WEAPON))
	router.emit_descriptor("body", 4, _descriptor(AudioEventRouter.CHAN_BODY))
	_check(router.active_voice_count() == 2, "different channels on one entity overlap")

	router.reset()
	router.emit_descriptor("one", 4, _descriptor(AudioEventRouter.CHAN_WEAPON))
	router.emit_descriptor("two", 5, _descriptor(AudioEventRouter.CHAN_WEAPON))
	_check(router.active_voice_count() == 2, "same channel on different entities overlaps")

	router.reset()
	router.emit_descriptor("auto.one", 4, _descriptor(AudioEventRouter.CHAN_AUTO))
	router.emit_descriptor("auto.two", 4, _descriptor(AudioEventRouter.CHAN_AUTO))
	_check(router.active_voice_count() == 2, "CHAN_AUTO allocates independent voices")
	_check(not router.stop_channel(4, AudioEventRouter.CHAN_AUTO), "CHAN_AUTO is not addressable")

	router.reset()
	router.emit_descriptor("weapon", 4, _descriptor(AudioEventRouter.CHAN_WEAPON))
	_check(router.stop_channel(4, AudioEventRouter.CHAN_WEAPON), "fixed channel stops")
	_check(router.active_voice_count() == 0, "fixed channel stop removes voice")
	_check(not router.stop_channel(4, AudioEventRouter.CHAN_WEAPON), "stopped channel absent")

	# Duration is converted onto the 100 Hz clock after source pitch scaling.
	router.reset()
	router.emit_descriptor(
		"pitched.duration",
		1,
		_descriptor(
			AudioEventRouter.CHAN_AUTO,
			1.0,
			AudioEventRouter.ATTN_NORM,
			200,
			200,
		),
	)
	_check(int(router.trace()[0].duration_ticks) == 50, "200 pitch halves duration")
	router.advance_ticks(49)
	_check(router.active_voice_count() == 1, "voice active before exact end tick")
	router.advance_ticks(1)
	_check(router.active_voice_count() == 0, "voice stops on exact end tick")
	var duration_trace := router.trace()
	_check(duration_trace[-1].reason == "finished", "natural completion reason")
	_check(int(duration_trace[-1].tick) == 50, "natural completion tick")

	# All source attenuation descriptors pass through without a guessed curve.
	router.reset()
	var attenuation_values := [
		AudioEventRouter.ATTN_NONE,
		AudioEventRouter.ATTN_NORM,
		AudioEventRouter.ATTN_STATIC,
		AudioEventRouter.ATTN_IDLE,
	]
	for attenuation: float in attenuation_values:
		router.emit_descriptor(
			"attenuation.%.2f" % attenuation,
			1,
			_descriptor(AudioEventRouter.CHAN_AUTO, 0.1, attenuation),
		)
	var attenuation_trace := router.trace()
	for index in range(attenuation_values.size()):
		_check(
			is_equal_approx(
				float(attenuation_trace[index].attenuation),
				float(attenuation_values[index]),
			),
			"attenuation descriptor %d preserved" % index,
		)

	# Seed, event order, variant selection, pitch, IDs, and trace are reproducible.
	var seeded_a := _seeded_trace(router, 0xA0D10)
	var seeded_b := _seeded_trace(router, 0xA0D10)
	var seeded_c := _seeded_trace(router, 0xA0D11)
	_check(seeded_a == seeded_b, "same seed produces byte-identical trace")
	_check(seeded_a != seeded_c, "different seed changes variant/pitch trace")

	# Invalid source descriptors fail cleanly without creating voices.
	router.reset()
	var invalid_channel := _descriptor(99)
	_check(
		router.emit_descriptor("invalid.channel", 1, invalid_channel) == -1,
		"invalid channel rejected",
	)
	_check(router.emit_catalog_event("missing.event", 1, 1) == -1, "unknown event rejected")
	var invalid_volume := _descriptor(AudioEventRouter.CHAN_AUTO)
	invalid_volume.volume = 1.1
	_check(
		router.emit_descriptor("invalid.volume", 1, invalid_volume) == -1,
		"invalid volume rejected",
	)
	var legacy_path := _descriptor(AudioEventRouter.CHAN_AUTO)
	legacy_path.samples = ["res://assets/sounds/ak47-1.wav"]
	_check(
		router.emit_descriptor("legacy.path", 1, legacy_path) == -1,
		"legacy non-classic path rejected",
	)
	var traversal_path := _descriptor(AudioEventRouter.CHAN_AUTO)
	traversal_path.samples = ["weapons/../../ak47-1.wav"]
	_check(
		router.emit_descriptor("traversal.path", 1, traversal_path) == -1,
		"classic-root traversal rejected",
	)
	_check(
		router.emit_descriptor(
			"invalid.entity",
			-1,
			_descriptor(AudioEventRouter.CHAN_AUTO),
		) == -1,
		"negative entity id rejected",
	)
	_check(router.active_voice_count() == 0, "invalid events create no voices")
	_check(errors.size() == 6, "each invalid descriptor emits router_error")

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("CS16_AUDIO_EVENT_ROUTER_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return
	print(
		"CS16_AUDIO_EVENT_ROUTER_TEST_PASS "
		+ "(100 Hz, hashes, deterministic variants, channels, descriptors, lifecycle)"
	)
	quit()
