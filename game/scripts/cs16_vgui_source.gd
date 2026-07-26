class_name CS16VGuiSource
extends RefCounted

const ROOT := "res://assets/ui/classic/"
const CSTRIKE_UI := ROOT + "resources/cstrike/UI/"
const CSTRIKE_RESOURCE := ROOT + "resources/cstrike/"
const VALVE_RESOURCE := ROOT + "resources/valve/"
const BINDING_LIST := ROOT + "bindings/kb_act.lst"
const VOICE_ART := ROOT + "voice/"

var _cache: Dictionary = {}
var _tokens: Array[String] = []
var _token_index := 0
var _localization: Dictionary = {}


func _init() -> void:
	_load_localization(CSTRIKE_RESOURCE + "cstrike_english.kv")
	_load_localization(VALVE_RESOURCE + "gameui_english.kv")
	_load_localization(VALVE_RESOURCE + "valve_english.kv")


func parse_file(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing staged App 90 VGUI resource: %s" % path)
		return {}
	var bytes := file.get_buffer(file.get_length())
	var text := ""
	if bytes.size() >= 2 and (
		(bytes[0] == 0xff and bytes[1] == 0xfe)
		or (bytes[0] == 0xfe and bytes[1] == 0xff)
	):
		text = bytes.get_string_from_utf16()
	else:
		text = bytes.get_string_from_utf8()
	_tokens = _tokenize(text)
	_token_index = 0
	var parsed := _parse_object(false)
	_cache[path] = parsed
	return parsed


func control(path: String, control_name: String) -> Dictionary:
	var parsed := parse_file(path)
	for root_key in parsed:
		var root_value: Variant = parsed[root_key]
		if root_value is Dictionary and (root_value as Dictionary).has(control_name):
			return (root_value as Dictionary)[control_name]
	if parsed.has(control_name) and parsed[control_name] is Dictionary:
		return parsed[control_name]
	return {}


func controls(path: String) -> Dictionary:
	var parsed := parse_file(path)
	for root_key in parsed:
		var value: Variant = parsed[root_key]
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}


func control_rect(
	path: String,
	control_name: String,
	fallback: Rect2,
	reference_size := Vector2(640.0, 480.0),
) -> Rect2:
	var data := control(path, control_name)
	if data.is_empty():
		return fallback
	return Rect2(
		Vector2(
			_resolve_coordinate(str(data.get("xpos", fallback.position.x)), reference_size.x),
			_resolve_coordinate(str(data.get("ypos", fallback.position.y)), reference_size.y),
		),
		Vector2(
			float(str(data.get("wide", fallback.size.x))),
			float(str(data.get("tall", fallback.size.y))),
		),
	)


func scheme_color(color_name: String, fallback: Color) -> Color:
	var parsed := parse_file(CSTRIKE_RESOURCE + "ClientScheme.kv")
	var scheme: Dictionary = parsed.get("Scheme", {})
	var colors: Dictionary = scheme.get("Colors", {})
	var raw := str(colors.get(color_name, ""))
	var visited := {}
	while colors.has(raw) and not visited.has(raw):
		visited[raw] = true
		raw = str(colors[raw])
	var parts := raw.split(" ", false)
	if parts.size() < 3:
		return fallback
	var alpha := int(parts[3]) if parts.size() >= 4 else 255
	return Color8(int(parts[0]), int(parts[1]), int(parts[2]), alpha)


func font_size(font_name: String, y_resolution: int, fallback: int) -> int:
	return int(font_spec(font_name, y_resolution, {"tall": fallback}).get("tall", fallback))


func font_spec(font_name: String, y_resolution: int, fallback := {}) -> Dictionary:
	var parsed := parse_file(CSTRIKE_RESOURCE + "ClientScheme.kv")
	var scheme: Dictionary = parsed.get("Scheme", {})
	var fonts: Dictionary = scheme.get("Fonts", {})
	var font_rules: Dictionary = fonts.get(font_name, {})
	var first_rule: Dictionary = {}
	for key in font_rules:
		var value: Variant = font_rules[key]
		if not value is Dictionary:
			continue
		var rule: Dictionary = value
		if first_rule.is_empty():
			first_rule = rule
		var y_range := str(rule.get("yres", "")).split(" ", false)
		if (
			y_range.is_empty()
			or (
				y_range.size() == 2
				and y_resolution >= int(y_range[0])
				and y_resolution <= int(y_range[1])
			)
		):
			return _normalize_font_spec(font_name, rule, fallback)
	if not first_rule.is_empty():
		return _normalize_font_spec(font_name, first_rule, fallback)
	var result: Dictionary = fallback.duplicate(true)
	result["font_key"] = font_name
	return result


func controls_by_tab(path: String) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for control_name in controls(path):
		var data: Variant = controls(path)[control_name]
		if not data is Dictionary:
			continue
		var copy: Dictionary = (data as Dictionary).duplicate(true)
		copy["source_control"] = str(control_name)
		copy["tab_position"] = int(copy.get("tabPosition", 0))
		ordered.append(copy)
	ordered.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var a_tab := int(a.tab_position)
			var b_tab := int(b.tab_position)
			if a_tab == b_tab:
				return str(a.source_control) < str(b.source_control)
			if a_tab == 0:
				return false
			if b_tab == 0:
				return true
			return a_tab < b_tab
	)
	return ordered


func composite_rgba(foreground: Color, background: Color) -> Color:
	var alpha := foreground.a + background.a * (1.0 - foreground.a)
	if alpha <= 0.0:
		return Color.TRANSPARENT
	return Color(
		(foreground.r * foreground.a + background.r * background.a * (1.0 - foreground.a)) / alpha,
		(foreground.g * foreground.a + background.g * background.a * (1.0 - foreground.a)) / alpha,
		(foreground.b * foreground.a + background.b * background.a * (1.0 - foreground.a)) / alpha,
		alpha,
	)


func _normalize_font_spec(font_name: String, rule: Dictionary, fallback: Dictionary) -> Dictionary:
	var result: Dictionary = fallback.duplicate(true)
	result["font_key"] = font_name
	result["name"] = str(rule.get("name", result.get("name", "Verdana")))
	result["tall"] = int(rule.get("tall", result.get("tall", 12)))
	result["weight"] = int(rule.get("weight", result.get("weight", 400)))
	result["underline"] = int(rule.get("underline", result.get("underline", 0))) != 0
	result["antialias"] = int(rule.get("antialias", result.get("antialias", 0))) != 0
	result["dropshadow"] = int(rule.get("dropshadow", result.get("dropshadow", 0))) != 0
	result["outline"] = int(rule.get("outline", result.get("outline", 0)))
	return result


func localize(token: String, fallback := "") -> String:
	if not token.begins_with("#"):
		return token
	var key := token.trim_prefix("#").to_lower()
	return str(_localization.get(key, fallback if not fallback.is_empty() else token))


func menu_entries(in_game := true, single_player := false) -> Array[Dictionary]:
	var parsed := parse_file(CSTRIKE_RESOURCE + "GameMenu.kv")
	var menu: Dictionary = parsed.get("GameMenu", {})
	var numeric_keys: Array[int] = []
	for key in menu:
		if str(key).is_valid_int():
			numeric_keys.append(int(key))
	numeric_keys.sort()
	var entries: Array[Dictionary] = []
	for numeric_key in numeric_keys:
		var entry: Dictionary = menu.get(str(numeric_key), {})
		if str(entry.get("label", "")).is_empty():
			continue
		if int(entry.get("OnlyInGame", 0)) != 0 and not in_game:
			continue
		if int(entry.get("notsingle", 0)) != 0 and single_player:
			continue
		if int(entry.get("notmulti", 0)) != 0 and not single_player:
			continue
		entries.append(entry.duplicate(true))
	return entries


func asset_texture(asset_name: String) -> Texture2D:
	return load(ROOT + "vgui/%s.tga" % asset_name) as Texture2D


func menu_texture(mouseover := false) -> Texture2D:
	var name := "game_menu_mouseover.tga" if mouseover else "game_menu.tga"
	return load(CSTRIKE_RESOURCE + name) as Texture2D


func logo_texture() -> Texture2D:
	return load(CSTRIKE_RESOURCE + "logo_game.tga") as Texture2D


func mic_meter_texture(live := false) -> Texture2D:
	return load(
		VALVE_RESOURCE + ("mic_meter_live.tga" if live else "mic_meter_dead.tga")
	) as Texture2D


func voice_texture(muted := false, level := 4) -> Texture2D:
	if muted:
		return load(VOICE_ART + "640_voiceblocked.tga") as Texture2D
	var safe_level := clampi(level, 1, 4)
	return load(VOICE_ART + "640_speaker%d.tga" % safe_level) as Texture2D


func key_bindings() -> Array[Dictionary]:
	var file := FileAccess.open(BINDING_LIST, FileAccess.READ)
	if file == null:
		push_error("Missing staged App 90 key binding list: %s" % BINDING_LIST)
		return []
	var tokens := _tokenize(file.get_as_text())
	var rows: Array[Dictionary] = []
	for index in range(0, tokens.size() - 1, 2):
		var command := str(tokens[index])
		var label_token := str(tokens[index + 1])
		var label := localize(label_token, label_token.trim_prefix("#"))
		rows.append({
			"command": command,
			"label": label,
			"label_token": label_token,
			"is_heading": command == "blank" and not label.begins_with("="),
			"is_separator": command == "blank" and label.begins_with("="),
		})
	return rows


func map_briefing(map_name: String) -> Dictionary:
	var clean_name := map_name.get_file().get_basename().to_lower()
	var path := ROOT + "briefings/%s.txt" % clean_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"title": clean_name.to_upper(),
			"scenario": "",
			"body": "",
			"source_path": "",
		}
	var lines := file.get_as_text().replace("\r", "").split("\n")
	var heading := str(lines[0]).strip_edges() if not lines.is_empty() else clean_name
	var title := heading
	var scenario := ""
	var separator := heading.find(" - ")
	if separator >= 0:
		title = heading.substr(0, separator)
		scenario = heading.substr(separator + 3)
	var body_lines := PackedStringArray()
	for index in range(1, lines.size()):
		var line := str(lines[index]).strip_edges()
		if line.begins_with("***") or line.begins_with("by "):
			continue
		body_lines.append(line)
	return {
		"title": title,
		"scenario": scenario,
		"body": "\n".join(body_lines).strip_edges(),
		"source_path": path,
	}


func _load_localization(path: String) -> void:
	var parsed := parse_file(path)
	var language: Dictionary = parsed.get("lang", {})
	var tokens: Dictionary = language.get("Tokens", {})
	for key in tokens:
		_localization[str(key).to_lower()] = str(tokens[key])


func _resolve_coordinate(raw: String, extent: float) -> float:
	if raw.begins_with("c"):
		return extent * 0.5 + float(raw.trim_prefix("c"))
	if raw.begins_with("r"):
		return extent + float(raw.trim_prefix("r"))
	return float(raw)


func _tokenize(source: String) -> Array[String]:
	var tokens: Array[String] = []
	var index := 0
	while index < source.length():
		var character := source[index]
		if character == "/" and index + 1 < source.length() and source[index + 1] == "/":
			index += 2
			while index < source.length() and source[index] != "\n":
				index += 1
			continue
		if character == "\"" or character == "'":
			var quote := character
			index += 1
			var value := ""
			while index < source.length() and source[index] != quote:
				if source[index] == "\\" and index + 1 < source.length():
					index += 1
					match source[index]:
						"n":
							value += "\n"
						"t":
							value += "\t"
						_:
							value += source[index]
				else:
					value += source[index]
				index += 1
			index += 1
			tokens.append(value)
			continue
		if character == "{" or character == "}":
			tokens.append(character)
			index += 1
			continue
		if character == " " or character == "\t" or character == "\r" or character == "\n":
			index += 1
			continue
		var start := index
		while (
			index < source.length()
			and source[index] != " "
			and source[index] != "\t"
			and source[index] != "\r"
			and source[index] != "\n"
			and source[index] != "{"
			and source[index] != "}"
		):
			index += 1
		tokens.append(source.substr(start, index - start))
	return tokens


func _parse_object(expect_close: bool) -> Dictionary:
	var result := {}
	while _token_index < _tokens.size():
		var key := _tokens[_token_index]
		_token_index += 1
		if key == "}":
			return result
		if key == "{":
			continue
		if _token_index >= _tokens.size():
			result[key] = ""
			break
		var next := _tokens[_token_index]
		_token_index += 1
		if next == "{":
			result[key] = _parse_object(true)
		else:
			result[key] = next
	if expect_close:
		push_error("Unterminated App 90 KeyValues object")
	return result
