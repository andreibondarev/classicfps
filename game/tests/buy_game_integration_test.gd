extends SceneTree

const Registry = preload("res://scripts/cs16_weapon_registry.gd")
const RoundState = preload("res://scripts/cs16_round_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BUY GAME INTEGRATION TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.set_physics_process(false)
	game.start_match()
	# Catalog semantics are independent of map geometry. The existing round
	# integration test separately proves the imported T/CT buy brush bounds.
	game.buy_regions.clear()

	_assert_catalog_contract(game)
	_assert_every_buyable_weapon(game)
	_assert_equipment(game)
	_assert_ammunition(game)
	_assert_rejections_do_not_charge(game)
	_assert_slot_replacement_and_grenade_caps(game)

	if failures.is_empty():
		print("GAME_BUY_INTEGRATION_TEST_PASS")
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_BUY_INTEGRATION_TEST_FAIL (%d)" % failures.size())
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)


func _assert_catalog_contract(game: Node) -> void:
	for alias in [
		"glock", "mp5navy", "elites", "vest", "vesthelm",
		"kevlar_helmet", "flash", "hegren", "sgren", "nightvision",
		"primammo", "secammo", "ammo_primary", "ammo_secondary",
	]:
		_check(game.BUY_ITEM_ALIASES.has(alias), "classic alias is routed: %s" % alias)
	for weapon_name: String in Registry.ROSTER:
		if weapon_name in ["knife", "c4"]:
			_check(
				not game.BUY_GRANTS.has(weapon_name),
				"non-purchasable roster item stays out of the buy catalog: %s" % weapon_name,
			)
		else:
			_check(
				game.BUY_GRANTS.get(weapon_name, "") == weapon_name,
				"buy grant uses canonical Player ID: %s" % weapon_name,
			)
			_check(
				int(game.BUY_PRICES.get(weapon_name, -1))
				== int(Registry.WEAPONS[weapon_name].price),
				"buy price matches registry for %s" % weapon_name,
			)
	for ammo_name: String in Registry.AMMO:
		var ammo_id := "ammo_%s" % ammo_name
		_check(
			game.BUY_GRANTS.get(ammo_id, "") == ammo_id,
			"ammo grant uses canonical Player ID: %s" % ammo_id,
		)
		_check(
			int(game.BUY_PRICES.get(ammo_id, -1))
			== int(Registry.AMMO[ammo_name].price),
			"ammo price matches registry for %s" % ammo_id,
		)


func _assert_every_buyable_weapon(game: Node) -> void:
	var accepted := 0
	for weapon_name: String in Registry.ROSTER:
		if weapon_name in ["knife", "c4"]:
			continue
		var definition: Dictionary = Registry.WEAPONS[weapon_name]
		var team := _legal_team_for(weapon_name, definition)
		_reset_buyer(game, team)
		var before := int(game.money)
		var result: Dictionary = game._purchase_and_grant(weapon_name)
		_check(bool(result.allowed), "%s is granted to its legal %s team" % [weapon_name, team])
		_check(
			int(game.money) == before - int(definition.price),
			"%s charges its exact catalog price" % weapon_name,
		)
		_check(
			bool(game.player.owned_weapons.get(weapon_name, false)),
			"%s reaches Player ownership" % weapon_name,
		)
		accepted += 1
	_check(accepted == 27, "all 27 purchasable entries in the 29-ID roster are covered")


func _assert_equipment(game: Node) -> void:
	for item_name: String in [
		"kevlar", "helmet", "assaultsuit", "nvgs", "defuser", "shield",
	]:
		var definition: Dictionary = Registry.EQUIPMENT[item_name]
		var team := str(definition.team[0])
		_reset_buyer(game, team)
		var before := int(game.money)
		var result: Dictionary = game._purchase_and_grant(item_name)
		_check(bool(result.allowed), "%s equipment grant succeeds" % item_name)
		_check(
			int(game.money) == before - int(definition.price),
			"%s charges only after Player accepts it" % item_name,
		)
		if item_name == "assaultsuit":
			_check(
				bool(game.player.equipment.kevlar)
				and bool(game.player.equipment.helmet)
				and game.player.armor == 100
				and game.player.has_helmet,
				"assault suit grants kevlar, helmet, and armor",
			)
		else:
			_check(
				bool(game.player.equipment[item_name]),
				"%s flag is owned after purchase" % item_name,
			)
		if item_name == "defuser":
			_check(
				bool(game.round_state.players.player.has_defuser),
				"defuser ownership reaches authoritative round state",
			)


func _assert_ammunition(game: Node) -> void:
	# The VGUI aliases resolve caliber and price from the held slot, rather than
	# using the old hard-coded $60/$40 placeholders.
	_reset_buyer(game, RoundState.TEAM_T)
	_check(game.player.grant_item("ak47"), "ammo fixture owns a primary")
	_check(game.player.grant_item("deagle"), "ammo fixture owns a secondary")
	game.player.ammunition.ak47.reserve = 0
	game.player.ammunition.deagle.reserve = 0
	game.player.active_weapon = "ak47"
	game.player.clip = int(game.player.ammunition.ak47.clip)
	game.player.reserve = 0
	var context: Dictionary = game._buy_menu_context()
	_check(int(context.primary_ammo_price) == 80, "AK primary ammo menu price is $80")
	_check(int(context.secondary_ammo_price) == 40, "Deagle secondary ammo menu price is $40")
	var before := int(game.money)
	var primary: Dictionary = game._purchase_and_grant("primammo")
	_check(
		bool(primary.allowed)
		and str(primary.grant) == "ammo_762nato"
		and int(game.player.ammunition.ak47.reserve) == 30
		and int(game.money) == before - 80,
		"primary alias grants one exact 7.62 NATO box before charging $80",
	)
	_check(
		game.hud.reserve_label.text == "30",
		"active-weapon ammo purchase reaches the classic HUD reserve counter",
	)
	before = int(game.money)
	var secondary: Dictionary = game._purchase_and_grant("secammo")
	_check(
		bool(secondary.allowed)
		and str(secondary.grant) == "ammo_50ae"
		and int(game.player.ammunition.deagle.reserve) == 7
		and int(game.money) == before - 40,
		"secondary alias grants one exact .50 AE box before charging $40",
	)
	_check(
		game.hud.money_label.text == "$%d" % game.money,
		"successful buy updates the classic HUD money state",
	)

	# Direct canonical ammo grants cover every source caliber and price.
	for ammo_name: String in Registry.AMMO:
		var compatible_weapon := _weapon_for_ammo(ammo_name)
		var team := str(Registry.WEAPONS[compatible_weapon].team[0])
		_reset_buyer(game, team)
		_check(game.player.grant_item(compatible_weapon), "fixture owns %s" % compatible_weapon)
		game.player.ammunition[compatible_weapon].reserve = 0
		var result: Dictionary = game._purchase_and_grant("ammo_%s" % ammo_name)
		_check(bool(result.allowed), "canonical %s ammo box is purchasable" % ammo_name)
		_check(
			int(game.player.ammunition[compatible_weapon].reserve)
			== int(Registry.AMMO[ammo_name].box),
			"%s grants its exact box count" % ammo_name,
		)


func _assert_rejections_do_not_charge(game: Node) -> void:
	_reset_buyer(game, RoundState.TEAM_T)
	var before := int(game.money)
	_check(
		not bool(game._purchase_and_grant("not_a_real_item").allowed)
		and int(game.money) == before,
		"unknown Player grant rejects before charge",
	)
	_check(
		not bool(game._purchase_and_grant("m4a1").allowed)
		and int(game.money) == before,
		"wrong-team weapon rejects before charge",
	)
	_check(
		not bool(game._purchase_and_grant("primammo").allowed)
		and int(game.money) == before,
		"slot ammo without an owned slot weapon rejects before charge",
	)
	_set_money(game, 100)
	var inventory_before: Dictionary = game._player_inventory_snapshot()
	_check(
		not bool(game._purchase_and_grant("ak47").allowed)
		and int(game.money) == 100
		and game._player_inventory_snapshot() == inventory_before,
		"insufficient funds rejects before Player mutation and charge",
	)

	_reset_buyer(game, RoundState.TEAM_T)
	_check(game.player.grant_item("ak47"), "full-ammo fixture owns AK-47")
	game.player.ammunition.ak47.reserve = int(Registry.AMMO["762nato"].reserve_max)
	var before_full_ammo := int(game.money)
	_check(
		not bool(game._purchase_and_grant("primammo").allowed)
		and int(game.money) == before_full_ammo
		and int(game.player.ammunition.ak47.reserve)
			== int(Registry.AMMO["762nato"].reserve_max),
		"full backpack ammo rejects before charge and remains capped",
	)
	_reset_buyer(game, RoundState.TEAM_T)
	_check(bool(game._purchase_and_grant("nvgs").allowed), "first NVG purchase succeeds")
	var before_duplicate_equipment := int(game.money)
	_check(
		not bool(game._purchase_and_grant("nvgs").allowed)
		and int(game.money) == before_duplicate_equipment,
		"duplicate equipment rejects before charge",
	)


func _assert_slot_replacement_and_grenade_caps(game: Node) -> void:
	_reset_buyer(game, RoundState.TEAM_T)
	_check(bool(game._purchase_and_grant("galil").allowed), "first primary purchase succeeds")
	game.player.switch_weapon("galil")
	_check(bool(game._purchase_and_grant("ak47").allowed), "replacement primary purchase succeeds")
	_check(
		bool(game.player.owned_weapons.get("ak47", false))
		and not bool(game.player.owned_weapons.get("galil", false))
		and game.player.active_weapon == "ak47"
		and game.player.clip == int(Registry.WEAPONS.ak47.magazine),
		"Player owns and holds only the valid replacement primary in slot one",
	)

	_reset_buyer(game, RoundState.TEAM_T)
	_check(bool(game._purchase_and_grant("flashbang").allowed), "first flashbang succeeds")
	_check(bool(game._purchase_and_grant("flashbang").allowed), "second flashbang succeeds")
	var before_third := int(game.money)
	var third: Dictionary = game._purchase_and_grant("flashbang")
	_check(
		not bool(third.allowed)
		and str(third.reason) == "already_owned_or_full"
		and int(game.money) == before_third
		and int(game.player.ammunition.flashbang.clip) == 2,
		"third flashbang is capped and rejected before charge",
	)
	_reset_buyer(game, RoundState.TEAM_T)
	_check(bool(game._purchase_and_grant("hegrenade").allowed), "first HE grenade succeeds")
	var before_second_he := int(game.money)
	_check(
		not bool(game._purchase_and_grant("hegrenade").allowed)
		and int(game.money) == before_second_he
		and int(game.player.ammunition.hegrenade.clip) == 1,
		"second HE grenade is capped and rejected before charge",
	)


func _weapon_for_ammo(ammo_name: String) -> String:
	for weapon_name: String in Registry.ROSTER:
		if (
			str(Registry.WEAPONS[weapon_name].ammo) == ammo_name
			and int(Registry.WEAPONS[weapon_name].slot) in [1, 2]
		):
			return weapon_name
	return ""


func _legal_team_for(item_name: String, definition: Dictionary) -> String:
	if item_name in RoundState.T_ONLY_ITEMS:
		return RoundState.TEAM_T
	if item_name in RoundState.CT_ONLY_ITEMS:
		return RoundState.TEAM_CT
	return str(definition.team[0])


func _reset_buyer(game: Node, team: String) -> void:
	game.player.team = team
	game.player.global_position = (
		game.target_spawns[0]
		if team == RoundState.TEAM_CT
		else game.player_spawn
	)
	var state_player: Dictionary = game.round_state.players.player
	state_player.team = team
	state_player.alive = true
	state_player.has_defuser = false
	game.round_state.players.player = state_player
	game.round_state.phase = RoundState.PHASE_FREEZE
	game.round_state.round_started_tick = game.round_state.tick
	game.player.owned_weapons = {"knife": true}
	game.player.ammunition = {"knife": {"clip": -1, "reserve": -1}}
	game.player.equipment = {
		"kevlar": false,
		"helmet": false,
		"defuser": false,
		"nvgs": false,
		"shield": false,
	}
	game.player.armor = 0
	game.player.has_helmet = false
	game.player.active_weapon = "knife"
	game.player.clip = -1
	game.player.reserve = -1
	_set_money(game, 16000)


func _set_money(game: Node, balance: int) -> void:
	game.money = balance
	var state_player: Dictionary = game.round_state.players.player
	state_player.money = balance
	game.round_state.players.player = state_player
	game.hud.update_match(
		game.round_number,
		game.phase,
		game.seconds_left,
		game.ct_score,
		game.terrorist_score,
		game.money,
	)
