extends SceneTree

const Registry = preload("res://scripts/cs16_weapon_registry.gd")
const RoundState = preload("res://scripts/cs16_round_state.gd")
const AudioRouter = preload("res://scripts/cs16_audio_event_router.gd")

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
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.set_physics_process(false)
	for actor: Node in game._all_bots() + [game.player]:
		actor.set_physics_process(false)
	game.start_match()
	# Catalog semantics are independent of map geometry. The existing round
	# integration test separately proves the imported T/CT buy brush bounds.
	game.buy_regions.clear()

	_assert_catalog_contract(game)
	_assert_every_buyable_weapon(game)
	_assert_equipment(game)
	_assert_ammunition(game)
	_assert_rejections_do_not_charge(game)
	_assert_pistols_are_team_neutral(game)
	_assert_slot_replacement_and_grenade_caps(game)
	await _assert_buy_menu_clicks(game)
	await _assert_direct_ammo_menu(game)
	await _assert_rifle_auto_equip(game)

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


func _click_buy_button(button: Button) -> void:
	_check(button.is_visible_in_tree() and not button.disabled, "buy click targets a visible enabled button")
	var point := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.pressed = down
		event.position = point
		root.push_input(event, true)


func _assert_buy_menu_clicks(game: Node) -> void:
	_reset_buyer(game, RoundState.TEAM_T)
	var hud: GameHUD = game.hud
	hud.set_deploy_visible(false)
	hud.set_paused_visible(false)
	hud.show_buy_menu(1, game.money, game._buy_menu_context())
	await process_frame
	for category: Array in hud.BUY_CATEGORIES:
		var category_id := str(category[2])
		if category_id in ["primary_ammo", "secondary_ammo"]:
			continue
		var category_button: Button = hud.buy_list_panel.get_node("BuyCategory_" + category_id)
		_click_buy_button(category_button)
		_check(hud._buy_navigation_level == "item" and hud._buy_category == category_id,
			"mouse category click completes submenu rebuild: " + category_id)
		if hud._buy_navigation_level != "item" or hud._buy_category != category_id:
			return
		_check(category_button.get_parent() == null and category_button.is_queued_for_deletion(),
			"clicked category is detached immediately and disposed after its callback")
		_check(hud.buy_list_panel.get_child_count() == hud._buy_items.size() + 1,
			"submenu contains only current rows and Back")
		await process_frame
		_check(not is_instance_valid(category_button), "old category controls are actually freed")
		var back: Button = hud.buy_list_panel.get_node("BuyBack")
		_click_buy_button(back)
		_check(hud._buy_navigation_level == "category" and not hud.buy_item_panel.visible,
			"mouse Back restores categories and hides item details")
		_check(hud.buy_list_panel.get_child_count() == hud.BUY_CATEGORIES.size() + 1,
			"Back leaves no old item rows")
		await process_frame
	_click_buy_button(hud.buy_list_panel.get_node("BuyCategory_pistols"))
	await process_frame
	var purchase: Button = hud.buy_list_panel.get_node("BuyItem_deagle")
	_click_buy_button(purchase)
	_check(game.player.owns_weapon("deagle") and game.money == 15350,
		"mouse purchase grants one weapon and charges exactly once")
	_check(not hud.buy_overlay.visible and game.player.active_weapon == "deagle"
		and not game.player.combat_controller.menu_input_blocked, "mouse purchase closes menu, draws replacement and releases gameplay input")
	_check(hud._buy_navigation_level == "item" and hud._buy_category == "pistols"
		and hud.buy_item_panel.get_node("BuyMoney").text == "ACCOUNT: $15350",
		"purchase callback finishes rebuilding the account and item panel")
	_check(purchase.get_parent() == null and purchase.is_queued_for_deletion(),
		"purchase-triggered refresh does not free its emitting button")
	await process_frame
	_check(not is_instance_valid(purchase), "old purchase button is freed after callback")
	hud.show_buy_menu(1, game.money, game._buy_menu_context())
	hud._show_buy_category("pistols")
	hud.update_buy_account(600, game._buy_menu_context())
	_check(hud.buy_list_panel.get_node("BuyItem_deagle").disabled,
		"replicated account refresh still updates affordability")
	await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw()
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--buy-capture="):
				_check(root.get_texture().get_image().save_png(argument.trim_prefix("--buy-capture=")) == OK,
					"rendered post-purchase menu capture saved")
	_click_buy_button(hud.buy_list_panel.get_node("BuyBack"))
	await process_frame
	_click_buy_button(hud.buy_list_panel.get_node("BuyCancel"))
	_check(not hud.buy_overlay.visible, "mouse Cancel closes the buy menu")
	hud.show_buy_menu(1, 600, game._buy_menu_context())
	await process_frame
	_check(hud._buy_navigation_level == "category", "reopening starts cleanly at categories")
	hud.set_buy_menu_visible(false)


func _assert_direct_ammo_menu(game: Node) -> void:
	var hud: GameHUD = game.hud
	for team: String in [RoundState.TEAM_T, RoundState.TEAM_CT]:
		_reset_buyer(game, team)
		game.player.grant_item("ak47")
		game.player.grant_item("deagle")
		game.player.ammunition.ak47.reserve = 0
		game.player.ammunition.deagle.reserve = 0
		hud.show_buy_menu(1 if team == RoundState.TEAM_T else 2, game.money, game._buy_menu_context())
		await process_frame
		for spec: Array in [["primary_ammo", "ak47", 80, 30, KEY_6], ["secondary_ammo", "deagle", 40, 7, KEY_7]]:
			hud.show_buy_menu(1 if team == RoundState.TEAM_T else 2, game.money, game._buy_menu_context())
			await process_frame
			var held: String = game.player.active_weapon
			var button: Button = hud.buy_list_panel.get_node("BuyCategory_" + str(spec[0]))
			var before: int = game.money
			_click_buy_button(button)
			_check(game.money == before - int(spec[2])
				and game.player.ammunition[spec[1]].reserve == spec[3],
				"ammo mouse click grants one caliber-specific pack and charges once: " + str(spec[0]))
			_check(not hud.buy_overlay.visible and game.player.active_weapon == held, "mouse ammo purchase closes menu without switching weapon")
			hud.show_buy_menu(1 if team == RoundState.TEAM_T else 2, game.money, game._buy_menu_context())
			await process_frame
			for down: bool in [true, false]:
				var event := InputEventKey.new()
				event.keycode = spec[4]
				event.physical_keycode = spec[4]
				event.pressed = down
				root.push_input(event, true)
			_check(game.money == before - 2 * int(spec[2])
				and game.player.ammunition[spec[1]].reserve == 2 * int(spec[3]),
				"ammo number key buys one more pack without a submenu: " + str(spec[0]))
			_check(hud._menu_state == "none" and not hud.buy_overlay.visible
				and game.player.active_weapon == held
				and hud.money_label.text == "$%d" % game.money,
				"keyboard ammo purchase closes menu and updates account without changing weapon")
		hud.show_buy_menu(1 if team == RoundState.TEAM_T else 2, game.money, game._buy_menu_context())
		await process_frame
		_set_money(game, 0)
		var reserve: int = game.player.ammunition.deagle.reserve
		_click_buy_button(hud.buy_list_panel.get_node("BuyCategory_secondary_ammo"))
		_check(game.money == 0 and game.player.ammunition.deagle.reserve == reserve,
			"direct ammo command cannot buy without money")
		_set_money(game, 1000)
		game.player.ammunition.deagle.reserve = Registry.AMMO["50ae"].reserve_max
		_click_buy_button(hud.buy_list_panel.get_node("BuyCategory_secondary_ammo"))
		_check(game.money == 1000, "full ammo command does not charge")
		game.player.owned_weapons.erase("ak47")
		_click_buy_button(hud.buy_list_panel.get_node("BuyCategory_primary_ammo"))
		_check(game.money == 1000 and hud._menu_state == "buy_category", "missing primary does not charge or open a page")
		hud.set_buy_menu_visible(false)


func _assert_rifle_auto_equip(game: Node) -> void:
	var hud: GameHUD = game.hud
	for mouse in [true, false]:
		_reset_buyer(game, RoundState.TEAM_T)
		game.player.grant_item("glock18")
		game.player.switch_weapon("glock18")
		hud.show_buy_menu(1, game.money, game._buy_menu_context())
		hud._show_buy_category("rifles")
		await process_frame
		if mouse:
			_click_buy_button(hud.buy_list_panel.get_node("BuyItem_ak47"))
		else:
			var number := 0
			for index in range(hud._buy_items.size()):
				if str(hud._buy_items[index].item_id) == "ak47": number = index + 1
			_check(number > 0, "AK has a numeric buy shortcut")
			for down in [true, false]:
				var event := InputEventKey.new()
				event.keycode = KEY_0 + number
				event.physical_keycode = event.keycode
				event.pressed = down
				root.push_input(event, true)
		_check(not hud.buy_overlay.visible and hud._menu_state == "none", "rifle purchase closes menu via mouse or number")
		_check(game.player.active_weapon == "ak47" and game.money == 13500, "rifle purchase draws AK from pistol and charges once")
		_check(not game.player.combat_controller._fire_pressed and not game.player.combat_controller._fire_held,
			"buy click does not leak into rifle fire")
		game._purchase_and_grant("deagle")
		_check(game.player.active_weapon == "ak47", "pistol purchase does not put away held rifle")
		hud.show_buy_menu(1, game.money, game._buy_menu_context())
		game._purchase_and_grant("ak47")
		_check(hud.buy_overlay.visible, "rejected duplicate weapon leaves buy menu open")
		hud.set_buy_menu_visible(false)


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
		game.audio_router.reset()
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
		var armor_audio := _armor_buy_audio(game)
		if item_name in ["kevlar", "helmet", "assaultsuit"]:
			_check(
				armor_audio.size() == 1
					and armor_audio[0].sample == "items/ammopickup2.wav"
					and int(armor_audio[0].channel) == AudioRouter.CHAN_ITEM
					and int(armor_audio[0].entity_id) == game.player.audio_entity_id(),
				"%s emits one original buyer-local armor cue" % item_name,
			)
		else:
			_check(armor_audio.is_empty(), "%s does not masquerade as an armor purchase" % item_name)
		if item_name in ["defuser", "nvgs"]:
			var equipment_audio := _buy_audio(game, "buy." + item_name)
			_check(equipment_audio.size() == 1
				and int(equipment_audio[0].channel) == AudioRouter.CHAN_ITEM
				and int(equipment_audio[0].entity_id) == game.player.audio_entity_id(),
				"%s emits one authoritative equipment cue" % item_name)


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
	game.audio_router.reset()
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
	var buy_audio := _ammo_buy_audio(game)
	_check(
		buy_audio.size() == 1
			and buy_audio[0].sample == "items/9mmclip1.wav"
			and int(buy_audio[0].channel) == AudioRouter.CHAN_ITEM
			and int(buy_audio[0].entity_id) == game.player.audio_entity_id(),
		"successful primary ammo purchase emits one original buyer-local clip cue",
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
	_check(
		_ammo_buy_audio(game).size() == 2,
		"each accepted secondary ammo box emits exactly one additional cue",
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


func _assert_pistols_are_team_neutral(game: Node) -> void:
	# BuyPistols_TER.kv and BuyPistols_CT.kv both list glock and usp, and the
	# registry marks both TEAM_BOTH, so neither side may be refused either pistol.
	_reset_buyer(game, RoundState.TEAM_T)
	_check(
		bool(game._purchase_and_grant("usp").allowed)
		and game.player.owns_weapon("usp"),
		"Terrorist buys the USP through the live buy path",
	)
	_reset_buyer(game, RoundState.TEAM_CT)
	_check(
		bool(game._purchase_and_grant("glock18").allowed)
		and game.player.owns_weapon("glock18"),
		"Counter-Terrorist buys the Glock through the live buy path",
	)


func _assert_rejections_do_not_charge(game: Node) -> void:
	_reset_buyer(game, RoundState.TEAM_T)
	game.audio_router.reset()
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
	_check(_ammo_buy_audio(game).is_empty(), "rejected ammo purchase stays silent")
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
	_check(_ammo_buy_audio(game).is_empty(), "full-ammo rejection stays silent")
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


func _ammo_buy_audio(game: Node) -> Array[Dictionary]:
	return _buy_audio(game, "buy.ammo")


func _armor_buy_audio(game: Node) -> Array[Dictionary]:
	return _buy_audio(game, "buy.armor")


func _buy_audio(game: Node, event_name: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for event: Dictionary in game.audio_router.trace():
		if str(event.kind) == "start" and str(event.event_name) == event_name:
			events.append(event)
	return events


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
