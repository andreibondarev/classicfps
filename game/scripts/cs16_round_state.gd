class_name CS16RoundState
extends RefCounted

# Integer-tick round/objective/economy model based on CHalfLifeMultiplay,
# CBasePlayer::CanPlayerBuy, CWeaponC4, and CGrenade::C4Think/Use.
const TICK_RATE := 100
const TEAM_T := "T"
const TEAM_CT := "CT"

const PHASE_DEPLOY := "deploy"
const PHASE_FREEZE := "freeze"
const PHASE_LIVE := "live"
const PHASE_BOMB := "bomb"
const PHASE_POST := "post"
const PHASE_INTERMISSION := "intermission"

const BOMB_NONE := "none"
const BOMB_CARRIED := "carried"
const BOMB_DROPPED := "dropped"
const BOMB_PLANTING := "planting"
const BOMB_PLANTED := "planted"
const BOMB_DEFUSED := "defused"
const BOMB_EXPLODED := "exploded"

const START_MONEY := 800
const MAX_MONEY := 16000
const KILL_REWARD := 300
const REWARD_BOMB_PLANTED := 800
const REWARD_TARGET_BOMB := 3500
const REWARD_BOMB_DEFUSED := 3250
const REWARD_BOMB_EXPLODED := 3250
const REWARD_TARGET_SAVED := 3250
const REWARD_TEAM_WIN := 3000
const LOSER_BONUS_DEFAULT := 1400
const LOSER_BONUS_MIN := 1500
const LOSER_BONUS_MAX := 3000
const LOSER_BONUS_ADD := 500
const DEFUSE_USE_REFRESH_TICKS := 50
const C4_DAMAGE := 500.0
const C4_RADIUS_HU := 1750.0
const T_ONLY_ITEMS := [
	"glock18", "elite", "mac10", "galil", "ak47", "sg552", "g3sg1",
]
const CT_ONLY_ITEMS := [
	"usp", "fiveseven", "tmp", "famas", "m4a1", "aug", "sg550",
	"shield", "defuser",
]

var config := {
	"freeze_ticks": 6 * TICK_RATE,
	"round_ticks": 5 * 60 * TICK_RATE,
	"c4_ticks": 45 * TICK_RATE,
	"restart_ticks": 5 * TICK_RATE,
	"plant_ticks": 3 * TICK_RATE,
	"defuse_kit_ticks": 5 * TICK_RATE,
	"defuse_ticks": 10 * TICK_RATE,
	"buy_ticks": 90 * TICK_RATE,
	"max_rounds": 0,
	"halftime": false,
}

var tick := 0
var round_number := 0
var phase := PHASE_DEPLOY
var phase_started_tick := 0
var deadline_tick := -1
var round_started_tick := 0
var ct_score := 0
var terrorist_score := 0
var round_winner := ""
var round_reason := ""

var players := {}
var bomb_owner := ""
var bomb_state := BOMB_NONE
var bomb_position := Vector3.ZERO
var bomb_site_id := ""
var bomb_deadline_tick := -1
var next_beep_tick := -1
var next_frequency_tick := -1
var beep_interval_ticks := 140
var frequency_interval_ticks := 0
var beep_wave := 0
var plant_actor := ""
var plant_started_tick := -1
var defuse_actor := ""
var defuse_started_tick := -1
var defuse_duration_ticks := 0
var defuse_refresh_deadline_tick := -1
var loss_streak := {TEAM_T: 0, TEAM_CT: 0}
var loser_bonus := LOSER_BONUS_DEFAULT
var pending_team_accounts := {TEAM_T: 0, TEAM_CT: 0}
var trace: Array[Dictionary] = []


func configure(overrides := {}) -> void:
	for key: Variant in overrides:
		if config.has(key):
			config[key] = overrides[key]


func register_player(
	player_id: String,
	team: String,
	money := START_MONEY,
	has_defuser := false,
) -> void:
	players[player_id] = {
		"team": team,
		"alive": true,
		"money": clampi(money, 0, MAX_MONEY),
		"has_c4": false,
		"has_defuser": has_defuser,
		"kills": 0,
		"deaths": 0,
	}


func start_match() -> void:
	tick = 0
	round_number = 0
	ct_score = 0
	terrorist_score = 0
	loss_streak = {TEAM_T: 0, TEAM_CT: 0}
	loser_bonus = LOSER_BONUS_DEFAULT
	pending_team_accounts = {TEAM_T: 0, TEAM_CT: 0}
	trace.clear()
	_start_round()


func advance_tick(command := {}) -> Array[Dictionary]:
	var event_start := trace.size()
	tick += 1
	match phase:
		PHASE_FREEZE:
			if tick >= deadline_tick:
				_set_phase(PHASE_LIVE, int(config.round_ticks))
				_emit("round_freeze_end")
		PHASE_LIVE:
			_update_plant(command.get("plant", {}))
			if phase == PHASE_LIVE:
				_check_elimination()
			if phase == PHASE_LIVE and tick >= deadline_tick:
				_end_round(TEAM_CT, "target_saved", REWARD_TARGET_SAVED)
		PHASE_BOMB:
			_update_defuse(command.get("defuse", {}))
			if phase == PHASE_BOMB:
				_check_elimination()
			if phase == PHASE_BOMB:
				_update_bomb_clock()
		PHASE_POST:
			if tick >= deadline_tick:
				if _match_limit_reached():
					_set_phase(PHASE_INTERMISSION, -1)
					_emit("match_end", {
						"ct_score": ct_score,
						"terrorist_score": terrorist_score,
					})
				else:
					_distribute_pending_round_money()
					_apply_halftime_if_needed()
					_start_round(false)
	return trace.slice(event_start)


func set_player_alive(
	player_id: String,
	alive: bool,
	position := Vector3.ZERO,
	killer_id := "",
) -> void:
	if not players.has(player_id):
		return
	var player: Dictionary = players[player_id]
	if bool(player.alive) == alive:
		return
	player.alive = alive
	players[player_id] = player
	if not alive:
		player.deaths = int(player.deaths) + 1
		players[player_id] = player
		if killer_id != "" and players.has(killer_id):
			grant_kill(killer_id)
		if bomb_owner == player_id and bomb_state in [BOMB_CARRIED, BOMB_PLANTING]:
			_cancel_plant("owner_died")
			player.has_c4 = false
			players[player_id] = player
			bomb_owner = ""
			bomb_state = BOMB_DROPPED
			bomb_position = position
			_emit("bomb_dropped", {"player_id": player_id, "position": position})
		if defuse_actor == player_id:
			_cancel_defuse("defuser_died")
		_emit("player_death", {"player_id": player_id, "killer_id": killer_id})
	if phase in [PHASE_LIVE, PHASE_BOMB]:
		_check_elimination()


func grant_kill(player_id: String) -> void:
	if not players.has(player_id):
		return
	var player: Dictionary = players[player_id]
	player.kills = int(player.kills) + 1
	player.money = mini(MAX_MONEY, int(player.money) + KILL_REWARD)
	players[player_id] = player
	_emit("money", {
		"player_id": player_id,
		"amount": KILL_REWARD,
		"reason": "kill",
		"balance": player.money,
	})


func pickup_bomb(player_id: String, position := Vector3.ZERO) -> bool:
	if (
		bomb_state != BOMB_DROPPED
		or not _is_alive_team(player_id, TEAM_T)
	):
		return false
	var player: Dictionary = players[player_id]
	player.has_c4 = true
	players[player_id] = player
	bomb_owner = player_id
	bomb_state = BOMB_CARRIED
	bomb_position = position
	_emit("bomb_picked_up", {"player_id": player_id})
	return true


func can_buy(
	player_id: String,
	inside_team_buy_zone: bool,
	map_has_buy_zones: bool,
) -> Dictionary:
	if not players.has(player_id):
		return {"allowed": false, "reason": "unknown_player"}
	var player: Dictionary = players[player_id]
	if not bool(player.alive):
		return {"allowed": false, "reason": "dead"}
	if phase not in [PHASE_FREEZE, PHASE_LIVE]:
		return {"allowed": false, "reason": "round_inactive"}
	# `inside_team_buy_zone` is the authoritative caller signal for either a
	# func_buyzone hull touch or OLD_CheckBuyZone's 200-HU spawn fallback.
	if not inside_team_buy_zone:
		return {"allowed": false, "reason": "outside_buy_zone"}
	if tick - round_started_tick > int(config.buy_ticks):
		return {"allowed": false, "reason": "buy_time_expired"}
	return {"allowed": true, "reason": "ok"}


func purchase(
	player_id: String,
	price: int,
	inside_team_buy_zone: bool,
	map_has_buy_zones: bool,
) -> Dictionary:
	var eligibility := can_buy(player_id, inside_team_buy_zone, map_has_buy_zones)
	if not bool(eligibility.allowed):
		return eligibility
	var player: Dictionary = players[player_id]
	if int(player.money) < price:
		return {"allowed": false, "reason": "insufficient_funds"}
	player.money = int(player.money) - price
	players[player_id] = player
	_emit("purchase", {
		"player_id": player_id,
		"price": price,
		"balance": player.money,
	})
	return {"allowed": true, "reason": "ok", "balance": player.money}


func purchase_item(
	player_id: String,
	item_id: String,
	price: int,
	inside_team_buy_zone: bool,
	map_has_buy_zones: bool,
) -> Dictionary:
	if not players.has(player_id):
		return {"allowed": false, "reason": "unknown_player"}
	var team := str(players[player_id].team)
	if item_id in T_ONLY_ITEMS and team != TEAM_T:
		return {"allowed": false, "reason": "wrong_team"}
	if item_id in CT_ONLY_ITEMS and team != TEAM_CT:
		return {"allowed": false, "reason": "wrong_team"}
	return purchase(
		player_id,
		price,
		inside_team_buy_zone,
		map_has_buy_zones,
	)


func set_defuser(player_id: String, has_defuser: bool) -> void:
	if players.has(player_id):
		var player: Dictionary = players[player_id]
		player.has_defuser = has_defuser
		players[player_id] = player


func seconds_left() -> float:
	if deadline_tick < 0:
		return 0.0
	return maxf(0.0, float(deadline_tick - tick) / float(TICK_RATE))


func action_progress() -> Dictionary:
	if plant_actor != "":
		return {
			"action": "plant",
			"actor": plant_actor,
			"elapsed_ticks": tick - plant_started_tick,
			"duration_ticks": int(config.plant_ticks),
		}
	if defuse_actor != "":
		return {
			"action": "defuse",
			"actor": defuse_actor,
			"elapsed_ticks": tick - defuse_started_tick,
			"duration_ticks": defuse_duration_ticks,
		}
	return {}


func scoreboard_snapshot() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ids: Array = players.keys()
	ids.sort()
	for player_id: String in ids:
		var player: Dictionary = players[player_id]
		rows.append({
			"id": player_id,
			"name": player_id,
			"team": player.team,
			"alive": player.alive,
			"score": player.kills,
			"deaths": player.deaths,
			"money": player.money,
			"bomb": player_id == bomb_owner and bool(player.has_c4),
		})
	return rows


func _start_round(distribute_accounts := true) -> void:
	if distribute_accounts:
		_distribute_pending_round_money()
	round_number += 1
	round_winner = ""
	round_reason = ""
	bomb_owner = ""
	bomb_state = BOMB_NONE
	bomb_position = Vector3.ZERO
	bomb_site_id = ""
	bomb_deadline_tick = -1
	next_beep_tick = -1
	next_frequency_tick = -1
	plant_actor = ""
	plant_started_tick = -1
	defuse_actor = ""
	defuse_started_tick = -1
	defuse_refresh_deadline_tick = -1
	for player_id: String in players:
		var player: Dictionary = players[player_id]
		player.alive = true
		player.has_c4 = false
		players[player_id] = player
	_assign_bomb()
	round_started_tick = tick
	_set_phase(PHASE_FREEZE, int(config.freeze_ticks))
	_emit("round_start", {
		"round": round_number,
		"bomb_owner": bomb_owner,
		"scoreboard": scoreboard_snapshot(),
	})


func _assign_bomb() -> void:
	var candidates: Array[String] = []
	for player_id: String in players:
		if str(players[player_id].team) == TEAM_T:
			candidates.append(player_id)
	candidates.sort()
	if candidates.is_empty():
		return
	bomb_owner = candidates[(round_number - 1) % candidates.size()]
	var owner: Dictionary = players[bomb_owner]
	owner.has_c4 = true
	players[bomb_owner] = owner
	bomb_state = BOMB_CARRIED


func _set_phase(next_phase: String, duration_ticks: int) -> void:
	phase = next_phase
	phase_started_tick = tick
	deadline_tick = tick + duration_ticks if duration_ticks >= 0 else -1
	_emit("phase", {
		"phase": phase,
		"deadline_tick": deadline_tick,
		"round": round_number,
	})


func _update_plant(raw: Variant) -> void:
	var request: Dictionary = raw if raw is Dictionary else {}
	var player_id := str(request.get("player_id", ""))
	var valid := (
		player_id != ""
		and player_id == bomb_owner
		and bomb_state in [BOMB_CARRIED, BOMB_PLANTING]
		and _is_alive_team(player_id, TEAM_T)
		and bool(request.get("attack", false))
		and bool(request.get("equipped_c4", false))
		and bool(request.get("grounded", false))
		and bool(request.get("in_bomb_site", false))
	)
	if not valid:
		_cancel_plant("interrupted")
		return
	if plant_actor == "":
		plant_actor = player_id
		plant_started_tick = tick
		bomb_state = BOMB_PLANTING
		bomb_site_id = str(request.get("site_id", ""))
		_emit("plant_start", {
			"player_id": player_id,
			"site_id": bomb_site_id,
			"duration_ticks": config.plant_ticks,
		})
	if tick - plant_started_tick < int(config.plant_ticks):
		return
	bomb_state = BOMB_PLANTED
	bomb_position = request.get("position", Vector3.ZERO)
	bomb_deadline_tick = tick + int(config.c4_ticks)
	deadline_tick = bomb_deadline_tick
	next_beep_tick = tick + 50
	frequency_interval_ticks = int(config.c4_ticks) / 4
	next_frequency_tick = tick
	beep_interval_ticks = 140
	beep_wave = 0
	var owner: Dictionary = players[player_id]
	owner.has_c4 = false
	players[player_id] = owner
	plant_actor = ""
	plant_started_tick = -1
	_set_phase(PHASE_BOMB, int(config.c4_ticks))
	_emit("bomb_planted", {
		"player_id": player_id,
		"site_id": bomb_site_id,
		"position": bomb_position,
		"deadline_tick": bomb_deadline_tick,
	})


func _cancel_plant(reason: String) -> void:
	if plant_actor == "":
		return
	_emit("plant_abort", {"player_id": plant_actor, "reason": reason})
	plant_actor = ""
	plant_started_tick = -1
	if bomb_state == BOMB_PLANTING:
		bomb_state = BOMB_CARRIED


func _update_defuse(raw: Variant) -> void:
	var request: Dictionary = raw if raw is Dictionary else {}
	var player_id := str(request.get("player_id", ""))
	var valid_use := (
		player_id != ""
		and bomb_state == BOMB_PLANTED
		and _is_alive_team(player_id, TEAM_CT)
		and bool(request.get("use", false))
		and bool(request.get("grounded", false))
		and bool(request.get("in_range", false))
		and bool(request.get("facing", false))
	)

	if defuse_actor == "":
		if not valid_use:
			return
		defuse_actor = player_id
		defuse_started_tick = tick
		defuse_refresh_deadline_tick = tick + DEFUSE_USE_REFRESH_TICKS
		defuse_duration_ticks = (
			int(config.defuse_kit_ticks)
			if bool(players[player_id].has_defuser)
			else int(config.defuse_ticks)
		)
		_emit("defuse_start", {
			"player_id": player_id,
			"has_kit": bool(players[player_id].has_defuser),
			"duration_ticks": defuse_duration_ticks,
			"use_refresh_ticks": DEFUSE_USE_REFRESH_TICKS,
		})
		return

	# PlayerUse calls CGrenade::Use continuously while +use keeps selecting the
	# C4. ReGameDLL refreshes m_fNextDefuse to time + 0.5 on each call. Losing
	# aim/range/releasing use therefore has a 0.5 s grace period; leaving the
	# ground or dying still aborts immediately in C4Think/SetPlayerAlive.
	if player_id == defuse_actor and valid_use:
		defuse_refresh_deadline_tick = tick + DEFUSE_USE_REFRESH_TICKS
	var actor_grounded := bool(request.get("grounded", true))
	if player_id == defuse_actor and not actor_grounded:
		_cancel_defuse("left_ground")
		return
	if tick > defuse_refresh_deadline_tick:
		_cancel_defuse("use_timeout")
		return
	if tick - defuse_started_tick < defuse_duration_ticks:
		return
	bomb_state = BOMB_DEFUSED
	var completed_by := defuse_actor
	defuse_actor = ""
	defuse_started_tick = -1
	defuse_refresh_deadline_tick = -1
	_emit("bomb_defused", {"player_id": completed_by})
	_end_round(
		TEAM_CT,
		"bomb_defused",
		REWARD_BOMB_DEFUSED,
		{TEAM_T: REWARD_BOMB_PLANTED},
	)


func _cancel_defuse(reason: String) -> void:
	if defuse_actor == "":
		return
	_emit("defuse_abort", {"player_id": defuse_actor, "reason": reason})
	defuse_actor = ""
	defuse_started_tick = -1
	defuse_duration_ticks = 0
	defuse_refresh_deadline_tick = -1


func _update_bomb_clock() -> void:
	if tick >= next_frequency_tick and beep_wave < 5:
		beep_wave += 1
		next_frequency_tick = tick + frequency_interval_ticks
		frequency_interval_ticks = maxi(1, int(round(float(frequency_interval_ticks) * 0.9)))
	if tick >= next_beep_tick:
		_emit("bomb_beep", {
			"wave": clampi(beep_wave, 1, 5),
			"position": bomb_position,
		})
		next_beep_tick += beep_interval_ticks
	if tick < bomb_deadline_tick:
		return
	_cancel_defuse("bomb_expired")
	bomb_state = BOMB_EXPLODED
	_emit("bomb_exploded", {
		"position": bomb_position,
		"damage": C4_DAMAGE,
		"radius_hu": C4_RADIUS_HU,
	})
	_end_round(TEAM_T, "target_bombed", REWARD_TARGET_BOMB)


func _check_elimination() -> void:
	if phase not in [PHASE_LIVE, PHASE_BOMB]:
		return
	var alive_t := _alive_count(TEAM_T)
	var alive_ct := _alive_count(TEAM_CT)
	if alive_ct == 0 and alive_t > 0:
		_end_round(
			TEAM_T,
			"terrorists_win",
			# This state model is the bomb-target ruleset (it assigns C4 every
			# round), where Terrorists_Win uses RR_BOMB_EXPLODED even before a
			# plant. Non-bomb scenarios need their own objective ruleset.
			REWARD_BOMB_EXPLODED,
		)
	elif alive_t == 0 and alive_ct > 0 and bomb_state != BOMB_PLANTED:
		_end_round(
			TEAM_CT,
			"cts_win",
			REWARD_BOMB_DEFUSED,
		)


func _end_round(
	winner: String,
	reason: String,
	winner_reward: int,
	team_supplements := {},
) -> void:
	if phase in [PHASE_POST, PHASE_INTERMISSION]:
		return
	_cancel_plant("round_end")
	_cancel_defuse("round_end")
	round_winner = winner
	round_reason = reason
	if winner == TEAM_T:
		terrorist_score += 1
	elif winner == TEAM_CT:
		ct_score += 1
	_queue_round_money(winner, winner_reward, team_supplements)
	_set_phase(PHASE_POST, int(config.restart_ticks))
	_emit("round_end", {
		"winner": winner,
		"reason": reason,
		"ct_score": ct_score,
		"terrorist_score": terrorist_score,
	})


func _queue_round_money(
	winner: String,
	winner_reward: int,
	team_supplements := {},
) -> void:
	var loser := TEAM_CT if winner == TEAM_T else TEAM_T

	# RestartRound uses one shared m_iLoserBonus and two consecutive-loss
	# counters. When a team breaks a streak longer than one round, the shared
	# value hands off at $1500 rather than resetting to the initial $1400.
	if int(loss_streak[winner]) > 1:
		loser_bonus = LOSER_BONUS_MIN
	loss_streak[winner] = 0
	loss_streak[loser] = int(loss_streak[loser]) + 1
	if int(loss_streak[loser]) > 1 and loser_bonus < LOSER_BONUS_MAX:
		loser_bonus = mini(LOSER_BONUS_MAX, loser_bonus + LOSER_BONUS_ADD)
	pending_team_accounts[winner] = (
		int(pending_team_accounts[winner])
		+ winner_reward
		+ int(team_supplements.get(winner, 0))
	)
	pending_team_accounts[loser] = (
		int(pending_team_accounts[loser])
		+ loser_bonus
		+ int(team_supplements.get(loser, 0))
	)
	_emit("round_accounts_queued", {
		TEAM_T: int(pending_team_accounts[TEAM_T]),
		TEAM_CT: int(pending_team_accounts[TEAM_CT]),
		"loser_bonus": loser_bonus,
	})


func _distribute_pending_round_money() -> void:
	if (
		int(pending_team_accounts[TEAM_T]) == 0
		and int(pending_team_accounts[TEAM_CT]) == 0
	):
		return
	for player_id: String in players:
		var player: Dictionary = players[player_id]
		var team := str(player.team)
		var amount := int(pending_team_accounts.get(team, 0))
		if amount <= 0:
			continue
		player.money = mini(MAX_MONEY, int(player.money) + amount)
		players[player_id] = player
		_emit("money", {
			"player_id": player_id,
			"amount": amount,
			"reason": "restart_round_account",
			"balance": player.money,
		})
	pending_team_accounts = {TEAM_T: 0, TEAM_CT: 0}


func _apply_halftime_if_needed() -> void:
	var max_rounds := int(config.max_rounds)
	if (
		not bool(config.halftime)
		or max_rounds <= 0
		or round_number != max_rounds / 2
	):
		return
	for player_id: String in players:
		var player: Dictionary = players[player_id]
		player.team = TEAM_CT if str(player.team) == TEAM_T else TEAM_T
		players[player_id] = player
	var old_ct := ct_score
	ct_score = terrorist_score
	terrorist_score = old_ct
	_emit("halftime", {"round": round_number})


func _match_limit_reached() -> bool:
	var max_rounds := int(config.max_rounds)
	return max_rounds > 0 and ct_score + terrorist_score >= max_rounds


func _alive_count(team: String) -> int:
	var count := 0
	for player: Dictionary in players.values():
		if str(player.team) == team and bool(player.alive):
			count += 1
	return count


func _is_alive_team(player_id: String, team: String) -> bool:
	return (
		players.has(player_id)
		and str(players[player_id].team) == team
		and bool(players[player_id].alive)
	)


func _emit(event_type: String, data := {}) -> void:
	var event := {
		"tick": tick,
		"type": event_type,
	}
	for key: Variant in data:
		event[key] = data[key]
	trace.append(event)
