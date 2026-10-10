extends SceneTree

var failures: Array[String] = []


class ErrorCatcher extends Logger:
	var messages: Array[String] = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(code + " " + rationale)


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var hud := GameHUD.new()
	root.add_child(hud)
	await process_frame
	hud.set_deploy_visible(false)
	var submissions: Array[Dictionary] = []
	hud.chat_submitted.connect(func(text: String, team_only: bool) -> void:
		submissions.append({"text": text, "team_only": team_only})
	)
	_check(hud.open_chat(true), "team chat opens")
	_check(hud.chat_input_panel.visible and hud.chat_prompt_label.text == "Say (TEAM):",
		"team chat shows the classic channel prompt")
	_check(hud.current_input_contract() == {"state": "chat", "captures_keyboard": true, "mouse_visible": false},
		"typing captures keyboard controls without releasing the FPS mouse")
	hud.chat_entry.text_submitted.emit("  Hold B  ")
	_check(submissions == [{"text": "Hold B", "team_only": true}],
		"Enter submits trimmed team text once")
	_check(not hud.chat_input_panel.visible and hud.current_input_contract().state == "none",
		"submitting returns control to gameplay")

	_check(hud.open_chat(false), "all-chat opens")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	hud._on_chat_entry_gui_input(escape)
	_check(not hud.chat_input_panel.visible and submissions.size() == 1,
		"Escape cancels without sending")

	hud.add_chat_message({"sender_name": "[color=red]Name[/color]", "team": "CT",
		"team_only": false, "text": "[b]literal[/b]"})
	var safe_row := hud.chat_feed_box.get_child(0) as RichTextLabel
	_check(safe_row.get_parsed_text().contains("[color=red]Name[/color]") \
		and safe_row.get_parsed_text().contains("[b]literal[/b]"),
		"chat names and text cannot inject rich-text markup")
	for index in range(10):
		hud.add_chat_message({"sender_name": "Player", "team": "T",
			"team_only": index % 2 == 0, "text": "Message %d" % index})
	_check(hud.chat_feed_box.get_child_count() == hud.CHAT_MAX_ROWS,
		"chat feed remains bounded")
	# A dedicated server rebuilds its HUD when the last player leaves, freeing
	# rows whose expiry is still pending; that must stay silent (no freed
	# lambda capture errors in the log) while live rows still expire.
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var rebuilt := GameHUD.new()
	root.add_child(rebuilt)
	await process_frame
	rebuilt.add_chat_message({"sender_name": "Player", "team": "T", "team_only": false, "text": "bye"})
	rebuilt.free()
	await create_timer(hud.CHAT_ROW_SECONDS + 0.3).timeout
	OS.remove_logger(catcher)
	_check(catcher.messages.filter(func(m: String) -> bool: return m.contains("freed")).is_empty(),
		"a freed HUD's pending chat expiry logs no errors: %s" % [catcher.messages])
	_check(hud.chat_feed_box.get_child_count() == 0, "chat rows expire after CHAT_ROW_SECONDS")
	hud.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("GAME_CHAT_UI_PASS" if failures.is_empty() else "GAME_CHAT_UI_FAIL")
	quit(0 if failures.is_empty() else 1)
