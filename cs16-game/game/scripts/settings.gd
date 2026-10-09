extends Node

signal changed

const KeyBindings := preload("res://scripts/cs16_key_bindings.gd")

const SETTINGS_PATH := "user://protocol47.cfg"
const MAX_PLAYER_NAME_LENGTH := 32
var settings_path := SETTINGS_PATH
var player_name := "Player"

var mouse_sensitivity := 0.10
var invert_y := false
var field_of_view := 74.0
var master_volume_db := 0.0
var performance_preset := 1
var vsync_enabled := true
var crosshair_scale := 1.0
## Multiplayer-tab crosshair appearance (cl_crosshair_size / _color /
## _translucent), as indices into the GameUI combo boxes.
const CROSSHAIR_SIZES := ["auto", "small", "medium", "large"]
const CROSSHAIR_COLORS: Array[Color] = [
	Color8(50, 250, 50), Color8(250, 50, 50), Color8(50, 50, 250), Color8(250, 250, 50), Color8(50, 250, 250),
]
var crosshair_size := 0
var crosshair_color := 0
var crosshair_translucent := true
## Options > Keyboard overrides (command -> key name); defaults are implied.
var key_bindings := {}
## Options > Voice. Volumes are GameUI slider values; 75 is unity gain.
var voice_enabled := true
var voice_transmit_volume := 75.0
var voice_receive_volume := 75.0
var voice_mic_boost := false
var high_contrast := false
var reduced_motion := false


static func sanitize_player_name(value: String) -> String:
	var cleaned := ""
	for character in value:
		var code := character.unicode_at(0)
		if code < 32 or (code >= 127 and code <= 159) or code in [0x200B, 0x200E, 0x200F, 0x2028, 0x2029, 0xFEFF] or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069):
			continue
		cleaned += character
	cleaned = cleaned.strip_edges().left(MAX_PLAYER_NAME_LENGTH).strip_edges()
	return "Player" if cleaned.is_empty() else cleaned


func _ready() -> void:
	# Export/automation checks can use fresh settings without touching the
	# player's profile. Godot does not honor GODOT_USER_DATA_DIR on macOS.
	var requested := OS.get_environment("PROTOCOL47_SETTINGS_PATH")
	if not requested.is_empty():
		settings_path = ""
		if (not requested.is_absolute_path() or requested.begins_with("res://")
			or requested.begins_with("user://")
			or DirAccess.dir_exists_absolute(requested)
			or not DirAccess.dir_exists_absolute(requested.get_base_dir())):
			push_error("Invalid PROTOCOL47_SETTINGS_PATH: use an absolute file path in an existing directory")
			get_tree().quit(2)
			return
		settings_path = requested
	var fresh_profile := not FileAccess.file_exists(settings_path)
	load_settings()
	apply()
	if "--verify-settings-storage" in OS.get_cmdline_user_args():
		print("GAME_SETTINGS_STORAGE_READY ", JSON.stringify({"path": settings_path, "fresh": fresh_profile}))


func load_settings() -> void:
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	player_name = sanitize_player_name(str(config.get_value("multiplayer", "player_name", player_name)))
	mouse_sensitivity = clampf(float(config.get_value("input", "mouse_sensitivity", mouse_sensitivity)), 0.03, 0.35)
	invert_y = bool(config.get_value("input", "invert_y", invert_y))
	field_of_view = clampf(float(config.get_value("video", "field_of_view", field_of_view)), 60.0, 100.0)
	performance_preset = clampi(int(config.get_value("video", "performance_preset", performance_preset)), 0, 2)
	vsync_enabled = bool(config.get_value("video", "vsync_enabled", vsync_enabled))
	master_volume_db = clampf(float(config.get_value("audio", "master_volume_db", master_volume_db)), -40.0, 6.0)
	crosshair_scale = clampf(float(config.get_value("accessibility", "crosshair_scale", crosshair_scale)), 0.75, 2.0)
	crosshair_size = clampi(int(config.get_value("crosshair", "size", crosshair_size)), 0, CROSSHAIR_SIZES.size() - 1)
	crosshair_color = clampi(int(config.get_value("crosshair", "color", crosshair_color)), 0, CROSSHAIR_COLORS.size() - 1)
	crosshair_translucent = bool(config.get_value("crosshair", "translucent", crosshair_translucent))
	voice_enabled = bool(config.get_value("voice", "enabled", voice_enabled))
	voice_transmit_volume = clampf(float(config.get_value("voice", "transmit_volume", voice_transmit_volume)), 0.0, 100.0)
	voice_receive_volume = clampf(float(config.get_value("voice", "receive_volume", voice_receive_volume)), 0.0, 100.0)
	voice_mic_boost = bool(config.get_value("voice", "mic_boost", voice_mic_boost))
	key_bindings = {}
	if config.has_section("bindings"):
		for command: String in config.get_section_keys("bindings"):
			if KeyBindings.is_bindable(command):
				key_bindings[command] = KeyBindings.normalize(str(config.get_value("bindings", command, "")))
	high_contrast = bool(config.get_value("accessibility", "high_contrast", high_contrast))
	reduced_motion = bool(config.get_value("accessibility", "reduced_motion", reduced_motion))


func save() -> void:
	if settings_path.is_empty():
		return
	var config := ConfigFile.new()
	config.set_value("multiplayer", "player_name", player_name)
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("input", "invert_y", invert_y)
	config.set_value("video", "field_of_view", field_of_view)
	config.set_value("video", "performance_preset", performance_preset)
	config.set_value("video", "vsync_enabled", vsync_enabled)
	config.set_value("audio", "master_volume_db", master_volume_db)
	config.set_value("accessibility", "crosshair_scale", crosshair_scale)
	config.set_value("crosshair", "size", crosshair_size)
	config.set_value("crosshair", "color", crosshair_color)
	config.set_value("crosshair", "translucent", crosshair_translucent)
	for command: String in key_bindings:
		config.set_value("bindings", command, key_bindings[command])
	config.set_value("voice", "enabled", voice_enabled)
	config.set_value("voice", "transmit_volume", voice_transmit_volume)
	config.set_value("voice", "receive_volume", voice_receive_volume)
	config.set_value("voice", "mic_boost", voice_mic_boost)
	config.set_value("accessibility", "high_contrast", high_contrast)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	var error := config.save(settings_path)
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))


func apply() -> void:
	KeyBindings.apply_actions(bindings())
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_volume_db)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED,
	)
	changed.emit()


func update_player_name(value: String) -> void:
	player_name = sanitize_player_name(value)
	_commit()


func update_input(sensitivity: float, inverted: bool) -> void:
	mouse_sensitivity = clampf(sensitivity, 0.03, 0.35)
	invert_y = inverted
	_commit()


func update_video(fov: float, preset: int, vsync: bool) -> void:
	field_of_view = clampf(fov, 60.0, 100.0)
	performance_preset = clampi(preset, 0, 2)
	vsync_enabled = vsync
	_commit()


func update_volume(volume_db: float) -> void:
	master_volume_db = clampf(volume_db, -40.0, 6.0)
	_commit()


func update_crosshair(size_index: int, color_index: int, translucent: bool) -> void:
	crosshair_size = clampi(size_index, 0, CROSSHAIR_SIZES.size() - 1)
	crosshair_color = clampi(color_index, 0, CROSSHAIR_COLORS.size() - 1)
	crosshair_translucent = translucent
	_commit()


func update_voice(enabled: bool, transmit_volume: float, receive_volume: float, mic_boost: bool) -> void:
	voice_enabled = enabled
	voice_transmit_volume = clampf(transmit_volume, 0.0, 100.0)
	voice_receive_volume = clampf(receive_volume, 0.0, 100.0)
	voice_mic_boost = mic_boost
	_commit()


## Outgoing gain for the microphone (boost doubles it, like GameUI's).
func voice_transmit_gain() -> float:
	return voice_transmit_volume / 75.0 * (2.0 if voice_mic_boost else 1.0)


## Playback gain for teammates' voices; 0 when voice is disabled.
func voice_receive_gain() -> float:
	return voice_receive_volume / 75.0 if voice_enabled else 0.0


## Every rebindable command's current key.
func bindings() -> Dictionary:
	return KeyBindings.effective(key_bindings)


## Stores only commands that differ from their default key.
func update_key_bindings(values: Dictionary) -> void:
	var defaults := KeyBindings.default_bindings()
	key_bindings = {}
	var requested := KeyBindings.effective(values)
	for command: String in requested:
		var key := str(requested[command])
		if key != str(defaults[command]):
			key_bindings[command] = key
	_commit()


func update_accessibility(scale: float, contrast: bool, reduce_motion: bool) -> void:
	crosshair_scale = clampf(scale, 0.75, 2.0)
	high_contrast = contrast
	reduced_motion = reduce_motion
	_commit()


func _commit() -> void:
	apply()
	save()
