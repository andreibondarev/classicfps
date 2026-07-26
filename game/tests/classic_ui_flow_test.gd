extends SceneTree

const RESOLUTIONS := [
	Vector2i(640, 480),
	Vector2i(1024, 768),
	Vector2i(1280, 720),
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _inside_viewport(control: Control, resolution: Vector2i) -> bool:
	return Rect2(Vector2.ZERO, Vector2(resolution)).encloses(control.get_global_rect())


func _style_is_square(control: Control, state: String) -> bool:
	var style := control.get_theme_stylebox(state) as StyleBoxFlat
	return (
		style != null
		and style.corner_radius_top_left == 0
		and style.corner_radius_top_right == 0
		and style.corner_radius_bottom_left == 0
		and style.corner_radius_bottom_right == 0
	)


func _visible_text_controls(node: Node) -> Array[Control]:
	var controls: Array[Control] = []
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
		if not current is Control or not (current as Control).is_visible_in_tree():
			continue
		var text := ""
		if current is Label:
			text = (current as Label).text
		elif current is Button:
			text = (current as Button).text
		if not text.is_empty():
			controls.append(current as Control)
	return controls


func _find_by_source_control(node: Node, source_control: String) -> Control:
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if (
			current is Control
			and str(current.get_meta("app90_control", "")) == source_control
		):
			return current as Control
		for child in current.get_children():
			pending.append(child)
	return null


func _check_state_geometry(hud: GameHUD, resolution: Vector2i, state: String) -> void:
	hud.set_deploy_visible(false)
	hud.set_buy_menu_visible(false)
	hud.set_scoreboard_visible(false)
	hud.set_paused_visible(false)
	match state:
		"team":
			hud.set_deploy_visible(true)
		"class":
			hud.set_deploy_visible(true)
			hud.show_class_menu(2)
		"buy":
			hud.show_buy_menu(1, 3350)
		"scoreboard":
			hud.show_scoreboard(
				[
					{"name": "Alpha", "team": 2, "score": 8, "deaths": 3, "latency": 26},
					{"name": "Bravo", "team": 1, "score": 5, "deaths": 4, "latency": 31},
				],
				"Counter-Strike",
				"de_dust2",
				4,
				3,
			)
		"escape":
			hud.set_paused_visible(true)
		"options":
			hud.set_paused_visible(true)
			hud._show_pause_options()
	await process_frame
	await process_frame
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
	var text_controls := _visible_text_controls(hud)
	for control in text_controls:
		_check(
			viewport_rect.encloses(control.get_global_rect()),
			"%s text '%s' stays inside %s"
			% [state, control.name, resolution],
		)
	for first in range(text_controls.size()):
		for second in range(first + 1, text_controls.size()):
			var a := text_controls[first]
			var b := text_controls[second]
			if a.get_parent() != b.get_parent():
				continue
			_check(
				not a.get_global_rect().intersects(b.get_global_rect()),
				"%s sibling text '%s'/'%s' does not overlap at %s"
				% [state, a.name, b.name, resolution],
			)


func _run() -> void:
	var hud := GameHUD.new()
	root.add_child(hud)
	await process_frame
	var hud_root := hud.get_node("HUDRoot") as Control

	_check(hud.deploy_overlay.visible, "join flow opens on the team menu")
	_check(hud.team_menu.visible, "team menu is the first deploy state")
	_check(not hud.class_menu.visible, "class menu waits for a team selection")
	_check(
		hud.team_menu.position == Vector2(76, 0),
		"team menu uses the App 90 640x480 frame origin",
	)
	_check(
		hud.team_menu.size == Vector2(552, 448),
		"team menu uses the App 90 frame dimensions",
	)
	_check(
		hud.team_menu.get_node("Team1").position == Vector2(0, 116),
		"first team button uses the source y=116 coordinate",
	)
	_check(
		hud.team_menu.get_node("Team2").position == Vector2(0, 148),
		"second team button uses the source 32px cadence",
	)
	for button_name in ["Team1", "Team2", "Team5", "Team6", "TeamCancel"]:
		_check(
			_style_is_square(hud.team_menu.get_node(button_name), "normal"),
			"%s has no modern rounded corners" % button_name,
		)
	var team_one := hud.team_menu.get_node("Team1") as Button
	_check(not team_one.text.contains("&"), "raw source accelerator marker is not exposed")
	_check(
		str(team_one.get_meta("accelerator")) == "1"
		and team_one.get_node_or_null("AcceleratorText") is RichTextLabel,
		"source team accelerator is rendered as an underlined span",
	)
	var accelerator_span := team_one.get_node("AcceleratorText") as RichTextLabel
	_check(
		str(accelerator_span.get_meta("source_font_rule")) == "DefaultUnderline"
		and float(accelerator_span.get_meta("source_baseline")) > 0.0,
		"accelerator uses the source underline font and a measured baseline",
	)
	var briefing := hud.team_menu.get_node(
		"MapInfo/BriefingScroll/Description"
	) as Label
	_check(
		briefing.text.contains("Other Notes:")
		and briefing.text.ends_with("weapon stashes in the mission."),
		"full source briefing including Other Notes remains in the scrollable document",
	)
	_check(
		hud.team_briefing_scroll.vertical_scroll_mode
		== ScrollContainer.SCROLL_MODE_AUTO
		and briefing.custom_minimum_size.y > hud.team_briefing_scroll.size.y,
		"full briefing is scrollable rather than clipped by a fixed label",
	)

	var signals := {
		"selected_team": -1,
		"selected_class": -1,
		"deploy_count": 0,
	}
	hud.team_selected.connect(
		func(team_id: int) -> void: signals.selected_team = team_id
	)
	hud.class_selected.connect(
		func(class_id: int) -> void: signals.selected_class = class_id
	)
	hud.deploy_requested.connect(
		func() -> void: signals.deploy_count = int(signals.deploy_count) + 1
	)
	hud._select_team(2)
	_check(int(signals.selected_team) == 2, "CT selection is exposed through the UI API")
	_check(hud.class_menu.visible, "team selection advances to class menu")
	_check(not hud.team_menu.visible, "team menu is hidden while choosing a class")
	_check(
		(hud.class_menu.get_node("Class1") as Button).text.contains("SEAL TEAM 6"),
		"CT class menu exposes the original class family",
	)
	_check(
		hud.class_menu.get_node_or_null("Class6") == null,
		"class menu is restricted to the eight shipped App 90 player MDLs",
	)
	_check(
		hud.class_portrait.texture != null
		and str(hud.class_portrait.get_meta("app90_portrait")) == "urban",
		"class hover presents the staged App 90 portrait",
	)
	hud._select_class(3)
	_check(int(signals.selected_class) == 3, "class selection is exposed through the UI API")
	_check(int(signals.deploy_count) == 1, "class selection bridges to existing deploy signal")
	hud.set_deploy_visible(true)
	_check(
		hud.handle_menu_action("menu_select_2", true)
		and hud.class_menu.visible
		and int(signals.selected_team) == 2,
		"typed menu action API forwards source numeric accelerators",
	)
	hud.accept_authoritative_deploy_selection(2, 4)
	_check(
		not hud.deploy_overlay.visible
		and int(hud.get_meta("authoritative_team")) == 2
		and int(hud.get_meta("authoritative_class")) == 4,
		"authoritative team/class acceptance API closes replicated deploy flow",
	)
	_check(
		hud.handle_menu_action("scoreboard", true)
		and hud.scoreboard_overlay.visible,
		"typed held-scoreboard action opens on press",
	)
	hud.handle_menu_action("scoreboard", false)
	_check(not hud.scoreboard_overlay.visible, "held-scoreboard action closes on release")

	hud.show_buy_menu(1, 800)
	_check(hud.buy_overlay.visible, "buy API opens a dedicated classic overlay")
	_check(
		hud.buy_canvas.get_node("BuyMenu").position == Vector2(76, 0),
		"buy menu shares the original VGUI origin",
	)
	hud._show_buy_category("pistols")
	var glock := hud.buy_list_panel.get_node("BuyItem_glock18") as Button
	var deagle := hud.buy_list_panel.get_node("BuyItem_deagle") as Button
	var elites := hud.buy_list_panel.get_node("BuyItem_elites") as Button
	var glock_accelerator := glock.get_node("AcceleratorText") as RichTextLabel
	_check(
		glock.text == "1 9X19MM SIDEARM"
		and not glock.text.contains("1 1")
		and not glock.text.contains("&"),
		"rendered buy row contains one accelerator digit and no raw source marker",
	)
	_check(
		glock_accelerator.text.contains("[u]1[/u]")
		and glock_accelerator.text.count("[u]1[/u]") == 1,
		"buy row renders exactly one underlined accelerator glyph",
	)
	_check(
		not hud.buy_description.text.contains("&")
		and hud.buy_description.text.begins_with("1 9X19MM SIDEARM"),
		"selected buy detail strips the source accelerator marker",
	)
	_check(not deagle.disabled, "affordable buy item remains selectable")
	_check(not elites.disabled, "item at exact account value remains selectable")
	_check(hud.buy_portrait.texture != null, "buy hover renders staged source weapon art")
	_check(
		str(deagle.get_meta("app90_source")).ends_with("BuyPistols_TER.kv"),
		"buy item order/cost is parsed from the Terrorist source catalog",
	)
	hud._buy_money = 600
	hud._show_buy_category("pistols")
	deagle = hud.buy_list_panel.get_node("BuyItem_deagle") as Button
	_check(deagle.disabled, "unaffordable buy item is visibly disabled")
	_check(
		deagle.get_theme_color("font_disabled_color").a == 0.0
		and (deagle.get_node("AcceleratorText") as RichTextLabel).visible,
		"disabled buy row has one RichText glyph layer with no ghosted Button copy",
	)
	hud.show_buy_menu(2, 10000)
	hud._show_buy_category("rifles")
	_check(hud.buy_list_panel.get_node_or_null("BuyItem_m4a1") != null, "CT catalog exposes M4A1")
	_check(hud.buy_list_panel.get_node_or_null("BuyItem_ak47") == null, "CT catalog excludes Terrorist AK-47")
	hud.show_buy_menu(1, 10000)
	hud._show_buy_category("rifles")
	_check(hud.buy_list_panel.get_node_or_null("BuyItem_ak47") != null, "T catalog exposes AK-47")
	_check(hud.buy_list_panel.get_node_or_null("BuyItem_m4a1") == null, "T catalog excludes CT M4A1")
	hud.show_buy_menu(1, 1000, {"primary_ammo_price": 80, "secondary_ammo_price": 40})
	hud._show_buy_category("primary_ammo")
	_check(
		int(hud._buy_items[0].price) == 80,
		"typed buy context supplies authoritative caliber-dependent ammo price",
	)

	var players := [
		{"name": "Alpha", "team": 2, "score": 8, "deaths": 3, "latency": 26, "alive": true},
		{"name": "Bravo", "team": 1, "score": 5, "deaths": 4, "latency": 31, "alive": false},
		{"name": "HLTV", "team": 0, "score": 0, "deaths": 0, "latency": 12, "alive": true},
	]
	hud.show_scoreboard(players, "Protocol 47 Test", "de_dust2", 4, 3)
	_check(hud.scoreboard_overlay.visible, "TAB scoreboard API controls visibility")
	_check(
		hud.scoreboard_rows.get_node_or_null("Player_Alpha") != null,
		"scoreboard renders CT player rows",
	)
	_check(
		hud.scoreboard_rows.get_node_or_null("Player_Bravo") != null,
		"scoreboard renders Terrorist player rows",
	)
	_check(
		hud.scoreboard_rows.get_node_or_null("Player_HLTV") != null,
		"scoreboard renders spectator rows",
	)
	var dead_row := hud.scoreboard_rows.get_node("Player_Bravo") as Control
	_check(
		dead_row.find_child("Status_smallskull", true, false) != null,
		"scoreboard uses the staged death status icon",
	)
	players[0]["voice_active"] = true
	players[1]["voice_muted"] = true
	hud.update_scoreboard(players, "Protocol 47 Test", "de_dust2", 4, 3)
	var active_voice := hud.scoreboard_rows.get_node("Player_Alpha").find_child(
		"Status_voice_active", true, false
	) as TextureRect
	var muted_voice := hud.scoreboard_rows.get_node("Player_Bravo").find_child(
		"Status_voice_muted", true, false
	) as TextureRect
	_check(
		active_voice != null
		and muted_voice != null
		and active_voice.texture != null
		and muted_voice.texture != null,
		"scoreboard renders distinct live voice and muted status fixtures",
	)
	_check(
		active_voice.custom_minimum_size == Vector2(16, 16)
		and muted_voice.custom_minimum_size == Vector2(16, 16)
		and str(active_voice.get_meta("app90_source")).ends_with("640_speaker4.tga")
		and str(muted_voice.get_meta("app90_source")).ends_with("640_voiceblocked.tga"),
		"scoreboard voice glyphs render from the pinned App 90 speaker artwork",
	)
	var voice_row_text := ""
	for voice_row in [
		hud.scoreboard_rows.get_node("Player_Alpha"),
		hud.scoreboard_rows.get_node("Player_Bravo"),
	]:
		for child in voice_row.find_children("*", "Label", true, false):
			voice_row_text += (child as Label).text
	_check(
		not voice_row_text.contains("●") and not voice_row_text.contains("×"),
		"scoreboard voice state contains no project-authored dot or x glyph",
	)
	var full_server: Array = []
	for index in range(32):
		full_server.append({
			"name": "Full %02d" % index,
			"team": 2 if index % 2 == 0 else 1,
			"score": index,
			"deaths": 31 - index,
			"latency": 20 + index,
		})
	hud.update_scoreboard(full_server, "Protocol 47 Test", "de_dust2", 4, 3)
	var full_row_count := 0
	for child in hud.scoreboard_rows.get_children():
		if child.name.begins_with("Player_Full"):
			full_row_count += 1
	_check(full_row_count == 32, "all 32 full-server rows exist behind scoreboard scrolling")
	var server_label := hud.scoreboard_canvas.get_node(
		"ClientScoreBoard/ScoreboardContent/ServerName"
	) as Label
	_check(server_label.text == "Protocol 47 Test  |  de_dust2", "scoreboard API updates server/map")

	hud.set_paused_visible(true)
	_check(hud.pause_main_menu.visible, "ESC opens the classic game menu list")
	_check(not hud.pause_options_menu.visible, "options remain a nested menu")
	_check(
		hud.pause_canvas.get_node_or_null("GameMenu/GameMenu_options") != null,
		"classic game menu retains the options capability",
	)
	_check(
		(hud.pause_main_menu.get_node("GameMenuArtwork") as TextureRect).texture != null,
		"ESC menu uses the exact App 90 game_menu artwork",
	)
	_check(not hud.crosshair.visible, "ESC menu suppresses the live crosshair/HUD")
	hud._show_pause_options()
	_check(hud.pause_options_menu.visible, "options page opens inside the faithful shell")
	_check(not hud.pause_main_menu.visible, "main entries hide while options are open")
	_check(
		_style_is_square(hud.pause_options_menu, "panel"),
		"options panel has square VGUI borders rather than a rounded card",
	)
	for tab_name in ["multiplayer", "keyboard", "mouse", "audio", "video", "voice"]:
		_check(
			hud.options_tab_bar.get_node_or_null("Tab_%s" % tab_name) != null,
			"source-style options dialog exposes %s tab" % tab_name,
		)
		var page := hud.options_pages.get_node("Page_%s" % tab_name) as Control
		_check(
			bool(page.get_meta("source_authored_controls"))
			and str(page.get_meta("app90_source")).ends_with(
				"OptionsSubMultiplayer.kv" if tab_name == "multiplayer"
				else "OptionsSub%s.kv" % tab_name.capitalize()
			),
			"%s page is built from its pinned OptionsSub resource" % tab_name,
		)
	_check(
		str(hud.pause_options_menu.get_meta("app90_source")).ends_with(
			"DialogOptionsIngame.kv"
		)
		and hud.pause_options_menu.get_meta("app90_source_rect")
		== Rect2(0, 0, 824, 736),
		"options shell parses the actual DialogOptionsIngame resource",
	)
	var mouse_reverse := hud.options_pages.get_node(
		"Page_mouse/Source_ReverseMouse"
	) as Control
	_check(
		mouse_reverse.position == Vector2(36, 32)
		and int(mouse_reverse.get_meta("tab_position")) == 1,
		"option geometry and focus order preserve source xpos/ypos/tabPosition",
	)
	var starting_sensitivity := float(hud.settings.mouse_sensitivity)
	var source_sensitivity := hud.options_pages.get_node(
		"Page_mouse/Source_Slider"
	) as HSlider
	source_sensitivity.value = minf(0.35, starting_sensitivity + 0.08)
	_check(
		not is_equal_approx(
			float(hud._options_pending.mouse_sensitivity),
			starting_sensitivity,
		)
		and is_equal_approx(float(hud.settings.mouse_sensitivity), starting_sensitivity),
		"source mouse control stages a changed setting without premature commit",
	)
	hud._options_cancel()
	_check(
		is_equal_approx(
			float(hud._options_pending.mouse_sensitivity),
			starting_sensitivity,
		)
		and is_equal_approx(float(hud.settings.mouse_sensitivity), starting_sensitivity),
		"Cancel rolls staged source-option changes back to the opening snapshot",
	)
	hud._show_pause_options()
	var keyboard_defaults := hud.options_pages.get_node(
		"Page_keyboard/Source_Defaults"
	) as Button
	_check(
		str(keyboard_defaults.get_meta("command")) == "Defaults"
		and int(keyboard_defaults.get_meta("tab_position")) == 2,
		"source Defaults command and tab semantics are retained",
	)
	var keyboard_bindings := hud.options_pages.get_node(
		"Page_keyboard/Source_listpanel_keybindlist/Bindings"
	) as VBoxContainer
	var forward_binding: Label
	var visible_binding_text := ""
	for binding_row in keyboard_bindings.get_children():
		if binding_row is Label:
			visible_binding_text += (binding_row as Label).text + "\n"
			if str(binding_row.get_meta("source_command", "")) == "+forward":
				forward_binding = binding_row as Label
	_check(
		keyboard_bindings.get_child_count() > 60
		and int(keyboard_bindings.get_parent().get_meta("source_row_count")) > 60,
		"keyboard options render the full App 90 action list",
	)
	_check(
		forward_binding != null
		and forward_binding.text.contains("Move forward")
		and forward_binding.text.ends_with("W")
		and visible_binding_text.contains("Walk")
		and visible_binding_text.contains("SHIFT"),
		"keyboard list pixels include localized movement actions and classic bindings",
	)
	var voice_page := hud.options_pages.get_node("Page_voice") as Control
	var transmit_slider := voice_page.get_node("Source_MicrophoneVolume") as HSlider
	var receive_slider := voice_page.get_node("Source_VoiceReceive") as HSlider
	var dead_meter := voice_page.get_node("Source_MicMeter") as TextureRect
	var live_meter := voice_page.get_node("Source_MicMeter2") as TextureRect
	var transmit_label := _find_by_source_control(voice_page, "Microphonelabel") as Label
	var receive_label := _find_by_source_control(voice_page, "ReceiveLabel") as Label
	_check(
		transmit_slider != null
		and receive_slider != null
		and transmit_slider.size == Vector2(160, 26)
		and receive_slider.size == Vector2(160, 42),
		"voice options render both source transmit and receive volume controls",
	)
	_check(
		transmit_label != null
		and receive_label != null
		and transmit_label.text == "Voice transmit volume *"
		and receive_label.text == "Voice receive volume *",
		"voice volume labels render localized source-authored text",
	)
	_check(
		dead_meter != null
		and live_meter != null
		and dead_meter.texture != null
		and live_meter.texture != null
		and dead_meter.visible
		and not live_meter.visible
		and dead_meter.size == Vector2(158, 32)
		and live_meter.size == Vector2(158, 32),
		"voice page renders both pinned microphone meter states at source geometry",
	)
	_check(
		not hud.accessibility_overlay.visible,
		"accessibility additions stay outside the CS 1.6 parity tabs",
	)

	hud.set_buy_menu_visible(false)
	hud.set_scoreboard_visible(false)
	hud.set_paused_visible(false)
	hud.set_deploy_visible(true)
	for resolution in RESOLUTIONS:
		root.content_scale_size = resolution
		root.size = resolution
		hud_root.size = Vector2(resolution)
		hud.layout_for_viewport(Vector2(resolution))
		await process_frame
		await process_frame
		for canvas in [
			hud.deploy_canvas,
			hud.buy_canvas,
			hud.scoreboard_canvas,
			hud.pause_canvas,
		]:
			_check(
				_inside_viewport(canvas, resolution),
				"%s stays in the viewport at %s" % [canvas.name, resolution],
			)
		var expected_scale := minf(
			float(resolution.x) / GameHUD.VGUI_BASE_SIZE.x,
			float(resolution.y) / GameHUD.VGUI_BASE_SIZE.y,
		)
		_check(
			is_equal_approx(
				float(hud.deploy_canvas.get_meta("reference_scale")),
				expected_scale,
			),
			"640x480 reference scale is deterministic at %s" % resolution,
		)
		for state in ["team", "class", "buy", "scoreboard", "escape", "options"]:
			await _check_state_geometry(hud, resolution, state)

	var tree_text := ""
	var pending: Array[Node] = [hud]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if node is Label:
			tree_text += (node as Label).text
		elif node is Button:
			tree_text += (node as Button).text
	tree_text = tree_text.replace("PROTOCOL 47 ACCESSIBILITY EXTENSION", "")
	_check(not tree_text.contains("PROTOCOL 47"), "normal parity UI flows contain no project-brand card")
	_check(not tree_text.contains("TACTICAL TRAINING"), "modern deploy copy is removed")
	_check(not tree_text.contains("PAUSED"), "modern centered pause title is removed")
	var capture_source := FileAccess.get_file_as_string(
		"res://tests/classic_ui_flow_capture.gd"
	)
	for fixture in [
		"buy_t_pistols_unaffordable",
		"scoreboard_1",
		"scoreboard_10",
		"scoreboard_20",
		"scoreboard_32",
		"scoreboard_voice",
	]:
		_check(capture_source.contains('"%s"' % fixture), "%s capture fixture exists" % fixture)

	hud.free()
	if _failures.is_empty():
		print("CLASSIC_UI_FLOW_TEST_PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("CLASSIC UI FLOW: %s" % failure)
		print("CLASSIC_UI_FLOW_TEST_FAIL (%d)" % _failures.size())
		quit(1)
