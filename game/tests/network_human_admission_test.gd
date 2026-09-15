extends SceneTree

## Production host admission/lifecycle on a real map. Team/class transport and
## independently rendered client worlds are not implemented by this fixture.
const GameScript = preload("res://scripts/game.gd")
const RoundScript = preload("res://scripts/cs16_round_state.gd")
var failures: Array[String] = []
var game: Node
var network: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _connect_peer(peer_id: int) -> PlayerController:
	network._register_input_peer(peer_id, Time.get_ticks_msec())
	game.remote_roster._on_peer_joined(peer_id)
	return game.remote_roster.actor_for_peer(peer_id)


func _pause_actors() -> void:
	game.player.set_physics_process(false)
	for human: PlayerController in game._human_players_stable():
		human.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "admission fixture must be silent")
	game = GameScript.new()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	_pause_actors()
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	var first := _connect_peer(99)
	var first_id: String = game._round_id_for_actor(first)
	_check(game.select_remote_weapon(777, "knife").reason == "unknown_peer"
		and game.select_remote_weapon(99, "knife").reason == "action_unavailable", "unknown/pending humans cannot switch weapons")
	var old_bots := {}
	for bot: TargetActor in game._all_bots():
		old_bots[str(bot.name)] = {"position": bot.global_position, "brush_id": game._brush_activator_id(bot)}
	_check(not game.select_remote_join_team(777, "T").accepted
		and not game.select_remote_join_team(99, "INVALID").accepted
		and not game.select_remote_join_class(99, 1).accepted
		and game._all_bots().size() == 9, "invalid/unowned requests cannot change roster")
	var selected: Dictionary = game.select_remote_join_team(99, "T")
	_check(selected.accepted and game._all_bots().size() == 8 and game.round_state.team_counts() == {"T": 5, "CT": 5},
		"accepted initial team selection replaces one bot and retains 5v5")
	_check(not first.alive and not first.visible and first.collision_layer == 0 and not first.is_physics_processing()
		and game.round_state.players[first_id].choosing_appearance and game.round_state.players[first_id].money == 800,
		"team selection reserves one slot/account without bypassing class choice")
	_check(not game.select_remote_join_team(99, "T").accepted and not game.select_remote_join_class(99, 9).accepted
		and game._all_bots().size() == 8, "duplicates/invalid classes do not remove another bot")
	for bot: TargetActor in game._all_bots():
		_check(bot.global_position == old_bots[str(bot.name)].position
			and game._brush_activator_id(bot) == old_bots[str(bot.name)].brush_id,
			"remaining bot position and brush identity stay unchanged: " + str(bot.name))
	_check(game._actor_for_round_id(str(selected.replaced_bot)) == null
		and not game.round_state.players.has(str(selected.replaced_bot))
		and game.round_state.trace.filter(func(event: Dictionary) -> bool:
			return event.type == "player_death" and event.player_id == selected.replaced_bot).is_empty(),
		"replaced bot leaves identity/account state without a synthetic kill")
	var class_result: Dictionary = game.select_remote_join_class(99, 4)
	_check(class_result.accepted and class_result.spawned and first.alive and first.visible
		and first.is_physics_processing() and first.controls_enabled and first.collision_layer == 2
		and first.character_model.skin_name == "guerilla" and first.active_weapon == "glock18" and first.armor == 0,
		"early class selection really spawns a source-loadout human with selected world skin")
	_check(game.player.collision_layer == (2 | 4) and root.get_camera_3d() == game.player.camera,
		"host participates in human hit masks without losing local view")
	var host_weapon: String = game.player.active_weapon
	var initial_clip := first.clip
	var initial_reserve := first.reserve
	first.clip = 7
	first.reserve = 22
	_check(game.select_remote_weapon(99, "ak47").reason == "weapon_not_owned" and first.active_weapon == "glock18",
		"valid weapon identifier cannot grant an unowned gun")
	first.controls_enabled = false
	first.look_enabled = true
	first.reloading = true
	_check(game.select_remote_weapon(99, "knife").accepted and first.active_weapon == "knife"
		and not first.reloading and first.ammunition.glock18 == {"clip": 7, "reserve": 22},
		"freeze-style input permits selection, cancels reload and stores exact ammo")
	var deploy_deadline: int = first.weapon_clock.next_primary_tick
	_check(game.select_remote_weapon(99, "knife").accepted and first.weapon_clock.next_primary_tick == deploy_deadline,
		"selecting already-held weapon does not restart deploy")
	_check(game.select_remote_weapon(99, "glock18").accepted and first.clip == 7 and first.reserve == 22
		and first.previous_weapon == "knife" and game.player.active_weapon == host_weapon,
		"switch back restores ammo and lastinv without mutating host pawn")
	first.controls_enabled = true
	first.clip = initial_clip
	first.reserve = initial_reserve
	var query := PhysicsRayQueryParameters3D.create(game.player.global_position + Vector3.UP * 1.2,
		game.player.global_position + Vector3.UP * 0.2, 2)
	_check(game.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == game.player,
		"actual physics ray using the human bullet mask can hit host body")
	var old_serial := first.spawn_serial
	first.health = 80
	first.clip = 3
	_check(not game.select_remote_join_class(99, 4).accepted and first.health == 80 and first.clip == 3
		and first.spawn_serial == old_serial, "duplicate class cannot heal/rearm/respawn")
	var host_position: Vector3 = game.player.global_position
	var origin := first.global_position
	var input_packet: Dictionary = network.sanitize_input({"movement": Vector2(0, -1), "buttons": 0,
		"yaw": first._yaw, "pitch": 0.0}, 1)
	_check(network.accept_peer_input(99, input_packet, Time.get_ticks_msec()), "admitted peer's normal input accepted")
	for tick in range(20):
		first._physics_process(0.01)
	_check(first.global_position.distance_to(origin) > 0.02 and game.player.global_position == host_position,
		"admitted human consumes validated movement in actual map without moving host")
	_pause_actors()
	# Late entry waits, while existing survivor equipment survives the same reset.
	var second := _connect_peer(100)
	var second_id: String = game._round_id_for_actor(second)
	game.round_state.tick = game.round_state.round_started_tick + int(game.round_state.config.freeze_ticks) + int(game.round_state.config.join_spawn_ticks) + 1
	_check(game.select_remote_join_team(100, "CT").accepted, "late peer can join team")
	var late: Dictionary = game.select_remote_join_class(100, 2)
	_check(late.accepted and not late.spawned and not second.alive and not second.is_physics_processing(),
		"past normal join window class completion waits for next round")
	first.grant_item("ak47")
	first.switch_weapon("ak47")
	first.clip = 7
	first.reserve = 29
	first.armor = 45
	game._reset_round()
	_check(first.alive and first.active_weapon == "ak47" and first.clip == 7 and first.reserve == 29 and first.armor == 45,
		"normal reset preserves survivor's actual weapon/ammo/armor")
	_check(second.alive and second.active_weapon == "usp" and second.character_model.skin_name == "gsg9"
		and not second.controls_enabled and second.look_enabled and second.is_physics_processing(),
		"late entrant spawns at next freeze with normal pistol and class")
	_check(first.global_position.distance_to(second.global_position) > 0.3, "opposing spawn reservations are distinct")
	_pause_actors()
	game._begin_live()
	first.receive_damage(100000, first.global_position, false, second)
	_check(not first.alive and not game.round_state.players[first_id].alive, "admitted human death reaches round state")
	_check(game.select_remote_weapon(99, "knife").reason == "action_unavailable", "dead remote human cannot switch weapons")
	game._reset_round()
	_check(first.alive and first.active_weapon == "glock18" and first.armor == 0
		and first.character_model.animation_state != "die", "dead entrant respawns with fresh equipment and live model")
	_pause_actors()
	# Incomplete appearance must survive halftime and a complete rematch.
	var third := _connect_peer(101)
	_check(game.select_remote_join_team(101, "CT").accepted, "third peer reserves appearance slot")
	game.round_state.round_number = 15
	game.round_state.rounds_played = 15
	game.round_state._apply_halftime_if_needed()
	game._consume_new_round_trace()
	game._reset_round()
	_check(first.team == "CT" and first.active_weapon == "usp" and first.character_model.skin_name == "gign"
		and second.team == "T" and second.active_weapon == "glock18" and second.character_model.skin_name == "leet",
		"halftime flips admitted identities, class families, spawns and pistol economy")
	_check(third.team == "T" and not third.alive and not third.is_physics_processing(), "halftime cannot bypass incomplete appearance")
	_check(game.select_remote_join_class(101, 3).spawned and third.character_model.skin_name == "arctic",
		"pending class finishes on the authoritative post-halftime side")
	_pause_actors()
	var fourth := _connect_peer(102)
	_check(game.select_remote_join_team(102, "CT").accepted, "fourth reserves slot before rematch")
	game._restart_match()
	_check(not fourth.alive and game.round_state.players[game._round_id_for_actor(fourth)].choosing_appearance
		and first.alive and first.team == "CT" and first.active_weapon == "usp"
		and game.round_state.players[first_id].money == 800, "rematch retains roster/unfinished appearance but resets equipment/accounts")
	_check(game.select_remote_join_class(102, 1).spawned, "pending rematch class can spawn exactly once")
	_pause_actors()
	# Exhaust a side's bot slots; a further client cannot grow the match past five.
	var next_peer := 103
	while game._all_bots().any(func(bot: TargetActor) -> bool: return bot.team == "CT"):
		_connect_peer(next_peer)
		var joined: Dictionary = game.select_remote_join_team(next_peer, "CT")
		_check(joined.accepted, "remaining CT bot slot accepts human")
		if not joined.accepted:
			break
		_check(game.select_remote_join_class(next_peer, 1).spawned, "replacement CT human spawns during freeze")
		next_peer += 1
	var extra := _connect_peer(next_peer)
	var before_count: int = game._all_bots().size()
	_check(not game.select_remote_join_team(next_peer, "CT").accepted and extra.team == "UNASSIGNED"
		and game._all_bots().size() == before_count and game.round_state.team_counts() == {"T": 5, "CT": 5},
		"full human side rejects admission without removing another team's bot")
	network.is_host = false
	_check(not game.select_remote_join_team(next_peer, "T").accepted, "client session cannot author admission")
	network.is_host = true
	_pause_actors()
	game._begin_live()
	game.player.receive_damage(100000, game.player.global_position, false, second)
	_check(game.spectator_camera.pending and not game.spectator_camera.active,
		"host death schedules the normal delayed spectator transition")
	game.spectator_camera._physics_process(game.spectator_camera.ACTIVATION_DELAY - 0.01)
	_check(game.spectator_camera.pending and not game.spectator_camera.active,
		"remote teammates do not bypass the normal death-camera delay")
	game.spectator_camera._physics_process(0.02)
	_check(game.spectator_camera.active and game.spectator_camera.target is PlayerController
		and game.spectator_camera.target != game.player and game.spectator_camera.target.team == game.player.team,
		"host death can spectate a living remote teammate when its side has no bots")
	var watched: Combatant = game.spectator_camera.target
	game.spectator_camera.cycle(1)
	_check(game.spectator_camera.target != watched and game.spectator_camera.target.team == game.player.team,
		"spectator cycling visits another remote teammate, not the enemy side")
	game._reset_round()
	_check(game.player.alive and not game.spectator_camera.is_engaged()
		and root.get_camera_3d() == game.player.camera,
		"round respawn restores the host view after remote-human spectating")
	print("NETWORK_HUMAN_ADMISSION map=", game.map_name, " humans=", game.remote_roster.size(), " bots=", game._all_bots().size())
	game.queue_free()
	await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_HUMAN_ADMISSION_TEST_PASS")
	quit(0 if failures.is_empty() else 1)
