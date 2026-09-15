extends SceneTree

const B = preload("res://scripts/cs16_ballistics.gd")
const Recoil = preload("res://scripts/cs16_weapon_recoil.gd")
const State = preload("res://scripts/network_world_state.gd")
const ClientView = preload("res://scripts/network_client_view.gd")
var failures: Array[String] = []

class OnlineSession extends Node:
	func is_online() -> bool: return true


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.000001, message + " actual=" + str(actual))


func _bombs(hud: GameHUD) -> Array:
	return hud.radar_display.contacts.filter(func(c: Dictionary) -> bool: return c.get("kind") == "bomb")


func _run() -> void:
	for weapon: String in B.AUTOMATIC_ACCURACY:
		_check(CS16WeaponRegistry.WEAPONS.has(weapon), "canonical accuracy weapon: " + weapon)
		_check(Recoil.TABLE.has(weapon), "weapon-specific recoil: " + weapon)
		var first := B.base_accuracy(weapon)
		var sustained := B.automatic_accuracy(weapon, 20)
		_check(sustained > first, "sustained fire loses precision: " + weapon)
		_check(B.weapon_spread(weapon, true, 0, false, false, sustained, 0.9) > B.weapon_spread(weapon, true, 0, false, false, first, 0.9), "spread consumes accuracy: " + weapon)
		for grounded in [false, true]:
			for moving in [false, true]:
				for crouched in [false, true]:
					_check(Recoil.parameters(weapon, grounded, moving, crouched).size() == 7, "all recoil stances have complete source parameters")
	_near(B.automatic_accuracy("m4a1", 3), 27.0 / 220.0 + 0.3, "M4 cubic growth")
	_near(B.automatic_accuracy("m4a1", 30), 1.0, "M4 accuracy cap")
	_near(B.weapon_spread("m4a1", true, 0, false, false, 0.2, 0.9), 0.004, "M4 unsilenced rest")
	_near(B.weapon_spread("m4a1", true, 0, false, false, 0.2, 0.9, true), 0.005, "M4 silenced rest")
	_near(B.weapon_spread("m4a1", false, 0, false, false, 0.2, 0.9), 0.115, "M4 airborne")
	_near(B.weapon_spread("awp", true, 0, false, false, 0.2, 0.9), 0.081, "AWP unscoped penalty")
	_near(B.weapon_spread("awp", true, 0.11, false, true, 0.2, 0.9), 0.1, "AWP slow-moving threshold")
	_near(B.weapon_spread("awp", true, 0, true, true, 0.2, 0.9), 0.0, "AWP crouched scoped")
	_near(B.weapon_spread("scout", true, 0, false, false, 0.2, 0.9), 0.032, "Scout unscoped penalty")
	_near(B.weapon_spread("g3sg1", true, 0, false, false, 0.98, 0.9), 0.0016, "G3 multiplies entire unscoped cone by inaccuracy")
	_near(B.weapon_spread("sg550", true, 0, false, false, 0.9, 0.9), 0.03, "SG550 unscoped penalty is outside accuracy scaling")
	_near(B.sniper_accuracy("g3sg1", 0.25), 0.625, "G3 refire accuracy")
	_near(B.sniper_accuracy("sg550", 0.25), 0.7375, "SG550 refire accuracy")
	for seed in range(256):
		var kick := B.shared_random_long(seed, 4, 6)
		_check(kick >= 4 and kick <= 6 and kick == B.shared_random_long(seed, 4, 6), "shared shotgun kick is bounded and deterministic")
	for weapon: String in B.PISTOL_ACCURACY:
		var base := B.base_accuracy(weapon)
		_check(B.pistol_accuracy(weapon, base, 0.1) < base, "rapid pistol shots lose precision: " + weapon)
		_near(B.pistol_accuracy(weapon, base, 2.0), base, "pistol recovery is capped: " + weapon)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	game.set_physics_process(false)
	var player: PlayerController = game.player
	player.set_physics_process(false)
	for bot: Node in game._all_bots(): bot.set_physics_process(false)
	player.alive = true
	player.active_weapon = "m4a1"
	player.weapon_clock.reset("m4a1")
	player._reset_weapon_accuracy()
	player._movement_grounded = true
	player._standing = true
	player.velocity = Vector3.ZERO
	player._punch_degrees = Vector2.ZERO
	player._record_weapon_shot(0)
	player._apply_weapon_kickback()
	_near(player._punch_degrees.x, -0.65, "live M4 first-shot recoil")
	for shot in range(2, 21): player._record_weapon_shot(float(shot) * 0.09)
	player._recover_weapon_accuracy()
	_check(player._ak_shots_fired == 15, "release caps stored recoil shots")
	player.weapon_clock.advance_tick(40)
	player._recover_weapon_accuracy()
	_check(player._ak_shots_fired == 15, "recovery does not reset whole burst at 400ms")
	for tick in range(50):
		player.weapon_clock.advance_tick()
		player._recover_weapon_accuracy()
	_check(player._ak_shots_fired == 0, "released trigger recovers incrementally")
	_near(player._ak_accuracy, 0.2, "fully recovered M4 baseline")
	player.active_weapon = "famas"
	player.viewmodel.load_weapon("famas")
	player.weapon_clock.reset("famas")
	player._reset_weapon_accuracy()
	player.weapon_modes.famas = true
	player.clip = 25
	player.global_position = Vector3(0, 100, 0)
	player._try_fire()
	_check(player._next_burst_tick == 5 and player.clip == 24, "FAMAS first follow-up is scheduled 50ms after trigger")
	player._advance_weapon_simulation_tick(5)
	_check(player.clip == 23 and player._ak_shots_fired == 1, "burst follow-up does not advance primary-shot accuracy")
	player._advance_weapon_simulation_tick(10)
	_check(player.clip == 22 and player._ak_shots_fired == 1 and player._burst_shots_remaining == 0, "FAMAS completes three bullets with one primary recoil step")
	# Both human and bot callers must use the victim's posture and axes.
	var bot: TargetActor = game._all_bots()[0]
	for crouched in [false, true]:
		bot.objective_crouch = crouched
		bot.last_command.crouch = crouched
		var bot_head := bot.to_global(Vector3(0, 0.36 if crouched else 0.6, 0))
		_check(player._hit_group_for_impact(bot, bot_head) == B.HitGroup.HEAD, "human can headshot crouched/standing bot")
	bot.objective_crouch = false
	bot.last_command.crouch = false
	for yaw in [0.0, PI / 2.0, PI]:
		player.rotation.y = yaw
		for crouched in [false, true]:
			player._standing = not crouched
			var head_y := 0.36 if crouched else 0.6
			var head := player.to_global(Vector3(0, head_y, 0))
			_check(bot._hit_group_for_impact(player, head) == B.HitGroup.HEAD, "bot can headshot rotated/crouched human")
			_check(player._hit_group_for_impact(player, head) == B.HitGroup.HEAD, "human shares headshot classification")
			var arm_y := 0.3 if crouched else 0.48
			_check(player.hit_group_at(player.to_global(Vector3(-0.12, arm_y, 0))) == B.HitGroup.LEFT_ARM, "left arm rotates with victim")
			_check(player.hit_group_at(player.to_global(Vector3(0.12, arm_y, 0))) == B.HitGroup.RIGHT_ARM, "right arm rotates with victim")
	player._standing = true
	player.rotation.y = 0
	player.global_position = game.player_spawn
	for team in ["T", "CT", "UNASSIGNED"]:
		player.team = team
		for alive in [false, true]:
			player.alive = alive
			for bomb_state in ["none", "carried", "dropped", "planting", "planted", "defused", "exploded"]:
				game.round_state.bomb_state = bomb_state
				game.round_state.bomb_position = player.global_position + Vector3(3, 0, -6)
				game._update_tactical_hud()
				var expected: bool = team == "T" and alive and bomb_state in ["dropped", "planted"]
				_check(_bombs(game.hud).size() == int(expected), "host radar visibility: " + team + " " + bomb_state)
	player.team = "T"
	player.alive = true
	player.active_weapon = "glock18"
	player.clip = 20
	player.reserve = 40
	player._store_active_ammunition()
	player.viewmodel.load_weapon("glock18")
	var view := ClientView.new()
	game.add_child(view)
	view.set_process(false)
	view.game = game
	var session := OnlineSession.new()
	game.add_child(session)
	view.session = session
	var owner: Dictionary = game._network_actor_state(player)
	owner.weapon = "glock18"
	var state := {"version": State.VERSION, "epoch": 2, "tick": 10, "map": "de_dust2",
		"owner_id": owner.id, "input_ack": 0, "started": true, "concluded": false,
		"items": [], "can_buy": false, "feedback": State.empty_feedback(), "broken_brushes": [],
		"inventory": State.inventory_for(player), "motion": State.motion_for(player),
		"round": {"number": 1, "phase": "live", "seconds": 100.0, "t_score": 0, "ct_score": 0}, "actors": [owner]}
	_check(not State.validate(state).is_empty(), "client radar uses valid production snapshot")
	for kind in ["dropped_c4", "planted_c4"]:
		var position := player.global_position + Vector3(3, 0, -6)
		state.items = [{"id": 47, "kind": kind, "weapon": "c4", "position": position,
			"rotation": Quaternion.IDENTITY, "total": 45.0 if kind == "planted_c4" else 0.0,
			"remaining": 30.0 if kind == "planted_c4" else 0.0}]
		state.feedback.bomb_state = "dropped" if kind == "dropped_c4" else "planted"
		for team in ["T", "CT"]:
			owner.team = team
			view.apply_snapshot(state)
			_check(_bombs(game.hud).size() == int(team == "T"), "late-join client radar team filter: " + kind)
			if team == "T":
				_check(_bombs(game.hud)[0].position == position, "radar follows authoritative C4 position")
				view.apply_snapshot(state)
				_check(_bombs(game.hud).size() == 1, "repeat snapshot does not duplicate marker")
		owner.team = "T"
		for terminal in ["defused", "exploded", "none"]:
			state.feedback.bomb_state = terminal
			view.apply_snapshot(state)
			_check(_bombs(game.hud).is_empty(), "resolved bomb clears radar even before world-model cleanup")
		state.items = []
		state.feedback.bomb_state = "carried"
		view.apply_snapshot(state)
		_check(_bombs(game.hud).is_empty() and not game.hud.radar_display.is_processing(), "pickup/reset clears marker and blink updates")
	if OS.get_cmdline_user_args().has("--capture"):
		state.items = [{"id": 47, "kind": "dropped_c4", "weapon": "c4", "position": player.global_position + Vector3(3, 0, -6),
			"rotation": Quaternion.IDENTITY, "total": 0.0, "remaining": 0.0}]
		state.feedback.bomb_state = "dropped"
		view.apply_snapshot(state)
		game.hud.show()
		game.hud.set_deploy_visible(false)
		game.hud.set_buy_menu_visible(false)
		player.weapon_anchor.show()
		player._punch_degrees = Vector2.ZERO
		player._sync_view_angles()
		player.camera.make_current()
		for frame in range(4): await process_frame
		while fmod(float(Time.get_ticks_msec()) / 1000.0, 1.0) >= 0.4:
			await process_frame
		RenderingServer.force_draw()
		_check(root.get_texture().get_image().save_png("/tmp/protocol47-radar-drop.png") == OK, "native dropped C4 radar capture saved")
	print("GAME_COMBAT_FIDELITY_PASS" if failures.is_empty() else "GAME_COMBAT_FIDELITY_FAIL " + str(failures))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
