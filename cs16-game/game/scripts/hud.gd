class_name GameHUD
extends CanvasLayer

signal deploy_requested
signal deploy_cancel_requested
## Options > Voice > Test Microphone (handled by the browser voice client).
signal voice_test_requested
signal resume_requested
signal team_selected(team_id: int)
signal class_selected(class_id: int)
signal buy_item_requested(item_id: String)
signal paused_input_received(event: InputEvent)
signal disconnect_requested
signal network_connection_requested(action: String, address: String, port: String)
signal quit_requested
signal menu_command_requested(command: String)
signal ui_sound_requested(sample_path: String)
signal input_contract_changed(state: String, captures_keyboard: bool, mouse_visible: bool)
signal menu_action_requested(action: String, payload: Dictionary)
signal options_apply_requested(values: Dictionary)
signal options_defaults_requested(page: String)
signal options_cancel_requested
signal chat_submitted(text: String, team_only: bool)

# CS 1.6's one fixed HUD colour (RGB 255,160,0) shared by every element —
# health, armor, ammo, timer, money — in every state.
const CLASSIC_ORANGE := Color(1.0, 160.0 / 255.0, 0.0, 1.0)
# Brief brightening used when the account value changes; same hue, more light.
const CLASSIC_ORANGE_BRIGHT := Color(1.0, 208.0 / 255.0, 96.0 / 255.0, 1.0)
const CLASSIC_GREEN := Color("#56c75b")
const CLASSIC_RED := Color("#fa250f")
const CLASSIC_SHADOW := Color(0.0, 0.0, 0.0, 0.92)
# GoldSrc rests HUD sprites near MIN_ALPHA rather than full brightness; drawing
# the additive glyphs at partial intensity keeps them orange over bright
# surfaces instead of saturating to yellow-white.
const CLASSIC_SPRITE_INTENSITY := 0.45
const CLASSIC_HUD_ROOT := "res://assets/hud/classic/"
const RadarDisplayScript := preload("res://scripts/cs16_radar_display.gd")
const KeyBindings := preload("res://scripts/cs16_key_bindings.gd")
const WEB_VGUI_FONT := preload("res://assets/fonts/DejaVuSans.ttf")
const WEB_VGUI_FONT_BOLD := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const KEY_LIST_ROW_HEIGHT := 18.0
const KEY_LIST_HEADER_HEIGHT := 18.0
const NetworkSessionScript := preload("res://scripts/network_session.gd")
const VGUI_AMBER_FALLBACK := Color(1.0, 176.0 / 255.0, 0.0, 1.0)
const VGUI_AMBER_DIM_FALLBACK := Color(188.0 / 255.0, 112.0 / 255.0, 0.0, 1.0)
const VGUI_BLUE_FALLBACK := Color(153.0 / 255.0, 204.0 / 255.0, 1.0, 1.0)
const VGUI_RED_FALLBACK := Color(1.0, 64.0 / 255.0, 64.0 / 255.0, 1.0)
# GameUI (escape) menu text: pale tan resting color that brightens toward
# white, matching the in-game Half-Life GameUI scheme rather than the amber
# cstrike ClientScheme used by gameplay dialogs.
const GAMEUI_MENU_TEXT := Color(216.0 / 255.0, 207.0 / 255.0, 180.0 / 255.0, 1.0)
const GAMEUI_MENU_TEXT_BRIGHT := Color(1.0, 1.0, 1.0, 1.0)
const GAMEUI_MENU_TEXT_DIM := Color(178.0 / 255.0, 166.0 / 255.0, 140.0 / 255.0, 1.0)
# Steam-era GameUI (TrackerScheme) dialog surface: dark olive/grey-green.
const GAMEUI_PANEL := Color(76.0 / 255.0, 88.0 / 255.0, 68.0 / 255.0, 0.94)
const GAMEUI_PANEL_BORDER := Color(56.0 / 255.0, 64.0 / 255.0, 50.0 / 255.0, 1.0)
const VGUI_BASE_SIZE := Vector2(640.0, 480.0)
const SCOREBOARD_COLUMN_WIDTHS := [200, 76, 36, 60, 48, 46, 46]
const VGUI_MENU_ORIGIN := Vector2(76.0, 0.0)
const VGUI_MENU_SIZE := Vector2(552.0, 448.0)
# One uniform row metric for every buy list: CS 1.6 keeps a single font and a
# fixed right-aligned price column instead of shrinking long rows.
const BUY_ROW_WIDTH := 202.0
const BUY_PRICE_COLUMN_WIDTH := 40.0
const BUY_ROW_FONT_SIZE := 10
const CHAT_MAX_ROWS := 6
const CHAT_ROW_SECONDS := 8.0
const CHAT_MAX_LENGTH := 120

const TEAM_MENU_ITEMS := [
	["1", "TERRORIST FORCES", 1, "terbutton"],
	["2", "CT FORCES", 2, "ctbutton"],
	["5", "AUTO-SELECT", 5, "autobutton"],
	["6", "SPECTATE", 6, "specbutton"],
]
const TERRORIST_CLASSES := [
	["1", "PHOENIX CONNEXION", "terror", "terror"],
	["2", "L337 KREW", "leet", "leet"],
	["3", "ARCTIC AVENGERS", "arctic", "arctic"],
	["4", "GUERILLA WARFARE", "guerilla", "guerilla"],
	["5", "AUTO-SELECT", "t_random", "autoselect_t"],
]
const CT_CLASSES := [
	["1", "SEAL TEAM 6", "urban", "urban"],
	["2", "GSG-9", "gsg9", "gsg9"],
	["3", "SAS", "sas", "sas"],
	["4", "GIGN", "gign", "gign"],
	["5", "AUTO-SELECT", "ct_random", "autoselect_ct"],
]
const BUY_CATEGORIES := [
	["1", "PISTOLS", "pistols"],
	["2", "SHOTGUNS", "shotguns"],
	["3", "SUB-MACHINE GUNS", "smg"],
	["4", "RIFLES", "rifles"],
	["5", "MACHINE GUNS", "machineguns"],
	["6", "PRIMARY WEAPON AMMO", "primary_ammo"],
	["7", "SECONDARY WEAPON AMMO", "secondary_ammo"],
	["8", "EQUIPMENT", "equipment"],
]
const BUY_DEFINITIONS := {
	"glock18": ["9X19MM SIDEARM", 400, "glock18"],
	"usp": ["KM .45 TACTICAL", 500, "usp45"],
	"p228": ["228 COMPACT", 600, "p228"],
	"deagle": ["NIGHT HAWK .50C", 650, "deserteagle"],
	"elites": [".40 DUAL ELITES", 800, "elites"],
	"fiveseven": ["ES FIVE-SEVEN", 750, "fiveseven"],
	"m3": ["LEONE 12 GAUGE SUPER", 1700, "m3"],
	"xm1014": ["LEONE YG1265 AUTO", 3000, "xm1014"],
	"mac10": ["INGRAM MAC-10", 1400, "mac10"],
	"tmp": ["SCHMIDT MACHINE PISTOL", 1250, "tmp"],
	"mp5": ["KM SUB-MACHINE GUN", 1500, "mp5"],
	"ump45": ["KM UMP45", 1700, "ump45"],
	"p90": ["ES C90", 2350, "p90"],
	"galil": ["IDF DEFENDER", 2000, "galil"],
	"ak47": ["CV-47", 2500, "ak47"],
	"scout": ["SCHMIDT SCOUT", 2750, "scout"],
	"sg552": ["KRIEG 552", 3500, "sg552"],
	"awp": ["MAGNUM SNIPER RIFLE", 4750, "awp"],
	"g3sg1": ["D3/AU-1", 5000, "g3sg1"],
	"famas": ["CLARION 5.56", 2250, "famas"],
	"m4a1": ["MAVERICK M4A1 CARBINE", 3100, "m4a1"],
	"aug": ["BULLPUP", 3500, "aug"],
	"sg550": ["KRIEG 550 COMMANDO", 4200, "sg550"],
	"m249": ["M249", 5750, "m249"],
	"vest": ["KEVLAR", 650, "kevlar"],
	"vesthelm": ["KEVLAR + HELMET", 1000, "kevlar_helmet"],
	"flash": ["FLASHBANG", 200, "flashbang"],
	"hegren": ["HE GRENADE", 300, "hegrenade"],
	"sgren": ["SMOKE GRENADE", 300, "smokegrenade"],
	"nvgs": ["NIGHTVISION", 1250, "nightvision"],
	"defuser": ["DEFUSAL KIT", 200, "defuser"],
	# The Tactical Shield is intentionally not offered. A faithful shield needs a
	# world/view model, directional damage blocking, the 180 ups carry speed cap
	# and its primary-weapon restrictions; none of that exists yet, so listing it
	# would only take $2200 for nothing. It is also absent from the competitive
	# 1.6 play this project targets. Source rows whose command is missing here are
	# skipped by _source_buy_items, so the equipment page simply omits it.
	"primammo": ["PRIMARY AMMO", 60, ""],
	"secammo": ["SECONDARY AMMO", 40, ""],
}
# CS 1.6 draws the active weapon's caliber sprite (each weapon_*.txt "ammo"
# atlas region) to the right of the reserve counter. Keys are the classic
# HUD-facing weapon display names emitted by the weapon registry.
const AMMO_ICONS := {
	"228 COMPACT": "ammo_p228",
	"SCHMIDT SCOUT": "ammo_scout",
	"HE GRENADE": "ammo_hegrenade",
	"LEONE YG1265 AUTO SHOTGUN": "ammo_xm1014",
	"C4 EXPLOSIVE": "ammo_c4",
	"INGRAM MAC-10": "ammo_mac10",
	"BULLPUP": "ammo_aug",
	"SMOKE GRENADE": "ammo_smokegrenade",
	"ELITE": "ammo_elite",
	"ES FIVE-SEVEN": "ammo_fiveseven",
	"KM UMP45": "ammo_ump45",
	"KRIEG 550 COMMANDO": "ammo_sg550",
	"IDF DEFENDER": "ammo_galil",
	"CLARION 5.56": "ammo_famas",
	"KM .45 TACTICAL": "ammo_usp",
	"9X19MM SIDEARM": "ammo_glock18",
	"MAGNUM SNIPER RIFLE": "ammo_awp",
	"KM SUB-MACHINE GUN": "ammo_mp5navy",
	"ES M249 PARA": "ammo_m249",
	"LEONE 12 GAUGE SUPER": "ammo_m3",
	"MAVERICK M4A1 CARBINE": "ammo_m4a1",
	"SCHMIDT MACHINE PISTOL": "ammo_tmp",
	"D3/AU-1": "ammo_g3sg1",
	"FLASHBANG": "ammo_flashbang",
	"DESERT EAGLE": "ammo_deagle",
	"KRIEG 552": "ammo_sg552",
	"AK-47": "ammo_ak47",
	"ES C90": "ammo_p90",
}

var health_label: Label
var armor_label: Label
var ammo_label: Label
var reserve_label: Label
var timer_label: Label
var round_label: Label
var objective_label: Label
var status_label: Label
var spectate_label: Label
var money_label: Label
var banner_label: Label
var deploy_overlay: Control
var pause_overlay: Control
var buy_overlay: Control
var scoreboard_overlay: Control
var deploy_canvas: Control
var pause_canvas: Control
var buy_canvas: Control
var scoreboard_canvas: Control
var team_menu: Control
var class_menu: Control
var class_portrait: TextureRect
var class_portrait_label: Label
var team_briefing_scroll: ScrollContainer
var buy_menu_frame: Control
var buy_list_panel: Control
var buy_item_panel: Control
var buy_portrait: TextureRect
var buy_description: Label
var scoreboard_rows: VBoxContainer
var pause_main_menu: Control
var pause_options_menu: Control
var network_menu: Control
var network_address: LineEdit
var network_port: LineEdit
var network_status: Label
var network_connect_button: Button
var _network_menu_action := "join"
var _network_online := false
var _network_client := false
var _pause_return_state := "none"
var options_tab_bar: HBoxContainer
var options_pages: Control
var accessibility_overlay: Control
var damage_flash: ColorRect
var nightvision_overlay: ColorRect
var flash_blind_overlay: ColorRect
var _flash_blind_tween: Tween
var hitmarker: Control
var crosshair: Control
var radar_display: CS16RadarDisplay
var kill_feed_box: VBoxContainer
var _kill_feed_icons := {}
var chat_feed_box: VBoxContainer
## Players currently talking on voice (1.6 speaker list, right side).
var voice_talkers_box: VBoxContainer
var _voice_talker_signature := ""
var chat_input_panel: Panel
var chat_prompt_label: Label
var chat_entry: LineEdit
var _chat_team_only := false
var hostage_status_group: HBoxContainer
var _banner_generation := 0
var _banner_tween: Tween
var _objective_tween: Tween
var _damage_tween: Tween
var settings: Node
var _weapon_name := "AK-47"
var _fire_mode := "FULL AUTO"
var health_digits: HBoxContainer
var armor_digits: HBoxContainer
var ammo_digits: HBoxContainer
var reserve_digits: HBoxContainer
var timer_digits: HBoxContainer
var money_digits: HBoxContainer
var _flow_canvases: Array[Control] = []
var _selected_team := 1
var _buy_team := 1
var _buy_money := 800
var _buy_category := "rifles"
var _buy_context: Dictionary = {}
var _buy_navigation_level := "category"
var _buy_items: Array = []
var _menu_state := "none"
var _gameplay_controls: Array[Control] = []
var _participant_controls: Array[Control] = []
var _spectating := false
var _spectator_first_person := false
var vgui_source: CS16VGuiSource
var vgui_amber := VGUI_AMBER_FALLBACK
var vgui_amber_dim := VGUI_AMBER_DIM_FALLBACK
var vgui_blue := VGUI_BLUE_FALLBACK
var vgui_red := VGUI_RED_FALLBACK
var _vgui_font: Font
var _vgui_fonts: Dictionary = {}
var _options_snapshot: Dictionary = {}
var _options_pending: Dictionary = {}
var _options_page_key := "multiplayer"
var _hud_additive_material: CanvasItemMaterial
var _money_sign: TextureRect
var _armor_icon: TextureRect
var _ammo_icon: TextureRect
var _buyzone_icon: TextureRect
var _defuse_kit_icon: TextureRect
var _c4_icon: TextureRect
var _crosshair_preview: Control
var _key_list: VBoxContainer
var _key_selected_command := ""
var _key_capture_command := ""
var _c4_flash: Tween
var _carrying_c4 := false
var _c4_in_bomb_zone := false
var defuse_progress_bar: Control
var _defuse_progress_fill: ColorRect
var _has_defuse_kit := false
var _defuse_progress_active := false
var _has_helmet := false
var _in_buy_zone := false
var buy_menu_generation := 0
var _last_money := -2147483648
var _money_flash_generation := 0
var money_delta: HBoxContainer
var money_delta_digits: HBoxContainer
var money_delta_amount := 0
var _money_delta_sign: TextureRect
var _money_delta_dollar: TextureRect
var _money_delta_tween: Tween
var _objective_text := ""
var _objective_generation := 0
var _crosshair_spread_px := 0


func _classic_additive_material() -> CanvasItemMaterial:
	# GoldSrc renders every 640hud7 glyph additively (SPR_DrawAdditive);
	# reproducing that blend keeps the sprites' dim fills/bright edges correct.
	if _hud_additive_material == null:
		_hud_additive_material = CanvasItemMaterial.new()
		_hud_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _hud_additive_material


func _classic_sprite(sprite_name: String, color: Color, additive := true) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.name = "Sprite_%s" % sprite_name
	var texture := load(CLASSIC_HUD_ROOT.path_join("%s.png" % sprite_name)) as Texture2D
	if texture == null:
		push_error("Missing classic HUD sprite: %s" % sprite_name)
	else:
		sprite.texture = texture
		sprite.custom_minimum_size = texture.get_size()
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	# GoldSrc's GL renderer samples HUD sprites with GL_LINEAR; nearest-neighbor
	# at the non-integer 1024/1280 HUD scales chews ragged notches into the
	# digit edges that the original never shows.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if additive:
		sprite.material = _classic_additive_material()
		# Rest additive glyphs below full brightness (GoldSrc FadeThink decays
		# toward MIN_ALPHA); modulate alpha scales the additive contribution.
		sprite.modulate = _classic_sprite_modulate(color)
	else:
		sprite.modulate = color
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.set_meta("classic_sprite", sprite_name)
	return sprite


func _classic_sprite_modulate(color: Color) -> Color:
	# Every classic sprite in one HUD element must carry the same additive
	# intensity; writing a raw full-alpha modulate onto one glyph (for example
	# the dollar sign) renders it visibly brighter than its sibling digits.
	return Color(color.r, color.g, color.b, color.a * CLASSIC_SPRITE_INTENSITY)


func _digit_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("uses_original_digits", true)
	return row


func _colon(color: Color) -> VBoxContainer:
	var colon := VBoxContainer.new()
	colon.name = "TimerColon"
	colon.custom_minimum_size = Vector2(9, 25)
	colon.alignment = BoxContainer.ALIGNMENT_CENTER
	colon.add_theme_constant_override("separation", 7)
	colon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(2):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(4, 4)
		dot.color = Color(color.r, color.g, color.b, color.a * CLASSIC_SPRITE_INTENSITY)
		dot.material = _classic_additive_material()
		dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		colon.add_child(dot)
	return colon


func _set_digit_row(
	row: HBoxContainer,
	value: String,
	color: Color,
	minimum_digits := 0,
) -> void:
	var cache_key := "%s:%s:%d" % [value, color.to_html(), minimum_digits]
	if str(row.get_meta("cache_key", "")) == cache_key:
		return
	for child in row.get_children():
		child.free()
	var digit_count := 0
	for character in value:
		if str(character).is_valid_int():
			digit_count += 1
	for index in range(maxi(0, minimum_digits - digit_count)):
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(20, 25)
		blank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(blank)
	for character in value:
		var glyph := str(character)
		if glyph.is_valid_int():
			row.add_child(_classic_sprite("number_%s" % glyph, color))
		elif glyph == ":":
			row.add_child(_colon(color))
	row.set_meta("cache_key", cache_key)


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = get_node("/root/GameSettings")
	vgui_source = CS16VGuiSource.new()
	vgui_amber = vgui_source.scheme_color("BaseText", VGUI_AMBER_FALLBACK)
	vgui_amber_dim = vgui_source.scheme_color("DimListText", VGUI_AMBER_DIM_FALLBACK)
	vgui_blue = vgui_source.scheme_color("team2", VGUI_BLUE_FALLBACK)
	vgui_red = vgui_source.scheme_color("team1", VGUI_RED_FALLBACK)
	_vgui_font = _font_for_rule("Default")
	# The finite atlas is loaded before combat, never from incoming weapon paths.
	for sprite: String in ["knife", "ak47", "awp", "deagle", "famas", "fiveseven", "flashbang", "g3sg1", "galil", "glock18", "grenade", "m249", "m3", "m4a1", "mp5navy", "p228", "p90", "scout", "sg550", "sg552", "ump45", "usp", "tmp", "xm1014", "skull", "tracktrain", "aug", "mac10", "elite", "headshot"]:
		_kill_feed_icons[sprite] = load("res://assets/hud/death/d_%s.png" % sprite)
	_build_hud()
	settings.changed.connect(_apply_accessibility)
	_apply_accessibility()


func _build_hud() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Nightvision tints and brightens the world beneath every HUD element, so
	# it is built first and stays the bottom-most child of the HUD root.
	nightvision_overlay = ColorRect.new()
	nightvision_overlay.name = "NightvisionOverlay"
	nightvision_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Additive green: CS 1.6's NVG amplifies light rather than veiling the
	# screen, so dark corners become readable instead of merely greener.
	nightvision_overlay.color = Color(0.04, 0.26, 0.05, 1.0)
	var nightvision_material := CanvasItemMaterial.new()
	nightvision_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	nightvision_overlay.material = nightvision_material
	nightvision_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nightvision_overlay.visible = false
	root.add_child(nightvision_overlay)

	# The CS 1.6 radar is a square translucent dark green-blue panel the world
	# stays visible through — GoldSrc draws it dim, with plain blips and a small
	# center mark drawn live by the contact layer above.
	var radar := _classic_sprite("radar", Color.WHITE, false)
	radar.texture = _classic_radar_texture(radar.texture)
	radar.name = "ClassicRadar"
	radar.position = Vector2(18, 18)
	radar.size = Vector2(128, 128)
	root.add_child(radar)

	radar_display = RadarDisplayScript.new()
	radar_display.name = "ClassicRadarContacts"
	radar_display.position = Vector2(18, 18)
	radar_display.size = Vector2(128, 128)
	root.add_child(radar_display)

	# CS 1.6 death notices: top-right rows of "Killer (weapon) Victim" with
	# team-colored names, newest at the bottom, fading out after a few seconds.
	kill_feed_box = VBoxContainer.new()
	kill_feed_box.name = "ClassicKillFeed"
	kill_feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_feed_box.offset_left = -460.0
	kill_feed_box.offset_right = -14.0
	kill_feed_box.offset_top = 12.0
	kill_feed_box.offset_bottom = 160.0
	kill_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	kill_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(kill_feed_box)
	voice_talkers_box = VBoxContainer.new()
	voice_talkers_box.name = "ClassicVoiceTalkers"
	voice_talkers_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	voice_talkers_box.offset_left = -260.0
	voice_talkers_box.offset_right = -14.0
	voice_talkers_box.offset_top = 172.0
	voice_talkers_box.offset_bottom = 340.0
	voice_talkers_box.add_theme_constant_override("separation", 2)
	voice_talkers_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(voice_talkers_box)
	_build_chat(root)

	hostage_status_group = HBoxContainer.new()
	hostage_status_group.name = "ClassicHostageStatus"
	hostage_status_group.position = Vector2(18, 148)
	hostage_status_group.size = Vector2(128, 32)
	hostage_status_group.add_theme_constant_override("separation", 0)
	hostage_status_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hostage_status_group)

	# CS 1.6 draws the account on the right side above the ammo counter in
	# resting HUD orange; it only flashes green on gain and red on loss.
	money_label = _label("$800", 1, CLASSIC_ORANGE)
	var money_group := HBoxContainer.new()
	money_group.name = "ClassicMoney"
	money_group.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	money_group.position = Vector2(-204, -112)
	money_group.size = Vector2(180, 34)
	money_group.alignment = BoxContainer.ALIGNMENT_END
	money_group.add_theme_constant_override("separation", 2)
	money_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(money_group)
	_money_sign = _classic_sprite("dollar", CLASSIC_ORANGE)
	money_group.add_child(_money_sign)
	money_digits = _digit_row()
	money_group.add_child(money_digits)
	_set_digit_row(money_digits, "800", CLASSIC_ORANGE)
	money_label.name = "Money"
	money_label.visible = false
	root.add_child(money_label)
	money_delta = HBoxContainer.new()
	money_delta.name = "ClassicMoneyDelta"
	money_delta.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	money_delta.position = Vector2(-224, -146)
	money_delta.size = Vector2(200, 28)
	money_delta.alignment = BoxContainer.ALIGNMENT_END
	money_delta.add_theme_constant_override("separation", 2)
	money_delta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_delta.modulate.a = 0.0
	root.add_child(money_delta)
	_money_delta_sign = _classic_sprite("plus", CLASSIC_GREEN)
	_money_delta_dollar = _classic_sprite("dollar", CLASSIC_GREEN)
	money_delta_digits = _digit_row()
	money_delta.add_child(_money_delta_sign)
	money_delta.add_child(_money_delta_dollar)
	money_delta.add_child(money_delta_digits)

	var health_group := HBoxContainer.new()
	health_group.name = "ClassicVitals"
	health_group.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_group.position = Vector2(24, -67)
	health_group.size = Vector2(360, 48)
	health_group.add_theme_constant_override("separation", 2)
	health_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(health_group)
	health_group.add_child(_classic_sprite("cross", CLASSIC_ORANGE))
	health_label = _label("100", 1, CLASSIC_ORANGE)
	health_label.name = "Health"
	health_label.visible = false
	root.add_child(health_label)
	health_digits = _digit_row()
	health_group.add_child(health_digits)
	_set_digit_row(health_digits, "100", CLASSIC_ORANGE, 3)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 12
	health_group.add_child(spacer)
	# CS 1.6 swaps this vest sprite for the vest+helmet variant while a
	# helmet is owned (see update_health).
	_armor_icon = _classic_sprite("suit_full", CLASSIC_ORANGE)
	health_group.add_child(_armor_icon)
	armor_label = _label("100", 1, CLASSIC_ORANGE)
	armor_label.name = "Armor"
	armor_label.visible = false
	root.add_child(armor_label)
	armor_digits = _digit_row()
	health_group.add_child(armor_digits)
	_set_digit_row(armor_digits, "100", CLASSIC_ORANGE, 3)

	var ammo_group := HBoxContainer.new()
	ammo_group.name = "ClassicAmmo"
	ammo_group.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_group.position = Vector2(-277, -67)
	ammo_group.size = Vector2(253, 48)
	ammo_group.alignment = BoxContainer.ALIGNMENT_END
	ammo_group.add_theme_constant_override("separation", 9)
	ammo_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ammo_group)
	ammo_label = _label("30", 1, CLASSIC_ORANGE)
	ammo_label.name = "Clip"
	ammo_label.visible = false
	root.add_child(ammo_label)
	reserve_label = _label("90", 1, CLASSIC_ORANGE)
	reserve_label.name = "Reserve"
	reserve_label.visible = false
	root.add_child(reserve_label)
	ammo_digits = _digit_row()
	ammo_group.add_child(ammo_digits)
	_set_digit_row(ammo_digits, "30", CLASSIC_ORANGE, 3)
	ammo_group.add_child(_classic_sprite("divider", CLASSIC_ORANGE))
	reserve_digits = _digit_row()
	ammo_group.add_child(reserve_digits)
	_set_digit_row(reserve_digits, "90", CLASSIC_ORANGE, 3)
	# The caliber-specific ammo sprite always follows the reserve count.
	_ammo_icon = _classic_sprite("ammo_ak47", CLASSIC_ORANGE)
	_ammo_icon.name = "AmmoTypeIcon"
	ammo_group.add_child(_ammo_icon)

	var timer_group := HBoxContainer.new()
	timer_group.name = "ClassicTimer"
	timer_group.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	timer_group.position = Vector2(-72, -67)
	timer_group.size = Vector2(144, 44)
	timer_group.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_group.add_theme_constant_override("separation", 7)
	timer_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(timer_group)
	timer_group.add_child(_classic_sprite("stopwatch", CLASSIC_ORANGE))
	timer_label = _label("1:30", 1, CLASSIC_ORANGE)
	timer_label.name = "RoundTimer"
	timer_label.visible = false
	root.add_child(timer_label)
	timer_digits = _digit_row()
	timer_group.add_child(timer_digits)
	_set_digit_row(timer_digits, "1:30", CLASSIC_ORANGE)

	# CS 1.6 pins the buyzone sprite (640hud7's cart glyph) against the left
	# screen edge, vertically centered, whenever the player can open the buy
	# menu (in a buy zone during buy time).
	_buyzone_icon = _classic_sprite("buyzone", CLASSIC_ORANGE)
	_buyzone_icon.name = "ClassicBuyZone"
	_buyzone_icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_buyzone_icon.position = Vector2(2, -16)
	_buyzone_icon.size = Vector2(32, 32)
	_buyzone_icon.visible = false
	root.add_child(_buyzone_icon)
	_defuse_kit_icon = _classic_sprite("defuser", Color("#00a000"))
	_defuse_kit_icon.name = "ClassicDefuseKit"
	_defuse_kit_icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_defuse_kit_icon.position = Vector2(2, -16)
	_defuse_kit_icon.size = Vector2(32, 32)
	_defuse_kit_icon.visible = false
	root.add_child(_defuse_kit_icon)
	# The bomb carrier's status icon (640hud7 "c4"), drawn in the kit's slot:
	# a Terrorist never holds a defusal kit. It flashes inside a bomb site.
	_c4_icon = _classic_sprite("c4", Color("#00a000"))
	_c4_icon.name = "ClassicC4"
	_c4_icon.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_c4_icon.position = Vector2(2, -16)
	_c4_icon.size = Vector2(32, 32)
	_c4_icon.visible = false
	root.add_child(_c4_icon)

	status_label = _classic_label("", 17, CLASSIC_ORANGE)
	status_label.name = "ObjectiveStatus"
	status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.position = Vector2(-260, -107)
	status_label.size = Vector2(520, 30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

	# GoldSrc's BarTime presentation is deliberately plain: a dark rectangular
	# track and a green fill near the lower middle of the view. It appears only
	# for the CT currently performing the authoritative defuse.
	defuse_progress_bar = Control.new()
	defuse_progress_bar.name = "ClassicDefuseProgress"
	defuse_progress_bar.set_anchors_preset(Control.PRESET_CENTER)
	defuse_progress_bar.position = Vector2(-100, 72)
	defuse_progress_bar.size = Vector2(200, 12)
	defuse_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	defuse_progress_bar.visible = false
	root.add_child(defuse_progress_bar)
	var progress_track := Panel.new()
	progress_track.name = "Track"
	progress_track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_style := StyleBoxFlat.new()
	track_style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	track_style.border_color = Color(0.55, 0.55, 0.55, 0.9)
	track_style.set_border_width_all(1)
	progress_track.add_theme_stylebox_override("panel", track_style)
	defuse_progress_bar.add_child(progress_track)
	_defuse_progress_fill = ColorRect.new()
	_defuse_progress_fill.name = "Fill"
	_defuse_progress_fill.position = Vector2(2, 2)
	_defuse_progress_fill.size = Vector2(0, 8)
	_defuse_progress_fill.color = CLASSIC_GREEN
	_defuse_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	defuse_progress_bar.add_child(_defuse_progress_fill)

	spectate_label = _classic_label("", 17, CLASSIC_ORANGE)
	spectate_label.name = "ClassicSpectate"
	spectate_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spectate_label.position = Vector2(-260, -72)
	spectate_label.size = Vector2(520, 26)
	spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spectate_label.visible = false
	root.add_child(spectate_label)

	# CS 1.6 exposes round and team scores on the scoreboard rather than in a
	# persistent top-center match card. Keep state labels for the existing API,
	# but intentionally do not add them to the visual tree.
	round_label = _classic_label("ROUND 01", 16, CLASSIC_ORANGE)
	round_label.name = "RoundStateAPI"
	round_label.visible = false
	root.add_child(round_label)
	objective_label = _classic_label("0 / 5", 16, CLASSIC_ORANGE)
	objective_label.name = "ObjectiveStateAPI"
	objective_label.visible = false
	root.add_child(objective_label)

	banner_label = _classic_label("", 24, CLASSIC_ORANGE)
	banner_label.name = "ClassicAnnouncement"
	banner_label.set_anchors_preset(Control.PRESET_CENTER)
	banner_label.position = Vector2(-310, -115)
	banner_label.size = Vector2(620, 44)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.modulate.a = 0.0
	root.add_child(banner_label)

	_build_crosshair(root)
	_build_damage_flash(root)
	for control_name in [
		"ClassicRadar",
		"ClassicRadarContacts",
		"ClassicHostageStatus",
		"ClassicMoney",
		"ClassicMoneyDelta",
		"ClassicVitals",
		"ClassicTimer",
		"ClassicAmmo",
		"ClassicDefuseProgress",
		"ObjectiveStatus",
		"ClassicSpectate",
		"ClassicAnnouncement",
		"Crosshair",
		"DamageVignette",
	]:
		var gameplay_control := root.get_node_or_null(control_name) as Control
		if gameplay_control != null:
			_gameplay_controls.append(gameplay_control)
			if control_name in ["ClassicRadar", "ClassicRadarContacts", "ClassicHostageStatus",
				"ClassicMoney", "ClassicMoneyDelta", "ClassicVitals", "ClassicAmmo", "Crosshair", "DamageVignette"]:
				_participant_controls.append(gameplay_control)
	_build_deploy_overlay(root)
	_build_buy_overlay(root)
	_build_scoreboard_overlay(root)
	_build_pause_overlay(root)
	root.resized.connect(func() -> void: layout_for_viewport(root.size))
	layout_for_viewport(root.size)
	_refresh_gameplay_visibility()


func _build_chat(root: Control) -> void:
	chat_feed_box = VBoxContainer.new()
	chat_feed_box.name = "ClassicChatFeed"
	chat_feed_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_feed_box.offset_left = 18.0
	chat_feed_box.offset_top = -238.0
	chat_feed_box.offset_right = 622.0
	chat_feed_box.offset_bottom = -86.0
	chat_feed_box.alignment = BoxContainer.ALIGNMENT_END
	chat_feed_box.add_theme_constant_override("separation", 1)
	chat_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chat_feed_box)

	chat_input_panel = Panel.new()
	chat_input_panel.name = "ClassicChatInput"
	chat_input_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	chat_input_panel.offset_left = 18.0
	chat_input_panel.offset_top = -78.0
	chat_input_panel.offset_right = 622.0
	chat_input_panel.offset_bottom = -46.0
	chat_input_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	input_style.border_color = Color(CLASSIC_ORANGE, 0.58)
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(0)
	chat_input_panel.add_theme_stylebox_override("panel", input_style)
	chat_input_panel.visible = false
	root.add_child(chat_input_panel)

	chat_prompt_label = _classic_label("Say:", 14, CLASSIC_ORANGE)
	chat_prompt_label.name = "Prompt"
	chat_prompt_label.position = Vector2(8, 2)
	chat_prompt_label.size = Vector2(78, 28)
	chat_input_panel.add_child(chat_prompt_label)

	chat_entry = LineEdit.new()
	chat_entry.name = "Entry"
	chat_entry.position = Vector2(84, 2)
	chat_entry.size = Vector2(510, 28)
	chat_entry.max_length = CHAT_MAX_LENGTH
	chat_entry.context_menu_enabled = false
	chat_entry.virtual_keyboard_enabled = false
	chat_entry.caret_blink = true
	chat_entry.add_theme_font_size_override("font_size", 14)
	chat_entry.add_theme_color_override("font_color", Color("#f2d6aa"))
	chat_entry.add_theme_color_override("caret_color", CLASSIC_ORANGE_BRIGHT)
	chat_entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	chat_entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if _vgui_font != null:
		chat_entry.add_theme_font_override("font", _vgui_font)
	chat_entry.text_submitted.connect(_submit_chat_entry)
	chat_entry.gui_input.connect(_on_chat_entry_gui_input)
	chat_input_panel.add_child(chat_entry)


func open_chat(team_only: bool) -> bool:
	if _menu_state not in ["none", "scoreboard"] or not is_instance_valid(chat_entry):
		return false
	if _menu_state == "scoreboard":
		set_scoreboard_visible(false)
	_chat_team_only = team_only
	chat_prompt_label.text = "Say (TEAM):" if team_only else "Say:"
	chat_prompt_label.size.x = 102.0 if team_only else 78.0
	chat_entry.position.x = 108.0 if team_only else 84.0
	chat_entry.size.x = 486.0 if team_only else 510.0
	chat_entry.clear()
	chat_input_panel.visible = true
	_set_menu_state("chat")
	chat_entry.grab_focus()
	return true


func close_chat() -> void:
	if not is_instance_valid(chat_input_panel):
		return
	chat_input_panel.visible = false
	chat_entry.clear()
	chat_entry.release_focus()
	if _menu_state == "chat":
		_set_menu_state("none")


func _submit_chat_entry(value: String) -> void:
	var text := value.strip_edges()
	var team_only := _chat_team_only
	close_chat()
	if not text.is_empty():
		chat_submitted.emit(text, team_only)


func _on_chat_entry_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_chat()
		chat_entry.accept_event()


## talkers: [{"id", "name", "team"}] for everyone currently speaking.
func update_voice_talkers(talkers: Array) -> void:
	if not is_instance_valid(voice_talkers_box):
		return
	var signature := JSON.stringify(talkers)
	if signature == _voice_talker_signature:
		return
	_voice_talker_signature = signature
	for child in voice_talkers_box.get_children():
		child.queue_free()
	var speaker: Texture2D = load("res://assets/ui/classic/voice/640_speaker3.tga") as Texture2D
	for talker: Dictionary in talkers:
		var row := HBoxContainer.new()
		row.name = "Talker_%s" % str(talker.get("id", "")).validate_node_name()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta("voice_id", str(talker.get("id", "")))
		var name_label := Label.new()
		name_label.text = str(talker.get("name", ""))
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(_kill_feed_team_hex(str(talker.get("team", "")))))
		name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_label)
		var icon := TextureRect.new()
		icon.texture = speaker
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		voice_talkers_box.add_child(row)


func add_chat_message(message: Dictionary) -> void:
	if not is_instance_valid(chat_feed_box):
		return
	var sender_name := str(message.get("sender_name", "Player")).replace("\n", " ").left(32)
	var text := str(message.get("text", "")).replace("\n", " ").strip_edges().left(CHAT_MAX_LENGTH)
	if text.is_empty():
		return
	var row := _new_chat_row()
	if bool(message.get("team_only", false)):
		row.push_color(CLASSIC_GREEN)
		row.add_text("(TEAM) ")
		row.pop()
	row.push_color(Color(_kill_feed_team_hex(str(message.get("team", "UNASSIGNED")))))
	row.add_text(sender_name)
	row.pop()
	row.push_color(Color("#f2d6aa"))
	row.add_text(" :  " + text)
	row.pop()
	_push_chat_row(row)


## Server notices in the chat area, worded as CS 1.6's #Game_connected and
## #Game_disconnected ("<name> has joined the game").
func add_notice(message: Dictionary) -> void:
	if not is_instance_valid(chat_feed_box):
		return
	var player_name := str(message.get("name", "")).replace("\n", " ").left(32)
	var wording := {"joined": " has joined the game", "left": " has left the game"}
	if player_name.is_empty() or not wording.has(str(message.get("kind", ""))):
		return
	var row := _new_chat_row()
	row.name = "NoticeRow"
	row.push_color(Color("#f2d6aa"))
	row.add_text(player_name + str(wording[str(message.kind)]))
	row.pop()
	_push_chat_row(row)


func _new_chat_row() -> RichTextLabel:
	var row := RichTextLabel.new()
	row.name = "ChatRow"
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(584, 18)
	if _vgui_font != null:
		row.add_theme_font_override("normal_font", _vgui_font)
	row.add_theme_font_size_override("normal_font_size", 14)
	row.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	row.add_theme_constant_override("shadow_offset_x", 1)
	row.add_theme_constant_override("shadow_offset_y", 1)
	return row


func _push_chat_row(row: RichTextLabel) -> void:
	chat_feed_box.add_child(row, true)  # readable names: ChatRow2, NoticeRow2
	while chat_feed_box.get_child_count() > CHAT_MAX_ROWS:
		var oldest := chat_feed_box.get_child(0)
		chat_feed_box.remove_child(oldest)
		oldest.queue_free()
	get_tree().create_timer(CHAT_ROW_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(row):
			row.queue_free()
	)


func _build_crosshair(root: Control) -> void:
	# CS 1.6 draws 1px crosshair segments pixel-symmetric around the center
	# pixel: equal 9px arms with a 3px gap on every side, no drop shadows.
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	_update_crosshair_scale()

	# A hit-confirm X was added by this project, but CS 1.6 never draws one.
	# Preserve the node/API for gameplay callers and tests while rendering none.
	hitmarker = Control.new()
	hitmarker.name = "Hitmarker"
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.position = Vector2(-20, -20)
	hitmarker.size = Vector2(40, 40)
	hitmarker.modulate.a = 0.0
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hitmarker)


func _build_damage_flash(root: Control) -> void:
	damage_flash = ColorRect.new()
	damage_flash.name = "DamageVignette"
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_flash.color = Color(0.72, 0.03, 0.02, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_flash)
	flash_blind_overlay = ColorRect.new()
	flash_blind_overlay.name = "FlashBlindOverlay"
	flash_blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_blind_overlay.color = Color(1.0, 1.0, 1.0, 0.0)
	flash_blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_blind_overlay)


func set_nightvision(active: bool) -> void:
	if is_instance_valid(nightvision_overlay):
		nightvision_overlay.visible = active


func show_flash_blind(seconds: float) -> void:
	# CS 1.6 flashbang: solid white hold, then a long linear fade.
	if not is_instance_valid(flash_blind_overlay):
		return
	if _flash_blind_tween != null and _flash_blind_tween.is_valid():
		_flash_blind_tween.kill()
	flash_blind_overlay.color.a = 1.0
	_flash_blind_tween = create_tween()
	_flash_blind_tween.tween_interval(seconds * 0.45)
	_flash_blind_tween.tween_property(
		flash_blind_overlay, "color:a", 0.0, seconds * 0.55,
	)


func set_network_flash(total: float, remaining: float) -> void:
	if _flash_blind_tween != null and _flash_blind_tween.is_valid():
		_flash_blind_tween.kill()
	flash_blind_overlay.color.a = clampf(remaining / maxf(total * 0.55, 0.001), 0.0, 1.0)


func _build_deploy_overlay(root: Control) -> void:
	deploy_overlay = ColorRect.new()
	deploy_overlay.name = "DeployOverlay"
	deploy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deploy_overlay.color = Color(0.0, 0.0, 0.0, 0.50)
	deploy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(deploy_overlay)
	deploy_canvas = _make_flow_canvas(deploy_overlay, "DeployFlowCanvas")
	_build_team_menu()
	_build_class_menu()
	show_team_menu()


func _build_team_menu() -> void:
	var source_path := CS16VGuiSource.CSTRIKE_UI + "Teammenu.kv"
	team_menu = _vgui_frame(deploy_canvas, "TeamMenu", source_path, "TeamMenu")
	var title_rect := _relative_source_rect(
		source_path,
		"joinTeam",
		Rect2(0, 22, 500, 48),
		team_menu.position,
	)
	_vgui_label(
		team_menu,
		"JoinTeamTitle",
		vgui_source.localize("#Cstrike_Join_Team", "SELECT TEAM"),
		title_rect.position,
		title_rect.size,
		_source_font_size("Title", 22),
		vgui_amber,
		false,
		"Title",
	)
	var map_rect := _relative_source_rect(
		source_path,
		"mapname",
		Rect2(168, 82, 180, 24),
		team_menu.position,
	)
	_vgui_label(
		team_menu,
		"MapName",
		"",
		map_rect.position,
		map_rect.size,
		_source_font_size("Default", 12),
		vgui_amber,
	)
	var map_info_rect := _relative_source_rect(
		source_path,
		"MapInfo",
		Rect2(168, 116, 316, 286),
		team_menu.position,
	)
	var map_panel := _vgui_dialog_panel(
		"MapInfo", map_info_rect.position, map_info_rect.size
	)
	team_menu.add_child(map_panel)
	_vgui_label(
		map_panel,
		"Scenario",
		"",
		Vector2(16, 14),
		Vector2(284, 24),
		_source_font_size("Default", 12),
		vgui_amber,
	)
	team_briefing_scroll = ScrollContainer.new()
	team_briefing_scroll.name = "BriefingScroll"
	team_briefing_scroll.position = Vector2(12, 44)
	team_briefing_scroll.size = Vector2(292, 232)
	team_briefing_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	team_briefing_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	team_briefing_scroll.set_meta("contains_full_source_briefing", true)
	_style_vgui_scrollbar(team_briefing_scroll)
	map_panel.add_child(team_briefing_scroll)
	var briefing_label := _vgui_label(
		team_briefing_scroll,
		"Description",
		"",
		Vector2.ZERO,
		Vector2(274, 320),
		_source_font_size("Default", 12),
		vgui_amber,
		true,
	)
	briefing_label.custom_minimum_size = Vector2(274, 320)
	for item_variant in TEAM_MENU_ITEMS:
		var item: Array = item_variant
		var team_id := int(item[2])
		var button_rect := _relative_source_rect(
			source_path,
			str(item[3]),
			Rect2(0, 116, 148, 20),
			team_menu.position,
		)
		var source_control := vgui_source.control(source_path, str(item[3]))
		var button_text := vgui_source.localize(
			str(source_control.get("labelText", "")),
			"%s %s" % [item[0], item[1]],
		)
		_vgui_button(
			team_menu,
			"Team%d" % team_id,
			button_text,
			button_rect.position,
			button_rect.size,
			func() -> void: _select_team(team_id),
			12,
			true,
		)
	var cancel_rect := _relative_source_rect(
		source_path,
		"CancelButton",
		Rect2(0, 276, 148, 20),
		team_menu.position,
	)
	_vgui_button(
		team_menu,
		"TeamCancel",
		vgui_source.localize(
			str(vgui_source.control(source_path, "CancelButton").get("labelText", "")),
			"&0 CANCEL",
		),
		cancel_rect.position,
		cancel_rect.size,
		func() -> void: deploy_cancel_requested.emit(),
		12,
		true,
	)
	update_deploy_briefing("de_dust2")


func _build_class_menu() -> void:
	var source_path := CS16VGuiSource.CSTRIKE_UI + "Classmenu_TER.kv"
	class_menu = _vgui_frame(deploy_canvas, "ClassMenu", source_path, "ClassMenu")
	class_menu.visible = false
	var title_rect := _relative_source_rect(
		source_path,
		"joinClass",
		Rect2(0, 22, 500, 48),
		class_menu.position,
	)
	_vgui_label(
		class_menu,
		"JoinClassTitle",
		vgui_source.localize("#Cstrike_Join_Class", "CHOOSE A CLASS"),
		title_rect.position,
		title_rect.size,
		_source_font_size("Title", 22),
		vgui_amber,
		false,
		"Title",
	)
	var info_rect := _relative_source_rect(
		source_path,
		"ClassInfo",
		Rect2(168, 116, 316, 286),
		class_menu.position,
	)
	# The source ClassInfo is 400x380 at y=116, which runs past both its
	# 448-tall frame and the 480-tall screen. Use the team menu's MapInfo
	# geometry, which the portrait/label layout below is built for.
	info_rect.size = Vector2(minf(info_rect.size.x, 316.0), minf(info_rect.size.y, 286.0))
	var info_panel := _vgui_dialog_panel(
		"ClassInfo", info_rect.position, info_rect.size
	)
	class_menu.add_child(info_panel)
	class_portrait = TextureRect.new()
	class_portrait.name = "ClassPortrait"
	class_portrait.position = Vector2(30, 18)
	class_portrait.size = Vector2(256, 196)
	class_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	class_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	class_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	class_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_child(class_portrait)
	class_portrait_label = _vgui_label(
		info_panel,
		"ClassPortraitLabel",
		"",
		Vector2(20, 226),
		Vector2(276, 32),
		_source_font_size("Default", 12),
		vgui_amber,
	)


func _populate_class_buttons() -> void:
	for child in class_menu.get_children():
		if child is Button:
			child.free()
	var classes: Array = TERRORIST_CLASSES if _selected_team == 1 else CT_CLASSES
	var source_path := (
		CS16VGuiSource.CSTRIKE_UI
		+ ("Classmenu_TER.kv" if _selected_team == 1 else "Classmenu_CT.kv")
	)
	for index in classes.size():
		var item: Array = classes[index]
		var class_id := index + 1
		var rect := _relative_source_rect(
			source_path,
			str(item[3]),
			Rect2(0, 116 + index * 32, 148, 20),
			class_menu.position,
		)
		var button := _vgui_button(
			class_menu,
			"Class%d" % class_id,
			vgui_source.localize(
				str(vgui_source.control(source_path, str(item[3])).get("labelText", "")),
				"&%s %s" % [item[0], item[1]],
			),
			rect.position,
			rect.size,
			func() -> void: _select_class(class_id),
			12,
			true,
		)
		var portrait_name := str(item[2])
		var portrait_label := str(item[1])
		button.mouse_entered.connect(
			func() -> void: _show_class_portrait(portrait_name, portrait_label)
		)
		button.focus_entered.connect(
			func() -> void: _show_class_portrait(portrait_name, portrait_label)
		)
	var cancel_rect := _relative_source_rect(
		source_path,
		"CancelButton",
		Rect2(0, 308, 148, 20),
		class_menu.position,
	)
	_vgui_button(
		class_menu,
		"ClassCancel",
		vgui_source.localize(
			str(vgui_source.control(source_path, "CancelButton").get("labelText", "")),
			"&0 CANCEL",
		),
		cancel_rect.position,
		cancel_rect.size,
		func() -> void: show_team_menu(),
		12,
		true,
	)
	if not classes.is_empty():
		_show_class_portrait(str(classes[0][2]), str(classes[0][1]))


func _show_class_portrait(portrait_name: String, display_name: String) -> void:
	class_portrait.texture = vgui_source.asset_texture(portrait_name)
	class_portrait.set_meta("app90_portrait", portrait_name)
	class_portrait_label.text = display_name


var _deploy_selection_rejected := false


func reject_deploy_selection() -> void:
	_deploy_selection_rejected = true
	show_team_menu()


func _select_team(team_id: int) -> void:
	_deploy_selection_rejected = false
	if team_id == 6:
		team_selected.emit(team_id)
		if _deploy_selection_rejected:
			return
		deploy_overlay.visible = false
		_set_menu_state("none")
		_refresh_gameplay_visibility()
		return
	_selected_team = 1 if team_id == 5 else team_id
	# Preserve auto-assign until game authority resolves it. Its synchronous
	# acceptance updates _selected_team to the actual class family.
	team_selected.emit(team_id)
	if _deploy_selection_rejected:
		return
	show_class_menu(_selected_team)


func _select_class(class_id: int) -> void:
	class_selected.emit(class_id)
	deploy_requested.emit()


func show_team_menu() -> void:
	team_menu.visible = true
	class_menu.visible = false
	_set_menu_state("team")
	var first := team_menu.get_node_or_null("Team1") as Control
	if first != null:
		first.call_deferred("grab_focus")


func show_class_menu(team_id: int) -> void:
	_selected_team = clampi(team_id, 1, 2)
	_populate_class_buttons()
	team_menu.visible = false
	class_menu.visible = true
	_set_menu_state("class")
	var first := class_menu.get_node_or_null("Class1") as Control
	if first != null:
		first.call_deferred("grab_focus")


func update_deploy_briefing(map_name: String) -> void:
	var briefing := vgui_source.map_briefing(map_name)
	var map_label := team_menu.get_node("MapName") as Label
	var scenario_label := team_menu.get_node("MapInfo/Scenario") as Label
	var description_label := team_menu.get_node("MapInfo/BriefingScroll/Description") as Label
	map_label.text = str(briefing.get("title", map_name.to_upper()))
	scenario_label.text = str(briefing.get("scenario", ""))
	description_label.text = str(briefing.get("body", ""))
	description_label.custom_minimum_size.y = maxf(
		320.0,
		float(description_label.text.count("\n") + 1)
		* float(_source_font_size("Default", 12) + 4),
	)
	map_label.set_meta("app90_source", briefing.get("source_path", ""))
	description_label.set_meta("app90_source", briefing.get("source_path", ""))


func _build_buy_overlay(root: Control) -> void:
	buy_overlay = ColorRect.new()
	buy_overlay.name = "BuyOverlay"
	buy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	buy_overlay.color = Color(0.0, 0.0, 0.0, 0.40)
	buy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	buy_overlay.visible = false
	root.add_child(buy_overlay)
	buy_canvas = _make_flow_canvas(buy_overlay, "BuyFlowCanvas")
	var source_path := CS16VGuiSource.CSTRIKE_UI + "MainBuyMenu.kv"
	buy_menu_frame = _vgui_frame(buy_canvas, "BuyMenu", "", "", 214.0)
	buy_menu_frame.set_meta("app90_source", source_path)
	var frame := buy_menu_frame
	_vgui_label(
		frame,
		"BuyTitle",
		vgui_source.localize("#Cstrike_Buy_Menu", "Buy Menu"),
		Vector2(0, 22),
		Vector2(500, 48),
		_source_font_size("Title", 22),
		vgui_amber,
		false,
		"Title",
	)
	_vgui_label(
		frame,
		"SelectCategory",
		vgui_source.localize("#Cstrike_Select_Category", "SHOP BY CATEGORY"),
		Vector2(8, 87),
		Vector2(160, 24),
		_source_font_size("Default", 12),
		vgui_amber,
	)
	buy_list_panel = Control.new()
	buy_list_panel.name = "BuyList"
	buy_list_panel.position = Vector2.ZERO
	buy_list_panel.size = frame.size
	frame.add_child(buy_list_panel)
	# The detail panel shares the option column's exact vertical extents and
	# ends flush with the 552-wide frame: one dialog, no overhang or seams.
	buy_item_panel = _vgui_dialog_panel(
		"ItemInfo",
		Vector2(202, 12),
		Vector2(frame.size.x - 202.0, frame.size.y - 24.0),
	)
	frame.add_child(buy_item_panel)
	_show_buy_category("rifles")


func _show_buy_category(category_id: String) -> void:
	# MainBuyMenu defines these as purchase commands, not submenu resources.
	# The purchase result owns closing the menu, just like weapon purchases.
	if category_id in ["primary_ammo", "secondary_ammo"]:
		buy_item_requested.emit("primammo" if category_id == "primary_ammo" else "secammo")
		return
	var old_title := buy_menu_frame.get_node_or_null("ItemTitle")
	if old_title != null:
		old_title.free()
	var main_title := buy_menu_frame.get_node_or_null("BuyTitle") as Control
	var category_prompt := buy_menu_frame.get_node_or_null("SelectCategory") as Control
	if main_title != null:
		main_title.visible = false
	if category_prompt != null:
		category_prompt.visible = false
	_clear_buy_controls(buy_list_panel)
	_clear_buy_controls(buy_item_panel)
	_buy_category = category_id
	_buy_navigation_level = "item"
	_set_menu_state("buy_item")
	buy_item_panel.visible = true
	_buy_items = _source_buy_items(category_id)
	var source_path := _buy_source_path(category_id)
	var title := category_id.replace("_", " ").capitalize()
	if not source_path.is_empty():
		var source_title := vgui_source.control(source_path, "Title")
		title = vgui_source.localize(str(source_title.get("labelText", title)), title)
	_vgui_label(
		buy_menu_frame,
		"ItemTitle",
		title,
		Vector2(0, 22),
		Vector2(500, 48),
		_source_font_size("Title", 22),
		vgui_amber,
		false,
		"Title",
	)
	for index in _buy_items.size():
		var item: Dictionary = _buy_items[index]
		var item_id := str(item.item_id)
		var price := int(item.price)
		# The App 90 localized label is already the authoritative accelerator
		# string (for example "&1 9X19MM SIDEARM"). Never synthesize a second
		# number in front of it. Every row shares one uniform VGUI font size;
		# classic 1.6 never auto-shrinks long rows.
		var text := str(item.label)
		var button := _vgui_button(
			buy_list_panel,
			"BuyItem_%s" % item_id,
			text,
			Vector2(0, 116 + index * 32),
			Vector2(BUY_ROW_WIDTH, 20),
			func() -> void: buy_item_requested.emit(item_id),
			BUY_ROW_FONT_SIZE,
			true,
		)
		button.set_meta("app90_source", source_path)
		button.set_meta("app90_control", item.source_control)
		var row_label := button.get_node_or_null("AcceleratorText") as RichTextLabel
		if row_label != null:
			# Reserve the fixed price column so no label ever runs beneath it.
			row_label.offset_right = -(BUY_PRICE_COLUMN_WIDTH + 12.0)
		# The classic list shows every cost in one fixed right-aligned column;
		# each price shares the row's font and vertical centerline.
		var price_label := _vgui_text(
			"$%d" % price,
			BUY_ROW_FONT_SIZE,
			vgui_amber_dim,
			"DefaultUnderline" if row_label != null else "Default",
		)
		price_label.name = "PriceText"
		price_label.position = Vector2(BUY_ROW_WIDTH - BUY_PRICE_COLUMN_WIDTH - 8.0, 0.0)
		price_label.size = Vector2(BUY_PRICE_COLUMN_WIDTH, 20.0)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# Match both the name's font metrics and its vertical alignment.
		# Accelerator overlays draw at the top; ordinary Button text centers.
		price_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP if row_label != null else VERTICAL_ALIGNMENT_CENTER
		button.add_child(price_label)
		button.mouse_entered.connect(func() -> void: _show_buy_portrait(item))
		button.focus_entered.connect(func() -> void: _show_buy_portrait(item))
		button.disabled = price > _buy_money
		if button.disabled:
			# Accelerator rows are rendered exclusively by the RichTextLabel
			# overlay. Keeping the Button's disabled font visible draws the same
			# source string twice with a different baseline.
			button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)
			var disabled_accelerator := button.get_node_or_null("AcceleratorText") as RichTextLabel
			if disabled_accelerator != null:
				disabled_accelerator.add_theme_color_override(
					"default_color",
					Color(0.31, 0.19, 0.0, 1.0),
				)
				disabled_accelerator.modulate = Color(0.70, 0.70, 0.70, 1.0)
			price_label.add_theme_color_override(
				"font_color",
				Color(0.31, 0.19, 0.0, 1.0),
			)
	_vgui_button(
		buy_list_panel,
		"BuyBack",
		vgui_source.localize("#Cstrike_Cancel", "&0 CANCEL"),
		Vector2(0, 380),
		Vector2(BUY_ROW_WIDTH, 20),
		_show_buy_categories,
		BUY_ROW_FONT_SIZE,
		true,
	)
	buy_portrait = TextureRect.new()
	buy_portrait.name = "WeaponPortrait"
	buy_portrait.position = Vector2(14, 96)
	buy_portrait.size = Vector2(322, 150)
	buy_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	buy_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	buy_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# The staged App 90 buy pictures are already the finished VGUI photos
	# (black polymer pistols, olive kevlar); present their diffuse colors
	# untouched — any brightness "lift" turns them into chrome clay renders.
	buy_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buy_item_panel.add_child(buy_portrait)
	buy_description = _vgui_label(
		buy_item_panel,
		"WeaponDescription",
		"",
		Vector2(16, 258),
		Vector2(318, 42),
		_source_font_size("Default", 12),
		vgui_amber,
		true,
	)
	# CS 1.6 keeps account text in the shared HUD orange scheme; it never
	# turns green inside the buy menu.
	_vgui_label(
		buy_item_panel,
		"BuyMoney",
		"ACCOUNT: $%d" % _buy_money,
		Vector2(16, 330),
		Vector2(292, 24),
		12,
		vgui_amber,
	)
	if not _buy_items.is_empty():
		_show_buy_portrait(_buy_items[0])
	_focus_first_buy_row.call_deferred()


func _show_buy_categories() -> void:
	_clear_buy_controls(buy_list_panel)
	_clear_buy_controls(buy_item_panel)
	_buy_navigation_level = "category"
	_set_menu_state("buy_category")
	# The submenu replaces the parent menu in CS 1.6; the item detail panel
	# must not linger behind the category list.
	buy_item_panel.visible = false
	var source_path := CS16VGuiSource.CSTRIKE_UI + "MainBuyMenu.kv"
	var item_title := buy_menu_frame.get_node_or_null("ItemTitle")
	if item_title != null:
		item_title.free()
	var main_title := buy_menu_frame.get_node_or_null("BuyTitle") as Control
	var category_prompt := buy_menu_frame.get_node_or_null("SelectCategory") as Control
	if main_title != null:
		main_title.visible = true
	if category_prompt != null:
		category_prompt.visible = true
	for index in BUY_CATEGORIES.size():
		var category: Array = BUY_CATEGORIES[index]
		var category_id := str(category[2])
		var source_control: String = str({
			"smg": "submachineguns",
			"primary_ammo": "primaryammo",
			"secondary_ammo": "secammo",
		}.get(category_id, category_id))
		var source_rect := vgui_source.control_rect(
			source_path,
			source_control,
			Rect2(76, 116 + index * 32, 148, 20),
			VGUI_BASE_SIZE,
		)
		# Use the authoritative App 90 label (for example "&6 PRIMARY AMMO"):
		# it carries the underlined accelerator and the source wording, and it
		# is short enough that every row keeps one uniform font size.
		var source_label := vgui_source.localize(
			str(vgui_source.control(source_path, source_control).get("labelText", "")),
			"&%s %s" % [category[0], category[1]],
		)
		_vgui_button(
			buy_list_panel,
			"BuyCategory_%s" % category_id,
			source_label,
			source_rect.position - VGUI_MENU_ORIGIN,
			Vector2(BUY_ROW_WIDTH, source_rect.size.y),
			func() -> void: _show_buy_category(category_id),
			12,
			true,
		)
	_vgui_button(
		buy_list_panel,
		"BuyCancel",
		vgui_source.localize("#Cstrike_Cancel", "&0 CANCEL"),
		Vector2(0, 380),
		Vector2(BUY_ROW_WIDTH, 20),
		func() -> void: set_buy_menu_visible(false),
		12,
		true,
	)
	_focus_first_buy_row.call_deferred()


func _clear_buy_controls(panel: Control) -> void:
	# A category, Back or purchase callback may still be running on one of
	# these buttons. Detach now so old rows cannot draw, intercept input or
	# collide with replacement names, then free after signal dispatch ends.
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()


func _focus_first_buy_row() -> void:
	# Rapid navigation can retire several rows before deferred calls run.
	# Resolve the current row here, never retain a soon-to-be-freed button.
	if not buy_overlay.is_visible_in_tree() or buy_list_panel.get_child_count() == 0:
		return
	var first := buy_list_panel.get_child(0) as Control
	if first != null and first.is_visible_in_tree():
		first.grab_focus()


func _buy_source_path(category_id: String) -> String:
	var prefix: String = str({
		"pistols": "BuyPistols",
		"shotguns": "BuyShotguns",
		"smg": "BuySubMachineguns",
		"rifles": "BuyRifles",
		"machineguns": "BuyMachineguns",
		"equipment": "BuyEquipment",
	}.get(category_id, ""))
	if prefix.is_empty():
		return ""
	return (
		CS16VGuiSource.CSTRIKE_UI
		+ "%s_%s.kv" % [prefix, "CT" if _buy_team == 2 else "TER"]
	)


func _source_buy_items(category_id: String) -> Array:
	var source_path := _buy_source_path(category_id)
	var parsed := vgui_source.parse_file(source_path)
	var controls: Dictionary = {}
	for root_key in parsed:
		if parsed[root_key] is Dictionary:
			controls = parsed[root_key]
			break
	var ordered: Array = []
	for control_name in controls:
		var data: Variant = controls[control_name]
		if not data is Dictionary:
			continue
		var command := str(data.get("command", data.get("Command", ""))).to_lower()
		if command.is_empty() or command == "vguicancel":
			continue
		command = {
			"glock": "glock18",
			"mp5navy": "mp5",
			"fn57": "fiveseven",
			"hegrenade": "hegren",
			"flashbang": "flash",
			"smokegrenade": "sgren",
		}.get(command, command)
		if not BUY_DEFINITIONS.has(command):
			continue
		var definition: Array = BUY_DEFINITIONS[command]
		var label_token := str(data.get("labelText", definition[0]))
		ordered.append({
			"item_id": command,
			"label": vgui_source.localize(label_token, str(definition[0])),
			"price": int(data.get("cost", definition[1])),
			"art": str(definition[2]),
			"source_control": str(control_name),
			"y": int(data.get("ypos", 9999)),
		})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.y) < int(b.y))
	return ordered


func _show_buy_portrait(item: Dictionary) -> void:
	buy_portrait.texture = vgui_source.asset_texture(str(item.art)) if not str(item.art).is_empty() else null
	buy_portrait.set_meta("app90_portrait", item.art)
	buy_description.text = "%s\nPRICE: $%d" % [
		_strip_accelerator(str(item.label)),
		item.price,
	]


func _strip_accelerator(text: String) -> String:
	return text.replace("&&", "\u001f").replace("&", "").replace("\u001f", "&")


func show_buy_menu(team_id: int, money: int, context: Dictionary = {}) -> void:
	if _menu_state == "chat":
		close_chat()
	buy_menu_generation += 1
	_buy_team = clampi(team_id, 1, 2)
	_buy_money = maxi(0, money)
	# The buy menu's ACCOUNT line and the HUD account counter are the same
	# value by definition in CS 1.6; opening the menu re-asserts the HUD digits
	# so the two can never disagree in one frame.
	update_money(_buy_money)
	_buy_context = context.duplicate(true)
	_show_buy_categories()
	buy_overlay.visible = true
	_set_menu_state("buy_category")
	_refresh_gameplay_visibility()


func update_buy_account(money: int, context: Dictionary) -> void:
	if _buy_money == money and _buy_context == context:
		return
	_buy_money = maxi(0, money)
	_buy_context = context.duplicate(true)
	if buy_overlay.visible and _buy_navigation_level == "item":
		_show_buy_category(_buy_category)


func set_buy_menu_visible(visible: bool) -> void:
	if visible and _menu_state == "chat":
		close_chat()
	if visible and not buy_overlay.visible:
		buy_menu_generation += 1
	buy_overlay.visible = visible
	_set_menu_state("buy_category" if visible else "none")
	_refresh_gameplay_visibility()


func complete_buy_purchase(generation := -1) -> void:
	# A delayed reply must not dismiss a newer buy session or steal focus from
	# Pause/Options opened while the reliable request was in flight.
	if not buy_overlay.visible or (generation >= 0 and generation != buy_menu_generation):
		return
	buy_overlay.hide()
	if _menu_state in ["buy_category", "buy_item"]:
		_set_menu_state("none")
	_refresh_gameplay_visibility()


func _build_scoreboard_overlay(root: Control) -> void:
	scoreboard_overlay = Control.new()
	scoreboard_overlay.name = "ScoreboardOverlay"
	scoreboard_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scoreboard_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_overlay.visible = false
	root.add_child(scoreboard_overlay)
	scoreboard_canvas = _make_flow_canvas(scoreboard_overlay, "ScoreboardFlowCanvas")
	var source_path := CS16VGuiSource.CSTRIKE_UI + "ScoreBoard.kv"
	# User reference: near-full-height scoreboard within the centered 4:3 canvas.
	var source_rect := Rect2(60, 16, 520, 448)
	var panel := PanelContainer.new()
	panel.name = "ClientScoreBoard"
	panel.position = source_rect.position
	panel.size = source_rect.size
	panel.clip_contents = true
	panel.set_meta("app90_source", source_path)
	panel.set_meta("app90_control", "ClientScoreBoard")
	var panel_style := _panel_style(Color(0.02, 0.025, 0.02, 0.36), Color(vgui_amber, 0.45), 6)
	panel_style.content_margin_left = 4
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 3
	panel_style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", panel_style)
	scoreboard_canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "ScoreboardContent"
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)
	var header := _scoreboard_row(["Counter-Strike 1.6  |  de_dust2", "", "HP", "Money", "Score", "Deaths", "Latency"], vgui_amber)
	header.name = "ColumnHeader"
	header.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	header.get_child(0).name = "ServerName"
	header.get_child(0).size_flags_stretch_ratio = SCOREBOARD_COLUMN_WIDTHS[0] + SCOREBOARD_COLUMN_WIDTHS[1]
	header.get_child(1).free()
	column.add_child(header)
	column.add_child(_scoreboard_divider(vgui_amber))
	var scroll := ScrollContainer.new()
	scroll.name = "PlayerScroll"
	scroll.custom_minimum_size = Vector2(0, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_style_vgui_scrollbar(scroll)
	column.add_child(scroll)
	scoreboard_rows = VBoxContainer.new()
	scoreboard_rows.name = "PlayerList"
	scoreboard_rows.add_theme_constant_override("separation", 0)
	scoreboard_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scoreboard_rows)
	# A full server adds a scrollbar; keep the heading over the same columns.
	scoreboard_rows.resized.connect(func() -> void:
		header.custom_minimum_size.x = scoreboard_rows.size.x)
	update_scoreboard([], "Counter-Strike 1.6", "de_dust2", 0, 0)


func _scoreboard_divider(color: Color) -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size.y = 1
	line.color = Color(color, 0.65)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _scoreboard_cell(value: String, index: int, color: Color) -> Label:
	var label := _vgui_text(value, 10, color)
	label.name = ["Name", "Status", "Health", "Money", "Score", "Deaths", "Latency"][index]
	label.custom_minimum_size.y = 20
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = SCOREBOARD_COLUMN_WIDTHS[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if index < 2 else HORIZONTAL_ALIGNMENT_CENTER
	return label


func _scoreboard_row(values: Array, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 20
	row.add_theme_constant_override("separation", 0)
	for index in values.size():
		row.add_child(_scoreboard_cell(str(values[index]), index, color))
	return row


func _scoreboard_player_row(player: Dictionary, team_color := Color.WHITE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 20
	row.add_theme_constant_override("separation", 0)
	var is_local := bool(player.get("is_local", false))
	row.set_meta("is_local", is_local)
	row.set_meta("actor_id", str(player.get("id", "")))
	if is_local:
		# Draw behind the existing columns without changing their layout or input.
		var highlight := StyleBoxFlat.new()
		highlight.bg_color = Color(1.0, 1.0, 1.0, 0.14)
		highlight.border_width_left = 2
		highlight.border_color = vgui_amber
		row.draw.connect(func() -> void:
			row.draw_style_box(highlight, Rect2(Vector2.ZERO, row.size)))
	var identity := HBoxContainer.new()
	identity.custom_minimum_size.y = 20
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_stretch_ratio = SCOREBOARD_COLUMN_WIDTHS[0]
	identity.add_theme_constant_override("separation", 4)
	var gutter := Control.new()
	gutter.custom_minimum_size.x = 12
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(gutter)
	# CS 1.6 draws every player's name (and row values) in the team color:
	# pale blue for CTs, red for Terrorists, white for spectators.
	var name_label := _vgui_text(str(player.get("name", "Player")), 10, team_color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_label)
	# Keep original voice art; no invented player avatars or account integration.
	if bool(player.get("voice_muted", false)):
		identity.add_child(_scoreboard_voice_icon(true, 0))
	elif bool(player.get("voice_active", false)):
		identity.add_child(
			_scoreboard_voice_icon(false, int(player.get("voice_level", 4)))
		)
	row.add_child(identity)
	var alive := bool(player.get("alive", true))
	var private_stats := bool(player.get("show_private_stats", false))
	var values := [
		"Dead" if not alive else ("Bomb" if private_stats and bool(player.get("bomb", false)) else ""),
		str(player.health) if private_stats and alive and player.has("health") else "",
		"$%d" % int(player.money) if private_stats and player.has("money") else "",
		player.get("score", 0),
		player.get("deaths", 0),
		player.get("latency", 0),
	]
	for index in values.size():
		row.add_child(_scoreboard_cell(str(values[index]), index + 1, team_color))
	row.set_meta("uses_source_status_icons", true)
	return row


func _scoreboard_status_icon(sprite_name: String, status_name: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Status_%s" % sprite_name
	icon.texture = load(CLASSIC_HUD_ROOT.path_join("%s.png" % sprite_name)) as Texture2D
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.tooltip_text = status_name
	icon.set_meta("classic_status", status_name)
	return icon


func _scoreboard_voice_icon(muted: bool, level: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Status_voice_muted" if muted else "Status_voice_active"
	icon.texture = vgui_source.voice_texture(muted, level)
	icon.custom_minimum_size = Vector2(16, 16)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.tooltip_text = "voice muted" if muted else "voice transmitting"
	icon.set_meta("voice_muted", muted)
	icon.set_meta("voice_active", not muted)
	icon.set_meta("voice_level", level)
	icon.set_meta(
		"app90_source",
		CS16VGuiSource.VOICE_ART
		+ ("640_voiceblocked.tga" if muted else "640_speaker%d.tga" % clampi(level, 1, 4)),
	)
	return icon


func update_scoreboard(
	players: Array,
	server_name: String,
	map_name: String,
	ct_score: int,
	terrorist_score: int,
) -> void:
	var server_label := scoreboard_canvas.get_node(
		"ClientScoreBoard/ScoreboardContent/ColumnHeader/ServerName"
	) as Label
	server_label.text = "%s  |  %s" % [server_name, map_name]
	var scroll := scoreboard_rows.get_parent() as ScrollContainer
	var previous_scroll := scroll.scroll_vertical
	for child in scoreboard_rows.get_children():
		child.free()
	var teams := [
		[1, "Terrorists", terrorist_score, vgui_red],
		[2, "Counter-Terrorists", ct_score, vgui_blue],
		[0, "Spectators", 0, vgui_amber],
	]
	for team_entry in teams:
		var team_id := int(team_entry[0])
		var team_players: Array = []
		for player_variant in players:
			var player: Dictionary = player_variant
			if int(player.get("team", 0)) == team_id:
				team_players.append(player)
		team_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("score", 0)) != int(b.get("score", 0)):
				return int(a.get("score", 0)) > int(b.get("score", 0))
			if int(a.get("deaths", 0)) != int(b.get("deaths", 0)):
				return int(a.get("deaths", 0)) < int(b.get("deaths", 0))
			return str(a.get("id", a.get("name", ""))) < str(b.get("id", b.get("name", ""))))
		if scoreboard_rows.get_child_count() > 0:
			var gap := Control.new()
			gap.custom_minimum_size.y = 6
			scoreboard_rows.add_child(gap)
		var section := _scoreboard_row(
			[
				"%s  -  %d %s" % [
					team_entry[1],
					team_players.size(),
					"player" if team_players.size() == 1 else "players",
				],
				"", "", "",
				str(team_entry[2]) if team_id != 0 else "",
				"", "",
			],
			team_entry[3],
		)
		section.name = "Team%dSection" % team_id
		# Team title spans name/status space; numeric cells remain aligned.
		section.get_child(0).size_flags_stretch_ratio = SCOREBOARD_COLUMN_WIDTHS[0] + SCOREBOARD_COLUMN_WIDTHS[1]
		section.get_child(1).free()
		scoreboard_rows.add_child(section)
		scoreboard_rows.add_child(_scoreboard_divider(team_entry[3]))
		for player in team_players:
			var row := _scoreboard_player_row(player, team_entry[3] if team_id != 0 else Color(0.8, 0.8, 0.8))
			row.name = "Player_%s" % str(player.get("id", player.get("name", "Player"))).validate_node_name()
			scoreboard_rows.add_child(row)
	scroll.set_deferred("scroll_vertical", previous_scroll)


func show_scoreboard(
	players: Array,
	server_name := "Counter-Strike 1.6",
	map_name := "de_dust2",
	ct_score := 0,
	terrorist_score := 0,
) -> void:
	update_scoreboard(players, server_name, map_name, ct_score, terrorist_score)
	set_scoreboard_visible(true)


func set_scoreboard_visible(visible: bool) -> void:
	scoreboard_overlay.visible = visible
	_set_menu_state("scoreboard" if visible else "none")


func set_scoreboard_held(held: bool) -> void:
	set_scoreboard_visible(held)


func _build_pause_overlay(root: Control) -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color(0.0, 0.0, 0.0, 0.56)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	root.add_child(pause_overlay)
	pause_canvas = _make_flow_canvas(pause_overlay, "PauseFlowCanvas")
	_build_pause_main_menu()
	_build_pause_options_menu()
	_build_network_menu()


func _build_pause_main_menu() -> void:
	pause_main_menu = Control.new()
	pause_main_menu.name = "GameMenu"
	pause_main_menu.position = Vector2(56, 84)
	pause_main_menu.size = Vector2(300, 360)
	pause_main_menu.set_meta("app90_source", CS16VGuiSource.CSTRIKE_RESOURCE + "GameMenu.kv")
	pause_canvas.add_child(pause_main_menu)
	var art := TextureRect.new()
	art.name = "GameMenuArtwork"
	art.position = Vector2.ZERO
	art.size = Vector2(207, 32)
	art.texture = vgui_source.menu_texture(false)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_meta("app90_source", CS16VGuiSource.CSTRIKE_RESOURCE + "game_menu.tga")
	pause_main_menu.add_child(art)
	var entries := vgui_source.menu_entries()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var source_command := str(entry.get("command", ""))
		# GameUI title-cases every menu entry ("Resume Game", "Player List"),
		# never the sentence case some localization strings carry.
		var label: String = _title_case(
			vgui_source.localize(str(entry.get("label", "")), source_command)
		)
		var command: String = str({
			"ResumeGame": "resume",
			"Disconnect": "disconnect",
			"OpenPlayerListDialog": "players",
			"OpenCreateMultiplayerGameDialog": "new_game",
			"OpenServerBrowser": "servers",
			"OpenOptionsDialog": "options",
			"Quit": "quit",
		}.get(source_command, source_command))
		var entry_button := _vgui_button(
			pause_main_menu,
			"GameMenu_%s" % command,
			label,
			Vector2(0, 52 + index * 32),
			Vector2(238, 26),
			func() -> void: _activate_pause_command(command),
			_source_font_size("MenuButton", 14),
		)
		# GameUI menu entries are title-case pale tan that brightens to white,
		# unlike the amber ClientScheme rows used by gameplay dialogs.
		entry_button.add_theme_color_override("font_color", GAMEUI_MENU_TEXT)
		entry_button.add_theme_color_override("font_hover_color", GAMEUI_MENU_TEXT_BRIGHT)
		entry_button.add_theme_color_override("font_focus_color", GAMEUI_MENU_TEXT_BRIGHT)
		entry_button.add_theme_color_override("font_pressed_color", GAMEUI_MENU_TEXT_BRIGHT)
	for child in pause_main_menu.get_children():
		if child is Button:
			var button := child as Button
			button.mouse_entered.connect(
				func() -> void: art.texture = vgui_source.menu_texture(true)
			)
			button.mouse_exited.connect(
				func() -> void: art.texture = vgui_source.menu_texture(false)
			)


func _title_case(text: String) -> String:
	var words := text.split(" ")
	for index in words.size():
		var word := str(words[index])
		if word.length() > 0:
			words[index] = word[0].to_upper() + word.substr(1)
	return " ".join(words)


func _activate_pause_command(command: String) -> void:
	menu_command_requested.emit(command)
	match command:
		"resume":
			resume_requested.emit()
		"disconnect":
			disconnect_requested.emit()
		"players":
			set_scoreboard_visible(true)
		"options":
			_show_pause_options()
		"new_game":
			show_network_menu("host")
		"servers":
			show_network_menu("join")
		"quit":
			quit_requested.emit()


func _build_network_menu() -> void:
	network_menu = Panel.new()
	network_menu.name = "DirectConnection"
	network_menu.position = Vector2(60, 80)
	network_menu.size = Vector2(520, 310)
	# Keep the underlying deployment text from bleeding through this form.
	var background := Color(GAMEUI_PANEL.r, GAMEUI_PANEL.g, GAMEUI_PANEL.b, 1.0)
	network_menu.add_theme_stylebox_override("panel", _panel_style(background, GAMEUI_PANEL_BORDER, 0))
	network_menu.visible = false
	pause_canvas.add_child(network_menu)
	_vgui_label(network_menu, "Title", "DUST2 MULTIPLAYER", Vector2(16, 10), Vector2(480, 30), 18, GAMEUI_MENU_TEXT)
	_vgui_label(network_menu, "Help", "Direct connection only. Both players need the same build.\nShare the host address and UDP port with your friend.", Vector2(16, 48), Vector2(488, 42), 12, GAMEUI_MENU_TEXT, true)
	_vgui_label(network_menu, "AddressLabel", "Host address", Vector2(16, 108), Vector2(112, 28), 12, GAMEUI_MENU_TEXT)
	_vgui_label(network_menu, "PortLabel", "UDP port", Vector2(16, 148), Vector2(112, 28), 12, GAMEUI_MENU_TEXT)
	network_address = _network_entry("Address", "127.0.0.1", Vector2(136, 108), Vector2(364, 28), 253)
	network_port = _network_entry("Port", "27447", Vector2(136, 148), Vector2(110, 28), 5)
	network_status = _vgui_label(network_menu, "Status", "OFFLINE", Vector2(16, 188), Vector2(488, 58), 12, GAMEUI_MENU_TEXT, true)
	network_connect_button = _vgui_button(network_menu, "Connect", "Join", Vector2(16, 266), Vector2(120, 28), _request_network_connection)
	_vgui_button(network_menu, "Offline", "Return Offline", Vector2(168, 266), Vector2(160, 28), func() -> void: disconnect_requested.emit())
	_vgui_button(network_menu, "Back", "Back", Vector2(404, 266), Vector2(96, 28), _show_pause_main)
	network_address.text_submitted.connect(func(_text: String) -> void: _request_network_connection())
	network_port.text_submitted.connect(func(_text: String) -> void: _request_network_connection())
	if OS.has_feature("web"):
		# Browsers reach servers over WebSocket, so the form takes a ws(s) URL
		# (defaulting to the server that served this page) and no UDP port.
		var help := network_menu.get_node("Help") as Label
		help.text = "Browser play connects over WebSocket.\nJoin the server this page came from, or paste another ws:// or wss:// URL."
		(network_menu.get_node("AddressLabel") as Label).text = "Server URL"
		network_address.max_length = NetworkSessionScript.MAX_WEB_SOCKET_URL_LENGTH
		network_address.text = NetworkSessionScript.default_web_server_url()
		network_port.visible = false
		(network_menu.get_node("PortLabel") as Label).visible = false


func _network_entry(entry_name: String, text: String, position: Vector2, size: Vector2, limit: int) -> LineEdit:
	var entry := LineEdit.new()
	entry.name = entry_name
	entry.text = text
	entry.position = position
	entry.size = size
	entry.max_length = limit
	entry.add_theme_font_override("font", _font_for_rule("Default"))
	entry.add_theme_font_size_override("font_size", 12)
	entry.add_theme_color_override("font_color", GAMEUI_MENU_TEXT)
	network_menu.add_child(entry)
	return entry


func show_network_menu(action: String) -> void:
	_network_menu_action = action
	pause_main_menu.hide()
	pause_options_menu.hide()
	accessibility_overlay.hide()
	network_menu.show()
	_refresh_network_controls()
	_set_menu_state("network")
	if action == "join" and not _network_online:
		network_address.grab_focus()


func update_network_status(text: String, online: bool, client_mode: bool) -> void:
	network_status.text = text
	_network_online = online
	_network_client = client_mode
	_refresh_network_controls()


func _refresh_network_controls() -> void:
	network_address.editable = not _network_online and _network_menu_action == "join"
	network_port.editable = not _network_online
	network_connect_button.text = "Host Dust2" if _network_menu_action == "host" else "Join"
	network_connect_button.disabled = _network_online or (_network_menu_action == "host" and _network_client)
	network_connect_button.tooltip_text = "Return Offline before hosting." if _network_menu_action == "host" and _network_client else ""


func _request_network_connection() -> void:
	if network_menu.is_visible_in_tree() and not network_connect_button.disabled:
		network_connection_requested.emit(_network_menu_action, network_address.text, network_port.text)


func _build_pause_options_menu() -> void:
	pause_options_menu = PanelContainer.new()
	pause_options_menu.name = "OptionsMenu"
	pause_options_menu.position = Vector2(60, 34)
	# The source dialog is 520x412, but our command buttons render 31 units
	# tall; the extra room keeps OK/Cancel/Apply inside the frame.
	pause_options_menu.size = Vector2(528, 424)
	var dialog_path := CS16VGuiSource.VALVE_RESOURCE + "DialogOptionsIngame.kv"
	var dialog_source := vgui_source.control(dialog_path, "OptionsDialog")
	pause_options_menu.set_meta(
		"app90_source",
		dialog_path,
	)
	pause_options_menu.set_meta("app90_source_control", "OptionsDialog")
	pause_options_menu.set_meta("app90_source_rect", vgui_source.control_rect(
		dialog_path,
		"OptionsDialog",
		Rect2(0, 0, 824, 736),
	))
	pause_options_menu.set_meta("app90_dialog_data", dialog_source)
	# The in-game options dialog is Steam GameUI (TrackerScheme): dark olive
	# grey-green panel with warm tan text, not the amber cstrike ClientScheme.
	pause_options_menu.add_theme_stylebox_override(
		"panel",
		_panel_style(GAMEUI_PANEL, GAMEUI_PANEL_BORDER, 0),
	)
	pause_options_menu.visible = false
	pause_canvas.add_child(pause_options_menu)
	var content := Control.new()
	content.name = "OptionsContent"
	pause_options_menu.add_child(content)
	_vgui_label(
		content,
		"OptionsTitle",
		vgui_source.localize("#GameUI_Options", "OPTIONS"),
		Vector2(10, 0),
		Vector2(480, 30),
		_source_font_size("Title", 18),
		GAMEUI_MENU_TEXT,
	)
	options_tab_bar = HBoxContainer.new()
	options_tab_bar.name = "OptionsTabs"
	options_tab_bar.position = Vector2(10, 34)
	options_tab_bar.size = Vector2(492, 26)
	options_tab_bar.add_theme_constant_override("separation", 2)
	content.add_child(options_tab_bar)
	options_pages = Control.new()
	options_pages.name = "OptionsPages"
	options_pages.position = Vector2(4, 62)
	options_pages.size = Vector2(512, 346)
	content.add_child(options_pages)
	# VGUI tab captions are mixed case ("Multiplayer"), never shouted caps.
	var tabs := ["Multiplayer", "Keyboard", "Mouse", "Audio", "Video", "Voice"]
	for tab_name in tabs:
		var tab_key: String = str(tab_name).to_lower()
		var button := _vgui_button(
			options_tab_bar,
			"Tab_%s" % tab_key,
			tab_name,
			Vector2.ZERO,
			Vector2(78, 24),
			func() -> void: _show_options_tab(tab_key),
			9,
		)
		button.custom_minimum_size = Vector2(78, 24)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		# GameUI tabs use the dialog's tan text scheme, not the amber
		# cstrike client scheme.
		button.add_theme_color_override("font_color", GAMEUI_MENU_TEXT_DIM)
		button.add_theme_color_override("font_hover_color", GAMEUI_MENU_TEXT_BRIGHT)
		button.add_theme_color_override("font_focus_color", GAMEUI_MENU_TEXT_BRIGHT)
		button.add_theme_color_override("font_pressed_color", GAMEUI_MENU_TEXT_BRIGHT)
		_build_source_options_page(tab_key)
	var commit_source := CS16VGuiSource.CSTRIKE_RESOURCE + "OptionsSubMultiplayer.kv"
	for button_spec in [
		["OptionsOK", "OK", "_options_ok"],
		["OptionsCancel", "Cancel", "_options_cancel"],
		["OptionsApply", "Apply", "_options_apply"],
	]:
		var source_name := str(button_spec[1])
		var data := vgui_source.control(commit_source, source_name)
		var rect := vgui_source.control_rect(
			commit_source,
			source_name,
			Rect2(308, 322, 64, 24),
		)
		var action: Callable = Callable(self, str(button_spec[2]))
		var button := _vgui_button(
			content,
			str(button_spec[0]),
			vgui_source.localize(str(data.get("labelText", source_name)), source_name),
			rect.position + options_pages.position,
			rect.size,
			action,
			10,
		)
		button.set_meta("app90_source", commit_source)
		button.set_meta("tab_position", int(data.get("tabPosition", 0)))
		button.set_meta("default", int(data.get("default", 0)) != 0)
		button.set_meta("command", source_name)
		_style_gameui_command_button(button)
	var accessibility_button := _vgui_button(content, "OptionsAccessibility", "Accessibility…", Vector2(140, 384), Vector2(126, 20), _show_accessibility, 9)
	_style_gameui_command_button(accessibility_button)
	_build_accessibility_overlay()
	_show_options_tab("multiplayer")


func _style_gameui_command_button(button: Button) -> void:
	# GoldSrc GameUI command buttons (OK/Cancel/Apply) are flat rectangular
	# plates with a plain 1px border and centered tan text — never bare labels.
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("font_color", GAMEUI_MENU_TEXT)
	button.add_theme_color_override("font_hover_color", GAMEUI_MENU_TEXT_BRIGHT)
	button.add_theme_color_override("font_focus_color", GAMEUI_MENU_TEXT_BRIGHT)
	button.add_theme_color_override("font_pressed_color", GAMEUI_MENU_TEXT_BRIGHT)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(Color(0.34, 0.39, 0.30, 1.0), Color(0.20, 0.23, 0.18, 1.0), 0),
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(Color(0.40, 0.45, 0.36, 1.0), Color(0.62, 0.66, 0.56, 1.0), 0),
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(Color(0.38, 0.43, 0.34, 1.0), Color(0.62, 0.66, 0.56, 1.0), 0),
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(Color(0.28, 0.32, 0.25, 1.0), Color(0.20, 0.23, 0.18, 1.0), 0),
	)


func _source_options_path(tab_key: String) -> String:
	if tab_key == "multiplayer":
		return CS16VGuiSource.CSTRIKE_RESOURCE + "OptionsSubMultiplayer.kv"
	return (
		CS16VGuiSource.VALVE_RESOURCE
		+ {
			"keyboard": "OptionsSubKeyboard.kv",
			"mouse": "OptionsSubMouse.kv",
			"audio": "OptionsSubAudio.kv",
			"video": "OptionsSubVideo.kv",
			"voice": "OptionsSubVoice.kv",
		}.get(tab_key, "OptionsSubAdvanced.kv")
	)


func _build_source_options_page(tab_key: String) -> void:
	var page := Control.new()
	page.name = "Page_%s" % tab_key
	page.position = Vector2.ZERO
	page.size = options_pages.size
	var source_path := _source_options_path(tab_key)
	page.set_meta("app90_source", source_path)
	page.set_meta("source_authored_controls", true)
	options_pages.add_child(page)
	var focus_controls: Array[Control] = []
	for data in vgui_source.controls_by_tab(source_path):
		if int(data.get("visible", 1)) == 0:
			continue
		var source_name := str(data.source_control)
		if source_name in ["OK", "Cancel", "Apply"]:
			continue
		var control_type := str(data.get("ControlName", "Panel"))
		var rect := vgui_source.control_rect(source_path, source_name, Rect2())
		# The source video page authors LowVideoDetail as a 44-tall two-line
		# checkbox at y=152 while DetailTextures sits at y=184, inside the
		# wrapped second line. Clear the two-line row and shift the
		# brightness/gamma cluster down to keep every row separated.
		if tab_key == "video":
			if source_name == "DetailTextures":
				rect.position.y = 200.0
			elif rect.position.y >= 205.0 and rect.position.y <= 280.0:
				rect.position.y += 24.0
		var label_text := vgui_source.localize(
			str(data.get("labelText", "")),
			str(data.get("labelText", "")),
		)
		var control: Control
		match control_type:
			"Label", "URLLabel":
				var text_label := _vgui_text(
					label_text,
					_source_font_size("DefaultSmall", 12),
					GAMEUI_MENU_TEXT_DIM if int(data.get("dulltext", 0)) != 0 else GAMEUI_MENU_TEXT,
					"DefaultSmall" if int(data.get("dulltext", 0)) != 0 else "Default",
				)
				# Labels authored taller than one line are GameUI paragraphs:
				# wrap them from the top instead of clipping one centered line.
				if rect.size.y >= 30.0:
					text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					text_label.clip_text = false
					text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
				control = text_label
			"Button":
				var command := str(data.get("command", data.get("Command", source_name)))
				control = _vgui_button(
					page,
					"Source_%s" % source_name.validate_node_name(),
					label_text if not label_text.is_empty() else source_name,
					rect.position,
					rect.size,
					func() -> void: _on_source_option_command(tab_key, command),
					_source_font_size("Default", 12),
				)
			"CheckButton", "CCvarToggleCheckButton":
				var check := _vgui_check(label_text if not label_text.is_empty() else source_name, false)
				check.name = "Source_%s" % source_name.validate_node_name()
				check.position = rect.position
				check.size = rect.size
				control = check
			"CCvarSlider":
				var slider := HSlider.new()
				slider.name = "Source_%s" % source_name.validate_node_name()
				slider.min_value = 0
				slider.max_value = 100
				slider.value = 50
				slider.position = rect.position
				slider.size = rect.size
				_style_vgui_slider(slider)
				control = slider
			"ComboBox", "CLabeledCommandComboBox":
				var option := OptionButton.new()
				option.name = "Source_%s" % source_name.validate_node_name()
				for choice in _source_option_choices(source_name):
					option.add_item(choice)
				option.position = rect.position
				option.size = rect.size
				_style_vgui_option(option)
				control = option
			"CCvarTextEntry", "TextEntry":
				var entry := LineEdit.new()
				entry.name = "Source_%s" % source_name.validate_node_name()
				entry.position = rect.position
				entry.size = rect.size
				entry.add_theme_font_override("font", _font_for_rule("Default"))
				entry.add_theme_font_size_override("font_size", _source_font_size("Default", 12))
				control = entry
			"ListPanel":
				control = _build_source_key_list(rect)
				control.name = "Source_%s" % source_name.validate_node_name()
			"ImagePanel":
				var image_panel := TextureRect.new()
				image_panel.name = "Source_%s" % source_name.validate_node_name()
				image_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				image_panel.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				image_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				image_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if tab_key == "voice" and source_name in ["MicMeter", "MicMeter2"]:
					var live_meter := source_name == "MicMeter2"
					image_panel.texture = vgui_source.mic_meter_texture(live_meter)
					image_panel.visible = not live_meter
					image_panel.set_meta("mic_meter_state", "live" if live_meter else "dead")
				control = image_panel
			"Panel":
				if tab_key == "voice" and source_name == "#GameUI_MicrophoneVolume":
					var transmit := HSlider.new()
					transmit.name = "Source_MicrophoneVolume"
					transmit.min_value = 0
					transmit.max_value = 100
					transmit.value = 75
					_style_vgui_slider(transmit)
					control = transmit
				else:
					var source_panel := ColorRect.new()
					source_panel.name = "Source_%s" % source_name.validate_node_name()
					source_panel.color = Color(0.0, 0.0, 0.0, 0.12)
					source_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
					control = source_panel
			_:
				var panel := ColorRect.new()
				panel.name = "Source_%s" % source_name.validate_node_name()
				panel.position = rect.position
				panel.size = rect.size
				panel.color = Color(0.0, 0.0, 0.0, 0.12)
				panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
				control = panel
		control.position = rect.position
		control.size = rect.size
		if control.get_parent() == null:
			page.add_child(control)
		control.set_meta("app90_source", source_path)
		control.set_meta("app90_control", source_name)
		control.set_meta("tab_position", int(data.get("tabPosition", 0)))
		control.set_meta("default", int(data.get("default", data.get("Default", 0))) != 0)
		control.set_meta("command", str(data.get("command", data.get("Command", ""))))
		_bind_source_option_control(tab_key, source_name, control)
		if control.focus_mode != Control.FOCUS_NONE and int(data.get("tabPosition", 0)) > 0:
			focus_controls.append(control)
	focus_controls.sort_custom(
		func(a: Control, b: Control) -> bool:
			return int(a.get_meta("tab_position")) < int(b.get_meta("tab_position"))
	)
	for index in focus_controls.size():
		var control := focus_controls[index]
		control.focus_neighbor_top = control.get_path_to(
			focus_controls[(index - 1 + focus_controls.size()) % focus_controls.size()]
		)
		control.focus_neighbor_bottom = control.get_path_to(
			focus_controls[(index + 1) % focus_controls.size()]
		)
	page.set_meta("source_focus_count", focus_controls.size())


func _bind_source_option_control(tab_key: String, source_name: String, control: Control) -> void:
	if tab_key == "multiplayer" and source_name == "NameEntry" and control is LineEdit:
		var entry := control as LineEdit
		entry.max_length = settings.MAX_PLAYER_NAME_LENGTH
		entry.text = settings.player_name
		entry.text_changed.connect(func(value: String) -> void: _options_pending["player_name"] = value)
	elif tab_key == "multiplayer" and source_name in ["CrosshairSizeComboBox", "CrosshairColorComboBox"] and control is OptionButton:
		var key := "crosshair_size" if source_name == "CrosshairSizeComboBox" else "crosshair_color"
		var option := control as OptionButton
		option.select(int(settings.get(key)))
		option.item_selected.connect(func(index: int) -> void:
			_options_pending[key] = index
			_refresh_crosshair_preview()
		)
	elif tab_key == "multiplayer" and source_name == "CrosshairTranslucencyCheckbox" and control is CheckBox:
		var translucent := control as CheckBox
		translucent.button_pressed = settings.crosshair_translucent
		translucent.toggled.connect(func(enabled: bool) -> void:
			_options_pending["crosshair_translucent"] = enabled
			_refresh_crosshair_preview()
		)
	elif tab_key == "multiplayer" and source_name == "CrosshairImage" and control is TextureRect:
		# GameUI previews the chosen crosshair in this panel.
		var preview := Control.new()
		preview.name = "CrosshairPreview"
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.draw.connect(func() -> void: _draw_crosshair_preview(preview))
		control.add_child(preview)
		_crosshair_preview = preview
	elif tab_key == "mouse" and source_name == "SensitivityLabel" and control is LineEdit:
		# GameUI shows the slider's value beside it.
		var value_entry := control as LineEdit
		value_entry.editable = false
		value_entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_entry.text = "%.2f" % settings.mouse_sensitivity
	elif tab_key == "mouse" and source_name == "ReverseMouse" and control is CheckBox:
		var reverse := control as CheckBox
		reverse.button_pressed = settings.invert_y
		reverse.toggled.connect(
			func(enabled: bool) -> void:
				_options_pending["invert_y"] = enabled
		)
	elif tab_key == "mouse" and source_name == "Slider" and control is HSlider:
		var sensitivity := control as HSlider
		sensitivity.min_value = 0.03
		sensitivity.max_value = 0.35
		sensitivity.step = 0.01
		sensitivity.value = settings.mouse_sensitivity
		sensitivity.value_changed.connect(
			func(value: float) -> void:
				_options_pending["mouse_sensitivity"] = value
				_sync_sensitivity_value()
		)
	elif tab_key == "audio" and source_name == "SFX Slider" and control is HSlider:
		var volume := control as HSlider
		volume.min_value = -40
		volume.max_value = 6
		volume.step = 1
		volume.value = settings.master_volume_db
		volume.value_changed.connect(
			func(value: float) -> void: _options_pending["master_volume_db"] = value
		)
	elif tab_key == "video" and source_name == "VSync" and control is CheckBox:
		var vsync := control as CheckBox
		vsync.button_pressed = settings.vsync_enabled
		vsync.toggled.connect(
			func(enabled: bool) -> void:
				_options_pending["vsync_enabled"] = enabled
		)
	elif tab_key == "voice" and source_name == "#GameUI_MicrophoneVolume" and control is HSlider:
		var transmit := control as HSlider
		transmit.value = float(_options_pending.get("voice_transmit_volume", 75.0))
		transmit.value_changed.connect(
			func(value: float) -> void: _options_pending["voice_transmit_volume"] = value
		)
	elif tab_key == "voice" and source_name == "VoiceReceive" and control is HSlider:
		var receive := control as HSlider
		receive.value = float(_options_pending.get("voice_receive_volume", 75.0))
		receive.value_changed.connect(
			func(value: float) -> void: _options_pending["voice_receive_volume"] = value
		)
	elif tab_key == "voice" and source_name == "voice_modenable" and control is CheckBox:
		var voice_enabled := control as CheckBox
		voice_enabled.button_pressed = bool(_options_pending.get("voice_enabled", true))
		voice_enabled.toggled.connect(
			func(enabled: bool) -> void: _options_pending["voice_enabled"] = enabled
		)
	elif tab_key == "voice" and source_name == "MicBoost" and control is CheckBox:
		var mic_boost := control as CheckBox
		mic_boost.button_pressed = bool(_options_pending.get("mic_boost", false))
		mic_boost.toggled.connect(
			func(enabled: bool) -> void: _options_pending["mic_boost"] = enabled
		)


func _build_source_key_list(rect: Rect2) -> Control:
	# GameUI's key list: an inset two-column table (action, key) with a
	# selectable row. Bindable rows edit through Edit/Clear/Defaults; rows the
	# game has no command for are dimmed, and menu digits stay fixed.
	var panel := Control.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.clip_contents = true
	var inset := ColorRect.new()
	inset.name = "Inset"
	inset.color = Color(0.0, 0.0, 0.0, 0.22)
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(inset)
	var key_x := roundf(rect.size.x * 0.58)
	var header := Control.new()
	header.name = "Header"
	header.size = Vector2(rect.size.x, KEY_LIST_HEADER_HEIGHT)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header_fill := ColorRect.new()
	header_fill.color = Color(0.0, 0.0, 0.0, 0.28)
	header_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	header.add_child(header_fill)
	for column: Array in [["Action", 6.0, key_x - 12.0], ["Key or button", key_x, rect.size.x - key_x - 20.0]]:
		var title := _vgui_text(str(column[0]), _source_font_size("DefaultSmall", 12), GAMEUI_MENU_TEXT_BRIGHT, "DefaultSmall")
		title.name = "Column_%s" % str(column[0]).validate_node_name()
		title.position = Vector2(float(column[1]), 0)
		title.size = Vector2(float(column[2]), KEY_LIST_HEADER_HEIGHT)
		header.add_child(title)
	panel.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(0, KEY_LIST_HEADER_HEIGHT + 2)
	scroll.size = Vector2(rect.size.x, rect.size.y - KEY_LIST_HEADER_HEIGHT - 2)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_vgui_scrollbar(scroll)
	scroll.set_meta("app90_source", CS16VGuiSource.BINDING_LIST)
	var rows := VBoxContainer.new()
	rows.name = "Bindings"
	rows.custom_minimum_size.x = rect.size.x - 16
	rows.add_theme_constant_override("separation", 0)
	scroll.add_child(rows)
	panel.add_child(scroll)
	var source_rows := vgui_source.key_bindings()
	for index in source_rows.size():
		var item: Dictionary = source_rows[index]
		if bool(item.is_separator):
			continue
		var command := str(item.command)
		if bool(item.is_heading):
			var heading := _vgui_text(str(item.label), _source_font_size("DefaultSmall", 12), vgui_blue, "DefaultSmall")
			heading.name = "BindingHeading_%d" % index
			heading.custom_minimum_size.y = KEY_LIST_ROW_HEIGHT + 4
			heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			heading.set_meta("source_command", command)
			rows.add_child(heading)
			continue
		rows.add_child(_key_list_row(command, str(item.label), str(item.label_token), key_x, rect.size.x - 16))
	scroll.set_meta("source_row_count", rows.get_child_count())
	_key_list = rows
	_refresh_key_list()
	return panel


func _key_list_row(command: String, label: String, label_token: String, key_x: float, width: float) -> Control:
	var row := Control.new()
	row.name = "Binding_%s" % command.validate_node_name()
	row.custom_minimum_size = Vector2(width, KEY_LIST_ROW_HEIGHT)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.set_meta("source_command", command)
	row.set_meta("source_label_token", label_token)
	var highlight := ColorRect.new()
	highlight.name = "Highlight"
	highlight.color = Color(0.0, 0.0, 0.0, 0.45)
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.visible = false
	row.add_child(highlight)
	var bindable := KeyBindings.is_bindable(command)
	var color := GAMEUI_MENU_TEXT if bindable else GAMEUI_MENU_TEXT_DIM.darkened(0.3)
	var action := _vgui_text(label, _source_font_size("DefaultSmall", 12), color, "DefaultSmall")
	action.name = "Action"
	action.position = Vector2(6, 0)
	action.size = Vector2(key_x - 12, KEY_LIST_ROW_HEIGHT)
	row.add_child(action)
	var key := _vgui_text("", _source_font_size("DefaultSmall", 12), color, "DefaultSmall")
	key.name = "Key"
	key.position = Vector2(key_x, 0)
	key.size = Vector2(width - key_x, KEY_LIST_ROW_HEIGHT)
	row.add_child(key)
	row.gui_input.connect(func(event: InputEvent) -> void: _on_key_row_input(command, event))
	return row


## Re-renders every row's key from the pending (unapplied) bindings.
func _refresh_key_list() -> void:
	if not is_instance_valid(_key_list):
		return
	var bindings: Dictionary = _options_pending.get("key_bindings", settings.bindings() if settings != null else {})
	for row in _key_list.get_children():
		var key_label := row.get_node_or_null("Key") as Label
		if key_label == null:
			continue
		var command := str(row.get_meta("source_command", ""))
		var text := str(bindings.get(command, KeyBindings.FIXED.get(command, "")))
		if command == _key_capture_command:
			text = "Press a key... (Esc cancels)"
		key_label.text = text
		row.set_meta("binding", text)
		(row.get_node("Highlight") as ColorRect).visible = command == _key_selected_command


func _on_key_row_input(command: String, event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT or not _key_capture_command.is_empty():
		return
	_key_selected_command = command
	_refresh_key_list()
	if click.double_click:
		_begin_key_capture()


func _begin_key_capture() -> void:
	if not KeyBindings.is_bindable(_key_selected_command):
		show_banner("SELECT AN ACTION THAT CAN BE REBOUND", Color("#ffca66"), 1.5)
		return
	_key_capture_command = _key_selected_command
	_refresh_key_list()


func _clear_selected_key() -> void:
	if not KeyBindings.is_bindable(_key_selected_command):
		return
	var bindings: Dictionary = _options_pending.get("key_bindings", settings.bindings()).duplicate()
	bindings[_key_selected_command] = ""
	_options_pending["key_bindings"] = bindings
	_refresh_key_list()


## Assigns the captured key; a key another command used moves here (GameUI).
func _assign_captured_key(key_text: String) -> void:
	var bindings: Dictionary = _options_pending.get("key_bindings", settings.bindings()).duplicate()
	for other: String in bindings:
		if other != _key_capture_command and str(bindings[other]) == key_text:
			bindings[other] = ""
	bindings[_key_capture_command] = key_text
	_options_pending["key_bindings"] = bindings
	_key_capture_command = ""
	_refresh_key_list()


func _input(event: InputEvent) -> void:
	# While capturing, the next key or mouse button belongs to the binding.
	if _key_capture_command.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		_key_capture_command = ""
		_refresh_key_list()
		return
	var text := KeyBindings.event_text(event)
	if text.is_empty():
		return
	_assign_captured_key(text)

func _source_option_choices(source_name: String) -> Array[String]:
	var lower := source_name.to_lower()
	if "resolution" in lower:
		return ["640 x 480", "800 x 600", "1024 x 768"]
	if "aspect" in lower:
		return ["Normal", "Widescreen"]
	if "renderer" in lower:
		return ["OpenGL", "Software"]
	if "quality" in lower:
		return ["High", "Low"]
	if "crosshair" in lower and "color" in lower:
		return ["Green", "Red", "Blue", "Yellow", "Light Blue"]
	if "crosshair" in lower and "size" in lower:
		return ["Auto-Size", "Small", "Medium", "Large"]
	return ["Default"]


func _on_source_option_command(tab_key: String, command: String) -> void:
	menu_command_requested.emit("options:%s:%s" % [tab_key, command])
	if tab_key == "voice" and command.to_lower() == "testmicrophone":
		voice_test_requested.emit()
		return
	if tab_key == "keyboard":
		match command.to_lower():
			"defaults":
				_options_pending["key_bindings"] = KeyBindings.default_bindings()
				_key_capture_command = ""
				_refresh_key_list()
			"changekey":
				_begin_key_capture()
			"clearkey":
				_clear_selected_key()
		return
	if command.to_lower() == "defaults":
		_options_defaults()


func _settings_values() -> Dictionary:
	return {
		"player_name": settings.player_name,
		"mouse_sensitivity": settings.mouse_sensitivity,
		"invert_y": settings.invert_y,
		"field_of_view": settings.field_of_view,
		"performance_preset": settings.performance_preset,
		"vsync_enabled": settings.vsync_enabled,
		"master_volume_db": settings.master_volume_db,
		"crosshair_size": settings.crosshair_size,
		"crosshair_color": settings.crosshair_color,
		"crosshair_translucent": settings.crosshair_translucent,
		"key_bindings": settings.bindings(),
		"voice_transmit_volume": settings.voice_transmit_volume,
		"voice_receive_volume": settings.voice_receive_volume,
		"voice_enabled": settings.voice_enabled,
		"mic_boost": settings.voice_mic_boost,
	}


func _restore_settings(values: Dictionary) -> void:
	settings.update_player_name(str(values.get("player_name", settings.player_name)))
	settings.update_input(float(values.mouse_sensitivity), bool(values.invert_y))
	settings.update_video(
		float(values.field_of_view),
		int(values.performance_preset),
		bool(values.vsync_enabled),
	)
	settings.update_volume(float(values.master_volume_db))
	settings.update_key_bindings(values.get("key_bindings", settings.bindings()))
	settings.update_voice(
		bool(values.get("voice_enabled", settings.voice_enabled)),
		float(values.get("voice_transmit_volume", settings.voice_transmit_volume)),
		float(values.get("voice_receive_volume", settings.voice_receive_volume)),
		bool(values.get("mic_boost", settings.voice_mic_boost)),
	)
	settings.update_crosshair(
		int(values.get("crosshair_size", settings.crosshair_size)),
		int(values.get("crosshair_color", settings.crosshair_color)),
		bool(values.get("crosshair_translucent", settings.crosshair_translucent)),
	)


func _options_apply() -> void:
	var values := _options_pending.duplicate(true)
	_restore_settings(values)
	values.player_name = settings.player_name
	_options_pending = values.duplicate(true)
	_sync_source_option_controls()
	options_apply_requested.emit(values)
	menu_command_requested.emit("options_apply")
	_options_snapshot = values.duplicate(true)


func _options_ok() -> void:
	_options_apply()
	_show_pause_main()


func _options_cancel() -> void:
	_options_pending = _options_snapshot.duplicate(true)
	options_cancel_requested.emit()
	menu_command_requested.emit("options_cancel")
	_show_pause_main()


func _options_defaults() -> void:
	_options_pending.merge({
		"mouse_sensitivity": 0.12,
		"invert_y": false,
		"field_of_view": 90.0,
		"performance_preset": 1,
		"vsync_enabled": true,
		"master_volume_db": 0.0,
		"crosshair_size": 0,
		"crosshair_color": 0,
		"crosshair_translucent": true,
		"voice_transmit_volume": 75.0,
		"voice_receive_volume": 75.0,
		"voice_enabled": true,
		"mic_boost": false,
	}, true)
	_sync_source_option_controls()
	options_defaults_requested.emit(_options_page_key)
	menu_command_requested.emit("options_defaults:%s" % _options_page_key)


func _sync_source_option_controls() -> void:
	var name_entry := options_pages.get_node_or_null("Page_multiplayer/Source_NameEntry") as LineEdit
	if name_entry != null:
		name_entry.text = str(_options_pending.player_name)
	var reverse := options_pages.get_node_or_null("Page_mouse/Source_ReverseMouse") as CheckBox
	var sensitivity := options_pages.get_node_or_null("Page_mouse/Source_Slider") as HSlider
	var volume := options_pages.get_node_or_null("Page_audio/Source_SFX Slider") as HSlider
	var vsync := options_pages.get_node_or_null("Page_video/Source_VSync") as CheckBox
	var transmit := options_pages.get_node_or_null("Page_voice/Source_MicrophoneVolume") as HSlider
	var receive := options_pages.get_node_or_null("Page_voice/Source_VoiceReceive") as HSlider
	var voice_enabled := options_pages.get_node_or_null("Page_voice/Source_voice_modenable") as CheckBox
	var mic_boost := options_pages.get_node_or_null("Page_voice/Source_MicBoost") as CheckBox
	if reverse != null:
		reverse.button_pressed = bool(_options_pending.invert_y)
	if sensitivity != null:
		sensitivity.value = float(_options_pending.mouse_sensitivity)
	_sync_sensitivity_value()
	if volume != null:
		volume.value = float(_options_pending.master_volume_db)
	if vsync != null:
		vsync.button_pressed = bool(_options_pending.vsync_enabled)
	if transmit != null:
		transmit.value = float(_options_pending.voice_transmit_volume)
	if receive != null:
		receive.value = float(_options_pending.voice_receive_volume)
	if voice_enabled != null:
		voice_enabled.button_pressed = bool(_options_pending.voice_enabled)
	if mic_boost != null:
		mic_boost.button_pressed = bool(_options_pending.mic_boost)
	var crosshair_size_option := options_pages.get_node_or_null("Page_multiplayer/Source_CrosshairSizeComboBox") as OptionButton
	var crosshair_color_option := options_pages.get_node_or_null("Page_multiplayer/Source_CrosshairColorComboBox") as OptionButton
	var crosshair_translucent := options_pages.get_node_or_null("Page_multiplayer/Source_CrosshairTranslucencyCheckbox") as CheckBox
	if crosshair_size_option != null:
		crosshair_size_option.select(int(_options_pending.get("crosshair_size", 0)))
	if crosshair_color_option != null:
		crosshair_color_option.select(int(_options_pending.get("crosshair_color", 0)))
	if crosshair_translucent != null:
		crosshair_translucent.set_pressed_no_signal(bool(_options_pending.get("crosshair_translucent", true)))
	_refresh_crosshair_preview()
	_key_capture_command = ""
	_refresh_key_list()


## Lights the live microphone meter up to level (0..1) in the Voice tab.
func set_mic_meter_level(level: float) -> void:
	var live := options_pages.get_node_or_null("Page_voice/Source_MicMeter2") as TextureRect
	if live == null:
		return
	var full := vgui_source.mic_meter_texture(true)
	var width := roundf(float(full.get_width()) * clampf(level * 4.0, 0.0, 1.0))
	live.visible = width >= 1.0
	if not live.visible:
		return
	var lit := live.texture as AtlasTexture
	if lit == null:
		lit = AtlasTexture.new()
		lit.atlas = full
		live.texture = lit
		live.stretch_mode = TextureRect.STRETCH_KEEP
	lit.region = Rect2(0, 0, width, full.get_height())


func voice_options_visible() -> bool:
	return is_instance_valid(pause_options_menu) and pause_options_menu.visible and _options_page_key == "voice"


func _sync_sensitivity_value() -> void:
	var value_entry := options_pages.get_node_or_null("Page_mouse/Source_SensitivityLabel") as LineEdit
	if value_entry != null:
		value_entry.text = "%.2f" % float(_options_pending.get("mouse_sensitivity", settings.mouse_sensitivity))


func _show_options_tab(tab_key: String) -> void:
	_options_page_key = tab_key
	for page in options_pages.get_children():
		page.visible = page.name == "Page_%s" % tab_key
	# GameUI raises/highlights the active tab: it reads as a lit plate joined
	# to the page while the resting tabs stay flat dim text.
	if is_instance_valid(options_tab_bar):
		for tab_variant in options_tab_bar.get_children():
			var tab := tab_variant as Button
			if tab == null:
				continue
			var active := tab.name == "Tab_%s" % tab_key
			tab.add_theme_stylebox_override(
				"normal",
				_panel_style(
					Color(0.40, 0.45, 0.36, 1.0) if active else Color(0.0, 0.0, 0.0, 0.10),
					Color(0.62, 0.66, 0.56, 1.0) if active else Color(0.30, 0.33, 0.27, 1.0),
					0,
				),
			)
			tab.add_theme_color_override(
				"font_color",
				GAMEUI_MENU_TEXT_BRIGHT if active else GAMEUI_MENU_TEXT_DIM,
			)
	_set_menu_state("options_%s" % tab_key)


func _build_accessibility_overlay() -> void:
	accessibility_overlay = PanelContainer.new()
	accessibility_overlay.name = "AccessibilityExtension"
	accessibility_overlay.position = Vector2(110, 92)
	accessibility_overlay.size = Vector2(420, 296)
	accessibility_overlay.visible = false
	# Keep this non-parity extension visually inside the GameUI scheme: tan on
	# olive, square borderless panel, mixed-case labels.
	accessibility_overlay.add_theme_stylebox_override("panel", _panel_style(GAMEUI_PANEL, GAMEUI_PANEL_BORDER, 0))
	pause_canvas.add_child(accessibility_overlay)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	accessibility_overlay.add_child(page)
	page.add_child(_vgui_text("Accessibility", 15, GAMEUI_MENU_TEXT))
	page.add_child(_vgui_text("These controls are additive and are not part of the CS 1.6 parity surface.", 10, GAMEUI_MENU_TEXT_DIM))
	var sensitivity_value := _vgui_text(
		"Crosshair scale  %.2f" % settings.crosshair_scale,
		11,
		GAMEUI_MENU_TEXT,
	)
	var crosshair_size := HSlider.new()
	crosshair_size.min_value = 0.75
	crosshair_size.max_value = 2.0
	crosshair_size.step = 0.25
	crosshair_size.value = settings.crosshair_scale
	_style_vgui_slider(crosshair_size)
	crosshair_size.value_changed.connect(func(value: float) -> void:
		sensitivity_value.text = "Crosshair scale  %.2f" % value
		settings.update_accessibility(value, settings.high_contrast, settings.reduced_motion)
	)
	page.add_child(sensitivity_value)
	page.add_child(crosshair_size)
	var contrast := _vgui_check("High-contrast crosshair", settings.high_contrast)
	contrast.toggled.connect(func(enabled: bool) -> void: settings.update_accessibility(settings.crosshair_scale, enabled, settings.reduced_motion))
	page.add_child(contrast)
	var reduced_motion := _vgui_check("Reduced camera motion", settings.reduced_motion)
	reduced_motion.toggled.connect(func(enabled: bool) -> void: settings.update_accessibility(settings.crosshair_scale, settings.high_contrast, enabled))
	page.add_child(reduced_motion)
	var back := _vgui_button(page, "AccessibilityBack", "Back to options", Vector2.ZERO, Vector2(140, 24), _hide_accessibility, 11)
	back.custom_minimum_size = Vector2(140, 24)


func _show_accessibility() -> void:
	pause_options_menu.visible = false
	accessibility_overlay.visible = true
	_set_menu_state("accessibility_extension")


func _hide_accessibility() -> void:
	accessibility_overlay.visible = false
	pause_options_menu.visible = true
	_show_options_tab("multiplayer")


func _show_pause_options() -> void:
	network_menu.hide()
	pause_main_menu.visible = false
	pause_options_menu.visible = true
	accessibility_overlay.visible = false
	_options_snapshot = _settings_values().duplicate(true)
	_options_pending = _options_snapshot.duplicate(true)
	_sync_source_option_controls()
	_show_options_tab("multiplayer")


func _show_pause_main() -> void:
	if is_instance_valid(network_menu):
		network_menu.hide()
	pause_options_menu.visible = false
	accessibility_overlay.visible = false
	pause_main_menu.visible = true
	_set_menu_state("pause")


func _vgui_frame(
	parent: Control,
	frame_name: String,
	source_path := "",
	source_control := "",
	shade_width := 172.0,
) -> Control:
	var frame := Control.new()
	frame.name = frame_name
	var source_rect := Rect2(VGUI_MENU_ORIGIN, VGUI_MENU_SIZE)
	if not source_path.is_empty() and not source_control.is_empty():
		source_rect = vgui_source.control_rect(
			source_path,
			source_control,
			source_rect,
			VGUI_BASE_SIZE,
		)
	frame.position = source_rect.position
	frame.size = source_rect.size
	frame.set_meta("app90_source", source_path)
	frame.set_meta("app90_control", source_control)
	parent.add_child(frame)
	# Classic VGUI menus sit on a compact near-black translucent panel behind
	# the option column, not a full-height light backdrop. Steam-era VGUI
	# panels have rounded corners and a visible scheme border (BorderBright).
	var shade := _vgui_dialog_panel(
		"FrameShade",
		Vector2(-12, 12),
		Vector2(shade_width, frame.size.y - 24.0),
	)
	frame.add_child(shade)
	frame.move_child(shade, 0)
	return frame


func _relative_source_rect(
	source_path: String,
	control_name: String,
	fallback: Rect2,
	_frame_origin: Vector2,
) -> Rect2:
	# Team/class child coordinates are authored relative to their 552x448 wizard
	# panel. Preserve them verbatim instead of reinterpreting them as viewport
	# coordinates.
	return vgui_source.control_rect(source_path, control_name, fallback, VGUI_BASE_SIZE)


func _source_font_size(font_name: String, fallback: int) -> int:
	return vgui_source.font_size(font_name, int(VGUI_BASE_SIZE.y), fallback)


func _font_for_rule(font_name: String) -> Font:
	if _vgui_fonts.has(font_name):
		return _vgui_fonts[font_name] as Font
	var spec := vgui_source.font_spec(font_name, int(VGUI_BASE_SIZE.y), {
		"name": "Verdana",
		"tall": 12,
		"weight": 400,
	})
	if OS.has_feature("web") or "--web-fonts" in OS.get_cmdline_user_args():
		# Browsers expose no system fonts, so a SystemFont silently becomes the
		# engine's wider default face and overflows the VGUI layouts. Ship a
		# Verdana-metric face (DejaVu Sans, Bitstream Vera license) instead.
		# --web-fonts previews the browser layout on desktop.
		var web_font: Font = WEB_VGUI_FONT_BOLD if int(spec.get("weight", 400)) >= 600 else WEB_VGUI_FONT
		_vgui_fonts[font_name] = web_font
		return web_font
	var font := SystemFont.new()
	var requested_name := str(spec.get("name", "Verdana")).replace(" Bold", "")
	font.font_names = PackedStringArray([
		requested_name, "Trebuchet MS", "Verdana", "Tahoma", "Arial",
	])
	font.font_weight = int(spec.get("weight", 400))
	_vgui_fonts[font_name] = font
	return font


func _make_flow_canvas(parent: Control, canvas_name: String) -> Control:
	var canvas := Control.new()
	canvas.name = canvas_name
	canvas.size = VGUI_BASE_SIZE
	canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(canvas)
	_flow_canvases.append(canvas)
	return canvas


func layout_for_viewport(viewport_size: Vector2) -> void:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var scale_factor := minf(
		viewport_size.x / VGUI_BASE_SIZE.x,
		viewport_size.y / VGUI_BASE_SIZE.y,
	)
	var scaled_size := VGUI_BASE_SIZE * scale_factor
	var offset := (viewport_size - scaled_size) * 0.5
	for canvas in _flow_canvases:
		canvas.scale = Vector2.ONE * scale_factor
		canvas.position = offset
		canvas.set_meta("reference_scale", scale_factor)
		canvas.set_meta("reference_offset", offset)
	_update_crosshair_scale()


func _update_crosshair_scale() -> void:
	# CS 1.6 draws the crosshair in physical pixels: hard-edged 1px arms at
	# every resolution. Rebuild the four segments in physical-pixel units
	# (converted through the canvas-items stretch factor) so they stay
	# hairline-thin with hard ends instead of fattening or blurring.
	if not is_instance_valid(crosshair):
		return
	for child in crosshair.get_children():
		child.free()
	var stretch := 1.0
	var window := get_window()
	var parent := crosshair.get_parent() as Control
	if window != null and parent != null and parent.size.y > 0.0:
		stretch = maxf(float(window.size.y) / parent.size.y, 0.001)
	var user_scale: float = settings.crosshair_scale if settings != null else 1.0
	user_scale *= _crosshair_size_factor(
		settings.crosshair_size if settings != null else 0, float(window.size.y) if window != null else 720.0)
	var arm := maxf(1.0, roundf(9.0 * user_scale))
	var gap := maxf(1.0, roundf(3.0 * user_scale)) + _crosshair_spread_px
	var color := _crosshair_color()
	crosshair.scale = Vector2.ONE
	# Pin the (zero-sized) control exactly to the parent's center via offsets;
	# assigning `position` here would re-anchor it to the parent's top-left.
	crosshair.offset_left = 0.0
	crosshair.offset_top = 0.0
	crosshair.offset_right = 0.0
	crosshair.offset_bottom = 0.0
	for rect: Rect2 in [
		Rect2(-1.0, -gap - arm, 1.0, arm),
		Rect2(-1.0, gap, 1.0, arm),
		Rect2(-gap - arm, -1.0, arm, 1.0),
		Rect2(gap, -1.0, arm, 1.0),
	]:
		var line := ColorRect.new()
		line.position = rect.position / stretch
		line.size = rect.size / stretch
		line.color = color
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(line)


func set_crosshair_spread(spread_px: int) -> void:
	# Classic dynamic gap: movement/firing widens the arm gap in pixels.
	var clamped := clampi(spread_px, 0, 24)
	if clamped == _crosshair_spread_px:
		return
	_crosshair_spread_px = clamped
	_update_crosshair_scale()


func _vgui_label(
	parent: Control,
	label_name: String,
	text: String,
	position: Vector2,
	size: Vector2,
	font_size: int,
	color: Color,
	wrap := false,
	font_rule := "Default",
) -> Label:
	var label := _vgui_text(text, font_size, color, font_rule)
	label.name = label_name
	label.position = position
	label.size = size
	label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
		if wrap
		else TextServer.AUTOWRAP_OFF
	)
	parent.add_child(label)
	return label


func _vgui_text(text: String, font_size: int, color: Color, font_rule := "Default") -> Label:
	var label := Label.new()
	label.text = text
	var source_font := _font_for_rule(font_rule)
	label.add_theme_font_override("font", source_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.clip_text = true
	label.set_meta("source_font_rule", font_rule)
	label.set_meta("source_baseline", source_font.get_ascent(font_size))
	return label


static func _fitted_font_size(font: Font, text: String, font_size: int, available_width: float) -> int:
	var fitted := font_size
	if font == null or available_width <= 0.0:
		return fitted
	while fitted > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fitted).x > available_width:
		fitted -= 1
	return fitted


func _vgui_button(
	parent: Node,
	button_name: String,
	text: String,
	position: Vector2,
	size: Vector2,
	action: Callable,
	font_size := 12,
	_bordered := false,
) -> Button:
	var button := Button.new()
	button.name = button_name
	var clean_text := text.replace("&&", "\u001f")
	var accelerator_index := clean_text.find("&")
	clean_text = clean_text.replace("&", "").replace("\u001f", "&")
	button.text = clean_text
	button.position = position
	button.size = size
	button.custom_minimum_size = size
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Keep the source row width: a label wider than its slot (long class
	# names, or a wider fallback face) shrinks to fit instead of growing the
	# row into neighbouring panels.
	button.clip_text = true
	font_size = _fitted_font_size(_vgui_font, clean_text, font_size, size.x - 12.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", _vgui_font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", vgui_amber_dim)
	button.add_theme_color_override("font_hover_color", vgui_amber)
	button.add_theme_color_override("font_focus_color", vgui_amber)
	button.add_theme_color_override("font_pressed_color", vgui_amber)
	# VGUI1 list rows (team/class/buy) are bare text on the dialog surface —
	# no per-row plate and no amber outline; the armed row only gets a faint
	# translucent highlight. GameUI rows behave the same way.
	button.clip_contents = true
	var row_border := Color(0.0, 0.0, 0.0, 0.0)
	var row_fill := Color(0.0, 0.0, 0.0, 0.0)
	button.add_theme_stylebox_override(
		"normal",
		_panel_style(row_fill, row_border, 0),
	)
	button.add_theme_stylebox_override(
		"hover",
		_panel_style(Color(1.0, 0.69, 0.0, 0.14), row_border, 0),
	)
	button.add_theme_stylebox_override(
		"focus",
		_panel_style(Color(1.0, 0.69, 0.0, 0.10), row_border, 0),
	)
	button.add_theme_stylebox_override(
		"pressed",
		_panel_style(Color(1.0, 0.69, 0.0, 0.20), row_border, 0),
	)
	button.add_theme_stylebox_override(
		"disabled",
		_panel_style(row_fill, row_border * Color(1, 1, 1, 0.6), 0),
	)
	if accelerator_index >= 0 and accelerator_index < clean_text.length():
		var accelerator := str(clean_text[accelerator_index])
		button.set_meta("accelerator", accelerator.to_lower())
		button.set_meta("accelerator_index", accelerator_index)
		var rich := RichTextLabel.new()
		rich.name = "AcceleratorText"
		rich.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rich.offset_left = 5
		rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rich.bbcode_enabled = true
		rich.fit_content = false
		rich.scroll_active = false
		rich.autowrap_mode = TextServer.AUTOWRAP_OFF
		rich.clip_contents = true
		rich.add_theme_font_override("normal_font", _font_for_rule("DefaultUnderline"))
		rich.add_theme_font_size_override("normal_font_size", font_size)
		rich.add_theme_color_override("default_color", vgui_amber_dim)
		rich.set_meta("source_font_rule", "DefaultUnderline")
		rich.set_meta(
			"source_baseline",
			_font_for_rule("DefaultUnderline").get_ascent(font_size),
		)
		var prefix := clean_text.substr(0, accelerator_index)
		var suffix := clean_text.substr(accelerator_index + 1)
		rich.text = "%s[u]%s[/u]%s" % [prefix, accelerator, suffix]
		button.add_theme_color_override("font_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)
		button.add_child(rich)
		button.mouse_entered.connect(
			func() -> void:
				if not button.disabled:
					rich.add_theme_color_override("default_color", vgui_amber)
		)
		button.mouse_exited.connect(
			func() -> void:
				if not button.disabled:
					rich.add_theme_color_override("default_color", vgui_amber_dim)
		)
	button.mouse_entered.connect(func() -> void: ui_sound_requested.emit("common/menu1.wav"))
	button.focus_entered.connect(func() -> void: ui_sound_requested.emit("common/menu1.wav"))
	button.pressed.connect(func() -> void:
		ui_sound_requested.emit("common/menu2.wav")
		action.call()
	)
	parent.add_child(button)
	# The first size assignment cached a minimum from the theme's default font
	# before clip_text and the source font applied, and entering the tree grew
	# the row to it. Refresh the minimum and settle on the source size.
	button.update_minimum_size()
	button.size = size
	return button


func _vgui_section(text: String) -> Label:
	var section := _vgui_text(text, 11, vgui_amber_dim)
	section.custom_minimum_size.y = 18
	return section


var _check_icons: Dictionary = {}


func _vgui_check_icon(checked: bool) -> ImageTexture:
	if _check_icons.has(checked):
		return _check_icons[checked]
	var size := 13
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.82))
	for index in range(size):
		image.set_pixel(index, 0, GAMEUI_MENU_TEXT_DIM)
		image.set_pixel(index, size - 1, GAMEUI_MENU_TEXT_DIM)
		image.set_pixel(0, index, GAMEUI_MENU_TEXT_DIM)
		image.set_pixel(size - 1, index, GAMEUI_MENU_TEXT_DIM)
	if checked:
		# GameUI checkboxes draw a check GLYPH, not a filled inner square:
		# short down-stroke into a long rising stroke, 2px thick.
		for step in range(3):
			for thickness in range(2):
				var y := 6 + step + thickness
				if y < size:
					image.set_pixel(3 + step, y, GAMEUI_MENU_TEXT)
		for step in range(6):
			for thickness in range(2):
				var y := 8 - step + thickness
				if y >= 0 and y < size and 5 + step < size:
					image.set_pixel(5 + step, y, GAMEUI_MENU_TEXT)
	var texture := ImageTexture.create_from_image(image)
	_check_icons[checked] = texture
	return texture


func _vgui_check(text: String, enabled: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = enabled
	check.custom_minimum_size.y = 20
	check.add_theme_font_override("font", _vgui_font)
	check.add_theme_font_size_override("font_size", 11)
	check.add_theme_color_override("font_color", GAMEUI_MENU_TEXT)
	check.add_theme_color_override("font_hover_color", GAMEUI_MENU_TEXT_BRIGHT)
	check.add_theme_color_override("font_pressed_color", GAMEUI_MENU_TEXT)
	check.add_theme_color_override("font_focus_color", GAMEUI_MENU_TEXT_BRIGHT)
	check.add_theme_icon_override("checked", _vgui_check_icon(true))
	check.add_theme_icon_override("unchecked", _vgui_check_icon(false))
	check.add_theme_icon_override("checked_disabled", _vgui_check_icon(true))
	check.add_theme_icon_override("unchecked_disabled", _vgui_check_icon(false))
	return check


func _style_vgui_scrollbar(scroll: ScrollContainer) -> void:
	# Square dark VGUI scrollbar instead of the rounded modern default.
	var bar := scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.custom_minimum_size.x = 9
	bar.add_theme_stylebox_override(
		"scroll",
		_panel_style(Color(0.0, 0.0, 0.0, 0.55), Color(0.24, 0.24, 0.24, 1.0), 0),
	)
	for grabber_state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(
			grabber_state,
			_panel_style(
				vgui_amber_dim if grabber_state == "grabber" else vgui_amber,
				Color(0.0, 0.0, 0.0, 0.0),
				0,
			),
		)


func _style_vgui_slider(slider: HSlider) -> void:
	slider.custom_minimum_size.y = 15
	# GameUI sliders: recessed dark groove with a wide beveled tan tick knob.
	slider.add_theme_icon_override("grabber", _solid_icon(GAMEUI_MENU_TEXT_DIM, Vector2i(9, 15)))
	slider.add_theme_icon_override("grabber_highlight", _solid_icon(GAMEUI_MENU_TEXT, Vector2i(9, 15)))
	slider.add_theme_stylebox_override(
		"slider",
		_panel_style(Color(0.14, 0.16, 0.12, 1.0), Color(0.09, 0.10, 0.08, 1.0), 0),
	)
	slider.add_theme_stylebox_override(
		"grabber_area",
		_panel_style(Color(0.20, 0.23, 0.17, 1.0), Color(0.0, 0.0, 0.0, 0.0), 0),
	)
	slider.add_theme_stylebox_override(
		"grabber_area_highlight",
		_panel_style(Color(0.24, 0.27, 0.20, 1.0), Color(0.0, 0.0, 0.0, 0.0), 0),
	)


func _style_vgui_option(option: OptionButton) -> void:
	# GameUI combo boxes show plain mixed-case text in the dialog's tan
	# scheme on a recessed dark field — not amber shouting caps.
	option.custom_minimum_size.y = 22
	option.add_theme_font_override("font", _vgui_font)
	option.add_theme_font_size_override("font_size", 11)
	option.add_theme_color_override("font_color", GAMEUI_MENU_TEXT)
	option.add_theme_color_override("font_hover_color", GAMEUI_MENU_TEXT_BRIGHT)
	option.add_theme_color_override("font_focus_color", GAMEUI_MENU_TEXT_BRIGHT)
	option.add_theme_color_override("font_pressed_color", GAMEUI_MENU_TEXT_BRIGHT)
	option.add_theme_stylebox_override(
		"normal",
		_panel_style(Color(0.10, 0.11, 0.09, 0.92), Color(0.30, 0.33, 0.27, 1.0), 0),
	)


func _solid_icon(color: Color, size: Vector2i) -> ImageTexture:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	var margin := 4.0 if radius == 0 else 12.0
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _apply_accessibility() -> void:
	if not is_instance_valid(crosshair):
		return
	_update_crosshair_scale()
	_refresh_crosshair_preview()


## Crosshair color from the Multiplayer tab, unless high contrast overrides it.
## Translucent keeps the long-standing 78% alpha; opaque draws solid.
func _crosshair_color(
	color_index: int = -1,
	translucent: Variant = null,
) -> Color:
	if settings == null:
		return Color(0.1, 1.0, 0.1, 0.78)
	if settings.high_contrast:
		return Color("#fff316")
	var index: int = settings.crosshair_color if color_index < 0 else color_index
	var color: Color = settings.CROSSHAIR_COLORS[clampi(index, 0, settings.CROSSHAIR_COLORS.size() - 1)]
	color.a = 0.78 if bool(settings.crosshair_translucent if translucent == null else translucent) else 1.0
	return color


## cl_crosshair_size: small/medium/large are fixed, auto follows the window
## height (medium covers the 720p-1080p range the crosshair was tuned for).
static func _crosshair_size_factor(size_index: int, window_height: float) -> float:
	match size_index:
		1:
			return 0.75
		2:
			return 1.0
		3:
			return 1.5
	if window_height <= 600.0:
		return 0.75
	return 1.0 if window_height <= 1080.0 else 1.5


func _refresh_crosshair_preview() -> void:
	if is_instance_valid(_crosshair_preview):
		_crosshair_preview.queue_redraw()


func _draw_crosshair_preview(preview: Control) -> void:
	preview.draw_rect(Rect2(Vector2.ZERO, preview.size), Color(0.0, 0.0, 0.0, 0.55))
	var size_index := int(_options_pending.get("crosshair_size", settings.crosshair_size))
	var factor := _crosshair_size_factor(size_index, float(get_window().size.y) if get_window() != null else 720.0)
	var arm := maxf(1.0, roundf(9.0 * factor))
	var gap := maxf(1.0, roundf(3.0 * factor))
	var color := _crosshair_color(
		int(_options_pending.get("crosshair_color", settings.crosshair_color)),
		bool(_options_pending.get("crosshair_translucent", settings.crosshair_translucent)),
	)
	var center := (preview.size * 0.5).floor()
	for rect: Rect2 in [
		Rect2(-1.0, -gap - arm, 1.0, arm), Rect2(-1.0, gap, 1.0, arm),
		Rect2(-gap - arm, -1.0, arm, 1.0), Rect2(gap, -1.0, arm, 1.0),
	]:
		preview.draw_rect(Rect2(center + rect.position, rect.size), color)


func _classic_radar_texture(texture: Texture2D) -> Texture2D:
	# CS 1.6's radar (per the classic in-game reference): a translucent bright
	# green DISC with thin quadrant cross lines and a darker rim. The center
	# implicitly means "you"; blips are drawn live by the contact layer above.
	var size := 128
	if texture != null:
		size = maxi(texture.get_width(), 8)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 1.0
	var fill := Color(0.13, 0.72, 0.10, 0.55)
	var grid := Color(0.07, 0.50, 0.06, 0.65)
	var rim := Color(0.04, 0.30, 0.03, 0.85)
	for y in range(size):
		for x in range(size):
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := point.distance_to(center)
			if distance > radius:
				continue
			var color := fill
			if distance > radius - 1.6:
				color = rim
			elif absf(point.x - center.x) < 0.9 or absf(point.y - center.y) < 0.9:
				color = grid
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _vgui_dialog_panel(panel_name: String, position: Vector2, size: Vector2) -> Panel:
	# Shared chrome for classic dialog surfaces. VGUI1 panels are square-
	# cornered translucent dark grey rectangles with a thin plain border —
	# never rounded cards and never a glowing accent stroke.
	var panel := Panel.new()
	panel.name = panel_name
	panel.position = position
	panel.size = size
	var style := _panel_style(
		_dialog_panel_color(),
		Color(0.36, 0.36, 0.36, 0.85),
		0,
	)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	style.anti_aliasing = true
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.clip_contents = true
	return panel


func _dialog_panel_color() -> Color:
	# CS 1.6's VGUI dialog surfaces are semi-transparent dark panels: the world
	# clearly reads through them (roughly three-quarter opacity in-game).
	var color := vgui_source.scheme_color("WindowBG", Color(0.0, 0.0, 0.0, 0.78))
	color.a = 0.78
	return color


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _classic_label(text: String, size: int, color: Color) -> Label:
	var label := _label(text, size, color)
	label.add_theme_color_override("font_outline_color", CLASSIC_SHADOW)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _metric(value: String, caption: String, color: Color) -> Label:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -5)
	var value_label := _label(value, 32, color)
	var caption_label := _label(caption, 10, Color("#8094a5"))
	column.add_child(value_label)
	column.add_child(caption_label)
	return value_label


func update_health(health: int, armor: int, helmet := false) -> void:
	health_label.text = str(health)
	armor_label.text = str(armor)
	var health_color := CLASSIC_RED if health <= 25 else CLASSIC_ORANGE
	health_label.add_theme_color_override("font_color", health_color)
	_set_digit_row(health_digits, health_label.text, health_color, 3)
	_set_digit_row(armor_digits, armor_label.text, CLASSIC_ORANGE, 3)
	# CS 1.6 shows the vest sprite for kevlar and the vest+helmet variant
	# once a helmet is owned.
	if helmet != _has_helmet and is_instance_valid(_armor_icon):
		_has_helmet = helmet
		var sprite_name := "suithelmet_full" if helmet else "suit_full"
		_armor_icon.texture = load(
			CLASSIC_HUD_ROOT.path_join("%s.png" % sprite_name)
		) as Texture2D
		_armor_icon.set_meta("classic_sprite", sprite_name)


func update_ammo(clip: int, reserve: int, reloading: bool) -> void:
	ammo_label.text = "--" if clip < 0 else str(clip)
	reserve_label.text = "" if reserve < 0 else str(reserve)
	var ammo_color := CLASSIC_RED if clip >= 0 and clip <= 5 else CLASSIC_ORANGE
	ammo_label.add_theme_color_override("font_color", ammo_color)
	_set_digit_row(ammo_digits, ammo_label.text, ammo_color, 3)
	_set_digit_row(reserve_digits, reserve_label.text, CLASSIC_ORANGE, 3)


func update_weapon(weapon_name: String, fire_mode: String) -> void:
	_weapon_name = weapon_name
	_fire_mode = fire_mode
	if not is_instance_valid(_ammo_icon):
		return
	var sprite_name := str(AMMO_ICONS.get(weapon_name.to_upper(), ""))
	if sprite_name.is_empty():
		# Knife/C4-style items draw no caliber icon in CS 1.6.
		_ammo_icon.visible = false
		return
	_ammo_icon.visible = true
	if str(_ammo_icon.get_meta("classic_sprite", "")) != sprite_name:
		_ammo_icon.texture = load(
			CLASSIC_HUD_ROOT.path_join("%s.png" % sprite_name)
		) as Texture2D
		_ammo_icon.set_meta("classic_sprite", sprite_name)


func update_defuse_kit(team: String, alive: bool, owns_kit: bool) -> void:
	_has_defuse_kit = team == "CT" and alive and owns_kit
	_refresh_gameplay_visibility()


func update_bomb_carrier(carrying: bool, in_bomb_zone: bool) -> void:
	var flashing := carrying and in_bomb_zone
	if carrying == _carrying_c4 and flashing == _c4_in_bomb_zone:
		return
	_carrying_c4 = carrying
	_c4_in_bomb_zone = flashing
	if is_instance_valid(_c4_flash):
		_c4_flash.kill()
		_c4_flash = null
	if is_instance_valid(_c4_icon):
		_c4_icon.modulate.a = 1.0
		if flashing:
			_c4_flash = _c4_icon.create_tween().set_loops()
			_c4_flash.tween_property(_c4_icon, "modulate:a", 0.15, 0.25)
			_c4_flash.tween_property(_c4_icon, "modulate:a", 1.0, 0.25)
	_refresh_gameplay_visibility()


func update_defuse_progress(active: bool, elapsed: float, total: float) -> void:
	_defuse_progress_active = active and total > 0.0
	var ratio := clampf(elapsed / total, 0.0, 1.0) if _defuse_progress_active else 0.0
	if is_instance_valid(_defuse_progress_fill):
		_defuse_progress_fill.size.x = 196.0 * ratio
	_refresh_gameplay_visibility()


func set_buy_zone(active: bool) -> void:
	# Mirrors CS 1.6's buyzone icon contract: shown only while the player
	# stands in a buy zone during buy time (and never under a modal menu).
	_in_buy_zone = active
	_refresh_gameplay_visibility()


func update_tactical_display(
	observer_position: Vector3,
	observer_yaw: float,
	teammates: Array[Dictionary],
	hostages: Array[Dictionary],
) -> void:
	radar_display.set_snapshot(observer_position, observer_yaw, teammates)
	var cache_key := JSON.stringify(hostages)
	if str(hostage_status_group.get_meta("cache_key", "")) == cache_key:
		return
	hostage_status_group.set_meta("cache_key", cache_key)
	for child in hostage_status_group.get_children():
		child.free()
	for hostage: Dictionary in hostages:
		var icon := _classic_sprite("hostage", CLASSIC_ORANGE)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.size = Vector2(32, 32)
		if bool(hostage.get("rescued", false)):
			icon.modulate = CLASSIC_GREEN
		elif not bool(hostage.get("alive", true)):
			icon.modulate = CLASSIC_RED
		icon.tooltip_text = str(hostage.get("id", "hostage"))
		hostage_status_group.add_child(icon)


func update_round(round_number: int, seconds_left: float, kills: int, target_count: int) -> void:
	round_label.text = "ROUND %02d" % round_number
	var whole_seconds: int = maxi(0, int(ceil(seconds_left)))
	timer_label.text = "%d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	timer_label.add_theme_color_override(
		"font_color",
		CLASSIC_RED if whole_seconds <= 15 else CLASSIC_ORANGE,
	)
	_set_digit_row(
		timer_digits,
		timer_label.text,
		CLASSIC_RED if whole_seconds <= 15 else CLASSIC_ORANGE,
	)
	objective_label.text = "%d / %d" % [kills, target_count]


func update_match(
	round_number: int,
	phase: String,
	seconds_left: float,
	ct_score: int,
	terrorist_score: int,
	money: int,
) -> void:
	round_label.text = "R%02d  %s" % [round_number, phase.to_upper()]
	var whole_seconds: int = maxi(0, int(ceil(seconds_left)))
	timer_label.text = "%d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	var timer_color := (
		CLASSIC_RED
		if whole_seconds <= 15 and phase != "freeze"
		else CLASSIC_ORANGE
	)
	timer_label.add_theme_color_override("font_color", timer_color)
	_set_digit_row(timer_digits, timer_label.text, timer_color)
	objective_label.text = "CT %d  :  %d T" % [ct_score, terrorist_score]
	# During freeze/buy phases every spawn point sits inside its buy zone, so
	# the classic buyzone icon shows; callers with real buy-zone volumes can
	# re-assert it with set_buy_zone() after any live-phase update.
	if phase == "freeze" or phase == "buy":
		set_buy_zone(true)
	elif _in_buy_zone:
		set_buy_zone(false)
	# First-person spectating supplies the watched actor's account separately;
	# do not alternate it with the dead local player's value every match tick.
	if not (_spectating and _spectator_first_person):
		update_money(money)


func update_money(money: int) -> void:
	if money == _last_money:
		return
	money_label.text = "$%d" % money
	# CS 1.6's account counter is always the one fixed HUD orange; on change it
	# briefly brightens (more additive light) but never shifts hue.
	var money_color := CLASSIC_ORANGE
	if _last_money != -2147483648 and money != _last_money:
		_show_money_delta(money - _last_money)
		money_color = CLASSIC_ORANGE_BRIGHT
		_money_flash_generation += 1
		var generation := _money_flash_generation
		get_tree().create_timer(0.9).timeout.connect(func() -> void:
			if generation != _money_flash_generation:
				return
			if not is_instance_valid(money_digits) or not is_instance_valid(_money_sign):
				return
			_set_digit_row(money_digits, money_label.text.trim_prefix("$"), CLASSIC_ORANGE)
			_money_sign.modulate = _classic_sprite_modulate(CLASSIC_ORANGE)
		)
	_last_money = money
	if is_instance_valid(_money_sign):
		_money_sign.modulate = _classic_sprite_modulate(money_color)
	_set_digit_row(money_digits, str(money), money_color)


func _show_money_delta(change: int) -> void:
	# Same-direction rewards arriving together share one row; spending replaces
	# a gain instead of silently netting it away. Unchanged snapshots do nothing.
	if money_delta.modulate.a > 0.0 and signi(change) == signi(money_delta_amount):
		money_delta_amount += change
	else:
		money_delta_amount = change
	if _money_delta_tween != null and _money_delta_tween.is_valid():
		_money_delta_tween.kill()
	var color := CLASSIC_GREEN if money_delta_amount > 0 else CLASSIC_RED
	var symbol := "plus" if money_delta_amount > 0 else "minus"
	_money_delta_sign.texture = load(CLASSIC_HUD_ROOT.path_join(symbol + ".png"))
	_money_delta_sign.custom_minimum_size = _money_delta_sign.texture.get_size()
	_money_delta_sign.set_meta("classic_sprite", symbol)
	_money_delta_sign.modulate = _classic_sprite_modulate(color)
	_money_delta_dollar.modulate = _classic_sprite_modulate(color)
	_set_digit_row(money_delta_digits, str(absi(money_delta_amount)), color)
	money_delta.modulate.a = 1.0
	_money_delta_tween = create_tween()
	_money_delta_tween.tween_interval(1.0)
	_money_delta_tween.tween_property(money_delta, "modulate:a", 0.0, 1.5)


func _clear_money_delta() -> void:
	if _money_delta_tween != null and _money_delta_tween.is_valid():
		_money_delta_tween.kill()
	money_delta_amount = 0
	if is_instance_valid(money_delta):
		money_delta.modulate.a = 0.0


func reset_money_presentation() -> void:
	_last_money = -2147483648
	_money_flash_generation += 1
	_clear_money_delta()


func update_objective(text: String) -> void:
	# CS 1.6 never keeps a persistent objective string on the HUD; surface
	# objective changes as a transient round-start style message instead.
	if text == _objective_text:
		return
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective_text = text
	# The standing mission statement is never printed by CS 1.6's HUD —
	# only situational objective updates appear, and only briefly.
	if text == "ELIMINATE OR PLANT":
		text = ""
	status_label.text = text
	_objective_generation += 1
	if text.is_empty():
		status_label.modulate.a = 0.0
		return
	status_label.modulate.a = 1.0
	var generation := _objective_generation
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if generation != _objective_generation or not is_instance_valid(status_label):
			return
		_objective_tween = create_tween()
		_objective_tween.tween_property(status_label, "modulate:a", 0.0, 0.4)
	)


func set_spectating(active: bool) -> void:
	if _spectating == active:
		return
	_spectating = active
	if not active:
		_spectator_first_person = false
	if active:
		clear_combat_feedback()
		_clear_money_delta()
		set_nightvision(false)
	# Keep identity, the match timer, and transient round notices in separate
	# rows. Normal first-person layout is unchanged when the camera returns.
	spectate_label.offset_top = -105.0 if active else -72.0
	spectate_label.offset_bottom = spectate_label.offset_top + 26.0
	status_label.offset_top = -143.0 if active else -107.0
	status_label.offset_bottom = status_label.offset_top + 30.0
	update_spectate_target("")
	_refresh_gameplay_visibility()


func set_spectator_first_person(active: bool) -> void:
	var next := active and _spectating
	if _spectator_first_person == next:
		return
	_spectator_first_person = next
	_refresh_gameplay_visibility()


func update_spectate_target(target_name: String) -> void:
	if not is_instance_valid(spectate_label):
		return
	spectate_label.text = (
		("Spectating" if _spectating else "") if target_name.is_empty()
		else "Spectating: %s" % target_name
	)


func show_hitmarker(headshot: bool) -> void:
	# Intentionally absent: hit-confirm markers were not part of CS 1.6.
	pass


func show_damage() -> void:
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	damage_flash.color.a = 0.24
	_damage_tween = create_tween()
	_damage_tween.tween_property(damage_flash, "color:a", 0.0, 0.26)


func clear_combat_feedback() -> void:
	for tween: Tween in [_damage_tween, _flash_blind_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	damage_flash.color.a = 0.0
	flash_blind_overlay.color.a = 0.0


func reset_match_presentation() -> void:
	reset_money_presentation()
	update_defuse_progress(false, 0.0, 0.0)
	# Invalidate delayed fades before clearing the completed match's messages.
	# Already-running tweens must be stopped too, so they cannot fade a new one.
	_banner_generation += 1
	_objective_generation += 1
	for tween: Tween in [_banner_tween, _objective_tween, _radio_line_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	banner_label.text = ""
	banner_label.modulate.a = 0.0
	_objective_text = ""
	status_label.text = ""
	status_label.modulate.a = 0.0
	for row in kill_feed_box.get_children():
		kill_feed_box.remove_child(row)
		row.queue_free()
	if is_instance_valid(_radio_line_label):
		_radio_line_label.text = ""
		_radio_line_label.modulate.a = 0.0
	hide_radio_menu()
	clear_combat_feedback()


var _radio_menu_box: VBoxContainer
var _radio_line_label: Label
var _radio_line_tween: Tween


func show_radio_menu(title: String, items: Array[String]) -> void:
	hide_radio_menu()
	_radio_menu_box = VBoxContainer.new()
	_radio_menu_box.name = "ClassicRadioMenu"
	_radio_menu_box.position = Vector2(18, 210)
	_radio_menu_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var root := get_node_or_null("HUDRoot")
	if root == null:
		root = self
	root.add_child(_radio_menu_box)
	var rows: Array[String] = [title]
	for index in range(items.size()):
		rows.append("%d. %s" % [index + 1, items[index]])
	rows.append("0. Exit")
	for row_index in range(rows.size()):
		var label := Label.new()
		label.text = rows[row_index]
		if _vgui_font != null:
			label.add_theme_font_override("font", _vgui_font)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override(
			"font_color",
			CLASSIC_ORANGE_BRIGHT if row_index == 0 else CLASSIC_ORANGE,
		)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		_radio_menu_box.add_child(label)


func hide_radio_menu() -> void:
	if is_instance_valid(_radio_menu_box):
		_radio_menu_box.queue_free()
	_radio_menu_box = null


func show_radio_line(text: String) -> void:
	if not is_instance_valid(_radio_line_label):
		_radio_line_label = Label.new()
		_radio_line_label.name = "ClassicRadioLine"
		_radio_line_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_radio_line_label.position = Vector2(18, -140)
		if _vgui_font != null:
			_radio_line_label.add_theme_font_override("font", _vgui_font)
		_radio_line_label.add_theme_font_size_override("font_size", 14)
		_radio_line_label.add_theme_color_override("font_color", CLASSIC_ORANGE)
		_radio_line_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		_radio_line_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var root := get_node_or_null("HUDRoot")
		if root == null:
			root = self
		root.add_child(_radio_line_label)
	_radio_line_label.text = text
	_radio_line_label.modulate.a = 1.0
	if _radio_line_tween != null and _radio_line_tween.is_valid():
		_radio_line_tween.kill()
	_radio_line_tween = create_tween()
	_radio_line_tween.tween_interval(4.0)
	_radio_line_tween.tween_property(_radio_line_label, "modulate:a", 0.0, 0.8)


const KILL_FEED_LIMIT := 5
const KILL_FEED_SECONDS := 6.0
const KILL_FEED_CT_HEX := "9bbdff"
const KILL_FEED_T_HEX := "ff5040"
const KILL_FEED_NEUTRAL_HEX := "d8d8d8"


func _kill_feed_team_hex(team: String) -> String:
	match team:
		Combatant.TEAM_COUNTER_TERRORIST:
			return KILL_FEED_CT_HEX
		Combatant.TEAM_TERRORIST:
			return KILL_FEED_T_HEX
	return KILL_FEED_NEUTRAL_HEX


func add_kill_notice(
	killer: String,
	killer_team: String,
	weapon: String,
	victim: String,
	victim_team: String,
	headshot := false,
) -> void:
	if not is_instance_valid(kill_feed_box):
		return
	var row := RichTextLabel.new()
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _vgui_font != null:
		row.add_theme_font_override("normal_font", _vgui_font)
	row.add_theme_font_size_override("normal_font_size", 14)
	row.add_theme_color_override("font_shadow_color", Color.BLACK)
	row.add_theme_constant_override("shadow_offset_x", 1)
	row.add_theme_constant_override("shadow_offset_y", 1)
	var icon := "grenade" if weapon in ["hegrenade", "c4"] else weapon
	if weapon == "mp5": icon = "mp5navy"
	if not _kill_feed_icons.has(icon) or icon == "headshot":
		icon = "skull"
	row.set_meta("weapon", weapon)
	row.set_meta("weapon_icon", icon)
	row.set_meta("headshot", headshot)
	# add_text never interprets player names as markup or texture paths.
	if not killer.is_empty():
		row.push_color(Color(_kill_feed_team_hex(killer_team)))
		row.add_text(killer)
		row.pop()
		row.add_text("  ")
	row.add_image(_kill_feed_icons[icon], 0, 16, Color("#ffb060"))
	if headshot:
		row.add_image(_kill_feed_icons.headshot, 0, 16, Color("#ffb060"))
	row.add_text("  ")
	row.push_color(Color(_kill_feed_team_hex(victim_team)))
	row.add_text(victim)
	row.pop()
	kill_feed_box.add_child(row)
	while kill_feed_box.get_child_count() > KILL_FEED_LIMIT:
		var oldest := kill_feed_box.get_child(0)
		kill_feed_box.remove_child(oldest)
		oldest.free()
	var tween := row.create_tween()
	tween.tween_interval(KILL_FEED_SECONDS)
	tween.tween_property(row, "modulate:a", 0.0, 0.8)
	tween.tween_callback(row.queue_free)


func show_banner(text: String, color: Color, duration := 1.7) -> void:
	for non_classic_prefix in ["FREEZE TIME", "LIVE", "HEADSHOT", "HOSTILE DOWN"]:
		if text.begins_with(non_classic_prefix):
			return
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_generation += 1
	var generation := _banner_generation
	banner_label.text = text.replace("  •  ", " - ")
	banner_label.add_theme_color_override(
		"font_color",
		CLASSIC_RED if color.r > 0.7 and color.g < 0.5 else CLASSIC_ORANGE,
	)
	banner_label.modulate.a = 1.0
	await get_tree().create_timer(duration).timeout
	if generation != _banner_generation:
		return
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.24)


func set_deploy_visible(visible: bool) -> void:
	if visible and _menu_state == "chat":
		close_chat()
	deploy_overlay.visible = visible
	if visible:
		show_team_menu()
	else:
		_set_menu_state("none")
	_refresh_gameplay_visibility()


func set_paused_visible(visible: bool) -> void:
	if visible and _menu_state == "chat":
		close_chat()
	if visible and not pause_overlay.visible:
		_pause_return_state = _menu_state
	pause_overlay.visible = visible
	if visible:
		_show_pause_main()
	else:
		set_scoreboard_visible(false)
	var next_state := "pause" if visible else "none"
	if not visible and deploy_overlay.visible:
		next_state = "class" if _pause_return_state == "class" else "team"
	_set_menu_state(next_state)
	_refresh_gameplay_visibility()


func _set_menu_state(state: String) -> void:
	_menu_state = state
	var captures_keyboard := state != "none"
	var mouse_visible := state not in ["none", "scoreboard", "chat"]
	input_contract_changed.emit(state, captures_keyboard, mouse_visible)


func _refresh_gameplay_visibility() -> void:
	var modal_visible := (
		(deploy_overlay != null and deploy_overlay.visible)
		or (buy_overlay != null and buy_overlay.visible)
		or (pause_overlay != null and pause_overlay.visible)
	)
	for control in _gameplay_controls:
		if is_instance_valid(control):
			control.visible = not modal_visible
	if _spectating:
		for control in _participant_controls:
			control.visible = _spectator_first_person and not modal_visible
	if is_instance_valid(spectate_label):
		spectate_label.visible = _spectating and not modal_visible
	if is_instance_valid(_buyzone_icon):
		_buyzone_icon.visible = _in_buy_zone and not modal_visible and not _spectating
	if is_instance_valid(_defuse_kit_icon):
		_defuse_kit_icon.visible = _has_defuse_kit and not modal_visible \
			and (not _spectating or _spectator_first_person)
		# Stack the kit above the cart while both status icons are present.
		_defuse_kit_icon.offset_top = -50 if _in_buy_zone else -16
		_defuse_kit_icon.offset_bottom = _defuse_kit_icon.offset_top + 32
	if is_instance_valid(_c4_icon):
		_c4_icon.visible = _carrying_c4 and not modal_visible and not _spectating
		# Stack above the cart while both status icons are present.
		_c4_icon.offset_top = -50 if _in_buy_zone else -16
		_c4_icon.offset_bottom = _c4_icon.offset_top + 32
	if is_instance_valid(defuse_progress_bar):
		defuse_progress_bar.visible = (
			_defuse_progress_active and not modal_visible
			and (not _spectating or _spectator_first_person)
		)


func current_input_contract() -> Dictionary:
	return {
		"state": _menu_state,
		"captures_keyboard": _menu_state != "none",
		"mouse_visible": _menu_state not in ["none", "scoreboard", "chat"],
	}


func handle_menu_action(action: String, pressed := true) -> bool:
	if action == "scoreboard":
		set_scoreboard_held(pressed)
		menu_action_requested.emit(action, {"pressed": pressed})
		return true
	if not pressed:
		return false
	if action in ["ui_cancel", "menu_cancel"]:
		return handle_menu_key(KEY_ESCAPE)
	if action.begins_with("menu_select_"):
		var number_text := action.trim_prefix("menu_select_")
		if number_text.is_valid_int():
			var number := clampi(int(number_text), 0, 9)
			return handle_menu_key(KEY_0 + number as Key)
	menu_action_requested.emit(action, {"pressed": true, "state": _menu_state})
	return false


func accept_authoritative_deploy_selection(team_id: int, class_id: int) -> void:
	_selected_team = clampi(team_id, 1, 2)
	set_meta("authoritative_team", _selected_team)
	set_meta("authoritative_class", maxi(0, class_id))
	if deploy_overlay.visible:
		if class_id > 0:
			deploy_overlay.visible = false
			_set_menu_state("none")
			_refresh_gameplay_visibility()
		else:
			show_class_menu(_selected_team)


func _unhandled_input(event: InputEvent) -> void:
	# The gameplay root does not process offline paused input. Route only
	# unhandled keys through its existing handler; live/online input stays
	# on the normal Game path and is never dispatched twice.
	if get_tree().paused and event is InputEventKey:
		paused_input_received.emit(event)


func handle_menu_key(keycode: Key) -> bool:
	if keycode == KEY_ESCAPE:
		match _menu_state:
			"chat":
				close_chat()
			"team":
				deploy_cancel_requested.emit()
			"class":
				show_team_menu()
			"buy_item":
				_show_buy_categories()
			"buy_category":
				set_buy_menu_visible(false)
			"options_multiplayer", "options_keyboard", "options_mouse", "options_audio", "options_video", "options_voice":
				_options_cancel()
			"accessibility_extension":
				_hide_accessibility()
			"pause":
				resume_requested.emit()
			"network":
				_show_pause_main()
			_:
				return false
		return true
	if keycode < KEY_0 or keycode > KEY_9:
		return false
	var numeric := int(keycode - KEY_0)
	match _menu_state:
		"team":
			var team_numbers := {1: 1, 2: 2, 5: 5, 6: 6}
			if numeric == 0:
				deploy_cancel_requested.emit()
				return true
			if team_numbers.has(numeric):
				_select_team(int(team_numbers[numeric]))
				return true
		"class":
			if numeric == 0:
				show_team_menu()
				return true
			var classes: Array = TERRORIST_CLASSES if _selected_team == 1 else CT_CLASSES
			if numeric >= 1 and numeric <= classes.size():
				_select_class(numeric)
				return true
		"buy_category":
			if numeric == 0:
				set_buy_menu_visible(false)
				return true
			if numeric >= 1 and numeric <= BUY_CATEGORIES.size():
				_show_buy_category(str(BUY_CATEGORIES[numeric - 1][2]))
				return true
		"buy_item":
			if numeric == 0:
				_show_buy_categories()
				return true
			if numeric >= 1 and numeric <= _buy_items.size():
				var item: Dictionary = _buy_items[numeric - 1]
				if int(item.price) <= _buy_money:
					buy_item_requested.emit(str(item.item_id))
				return true
	return false
