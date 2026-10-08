extends SceneTree

## Click the actual paused menu through viewport GUI dispatch. Only production
## handles successful shutdown; the fixture may quit solely to report failure.
var game: Node
var network: Node
var requested := false
var failed := false


func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	failed = true
	push_error("MENU QUIT: " + message)
	quit(1)


func _run() -> void:
	if AudioServer.get_driver_name() != "Dummy":
		_fail("fixture must be silent")
		return
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	network = root.get_node("NetworkSession")
	if "--host-session" in OS.get_cmdline_user_args():
		if network.host_game(0, "127.0.0.1") != OK:
			_fail("could not create isolated loopback host")
			return
		# Pending-peer resources also have to be released before process exit.
		network._register_input_peer(99, Time.get_ticks_msec())
		game.remote_roster._on_peer_joined(99)
		if game.remote_roster.size() != 1:
			_fail("host fixture did not register pending peer")
			return
	game.start_match()
	game._set_paused(true)
	await process_frame
	await process_frame
	if "--pending-lookup" in OS.get_cmdline_user_args():
		if network.join_game("localhost") != OK or network._resolver_id == IP.RESOLVER_INVALID_ID:
			_fail("could not queue hostname lookup before Quit")
			return
	var button: Button = game.hud.pause_main_menu.get_node("GameMenu_quit")
	if paused == network.is_online() or not game._pause_menu_open() or not button.is_visible_in_tree() or button.disabled:
		_fail("actual Quit button must be usable with offline world pause or online local menu")
		return
	game.hud.quit_requested.connect(_on_quit_requested)
	game.tree_exiting.connect(_on_game_exiting)
	create_timer(2.0, true).timeout.connect(func() -> void:
		_fail("click did not terminate the game within two seconds")
	)
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		event.global_position = point
		root.push_input(event, true)


func _on_quit_requested() -> void:
	requested = true
	if network.is_online() or network.is_connecting() or network._resolver_id != IP.RESOLVER_INVALID_ID or network.is_host or network.has_input_peer(99) or game.remote_roster.size() != 0:
		_fail("Quit must close the network session and clear pending peers")
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail("Quit must release the mouse")


func _on_game_exiting() -> void:
	if requested and not failed:
		print("GAME_MENU_QUIT_PASS host_session=", "--host-session" in OS.get_cmdline_user_args(), " pending_lookup=", "--pending-lookup" in OS.get_cmdline_user_args())
	elif not failed:
		_fail("game exited without the actual menu request")
