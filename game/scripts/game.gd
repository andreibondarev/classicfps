extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TargetScript = preload("res://scripts/target.gd")
const HUDScript = preload("res://scripts/hud.gd")
const BspMapScript = preload("res://scripts/bsp_map.gd")
const AudioRouterScript = preload("res://scripts/cs16_audio_event_router.gd")
const AudioPlaybackScript = preload("res://scripts/cs16_audio_playback_adapter.gd")
const RoundStateScript = preload("res://scripts/cs16_round_state.gd")
const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")
const C4WorldScript = preload("res://scripts/cs16_c4_world.gd")
const CombatEffectsScript = preload("res://scripts/cs16_combat_effects.gd")
const BombKnowledgeScript = preload("res://scripts/cs16_bomb_knowledge.gd")
const PlayerUseResolverScript = preload("res://scripts/cs16_player_use_resolver.gd")
const C4DropContractScript = preload("res://scripts/cs16_c4_drop_contract.gd")
const BombEscapeScript = preload("res://scripts/cs16_bomb_escape.gd")

const FREEZE_SECONDS := 6.0
const ROUND_SECONDS := 300.0
const BOMB_SECONDS := 45.0
const PLANT_SECONDS := 3.0
const GOLDSRC_UNIT := 0.01
const MAX_PLAYER_USE_RADIUS := 64.0 * GOLDSRC_UNIT
const VIEW_FIELD_NARROW := 0.7
const BOT_DEFUSER_STALL_FRAMES := 500
const BOT_DEFUSER_PROGRESS_EPSILON := 8.0 * GOLDSRC_UNIT
const LEGACY_BUY_RADIUS := 200.0 * GOLDSRC_UNIT
const IMPORTED_MAP_PATH := "res://generated/de_dust2/map.json"
const FALLBACK_PLAYER_SPAWN := Vector3(0, 0.08, 12)
const FALLBACK_ALLIED_SPAWNS := [
	Vector3(-4, 0.08, 12),
	Vector3(-2, 0.08, 10),
	Vector3(2, 0.08, 10),
	Vector3(4, 0.08, 12),
]
const FALLBACK_TARGET_SPAWNS := [
	Vector3(-8, 0.08, -10),
	Vector3(0, 0.08, -15),
	Vector3(8, 0.08, -10),
	Vector3(-11, 2.58, -23),
	Vector3(11, 2.58, -23),
]
const BUY_PRICES := {
	"glock18": 400, "usp": 500, "p228": 600, "deagle": 650,
	"elite": 800, "fiveseven": 750, "m3": 1700, "xm1014": 3000,
	"mac10": 1400, "tmp": 1250, "mp5": 1500, "ump45": 1700,
	"p90": 2350, "galil": 2000, "ak47": 2500, "scout": 2750,
	"sg552": 3500, "awp": 4750, "g3sg1": 5000, "famas": 2250,
	"m4a1": 3100, "aug": 3500, "sg550": 4200, "m249": 5750,
	"kevlar": 650, "helmet": 350, "assaultsuit": 1000,
	"flashbang": 200, "hegrenade": 300,
	"smokegrenade": 300, "nvgs": 1250, "defuser": 200, "shield": 2200,
	"ammo_buckshot": 65, "ammo_9mm": 20, "ammo_556nato": 60,
	"ammo_556natobox": 60, "ammo_762nato": 80, "ammo_45acp": 25,
	"ammo_50ae": 40, "ammo_338mag": 125, "ammo_57mm": 50,
	"ammo_357sig": 50,
}
const BUY_ITEM_ALIASES := {
	# Classic VGUI command names are normalized before authoritative validation.
	"glock": "glock18",
	"mp5navy": "mp5",
	"elites": "elite",
	"vest": "kevlar",
	"vesthelm": "assaultsuit",
	"kevlar_helmet": "assaultsuit",
	"flash": "flashbang",
	"hegren": "hegrenade",
	"sgren": "smokegrenade",
	"nightvision": "nvgs",
	"primammo": "primary_ammo",
	"secammo": "secondary_ammo",
	"ammo_primary": "primary_ammo",
	"ammo_secondary": "secondary_ammo",
}
const BUY_GRANTS := {
	# Values are the canonical IDs accepted by Player.grant_item. Slot ammo
	# aliases are resolved against the currently owned primary/secondary.
	"glock18": "glock18", "usp": "usp", "p228": "p228",
	"deagle": "deagle", "elite": "elite", "fiveseven": "fiveseven",
	"m3": "m3", "xm1014": "xm1014", "mac10": "mac10", "tmp": "tmp",
	"mp5": "mp5", "ump45": "ump45", "p90": "p90", "galil": "galil",
	"ak47": "ak47", "scout": "scout", "sg552": "sg552", "awp": "awp",
	"g3sg1": "g3sg1", "famas": "famas", "m4a1": "m4a1", "aug": "aug",
	"sg550": "sg550", "m249": "m249",
	"flashbang": "flashbang", "hegrenade": "hegrenade",
	"smokegrenade": "smokegrenade",
	"kevlar": "kevlar", "helmet": "helmet", "assaultsuit": "assaultsuit",
	"nvgs": "nvgs", "defuser": "defuser", "shield": "shield",
	"ammo_buckshot": "ammo_buckshot", "ammo_9mm": "ammo_9mm",
	"ammo_556nato": "ammo_556nato", "ammo_556natobox": "ammo_556natobox",
	"ammo_762nato": "ammo_762nato", "ammo_45acp": "ammo_45acp",
	"ammo_50ae": "ammo_50ae", "ammo_338mag": "ammo_338mag",
	"ammo_57mm": "ammo_57mm", "ammo_357sig": "ammo_357sig",
	"primary_ammo": "primary_ammo", "secondary_ammo": "secondary_ammo",
}

var player: PlayerController
var hud: GameHUD
var targets: Array[TargetActor] = []
var allied_bots: Array[TargetActor] = []
var round_number := 1
var kills := 0
var seconds_left := ROUND_SECONDS
var match_started := false
var round_ending := false
var phase := "deploy"
var ct_score := 0
var terrorist_score := 0
var money := 800
var plant_progress := 0.0
var bomb_planted := false
var bomb: Node3D
var dropped_c4: CS16C4World
var bomb_position := Vector3.ZERO
var bomb_sites: Array[Vector3] = []
var bomb_regions: Array[Dictionary] = []
var buy_regions: Array[Dictionary] = []
var imported_map: BspMap
var player_spawn := FALLBACK_PLAYER_SPAWN
var allied_spawns: Array[Vector3] = []
var target_spawns: Array[Vector3] = []
var terrorist_team_spawns: Array[Vector3] = []
var counter_terrorist_team_spawns: Array[Vector3] = []
var using_imported_map := false
var audio_router: CS16AudioEventRouter
var audio_playback: CS16AudioPlaybackAdapter
var _next_c4_beep_tick := -1
var _c4_beep_index := 0
var round_state: RefCounted
var _consumed_round_events := 0
var _last_hud_second := -1
var _c4_equipped := false
var _c4_drop_animation_played := false
var _bot_site_assignments: Dictionary = {}
var _bot_defuser_id := ""
var _bot_defuser_progress_position := Vector3.INF
var _bot_defuser_last_progress_frame := -1
var _bot_defuser_stalled_ids: Dictionary = {}
var _ct_bomb_location_known := false
var bomb_knowledge: CS16BombKnowledge
var selected_class_id := 1
var selected_player_skin := "terror"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_audio_runtime()
	_build_environment()
	get_node("/root/GameSettings").changed.connect(_apply_performance_settings)
	if not _build_imported_map():
		_build_arena()
		allied_spawns.assign(FALLBACK_ALLIED_SPAWNS)
		target_spawns.assign(FALLBACK_TARGET_SPAWNS)
		terrorist_team_spawns.assign([FALLBACK_PLAYER_SPAWN] + FALLBACK_ALLIED_SPAWNS)
		counter_terrorist_team_spawns.assign(FALLBACK_TARGET_SPAWNS)
	_spawn_player()
	_spawn_targets()
	_build_bomb_sites()
	_build_round_state()
	_build_hud()
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	hud.set_deploy_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_performance_settings()


func _build_imported_map() -> bool:
	if "--procedural-test" in OS.get_cmdline_user_args():
		return false
	if not FileAccess.file_exists(IMPORTED_MAP_PATH):
		push_warning("Converted Dust2 map not found; using the procedural test arena.")
		return false
	imported_map = BspMapScript.new()
	imported_map.name = "DeDust2"
	add_child(imported_map)
	if not imported_map.load_map(IMPORTED_MAP_PATH):
		imported_map.queue_free()
		imported_map = null
		return false

	var ct_spawns := imported_map.spawn_points("info_player_start")
	var terrorist_spawns := imported_map.spawn_points("info_player_deathmatch")
	if ct_spawns.size() < 5 or terrorist_spawns.size() < 5:
		push_error("Dust2 is missing the player spawns needed by the combat scenario.")
		imported_map.queue_free()
		imported_map = null
		return false
	terrorist_team_spawns.assign(terrorist_spawns)
	counter_terrorist_team_spawns.assign(ct_spawns)
	_apply_spawn_side(Combatant.TEAM_TERRORIST)
	using_imported_map = true
	return true


func _process(delta: float) -> void:
	# Round and objective time is owned exclusively by the 100 Hz physics tick.
	pass


func _physics_process(delta: float) -> void:
	if is_instance_valid(audio_router):
		audio_router.advance_ticks(1)
		if is_instance_valid(player):
			audio_playback.set_listener_origin_hu(
				AudioRouterScript.meters_to_hu(player.camera.global_position)
			)
	if (
		match_started
		and not get_tree().paused
		and is_instance_valid(round_state)
	):
		_sync_dropped_c4_position()
		var round_events: Array[Dictionary] = round_state.advance_tick(
			_round_tick_command()
		)
		_consume_round_events(round_events)
		_consumed_round_events = round_state.trace.size()
		_sync_round_public_state()
		_update_round_hud()
	var network := get_node("/root/NetworkSession")
	if not match_started or not is_instance_valid(player):
		return
	var command := player.last_command
	var movement: Vector2 = command.get("movement", Vector2.ZERO)
	network.submit_local_input({
		"movement": movement,
		"yaw": player.rotation.y,
		"pitch": player.camera.rotation.x,
		"buttons": (
			(1 if command.get("fire", false) else 0)
			| (2 if command.get("jump", false) else 0)
			| (4 if command.get("crouch", false) else 0)
			| (8 if command.get("reload", false) else 0)
			| (16 if command.get("use", false) else 0)
			| (32 if command.get("walk", false) else 0)
		),
	})
	network.tick_snapshot(delta, {
		"tick": Engine.get_physics_frames(),
		"position": player.global_position,
		"velocity": player.velocity,
		"health": player.health,
		"phase": phase,
		"round_time": seconds_left,
	})


func _build_audio_runtime() -> void:
	audio_router = AudioRouterScript.new()
	audio_router.name = AudioRouterScript.NODE_NAME
	# The game advances this clock exactly once per authoritative physics tick.
	audio_router.set_process(false)
	add_child(audio_router)
	# Adding a scripted node registers its _process callback, so disable it
	# again after tree entry. Only Game._physics_process owns this clock live.
	audio_router.set_process(false)
	audio_router.reset(0xC516)
	audio_playback = AudioPlaybackScript.new()
	audio_playback.name = "CS16AudioPlaybackAdapter"
	# Dedicated/headless simulations still route and validate every sound event,
	# but must not allocate an audio-device playback object.
	audio_playback.playback_enabled = DisplayServer.get_name() != "headless"
	add_child(audio_playback)
	audio_playback.bind_router(audio_router)


func _emit_world_audio(
	event_name: String,
	channel: int,
	origin_meters := Vector3.ZERO,
	overrides := {},
) -> int:
	if not is_instance_valid(audio_router):
		return -1
	return audio_router.emit_catalog_event(
		event_name,
		0,
		channel,
		AudioRouterScript.meters_to_hu(origin_meters),
		overrides,
	)


func _update_c4_audio() -> void:
	if (
		not bomb_planted
		or not is_instance_valid(bomb)
		or _next_c4_beep_tick < 0
		or audio_router.current_tick < _next_c4_beep_tick
	):
		return
	var event_name := "c4.beep%d" % mini(_c4_beep_index + 1, 5)
	_emit_world_audio(
		event_name,
		AudioRouterScript.CHAN_VOICE,
		bomb.global_position,
		{"attenuation": [1.5, 1.0, 0.8, 0.5, 0.2][mini(_c4_beep_index, 4)]},
	)
	_c4_beep_index = mini(_c4_beep_index + 1, 4)
	_next_c4_beep_tick += 140


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_TAB:
		hud.set_scoreboard_held(key_event.pressed)
		get_viewport().set_input_as_handled()
		return
	if (
		key_event.pressed
		and not key_event.echo
		and hud.handle_menu_key(key_event.keycode)
	):
		get_viewport().set_input_as_handled()
		return
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		if not match_started:
			return
		_set_paused(not get_tree().paused)
	elif (
		key_event.pressed
		and not key_event.echo
		and key_event.keycode == KEY_5
		and phase == RoundStateScript.PHASE_LIVE
	):
		_c4_equipped = _equip_player_c4()
		if _c4_equipped:
			hud.update_objective("C4 EQUIPPED  •  HOLD FIRE IN A BOMB SITE")
	elif (
		key_event.pressed
		and not key_event.echo
		and key_event.keycode == KEY_G
	):
		_request_drop_active_weapon()
	elif (
		key_event.pressed
		and not key_event.echo
		and key_event.keycode == KEY_B
		and match_started
	):
		var eligibility := _buy_eligibility()
		if bool(eligibility.allowed):
			hud.show_buy_menu(_hud_team_id(), money, _buy_menu_context())
		else:
			hud.show_banner("CANNOT BUY HERE", Color("#ff6a62"), 0.75)
	elif key_event.pressed and not key_event.echo and phase == "freeze":
		match key_event.keycode:
			KEY_F1:
				_buy("ak47", 2500, "AK-47")
			KEY_F2:
				_buy("deagle", 650, "DESERT EAGLE")
			KEY_F3:
				_buy("armor", 1000, "KEVLAR + HELMET")
			KEY_F4:
				_buy("hegrenade", 300, "HE GRENADE")


func _buy(item: String, _price: int, label: String) -> void:
	var result := _purchase_and_grant({
		"armor": "assaultsuit",
	}.get(item, item))
	if not bool(result.allowed):
		_show_buy_rejection(str(result.reason))
		return
	hud.show_banner("PURCHASED  %s" % label, Color("#77e3ae"), 0.65)


func _on_buy_item_requested(item_id: String) -> void:
	var result := _purchase_and_grant(item_id)
	if not bool(result.allowed):
		_show_buy_rejection(str(result.reason))
		return
	hud.show_banner("PURCHASED", Color("#77e3ae"), 0.65)


func _purchase_and_grant(item_id: String) -> Dictionary:
	var requested_item := item_id.to_lower().strip_edges()
	var source_item := str(BUY_ITEM_ALIASES.get(requested_item, requested_item))
	if not BUY_GRANTS.has(source_item):
		return {"allowed": false, "reason": "item_unavailable"}
	var grant_id := _resolve_buy_grant(str(BUY_GRANTS[source_item]))
	if grant_id.is_empty():
		return {"allowed": false, "reason": "item_unavailable"}
	var price := _resolve_buy_price(source_item, grant_id)
	if price < 0:
		return {"allowed": false, "reason": "item_unavailable"}
	var inside_zone := _is_in_team_buy_zone(
		player.global_position,
		player.team,
		_player_hull_size(),
	)
	var map_has_zones := not buy_regions.is_empty()
	var eligibility: Dictionary = round_state.can_buy(
		"player",
		inside_zone,
		map_has_zones,
	)
	if not bool(eligibility.allowed):
		return eligibility
	if not _team_may_buy(source_item):
		return {"allowed": false, "reason": "wrong_team"}
	if int(round_state.players.player.money) < price:
		return {"allowed": false, "reason": "insufficient_funds"}

	# The inventory mutation deliberately precedes the authoritative debit.
	# Player.grant_item owns slot replacement, grenade carry limits, equipment
	# flags, and ammo caps. An unavailable or already-full grant never charges.
	var inventory_before := _player_inventory_snapshot()
	if not player.grant_item(grant_id):
		return {"allowed": false, "reason": "item_unavailable"}
	if _player_inventory_snapshot() == inventory_before:
		return {"allowed": false, "reason": "already_owned_or_full"}
	var result: Dictionary = round_state.purchase_item(
		"player",
		source_item,
		price,
		inside_zone,
		map_has_zones,
	)
	if not bool(result.allowed):
		_restore_player_inventory(inventory_before)
		return result

	money = int(result.balance)
	if source_item == "defuser":
		round_state.set_defuser("player", true)
	if (
		WeaponRegistryScript.WEAPONS.has(grant_id)
		and not player.owns_weapon(player.active_weapon)
	):
		# Buying a replacement for the weapon in hand must never leave the
		# controller pointing at the removed slot entry.
		player.switch_weapon(grant_id)
	if player.ammunition.has(player.active_weapon):
		player.clip = int(player.ammunition[player.active_weapon].clip)
		player.reserve = int(player.ammunition[player.active_weapon].reserve)
	hud.update_health(player.health, player.armor)
	hud.update_ammo(player.clip, player.reserve, player.reloading)
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	return {
		"allowed": true,
		"reason": "ok",
		"balance": money,
		"item": source_item,
		"grant": grant_id,
		"price": price,
	}


func _resolve_buy_grant(grant_id: String) -> String:
	if grant_id == "primary_ammo":
		return _owned_slot_ammo_grant(1)
	if grant_id == "secondary_ammo":
		return _owned_slot_ammo_grant(2)
	return grant_id


func _owned_slot_ammo_grant(slot: int) -> String:
	for weapon_name: String in player.owned_weapons:
		if (
			bool(player.owned_weapons[weapon_name])
			and PlayerController.WEAPONS.has(weapon_name)
			and int(PlayerController.WEAPONS[weapon_name].slot) == slot
		):
			var ammo_name := str(PlayerController.WEAPONS[weapon_name].ammo)
			if WeaponRegistryScript.AMMO.has(ammo_name):
				return "ammo_%s" % ammo_name
	return ""


func _resolve_buy_price(source_item: String, grant_id: String) -> int:
	if source_item in ["primary_ammo", "secondary_ammo"]:
		return int(BUY_PRICES.get(grant_id, -1))
	return int(BUY_PRICES.get(source_item, -1))


func _team_may_buy(source_item: String) -> bool:
	if source_item in ["primary_ammo", "secondary_ammo"] or source_item.begins_with("ammo_"):
		return true
	var team_id := (
		RoundStateScript.TEAM_CT
		if player.team == Combatant.TEAM_COUNTER_TERRORIST
		else RoundStateScript.TEAM_T
	)
	if source_item in RoundStateScript.T_ONLY_ITEMS:
		return team_id == RoundStateScript.TEAM_T
	if source_item in RoundStateScript.CT_ONLY_ITEMS:
		return team_id == RoundStateScript.TEAM_CT
	if WeaponRegistryScript.WEAPONS.has(source_item):
		return team_id in WeaponRegistryScript.WEAPONS[source_item].team
	if WeaponRegistryScript.EQUIPMENT.has(source_item):
		return team_id in WeaponRegistryScript.EQUIPMENT[source_item].team
	return false


func _player_inventory_snapshot() -> Dictionary:
	return {
		"owned_weapons": player.owned_weapons.duplicate(true),
		"ammunition": player.ammunition.duplicate(true),
		"equipment": player.equipment.duplicate(true),
		"armor": player.armor,
		"has_helmet": player.has_helmet,
		"active_weapon": player.active_weapon,
		"clip": player.clip,
		"reserve": player.reserve,
	}


func _restore_player_inventory(snapshot: Dictionary) -> void:
	player.owned_weapons = snapshot.owned_weapons.duplicate(true)
	player.ammunition = snapshot.ammunition.duplicate(true)
	player.equipment = snapshot.equipment.duplicate(true)
	player.armor = int(snapshot.armor)
	player.has_helmet = bool(snapshot.has_helmet)
	player.active_weapon = str(snapshot.active_weapon)
	player.clip = int(snapshot.clip)
	player.reserve = int(snapshot.reserve)


func _buy_menu_context() -> Dictionary:
	return {
		"primary_ammo_price": _slot_ammo_price(1),
		"secondary_ammo_price": _slot_ammo_price(2),
	}


func _slot_ammo_price(slot: int) -> int:
	var grant_id := _owned_slot_ammo_grant(slot)
	return int(BUY_PRICES.get(grant_id, 0))


func _show_buy_rejection(reason: String) -> void:
	var text := "CANNOT BUY HERE"
	if reason == "insufficient_funds":
		text = "NOT ENOUGH MONEY"
	elif reason in ["item_unavailable", "already_owned_or_full"]:
		text = "ITEM UNAVAILABLE"
	hud.show_banner(text, Color("#ff6a62"), 0.75)


func _buy_eligibility() -> Dictionary:
	return round_state.can_buy(
		"player",
		_is_in_team_buy_zone(
			player.global_position,
			player.team,
			_player_hull_size(),
		),
		not buy_regions.is_empty(),
	)


func _hud_team_id() -> int:
	return 2 if player.team == Combatant.TEAM_COUNTER_TERRORIST else 1


func _is_in_team_buy_zone(
	position: Vector3,
	team: String,
	hull_size := Vector3(
		PlayerController.HULL_WIDTH,
		PlayerController.STAND_HEIGHT,
		PlayerController.HULL_WIDTH,
	),
) -> bool:
	if buy_regions.is_empty():
		# Maps without func_buyzone use OLD_CheckBuyZone: within 200 HU of a
		# matching team spawn. This is not a map-wide buy-anywhere fallback.
		var spawns: Array = (
			target_spawns
			if team == Combatant.TEAM_COUNTER_TERRORIST
			else ([player_spawn] + allied_spawns)
		)
		for spawn: Vector3 in spawns:
			if position.distance_to(spawn) < LEGACY_BUY_RADIUS:
				return true
		return false
	var source_team := 1 if team == Combatant.TEAM_TERRORIST else 2
	var player_hull := _feet_hull_aabb(position, hull_size)
	for region: Dictionary in buy_regions:
		var bounds: AABB = region.bounds
		var region_team := int(region.team)
		if (
			region_team in [0, source_team]
			and _aabb_touches(player_hull, bounds)
		):
			return true
	return false


func _player_hull_size() -> Vector3:
	if (
		is_instance_valid(player)
		and is_instance_valid(player.collider)
		and player.collider.shape is BoxShape3D
	):
		return (player.collider.shape as BoxShape3D).size
	return Vector3(
		PlayerController.HULL_WIDTH,
		PlayerController.STAND_HEIGHT,
		PlayerController.HULL_WIDTH,
	)


func _feet_hull_aabb(feet_position: Vector3, hull_size: Vector3) -> AABB:
	return AABB(
		feet_position + Vector3(-hull_size.x * 0.5, 0.0, -hull_size.z * 0.5),
		hull_size,
	)


func _aabb_touches(first: AABB, second: AABB) -> bool:
	var first_end := first.end
	var second_end := second.end
	return not (
		first_end.x < second.position.x
		or first.position.x > second_end.x
		or first_end.y < second.position.y
		or first.position.y > second_end.y
		or first_end.z < second.position.z
		or first.position.z > second_end.z
	)


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#71828b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c8d0ce")
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#7f8e90")
	environment.fog_density = 0.0025
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sunlight"
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_color = Color("#fff1d3")
	sun.light_energy = 1.32
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70
	add_child(sun)


func _apply_performance_settings() -> void:
	var settings := get_node("/root/GameSettings")
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := get_node_or_null("Sunlight") as DirectionalLight3D
	if is_instance_valid(world_environment):
		world_environment.environment.fog_enabled = settings.performance_preset > 0
	if is_instance_valid(sun):
		sun.shadow_enabled = settings.performance_preset > 0
		sun.directional_shadow_max_distance = 45.0 if settings.performance_preset == 1 else 80.0


func _build_arena() -> void:
	var concrete := Color("#37434a")
	var dark_concrete := Color("#202a31")
	var steel := Color("#52646d")
	var accent := Color("#b56d35")
	_make_box("Floor", Vector3(0, -0.5, -5), Vector3(40, 1, 48), concrete)
	_make_box("LeftWall", Vector3(-20.5, 3.5, -5), Vector3(1, 8, 48), dark_concrete)
	_make_box("RightWall", Vector3(20.5, 3.5, -5), Vector3(1, 8, 48), dark_concrete)
	_make_box("BackWall", Vector3(0, 3.5, -29.5), Vector3(42, 8, 1), dark_concrete)
	_make_box("SpawnWall", Vector3(0, 2.0, 19.5), Vector3(42, 5, 1), dark_concrete)

	# Central combat cover and two elevated firing platforms.
	_make_box("CenterCover", Vector3(0, 1.05, -5), Vector3(4.5, 2.1, 1.2), steel)
	_make_box("LeftCover", Vector3(-9, 0.75, -3), Vector3(3.2, 1.5, 2.0), accent)
	_make_box("RightCover", Vector3(9, 0.75, -3), Vector3(3.2, 1.5, 2.0), accent)
	_make_box("LeftPlatform", Vector3(-11, 2.0, -23), Vector3(7.0, 1.0, 7.0), concrete)
	_make_box("RightPlatform", Vector3(11, 2.0, -23), Vector3(7.0, 1.0, 7.0), concrete)

	# Stairs exercise GoldSrc-style step handling.
	for side in [-1, 1]:
		for step in range(8):
			var height := 0.25 * float(step + 1)
			_make_box(
				"Stair_%d_%d" % [side, step],
				Vector3(11.0 * side, height * 0.5, -14.5 - step * 0.65),
				Vector3(3.0, height, 0.68),
				steel,
			)

	# Angled ramps provide an alternate route onto each platform.
	_make_box("LeftRamp", Vector3(-15.2, 1.05, -20), Vector3(3.0, 0.45, 9.0), steel, Vector3(deg_to_rad(-14), 0, 0))
	_make_box("RightRamp", Vector3(15.2, 1.05, -20), Vector3(3.0, 0.45, 9.0), steel, Vector3(deg_to_rad(-14), 0, 0))

	# Emissive lane markers keep orientation readable without expensive lights.
	for lane_x in [-11.0, 0.0, 11.0]:
		var marker := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.14, 0.025, 35)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#3cb9e3")
		material.emission_enabled = true
		material.emission = Color("#176c89")
		mesh.material = material
		marker.mesh = mesh
		marker.position = Vector3(lane_x, 0.02, -6)
		add_child(marker)


func _make_box(
	box_name: String,
	position: Vector3,
	size: Vector3,
	color: Color,
	rotation := Vector3.ZERO,
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = box_name
	body.position = position
	body.rotation = rotation
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	mesh.material = material
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	add_child(body)
	return body


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.configure_identity(Combatant.TEAM_TERRORIST, "Player")
	player.position = player_spawn
	add_child(player)
	if using_imported_map and not target_spawns.is_empty():
		player.face_toward(target_spawns[0])


func _spawn_targets() -> void:
	for ally_index in range(allied_spawns.size()):
		var ally := _make_bot(
			"T_Bot_%02d" % (ally_index + 1),
			Combatant.TEAM_TERRORIST,
			ally_index,
			allied_spawns[ally_index],
		)
		allied_bots.append(ally)
	for target_index in range(target_spawns.size()):
		var target := _make_bot(
			"CT_Bot_%02d" % (target_index + 1),
			Combatant.TEAM_COUNTER_TERRORIST,
			target_index,
			target_spawns[target_index],
		)
		target.damaged.connect(_on_target_damaged)
		targets.append(target)


func _make_bot(
	bot_name: String,
	bot_team: String,
	bot_index: int,
	spawn_position: Vector3,
) -> TargetActor:
	var bot: TargetActor = TargetScript.new()
	bot.name = bot_name
	bot.index = bot_index
	bot.configure_identity(bot_team, bot_name.replace("_", " "))
	bot.position = spawn_position
	add_child(bot)
	bot.died.connect(_on_target_died)
	return bot


func _all_bots() -> Array[TargetActor]:
	var bots: Array[TargetActor] = []
	bots.append_array(allied_bots)
	bots.append_array(targets)
	return bots


func _build_round_state() -> void:
	round_state = RoundStateScript.new()
	round_state.register_player(
		"player",
		Combatant.TEAM_TERRORIST,
		RoundStateScript.START_MONEY,
		false,
	)
	for bot in allied_bots:
		round_state.register_player(bot.name, bot.team)
	for bot in targets:
		round_state.register_player(bot.name, bot.team)
	bomb_knowledge = BombKnowledgeScript.new()
	_refresh_bomb_knowledge_roster()


func _refresh_bomb_knowledge_roster() -> void:
	if not is_instance_valid(bomb_knowledge):
		return
	bomb_knowledge.register_actor("player", _knowledge_team(player.team))
	for bot in _all_bots():
		bomb_knowledge.register_actor(bot.name, _knowledge_team(bot.team))


func _knowledge_team(team: String) -> String:
	return (
		BombKnowledgeScript.TEAM_CT
		if team == Combatant.TEAM_COUNTER_TERRORIST
		else BombKnowledgeScript.TEAM_T
	)


func _build_bomb_sites() -> void:
	bomb_sites.clear()
	bomb_regions.clear()
	buy_regions.clear()
	if using_imported_map:
		bomb_regions = imported_map.brush_entity_regions("func_bomb_target")
		buy_regions = imported_map.brush_entity_regions("func_buyzone")
		for region: Dictionary in bomb_regions:
			var bounds: AABB = region.bounds
			bomb_sites.append(bounds.get_center())
	else:
		bomb_sites.append(Vector3(-11, 2.58, -23))
		bomb_sites.append(Vector3(11, 2.58, -23))
		for site_index in range(bomb_sites.size()):
			bomb_regions.append({
				"bounds": AABB(
					bomb_sites[site_index] - Vector3(2.0, 1.0, 2.0),
					Vector3(4.0, 2.0, 4.0),
				),
				"target": "site_%d" % site_index,
			})
		for site_index in range(bomb_sites.size()):
			var marker := MeshInstance3D.new()
			marker.name = "Bombsite_%s" % ("A" if site_index == 0 else "B")
			var mesh := CylinderMesh.new()
			mesh.top_radius = 1.9
			mesh.bottom_radius = 1.9
			mesh.height = 0.025
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.92, 0.35, 0.10, 0.25)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.material = material
			marker.mesh = mesh
			marker.position = bomb_sites[site_index]
			add_child(marker)


func _build_hud() -> void:
	hud = HUDScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.deploy_requested.connect(start_match)
	hud.resume_requested.connect(func() -> void: _set_paused(false))
	hud.buy_item_requested.connect(_on_buy_item_requested)
	hud.team_selected.connect(_on_team_selected)
	hud.class_selected.connect(_on_class_selected)
	player.health_changed.connect(_on_player_health_changed)
	player.ammo_changed.connect(_on_player_ammo_changed)
	player.weapon_changed.connect(func(weapon_name: String, fire_mode: String) -> void:
		hud.update_weapon(weapon_name, fire_mode)
	)
	player.hit_confirmed.connect(func(headshot: bool) -> void: hud.show_hitmarker(headshot))
	player.died.connect(_on_player_died)
	hud.update_health(player.health, player.armor)
	hud.update_weapon(PlayerController.WEAPONS[player.active_weapon].name, PlayerController.WEAPONS[player.active_weapon].mode)
	hud.update_ammo(player.clip, player.reserve, player.reloading)
	_update_scoreboard()


func _on_team_selected(team_id: int) -> void:
	if team_id == 6:
		player.configure_identity(Combatant.TEAM_UNASSIGNED, "Player")
		if round_state.players.has("player"):
			var spectator_state: Dictionary = round_state.players.player
			spectator_state.team = Combatant.TEAM_UNASSIGNED
			round_state.players.player = spectator_state
		return
	var selected_team := (
		Combatant.TEAM_COUNTER_TERRORIST
		if team_id == 2
		else Combatant.TEAM_TERRORIST
	)
	player.configure_identity(selected_team, "Player")
	_apply_spawn_side(selected_team)
	_apply_bot_sides(selected_team)
	if round_state.players.has("player"):
		var state_player: Dictionary = round_state.players.player
		state_player.team = selected_team
		round_state.players.player = state_player
	player.reset_player(player_spawn, false)
	player.controls_enabled = false
	selected_player_skin = _class_skin(selected_team, selected_class_id)
	player.set_meta("cs16_team_id", 2 if selected_team == Combatant.TEAM_COUNTER_TERRORIST else 1)
	player.set_meta("cs16_player_skin", selected_player_skin)
	_update_scoreboard()


func _on_class_selected(class_id: int) -> void:
	selected_class_id = clampi(class_id, 1, 4)
	selected_player_skin = _class_skin(player.team, selected_class_id)
	player.set_meta("cs16_class_id", selected_class_id)
	player.set_meta("cs16_player_skin", selected_player_skin)


func _class_skin(team: String, class_id: int) -> String:
	var skins := (
		["urban", "gsg9", "sas", "gign"]
		if team == Combatant.TEAM_COUNTER_TERRORIST
		else ["terror", "leet", "arctic", "guerilla"]
	)
	return str(skins[clampi(class_id, 1, 4) - 1])


func _apply_spawn_side(player_team: String) -> void:
	var friendly_spawns := (
		counter_terrorist_team_spawns
		if player_team == Combatant.TEAM_COUNTER_TERRORIST
		else terrorist_team_spawns
	)
	var enemy_spawns := (
		terrorist_team_spawns
		if player_team == Combatant.TEAM_COUNTER_TERRORIST
		else counter_terrorist_team_spawns
	)
	if friendly_spawns.is_empty() or enemy_spawns.is_empty():
		return
	player_spawn = friendly_spawns[0]
	allied_spawns.clear()
	target_spawns.clear()
	for spawn_index in range(1, mini(5, friendly_spawns.size())):
		allied_spawns.append(friendly_spawns[spawn_index])
	for spawn_index in range(mini(5, enemy_spawns.size())):
		target_spawns.append(enemy_spawns[spawn_index])


func _apply_bot_sides(player_team: String) -> void:
	var enemy_team := (
		Combatant.TEAM_TERRORIST
		if player_team == Combatant.TEAM_COUNTER_TERRORIST
		else Combatant.TEAM_COUNTER_TERRORIST
	)
	for bot_index in range(allied_bots.size()):
		_set_bot_team(allied_bots[bot_index], player_team)
		if bot_index < allied_spawns.size():
			allied_bots[bot_index].reset_target(allied_spawns[bot_index])
			allied_bots[bot_index].active = false
	for bot_index in range(targets.size()):
		_set_bot_team(targets[bot_index], enemy_team)
		if bot_index < target_spawns.size():
			targets[bot_index].reset_target(target_spawns[bot_index])
			targets[bot_index].active = false
	_refresh_bomb_knowledge_roster()


func _set_bot_team(bot: TargetActor, team: String) -> void:
	bot.configure_identity(team, bot.display_name)
	if round_state.players.has(bot.name):
		var state_bot: Dictionary = round_state.players[bot.name]
		state_bot.team = team
		round_state.players[bot.name] = state_bot
	if is_instance_valid(bot.character_model):
		bot.player_skin = bot._skin_for_identity()
		bot.character_model.load_character(bot.player_skin, "ak47")


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	hud.set_paused_visible(paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func start_match() -> void:
	if round_ending:
		return
	match_started = true
	hud.set_deploy_visible(false)
	hud.set_paused_visible(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_consumed_round_events = 0
	round_state.start_match()
	_consume_round_events(round_state.trace)
	_consumed_round_events = round_state.trace.size()
	_sync_round_public_state()
	_update_round_hud(true)


func _begin_freeze() -> void:
	# Compatibility hook used by existing smoke tests.
	if is_instance_valid(round_state):
		round_state._set_phase(RoundStateScript.PHASE_FREEZE, int(round_state.config.freeze_ticks))
		_sync_round_public_state()


func _begin_live() -> void:
	# Compatibility hook used by tests that skip the source freeze period.
	if is_instance_valid(round_state):
		round_state._set_phase(RoundStateScript.PHASE_LIVE, int(round_state.config.round_ticks))
		_consume_round_events([round_state.trace.back()])
		_consumed_round_events = round_state.trace.size()
		_sync_round_public_state()


func _on_target_damaged(_target: TargetActor, _health: int, headshot: bool) -> void:
	if headshot:
		hud.show_banner("HEADSHOT", Color("#ffca66"), 0.55)


func _on_target_died(target: TargetActor, headshot: bool) -> void:
	if round_ending:
		return
	if is_instance_valid(round_state):
		round_state.set_player_alive(
			target.name,
			false,
			target.global_position,
			_round_id_for_actor(target.last_damage_attacker)
			if is_instance_valid(target.last_damage_attacker)
			else "",
		)
		_consume_new_round_trace()
		_sync_round_public_state()
	if target.team == Combatant.TEAM_COUNTER_TERRORIST:
		kills += 1
		hud.show_banner(
			"HOSTILE DOWN%s" % ("  •  HEADSHOT" if headshot else ""),
			Color("#ffca66"),
			0.7,
		)
	_update_round_hud(true)


func _on_player_health_changed(health: int, armor: int) -> void:
	if is_instance_valid(hud):
		var took_damage := health < int(hud.health_label.text) if hud.health_label.text.is_valid_int() else false
		hud.update_health(health, armor)
		if took_damage:
			hud.show_damage()


func _on_player_ammo_changed(clip: int, reserve: int, reloading: bool) -> void:
	if is_instance_valid(hud):
		hud.update_ammo(clip, reserve, reloading)


func _on_player_died() -> void:
	if is_instance_valid(round_state):
		round_state.set_player_alive(
			"player",
			false,
			player.global_position,
			_round_id_for_actor(player.last_damage_attacker)
			if is_instance_valid(player.last_damage_attacker)
			else "",
		)
		_consume_new_round_trace()
		_sync_round_public_state()
		_update_round_hud(true)


func _check_team_elimination() -> void:
	if round_ending or not is_instance_valid(round_state):
		return
	round_state._check_elimination()
	_consume_new_round_trace()
	_sync_round_public_state()


func _team_has_survivors(team_name: String) -> bool:
	for combatant_node in get_tree().get_nodes_in_group("combatants"):
		var combatant := combatant_node as Combatant
		if (
			is_instance_valid(combatant)
			and combatant.team == team_name
			and combatant.alive
		):
			return true
	return false


func _end_round(won: bool, reason: String) -> void:
	if round_ending or not is_instance_valid(round_state):
		return
	round_state._end_round(
		RoundStateScript.TEAM_T if won else RoundStateScript.TEAM_CT,
		"terrorists_win" if won else "cts_win",
		RoundStateScript.REWARD_TEAM_WIN,
	)
	_consume_new_round_trace()
	_sync_round_public_state()
	_update_round_hud(true)


func _reset_round() -> void:
	if not is_instance_valid(round_state):
		return
	round_state._start_round()
	_consume_new_round_trace()
	_sync_round_public_state()
	_update_round_hud(true)


func _round_tick_command() -> Dictionary:
	var command := {}
	if phase == RoundStateScript.PHASE_LIVE:
		var carrier := _actor_for_round_id(str(round_state.bomb_owner))
		if not is_instance_valid(carrier):
			return command
		var site := _bomb_region_at(
			carrier.global_position,
			_player_hull_size()
			if carrier == player
			else TargetActor.STANDING_HULL_SIZE,
		)
		var is_human_carrier := carrier == player
		var bot_command: Dictionary = carrier.last_command
		var c4_is_equipped := (
			player.active_weapon == "c4"
			if is_human_carrier
			else bool((carrier as TargetActor).c4_equipped)
		)
		command.plant = {
			"player_id": _round_id_for_actor(carrier),
			"attack": (
				(
					Input.is_action_pressed("fire")
					and player.weapon_clock.can_primary_attack()
				)
				if is_human_carrier
				else (
					str(bot_command.get("objective_action", "")) == "plant"
					and not site.is_empty()
					and (carrier as TargetActor).c4_ready_for_plant()
				)
			),
			"equipped_c4": c4_is_equipped,
			"grounded": (
				_player_objective_grounded()
				if is_human_carrier
				else carrier.is_on_floor()
			),
			"in_bomb_site": not site.is_empty(),
			"site_id": str(site.get("target", "")),
			"position": carrier.global_position,
			"yaw": carrier.global_rotation.y,
		}
	elif phase == RoundStateScript.PHASE_BOMB:
		var active_defuser := _active_round_defuser()
		if is_instance_valid(active_defuser):
			var use_pressed := (
				Input.is_action_pressed("use")
				if active_defuser == player
				else true
			)
			command.defuse = _defuse_request(active_defuser, use_pressed)
		elif (
			player.team == Combatant.TEAM_COUNTER_TERRORIST
			and Input.is_action_pressed("use")
		):
			command.defuse = _defuse_request(
				player,
				true,
			)
		else:
			var bot_defuser := _active_bot_defuser()
			if is_instance_valid(bot_defuser):
				command.defuse = _defuse_request(bot_defuser, true)
	return command


func _player_objective_grounded() -> bool:
	if player._movement_grounded:
		return true
	player._movement_grounded = player.movement_kernel.categorize_ground(
		player.velocity,
	)
	if not player._movement_grounded:
		# Objective eligibility uses the same 2-HU downward floor contract even
		# on the exact coplanar frame where Godot's simulated box sweep returns
		# no new collision.
		var query := PhysicsRayQueryParameters3D.create(
			player.global_position + Vector3.UP * GOLDSRC_UNIT,
			player.global_position - Vector3.UP * 3.0 * GOLDSRC_UNIT,
			1,
			[player.get_rid()],
		)
		query.collide_with_areas = false
		var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
		player._movement_grounded = (
			not hit.is_empty()
			and Vector3(hit.get("normal", Vector3.ZERO)).dot(Vector3.UP) >= 0.7
		)
	return player._movement_grounded


func _bomb_region_at(
	position: Vector3,
	hull_size := Vector3(
		PlayerController.HULL_WIDTH,
		PlayerController.STAND_HEIGHT,
		PlayerController.HULL_WIDTH,
	),
) -> Dictionary:
	var player_hull := _feet_hull_aabb(position, hull_size)
	for region: Dictionary in bomb_regions:
		var bounds: AABB = region.bounds
		# CBombTarget first receives a regular trigger touch, then the
		# ReGameDLL fix requires the complete player hull to fit inside the
		# trigger on the two horizontal source axes. Vertical containment is
		# intentionally not required after touch.
		if (
			_aabb_touches(player_hull, bounds)
			and bounds.position.x <= player_hull.position.x
			and bounds.end.x >= player_hull.end.x
			and bounds.position.z <= player_hull.position.z
			and bounds.end.z >= player_hull.end.z
		):
			return region
	return {}


func _active_bot_defuser() -> TargetActor:
	if not bomb_planted:
		return null
	var physics_frame := Engine.get_physics_frames()
	var assigned := _actor_for_round_id(_bot_defuser_id) as TargetActor
	if (
		is_instance_valid(assigned)
		and assigned.alive
		and assigned.active
		and assigned.team == Combatant.TEAM_COUNTER_TERRORIST
	):
		if str(round_state.defuse_actor) == assigned.name:
			return assigned
		if (
			_bot_defuser_progress_position == Vector3.INF
			or assigned.global_position.distance_to(
				_bot_defuser_progress_position,
			) >= BOT_DEFUSER_PROGRESS_EPSILON
		):
			# Detours around BSP often increase straight-line bomb distance.
			# Count physical displacement as progress so a valid corridor route
			# is not reassigned merely for initially moving away from the C4.
			_bot_defuser_progress_position = assigned.global_position
			_bot_defuser_last_progress_frame = physics_frame
		elif (
			_bot_defuser_last_progress_frame >= 0
			and physics_frame - _bot_defuser_last_progress_frame
				>= BOT_DEFUSER_STALL_FRAMES
		):
			_bot_defuser_stalled_ids[assigned.name] = true
			_bot_defuser_id = ""
		else:
			return assigned
	_bot_defuser_id = ""
	var nearest: TargetActor
	var nearest_distance := INF
	for include_stalled in [false, true]:
		for target in _all_bots():
			if (
				not target.alive
				or not target.active
				or target.team != Combatant.TEAM_COUNTER_TERRORIST
				or (
					not include_stalled
					and _bot_defuser_stalled_ids.has(target.name)
				)
			):
				continue
			var distance := target.global_position.distance_to(bomb_position)
			if distance < nearest_distance:
				nearest = target
				nearest_distance = distance
		if is_instance_valid(nearest):
			break
		_bot_defuser_stalled_ids.clear()
	if is_instance_valid(nearest):
		_bot_defuser_id = nearest.name
		_bot_defuser_progress_position = nearest.global_position
		_bot_defuser_last_progress_frame = physics_frame
	return nearest


func _reset_bot_defuser_assignment() -> void:
	_bot_defuser_id = ""
	_bot_defuser_progress_position = Vector3.INF
	_bot_defuser_last_progress_frame = -1
	_bot_defuser_stalled_ids.clear()
	_ct_bomb_location_known = false


func _active_round_defuser() -> Combatant:
	if not is_instance_valid(round_state) or str(round_state.defuse_actor).is_empty():
		return null
	var actor_id := str(round_state.defuse_actor)
	if actor_id == "player":
		return player
	for bot in _all_bots():
		if bot.name == actor_id:
			return bot
	return null


func _defuse_request(actor: Combatant, use_pressed: bool) -> Dictionary:
	var eye_position := actor.global_position + Vector3.UP * Combatant.STANDING_VIEW_HEIGHT
	var view_forward := -actor.global_transform.basis.z
	if actor == player and is_instance_valid(player.camera):
		eye_position = player.camera.global_position
		view_forward = -player.camera.global_transform.basis.z
	var candidates: Array = [{
		"id": "c4",
		"origin": bomb_position,
		"usable": bomb_planted,
	}]
	for candidate_node in get_tree().get_nodes_in_group("source_use_targets"):
		var candidate_origin: Variant = (
			candidate_node.call("source_use_origin")
			if candidate_node.has_method("source_use_origin")
			else (
				(candidate_node as Node3D).global_position
				if candidate_node is Node3D
				else Vector3.INF
			)
		)
		if candidate_origin is Vector3 and candidate_origin != Vector3.INF:
			candidates.append({
				"id": str(candidate_node.name),
				"origin": candidate_origin,
				"usable": (
					bool(candidate_node.call("source_use_usable", actor))
					if candidate_node.has_method("source_use_usable")
					else true
				),
				"node": candidate_node,
			})
	var selected := PlayerUseResolverScript.select_candidate(
		actor.global_position,
		eye_position,
		view_forward,
		candidates,
	)
	var c4_selected := str(selected.get("id", "")) == "c4"
	var geometry := _c4_use_geometry(
		actor.global_position,
		eye_position,
		view_forward,
		bomb_position,
	)
	return {
		"player_id": _round_id_for_actor(actor),
		"use": use_pressed and c4_selected,
		"grounded": actor.is_on_floor(),
		"in_range": bool(geometry.in_range),
		"facing": bool(geometry.facing),
	}


func _c4_use_geometry(
	user_origin: Vector3,
	eye_origin: Vector3,
	view_forward: Vector3,
	c4_origin: Vector3,
) -> Dictionary:
	var to_c4_from_eye := c4_origin - eye_origin
	var facing_dot := -1.0
	if not to_c4_from_eye.is_zero_approx() and not view_forward.is_zero_approx():
		facing_dot = to_c4_from_eye.normalized().dot(view_forward.normalized())
	return {
		# PlayerUse searches entity origins in a 64-HU sphere around pev->origin.
		"in_range": user_origin.distance_to(c4_origin) <= MAX_PLAYER_USE_RADIUS,
		# The closest usable entity must be in VIEW_FIELD_NARROW (> 0.7).
		"facing": facing_dot > VIEW_FIELD_NARROW,
		"dot": facing_dot,
	}


func _round_id_for_actor(actor: Combatant) -> String:
	return "player" if actor == player else actor.name


func _actor_for_round_id(actor_id: String) -> Combatant:
	if actor_id == "player":
		return player
	for bot in _all_bots():
		if bot.name == actor_id:
			return bot
	return null


func _assigned_bomb_site(actor: TargetActor) -> Vector3:
	if bomb_sites.is_empty():
		return actor.global_position
	if not _bot_site_assignments.has(actor.name):
		var best_index := 0
		var best_distance := INF
		for site_index in range(bomb_sites.size()):
			var distance := actor.global_position.distance_squared_to(
				bomb_sites[site_index],
			)
			if distance < best_distance:
				best_distance = distance
				best_index = site_index
		_bot_site_assignments[actor.name] = best_index
	return bomb_sites[int(_bot_site_assignments[actor.name]) % bomb_sites.size()]


func _bomb_site_position_by_id(site_id: String) -> Vector3:
	for site_index in bomb_regions.size():
		if str((bomb_regions[site_index] as Dictionary).get("target", "")) == site_id:
			return bomb_sites[site_index]
	return bomb_sites[0] if not bomb_sites.is_empty() else bomb_position


func _nearest_living_terrorist_to(position: Vector3) -> TargetActor:
	var nearest: TargetActor
	var nearest_distance := INF
	for bot in _all_bots():
		if not bot.alive or bot.team != Combatant.TEAM_TERRORIST:
			continue
		var distance := bot.global_position.distance_squared_to(position)
		if distance < nearest_distance:
			nearest = bot
			nearest_distance = distance
	return nearest


func _objective_cover_position(center: Vector3, bot: TargetActor) -> Vector3:
	# ReGameDLL's hide/guard tasks select distinct nav-area hiding spots rather
	# than stopping every teammate on a concentric radius around one point.
	# These stable candidates are subsequently projected/path-resolved by the
	# bot's NavigationAgent, so each guard owns a separate destination.
	var angle := (
		float((bot.index * 137 + (0 if bot.team == Combatant.TEAM_TERRORIST else 53)) % 360)
		* PI
		/ 180.0
	)
	var radius := 3.2 + float(bot.index % 3) * 0.75
	return center + Vector3(cos(angle), 0.0, sin(angle)) * radius


func _objective_escape_position(center: Vector3, bot: TargetActor) -> Vector3:
	var away := bot.global_position - center
	away.y = 0.0
	if away.is_zero_approx():
		var angle := float((bot.index * 137 + 29) % 360) * PI / 180.0
		away = Vector3(cos(angle), 0.0, sin(angle))
	return bot.global_position + away.normalized() * 8.0


func _bot_is_attacking(bot: TargetActor) -> bool:
	return (
		bool(bot.last_command.get("fire", false))
		or str(bot.combat_state) in ["react", "engage"]
	)


func _bot_has_bomb_knowledge(bot: TargetActor) -> bool:
	if not is_instance_valid(bomb_knowledge):
		return false
	var to_bomb := bomb_position - bot.aim_point()
	var view_forward := -bot.global_transform.basis.z
	var in_fov := (
		not to_bomb.is_zero_approx()
		and not view_forward.is_zero_approx()
		and to_bomb.normalized().dot(view_forward.normalized()) > VIEW_FIELD_NARROW
	)
	var query := PhysicsRayQueryParameters3D.create(
		bot.aim_point(),
		bomb_position + Vector3.UP * 4.0 * GOLDSRC_UNIT,
		1,
		[bot.get_rid()],
	)
	query.collide_with_areas = false
	var hit: Dictionary = bot.get_world_3d().direct_space_state.intersect_ray(query)
	var line_clear: bool = hit.is_empty() or (
		is_instance_valid(bomb)
		and hit.get("collider") == bomb
	)
	bomb_knowledge.on_visual_contact(
		bot.name,
		bomb_position,
		in_fov,
		line_clear,
	)
	return bomb_knowledge.knows_exact(bot.name)


func bot_objective_context(bot: TargetActor) -> Dictionary:
	if (
		not match_started
		or not is_instance_valid(round_state)
		or not bot.alive
		or bomb_sites.is_empty()
		or phase not in [
			RoundStateScript.PHASE_LIVE,
			RoundStateScript.PHASE_BOMB,
		]
	):
		return {}

	var bomb_state := str(round_state.bomb_state)
	if phase == RoundStateScript.PHASE_BOMB:
		var bomb_ticks_left := maxi(0, round_state.bomb_deadline_tick - round_state.tick)
		var active_round_defuser := _active_round_defuser()
		if (
			bot.team == Combatant.TEAM_TERRORIST
			and BombEscapeScript.should_escape(
				bomb_ticks_left,
				float((bot.combat_controller as BotCombatController).aggression),
				false,
				_bot_is_attacking(bot),
				false,
			)
		):
			var t_escape := _objective_escape_position(bomb_position, bot)
			return {
				"state": "escape_from_bomb",
				"action": "flee",
				"target": t_escape,
				"look_target": bomb_position,
				"stop_radius": 0.32,
			}
		if bot.team == Combatant.TEAM_COUNTER_TERRORIST:
			if is_instance_valid(active_round_defuser) and active_round_defuser != bot:
				var coordinated_guard_target := _objective_cover_position(
					active_round_defuser.global_position,
					bot,
				)
				return {
					"state": "guard_defuser",
					"action": "guard",
					"target": coordinated_guard_target,
					"look_target": bomb_position,
					"stop_radius": 0.32,
				}
			if not _bot_has_bomb_knowledge(bot):
				var search_site := bomb_sites[0]
				var known_site := bomb_knowledge.known_site(bot.name)
				if not known_site.is_empty():
					search_site = _bomb_site_position_by_id(known_site)
				else:
					search_site = bomb_sites[bot.index % bomb_sites.size()]
				return {
					"state": "search_planted_site",
					"action": "search_site",
					"target": search_site,
					"look_target": search_site,
					"stop_radius": 0.42,
					"round_number": round_state.round_number,
				}
			var has_kit := bool(
				round_state.players.get(bot.name, {}).get("has_defuser", false)
			)
			var needed_ticks := (
				int(round_state.config.defuse_kit_ticks)
				if has_kit
				else int(round_state.config.defuse_ticks)
			)
			if (
				BombEscapeScript.should_escape(
					bomb_ticks_left,
					float((bot.combat_controller as BotCombatController).aggression),
					has_kit,
					_bot_is_attacking(bot),
					active_round_defuser == bot,
				)
			):
				var ct_escape := _objective_escape_position(bomb_position, bot)
				return {
					"state": "escape_from_bomb",
					"action": "flee",
					"target": ct_escape,
					"look_target": bomb_position,
					"stop_radius": 0.32,
				}
			if is_instance_valid(active_round_defuser) and active_round_defuser != bot:
				var active_guard_target := _objective_cover_position(
					active_round_defuser.global_position,
					bot,
				)
				return {
					"state": "guard_defuser",
					"action": "guard",
					"target": active_guard_target,
					"look_target": bomb_position,
					"stop_radius": 0.32,
				}
			var assigned_defuser := _active_bot_defuser()
			if assigned_defuser != bot:
				var guard_center := (
					assigned_defuser.global_position
					if is_instance_valid(assigned_defuser)
					else bomb_position
				)
				var guard_target := _objective_cover_position(guard_center, bot)
				return {
					"state": "guard_defuser",
					"action": "guard",
					"target": guard_target,
					"look_target": bomb_position,
					"stop_radius": 0.32,
				}
			var within_approach_radius := (
				bot.global_position.distance_to(bomb_position)
				<= 100.0 * GOLDSRC_UNIT
			)
			return {
				"state": "retake",
				"action": "defuse",
				"target": bomb_position,
				"look_target": bomb_position + Vector3.UP * 0.04,
				"stop_radius": 0.42,
				"crouch": within_approach_radius,
			}
		var bomb_cover := _objective_cover_position(bomb_position, bot)
		return {
			"state": "defend_bomb",
			"action": "cover",
			"target": bomb_cover,
			"look_target": bomb_position,
			"stop_radius": 0.32,
		}

	if bomb_state == RoundStateScript.BOMB_DROPPED:
		if bot.team == Combatant.TEAM_TERRORIST:
			var recoverer := _nearest_living_terrorist_to(round_state.bomb_position)
			var loose_c4_target: Vector3 = (
				round_state.bomb_position
				if recoverer == bot
				else _objective_cover_position(round_state.bomb_position, bot)
			)
			return {
				"state": "recover_c4" if recoverer == bot else "cover_c4",
				"action": "recover" if recoverer == bot else "cover",
				"target": loose_c4_target,
				"look_target": round_state.bomb_position,
				"stop_radius": 0.18 if recoverer == bot else 0.32,
			}
		if not _bot_has_bomb_knowledge(bot):
			return {}
		var ct_loose_cover := _objective_cover_position(round_state.bomb_position, bot)
		return {
			"state": "guard_dropped_c4",
			"action": "guard",
			"target": ct_loose_cover,
			"look_target": round_state.bomb_position,
			"stop_radius": 0.32,
		}

	if bot.team == Combatant.TEAM_TERRORIST:
		var carrier := _actor_for_round_id(str(round_state.bomb_owner))
		if carrier == bot:
			var site := _assigned_bomb_site(bot)
			var inside := not _bomb_region_at(
				bot.global_position,
				TargetActor.STANDING_HULL_SIZE,
			).is_empty()
			var plant_look := -bot.global_transform.basis.z
			plant_look.y = 0.0
			if plant_look.is_zero_approx():
				plant_look = Vector3(0.0, 0.0, -1.0)
			plant_look = (
				bot.global_position + plant_look.normalized() * 10.0 * GOLDSRC_UNIT
			)
			plant_look.y = bot.global_position.y
			return {
				"state": "plant_c4" if inside else "carry_c4",
				"action": "plant" if inside else "route_to_site",
				"target": site,
				"site_candidates": bomb_sites.duplicate(),
				"look_target": plant_look if inside else site,
				"stop_radius": 0.05 if inside else 0.28,
				"equip_c4": inside,
				"crouch": inside,
				"plant_in_progress": str(round_state.plant_actor) == bot.name,
				"round_number": round_state.round_number,
				"live_elapsed_ticks": (
					int(round_state.config.round_ticks)
					- maxi(0, round_state.deadline_tick - round_state.tick)
				),
			}
		# ReGameDLL does not blanket-assign every non-carrier as a follower.
		# Without a radio/follow role they retain normal hunt/combat behavior,
		# which also prevents the entire T team converging on a stationary
		# human carrier at spawn.
		return {}

	# Counter-Terrorists split into source-like roles: alternating bots guard
	# the two bombsites while their teammates patrol/hunt. Assigning all five
	# to static guard tasks can leave a spawn-adjacent guard with no route and
	# recreates the original stuck-player crowd.
	if bot.index % 2 == 1:
		return {}
	var defense_site := bomb_sites[bot.index % bomb_sites.size()]
	var defense_cover := _objective_cover_position(defense_site, bot)
	return {
		"state": "defend_site",
		"action": "guard",
		"target": defense_cover,
		"look_target": defense_site,
		"stop_radius": 0.32,
	}


func _consume_new_round_trace() -> void:
	if not is_instance_valid(round_state):
		return
	if _consumed_round_events >= round_state.trace.size():
		return
	var events: Array[Dictionary] = round_state.trace.slice(_consumed_round_events)
	_consumed_round_events = round_state.trace.size()
	_consume_round_events(events)


func _consume_round_events(events: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		match str(event.type):
			"phase":
				_apply_round_phase(str(event.phase))
			"round_start":
				if int(event.round) > 1:
					_reset_combatants_for_round()
				_c4_equipped = false
				_c4_drop_animation_played = false
				_bot_site_assignments.clear()
				_reset_bot_defuser_assignment()
				round_ending = false
				kills = 0
				if is_instance_valid(bomb_knowledge):
					bomb_knowledge.reset_round()
					bomb_knowledge.on_bomb_carried()
				_update_scoreboard()
			"bomb_dropped":
				_c4_equipped = false
				if is_instance_valid(bomb_knowledge):
					bomb_knowledge.on_bomb_dropped(event.position)
				_spawn_dropped_c4(
					event.position,
					_actor_for_round_id(str(event.player_id)),
				)
			"bomb_picked_up":
				_c4_equipped = false
				if is_instance_valid(bomb_knowledge):
					bomb_knowledge.on_bomb_picked_up()
				_clear_dropped_c4()
			"plant_start":
				_c4_drop_animation_played = false
				_set_objective_actor_frozen(str(event.player_id), true, "plant")
				if str(event.player_id) == "player":
					player.viewmodel._start_animation("pressbutton", false)
			"plant_abort":
				_set_objective_actor_frozen(str(event.player_id), false, "plant")
				_c4_drop_animation_played = false
				if str(event.player_id) == "player" and player.active_weapon == "c4":
					player.viewmodel._start_animation("idle1", true)
			"defuse_start":
				_set_objective_actor_frozen(str(event.player_id), true, "defuse")
			"defuse_abort":
				_set_objective_actor_frozen(str(event.player_id), false, "defuse")
			"bomb_planted":
				_c4_equipped = false
				_reset_bot_defuser_assignment()
				_clear_dropped_c4()
				_spawn_bomb_visual(
					event.position,
					float(event.get("yaw", 0.0)),
				)
				if is_instance_valid(bomb_knowledge):
					bomb_knowledge.on_bomb_planted(
						event.position,
						_round_actor_positions(),
					)
					var ct_ids: Array[String] = []
					for bot in _all_bots():
						if bot.team == Combatant.TEAM_COUNTER_TERRORIST:
							ct_ids.append(bot.name)
					bomb_knowledge.broadcast_planted_site(
						str(event.get("site_id", "")),
						ct_ids,
					)
				_emit_world_audio(
					"c4.plant",
					AudioRouterScript.CHAN_WEAPON,
					bomb_position,
				)
				_emit_world_audio(
					"radio.bomb_planted",
					AudioRouterScript.CHAN_STREAM,
					Vector3.ZERO,
					{"attenuation": AudioRouterScript.ATTN_NONE},
				)
				hud.show_banner(
					"THE BOMB HAS BEEN PLANTED",
					Color("#ff9e68"),
					1.8,
				)
			"bomb_beep":
				var wave := clampi(int(event.wave), 1, 5)
				if is_instance_valid(bomb_knowledge):
					bomb_knowledge.on_bomb_beep(
						event.position,
						_round_actor_positions(),
					)
				_emit_world_audio(
					"c4.beep%d" % wave,
					AudioRouterScript.CHAN_VOICE,
					event.position,
					{"attenuation": [1.5, 1.0, 0.8, 0.5, 0.2][wave - 1]},
				)
			"bomb_defused":
				_bot_defuser_id = ""
				_set_objective_actor_frozen(str(event.player_id), false, "defuse")
				hud.show_banner("THE BOMB HAS BEEN DEFUSED", Color("#77d9ff"), 2.0)
			"bomb_exploded":
				_apply_c4_explosion(event)
			"money", "purchase":
				if str(event.player_id) == "player":
					money = int(event.balance)
			"round_end":
				player.set_objective_movement_locked(false)
				round_ending = true
				_emit_round_result(event)
				_update_scoreboard()
			"halftime":
				hud.show_banner("HALFTIME", Color("#ffca66"), 2.0)
			"match_end":
				match_started = false
				player.controls_enabled = false


func _round_actor_positions() -> Dictionary:
	var result := {"player": player.global_position}
	for bot in _all_bots():
		result[bot.name] = bot.global_position
	return result


func _set_objective_actor_frozen(
	actor_id: String,
	frozen: bool,
	action := "",
) -> void:
	if actor_id == "player":
		player.set_objective_movement_locked(frozen, frozen)
		player.controls_enabled = (
			player.alive
			and phase in [
				RoundStateScript.PHASE_LIVE,
				RoundStateScript.PHASE_BOMB,
			]
		)
		return
	for bot in _all_bots():
		if bot.name == actor_id:
			var look_target := Vector3.INF
			if frozen and action == "defuse":
				look_target = bomb_position
			elif frozen and action == "plant":
				var forward := -bot.global_transform.basis.z
				forward.y = 0.0
				if forward.is_zero_approx():
					forward = Vector3(0.0, 0.0, -1.0)
				look_target = bot.global_position + forward.normalized() * 0.1
				look_target.y = bot.global_position.y
			bot.set_objective_lock(frozen, frozen, look_target)
			bot.active = bot.alive
			return


func _apply_round_phase(next_phase: String) -> void:
	match next_phase:
		RoundStateScript.PHASE_FREEZE:
			player.controls_enabled = false
			player.set_objective_movement_locked(false)
			for target in _all_bots():
				target.set_objective_lock(false)
				target.active = false
		RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB:
			player.set_objective_movement_locked(false)
			player.controls_enabled = player.alive
			for target in _all_bots():
				if str(round_state.plant_actor) != target.name and str(round_state.defuse_actor) != target.name:
					target.set_objective_lock(false)
				target.active = target.alive
		RoundStateScript.PHASE_POST, RoundStateScript.PHASE_INTERMISSION:
			player.controls_enabled = false
			player.set_objective_movement_locked(false)
			for target in _all_bots():
				target.set_objective_lock(false)
				target.active = false


func _sync_round_public_state() -> void:
	if not is_instance_valid(round_state):
		return
	phase = str(round_state.phase)
	round_number = int(round_state.round_number)
	seconds_left = float(round_state.seconds_left())
	ct_score = int(round_state.ct_score)
	terrorist_score = int(round_state.terrorist_score)
	bomb_planted = str(round_state.bomb_state) == RoundStateScript.BOMB_PLANTED
	bomb_position = round_state.bomb_position
	round_ending = phase == RoundStateScript.PHASE_POST
	if round_state.players.has("player"):
		money = int(round_state.players.player.money)
	_sync_player_c4_ownership()
	_sync_bot_c4_ownership()


func _update_round_hud(force := false) -> void:
	if not is_instance_valid(hud):
		return
	var displayed_second := int(ceil(seconds_left))
	if force or displayed_second != _last_hud_second:
		_last_hud_second = displayed_second
		hud.update_match(
			round_number,
			phase,
			seconds_left,
			ct_score,
			terrorist_score,
			money,
		)
	var action: Dictionary = round_state.action_progress()
	if not action.is_empty():
		if (
			str(action.action) == "plant"
			and str(action.actor) == "player"
			and not _c4_drop_animation_played
			and int(action.elapsed_ticks) >= int(action.duration_ticks) - 75
		):
			_c4_drop_animation_played = true
			player.viewmodel._start_animation("drop", false)
		var percent := int(
			float(action.elapsed_ticks) / float(action.duration_ticks) * 100.0
		)
		hud.update_objective(
			"%s  %d%%"
			% [
				"PLANTING" if str(action.action) == "plant" else "DEFUSING",
				clampi(percent, 0, 100),
			],
		)
	elif phase == RoundStateScript.PHASE_BOMB:
		hud.update_objective("DEFEND THE BOMB")
	elif phase == RoundStateScript.PHASE_LIVE:
		var site := _bomb_region_at(
			player.global_position,
			_player_hull_size(),
		)
		hud.update_objective(
			"PRESS 5, THEN HOLD FIRE TO PLANT"
			if str(round_state.bomb_owner) == "player" and not site.is_empty()
			else "ELIMINATE OR PLANT"
		)


func _sync_player_c4_ownership() -> void:
	if not is_instance_valid(player) or not is_instance_valid(round_state):
		return
	var should_own := (
		str(round_state.bomb_owner) == "player"
		and str(round_state.bomb_state) in [
			RoundStateScript.BOMB_CARRIED,
			RoundStateScript.BOMB_PLANTING,
		]
		and bool(round_state.players.get("player", {}).get("has_c4", false))
	)
	if should_own:
		if not player.owns_weapon("c4"):
			player.grant_item("c4")
		_c4_equipped = player.active_weapon == "c4"
		return
	if player.active_weapon == "c4":
		player.switch_weapon(player._best_owned_weapon())
	player.owned_weapons.erase("c4")
	player.ammunition.erase("c4")
	_c4_equipped = false


func _equip_player_c4() -> bool:
	if (
		not is_instance_valid(round_state)
		or str(round_state.bomb_owner) != "player"
		or str(round_state.bomb_state) not in [
			RoundStateScript.BOMB_CARRIED,
			RoundStateScript.BOMB_PLANTING,
		]
		or not player.owns_weapon("c4")
	):
		return false
	player.switch_weapon("c4")
	return player.active_weapon == "c4"


func _sync_bot_c4_ownership() -> void:
	if not is_instance_valid(round_state):
		return
	for bot in _all_bots():
		var owned := (
			str(round_state.bomb_owner) == bot.name
			and str(round_state.bomb_state) in [
				RoundStateScript.BOMB_CARRIED,
				RoundStateScript.BOMB_PLANTING,
			]
			and bool(round_state.players.get(bot.name, {}).get("has_c4", false))
		)
		var equipped := (
			owned
			and (
				bool(bot.last_command.get("c4_equipped", false))
				or str(round_state.plant_actor) == bot.name
			)
		)
		bot.set_c4_state(owned, equipped)


func _reset_combatants_for_round() -> void:
	bomb_planted = false
	_next_c4_beep_tick = -1
	_c4_beep_index = 0
	if is_instance_valid(bomb):
		bomb.queue_free()
	bomb = null
	_clear_dropped_c4()
	_reset_bot_defuser_assignment()
	var keep_loadout := not player.is_dead()
	player.reset_player(player_spawn, keep_loadout)
	if using_imported_map and not target_spawns.is_empty():
		player.face_toward(target_spawns[0])
	for target_index in range(targets.size()):
		targets[target_index].reset_target(target_spawns[target_index])
	for ally_index in range(allied_bots.size()):
		allied_bots[ally_index].reset_target(allied_spawns[ally_index])
	hud.update_health(player.health, player.armor)
	hud.update_ammo(player.clip, player.reserve, player.reloading)
	_update_scoreboard()


func _spawn_dropped_c4(
	position: Vector3,
	dropped_by: Combatant = null,
) -> void:
	_clear_dropped_c4()
	var forward := Vector3(0.0, 0.0, -1.0)
	if is_instance_valid(dropped_by):
		forward = -dropped_by.global_transform.basis.z
		forward.y = 0.0
		if forward.is_zero_approx():
			forward = Vector3(0.0, 0.0, -1.0)
		else:
			forward = forward.normalized()
	var drop := C4DropContractScript.build_drop(position, forward)
	dropped_c4 = C4WorldScript.new()
	dropped_c4.position = drop.origin
	dropped_c4.pickup_requested.connect(_on_dropped_c4_pickup)
	add_child(dropped_c4)
	dropped_c4.linear_velocity = drop.velocity


func _request_drop_active_weapon() -> bool:
	if not is_instance_valid(round_state) or not is_instance_valid(player):
		return false
	var request := C4DropContractScript.resolve_manual_drop(
		player.active_weapon,
		player.alive,
		str(round_state.bomb_owner) == "player",
		str(round_state.bomb_state),
		player.global_position,
		-player.global_transform.basis.z,
	)
	if not bool(request.allowed):
		return false
	if not round_state.drop_bomb("player", player.global_position):
		return false
	_consume_new_round_trace()
	_sync_round_public_state()
	player.switch_weapon(player._best_owned_weapon())
	return true


func _clear_dropped_c4() -> void:
	if is_instance_valid(dropped_c4):
		dropped_c4.queue_free()
	dropped_c4 = null


func _on_dropped_c4_pickup(actor: Combatant) -> void:
	if (
		not is_instance_valid(round_state)
		or not is_instance_valid(actor)
		or not actor.alive
	):
		return
	if round_state.pickup_bomb(
		_round_id_for_actor(actor),
		actor.global_position,
	):
		_consume_new_round_trace()
		_sync_round_public_state()


func _update_scoreboard() -> void:
	if not is_instance_valid(hud) or not is_instance_valid(round_state):
		return
	var rows: Array = []
	for raw_row: Dictionary in round_state.scoreboard_snapshot():
		var row := raw_row.duplicate()
		row.team = 2 if str(raw_row.team) == Combatant.TEAM_COUNTER_TERRORIST else 1
		row.latency = 0
		rows.append(row)
	hud.update_scoreboard(
		rows,
		"Protocol 47",
		"de_dust2" if using_imported_map else "training",
		ct_score,
		terrorist_score,
	)


func _spawn_bomb_visual(position: Vector3, planter_yaw := 0.0) -> void:
	bomb_planted = true
	if is_instance_valid(bomb):
		bomb.queue_free()
	bomb = Node3D.new()
	bomb.name = "PlantedBomb"
	bomb.add_child(C4WorldScript.create_planted_visual())
	var body := StaticBody3D.new()
	body.name = "C4UseBody"
	body.collision_layer = 8
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# ShootSatchelCharge uses mins(-3,-6,0), maxs(3,6,8) HU.
	shape.size = Vector3(6.0, 8.0, 12.0) * GOLDSRC_UNIT
	shape_node.shape = shape
	shape_node.position.y = 4.0 * GOLDSRC_UNIT
	body.add_child(shape_node)
	bomb.add_child(body)
	bomb.position = position
	# CGrenade::ShootSatchelCharge receives pev->angles.y - 90.
	bomb.rotation.y = planter_yaw - deg_to_rad(90.0)
	bomb_position = position
	add_child(bomb)


func _apply_c4_explosion(event: Dictionary) -> void:
	var origin: Vector3 = event.position
	var radius_m := float(event.radius_hu) * 0.01
	var base_damage := float(event.damage)
	var planter := _actor_for_round_id(str(event.get(
		"attacker_id",
		event.get("planter_id", event.get("player_id", "")),
	)))
	# Explode2 makes the grenade invisible and non-solid before RadiusDamage.
	if is_instance_valid(bomb):
		bomb.visible = false
		for child in bomb.get_children():
			if child is CollisionObject3D:
				(child as CollisionObject3D).collision_layer = 0
				(child as CollisionObject3D).collision_mask = 0
	var effects := CombatEffectsScript.for_scene(self)
	var blast_underwater := _source_point_in_water(origin)
	if is_instance_valid(effects):
		effects.spawn_c4_explosion(origin, Vector3.UP, blast_underwater)
	_emit_world_audio(
		"c4.explode",
		AudioRouterScript.CHAN_WEAPON,
		origin,
		{"attenuation": 0.25},
	)
	for node in get_tree().get_nodes_in_group("combatants"):
		var combatant := node as Combatant
		if not is_instance_valid(combatant) or not combatant.alive:
			continue
		var water_level := _source_water_level(combatant)
		if (
			(blast_underwater and water_level == 0)
			or (not blast_underwater and water_level == 3)
		):
			continue
		var distance := combatant.global_position.distance_to(origin)
		if distance > radius_m:
			continue
		var damage := base_damage * maxf(0.0, 1.0 - distance / radius_m)
		combatant.receive_c4_explosion_damage(damage, origin, planter)
	if is_instance_valid(bomb):
		bomb.queue_free()
		bomb = null
	bomb_planted = false


func _source_point_in_water(point: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("water_volumes"):
		if node.has_method("contains_point") and bool(node.call("contains_point", point)):
			return true
	return false


func _source_water_level(combatant: Combatant) -> int:
	if combatant.has_meta("source_water_level"):
		return clampi(int(combatant.get_meta("source_water_level")), 0, 3)
	var samples := [
		combatant.global_position + Vector3.UP * 2.0 * GOLDSRC_UNIT,
		combatant.global_position + Vector3.UP * 36.0 * GOLDSRC_UNIT,
		combatant.global_position + Vector3.UP * 71.0 * GOLDSRC_UNIT,
	]
	var level := 0
	for sample: Vector3 in samples:
		if _source_point_in_water(sample):
			level += 1
	return level


func _sync_dropped_c4_position() -> void:
	if (
		not is_instance_valid(round_state)
		or str(round_state.bomb_state) != RoundStateScript.BOMB_DROPPED
		or not is_instance_valid(dropped_c4)
	):
		return
	if round_state.update_dropped_bomb_position(dropped_c4.global_position):
		bomb_position = dropped_c4.global_position


func _emit_round_result(event: Dictionary) -> void:
	var terrorists_won := str(event.winner) == RoundStateScript.TEAM_T
	_emit_world_audio(
		"round.t_win" if terrorists_won else "round.ct_win",
		AudioRouterScript.CHAN_STREAM,
		Vector3.ZERO,
		{"attenuation": AudioRouterScript.ATTN_NONE},
	)
	var labels := {
		"target_bombed": "TARGET BOMBED  •  TERRORISTS WIN",
		"bomb_defused": "BOMB DEFUSED  •  COUNTER-TERRORISTS WIN",
		"target_saved": "TARGET SAVED  •  COUNTER-TERRORISTS WIN",
		"terrorists_win": "TERRORISTS WIN",
		"cts_win": "COUNTER-TERRORISTS WIN",
	}
	hud.show_banner(
		str(labels.get(str(event.reason), str(event.reason).to_upper())),
		Color("#ff9e68") if terrorists_won else Color("#77d9ff"),
		2.0,
	)


# Retained as a test/diagnostic compatibility entry point. Live planting is driven
# exclusively by CS16RoundState's 100 Hz command path.
func _plant_bomb(site: Vector3) -> void:
	phase = "bomb"
	seconds_left = BOMB_SECONDS
	_spawn_bomb_visual(site)
	_emit_world_audio("c4.plant", AudioRouterScript.CHAN_WEAPON, bomb.global_position)
	_emit_world_audio(
		"radio.bomb_planted",
		AudioRouterScript.CHAN_STREAM,
		Vector3.ZERO,
		{"attenuation": AudioRouterScript.ATTN_NONE},
	)
	_c4_beep_index = 0
	_next_c4_beep_tick = audio_router.current_tick
	hud.show_banner("THE BOMB HAS BEEN PLANTED", Color("#ff9e68"), 1.8)
	hud.update_objective("DEFEND THE BOMB")


func _explode_bomb() -> void:
	if not bomb_planted:
		return
	_emit_world_audio(
		"c4.explode",
		AudioRouterScript.CHAN_WEAPON,
		bomb.global_position,
		{"attenuation": 0.25},
	)
	_next_c4_beep_tick = -1
	var flash := OmniLight3D.new()
	flash.light_color = Color("#ff8b38")
	flash.light_energy = 12.0
	flash.omni_range = 18.0
	bomb.add_child(flash)
	_end_round(true, "TARGET BOMBED  •  TERRORISTS WIN")
