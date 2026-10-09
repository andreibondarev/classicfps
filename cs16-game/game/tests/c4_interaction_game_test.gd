extends SceneTree

const RoundStateScript := preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("C4 INTERACTION GAME TEST: " + message)


func _run() -> void:
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()

	# One `drop` press while holding the C4 (the player's G path) drops only
	# the bomb: the weapon it switches to must not be thrown by the same press.
	_force_owner(game, "player")
	game.player.grant_item("ak47")
	_check(game._equip_player_c4(), "carrier with a rifle equips the C4")
	game.player._try_drop_active_weapon()
	_check(
		game.round_state.bomb_state == RoundStateScript.BOMB_DROPPED
		and game.player.owns_weapon("ak47")
		and game.player.active_weapon == "ak47",
		"G with the C4 drops the bomb and keeps the rifle (state=%s owns_ak47=%s active=%s)"
		% [game.round_state.bomb_state, game.player.owns_weapon("ak47"), game.player.active_weapon],
	)
	game._clear_dropped_c4()
	_force_owner(game, "player")
	_check(game._equip_player_c4(), "production player equips carried C4")
	_check(
		game._request_drop_active_weapon()
		and game.round_state.bomb_state == RoundStateScript.BOMB_DROPPED
		and is_instance_valid(game.dropped_c4)
		and game.player.active_weapon != "c4",
		"G invokes the validated manual-drop transition and switches weapon",
	)
	for terrorist in game.allied_bots:
		terrorist.alive = false
		terrorist.active = false
	game.player.configure_identity(Combatant.TEAM_COUNTER_TERRORIST, "Player")
	var physical_drop = game.dropped_c4
	var dropped_spawn: Vector3 = physical_drop.global_position
	for landing_tick in 240:
		await physics_frame
		if not is_instance_valid(physical_drop) or physical_drop.materialized:
			break
	_check(
		is_instance_valid(physical_drop)
		and physical_drop.materialized
		and game.round_state.bomb_position.distance_to(
			physical_drop.global_position,
		) < 0.001
		and game.round_state.bomb_position.distance_to(dropped_spawn)
			> 1.0 * Combatant.GOLDSRC_UNIT,
		"authoritative dropped-bomb position follows the real toss through landing "
		+ "(valid=%s landed=%s authority=%s physical=%s travel_hu=%.2f)"
		% [
			is_instance_valid(physical_drop),
			bool(physical_drop.materialized) if is_instance_valid(physical_drop) else false,
			game.round_state.bomb_position,
			physical_drop.global_position if is_instance_valid(physical_drop) else Vector3.INF,
			(
				physical_drop.global_position.distance_to(dropped_spawn)
				/ Combatant.GOLDSRC_UNIT
				if is_instance_valid(physical_drop)
				else -1.0
			),
		],
	)

	var ct = game.targets[0]
	ct.global_position = Vector3(0.0, 20.0, 0.0)
	var loose_position: Vector3 = ct.global_position + Vector3(0.0, 0.0, 0.80)
	game.round_state.bomb_state = RoundStateScript.BOMB_DROPPED
	game.round_state.bomb_position = loose_position
	game.bomb_position = loose_position
	game.bomb_knowledge.on_bomb_dropped(loose_position)
	ct.rotation.y = 0.0
	_check(
		game.bot_objective_context(ct).is_empty(),
		"a CT facing away receives no omniscient dropped-C4 guard task",
	)
	ct.face_aim_target(loose_position + Vector3.UP * 0.04)
	_check(
		str(game.bot_objective_context(ct).get("action", "")) == "guard",
		"strict FOV plus line of sight reveals the loose C4 to a CT",
	)

	game.phase = RoundStateScript.PHASE_BOMB
	game.round_state.phase = RoundStateScript.PHASE_BOMB
	game.round_state.bomb_state = RoundStateScript.BOMB_PLANTED
	game.round_state.bomb_deadline_tick = game.round_state.tick + 3000
	var planted_position: Vector3 = game.bomb_sites[0]
	game.round_state.bomb_position = planted_position
	game.bomb_position = planted_position
	ct.global_position = planted_position + Vector3(20.0, 0.0, 0.0)
	ct.rotation.y = 0.0
	game.bomb_knowledge.reset_round()
	game.bomb_knowledge.on_bomb_planted(
		planted_position,
		{ct.name: ct.global_position},
	)
	var ct_receivers: Array[String] = [ct.name]
	game.bomb_knowledge.broadcast_planted_site(
		str(game.bomb_regions[0].get("target", "")),
		ct_receivers,
	)
	var search_context: Dictionary = game.bot_objective_context(ct)
	_check(
		not game.bomb_knowledge.knows_exact(ct.name)
		and str(search_context.get("action", "")) == "search_site",
		"a far CT receives planted-site radio knowledge without exact C4 origin",
	)

	game._spawn_bomb_visual(game.player.global_position + Vector3(0.0, 0.0, -0.60))
	game.phase = RoundStateScript.PHASE_BOMB
	game.player.rotation.y = 0.0
	var c4_request: Dictionary = game._defuse_request(game.player, true)
	_check(bool(c4_request.use), "C4 wins PlayerUse when it has the best view dot")
	var competitor := Node3D.new()
	competitor.name = "DoorButton"
	game.add_child(competitor)
	competitor.add_to_group("source_use_targets")
	competitor.global_position = (
		game.player.camera.global_position
		- game.player.camera.global_transform.basis.z * 0.20
	)
	var stolen_request: Dictionary = game._defuse_request(game.player, true)
	_check(
		not bool(stolen_request.use),
		"a higher-dot door/button candidate steals +use from the planted C4",
	)
	competitor.remove_from_group("source_use_targets")
	competitor.queue_free()

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_C4_INTERACTION_GAME_TEST_PASS")
		quit(0)
	else:
		print("GAME_C4_INTERACTION_GAME_TEST_FAIL: " + ", ".join(failures))
		quit(1)


func _force_owner(game: Node, owner_id: String) -> void:
	for actor_id: String in game.round_state.players:
		var state: Dictionary = game.round_state.players[actor_id]
		state.alive = true
		state.has_c4 = actor_id == owner_id
		game.round_state.players[actor_id] = state
	game.round_state.bomb_owner = owner_id
	game.round_state.bomb_state = RoundStateScript.BOMB_CARRIED
	game._sync_round_public_state()
