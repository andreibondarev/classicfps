extends Node

signal changed

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
	config.set_value("accessibility", "high_contrast", high_contrast)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	var error := config.save(settings_path)
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))


func apply() -> void:
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


func update_accessibility(scale: float, contrast: bool, reduce_motion: bool) -> void:
	crosshair_scale = clampf(scale, 0.75, 2.0)
	high_contrast = contrast
	reduced_motion = reduce_motion
	_commit()


func _commit() -> void:
	apply()
	save()
