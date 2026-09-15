extends SceneTree

const Events = preload("res://scripts/network_combat_events.gd")
const ClientView = preload("res://scripts/network_client_view.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _starts(game: Node) -> Array:
	return game.audio_router.trace().filter(func(e: Dictionary) -> bool: return e.kind == "start")


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	game.set_physics_process(false)
	var player: PlayerController = game.player
	player.set_physics_process(false)
	player.viewmodel.set_process(false)
	for bot: Node in game._all_bots():
		bot.set_physics_process(false)
	player.alive = true
	player.global_position = Vector3(0, 100, 0)
	player._yaw = 0
	player._pitch = 0
	player._punch_degrees = Vector2.ZERO
	player._sync_view_angles()
	player.switch_weapon("knife")
	player.weapon_clock.reset("knife")
	await physics_frame
	for expected in ["midslash1", "midslash2"]:
		game.audio_router.reset(1)
		player._try_fire()
		_check(player.viewmodel._animation_name == expected, "click1 selects " + expected)
		_check(_starts(game).size() == 1 and _starts(game)[0].event_name == "knife.slash", "miss plays only a swish")
		player.viewmodel._process(0.2)
		_check(player.viewmodel._animation_name == expected, "slash remains animated at 200ms")
		var frame := player.viewmodel._frame_key
		player._try_fire()
		_check(player.viewmodel._frame_key == frame, "blocked repeat cannot restart motion")
		player.weapon_clock.advance_tick(50)
	game.audio_router.reset(1)
	_check(player._try_secondary(), "click2 accepted")
	_check(player.viewmodel._animation_name == "stab_miss", "click2 miss selects full stab miss")
	_check(_starts(game).size() == 1 and _starts(game)[0].event_name == "knife.slash", "stab miss never plays flesh impact")
	player.weapon_clock.advance_tick(100)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.1)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = player.camera.global_position + Vector3(0, 0, -0.25)
	await physics_frame
	game.audio_router.reset(1)
	_check(player._try_secondary(), "stab against wall accepted")
	_check(player.viewmodel._animation_name == "stab", "contact selects stab hit motion")
	_check(_starts(game).size() == 1 and _starts(game)[0].event_name == "knife.hit_wall", "wall contact plays only wall impact")
	wall.queue_free()
	await physics_frame
	var view := ClientView.new()
	game.add_child(view)
	view.set_process(false)
	view.game = game
	view.owner_id = "player"
	view._epoch = 1
	view.snapshot = {"tick": 1, "round": {"number": 1}, "actors": [{"id": "player", "life": 1, "alive": true, "weapon": "knife"}]}
	var session := root.get_node("NetworkSession")
	session.disconnect_session()
	session.combat_event_received.connect(view.queue_combat_event)
	var event := {"version": Events.VERSION, "epoch": 1, "sequence": 1, "tick": 1,
		"actor": "player", "life": 1, "kind": "knife_action", "data": {"action": "midslash1"}}
	for action in ["midslash1", "midslash2", "stab_miss", "stab"]:
		event.data.action = action
		_check(not Events.validate(event).is_empty(), "bounded knife event validates")
		_check(session.accept_combat_event(event.duplicate(true)), "client accepts knife event")
		_check(player.viewmodel._animation_name == action, "client receives exact knife motion: " + action)
		player.viewmodel._process(0.2)
		_check(not session.accept_combat_event(event.duplicate(true)), "client rejects duplicate knife event")
		_check(player.viewmodel._animation_time >= 0.2, "duplicate event cannot restart attack")
		event.sequence += 1
	event.data.action = "reload"
	_check(Events.validate(event).is_empty(), "knife packet cannot select arbitrary animation")
	event.data.action = "stab"
	event.actor = ""
	_check(Events.validate(event).is_empty(), "knife packet requires actor identity")
	session.combat_event_received.disconnect(view.queue_combat_event)
	for weapon in ["m4a1", "usp"]:
		player.owned_weapons[weapon] = true
		player.ammunition[weapon] = {"clip": 10, "reserve": 90}
		player.switch_weapon(weapon)
		for silenced in [false, true, false]:
			player.weapon_clock.reset(weapon)
			if bool(player.weapon_modes.get(weapon, false)) != silenced:
				_check(player._try_secondary(), "silencer toggle accepted")
				var ammo := player.clip
				player._try_fire()
				_check(player.clip == ammo, "cannot shoot during attachment")
				player.weapon_clock.advance_tick(320)
				player.viewmodel._process(4.0)
			game.audio_router.reset(1)
			player._try_fire()
			var suffix := "" if silenced else "_unsil"
			var cue: String = weapon + (".fire_silenced" if silenced else ".fire")
			_check(_starts(game).size() == 1 and _starts(game)[0].event_name == cue, "fire sound matches mode: " + cue)
			_check(player.viewmodel._animation_name == "shoot1" + suffix, "shot shows matching barrel")
			player.viewmodel._process(2.0)
			_check(player.viewmodel._animation_name == "idle" + suffix, "idle retains visible silencer state")
			player.switch_weapon("knife")
			player.switch_weapon(weapon)
			_check(player.viewmodel._animation_name == "draw" + suffix, "re-equipping preserves silencer appearance")
			player.weapon_clock.reset(weapon)
			player._start_reload()
			_check(player.viewmodel._animation_name == "reload" + suffix, "reload preserves silencer appearance")
			player.reloading = false
			player._audio_schedule.clear()
	_check_kill_feed(game)
	_check_fresh_silencer_defaults(game)
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--capture":
			await _capture(game)
	print("GAME_KNIFE_SILENCER_PASS" if failures.is_empty() else "GAME_KNIFE_SILENCER_FAIL: " + str(failures))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _check_fresh_silencer_defaults(game: Node) -> void:
	var player: PlayerController = game.player
	player.team = "CT"
	player.reset_player(Vector3(0, 100, 0), false)
	_check(player.weapon_modes.usp and player.viewmodel.weapon_silenced, "fresh CT USP starts visibly silenced")
	for weapon in ["usp", "m4a1"]:
		player.switch_weapon("knife")
		player.grant_item(weapon)
		player.switch_weapon(weapon)
		player.weapon_clock.reset(weapon)
		game.audio_router.reset(1)
		player._try_fire()
		_check(_starts(game).size() == 1 and _starts(game)[0].event_name == weapon + ".fire_silenced", "fresh " + weapon + " first shot is suppressed")
		_check(player.viewmodel.weapon_silenced and player.viewmodel._animation_name == "shoot1", "first-shot animation is suppressed")
		player.weapon_clock.reset(weapon)
		_check(player._try_secondary() and not player.weapon_modes[weapon], "right-click removes default silencer")
		player.switch_weapon("knife")
		player.switch_weapon(weapon)
		player.grant_item(weapon)
		player.reset_player(player.global_position, true)
		_check(not player.weapon_modes[weapon] and not player.viewmodel.weapon_silenced, "owned/surviving weapon preserves selected mode")
		player.switch_weapon("knife")
		player.owned_weapons.erase(weapon)
		player.grant_item(weapon)
		_check(player.weapon_modes[weapon], "fresh replacement resets old weapon mode")
	player.team = "T"
	player.reset_player(player.global_position, false)
	_check(not bool(player.weapon_modes.get("glock18", false)), "Glock still defaults to semi-auto")


func _check_kill_feed(game: Node) -> void:
	var hud: GameHUD = game.hud
	for weapon: String in PlayerController.WEAPONS:
		hud.add_kill_notice("[b]Player 1[/b]", "T", weapon, "Player 2", "CT", true)
		var row := hud.kill_feed_box.get_child(-1) as RichTextLabel
		var expected := "grenade" if weapon in ["hegrenade", "c4"] else weapon
		if weapon == "mp5": expected = "mp5navy"
		if not hud._kill_feed_icons.has(expected):
			expected = "skull"
		_check(row.get_meta("weapon_icon") == expected and row.get_meta("headshot"), "kill uses weapon and headshot icons: " + weapon)
		_check(row.get_parsed_text().contains("[b]Player 1[/b]") and not row.get_parsed_text().contains(" hs"), "names remain literal and no text headshot placeholder")
		var texture: Texture2D = hud._kill_feed_icons[expected]
		_check(texture != null and texture.get_height() == 16, "original death sprite loaded: " + weapon)
	_check(hud.kill_feed_box.get_child_count() == hud.KILL_FEED_LIMIT, "kill feed remains bounded")
	hud.add_kill_notice("", "", "../../invalid", "World victim", "CT")
	_check(hud.kill_feed_box.get_child(-1).get_meta("weapon_icon") == "skull", "unknown or world kills use safe skull fallback")
	var attacker := Combatant.new()
	var victim := Combatant.new()
	attacker.configure_identity("T", "Grenadier")
	victim.configure_identity("CT", "Victim")
	game.add_child(attacker)
	game.add_child(victim)
	victim.receive_explosion_damage(200, Vector3.ZERO, attacker)
	_check(victim.last_damage_weapon == "hegrenade", "explosion records actual lethal weapon")
	game._emit_kill_notice(attacker, victim, false)
	_check(hud.kill_feed_box.get_child(-1).get_meta("weapon_icon") == "grenade", "grenade death uses explosion icon even without an equipped gun")
	attacker.queue_free()
	victim.queue_free()


func _capture(game: Node) -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	game.start_match()
	game.player.global_position = game.player_spawn
	game.player._yaw = 0.0
	game.player._pitch = 0.0
	game.player._punch_degrees = Vector2.ZERO
	game.player._sync_view_angles()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: Node in game._all_bots():
		bot.set_physics_process(false)
	game.player.camera.make_current()
	game.hud.set_deploy_visible(false)
	game.hud.set_buy_menu_visible(false)
	for row: Node in game.hud.kill_feed_box.get_children():
		game.hud.kill_feed_box.remove_child(row)
		row.queue_free()
	game.hud.add_kill_notice("@rushing_andrei", "T", "ak47", "Counter-Terrorist", "CT", true)
	game.hud.add_kill_notice("Counter-Terrorist", "CT", "m4a1", "Terrorist", "T")
	game.hud.add_kill_notice("@rushing_andrei", "T", "knife", "Counter-Terrorist", "CT")
	game.hud.add_kill_notice("Terrorist", "T", "hegrenade", "Counter-Terrorist", "CT")
	for frame in range(3):
		await process_frame
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png("/tmp/protocol47-kill-feed.png") == OK, "native kill-feed screenshot saved")
	game.hud.hide()
	game.player.weapon_anchor.show()
	game.player.viewmodel.load_weapon("knife")
	game.player.viewmodel.set_process(false)
	var grid := Image.create(2560, 1440, false, Image.FORMAT_RGB8)
	var actions := ["midslash1", "midslash2", "stab_miss", "stab"]
	for row_index in actions.size():
		for column in 4:
			game.player.viewmodel.play_action(actions[row_index])
			game.player.viewmodel._process([0.0, 0.15, 0.3, 0.6][column])
			await process_frame
			RenderingServer.force_draw()
			var frame := root.get_texture().get_image()
			frame.resize(640, 360)
			frame.convert(Image.FORMAT_RGB8)
			grid.blit_rect(frame, Rect2i(0, 0, 640, 360), Vector2i(column * 640, row_index * 360))
	_check(grid.save_png("/tmp/protocol47-knife-motion.png") == OK, "native knife animation contact sheet saved")
