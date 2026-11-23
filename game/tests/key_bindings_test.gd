extends SceneTree

## Options > Keyboard: select a row, Edit key, press a key; bindings stay
## pending until Apply, then drive the InputMap (actions) or the key checks
## (menu commands such as chooseteam), persist, and support Clear, conflicts,
## Esc-cancel and Use Defaults. Unsupported actions cannot be rebound.

const SettingsScript = preload("res://scripts/settings.gd")
const KeyBindings = preload("res://scripts/cs16_key_bindings.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("KEY BINDINGS: " + message)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _action_key(action: StringName) -> String:
	var events := InputMap.action_get_events(action)
	return KeyBindings.event_text(events[0]) if not events.is_empty() else ""


func _row(hud: CanvasLayer, command: String) -> Control:
	return hud.options_pages.get_node(
		"Page_keyboard/Source_listpanel_keybindlist/Scroll/Bindings/Binding_%s" % command.validate_node_name()) as Control


func _select(hud: CanvasLayer, command: String) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_row(hud, command).gui_input.emit(click)


func _edit(hud: CanvasLayer, keycode: Key) -> void:
	(hud.options_pages.get_node("Page_keyboard/Source_ChangeKeyButton") as Button).pressed.emit()
	hud._input(_key(keycode))


func _key_text(hud: CanvasLayer, command: String) -> String:
	return (_row(hud, command).get_node("Key") as Label).text


func _run() -> void:
	var settings := root.get_node("GameSettings")
	if OS.get_environment("PROTOCOL47_SETTINGS_PATH").is_empty() or settings.settings_path != OS.get_environment("PROTOCOL47_SETTINGS_PATH"):
		push_error("Key bindings test requires isolated settings")
		quit(1)
		return
	settings.update_key_bindings({})
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
	_check(_action_key(&"jump") == "SPACE", "default jump is SPACE")

	hud.set_paused_visible(true)
	hud._show_pause_options()
	hud._show_options_tab("keyboard")
	var header: Node = hud.options_pages.get_node_or_null("Page_keyboard/Source_listpanel_keybindlist/Header")
	_check(header != null and header.get_node("Column_Action") != null, "list has Action / Key columns")
	_check(_key_text(hud, "+jump") == "SPACE" and _key_text(hud, "slot1") == "1", "rows show current and fixed keys")

	_select(hud, "+jump")
	_check((_row(hud, "+jump").get_node("Highlight") as ColorRect).visible, "clicking a row selects it")
	_edit(hud, KEY_J)
	_check(_key_text(hud, "+jump") == "J" and _action_key(&"jump") == "SPACE", "the new key is pending until Apply")
	hud.pause_options_menu.get_node("OptionsContent/OptionsApply").pressed.emit()
	_check(_action_key(&"jump") == "J" and settings.key_bindings.get("+jump") == "J", "Apply rebinds the jump action")

	_select(hud, "+use")
	_edit(hud, KEY_J)
	_check(_key_text(hud, "+use") == "J" and _key_text(hud, "+jump") == "", "taking a used key clears its old action")
	(hud.options_pages.get_node("Page_keyboard/Source_ClearKeyButton") as Button).pressed.emit()
	_check(_key_text(hud, "+use") == "", "Clear key unbinds the selection")
	(hud.options_pages.get_node("Page_keyboard/Source_ChangeKeyButton") as Button).pressed.emit()
	hud._input(_key(KEY_ESCAPE))
	_check(_key_text(hud, "+use") == "" and hud._key_capture_command.is_empty(), "Esc cancels a capture")

	_select(hud, "+left")
	(hud.options_pages.get_node("Page_keyboard/Source_ChangeKeyButton") as Button).pressed.emit()
	_check(hud._key_capture_command.is_empty(), "actions the game lacks cannot be rebound")

	(hud.options_pages.get_node("Page_keyboard/Source_Defaults") as Button).pressed.emit()
	_check(_key_text(hud, "+jump") == "SPACE" and _key_text(hud, "+use") == "E", "Use Defaults restores every key")
	hud.pause_options_menu.get_node("OptionsContent/OptionsApply").pressed.emit()
	_check(_action_key(&"jump") == "SPACE" and settings.key_bindings.is_empty(), "applying defaults clears overrides")

	# A key-check command: the team menu moves from M to J.
	_select(hud, "chooseteam")
	_edit(hud, KEY_J)
	hud.pause_options_menu.get_node("OptionsContent/OptionsOK").pressed.emit()
	var reloaded := SettingsScript.new()
	reloaded.settings_path = settings.settings_path
	reloaded.load_settings()
	_check(reloaded.key_bindings == {"chooseteam": "J"}, "bindings persist to the settings file")
	reloaded.free()
	hud.set_paused_visible(false)
	game.match_started = true
	game.hud.set_deploy_visible(false)
	game._unhandled_input(_key(KEY_M))
	_check(hud.current_input_contract().state == "none", "M no longer opens the team menu")
	game._unhandled_input(_key(KEY_J))
	_check(hud.current_input_contract().state == "team", "J now opens the team menu")
	settings.update_key_bindings({})

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_KEY_BINDINGS_PASS")
	quit(0 if failures.is_empty() else 1)
