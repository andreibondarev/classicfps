extends SceneTree

var game: Node
var network: Node
var failures: Array[String] = []
var c4_drop_spawns := 0
var stage := "initializing"


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _wait_for(predicate: Callable, description: String) -> bool:
	stage = description
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	print("NETWORK_WORLD_TIMEOUT_STATE ", {"stage": description, "host": network.is_host,
		"result": network.latest_action_result, "weapon": game.player.active_weapon, "inventory": game.player.owned_weapons,
		"bomb_state": game.round_state.bomb_state, "bomb_owner": game.round_state.bomb_owner})
	if is_instance_valid(game.network_client_view):
		print("NETWORK_COMBAT_TIMEOUT ", {"counts": game.network_client_view.presented_combat_counts,
			"pending": game.network_client_view._pending_combat, "actors": game.network_client_view.snapshot.get("actors", [])})
	if network.is_host and game.remote_roster.size() > 0:
		var remote: PlayerController = game.remote_roster.actor_for_id(game.remote_roster.actor_ids()[0])
		print("NETWORK_WORLD_TIMEOUT_REMOTE ", {"weapon": remote.active_weapon, "inventory": remote.owned_weapons,
			"position": remote.global_position, "actions": network._action_peers})
	failures.append("Timed out: " + description)
	return false


func _load_game() -> void:
	_stage("instantiate Game")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	_stage("first process frame")
	await process_frame
	_stage("first physics frame")
	await physics_frame
	_stage("presentation warmup")
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	_stage("Game ready")


func _stage(value: String) -> void:
	stage = value
	print("NETWORK_WORLD_STAGE ", value)


func _run() -> void:
	network = root.get_node("NetworkSession")
	create_timer(60.0).timeout.connect(func() -> void:
		push_error("World fixture deadline at stage: " + stage)
		print("NETWORK_WORLD_DEADLINE_STATE ", {"stage": stage, "paused": paused,
			"host": network.is_host, "online": network.is_online(),
			"presentation_ready": game.combat_effects.presentation_is_ready if is_instance_valid(game) else false})
		quit(1)
	)
	var role := ""
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
	if role not in ["host", "client"] or port < 1024 or port > 65535 or AudioServer.get_driver_name() != "Dummy":
		push_error("World fixture requires role, loopback port and Dummy audio")
		quit(1)
		return
	if role == "host":
		await _host(port)
	else:
		await _client(port)
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_WORLD_", role.to_upper(), "_PASS")
	quit(0 if failures.is_empty() else 1)


func _host(port: int) -> void:
	root.get_node("GameSettings").update_player_name("Host Before")
	await _load_game()
	game.child_entered_tree.connect(func(child: Node) -> void:
		if child is CS16C4World:
			c4_drop_spawns += 1
	)
	game.round_state.configure({"freeze_ticks": 1})
	game.start_match()
	game.player.set_physics_process(false)
	# Keep AI stationary so the transport assertions have controlled opponents.
	# The actual Game and admitted human retain normal physics/round processing.
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	if game.map_name == "de_dust2":
		game._set_paused(true)
		_click_menu_button(game.hud.pause_main_menu.get_node("GameMenu_new_game"))
		game.hud.network_port.text = str(port)
		_click_menu_button(game.hud.network_connect_button)
		_check(network.is_host and network.is_online(), "actual Host Dust2 menu starts server")
		_click_menu_button(game.hud.network_menu.get_node("Back"))
		_click_menu_button(game.hud.pause_main_menu.get_node("GameMenu_resume"))
	else:
		_check(network.host_game(port, "127.0.0.1") == OK, "host opens isolated server")
	print("NETWORK_TRANSPORT_READY")
	# Persistent graffiti is state, not a transient event: late joiners see it.
	game.sprays.apply_records([{"id": 1, "position": Vector3(0, 100, 0), "normal": Vector3.BACK}])
	if not await _wait_for(func() -> bool: return game.remote_roster.size() == 1, "client owns a pending human"):
		return
	var human: PlayerController = game.remote_roster.actor_for_id(game.remote_roster.actor_ids()[0])
	var peer: int = human.combat_controller._peer_id
	if not await _wait_for(func() -> bool: return human.alive, "real client menu completes class admission"):
		return
	if not await _wait_for(func() -> bool: return human.display_name == "Client Renamed", "client Apply changes authoritative name"):
		return
	_check(game.player.display_name == "Host Before", "remote rename cannot change host identity")
	root.get_node("GameSettings").update_player_name("Host Renamed")
	var spawn := human.global_position
	if game.map_name == "de_dust2":
		game._set_paused(true)
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 32, "client saw movement and its shot"):
		return
	_check(human.global_position.distance_to(spawn) > 0.05 and human._shot_sequence == 1 and human.clip == 19,
		"client input moves/fires exactly one pistol shot on the host pawn")
	_check(human.previous_weapon == "knife" and human.active_weapon == "glock18", "client slot/lastinv commands selected host-owned weapons")
	# Host-owned first-person pawn also appears as a remote shooter/reloader.
	game.player.grant_item("ak47")
	game.player.switch_weapon("ak47")
	game.player.reserve = 90 # Explicit fixture ammunition; a granted gun has no reserve.
	game.player._advance_weapon_simulation_tick(400)
	game.player._try_fire()
	game.player._advance_weapon_simulation_tick(20)
	game.player._start_reload()
	game.player._advance_weapon_simulation_tick(40)
	print("NETWORK_HOST_COMBAT ", {"actor": game._network_actor_state(game.player), "shots": game.player._shot_sequence,
		"reload": game.player.reloading, "event_sequence": network._combat_sequence})
	game.combat_effects.spawn_world_impact(human.global_position + Vector3.UP, Vector3.UP, 17)
	game.combat_effects.spawn_blood_impact(human.global_position + Vector3.UP, Vector3.FORWARD, 18)
	game.combat_effects.spawn_blood_decal(human.global_position, Vector3.UP, 18)
	await create_timer(0.2).timeout
	if game.map_name == "de_dust2":
		_check(game._pause_menu_open() and not paused, "host pause menu cannot stop client buying, movement or shooting")
		game._set_paused(false)
		_check(human.equipment.kevlar and human.armor == 100 and game.round_state.players[game._round_id_for_actor(human)].money == 150,
			"client menu purchase used authoritative inventory and debited its own 800-dollar wallet")
		_check(game.round_state.players.player.money == 800 and not game.player.equipment.kevlar,
			"client purchase leaves host local wallet and armor untouched")
	human.receive_damage(25, human.global_position)
	print("NETWORK_BUY_DAMAGE ", {"health": human.health, "armor": human.armor})
	for bot: TargetActor in game._all_bots():
		if bot.team == "CT":
			bot.receive_damage(10000, bot.global_position, true, human)
	_check(game.phase == "post" and game.terrorist_score == 1, "normal elimination produces authoritative round result")
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 16, "client verified damage, corpses and round result"):
		return
	game._reset_round()
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	# Staged grants exercise authoritative inventory/selection, not buying.
	human.grant_item("ak47")
	human.ammunition.ak47 = {"clip": 7, "reserve": 29}
	for item: String in ["hegrenade", "flashbang", "smokegrenade", "kevlar"]:
		human.grant_item(item)
	if game.map_name == "de_dust2":
		human.weapon_drop_requested.connect(func(weapon: String, _clip: int, _reserve: int) -> void:
			if weapon == "ak47":
				human.grant_item("awp")  # Staged follow-up for live zoom presentation.
		)
		_check(game.round_state.drop_bomb(game.round_state.bomb_owner, human.global_position), "fixture drops normal carried C4")
		_check(game.round_state.pickup_bomb(game._round_id_for_actor(human), human.global_position), "remote human picks up normal dropped C4")
		game._consume_new_round_trace()
		game._sync_player_c4_ownership()
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 32, "client verified new round and revived replicas"):
		return
	_check(human.active_weapon == "glock18" and human.clip == 19
		and human.equipment.kevlar, "slot/grenade/C4 selections preserve host inventory and exact ammo")
	if game.map_name == "de_dust2":
		var rifles: Array = game.dropped_weapons.filter(func(item: Node) -> bool: return item.weapon_name == "ak47")
		_check(not human.owns_weapon("ak47") and rifles.size() == 1 and rifles[0].clip_ammo == 7 and rifles[0].reserve_ammo == 29,
			"reliable drop creates exactly one host world gun with preserved ammunition")
		var manual_drops: Array = game.round_state.trace.filter(func(event: Dictionary) -> bool:
			return event.type == "bomb_dropped" and str(event.player_id) == game._round_id_for_actor(human))
		_check(manual_drops.size() == 1 and c4_drop_spawns == 2, "one staged transfer plus exactly one network C4 drop materialize world items")
		_check((game.round_state.bomb_state == game.round_state.BOMB_DROPPED and is_instance_valid(game.dropped_c4))
			or (game.round_state.bomb_state == game.round_state.BOMB_CARRIED and not is_instance_valid(game.dropped_c4)
				and not str(game.round_state.bomb_owner).is_empty()), "subsequent normal pickup or remaining world drop has consistent ownership")
		print("NETWORK_C4_DROP_TRACE ", {"spawned_world_items": c4_drop_spawns, "manual_drops": manual_drops.size(), "state": game.round_state.bomb_state, "owner": game.round_state.bomb_owner,
			"events": game.round_state.trace.filter(func(event: Dictionary) -> bool: return str(event.type) in ["bomb_dropped", "bomb_picked_up"])})
		if not await _host_item_scenario(human, peer):
			return
		if not await _host_grenade_scenario(human, peer):
			return
	print("NETWORK_SHARED_ACTORS map=", game.map_name, " actors=", game._all_bots().size() + game._human_players_stable().size(),
		" host_round=", game.round_number, " remote_shots=", human._shot_sequence, " packet_bytes=", network.largest_world_packet_bytes,
		" snapshot_bytes=", network.largest_world_snapshot_bytes)
	_check(network.largest_world_packet_bytes <= 1200, "normal ten-player snapshots fit an unfragmented network payload")
	network.disconnect_session()
	await create_timer(0.3).timeout


func _mode_cue_count() -> int:
	var count := 0
	for event: Dictionary in game.audio_router.trace():
		if event.kind == "start" and event.event_name == "weapon.mode_switch":
			count += 1
	return count


func _client(port: int) -> void:
	root.get_node("GameSettings").update_player_name("Client Before")
	network.action_result_received.connect(func(result: Dictionary) -> void:
		if result.action == "drop_weapon":
			print("NETWORK_DROP_RESULT ", result)
	)
	if "--map=de_dust2" in OS.get_cmdline_user_args():
		await _load_game()
		game._set_paused(true)
		_click_menu_button(game.hud.pause_main_menu.get_node("GameMenu_servers"))
		game.hud.network_address.text = "localhost"
		game.hud.network_port.text = str(port)
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				_stage("draw connection menu")
				await _draw_capture_frame()
				_check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture=").replace(".png", "-connect-menu.png")) == OK, "save direct connection menu")
		_stage("click Join")
		_click_menu_button(game.hud.network_connect_button)
	else:
		_check(network.join_game("127.0.0.1", port) == OK, "client connects directly")
		await _load_game()
	var expected_health := 89 if game.map_name == "de_dust2" else 75
	_check(game._network_client_mode and game.player.network_read_only and game._all_bots().is_empty(),
		"client has no offline AI or authoritative local pawn")
	if not is_instance_valid(game.network_client_view):
		failures.append("client view did not initialize")
		return
	var kernel_tick: int = game.round_state.tick
	var kernel_trace: Array = game.round_state.trace.duplicate(true)
	if not await _wait_for(func() -> bool: return not game.network_client_view.snapshot.is_empty(), "client receives complete host actor list"):
		return
	_check(game.network_client_view.actors.size() == 10 and not game.player.alive,
		"pending client sees host plus nine bots without an extra local participant")
	_check(game.sprays.records.size() == 1 and game.sprays._nodes.size() == 1, "late-joining client receives existing spray exactly once")
	_check(not game._pause_menu_open() and game.hud.current_input_contract().state == "team",
		"first authoritative world dismisses connection form and restores team selection")
	# Use the shipped team/class menu's keyboard route, not direct host methods.
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	game._unhandled_input(key)
	if not await _wait_for(func() -> bool: return game.hud.current_input_contract().state == "class", "host team reply opens existing class menu"):
		return
	key.keycode = KEY_4
	game._unhandled_input(key)
	if not await _wait_for(func() -> bool: return game.player.alive and not game.hud.deploy_overlay.visible, "host class reply and snapshot activate owned camera"):
		return
	_check(root.get_camera_3d() == game.player.camera and game.selected_player_skin == "guerilla"
		and game.network_client_view.actors.size() == 9 and game.network_client_view.actors.has("player"),
		"owner keeps first-person view; host and remaining actors are remote models")
	_check(game.player.owns_weapon("knife") and game.player.owns_weapon("glock18") and not game.player.owns_weapon("ak47"),
		"owner receives host starting inventory without an offline rifle")
	if not await _wait_for(func() -> bool: return game.player.display_name == "Client Before", "initial saved name survives class admission"):
		return
	var owner_id: String = game.network_client_view.snapshot.owner_id
	game._set_paused(true)
	game.hud._show_pause_options()
	var entry := game.hud.options_pages.get_node("Page_multiplayer/Source_NameEntry") as LineEdit
	entry.text = "Client Renamed"
	entry.text_changed.emit(entry.text)
	_click_menu_button(game.hud.pause_options_menu.get_node("OptionsContent/OptionsOK"))
	game._set_paused(false)
	if not await _wait_for(func() -> bool:
		var rows: Array = game.network_client_view.snapshot.actors
		return rows.any(func(row: Dictionary) -> bool: return row.id == owner_id and row.name == "Client Renamed") and rows.any(func(row: Dictionary) -> bool: return row.id == "player" and row.name == "Host Renamed"),
		"both saved names propagate through authoritative world snapshots"):
		return
	game.network_client_view.update_scoreboard()
	await process_frame
	await process_frame
	var name_row: Node = game.hud.scoreboard_rows.get_node("Player_" + owner_id)
	_check(name_row.get_meta("is_local") and (name_row.get_child(0).get_child(1) as Label).text == "Client Renamed", "remote scoreboard rename keeps owner highlight")
	var before_spray: int = network._action_sequence
	key.keycode = KEY_T
	game._unhandled_input(key)
	_check(network._action_sequence == before_spray + 1, "client T sends one reliable spray request")
	if not await _wait_for(func() -> bool: return network.latest_action_result.get("sequence", 0) == before_spray + 1, "host answers real spray key request"):
		return
	_check(network.latest_action_result.action == "spray", "spray request uses the ordinary host action channel")
	var reserve: int = game.player.reserve
	if game.map_name == "de_dust2":
		if not await _client_buy_scenario():
			return
		key.keycode = KEY_ESCAPE
		game._unhandled_input(key)
		var before_tick: int = game.network_client_view.snapshot.tick
		Input.action_press("fire")
		Input.action_press("move_forward")
		if not await _wait_for(func() -> bool: return int(game.network_client_view.snapshot.tick) >= before_tick + 15, "host snapshots continue behind client's local pause menu"):
			return
		Input.action_release("fire")
		Input.action_release("move_forward")
		_check(not paused and game._pause_menu_open() and game.player.clip == 20
			and game.player.last_command.is_empty(), "client menu sends neutral input without pausing replication")
		game._unhandled_input(key)
		_check(not game._pause_menu_open(), "client Escape closes online menu")
	# Traverse actual Player input latches and the normal client tick, not a direct RPC.
	_weapon_key(KEY_3)
	if not await _wait_for(func() -> bool: return game.player.active_weapon == "knife", "slot three selects the host knife"):
		return
	_check(game.player.clip == -1 and game.player.previous_weapon == "glock18", "knife ammo and lastinv mirror host state")
	_weapon_key(KEY_Q)
	if not await _wait_for(func() -> bool: return game.player.active_weapon == "glock18", "lastinv returns to the host pistol"):
		return
	_check(game.player.clip == 20 and game.player.reserve == reserve and game.player.previous_weapon == "knife",
		"switching preserves host pistol ammunition and previous weapon")
	var rejected: int = network.request_weapon("ak47")
	if not await _wait_for(func() -> bool: return int(network.latest_action_result.get("sequence", 0)) == rejected,
		"host replies to unowned weapon request"):
		return
	_check(not network.latest_action_result.accepted and network.latest_action_result.reason == "weapon_not_owned"
		and game.player.active_weapon == "glock18", "remote request cannot conjure an unowned rifle")
	if game.map_name == "de_dust2":
		await create_timer(game.player.WeaponClockScript.DEFAULT_DEPLOY_SECONDS + 0.1).timeout
		_check(_mode_cue_count() == 0, "joining and equipping a pistol produces no false mode confirmation")
		_right_click()
		if not await _wait_for(func() -> bool: return bool(game.player.weapon_modes.get("glock18", false)), "right click selects host burst mode"):
			return
		_check(game.hud._fire_mode == "BURST FIRE" and game.player.clip == 20 and game.player._shot_sequence == 0,
			"host burst mode reaches HUD without firing a local shot")
		_check(_mode_cue_count() == 1, "host-confirmed burst change plays one local cue")
		await create_timer(0.4).timeout
		_check(_mode_cue_count() == 1, "unchanged snapshots do not repeat mode confirmation")
		_check(game.audio_router.active_voices().is_empty(), "client presentation clock expires the mode cue")
		_right_click()
		if not await _wait_for(func() -> bool: return not bool(game.player.weapon_modes.get("glock18", true)), "right click returns host to semi-auto"):
			return
		_check(_mode_cue_count() == 2, "host-confirmed semi-auto change plays exactly one more cue")
	var origin: Vector3 = game.player.global_position
	var view: Node = game.network_client_view
	view.combat_presented.connect(func(event: Dictionary) -> void:
		if event.kind == "shot" and event.actor == view.owner_id:
			_check(game.player._punch_degrees.is_zero_approx() and is_equal_approx(game.player.camera.rotation.x, game.player._pitch),
				"host-confirmed Glock retains source zero camera punch while its viewmodel fires")
		if event.kind == "reload" and event.actor == "player":
			_check(view.actors.player.model._action_state == "reload", "remote model requests the source reload action")
		if event.kind == "kill":
			_check(event.data.headshot, "host headshot flag reaches kill presentation")
	)
	var world_tick: int = view.snapshot.tick
	# Hold presentation snapshots for twelve real physics ticks. ENet and the host
	# keep running; this verifies the actual client's movement does not wait for
	# a snapshot. This staged delivery gap is not a packet-loss/latency soak.
	network.world_snapshot_received.disconnect(view.apply_snapshot)
	Input.action_press("move_forward")
	# The signal precedes Game's tick; this gives eleven executed movement steps,
	# enough for normal 5.0 ground acceleration to cover 5cm from rest.
	for ignored_tick in range(12):
		await physics_frame
	print("NETWORK_PREDICTED_MOVEMENT ", {"tick_before": world_tick, "tick_after": view.snapshot.tick,
		"origin": origin, "position": game.player.global_position, "velocity": game.player.velocity,
		"distance": game.player.global_position.distance_to(origin), "pending": view.movement_prediction.pending.size(),
		"motion": view.snapshot.motion, "command": game.player.last_command,
		"snapshot_age_ms": Time.get_ticks_msec() - view._received_ms})
	_check(view.snapshot.tick == world_tick and game.player.global_position.distance_to(origin) > 0.05,
		"owner moves locally while host presentation snapshots are withheld")
	_check(not view.movement_prediction.pending.is_empty() and game.player.clip == 20 and game.player._shot_sequence == 0,
		"real client queues unacknowledged movement without simulating combat")
	network.world_snapshot_received.connect(view.apply_snapshot)
	view.apply_snapshot(network.latest_world_snapshot)
	if not await _wait_for(func() -> bool: return game.player.global_position.distance_to(origin) > 0.05, "host movement snapshots move the owned client body"):
		Input.action_release("move_forward")
		return
	Input.action_release("move_forward")
	# A semi-auto press during deploy is intentionally ignored by the existing
	# weapon clock. Wait its real deploy duration before issuing the single shot.
	await create_timer(game.player.WeaponClockScript.DEFAULT_DEPLOY_SECONDS + 0.1).timeout
	Input.action_press("crouch")
	var crouch_shot := InputEventMouseButton.new()
	crouch_shot.button_index = MOUSE_BUTTON_RIGHT if OS.get_name() == "macOS" else MOUSE_BUTTON_LEFT
	crouch_shot.button_mask = MOUSE_BUTTON_MASK_LEFT
	crouch_shot.ctrl_pressed = true
	crouch_shot.pressed = true
	game.player._input(crouch_shot)
	if not await _wait_for(func() -> bool: return game.player.clip == 19, "crouched primary reaches host and decrements client ammunition"):
		Input.action_release("crouch")
		return
	crouch_shot = crouch_shot.duplicate()
	crouch_shot.pressed = false
	crouch_shot.button_mask = 0
	crouch_shot.ctrl_pressed = false
	game.player._input(crouch_shot)
	Input.action_release("crouch")
	if not await _wait_for(func() -> bool: return int(view.presented_combat_counts.get("shot", 0)) == 1, "owned shot reaches presentation event stream"):
		return
	_check(game.player._shot_sequence == 0 and game.player.weapon_clock.tick == 0,
		"presentation shot cannot run local bullets or advance weapon simulation")
	var glock_sounds: Array = game.audio_router.trace().filter(func(event: Dictionary) -> bool:
		return event.kind == "start" and event.event_name == "glock18.fire")
	_check(glock_sounds.size() == 1 and glock_sounds[0].sample == "weapons/glock18-2.wav", "owner hears exact host-selected single shot once")
	await create_timer(0.2).timeout # Let the shot's existing primary cooldown finish.
	_weapon_key(KEY_R)
	if not await _wait_for(func() -> bool: return int(view.presented_combat_counts.get("reload", 0)) == 1, "owner reload input triggers host-confirmed animation"):
		Input.action_release("reload")
		return
	Input.action_release("reload")
	# Reliable presentation and owner snapshots can arrive on different frames.
	# Observing the event alone does not guarantee the reloading flag is here yet.
	if not await _wait_for(func() -> bool: return game.player.reloading and game.player.viewmodel._animation_name.contains("reload"),
		"owner viewmodel actually enters reload"):
		return
	# Cancel through the existing weapon-selection path; preserve the magazine
	# that the later survivor/drop assertions intentionally track.
	_weapon_key(KEY_3)
	if not await _wait_for(func() -> bool: return game.player.active_weapon == "knife", "switch cancels owner reload"):
		return
	_weapon_key(KEY_Q)
	if not await _wait_for(func() -> bool: return game.player.active_weapon == "glock18", "return to pistol after cancelled reload"):
		return
	Input.action_press("walk")
	if not await _wait_for(func() -> bool: return int(view.presented_combat_counts.get("reload", 0)) == 2 and int(view.presented_combat_counts.get("shot", 0)) == 2 \
		and view.actors.player.model.animation_state == "reload", "remote host shot and reload animate on client"):
		return
	if not await _wait_for(func() -> bool: return game.player.health == expected_health and game.phase == "post" and game.terrorist_score == 1,
		"server damage and round result reach client HUD state"):
		return
	Input.action_release("walk")
	_check(int(view.presented_combat_counts.get("impact", 0)) >= 1, "host world impacts reach client effects")
	print("NETWORK_COMBAT_POST ", {"counts": view.presented_combat_counts, "pending": view._pending_combat,
		"round": view.snapshot.round, "epoch": view._epoch, "tick": view.snapshot.tick, "last_event": network._last_combat_sequence})
	_check(int(view.presented_combat_counts.get("blood", 0)) >= 1 and int(view.presented_combat_counts.get("blood_decal", 0)) >= 1,
		"host blood effects reach client without client damage simulation")
	if not await _wait_for(func() -> bool: return int(view.presented_combat_counts.get("kill", 0)) >= 5, "host kill notices reach client HUD"):
		return
	_check(game.hud.kill_feed_box.get_child_count() > 0, "replicated deaths populate visible kill feed")
	var reload_sounds: Array = game.audio_router.trace().filter(func(event: Dictionary) -> bool:
		return event.kind == "start" and event.event_name == "ak47.clip_out")
	_check(reload_sounds.size() == 1, "remote reload sound plays once")
	_check(game.player._shot_sequence == 0 and int(game.hud.health_label.text) == expected_health,
		"client did not fire a duplicate local bullet and HUD displays host health")
	_check(not game.network_client_view.items.is_empty(), "host death drops appear as client world models")
	var item_instances := {}
	for item_id: int in game.network_client_view.items:
		var record: Dictionary = game.network_client_view.items[item_id]
		item_instances[item_id] = record.body.get_instance_id()
		_check(_visual_only(record.body) and _mesh_count(record.body) > 0, "world item has original mesh but no client physics/pickup nodes")
	var item_tick: int = game.network_client_view.snapshot.tick
	if not await _wait_for(func() -> bool: return int(game.network_client_view.snapshot.tick) > item_tick, "another world-item update"):
		return
	for item_id: int in item_instances:
		_check(game.network_client_view.items.has(item_id) and game.network_client_view.items[item_id].body.get_instance_id() == item_instances[item_id],
			"stable world ID reuses existing model across snapshots")
	for record: Dictionary in game.network_client_view.actors.values():
		_check(record.body.network_read_only and record.body.collision_layer == 0 and record.model.model_loaded,
			"replica uses existing model without a client damage collider")
		if record.body.team == "CT":
			_check(not record.body.alive and record.model.animation_state == "die", "host CT death displays a corpse")
	var ammo: int = game.player.clip
	game.player.receive_damage(10000)
	game.player.receive_bullet_damage(10000, 1, "ak47")
	game.player.receive_explosion_damage(10000)
	game.player.receive_c4_explosion_damage(10000)
	game.player._try_fire()
	game.player._try_secondary()
	game.player._try_drop_active_weapon()
	game.player.switch_weapon("knife")
	game.player._physics_process(0.01)
	game.start_match()
	game._restart_match()
	_check(game.player.health == expected_health and game.player.clip == ammo and not bool(game.player.weapon_modes.get("glock18", false))
		and game.player.active_weapon == "glock18" and game.round_state.tick == kernel_tick
		and game.round_state.trace == kernel_trace, "client cannot author damage, ammunition or round/reward simulation")
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				await _draw_capture_frame()
				var path := argument.trim_prefix("--capture=")
				_check(root.get_texture().get_image().save_png(path) == OK, "native client capture saves")
				print("NETWORK_CLIENT_CAPTURE ", path)
				var nearest: Combatant
				var distance := INF
				for record: Dictionary in game.network_client_view.actors.values():
					var body: Combatant = record.body
					var candidate := body.global_position.distance_to(game.player.global_position)
					if body.alive and body.visible and candidate < distance:
						nearest = body
						distance = candidate
				if is_instance_valid(nearest):
					game.player.face_toward(nearest.global_position)
					await _draw_capture_frame()
					var actor_path := path.replace(".png", "-actors.png")
					_check(root.get_texture().get_image().save_png(actor_path) == OK, "native replica capture saves")
					print("NETWORK_CLIENT_ACTOR_CAPTURE ", actor_path)
	Input.action_press("use")
	if not await _wait_for(func() -> bool: return game.round_number == 2 and game.phase == "live", "normal host round reset reaches client"):
		return
	Input.action_release("use")
	_check(game.network_client_view.items.is_empty(), "round reset removes prior death-drop models")
	if not await _wait_for(func() -> bool: return game.player.owns_weapon("ak47") and bool(game.player.equipment.kevlar),
		"host-granted inventory/equipment reaches owner"):
		return
	for selection: Array in [[KEY_1, "ak47"], [KEY_4, "hegrenade"], [KEY_4, "flashbang"], [KEY_4, "smokegrenade"],
		[KEY_Q, "flashbang"], [KEY_2, "glock18"]]:
		_weapon_key(selection[0])
		if not await _wait_for(func() -> bool: return game.player.active_weapon == selection[1], "host selection: " + str(selection[1])):
			return
		if selection[1] == "ak47":
			_check(game.player.clip == 7 and game.player.reserve == 29, "primary slot reads host-granted rifle ammunition")
	if game.map_name == "de_dust2":
		_check(game.player.owns_weapon("c4"), "host C4 ownership reaches inventory")
		_weapon_key(KEY_5)
		if not await _wait_for(func() -> bool: return game.player.active_weapon == "c4", "slot five selects host-owned C4"):
			return
		_weapon_key(KEY_G)
		# A backpack tossed against nearby spawn geometry may be picked up again
		# before the next 20 Hz snapshot. Check the reply/switch; host trace and
		# world-spawn assertions establish the drop without forbidding valid pickup.
		if not await _wait_for(func() -> bool: return (network.latest_action_result.get("action", "") == "drop_weapon"
			and bool(network.latest_action_result.get("accepted", false)) and game.player.active_weapon == "ak47"), "G drops owned C4 on host and selects primary"):
			return
		_weapon_key(KEY_2)
		if not await _wait_for(func() -> bool: return game.player.active_weapon == "glock18", "pistol selection after C4 drop"):
			return
	_check(game.player.ammunition.ak47 == {"clip": 7, "reserve": 29} and game.player.clip == 19,
		"client receives preserved inactive and active ammunition across selections")
	if game.map_name == "de_dust2":
		_weapon_key(KEY_1)
		if not await _wait_for(func() -> bool: return game.player.active_weapon == "ak47", "select rifle to drop"):
			return
		_weapon_key(KEY_G)
		if not await _wait_for(func() -> bool: return not game.player.owns_weapon("ak47") and game.player.active_weapon == "glock18", "G drops host rifle and updates client inventory"):
			return
		_check(game.network_client_view.items.values().any(func(record: Dictionary) -> bool: return record.weapon == "ak47"),
			"manual gun drop appears in shared client world")
		for item: Dictionary in game.network_client_view.items.values():
			if item.weapon == "ak47":
				var drop_origin: Vector3 = item.to
				var drop_id: int = item.body.get_instance_id()
				if not await _wait_for(func() -> bool: return is_instance_valid(item.body) and (item.to as Vector3).distance_to(drop_origin) > 0.02,
					"dropped gun visibly travels through host snapshots"):
					return
				_check(item.body.get_instance_id() == drop_id and _visual_only(item.body), "gun toss reuses a visual-only client replica")
				await _capture_item(item, "dropped-gun")
		if not await _wait_for(func() -> bool: return game.player.owns_weapon("awp"), "host grants follow-up sniper fixture"):
			return
		_weapon_key(KEY_1)
		if not await _wait_for(func() -> bool: return game.player.active_weapon == "awp", "select host sniper"):
			return
		_check(not game.player.weapon_is_zoomed() and is_equal_approx(game.player.camera.fov, game.player.settings.field_of_view),
			"unzoomed client retains display FOV without claiming scoped state")
		await create_timer(game.player.WeaponClockScript.DEFAULT_DEPLOY_SECONDS + 0.1).timeout
		_right_click()
		if not await _wait_for(func() -> bool: return game.player.weapon_is_zoomed() and game.player.camera.fov == 40.0, "host zoom state drives client camera"):
			return
		_weapon_key(KEY_2)
		if not await _wait_for(func() -> bool: return game.player.active_weapon == "glock18", "leave scope for pistol"):
			return
		_check(is_equal_approx(game.player.camera.fov, game.player.settings.field_of_view), "leaving zoom restores client display FOV")
	for record: Dictionary in game.network_client_view.actors.values():
		if record.body.team == "CT":
			_check(record.body.alive and record.model.animation_state != "die", "new round revives client corpse presentation")
	Input.action_press("walk")
	if game.map_name == "de_dust2" and not await _client_item_scenario():
		return
	if game.map_name == "de_dust2" and not await _client_grenade_scenario():
		return
	if not await _wait_for(func() -> bool: return not network.is_online(), "host disconnect reaches client"):
		return
	Input.action_release("walk")
	Input.action_release("use")
	_check(game.network_client_view.actors.is_empty() and game.network_client_view.items.is_empty() and not game.player.alive and game._network_client_mode
		and game.round_state.tick == kernel_tick, "disconnect clears replicas without starting an offline match")


func _host_item_scenario(human: PlayerController, peer: int) -> bool:
	# Place a normal host toss above spawn so this presentation fixture observes
	# flight before a ground touch/pickup. Travel to the bombsite is staged below;
	# the client still selects C4 and holds fire for the normal plant duration.
	var origin := human.global_position + Vector3.UP * 4.0
	if game.round_state.bomb_state == game.round_state.BOMB_CARRIED:
		_check(game.round_state.drop_bomb(game.round_state.bomb_owner, origin), "stage observable airborne C4")
		game._consume_new_round_trace()
	else:
		game._spawn_dropped_c4(origin, human)
	game._sync_player_c4_ownership()
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 16, "client saw host backpack flight"):
		return false
	_check(game.round_state.pickup_bomb(game._round_id_for_actor(human), human.global_position), "fixture returns dropped C4 to planter")
	game._consume_new_round_trace()
	game._sync_player_c4_ownership()
	human.global_position = game.bomb_sites[0]
	human.velocity = Vector3.ZERO
	human._movement_grounded = false
	if not await _wait_for(func() -> bool: return game.round_state.bomb_state == game.round_state.BOMB_PLANTED, "remote held fire completes real host plant"):
		return false
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 32, "client saw planted C4 and countdown"):
		return false
	game._reset_round()
	_check(game.sprays.records.is_empty(), "round restart clears authoritative sprays")
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 16, "client saw round-three item cleanup"):
		return false
	return true


func _client_item_scenario() -> bool:
	if not await _wait_for(func() -> bool: return not _item_of_kind("dropped_c4").is_empty(), "client sees airborne backpack model"):
		return false
	Input.action_release("walk")
	var backpack := _item_of_kind("dropped_c4")
	var node_id: int = backpack.body.get_instance_id()
	var position: Vector3 = backpack.to
	_check(_visual_only(backpack.body) and _mesh_count(backpack.body) > 0, "backpack replica is visual-only original model")
	if not await _wait_for(func() -> bool: return is_instance_valid(backpack.body) and (backpack.to as Vector3).distance_to(position) > 0.005,
		"host flight updates backpack transform"):
		return false
	_check(backpack.body.get_instance_id() == node_id, "flight reuses stable backpack identity")
	Input.action_press("use")
	if not await _wait_for(func() -> bool: return game.player.owns_weapon("c4") and _item_of_kind("dropped_c4").is_empty(), "pickup removes backpack and grants owner inventory"):
		return false
	Input.action_release("use")
	_weapon_key(KEY_5)
	if not await _wait_for(func() -> bool: return game.player.active_weapon == "c4", "client equips C4 at staged bombsite"):
		return false
	await create_timer(game.player.WeaponClockScript.DEFAULT_DEPLOY_SECONDS + 0.2).timeout
	Input.action_press("fire")
	if not await _wait_for(func() -> bool: return game.network_client_view.snapshot.feedback.action == "plant", "owner sees authoritative planting progress"):
		Input.action_release("fire")
		return false
	_check(game.hud.status_label.text.begins_with("PLANTING") and game.player.viewmodel._animation_name == "pressbutton",
		"plant progress and C4 button animation reach owner HUD/viewmodel")
	if not await _wait_for(func() -> bool: return game.phase == "bomb" and not _item_of_kind("planted_c4").is_empty(), "real host plant appears as planted model"):
		Input.action_release("fire")
		return false
	Input.action_release("fire")
	var planted := _item_of_kind("planted_c4")
	_check(game.network_client_view.snapshot.feedback.result == "bomb_planted" and game.hud.banner_label.text == "THE BOMB HAS BEEN PLANTED",
		"planted result reaches owner banner")
	if not await _wait_for(func() -> bool: return game.audio_router.trace().any(func(event: Dictionary) -> bool:
		return event.kind == "start" and str(event.event_name).begins_with("c4.beep")), "host bomb beep reaches client audio router"):
		return false
	_check(not game.player.owns_weapon("c4") and _visual_only(planted.body) and _mesh_count(planted.body) == 1
		and planted.visual.seconds_remaining > 0.0 and planted.visual.seconds_remaining <= planted.visual.total_seconds,
		"planted replica gets authoritative countdown with no bomb/use collider or client inventory")
	await _capture_item(planted, "planted-c4")
	Input.action_press("walk")
	if not await _wait_for(func() -> bool: return game.round_number == 3 and game.network_client_view.items.is_empty(), "reset removes planted bomb and all gun replicas"):
		return false
	Input.action_release("walk")
	Input.action_press("use")
	return true


func _host_grenade_scenario(human: PlayerController, peer: int) -> bool:
	_check(game.breakable_runtime.trigger(int(game.breakable_runtime._breakables.keys()[0]), 0), "host activates an authored Dust2 breakable")
	for kind: String in ["hegrenade", "flashbang", "smokegrenade"]:
		var grenade := HEGrenade.new()
		game.add_child(grenade)
		var offset := Vector3(30, 4, 0) if kind == "hegrenade" else Vector3(0.5, 1, -0.5)
		grenade.launch(human.global_position + offset, Vector3.RIGHT if kind == "hegrenade" else Vector3.ZERO, human, kind)
		grenade.freeze = kind != "hegrenade" # Stage close flash/smoke; retain normal fuse and effects.
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 32, "client saw grenade flight replicas"):
		return false
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 16, "client verified smoke reconstruction and flash"):
		return false
	game._reset_round()
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	if not await _wait_for(func() -> bool: return int(network.input_for_peer(peer).get("buttons", 0)) == 32, "client verified grenade and flash reset"):
		return false
	return true


func _client_grenade_scenario() -> bool:
	var view: Node = game.network_client_view
	if not await _wait_for(func() -> bool: return view.items.values().filter(func(item: Dictionary) -> bool: return item.kind == "grenade").size() == 3, "all three grenade types appear in flight"):
		return false
	Input.action_release("use")
	var flying: Dictionary = {}
	for record: Dictionary in view.items.values():
		_check(_visual_only(record.body), "grenade replica has no physics or damage authority")
		if record.weapon == "hegrenade":
			flying = record
	var origin: Vector3 = flying.to
	if not await _wait_for(func() -> bool: return (flying.to as Vector3).distance_to(origin) > 0.005, "host grenade motion reaches client"):
		return false
	Input.action_press("walk")
	if not await _wait_for(func() -> bool: return not _item_of_kind("smoke").is_empty() and view.snapshot.feedback.flash_remaining > 0.0, "smoke cloud and host flash blindness arrive"):
		return false
	_check(game.hud.flash_blind_overlay.color.a > 0.0 and game.player.flash_blind_until_frame == -1,
		"owner displays host flash without running local blindness or grenade simulation")
	if not await _wait_for(func() -> bool: return int(view.presented_combat_counts.get("explosion", 0)) >= 2, "HE and flash detonation effects arrive"):
		return false
	if not await _wait_for(func() -> bool: return game.audio_router.trace().filter(func(event: Dictionary) -> bool:
		return event.kind == "start" and event.event_name in ["he.explode", "flash.explode", "smoke.explode"]).size() == 3, "all grenade detonation sounds reach client router"):
		return false
	var sources: Dictionary = {}
	for event: Dictionary in game.audio_router.trace():
		if event.kind == "start" and event.event_name in ["he.explode", "flash.explode", "smoke.explode"]:
			sources[event.entity_id] = true
	for cue: String in ["he.explode", "flash.explode", "smoke.explode"]:
		_check(game.audio_router.trace().filter(func(event: Dictionary) -> bool: return event.kind == "start" and event.event_name == cue).size() == 1,
			"client receives exactly one correct detonation family: " + cue)
	_check(sources.size() == 3, "simultaneous grenades from one thrower keep independent audio channels")
	var smoke := _item_of_kind("smoke")
	_check(not view.snapshot.broken_brushes.is_empty(), "host broken brush state reaches client snapshot")
	for model: int in view.snapshot.broken_brushes:
		_check(not game.imported_map.model_runtime_active(model)
			and game.imported_map.collision_body_for_model(model).collision_layer == 0, "client hides broken crate and removes prediction collision")
	_check(_visual_only(smoke.body) and smoke.visual._sprites.size() == 17, "smoke uses original visual cloud without grenade physics")
	if DisplayServer.get_name() != "headless":
		if not await _wait_for(func() -> bool: return game.hud.flash_blind_overlay.color.a == 0.0, "flash fades before rendered smoke inspection"):
			return false
	await _capture_item(smoke, "smoke")
	await create_timer(0.5).timeout
	var smoke_row: Dictionary = {}
	for row: Dictionary in view.snapshot.items:
		if row.kind == "smoke":
			smoke_row = row
	_check(not smoke_row.is_empty() and smoke_row.remaining < smoke_row.total, "host owns smoke lifetime")
	smoke.body.queue_free()
	view.items.erase(smoke_row.id)
	view._apply_items(view.snapshot.items) # Equivalent reconstruction path for a late join.
	smoke = _item_of_kind("smoke")
	_check(smoke.visual.tick >= 40 and smoke.visual._sprites.size() == 17,
		"snapshot reconstructs an already-active cloud at its existing age")
	Input.action_release("walk")
	Input.action_press("use")
	if not await _wait_for(func() -> bool: return game.round_number == 4 and _item_of_kind("smoke").is_empty(), "round reset removes smoke and grenade replicas"):
		return false
	_check(view.snapshot.feedback.flash_remaining == 0.0 and game.hud.flash_blind_overlay.color.a == 0.0, "round reset clears owner flash")
	_check(view.snapshot.broken_brushes.is_empty(), "round reset clears replicated broken brush list")
	for model: int in game.breakable_runtime.model_indices():
		_check(game.imported_map.model_runtime_active(model), "round reset restores client map crate")
	Input.action_release("use")
	Input.action_press("walk")
	return true


func _item_of_kind(kind: String) -> Dictionary:
	for record: Dictionary in game.network_client_view.items.values():
		if record.kind == kind:
			return record
	return {}


func _visual_only(node: Node) -> bool:
	if node is CollisionObject3D or node.is_physics_processing():
		return false
	for child: Node in node.get_children():
		if not _visual_only(child):
			return false
	return true


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _mesh_count(child)
	return count


func _capture_item(record: Dictionary, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			# Gameplay updates the player's aim every tick. Use a separate camera
			# so the capture actually looks at the replicated item across draws.
			var camera := Camera3D.new()
			game.add_child(camera)
			camera.global_transform = game.player.camera.global_transform
			camera.fov = game.player.camera.fov
			camera.near = 0.05
			var target: Vector3 = record.body.global_position + Vector3.UP * 0.05
			if label == "smoke":
				target += Vector3.UP * 0.5
				var desired := target + Vector3(4, 1.5, 4)
				var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(target, desired, 1))
				camera.global_position = desired if hit.is_empty() else (hit.position as Vector3).move_toward(target, 0.2)
			var direction := (target - camera.global_position).normalized()
			camera.look_at(target, Vector3.FORWARD if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP)
			camera.make_current()
			await _draw_capture_frame()
			var path := argument.trim_prefix("--capture=").replace(".png", "-" + label + ".png")
			_check(root.get_texture().get_image().save_png(path) == OK, "native world item capture saves")
			game.player.camera.make_current()
			camera.queue_free()
			print("NETWORK_WORLD_ITEM_CAPTURE ", path)


func _draw_capture_frame() -> void:
	# Explicit capture draw, as in the existing debris render fixture. Avoid
	# an unbounded wait for a post-draw signal when a native window is idle.
	# This is functional image QA, never a frame-timing sample.
	await process_frame
	await process_frame
	RenderingServer.force_draw()


func _client_buy_scenario() -> bool:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("NETWORK_CAPTURE_CONTROL ", {"display": DisplayServer.get_name(), "requested": Input.MOUSE_MODE_CAPTURED, "actual": Input.mouse_mode})
	_check(game.network_client_view.can_buy(), "host publishes current Dust2 buy eligibility")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_B
	game._unhandled_input(key)
	_check(game.hud.buy_overlay.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "B opens existing menu with clickable cursor")
	key.keycode = KEY_8
	game.player._input(key)
	game._unhandled_input(key)
	_check(game.hud._buy_items[0].item_id == "vest", "existing equipment page offers kevlar first")
	key.keycode = KEY_1
	game.player._input(key)
	game._unhandled_input(key)
	if not await _wait_for(func() -> bool: return game.player.equipment.kevlar and game.money == 150, "menu purchase reaches host then owner snapshot"):
		return false
	_check(game.hud._buy_money == 150 and game.hud.money_label.text == "$150"
		and game.hud.current_input_contract().state == "none" and not game.hud.buy_overlay.visible, "accepted purchase updates wallet and closes menu")
	_check(game.player.active_weapon == "glock18" and game.player.clip == 20
		and not game.player.combat_controller.menu_input_blocked, "equipment purchase preserves gun and returns gameplay input")
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				await _draw_capture_frame()
				var path := argument.trim_prefix("--capture=").replace(".png", "-buy-menu.png")
				_check(root.get_texture().get_image().save_png(path) == OK, "save client authoritative buy-menu capture")
	var sequence: int = network._action_sequence
	game.hud.show_buy_menu(game._hud_team_id(), game.money, game._buy_menu_context())
	game.hud._show_buy_category("equipment")
	game._unhandled_input(key)
	_check(network._action_sequence == sequence, "unaffordable menu row is disabled after host balance update")
	var denied: int = network.request_buy("ak47")
	if not await _wait_for(func() -> bool: return network.latest_action_result.get("sequence", 0) == denied, "host rejects unaffordable direct purchase"):
		return false
	_check(network.latest_action_result.reason == "insufficient_funds" and not game.player.owns_weapon("ak47"), "client cannot bypass wallet with direct reliable action")
	key.keycode = KEY_ESCAPE
	game._unhandled_input(key)
	game._unhandled_input(key)
	print("NETWORK_BUY_MENU_CLOSED ", {"visible": game.hud.buy_overlay.visible, "blocked": game.player.combat_controller.menu_input_blocked,
		"cursor": Input.mouse_mode, "state": game.hud.current_input_contract(), "alive": game.player.alive, "started": game.match_started, "paused": paused})
	_check(not game.hud.buy_overlay.visible and not game.player.combat_controller.menu_input_blocked
		and not game.hud.current_input_contract().mouse_visible, "Escape returns to gameplay input and non-modal mouse contract")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "native buy-menu close captures OS cursor")
	return true


func _weapon_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)


func _click_menu_button(button: Button) -> void:
	_check(button.is_visible_in_tree() and not button.disabled, "menu control is usable: " + str(button.name))
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		root.push_input(event, true)


func _right_click() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		root.push_input(event, true)
