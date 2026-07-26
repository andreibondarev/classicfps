extends SceneTree

const Registry := preload("res://scripts/cs16_weapon_registry.gd")
const Ballistics := preload("res://scripts/cs16_ballistics.gd")
const WeaponClock := preload("res://scripts/cs16_weapon_clock.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var errors := Registry.validation_errors(true)
	for error in errors:
		_fail(error)
	_check(Registry.ROSTER.size() == 29, "all 29 CS 1.6 weapon IDs are registered")
	_check(Registry.WEAPONS.size() == 29, "registry contains no partial or extra weapon rows")
	_check(Registry.EQUIPMENT.size() == 9, "classic equipment and shield catalog is complete")
	_check(Registry.can_buy("ak47", "T"), "T can buy AK-47")
	_check(not Registry.can_buy("ak47", "CT"), "CT cannot buy AK-47")
	_check(Registry.can_buy("m4a1", "CT"), "CT can buy M4A1")
	_check(not Registry.can_buy("m4a1", "T"), "T cannot buy M4A1")
	_check(Registry.can_buy("awp", "T") and Registry.can_buy("awp", "CT"), "AWP is shared")
	_check(int(Registry.definition("flashbang").reserve_max) == 2, "flashbang carry maximum is two")
	_check(int(Registry.definition("m249").magazine) == 100, "M249 magazine is 100 rounds")
	_check(int(Registry.definition("p90").reserve_max) == 100, "P90 reserve cap is 100 rounds")
	_check(
		int(Registry.definition("c4").damage) == 500
		and is_equal_approx(float(Registry.definition("c4").range_units), 1750.0),
		"C4 registry separates 500 base damage from 1750 HU effective radius",
	)

	for weapon_name: String in Registry.ROSTER:
		var item := Registry.definition(weapon_name)
		var timing := WeaponClock.timing(weapon_name)
		_check(not timing.is_empty(), "%s has a deterministic clock profile" % weapon_name)
		_check(
			WeaponClock.ticks_from_seconds(float(item.primary))
				== int(ceil(float(item.primary) * 100.0 - 0.000001)),
			"%s primary cycle quantizes at 100 Hz" % weapon_name,
		)
		if int(item.damage) > 0 and str(item.category) not in ["melee", "grenade", "objective"]:
			var profile := Ballistics.weapon_profile(weapon_name)
			_check(not profile.is_empty(), "%s has a live ballistic profile" % weapon_name)
			_check(int(profile.base_damage) == int(item.damage), "%s damage reaches ballistics" % weapon_name)
			_check(is_equal_approx(float(profile.range_modifier), float(item.range_modifier)), "%s range modifier reaches ballistics" % weapon_name)

	var ammo := Registry.initial_ammunition()
	_check(ammo.size() == 28, "every non-knife weapon has persistent ammunition state")
	_check(int(ammo.ak47.clip) == 30 and int(ammo.ak47.reserve) == 90, "AK defaults are preserved")
	_check(int(ammo.deagle.clip) == 7 and int(ammo.deagle.reserve) == 35, "Deagle defaults are preserved")

	if failures.is_empty():
		print("GAME_WEAPON_REGISTRY_TEST_PASS")
		quit(0)
	else:
		print("GAME_WEAPON_REGISTRY_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	push_error("WEAPON REGISTRY TEST: " + message)
