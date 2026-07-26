extends SceneTree

const AudioCatalog := preload("res://scripts/cs16_audio_catalog.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	_check(AudioCatalog.material_code("TSIBeam") == AudioCatalog.METAL, "metal table entry")
	_check(AudioCatalog.material_code("TSFlrGrt") == AudioCatalog.GRATE, "grate table entry")
	_check(AudioCatalog.material_code("brickPath") == AudioCatalog.DIRT, "dirt table entry")
	_check(AudioCatalog.material_code("pi_steptop1") == AudioCatalog.TILE, "tile table entry")
	_check(
		AudioCatalog.material_code("unlisted_dust_texture") == AudioCatalog.CONCRETE,
		"unlisted textures use classic concrete fallback",
	)

	for step_index in range(12):
		var step_path := AudioCatalog.footstep_sample("TSIBeam", step_index)
		_check(FileAccess.file_exists(step_path), "metal step sample %d exists" % step_index)
	for event_name: String in AudioCatalog.EVENT_SAMPLES:
		var variants: Array = AudioCatalog.EVENT_SAMPLES[event_name]
		for variant_index in range(variants.size()):
			var sample_path := AudioCatalog.event_sample(event_name, variant_index)
			_check(FileAccess.file_exists(sample_path), "%s variant %d exists" % [event_name, variant_index])

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("GAME_AUDIO_CATALOG_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return
	print(
		"GAME_AUDIO_CATALOG_TEST_PASS (%d event families, %d material tags)"
		% [AudioCatalog.EVENT_SAMPLES.size(), AudioCatalog._material_types.size()]
	)
	quit()
