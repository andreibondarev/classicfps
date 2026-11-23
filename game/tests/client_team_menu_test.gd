extends SceneTree

## Online clients open the team menu with M once joined, and cancelling it
## (0 or Esc) closes the menu instead of pausing, as offline.

const ClientView = preload("res://scripts/network_client_view.gd")
var failures: Array[String] = []

class SessionStub extends Node:
	var online := true
	func is_online() -> bool: return online
	func is_connecting() -> bool: return false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("CLIENT TEAM MENU: " + message)


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots(): bot.set_physics_process(false)
	var view := ClientView.new()
	game.add_child(view)
	view.set_process(false)
	view.game = game
	var session := SessionStub.new()
	game.add_child(session)
	view.session = session
	game._network_client_mode = true
	game.network_client_view = view
	game.match_started = true
	game.hud.set_deploy_visible(false)
	game.player.configure_identity("T", "Tester")
	var hud: GameHUD = game.hud

	view.handle_input(_key(KEY_M))
	_check(hud.current_input_contract().state == "team", "M opens the team menu for a joined player")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE or DisplayServer.get_name() == "headless", "the cursor is released")
	_check(hud.handle_menu_key(KEY_0) and hud.current_input_contract().state == "none", "0 closes the menu")
	_check(not game._pause_menu_open(), "cancelling does not open the pause menu")

	view.handle_input(_key(KEY_M))
	hud.handle_menu_key(KEY_ESCAPE)
	_check(hud.current_input_contract().state == "none" and not game._pause_menu_open(), "Esc also just closes it")

	game.player.configure_identity("UNASSIGNED", "Tester")
	view.handle_input(_key(KEY_M))
	_check(hud.current_input_contract().state == "none", "M is inert before joining a team")

	# Release pooled audio and the shared model caches so the process exits
	# without leaked resources.
	game.audio_router.stop_all("test_teardown")
	game.audio_playback.clear_pool()
	game.queue_free()
	await process_frame
	await process_frame
	CS16CombatEffects.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	if failures.is_empty():
		print("GAME_CLIENT_TEAM_MENU_PASS")
	quit(0 if failures.is_empty() else 1)
