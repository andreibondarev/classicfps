extends SceneTree

const State = preload("res://scripts/network_world_state.gd")
const Events = preload("res://scripts/network_combat_events.gd")
const ClientView = preload("res://scripts/network_client_view.gd")
const Grenade = preload("res://scripts/grenade.gd")
var failures: Array[String] = []

class OnlinePresentationSession extends Node:
	func is_online() -> bool:
		return true

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _check_grenade_mesh(visual: Node3D, kind: String) -> void:
	_check(visual.get_meta("source_model", "") == Grenade.WORLD_MODELS[kind], "correct source grenade model: " + kind)
	var mesh := visual.get_child(0) as MeshInstance3D if visual.get_child_count() > 0 else null
	_check(mesh != null and mesh.mesh is ArrayMesh and mesh.mesh.get_surface_count() == 2,
		"grenade renders original textured surfaces, not a sphere: " + kind)
	if mesh == null:
		return
	var bounds := mesh.get_aabb()
	_check(bounds.size.length() > 0.05 and bounds.size.length() < 0.3, "grenade has visible source-scale bounds: " + kind)
	for surface in mesh.mesh.get_surface_count():
		var material := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
		_check(material != null and material.albedo_texture != null
			and material.albedo_texture.resource_path.contains("/world_weapons/%s/" % kind),
			"grenade uses its own original skin: " + kind)


func _check_flying_grenades(game: Node, view: Node) -> void:
	view.set_process(false)
	var projectiles: Array[HEGrenade] = []
	var index := 0
	for kind: String in Grenade.WORLD_MODELS:
		var grenade := Grenade.new()
		game.add_child(grenade)
		# Launch happens after _ready in the real human/bot paths as well.
		var origin := Vector3((index - 1) * 0.3, 100, 0)
		var impulse := Vector3(2, 3, -4)
		grenade.launch(origin, impulse, game.player, kind)
		_check_grenade_mesh(grenade.visual, kind)
		_check(grenade.visual.is_visible_in_tree() and grenade.global_position == origin
			and grenade.linear_velocity == impulse and grenade._simulation_tick == 0,
			"world model appears at launch without changing throw or fuse: " + kind)
		grenade.freeze = true
		grenade.set_physics_process(false)
		projectiles.append(grenade)
		var item: Dictionary = game._network_item_state(grenade, "grenade", kind)
		_check(State.valid_world_items([item]), "grenade snapshot retains existing schema")
		view._apply_items([item])
		var replica: Node3D = view.items[item.id].visual
		_check_grenade_mesh(replica, kind)
		_check(replica.is_visible_in_tree(), "client projectile is visible: " + kind)
		view._apply_items([item])
		_check(view.items.size() == 1 and view.items[item.id].visual == replica,
			"repeated snapshots retain one grenade visual: " + kind)
		index += 1
	view._apply_items([])
	_check(view.items.is_empty(), "client removes the model when the projectile disappears")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--grenade-capture="):
			game.hud.hide()
			var camera := Camera3D.new()
			game.add_child(camera)
			camera.global_position = Vector3(0, 100.55, 0.85)
			camera.look_at(Vector3(0, 100.04, 0))
			camera.make_current()
			for frame in range(4):
				await process_frame
			RenderingServer.force_draw()
			var picture := root.get_texture().get_image()
			_check(picture.save_png(argument.trim_prefix("--grenade-capture=")) == OK, "in-air grenade capture saved")
			camera.queue_free()
	for grenade in projectiles:
		grenade.explode()
		_check(not grenade.visible and not grenade.visual.is_visible_in_tree(), "detonation hides grenade model")
		grenade.queue_free()


func _check_money_snapshots(game: Node, view: Node) -> void:
	var session := OnlinePresentationSession.new()
	game.add_child(session)
	view.session = session
	view.set_process(false)
	view.snapshot = {}
	var owner: Dictionary = game._network_actor_state(game.player)
	owner.money = 5000
	var state := {"version": State.VERSION, "epoch": 2, "tick": 10, "map": "de_dust2",
		"owner_id": owner.id, "input_ack": 0, "started": true, "concluded": false,
		"items": [], "can_buy": false, "feedback": State.empty_feedback(), "broken_brushes": [],
		"inventory": State.inventory_for(game.player), "motion": State.motion_for(game.player),
		"round": {"number": 5, "phase": "live", "seconds": 100.0, "t_score": 2, "ct_score": 2},
		"actors": [owner]}
	_check(not State.validate(state).is_empty(), "money fixture uses a complete valid owner snapshot")
	view.apply_snapshot(state)
	_check(game.hud.money_label.text == "$5000" and game.hud.money_delta.modulate.a == 0.0,
		"joining an existing balance does not show a false reward")
	owner.money = 5300
	view.apply_snapshot(state)
	_check(game.hud.money_delta_amount == 300, "client renders authoritative owner reward")
	var fade: Tween = game.hud._money_delta_tween
	view.apply_snapshot(state)
	_check(game.hud._money_delta_tween == fade and game.hud.money_delta_amount == 300,
		"duplicate money snapshots never restart or duplicate the effect")
	owner.money = 5220
	view.apply_snapshot(state)
	_check(game.hud.money_delta_amount == -80, "client renders authoritative owner purchase")
	state.round.number = 1
	owner.money = 800
	view.apply_snapshot(state)
	_check(game.hud.money_delta.modulate.a == 0.0, "client match restart clears money effect")
	owner.team = "CT" if owner.team == "T" else "T"
	owner.money = 1000
	view.apply_snapshot(state)
	_check(game.hud.money_delta.modulate.a == 0.0, "client side change establishes a quiet baseline")
	owner.money = 1300
	view.apply_snapshot(state)
	_check(game.hud.money_delta_amount == 300, "rewards resume after baseline reset")
	game.hud.set_deploy_visible(false)
	game.hud.set_buy_menu_visible(false)
	game.hud.set_spectating(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--money-capture="):
			# Isolate this HUD check from earlier grenade/death animation fixtures.
			game.player.viewmodel.visible = false
			game.hud.banner_label.modulate.a = 0.0
			game.hud.status_label.modulate.a = 0.0
			game._build_deploy_camera()
			await process_frame
			RenderingServer.force_draw()
			_check(root.get_texture().get_image().save_png(argument.trim_prefix("--money-capture=")) == OK,
				"rendered money reward capture saved")


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "fixture requires muted audio")
	var feedback := State.empty_feedback()
	_check(State.valid_feedback(feedback), "empty owner feedback validates")
	_check(State.valid_broken_brushes([1, 31, 41]), "bounded brush model IDs validate")
	for invalid_models: Variant in [null, {}, [0], [-1], [4097], [1, 1], [1.0]]:
		_check(not State.valid_broken_brushes(invalid_models), "invalid/duplicate broken model ID rejected")
	for pair in [["remaining", 1.0], ["flash_remaining", 1.0], ["action", "damage"], ["total", NAN],
		["can_plant", 1], ["bomb_state", "invalid"], ["result", "arbitrary text"], ["extra", 0]]:
		var bad := feedback.duplicate()
		bad[pair[0]] = pair[1]
		_check(not State.valid_feedback(bad), "invalid feedback rejected: " + str(pair[0]))
	var smoke := {"id": 50, "kind": "smoke", "weapon": "smokegrenade", "position": Vector3.ZERO,
		"rotation": Quaternion.IDENTITY, "total": 15.64, "remaining": 10.64}
	_check(State.valid_world_items([smoke]), "active smoke validates")
	var invalid := smoke.duplicate()
	invalid.weapon = "hegrenade"
	_check(not State.valid_world_items([invalid]), "HE cannot impersonate persistent smoke")
	invalid = smoke.duplicate()
	invalid.total = 100.0
	_check(not State.valid_world_items([invalid]), "smoke lifetime is bounded")
	var explosion := {"version": Events.VERSION, "epoch": 1, "sequence": 1, "tick": 1, "actor": "", "life": 1,
		"kind": "explosion", "data": {"weapon": "hegrenade", "position": Vector3.ZERO, "normal": Vector3.UP, "underwater": false}}
	_check(Events.validate(explosion) == explosion, "host explosion validates")
	explosion.actor = "player"
	_check(Events.validate(explosion).is_empty(), "world explosion cannot impersonate an actor event")
	explosion.actor = ""
	explosion.data.weapon = "smokegrenade"
	_check(Events.validate(explosion).is_empty(), "persistent smoke cannot be emitted as a transient explosion")
	var world_audio := explosion.duplicate(true)
	world_audio.kind = "world_audio"
	world_audio.data = {"source": 50, "name": "c4.beep1", "sample": "weapons/c4_beep1.wav", "channel": 1,
		"volume": 1.0, "attenuation": 1.0, "pitch": 100, "origin": Vector3.ZERO}
	_check(Events.validate(world_audio) == world_audio, "world audio validates exact catalog sample and source")
	world_audio.data.source = -1
	_check(Events.validate(world_audio).is_empty(), "world audio rejects invalid source")
	world_audio.data.source = 50
	world_audio.data.sample = "weapons/c4_explode1.wav"
	_check(Events.validate(world_audio).is_empty(), "world audio rejects mismatched catalog sample")
	var actor_step := world_audio.duplicate(true)
	actor_step.kind = "audio"
	actor_step.actor = "player"
	actor_step.data.erase("source")
	actor_step.data.name = "player.step.M"
	actor_step.data.sample = "player/pl_metal2.wav"
	actor_step.data.channel = 4
	_check(Events.validate(actor_step) == actor_step, "actor material footstep validates")
	actor_step.data.sample = "player/pl_step2.wav"
	_check(Events.validate(actor_step).is_empty(), "actor footstep rejects a mismatched material sample")
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	# Native startup prepares assets asynchronously; let it finish before this
	# short fixture tears down the scene and releases shared model resources.
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	await physics_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.alive = true
	for bot: Node in game._all_bots():
		bot.set_physics_process(false)
	var view := ClientView.new()
	game.add_child(view)
	view.game = game
	var network := root.get_node("NetworkSession")
	network.disconnect_session()
	network.combat_event_received.connect(view.queue_combat_event)
	view._epoch = 1
	view.snapshot = {"tick": 1, "round": {"number": 1}, "actors": []}
	for cue: String in ["c4.disarm", "c4.disarmed"]:
		world_audio.sequence += 1
		world_audio.data = {"source": 0, "name": cue,
			"sample": "weapons/c4_disarm.wav" if cue == "c4.disarm" else "weapons/c4_disarmed.wav",
			"channel": 3 if cue == "c4.disarm" else 1, "volume": 1.0, "attenuation": 0.8,
			"pitch": 100, "origin": Vector3(10, 0, 0)}
		_check(network.accept_combat_event(world_audio), "client accepts defuse cue: " + cue)
		_check(not network.accept_combat_event(world_audio), "duplicate defuse cue rejected: " + cue)
		var starts: Array = game.audio_router.trace().filter(func(e: Dictionary) -> bool:
			return e.kind == "start" and e.event_name == cue)
		_check(starts.size() == 1 and starts[0].sample == world_audio.data.sample
			and starts[0].origin == [1000.0, 0.0, 0.0], "client presents exact spatial sample once: " + cue)
	view.owner_id = "player"
	view.snapshot.actors = [{"id": "player", "life": 1}]
	var ammo_before: int = game.player.clip
	for cue: String in ["glock18.reload_0", "usp.reload_0"]:
		world_audio.sequence += 1
		world_audio.kind = "audio"
		world_audio.actor = "player"
		world_audio.data.erase("source")
		world_audio.data.name = cue
		world_audio.data.sample = "weapons/clipout1.wav" if cue.begins_with("glock") else "weapons/usp_clipout.wav"
		world_audio.data.channel = 1
		_check(network.accept_combat_event(world_audio), "client accepts owner reload sound: " + cue)
		_check(not network.accept_combat_event(world_audio), "duplicate owner reload cue rejected")
		var starts: Array = game.audio_router.trace().filter(func(e: Dictionary) -> bool:
			return e.kind == "start" and e.event_name == cue)
		_check(starts.size() == 1 and starts[0].attenuation == 0.0,
			"owner reload plays once without distance attenuation: " + cue)
	_check(game.player.clip == ammo_before, "client reload audio does not mutate ammunition")
	network.combat_event_received.disconnect(view.queue_combat_event)
	view.owner_id = "remote_human_1"
	view.snapshot.actors = [
		{"id": "player", "name": "Same Name", "team": "CT", "kills": 2, "deaths": 0, "alive": true, "health": 81, "money": 1200},
		{"id": "remote_human_1", "name": "Same Name", "team": "CT", "kills": 1, "deaths": 1, "alive": false, "health": 0, "money": 2400},
		{"id": "enemy", "name": "Enemy", "team": "T", "kills": 3, "deaths": 0, "alive": true, "health": 48, "money": 16000, "weapon": "c4"},
	]
	view.update_scoreboard()
	var highlighted: Array[String] = []
	for score_row: Node in game.hud.scoreboard_rows.get_children():
		if score_row.get_meta("is_local", false):
			highlighted.append(str(score_row.get_meta("actor_id")))
		if score_row.get_meta("actor_id", "") == "player":
			_check(score_row.get_node("Health").text == "81" and score_row.get_node("Money").text == "$1200",
				"client shows teammate HP and money from authoritative snapshot")
		if score_row.get_meta("actor_id", "") == "enemy":
			_check(score_row.get_node("Health").text == "" and score_row.get_node("Money").text == ""
				and score_row.get_node("Status").text == "", "client hides enemy HP, money and bomb")
	_check(highlighted == ["remote_human_1"], "client highlights its own durable ID even when dead or names match")
	view.snapshot = {}
	var model: int = game.breakable_runtime.model_indices()[0]
	view._apply_breakables([model, 4096])
	_check(not game.imported_map.model_runtime_active(model)
		and game.imported_map.collision_body_for_model(model).collision_layer == 0
		and game.breakable_runtime.broken_model_indices().is_empty(), "client applies known brush visibility/collision without local break rules")
	view._apply_breakables([])
	_check(game.imported_map.model_runtime_active(model)
		and game.imported_map.collision_body_for_model(model).collision_layer != 0, "complete snapshot restores brush collision")
	game.player.grant_item("hegrenade")
	game.player.switch_weapon("hegrenade")
	var grenade_clip: int = game.player.clip
	view.owner_id = "player"
	var grenade_action := {"version": Events.VERSION, "epoch": 1, "sequence": 1, "tick": 1,
		"actor": "player", "life": 1, "kind": "grenade_action", "data": {"weapon": "hegrenade", "action": "pullpin"}}
	for action: String in ["pullpin", "throw"]:
		grenade_action.data.action = action
		_check(Events.validate(grenade_action) == grenade_action, "grenade action validates: " + action)
		view._present_combat(grenade_action, {"alive": true})
		_check(game.player.active_weapon == "hegrenade" and game.player.viewmodel._animation_name == action and game.player.clip == grenade_clip,
			"grenade presentation animates without consuming ammunition: " + action)
	grenade_action.data.action = "damage"
	_check(Events.validate(grenade_action).is_empty(), "grenade event cannot invoke arbitrary action")
	grenade_action.data.action = "throw"
	game.player.switch_weapon("knife")
	var animation: String = game.player.viewmodel._animation_name
	view._present_combat(grenade_action, {"alive": true})
	_check(game.player.viewmodel._animation_name == animation, "late throw cannot overwrite newly selected weapon")
	view._received_ms = Time.get_ticks_msec()
	feedback.action = "defuse"
	feedback.total = 10.0
	feedback.remaining = 7.0
	feedback.flash_total = 4.0
	feedback.flash_remaining = 2.0
	view.snapshot = {"concluded": false, "feedback": feedback}
	view._apply_feedback(feedback)
	_check(game.hud.status_label.text.begins_with("DEFUSING") and game.hud.status_label.modulate.a == 1.0, "defuse progress uses visible status row")
	_check(game.hud.flash_blind_overlay.color.a > 0.8, "flash overlay follows remaining host duration")
	view._received_ms -= 5000
	view._update_flash_feedback()
	_check(game.hud.flash_blind_overlay.color.a == 0.0, "flash expires even without further snapshots")
	feedback.action = ""
	feedback.total = 0.0
	feedback.remaining = 0.0
	feedback.result = "bomb_defused"
	view._apply_feedback(feedback)
	_check(game.hud.banner_label.text == "THE BOMB HAS BEEN DEFUSED" and not game.hud.status_label.text.begins_with("DEFUSING"), "defuse result and cancellation clear progress")
	view._apply_items([smoke])
	var cloud: Node = view.items[50].visual
	_check(cloud.tick == 500 and cloud._sprites.size() == 17 and not cloud.is_physics_processing(), "late-join cloud has existing age and no independent simulation")
	view._apply_items([smoke])
	_check(view.items[50].visual == cloud and cloud._sprites.size() == 17, "repeated snapshots do not duplicate smoke")
	cloud.seek_age(16.0)
	_check(cloud._sprites.is_empty(), "aged smoke expires without replaying its lifetime")
	view._apply_items([])
	_check(view.items.is_empty(), "absent smoke is removed atomically")
	game.combat_effects.spawn_smoke_cloud(Vector3.ZERO, 50, true)
	_check(game.combat_effects._sprites.size() >= 17, "host smoke exists before reset")
	game._reset_combatants_for_round()
	_check(game.combat_effects._sprites.filter(func(sprite: Dictionary) -> bool: return sprite.event_type == game.combat_effects.EVENT_SMOKE_CLOUD).is_empty(),
		"round reset removes host smoke as well as client replicas")
	# The corpse renderer and the pickup system must not each create a gun.
	game.round_ending = false
	game._clear_dropped_weapons()
	var victim: TargetActor = game._all_bots()[0]
	victim.configure_weapon("ak47")
	victim.weapon_clip = 7
	victim.weapon_reserve = 29
	victim.receive_bullet_damage(200, 1, "ak47", victim.aim_point(), null)
	_check(game.dropped_weapons.size() == 1 and game.dropped_weapons[0].clip_ammo == 7
		and game.dropped_weapons[0].reserve_ammo == 29, "bot death creates one real pickup with its ammunition")
	_check(not victim.character_model.weapon_instance.visible
		and not is_instance_valid(victim.character_model.dropped_weapon_instance), "host corpse does not create a cosmetic duplicate")
	var dead_actor: Dictionary = game._network_actor_state(victim)
	view._apply_actor(dead_actor)
	var gun_rows: Array = game._network_world_items().filter(func(item: Dictionary) -> bool: return item.kind == "gun")
	view._apply_items(gun_rows)
	var corpse: MdlCharacterModel = view.actors[dead_actor.id].model
	_check(view.items.size() == 1 and not corpse.weapon_instance.visible
		and not is_instance_valid(corpse.dropped_weapon_instance), "late-joining client renders one world gun and an empty-handed corpse")
	var gun_visual: Node = view.items[gun_rows[0].id].visual
	view._apply_actor(dead_actor)
	view._apply_items(gun_rows)
	_check(view.items.size() == 1 and view.items[gun_rows[0].id].visual == gun_visual,
		"repeated dead snapshots do not duplicate the pickup")
	view._apply_items([])
	_check(view.items.is_empty() and not is_instance_valid(corpse.dropped_weapon_instance),
		"picking up the replicated gun leaves no decorative copy beside the corpse")
	await _check_flying_grenades(game, view)
	await _check_money_snapshots(game, view)
	game.audio_router.stop_all("test_teardown")
	game.audio_playback.clear_pool()
	game.queue_free()
	await process_frame
	await process_frame
	CS16CombatEffects.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_GRENADE_FEEDBACK_PASS")
	quit(0 if failures.is_empty() else 1)
