extends SceneTree

const State = preload("res://scripts/network_world_state.gd")
const ClientView = preload("res://scripts/network_client_view.gd")
var failures: Array[String] = []

class SessionStub extends Node:
	var online := true
	func is_online() -> bool: return online
	func is_connecting() -> bool: return false

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	root.gui_disable_input = true
	game.set_process_unhandled_input(false)
	game.player.set_process_input(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots(): bot.set_physics_process(false)
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	game.hud._select_team(2)
	game.hud._select_class(1)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots(): bot.set_physics_process(false)
	var player: PlayerController = game.player
	var hud: GameHUD = game.hud
	var icon: TextureRect = hud._defuse_kit_icon
	var progress: Control = hud.defuse_progress_bar
	_check(player.team == "CT" and player.alive, "real CT deployment")
	_check(icon.texture != null and icon.texture.get_size() == Vector2(32, 32), "original 32px defuser sprite")
	_check(icon.get_meta("classic_sprite") == "defuser" and icon.modulate.g > icon.modulate.r, "original artwork tinted green")
	_check(not icon.visible, "new CT without kit has no indicator")
	_check(not progress.visible and progress.size == Vector2(200, 12), "defuse progress starts hidden with classic compact geometry")
	_check(hud._armor_icon.get_meta("classic_sprite") == "suit_full", "fresh player has vest-only HUD icon")
	var purchase: Dictionary = game._purchase_and_grant("defuser")
	_check(purchase.allowed and player.equipment.defuser and game.round_state.players.player.has_defuser, "real purchase grants authoritative kit")
	_check(icon.visible, "purchase updates HUD immediately")
	game.money = 16000
	game.round_state.players.player.money = 16000
	_check(game._purchase_and_grant("kevlar").allowed, "vest purchase succeeds")
	_check(hud._armor_icon.get_meta("classic_sprite") == "suit_full", "vest does not show helmet")
	_check(game._purchase_and_grant("assaultsuit").allowed, "helmet upgrade succeeds")
	_check(hud._armor_icon.get_meta("classic_sprite") == "suithelmet_full", "purchase immediately shows combined armor and helmet")
	player.armor = 70
	player.health_changed.emit(player.health, player.armor)
	_check(hud._has_helmet, "damage refresh retains helmet indicator")
	game._update_tactical_hud()
	_check(icon.get_global_rect().position.y >= 0, "kit remains inside viewport")
	_check(not icon.get_global_rect().intersects(hud._buyzone_icon.get_global_rect()), "kit and buy cart do not overlap")
	for team in ["CT", "T", "UNASSIGNED"]:
		for alive in [false, true]:
			for kit in [false, true]:
				player.team = team
				player.alive = alive
				player.equipment.defuser = kit
				game._update_tactical_hud()
				_check(icon.visible == (team == "CT" and alive and kit), "local ownership/team/life visibility")
	player.team = "CT"
	player.alive = true
	player.equipment.defuser = true
	game._update_tactical_hud()
	hud.set_buy_menu_visible(true)
	_check(not icon.visible, "buy menu hides kit")
	hud.set_buy_menu_visible(false)
	_check(icon.visible, "closing menu restores owned kit")
	hud.set_spectating(true)
	_check(not icon.visible, "spectators do not show a kit")
	hud.set_spectating(false)
	var saved_tick: int = game.round_state.tick
	game.round_state.defuse_actor = "player"
	game.round_state.defuse_started_tick = saved_tick
	game.round_state.defuse_duration_ticks = 500
	game._update_round_hud(true)
	_check(progress.visible and hud._defuse_progress_fill.size.x == 0.0, "real local defuse starts an empty progress bar")
	game.round_state.tick += 250
	game._update_round_hud(true)
	_check(is_equal_approx(hud._defuse_progress_fill.size.x, 98.0)
		and hud._defuse_progress_fill.color == GameHUD.CLASSIC_GREEN, "real local defuse fills the green bar to authoritative progress")
	hud.set_paused_visible(true)
	_check(not progress.visible, "Pause hides defuse progress")
	hud.set_paused_visible(false)
	_check(progress.visible, "closing Pause restores an active defuse")
	game.round_state.defuse_actor = ""
	game.round_state.tick = saved_tick
	game._update_round_hud(true)
	_check(not progress.visible, "local abort immediately clears progress")
	var view := ClientView.new()
	game.add_child(view)
	view.set_process(false)
	view.game = game
	var session := SessionStub.new()
	game.add_child(session)
	view.session = session
	var owner: Dictionary = game._network_actor_state(player)
	var state := {"version": State.VERSION, "epoch": 2, "tick": 10, "map": "de_dust2",
		"owner_id": owner.id, "input_ack": 0, "started": true, "concluded": false,
		"items": [], "can_buy": false, "feedback": State.empty_feedback(), "broken_brushes": [],
		"inventory": State.inventory_for(player), "motion": State.motion_for(player),
		"round": {"number": 1, "phase": "live", "seconds": 100.0, "t_score": 0, "ct_score": 0}, "actors": [owner]}
	_check(not State.validate(state).is_empty(), "valid authoritative owner snapshot")
	player.equipment.defuser = false
	view.apply_snapshot(state)
	_check(icon.visible and player.equipment.defuser, "late join receives kit from owner inventory")
	state.feedback = State.empty_feedback()
	state.feedback.action = "defuse"
	state.feedback.total = 5.0
	state.feedback.remaining = 2.5
	state.feedback.bomb_state = "planted"
	view.apply_snapshot(state)
	_check(progress.visible and is_equal_approx(hud._defuse_progress_fill.size.x, 98.0), "network owner sees authoritative half-complete defuse")
	state.feedback = State.empty_feedback()
	view.apply_snapshot(state)
	_check(not progress.visible, "network abort/completion clears progress")
	_check(hud._has_helmet and hud._armor_icon.get_meta("classic_sprite") == "suithelmet_full", "owner snapshot shows helmet")
	owner.helmet = false
	view.apply_snapshot(state)
	_check(not hud._has_helmet and hud._armor_icon.get_meta("classic_sprite") == "suit_full", "owner snapshot clears lost helmet")
	owner.helmet = true
	view.apply_snapshot(state)
	_check(player.viewmodel.weapon_silenced, "owner snapshot preserves default USP silencer")
	view.apply_snapshot(state)
	_check(icon.visible, "duplicate snapshot preserves single icon")
	state.inventory.equipment.defuser = false
	view.apply_snapshot(state)
	_check(not icon.visible, "authoritative kit loss clears icon")
	state.inventory.equipment.defuser = true
	owner.alive = false
	view.apply_snapshot(state)
	_check(not icon.visible, "dead network owner cannot show stale kit")
	owner.alive = true
	owner.team = "T"
	view.apply_snapshot(state)
	_check(not icon.visible, "network team switch cannot show stale kit")
	owner.team = "CT"
	view.apply_snapshot(state)
	hud.set_spectating(false)
	if OS.get_cmdline_user_args().has("--capture"):
		player.global_position = Vector3(2.56, -1.28, -24.64)
		player.camera.look_at(Vector3(3.2, -0.75, -20))
		player.camera.make_current()
		player.weapon_anchor.show()
		hud.set_buy_zone(true)
		hud.update_defuse_progress(true, 2.5, 5.0)
		for frame in range(4): await process_frame
		_check(icon.is_visible_in_tree() and icon.get_global_rect().position.y > 0, "kit is on-screen at capture time")
		_check(progress.is_visible_in_tree() and progress.get_global_rect().position.y > 0, "progress is on-screen at capture time")
		RenderingServer.force_draw()
		_check(root.get_texture().get_image().save_png("/tmp/protocol47-defuse-kit-hud.png") == OK, "native capture saved")
		hud.update_defuse_progress(false, 0.0, 0.0)
	session.online = false
	view._on_status("offline")
	_check(not icon.visible and not progress.visible, "disconnect clears kit icon and defuse progress")
	player.reset_player(player.global_position, false)
	game._update_tactical_hud()
	_check(not icon.visible and not player.equipment.defuser, "fresh spawn clears kit")
	_check(not hud._has_helmet and hud._armor_icon.get_meta("classic_sprite") == "suit_full", "fresh spawn clears helmet icon")
	player.grant_item("defuser")
	player.grant_item("assaultsuit")
	player.reset_player(player.global_position, true)
	game._update_tactical_hud()
	_check(icon.visible, "surviving loadout retains kit")
	_check(hud._has_helmet, "surviving loadout retains helmet icon")
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("GAME_DEFUSE_KIT_HUD_PASS")
	quit(0 if failures.is_empty() else 1)
