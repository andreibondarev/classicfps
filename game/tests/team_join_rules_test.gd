extends SceneTree

const Rules = preload("res://scripts/cs16_round_state.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var caps := {"T": 16, "CT": 16}
	var rules = _match()
	var before: Array = rules.trace.duplicate(true)
	var tick: int = rules.tick
	var selected: Dictionary = rules.select_player_team("p", "T", caps)
	_check(selected.accepted and selected.selection_death, "same-team selection kills a living participant")
	_check(rules.tick == tick and rules.round_number == 1 and rules.trace.slice(0, before.size()) == before,
		"selection preserves clock and prior trace")
	_check(rules.players.p.deaths == 1 and rules.players.p.kills == -1, "normal selection suicide scores once")
	_check(rules.bomb_owner.is_empty() and rules.bomb_state == Rules.BOMB_DROPPED,
		"selection death drops carried C4 through the existing objective path")
	_check(not rules.finish_player_appearance("p") and not rules.players.p.alive,
		"previously spawned participant cannot respawn by choosing appearance")
	_check(rules.team_selection_error("p", "CT", caps) == "already_changed", "dead player cannot switch twice")
	rules._start_round()
	_check(rules.players.p.alive and not rules.players.p.team_changed, "next round respawns and resets switch restriction")

	rules = _match()
	rules.set_player_alive("t", false)
	rules._set_phase(Rules.PHASE_LIVE, 1000)
	rules.select_player_team("p", "CT", caps)
	_check(rules.phase == Rules.PHASE_POST and rules.ct_score == 1 and rules.round_number == 1,
		"last survivor's selection death preserves the legitimate round outcome")

	rules = _match()
	rules.register_player("new", "UNASSIGNED")
	selected = rules.select_player_team("new", "CT", caps)
	_check(selected.accepted and not selected.selection_death and rules.players.new.money == 800,
		"observer enrollment starts an account without a death")
	_check(not rules.can_spawn_joined_player("new"), "appearance menu prevents early spawning")
	_check(rules.finish_player_appearance("new") and rules.players.new.round_spawns == 1,
		"new early entrant spawns once")
	_check(not rules.finish_player_appearance("new"), "duplicate class submission cannot spawn again")

	rules = _match()
	rules.register_player("new", "UNASSIGNED")
	rules.tick = rules.round_started_tick + int(rules.config.freeze_ticks) + 2000
	rules._set_phase(Rules.PHASE_LIVE, 10000)
	rules.select_player_team("new", "CT", caps)
	_check(rules.finish_player_appearance("new"), "exact respawn-window endpoint is inclusive")

	rules = _match()
	rules.register_player("new", "UNASSIGNED")
	rules.tick = rules.round_started_tick + int(rules.config.freeze_ticks) + 2001
	rules._set_phase(Rules.PHASE_LIVE, 10000)
	_check(rules.select_player_team("new", "CT", caps).accepted, "late entrant may enroll")
	_check(not rules.finish_player_appearance("new") and rules.players.new.team == "CT", "late entrant waits on the selected team")
	rules._start_round()
	_check(rules.players.new.alive, "late entrant spawns at the next real round")

	rules = _match()
	rules.register_player("new", "UNASSIGNED")
	rules.select_player_team("new", "CT", caps)
	rules._start_round()
	_check(not rules.players.new.alive and rules.players.new.round_spawns == 0, "open appearance menu survives round boundary without spawning")
	_check(rules.finish_player_appearance("new"), "closing appearance in the new round permits first spawn")

	rules = _match()
	_check(rules.team_selection_error("p", "CT", {"T": 16, "CT": 2}) == "team_full", "spawn capacity is authoritative")
	rules.register_player("extra_ct", "CT")
	_check(rules.team_selection_error("p", "CT", caps) == "team_stacked", "switch cannot exceed configured imbalance")
	_check(rules.team_selection_error("p", "T", caps).is_empty(), "same-team choice is exempt from stacking")
	_check(rules.default_join_team(caps, "CT") == "T", "auto chooses smaller roster")
	rules.players.erase("extra_ct")
	rules.ct_score = 3
	_check(rules.default_join_team(caps, "CT") == "T", "equal rosters choose losing score")
	rules.ct_score = 0
	_check(rules.default_join_team(caps, "CT") == "CT", "tie break is used only after count and score tie")
	_check(rules.default_join_team({"T": 2, "CT": 3}, "T") == "CT", "auto falls back from full side")
	_check(rules.default_join_team({"T": 2, "CT": 2}).is_empty(), "auto reports both full")
	_check(rules.team_selection_error("p", "invalid", caps) == "invalid_team", "invalid teams rejected")

	# Host-selected bot replacement uses the projected roster for capacity and
	# balance. Invalid reservations must not mutate either player or the trace.
	rules = _match()
	rules.register_player("new", "UNASSIGNED")
	var replacement_caps := {"T": 2, "CT": 2}
	var original_players: Dictionary = rules.players.duplicate(true)
	var original_trace: Array = rules.trace.duplicate(true)
	for replacement in ["missing", "new", "t"]:
		var rejected: Dictionary = rules.select_player_team("new", "CT", replacement_caps, Vector3.ZERO, replacement)
		_check(not rejected.accepted and rejected.reason == "invalid_replacement",
			"unknown, self and opposite-side replacement rejected: " + replacement)
		_check(rules.players == original_players and rules.trace == original_trace,
			"invalid replacement is inert: " + replacement)
	_check(rules.team_selection_error("new", "CT", replacement_caps) == "team_full",
		"full side still rejects enrollment without a replacement")
	_check(rules.team_selection_error("new", "CT", replacement_caps, "c2").is_empty(),
		"valid same-side replacement reserves exactly one full-side place")
	selected = rules.select_player_team("new", "CT", replacement_caps, Vector3.ZERO, "c2")
	_check(selected.accepted and not selected.selection_death and rules.players.new.choosing_appearance
		and rules.players.has("c2"), "selection reserves appearance; host owns synchronous replacement removal")
	rules.disconnect_player("c2", Vector3.ZERO)
	_check(rules.team_counts() == {"T": 2, "CT": 2} and rules.players.new.money == 800,
		"committed replacement retains balanced capacity and normal entrant money")
	rules = _match()
	rules.register_player("new", "UNASSIGNED")
	rules.register_player("c3", "CT")
	rules.register_player("c4", "CT")
	_check(rules.team_selection_error("new", "CT", caps, "c4").is_empty(),
		"replacement at the configured two-player imbalance boundary remains legal")
	rules.register_player("c5", "CT")
	_check(rules.team_selection_error("new", "CT", caps, "c4") == "team_stacked",
		"one replacement cannot waive the normal team-balance restriction")

	print("GAME_TEAM_JOIN_RULES_PASS" if failures.is_empty() else "GAME_TEAM_JOIN_RULES_FAIL")
	quit(0 if failures.is_empty() else 1)

func _match() -> RefCounted:
	var rules = Rules.new()
	rules.register_player("p", "T")
	rules.register_player("t", "T")
	rules.register_player("c1", "CT")
	rules.register_player("c2", "CT")
	rules.start_match()
	return rules

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("TEAM JOIN: " + message)
