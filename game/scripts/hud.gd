class_name GameHUD
extends CanvasLayer

signal deploy_requested
signal resume_requested
signal team_selected(team_id: int)
signal class_selected(class_id: int)
signal buy_item_requested(item_id: String)
signal disconnect_requested
signal quit_requested
signal menu_command_requested(command: String)
signal ui_sound_requested(sample_path: String)
signal input_contract_changed(state: String, captures_keyboard: bool, mouse_visible: bool)
signal menu_action_requested(action: String, payload: Dictionary)
signal options_apply_requested(values: Dictionary)
signal options_defaults_requested(page: String)
signal options_cancel_requested

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
const VGUI_MENU_ORIGIN := Vector2(76.0, 0.0)
const VGUI_MENU_SIZE := Vector2(552.0, 448.0)
# One uniform row metric for every buy list: CS 1.6 keeps a single font and a
# fixed right-aligned price column instead of shrinking long rows.
const BUY_ROW_WIDTH := 202.0
const BUY_PRICE_COLUMN_WIDTH := 40.0
const BUY_ROW_FONT_SIZE := 10

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
var hostage_status_group: HBoxContainer
var _banner_generation := 0
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
var vgui_source: CS16VGuiSource
var vgui_amber := VGUI_AMBER_FALLBACK
var vgui_amber_dim := VGUI_AMBER_DIM_FALLBACK
var vgui_blue := VGUI_BLUE_FALLBACK
var vgui_red := VGUI_RED_FALLBACK
var _vgui_font: SystemFont
var _vgui_fonts: Dictionary = {}
var _options_snapshot: Dictionary = {}
var _options_pending: Dictionary = {}
var _options_page_key := "multiplayer"
var _hud_additive_material: CanvasItemMaterial
var _money_sign: TextureRect
var _armor_icon: TextureRect
var _ammo_icon: TextureRect
var _buyzone_icon: TextureRect
var _has_helmet := false
var _in_buy_zone := false
var _last_money := -2147483648
var _money_flash_generation := 0
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

	status_label = _classic_label("", 17, CLASSIC_ORANGE)
	status_label.name = "ObjectiveStatus"
	status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.position = Vector2(-260, -107)
	status_label.size = Vector2(520, 30)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

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
		"ClassicVitals",
		"ClassicTimer",
		"ClassicAmmo",
		"ObjectiveStatus",
		"ClassicSpectate",
		"ClassicAnnouncement",
		"Crosshair",
		"DamageVignette",
	]:
		var gameplay_control := root.get_node_or_null(control_name) as Control
		if gameplay_control != null:
			_gameplay_controls.append(gameplay_control)
	_build_deploy_overlay(root)
	_build_buy_overlay(root)
	_build_scoreboard_overlay(root)
	_build_pause_overlay(root)
	root.resized.connect(func() -> void: layout_for_viewport(root.size))
	layout_for_viewport(root.size)
	_refresh_gameplay_visibility()


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
		func() -> void: show_team_menu(),
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


func _select_team(team_id: int) -> void:
	if team_id == 6:
		team_selected.emit(team_id)
		deploy_overlay.visible = false
		_set_menu_state("none")
		_refresh_gameplay_visibility()
		return
	_selected_team = 1 if team_id == 5 else team_id
	team_selected.emit(_selected_team)
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
	var old_title := buy_menu_frame.get_node_or_null("ItemTitle")
	if old_title != null:
		old_title.free()
	var main_title := buy_menu_frame.get_node_or_null("BuyTitle") as Control
	var category_prompt := buy_menu_frame.get_node_or_null("SelectCategory") as Control
	if main_title != null:
		main_title.visible = false
	if category_prompt != null:
		category_prompt.visible = false
	for child in buy_list_panel.get_children():
		child.free()
	for child in buy_item_panel.get_children():
		child.free()
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
		)
		price_label.name = "PriceText"
		price_label.position = Vector2(BUY_ROW_WIDTH - BUY_PRICE_COLUMN_WIDTH - 8.0, 0.0)
		price_label.size = Vector2(BUY_PRICE_COLUMN_WIDTH, 20.0)
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# The accelerator RichTextLabel draws from the row top; anchor the
		# price to the same top edge so name and price share one baseline.
		price_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
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
	var first := buy_list_panel.get_child(0) as Control if buy_list_panel.get_child_count() > 0 else null
	if first != null:
		first.call_deferred("grab_focus")


func _show_buy_categories() -> void:
	for child in buy_list_panel.get_children():
		child.free()
	for child in buy_item_panel.get_children():
		child.free()
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
	var first := buy_list_panel.get_child(0) as Control if buy_list_panel.get_child_count() > 0 else null
	if first != null:
		first.call_deferred("grab_focus")


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
	if category_id == "primary_ammo":
		return [_buy_item_dictionary(
			"primammo",
			"PRIMARY AMMO",
			int(_buy_context.get("primary_ammo_price", 60)),
			"",
		)]
	if category_id == "secondary_ammo":
		return [_buy_item_dictionary(
			"secammo",
			"SECONDARY AMMO",
			int(_buy_context.get("secondary_ammo_price", 40)),
			"",
		)]
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


func _buy_item_dictionary(item_id: String, label: String, price: int, art: String) -> Dictionary:
	return {
		"item_id": item_id,
		"label": label,
		"price": price,
		"art": art,
		"source_control": item_id,
		"y": 116,
	}


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
	_buy_team = clampi(team_id, 1, 2)
	_buy_money = maxi(0, money)
	# The buy menu's ACCOUNT line and the HUD account counter are the same
	# value by definition in CS 1.6; opening the menu re-asserts the HUD digits
	# so the two can never disagree in one frame.
	money_label.text = "$%d" % _buy_money
	_last_money = _buy_money
	if is_instance_valid(_money_sign):
		_money_sign.modulate = _classic_sprite_modulate(CLASSIC_ORANGE)
	_set_digit_row(money_digits, str(_buy_money), CLASSIC_ORANGE)
	_buy_context = context.duplicate(true)
	_show_buy_categories()
	buy_overlay.visible = true
	_set_menu_state("buy_category")
	_refresh_gameplay_visibility()


func set_buy_menu_visible(visible: bool) -> void:
	buy_overlay.visible = visible
	_set_menu_state("buy_category" if visible else "none")
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
	var source_rect := vgui_source.control_rect(
		source_path,
		"ClientScoreBoard",
		Rect2(60, 48, 520, 340),
		VGUI_BASE_SIZE,
	)
	var panel := PanelContainer.new()
	panel.name = "ClientScoreBoard"
	panel.position = source_rect.position
	panel.size = source_rect.size
	panel.clip_contents = true
	panel.set_meta("app90_source", source_path)
	panel.set_meta("app90_control", "ClientScoreBoard")
	# CS 1.6's scoreboard is a translucent black VGUI panel with no bright
	# frame around it.
	panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.0, 0.0, 0.0, 0.74), Color(0.0, 0.0, 0.0, 0.0), 0),
	)
	scoreboard_canvas.add_child(panel)
	var column := VBoxContainer.new()
	column.name = "ScoreboardContent"
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	var server := _vgui_text("Counter-Strike 1.6  |  de_dust2", 14, vgui_amber)
	server.name = "ServerName"
	server.custom_minimum_size.y = 24
	column.add_child(server)
	var header := _scoreboard_row(["NAME", "SCORE", "DEATHS", "LATENCY"], vgui_amber_dim)
	header.name = "ColumnHeader"
	column.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.name = "PlayerScroll"
	scroll.custom_minimum_size = Vector2(512, 276)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_style_vgui_scrollbar(scroll)
	column.add_child(scroll)
	scoreboard_rows = VBoxContainer.new()
	scoreboard_rows.name = "PlayerList"
	scoreboard_rows.add_theme_constant_override("separation", 1)
	scoreboard_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scoreboard_rows)
	update_scoreboard([], "Counter-Strike 1.6", "de_dust2", 0, 0)


func _scoreboard_row(values: Array, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 18
	row.add_theme_constant_override("separation", 0)
	var widths := [302, 66, 76, 68]
	for index in values.size():
		var label := _vgui_text(str(values[index]), 11, color)
		label.custom_minimum_size = Vector2(widths[index], 18)
		label.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_LEFT
			if index == 0
			else HORIZONTAL_ALIGNMENT_CENTER
		)
		row.add_child(label)
	return row


func _scoreboard_player_row(player: Dictionary, team_color := Color.WHITE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 18
	row.add_theme_constant_override("separation", 0)
	var identity := HBoxContainer.new()
	identity.custom_minimum_size = Vector2(302, 18)
	identity.add_theme_constant_override("separation", 4)
	# CS 1.6 draws every player's name (and row values) in the team color:
	# pale blue for CTs, red for Terrorists, white for spectators.
	var name_label := _vgui_text(str(player.get("name", "Player")), 11, team_color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_label)
	# CS 1.6's scoreboard rows carry no dead/VIP/bomb glyphs — dead players
	# simply keep an unadorned row and the bomb carrier is never revealed.
	# Only the voice speaker/muted icon is drawn beside the name.
	if bool(player.get("voice_muted", false)):
		identity.add_child(_scoreboard_voice_icon(true, 0))
	elif bool(player.get("voice_active", false)):
		identity.add_child(
			_scoreboard_voice_icon(false, int(player.get("voice_level", 4)))
		)
	row.add_child(identity)
	for value in [
		player.get("score", 0),
		player.get("deaths", 0),
		# CS 1.6 marks dead players by printing DEAD in the ping column.
		"DEAD" if not bool(player.get("alive", true)) else player.get("latency", 0),
	]:
		var label := _vgui_text(str(value), 11, team_color)
		var widths := [66, 76, 68]
		label.custom_minimum_size = Vector2(widths[label.get_index() if label.get_index() >= 0 else 0], 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(label)
	# Child indices are only known after insertion; apply the exact column widths.
	for index in range(1, row.get_child_count()):
		(row.get_child(index) as Control).custom_minimum_size.x = [66, 76, 68][index - 1]
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
		"ClientScoreBoard/ScoreboardContent/ServerName"
	) as Label
	server_label.text = "%s  |  %s" % [server_name, map_name]
	for child in scoreboard_rows.get_children():
		child.free()
	var teams := [
		[2, "COUNTER-TERRORISTS", ct_score, vgui_blue],
		[1, "TERRORISTS", terrorist_score, vgui_red],
		[0, "SPECTATORS", 0, Color(0.8, 0.8, 0.8, 1.0)],
	]
	for team_entry in teams:
		var team_id := int(team_entry[0])
		var team_players: Array = []
		for player_variant in players:
			var player: Dictionary = player_variant
			if int(player.get("team", 0)) == team_id:
				team_players.append(player)
		var section := _scoreboard_row(
			[
				"%s  —  %d %s" % [
					team_entry[1],
					team_players.size(),
					"player" if team_players.size() == 1 else "players",
				],
				str(team_entry[2]),
				"",
				"",
			],
			team_entry[3],
		)
		section.name = "Team%dSection" % team_id
		scoreboard_rows.add_child(section)
		for player in team_players:
			var row := _scoreboard_player_row(player, team_entry[3])
			row.name = "Player_%s" % str(player.get("name", "Player")).validate_node_name()
			scoreboard_rows.add_child(row)


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
		"quit":
			quit_requested.emit()


func _build_pause_options_menu() -> void:
	pause_options_menu = PanelContainer.new()
	pause_options_menu.name = "OptionsMenu"
	pause_options_menu.position = Vector2(60, 34)
	pause_options_menu.size = Vector2(520, 412)
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
				control = _vgui_text(
					label_text,
					_source_font_size("DefaultSmall", 12),
					GAMEUI_MENU_TEXT_DIM if int(data.get("dulltext", 0)) != 0 else GAMEUI_MENU_TEXT,
					"DefaultSmall" if int(data.get("dulltext", 0)) != 0 else "Default",
				)
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
	if tab_key == "mouse" and source_name == "ReverseMouse" and control is CheckBox:
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
			func(value: float) -> void: _options_pending["mouse_sensitivity"] = value
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


func _build_source_key_list(rect: Rect2) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.position = rect.position
	scroll.size = rect.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_style_vgui_scrollbar(scroll)
	scroll.set_meta("app90_source", CS16VGuiSource.BINDING_LIST)
	var rows := VBoxContainer.new()
	rows.name = "Bindings"
	rows.custom_minimum_size.x = rect.size.x - 16
	scroll.add_child(rows)
	var defaults := {
		"+forward": "W",
		"+back": "S",
		"+moveleft": "A",
		"+moveright": "D",
		"+speed": "SHIFT",
		"+jump": "SPACE",
		"+duck": "CTRL",
		"+voicerecord": "K",
		"radio1": "Z",
		"radio2": "X",
		"radio3": "C",
		"buy": "B",
		"buyammo1": ",",
		"buyammo2": ".",
		"buyequip": "O",
		"chooseteam": "M",
		"+showscores": "TAB",
		"+attack": "MOUSE1",
		"+attack2": "MOUSE2",
		"+reload": "R",
		"lastinv": "Q",
		"+use": "E",
		"drop": "G",
		"nightvision": "N",
		"impulse 100": "F",
		"impulse 201": "T",
		"snapshot": "F5",
	}
	var source_rows := vgui_source.key_bindings()
	for index in source_rows.size():
		var item: Dictionary = source_rows[index]
		if bool(item.is_separator):
			continue
		var command := str(item.command)
		var label := str(item.label)
		var row_text := (
			label
			if bool(item.is_heading)
			else "%-36s %s" % [label, str(defaults.get(command, ""))]
		)
		var row := _vgui_text(
			row_text,
			_source_font_size("DefaultSmall", 12),
			vgui_blue if bool(item.is_heading) else GAMEUI_MENU_TEXT,
			"DefaultSmall",
		)
		row.name = (
			"BindingHeading_%d" % index
			if bool(item.is_heading)
			else "Binding_%s" % command.validate_node_name()
		)
		row.custom_minimum_size.y = 18
		row.set_meta("source_command", command)
		row.set_meta("source_label_token", item.label_token)
		row.set_meta("binding", str(defaults.get(command, "")))
		rows.add_child(row)
	scroll.set_meta("source_row_count", rows.get_child_count())
	return scroll


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
	if command.to_lower() == "defaults":
		_options_defaults()


func _settings_values() -> Dictionary:
	return {
		"mouse_sensitivity": settings.mouse_sensitivity,
		"invert_y": settings.invert_y,
		"field_of_view": settings.field_of_view,
		"performance_preset": settings.performance_preset,
		"vsync_enabled": settings.vsync_enabled,
		"master_volume_db": settings.master_volume_db,
		"voice_transmit_volume": 75.0,
		"voice_receive_volume": 75.0,
		"voice_enabled": true,
		"mic_boost": false,
	}


func _restore_settings(values: Dictionary) -> void:
	settings.update_input(float(values.mouse_sensitivity), bool(values.invert_y))
	settings.update_video(
		float(values.field_of_view),
		int(values.performance_preset),
		bool(values.vsync_enabled),
	)
	settings.update_volume(float(values.master_volume_db))


func _options_apply() -> void:
	var values := _options_pending.duplicate(true)
	_restore_settings(values)
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
		"voice_transmit_volume": 75.0,
		"voice_receive_volume": 75.0,
		"voice_enabled": true,
		"mic_boost": false,
	}, true)
	_sync_source_option_controls()
	options_defaults_requested.emit(_options_page_key)
	menu_command_requested.emit("options_defaults:%s" % _options_page_key)


func _sync_source_option_controls() -> void:
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
	pause_main_menu.visible = false
	pause_options_menu.visible = true
	accessibility_overlay.visible = false
	_options_snapshot = _settings_values().duplicate(true)
	_options_pending = _options_snapshot.duplicate(true)
	_sync_source_option_controls()
	_show_options_tab("multiplayer")


func _show_pause_main() -> void:
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


func _font_for_rule(font_name: String) -> SystemFont:
	if _vgui_fonts.has(font_name):
		return _vgui_fonts[font_name] as SystemFont
	var spec := vgui_source.font_spec(font_name, int(VGUI_BASE_SIZE.y), {
		"name": "Verdana",
		"tall": 12,
		"weight": 400,
	})
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
	var arm := maxf(1.0, roundf(9.0 * user_scale))
	var gap := maxf(1.0, roundf(3.0 * user_scale)) + _crosshair_spread_px
	var color := (
		Color("#fff316")
		if settings != null and settings.high_contrast
		else Color(0.1, 1.0, 0.1, 0.78)
	)
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
	for child in crosshair.get_children():
		if child is ColorRect:
			child.color = (
				Color("#fff316")
				if settings.high_contrast
				else Color(0.1, 1.0, 0.1, 0.78)
			)


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
	money_label.text = "$%d" % money
	# CS 1.6's account counter is always the one fixed HUD orange; on change it
	# briefly brightens (more additive light) but never shifts hue.
	var money_color := CLASSIC_ORANGE
	if _last_money != -2147483648 and money != _last_money:
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


func update_objective(text: String) -> void:
	# CS 1.6 never keeps a persistent objective string on the HUD; surface
	# objective changes as a transient round-start style message instead.
	if text == _objective_text:
		return
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
		var tween := create_tween()
		tween.tween_property(status_label, "modulate:a", 0.0, 0.4)
	)


func update_spectate_target(target_name: String) -> void:
	if not is_instance_valid(spectate_label):
		return
	spectate_label.text = (
		"" if target_name.is_empty() else "Spectating: %s" % target_name
	)


func show_hitmarker(headshot: bool) -> void:
	# Intentionally absent: hit-confirm markers were not part of CS 1.6.
	pass


func show_damage() -> void:
	damage_flash.color.a = 0.24
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.26)


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
	row.bbcode_enabled = true
	row.fit_content = true
	row.scroll_active = false
	row.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	if _vgui_font != null:
		row.add_theme_font_override("normal_font", _vgui_font)
	row.add_theme_font_size_override("normal_font_size", 14)
	if killer.is_empty():
		row.text = "[color=#%s]%s[/color] [color=#%s]died[/color]" % [
			_kill_feed_team_hex(victim_team), victim, KILL_FEED_NEUTRAL_HEX,
		]
	else:
		row.text = "[color=#%s]%s[/color] [color=#ffa000](%s%s)[/color] [color=#%s]%s[/color]" % [
			_kill_feed_team_hex(killer_team),
			killer,
			weapon if not weapon.is_empty() else "?",
			" hs" if headshot else "",
			_kill_feed_team_hex(victim_team),
			victim,
		]
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
	var tween := create_tween()
	tween.tween_property(banner_label, "modulate:a", 0.0, 0.24)


func set_deploy_visible(visible: bool) -> void:
	deploy_overlay.visible = visible
	if visible:
		show_team_menu()
	else:
		_set_menu_state("none")
	_refresh_gameplay_visibility()


func set_paused_visible(visible: bool) -> void:
	pause_overlay.visible = visible
	if visible:
		_show_pause_main()
	else:
		set_scoreboard_visible(false)
	_set_menu_state("pause" if visible else "none")
	_refresh_gameplay_visibility()


func _set_menu_state(state: String) -> void:
	_menu_state = state
	var modal := state != "none" and state != "scoreboard"
	input_contract_changed.emit(state, modal or state == "scoreboard", modal)


func _refresh_gameplay_visibility() -> void:
	var modal_visible := (
		(deploy_overlay != null and deploy_overlay.visible)
		or (buy_overlay != null and buy_overlay.visible)
		or (pause_overlay != null and pause_overlay.visible)
	)
	for control in _gameplay_controls:
		if is_instance_valid(control):
			control.visible = not modal_visible
	if is_instance_valid(_buyzone_icon):
		_buyzone_icon.visible = _in_buy_zone and not modal_visible


func current_input_contract() -> Dictionary:
	return {
		"state": _menu_state,
		"captures_keyboard": _menu_state != "none",
		"mouse_visible": _menu_state != "none" and _menu_state != "scoreboard",
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


func handle_menu_key(keycode: Key) -> bool:
	if keycode == KEY_ESCAPE:
		match _menu_state:
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
				_set_menu_state("buy_item")
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
