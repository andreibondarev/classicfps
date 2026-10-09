extends SceneTree

## Multiplayer-tab crosshair appearance: the size/color combo boxes and the
## Translucent checkbox are pending until Apply/OK, then restyle the live
## crosshair, persist, and preview in the CrosshairImage panel.

const SettingsScript = preload("res://scripts/settings.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("CROSSHAIR OPTIONS: " + message)


func _arm_color(hud: CanvasLayer) -> Color:
	return (hud.crosshair.get_child(0) as ColorRect).color


func _arm_length(hud: CanvasLayer) -> float:
	return (hud.crosshair.get_child(0) as ColorRect).size.y


func _run() -> void:
	var settings := root.get_node("GameSettings")
	if OS.get_environment("PROTOCOL47_SETTINGS_PATH").is_empty() or settings.settings_path != OS.get_environment("PROTOCOL47_SETTINGS_PATH"):
		push_error("Crosshair options test requires isolated settings")
		quit(1)
		return
	settings.update_crosshair(0, 0, true)
	settings.update_accessibility(1.0, false, false)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	var hud: CanvasLayer = game.hud
	var default_color := _arm_color(hud)
	var default_arm := _arm_length(hud)
	_check(default_color.is_equal_approx(Color(Color8(50, 250, 50), 0.78)), "default is translucent classic green")

	hud.set_paused_visible(true)
	hud._show_pause_options()
	var page: Node = hud.options_pages.get_node("Page_multiplayer")
	var size_option := page.get_node("Source_CrosshairSizeComboBox") as OptionButton
	var color_option := page.get_node("Source_CrosshairColorComboBox") as OptionButton
	var translucent := page.get_node("Source_CrosshairTranslucencyCheckbox") as CheckBox
	_check(size_option.selected == 0 and color_option.selected == 0 and translucent.button_pressed,
		"controls load the saved appearance")
	_check(page.get_node_or_null("Source_CrosshairImage/CrosshairPreview") != null, "CrosshairImage holds a live preview")

	color_option.select(4)
	color_option.item_selected.emit(4)
	size_option.select(3)
	size_option.item_selected.emit(3)
	translucent.button_pressed = false
	_check(settings.crosshair_color == 0 and _arm_color(hud).is_equal_approx(default_color),
		"choices stay pending until Apply")
	hud.pause_options_menu.get_node("OptionsContent/OptionsApply").pressed.emit()
	_check(settings.crosshair_size == 3 and settings.crosshair_color == 4 and not settings.crosshair_translucent,
		"Apply saves size, color and translucency")
	_check(_arm_color(hud).is_equal_approx(Color8(50, 250, 250)), "live crosshair turns opaque light blue")
	_check(_arm_length(hud) > default_arm, "Large lengthens the live crosshair arms")

	var reloaded := SettingsScript.new()
	reloaded.settings_path = settings.settings_path
	reloaded.load_settings()
	_check(reloaded.crosshair_size == 3 and reloaded.crosshair_color == 4 and not reloaded.crosshair_translucent,
		"appearance persists to the settings file")
	reloaded.free()

	color_option.select(1)
	color_option.item_selected.emit(1)
	hud.pause_options_menu.get_node("OptionsContent/OptionsCancel").pressed.emit()
	_check(settings.crosshair_color == 4 and _arm_color(hud).is_equal_approx(Color8(50, 250, 250)),
		"Cancel discards an unapplied color")
	hud._show_pause_options()
	_check(color_option.selected == 4 and size_option.selected == 3 and not translucent.button_pressed,
		"reopening shows the applied appearance")

	settings.update_accessibility(1.0, true, false)
	_check(_arm_color(hud).is_equal_approx(Color("#fff316")), "high contrast still overrides the color")
	settings.update_accessibility(1.0, false, false)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_CROSSHAIR_OPTIONS_PASS")
	quit(0 if failures.is_empty() else 1)
