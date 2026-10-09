extends RefCounted

## Rebindable commands from the Options > Keyboard list (kb_act.lst names).
## Each maps to its default key and, when the game reads it through the
## InputMap, the action it drives. Commands without an action are read by
## key checks in game.gd / network_client_view.gd, which see a rebound key
## as its command's default key through canonical_keycode().
## Keys are stored as uppercase OS key names ("W", "CTRL", "TAB") or MOUSE1-5.
const COMMANDS := {
	"+forward": ["W", "move_forward"],
	"+back": ["S", "move_back"],
	"+moveleft": ["A", "move_left"],
	"+moveright": ["D", "move_right"],
	"+speed": ["SHIFT", "walk"],
	"+jump": ["SPACE", "jump"],
	"+duck": ["CTRL", "crouch"],
	"+attack": ["MOUSE1", "fire"],
	"+reload": ["R", "reload"],
	"+use": ["E", "use"],
	"drop": ["G", "drop"],
	"lastinv": ["Q", "weapon_last"],
	"radio1": ["Z", ""],
	"radio2": ["X", ""],
	"radio3": ["C", ""],
	"messagemode": ["Y", ""],
	"messagemode2": ["U", ""],
	"buy": ["B", ""],
	"chooseteam": ["M", ""],
	"+showscores": ["TAB", ""],
	"nightvision": ["N", ""],
	"impulse 201": ["T", ""],
}
## Shown in the list but fixed: menus and weapon slots read the digit keys.
const FIXED := {
	"slot1": "1", "slot2": "2", "slot3": "3", "slot4": "4", "slot5": "5",
	"slot6": "6", "slot7": "7", "slot8": "8", "slot9": "9", "slot10": "0",
	"+attack2": "MOUSE2",
}


static func is_bindable(command: String) -> bool:
	return COMMANDS.has(command)


static func default_bindings() -> Dictionary:
	var result := {}
	for command: String in COMMANDS:
		result[command] = str(COMMANDS[command][0])
	return result


## Saved overrides on top of the defaults; unknown commands are dropped.
static func effective(overrides: Dictionary) -> Dictionary:
	var result := default_bindings()
	for command: Variant in overrides:
		if COMMANDS.has(str(command)):
			result[str(command)] = normalize(str(overrides[command]))
	return result


static func normalize(key_text: String) -> String:
	var text := key_text.strip_edges().to_upper()
	if text.is_empty() or text.begins_with("MOUSE"):
		return text if text.is_empty() or _mouse_button(text) != MOUSE_BUTTON_NONE else ""
	var keycode := OS.find_keycode_from_string(text)
	return OS.get_keycode_string(keycode).to_upper() if keycode != KEY_NONE else ""


## The name of the key or mouse button an input event presses, or "".
static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return OS.get_keycode_string(code).to_upper() if code != KEY_NONE else ""
	if event is InputEventMouseButton:
		var index := int((event as InputEventMouseButton).button_index)
		return "MOUSE%d" % index if index >= 1 and index <= 5 else ""
	return ""


static func _mouse_button(text: String) -> MouseButton:
	var index := text.trim_prefix("MOUSE").to_int() if text.begins_with("MOUSE") else 0
	return index as MouseButton if index >= 1 and index <= 5 else MOUSE_BUTTON_NONE


## Rewrites the InputMap actions behind rebindable commands.
static func apply_actions(bindings: Dictionary) -> void:
	for command: String in COMMANDS:
		var action := StringName(COMMANDS[command][1])
		if action.is_empty():
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var text := str(bindings.get(command, ""))
		if text.is_empty():
			continue
		var button := _mouse_button(text)
		if button != MOUSE_BUTTON_NONE:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = button
			InputMap.action_add_event(action, mouse)
		else:
			var key := InputEventKey.new()
			key.physical_keycode = OS.find_keycode_from_string(text)
			InputMap.action_add_event(action, key)


## For key-check commands: a key bound to one of them reads as that command's
## default key, and a default key whose command moved elsewhere reads as
## KEY_NONE. Every other key passes through unchanged.
static func canonical_keycode(event: InputEventKey, bindings: Dictionary) -> Key:
	var pressed := event_text(event)
	var logical := OS.get_keycode_string(event.keycode).to_upper() if event.keycode != KEY_NONE else ""
	for command: String in COMMANDS:
		if not str(COMMANDS[command][1]).is_empty():
			continue
		var bound := str(bindings.get(command, ""))
		if not bound.is_empty() and (bound == pressed or bound == logical):
			return OS.find_keycode_from_string(str(COMMANDS[command][0]))
	for command: String in COMMANDS:
		if not str(COMMANDS[command][1]).is_empty():
			continue
		var default_text := str(COMMANDS[command][0])
		if default_text == logical and str(bindings.get(command, "")) != default_text:
			return KEY_NONE
	return event.keycode
