class_name CS16ScenarioRules
extends RefCounted

## Source-faithful scenario classification and round-resolution helpers.
##
## The ordered objective checks mirror CHalfLifeMultiplay::CheckWinConditions:
## VIP, prison escape, bomb, elimination, then hostage rescue.  Keeping this
## policy outside Game lets the 100 Hz round kernel and deterministic bot tests
## share one authoritative contract.

const SCENARIO_BOMB := "bomb_defuse"
const SCENARIO_HOSTAGE := "hostage_rescue"
const SCENARIO_VIP := "escort_vip"
const SCENARIO_ESCAPE := "terrorist_escape"
const SCENARIO_ELIMINATION := "elimination"

const TEAM_T := "T"
const TEAM_CT := "CT"

const ESCAPE_REQUIRED_RATIO := 0.5
const HOSTAGE_REQUIRED_RESCUE_RATIO := 0.5

const REWARD_TARGET_SAVED := 3250
const REWARD_HOSTAGE_TIMEOUT := 3250
const REWARD_VIP_TIMEOUT := 3250
const REWARD_ESCAPE_SUCCESS := 3150
const REWARD_ESCAPE_PREVENTED := 3500
const REWARD_VIP_ESCAPED := 3500
const REWARD_VIP_ASSASSINATED := 3250
const REWARD_ALL_HOSTAGES_RESCUED := 2500

const TIMEOUTS := {
	SCENARIO_BOMB: {
		"winner": TEAM_CT,
		"reason": "target_saved",
		"team_reward": REWARD_TARGET_SAVED,
	},
	SCENARIO_HOSTAGE: {
		"winner": TEAM_T,
		"reason": "hostages_not_rescued",
		"team_reward": REWARD_HOSTAGE_TIMEOUT,
	},
	SCENARIO_VIP: {
		"winner": TEAM_T,
		"reason": "vip_not_escaped",
		"team_reward": REWARD_VIP_TIMEOUT,
	},
	SCENARIO_ESCAPE: {
		"winner": TEAM_CT,
		"reason": "terrorists_not_escaped",
		"team_reward": 0,
	},
	SCENARIO_ELIMINATION: {
		"winner": "",
		"reason": "round_draw",
		"team_reward": 0,
	},
}


static func classify_entities(entities: Array) -> Dictionary:
	var classes := {}
	for raw_entity: Variant in entities:
		if not raw_entity is Dictionary:
			continue
		var entity := raw_entity as Dictionary
		var classname := str(entity.get("classname", "")).to_lower()
		if classname.is_empty():
			continue
		classes[classname] = int(classes.get(classname, 0)) + 1

	var scenario := SCENARIO_ELIMINATION
	# A map should define one scenario, but use the same precedence as the
	# source win-condition checks when malformed/custom maps mix objectives.
	if classes.has("info_vip_start") or classes.has("func_vip_safetyzone"):
		scenario = SCENARIO_VIP
	elif classes.has("func_escapezone"):
		scenario = SCENARIO_ESCAPE
	elif classes.has("func_bomb_target") or classes.has("info_bomb_target"):
		scenario = SCENARIO_BOMB
	elif classes.has("hostage_entity") or classes.has("monster_scientist"):
		scenario = SCENARIO_HOSTAGE

	return {
		"scenario": scenario,
		"classes": classes,
		"has_brush_rescue": classes.has("func_hostage_rescue"),
		"legacy_rescue_points": int(classes.get("info_hostage_rescue", 0)),
		"hostage_count": (
			int(classes.get("hostage_entity", 0))
			+ int(classes.get("monster_scientist", 0))
		),
		"vip_start_count": int(classes.get("info_vip_start", 0)),
		"escape_zone_count": int(classes.get("func_escapezone", 0)),
		"bomb_target_count": (
			int(classes.get("func_bomb_target", 0))
			+ int(classes.get("info_bomb_target", 0))
		),
	}


static func timeout_result(scenario: String) -> Dictionary:
	return (TIMEOUTS.get(scenario, TIMEOUTS[SCENARIO_ELIMINATION]) as Dictionary).duplicate(true)


static func required_escape_count(starting_terrorists: int) -> int:
	if starting_terrorists <= 0:
		return 0
	return ceili(float(starting_terrorists) * ESCAPE_REQUIRED_RATIO)


static func escape_result(
	starting_terrorists: int,
	escaped_terrorists: int,
	alive_terrorists: int,
) -> Dictionary:
	if starting_terrorists <= 0:
		return {}
	var escaped := clampi(escaped_terrorists, 0, starting_terrorists)
	var ratio := float(escaped) / float(starting_terrorists)
	if escaped >= required_escape_count(starting_terrorists):
		return {
			"winner": TEAM_T,
			"reason": "terrorists_escaped",
			"team_reward": REWARD_ESCAPE_SUCCESS,
			"escape_ratio": ratio,
		}
	if alive_terrorists <= 0:
		return {
			"winner": TEAM_CT,
			"reason": "terrorists_stopped",
			"team_reward": int((1.0 - ratio) * float(REWARD_ESCAPE_PREVENTED)),
			"escape_ratio": ratio,
		}
	return {}


static func hostage_result(
	original_hostages: int,
	alive_hostages: int,
	rescued_hostages: int,
) -> Dictionary:
	if original_hostages <= 0 or alive_hostages > 0:
		return {}
	var rescued := clampi(rescued_hostages, 0, original_hostages)
	var ratio := float(rescued) / float(original_hostages)
	if ratio + 0.000001 < HOSTAGE_REQUIRED_RESCUE_RATIO:
		return {}
	return {
		"winner": TEAM_CT,
		"reason": "all_hostages_rescued",
		"team_reward": REWARD_ALL_HOSTAGES_RESCUED,
		"rescue_ratio": ratio,
	}


static func vip_result(vip_alive: bool, vip_escaped: bool) -> Dictionary:
	if vip_escaped:
		return {
			"winner": TEAM_CT,
			"reason": "vip_escaped",
			"team_reward": REWARD_VIP_ESCAPED,
		}
	if not vip_alive:
		return {
			"winner": TEAM_T,
			"reason": "vip_assassinated",
			"team_reward": REWARD_VIP_ASSASSINATED,
		}
	return {}

