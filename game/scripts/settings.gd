extends Node

signal changed

const SETTINGS_PATH := "user://protocol47.cfg"

var mouse_sensitivity := 0.10
var invert_y := false
var field_of_view := 74.0
var master_volume_db := 0.0
var performance_preset := 1
var vsync_enabled := true
var crosshair_scale := 1.0
var high_contrast := false
var reduced_motion := false


func _ready() -> void:
	load_settings()
	apply()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
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
	var config := ConfigFile.new()
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("input", "invert_y", invert_y)
	config.set_value("video", "field_of_view", field_of_view)
	config.set_value("video", "performance_preset", performance_preset)
	config.set_value("video", "vsync_enabled", vsync_enabled)
	config.set_value("audio", "master_volume_db", master_volume_db)
	config.set_value("accessibility", "crosshair_scale", crosshair_scale)
	config.set_value("accessibility", "high_contrast", high_contrast)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save settings: %s" % error_string(error))


func apply() -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_volume_db)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED,
	)
	changed.emit()


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
