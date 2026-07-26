class_name GameHUD
extends CanvasLayer

signal deploy_requested
signal resume_requested

var health_label: Label
var armor_label: Label
var ammo_label: Label
var reserve_label: Label
var timer_label: Label
var round_label: Label
var objective_label: Label
var status_label: Label
var money_label: Label
var banner_label: Label
var deploy_overlay: Control
var pause_overlay: Control
var damage_flash: ColorRect
var hitmarker: Control
var crosshair: Control
var _banner_generation := 0
var settings: Node
var _weapon_name := "AK-47"
var _fire_mode := "FULL AUTO"


func _ready() -> void:
	layer = 20
	settings = get_node("/root/GameSettings")
	_build_hud()
	settings.changed.connect(_apply_accessibility)
	_apply_accessibility()


func _build_hud() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_bar := PanelContainer.new()
	top_bar.name = "MatchBar"
	top_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_bar.position = Vector2(-250, 20)
	top_bar.size = Vector2(500, 58)
	top_bar.add_theme_stylebox_override("panel", _panel_style(Color("#07111de8"), Color("#36516b"), 7))
	root.add_child(top_bar)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 26)
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_child(top_row)
	round_label = _label("ROUND 01", 16, Color("#78d8ff"))
	timer_label = _label("01:30", 25, Color.WHITE)
	objective_label = _label("0 / 5", 16, Color("#ffca66"))
	money_label = _label("$800", 16, Color("#77e3ae"))
	top_row.add_child(round_label)
	top_row.add_child(timer_label)
	top_row.add_child(objective_label)
	top_row.add_child(money_label)

	var health_panel := PanelContainer.new()
	health_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_panel.position = Vector2(24, -104)
	health_panel.size = Vector2(230, 72)
	health_panel.add_theme_stylebox_override("panel", _panel_style(Color("#07111ddc"), Color("#27475e"), 6))
	root.add_child(health_panel)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 22)
	health_panel.add_child(health_row)
	health_label = _metric("100", "HEALTH", Color("#f0f5f8"))
	armor_label = _metric("100", "ARMOR", Color("#76ceef"))
	health_row.add_child(health_label.get_parent())
	health_row.add_child(armor_label.get_parent())

	var ammo_panel := PanelContainer.new()
	ammo_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_panel.position = Vector2(-244, -104)
	ammo_panel.size = Vector2(220, 72)
	ammo_panel.add_theme_stylebox_override("panel", _panel_style(Color("#07111ddc"), Color("#5f4a29"), 6))
	root.add_child(ammo_panel)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 10)
	ammo_panel.add_child(ammo_row)
	ammo_label = _label("30", 40, Color("#fff2d0"))
	reserve_label = _label("/ 90", 18, Color("#b7a98c"))
	ammo_row.add_child(ammo_label)
	ammo_row.add_child(reserve_label)

	status_label = _label("AK-47  •  FULL AUTO", 13, Color("#a9bac8"))
	status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_label.position = Vector2(-130, -47)
	status_label.size = Vector2(260, 26)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status_label)

	banner_label = _label("", 28, Color.WHITE)
	banner_label.set_anchors_preset(Control.PRESET_CENTER)
	banner_label.position = Vector2(-280, -126)
	banner_label.size = Vector2(560, 52)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.modulate.a = 0.0
	root.add_child(banner_label)

	_build_crosshair(root)
	_build_damage_flash(root)
	_build_deploy_overlay(root)
	_build_pause_overlay(root)


func _build_crosshair(root: Control) -> void:
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-16, -16)
	crosshair.size = Vector2(32, 32)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	var color := Color("#d7f8e1")
	for rect in [
		Rect2(15, 2, 2, 9),
		Rect2(15, 21, 2, 9),
		Rect2(2, 15, 9, 2),
		Rect2(21, 15, 9, 2),
	]:
		var line := ColorRect.new()
		line.position = rect.position
		line.size = rect.size
		line.color = color
		crosshair.add_child(line)

	hitmarker = Control.new()
	hitmarker.name = "Hitmarker"
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.position = Vector2(-20, -20)
	hitmarker.size = Vector2(40, 40)
	hitmarker.modulate.a = 0.0
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hitmarker)
	for data in [
		[Vector2(8, 8), 45.0],
		[Vector2(27, 8), -45.0],
		[Vector2(8, 27), -45.0],
		[Vector2(27, 27), 45.0],
	]:
		var mark := ColorRect.new()
		mark.position = data[0]
		mark.size = Vector2(9, 2)
		mark.rotation_degrees = data[1]
		mark.color = Color.WHITE
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hitmarker.add_child(mark)


func _build_damage_flash(root: Control) -> void:
	damage_flash = ColorRect.new()
	damage_flash.name = "DamageVignette"
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_flash.color = Color(0.72, 0.03, 0.02, 0.0)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_flash)


func _build_deploy_overlay(root: Control) -> void:
	deploy_overlay = ColorRect.new()
	deploy_overlay.name = "DeployOverlay"
	deploy_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deploy_overlay.color = Color("#03070dda")
	deploy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(deploy_overlay)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = Vector2(-265, -180)
	card.size = Vector2(530, 360)
	card.add_theme_stylebox_override("panel", _panel_style(Color("#07121ef4"), Color("#42708e"), 10))
	deploy_overlay.add_child(card)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	var eyebrow := _label("TACTICAL TRAINING ENVIRONMENT", 12, Color("#67cff6"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(eyebrow)
	var title := _label("PROTOCOL 47", 43, Color("#f1f6f9"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var rule := HSeparator.new()
	column.add_child(rule)
	var description := _label(
		"Clear five hostile operators before the round clock expires.\n"
		+ "Movement uses acceleration, friction and air control—not a stock controller.",
		15,
		Color("#aebdca"),
	)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(description)
	var controls := _label("WASD MOVE  •  1–4 WEAPONS  •  E PLANT  •  R RELOAD  •  ESC SETTINGS", 12, Color("#e5bd6f"))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(controls)
	var buy_hint := _label("FREEZE BUY:  F1 AK $2500  •  F2 DEAGLE $650  •  F3 ARMOR $1000  •  F4 HE $300", 11, Color("#77e3ae"))
	buy_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(buy_hint)
	var deploy := Button.new()
	deploy.text = "DEPLOY"
	deploy.custom_minimum_size = Vector2(250, 52)
	deploy.add_theme_font_size_override("font_size", 17)
	deploy.add_theme_color_override("font_color", Color("#07111d"))
	deploy.add_theme_stylebox_override("normal", _panel_style(Color("#70d3f6"), Color("#9ee4ff"), 6))
	deploy.add_theme_stylebox_override("hover", _panel_style(Color("#a4e8ff"), Color.WHITE, 6))
	deploy.pressed.connect(func() -> void: deploy_requested.emit())
	column.add_child(deploy)


func _build_pause_overlay(root: Control) -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.name = "PauseOverlay"
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.color = Color("#02060bc4")
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	root.add_child(pause_overlay)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = Vector2(-300, -325)
	card.size = Vector2(600, 650)
	card.add_theme_stylebox_override("panel", _panel_style(Color("#07121ef7"), Color("#426580"), 10))
	pause_overlay.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	card.add_child(column)
	var title := _label("PAUSED", 32, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(_label("INPUT", 11, Color("#67cff6")))
	var sensitivity_value := _label("%.2f° / PX" % settings.mouse_sensitivity, 12, Color("#dce9f0"))
	var sensitivity := HSlider.new()
	sensitivity.min_value = 0.03
	sensitivity.max_value = 0.35
	sensitivity.step = 0.01
	sensitivity.value = settings.mouse_sensitivity
	sensitivity.custom_minimum_size.y = 24
	sensitivity.value_changed.connect(func(value: float) -> void:
		sensitivity_value.text = "%.2f° / PX" % value
		settings.update_input(value, settings.invert_y)
	)
	column.add_child(sensitivity_value)
	column.add_child(sensitivity)
	var invert := CheckButton.new()
	invert.text = "INVERT VERTICAL AIM"
	invert.button_pressed = settings.invert_y
	invert.toggled.connect(func(enabled: bool) -> void:
		settings.update_input(settings.mouse_sensitivity, enabled)
	)
	column.add_child(invert)
	column.add_child(_label("VIDEO", 11, Color("#67cff6")))
	var fov_value := _label("FIELD OF VIEW  %.0f°" % settings.field_of_view, 12, Color("#dce9f0"))
	var fov := HSlider.new()
	fov.min_value = 60
	fov.max_value = 100
	fov.step = 1
	fov.value = settings.field_of_view
	fov.custom_minimum_size.y = 24
	fov.value_changed.connect(func(value: float) -> void:
		fov_value.text = "FIELD OF VIEW  %.0f°" % value
		settings.update_video(value, settings.performance_preset, settings.vsync_enabled)
	)
	column.add_child(fov_value)
	column.add_child(fov)
	var vsync := CheckButton.new()
	vsync.text = "VERTICAL SYNC"
	vsync.button_pressed = settings.vsync_enabled
	vsync.toggled.connect(func(enabled: bool) -> void:
		settings.update_video(settings.field_of_view, settings.performance_preset, enabled)
	)
	column.add_child(vsync)
	var quality := OptionButton.new()
	quality.add_item("PERFORMANCE: LOW")
	quality.add_item("PERFORMANCE: BALANCED")
	quality.add_item("PERFORMANCE: HIGH")
	quality.selected = settings.performance_preset
	quality.item_selected.connect(func(index: int) -> void:
		settings.update_video(settings.field_of_view, index, settings.vsync_enabled)
	)
	column.add_child(quality)
	column.add_child(_label("AUDIO", 11, Color("#67cff6")))
	var volume_value := _label("MASTER  %+.0f dB" % settings.master_volume_db, 12, Color("#dce9f0"))
	var volume := HSlider.new()
	volume.min_value = -40
	volume.max_value = 6
	volume.step = 1
	volume.value = settings.master_volume_db
	volume.custom_minimum_size.y = 24
	volume.value_changed.connect(func(value: float) -> void:
		volume_value.text = "MASTER  %+.0f dB" % value
		settings.update_volume(value)
	)
	column.add_child(volume_value)
	column.add_child(volume)
	column.add_child(_label("ACCESSIBILITY", 11, Color("#67cff6")))
	var crosshair_size := HSlider.new()
	crosshair_size.min_value = 0.75
	crosshair_size.max_value = 2.0
	crosshair_size.step = 0.25
	crosshair_size.value = settings.crosshair_scale
	crosshair_size.custom_minimum_size.y = 22
	crosshair_size.value_changed.connect(func(value: float) -> void:
		settings.update_accessibility(value, settings.high_contrast, settings.reduced_motion)
	)
	column.add_child(_label("CROSSHAIR SIZE", 11, Color("#dce9f0")))
	column.add_child(crosshair_size)
	var contrast := CheckButton.new()
	contrast.text = "HIGH-CONTRAST CROSSHAIR"
	contrast.button_pressed = settings.high_contrast
	contrast.toggled.connect(func(enabled: bool) -> void:
		settings.update_accessibility(settings.crosshair_scale, enabled, settings.reduced_motion)
	)
	column.add_child(contrast)
	var reduced_motion := CheckButton.new()
	reduced_motion.text = "REDUCED CAMERA MOTION"
	reduced_motion.button_pressed = settings.reduced_motion
	reduced_motion.toggled.connect(func(enabled: bool) -> void:
		settings.update_accessibility(settings.crosshair_scale, settings.high_contrast, enabled)
	)
	column.add_child(reduced_motion)
	var resume := Button.new()
	resume.text = "RESUME"
	resume.custom_minimum_size.y = 48
	resume.add_theme_font_size_override("font_size", 16)
	resume.add_theme_stylebox_override("normal", _panel_style(Color("#70d3f6"), Color("#9ee4ff"), 6))
	resume.pressed.connect(func() -> void: resume_requested.emit())
	column.add_child(resume)


func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _apply_accessibility() -> void:
	if not is_instance_valid(crosshair):
		return
	crosshair.scale = Vector2.ONE * settings.crosshair_scale
	crosshair.pivot_offset = crosshair.size * 0.5
	var color := Color("#fff05c") if settings.high_contrast else Color("#d7f8e1")
	for child in crosshair.get_children():
		if child is ColorRect:
			child.color = color


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _metric(value: String, caption: String, color: Color) -> Label:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", -5)
	var value_label := _label(value, 32, color)
	var caption_label := _label(caption, 10, Color("#8094a5"))
	column.add_child(value_label)
	column.add_child(caption_label)
	return value_label


func update_health(health: int, armor: int) -> void:
	health_label.text = str(health)
	armor_label.text = str(armor)
	if health < 35:
		health_label.add_theme_color_override("font_color", Color("#ff655f"))
	else:
		health_label.add_theme_color_override("font_color", Color("#f0f5f8"))


func update_ammo(clip: int, reserve: int, reloading: bool) -> void:
	ammo_label.text = "--" if clip < 0 else str(clip).pad_zeros(2)
	reserve_label.text = "" if reserve < 0 else "/ %d" % reserve
	status_label.text = "%s  •  %s" % [_weapon_name, "RELOADING" if reloading else _fire_mode]
	ammo_label.add_theme_color_override("font_color", Color("#ff9d68") if clip <= 5 else Color("#fff2d0"))


func update_weapon(weapon_name: String, fire_mode: String) -> void:
	_weapon_name = weapon_name
	_fire_mode = fire_mode
	status_label.text = "%s  •  %s" % [_weapon_name, _fire_mode]


func update_round(round_number: int, seconds_left: float, kills: int, target_count: int) -> void:
	round_label.text = "ROUND %02d" % round_number
	var whole_seconds: int = maxi(0, int(ceil(seconds_left)))
	timer_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	timer_label.add_theme_color_override("font_color", Color("#ff6f65") if whole_seconds <= 15 else Color.WHITE)
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
	timer_label.text = "%02d:%02d" % [whole_seconds / 60, whole_seconds % 60]
	timer_label.add_theme_color_override(
		"font_color",
		Color("#ff6f65") if whole_seconds <= 15 and phase != "freeze" else Color.WHITE,
	)
	objective_label.text = "CT %d  :  %d T" % [ct_score, terrorist_score]
	money_label.text = "$%d" % money


func update_objective(text: String) -> void:
	status_label.text = text


func show_hitmarker(headshot: bool) -> void:
	for child in hitmarker.get_children():
		if child is ColorRect:
			child.color = Color("#ffca66") if headshot else Color.WHITE
	hitmarker.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(hitmarker, "modulate:a", 0.0, 0.13)


func show_damage() -> void:
	damage_flash.color.a = 0.24
	var tween := create_tween()
	tween.tween_property(damage_flash, "color:a", 0.0, 0.26)


func show_banner(text: String, color: Color, duration := 1.7) -> void:
	_banner_generation += 1
	var generation := _banner_generation
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_label.modulate.a = 1.0
	await get_tree().create_timer(duration).timeout
	if generation != _banner_generation:
		return
	var tween := create_tween()
	tween.tween_property(banner_label, "modulate:a", 0.0, 0.24)


func set_deploy_visible(visible: bool) -> void:
	deploy_overlay.visible = visible


func set_paused_visible(visible: bool) -> void:
	pause_overlay.visible = visible
