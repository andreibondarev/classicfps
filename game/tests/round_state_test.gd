extends SceneTree

const RoundStateScript := preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ROUND STATE TEST: " + message)


func _run() -> void:
	_assert_default_timing()
	_assert_plant_contract()
	_assert_defuse_contract()
	_assert_win_truth_table()
	_assert_buy_contract()
	_assert_economy()
	_assert_round_reset_clears_dead_hud_state()
	_assert_halftime_and_maxrounds()
	_assert_competitive_match_limits()
	_assert_pistols_are_team_neutral()
	_assert_post_plant_buying()
	_assert_simultaneous_wipe()
	_assert_bomb_planted_accounting()
	_assert_render_rate_independence()
	_assert_observer_transition()
	_write_trace_artifact()
	if failures.is_empty():
		print("GAME_ROUND_STATE_TEST_PASS")
		quit(0)
	else:
		print("GAME_ROUND_STATE_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _assert_observer_transition() -> void:
	for planting in [false, true]:
		var state := _fixture({"freeze_ticks": 1})
		state.advance_tick()
		var owner: String = state.bomb_owner
		if planting:
			state.advance_tick({"plant": {"player_id": owner, "attack": true,
				"equipped_c4": true, "grounded": true, "in_bomb_site": true,
				"site_id": "A", "position": Vector3.ONE}})
			_check(state.plant_actor == owner, "observer test starts a real plant")
		_check(not state.enter_observer(owner, Vector3.ONE) and state.players[owner].alive
			and state.bomb_owner == owner, "alive live players cannot escape into spectator mode")
		state.set_player_alive(owner, false, Vector3.ONE)
		_check(state.enter_observer(owner), "dead players may observe during live play")
		_check(state.bomb_state == "dropped" and state.bomb_owner == "" and state.plant_actor == ""
			and state.bomb_position == Vector3.ONE, "dead observer retains the real death's dropped C4")
		_check(not state.players[owner].alive and not state.players[owner].has_c4
			and state.players[owner].deaths == 1 and state.players[owner].money == 0,
			"observing after death does not count another death and clears the account")
		state.start_match()
		_check(not state.players[owner].alive and state.bomb_owner != owner,
			"match reset never revives or assigns C4 to observers")
	var defusing := _planted_fixture(true)
	defusing.advance_tick({"defuse": {"player_id": "ct1", "use": true,
		"grounded": true, "in_range": true, "facing": true}})
	_check(defusing.defuse_actor == "ct1", "observer test starts a real defuse")
	_check(not defusing.enter_observer("ct1") and defusing.defuse_actor == "ct1",
		"alive defuser cannot escape into observation")
	defusing.set_player_alive("ct1", false)
	_check(defusing.enter_observer("ct1"), "dead defuser may observe")
	_check(defusing.defuse_actor == "" and defusing.bomb_state == "planted"
		and not defusing.players.ct1.has_defuser, "observing cancels defuse without resolving the planted bomb")
	var frozen := _fixture({"freeze_ticks": 1})
	var owner: String = frozen.bomb_owner
	_check(frozen.enter_observer(owner, Vector3.ONE), "alive participant may observe during freeze")
	_check(frozen.players[owner].deaths == 1 and frozen.players[owner].kills == 0
		and frozen.bomb_state == "dropped", "freeze observer suicide counts a death, drops C4, and does not change frags")
	_check(frozen.enter_observer(owner) and frozen.players[owner].deaths == 1, "observer selection is idempotent")
	var deploying := RoundStateScript.new()
	deploying.register_player("player", "T")
	_check(deploying.enter_observer("player") and deploying.players.player.deaths == 0,
		"initial deployment observer does not create a death")


func _fixture(overrides := {}) -> RefCounted:
	var state: RefCounted = RoundStateScript.new()
	state.configure(overrides)
	state.register_player("t1", RoundStateScript.TEAM_T)
	state.register_player("t2", RoundStateScript.TEAM_T)
	state.register_player("ct1", RoundStateScript.TEAM_CT)
	state.register_player("ct2", RoundStateScript.TEAM_CT)
	state.start_match()
	return state


func _advance(state: RefCounted, count: int, command := {}) -> void:
	for ignored in range(count):
		state.advance_tick(command)


func _assert_default_timing() -> void:
	var state := _fixture()
	_check(state.phase == "freeze" and state.deadline_tick == 600, "default freeze is 6 s")
	_advance(state, 599)
	_check(state.phase == "freeze", "freeze lasts through tick 599")
	state.advance_tick()
	_check(
		state.phase == "live" and state.deadline_tick == 30600,
		"default live phase starts at tick 600 and lasts 5 minutes",
	)
	_advance(state, 29999)
	_check(state.phase == "live", "round remains live through its penultimate tick")
	state.advance_tick()
	_check(
		state.phase == "post"
		and state.round_winner == "CT"
		and state.round_reason == "target_saved"
		and state.deadline_tick == 31100,
		"round timeout awards target saved and schedules 5 s restart",
	)
	_advance(state, 500)
	_check(
		state.phase == "freeze" and state.round_number == 2,
		"post phase restarts the next round on its exact deadline",
	)


func _assert_plant_contract() -> void:
	var state := _fixture({
		"freeze_ticks": 1,
		"round_ticks": 2000,
		"plant_ticks": 300,
		"c4_ticks": 4500,
	})
	state.advance_tick()
	var owner: String = state.bomb_owner
	var valid := {
		"player_id": owner,
		"attack": true,
		"equipped_c4": true,
		"grounded": true,
		"in_bomb_site": true,
		"site_id": "A",
		"position": Vector3(1, 2, 3),
		"yaw": 1.25,
	}
	_advance(state, 100, {"plant": valid})
	_check(
		state.bomb_state == "planting"
		and int(state.action_progress().elapsed_ticks) == 99,
		"plant holds source progress while all conditions remain valid",
	)
	var released := valid.duplicate()
	released.attack = false
	state.advance_tick({"plant": released})
	_check(
		state.bomb_state == "carried" and state.action_progress().is_empty(),
		"plant release interrupts and clears progress",
	)
	var release_retry_tick: int = int(state.plant_retry_deadline_by_actor[owner])
	_advance(state, 99, {"plant": valid})
	_check(
		state.plant_actor == "" and state.tick == release_retry_tick - 1,
		"released C4 cannot restart during the source 100-tick cooldown",
	)
	state.advance_tick({"plant": valid})
	_check(
		state.plant_actor == owner and state.tick == release_retry_tick,
		"released C4 may restart exactly on its cooldown deadline",
	)
	state.advance_tick({"plant": released})
	_advance(state, 100)
	for invalid_key in ["grounded", "in_bomb_site", "equipped_c4"]:
		var request := valid.duplicate()
		_advance(state, 20, {"plant": request})
		request[invalid_key] = false
		state.advance_tick({"plant": request})
		_check(
			state.bomb_state == "carried" and state.action_progress().is_empty(),
			"plant interruption clears on %s loss" % invalid_key,
		)
		var expected_cooldown := 150 if invalid_key in ["grounded", "in_bomb_site"] else 100
		_check(
			int(state.plant_retry_deadline_by_actor[owner]) - state.tick
			== expected_cooldown,
			"plant %s interruption applies the source %d-tick retry lock"
			% [invalid_key, expected_cooldown],
		)
		_advance(state, expected_cooldown)
	_advance(state, 301, {"plant": valid})
	_check(
		state.phase == "bomb"
		and state.bomb_state == "planted"
		and state.bomb_position == Vector3(1, 2, 3)
		and state.bomb_deadline_tick - state.tick == 4500,
		"valid 3 s plant creates C4 with an exact 45 s deadline",
	)
	var planted_event: Dictionary = state.trace.filter(
		func(event: Dictionary) -> bool:
			return str(event.type) == "bomb_planted"
	).back()
	_check(
		is_equal_approx(float(planted_event.yaw), 1.25),
		"plant completion carries the authoritative planter yaw to w_c4",
	)
	_check(
		int(state.players[owner].money) == 800,
		"planting does not invent an immediate individual planter payment",
	)


func _planted_fixture(has_kit: bool, c4_ticks := 4500) -> RefCounted:
	var state := _fixture({
		"freeze_ticks": 1,
		"round_ticks": 5000,
		"plant_ticks": 1,
		"c4_ticks": c4_ticks,
	})
	state.set_defuser("ct1", has_kit)
	state.advance_tick()
	var request := {
		"player_id": state.bomb_owner,
		"attack": true,
		"equipped_c4": true,
		"grounded": true,
		"in_bomb_site": true,
		"site_id": "A",
		"position": Vector3.ZERO,
	}
	_advance(state, 2, {"plant": request})
	return state


func _assert_defuse_contract() -> void:
	for has_kit in [false, true]:
		var state := _planted_fixture(has_kit)
		var duration := 500 if has_kit else 1000
		var request := {
			"player_id": "ct1",
			"use": true,
			"grounded": true,
			"in_range": true,
			"facing": true,
		}
		_advance(state, duration, {"defuse": request})
		_check(
			state.phase == "bomb",
			"%s defuse has not completed one tick early"
			% ("kit" if has_kit else "no-kit"),
		)
		state.advance_tick({"defuse": request})
		_check(
			state.phase == "post"
			and state.bomb_state == "defused"
			and state.round_winner == "CT",
			"%s defuse completes at exactly %d ticks"
			% ["kit" if has_kit else "no-kit", duration],
		)
		_check(
			int(state.players.ct1.kills) == 3,
			"source objective score grants the completing defuser +3",
		)
		_check(
			int(state.players.t1.money) == 800
			and int(state.players.t2.money) == 800
			and int(state.pending_team_accounts.T) == 2200,
			"defuse queues $800 planted + $1400 loss without paying during post",
		)
		_check(
			int(state.players.ct1.money) == 800
			and int(state.players.ct2.money) == 800
			and int(state.pending_team_accounts.CT) == 3250,
			"defuse queues the source $3250 CT account without an early HUD jump",
		)
		_advance(state, int(state.config.restart_ticks))
		_check(
			int(state.players.t1.money) == 3000
			and int(state.players.t2.money) == 3000,
			"RestartRound distributes the full planted/loss account to every Terrorist",
		)
		_check(
			int(state.players.ct1.money) == 4050
			and int(state.players.ct2.money) == 4050,
			"RestartRound distributes the source $3250 to every Counter-Terrorist",
		)

	var interrupted := _planted_fixture(false)
	var held := {
		"player_id": "ct1",
		"use": true,
		"grounded": true,
		"in_range": true,
		"facing": true,
	}
	_advance(interrupted, 250, {"defuse": held})
	for invalid_key in ["use", "in_range", "facing"]:
		var request := held.duplicate()
		request[invalid_key] = false
		_advance(interrupted, 50, {"defuse": request})
		_check(
			interrupted.defuse_actor == "ct1",
			"continuous-use refresh gives exactly 0.5 s grace after %s loss"
			% invalid_key,
		)
		interrupted.advance_tick({"defuse": request})
		_check(
			interrupted.defuse_actor == "",
			"defuse aborts after the 0.5 s %s refresh window expires"
			% invalid_key,
		)
		interrupted.advance_tick({"defuse": held})
	var airborne := held.duplicate()
	airborne.grounded = false
	interrupted.advance_tick({"defuse": airborne})
	_check(
		interrupted.defuse_actor == "",
		"leaving the ground aborts defuse immediately without use grace",
	)

	var exclusive := _planted_fixture(false)
	exclusive.advance_tick({"defuse": held})
	var thief := held.duplicate()
	thief.player_id = "ct2"
	_advance(exclusive, 50, {"defuse": thief})
	_check(
		exclusive.defuse_actor == "ct1",
		"a second Counter-Terrorist cannot steal or refresh the assigned defuse",
	)
	exclusive.advance_tick({"defuse": thief})
	_check(
		exclusive.defuse_actor == "",
		"assigned defuse expires after exactly 50 unrefreshed ticks",
	)

	# ReGameDLL fixes deliberately let a completed defuse win when its countdown
	# and the C4 blow time are the same tick.
	var race := _planted_fixture(true, 501)
	var race_request := {
		"player_id": "ct1",
		"use": true,
		"grounded": true,
		"in_range": true,
		"facing": true,
	}
	_advance(race, 501, {"defuse": race_request})
	_check(
		race.bomb_state == "defused" and race.round_winner == "CT",
		"same-tick defuse-versus-explosion race resolves to completed defuse",
	)

	var deadline_reject := _planted_fixture(true, 100)
	_advance(deadline_reject, 99)
	deadline_reject.advance_tick({"defuse": race_request})
	_check(
		deadline_reject.bomb_state == "exploded"
		and deadline_reject.defuse_actor == "",
		"a new defuse beginning on the C4 deadline is rejected before +use",
	)


func _assert_win_truth_table() -> void:
	var t_elimination := _fixture({"freeze_ticks": 1})
	t_elimination.advance_tick()
	t_elimination.set_player_alive("t1", false)
	t_elimination.set_player_alive("t2", false)
	_check(
		t_elimination.round_winner == "CT",
		"eliminating all terrorists before plant awards CT",
	)

	var ct_elimination := _fixture({"freeze_ticks": 1})
	ct_elimination.advance_tick()
	ct_elimination.set_player_alive("ct1", false)
	ct_elimination.set_player_alive("ct2", false)
	_check(
		ct_elimination.round_winner == "T",
		"eliminating all counter-terrorists awards T",
	)

	var planted := _planted_fixture(false, 100)
	planted.set_player_alive("t1", false)
	planted.set_player_alive("t2", false)
	_check(
		planted.phase == "bomb",
		"planted bomb prevents premature CT win after T elimination",
	)
	_advance(planted, 100)
	_check(
		planted.bomb_state == "exploded"
		and planted.round_winner == "T"
		and planted.round_reason == "target_bombed",
		"expired planted bomb damages and awards the target-bombed outcome",
	)
	_check(
		int(planted.players[planted.bomb_planter_id].kills) == 3,
		"source objective score grants the planter +3 when C4 explodes",
	)


func _assert_buy_contract() -> void:
	var state := _fixture({
		"freeze_ticks": 600,
		"round_ticks": 30000,
		"buy_ticks": 9000,
	})
	_check(
		bool(state.can_buy("t1", true, true).allowed),
		"alive player in matching BSP buy zone may buy",
	)
	_check(
		state.can_buy("t1", false, true).reason == "outside_buy_zone",
		"BSP map rejects buys outside team zone",
	)
	_check(
		state.can_buy("t1", false, false).reason == "outside_buy_zone",
		"map without buy brushes still requires the caller's 200-HU spawn fallback",
	)
	_check(
		bool(state.can_buy("t1", true, false).allowed),
		"map without buy brushes accepts a caller-confirmed 200-HU spawn fallback",
	)
	_check(
		state.purchase_item("ct1", "elite", 800, true, true).reason == "wrong_team",
		"CT cannot purchase the Terrorist-only dual Elites",
	)
	_check(
		state.purchase_item("t1", "m4a1", 3100, true, true).reason == "wrong_team",
		"Terrorist cannot purchase the CT-only M4A1",
	)
	state.set_player_alive("t1", false)
	_check(state.can_buy("t1", true, true).reason == "dead", "dead player cannot buy")
	state.players.t1.alive = true
	_advance(state, 9001)
	_check(
		state.can_buy("t1", true, true).reason == "buy_time_expired",
		"buying closes at the authoritative 1.5-minute deadline",
	)


func _assert_economy() -> void:
	var state := _fixture({"freeze_ticks": 1, "restart_ticks": 1})
	var loser_balances: Array[int] = []
	for round_index in 5:
		state.advance_tick()
		state.set_player_alive("ct1", false)
		state.set_player_alive("ct2", false)
		_check(
			int(state.players.ct1.money)
			== (800 if loser_balances.is_empty() else loser_balances.back()),
			"round account stays pending until RestartRound",
		)
		state.advance_tick()
		loser_balances.append(int(state.players.ct1.money))
	_check(
		loser_balances == [2200, 4100, 6500, 9400, 12400],
		"five-round losing streak applies $1400/$1900/$2400/$2900/$3000",
	)
	var before := int(state.players.ct1.money)
	state.grant_kill("ct1")
	_check(
		int(state.players.ct1.money) == mini(16000, before + 300),
		"enemy kill grants $300 with $16000 cap",
	)

	var handoff := _fixture({"freeze_ticks": 1, "restart_ticks": 1})
	for ignored_round in 2:
		handoff.advance_tick()
		handoff.set_player_alive("ct1", false)
		handoff.set_player_alive("ct2", false)
		handoff.advance_tick()
	handoff.advance_tick()
	handoff.set_player_alive("t1", false)
	handoff.set_player_alive("t2", false)
	handoff.advance_tick()
	var t_loss_amount := -1
	for event: Dictionary in handoff.trace:
		if (
			str(event.type) == "money"
			and str(event.player_id) == "t1"
			and str(event.reason) == "restart_round_account"
		):
			t_loss_amount = int(event.amount)
	_check(
		t_loss_amount == 1500,
		"breaking a two-loss streak hands the shared loser bonus to the other team at $1500",
	)


func _assert_round_reset_clears_dead_hud_state() -> void:
	var state := _fixture({"freeze_ticks": 1, "restart_ticks": 1})
	state.advance_tick()
	state.set_player_alive("ct1", false)
	state.set_player_alive("ct2", false)
	var dead_snapshot: Array[Dictionary] = state.scoreboard_snapshot()
	_check(
		not bool(_row(dead_snapshot, "ct1").alive),
		"round-end scoreboard records dead combatant",
	)
	state.advance_tick()
	var reset_snapshot: Array[Dictionary] = state.scoreboard_snapshot()
	for row: Dictionary in reset_snapshot:
		_check(
			bool(row.alive),
			"new-round scoreboard clears stale dead flag for %s" % row.id,
		)


func _assert_halftime_and_maxrounds() -> void:
	var state := _fixture({
		"freeze_ticks": 1,
		"restart_ticks": 1,
		"max_rounds": 4,
		"halftime": true,
	})
	for round_index in 4:
		state.advance_tick()
		var loser_team := "CT" if round_index % 2 == 0 else "T"
		for player_id: String in state.players:
			if str(state.players[player_id].team) == loser_team:
				state.set_player_alive(player_id, false)
		state.advance_tick()
		if round_index == 1:
			_check(
				str(state.players.t1.team) == "CT",
				"halftime hook swaps teams after half of maxrounds",
			)
	_check(
		state.phase == "intermission",
		"maxrounds hook enters intermission after configured rounds",
	)


func _assert_competitive_match_limits() -> void:
	var state := _fixture({
		"freeze_ticks": 1,
		"restart_ticks": 1,
		"max_rounds": 30,
		"win_limit": 16,
		"halftime": true,
	})
	for player_id: String in state.players:
		state.adjust_player_money(player_id, 16000, "test_seed")
	var halftime_events := 0
	var match_end_events := 0
	var swapped_at_round := 0
	var money_at_second_half := -1
	var bonus_at_second_half := -1
	var streaks_at_second_half := -1
	for round_index in 30:
		if state.phase == "intermission":
			break
		state.advance_tick()
		# Terrorists take the first half, counter-terrorists the second, so the
		# match must end on the win limit before the round limit is reached.
		var loser_team := "CT" if round_index < 16 else "T"
		for player_id: String in state.players:
			if str(state.players[player_id].team) == loser_team:
				state.set_player_alive(player_id, false)
		for event: Dictionary in state.advance_tick():
			if str(event.type) == "halftime":
				halftime_events += 1
				swapped_at_round = int(event.round)
				money_at_second_half = int(state.players.t1.money)
				bonus_at_second_half = int(state.loser_bonus)
				streaks_at_second_half = (
					int(state.loss_streak.T) + int(state.loss_streak.CT)
				)
			elif str(event.type) == "match_end":
				match_end_events += 1
	_check(
		halftime_events == 1 and swapped_at_round == 15,
		"MR15 configuration swaps sides exactly once, after round 15",
	)
	_check(
		money_at_second_half == RoundStateScript.START_MONEY,
		"half-time restarts every account at $800",
	)
	_check(
		bonus_at_second_half == RoundStateScript.LOSER_BONUS_DEFAULT
		and streaks_at_second_half == 0,
		"half-time restarts the shared loser-bonus ladder",
	)
	_check(
		match_end_events == 1 and state.phase == "intermission",
		"MR15 match ends once a side reaches the 16-win limit",
	)
	_check(
		maxi(int(state.ct_score), int(state.terrorist_score)) == 16
		and int(state.rounds_played) < 30,
		"win limit ends the match before the 30-round limit",
	)

	var swapped_teams: Array[String] = []
	for player_id: String in ["t1", "ct1"]:
		swapped_teams.append(str(state.players[player_id].team))
	_check(
		swapped_teams == ["CT", "T"],
		"half-time leaves the roster on the opposite sides",
	)


func _assert_pistols_are_team_neutral() -> void:
	var state := _fixture()
	_check(
		bool(state.purchase_item("t1", "usp", 500, true, true).allowed),
		"Terrorist may buy the USP listed in BuyPistols_TER.kv",
	)
	_check(
		bool(state.purchase_item("ct1", "glock18", 400, true, true).allowed),
		"Counter-Terrorist may buy the Glock listed in BuyPistols_CT.kv",
	)
	_check(
		state.purchase_item("t1", "fiveseven", 750, true, true).reason == "wrong_team",
		"Five-SeveN stays CT-only",
	)
	_check(
		state.purchase_item("ct1", "elite", 800, true, true).reason == "wrong_team",
		"dual Elites stay T-only",
	)


func _assert_post_plant_buying() -> void:
	var state := _planted_fixture(false, 4500)
	_check(state.phase == "bomb", "planted fixture reaches the bomb phase")
	_check(
		bool(state.can_buy("t1", true, true).allowed)
		and bool(state.can_buy("ct1", true, true).allowed),
		"a planted bomb does not close the buy menu",
	)
	state.adjust_player_money("ct1", 3100, "test_seed")
	var balance_before := int(state.players.ct1.money)
	_check(
		bool(state.purchase_item("ct1", "m4a1", 3100, true, true).allowed)
		and int(state.players.ct1.money) == balance_before - 3100,
		"post-plant purchases still debit the account",
	)
	state.set_player_alive("ct2", false)
	_check(
		state.can_buy("ct2", true, true).reason == "dead",
		"post-plant buying still requires a living buyer",
	)
	state.configure({"buy_ticks": 200})
	_advance(state, 300)
	_check(state.phase == "bomb", "bomb keeps ticking through the buy deadline")
	_check(
		state.can_buy("t1", true, true).reason == "buy_time_expired",
		"mp_buytime still closes buying during the bomb phase",
	)


func _assert_simultaneous_wipe() -> void:
	var state := _fixture({"freeze_ticks": 1, "round_ticks": 2000})
	state.advance_tick()
	state.players.t1.alive = false
	state.players.t2.alive = false
	state.players.ct1.alive = false
	state.set_player_alive("ct2", false)
	_check(
		state.phase == "post",
		"a same-tick mutual wipe ends the round instead of running to timeout",
	)
	_check(
		state.round_winner == "T" and state.round_reason == "terrorists_win",
		"TeamExterminationCheck order awards a mutual wipe to the Terrorists",
	)

	var one_sided: RefCounted = RoundStateScript.new()
	one_sided.configure({"freeze_ticks": 1, "round_ticks": 2000})
	one_sided.register_player("t1", RoundStateScript.TEAM_T)
	one_sided.start_match()
	one_sided.advance_tick()
	one_sided.set_player_alive("t1", false)
	_check(
		one_sided.phase == "post"
		and one_sided.round_winner == ""
		and one_sided.round_reason == "round_draw",
		"an unpopulated side falls through to a scoreless round draw",
	)
	_check(
		int(one_sided.ct_score) == 0
		and int(one_sided.terrorist_score) == 0
		and int(one_sided.pending_team_accounts.T) == 0
		and int(one_sided.pending_team_accounts.CT) == 0,
		"a drawn round scores nothing and queues no team account",
	)


func _assert_bomb_planted_accounting() -> void:
	# ReGameDLL pays RR_BOMB_PLANTED ($800) in Target_Defused and grants the
	# planter's +3 frags in CGrenade::C4Think, i.e. both are round-end awards.
	var defused := _planted_fixture(true, 4500)
	var planter := str(defused.bomb_planter_id)
	_check(
		int(defused.players[planter].kills) == 0,
		"planting alone grants no objective score",
	)
	var t_balance_before := int(defused.players.t1.money)
	var request := {
		"player_id": "ct1",
		"use": true,
		"grounded": true,
		"in_range": true,
		"facing": true,
	}
	_advance(defused, 501, {"defuse": request})
	_check(
		defused.bomb_state == "defused" and int(defused.players.ct1.kills) == 3,
		"the defuser receives the +3 objective score",
	)
	_check(
		int(defused.players[planter].kills) == 0,
		"a defused bomb leaves the planter without the explosion score",
	)
	_check(
		int(defused.pending_team_accounts.T)
		== RoundStateScript.REWARD_BOMB_PLANTED + int(defused.loser_bonus),
		"a defused bomb pays the planting team $800 on top of the loser bonus",
	)
	defused.advance_tick()
	_advance(defused, int(defused.config.restart_ticks))
	_check(
		int(defused.players.t1.money)
		== t_balance_before
		+ RoundStateScript.REWARD_BOMB_PLANTED
		+ RoundStateScript.LOSER_BONUS_DEFAULT,
		"the $800 plant bonus is distributed exactly once at RestartRound",
	)


func _assert_render_rate_independence() -> void:
	var reference := ""
	for render_rate in [30, 60, 144]:
		var state := _fixture({
			"freeze_ticks": 60,
			"round_ticks": 400,
			"restart_ticks": 50,
		})
		var accumulator := 0.0
		var physics_ticks := 0
		while physics_ticks < 1200:
			accumulator += 1.0 / float(render_rate)
			while accumulator + 0.0000001 >= 0.01 and physics_ticks < 1200:
				accumulator -= 0.01
				state.advance_tick()
				physics_ticks += 1
		var signature := _trace_signature(state.trace)
		if reference.is_empty():
			reference = signature
		else:
			_check(
				signature == reference,
				"%d Hz render scheduling produces identical 100 Hz trace" % render_rate,
			)


func _row(rows: Array[Dictionary], player_id: String) -> Dictionary:
	for row: Dictionary in rows:
		if str(row.id) == player_id:
			return row
	return {}


func _trace_signature(events: Array[Dictionary]) -> String:
	var parts: Array[String] = []
	for event: Dictionary in events:
		parts.append(
			"%d:%s:%s:%s"
			% [
				int(event.tick),
				str(event.type),
				str(event.get("winner", "")),
				str(event.get("reason", "")),
			],
		)
	return "|".join(parts)


func _write_trace_artifact() -> void:
	var state := _planted_fixture(true, 700)
	var request := {
		"player_id": "ct1",
		"use": true,
		"grounded": true,
		"in_range": true,
		"facing": true,
	}
	_advance(state, 501, {"defuse": request})
	var file := FileAccess.open(
		"/tmp/protocol47-round-state-100hz-trace.json",
		FileAccess.WRITE,
	)
	_check(file != null, "deterministic round trace artifact opens")
	if file != null:
		file.store_string(JSON.stringify({
			"tick_rate_hz": 100,
			"trace": state.trace,
			"scoreboard": state.scoreboard_snapshot(),
		}, "\t"))
