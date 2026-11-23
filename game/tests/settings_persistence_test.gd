extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("SETTINGS: " + message)

func _run() -> void:
	var settings := root.get_node("GameSettings")
	var expected_path := OS.get_environment("PROTOCOL47_SETTINGS_PATH")
	if settings.get("settings_path") == "":
		# Autoload already rejected the override and queued exit 2.
		return
	# Fail before any write if the running implementation ignores isolation.
	if expected_path.is_empty() or settings.get("settings_path") != expected_path:
		push_error("SETTINGS: isolated storage was not selected; refusing to write")
		quit(1)
		return
	if "--write" in OS.get_cmdline_user_args():
		# A fresh profile is saved at once so its generated client tag stays stable.
		_check(settings.is_valid_client_tag(settings.client_tag), "fresh profile generates a client tag")
		_check(settings.player_name == "Player", "fresh profile uses the default player name")
		_check(is_equal_approx(settings.mouse_sensitivity, 0.10) and not settings.invert_y,
			"fresh profile uses default input settings")
		_check(is_equal_approx(settings.field_of_view, 74.0) and settings.performance_preset == 1
			and settings.vsync_enabled, "fresh profile uses default video settings")
		_check(is_zero_approx(settings.master_volume_db) and is_equal_approx(settings.crosshair_scale, 1.0)
			and not settings.high_contrast and not settings.reduced_motion, "fresh audio/accessibility defaults")
		if not failures.is_empty():
			quit(1)
			return
		settings.update_input(0.21, true)
		settings.update_player_name("  [P47] André  ")
		settings.update_video(92.0, 2, false)
		settings.update_volume(-12.0)
		settings.update_accessibility(1.5, true, true)
		_check(FileAccess.file_exists(expected_path), "commits create only the selected settings file")
	else:
		_check(settings.player_name == "[P47] André", "player name persists across processes")
		_check(FileAccess.file_exists(expected_path), "restart loads an existing profile")
		_check(is_equal_approx(settings.mouse_sensitivity, 0.21) and settings.invert_y,
			"input settings persist across processes")
		_check(is_equal_approx(settings.field_of_view, 92.0) and settings.performance_preset == 2
			and not settings.vsync_enabled, "video settings persist across processes")
		_check(is_equal_approx(settings.master_volume_db, -12.0) and is_equal_approx(settings.crosshair_scale, 1.5)
			and settings.high_contrast and settings.reduced_motion, "audio/accessibility persist across processes")
	print("GAME_SETTINGS_PERSISTENCE_PASS" if failures.is_empty() else "GAME_SETTINGS_PERSISTENCE_FAIL")
	quit(0 if failures.is_empty() else 1)
