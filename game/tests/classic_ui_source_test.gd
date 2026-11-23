extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var source := CS16VGuiSource.new()
	var team_path := CS16VGuiSource.CSTRIKE_UI + "Teammenu.kv"
	var score_path := CS16VGuiSource.CSTRIKE_UI + "ScoreBoard.kv"
	_check(
		source.control_rect(team_path, "TeamMenu", Rect2()) == Rect2(76, 0, 552, 448),
		"team frame geometry comes from Teammenu.res",
	)
	_check(
		source.control_rect(team_path, "terbutton", Rect2()) == Rect2(0, 116, 148, 20),
		"team button geometry comes from Teammenu.res",
	)
	_check(
		source.control_rect(score_path, "ClientScoreBoard", Rect2()) == Rect2(60, 48, 520, 340),
		"center-relative scoreboard geometry is resolved",
	)
	_check(
		source.scheme_color("BaseText", Color.TRANSPARENT) == Color8(255, 176, 0, 255),
		"ClientScheme BaseText is parsed",
	)
	_check(source.font_size("Default", 480, -1) > 0, "ClientScheme font rules are parsed")
	var default_font := source.font_spec("Default", 480)
	var small_font := source.font_spec("DefaultSmall", 480)
	var underline_font := source.font_spec("DefaultUnderline", 480)
	_check(
		str(default_font.name) == "Verdana" and int(default_font.weight) == 600,
		"Default source font face and weight are parsed",
	)
	_check(int(small_font.weight) == 0, "DefaultSmall preserves source weight 0")
	_check(
		str(underline_font.name) == "Tahoma"
		and int(underline_font.weight) == 500
		and bool(underline_font.underline),
		"DefaultUnderline preserves source face/weight/underline",
	)
	var composited := source.composite_rgba(
		Color(1.0, 0.0, 0.0, 0.5),
		Color(0.0, 0.0, 1.0, 1.0),
	)
	_check(
		is_equal_approx(composited.r, 0.5)
		and is_equal_approx(composited.b, 0.5)
		and is_equal_approx(composited.a, 1.0),
		"source RGBA compositing is deterministic",
	)
	_check(
		not source.localize("#Cstrike_Join_Team", "").is_empty(),
		"App 90 localization is parsed",
	)
	_check(source.menu_entries().size() == 7, "GameMenu source exposes seven visible entries")
	_check(
		source.menu_entries(false, false).size() == 4,
		"GameMenu OnlyInGame visibility contract is parsed",
	)
	var dialog_path := CS16VGuiSource.VALVE_RESOURCE + "DialogOptionsIngame.kv"
	_check(
		source.control_rect(dialog_path, "OptionsDialog", Rect2()) == Rect2(0, 0, 824, 736),
		"DialogOptionsIngame source is parsed",
	)
	var mouse_controls := source.controls_by_tab(
		CS16VGuiSource.VALVE_RESOURCE + "OptionsSubMouse.kv"
	)
	_check(
		not mouse_controls.is_empty()
		and int(mouse_controls[0].tab_position) == 1
		and str(mouse_controls[0].source_control) == "ReverseMouse",
		"option controls preserve source tabPosition ordering",
	)
	var briefing := source.map_briefing("de_dust2")
	_check(
		str(briefing.scenario) == "Bomb/Defuse"
		and str(briefing.body).to_lower().contains("bomb"),
		"de_dust2 source briefing is loaded",
	)
	for portrait in ["terror", "leet", "arctic", "guerilla", "urban", "gsg9", "sas", "gign"]:
		_check(source.asset_texture(portrait) != null, "portrait %s is loadable" % portrait)
	for weapon in ["ak47", "m4a1", "awp", "shield"]:
		_check(source.asset_texture(weapon) != null, "weapon art %s is loadable" % weapon)
	_check(source.menu_texture() != null, "game_menu.tga is loadable")
	var binding_rows := source.key_bindings()
	_check(binding_rows.size() > 60, "App 90 kb_act.lst populates the keyboard action list")
	var has_forward_binding := false
	for binding in binding_rows:
		if str(binding.command) == "+forward":
			has_forward_binding = str(binding.label).to_lower().contains("forward")
			break
	_check(has_forward_binding, "source forward binding label is localized")
	for level in range(1, 5):
		_check(
			source.voice_texture(false, level) != null,
			"source scoreboard speaker level %d is loadable" % level,
		)
	_check(source.voice_texture(true) != null, "source voice-blocked glyph is loadable")
	_check(source.mic_meter_texture(false) != null, "source dead mic meter is loadable")
	_check(source.mic_meter_texture(true) != null, "source live mic meter is loadable")
	source = null
	if failures.is_empty():
		print("CLASSIC_UI_SOURCE_TEST_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("CLASSIC UI SOURCE: %s" % failure)
		print("CLASSIC_UI_SOURCE_TEST_FAIL (%d)" % failures.size())
		quit(1)
