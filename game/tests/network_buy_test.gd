extends SceneTree

class BuySessionStub extends Node:
	var sequence := 0
	func is_online() -> bool: return true
	func request_buy(_item: String) -> int:
		sequence += 1
		return sequence

var failures: Array[String] = []
var game: Node
var network: Node
var sequence := 0
var now := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _buy(peer: int, item: String) -> Dictionary:
	sequence += 1
	now += 1000
	return network.accept_peer_action(peer, {"version": 1, "sequence": sequence, "action": "buy_item", "value": item}, now)


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "buy fixture must be silent")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	_check(game.map_name == "de_dust2", "current buy validation is Dust2-only")
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	for actor: Node in game._all_bots() + game._human_players_stable():
		actor.set_physics_process(false)
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	now = Time.get_ticks_msec()
	var host_inventory: Dictionary = game._player_inventory_snapshot()
	var host_balance: int = game.round_state.players.player.money
	var hud_money: int = game.money
	for peer in [99, 100]:
		network._register_input_peer(peer, now)
		game.remote_roster._on_peer_joined(peer)
	_check(_buy(99, "vest").reason == "action_unavailable", "pending participant cannot buy")
	_check(game.select_remote_join_team(99, "T").accepted and game.select_remote_join_class(99, 1).spawned, "admit T buyer")
	var human: PlayerController = game.remote_roster.actor_for_peer(99)
	human.set_physics_process(false)
	var id: String = game._round_id_for_actor(human)
	_check(game._human_buy_eligibility(human).allowed, "real Dust2 spawn is purchasable")
	human.clip = 7
	human.reserve = 11  # Deliberately newer than the inactive-ammo dictionary.
	game.audio_router.reset()
	_check(_buy(99, "vest").accepted and human.armor == 100 and game.round_state.players[id].money == 150,
		"existing alias grants armor and charges only the remote buyer")
	_check(human.clip == 7 and human.reserve == 11, "equipment buying cannot restore stale ammunition")
	var armor_audio: Array[Dictionary] = game.audio_router.trace().filter(
		func(event: Dictionary) -> bool:
			return str(event.kind) == "start" and str(event.event_name) == "buy.armor"
	)
	_check(armor_audio.size() == 1 and armor_audio[0].sample == "items/ammopickup2.wav"
		and int(armor_audio[0].channel) == CS16AudioEventRouter.CHAN_ITEM
		and int(armor_audio[0].entity_id) == human.audio_entity_id(),
		"remote armor purchase emits one authoritative original armor cue")
	var replay := {"version": 1, "sequence": sequence, "action": "buy_item", "value": "vest"}
	_check(network.accept_peer_action(99, replay, now).is_empty() and game.round_state.players[id].money == 150,
		"reliable request replay cannot grant or debit twice")
	_check(game.audio_router.trace().filter(func(event: Dictionary) -> bool:
		return str(event.kind) == "start" and str(event.event_name) == "buy.armor").size() == 1,
		"replayed remote armor purchase emits no duplicate cue")
	_check(_buy(99, "ak47").reason == "insufficient_funds" and not human.owns_weapon("ak47"), "insufficient funds cannot grant rifle")
	game.round_state.players[id].money = 16000  # Fixture funding, never client input.
	_check(_buy(99, "vest").reason == "already_owned_or_full" and game.round_state.players[id].money == 16000, "full armor is not charged")
	_check(_buy(99, "defuser").reason == "wrong_team" and _buy(99, "m4a1").reason == "wrong_team", "T cannot buy CT kit or rifle")
	game.audio_router.reset()
	_check(_buy(99, "ak47").accepted and human.owns_weapon("ak47") and game.round_state.players[id].money == 13500, "host sets rifle price")
	_check(human.active_weapon == "ak47", "authority auto-equips purchased primary over pistol")
	var weapon_audio: Array[Dictionary] = game.audio_router.trace().filter(
		func(event: Dictionary) -> bool:
			return str(event.kind) == "start" and str(event.event_name) == "weapon.acquire"
	)
	_check(weapon_audio.size() == 1 and weapon_audio[0].sample == "items/gunpickup2.wav"
		and int(weapon_audio[0].channel) == CS16AudioEventRouter.CHAN_ITEM
		and int(weapon_audio[0].entity_id) == human.audio_entity_id(),
		"remote weapon purchase emits one authoritative original pickup cue")
	human.clip = 3
	human.reserve = 1
	game.audio_router.reset()
	_check(_buy(99, "primammo").accepted and human.clip == 3 and human.reserve == 31
		and game.round_state.players[id].money == 13420, "primary ammo resolves against remote slot, preserves magazine and charges one box")
	var ammo_audio: Array[Dictionary] = game.audio_router.trace().filter(
		func(event: Dictionary) -> bool:
			return str(event.kind) == "start" and str(event.event_name) == "buy.ammo"
	)
	_check(ammo_audio.size() == 1 and ammo_audio[0].sample == "items/9mmclip1.wav"
		and int(ammo_audio[0].channel) == CS16AudioEventRouter.CHAN_ITEM
		and int(ammo_audio[0].entity_id) == human.audio_entity_id(),
		"remote ammo purchase emits one authoritative original clip cue from its buyer")
	human.reserve = 90
	_check(_buy(99, "primary_ammo").reason == "already_owned_or_full" and game.round_state.players[id].money == 13420,
		"full reserve is not charged despite stale stored ammo")
	_check(game.audio_router.trace().filter(func(event: Dictionary) -> bool: return str(event.kind) == "start" and str(event.event_name) == "buy.ammo").size() == 1,
		"rejected remote ammo purchase emits no extra cue")
	_check(_buy(99, "galil").accepted and human.active_weapon == "galil" and not human.owns_weapon("ak47"), "purchased active-slot replacement remains selectable")
	_check(_buy(99, "flashbang").accepted and _buy(99, "flashbang").accepted, "two flashbangs permitted")
	var balance: int = game.round_state.players[id].money
	_check(_buy(99, "flashbang").reason == "already_owned_or_full" and human.ammunition.flashbang.clip == 2
		and game.round_state.players[id].money == balance, "third flash cannot exceed carry limit or debit")
	_check(_buy(99, "hegrenade").accepted and _buy(99, "hegrenade").reason == "already_owned_or_full", "HE carry limit reused")
	var spawn: Vector3 = human.global_position
	human.global_position = Vector3(100, 100, 100)
	_check(_buy(99, "deagle").reason == "outside_buy_zone" and not game._human_buy_eligibility(human).allowed, "host uses buyer's position, not local host zone")
	human.global_position = spawn
	human.alive = false
	_check(_buy(99, "deagle").reason == "action_unavailable", "dead body cannot buy")
	human.alive = true
	game.round_state.players[id].alive = false
	_check(_buy(99, "deagle").reason == "dead", "round authority also checks life")
	game.round_state.players[id].alive = true
	var tick: int = game.round_state.tick
	game.round_state.tick = game.round_state.round_started_tick + game.round_state.config.buy_ticks + 1
	_check(_buy(99, "deagle").reason == "buy_time_expired", "host checks buy deadline")
	game.round_state.tick = tick
	game.round_state.phase = "post"
	_check(_buy(99, "deagle").reason == "round_inactive", "post-round rejects buying")
	game.round_state.phase = "freeze"
	human.controls_enabled = false
	_check(_buy(99, "deagle").accepted, "freeze allows buying while combat controls are disabled")
	game.round_state.phase = "live"
	game._match_concluded = true
	_check(_buy(99, "nvgs").reason == "action_unavailable", "concluded match rejects buying")
	game._match_concluded = false
	_check(_buy(99, "invented").reason == "item_unavailable", "unknown bounded identifier receives safe rejection")
	_check(game.select_remote_join_team(100, "CT").accepted and game.select_remote_join_class(100, 1).spawned, "admit separate CT buyer")
	var ct: PlayerController = game.remote_roster.actor_for_peer(100)
	ct.set_physics_process(false)
	var ct_id: String = game._round_id_for_actor(ct)
	game.audio_router.reset()
	_check(_buy(100, "defuser").accepted and ct.equipment.defuser and game.round_state.players[ct_id].has_defuser
		and game.round_state.players[ct_id].money == 600 and not human.equipment.defuser, "CT kit updates only buyer's inventory and objective flag")
	var defuser_audio: Array[Dictionary] = game.audio_router.trace().filter(
		func(event: Dictionary) -> bool:
			return str(event.kind) == "start" and str(event.event_name) == "buy.defuser"
	)
	_check(defuser_audio.size() == 1 and defuser_audio[0].sample == "items/kevlar.wav"
		and int(defuser_audio[0].entity_id) == ct.audio_entity_id(),
		"remote defuse-kit purchase emits one authoritative stock cue")
	_check(_buy(100, "ak47").reason == "wrong_team", "CT cannot buy T rifle")
	_check(ct.weapon_modes.usp, "remote CT starts with suppressed USP")
	game.round_state.players[ct_id].money = 16000
	_check(_buy(100, "m4a1").accepted and ct.weapon_modes.m4a1, "real remote M4 purchase starts suppressed")
	_check(game._player_inventory_snapshot() == host_inventory and game.round_state.players.player.money == host_balance
		and game.money == hud_money, "remote buying cannot mutate host inventory, wallet or HUD account")
	game._network_client_mode = true
	_check(not game._purchase_and_grant("kevlar").allowed, "read-only client cannot use local purchase entry point")
	game._network_client_mode = false
	_assert_client_purchase_feedback()
	game.queue_free()
	await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_BUY_PASS")
	quit(0 if failures.is_empty() else 1)


func _assert_client_purchase_feedback() -> void:
	var view := preload("res://scripts/network_client_view.gd").new()
	game.add_child(view)
	view.set_process(false)
	view.game = game
	var session := BuySessionStub.new()
	game.add_child(session)
	view.session = session
	view.snapshot = {"can_buy": true}
	view._received_ms = Time.get_ticks_msec()
	var hud: GameHUD = game.hud
	hud.set_deploy_visible(false)
	for reason in ["insufficient_funds", "timeout", "accepted", "late", "pause"]:
		hud.show_buy_menu(1, game.money, game._buy_menu_context())
		var held: String = game.player.active_weapon
		view.buy_item("ak47")
		_check(hud.buy_overlay.visible and game.player.active_weapon == held, "client waits for authority before closing/equipping")
		if reason == "late":
			hud.set_buy_menu_visible(false)
			hud.show_buy_menu(1, game.money, game._buy_menu_context())
		elif reason == "pause":
			hud.set_paused_visible(true)
		var accepted: bool = reason in ["accepted", "late", "pause"]
		view._on_action_result({"action": "buy_item", "sequence": session.sequence, "accepted": accepted, "reason": reason})
		if reason == "pause":
			_check(hud._menu_state == "pause", "delayed purchase cannot dismiss Pause")
			hud.set_paused_visible(false)
		else:
			_check(hud.buy_overlay.visible == (reason != "accepted"), "only accepted current-session purchase closes buy menu: " + reason)
		_check(view._pending_buys.is_empty(), "buy reply clears pending bookkeeping")
		_check(game.player.active_weapon == held, "buy reply leaves weapon selection to authoritative snapshot")
	hud.set_buy_menu_visible(false)
