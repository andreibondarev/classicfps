extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TargetScript = preload("res://scripts/target.gd")
const HUDScript = preload("res://scripts/hud.gd")
const BspMapScript = preload("res://scripts/bsp_map.gd")
const AudioCatalogScript = preload("res://scripts/cs16_audio_catalog.gd")
const AudioRouterScript = preload("res://scripts/cs16_audio_event_router.gd")
const AudioPlaybackScript = preload("res://scripts/cs16_audio_playback_adapter.gd")
const RoundStateScript = preload("res://scripts/cs16_round_state.gd")
const KeyBindings := preload("res://scripts/cs16_key_bindings.gd")
const AdminLogScript := preload("res://scripts/admin_log.gd")
const ModerationScript := preload("res://scripts/moderation.gd")
const LoadingBudget := preload("res://scripts/loading_budget.gd")
const NetworkSessionScript := preload("res://scripts/network_session.gd")
const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")
const C4WorldScript = preload("res://scripts/cs16_c4_world.gd")
const CombatEffectsScript = preload("res://scripts/cs16_combat_effects.gd")
const BombKnowledgeScript = preload("res://scripts/cs16_bomb_knowledge.gd")
const PlayerUseResolverScript = preload("res://scripts/cs16_player_use_resolver.gd")
const C4DropContractScript = preload("res://scripts/cs16_c4_drop_contract.gd")
const DroppedWeaponScript = preload("res://scripts/cs16_dropped_weapon.gd")
const BombEscapeScript = preload("res://scripts/cs16_bomb_escape.gd")
const BotBuyPlanScript = preload("res://scripts/cs16_bot_buy_plan.gd")
const ScenarioRulesScript = preload("res://scripts/cs16_scenario_rules.gd")
const EntityWorldScript = preload("res://scripts/cs16_entity_world.gd")
const BrushRuntimeScript = preload("res://scripts/cs16_brush_runtime.gd")
const BreakableRuntimeScript = preload("res://scripts/cs16_breakable_runtime.gd")
const BreakableProxyScript = preload("res://scripts/cs16_breakable_collision_proxy.gd")
const BreakableDebrisScript = preload("res://scripts/cs16_breakable_debris_presenter.gd")
const HostageStateScript = preload("res://scripts/cs16_hostage_state.gd")
const SpectatorCameraScript = preload("res://scripts/cs16_spectator_camera.gd")
const HostageActorScript = preload("res://scripts/cs16_hostage.gd")
const RemoteRosterScript = preload("res://scripts/remote_human_roster.gd")

const MATCH_MAX_ROUNDS := 30
const MATCH_WIN_LIMIT := 16
const FREEZE_SECONDS := 6.0
const ROUND_SECONDS := 300.0
const BOMB_SECONDS := 45.0
const PLANT_SECONDS := 3.0
const GOLDSRC_UNIT := 0.01
const MAX_PLAYER_USE_RADIUS := 64.0 * GOLDSRC_UNIT
const VIEW_FIELD_NARROW := 0.7
const BRUSH_TOUCH_CONTACT_EPSILON := 0.002
const BOT_DEFUSER_STALL_FRAMES := 500
const BOT_DEFUSER_PROGRESS_EPSILON := 8.0 * GOLDSRC_UNIT
const LEGACY_BUY_RADIUS := 200.0 * GOLDSRC_UNIT
# CWeaponBox pickup is a player-hull touch; ~1 m covers the 32-HU hull plus
# the box extents at this project's 0.01 world scale.
const WEAPON_PICKUP_RADIUS := 1.0
const WEAPON_DROP_TOSS_DISTANCE := 0.5
const DEFAULT_MAP_NAME := "de_dust2"
const SUPPORTED_MAP_NAMES := ["de_dust2", "cs_assault", "de_inferno"]
## Dedicated servers move to the next map once a match ends. cs_assault is
## left out: the browser build does not ship its assets.
const MAP_ROTATION := ["de_dust2", "de_inferno"]
const MAP_CHANGE_DELAY_SECONDS := 10.0
const BOMB_SEARCH_REACHED_RADIUS := 0.8
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
var combat_effects: CS16CombatEffects
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
var dropped_weapons: Array[CS16DroppedWeapon] = []
var bomb_position := Vector3.ZERO
var bomb_sites: Array[Vector3] = []
var bomb_regions: Array[Dictionary] = []
var buy_regions: Array[Dictionary] = []
var imported_map: BspMap
var deploy_camera: Camera3D
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
var _objective_audio_schedule: Array[Dictionary] = []
var round_state: RefCounted
var _consumed_round_events := 0
var _round_loadout_reset_pending := false
var _last_hud_second := -1
var _last_hud_money := -1
var _scoreboard_refresh_seconds := 0.0
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
var map_name := DEFAULT_MAP_NAME
var _following_host_map := false
var _bomb_search_progress := {}
var imported_map_path := "res://generated/%s/map.json" % DEFAULT_MAP_NAME
var scenario := ScenarioRulesScript.SCENARIO_BOMB
var scenario_info := {}
var entity_world: CS16EntityWorld
## Dedicated server only (--moderation=): kicks, bans and mutes from the admin service.
var moderation: Node
var brush_runtime: CS16BrushRuntime
var breakable_runtime: CS16BreakableRuntime
var breakable_debris: CS16BreakableDebrisPresenter
var hostage_state: CS16HostageState
var hostage_actors: Dictionary = {}
var _human_use_was_down: Dictionary = {}
# Existing local capture probes may reset their edge without clearing peers.
var _player_use_was_down: bool:
	get:
		return bool(_human_use_was_down.get("player", false))
	set(value):
		_human_use_was_down["player"] = value
# A separate host-local namespace; neither peer IDs nor reusable pawn slots.
var _next_remote_brush_activator := 0x100000000
var _remote_brush_activator_ids: Dictionary = {}
var _remote_trigger_cameras: Dictionary = {}
var _brush_touch_pairs: Dictionary = {}
var _hostage_paths: Dictionary = {}
var _hostage_path_indices: Dictionary = {}
var _hostage_path_targets: Dictionary = {}
var _hostage_bot_assignments: Dictionary = {}
var _hostage_bot_rescue_targets: Dictionary = {}
var _hostage_floor_registration_pending := false
var trigger_camera: Camera3D
var trigger_camera_entity_id := -1
var trigger_camera_return_tick := -1
var spectator_camera: CS16SpectatorCamera
var _trigger_camera_controls_enabled := false
var remote_roster: Node
var _bot_brush_activator_ids: Dictionary = {}
var _human_death_serials: Dictionary = {}
var _network_client_mode := false
var _dedicated_server_mode := false
var _next_network_item_id := 1
var _network_objective_result := ""
var network_client_view: Node3D
var _network_menu_join_pending := false
var _network_menu_deadline_ms := 0
var _returning_offline := false
const SprayScript = preload("res://scripts/cs16_spray.gd")
var sprays: CS16Spray
const NetworkClientViewScript = preload("res://scripts/network_client_view.gd")


func _ready() -> void:
	# Gameplay children inherit this pause behavior. HUD and networking opt
	# into ALWAYS separately, so offline menus can still resume or quit.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var network := get_node("/root/NetworkSession")
	_dedicated_server_mode = bool(network.dedicated_server)
	_network_client_mode = (network.is_online() or network.is_connecting()) and not network.is_host
	_select_map_from_command_line()
	# A rotation (server) or a client following its host reloads this scene;
	# the session autoload remembers which map the shared world now runs.
	if (_dedicated_server_mode or _network_client_mode) and network.active_map in SUPPORTED_MAP_NAMES:
		_use_map(network.active_map)
	if _dedicated_server_mode:
		network.active_map = map_name
	_build_audio_runtime()
	if "--verify-packaged-audio" in OS.get_cmdline_user_args():
		# This path runs from the exported PCK. It guards against checking source
		# WAVs with FileAccess, which works in-editor but silences release builds.
		set_physics_process(false)
		_verify_packaged_audio.call_deferred()
		return
	sprays = SprayScript.new()
	sprays.name = "SprayPaint"
	add_child(sprays)
	_build_environment()
	combat_effects = CombatEffectsScript.for_scene(self)
	combat_effects.network_impact.connect(_publish_network_impact)
	combat_effects.world_audio_requested.connect(_emit_world_audio)
	audio_router.event_started.connect(_publish_network_audio)
	get_node("/root/GameSettings").changed.connect(_apply_performance_settings)
	get_node("/root/GameSettings").changed.connect(_apply_player_name)
	if not _build_imported_map():
		_build_arena()
		allied_spawns.assign(FALLBACK_ALLIED_SPAWNS)
		target_spawns.assign(FALLBACK_TARGET_SPAWNS)
		terrorist_team_spawns.assign([FALLBACK_PLAYER_SPAWN] + FALLBACK_ALLIED_SPAWNS)
		counter_terrorist_team_spawns.assign(FALLBACK_TARGET_SPAWNS)
	_build_entity_world()
	_spawn_player()
	_build_trigger_camera()
	if not _network_client_mode:
		if _dedicated_server_mode:
			# A listen server uses the first T spawn for its local player. A dedicated
			# server has no local combatant, so make that fifth slot a replaceable bot.
			allied_spawns.push_front(player_spawn)
		_spawn_targets()
	player.combat_effects = combat_effects
	for bot: TargetActor in allied_bots + targets:
		bot.combat_effects = combat_effects
	_build_hostages()
	_build_bomb_sites()
	_build_round_state()
	_build_hud()
	if _dedicated_server_mode:
		hud.visible = false
	if not _dedicated_server_mode:
		_build_spectator_camera()
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	_update_tactical_hud()
	hud.set_deploy_visible(true)
	_build_deploy_camera()
	_build_network_roster()
	network.status_changed.connect(_on_network_role_changed)
	_on_network_role_changed(str(network.status))
	if not _dedicated_server_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_performance_settings()
	_prepare_gameplay_presentation()


func _verify_packaged_audio() -> void:
	var voice_id := audio_router.emit_catalog_event(
		"glock18.fire",
		1,
		AudioRouterScript.CHAN_WEAPON,
		Vector3.ZERO,
	)
	var adapter_started := audio_playback.trace().any(func(event: Dictionary) -> bool:
		return event.kind == "start" and event.sample == "weapons/glock18-2.wav"
	)
	if voice_id < 0 or not adapter_started:
		push_error("GAME_PACKAGED_AUDIO_FAIL " + audio_router.last_error)
		get_tree().quit(1)
		return
	print("GAME_PACKAGED_AUDIO_READY")
	audio_router.stop_all("packaged_audio_probe")
	audio_playback.clear_pool()
	get_tree().quit(0)


var bot_asset_preparation: Dictionary = {}


func _build_network_roster() -> void:
	var network := get_node("/root/NetworkSession")
	var ordered_bots := _all_bots()
	ordered_bots.sort_custom(func(left: TargetActor, right: TargetActor) -> bool: return left.name.naturalnocasecmp_to(right.name) < 0)
	for index in ordered_bots.size():
		_bot_brush_activator_ids[ordered_bots[index].get_instance_id()] = entity_world.entity_count() + index + 2
	remote_roster = RemoteRosterScript.new()
	remote_roster.name = "RemoteHumanRoster"
	add_child(remote_roster)
	remote_roster.human_added.connect(_on_remote_human_added)
	remote_roster.human_removing.connect(_on_remote_human_removing)
	remote_roster.bind_session(network)
	if not network.chat_received.is_connected(_on_network_chat_received):
		network.chat_received.connect(_on_network_chat_received)
	if not network.notice_received.is_connected(_on_network_notice_received):
		network.notice_received.connect(_on_network_notice_received)
	if not _network_client_mode and not network.bind_game_actions(_handle_network_action):
		push_error("Game could not bind authoritative network actions")
	if not _network_client_mode and not network.bind_chat(_handle_network_chat):
		push_error("Game could not bind authoritative network chat")
	if not _network_client_mode and not network.bind_voice(_handle_network_voice):
		push_error("Game could not bind authoritative network voice")
	if _dedicated_server_mode and not AdminLogScript.requested_path().is_empty():
		var admin_log := AdminLogScript.new()
		admin_log.name = "AdminLog"
		add_child(admin_log)
		admin_log.start(self, network, AdminLogScript.requested_path())
	if _dedicated_server_mode and not ModerationScript.requested_path().is_empty():
		moderation = ModerationScript.new()
		moderation.name = "Moderation"
		add_child(moderation)
		moderation.start(network, ModerationScript.requested_path())
		var admin_log := get_node_or_null("AdminLog")
		if admin_log != null:
			moderation.enforced.connect(admin_log.record)


func _on_network_role_changed(_status: String) -> void:
	# A dedicated server rebuilds its scene when the last player leaves; the old
	# game may still hear this signal while it is outside the tree.
	if not is_inside_tree():
		return
	var network := get_node("/root/NetworkSession")
	if _pause_menu_open():
		# Starting/joining while an offline menu is open must release the
		# simulation pause without dismissing the local menu.
		get_tree().paused = not network.is_online()
	if (network.is_online() or network.is_connecting()) and not network.is_host and not is_instance_valid(network_client_view):
		_network_client_mode = true
		network.unbind_game_actions(_handle_network_action)
		network.unbind_chat(_handle_network_chat)
		network.unbind_voice(_handle_network_voice)
		network_client_view = NetworkClientViewScript.new()
		network_client_view.name = "NetworkClientView"
		add_child(network_client_view)
		network_client_view.bind_game(self, network)
	hud.update_network_status(str(network.status), network.is_online() or network.is_connecting(), _network_client_mode)
	if _network_client_mode and not network.is_online() and not network.is_connecting() and _status != "OFFLINE" and not _returning_offline:
		_network_menu_join_pending = false
		_set_paused(true)
		hud.show_network_menu("join")


func _exit_tree() -> void:
	var session := get_node_or_null("/root/NetworkSession")
	if is_instance_valid(session):
		session.unbind_game_actions(_handle_network_action)
		session.unbind_chat(_handle_network_chat)
		session.unbind_voice(_handle_network_voice)
		if session.chat_received.is_connected(_on_network_chat_received):
			session.chat_received.disconnect(_on_network_chat_received)
		if session.notice_received.is_connected(_on_network_notice_received):
			session.notice_received.disconnect(_on_network_notice_received)


func _chat_actor_for_peer(peer_id: int) -> PlayerController:
	if peer_id == 1:
		return player
	return _remote_join_actor(peer_id)


func _chat_recipient_peers(sender_peer_id: int, sender_team: String, team_only: bool) -> Array[int]:
	var recipients: Array[int] = []
	var candidate_peers: Array[int] = [1]
	if is_instance_valid(remote_roster):
		candidate_peers.append_array(remote_roster.peer_ids())
	for peer_id: int in candidate_peers:
		var actor := _chat_actor_for_peer(peer_id)
		if not is_instance_valid(actor):
			continue
		if not team_only or peer_id == sender_peer_id \
				or (sender_team in ["T", "CT"] and actor.team == sender_team):
			recipients.append(peer_id)
	return recipients


## Voice routing, as CS 1.6 without alltalk (ReGameDLL CanPlayerHearPlayer):
## only the speaker's team hears them, and living players do not hear the dead.
func _handle_network_voice(peer_id: int) -> Dictionary:
	if is_instance_valid(moderation) and moderation.is_muted(peer_id):
		return {}
	var sender := _remote_join_actor(peer_id)
	if not is_instance_valid(sender) or sender.team not in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
		return {}
	var recipients: Array[int] = []
	if is_instance_valid(remote_roster):
		for listener_peer: int in remote_roster.peer_ids():
			var listener := _remote_join_actor(listener_peer)
			if listener_peer == peer_id or not is_instance_valid(listener) or listener.team != sender.team:
				continue
			if not sender.alive and listener.alive:
				continue
			recipients.append(listener_peer)
	return {"sender_id": _round_id_for_actor(sender), "recipients": recipients}


func _handle_network_chat(peer_id: int, team_only: bool, text: String) -> bool:
	var sender := _chat_actor_for_peer(peer_id)
	if not is_instance_valid(sender):
		return false
	var muted: bool = is_instance_valid(moderation) and moderation.is_muted(peer_id)
	var admin_log := get_node_or_null("AdminLog")
	if admin_log != null:
		admin_log.log_chat(peer_id, sender.display_name, sender.team, team_only, text, muted)
	if muted:
		return false
	var recipients := _chat_recipient_peers(peer_id, sender.team, team_only)
	return get_node("/root/NetworkSession").publish_chat(
		_round_id_for_actor(sender),
		sender.display_name,
		sender.team,
		team_only,
		text,
		recipients,
	)


func _on_network_notice_received(message: Dictionary) -> void:
	if is_instance_valid(hud):
		hud.add_notice(message)


func _on_network_chat_received(message: Dictionary) -> void:
	if is_instance_valid(hud):
		hud.add_chat_message(message)


func _on_chat_submitted(text: String, team_only: bool) -> void:
	var network := get_node("/root/NetworkSession")
	var cleaned: String = network.sanitize_chat_text(text)
	if cleaned.is_empty():
		return
	if network.is_online():
		if not network.request_chat(cleaned, team_only):
			hud.show_banner("CHAT UNAVAILABLE", Color("#ffca66"), 1.5)
		return
	# Offline practice keeps the exact same presentation path without inventing
	# a transport peer or pretending bots are chat participants.
	hud.add_chat_message({"sender_id": "player", "sender_name": player.display_name,
		"team": player.team, "team_only": team_only, "text": cleaned})


func _handle_network_action(peer_id: int, command: Dictionary) -> Dictionary:
	var result: Dictionary
	match str(command.action):
		"spray":
			result = {"accepted": false, "reason": "action_unavailable"}
			if _spray_for_human(_remote_join_actor(peer_id)):
				result = {"accepted": true, "reason": ""}
		"join_team":
			result = select_remote_join_team(peer_id, str(command.value))
		"join_class":
			result = select_remote_join_class(peer_id, int(command.value))
		"select_weapon":
			result = select_remote_weapon(peer_id, str(command.value))
		"secondary", "drop_weapon", "reload_weapon":
			result = remote_weapon_action(peer_id, str(command.action), str(command.value))
		"buy_item":
			var human := _remote_join_actor(peer_id)
			if not is_instance_valid(human):
				result = {"accepted": false, "reason": "unknown_peer"}
			else:
				var purchase := _purchase_for_human(human, str(command.value))
				result = {"accepted": purchase.allowed, "reason": "" if purchase.allowed else purchase.reason}
		"radio":
			var human := _remote_join_actor(peer_id)
			if not is_instance_valid(human):
				result = {"accepted": false, "reason": "unknown_peer"}
			elif not match_started or _match_concluded or not human.alive \
					or human.team not in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
				result = {"accepted": false, "reason": "action_unavailable"}
			else:
				_broadcast_radio_message(human, str(command.value), peer_id)
				result = {"accepted": true, "reason": ""}
		_:
			return {"accepted": false, "reason": "internal_error"}
	var human := _remote_join_actor(peer_id)
	if is_instance_valid(human):
		result.actor_id = _round_id_for_actor(human)
		result.team = human.team
		result.class_id = int(human.get_meta("cs16_class_id", 0))
	return result


func select_remote_weapon(peer_id: int, weapon: String) -> Dictionary:
	var human := _remote_join_actor(peer_id)
	if not is_instance_valid(human):
		return {"accepted": false, "reason": "unknown_peer"}
	if not match_started or _match_concluded or not human.alive or not (human.controls_enabled or human.look_enabled):
		return {"accepted": false, "reason": "action_unavailable"}
	if not human.WEAPONS.has(weapon) or not human.owns_weapon(weapon):
		return {"accepted": false, "reason": "weapon_not_owned"}
	# Same deploy, reload cancellation, ammo preservation and lastinv semantics
	# as a local human. Never grant a weapon or accept client ammunition.
	human.switch_weapon(weapon)
	return {"accepted": true, "reason": ""}


func remote_weapon_action(peer_id: int, action: String, expected_weapon: String) -> Dictionary:
	var human := _remote_join_actor(peer_id)
	if not is_instance_valid(human):
		return {"accepted": false, "reason": "unknown_peer"}
	if not match_started or _match_concluded or not human.alive:
		return {"accepted": false, "reason": "action_unavailable"}
	# Reliable action ordering cannot make a delayed click/drop apply to a
	# different weapon after pickup, depletion or another authoritative switch.
	if human.active_weapon != expected_weapon:
		return {"accepted": false, "reason": "weapon_changed"}
	if action == "secondary":
		if not human.controls_enabled or human.reloading or not human.weapon_clock.can_secondary_attack():
			return {"accepted": false, "reason": "action_unavailable"}
		if expected_weapon != "knife" and str(human.WEAPONS[expected_weapon].secondary) == "none":
			return {"accepted": false, "reason": "action_unavailable"}
		human._try_secondary()
	elif action == "reload_weapon":
		if human.reloading or not (human.controls_enabled or human.look_enabled):
			return {"accepted": false, "reason": "action_unavailable"}
		human._start_reload()
		if not human.reloading:
			return {"accepted": false, "reason": "action_unavailable"}
	elif action == "drop_weapon":
		if not human.controls_enabled and (expected_weapon != "c4" or not human.look_enabled):
			return {"accepted": false, "reason": "action_unavailable"}
		if expected_weapon == "c4":
			if not _request_human_c4_drop(human):
				return {"accepted": false, "reason": "not_droppable"}
		elif human._is_droppable_gun(expected_weapon) and human.owns_weapon(expected_weapon):
			human._try_drop_active_weapon()
		else:
			return {"accepted": false, "reason": "not_droppable"}
	else:
		return {"accepted": false, "reason": "internal_error"}
	return {"accepted": true, "reason": ""}


func _on_remote_human_added(actor_id: String, _peer_id: int, actor: PlayerController) -> void:
	_remote_brush_activator_ids[actor_id] = _next_remote_brush_activator
	_next_remote_brush_activator += 1
	actor.combat_effects = combat_effects
	actor.audio_router = audio_router
	actor.weapon_drop_requested.connect(_on_human_weapon_drop.bind(actor))
	actor.combatant_eliminated.connect(_on_human_eliminated)
	round_state.register_player(actor_id, Combatant.TEAM_UNASSIGNED)
	bomb_knowledge.register_actor(actor_id, Combatant.TEAM_UNASSIGNED)
	if _dedicated_server_mode and not match_started:
		# An empty public server waits in deploy instead of letting bots age the
		# match. The first transport peer always receives a fresh Dust2 session.
		start_match()
	_update_scoreboard()


func _remote_join_actor(peer_id: int) -> PlayerController:
	var session := get_node("/root/NetworkSession")
	if not session.is_host or not session.has_input_peer(peer_id) or not is_instance_valid(remote_roster):
		return null
	return remote_roster.actor_for_peer(peer_id)


func select_remote_join_team(peer_id: int, selected_team: String) -> Dictionary:
	var human := _remote_join_actor(peer_id)
	if not is_instance_valid(human):
		return {"accepted": false, "reason": "unknown_peer"}
	if not match_started or _match_concluded:
		return {"accepted": false, "reason": "match_not_live"}
	if selected_team not in ["T", "CT"]:
		return {"accepted": false, "reason": "invalid_team"}
	var actor_id := _round_id_for_actor(human)
	# Joined players may switch sides (the M menu). The round kernel applies
	# CS 1.6's rules: a living switch is a suicide, the new side waits for the
	# next round, and a dead player may switch once per round.
	if human.team == selected_team:
		return {"accepted": false, "reason": "already_joined"}
	var capacities := {"T": mini(5, terrorist_team_spawns.size()), "CT": mini(5, counter_terrorist_team_spawns.size())}
	var replacement: TargetActor
	var slot := -1
	if int(round_state.team_counts()[selected_team]) >= int(capacities[selected_team]):
		var bots := _all_bots()
		bots.reverse()
		for bot: TargetActor in bots:
			if bot.team == selected_team and (not is_instance_valid(replacement) or not bot.alive):
				replacement = bot
				if not bot.alive:
					break
		if is_instance_valid(replacement):
			var positions: Array = allied_spawns if allied_bots.has(replacement) else target_spawns
			var index := allied_bots.find(replacement) if allied_bots.has(replacement) else targets.find(replacement)
			var team_spawns: Array = terrorist_team_spawns if selected_team == "T" else counter_terrorist_team_spawns
			slot = team_spawns.find(positions[index])
	else:
		var used := _used_team_spawn_slots(selected_team)
		for candidate in int(capacities[selected_team]):
			if not used.has(candidate):
				slot = candidate
				break
	var replaced_id := str(replacement.name) if is_instance_valid(replacement) else ""
	var reason: String = round_state.team_selection_error(actor_id, selected_team, capacities, replaced_id)
	if not reason.is_empty() or slot < 0:
		return {"accepted": false, "reason": reason if not reason.is_empty() else "no_spawn_slot"}
	# Validate before removing any bot. Selection and replacement are one
	# synchronous host transaction; clients never supply the replaced identity.
	var result: Dictionary = round_state.select_player_team(actor_id, selected_team, capacities, human.global_position, replaced_id)
	if not result.accepted:
		return result
	if bool(result.get("selection_death", false)):
		# Kernel death/drop is idempotent; actor death adds the physical weapon
		# and C4 drops without a second recorded death (as offline).
		human.receive_damage(100000.0, human.global_position)
		_consume_new_round_trace()
	human.configure_identity(selected_team, human.display_name)
	human.set_meta("network_spawn_slot", slot)
	human.set_meta("cs16_class_id", 0)
	if is_instance_valid(replacement):
		_remove_replaced_bot(replacement)
	_refresh_roster_spawns()
	_refresh_bomb_knowledge_roster()
	_sync_round_public_state()
	_update_scoreboard()
	return {"accepted": true, "actor_id": actor_id, "team": selected_team, "replaced_bot": replaced_id}


func select_remote_join_class(peer_id: int, class_id: int) -> Dictionary:
	var human := _remote_join_actor(peer_id)
	if not is_instance_valid(human):
		return {"accepted": false, "reason": "unknown_peer"}
	var actor_id := _round_id_for_actor(human)
	if class_id not in [1, 2, 3, 4] or not human.has_meta("network_spawn_slot"):
		return {"accepted": false, "reason": "invalid_class"}
	if _match_concluded or not bool(round_state.players.get(actor_id, {}).get("choosing_appearance", false)):
		return {"accepted": false, "reason": "not_choosing_class"}
	human.set_meta("cs16_class_id", class_id)
	human.set_meta("cs16_player_skin", _class_skin(human.team, class_id))
	var spawned: bool = round_state.finish_player_appearance(actor_id)
	if spawned:
		_spawn_remote_human(human, false)
	_sync_round_public_state()
	_update_scoreboard()
	return {"accepted": true, "spawned": spawned, "actor_id": actor_id, "class_id": class_id}


func _used_team_spawn_slots(team: String) -> Dictionary:
	var spawns: Array = terrorist_team_spawns if team == "T" else counter_terrorist_team_spawns
	var used := {}
	if player.team == team:
		used[spawns.find(player_spawn)] = true
	for bot: TargetActor in _all_bots():
		if bot.team != team:
			continue
		var positions: Array = allied_spawns if allied_bots.has(bot) else target_spawns
		var index := allied_bots.find(bot) if allied_bots.has(bot) else targets.find(bot)
		used[spawns.find(positions[index])] = true
	for human: PlayerController in _human_players_stable():
		if human.team == team and human.has_meta("network_spawn_slot"):
			used[int(human.get_meta("network_spawn_slot"))] = true
	return used


func _spawn_remote_human(human: PlayerController, keep_loadout: bool) -> void:
	var spawns: Array = terrorist_team_spawns if human.team == "T" else counter_terrorist_team_spawns
	human.set_meta("cs16_player_skin", _class_skin(human.team, int(human.get_meta("cs16_class_id", 1))))
	human.reset_player(spawns[int(human.get_meta("network_spawn_slot"))], keep_loadout)
	human.visible = true
	human.collision_layer = 2
	human.look_enabled = true
	human.controls_enabled = phase in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB]
	human.set_physics_process(true)
	var opponents: Array = counter_terrorist_team_spawns if human.team == "T" else terrorist_team_spawns
	if not opponents.is_empty():
		human.face_toward(opponents[0])
	player.collision_layer = _local_player_collision_layer() if player.alive else 0


func _local_player_collision_layer(excluding_actor_id := "") -> int:
	if get_node("/root/NetworkSession").is_host and is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			if actor_id != excluding_actor_id and remote_roster.actor_for_id(actor_id).has_meta("network_spawn_slot"):
				return 2 | 4
	return 4


func _remove_replaced_bot(bot: TargetActor) -> void:
	var actor_id := str(bot.name)
	var activator_id := _brush_activator_id(bot)
	bot.alive = false
	bot.active = false
	bot.collision_layer = 0
	bot.set_physics_process(false)
	round_state.disconnect_player(actor_id, bot.global_position)
	_consume_new_round_trace()
	_sync_round_public_state()
	bomb_knowledge.unregister_actor(actor_id)
	for voice: Dictionary in audio_router.active_voices():
		if int(voice.entity_id) == bot.audio_entity_id():
			audio_router.stop_voice(int(voice.voice_id), "bot_replaced")
	if is_instance_valid(hostage_state):
		for hostage_id: String in hostage_state.hostages:
			if str(hostage_state.hostages[hostage_id].leader_id) == actor_id:
				hostage_state.release_invalid_leader(hostage_id, false)
				_hostage_paths.erase(hostage_id)
				_hostage_path_indices.erase(hostage_id)
				_hostage_path_targets.erase(hostage_id)
		_sync_hostage_actors()
	_hostage_bot_assignments.erase(actor_id)
	_bot_site_assignments.erase(actor_id)
	if _bot_defuser_id == actor_id:
		_reset_bot_defuser_assignment()
	if is_instance_valid(brush_runtime):
		brush_runtime.clear_activator_position(activator_id)
	for key: String in _brush_touch_pairs.keys():
		if int(_brush_touch_pairs[key].activator_id) == activator_id:
			entity_world.queue_touch(int(_brush_touch_pairs[key].entity_id), activator_id, EntityWorldScript.TOUCH_EXIT)
			_brush_touch_pairs.erase(key)
	if is_instance_valid(spectator_camera) and spectator_camera.target == bot:
		spectator_camera._advance_after_target_loss()
	if allied_bots.has(bot):
		allied_spawns.remove_at(allied_bots.find(bot))
		allied_bots.erase(bot)
	else:
		target_spawns.remove_at(targets.find(bot))
		targets.erase(bot)
	_bot_brush_activator_ids.erase(bot.get_instance_id())
	remove_child(bot)
	bot.queue_free()


func _on_remote_human_removing(actor_id: String, _peer_id: int, actor: PlayerController) -> void:
	sprays._cooldowns.erase(actor.get_instance_id())
	# Roster lookup remains valid until this callback finishes. In particular,
	# bomb_dropped needs the departing actor's orientation before it is freed.
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_human_use_was_down.erase(actor_id)
	_human_death_serials.erase(actor_id)
	if actor.has_meta("network_spawn_slot"):
		actor.remove_meta("network_spawn_slot")
	player.collision_layer = _local_player_collision_layer(actor_id) if player.alive else 0
	_remote_trigger_cameras.erase(actor_id)
	var activator_id := int(_remote_brush_activator_ids.get(actor_id, -1))
	if is_instance_valid(brush_runtime):
		brush_runtime.clear_activator_position(activator_id)
	for pair_key: String in _brush_touch_pairs.keys():
		var pair: Dictionary = _brush_touch_pairs[pair_key]
		if int(pair.activator_id) == activator_id:
			entity_world.queue_touch(int(pair.entity_id), activator_id, EntityWorldScript.TOUCH_EXIT)
			_brush_touch_pairs.erase(pair_key)
	_remote_brush_activator_ids.erase(actor_id)
	if is_instance_valid(round_state):
		round_state.disconnect_player(actor_id, actor.global_position)
		_consume_new_round_trace()
		_sync_round_public_state()
	if is_instance_valid(bomb_knowledge):
		bomb_knowledge.unregister_actor(actor_id)
	if is_instance_valid(audio_router):
		var entity_id := actor.audio_entity_id()
		for voice: Dictionary in audio_router.active_voices():
			if int(voice.entity_id) == entity_id:
				audio_router.stop_voice(int(voice.voice_id), "human_disconnected")
	if is_instance_valid(hostage_state):
		for hostage_id: String in hostage_state.hostages:
			if str(hostage_state.hostages[hostage_id].leader_id) == actor_id:
				hostage_state.release_invalid_leader(hostage_id, false)
				_hostage_paths.erase(hostage_id)
				_hostage_path_indices.erase(hostage_id)
				_hostage_path_targets.erase(hostage_id)
				var hostage: CS16Hostage = hostage_actors.get(hostage_id)
				if is_instance_valid(hostage):
					hostage.set_motion_velocity_hu(Vector3.ZERO)
		_sync_hostage_actors()
	if is_instance_valid(spectator_camera) and spectator_camera.target == actor:
		spectator_camera._advance_after_target_loss()
	_update_scoreboard()
	if _dedicated_server_mode and is_instance_valid(remote_roster) and remote_roster.size() == 1:
		_reset_empty_dedicated_server.call_deferred()


func _reset_empty_dedicated_server() -> void:
	# RemoteHumanRoster emits removal before releasing its record. By the next
	# deferred turn the session is empty, so rebuild the scene and recover every
	# bot/spawn slot removed during that group's play without touching ENet.
	if not _dedicated_server_mode or not is_instance_valid(remote_roster) or remote_roster.size() != 0:
		return
	get_tree().reload_current_scene()


func _prepare_gameplay_presentation() -> void:
	# start_match already waits for the effects-ready signal. Do all finite
	# cold weapon I/O/conversion before that signal can permit deployment.
	var started := Time.get_ticks_msec()
	if DisplayServer.get_name() != "headless":
		if not await player.viewmodel.prepare_weapon_assets(player.WEAPONS.keys()):
			return
		_log_loading_phase("weapons", started)
		if not await _prepare_bot_presentation_assets():
			return
		_log_loading_phase("bot models", started)
		if using_imported_map:
			for bot: TargetActor in _all_bots():
				if not bot.combat_controller._ensure_objective_graph():
					push_error("Cannot prepare bot navigation before deployment")
					return
				await LoadingBudget.pace(get_tree())
		_log_loading_phase("bot navigation", started)
	if not combat_effects.presentation_ready.is_connected(_on_presentation_ready_logged):
		combat_effects.presentation_ready.connect(_on_presentation_ready_logged.bind(started), CONNECT_ONE_SHOT)
	combat_effects.warm_up_presentation(player.camera)


func _on_presentation_ready_logged(started: int) -> void:
	_log_loading_phase("effects warm-up (deploy allowed)", started)


## Browser ?perf: loading milestones, in ms since preparation began.
func _log_loading_phase(phase_name: String, started: int) -> void:
	if OS.has_feature("web") and NetworkSessionScript.web_page_query("perf") != null:
		print("PROTOCOL47_LOAD %s at %d ms" % [phase_name, Time.get_ticks_msec() - started])


func _bot_presentation_requests() -> Array[Dictionary]:
	var requests: Array[Dictionary] = []
	var seen := {}
	for bot: TargetActor in _all_bots():
		# Both sides are possible after team selection and halftime. Use the
		# actual roster indices, rather than loading every weapon for every skin.
		for side: String in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
			var skin := TargetScript.skin_for_team(side, bot.index)
			var weapons := BotBuyPlanScript.presentation_weapons(side, bot.index)
			if side == Combatant.TEAM_TERRORIST and scenario == ScenarioRulesScript.SCENARIO_BOMB:
				weapons.append("c4")
			for weapon: String in weapons:
				var key := skin + ":" + weapon
				if not seen.has(key):
					seen[key] = true
					requests.append({"skin": skin, "weapon": weapon})
	return requests


func _prepare_bot_presentation_assets() -> bool:
	var started := Time.get_ticks_usec()
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var templates_before := MdlCharacterModel._template_cache.size()
	var requests := _bot_presentation_requests()
	var loading_slices := 0
	for request: Dictionary in requests:
		if MdlCharacterModel.character_assets_prepared(request.skin, request.weapon):
			continue
		if not MdlCharacterModel.prepare_character_assets(request.skin, request.weapon):
			push_error("Cannot prepare bot presentation: %s/%s" % [request.skin, request.weapon])
			return false
		loading_slices += 1
		await LoadingBudget.pace(get_tree())
	bot_asset_preparation = {"requests": requests.size(), "loading_slices": loading_slices,
		"new_templates": MdlCharacterModel._template_cache.size() - templates_before,
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0,
		"static_memory_delta_bytes": Performance.get_monitor(Performance.MEMORY_STATIC) - memory_before}
	return true


func _build_deploy_camera() -> void:
	## Real 1.6 team select shows the map from a normally lit spectate camera;
	## the player spawn frame at that moment is a nose-to-wall shot in shade.
	## Park a temporary camera on a sunlit T-spawn vista looking toward mid.
	if not using_imported_map:
		return
	deploy_camera = Camera3D.new()
	deploy_camera.name = "DeployCamera"
	add_child(deploy_camera)
	if map_name == "de_dust2" or terrorist_team_spawns.is_empty() or counter_terrorist_team_spawns.is_empty():
		deploy_camera.position = Vector3(-7.8, 2.7, 8.0)
		deploy_camera.look_at(deploy_camera.position + Vector3(10.0, 0.4, 0.0), Vector3.UP)
	else:
		# Other maps: stand above the T spawn and look down its longest clear
		# sightline (a spawn courtyard otherwise often frames a bare wall).
		deploy_camera.position = _spawn_centroid(terrorist_team_spawns) + Vector3(0.0, 1.1, 0.0)
		deploy_camera.look_at(deploy_camera.position + _longest_sightline(deploy_camera.position), Vector3.UP)
	deploy_camera.make_current()


func _longest_sightline(from: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var best := Vector3.RIGHT
	var best_distance := -1.0
	for step in 16:
		var direction := Vector3.RIGHT.rotated(Vector3.UP, TAU * step / 16.0)
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * 60.0, 1)
		var hit := space.intersect_ray(query)
		var distance := from.distance_to(hit.position) if not hit.is_empty() else 60.0
		if distance > best_distance:
			best_distance = distance
			best = direction
	return best + Vector3(0.0, -0.08, 0.0)


static func _spawn_centroid(spawns: Array[Vector3]) -> Vector3:
	var sum := Vector3.ZERO
	for spawn: Vector3 in spawns:
		sum += spawn
	return sum / float(spawns.size())


func _build_imported_map() -> bool:
	if "--procedural-test" in OS.get_cmdline_user_args():
		return false
	if not FileAccess.file_exists(imported_map_path):
		push_warning(
			"Converted %s map not found at %s; using the procedural test arena."
			% [map_name, imported_map_path]
		)
		return false
	imported_map = BspMapScript.new()
	imported_map.name = map_name.to_pascal_case()
	add_child(imported_map)
	if not imported_map.load_map(imported_map_path):
		imported_map.queue_free()
		imported_map = null
		return false
	scenario_info = ScenarioRulesScript.classify_entities(imported_map.entities)
	scenario = str(scenario_info.scenario)

	var ct_spawns := imported_map.spawn_points("info_player_start")
	var terrorist_spawns := imported_map.spawn_points("info_player_deathmatch")
	if ct_spawns.size() < 5 or terrorist_spawns.size() < 5:
		push_error("%s is missing the player spawns needed by the 5v5 scenario." % map_name)
		imported_map.queue_free()
		imported_map = null
		return false
	terrorist_team_spawns.assign(terrorist_spawns)
	counter_terrorist_team_spawns.assign(ct_spawns)
	_apply_spawn_side(Combatant.TEAM_TERRORIST)
	using_imported_map = true
	return true


func _select_map_from_command_line() -> void:
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			requested = argument.trim_prefix("--map=").to_lower()
			break
	# Browser offline play: classicfps.app/?offline&map=de_inferno
	var web_map: Variant = NetworkSessionScript.web_page_query("map")
	if requested.is_empty() and web_map != null:
		requested = str(web_map).to_lower()
	if not requested.is_empty() and not _map_available(requested):
		push_warning(
			"Unsupported map '%s'; using %s. Supported maps: %s"
			% [requested, DEFAULT_MAP_NAME, ", ".join(SUPPORTED_MAP_NAMES)]
		)
		requested = ""
	_use_map(requested if not requested.is_empty() else map_name)


func _use_map(name: String) -> void:
	map_name = name
	imported_map_path = "res://generated/%s/map.json" % map_name


func _map_available(name: String) -> bool:
	return name in SUPPORTED_MAP_NAMES and ResourceLoader.exists("res://generated/%s/map.json" % name)


func _next_rotation_map() -> String:
	var index := MAP_ROTATION.find(map_name)
	return MAP_ROTATION[(index + 1) % MAP_ROTATION.size()]


func _change_to_next_map() -> void:
	# Bound method, not a lambda: a scene rebuilt meanwhile simply drops it.
	if not _dedicated_server_mode or not _match_concluded:
		return
	get_node("/root/NetworkSession").active_map = _next_rotation_map()
	get_tree().reload_current_scene()


## Online clients load whatever map their host runs. The session survives the
## scene reload, so the client stays connected and rejoins on the new map.
func follow_host_map(host_map: String) -> bool:
	if not _network_client_mode or host_map == map_name or not _map_available(host_map):
		return false
	if _following_host_map:
		return true
	_following_host_map = true
	get_node("/root/NetworkSession").active_map = host_map
	get_tree().reload_current_scene.call_deferred()
	return true


func _build_entity_world() -> void:
	entity_world = EntityWorldScript.new()
	entity_world.load_entities(
		imported_map.entities if is_instance_valid(imported_map) else []
	)
	brush_runtime = null
	breakable_runtime = null
	breakable_debris = null
	_brush_touch_pairs.clear()
	if is_instance_valid(imported_map):
		brush_runtime = BrushRuntimeScript.new()
		brush_runtime.configure(imported_map, entity_world)
		brush_runtime.runtime_event.connect(_on_brush_runtime_event)
		breakable_runtime = BreakableRuntimeScript.new()
		breakable_runtime.configure(imported_map, entity_world)
		breakable_runtime.runtime_event.connect(_on_breakable_runtime_event)
		breakable_debris = BreakableDebrisScript.new()
		breakable_debris.name = "AuthenticBreakableDebris"
		add_child(breakable_debris)
		breakable_debris.bind_runtime(breakable_runtime)
		_bind_breakable_collision_proxies()


func _bind_breakable_collision_proxies() -> void:
	if breakable_runtime == null or not is_instance_valid(imported_map):
		return
	for entity_id in entity_world.entity_count():
		if not breakable_runtime.has_entity(entity_id):
			continue
		var record := breakable_runtime.get_breakable(entity_id)
		var body := imported_map.model_collision_body(int(record.model_index))
		if not is_instance_valid(body):
			continue
		body.set_script(BreakableProxyScript)
		body.call(
			"bind_breakable",
			breakable_runtime,
			entity_id,
			Callable(self, "_breakable_activator_id"),
		)


func _breakable_activator_id(actor: Variant) -> int:
	if actor is Combatant:
		return _brush_activator_id(actor as Combatant)
	return -1


func _build_hostages() -> void:
	hostage_actors.clear()
	_hostage_bot_assignments.clear()
	_hostage_bot_rescue_targets.clear()
	if (
		scenario != ScenarioRulesScript.SCENARIO_HOSTAGE
		or not is_instance_valid(imported_map)
	):
		hostage_state = null
		return
	hostage_state = HostageStateScript.new()
	for raw_entity: Variant in imported_map.entities:
		if not raw_entity is Dictionary:
			continue
		var entity := raw_entity as Dictionary
		var classname := str(entity.get("classname", ""))
		if classname not in ["hostage_entity", "monster_scientist"]:
			continue
		var properties := _ordered_entity_properties(entity)
		var entity_index := int(entity.get("entity_index", hostage_actors.size()))
		var hostage_id := "hostage_%03d" % entity_index
		var source_origin := _source_vector(entity.get("origin", {}))
		var position_hu := Vector3(
			source_origin.x,
			source_origin.z,
			-source_origin.y,
		)
		var skin := int(properties.get("skin", "0"))
		# Source yaw zero points +X while Godot yaw zero points -Z.
		var yaw_degrees := float(
			properties.get("angle", properties.get("angles", "0").split(" ")[0])
		) - 90.0
		hostage_state.register_hostage(
			hostage_id,
			position_hu,
			skin,
			yaw_degrees,
		)
		var actor: CS16Hostage = HostageActorScript.new()
		actor.set_meta("entity_index", entity_index)
		actor.configure(hostage_id, skin)
		actor.auto_advance_animation = false
		actor.use_requested.connect(_on_hostage_use_requested)
		actor.damage_requested.connect(_on_hostage_damage_requested)
		add_child(actor)
		actor.global_position = position_hu * HostageActorScript.GOLDSRC_UNIT
		if actor.drop_to_floor():
			hostage_state.set_spawn_position(
				hostage_id,
				actor.global_position / HostageActorScript.GOLDSRC_UNIT,
			)
		hostage_actors[hostage_id] = actor
	hostage_state.start_round()
	_sync_hostage_actors()
	_hostage_floor_registration_pending = true


func _drop_hostages_to_floor() -> void:
	if not _hostage_floor_registration_pending or hostage_state == null:
		return
	_hostage_floor_registration_pending = false
	for hostage_id: String in hostage_actors:
		var actor: CS16Hostage = hostage_actors[hostage_id]
		if not is_instance_valid(actor):
			continue
		if actor.drop_to_floor():
			hostage_state.set_spawn_position(
				hostage_id,
				actor.global_position / HostageActorScript.GOLDSRC_UNIT,
			)
	hostage_state.start_round()
	_sync_hostage_actors()


func _ordered_entity_properties(entity: Dictionary) -> Dictionary:
	var properties := {}
	for raw_pair: Variant in entity.get("properties", []):
		if raw_pair is Array and raw_pair.size() >= 2:
			properties[str(raw_pair[0])] = str(raw_pair[1])
	return properties


func _source_vector(raw: Variant) -> Vector3:
	if not raw is Dictionary:
		return Vector3.ZERO
	var value := raw as Dictionary
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0)),
	)


func _build_trigger_camera() -> void:
	trigger_camera = Camera3D.new()
	trigger_camera.name = "GoldSrcTriggerCamera"
	trigger_camera.fov = player.camera.fov
	trigger_camera.near = player.camera.near
	trigger_camera.current = false
	add_child(trigger_camera)
	if entity_world == null or not is_instance_valid(imported_map):
		return
	for raw_entity: Variant in imported_map.entities:
		if not raw_entity is Dictionary:
			continue
		var entity := raw_entity as Dictionary
		if str(entity.get("classname", "")) != "trigger_camera":
			continue
		var entity_id := int(entity.get("entity_index", -1))
		if entity_world.is_valid_entity(entity_id):
			entity_world.bind_handler(
				entity_id,
				Callable(self, "_on_trigger_camera_use").bind(entity_id),
			)


func _on_trigger_camera_use(event: Dictionary, entity_id: int) -> void:
	if (
		not is_instance_valid(trigger_camera)
		or not is_instance_valid(player)
		or not is_instance_valid(imported_map)
	):
		return
	var camera_entity := _map_entity_by_index(entity_id)
	if camera_entity.is_empty():
		return
	var properties := _ordered_entity_properties(camera_entity)
	var source_origin := _source_vector(camera_entity.get("origin", {}))
	var camera_position := Vector3(
		source_origin.x,
		source_origin.z,
		-source_origin.y,
	) * GOLDSRC_UNIT
	var camera_transform := Transform3D(Basis.IDENTITY, camera_position)
	var target_position := _entity_target_position(str(properties.get("target", "")))
	if target_position != Vector3.INF:
		camera_transform = camera_transform.looking_at(target_position, Vector3.UP)
	else:
		var yaw := deg_to_rad(float(properties.get("angle", "0")))
		var forward := Vector3(cos(yaw), 0.0, -sin(yaw))
		camera_transform = camera_transform.looking_at(camera_position + forward, Vector3.UP)
	var wait_seconds := maxf(0.0, float(properties.get("wait", "0")))
	var return_tick := int(entity_world.tick) + maxi(1, roundi(wait_seconds * float(EntityWorldScript.TICK_RATE)))
	var activator_id := int(event.get("activator_id", -1))
	if activator_id >= 0x100000000:
		# The host viewport belongs only to the local human. Retain the remote
		# camera's authoritative state for later owner snapshot presentation.
		# A departed activator never falls back to the host, even for delayed IO.
		for actor_id: String in _remote_brush_activator_ids:
			if int(_remote_brush_activator_ids[actor_id]) != activator_id:
				continue
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if not is_instance_valid(human) or not human.alive:
				return
			var prior: Dictionary = _remote_trigger_cameras.get(actor_id, {})
			_remote_trigger_cameras[actor_id] = {
				"entity_id": entity_id, "transform": camera_transform,
				"return_tick": return_tick, "fov": human.camera.fov,
				"controls_enabled": bool(prior.get("controls_enabled", human.controls_enabled)),
			}
			human.controls_enabled = false
			return
		return
	trigger_camera.global_transform = camera_transform
	trigger_camera.fov = player.camera.fov
	_trigger_camera_controls_enabled = player.controls_enabled
	player.controls_enabled = false
	trigger_camera.current = true
	trigger_camera_entity_id = entity_id
	trigger_camera_return_tick = return_tick
	if is_instance_valid(hud):
		hud.update_objective(
			"SECURITY CAMERA %d" % entity_id
		)


func _advance_trigger_camera() -> void:
	for actor_id: String in _remote_trigger_cameras.keys():
		var human: PlayerController = remote_roster.actor_for_id(actor_id)
		if not is_instance_valid(human) or not human.alive or int(entity_world.tick) >= int(_remote_trigger_cameras[actor_id].return_tick):
			_end_remote_trigger_camera(actor_id)
	if (
		trigger_camera_entity_id < 0
		or trigger_camera_return_tick < 0
		or entity_world == null
		or int(entity_world.tick) < trigger_camera_return_tick
	):
		return
	_end_trigger_camera()


func _end_remote_trigger_camera(actor_id: String, restore_controls := true) -> void:
	var state: Dictionary = _remote_trigger_cameras.get(actor_id, {})
	_remote_trigger_cameras.erase(actor_id)
	var human: PlayerController = remote_roster.actor_for_id(actor_id)
	if restore_controls and is_instance_valid(human) and not state.is_empty():
		human.controls_enabled = human.alive and bool(state.controls_enabled) and phase in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB]


func _end_trigger_camera() -> void:
	if trigger_camera_entity_id < 0:
		return
	trigger_camera.current = false
	if is_instance_valid(player):
		player.camera.current = true
		player.controls_enabled = _trigger_camera_controls_enabled
	trigger_camera_entity_id = -1
	trigger_camera_return_tick = -1


func _build_spectator_camera() -> void:
	spectator_camera = SpectatorCameraScript.new()
	spectator_camera.name = "DeathSpectatorCamera"
	spectator_camera.setup(
		player,
		Callable(self, "_living_spectate_teammates"),
		Callable(self, "_death_spectate_blocked"),
		hud,
	)
	spectator_camera.ended.connect(_end_death_spectate)
	add_child(spectator_camera)


func _living_spectate_teammates() -> Array[Combatant]:
	if is_instance_valid(network_client_view):
		return network_client_view.spectate_teammates()
	var mates: Array[Combatant] = []
	if not is_instance_valid(player):
		return mates
	for bot in _all_bots():
		if is_instance_valid(bot) and bot.alive and (
			player.team == Combatant.TEAM_UNASSIGNED or bot.team == player.team
		):
			mates.append(bot)
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if human.alive and (player.team == Combatant.TEAM_UNASSIGNED or human.team == player.team):
				mates.append(human)
	return mates


func _death_spectate_blocked() -> bool:
	# A running trigger_camera sequence owns the view; do not fight it.
	return trigger_camera_entity_id >= 0


func _end_death_spectate() -> void:
	if not is_instance_valid(spectator_camera) or not spectator_camera.is_engaged():
		return
	spectator_camera.stop()
	if trigger_camera_entity_id < 0 and is_instance_valid(player):
		player.camera.current = true


func _map_entity_by_index(entity_id: int) -> Dictionary:
	if not is_instance_valid(imported_map):
		return {}
	for raw_entity: Variant in imported_map.entities:
		if (
			raw_entity is Dictionary
			and int((raw_entity as Dictionary).get("entity_index", -1)) == entity_id
		):
			return raw_entity as Dictionary
	return {}


func _entity_target_position(targetname: String) -> Vector3:
	if targetname.is_empty() or not is_instance_valid(imported_map):
		return Vector3.INF
	for raw_entity: Variant in imported_map.entities:
		if not raw_entity is Dictionary:
			continue
		var entity := raw_entity as Dictionary
		var properties := _ordered_entity_properties(entity)
		if str(properties.get("targetname", "")) != targetname:
			continue
		var source_origin := _source_vector(entity.get("origin", {}))
		return Vector3(
			source_origin.x,
			source_origin.z,
			-source_origin.y,
		) * GOLDSRC_UNIT
	return Vector3.INF


func _process_player_world_use() -> Dictionary:
	var selections := {}
	if not is_instance_valid(player):
		return selections
	for human: PlayerController in _human_players_stable():
		selections[_round_id_for_actor(human)] = _process_human_world_use(human)
	return selections


func _process_human_world_use(human: PlayerController) -> Dictionary:
	var actor_id := _round_id_for_actor(human)
	var use_down := human.alive and human.controls_enabled and bool(human.last_command.get("use", false))
	var use_pressed := use_down and not bool(_human_use_was_down.get(actor_id, false))
	_human_use_was_down[actor_id] = use_down
	if (
		not use_down
		or phase not in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB]
	):
		return {}
	var selected := PlayerUseResolverScript.select_candidate(
		human.global_position,
		human.camera.global_position,
		-human.camera.global_transform.basis.z,
		_world_use_candidates(human, bomb_planted),
	)
	if not use_pressed:
		return selected
	var selected_node: Node = selected.get("node")
	if is_instance_valid(selected_node) and selected_node.has_method("request_source_use"):
		selected_node.call("request_source_use", human)
	elif selected.has("brush_entity_id"):
		_queue_brush_use(int(selected.brush_entity_id), human)
	# C4's selected held-use is consumed by the authoritative round tick.
	return selected


func _world_use_candidates(actor: Combatant, include_c4 := false) -> Array:
	var candidates: Array = []
	if include_c4:
		candidates.append({"id": "c4", "origin": bomb_position, "usable": bomb_planted})
	for candidate_node: Node in get_tree().get_nodes_in_group("source_use_targets"):
		var origin: Variant = (
			candidate_node.call("source_use_origin") if candidate_node.has_method("source_use_origin")
			else (candidate_node.global_position if candidate_node is Node3D else Vector3.INF)
		)
		if not origin is Vector3 or origin == Vector3.INF:
			continue
		candidates.append({
			"id": str(candidate_node.name),
			"origin": origin,
			"usable": bool(candidate_node.call("source_use_usable", actor)) if candidate_node.has_method("source_use_usable") else true,
			"node": candidate_node,
		})
	if brush_runtime != null:
		for raw_entity_id: Variant in _sorted_brush_entity_ids():
			var entity_id := int(raw_entity_id)
			if not entity_world.has_capability(
				entity_id,
				EntityWorldScript.CAP_USE_PRESSED,
			):
				continue
			candidates.append({
				"id": "brush_%03d" % entity_id,
				"origin": _brush_world_aabb(entity_id).get_center(),
				"usable": actor.alive,
				"brush_entity_id": entity_id,
			})
	return candidates


func _queue_brush_use(entity_id: int, actor: Combatant) -> bool:
	if brush_runtime == null or not is_instance_valid(actor) or not actor.alive:
		return false
	var activator_id := _brush_activator_id(actor)
	brush_runtime.set_activator_position(activator_id, actor.global_position)
	return entity_world.queue_use(
		entity_id,
		activator_id,
		EntityWorldScript.INPUT_PRESSED,
	)


func _queue_brush_touches() -> void:
	if brush_runtime == null:
		return
	var touch_actors: Array[Node3D] = []
	for actor: Combatant in _live_combatants_stable():
		touch_actors.append(actor)
	var hostage_ids := hostage_actors.keys()
	hostage_ids.sort()
	for hostage_id: String in hostage_ids:
		var hostage: CS16Hostage = hostage_actors[hostage_id]
		if is_instance_valid(hostage) and hostage.alive and not hostage.rescued:
			touch_actors.append(hostage)
	var movement_contacts := {}
	for actor: Node3D in touch_actors:
		if actor is TargetActor or actor is CS16Hostage:
			movement_contacts[actor] = actor.take_brush_contacts()
	var current_pairs := {}
	for raw_entity_id: Variant in _sorted_brush_entity_ids():
		var entity_id := int(raw_entity_id)
		if not entity_world.has_capability(entity_id, EntityWorldScript.CAP_TOUCH):
			continue
		var allows_hostage_touch := str(brush_runtime.get_brush(entity_id).classname) != "func_button"
		# CharacterBody safe margins stop a hull a fraction short of an exact
		# brush-plane overlap. GoldSrc still reports that collision contact as a
		# touch, so grow the query by a tiny physical-contact tolerance.
		var brush_bounds := _brush_world_aabb(entity_id).grow(
			BRUSH_TOUCH_CONTACT_EPSILON
		)
		if brush_bounds.size.is_zero_approx():
			continue
		for actor: Node3D in touch_actors:
			# Source doors accept living non-player touchers. Buttons retain
			# their player-only contract; hostages do not press them by contact.
			if actor is CS16Hostage and not allows_hostage_touch:
				continue
			var activator_id := _brush_activator_id(actor)
			var pair_key := "%d:%d" % [entity_id, activator_id]
			var actor_size := (
				_human_hull_size(actor as PlayerController)
				if actor is PlayerController
				else TargetActor.STANDING_HULL_SIZE
			)
			if actor is CS16Hostage:
				actor_size = CS16Hostage.HULL_SIZE
			var actor_bounds := _feet_hull_aabb(actor.global_position, actor_size)
			var touching := _aabb_touches(actor_bounds, brush_bounds)
			if not touching and movement_contacts.has(actor):
				touching = movement_contacts[actor].has(entity_id)
			if not touching:
				continue
			current_pairs[pair_key] = {
				"entity_id": entity_id,
				"activator_id": activator_id,
			}
			brush_runtime.set_activator_position(
				activator_id,
				actor.global_position,
			)
			entity_world.queue_touch(
				entity_id,
				activator_id,
				EntityWorldScript.TOUCH_STAY
				if _brush_touch_pairs.has(pair_key)
				else EntityWorldScript.TOUCH_ENTER,
			)
	var previous_keys: Array = _brush_touch_pairs.keys()
	previous_keys.sort()
	for raw_pair_key: Variant in previous_keys:
		var pair_key := str(raw_pair_key)
		if current_pairs.has(pair_key):
			continue
		var previous: Dictionary = _brush_touch_pairs[pair_key]
		entity_world.queue_touch(
			int(previous.entity_id),
			int(previous.activator_id),
			EntityWorldScript.TOUCH_EXIT,
		)
	_brush_touch_pairs = current_pairs


func _process_breakable_touches() -> void:
	if breakable_runtime == null:
		return
	# Gather the actors and their hulls once per tick, not once per breakable.
	var actors := _live_combatants_stable()
	var actor_hulls: Array[AABB] = []
	for actor: Combatant in actors:
		var actor_size := (
			_human_hull_size(actor as PlayerController)
			if actor is PlayerController
			else TargetActor.STANDING_HULL_SIZE
		)
		actor_hulls.append(_feet_hull_aabb(actor.global_position, actor_size))
	for breakable: Vector2i in breakable_runtime.alive_models():
		var entity_id := breakable.x
		var bounds := _model_world_aabb(breakable.y)
		for actor_index in actors.size():
			var actor: Combatant = actors[actor_index]
			if not is_instance_valid(actor) or not actor.alive:
				continue  # a break earlier this tick can kill (explosive breakables)
			var actor_bounds := actor_hulls[actor_index]
			if not _aabb_touches(actor_bounds, bounds):
				continue
			var standing_on_top := (
				absf(actor_bounds.position.y - bounds.end.y)
				<= 2.0 * GOLDSRC_UNIT
				and actor_bounds.end.x >= bounds.position.x
				and actor_bounds.position.x <= bounds.end.x
				and actor_bounds.end.z >= bounds.position.z
				and actor_bounds.position.z <= bounds.end.z
			)
			var source_velocity := Vector3(
				actor.velocity.x,
				-actor.velocity.z,
				actor.velocity.y,
			) / GOLDSRC_UNIT
			breakable_runtime.touch(
				entity_id,
				_brush_activator_id(actor),
				source_velocity,
				standing_on_top,
				true,
			)


func _sorted_brush_entity_ids() -> Array:
	var ids: Array = []
	if brush_runtime == null:
		return ids
	for entity_id in entity_world.entity_count():
		if brush_runtime.has_entity(entity_id):
			ids.append(entity_id)
	return ids


func _live_combatants_stable() -> Array[Combatant]:
	var actors: Array[Combatant] = []
	if is_instance_valid(player) and player.alive:
		actors.append(player)
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if human.alive and human.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
				actors.append(human)
	var bots := _all_bots()
	bots.sort_custom(func(left: TargetActor, right: TargetActor) -> bool:
		return left.name.naturalnocasecmp_to(right.name) < 0
	)
	for bot: TargetActor in bots:
		if is_instance_valid(bot) and bot.alive:
			actors.append(bot)
	return actors


func _brush_activator_id(actor: Node3D) -> int:
	if actor is CS16Hostage:
		return int(actor.get_meta("entity_index", -1))
	var base := entity_world.entity_count() + 1
	if actor == player:
		return base
	if _bot_brush_activator_ids.has(actor.get_instance_id()):
		return int(_bot_brush_activator_ids[actor.get_instance_id()])
	if actor is PlayerController and is_instance_valid(remote_roster):
		var actor_id: String = remote_roster.id_for_actor(actor)
		if _remote_brush_activator_ids.has(actor_id):
			return int(_remote_brush_activator_ids[actor_id])
	var bots := _all_bots()
	bots.sort_custom(func(left: TargetActor, right: TargetActor) -> bool:
		return left.name.naturalnocasecmp_to(right.name) < 0
	)
	for bot_index in bots.size():
		if bots[bot_index] == actor:
			return base + bot_index + 1
	return base + 4096


func _brush_world_aabb(entity_id: int) -> AABB:
	if brush_runtime == null:
		return AABB()
	var brush := brush_runtime.get_brush(entity_id)
	if brush.is_empty():
		return AABB()
	return _model_world_aabb(int(brush.model_index))


func _model_world_aabb(model_index: int) -> AABB:
	var local_bounds := imported_map.model_bounds_for_index(model_index)
	var model_root := imported_map.model_root(model_index)
	if model_root == null:
		return AABB()
	var world_transform := model_root.global_transform
	var first := world_transform * local_bounds.get_endpoint(0)
	var bounds := AABB(first, Vector3.ZERO)
	for corner_index in range(1, 8):
		bounds = bounds.expand(
			world_transform * local_bounds.get_endpoint(corner_index)
		)
	return bounds


func _on_hostage_use_requested(hostage: CS16Hostage, actor: Node) -> void:
	if hostage_state == null or not is_instance_valid(hostage) or actor == null:
		return
	var actor_id := _round_id_for_actor(actor as Combatant)
	var team: String = (
		HostageStateScript.TEAM_CT
		if str(actor.get("team")) == Combatant.TEAM_COUNTER_TERRORIST
		else RoundStateScript.TEAM_T
	)
	var result: Dictionary = hostage_state.use_hostage(
		hostage.hostage_id,
		actor_id,
		team,
		bool(actor.get("alive")),
	)
	if result.is_empty():
		return
	if bool(result.first_use):
		round_state.adjust_player_money(
			actor_id,
			int(result.player_reward),
			"hostage_touched",
		)
		round_state.add_pending_team_account(
			RoundStateScript.TEAM_CT,
			int(result.team_reward),
			"hostage_touched",
		)
	_consume_new_round_trace()
	_sync_hostage_actors()
	hud.show_banner(
		"HOSTAGE IS %s"
		% ("FOLLOWING" if bool(result.following) else "WAITING"),
		Color("#77d9ff"),
		1.2,
	)


func _on_hostage_damage_requested(
	hostage: CS16Hostage,
	damage: int,
	hit_group: int,
	_weapon_name: String,
	_impact_position: Vector3,
	attacker: Node,
) -> void:
	if hostage_state == null or not is_instance_valid(hostage):
		return
	var hitgroup_names := [
		"generic",
		"head",
		"chest",
		"stomach",
		"left_arm",
		"right_arm",
		"left_leg",
		"right_leg",
		"generic",
	]
	var hitgroup_name: String = (
		hitgroup_names[hit_group]
		if hit_group >= 0 and hit_group < hitgroup_names.size()
		else "generic"
	)
	var attacker_id := (
		_round_id_for_actor(attacker as Combatant)
		if attacker is Combatant
		else ""
	)
	var result := hostage_state.apply_damage(
		hostage.hostage_id,
		float(damage),
		hitgroup_name,
		attacker_id,
	)
	if result.is_empty():
		return
	if not attacker_id.is_empty() and round_state.players.has(attacker_id):
		round_state.adjust_player_money(
			attacker_id,
			int(result.money_penalty),
			"hostage_killed" if bool(result.killed) else "hostage_injured",
		)
	if bool(result.killed):
		hostage.hostage_model.play_death()
	else:
		hostage.hurt()
	_sync_hostage_actors()
	_consume_new_round_trace()
	hud.show_banner(
		"HOSTAGE KILLED" if bool(result.killed) else "HOSTAGE INJURED",
		Color("#ff6f61"),
		1.5,
	)


func _advance_hostages() -> void:
	if hostage_state == null:
		return
	hostage_state.advance_tick()
	if phase == RoundStateScript.PHASE_LIVE:
		_process_hostage_bot_use_commands()
		for hostage_id: String in hostage_actors:
			_advance_hostage_follow(hostage_id)
			if hostage_state.tick % HostageStateScript.THINK_INTERVAL_TICKS == 0:
				_check_hostage_rescue(hostage_id)
	_sync_hostage_actors()
	for actor: CS16Hostage in hostage_actors.values():
		actor.advance_hostage_tick()


func _advance_hostage_follow(hostage_id: String) -> void:
	var actor: CS16Hostage = hostage_actors.get(hostage_id)
	if not is_instance_valid(actor) or not hostage_state.hostages.has(hostage_id):
		return
	var contract: Dictionary = hostage_state.hostages[hostage_id]
	if (
		not bool(contract.alive)
		or bool(contract.rescued)
		or not bool(contract.following)
	):
		actor.set_motion_velocity_hu(Vector3.ZERO)
		return
	var leader := _actor_for_round_id(str(contract.leader_id))
	if not is_instance_valid(leader) or not leader.alive:
		hostage_state.release_invalid_leader(hostage_id, false)
		actor.move_source_tick(Vector3.ZERO)
		return
	var distance_to_leader := actor.global_position.distance_to(leader.global_position)
	if distance_to_leader <= 0.80:
		actor.move_source_tick(Vector3.ZERO)
		hostage_state.set_position(
			hostage_id,
			actor.global_position / HostageActorScript.GOLDSRC_UNIT,
		)
		hostage_state.update_stuck(hostage_id, false)
		return
	var previous_position := actor.global_position
	var next_point := _hostage_navigation_point(
		hostage_id,
		actor.global_position,
		leader.global_position,
	)
	var direction := next_point - actor.global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.000001:
		direction = leader.global_position - actor.global_position
		direction.y = 0.0
	if direction.length_squared() <= 0.000001:
		actor.move_source_tick(Vector3.ZERO)
		hostage_state.set_position(
			hostage_id,
			actor.global_position / HostageActorScript.GOLDSRC_UNIT,
		)
		return
	var velocity_hu := direction.normalized() * 250.0
	actor.look_at(
		actor.global_position + Vector3(direction.x, 0.0, direction.z),
		Vector3.UP,
	)
	actor.move_source_tick(velocity_hu)
	hostage_state.set_position(
		hostage_id,
		actor.global_position / HostageActorScript.GOLDSRC_UNIT,
	)
	var moved_hu := (
		actor.global_position.distance_to(previous_position)
		/ HostageActorScript.GOLDSRC_UNIT
	)
	hostage_state.update_stuck(hostage_id, moved_hu < 0.25)


func _hostage_navigation_point(
	hostage_id: String,
	from_position: Vector3,
	target_position: Vector3,
) -> Vector3:
	var path: PackedVector3Array = _hostage_paths.get(hostage_id, PackedVector3Array())
	var path_index := int(_hostage_path_indices.get(hostage_id, 0))
	# Consume a reached entrance before considering a refresh. Re-querying from
	# inside an off-mesh link can project back to its entrance, making the pawn
	# oscillate forever when the crossing takes longer than the refresh interval.
	while path_index < path.size() - 1 and from_position.distance_to(path[path_index]) <= 0.24:
		path_index += 1
	var should_repath := (
		not _hostage_paths.has(hostage_id)
		or hostage_state.tick % 25 == 0
		or (
			_hostage_path_targets.has(hostage_id)
			and (_hostage_path_targets[hostage_id] as Vector3).distance_to(target_position)
				> 0.50
		)
	) and not _hostage_traversing_link(path, path_index, from_position)
	if should_repath and is_instance_valid(imported_map):
		var map_rid := imported_map.navigation_region.get_navigation_map()
		var route := NavigationServer3D.map_get_path(
			map_rid,
			from_position,
			target_position,
			true,
		)
		_hostage_paths[hostage_id] = route
		_hostage_path_indices[hostage_id] = 0
		_hostage_path_targets[hostage_id] = target_position
		path = route
		path_index = 0
	while (
		path_index < path.size() - 1
		and from_position.distance_to(path[path_index]) <= 0.24
	):
		path_index += 1
	_hostage_path_indices[hostage_id] = path_index
	return path[path_index] if path_index < path.size() else target_position


func _hostage_traversing_link(path: PackedVector3Array, path_index: int, from_position: Vector3) -> bool:
	if not is_instance_valid(imported_map) or path_index <= 0 or path_index >= path.size():
		return false
	if from_position.distance_to(path[path_index]) <= 0.24:
		return false
	for link: NavigationLink3D in imported_map.navigation_links:
		if not link.enabled:
			continue
		var start := link.get_global_start_position()
		var end := link.get_global_end_position()
		if (path[path_index - 1].distance_to(start) < 0.001
			and path[path_index].distance_to(end) < 0.001):
			return true
		if (link.bidirectional and path[path_index - 1].distance_to(end) < 0.001
			and path[path_index].distance_to(start) < 0.001):
			return true
	return false


func _check_hostage_rescue(hostage_id: String) -> void:
	if not hostage_state.hostages.has(hostage_id):
		return
	var contract: Dictionary = hostage_state.hostages[hostage_id]
	if not bool(contract.alive) or bool(contract.rescued):
		return
	var position_meters := Vector3(contract.position_hu) * HostageActorScript.GOLDSRC_UNIT
	var in_rescue_zone := false
	# Stock cs_assault has no explicit rescue brush/point. GoldSrc falls back to
	# strict <256 HU distance from any CT spawn.
	for rescue_position: Vector3 in counter_terrorist_team_spawns:
		if position_meters.distance_to(rescue_position) < (
			HostageStateScript.LEGACY_RESCUE_RADIUS_HU
			* HostageActorScript.GOLDSRC_UNIT
		):
			in_rescue_zone = true
			break
	if not in_rescue_zone:
		return
	var rescuer_id := str(contract.leader_id)
	var result := hostage_state.rescue(hostage_id, rescuer_id)
	if result.is_empty():
		return
	if not rescuer_id.is_empty():
		round_state.adjust_player_money(
			rescuer_id,
			int(result.player_reward),
			"hostage_rescued",
		)
	round_state.add_pending_team_account(
		RoundStateScript.TEAM_CT,
		int(result.next_round_ct_reward),
		"hostage_rescued",
	)
	_sync_hostage_actors()
	hud.show_banner("HOSTAGE RESCUED", Color("#77d9ff"), 1.5)
	var objective_result := hostage_state.round_result()
	if not objective_result.is_empty():
		round_state.resolve_scenario_objective(
			str(objective_result.winner),
			str(objective_result.reason),
			int(objective_result.team_reward),
		)
	_consume_new_round_trace()


func _sync_hostage_actors() -> void:
	if hostage_state == null:
		return
	for hostage_id: String in hostage_actors:
		var actor: CS16Hostage = hostage_actors[hostage_id]
		if (
			is_instance_valid(actor)
			and hostage_state.hostages.has(hostage_id)
		):
			actor.apply_contract_state(hostage_state.hostages[hostage_id])


func _process_hostage_bot_use_commands() -> void:
	_refresh_hostage_bot_assignments()
	var ct_bots: Array[TargetActor] = []
	for bot in _all_bots():
		if (
			bot.alive
			and bot.active
			and bot.team == Combatant.TEAM_COUNTER_TERRORIST
		):
			ct_bots.append(bot)
	ct_bots.sort_custom(
		func(first: TargetActor, second: TargetActor) -> bool:
			return str(first.name) < str(second.name)
	)
	for bot in ct_bots:
		var command: Dictionary = bot.last_command
		if (
			str(command.get("objective_action", "")) != "use_hostage"
			or not bool(command.get("use", false))
		):
			continue
		var hostage_id := str(command.get("objective_id", ""))
		if (
			hostage_id.is_empty()
			or str(_hostage_bot_assignments.get(bot.name, "")) != hostage_id
			or not hostage_actors.has(hostage_id)
		):
			continue
		var hostage: CS16Hostage = hostage_actors[hostage_id]
		if not is_instance_valid(hostage) or not hostage.source_use_usable(bot):
			continue
		var use_origin := hostage.source_use_origin()
		if (
			bot.global_position.distance_to(use_origin)
			> HostageStateScript.USE_RADIUS_HU * GOLDSRC_UNIT
		):
			continue
		var to_hostage := use_origin - bot.aim_point()
		var view_forward := -bot.global_transform.basis.z
		if (
			to_hostage.is_zero_approx()
			or view_forward.is_zero_approx()
			or to_hostage.normalized().dot(view_forward.normalized())
				<= HostageStateScript.USE_VIEW_DOT
		):
			continue
		hostage.request_source_use(bot)


func _refresh_hostage_bot_assignments() -> void:
	if (
		scenario != ScenarioRulesScript.SCENARIO_HOSTAGE
		or hostage_state == null
	):
		_hostage_bot_assignments.clear()
		return
	var ct_bots: Array[TargetActor] = []
	var ct_by_name := {}
	for bot in _all_bots():
		if (
			bot.alive
			and bot.team == Combatant.TEAM_COUNTER_TERRORIST
		):
			ct_bots.append(bot)
			ct_by_name[bot.name] = bot
	ct_bots.sort_custom(
		func(first: TargetActor, second: TargetActor) -> bool:
			return str(first.name) < str(second.name)
	)

	var hostage_ids: Array[String] = []
	for hostage_id: String in hostage_state.hostages:
		var contract: Dictionary = hostage_state.hostages[hostage_id]
		if bool(contract.alive) and not bool(contract.rescued):
			hostage_ids.append(hostage_id)
	hostage_ids.sort()
	for raw_hostage_id: Variant in _hostage_bot_rescue_targets.keys():
		if str(raw_hostage_id) not in hostage_ids:
			_hostage_bot_rescue_targets.erase(raw_hostage_id)

	# A following hostage remains reserved for its living leader. This is the
	# strongest assignment and survives distance changes during the escort.
	var claimed := {}
	var next_assignments := {}
	for hostage_id: String in hostage_ids:
		var contract: Dictionary = hostage_state.hostages[hostage_id]
		if not bool(contract.following):
			continue
		# A human-led hostage is unavailable to bot selection as well; bots must
		# support that escort rather than stealing its leader on another +use.
		claimed[hostage_id] = true
		var leader_id := str(contract.leader_id)
		if ct_by_name.has(leader_id) and not next_assignments.has(leader_id):
			next_assignments[leader_id] = hostage_id

	# Keep valid pre-use assignments stable so two bots approaching adjacent
	# Assault hostages cannot swap targets as their distance ordering crosses.
	for bot in ct_bots:
		if next_assignments.has(bot.name):
			continue
		var existing_id := str(_hostage_bot_assignments.get(bot.name, ""))
		if existing_id.is_empty() or claimed.has(existing_id):
			continue
		if existing_id in hostage_ids:
			var contract: Dictionary = hostage_state.hostages[existing_id]
			if not bool(contract.following):
				next_assignments[bot.name] = existing_id
				claimed[existing_id] = true

	# Source task ownership must not oscillate with sub-unit physics drift.
	# Living CTs in stable actor order claim available hostages in stable BSP
	# entity order. On Assault the four hostages share one room, so this keeps
	# the source-style distribution while remaining host/render independent.
	for bot in ct_bots:
		if next_assignments.has(bot.name):
			continue
		var selected_id := ""
		for hostage_id: String in hostage_ids:
			if claimed.has(hostage_id):
				continue
			var hostage: CS16Hostage = hostage_actors.get(hostage_id)
			if not is_instance_valid(hostage):
				continue
			selected_id = hostage_id
			break
		if not selected_id.is_empty():
			next_assignments[bot.name] = selected_id
			claimed[selected_id] = true
	_hostage_bot_assignments = next_assignments


func _hostage_bot_objective_context(bot: TargetActor) -> Dictionary:
	_refresh_hostage_bot_assignments()
	var live_hostage_ids: Array[String] = []
	var following_hostage_ids: Array[String] = []
	for hostage_id: String in hostage_state.hostages:
		var contract: Dictionary = hostage_state.hostages[hostage_id]
		if not bool(contract.alive) or bool(contract.rescued):
			continue
		live_hostage_ids.append(hostage_id)
		if bool(contract.following):
			following_hostage_ids.append(hostage_id)
	live_hostage_ids.sort()
	following_hostage_ids.sort()
	if live_hostage_ids.is_empty():
		return {}

	if bot.team == Combatant.TEAM_COUNTER_TERRORIST:
		var assigned_id := str(_hostage_bot_assignments.get(bot.name, ""))
		if not assigned_id.is_empty():
			var contract: Dictionary = hostage_state.hostages[assigned_id]
			var hostage: CS16Hostage = hostage_actors.get(assigned_id)
			if is_instance_valid(hostage):
				if (
					bool(contract.following)
					and str(contract.leader_id) == bot.name
				):
					var rescue_position := _assigned_hostage_rescue_position(
						assigned_id,
						hostage.global_position
					)
					return {
						"state": "escort_hostage",
						"action": "escort_hostage",
						"objective_id": assigned_id,
						"target": rescue_position,
						"look_target": rescue_position,
						"stop_radius": 0.32,
					}
				var use_origin := hostage.source_use_origin()
				return {
					"state": "rescue_hostage",
					"action": "use_hostage",
					"objective_id": assigned_id,
					"target": hostage.global_position,
					"look_target": use_origin,
					"stop_radius": 48.0 * GOLDSRC_UNIT,
					"use": (
						bot.global_position.distance_to(use_origin)
						<= HostageStateScript.USE_RADIUS_HU * GOLDSRC_UNIT
					),
				}
		if not following_hostage_ids.is_empty():
			var support_id := following_hostage_ids[
				bot.index % following_hostage_ids.size()
			]
			var support: Dictionary = hostage_state.hostages[support_id]
			var leader := _actor_for_round_id(str(support.leader_id))
			if is_instance_valid(leader):
				var support_target := _hostage_guard_position(
					leader.global_position,
					bot,
					0.90,
				)
				return {
					"state": "cover_hostage_escort",
					"action": "cover_hostage",
					"objective_id": support_id,
					"target": support_target,
					"look_target": leader.global_position,
					"stop_radius": 0.32,
				}
		return {}

	if bot.team != Combatant.TEAM_TERRORIST:
		return {}
	if following_hostage_ids.is_empty():
		var guard_id := live_hostage_ids[bot.index % live_hostage_ids.size()]
		var guarded: CS16Hostage = hostage_actors.get(guard_id)
		if not is_instance_valid(guarded):
			return {}
		return {
			"state": "guard_hostages",
			"action": "guard_hostage",
			"objective_id": guard_id,
			"target": _hostage_guard_position(
				guarded.global_position,
				bot,
				1.10,
			),
			"look_target": guarded.global_position,
			"stop_radius": 0.32,
		}

	var intercept_id := following_hostage_ids[
		bot.index % following_hostage_ids.size()
	]
	var escaping: Dictionary = hostage_state.hostages[intercept_id]
	var escort := _actor_for_round_id(str(escaping.leader_id))
	var hostage_actor: CS16Hostage = hostage_actors.get(intercept_id)
	if not is_instance_valid(escort) or not is_instance_valid(hostage_actor):
		return {}
	var rescue_position := _assigned_hostage_rescue_position(
		intercept_id,
		hostage_actor.global_position,
	)
	var intercept_target := escort.global_position.lerp(rescue_position, 0.42)
	var route_direction := rescue_position - escort.global_position
	route_direction.y = 0.0
	if not route_direction.is_zero_approx():
		var side := Vector3(-route_direction.z, 0.0, route_direction.x).normalized()
		intercept_target += side * (
			0.55 if bot.index % 2 == 0 else -0.55
		)
	return {
		"state": "intercept_hostage_rescue",
		"action": "intercept_hostage",
		"objective_id": intercept_id,
		"target": intercept_target,
		"look_target": escort.aim_point(),
		"stop_radius": 0.32,
	}


func _hostage_rescue_position(from_position: Vector3) -> Vector3:
	var nearest := from_position
	var nearest_distance := INF
	for rescue_position: Vector3 in counter_terrorist_team_spawns:
		var distance := from_position.distance_squared_to(rescue_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = rescue_position
	return nearest


func _assigned_hostage_rescue_position(
	hostage_id: String,
	from_position: Vector3,
) -> Vector3:
	if _hostage_bot_rescue_targets.has(hostage_id):
		return _hostage_bot_rescue_targets[hostage_id] as Vector3
	var rescue_position := _hostage_rescue_position(from_position)
	_hostage_bot_rescue_targets[hostage_id] = rescue_position
	return rescue_position


func _hostage_guard_position(
	center: Vector3,
	bot: TargetActor,
	radius: float,
) -> Vector3:
	var angle := float((bot.index * 137 + 31) % 360) * PI / 180.0
	return center + Vector3(cos(angle), 0.0, sin(angle)) * radius


func _process(delta: float) -> void:
	# Round and objective time is owned exclusively by the 100 Hz physics tick.
	pass


func _physics_process(delta: float) -> void:
	if _network_menu_join_pending and Time.get_ticks_msec() >= _network_menu_deadline_ms:
		_network_menu_join_pending = false
		var session := get_node("/root/NetworkSession")
		session.disconnect_session()
		session._set_status("HOST WORLD TIMED OUT")
	if _network_client_mode:
		# Local presentation sounds still need expiry; do not run gameplay ticks.
		if is_instance_valid(audio_router):
			audio_router.advance_ticks(1)
			var listener := get_viewport().get_camera_3d()
			if is_instance_valid(listener):
				audio_playback.set_listener_origin_hu(AudioRouterScript.meters_to_hu(listener.global_position))
		if is_instance_valid(network_client_view):
			network_client_view.tick_input(delta)
		return
	_refresh_visible_scoreboard(delta)
	_drop_hostages_to_floor()
	if is_instance_valid(audio_router):
		audio_router.advance_ticks(1)
		# Positional gain must follow the view, including deployment, scripted
		# cameras and spectating, rather than the inactive/dead player's body.
		var listener_camera := get_viewport().get_camera_3d()
		if is_instance_valid(listener_camera):
			audio_playback.set_listener_origin_hu(
				AudioRouterScript.meters_to_hu(listener_camera.global_position)
			)
	if (
		match_started
		and not get_tree().paused
		and is_instance_valid(round_state)
	):
		var world_use_selections := _process_player_world_use()
		_queue_brush_touches()
		_process_breakable_touches()
		if entity_world != null:
			entity_world.advance_tick()
		_advance_trigger_camera()
		if brush_runtime != null:
			brush_runtime.advance_tick(false)
		if breakable_runtime != null:
			breakable_runtime.advance_tick(false)
		if is_instance_valid(breakable_debris):
			breakable_debris.advance_tick()
		_advance_hostages()
		_sync_dropped_c4_position()
		_process_weapon_pickups()
		var round_events: Array[Dictionary] = round_state.advance_tick(
			_round_tick_command(world_use_selections)
		)
		_consume_round_events(round_events)
		_advance_objective_audio()
		_consumed_round_events = round_state.trace.size()
		_sync_round_public_state()
		_update_round_hud()
		_update_tactical_hud()
	_publish_network_world(delta)
	if not match_started or not is_instance_valid(player):
		return
	_submit_network_input(player.last_command)


func _submit_network_input(command: Dictionary) -> void:
	var network := get_node("/root/NetworkSession")
	var movement: Vector2 = command.get("movement", Vector2.ZERO)
	var input_angles := player.input_view_angles()
	network.submit_local_input({
		"movement": movement,
		"yaw": input_angles.x,
		"pitch": input_angles.y,
		"buttons": (
			(1 if command.get("fire", false) else 0)
			| (2 if command.get("jump", false) else 0)
			| (4 if command.get("crouch", false) else 0)
			| (8 if command.get("reload", false) else 0)
			| (16 if command.get("use", false) else 0)
			| (32 if command.get("walk", false) else 0)
		),
	})


func _network_actor_state(actor: Combatant) -> Dictionary:
	var actor_id := _round_id_for_actor(actor)
	var row: Dictionary = round_state.players.get(actor_id, {})
	var human := actor as PlayerController
	var bot := actor as TargetActor
	var weapon: String = human.active_weapon if human != null else bot.active_weapon_name
	var skin: String = (selected_player_skin if human == player else str(human.get_meta("cs16_player_skin", "terror"))) if human != null else bot.player_skin
	return {"id": actor_id, "kind": "human" if human != null else "bot", "name": actor.display_name,
		"team": actor.team, "position": actor.global_position, "velocity": actor.velocity,
		"angles": human.input_view_angles() if human != null else Vector2(
			wrapf(actor.rotation.y, -PI, PI), bot.spectator_view_pitch),
		"alive": actor.alive and actor.team != "UNASSIGNED", "visible": actor.visible and actor.team != "UNASSIGNED",
		"health": actor.health, "armor": actor.armor, "helmet": actor.has_helmet,
		"weapon": weapon, "clip": human.clip if human != null else bot.weapon_clip,
		"reserve": human.reserve if human != null else bot.weapon_reserve,
		"reloading": human.reloading if human != null else bot.weapon_reloading, "skin": skin,
		"life": human.spawn_serial if human != null else round_state.round_number,
		"crouched": not human._standing if human != null else bot.is_crouching(),
		"kills": int(row.get("kills", 0)), "deaths": int(row.get("deaths", 0)), "money": int(row.get("money", 800)),
		"class_id": int(human.get_meta("cs16_class_id", 0)) if human != null else 0,
		"ping": _actor_ping_ms(actor)}


## Scoreboard latency: the host's own player is 0 ms, remote humans carry the
## session's measured round trip, and bots (or unmeasured peers) are -1.
func _actor_ping_ms(actor: Combatant) -> int:
	var human := actor as PlayerController
	if human == null:
		return -1
	if human == player:
		return 0
	var peer_id := int(human.combat_controller._peer_id) if is_instance_valid(human.combat_controller) else 0
	if peer_id <= 1:
		return -1
	return get_node("/root/NetworkSession").peer_rtt_ms(peer_id)


## CS 1.6 shows "BOT" in the latency column for bots.
static func scoreboard_latency(kind: String, ping_ms: int) -> String:
	if kind == "bot":
		return "BOT"
	return str(ping_ms) if ping_ms >= 0 else ""


func publish_combat_presentation(actor: Combatant, kind: String, data: Dictionary) -> void:
	var network := get_node("/root/NetworkSession")
	if not network.is_host or not network.is_online() or not is_instance_valid(actor):
		return
	var actor_id := _round_id_for_actor(actor)
	if actor_id.is_empty():
		return
	var life: int = actor.spawn_serial if actor is PlayerController else round_state.round_number
	network.send_combat_event(actor_id, life, kind, data)


func _publish_network_impact(kind: String, data: Dictionary) -> void:
	var network := get_node("/root/NetworkSession")
	if network.is_host and is_instance_valid(round_state):
		network.send_combat_event("", round_state.round_number, kind, data)


func _publish_network_audio(event: Dictionary) -> void:
	var network := get_node("/root/NetworkSession")
	if not network.is_host or not network.is_online() or event.event_name == "weapon.mode_switch":
		return
	# Replicate actual sample choices, never pick a fresh random variant. Dynamic
	# material footsteps are permitted only when the selected sample belongs to
	# the named material family.
	if not AudioRouterScript.AudioCatalog.network_audio_sample_valid(
		str(event.event_name),
		str(event.sample),
	):
		return
	for actor: Combatant in _human_players_stable() + _all_bots():
		if actor.audio_entity_id() == int(event.entity_id):
			publish_combat_presentation(actor, "audio", {"name": event.event_name, "sample": event.sample,
				"channel": event.channel, "volume": event.volume, "attenuation": event.attenuation,
				"pitch": event.pitch, "origin": Vector3(event.origin[0], event.origin[1], event.origin[2]) / AudioRouterScript.HU_PER_METER})
			return
	var source := -1
	if int(event.entity_id) == 0 and (str(event.event_name).begins_with("c4.") or str(event.event_name).begins_with("radio.bomb_") or str(event.event_name).begins_with("round.") or str(event.event_name) == "weapon.drop"):
		source = 0
	else:
		for grenade: Node in get_tree().get_nodes_in_group("live_grenades"):
			if grenade._audio_entity_id() == int(event.entity_id):
				source = int(grenade.get_meta("network_item_id", 0))
				break
	if source >= 0:
		_publish_network_impact("world_audio", {"source": source, "name": event.event_name, "sample": event.sample,
			"channel": event.channel, "volume": event.volume, "attenuation": event.attenuation, "pitch": event.pitch,
			"origin": Vector3(event.origin[0], event.origin[1], event.origin[2]) / AudioRouterScript.HU_PER_METER})


func _network_owner_feedback(human: PlayerController) -> Dictionary:
	var feedback := get_node("/root/NetworkSession").WorldState.empty_feedback() as Dictionary
	feedback.bomb_state = str(round_state.bomb_state)
	feedback.result = _network_objective_result
	var actor_id := _round_id_for_actor(human)
	var action: Dictionary = round_state.action_progress()
	if human.alive and not action.is_empty() and str(action.actor) == actor_id:
		feedback.action = str(action.action)
		feedback.total = float(action.duration_ticks) / 100.0
		feedback.remaining = maxf(0.0, float(action.duration_ticks - action.elapsed_ticks) / 100.0)
	if human.alive:
		feedback.flash_total = human.flash_blind_total_seconds
		feedback.flash_remaining = clampf(float(human.flash_blind_until_frame - Engine.get_physics_frames()) / Engine.physics_ticks_per_second, 0.0, feedback.flash_total)
		feedback.can_plant = round_state.bomb_owner == actor_id and not _bomb_region_at(human.global_position, _human_hull_size(human)).is_empty()
	return feedback


func _publish_network_world(delta: float) -> void:
	var network := get_node("/root/NetworkSession")
	if not network.is_host or not is_instance_valid(remote_roster) or remote_roster.size() == 0 or not network.world_snapshot_due(delta):
		return
	var actors: Array[Dictionary] = []
	for human: PlayerController in _human_players_stable():
		actors.append(_network_actor_state(human))
	for bot: TargetActor in _all_bots():
		actors.append(_network_actor_state(bot))
	var state := {"tick": Engine.get_physics_frames(), "map": map_name, "started": match_started, "concluded": _match_concluded,
		"round": {"number": round_number, "phase": phase, "seconds": seconds_left, "t_score": terrorist_score, "ct_score": ct_score},
		"actors": actors, "owner_id": "", "input_ack": 0, "items": _network_world_items(),
		"broken_brushes": breakable_runtime.broken_model_indices() if breakable_runtime != null else [],
		"sprays": sprays.records.duplicate(true)}
	for actor_id: String in remote_roster.actor_ids():
		var human: PlayerController = remote_roster.actor_for_id(actor_id)
		state.owner_id = actor_id
		state.input_ack = int(human.combat_controller._last_sequence)
		state.inventory = network.WorldState.inventory_for(human)
		state.motion = network.WorldState.motion_for(human)
		state.feedback = _network_owner_feedback(human)
		state.can_buy = bool(_human_buy_eligibility(human).allowed)
		network.send_world_snapshot(human.combat_controller._peer_id, state)


func _network_item_state(item: Node3D, kind: String, weapon: String) -> Dictionary:
	if not item.has_meta("network_item_id"):
		item.set_meta("network_item_id", _next_network_item_id)
		_next_network_item_id += 1
	var total := float(round_state.config.c4_ticks) / 100.0 if kind == "planted_c4" else 0.0
	var remaining := clampf(float(round_state.bomb_deadline_tick - round_state.tick) / 100.0, 0.0, total) if kind == "planted_c4" else 0.0
	if kind == "smoke":
		total = float(item._cleanup_tick - item._detonated_tick) / 100.0
		remaining = clampf(float(item._cleanup_tick - item._simulation_tick) / 100.0, 0.0, total)
	return {"id": int(item.get_meta("network_item_id")), "kind": kind, "weapon": weapon,
		"position": item.global_position, "rotation": item.global_basis.get_rotation_quaternion().normalized(),
		"total": total, "remaining": remaining}


func _network_world_items() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for grenade: Node3D in get_tree().get_nodes_in_group("live_grenades"):
		if grenade.is_queued_for_deletion():
			continue
		if not grenade._exploded:
			items.append(_network_item_state(grenade, "grenade", grenade.grenade_kind))
		elif grenade.grenade_kind == "smokegrenade":
			items.append(_network_item_state(grenade, "smoke", grenade.grenade_kind))
	for item: CS16DroppedWeapon in dropped_weapons:
		if is_instance_valid(item) and not item.is_queued_for_deletion() and item.visible:
			items.append(_network_item_state(item, "gun", item.weapon_name))
	if is_instance_valid(dropped_c4) and not dropped_c4.is_queued_for_deletion() and dropped_c4.visible:
		items.append(_network_item_state(dropped_c4, "dropped_c4", "c4"))
	if is_instance_valid(bomb) and not bomb.is_queued_for_deletion() and bomb.visible:
		items.append(_network_item_state(bomb, "planted_c4", "c4"))
	return items


func _update_tactical_hud() -> void:
	if not is_instance_valid(hud) or not is_instance_valid(player):
		return
	var observer: Combatant = player
	if is_instance_valid(spectator_camera) and spectator_camera.is_first_person() \
			and is_instance_valid(spectator_camera.target):
		observer = spectator_camera.target
	hud.update_defuse_kit(player.team, player.alive, bool(player.equipment.get("defuser", false)))
	var carrying_c4: bool = player.alive and round_state.bomb_owner == _round_id_for_actor(player)
	hud.update_bomb_carrier(carrying_c4,
		carrying_c4 and not _bomb_region_at(player.global_position, _human_hull_size(player)).is_empty())
	# CS 1.6 shows the cart glyph while the player stands in their team's buy
	# zone and buying is still possible; nothing drove it before.
	hud.set_buy_zone(
		is_instance_valid(round_state)
		and player.alive
		and bool(_buy_eligibility().allowed)
	)
	var contacts: Array[Dictionary] = []
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if human != observer and human.team == player.team and human.team in ["T", "CT"]:
				contacts.append({"id": actor_id, "position": human.global_position, "alive": human.alive})
	for bot: TargetActor in _all_bots():
		if bot == observer or bot.team != player.team:
			continue
		contacts.append({
			"id": bot.name,
			"position": bot.global_position,
			# CS 1.6 shows teammate blips whenever they are alive, including
			# freeze time (bots are not yet "active" then).
			"alive": bot.alive,
		})
	contacts.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return str(left.id) < str(right.id)
	)
	if is_instance_valid(round_state):
		contacts.append_array(CS16RadarDisplay.bomb_contact(
			observer.team, observer.alive, round_state.bomb_state, round_state.bomb_position))
	if scenario == ScenarioRulesScript.SCENARIO_HOSTAGE:
		for hostage_id_variant in hostage_actors:
			var hostage_actor: Node3D = hostage_actors[hostage_id_variant]
			if not is_instance_valid(hostage_actor):
				continue
			var hostage_alive: Variant = hostage_actor.get("alive")
			contacts.append({
				"id": str(hostage_id_variant),
				"kind": "hostage",
				"position": hostage_actor.global_position,
				"alive": bool(hostage_alive) if hostage_alive != null else true,
			})
	var hostage_snapshot: Array[Dictionary] = []
	if scenario == ScenarioRulesScript.SCENARIO_HOSTAGE and hostage_state != null:
		var hostage_ids: Array = hostage_state.hostages.keys()
		hostage_ids.sort()
		for hostage_id_variant in hostage_ids:
			var hostage_id := str(hostage_id_variant)
			var state: Dictionary = hostage_state.hostages[hostage_id]
			hostage_snapshot.append({
				"id": hostage_id,
				"alive": bool(state.get("alive", true)),
				"rescued": bool(state.get("rescued", false)),
			})
	hud.update_tactical_display(
		observer.global_position,
		observer.global_rotation.y,
		contacts,
		hostage_snapshot,
	)


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


func _schedule_c4_arm_audio(actor_id: String) -> void:
	_objective_audio_schedule.clear()
	for offset: int in AudioCatalogScript.C4_ARM_AUDIO_STAGES:
		_objective_audio_schedule.append({
			"actor_id": actor_id,
			"due_tick": int(round_state.tick) + offset,
		})


func _cancel_c4_arm_audio(actor_id: String) -> void:
	var retained: Array[Dictionary] = []
	for cue: Dictionary in _objective_audio_schedule:
		if str(cue.actor_id) != actor_id:
			retained.append(cue)
	_objective_audio_schedule = retained


func _advance_objective_audio() -> void:
	if _objective_audio_schedule.is_empty():
		return
	var retained: Array[Dictionary] = []
	for cue: Dictionary in _objective_audio_schedule:
		if int(cue.due_tick) > int(round_state.tick):
			retained.append(cue)
			continue
		var actor := _actor_for_round_id(str(cue.actor_id))
		if is_instance_valid(actor) and actor.alive:
			_emit_world_audio(
				"c4.click",
				AudioRouterScript.CHAN_WEAPON,
				actor.global_position,
			)
	_objective_audio_schedule = retained


func _consume_brush_runtime_events(events: Array[Dictionary]) -> void:
	if not is_instance_valid(audio_router):
		return
	for event: Dictionary in events:
		var entity_id := entity_world.entity_count() + int(event.entity_id) + 1
		var origin_hu := AudioRouterScript.meters_to_hu(
			_brush_world_aabb(int(event.entity_id)).get_center()
		)
		var event_name := ""
		if str(event.event) == "move":
			event_name = (
				AudioCatalogScript.button_press_event(int(event.button_sound))
				if str(event.classname) == BrushRuntimeScript.KIND_BUTTON
				else AudioCatalogScript.door_move_event(int(event.movesnd))
			)
		else:
			audio_router.stop_channel(
				entity_id,
				AudioRouterScript.CHAN_STATIC,
				"brush_endpoint",
			)
			if str(event.classname) != BrushRuntimeScript.KIND_BUTTON:
				event_name = AudioCatalogScript.door_stop_event(
					int(event.stopsnd)
				)
		if event_name.is_empty():
			continue
		audio_router.emit_catalog_event(
			event_name,
			entity_id,
			AudioRouterScript.CHAN_STATIC,
			origin_hu,
		)


func _on_brush_runtime_event(event: Dictionary) -> void:
	_consume_brush_runtime_events([event])


func _on_breakable_runtime_event(event: Dictionary) -> void:
	var event_type := str(event.get("event", ""))
	if event_type in ["damage", "break"]:
		var sample := str(event.get("sound", ""))
		if not sample.is_empty() and is_instance_valid(audio_router):
			audio_router.emit_descriptor(
				"breakable.%s.%s"
				% [event_type, str(event.get("material_name", "unknown"))],
				entity_world.entity_count() + int(event.entity_id) + 1,
				{
					"samples": [sample],
					"channel": AudioRouterScript.CHAN_VOICE,
					"volume": float(event.get("volume", 1.0)),
					"attenuation": AudioRouterScript.ATTN_NORM,
					"pitch_min": int(event.get("pitch", 100)),
					"pitch_max": int(event.get("pitch", 100)),
					"flags": 0,
				},
				AudioRouterScript.meters_to_hu(
					_model_world_aabb(int(event.model_index)).get_center()
				),
			)
	elif event_type == "explosion":
		_apply_breakable_explosion(event)


func _apply_breakable_explosion(event: Dictionary) -> void:
	var origin: Vector3 = event.get("origin", Vector3.ZERO)
	var magnitude := float(event.get("magnitude", 0))
	if magnitude <= 0.0:
		return
	var effects := CombatEffectsScript.for_scene(self)
	if is_instance_valid(effects):
		effects.spawn_he_explosion(origin, Vector3.UP)
	var radius := magnitude * 2.5 * GOLDSRC_UNIT
	var blast_underwater := _source_point_in_water(origin)
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
		var target := combatant.aim_point()
		var distance := target.distance_to(origin)
		if distance > radius or not _breakable_blast_visible(origin, target, combatant):
			continue
		combatant.receive_c4_explosion_damage(
			maxf(0.0, magnitude - distance / GOLDSRC_UNIT / 2.5),
			origin,
			null,
		)
	if hostage_state != null:
		for hostage_id: String in hostage_actors:
			var hostage: CS16Hostage = hostage_actors[hostage_id]
			if not is_instance_valid(hostage) or not hostage.alive or hostage.rescued:
				continue
			var target := hostage.global_position + CS16Hostage.HULL_CENTER
			var distance := target.distance_to(origin)
			if distance > radius or not _breakable_blast_visible(origin, target, hostage):
				continue
			_on_hostage_damage_requested(
				hostage,
				roundi(maxf(
					0.0,
					magnitude - distance / GOLDSRC_UNIT / 2.5,
				)),
				0,
				"env_explosion",
				target,
				null,
			)


func _breakable_blast_visible(
	origin: Vector3,
	target: Vector3,
	expected: CollisionObject3D,
) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		origin + Vector3.UP * GOLDSRC_UNIT,
		target,
		1 | 2 | 4 | 16,
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == expected


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


# CS 1.6 radio menus: Z standard, X group, C responses. Wav names are the
# stock cstrike sound/radio files.
const RADIO_MENUS := {
	KEY_Z: {
		"title": "Radio Commands",
		"items": [
			{"label": "Cover Me", "wav": "ct_coverme", "text": "Cover me!"},
			{"label": "You Take the Point", "wav": "takepoint", "text": "You take the point."},
			{"label": "Hold This Position", "wav": "position", "text": "Hold this position."},
			{"label": "Regroup Team", "wav": "regroup", "text": "Regroup, team."},
			{"label": "Follow Me", "wav": "followme", "text": "Follow me."},
			{"label": "Taking Fire, Need Assistance", "wav": "fireassis", "text": "Taking fire... need assistance!"},
		],
	},
	KEY_X: {
		"title": "Group Radio Commands",
		"items": [
			{"label": "Go Go Go!", "wav": "com_go", "text": "Go go go!"},
			{"label": "Team, Fall Back", "wav": "fallback", "text": "Team, fall back!"},
			{"label": "Stick Together, Team", "wav": "sticktog", "text": "Stick together, team."},
			{"label": "Get in Position and Wait", "wav": "com_getinpos", "text": "Get in position and wait for my go."},
			{"label": "Storm the Front", "wav": "stormfront", "text": "Storm the front!"},
			{"label": "Report In, Team", "wav": "com_reportin", "text": "Report in, team."},
		],
	},
	KEY_C: {
		"title": "Radio Responses",
		"items": [
			{"label": "Affirmative", "wav": "ct_affirm", "text": "Affirmative."},
			{"label": "Enemy Spotted", "wav": "ct_enemys", "text": "Enemy spotted."},
			{"label": "Need Backup", "wav": "ct_backup", "text": "Need backup."},
			{"label": "Sector Clear", "wav": "clear", "text": "Sector clear."},
			{"label": "I'm in Position", "wav": "ct_inpos", "text": "I'm in position."},
			{"label": "Reporting In", "wav": "ct_reportingin", "text": "Reporting in."},
			{"label": "She's Gonna Blow!", "wav": "blow", "text": "She's gonna blow!"},
			{"label": "Negative", "wav": "negative", "text": "Negative."},
			{"label": "Enemy Down", "wav": "enemydown", "text": "Enemy down."},
		],
	},
}

var _radio_menu_key := 0
var _radio_voice: AudioStreamPlayer


var _nightvision_on := false


func _toggle_nightvision() -> void:
	## CS 1.6 binds nightvision to N and only honours it once the goggles are
	## bought; the toggle is silent-but-refused otherwise.
	if not is_instance_valid(player) or not player.alive:
		return
	if not bool(player.equipment.get("nvgs", false)):
		return
	_set_nightvision(not _nightvision_on)
	_emit_player_item_audio("nvg_on" if _nightvision_on else "nvg_off")


func _set_nightvision(active: bool) -> void:
	_nightvision_on = active
	if is_instance_valid(hud):
		hud.set_nightvision(active)


var _item_voice: AudioStreamPlayer


func _emit_player_item_audio(sample: String) -> void:
	# Own player so an item click never cuts a radio line short.
	if not is_instance_valid(_item_voice):
		_item_voice = AudioStreamPlayer.new()
		_item_voice.name = "ItemVoice"
		add_child(_item_voice)
	var stream := load(
		"res://assets/sounds/classic/items/%s.wav" % sample
	) as AudioStream
	if stream != null:
		_item_voice.stream = stream
		_item_voice.play()


func _handle_radio_key(keycode: Key) -> bool:
	if not match_started or not is_instance_valid(player) or not player.alive:
		return false
	if _radio_menu_key == 0:
		if not RADIO_MENUS.has(keycode) or _pause_menu_open():
			return false
		_radio_menu_key = keycode
		player.radio_menu_open = true
		var menu: Dictionary = RADIO_MENUS[keycode]
		var labels: Array[String] = []
		for item: Dictionary in menu.items:
			labels.append(str(item.label))
		hud.show_radio_menu(str(menu.title), labels)
		return true
	# A menu is open: digits select, 0/Escape close, Z/X/C switch menus.
	if RADIO_MENUS.has(keycode):
		_close_radio_menu()
		return _handle_radio_key(keycode)
	if keycode == KEY_0 or keycode == KEY_ESCAPE:
		_close_radio_menu()
		return true
	if keycode >= KEY_1 and keycode <= KEY_9:
		var index := int(keycode - KEY_1)
		var items: Array = RADIO_MENUS[_radio_menu_key].items
		if index < items.size():
			_send_radio_message(items[index] as Dictionary)
		_close_radio_menu()
		return true
	return true


func _close_radio_menu() -> void:
	_radio_menu_key = 0
	if is_instance_valid(player):
		player.radio_menu_open = false
	hud.hide_radio_menu()


func _send_radio_message(item: Dictionary) -> void:
	# Radio traffic plays flat and full-volume for the whole team, like the
	# GoldSrc radio channel — never positional.
	var sample_id := str(item.wav)
	var network := get_node("/root/NetworkSession")
	if _network_client_mode:
		if network.request_radio(sample_id) == 0:
			hud.show_banner("RADIO UNAVAILABLE", Color("#ffca66"), 1.5)
		return
	if network.is_host and network.is_online():
		_broadcast_radio_message(player, sample_id, 1)
		return
	_play_radio_message(sample_id, player.display_name, str(item.text))


func _play_radio_message(sample_id: String, sender_name: String, message_text: String) -> void:
	if not AudioCatalogScript.RADIO_MESSAGES.has(sample_id) \
			or message_text != str(AudioCatalogScript.RADIO_MESSAGES[sample_id]):
		return
	if not is_instance_valid(_radio_voice):
		_radio_voice = AudioStreamPlayer.new()
		_radio_voice.name = "RadioVoice"
		add_child(_radio_voice)
	var stream := load(
		"res://assets/sounds/classic/radio/%s.wav" % sample_id
	) as AudioStream
	if stream != null:
		_radio_voice.stream = stream
		_radio_voice.play()
	hud.show_radio_line("%s (RADIO): %s" % [sender_name, message_text])


func _broadcast_radio_message(speaker: PlayerController, sample_id: String, sender_peer_id: int) -> void:
	if not is_instance_valid(speaker) or not AudioCatalogScript.RADIO_MESSAGES.has(sample_id):
		return
	var message_text := str(AudioCatalogScript.RADIO_MESSAGES[sample_id])
	var recipients := _chat_recipient_peers(sender_peer_id, speaker.team, true)
	if recipients.has(1):
		_play_radio_message(sample_id, speaker.display_name, message_text)
	var remote_recipients: Array[int] = []
	for peer_id: int in recipients:
		if peer_id > 1:
			remote_recipients.append(peer_id)
	if remote_recipients.is_empty():
		return
	get_node("/root/NetworkSession").send_combat_event_to_peers(
		_round_id_for_actor(speaker),
		speaker.spawn_serial,
		"radio",
		{"sample": sample_id, "sender_name": speaker.display_name,
			"team": speaker.team, "text": message_text},
		remote_recipients,
	)


func _unhandled_input(event: InputEvent) -> void:
	if _network_client_mode:
		if is_instance_valid(network_client_view):
			network_client_view.handle_input(event)
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	# Options > Keyboard rebinds: a bound key reads as its command's default.
	var key := KeyBindings.canonical_keycode(key_event, get_node("/root/GameSettings").bindings())
	if key == KEY_TAB:
		if key_event.pressed and not key_event.echo:
			_update_scoreboard()
		hud.set_scoreboard_held(key_event.pressed)
		get_viewport().set_input_as_handled()
		return
	if (
		key_event.pressed
		and not key_event.echo
		and key in [KEY_Y, KEY_U]
		and match_started
		and not _pause_menu_open()
		and hud.current_input_contract().state in ["none", "scoreboard"]
	):
		_close_radio_menu()
		hud.set_scoreboard_held(false)
		hud.open_chat(key == KEY_U)
		get_viewport().set_input_as_handled()
		return
	if (
		key_event.pressed
		and not key_event.echo
		and _match_concluded
		and not _pause_menu_open()
		and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	):
		_restart_match()
		get_viewport().set_input_as_handled()
		return
	if key_event.pressed and not key_event.echo and _handle_radio_key(key):
		get_viewport().set_input_as_handled()
		return
	if key_event.pressed and not key_event.echo and key == KEY_M and match_started and not _pause_menu_open():
		_close_radio_menu()
		hud.set_buy_menu_visible(false)
		hud.set_deploy_visible(true)
		if bool(round_state.players.player.choosing_appearance):
			hud.show_class_menu(2 if player.team == "CT" else 1)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ESCAPE, KEY_0] and match_started and hud.current_input_contract().state == "team":
		_close_deploy_menu()
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
		_set_paused(not _pause_menu_open())
	elif _pause_menu_open():
		return
	elif key_event.pressed and not key_event.echo and key == KEY_T:
		if not _spray_for_human(player):
			hud.show_banner("SPRAY: MOVE CLOSE TO A FLAT SURFACE • 10s COOLDOWN", Color("#ffca66"), 1.5)
		get_viewport().set_input_as_handled()
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
		and key == KEY_N
	):
		_toggle_nightvision()
	elif (
		key_event.pressed
		and not key_event.echo
		and key == KEY_B
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
	if _network_client_mode:
		network_client_view.buy_item(item_id)
		return
	var result := _purchase_and_grant(item_id)
	if not bool(result.allowed):
		_show_buy_rejection(str(result.reason))
		return
	hud.show_banner("PURCHASED", Color("#77e3ae"), 0.65)


func _purchase_and_grant(item_id: String) -> Dictionary:
	var result := _purchase_for_human(player, item_id)
	if bool(result.allowed):
		money = int(result.balance)
		hud.update_health(player.health, player.armor, player.has_helmet)
		hud.update_ammo(player.clip, player.reserve, player.reloading)
		hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
		hud.update_buy_account(money, _buy_menu_context())
		hud.update_defuse_kit(player.team, player.alive, bool(player.equipment.get("defuser", false)))
		hud.complete_buy_purchase()
	return result


func _purchase_for_human(human: PlayerController, item_id: String) -> Dictionary:
	if _network_client_mode or not match_started or _match_concluded or not human.alive:
		return {"allowed": false, "reason": "action_unavailable"}
	var actor_id := _round_id_for_actor(human)
	var requested_item := item_id.to_lower().strip_edges()
	var source_item := str(BUY_ITEM_ALIASES.get(requested_item, requested_item))
	if not BUY_GRANTS.has(source_item):
		return {"allowed": false, "reason": "item_unavailable"}
	var grant_id := _resolve_buy_grant(str(BUY_GRANTS[source_item]), human)
	if grant_id.is_empty():
		return {"allowed": false, "reason": "item_unavailable"}
	var price := _resolve_buy_price(source_item, grant_id)
	if price < 0:
		return {"allowed": false, "reason": "item_unavailable"}
	var inside_zone := _is_in_team_buy_zone(
		human.global_position,
		human.team,
		_human_hull_size(human),
	)
	var map_has_zones := not buy_regions.is_empty()
	var eligibility: Dictionary = round_state.can_buy(
		actor_id,
		inside_zone,
		map_has_zones,
	)
	if not bool(eligibility.allowed):
		return eligibility
	if not _team_may_buy(source_item, human):
		return {"allowed": false, "reason": "wrong_team"}
	if int(round_state.players[actor_id].money) < price:
		return {"allowed": false, "reason": "insufficient_funds"}

	# The inventory mutation deliberately precedes the authoritative debit.
	# Player.grant_item owns slot replacement, grenade carry limits, equipment
	# flags, and ammo caps. An unavailable or already-full grant never charges.
	human._store_active_ammunition()
	var inventory_before := _player_inventory_snapshot(human)
	if not human.grant_item(grant_id):
		return {"allowed": false, "reason": "item_unavailable"}
	if _player_inventory_snapshot(human) == inventory_before:
		return {"allowed": false, "reason": "already_owned_or_full"}
	var result: Dictionary = round_state.purchase_item(
		actor_id,
		source_item,
		price,
		inside_zone,
		map_has_zones,
	)
	if not bool(result.allowed):
		_restore_player_inventory(inventory_before, human)
		return result

	if source_item == "defuser":
		round_state.set_defuser(actor_id, true)
	if _should_equip_purchase(human, grant_id):
		human.switch_weapon(grant_id)
	if human.ammunition.has(human.active_weapon):
		human.clip = int(human.ammunition[human.active_weapon].clip)
		human.reserve = int(human.ammunition[human.active_weapon].reserve)
	# CS 1.6 BuyGunAmmo emits items/9mmclip1.wav from the buyer's weapon after
	# the ammo grant succeeds. The actor-owned event also follows the existing
	# host-to-client audio path, so clients never predict or double-play it.
	if grant_id.begins_with("ammo_"):
		human._emit_audio("buy.ammo", AudioRouterScript.CHAN_ITEM)
	elif grant_id in ["kevlar", "helmet", "assaultsuit"]:
		# Both original armor item classes use items/ammopickup2.wav on CHAN_ITEM.
		# Emit only after the authoritative grant and debit have succeeded, so
		# rejected/full purchases and client retries cannot produce false cues.
		human._emit_audio("buy.armor", AudioRouterScript.CHAN_ITEM)
	elif grant_id == "defuser":
		human._emit_audio("buy.defuser", AudioRouterScript.CHAN_ITEM)
	elif grant_id == "nvgs":
		human._emit_audio("buy.nvgs", AudioRouterScript.CHAN_ITEM)
	elif WeaponRegistryScript.WEAPONS.has(grant_id):
		human._emit_audio("weapon.acquire", AudioRouterScript.CHAN_ITEM)
	return {
		"allowed": true,
		"reason": "ok",
		"balance": int(result.balance),
		"item": source_item,
		"grant": grant_id,
		"price": price,
	}


func _should_equip_purchase(human: PlayerController, weapon: String) -> bool:
	if not WeaponRegistryScript.WEAPONS.has(weapon):
		return false # Ammo and equipment never change the held weapon.
	var slot := int(WeaponRegistryScript.WEAPONS[weapon].slot)
	if slot not in [1, 2]:
		return false
	if not human.owns_weapon(human.active_weapon):
		return true # The new firearm replaced the gun in hand.
	var held_slot := int(WeaponRegistryScript.WEAPONS[human.active_weapon].slot)
	return held_slot not in [1, 2] or slot < held_slot


func _resolve_buy_grant(grant_id: String, human: PlayerController = null) -> String:
	if grant_id == "primary_ammo":
		return _owned_slot_ammo_grant(1, human)
	if grant_id == "secondary_ammo":
		return _owned_slot_ammo_grant(2, human)
	return grant_id


func _owned_slot_ammo_grant(slot: int, human: PlayerController = null) -> String:
	if human == null:
		human = player
	for weapon_name: String in human.owned_weapons:
		if (
			bool(human.owned_weapons[weapon_name])
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


func _team_may_buy(source_item: String, human: PlayerController = null) -> bool:
	if human == null:
		human = player
	if source_item in ["primary_ammo", "secondary_ammo"] or source_item.begins_with("ammo_"):
		return true
	var team_id := (
		RoundStateScript.TEAM_CT
		if human.team == Combatant.TEAM_COUNTER_TERRORIST
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


func _player_inventory_snapshot(human: PlayerController = null) -> Dictionary:
	if human == null:
		human = player
	return {
		"owned_weapons": human.owned_weapons.duplicate(true),
		"ammunition": human.ammunition.duplicate(true),
		"equipment": human.equipment.duplicate(true),
		"weapon_modes": human.weapon_modes.duplicate(true),
		"armor": human.armor,
		"has_helmet": human.has_helmet,
		"active_weapon": human.active_weapon,
		"clip": human.clip,
		"reserve": human.reserve,
	}


func _restore_player_inventory(snapshot: Dictionary, human: PlayerController = null) -> void:
	if human == null:
		human = player
	human.owned_weapons = snapshot.owned_weapons.duplicate(true)
	human.ammunition = snapshot.ammunition.duplicate(true)
	human.equipment = snapshot.equipment.duplicate(true)
	human.weapon_modes = snapshot.weapon_modes.duplicate(true)
	human.armor = int(snapshot.armor)
	human.has_helmet = bool(snapshot.has_helmet)
	human.active_weapon = str(snapshot.active_weapon)
	human.clip = int(snapshot.clip)
	human.reserve = int(snapshot.reserve)


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
	return _human_buy_eligibility(player)


func _human_buy_eligibility(human: PlayerController) -> Dictionary:
	if _network_client_mode or not match_started or _match_concluded or not human.alive:
		return {"allowed": false, "reason": "action_unavailable"}
	return round_state.can_buy(
		_round_id_for_actor(human),
		_is_in_team_buy_zone(
			human.global_position,
			human.team,
			_human_hull_size(human),
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
	return _human_hull_size(player)


func _human_hull_size(human: PlayerController) -> Vector3:
	if (
		is_instance_valid(human)
		and is_instance_valid(human.collider)
		and human.collider.shape is BoxShape3D
	):
		return (human.collider.shape as BoxShape3D).size
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


## GoldSrc 6-face skybox shader. Face selection and per-face texcoords follow
## the engine's R_DrawSkyBox/st_to_vec tables (rt=+X, lf=-X, bk=+Y north,
## ft=-Y, up=+Z, dn=-Z in GoldSrc axes), converted to Godot's Y-up basis.
const SKYBOX_SHADER_SOURCE := """
shader_type sky;
uniform sampler2D face_rt : source_color, filter_linear, repeat_disable;
uniform sampler2D face_lf : source_color, filter_linear, repeat_disable;
uniform sampler2D face_bk : source_color, filter_linear, repeat_disable;
uniform sampler2D face_ft : source_color, filter_linear, repeat_disable;
uniform sampler2D face_up : source_color, filter_linear, repeat_disable;
uniform sampler2D face_dn : source_color, filter_linear, repeat_disable;

vec2 face_uv(float s, float t) {
	vec2 uv = vec2((s + 1.0) * 0.5, 1.0 - (t + 1.0) * 0.5);
	return clamp(uv, vec2(0.5 / 256.0), vec2(1.0 - 0.5 / 256.0));
}

void sky() {
	// GoldSrc axes: x east, y north, z up.
	vec3 g = vec3(EYEDIR.x, -EYEDIR.z, EYEDIR.y);
	vec3 a = abs(g);
	vec3 sample_color;
	if (a.z >= a.x && a.z >= a.y) {
		if (g.z > 0.0) {
			sample_color = texture(face_up, face_uv(-g.y / a.z, -g.x / a.z)).rgb;
		} else {
			sample_color = texture(face_dn, face_uv(-g.y / a.z, g.x / a.z)).rgb;
		}
	} else if (a.x >= a.y) {
		if (g.x > 0.0) {
			sample_color = texture(face_rt, face_uv(-g.y / a.x, g.z / a.x)).rgb;
		} else {
			sample_color = texture(face_lf, face_uv(g.y / a.x, g.z / a.x)).rgb;
		}
	} else {
		if (g.y > 0.0) {
			sample_color = texture(face_bk, face_uv(g.x / a.y, g.z / a.y)).rgb;
		} else {
			sample_color = texture(face_ft, face_uv(-g.x / a.y, g.z / a.y)).rgb;
		}
	}
	// GoldSrc pushes sky faces through the same texgamma 2.0 / gamma 2.5 ramp
	// as every other texture (~pow 0.8 screen lift), and its 8-bit palette +
	// low-precision ramp further mutes chroma: the raw des TGAs' vivid
	// photographic blues and mountain greens display as the pale, hazy,
	// washed-out sky veterans remember. Rendering the raw texels reads as a
	// modern photo backdrop, so reproduce the ramp plus a mild chroma pull.
	vec3 washed = pow(sample_color, vec3(0.75));
	float sky_luma = dot(washed, vec3(0.299, 0.587, 0.114));
	COLOR = mix(washed, vec3(sky_luma), 0.14);
}
"""


func _sky_face_texture(sky_root: String, face: String) -> Texture2D:
	var path := "%s/%s.tga" % [sky_root, face]
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as Texture2D
	return null


func _worldspawn_skyname() -> String:
	if is_instance_valid(imported_map):
		for raw_entity: Variant in imported_map.entities:
			if raw_entity is Dictionary and str(raw_entity.get("classname", "")) == "worldspawn":
				var skyname := str(_ordered_entity_properties(raw_entity).get("skyname", ""))
				if skyname.is_valid_filename() and not skyname.is_empty():
					return skyname
	return "des"


func _build_goldsrc_sky() -> Sky:
	## Real CS 1.6 skybox faces (cstrike/gfx/env) named by the map's worldspawn
	## "skyname". Falls back to the dust2 "des" set for maps whose sky faces are
	## not converted yet.
	var sky_sources := [
		["res://generated/%s/sky" % map_name, _worldspawn_skyname()],
		["res://generated/de_dust2/sky", "des"],
	]
	for source: Array in sky_sources:
		var sky_root: String = source[0]
		var faces := {}
		var complete := true
		for face in ["rt", "lf", "bk", "ft", "up", "dn"]:
			var texture := _sky_face_texture(sky_root, "%s%s" % [source[1], face])
			if texture == null:
				complete = false
				break
			faces[face] = texture
		if not complete:
			continue
		var shader := Shader.new()
		shader.code = SKYBOX_SHADER_SOURCE
		var sky_material := ShaderMaterial.new()
		sky_material.shader = shader
		for face in faces:
			sky_material.set_shader_parameter("face_%s" % face, faces[face])
		var sky := Sky.new()
		sky.sky_material = sky_material
		sky.radiance_size = Sky.RADIANCE_SIZE_64
		return sky
	return null


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment := Environment.new()
	# Authentic GoldSrc presentation: real six-sided skybox, no distance fog,
	# and no tonemap curve — 1.6 outputs raw gamma-space color, which is where
	# dust2's punchy saturated sand look comes from.
	var sky := _build_goldsrc_sky()
	if sky != null:
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
	else:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("#97a5b8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c8d0ce")
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = false
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
	# GoldSrc dust2 has no distance fog at any preset; keep it permanently off.
	if is_instance_valid(world_environment):
		world_environment.environment.fog_enabled = false
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


func _spray_for_human(human: PlayerController) -> bool:
	if _network_client_mode or not match_started or _match_concluded or not is_instance_valid(human):
		return false
	if not sprays.try_place(human, Time.get_ticks_msec()):
		return false
	_emit_world_audio("player.spray", 0, sprays.records.back().position)
	return true


func _apply_player_name() -> void:
	if is_instance_valid(player) and player.display_name != get_node("/root/GameSettings").player_name:
		player.display_name = get_node("/root/GameSettings").player_name
		if is_instance_valid(hud) and not _network_client_mode:
			_update_scoreboard()


func _spawn_player() -> void:
	player = PlayerScript.new()
	player.name = "Player"
	player.configure_identity(
		Combatant.TEAM_UNASSIGNED if _dedicated_server_mode else Combatant.TEAM_TERRORIST,
		"Dedicated Server" if _dedicated_server_mode else get_node("/root/GameSettings").player_name,
	)
	player.position = player_spawn
	add_child(player)
	if _dedicated_server_mode:
		# Player's local-human _ready() supplies the normal offline T default.
		# Override it after tree entry so the server never occupies a team slot.
		player.configure_identity(Combatant.TEAM_UNASSIGNED, "Dedicated Server")
		player.alive = false
		player.visible = false
		player.collision_layer = 0
		player.controls_enabled = false
		player.look_enabled = false
		player.set_physics_process(false)
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
	bot.configure_weapon(
		"usp"
		if bot_team == Combatant.TEAM_COUNTER_TERRORIST
		else "glock18"
	)
	bot.died.connect(_on_target_died)
	if is_instance_valid(bot.combat_controller) and bot.combat_controller.has_method("set_perception_predicates"):
		bot.combat_controller.set_perception_predicates(
			Callable(self, "_perception_flash_blind"), Callable(),
		)
	return bot


func _perception_flash_blind(actor: Combatant, _tick: int) -> bool:
	return is_instance_valid(actor) and actor.is_flash_blinded()


func _all_bots() -> Array[TargetActor]:
	var bots: Array[TargetActor] = []
	bots.append_array(allied_bots)
	bots.append_array(targets)
	return bots


func _build_round_state() -> void:
	round_state = RoundStateScript.new()
	# Competitive CS 1.6 defaults: mp_maxrounds 30 with a side switch at 15 and
	# mp_winlimit 16, i.e. MR15 first-to-16.
	round_state.configure({
		"scenario": scenario,
		"max_rounds": MATCH_MAX_ROUNDS,
		"win_limit": MATCH_WIN_LIMIT,
		"halftime": true,
	})
	round_state.register_player(
		"player",
		player.team,
		RoundStateScript.START_MONEY,
		false,
	)
	for bot in allied_bots:
		round_state.register_player(bot.name, bot.team)
	for bot in targets:
		round_state.register_player(bot.name, bot.team)
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			round_state.register_player(actor_id, human.team)
			if human.has_meta("network_spawn_slot") and int(human.get_meta("cs16_class_id", 0)) == 0:
				round_state.players[actor_id].choosing_appearance = true
				round_state.players[actor_id].alive = false
	bomb_knowledge = BombKnowledgeScript.new()
	_refresh_bomb_knowledge_roster()


func _refresh_bomb_knowledge_roster() -> void:
	if not is_instance_valid(bomb_knowledge):
		return
	bomb_knowledge.register_actor("player", _knowledge_team(player.team))
	for bot in _all_bots():
		bomb_knowledge.register_actor(bot.name, _knowledge_team(bot.team))
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			bomb_knowledge.register_actor(actor_id, _knowledge_team(remote_roster.actor_for_id(actor_id).team))


func _knowledge_team(team: String) -> String:
	return team


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
	hud.update_deploy_briefing(map_name)
	hud.deploy_requested.connect(_on_deploy_requested)
	hud.paused_input_received.connect(_unhandled_input)
	hud.deploy_cancel_requested.connect(_on_deploy_cancel_requested)
	hud.voice_test_requested.connect(func() -> void:
		# Online browser clients answer this themselves (network_client_view).
		if not _network_client_mode:
			hud.show_banner("VOICE IS AVAILABLE IN BROWSER MULTIPLAYER", Color("#ffca66"), 2.0)
	)
	hud.input_contract_changed.connect(func(state: String, _keyboard: bool, mouse_visible: bool) -> void:
		if player.combat_controller is HumanCombatController:
			player.combat_controller.set_menu_input_blocked(state == "chat" or mouse_visible or _pause_menu_open())
		if state in ["buy_category", "buy_item"]:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif state == "none" and match_started and player.alive and not _pause_menu_open() and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	hud.resume_requested.connect(func() -> void: _set_paused(false))
	hud.quit_requested.connect(_on_quit_requested)
	hud.disconnect_requested.connect(_on_disconnect_requested)
	hud.network_connection_requested.connect(_on_network_connection_requested)
	hud.buy_item_requested.connect(_on_buy_item_requested)
	hud.team_selected.connect(_on_team_selected)
	hud.class_selected.connect(_on_class_selected)
	hud.chat_submitted.connect(_on_chat_submitted)
	player.health_changed.connect(_on_player_health_changed)
	player.ammo_changed.connect(_on_player_ammo_changed)
	player.weapon_changed.connect(func(weapon_name: String, fire_mode: String) -> void:
		hud.update_weapon(weapon_name, fire_mode)
	)
	player.hit_confirmed.connect(func(headshot: bool) -> void: hud.show_hitmarker(headshot))
	player.flash_blinded.connect(func(seconds: float) -> void: hud.show_flash_blind(seconds))
	player.combatant_eliminated.connect(_on_human_eliminated)
	player.weapon_drop_requested.connect(_on_player_weapon_drop)
	player.c4_drop_requested.connect(_request_drop_active_weapon)
	hud.update_health(player.health, player.armor, player.has_helmet)
	hud.update_weapon(PlayerController.WEAPONS[player.active_weapon].name, PlayerController.WEAPONS[player.active_weapon].mode)
	hud.update_ammo(player.clip, player.reserve, player.reloading)
	_update_scoreboard()


func _on_team_selected(team_id: int) -> void:
	if _network_client_mode:
		network_client_view.select_team(team_id)
		return
	if team_id not in [1, 2, 5, 6] or _match_concluded:
		hud.reject_deploy_selection()
		return
	if team_id == 6:
		if not round_state.can_enter_observer("player"):
			hud.reject_deploy_selection()
			hud.show_banner("CANNOT SPECTATE WHILE ALIVE", Color("#ffca66"), 2.0)
			return
		if match_started and phase == RoundStateScript.PHASE_FREEZE and player.alive:
			# Use the existing death/drop path; no opponent receives kill credit.
			player.receive_damage(100000.0, player.global_position)
		round_state.enter_observer("player", player.global_position)
		player.configure_identity(Combatant.TEAM_UNASSIGNED, player.display_name)
		_consume_new_round_trace()
		_sync_round_public_state()
		bomb_knowledge.register_actor("player", Combatant.TEAM_UNASSIGNED)
		_enter_observer_view()
		_update_scoreboard()
		if not match_started and not _match_concluded:
			start_match()
		return
	if team_id == 5:
		var automatic: String = round_state.default_join_team(_team_spawn_capacities(), "T" if randi() % 2 == 0 else "CT")
		if automatic.is_empty():
			hud.reject_deploy_selection()
			hud.show_banner("BOTH TEAMS ARE FULL", Color("#ffca66"), 2.0)
			return
		team_id = 1 if automatic == "T" else 2
	var selected_team := (
		Combatant.TEAM_COUNTER_TERRORIST
		if team_id == 2
		else Combatant.TEAM_TERRORIST
	)
	if match_started:
		var result: Dictionary = round_state.select_player_team("player", selected_team, _team_spawn_capacities(), player.global_position)
		if not result.accepted:
			hud.reject_deploy_selection()
			hud.show_banner(str(result.reason).replace("_", " ").to_upper(), Color("#ffca66"), 2.0)
			return
		if result.selection_death:
			# Kernel death/drop is idempotent; actor death adds physical weapon
			# drops and camera presentation without a second recorded death.
			player.receive_damage(100000.0, player.global_position)
		player.configure_identity(selected_team, player.display_name)
		_consume_new_round_trace()
		_sync_round_public_state()
		_refresh_roster_spawns()
		_refresh_bomb_knowledge_roster()
		_enter_waiting_participant_view()
		player.set_meta("cs16_team_id", team_id)
		hud.accept_authoritative_deploy_selection(team_id, 0)
		_update_scoreboard()
		return
	player.configure_identity(selected_team, player.display_name)
	_end_death_spectate()
	player.visible = true
	player.collision_layer = _local_player_collision_layer()
	_apply_spawn_side(selected_team)
	_apply_bot_sides(selected_team)
	if round_state.players.has("player"):
		var state_player: Dictionary = round_state.players.player
		state_player.team = selected_team
		state_player.alive = true
		round_state.players.player = state_player
	player.reset_player(player_spawn, false)
	player.controls_enabled = false
	selected_player_skin = _class_skin(selected_team, selected_class_id)
	player.set_meta("cs16_team_id", 2 if selected_team == Combatant.TEAM_COUNTER_TERRORIST else 1)
	player.set_meta("cs16_player_skin", selected_player_skin)
	hud.accept_authoritative_deploy_selection(team_id, 0)
	_update_scoreboard()


func _team_spawn_capacities() -> Dictionary:
	if _local_player_collision_layer() == (2 | 4):
		return {"T": mini(5, terrorist_team_spawns.size()), "CT": mini(5, counter_terrorist_team_spawns.size())}
	return {"T": terrorist_team_spawns.size(), "CT": counter_terrorist_team_spawns.size()}


func _refresh_roster_spawns() -> void:
	# Remote admissions inherit the replaced bot's reserved map slot. Do not
	# shift living bots onto each other when the new human finishes appearance.
	var indices := {"T": 0, "CT": 0}
	var reserved := {"T": {}, "CT": {}}
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if human.team in ["T", "CT"] and human.has_meta("network_spawn_slot"):
				reserved[human.team][int(human.get_meta("network_spawn_slot"))] = true
	if player.team in ["T", "CT"]:
		var local_spawns: Array = counter_terrorist_team_spawns if player.team == "CT" else terrorist_team_spawns
		while reserved[player.team].has(indices[player.team]):
			indices[player.team] += 1
		player_spawn = local_spawns[indices[player.team]]
		indices[player.team] += 1
	allied_spawns.clear()
	target_spawns.clear()
	for bot in _all_bots():
		var spawns: Array = counter_terrorist_team_spawns if bot.team == "CT" else terrorist_team_spawns
		while reserved[bot.team].has(indices[bot.team]):
			indices[bot.team] += 1
		var index: int = indices[bot.team]
		assert(index < spawns.size(), "Accepted roster exceeds map spawn capacity")
		if allied_bots.has(bot):
			allied_spawns.append(spawns[index])
		else:
			target_spawns.append(spawns[index])
		indices[bot.team] += 1


func _enter_waiting_participant_view() -> void:
	_end_trigger_camera()
	player.alive = false
	player.controls_enabled = false
	player.look_enabled = false
	player.velocity = Vector3.ZERO
	player.last_command = {}
	player.collision_layer = 0
	player.visible = false
	if is_instance_valid(spectator_camera):
		spectator_camera.stop()
		spectator_camera.schedule(0.0)


func _on_deploy_cancel_requested() -> void:
	if _network_client_mode:
		# A joined player opened the team menu with M: cancel just closes it.
		if match_started and player.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
			_close_deploy_menu()
		else:
			_set_paused(true)
		return
	if match_started:
		_close_deploy_menu()
	else:
		_set_paused(true)


func _close_deploy_menu() -> void:
	hud.set_deploy_visible(false)
	if not _dedicated_server_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_deploy_requested() -> void:
	if _network_client_mode:
		return
	if _match_concluded:
		return
	if match_started:
		_close_deploy_menu()
		return
	start_match()


func _enter_observer_view() -> void:
	# Spectator is an unoccupied combat slot, not a living invisible player.
	# Initial menu selection does not synthesize a combat death.
	_end_trigger_camera()
	_close_radio_menu()
	_set_nightvision(false)
	hud.clear_combat_feedback()
	player.alive = false
	player.controls_enabled = false
	player.look_enabled = false
	player.velocity = Vector3.ZERO
	player.last_command = {}
	player.collision_layer = 0
	player.visible = false
	player.set_meta("cs16_team_id", 0)
	player.set_objective_movement_locked(false)
	if is_instance_valid(spectator_camera):
		spectator_camera.stop()
		spectator_camera.schedule(0.0)


func _on_class_selected(class_id: int) -> void:
	if _network_client_mode:
		network_client_view.select_class(class_id)
		return
	if class_id not in [1, 2, 3, 4] or player.team not in ["T", "CT"]:
		return
	selected_class_id = clampi(class_id, 1, 4)
	selected_player_skin = _class_skin(player.team, selected_class_id)
	player.set_meta("cs16_class_id", selected_class_id)
	player.set_meta("cs16_player_skin", selected_player_skin)
	if match_started:
		if round_state.finish_player_appearance("player"):
			_end_death_spectate()
			player.visible = true
			player.collision_layer = _local_player_collision_layer()
			player.reset_player(player_spawn, false)
			player.look_enabled = true
			player.controls_enabled = phase in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB]
			player.camera.make_current()
		_sync_round_public_state()
		_update_scoreboard()


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


func _apply_halftime_side_switch() -> void:
	hud.reset_money_presentation()
	# CS16RoundState has already swapped its own roster; mirror the new sides onto
	# the live actors, spawn assignments and skins before the next round starts.
	_round_loadout_reset_pending = true
	var switched_team := str(round_state.players.player.team)
	player.configure_identity(switched_team, player.display_name)
	for bot in _all_bots():
		_set_bot_team(bot, str(round_state.players[bot.name].team))
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if human.has_meta("network_spawn_slot"):
				human.configure_identity(str(round_state.players[actor_id].team), human.display_name)
				human.set_meta("cs16_player_skin", _class_skin(human.team, int(human.get_meta("cs16_class_id", 1))))
	_refresh_roster_spawns()
	_refresh_bomb_knowledge_roster()
	selected_player_skin = _class_skin(switched_team, selected_class_id)
	player.set_meta(
		"cs16_team_id",
		(2 if switched_team == Combatant.TEAM_COUNTER_TERRORIST else 1) if switched_team in ["T", "CT"] else 0,
	)
	player.set_meta("cs16_player_skin", selected_player_skin)
	if bool(round_state.players.player.choosing_appearance):
		hud.accept_authoritative_deploy_selection(2 if switched_team == "CT" else 1, 0)
	_update_scoreboard()


func _set_bot_team(bot: TargetActor, team: String) -> void:
	bot.configure_identity(team, bot.display_name)
	if round_state.players.has(bot.name):
		var state_bot: Dictionary = round_state.players[bot.name]
		state_bot.team = team
		round_state.players[bot.name] = state_bot
	if is_instance_valid(bot.character_model):
		bot.player_skin = bot._skin_for_identity()
		bot.character_model.load_character(bot.player_skin, "ak47")


func _on_quit_requested() -> void:
	# Menu signals still run while the world is paused. Close the transport
	# explicitly so connected peers are released before the scene shuts down.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_node("/root/NetworkSession").disconnect_session()
	get_tree().quit()


func _on_network_connection_requested(action: String, address: String, port_text: String) -> void:
	var network := get_node("/root/NetworkSession")
	if _returning_offline or action not in ["host", "join"]:
		return
	var reason := ""
	if network.is_online() or network.is_connecting():
		reason = "Already online. Return Offline before changing sessions."
	elif action == "host" and _network_client_mode:
		reason = "Return Offline before hosting."
	var endpoint: Dictionary = network.connection_endpoint("127.0.0.1" if action == "host" else address, port_text)
	if reason.is_empty() and not endpoint.valid:
		reason = endpoint.reason
	if not reason.is_empty():
		hud.update_network_status(reason, network.is_online() or network.is_connecting(), _network_client_mode)
		return
	if action == "host":
		network.host_game(int(endpoint.port))
	else:
		_network_menu_join_pending = true
		_network_menu_deadline_ms = Time.get_ticks_msec() + 15000
		hud.set_deploy_visible(true)
		hud.show_network_menu("join")
		if network.join_game(str(endpoint.address), int(endpoint.port)) != OK:
			_network_menu_join_pending = false


func _on_client_world_ready(map: String) -> void:
	if not _network_menu_join_pending:
		return
	_network_menu_join_pending = false
	if map != map_name:
		if follow_host_map(map):
			return
		var network := get_node("/root/NetworkSession")
		network.disconnect_session()
		network._set_status("HOST MAP %s IS NOT AVAILABLE" % map.to_upper())
		return
	if hud.network_menu.is_visible_in_tree():
		_set_paused(false)
		hud.set_deploy_visible(true)


func _on_disconnect_requested() -> void:
	if _returning_offline:
		return
	_returning_offline = true
	_network_menu_join_pending = false
	get_node("/root/NetworkSession").disconnect_session()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# A fresh scene restores offline AI, collision and ownership together;
	# never partially turn a read-only client pawn back into an authority.
	_return_to_offline.call_deferred()


func _return_to_offline() -> void:
	var error := get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		_returning_offline = false
		_set_paused(true)
		hud.update_network_status("Could not return offline: " + error_string(error), false, _network_client_mode)
		hud.show_network_menu("join")


func _pause_menu_open() -> bool:
	return is_instance_valid(hud) and is_instance_valid(hud.pause_overlay) and hud.pause_overlay.visible


## True while live play should hold the mouse captured: no pause menu and
## no HUD menu that needs a visible cursor.
func wants_mouse_capture() -> bool:
	return (match_started or _network_client_mode) and not _pause_menu_open() \
		and not hud.current_input_contract().mouse_visible


func _set_paused(paused: bool) -> void:
	# Online menus are local input overlays, not authority to stop the server
	# or client presentation. Offline games retain their normal full pause.
	get_tree().paused = paused and not get_node("/root/NetworkSession").is_online()
	if paused:
		_close_radio_menu()
	hud.set_paused_visible(paused)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused or hud.current_input_contract().mouse_visible else Input.MOUSE_MODE_CAPTURED


var _match_concluded := false


func _restart_match() -> void:
	if _network_client_mode:
		return
	## A concluded MR15 match restarts with fresh scores and accounts, but the
	## roster keeps its current sides (halftime may have swapped them).
	_match_concluded = false
	match_started = false
	round_ending = false
	_round_loadout_reset_pending = true
	_build_round_state()
	if is_instance_valid(player) and round_state.players.has("player"):
		var player_row: Dictionary = round_state.players.player
		player_row.team = player.team
		round_state.players.player = player_row
	_consume_new_round_trace()
	_sync_round_public_state()
	hud.reset_match_presentation()
	if is_instance_valid(_radio_voice):
		_radio_voice.stop()
	start_match()


func start_match() -> void:
	if _network_client_mode:
		return
	if match_started or round_ending or _match_concluded:
		return
	if is_instance_valid(combat_effects) and not combat_effects.presentation_is_ready:
		if not combat_effects.presentation_ready.is_connected(start_match):
			combat_effects.presentation_ready.connect(start_match, CONNECT_ONE_SHOT)
		return
	match_started = true
	if is_instance_valid(deploy_camera):
		deploy_camera.queue_free()
		deploy_camera = null
		if is_instance_valid(player) and is_instance_valid(player.camera):
			player.camera.make_current()
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
	_emit_kill_notice(target.last_damage_attacker, target, headshot)
	# Bots track a single carried gun; a knife/grenade holder has nothing else
	# recorded, so only a gun in hand hits the floor (with its live clip).
	_spawn_weapon_drop(
		target.active_weapon_name,
		target.weapon_clip,
		target.weapon_reserve,
		target.global_position,
		Vector3.ZERO,
	)
	if target.team == Combatant.TEAM_COUNTER_TERRORIST:
		kills += 1
		hud.show_banner(
			"HOSTILE DOWN%s" % ("  •  HEADSHOT" if headshot else ""),
			Color("#ffca66"),
			0.7,
		)
	_update_round_hud(true)
	# The Tab scoreboard marks the dead live, so it has to be rebuilt on the
	# elimination itself, not only on the next round event.
	_update_scoreboard()


func _on_player_health_changed(health: int, armor: int) -> void:
	if is_instance_valid(hud):
		var took_damage := health < int(hud.health_label.text) if hud.health_label.text.is_valid_int() else false
		hud.update_health(health, armor, player.has_helmet)
		if took_damage:
			hud.show_damage()


func _on_player_ammo_changed(clip: int, reserve: int, reloading: bool) -> void:
	if is_instance_valid(hud):
		hud.update_ammo(clip, reserve, reloading)


func _combatant_display_name(actor: Combatant) -> String:
	var display: Variant = actor.get("display_name")
	if display is String and not str(display).is_empty():
		return str(display)
	return str(actor.name)


func _combatant_weapon_label(actor: Combatant) -> String:
	if actor is PlayerController:
		return str(actor.active_weapon)
	var weapon: Variant = actor.get("active_weapon_name")
	return str(weapon) if weapon is String else ""


func _emit_kill_notice(attacker: Combatant, victim: Combatant, headshot: bool) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(victim):
		return
	var has_killer := is_instance_valid(attacker) and attacker != victim
	# Grenades can kill after their owner has already switched back to a gun.
	var lethal_weapon := victim.last_damage_weapon
	if lethal_weapon.is_empty() and has_killer:
		lethal_weapon = _combatant_weapon_label(attacker)
	get_node("/root/NetworkSession").send_combat_event("", round_state.round_number, "kill", {
		"killer": _combatant_display_name(attacker) if has_killer else "",
		"killer_team": str(attacker.team) if has_killer else "",
		"weapon": lethal_weapon,
		"victim": _combatant_display_name(victim), "victim_team": str(victim.team), "headshot": headshot if has_killer else false})
	if is_instance_valid(attacker) and attacker != victim:
		hud.add_kill_notice(
			_combatant_display_name(attacker),
			str(attacker.team),
			lethal_weapon,
			_combatant_display_name(victim),
			str(victim.team),
			headshot,
		)
	else:
		hud.add_kill_notice(
			"", "", lethal_weapon, _combatant_display_name(victim), str(victim.team), false,
		)


func _on_player_died() -> void:
	_on_human_died(player)


func _on_human_eliminated(actor: Combatant, _attacker: Combatant, headshot: bool) -> void:
	if actor is PlayerController:
		_on_human_died(actor as PlayerController, headshot)


func _on_human_died(human: PlayerController, headshot := false) -> void:
	var actor_id := _round_id_for_actor(human)
	if human.alive or not is_instance_valid(round_state) or not round_state.players.has(actor_id):
		return
	if int(_human_death_serials.get(actor_id, -1)) == human.spawn_serial:
		return
	_human_death_serials[actor_id] = human.spawn_serial
	if human == player:
		_set_nightvision(false)
	else:
		human.collision_layer = 0
		_human_use_was_down.erase(actor_id)
		_end_remote_trigger_camera(actor_id, false)
	_emit_kill_notice(human.last_damage_attacker, human, headshot)
	var drop_weapon := human.death_drop_weapon()
	if not drop_weapon.is_empty():
		var drop_ammo: Dictionary = human.ammunition.get(drop_weapon, {})
		human.owned_weapons.erase(drop_weapon)
		human.ammunition.erase(drop_weapon)
		_spawn_weapon_drop(
			drop_weapon,
			int(drop_ammo.get("clip", 0)),
			int(drop_ammo.get("reserve", 0)),
			human.global_position,
			Vector3.ZERO,
			true,
			actor_id,
		)
	if is_instance_valid(round_state):
		round_state.set_player_alive(
			actor_id,
			false,
			human.global_position,
			_round_id_for_actor(human.last_damage_attacker)
			if is_instance_valid(human.last_damage_attacker)
			else "",
		)
		_consume_new_round_trace()
		_sync_round_public_state()
		_update_round_hud(true)
		_update_scoreboard()
	if human == player and is_instance_valid(spectator_camera):
		spectator_camera.schedule()


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


func _round_tick_command(world_use_selections: Dictionary = {}) -> Dictionary:
	var command := {}
	if phase == RoundStateScript.PHASE_LIVE:
		var carrier := _actor_for_round_id(str(round_state.bomb_owner))
		if not is_instance_valid(carrier):
			return command
		var site := _bomb_region_at(
			carrier.global_position,
			_human_hull_size(carrier as PlayerController)
			if carrier is PlayerController
			else TargetActor.STANDING_HULL_SIZE,
		)
		var is_human_carrier := carrier is PlayerController
		var human_carrier := carrier as PlayerController
		var bot_command: Dictionary = carrier.last_command
		var c4_is_equipped := (
			human_carrier.active_weapon == "c4"
			if is_human_carrier
			else bool((carrier as TargetActor).c4_equipped)
		)
		command.plant = {
			"player_id": _round_id_for_actor(carrier),
			"attack": (
				(
					_human_objective_pressed(human_carrier, "fire")
					and human_carrier.weapon_clock.can_primary_attack()
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
				_human_objective_grounded(human_carrier)
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
				_human_objective_pressed(active_defuser as PlayerController, "use")
				if active_defuser is PlayerController
				else true
			)
			command.defuse = _defuse_request(active_defuser, use_pressed, world_use_selections.get(_round_id_for_actor(active_defuser)))
		else:
			# The active defuser retains the use-refresh grace period. Without
			# one, an invalid human request must not starve another human/bot.
			for human: PlayerController in _human_players_stable():
				if human.team != Combatant.TEAM_COUNTER_TERRORIST or not _human_objective_pressed(human, "use"):
					continue
				var request := _defuse_request(human, true, world_use_selections.get(_round_id_for_actor(human)))
				if request.use and request.grounded and request.in_range and request.facing:
					command.defuse = request
					return command
			var bot_defuser := _active_bot_defuser()
			if is_instance_valid(bot_defuser):
				command.defuse = _defuse_request(bot_defuser, true)
	return command


func _player_objective_grounded() -> bool:
	return _human_objective_grounded(player)


func _human_players_stable() -> Array[PlayerController]:
	var humans: Array[PlayerController] = [player]
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			humans.append(remote_roster.actor_for_id(actor_id))
	return humans


func _human_objective_pressed(human: PlayerController, action: String) -> bool:
	if not human.alive or not human.controls_enabled:
		return false
	if human.is_local_human():
		if human.combat_controller is HumanCombatController and human.combat_controller.menu_input_blocked:
			return false
		return Input.is_action_pressed(action)
	return bool(human.last_command.get(action, false))


func _human_objective_grounded(human: PlayerController) -> bool:
	if human._movement_grounded:
		return true
	human._movement_grounded = human.movement_kernel.categorize_ground(
		human.velocity,
	)
	if not human._movement_grounded:
		# Objective eligibility uses the same 2-HU downward floor contract even
		# on the exact coplanar frame where Godot's simulated box sweep returns
		# no new collision.
		var query := PhysicsRayQueryParameters3D.create(
			human.global_position + Vector3.UP * GOLDSRC_UNIT,
			human.global_position - Vector3.UP * 3.0 * GOLDSRC_UNIT,
			1,
			[human.get_rid()],
		)
		query.collide_with_areas = false
		var hit := human.get_world_3d().direct_space_state.intersect_ray(query)
		human._movement_grounded = (
			not hit.is_empty()
			and Vector3(hit.get("normal", Vector3.ZERO)).dot(Vector3.UP) >= 0.7
		)
	return human._movement_grounded


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
	return _actor_for_round_id(str(round_state.defuse_actor))


func _defuse_request(actor: Combatant, use_pressed: bool, selected_use: Variant = null) -> Dictionary:
	var eye_position := actor.global_position + Vector3.UP * Combatant.STANDING_VIEW_HEIGHT
	var view_forward := -actor.global_transform.basis.z
	if actor is PlayerController and is_instance_valid(actor.camera):
		eye_position = actor.camera.global_position
		view_forward = -actor.camera.global_transform.basis.z
	# Share the frame's PlayerUse selection with world interaction. A button
	# handler/moving brush must not turn one press into a second C4 activation.
	var selected: Dictionary = selected_use if selected_use is Dictionary else PlayerUseResolverScript.select_candidate(
		actor.global_position, eye_position, view_forward, _world_use_candidates(actor, true),
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
		"grounded": _human_objective_grounded(actor as PlayerController) if actor is PlayerController else actor.is_on_floor(),
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
	if not is_instance_valid(actor):
		return ""
	if is_instance_valid(remote_roster):
		var remote_id: String = remote_roster.id_for_actor(actor)
		if not remote_id.is_empty():
			return remote_id
	return "player" if actor == player else actor.name


func _actor_for_round_id(actor_id: String) -> Combatant:
	if actor_id == "player":
		return player
	if is_instance_valid(remote_roster):
		var human: PlayerController = remote_roster.actor_for_id(actor_id)
		if is_instance_valid(human):
			return human
	for bot in _all_bots():
		if bot.name == actor_id:
			return bot
	return null


func _assigned_bomb_site(actor: TargetActor) -> Vector3:
	if bomb_sites.is_empty():
		return actor.global_position
	if not _bot_site_assignments.has(actor.name):
		# Keep one stable team plan for the round and exercise both authored
		# Dust2 sites. A nearest-site choice makes every round repeat the same
		# spawn-biased execute.
		_bot_site_assignments[actor.name] = posmod(
			int(round_state.round_number) - 1,
			bomb_sites.size(),
		)
	return bomb_sites[int(_bot_site_assignments[actor.name]) % bomb_sites.size()]


func _assigned_ct_defense_site(bot: TargetActor) -> Vector3:
	if bomb_sites.is_empty():
		return bot.global_position
	# Even-index bots own the static defense roles. Divide the role index before
	# modulo: bot.index % 2 assigned CT 0, 2, and 4 to the same Dust2 site.
	var defense_slot := floori(float(bot.index) / 2.0)
	return bomb_sites[defense_slot % bomb_sites.size()]


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
		or phase not in [
			RoundStateScript.PHASE_LIVE,
			RoundStateScript.PHASE_BOMB,
		]
	):
		return {}
	if (
		scenario == ScenarioRulesScript.SCENARIO_HOSTAGE
		and hostage_state != null
		and phase == RoundStateScript.PHASE_LIVE
	):
		return _hostage_bot_objective_context(bot)
	if bomb_sites.is_empty():
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
					search_site = bomb_sites[_bomb_search_site_index(bot)]
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
				# The team plan owns this selection for the whole round. Passing
				# both sites here caused the controller's nearest-path resolver
				# to silently override planned B executes.
				"site_candidates": [site],
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
		# Two non-carriers execute into distinct space around the team site while
		# the remaining pair hunt. This provides trade support without making
		# all five bots crowd a stationary human bomb carrier at spawn.
		if bot.index % 2 == 0:
			var team_site := (
				_assigned_bomb_site(carrier as TargetActor)
				if carrier is TargetActor
				else bomb_sites[
					posmod(int(round_state.round_number) - 1, bomb_sites.size())
				]
			)
			return {
				"state": "execute_site",
				"action": "support_site",
				"target": _objective_cover_position(team_site, bot),
				"look_target": team_site,
				"stop_radius": 0.42,
				"round_number": round_state.round_number,
			}
		return {}

	# Counter-Terrorists split into source-like roles: alternating bots guard
	# the two bombsites while their teammates patrol/hunt. Assigning all five
	# to static guard tasks can leave a spawn-adjacent guard with no route and
	# recreates the original stuck-player crowd.
	if bot.index % 2 == 1:
		return {}
	var defense_site := _assigned_ct_defense_site(bot)
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
				_objective_audio_schedule.clear()
				_network_objective_result = ""
				_human_use_was_down.clear()
				_remote_trigger_cameras.clear()
				# Ordinary rounds retain survivors' equipment; a halftime or new
				# match is a fresh pistol round, even for actors still alive.
				var carried_bot_loadouts := {} if _round_loadout_reset_pending else _capture_bot_loadouts()
				_end_trigger_camera()
				_end_death_spectate()
				if entity_world != null:
					entity_world.reset_round()
				if brush_runtime != null:
					brush_runtime.reset_round(false)
					_brush_touch_pairs.clear()
				if breakable_runtime != null:
					breakable_runtime.reset_round(false)
				if is_instance_valid(breakable_debris):
					breakable_debris.reset()
				if hostage_state != null:
					hostage_state.start_round()
					_hostage_bot_assignments.clear()
					_hostage_bot_rescue_targets.clear()
					_hostage_paths.clear()
					_hostage_path_indices.clear()
					_hostage_path_targets.clear()
					_sync_hostage_actors()
				if int(event.round) > 1 or _round_loadout_reset_pending:
					_reset_combatants_for_round(not _round_loadout_reset_pending)
				_round_loadout_reset_pending = false
				_apply_bot_round_buy(
					carried_bot_loadouts,
					int(event.round),
				)
				_c4_equipped = false
				_c4_drop_animation_played = false
				_bot_site_assignments.clear()
				_reset_bot_defuser_assignment()
				round_ending = false
				kills = 0
				if is_instance_valid(bomb_knowledge):
					bomb_knowledge.reset_round()
					bomb_knowledge.on_bomb_carried()
				# RoundState emits freeze before round_start. Respawn restores
				# actor defaults (including active=true), so enforce the event's
				# freeze controls after reset/buy, before any actor physics runs.
				# Do not read round_state.phase here: a batched event stream may
				# already have advanced beyond this round_start to a later phase.
				_apply_round_phase(RoundStateScript.PHASE_FREEZE)
				if player.team == Combatant.TEAM_UNASSIGNED:
					_enter_observer_view()
				elif bool(round_state.players.player.choosing_appearance):
					_enter_waiting_participant_view()
				_update_scoreboard()
			"bomb_dropped":
				_objective_audio_schedule.clear()
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
				_schedule_c4_arm_audio(str(event.player_id))
				_set_objective_actor_frozen(str(event.player_id), true, "plant")
				if str(event.player_id) == "player":
					player.viewmodel._start_animation("pressbutton", false)
			"plant_abort":
				_cancel_c4_arm_audio(str(event.player_id))
				_set_objective_actor_frozen(str(event.player_id), false, "plant")
				_c4_drop_animation_played = false
				if str(event.player_id) == "player" and player.active_weapon == "c4":
					player.viewmodel._start_animation("idle1", true)
			"defuse_start":
				_set_objective_actor_frozen(str(event.player_id), true, "defuse")
				_emit_world_audio("c4.disarm", AudioRouterScript.CHAN_ITEM, bomb_position)
			"defuse_abort":
				_set_objective_actor_frozen(str(event.player_id), false, "defuse")
			"bomb_planted":
				_objective_audio_schedule.clear()
				_network_objective_result = "bomb_planted"
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
				_network_objective_result = "bomb_defused"
				_bot_defuser_id = ""
				_set_objective_actor_frozen(str(event.player_id), false, "defuse")
				var defuser := _actor_for_round_id(str(event.player_id))
				_emit_world_audio("c4.disarmed", AudioRouterScript.CHAN_WEAPON,
					defuser.global_position if is_instance_valid(defuser) else bomb_position)
				hud.show_banner("THE BOMB HAS BEEN DEFUSED", Color("#77d9ff"), 2.0)
			"bomb_exploded":
				_objective_audio_schedule.clear()
				_network_objective_result = "bomb_exploded"
				_apply_c4_explosion(event)
			"money", "purchase":
				if str(event.player_id) == "player":
					money = int(event.balance)
			"round_end":
				_objective_audio_schedule.clear()
				player.set_objective_movement_locked(false)
				round_ending = true
				_emit_round_result(event)
				_update_scoreboard()
			"halftime":
				_apply_halftime_side_switch()
				hud.show_banner("HALFTIME  •  SWITCHING SIDES", Color("#ffca66"), 2.5)
			"match_end":
				_objective_audio_schedule.clear()
				_close_radio_menu()
				match_started = false
				_match_concluded = true
				player.controls_enabled = false
				player.look_enabled = false
				hud.show_banner(
					"MATCH OVER  •  CT %d  -  T %d"
					% [int(event.ct_score), int(event.terrorist_score)],
					Color("#ffca66"),
					4.0,
				)
				if _dedicated_server_mode:
					hud.update_objective("NEXT MAP: %s" % _next_rotation_map().to_upper())
					get_tree().create_timer(MAP_CHANGE_DELAY_SECONDS).timeout.connect(_change_to_next_map)
				else:
					hud.update_objective("PRESS ENTER FOR A NEW MATCH")


func _bomb_search_site_index(bot: TargetActor) -> int:
	## A CT bot that reaches its search site without finding the bomb moves on
	## to the next site, like CS bots, instead of standing on an empty site.
	var progress: Dictionary = _bomb_search_progress.get(bot.name, {})
	if int(progress.get("round", -1)) != round_state.round_number:
		progress = {"round": round_state.round_number, "searched": []}
		_bomb_search_progress[bot.name] = progress
	var searched: Array = progress.searched
	var count := bomb_sites.size()
	for step in count:
		var candidate := (bot.index + step) % count
		if searched.has(candidate):
			continue
		if bot.global_position.distance_to(bomb_sites[candidate]) > BOMB_SEARCH_REACHED_RADIUS:
			return candidate
		searched.append(candidate)
	# Every site checked: start over from the first.
	searched.clear()
	return bot.index % count


func _round_actor_positions() -> Dictionary:
	var result := {"player": player.global_position}
	for bot in _all_bots():
		result[bot.name] = bot.global_position
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			result[actor_id] = remote_roster.actor_for_id(actor_id).global_position
	return result


func _set_objective_actor_frozen(
	actor_id: String,
	frozen: bool,
	action := "",
) -> void:
	var human := _actor_for_round_id(actor_id) as PlayerController
	if is_instance_valid(human):
		human.set_objective_movement_locked(frozen, frozen)
		human.controls_enabled = (
			human.alive
			and not _remote_trigger_cameras.has(actor_id)
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
	player.post_round_movement_enabled = (next_phase == RoundStateScript.PHASE_POST and player.alive
		and player.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST])
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			var row: Dictionary = round_state.players.get(actor_id, {})
			var participating := (
				human.alive and bool(row.get("alive", false))
				and human.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]
				and not bool(row.get("choosing_appearance", true))
			)
			human.controls_enabled = participating and next_phase in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB]
			human.post_round_movement_enabled = participating and next_phase == RoundStateScript.PHASE_POST
			if _remote_trigger_cameras.has(actor_id):
				if next_phase in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB] and participating:
					human.controls_enabled = false
				else:
					_end_remote_trigger_camera(actor_id, false)
			human.look_enabled = participating
			if next_phase not in [RoundStateScript.PHASE_LIVE, RoundStateScript.PHASE_BOMB] or (
					str(round_state.plant_actor) != actor_id and str(round_state.defuse_actor) != actor_id):
				human.set_objective_movement_locked(false)
	match next_phase:
		RoundStateScript.PHASE_FREEZE:
			player.controls_enabled = false
			player.look_enabled = player.alive
			_set_nightvision(false)
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
			player.look_enabled = player.alive
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
	if force or displayed_second != _last_hud_second or money != _last_hud_money:
		_last_hud_second = displayed_second
		_last_hud_money = money
		hud.update_match(
			round_number,
			phase,
			seconds_left,
			ct_score,
			terrorist_score,
			money,
		)
	var action: Dictionary = round_state.action_progress()
	var local_defuse := (
		not action.is_empty()
		and str(action.action) == "defuse"
		and str(action.actor) == "player"
		and player.team == "CT"
		and player.alive
	)
	hud.update_defuse_progress(
		local_defuse,
		float(action.get("elapsed_ticks", 0)),
		float(action.get("duration_ticks", 0)),
	)
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
		if scenario == ScenarioRulesScript.SCENARIO_HOSTAGE and hostage_state != null:
			hud.update_objective(
				"RESCUE THE HOSTAGES  %d/%d"
				% [hostage_state.rescued_count, hostage_state.original_count]
			)
			return
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
	for human: PlayerController in _human_players_stable():
		_sync_human_c4_ownership(human)
	_c4_equipped = player.active_weapon == "c4"


func _sync_human_c4_ownership(human: PlayerController) -> void:
	var actor_id := _round_id_for_actor(human)
	var should_own := (
		str(round_state.bomb_owner) == actor_id
		and str(round_state.bomb_state) in [
			RoundStateScript.BOMB_CARRIED,
			RoundStateScript.BOMB_PLANTING,
		]
		and bool(round_state.players.get(actor_id, {}).get("has_c4", false))
	)
	if should_own:
		if not human.owns_weapon("c4"):
			human.grant_item("c4")
		return
	if human.active_weapon == "c4":
		human.switch_weapon(human._best_owned_weapon())
	human.owned_weapons.erase("c4")
	human.ammunition.erase("c4")


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


func _capture_bot_loadouts() -> Dictionary:
	var result := {}
	for bot: TargetActor in _all_bots():
		result[bot.name] = {
			"survived": bot.alive,
			"weapon": bot.active_weapon_name,
			"armor": bot.armor,
			"helmet": bot.has_helmet,
		}
	return result


func _apply_bot_round_buy(
	carried_loadouts: Dictionary,
	next_round: int,
) -> void:
	for bot: TargetActor in _all_bots():
		var carried: Dictionary = carried_loadouts.get(bot.name, {})
		var survived := next_round == 1 or bool(carried.get("survived", false))
		if survived:
			bot.configure_weapon(
				str(
					carried.get(
						"weapon",
						"usp"
						if bot.team == Combatant.TEAM_COUNTER_TERRORIST
						else "glock18",
					)
				),
				false,
			)
			bot.armor = int(carried.get("armor", 0))
			bot.has_helmet = bool(carried.get("helmet", false))
		else:
			bot.configure_weapon(
				"usp"
				if bot.team == Combatant.TEAM_COUNTER_TERRORIST
				else "glock18",
				false,
			)
			bot.armor = 0
			bot.has_helmet = false

		var actor_state: Dictionary = round_state.players.get(bot.name, {})
		var weapon_definition := WeaponRegistryScript.definition(
			bot.active_weapon_name,
		)
		var has_primary := (
			not weapon_definition.is_empty()
			and int(weapon_definition.slot) == 1
		)
		var plan := BotBuyPlanScript.build(
			bot.team,
			int(actor_state.get("money", 0)),
			bot.index,
			has_primary,
			bot.armor,
			bool(actor_state.get("has_defuser", false)),
			bot.has_helmet,
		)
		for purchase: Dictionary in plan:
			var item_id := str(purchase.id)
			var result: Dictionary = round_state.purchase_item(
				bot.name,
				item_id,
				int(purchase.price),
				_is_in_team_buy_zone(
					bot.global_position,
					bot.team,
					TargetActor.STANDING_HULL_SIZE,
				),
				not buy_regions.is_empty(),
			)
			if not bool(result.get("allowed", false)):
				continue
			if WeaponRegistryScript.WEAPONS.has(item_id):
				bot.configure_weapon(item_id, false)
			elif item_id == "kevlar":
				bot.armor = 100
			elif item_id == "assaultsuit":
				bot.armor = 100
				bot.has_helmet = true
			elif item_id == "defuser":
				round_state.set_defuser(bot.name, true)
		bot.refresh_weapon_presentation()


func _reset_combatants_for_round(keep_surviving_loadouts := true) -> void:
	sprays.clear()
	for grenade: Node in get_tree().get_nodes_in_group("live_grenades"):
		grenade.queue_free()
	if is_instance_valid(combat_effects):
		combat_effects.clear_smoke_clouds()
	_close_radio_menu()
	hud.clear_combat_feedback()
	bomb_planted = false
	_next_c4_beep_tick = -1
	_c4_beep_index = 0
	if is_instance_valid(bomb):
		bomb.queue_free()
	bomb = null
	_clear_dropped_c4()
	_clear_dropped_weapons()
	_reset_bot_defuser_assignment()
	var keep_loadout := keep_surviving_loadouts and not player.is_dead()
	player.reset_player(player_spawn, keep_loadout)
	player.alive = player.team in ["T", "CT"] and not bool(round_state.players.player.choosing_appearance)
	player.visible = player.alive
	player.collision_layer = _local_player_collision_layer() if player.alive else 0
	if using_imported_map and not target_spawns.is_empty():
		player.face_toward(target_spawns[0])
	for target_index in range(targets.size()):
		targets[target_index].reset_target(target_spawns[target_index])
	for ally_index in range(allied_bots.size()):
		allied_bots[ally_index].reset_target(allied_spawns[ally_index])
	if is_instance_valid(remote_roster):
		for actor_id: String in remote_roster.actor_ids():
			var human: PlayerController = remote_roster.actor_for_id(actor_id)
			if not human.has_meta("network_spawn_slot"):
				continue
			if bool(round_state.players.get(actor_id, {}).get("alive", false)):
				_spawn_remote_human(human, keep_surviving_loadouts and human.alive)
			else:
				human.alive = false
				human.visible = false
				human.collision_layer = 0
				human.controls_enabled = false
				human.look_enabled = false
				human.set_physics_process(false)
	hud.update_health(player.health, player.armor, player.has_helmet)
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
	return _request_human_c4_drop(player)


func _request_human_c4_drop(human: PlayerController) -> bool:
	if not is_instance_valid(round_state) or not is_instance_valid(human):
		return false
	var actor_id := _round_id_for_actor(human)
	var request := C4DropContractScript.resolve_manual_drop(
		human.active_weapon,
		human.alive,
		str(round_state.bomb_owner) == actor_id,
		str(round_state.bomb_state),
		human.global_position,
		-human.global_transform.basis.z,
	)
	if not bool(request.allowed):
		return false
	if not round_state.drop_bomb(actor_id, human.global_position):
		return false
	_consume_new_round_trace()
	_sync_round_public_state()
	human.switch_weapon(human._best_owned_weapon())
	return true


func _clear_dropped_c4() -> void:
	if is_instance_valid(dropped_c4):
		dropped_c4.queue_free()
	dropped_c4 = null


func _on_player_weapon_drop(
	weapon_name: String,
	dropped_clip: int,
	dropped_reserve: int,
) -> void:
	_on_human_weapon_drop(weapon_name, dropped_clip, dropped_reserve, player)


func _on_human_weapon_drop(
	weapon_name: String,
	dropped_clip: int,
	dropped_reserve: int,
	human: PlayerController,
) -> void:
	if not is_instance_valid(human) or not human.alive:
		return
	var actor_id := _round_id_for_actor(human)
	if not round_state.players.has(actor_id):
		return
	var forward := -human.global_transform.basis.z
	forward.y = 0.0
	_spawn_weapon_drop(
		weapon_name,
		dropped_clip,
		dropped_reserve,
		human.global_position,
		forward,
		false,
		actor_id,
	)


func _spawn_weapon_drop(
	weapon_name: String,
	dropped_clip: int,
	dropped_reserve: int,
	origin: Vector3,
	forward: Vector3,
	armed := true,
	dropper_id := "",
) -> void:
	if not DroppedWeaponScript.is_droppable(weapon_name):
		return
	var item := DroppedWeaponScript.new()
	item.setup(weapon_name, dropped_clip, dropped_reserve)
	item.pickup_armed = armed
	item.dropper_id = dropper_id
	var toss := Vector3(forward.x, 0.0, forward.z)
	if not toss.is_zero_approx():
		toss = toss.normalized() * WEAPON_DROP_TOSS_DISTANCE
	item.position = origin + toss + Vector3.UP * 0.45
	var start := origin + Vector3.UP * 0.45
	var obstruction := get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(start, item.position, 1)) if not toss.is_zero_approx() else {}
	if not obstruction.is_empty():
		item.position = (obstruction.position as Vector3).move_toward(start, 0.02)
	# Start above the floor and travel over time; the old floor snap made G
	# look like the weapon vanished and teleported onto the ground.
	item.start_toss(forward)
	item.landed.connect(_on_dropped_weapon_landed)
	add_child(item)
	dropped_weapons.append(item)


func _on_dropped_weapon_landed(drop_position: Vector3) -> void:
	_emit_world_audio(
		"weapon.drop",
		AudioRouterScript.CHAN_VOICE,
		drop_position,
		{"pitch_min": 95, "pitch_max": 124},
	)


func _process_weapon_pickups() -> void:
	if dropped_weapons.is_empty():
		return
	var humans := _human_players_stable()
	for index in range(dropped_weapons.size() - 1, -1, -1):
		var item := dropped_weapons[index]
		if not is_instance_valid(item):
			dropped_weapons.remove_at(index)
			continue
		if not item.pickup_armed:
			var dropper := _actor_for_round_id(item.dropper_id)
			item.pickup_armed = not is_instance_valid(dropper) or not dropper.alive or dropper.global_position.distance_to(item.global_position) > WEAPON_PICKUP_RADIUS
		for human: PlayerController in humans:
			if not human.alive or human.team not in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
				continue
			if not item.pickup_armed and _round_id_for_actor(human) == item.dropper_id:
				continue
			if human.global_position.distance_to(item.global_position) > WEAPON_PICKUP_RADIUS:
				continue
			# Deterministic local/creation order resolves simultaneous touches.
			# Occupied slots are never replaced by an automatic pickup.
			if not str(human.best_owned_weapon_in_slot(item.slot)).is_empty():
				continue
			if human.grant_item(item.weapon_name):
				human.ammunition[item.weapon_name] = {
					"clip": item.clip_ammo,
					"reserve": item.reserve_ammo,
				}
				human.switch_weapon(item.weapon_name)
				human._emit_audio("weapon.acquire", AudioRouterScript.CHAN_ITEM)
				dropped_weapons.remove_at(index)
				item.queue_free()
				break


func _clear_dropped_weapons() -> void:
	for item in dropped_weapons:
		if is_instance_valid(item):
			item.queue_free()
	dropped_weapons.clear()


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
		if actor is PlayerController:
			(actor as PlayerController)._emit_audio("weapon.acquire", AudioRouterScript.CHAN_ITEM)
		elif actor is TargetActor:
			(actor as TargetActor)._emit_audio("weapon.acquire", AudioRouterScript.CHAN_ITEM)
		_consume_new_round_trace()
		_sync_round_public_state()


func _refresh_visible_scoreboard(delta: float) -> void:
	if not is_instance_valid(hud) or not hud.scoreboard_overlay.visible:
		_scoreboard_refresh_seconds = 0.0
		return
	_scoreboard_refresh_seconds += delta
	if _scoreboard_refresh_seconds >= 0.2:
		_scoreboard_refresh_seconds = 0.0
		_update_scoreboard()


func _update_scoreboard() -> void:
	if is_instance_valid(network_client_view):
		network_client_view.update_scoreboard()
		return
	if not is_instance_valid(hud) or not is_instance_valid(round_state):
		return
	var rows: Array = []
	for raw_row: Dictionary in round_state.scoreboard_snapshot():
		var row := raw_row.duplicate()
		row.team = {"T": 1, "CT": 2}.get(str(raw_row.team), 0)
		row.is_local = str(raw_row.id) == "player"
		var actor := _actor_for_round_id(str(raw_row.id))
		row.name = _combatant_display_name(actor) if is_instance_valid(actor) else raw_row.name
		row.health = actor.health if is_instance_valid(actor) else 0
		row.show_private_stats = player.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST] and str(raw_row.team) == player.team
		row.latency = (
			scoreboard_latency("human", _actor_ping_ms(actor))
			if actor is PlayerController
			else scoreboard_latency("bot", -1)
		)
		rows.append(row)
	hud.update_scoreboard(
		rows,
		"Classic FPS",
		map_name if using_imported_map else "training",
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
	_publish_network_impact("explosion", {"weapon": "c4", "position": origin, "normal": Vector3.UP, "underwater": blast_underwater})
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
	_objective_audio_schedule.clear()


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
	var winner := str(event.winner)
	if _network_objective_result not in ["bomb_defused", "bomb_exploded"]:
		_network_objective_result = "t_win" if winner == "T" else ("ct_win" if winner == "CT" else "draw")
	var terrorists_won := winner == RoundStateScript.TEAM_T
	var drawn := winner.is_empty()
	var result_sound := "round.t_win" if terrorists_won else "round.ct_win"
	if drawn:
		result_sound = "round.draw"
	_emit_world_audio(
		result_sound,
		AudioRouterScript.CHAN_STREAM,
		Vector3.ZERO,
		{"attenuation": AudioRouterScript.ATTN_NONE},
	)
	var labels := {
		"round_draw": "ROUND DRAW",
		"target_bombed": "TARGET BOMBED  •  TERRORISTS WIN",
		"bomb_defused": "BOMB DEFUSED  •  COUNTER-TERRORISTS WIN",
		"target_saved": "TARGET SAVED  •  COUNTER-TERRORISTS WIN",
		"terrorists_win": "TERRORISTS WIN",
		"cts_win": "COUNTER-TERRORISTS WIN",
	}
	var banner_color := Color("#ff9e68") if terrorists_won else Color("#77d9ff")
	if drawn:
		banner_color = Color("#ffca66")
	hud.show_banner(
		str(labels.get(str(event.reason), str(event.reason).to_upper())),
		banner_color,
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
