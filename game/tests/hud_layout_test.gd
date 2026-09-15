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
	_check(
		hud_root.get_node_or_null("ClassicRadarContacts") != null,
		"radar has a live client contact layer",
	)
	_check(
		hud_root.get_node_or_null("ClassicHostageStatus") != null,
		"hostage objective has a source-sprite status row",
	)
	_check(hud_root.get_node_or_null("ClassicVitals") != null, "vitals are lower-left")
	_check(hud_root.get_node_or_null("ClassicTimer") != null, "timer is lower-center")
	_check(hud_root.get_node_or_null("ClassicAmmo") != null, "ammo is lower-right")
	_check(hud_root.get_node_or_null("ClassicDefuseProgress") != null, "defuse progress track is present")
	_check(hud.hitmarker.get_child_count() == 0, "hitmarker renders no geometry")
	hud.set_deploy_visible(false)
	hud.update_defuse_progress(true, 2.5, 5.0)
	_check(hud.defuse_progress_bar.visible
		and is_equal_approx(hud._defuse_progress_fill.size.x, 98.0)
		and hud._defuse_progress_fill.color == GameHUD.CLASSIC_GREEN,
		"defuse progress uses a half-filled classic green track")
	hud.update_defuse_progress(false, 0.0, 0.0)

	hud.update_match(2, "live", 83.1, 3, 4, 4750)
	hud.update_health(24, 76)
	hud.update_ammo(5, 62, false)
	_check(hud.timer_label.text == "1:24", "timer uses classic non-padded minute format")
	_check(hud.money_label.text == "$4750", "money uses classic dollar prefix")
	_check(hud.money_delta.modulate.a == 0.0, "initial balance is not a reward")
	hud.update_money(5050)
	_check(hud.money_delta_amount == 300 and hud.money_delta.modulate.a == 1.0
		and hud._money_delta_sign.get_meta("classic_sprite") == "plus"
		and hud._money_delta_sign.modulate == hud._classic_sprite_modulate(GameHUD.CLASSIC_GREEN),
		"reward displays original green plus and dollar sprites")
	var reward_tween: Tween = hud._money_delta_tween
	hud.update_money(5050)
	_check(hud._money_delta_tween == reward_tween and hud.money_delta_amount == 300,
		"repeated balance updates do not replay rewards")
	reward_tween.custom_step(1.75)
	_check(hud.money_delta.modulate.a > 0.0 and hud.money_delta.modulate.a < 1.0,
		"money reward fades after its hold")
	hud.update_money(5350)
	_check(hud.money_delta_amount == 600 and hud.money_delta.modulate.a == 1.0,
		"rapid rewards combine and replace the previous fade")
	hud.update_money(5270)
	_check(hud.money_delta_amount == -80
		and hud._money_delta_sign.get_meta("classic_sprite") == "minus"
		and hud._money_delta_sign.modulate == hud._classic_sprite_modulate(GameHUD.CLASSIC_RED),
		"expense replaces a gain with a red minus")
	hud._money_delta_tween.custom_step(3.0)
	_check(hud.money_delta.modulate.a == 0.0, "money change expires")
	hud.reset_match_presentation()
	hud.update_money(15980)
	_check(hud.money_delta.modulate.a == 0.0, "match reset establishes a quiet balance")
	hud.update_money(16000)
	_check(hud.money_delta_amount == 20, "capped reward shows only the actual balance increase")
	hud.update_money(16000)
	_check(hud.money_delta_amount == 20, "no extra award at the account cap")
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
	hud.update_tactical_display(
		Vector3.ZERO,
		0.0,
		[{"id": "ally", "position": Vector3(0.0, 0.0, -1.0), "alive": true}],
		[
			{"id": "h1", "alive": true, "rescued": false},
			{"id": "h2", "alive": false, "rescued": false},
			{"id": "h3", "alive": true, "rescued": true},
		],
	)
	_check(hud.radar_display.contacts.size() == 1, "radar receives live teammate contacts")
	_check(
		hud.hostage_status_group.get_child_count() == 3,
		"hostage row reflects authoritative objective count",
	)

	hud.show_hitmarker(true)
	await process_frame
	_check(hud.hitmarker.modulate.a == 0.0, "hit confirmation remains invisible")

	hud.set_deploy_visible(false)
	var participant_names := ["ClassicRadar", "ClassicRadarContacts", "ClassicHostageStatus",
		"ClassicMoney", "ClassicMoneyDelta", "ClassicVitals", "ClassicAmmo", "Crosshair", "DamageVignette"]
	for resolution in [Vector2i(640, 480), Vector2i(1024, 768), Vector2i(1280, 720)]:
		root.content_scale_size = resolution
		root.size = resolution
		hud_root.size = Vector2(resolution)
		hud.layout_for_viewport(Vector2(resolution))
		_check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(hud.money_delta.get_global_rect())
			and not hud.money_delta.get_global_rect().intersects(hud_root.get_node("ClassicMoney").get_global_rect()),
			"money delta stays on-screen above the balance at " + str(resolution))
		hud.show_damage()
		hud.show_flash_blind(10.0)
		hud.set_spectating(true)
		hud.update_spectate_target("CT Bot 04")
		hud.set_buy_zone(true)
		hud.update_health(13, 57)
		hud.update_ammo(7, 42, false)
		hud.update_match(3, "freeze", 60.0, 2, 1, 9999)
		await process_frame
		for control_name in participant_names:
			_check(not (hud_root.get_node(control_name) as Control).is_visible_in_tree(),
				"spectator hides " + control_name + " despite live updates")
		_check(not hud._buyzone_icon.visible, "buy-zone refresh cannot reveal a spectator's cart")
		_check(hud.damage_flash.color.a == 0.0 and hud.flash_blind_overlay.color.a == 0.0,
			"chase entry clears the previous life's combat feedback")
		var timer := hud_root.get_node("ClassicTimer") as Control
		_check(timer.visible and hud.spectate_label.visible, "observer retains timer and identity")
		_check(not timer.get_global_rect().intersects(hud.spectate_label.get_global_rect())
			and not hud.status_label.get_global_rect().intersects(hud.spectate_label.get_global_rect()),
			"observer identity does not overlap timer or objective at " + str(resolution))
		_check(Rect2(Vector2.ZERO, Vector2(resolution)).encloses(hud.spectate_label.get_global_rect()),
			"observer identity stays inside viewport")
		hud.set_paused_visible(true)
		_check(not hud.spectate_label.visible and not timer.visible, "pause hides observer presentation")
		hud.set_paused_visible(false)
		_check(hud.spectate_label.visible and not hud.crosshair.visible, "resume preserves observer presentation")
		hud.update_spectate_target("")
		_check(hud.spectate_label.text == "Spectating" and not hud.crosshair.visible,
			"missing target does not restore combat HUD")
		hud.set_spectating(false)
		for control_name in participant_names:
			_check((hud_root.get_node(control_name) as Control).visible,
				"return to first-person restores " + control_name)
		_check(not hud.spectate_label.visible and hud.spectate_label.text.is_empty()
			and hud.status_label.offset_top == -107.0, "return restores normal announcement layout")
		_check(hud._buyzone_icon.visible, "return restores eligible buy-zone indicator")

	hud.free()
	if _failed:
		quit(1)
	else:
		print("HUD_LAYOUT_TEST_PASS")
		quit(0)
