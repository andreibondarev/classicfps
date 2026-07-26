extends SceneTree

const RoundState := preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_assert_round_reset_and_kit_carry()
	_assert_manual_bomb_drop_transition()
	_assert_explosion_ownership_and_economy()
	if failures.is_empty():
		print("GAME_ROUND_RESET_RULES_TEST_PASS")
		quit(0)
	else:
		print("GAME_ROUND_RESET_RULES_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ROUND RESET RULES TEST: " + message)


func _fixture(overrides := {}) -> RefCounted:
	var state: RefCounted = RoundState.new()
	state.configure(overrides)
	state.register_player("t1", RoundState.TEAM_T)
	state.register_player("ct_dead", RoundState.TEAM_CT, 800, true)
	state.register_player("ct_survivor", RoundState.TEAM_CT, 800, true)
	state.start_match()
	return state


func _advance(state: RefCounted, ticks: int, command := {}) -> void:
	for ignored in range(ticks):
		state.advance_tick(command)


func _assert_round_reset_and_kit_carry() -> void:
	var state := _fixture({
		"freeze_ticks": 1,
		"restart_ticks": 1,
	})
	state.advance_tick()
	state.defuse_actor = "ct_dead"
	state.defuse_started_tick = state.tick
	state.defuse_duration_ticks = 500
	state.defuse_refresh_deadline_tick = state.tick + 50
	state.plant_actor = "t1"
	state.plant_started_tick = state.tick
	state.plant_retry_deadline_by_actor.t1 = state.tick + 150
	state.bomb_planter_id = "t1"
	state.bomb_state = RoundState.BOMB_PLANTING
	state.bomb_deadline_tick = state.tick + 4500
	state.next_beep_tick = state.tick + 50
	state.next_frequency_tick = state.tick
	state.frequency_interval_ticks = 1125
	state.beep_interval_ticks = 20
	state.beep_wave = 4

	state.set_player_alive("ct_dead", false)
	# End the round without killing the surviving kit owner.
	state.set_player_alive("ct_survivor", false)
	# Re-open this actor as the survivor before the authoritative reset. This
	# keeps elimination deterministic while testing the exact prior-alive bit.
	state.players.ct_survivor.alive = true
	_check(
		state.phase == RoundState.PHASE_POST,
		"fixture reaches post-round before RestartRound",
	)
	_check(
		int(state.pending_team_accounts.T) == 3250
		and int(state.pending_team_accounts.CT) == 1400,
		"winning and losing money remains queued during post-round",
	)
	# A completed objective normally clears its actor but can leave duration and
	# planted-clock data populated until RestartRound. Seed that legal boundary
	# shape explicitly so this regression fails if reset ordering ever regresses.
	state.defuse_duration_ticks = 500
	state.bomb_deadline_tick = state.tick + 4500
	state.next_beep_tick = state.tick + 50
	state.next_frequency_tick = state.tick
	state.frequency_interval_ticks = 1125
	state.beep_interval_ticks = 20
	state.beep_wave = 4

	state.advance_tick()
	_check(
		state.phase == RoundState.PHASE_FREEZE and state.round_number == 2,
		"RestartRound begins the next freeze phase on the exact deadline",
	)
	_check(
		not bool(state.players.ct_dead.has_defuser),
		"dead CT does not resurrect a dropped defuse kit",
	)
	_check(
		bool(state.players.ct_survivor.has_defuser),
		"living CT carries the defuse kit into the next round",
	)
	_check(
		int(state.players.ct_dead.money) == 2200
		and int(state.players.ct_survivor.money) == 2200
		and int(state.players.t1.money) == 4050
		and state.pending_team_accounts == {
			RoundState.TEAM_T: 0,
			RoundState.TEAM_CT: 0,
		},
		"queued economy distributes before the new round snapshot and clears accounts",
	)
	_check(
		state.action_progress().is_empty()
		and state.plant_actor == ""
		and state.plant_started_tick == -1
		and state.plant_retry_deadline_by_actor.is_empty()
		and state.defuse_actor == ""
		and state.defuse_started_tick == -1
		and state.defuse_duration_ticks == 0
		and state.defuse_refresh_deadline_tick == -1,
		"new round has no stale plant, retry, defuse, or progress lock",
	)
	_check(
		state.bomb_planter_id == ""
		and state.bomb_state == RoundState.BOMB_CARRIED
		and state.bomb_owner == "t1"
		and bool(state.players.t1.has_c4)
		and state.bomb_deadline_tick == -1
		and state.next_beep_tick == -1
		and state.next_frequency_tick == -1
		and state.frequency_interval_ticks == 0
		and state.beep_interval_ticks == 140
		and state.beep_wave == 0,
		"new round owns one fresh carried C4 and clears every planted-C4 timer",
	)
	var round_start: Dictionary = state.trace.filter(
		func(event: Dictionary) -> bool:
			return str(event.type) == "round_start" and int(event.round) == 2
	).back()
	_check(
		int(_row(round_start.scoreboard, "ct_dead").money) == 2200
		and not bool(_row(round_start.scoreboard, "ct_dead").get("bomb", true))
		and bool(_row(round_start.scoreboard, "ct_dead").alive),
		"round_start snapshot is emitted after economy, respawn, and C4 reassignment",
	)


func _assert_explosion_ownership_and_economy() -> void:
	var state := _fixture({
		"freeze_ticks": 1,
		"plant_ticks": 1,
		"c4_ticks": 2,
	})
	state.advance_tick()
	var planter := str(state.bomb_owner)
	var plant_request := {
		"player_id": planter,
		"attack": true,
		"equipped_c4": true,
		"grounded": true,
		"in_bomb_site": true,
		"site_id": "A",
		"position": Vector3(4, 5, 6),
	}
	_advance(state, 2, {"plant": plant_request})
	_advance(state, 2)

	var explosion_events: Array[Dictionary] = state.trace.filter(
		func(event: Dictionary) -> bool:
			return str(event.type) == "bomb_exploded"
	)
	_check(explosion_events.size() == 1, "C4 emits exactly one explosion event")
	if explosion_events.size() != 1:
		return
	var explosion := explosion_events[0]
	_check(
		str(explosion.player_id) == planter
		and str(explosion.planter_id) == planter
		and str(explosion.attacker_id) == planter
		and str(explosion.inflictor) == "c4"
		and bool(explosion.cleanup_world_c4),
		"explosion carries explicit planter ownership for kills, VFX, and model cleanup",
	)
	_check(
		is_equal_approx(float(explosion.damage), 500.0)
		and is_equal_approx(float(explosion.radius_hu), 1750.0),
		"explosion event carries Source 500 base damage and 1750 HU effective radius",
	)
	var score_events: Array[Dictionary] = state.trace.filter(
		func(event: Dictionary) -> bool:
			return (
				str(event.type) == "score"
				and str(event.reason) == "bomb_exploded"
			)
	)
	_check(
		score_events.size() == 1
		and str(score_events[0].player_id) == planter
		and int(score_events[0].amount) == 3
		and int(state.players[planter].kills) == 3,
		"bomb score event and scoreboard attribute the source +3 to the planter",
	)
	_check(
		int(state.players[planter].money) == 800
		and int(state.pending_team_accounts.T) == 3500
		and int(state.pending_team_accounts.CT) == 1400,
		"explosion queues exact team accounts without inventing planter cash",
	)


func _assert_manual_bomb_drop_transition() -> void:
	var state := _fixture()
	var owner := str(state.bomb_owner)
	var drop_position := Vector3(2, 3, 4)
	_check(
		not state.drop_bomb("ct_dead", drop_position),
		"non-owner cannot manually drop the C4",
	)
	_check(
		state.drop_bomb(owner, drop_position),
		"living carried-C4 owner can manually drop the bomb",
	)
	_check(
		state.bomb_owner == ""
		and state.bomb_state == RoundState.BOMB_DROPPED
		and state.bomb_position == drop_position
		and not bool(state.players[owner].has_c4),
		"manual drop atomically clears ownership and records the world position",
	)
	var event: Dictionary = state.trace.back()
	_check(
		str(event.type) == "bomb_dropped"
		and str(event.player_id) == owner
		and str(event.reason) == "manual"
		and event.position == drop_position,
		"manual drop emits one integration-ready bomb_dropped event",
	)
	_check(
		not state.drop_bomb(owner, Vector3.ZERO),
		"dropped C4 cannot be dropped a second time",
	)


func _row(rows: Array[Dictionary], player_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.id) == player_id:
			return row
	return {}
