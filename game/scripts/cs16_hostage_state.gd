class_name CS16HostageState
extends RefCounted

const ScenarioRulesScript = preload("res://scripts/cs16_scenario_rules.gd")

const TICK_RATE := 100
const TEAM_CT := "CT"
const MAX_HEALTH := 100.0
const USE_COOLDOWN_TICKS := 1 * TICK_RATE
const STUCK_RELEASE_TICKS := 5 * TICK_RATE
const THINK_INTERVAL_TICKS := 10
const RADAR_INTERVAL_TICKS := 1 * TICK_RATE
const USE_RADIUS_HU := 64.0
const USE_VIEW_DOT := 0.7
const LEGACY_RESCUE_RADIUS_HU := 256.0
const FOLLOW_WAIT_DISTANCE_HU := 500.0
const FOLLOW_WAIT_MAX_TICKS := 10 * TICK_RATE
const FOLLOW_WAIT_INHIBIT_TICKS := 3 * TICK_RATE
const HULL_MINS_HU := Vector3(-10.0, -10.0, 0.0)
const HULL_MAXS_HU := Vector3(10.0, 10.0, 62.0)

const FIRST_USE_PLAYER_REWARD := 150
const FIRST_USE_TEAM_REWARD := 100
const RESCUE_PLAYER_REWARD := 1000
const RESCUE_NEXT_ROUND_CT_REWARD := 750

const HITGROUP_MULTIPLIER := {
	"generic": 1.75,
	"head": 2.50,
	"chest": 1.50,
	"stomach": 1.75,
	"left_arm": 0.75,
	"right_arm": 0.75,
	"left_leg": 0.60,
	"right_leg": 0.60,
}

var hostages := {}
var tick := 0
var original_count := 0
var rescued_count := 0
var trace: Array[Dictionary] = []
var _round_snapshot := {}


func register_hostage(
	hostage_id: String,
	position_hu: Vector3,
	skin := 0,
	yaw_degrees := 0.0,
) -> void:
	if hostage_id.is_empty() or hostages.has(hostage_id):
		return
	hostages[hostage_id] = {
		"id": hostage_id,
		"spawn_position_hu": position_hu,
		"position_hu": position_hu,
		"spawn_yaw_degrees": yaw_degrees,
		"yaw_degrees": yaw_degrees,
		"skin": skin,
		"health": MAX_HEALTH,
		"alive": true,
		"rescued": false,
		"following": false,
		"leader_id": "",
		"ever_used": false,
		"next_use_tick": 0,
		"stuck_since_tick": -1,
		"last_think_tick": 0,
	}
	original_count = hostages.size()
	_round_snapshot = hostages.duplicate(true)


func set_spawn_position(hostage_id: String, position_hu: Vector3) -> bool:
	if not hostages.has(hostage_id):
		return false
	var hostage: Dictionary = hostages[hostage_id]
	hostage.spawn_position_hu = position_hu
	hostage.position_hu = position_hu
	hostages[hostage_id] = hostage
	_round_snapshot = hostages.duplicate(true)
	return true


func start_round() -> void:
	tick = 0
	rescued_count = 0
	trace.clear()
	hostages = _round_snapshot.duplicate(true)
	for hostage_id: String in hostages:
		var hostage: Dictionary = hostages[hostage_id]
		hostage.health = MAX_HEALTH
		hostage.alive = true
		hostage.rescued = false
		hostage.following = false
		hostage.leader_id = ""
		hostage.ever_used = false
		hostage.next_use_tick = 0
		hostage.stuck_since_tick = -1
		hostage.last_think_tick = 0
		hostage.position_hu = hostage.spawn_position_hu
		hostage.yaw_degrees = hostage.spawn_yaw_degrees
		hostages[hostage_id] = hostage
	_emit("hostages_reset", {"count": original_count})


func advance_tick() -> Array[Dictionary]:
	var event_start := trace.size()
	tick += 1
	if tick % THINK_INTERVAL_TICKS == 0:
		for hostage_id: String in hostages:
			var hostage: Dictionary = hostages[hostage_id]
			hostage.last_think_tick = tick
			hostages[hostage_id] = hostage
	return trace.slice(event_start)


func use_hostage(
	hostage_id: String,
	actor_id: String,
	actor_team: String,
	actor_alive := true,
) -> Dictionary:
	if (
		not hostages.has(hostage_id)
		or actor_id.is_empty()
		or actor_team != TEAM_CT
		or not actor_alive
	):
		return {}
	var hostage: Dictionary = hostages[hostage_id]
	if (
		not bool(hostage.alive)
		or bool(hostage.rescued)
		or tick < int(hostage.next_use_tick)
	):
		return {}
	var first_use := not bool(hostage.ever_used)
	var following := not (
		bool(hostage.following)
		and str(hostage.leader_id) == actor_id
	)
	hostage.following = following
	hostage.leader_id = actor_id if following else ""
	hostage.ever_used = true
	hostage.next_use_tick = tick + USE_COOLDOWN_TICKS
	hostage.stuck_since_tick = -1
	hostages[hostage_id] = hostage
	var result := {
		"hostage_id": hostage_id,
		"actor_id": actor_id,
		"following": following,
		"first_use": first_use,
		"player_reward": FIRST_USE_PLAYER_REWARD if first_use else 0,
		"team_reward": FIRST_USE_TEAM_REWARD if first_use else 0,
	}
	_emit("hostage_follow" if following else "hostage_stop", result)
	return result


func release_invalid_leader(hostage_id: String, leader_alive: bool) -> bool:
	if not hostages.has(hostage_id):
		return false
	var hostage: Dictionary = hostages[hostage_id]
	if not bool(hostage.following) or leader_alive:
		return false
	_stop_following(hostage_id, hostage, "leader_died")
	return true


func update_stuck(hostage_id: String, stuck: bool) -> bool:
	if not hostages.has(hostage_id):
		return false
	var hostage: Dictionary = hostages[hostage_id]
	if not bool(hostage.following):
		return false
	if not stuck:
		hostage.stuck_since_tick = -1
		hostages[hostage_id] = hostage
		return false
	if int(hostage.stuck_since_tick) < 0:
		hostage.stuck_since_tick = tick
		hostages[hostage_id] = hostage
		return false
	if tick - int(hostage.stuck_since_tick) <= STUCK_RELEASE_TICKS:
		return false
	_stop_following(hostage_id, hostage, "stuck")
	return true


func apply_damage(
	hostage_id: String,
	raw_damage: float,
	hitgroup := "generic",
	attacker_id := "",
) -> Dictionary:
	if not hostages.has(hostage_id) or raw_damage <= 0.0:
		return {}
	var hostage: Dictionary = hostages[hostage_id]
	if not bool(hostage.alive) or bool(hostage.rescued):
		return {}
	var multiplier := float(
		HITGROUP_MULTIPLIER.get(hitgroup, HITGROUP_MULTIPLIER.generic)
	)
	var scaled_damage := raw_damage * multiplier
	var actual_damage := minf(float(hostage.health), scaled_damage)
	hostage.health = maxf(0.0, float(hostage.health) - scaled_damage)
	var killed := float(hostage.health) <= 0.0
	if killed:
		hostage.alive = false
		hostage.following = false
		hostage.leader_id = ""
	var money_penalty := (
		int(round(20.0 * (-25.0 - actual_damage)))
		if killed
		else -int(round(20.0 * actual_damage))
	)
	hostages[hostage_id] = hostage
	var result := {
		"hostage_id": hostage_id,
		"attacker_id": attacker_id,
		"hitgroup": hitgroup,
		"raw_damage": raw_damage,
		"actual_damage": actual_damage,
		"killed": killed,
		"money_penalty": money_penalty,
		"health": hostage.health,
	}
	_emit("hostage_killed" if killed else "hostage_hurt", result)
	return result


func rescue(hostage_id: String, rescuer_id: String) -> Dictionary:
	if not hostages.has(hostage_id):
		return {}
	var hostage: Dictionary = hostages[hostage_id]
	if not bool(hostage.alive) or bool(hostage.rescued):
		return {}
	hostage.rescued = true
	hostage.following = false
	hostage.leader_id = ""
	hostages[hostage_id] = hostage
	rescued_count += 1
	var result := {
		"hostage_id": hostage_id,
		"rescuer_id": rescuer_id,
		"player_reward": RESCUE_PLAYER_REWARD,
		"next_round_ct_reward": RESCUE_NEXT_ROUND_CT_REWARD,
		"rescued_count": rescued_count,
	}
	_emit("hostage_rescued", result)
	return result


func set_position(hostage_id: String, position_hu: Vector3) -> void:
	if not hostages.has(hostage_id):
		return
	var hostage: Dictionary = hostages[hostage_id]
	hostage.position_hu = position_hu
	hostages[hostage_id] = hostage


func round_result() -> Dictionary:
	return ScenarioRulesScript.hostage_result(
		original_count,
		alive_unrescued_count(),
		rescued_count,
	)


func alive_unrescued_count() -> int:
	var count := 0
	for hostage: Dictionary in hostages.values():
		if bool(hostage.alive) and not bool(hostage.rescued):
			count += 1
	return count


func snapshot() -> Dictionary:
	return {
		"tick": tick,
		"original_count": original_count,
		"rescued_count": rescued_count,
		"alive_unrescued_count": alive_unrescued_count(),
		"hostages": hostages.duplicate(true),
	}


func _stop_following(
	hostage_id: String,
	hostage: Dictionary,
	reason: String,
) -> void:
	var previous_leader := str(hostage.leader_id)
	hostage.following = false
	hostage.leader_id = ""
	hostage.stuck_since_tick = -1
	hostages[hostage_id] = hostage
	_emit("hostage_stop", {
		"hostage_id": hostage_id,
		"actor_id": previous_leader,
		"following": false,
		"reason": reason,
	})


func _emit(event_type: String, data := {}) -> void:
	var event := {"tick": tick, "type": event_type}
	for key: Variant in data:
		event[key] = data[key]
	trace.append(event)
