extends SceneTree

const AudioCatalog := preload("res://scripts/cs16_audio_catalog.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	_check(AudioCatalog.EVENT_SAMPLES["buy.ammo"] == ["items/9mmclip1.wav"], "ammo purchase uses the original CS clip cue")
	_check(AudioCatalog.EVENT_SAMPLES["buy.armor"] == ["items/ammopickup2.wav"],
		"kevlar and helmet purchases use the original CS armor cue")
	_check(AudioCatalog.EVENT_SAMPLES["weapon.acquire"] == ["items/gunpickup2.wav"],
		"weapon acquisition uses the original CS gun-pickup cue")
	_check(AudioCatalog.EVENT_SAMPLES["weapon.drop"] == ["items/weapondrop1.wav"],
		"weapon landing uses the original CS drop cue")
	_check(AudioCatalog.EVENT_SAMPLES["buy.defuser"] == ["items/kevlar.wav"]
		and AudioCatalog.EVENT_SAMPLES["buy.nvgs"] == ["items/equip_nvg.wav"],
		"remaining equipment purchases use their stock CS cues")
	_check(AudioCatalog.EVENT_SAMPLES["player.hit_helmet"] == ["player/bhit_helmet-1.wav"]
		and AudioCatalog.EVENT_SAMPLES["player.hit_kevlar"] == ["player/bhit_kevlar-1.wav"],
		"armored bullet hits retain helmet and kevlar distinctions")
	_check(AudioCatalog.DEPLOY_AUDIO_STAGES["m4a1"].size() == 2
		and int(AudioCatalog.DEPLOY_AUDIO_STAGES["ak47"][0].offset) == 37,
		"viewmodel-authored deploy markers drive draw sounds")
	_check(AudioCatalog.C4_ARM_AUDIO_STAGES == [118, 142, 164, 188, 212, 236, 255],
		"C4 keypad clicks retain the stock pressbutton timing")
	_check(AudioCatalog.EVENT_SAMPLES["glock18.fire"] == ["weapons/glock18-2.wav"], "Glock semi-auto uses only the single-shot recording")
	_check(AudioCatalog.EVENT_SAMPLES["glock18.fire_burst"] == ["weapons/glock18-1.wav"], "Glock burst uses the three-shot recording")
	_check(AudioCatalog.EVENT_SAMPLES["weapon.mode_switch"] == ["common/wpn_select.wav"], "fire-mode confirmation uses existing menu click")
	_check(AudioCatalog.material_code("TSIBeam") == AudioCatalog.METAL, "metal table entry")
	_check(AudioCatalog.material_code("TSFlrGrt") == AudioCatalog.GRATE, "grate table entry")
	_check(AudioCatalog.material_code("brickPath") == AudioCatalog.DIRT, "dirt table entry")
	_check(AudioCatalog.material_code("pi_steptop1") == AudioCatalog.TILE, "tile table entry")
	_check(AudioCatalog.network_audio_sample_valid("player.step.M", "player/pl_metal3.wav"),
		"network accepts a sample from the named dynamic footstep family")
	_check(not AudioCatalog.network_audio_sample_valid("player.step.M", "player/pl_step1.wav")
		and not AudioCatalog.network_audio_sample_valid("player.step.Z", "player/pl_step1.wav")
		and not AudioCatalog.network_audio_sample_valid("player.step.C", "../player/pl_step1.wav"),
		"network rejects mismatched, unknown, and traversing footstep samples")
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
