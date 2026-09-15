class_name CS16BotBuyPlan
extends RefCounted

## Deterministic offline-bot buy priorities for the classic 5v5 bomb ruleset.
## The plan only returns affordable items; CS16RoundState remains authoritative
## for team restrictions, buy time, zone eligibility, and money mutation.

const TEAM_T := "T"
const TEAM_CT := "CT"

const KEVLAR_PRICE := 650
const ASSAULTSUIT_PRICE := 1000
const DEFUSER_PRICE := 200
const HE_PRICE := 300
const FLASHBANG_PRICE := 200
const SMOKE_PRICE := 300

## Cash a bot keeps back for the next round before it spends on utility.
const UTILITY_RESERVE := 700
## Smoke is the last thing a 1.6 bot buys, and only out of genuine surplus.
const SMOKE_RESERVE := 2000
## The second flashbang (carry_max 2) is pure surplus spending.
const SECOND_FLASHBANG_RESERVE := 3000
## A bot that already owns a primary only re-buys once it is genuinely rich;
## below this it keeps the gun it has instead of trading it every round.
const UPGRADE_MONEY := 6000
## Approaching the $16000 cap the bot stops hoarding and refreshes armor it may
## already own — `build` cannot observe a helmet unless the caller passes one.
const SURPLUS_MONEY := 8000

const T_PRIMARIES := [
	{"id": "ak47", "price": 2500},
	{"id": "galil", "price": 2000},
	{"id": "mp5", "price": 1500},
]
const CT_PRIMARIES := [
	{"id": "m4a1", "price": 3100},
	{"id": "famas", "price": 2250},
	{"id": "mp5", "price": 1500},
]
const AWP := {"id": "awp", "price": 4750}


static func presentation_weapons(team: String, bot_index: int) -> Array[String]:
	# Loading uses the same candidate list as buying, including the assigned
	# sniper role. This is not a purchase and must never change any accounts.
	var result: Array[String] = ["glock18" if team == TEAM_T else "usp"]
	for candidate: Dictionary in _primary_candidates(team, bot_index % 5 == 0):
		result.append(str(candidate.id))
	return result


static func build(
	team: String,
	money: int,
	bot_index: int,
	has_primary: bool,
	armor_points: int,
	has_defuser: bool,
	has_helmet := false,
) -> Array[Dictionary]:
	var remaining := maxi(0, money)
	var result: Array[Dictionary] = []
	var wants_kit := team == TEAM_CT and not has_defuser and bot_index % 2 == 0
	var kit_reserve := DEFUSER_PRICE if wants_kit else 0
	# Armor is reserved at kevlar price only: a 1.6 bot buys the rifle first and
	# upgrades to the helmet with what is left, it never downgrades the gun.
	var armor_reserve := KEVLAR_PRICE if armor_points <= 0 else 0
	# One AWP role per five bots, chosen by index so the pick stays identical
	# across replays without consulting an RNG.
	var awp_role := bot_index % 5 == 0
	var candidates := _primary_candidates(team, awp_role)

	if not has_primary or remaining >= UPGRADE_MONEY:
		for raw_candidate: Variant in candidates:
			var candidate: Dictionary = raw_candidate
			var price := int(candidate.price)
			if price + kit_reserve + armor_reserve <= remaining:
				result.append(candidate.duplicate())
				remaining -= price
				break

	if armor_points <= 0 or (not has_helmet and remaining >= SURPLUS_MONEY):
		if not has_helmet and remaining >= ASSAULTSUIT_PRICE + kit_reserve:
			result.append({"id": "assaultsuit", "price": ASSAULTSUIT_PRICE})
			remaining -= ASSAULTSUIT_PRICE
		elif armor_points <= 0 and remaining >= KEVLAR_PRICE:
			result.append({"id": "kevlar", "price": KEVLAR_PRICE})
			remaining -= KEVLAR_PRICE

	if wants_kit and remaining >= DEFUSER_PRICE:
		result.append({"id": "defuser", "price": DEFUSER_PRICE})
		remaining -= DEFUSER_PRICE

	if remaining - HE_PRICE >= UTILITY_RESERVE:
		result.append({"id": "hegrenade", "price": HE_PRICE})
		remaining -= HE_PRICE
	if remaining - FLASHBANG_PRICE >= UTILITY_RESERVE:
		result.append({"id": "flashbang", "price": FLASHBANG_PRICE})
		remaining -= FLASHBANG_PRICE
	if remaining - SMOKE_PRICE >= SMOKE_RESERVE:
		result.append({"id": "smokegrenade", "price": SMOKE_PRICE})
		remaining -= SMOKE_PRICE
	if remaining - FLASHBANG_PRICE >= SECOND_FLASHBANG_RESERVE:
		result.append({"id": "flashbang", "price": FLASHBANG_PRICE})
		remaining -= FLASHBANG_PRICE
	return result


static func _primary_candidates(team: String, awp_role: bool) -> Array:
	var candidates: Array = []
	if awp_role:
		candidates.append(AWP)
	candidates.append_array(T_PRIMARIES if team == TEAM_T else CT_PRIMARIES)
	return candidates
