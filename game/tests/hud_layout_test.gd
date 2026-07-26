extends SceneTree

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("HUD LAYOUT: %s" % message)


func _run() -> void:
	var hud_script := load("res://scripts/hud.gd") as GDScript
	_check(hud_script != null, "HUD script loads")
	if hud_script == null:
		quit(1)
		return
	var hud := hud_script.new() as GameHUD
	root.add_child(hud)
	await process_frame

	var hud_root := hud.get_node("HUDRoot") as Control
	_check(hud_root != null, "HUD root exists")
	_check(hud_root.get_node_or_null("MatchBar") == null, "modern match card is absent")
	_check(hud_root.get_node_or_null("ClassicRadar") != null, "radar is upper-left")
	_check(hud_root.get_node_or_null("ClassicVitals") != null, "vitals are lower-left")
	_check(hud_root.get_node_or_null("ClassicTimer") != null, "timer is lower-center")
	_check(hud_root.get_node_or_null("ClassicAmmo") != null, "ammo is lower-right")
	_check(hud.hitmarker.get_child_count() == 0, "hitmarker renders no geometry")

	hud.update_match(2, "live", 83.1, 3, 4, 4750)
	hud.update_health(24, 76)
	hud.update_ammo(5, 62, false)
	_check(hud.timer_label.text == "1:24", "timer uses classic non-padded minute format")
	_check(hud.money_label.text == "$4750", "money uses classic dollar prefix")
	_check(hud.health_label.text == "24", "health update reaches classic digits")
	_check(hud.armor_label.text == "76", "armor update reaches classic digits")
	_check(hud.ammo_label.text == "5", "clip is not zero padded")
	_check(hud.reserve_label.text == "62", "reserve is separate from the separator")
	_check(
		hud.health_label.get_theme_color("font_color") == GameHUD.CLASSIC_RED,
		"low health switches to classic red",
	)
	_check(
		hud.ammo_label.get_theme_color("font_color") == GameHUD.CLASSIC_RED,
		"low ammo switches to classic red",
	)

	hud.show_hitmarker(true)
	await process_frame
	_check(hud.hitmarker.modulate.a == 0.0, "hit confirmation remains invisible")

	hud.free()
	if _failed:
		quit(1)
	else:
		print("HUD_LAYOUT_TEST_PASS")
		quit(0)
