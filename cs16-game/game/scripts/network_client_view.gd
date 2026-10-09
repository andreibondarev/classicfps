extends Node3D

## Client-only presentation/input adapter. Reuses the existing map, HUD,
## local camera and character models; never runs a second match simulation.
const CharacterModel = preload("res://scripts/mdl_character_model.gd")
const KeyBindings := preload("res://scripts/cs16_key_bindings.gd")
const C4World = preload("res://scripts/cs16_c4_world.gd")
const MovementPrediction = preload("res://scripts/network_movement_prediction.gd")
const CombatEvents = preload("res://scripts/network_combat_events.gd")
const Grenade = preload("res://scripts/grenade.gd")
const SmokeView = preload("res://scripts/network_smoke_view.gd")
const WebVoiceScript = preload("res://scripts/web_voice.gd")
var _feedback_action := ""
var _feedback_result := ""
var _plant_drop_played := false
signal combat_presented(event: Dictionary)
var _pending_combat: Array[Dictionary] = []
var _audio_entities: Dictionary = {}
var _next_audio_entity := 10000
var presented_combat_counts: Dictionary = {}
var movement_prediction := MovementPrediction.new()
var game: Node
var session: Node
## Browser push-to-talk voice (inert off the web).
var voice: Node
var actors: Dictionary = {}
var items: Dictionary = {}
var snapshot: Dictionary = {}
var owner_id := ""
var _epoch := -1
var _owner_life := -1
var _pending_selection := 0
var _pending_buys: Dictionary = {}
var _received_ms := 0


func bind_game(owner_game: Node, network: Node) -> void:
	game = owner_game
	session = network
	process_mode = Node.PROCESS_MODE_ALWAYS
	voice = WebVoiceScript.new()
	voice.name = "WebVoice"
	voice.session = session
	add_child(voice)
	if not session.voice_received.is_connected(_on_voice_received):
		session.voice_received.connect(_on_voice_received)
	var settings := get_node("/root/GameSettings")
	if not settings.changed.is_connected(_apply_voice_settings):
		settings.changed.connect(_apply_voice_settings)
	_apply_voice_settings()
	if not game.hud.voice_test_requested.is_connected(_on_voice_test_requested):
		game.hud.voice_test_requested.connect(_on_voice_test_requested)
	game.player.network_read_only = true
	game.player.set_physics_process(false)
	game.player.collision_layer = 0
	game.player.collision_mask = 0
	game.player.alive = false
	game.player.controls_enabled = false
	game.player.look_enabled = false
	game.player.weapon_anchor.visible = false
	# Remove any pre-existing offline bots without death/disconnect gameplay.
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
		game.remove_child(bot)
		bot.queue_free()
	game.allied_bots.clear()
	game.targets.clear()
	for hostage: Node3D in game.hostage_actors.values():
		hostage.set_physics_process(false)
		hostage.visible = false
	game._clear_dropped_weapons()
	game._clear_dropped_c4()
	for grenade: Node in get_tree().get_nodes_in_group("live_grenades"):
		grenade.queue_free()
	game.combat_effects.clear_smoke_clouds()
	if is_instance_valid(game.bomb):
		game.bomb.queue_free()
		game.bomb = null
	game.spectator_camera.stop()
	session.world_snapshot_received.connect(apply_snapshot)
	session.combat_event_received.connect(queue_combat_event)
	session.action_result_received.connect(_on_action_result)
	session.status_changed.connect(_on_status)
	if not session.latest_world_snapshot.is_empty():
		apply_snapshot(session.latest_world_snapshot)


func _clear_actors() -> void:
	game.sprays.clear()
	game.audio_router.stop_all("network_world_reset")
	_feedback_action = ""
	_feedback_result = ""
	_plant_drop_played = false
	game.hud.set_network_flash(0.0, 0.0)
	game.hud.update_defuse_progress(false, 0.0, 0.0)
	_audio_entities.clear()
	_next_audio_entity = 10000
	for record: Dictionary in actors.values():
		record.body.alive = false
		record.body.queue_free()
	actors.clear()
	for record: Dictionary in items.values():
		record.body.queue_free()
	items.clear()


func _on_status(_status: String) -> void:
	if session.is_online() or session.is_connecting():
		return
	_clear_actors()
	snapshot.clear()
	owner_id = ""
	_epoch = -1
	_owner_life = -1
	_pending_selection = 0
	_pending_buys.clear()
	_pending_combat.clear()
	_feedback_action = ""
	_feedback_result = ""
	game.hud.set_network_flash(0.0, 0.0)
	game.hud.update_objective("")
	presented_combat_counts.clear()
	movement_prediction.clear()
	game.player.alive = false
	game.player.controls_enabled = false
	game.player.look_enabled = false
	game.player.weapon_anchor.visible = false
	game.spectator_camera.stop()
	game.hud.show_banner("DISCONNECTED", Color("#ffca66"), 10.0)
	game.hud.set_buy_menu_visible(false)
	game.hud.set_buy_zone(false)
	game.hud.update_defuse_kit("", false, false)
	game.hud.update_bomb_carrier(false, false)
	if is_instance_valid(voice):
		voice.set_transmitting(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_voice_settings() -> void:
	if not is_instance_valid(voice):
		return
	var settings := get_node("/root/GameSettings")
	voice.set_receive_volume(settings.voice_receive_gain())
	voice.set_transmit_gain(settings.voice_transmit_gain())
	if not bool(settings.voice_enabled):
		voice.set_transmitting(false)


func _on_voice_test_requested() -> void:
	if is_instance_valid(voice) and voice.available():
		voice.open_microphone()
	else:
		game.hud.show_banner("VOICE NEEDS A BROWSER WITH MICROPHONE SUPPORT", Color("#ffca66"), 2.0)


## Talking list: relayed speakers heard recently, plus yourself while sending.
func _update_voice_hud() -> void:
	if not is_instance_valid(voice) or not voice.available() or not is_instance_valid(game):
		return
	if game.hud.voice_options_visible():
		game.hud.set_mic_meter_level(voice.mic_level())
	var talking: PackedStringArray = voice.talking()
	var talkers: Array = []
	var owner_id := str(snapshot.get("owner_id", ""))
	for row: Dictionary in snapshot.get("actors", []):
		var id := str(row.get("id", ""))
		if talking.has(id) or (id == owner_id and voice.is_transmitting()):
			talkers.append({"id": id, "name": str(row.get("name", "")), "team": str(row.get("team", ""))})
	game.hud.update_voice_talkers(talkers)


func _on_voice_received(sender_id: String, sequence: int, frame: PackedByteArray) -> void:
	if is_instance_valid(voice):
		voice.play(sender_id, sequence, frame)


func apply_snapshot(state: Dictionary) -> void:
	game._on_client_world_ready(str(state.map))
	if not session.is_online():
		return
	if state.map != game.map_name:
		# Keep the current map inert; never simulate/collide against a wrong map.
		snapshot.clear()
		_clear_actors()
		game.player.alive = false
		game.hud.update_defuse_progress(false, 0.0, 0.0)
		game.hud.update_defuse_kit("", false, false)
		game.hud.update_bomb_carrier(false, false)
		game.player.look_enabled = false
		game.player.weapon_anchor.visible = false
		game.hud.show_banner("HOST MAP: " + str(state.map), Color("#ffca66"), 10.0)
		return
	var quiet_money_baseline: bool = int(state.epoch) != _epoch \
		or owner_id != str(state.owner_id) \
		or (not snapshot.is_empty() and (state.round.number < snapshot.round.number \
			or (snapshot.concluded and not state.concluded)))
	if int(state.epoch) != _epoch:
		_clear_actors()
		# Stopping spectator mode restores the previous player's HUD balance.
		# Establish the quiet network baseline after that restoration, so joining
		# a fresh epoch cannot look like a round reward.
		game.hud.reset_money_presentation()
		_epoch = int(state.epoch)
		_owner_life = -1
		movement_prediction.clear()
	if not snapshot.is_empty() and state.round.number != snapshot.round.number:
		_feedback_result = ""
		_feedback_action = ""
		for source: String in _audio_entities.keys():
			if source.begins_with("world_"):
				_stop_actor_audio(source)
	# New ownership, a fresh match or a side switch establishes a baseline;
	# it is not a reward or expense. Ordinary round payouts still animate.
	if owner_id != str(state.owner_id) or (not snapshot.is_empty() and (
		state.round.number < snapshot.round.number or (snapshot.concluded and not state.concluded))):
		game.hud.reset_money_presentation()
	snapshot = state.duplicate(true)
	_received_ms = Time.get_ticks_msec()
	owner_id = str(state.owner_id)
	game.phase = str(state.round.phase)
	game.round_number = int(state.round.number)
	game.seconds_left = float(state.round.seconds)
	game.terrorist_score = int(state.round.t_score)
	game.ct_score = int(state.round.ct_score)
	game.match_started = bool(state.started)
	game._match_concluded = bool(state.concluded)
	_apply_breakables(state.broken_brushes)
	game.sprays.apply_records(state.get("sprays", []))
	var present := {}
	for row: Dictionary in state.actors:
		if row.id == owner_id:
			if row.team != game.player.team:
				quiet_money_baseline = true
				game.hud.reset_money_presentation()
			_apply_owner(row)
			continue
		present[row.id] = true
		_apply_actor(row)
	for actor_id: String in actors.keys():
		if not present.has(actor_id):
			actors[actor_id].body.alive = false
			actors[actor_id].body.queue_free()
			actors.erase(actor_id)
	# Reviving the owner can stop spectator mode inside _apply_owner(), whose HUD
	# restoration writes the previous local balance. Re-assert the new-session
	# baseline after all ownership/view transitions, immediately before display.
	if quiet_money_baseline:
		game.hud.reset_money_presentation()
	game.hud.update_match(game.round_number, game.phase, game.seconds_left, game.ct_score, game.terrorist_score, game.money)
	game.hud.set_buy_zone(can_buy())
	game.hud.update_buy_account(game.money, game._buy_menu_context())
	if not can_buy() and game.hud.buy_overlay.visible:
		game.hud.set_buy_menu_visible(false)
	update_scoreboard()
	var spectator_target: Combatant = null
	if game.spectator_camera.is_first_person() and is_instance_valid(game.spectator_camera.target):
		spectator_target = game.spectator_camera.target
	var contacts: Array[Dictionary] = []
	for row: Dictionary in state.actors:
		if row.id != owner_id and row.team == game.player.team \
				and (not is_instance_valid(spectator_target) or row.id != spectator_target.name):
			contacts.append({"id": row.id, "position": row.position, "alive": row.alive})
	var hostages: Array[Dictionary] = []
	# Persistent world items also cover joining after the C4 was dropped/planted.
	for item: Dictionary in state.items:
		if (item.kind == "dropped_c4" and state.feedback.bomb_state == "dropped") or (item.kind == "planted_c4" and state.feedback.bomb_state == "planted"):
			contacts.append_array(CS16RadarDisplay.bomb_contact(game.player.team, game.player.alive,
				"dropped" if item.kind == "dropped_c4" else "planted", item.position))
	var observer_position: Vector3 = (
		spectator_target.global_position if is_instance_valid(spectator_target)
		else game.player.global_position
	)
	var observer_yaw: float = (
		spectator_target.global_rotation.y if is_instance_valid(spectator_target)
		else game.player.global_rotation.y
	)
	game.hud.update_tactical_display(observer_position, observer_yaw, contacts, hostages)
	_apply_items(state.items)
	_apply_feedback(state.feedback)
	_drain_combat_events()
	for actor_id: String in _audio_entities.keys():
		if actor_id.begins_with("world_"):
			var active := false
			for voice: Dictionary in game.audio_router.active_voices():
				active = active or voice.entity_id == _audio_entities[actor_id]
			if not active:
				_audio_entities.erase(actor_id)
			continue
		if actor_id != owner_id and not present.has(actor_id):
			_stop_actor_audio(actor_id)


func _stop_actor_audio(actor_id: String) -> void:
	if not _audio_entities.has(actor_id):
		return
	for voice: Dictionary in game.audio_router.active_voices():
		if voice.entity_id == _audio_entities[actor_id]:
			game.audio_router.stop_voice(voice.voice_id, "network_actor_reset")
	_audio_entities.erase(actor_id)


func queue_combat_event(event: Dictionary) -> void:
	if int(event.epoch) < _epoch:
		return
	if _pending_combat.size() >= CombatEvents.MAX_PENDING:
		_pending_combat.pop_front()
	_pending_combat.append({"event": event, "received_ms": Time.get_ticks_msec()})
	_drain_combat_events()


func _drain_combat_events() -> void:
	var waiting: Array[Dictionary] = []
	for pending: Dictionary in _pending_combat:
		var event: Dictionary = pending.event
		var max_age: int = CombatEvents.maximum_age_ticks(event.kind)
		if Time.get_ticks_msec() - int(pending.received_ms) > max_age * 10 or event.epoch < _epoch:
			continue
		if snapshot.is_empty() or event.epoch > _epoch or event.tick > snapshot.tick:
			waiting.append(pending)
			continue
		if snapshot.tick - event.tick > max_age:
			continue
		var row: Dictionary = {}
		if event.actor != "":
			for candidate: Dictionary in snapshot.actors:
				if candidate.id == event.actor:
					row = candidate
					break
			if row.is_empty() or row.life != event.life:
				continue
		elif event.life != snapshot.round.number:
			continue
		_present_combat(event, row)
	_pending_combat = waiting


func _present_combat(event: Dictionary, row: Dictionary) -> void:
	var d: Dictionary = event.data
	var local: bool = event.actor == owner_id
	var player: PlayerController = game.player
	match event.kind:
		"knife_action":
			if not row.alive or row.weapon != "knife":
				return
			if local:
				if player.active_weapon != "knife":
					return
				player._play_weapon_action(d.action)
			else:
				actors[event.actor].model.play_action("shoot")
		"grenade_action":
			if not row.alive:
				return
			if local:
				if player.active_weapon != d.weapon:
					return # A late throw must never replace the newly equipped gun.
				player._play_weapon_action(d.action)
			elif d.action == "throw":
				actors[event.actor].model.play_action("throw")
		"shot", "reload":
			if not row.alive or row.weapon != d.weapon:
				return
			var action := "fire" if event.kind == "shot" else "reload"
			if local:
				if action == "fire" and d.weapon in ["usp", "m4a1"]:
					player.viewmodel._start_animation("shoot1" if bool(player.weapon_modes.get(d.weapon, false)) else "shoot1_unsil", false)
				else:
					player._play_weapon_action(action)
			else:
				actors[event.actor].model.play_action("shoot" if action == "fire" else "reload")
			if event.kind == "shot":
				var origin: Vector3 = player.first_person_shot_effect_origin() if local else d.origin
				var right: Vector3 = player.camera.global_basis.x if local else d.right
				var up: Vector3 = player.camera.global_basis.y if local else d.up
				var direction: Vector3 = -player.camera.global_basis.z if local else d.direction
				game.combat_effects.spawn_weapon_shot(d.weapon, d.sequence, origin, direction, right, up)
				if local:
					player._punch_degrees = d.punch
					player._sync_view_angles()
		"audio", "world_audio":
			var source: String = "world_%d" % int(d.source) if event.kind == "world_audio" else str(event.actor)
			if not _audio_entities.has(source):
				_audio_entities[source] = _next_audio_entity
				_next_audio_entity += 1
			game.audio_router.emit_descriptor(d.name, _audio_entities[source], {
				"samples": [d.sample], "channel": d.channel, "volume": d.volume,
				"attenuation": 0.0 if local else d.attenuation,
				"pitch_min": d.pitch, "pitch_max": d.pitch},
				CS16AudioEventRouter.meters_to_hu(d.origin))
		"radio":
			game._play_radio_message(str(d.sample), str(d.sender_name), str(d.text))
		"impact":
			game.combat_effects.spawn_world_impact(d.position, d.normal, d.sequence, d.surface)
		"blood":
			game.combat_effects.spawn_blood_impact(d.position, d.normal, d.sequence)
		"blood_decal":
			game.combat_effects.spawn_blood_decal(d.position, d.normal, d.sequence)
		"kill":
			game.hud.add_kill_notice(d.killer, d.killer_team, d.weapon, d.victim, d.victim_team, d.headshot)
		"explosion":
			if d.weapon == "hegrenade":
				game.combat_effects.spawn_he_explosion(d.position, d.normal)
			elif d.weapon == "c4":
				game.combat_effects.spawn_c4_explosion(d.position, d.normal, d.underwater)
			else:
				game.combat_effects._spawn_sprite("muzzleflash1", d.position, 4.0, 30.0, game.combat_effects.EVENT_MUZZLE_FLASH, 0, true)
	presented_combat_counts[event.kind] = int(presented_combat_counts.get(event.kind, 0)) + 1
	combat_presented.emit(event)


func _apply_breakables(broken: Array) -> void:
	if game.breakable_runtime == null or not is_instance_valid(game.imported_map):
		return
	# Only map-authored breakables: never disable arbitrary BSP/world geometry,
	# run local damage/target chains, or replay explosions for a late join.
	for model: int in game.breakable_runtime.model_indices():
		var active := not broken.has(model)
		if game.imported_map.model_runtime_active(model) != active:
			game.imported_map.set_model_runtime_active(model, active)


func _apply_items(rows: Array) -> void:
	var present := {}
	for row: Dictionary in rows:
		present[row.id] = true
		if items.has(row.id) and (items[row.id].kind != row.kind or items[row.id].weapon != row.weapon):
			items[row.id].body.queue_free()
			items.erase(row.id)
		if not items.has(row.id):
			# Models only: no pickup areas, collision bodies, damage or bomb logic.
			var body := Node3D.new()
			body.name = "WorldItem_%d" % int(row.id)
			var visual: Node3D
			if row.kind == "planted_c4":
				visual = C4World.create_planted_visual()
			elif row.kind == "grenade":
				visual = Grenade.create_visual(str(row.weapon))
			elif row.kind == "smoke":
				visual = SmokeView.new()
			else:
				var path: String = C4World.BACKPACK_MODEL if row.kind == "dropped_c4" else "res://generated/world_weapons/%s/model.json" % str(row.weapon)
				visual = C4World.create_source_model(path, "WorldModel")
			body.add_child(visual)
			add_child(body)
			body.global_position = row.position
			body.global_basis = Basis(row.rotation)
			if row.kind == "smoke":
				visual.set_physics_process(false)
				visual.configure(row.position, int(row.id), float(row.total - row.remaining))
			items[row.id] = {"body": body, "visual": visual, "kind": row.kind, "weapon": row.weapon}
		var record: Dictionary = items[row.id]
		record.from = record.body.global_position
		record.to = row.position
		record.rotation_from = record.body.global_basis.get_rotation_quaternion()
		record.rotation_to = row.rotation
		record.elapsed = 0.0
		if row.kind == "planted_c4":
			record.visual.set_countdown(float(row.total), float(row.remaining))
		elif row.kind == "smoke":
			record.visual.seek_age(float(row.total - row.remaining))
	for item_id: int in items.keys():
		if not present.has(item_id):
			items[item_id].body.queue_free()
			items.erase(item_id)


func _apply_feedback(feedback: Dictionary) -> void:
	var action := str(feedback.action)
	game.hud.update_defuse_progress(
		action == "defuse" and game.player.team == "CT" and game.player.alive,
		float(feedback.total) - float(feedback.remaining),
		float(feedback.total),
	)
	if action != _feedback_action:
		_plant_drop_played = false
		if action == "plant" and game.player.active_weapon == "c4":
			game.player.viewmodel._start_animation("pressbutton", false)
		elif _feedback_action == "plant" and game.player.active_weapon == "c4":
			game.player.viewmodel._start_animation("idle1", true)
	_feedback_action = action
	if action != "":
		var percent := int((1.0 - float(feedback.remaining) / float(feedback.total)) * 100.0)
		game.hud.update_objective("%s  %d%%" % ["PLANTING" if action == "plant" else "DEFUSING", clampi(percent, 0, 100)])
		if action == "plant" and feedback.remaining <= 0.75 and not _plant_drop_played and game.player.active_weapon == "c4":
			_plant_drop_played = true
			game.player.viewmodel._start_animation("drop", false)
	elif snapshot.concluded:
		game.hud.update_objective("MATCH OVER")
	elif feedback.bomb_state == "planted":
		game.hud.update_objective("DEFUSE THE BOMB" if game.player.team == "CT" else "DEFEND THE BOMB")
	elif feedback.can_plant:
		game.hud.update_objective("PRESS 5, THEN HOLD FIRE TO PLANT")
	else:
		game.hud.update_objective("ELIMINATE OR PLANT" if game.player.team == "T" else "ELIMINATE OR DEFUSE")
	if feedback.result != _feedback_result:
		_feedback_result = str(feedback.result)
		var labels := {"bomb_planted": "THE BOMB HAS BEEN PLANTED", "bomb_defused": "THE BOMB HAS BEEN DEFUSED",
			"bomb_exploded": "TARGET BOMBED", "t_win": "TERRORISTS WIN", "ct_win": "COUNTER-TERRORISTS WIN", "draw": "ROUND DRAW"}
		if labels.has(_feedback_result):
			game.hud.show_banner(labels[_feedback_result], Color("#ffca66"), 2.0)
	_update_flash_feedback()


func _update_flash_feedback() -> void:
	if snapshot.is_empty():
		return
	var feedback: Dictionary = snapshot.feedback
	var remaining := maxf(0.0, float(feedback.flash_remaining) - float(Time.get_ticks_msec() - _received_ms) / 1000.0)
	game.hud.set_network_flash(float(feedback.flash_total), remaining if game.player.alive else 0.0)


func _apply_owner(row: Dictionary) -> void:
	var player: PlayerController = game.player
	var prior_weapon := player.active_weapon
	var prior_reloading := player.reloading
	var prior_mode: Variant = player.weapon_modes.get(prior_weapon, false)
	var inventory: Dictionary = snapshot.inventory
	player.owned_weapons.clear()
	player.ammunition.clear()
	player.weapon_modes.clear()
	for item: Dictionary in inventory.weapons:
		player.owned_weapons[item.weapon] = true
		player.ammunition[item.weapon] = {"clip": item.clip, "reserve": item.reserve}
		player.weapon_modes[item.weapon] = item.mode
	player.previous_weapon = inventory.previous
	player.equipment = inventory.equipment.duplicate()
	var revived: bool = row.alive and (not player.alive or _owner_life != int(row.life))
	var died: bool = player.alive and not row.alive
	if revived or died:
		_stop_actor_audio(row.id)
	player.configure_identity(row.team, row.name)
	player.health = int(row.health)
	player.armor = int(row.armor)
	player.has_helmet = row.helmet
	player.alive = row.alive
	player.look_enabled = row.alive
	player.controls_enabled = false  # Only movement is predicted, never the gameplay tick.
	player.visible = row.visible
	player.camera.position.y = player.CROUCH_EYE if row.crouched else player.STAND_EYE
	if revived:
		player._yaw = float(row.angles.x)
		player._pitch = float(row.angles.y)
		player._punch_degrees = Vector2.ZERO
		player._sync_view_angles()
		game.spectator_camera.stop()
		player.camera.make_current()
		if is_instance_valid(game.deploy_camera):
			game.deploy_camera.queue_free()
			game.deploy_camera = null
	elif died:
		game.spectator_camera.schedule()
	_owner_life = int(row.life)
	if player.active_weapon != row.weapon:
		player.active_weapon = row.weapon
		player.weapon_clock.reset(row.weapon)
		player.viewmodel.load_weapon(row.weapon)
		player.viewmodel.set_silenced(bool(player.weapon_modes.get(row.weapon, false)))
		player.viewmodel.play_action("switch")
	elif prior_reloading and not row.reloading:
		player.viewmodel._start_animation(player.viewmodel._idle_animation(), true)
	player.clip = int(row.clip)
	player.reserve = int(row.reserve)
	player.reloading = row.reloading
	player.weapon_anchor.visible = row.alive
	game.money = int(row.money)
	game.selected_player_skin = row.skin
	game.selected_class_id = int(row.class_id)
	game.hud.update_health(player.health, player.armor, player.has_helmet)
	game.hud.update_defuse_kit(player.team, player.alive, bool(player.equipment.get("defuser", false)))
	# The host's feedback says when the carrier stands where planting works.
	var carrying_c4: bool = player.alive and player.owns_weapon("c4")
	game.hud.update_bomb_carrier(carrying_c4, carrying_c4 and bool((snapshot.feedback as Dictionary).get("can_plant", false)))
	game.hud.update_ammo(player.clip, player.reserve, player.reloading)
	var definition: Dictionary = player.WEAPONS[player.active_weapon]
	var mode: Variant = player.weapon_modes.get(player.active_weapon, false)
	player.viewmodel.set_silenced(bool(mode))
	var label := str(definition.mode)
	if str(definition.secondary) == "burst" and bool(mode):
		label = "BURST FIRE"
	elif str(definition.secondary) == "silencer" and bool(mode):
		label = "SILENCED"
	player.camera.fov = float(definition.zoom_levels[int(mode)]) if player.weapon_is_zoomed() else player.settings.field_of_view
	if prior_weapon == player.active_weapon and prior_mode != mode and str(definition.secondary) == "silencer":
		player.viewmodel._start_animation("add_silencer" if bool(mode) else "detach_silencer", false)
	if not revived and row.alive and prior_weapon == player.active_weapon and prior_mode != mode and str(definition.secondary) == "burst":
		player.play_fire_mode_feedback()
	game.hud.update_weapon(definition.name, label)
	movement_prediction.reconcile(player, row, snapshot.motion, int(snapshot.input_ack),
		"%d:%s:%d" % [_epoch, owner_id, int(row.life)], _received_ms)


func _apply_actor(row: Dictionary) -> void:
	if not actors.has(row.id):
		var body := Combatant.new()
		body.name = row.id
		body.network_read_only = true
		body.collision_layer = 0
		body.collision_mask = 0
		var model := CharacterModel.new()
		body.add_child(model)
		add_child(body)
		body.global_position = row.position
		actors[row.id] = {"body": body, "model": model, "row": {}, "from": row.position,
			"to": row.position, "elapsed": 0.0, "yaw_from": row.angles.x, "yaw_to": row.angles.x}
	var record: Dictionary = actors[row.id]
	var previous: Dictionary = record.row
	if not previous.is_empty() and (int(previous.life) != int(row.life) or (previous.alive and not row.alive)):
		_stop_actor_audio(row.id)
	var body: Combatant = record.body
	var model: MdlCharacterModel = record.model
	if model.skin_name != row.skin or model.weapon_name != row.weapon:
		if not model.load_character(row.skin, row.weapon):
			push_error("Could not load replicated actor model")
	if previous.is_empty() or int(previous.life) != int(row.life) or body.global_position.distance_to(row.position) > 3.0:
		body.global_position = row.position
		body.rotation.y = row.angles.x
	record.from = body.global_position
	record.to = row.position
	record.elapsed = 0.0
	record.yaw_from = body.rotation.y
	record.yaw_to = row.angles.x
	record.row = row.duplicate()
	body.configure_identity(row.team, row.name)
	body.health = int(row.health)
	body.armor = int(row.armor)
	body.alive = row.alive
	body.visible = row.visible
	body.spectator_view_pitch = row.angles.y
	body.spectator_crouched = row.crouched
	body.set_meta("spectator_weapon", row.weapon)
	body.set_meta("spectator_clip", row.clip)
	body.set_meta("spectator_reserve", row.reserve)
	body.set_meta("spectator_reloading", row.reloading)
	body.set_meta("spectator_money", row.money)
	model.set_locomotion(Vector2(row.velocity.x, row.velocity.z).length() > 0.01, row.crouched)
	model.set_aim_pitch(row.angles.y)
	if not row.alive and model.animation_state != "die":
		model.play_death()
	elif row.alive and (previous.is_empty() or not bool(previous.alive) or int(previous.life) != int(row.life)):
		model.reset_animation()
	elif row.alive and not previous.is_empty() and previous.reloading and not row.reloading:
		model.reset_animation()


var _voice_hud_elapsed := 0.0


func _process(delta: float) -> void:
	_voice_hud_elapsed += delta
	if _voice_hud_elapsed >= 0.1:
		_voice_hud_elapsed = 0.0
		_update_voice_hud()
	for record: Dictionary in actors.values():
		record.elapsed = minf(float(record.elapsed) + delta, 0.05)
		var fraction := float(record.elapsed) / 0.05
		record.body.global_position = (record.from as Vector3).lerp(record.to, fraction)
		record.body.rotation.y = lerp_angle(float(record.yaw_from), float(record.yaw_to), fraction)
	for record: Dictionary in items.values():
		record.elapsed = minf(float(record.elapsed) + delta, 0.05)
		var fraction := float(record.elapsed) / 0.05
		record.body.global_position = (record.from as Vector3).lerp(record.to, fraction)
		record.body.global_basis = Basis((record.rotation_from as Quaternion).slerp(record.rotation_to, fraction))


func tick_input(delta: float) -> void:
	_drain_combat_events()
	_update_flash_feedback()
	for record: Dictionary in items.values():
		if record.kind == "smoke":
			record.visual.advance_tick(1)
	game.player._drop_punch_angle()
	if snapshot.is_empty() or not session.is_online():
		return
	var player: PlayerController = game.player
	var command: Dictionary = player.combat_controller.gather_command(delta)
	if game._pause_menu_open() or get_tree().paused or not player.alive or Time.get_ticks_msec() - _received_ms > 1000:
		command = {}
	else:
		player._apply_command_look(command)
		var weapon := str(command.get("weapon", ""))
		if not weapon.is_empty():
			session.request_weapon(weapon)
		if bool(command.get("secondary_pressed", false)):
			session.request_secondary(player.active_weapon)
		if bool(command.get("reload", false)):
			session.request_reload(player.active_weapon)
			command.reload = false # Reliable action owns the press, not a lossy held-input pulse.
		if bool(command.get("drop", false)):
			session.request_drop(player.active_weapon)
	player.last_command = command
	var prior_sequence: int = session._input_sequence
	game._submit_network_input(command)
	if session._input_sequence > prior_sequence:
		movement_prediction.predict(player, command, session._input_sequence, delta, Time.get_ticks_msec())


func select_team(team_id: int) -> void:
	game.hud.reject_deploy_selection()  # Hold the menu until the host replies.
	if _pending_selection != 0:
		return
	if team_id == 5:
		var counts := {"T": 0, "CT": 0}
		for row: Dictionary in snapshot.get("actors", []):
			if counts.has(row.team):
				counts[row.team] += 1
		team_id = 1 if counts.T <= counts.CT else 2
	if team_id not in [1, 2]:
		game.hud.show_banner("SELECT T OR CT", Color("#ffca66"), 2.0)
		return
	_pending_selection = session.request_join_team("T" if team_id == 1 else "CT")
	if _pending_selection == 0:
		game.hud.show_banner("WAITING FOR HOST", Color("#ffca66"), 2.0)


func select_class(class_id: int) -> void:
	if _pending_selection == 0:
		_pending_selection = session.request_join_class(class_id)


func _on_action_result(result: Dictionary) -> void:
	if result.action == "spray":
		if not result.accepted:
			game.hud.show_banner("SPRAY: MOVE CLOSE TO A FLAT SURFACE • 10s COOLDOWN", Color("#ffca66"), 1.5)
		return
	if result.action == "buy_item":
		var sequence := int(result.sequence)
		var generation := int(_pending_buys.get(sequence, -1))
		_pending_buys.erase(sequence)
		if result.accepted:
			if generation >= 0:
				game.hud.complete_buy_purchase(generation)
			game.hud.show_banner("PURCHASED", Color("#77e3ae"), 0.65)
		elif result.reason == "timeout":
			game.hud.show_banner("PURCHASE UNCONFIRMED", Color("#ffca66"), 2.0)
		else:
			game._show_buy_rejection(str(result.reason))
		return
	if int(result.sequence) != _pending_selection:
		return
	_pending_selection = 0
	if not result.accepted:
		game.hud.set_deploy_visible(true)
		game.hud.show_banner(str(result.reason).replace("_", " ").to_upper(), Color("#ffca66"), 3.0)
		return
	game.hud.accept_authoritative_deploy_selection(1 if result.team == "T" else 2, int(result.class_id))
	if int(result.class_id) > 0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func can_buy() -> bool:
	return session.is_online() and not snapshot.is_empty() and bool(snapshot.can_buy) and game.player.alive \
		and game.match_started and not game._match_concluded and Time.get_ticks_msec() - _received_ms <= 1000


func buy_item(item_id: String) -> void:
	if not can_buy():
		game._show_buy_rejection("action_unavailable")
	else:
		var sequence: int = session.request_buy(item_id)
		if sequence == 0:
			game.hud.show_banner("WAITING FOR HOST", Color("#ffca66"), 2.0)
		else:
			_pending_buys[sequence] = game.hud.buy_menu_generation


func handle_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	# Options > Keyboard rebinds: a bound key reads as its command's default.
	var key := KeyBindings.canonical_keycode(event, get_node("/root/GameSettings").bindings())
	if key == KEY_K and not event.echo:
		# +voicerecord: hold to talk to your team (released keys stop it).
		if is_instance_valid(voice):
			voice.set_transmitting(event.pressed and game.match_started and not game._pause_menu_open()
				and bool(get_node("/root/GameSettings").voice_enabled)
				and game.player.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST])
		get_viewport().set_input_as_handled()
		return
	if key == KEY_TAB:
		game.hud.set_scoreboard_held(event.pressed)
	elif event.pressed and not event.echo:
		if key in [KEY_Y, KEY_U] and game.match_started \
				and not game._pause_menu_open() \
				and game.hud.current_input_contract().state in ["none", "scoreboard"]:
			game.hud.set_scoreboard_held(false)
			game.hud.open_chat(key == KEY_U)
			get_viewport().set_input_as_handled()
		elif game._handle_radio_key(key):
			get_viewport().set_input_as_handled()
		elif game.hud.handle_menu_key(event.keycode):
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			game._set_paused(not game._pause_menu_open())
		elif key == KEY_M and game.match_started and not game._pause_menu_open() and not get_tree().paused \
				and game.player.team in [Combatant.TEAM_TERRORIST, Combatant.TEAM_COUNTER_TERRORIST]:
			# Change team, as offline: the host validates the switch.
			game._close_radio_menu()
			game.hud.set_buy_menu_visible(false)
			game.hud.set_deploy_visible(true)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		elif key == KEY_T and not game._pause_menu_open() and not get_tree().paused and game.player.alive and game.match_started:
			session.submit_action("spray", "")
			get_viewport().set_input_as_handled()
		elif key == KEY_B and not game._pause_menu_open() and not get_tree().paused:
			if can_buy():
				game.hud.show_buy_menu(game._hud_team_id(), game.money, game._buy_menu_context())
			else:
				game._show_buy_rejection("action_unavailable")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_5 and not game._pause_menu_open() and not get_tree().paused and game.player.alive and game.phase == "live" and game.player.owns_weapon("c4"):
			session.request_weapon("c4")
			get_viewport().set_input_as_handled()


func update_scoreboard() -> void:
	var rows: Array = []
	var viewer_team := ""
	for actor: Dictionary in snapshot.get("actors", []):
		if str(actor.id) == owner_id:
			viewer_team = str(actor.team)
	for row: Dictionary in snapshot.get("actors", []):
		rows.append({"id": row.id, "is_local": not owner_id.is_empty() and row.id == owner_id,
			"name": row.name, "team": {"T": 1, "CT": 2}.get(row.team, 0),
			"show_private_stats": viewer_team in ["T", "CT"] and row.team == viewer_team,
			"health": row.get("health", 0), "money": row.get("money", 0),
			# No new carrier field on the wire: show only a known equipped C4,
			# or the owner's replicated inventory. Do not infer other inventories.
			"bomb": row.get("weapon", "") == "c4" or (row.id == owner_id and game.player.owns_weapon("c4")),
			"score": row.kills, "deaths": row.deaths, "alive": row.alive, "latency": 0})
	game.hud.update_scoreboard(rows, "Protocol 47", game.map_name, game.ct_score, game.terrorist_score)


func spectate_teammates() -> Array[Combatant]:
	var mates: Array[Combatant] = []
	for record: Dictionary in actors.values():
		if record.body.alive and record.body.team == game.player.team:
			mates.append(record.body)
	return mates
