extends SceneTree

## The bomb carrier's HUD status icon: the original 640hud7 "c4" sprite in
## green, shown while the local Terrorist carries the bomb, flashing inside a
## bomb site, stacked above the buy-zone cart, and cleared once the bomb is
## gone or the view is a spectator's.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("C4 CARRIER HUD: " + message)


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	root.gui_disable_input = true
	game.set_process_unhandled_input(false)
	game.player.set_process_input(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots(): bot.set_physics_process(false)
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	game.hud._select_team(1)
	game.hud._select_class(1)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots(): bot.set_physics_process(false)
	var player: PlayerController = game.player
	var hud: GameHUD = game.hud
	var icon: TextureRect = hud._c4_icon
	var player_id: String = game._round_id_for_actor(player)
	_check(player.team == "T" and player.alive, "real Terrorist deployment")
	_check(icon.texture != null and icon.texture.get_size() == Vector2(32, 32), "original 32px c4 sprite")
	_check(icon.get_meta("classic_sprite") == "c4" and icon.modulate.g > icon.modulate.r, "original artwork tinted green")

	# Start from a Terrorist without the bomb, wherever the rotation put it.
	game.round_state.bomb_owner = ""
	hud.set_buy_zone(false)
	game._update_tactical_hud()
	_check(not icon.visible, "a Terrorist without the bomb has no indicator")

	game.round_state.bomb_owner = player_id
	game._update_tactical_hud()
	_check(icon.visible, "carrying the bomb shows the indicator")
	_check(not is_instance_valid(hud._c4_flash) and is_equal_approx(icon.modulate.a, 1.0),
		"the indicator is steady outside a bomb site")

	hud.set_buy_zone(true)
	_check(icon.offset_top == -50.0, "the indicator stacks above the buy-zone cart")
	hud.set_buy_zone(false)
	_check(icon.offset_top == -16.0, "the indicator returns to the cart's slot")

	_check(not game.bomb_regions.is_empty(), "Dust2 exposes bomb site triggers")
	var bounds: AABB = game.bomb_regions[0].bounds
	var site := Vector3(bounds.get_center().x, bounds.position.y + 0.02, bounds.get_center().z)
	player.global_position = site
	_check(not game._bomb_region_at(site, game._human_hull_size(player)).is_empty(), "test stands inside a bomb site")
	game._update_tactical_hud()
	_check(icon.visible and is_instance_valid(hud._c4_flash) and hud._c4_flash.is_running(),
		"the indicator flashes inside a bomb site")
	for frame in range(20): await process_frame

	player.global_position = site + Vector3(0, 0, 40)
	game._update_tactical_hud()
	_check(icon.visible and not is_instance_valid(hud._c4_flash) and is_equal_approx(icon.modulate.a, 1.0),
		"leaving the site restores a steady, fully opaque indicator")
	if OS.get_cmdline_user_args().has("--capture"):
		# Capture the steady icon; mid-flash frames can catch it nearly clear.
		player.camera.make_current()
		player.weapon_anchor.show()
		for frame in range(4): await process_frame
		RenderingServer.force_draw()
		_check(root.get_texture().get_image().save_png("/tmp/protocol47-c4-carrier-hud.png") == OK, "native capture saved")

	hud.set_spectating(true)
	_check(not icon.visible, "spectating hides the carrier indicator")
	hud.set_spectating(false)
	_check(icon.visible, "returning from spectating restores it")

	game.round_state.bomb_owner = ""
	game._update_tactical_hud()
	_check(not icon.visible, "dropping or planting the bomb clears the indicator")

	# Network clients pass their owned C4 and the host's can_plant feedback.
	hud.update_bomb_carrier(true, true)
	_check(icon.visible and is_instance_valid(hud._c4_flash), "client feedback in a site flashes")
	hud.update_bomb_carrier(false, true)
	_check(not icon.visible and not is_instance_valid(hud._c4_flash), "can_plant without the bomb shows nothing")

	game.queue_free()
	await process_frame
	if failures.is_empty(): print("GAME_C4_CARRIER_HUD_PASS")
	quit(0 if failures.is_empty() else 1)
