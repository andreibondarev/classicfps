extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TargetScript = preload("res://scripts/target.gd")
const HUDScript = preload("res://scripts/hud.gd")
const BspMapScript = preload("res://scripts/bsp_map.gd")
const AudioRouterScript = preload("res://scripts/cs16_audio_event_router.gd")
const AudioPlaybackScript = preload("res://scripts/cs16_audio_playback_adapter.gd")
const RoundStateScript = preload("res://scripts/cs16_round_state.gd")
const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")

const FREEZE_SECONDS := 6.0
const ROUND_SECONDS := 300.0
const BOMB_SECONDS := 45.0
const PLANT_SECONDS := 3.0
const GOLDSRC_UNIT := 0.01
const MAX_PLAYER_USE_RADIUS := 64.0 * GOLDSRC_UNIT
const VIEW_FIELD_NARROW := 0.7
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
		_c4_equipped = (
			is_instance_valid(round_state)
			and str(round_state.bomb_owner) == "player"
			and str(round_state.bomb_state) == RoundStateScript.BOMB_CARRIED
		)
		if _c4_equipped:
			hud.update_objective("C4 EQUIPPED  •  HOLD FIRE IN A BOMB SITE")
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
			"player" if target.team == Combatant.TEAM_COUNTER_TERRORIST else "",
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
		"",
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
	if phase == RoundStateScript.PHASE_LIVE and is_instance_valid(player):
		var site := _bomb_region_at(
			player.global_position,
			_player_hull_size(),
		)
		command.plant = {
			"player_id": "player",
			"attack": Input.is_action_pressed("fire"),
			"equipped_c4": _c4_equipped,
			"grounded": player.is_on_floor(),
			"in_bomb_site": not site.is_empty(),
			"site_id": str(site.get("target", "")),
			"position": player.global_position,
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
		elif player.team == Combatant.TEAM_COUNTER_TERRORIST:
			command.defuse = _defuse_request(
				player,
				Input.is_action_pressed("use"),
			)
		else:
			var bot_defuser := _active_bot_defuser()
			if is_instance_valid(bot_defuser):
				command.defuse = _defuse_request(bot_defuser, true)
	return command


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
	var nearest: TargetActor
	var nearest_distance := INF
	for target in targets:
		if (
			not target.alive
			or target.team != Combatant.TEAM_COUNTER_TERRORIST
		):
			continue
		var distance := target.global_position.distance_to(bomb_position)
		if distance < nearest_distance:
			nearest = target
			nearest_distance = distance
	return nearest


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
	var geometry := _c4_use_geometry(
		actor.global_position,
		eye_position,
		view_forward,
		bomb_position,
	)
	return {
		"player_id": actor.name,
		"use": use_pressed,
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
				round_ending = false
				kills = 0
				_update_scoreboard()
			"bomb_dropped":
				_c4_equipped = false
			"bomb_picked_up":
				_c4_equipped = false
			"plant_start":
				player.controls_enabled = false
			"plant_abort":
				player.controls_enabled = player.alive and phase == "live"
			"defuse_start":
				_set_objective_actor_frozen(str(event.player_id), true)
			"defuse_abort":
				_set_objective_actor_frozen(str(event.player_id), false)
			"bomb_planted":
				_c4_equipped = false
				_spawn_bomb_visual(event.position)
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
				_emit_world_audio(
					"c4.beep%d" % wave,
					AudioRouterScript.CHAN_VOICE,
					event.position,
					{"attenuation": [1.5, 1.0, 0.8, 0.5, 0.2][wave - 1]},
				)
			"bomb_defused":
				hud.show_banner("THE BOMB HAS BEEN DEFUSED", Color("#77d9ff"), 2.0)
			"bomb_exploded":
				_apply_c4_explosion(event)
			"money", "purchase":
				if str(event.player_id) == "player":
					money = int(event.balance)
			"round_end":
				round_ending = true
				_emit_round_result(event)
				_update_scoreboard()
			"halftime":
				hud.show_banner("HALFTIME", Color("#ffca66"), 2.0)
			"match_end":
				match_started = false
				player.controls_enabled = false


func _set_objective_actor_frozen(actor_id: String, frozen: bool) -> void:
	if actor_id == "player":
		player.controls_enabled = (
			not frozen
			and player.alive
			and phase in [
				RoundStateScript.PHASE_LIVE,
				RoundStateScript.PHASE_BOMB,
			]
		)
		return
	for bot in _all_bots():
		if bot.name == actor_id:
			bot.active = not frozen and bot.alive
			return


func _apply_round_phase(next_phase: String) -> void:
	match next_phase:
		RoundStateScript.PHASE_FREEZE:
			player.controls_enabled = false
			for target in _all_bots():
				target.active = false
		RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB:
			player.controls_enabled = player.alive
			for target in _all_bots():
				target.active = target.alive
		RoundStateScript.PHASE_POST, RoundStateScript.PHASE_INTERMISSION:
			player.controls_enabled = false
			for target in _all_bots():
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
		return
	player.owned_weapons.erase("c4")
	player.ammunition.erase("c4")

	# Ownership can use Player's public inventory API today. Equipping the
	# source v_c4 model remains an explicit boundary: Player's generic primary
	# path treats every non-grenade item as a firearm, so switching to C4 here
	# would emit a fake bullet and consume its clip. Game owns the virtual
	# `_c4_equipped` plant input until Player exposes an objective-use callback.


func _reset_combatants_for_round() -> void:
	bomb_planted = false
	_next_c4_beep_tick = -1
	_c4_beep_index = 0
	if is_instance_valid(bomb):
		bomb.queue_free()
	bomb = null
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


func _spawn_bomb_visual(position: Vector3) -> void:
	bomb_planted = true
	if is_instance_valid(bomb):
		bomb.queue_free()
	bomb = Node3D.new()
	bomb.name = "PlantedBomb"
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.28, 0.16, 0.42)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#263128")
	material.emission_enabled = true
	material.emission = Color("#4b160f")
	mesh.material = material
	mesh_node.mesh = mesh
	bomb.add_child(mesh_node)
	bomb.position = position + Vector3.UP * 0.1
	bomb_position = position
	add_child(bomb)


func _apply_c4_explosion(event: Dictionary) -> void:
	var origin: Vector3 = event.position
	var radius_m := float(event.radius_hu) * 0.01
	var base_damage := float(event.damage)
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
		var distance := combatant.global_position.distance_to(origin)
		if distance > radius_m:
			continue
		var damage := base_damage * maxf(0.0, 1.0 - distance / radius_m)
		combatant.receive_explosion_damage(damage, origin, null)


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
	bomb_planted = true
	phase = "bomb"
	seconds_left = BOMB_SECONDS
	bomb = Node3D.new()
	bomb.name = "PlantedBomb"
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.28, 0.16, 0.42)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#263128")
	material.emission_enabled = true
	material.emission = Color("#4b160f")
	mesh.material = material
	mesh_node.mesh = mesh
	bomb.add_child(mesh_node)
	bomb.position = site + Vector3.UP * 0.1
	add_child(bomb)
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
