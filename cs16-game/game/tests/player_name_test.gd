extends SceneTree

const SettingsScript = preload("res://scripts/settings.gd")
const SessionScript = preload("res://scripts/network_session.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var settings := root.get_node("GameSettings")
	if OS.get_environment("PROTOCOL47_SETTINGS_PATH").is_empty() or settings.settings_path != OS.get_environment("PROTOCOL47_SETTINGS_PATH"):
		push_error("Player-name test requires isolated settings")
		quit(1)
		return
	_check(SettingsScript.sanitize_player_name("  Андрій [CT]  ") == "Андрій [CT]", "Unicode and clan tags remain plain text")
	_check(SettingsScript.sanitize_player_name(" \n\t ") == "Player", "blank name uses a visible fallback")
	_check(SettingsScript.sanitize_player_name("A\nB\tC" + String.chr(0x202E)) == "ABC", "control and direction overrides are removed")
	_check(SettingsScript.sanitize_player_name("x".repeat(100)).length() == 32, "name length is bounded")
	_test_network_validation()
	settings.update_player_name("Before Spawn")
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	_check(game.player.display_name == "Before Spawn", "saved name initializes the local actor")
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	var hud: CanvasLayer = game.hud
	hud.set_paused_visible(true)
	hud._show_pause_options()
	var entry := hud.options_pages.get_node("Page_multiplayer/Source_NameEntry") as LineEdit
	_check(entry.text == "Before Spawn" and entry.max_length == 32, "name field loads current settings and bounds input")
	var original_state: Dictionary = game.round_state.players.player.duplicate(true)
	_edit(entry, "  [P47] André  ")
	_check(settings.player_name == "Before Spawn" and game.player.display_name == "Before Spawn", "typing is pending until Apply/OK")
	hud.pause_options_menu.get_node("OptionsContent/OptionsApply").pressed.emit()
	_check(settings.player_name == "[P47] André" and game.player.display_name == settings.player_name and entry.text == settings.player_name, "Apply saves normalized name and updates the live actor/field")
	_check(game.player.name == "Player" and game._round_id_for_actor(game.player) == "player" and game.round_state.players.player == original_state, "rename preserves durable identity and all round stats")
	_check(game._combatant_display_name(game.player) == settings.player_name, "kill-notice name lookup uses the saved display name")
	await process_frame
	await process_frame
	var row: Node = hud.scoreboard_rows.get_node("Player_player")
	_check(row.get_meta("is_local") and (row.get_child(0).get_child(1) as Label).text == settings.player_name, "scoreboard uses new name and retains local highlight")
	_edit(entry, "Discard Me")
	hud.pause_options_menu.get_node("OptionsContent/OptionsCancel").pressed.emit()
	hud._show_pause_options()
	_check(entry.text == "[P47] André" and settings.player_name == entry.text, "Cancel after Apply discards only subsequent edits")
	_edit(entry, "[color=red]Name[/color]")
	hud.pause_options_menu.get_node("OptionsContent/OptionsOK").pressed.emit()
	_check(game.player.display_name == entry.text and not hud.pause_options_menu.visible, "OK applies and closes")
	hud.add_kill_notice(entry.text, "T", "ak47", "[b]Victim[/b]", "CT", true)
	var feed := hud.kill_feed_box.get_child(hud.kill_feed_box.get_child_count() - 1) as RichTextLabel
	_check(feed.get_parsed_text().contains(entry.text) and feed.get_parsed_text().contains("[b]Victim[/b]"), "names cannot inject kill-feed markup")
	var restored := SettingsScript.new()
	restored.settings_path = settings.settings_path
	restored.load_settings()
	_check(restored.player_name == settings.player_name, "name persists on disk")
	restored.free()
	game._on_team_selected(2)
	_check(game.player.display_name == settings.player_name, "team selection preserves name")
	game._on_team_selected(6)
	_check(game.player.display_name == settings.player_name, "spectator selection preserves name")
	game._restart_match()
	_check(game.player.display_name == settings.player_name, "match restart preserves name")
	hud.update_scoreboard([
		{"id": "player", "name": "Duplicate", "team": 1, "is_local": true},
		{"id": "remote_human_1", "name": "Duplicate", "team": 1, "is_local": false},
	], "Classic FPS", "de_dust2", 0, 0)
	_check(hud.scoreboard_rows.get_node("Player_player").get_meta("is_local") and not hud.scoreboard_rows.get_node("Player_remote_human_1").get_meta("is_local"), "duplicate display names keep separate rows and local identity")
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	for failure in failures:
		push_error(failure)
	print("GAME_PLAYER_NAME_PASS" if failures.is_empty() else "GAME_PLAYER_NAME_FAIL")
	quit(0 if failures.is_empty() else 1)


func _edit(entry: LineEdit, value: String) -> void:
	entry.text = value
	entry.text_changed.emit(entry.text)


func _test_network_validation() -> void:
	var session := SessionScript.new()
	session.is_host = true
	session._register_input_peer(2, 100)
	session._register_input_peer(3, 100)
	_check(session.accept_peer_name(2, "Remote André", 100), "registered sender can rename before Game loads")
	_check(session.peer_player_name(2, "fallback") == "Remote André" and session.peer_player_name(3, "fallback") == "fallback", "only the sender's display name changes")
	for value in [null, 42, {"peer_id": 3, "name": "Spoof"}, "", " padded ", "line\nbreak", "x".repeat(33)]:
		_check(not session.accept_peer_name(2, value, 100), "reject malformed name: " + str(value))
	_check(not session.accept_peer_name(1, "Spoof", 100) and not session.accept_peer_name(99, "Spoof", 100), "reject local or unknown sender")
	_check(not session.accept_peer_name(2, "Past", 99), "reject backwards rate clock")
	for index in 7:
		_check(session.accept_peer_name(2, "Name%d" % index, 100), "bounded name burst")
	_check(not session.accept_peer_name(2, "Flood", 100), "rate limit excess renames")
	_check(session.accept_peer_name(2, "Recovered", 1100), "name budget refills")
	session._remove_input_peer(2)
	session._register_input_peer(2, 1200)
	_check(session.peer_player_name(2, "fallback") == "fallback", "reused peer cannot inherit departed name")
	session.free()
