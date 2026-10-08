extends SceneTree

const BuyPlan := preload("res://scripts/cs16_bot_buy_plan.gd")

var failures: Array[String] = []


func _init() -> void:
	_assert_pistol_rounds()
	_assert_full_buys()
	_assert_survivor_supplements()
	_assert_helmet_and_utility()
	_assert_rich_bots_stop_hoarding()
	_assert_determinism()
	_assert_presentation_candidates()
	if failures.is_empty():
		print("GAME_BOT_BUY_PLAN_TEST_PASS")
		quit(0)
	else:
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("BOT BUY PLAN TEST: " + message)


func _assert_presentation_candidates() -> void:
	for team: String in ["T", "CT"]:
		for index in range(10):
			var prepared := BuyPlan.presentation_weapons(team, index)
			_check(prepared.has("glock18" if team == "T" else "usp"), "preparation covers starting pistol")
			_check(prepared.has("awp") == (index % 5 == 0), "preparation uses the actual sniper role")
			for money in [0, 1500, 2150, 2250, 2500, 2900, 3100, 4000, 4750, 5600, 6000, 16000]:
				for armor in [0, 100]:
					for has_primary: bool in [false, true]:
						for purchase: Dictionary in BuyPlan.build(team, money, index, has_primary, armor, false):
							var definition := CS16WeaponRegistry.definition(str(purchase.id))
							if not definition.is_empty() and int(definition.slot) in [1, 2]:
								_check(prepared.has(str(purchase.id)), "preparation covers every possible primary purchase")
			prepared.clear()
			_check(not BuyPlan.presentation_weapons(team, index).is_empty(), "preparation candidates are caller-owned")


func _ids(plan: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in plan:
		result.append(str(row.id))
	return result


func _total(plan: Array[Dictionary]) -> int:
	var result := 0
	for row: Dictionary in plan:
		result += int(row.price)
	return result


func _assert_pistol_rounds() -> void:
	var terrorist := BuyPlan.build("T", 800, 0, false, 0, false)
	var ct_kit := BuyPlan.build("CT", 800, 0, false, 0, false)
	var ct_armor := BuyPlan.build("CT", 800, 1, false, 0, false)
	_check(
		_ids(terrorist) == ["kevlar"] and _total(terrorist) == 650,
		"T pistol bot keeps its Glock and buys affordable armor",
	)
	_check(
		_ids(ct_kit) == ["kevlar"],
		"kit-role CT does not sacrifice pistol-round armor when both are unaffordable",
	)
	_check(
		_ids(ct_armor) == ["kevlar"],
		"non-kit CT buys pistol-round armor",
	)


func _assert_full_buys() -> void:
	var terrorist := BuyPlan.build("T", 4000, 0, false, 0, false)
	var ct := BuyPlan.build("CT", 4000, 0, false, 0, false)
	_check(
		_ids(terrorist) == ["ak47", "assaultsuit"] and _total(terrorist) == 3500,
		"T full buy prioritizes AK, then upgrades armor to a helmet",
	)
	_check(
		_ids(ct) == ["m4a1", "kevlar", "defuser"] and _total(ct) == 3950,
		"CT full buy funds M4, kevlar, and its assigned kit",
	)


func _assert_survivor_supplements() -> void:
	var survivor := BuyPlan.build("CT", 2200, 2, true, 0, false)
	_check(
		_ids(survivor) == ["assaultsuit", "defuser", "hegrenade"],
		"surviving rifle CT replaces armor and buys a kit without rebuying a primary",
	)
	for money in [0, 199, 650, 800, 1500, 2200, 4000, 6000, 9000, 16000]:
		for index in range(5):
			for team: String in ["T", "CT"]:
				for has_primary: bool in [false, true]:
					var plan := BuyPlan.build(
						team,
						money,
						index,
						has_primary,
						0,
						false,
					)
					_check(
						_total(plan) <= money,
						"buy plan never overspends $%d (%s idx %d primary %s)"
						% [money, team, index, has_primary],
					)


func _assert_helmet_and_utility() -> void:
	var helmeted := BuyPlan.build("T", 5000, 1, false, 0, false)
	_check(
		"assaultsuit" in _ids(helmeted),
		"a funded bot buys the helmet variant of armor",
	)
	_check(
		"hegrenade" in _ids(helmeted),
		"spare money after the rifle and armor buys an HE grenade",
	)
	var utility := BuyPlan.build("T", 3400, 1, true, 100, true)
	_check(
		_ids(utility) == ["hegrenade", "flashbang", "smokegrenade"],
		"an armored survivor spends its surplus on utility, not on nothing",
	)
	var broke := BuyPlan.build("T", 850, 1, true, 100, true)
	_check(
		_ids(broke).is_empty(),
		"a bot below the utility reserve saves instead of buying grenades",
	)


func _assert_rich_bots_stop_hoarding() -> void:
	var rich_sniper := BuyPlan.build("T", 16000, 0, true, 100, false)
	_check(
		_ids(rich_sniper)[0] == "awp",
		"the seeded AWP role upgrades its primary when rich (got %s)"
		% str(_ids(rich_sniper)),
	)
	_check(
		"assaultsuit" in _ids(rich_sniper) and "hegrenade" in _ids(rich_sniper),
		"a capped bot also refreshes armor and utility",
	)
	var rich_rifle := BuyPlan.build("CT", 16000, 1, true, 100, false)
	_check(
		_ids(rich_rifle)[0] == "m4a1",
		"a capped non-sniper CT re-buys the best team rifle",
	)
	var saving := BuyPlan.build("CT", 5000, 1, true, 100, false)
	_check(
		"m4a1" not in _ids(saving),
		"below the upgrade threshold a bot keeps the primary it already owns",
	)


func _assert_determinism() -> void:
	for index in range(5):
		var first := BuyPlan.build("T", 7300, index, false, 0, false)
		var second := BuyPlan.build("T", 7300, index, false, 0, false)
		_check(
			_ids(first) == _ids(second),
			"identical inputs produce an identical plan for bot %d" % index,
		)
