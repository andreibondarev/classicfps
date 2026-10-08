extends SceneTree

## Staged host-Game objective integration, not team admission or client rendering.
const RoundScript = preload("res://scripts/cs16_round_state.gd")
var failures: Array[String] = []
var game: Node
var network: Node
var sequence := 0
var input_time := 1000
var defuse_audio: Array[Dictionary] = []


func _record_defuse_audio(event: Dictionary) -> void:
	if event.event_name in ["c4.disarm", "c4.disarmed"]:
		defuse_audio.append(event)


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _input(human: PlayerController, buttons: int) -> void:
	sequence += 1
	input_time += 10
	var packet: Dictionary = network.sanitize_input({"movement": Vector2.ZERO, "buttons": buttons}, sequence)
	_check(network.accept_peer_input(99, packet, input_time), "registered peer input accepted")
	human.last_command = human.combat_controller.gather_command(0.01)


func _step() -> void:
	game.round_state.advance_tick(game._round_tick_command())
	game._consume_new_round_trace()
	game._sync_round_public_state()


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "objective fixture must be silent")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	game.audio_router.event_started.connect(_record_defuse_audio)
	game.player.set_physics_process(false)
	for bot in game._all_bots():
		bot.set_physics_process(false)
		bot.active = false
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	network._register_input_peer(99, 1000)
	game.remote_roster._on_peer_joined(99)
	var human: PlayerController = game.remote_roster.actor_for_peer(99)
	var actor_id: String = game.remote_roster.id_for_actor(human)
	_input(human, 17)
	_check(not game._human_objective_pressed(human, "fire") and not game._human_objective_pressed(human, "use"),
		"pending pawn cannot act even with held remote buttons")
	game._apply_round_phase(RoundScript.PHASE_LIVE)
	_check(not human.controls_enabled and not human.look_enabled and not human.is_physics_processing(),
		"phase changes do not admit a pending human")
	game._apply_round_phase(RoundScript.PHASE_POST)
	_check(not human.can_simulate_movement(), "post countdown cannot move an unadmitted human")
	game._apply_round_phase(RoundScript.PHASE_LIVE)
	# Explicitly stage an admitted row/body to exercise the downstream seam.
	# No new team/class protocol or admission policy is claimed by this fixture.
	human.configure_identity(Combatant.TEAM_TERRORIST, "Objective Human")
	human.alive = true
	var row: Dictionary = game.round_state.players[actor_id]
	row.team = Combatant.TEAM_TERRORIST
	row.alive = true
	row.choosing_appearance = false
	for id: String in game.round_state.players:
		game.round_state.players[id].has_c4 = id == actor_id
	game.round_state.bomb_owner = actor_id
	game.round_state.bomb_state = RoundScript.BOMB_CARRIED
	game._sync_round_public_state()
	game._apply_round_phase(RoundScript.PHASE_LIVE)
	_check(human.owns_weapon("c4") and not game.player.owns_weapon("c4"), "C4 inventory follows remote actor identity")
	game._apply_round_phase(RoundScript.PHASE_FREEZE)
	_check(not human.controls_enabled and human.look_enabled and not game._human_objective_pressed(human, "fire"),
		"freeze withholds remote objective attacks while retaining look")
	game._apply_round_phase(RoundScript.PHASE_LIVE)
	human.switch_weapon("c4")
	human.weapon_clock.advance_tick(100)
	human.global_position = game.bomb_sites[0]
	human._movement_grounded = true
	game.player._movement_grounded = false
	var host_position: Vector3 = game.player.global_position
	var host_camera: Camera3D = root.get_camera_3d()
	_input(human, 1)
	var plant: Dictionary = game._round_tick_command().get("plant", {})
	_check(plant.get("player_id") == actor_id and plant.get("attack", false) and plant.get("grounded", false)
		and plant.get("in_bomb_site", false) and plant.get("equipped_c4", false), "remote C4 builds a human plant request without bot casting or host fire")
	_step()
	_check(game.round_state.plant_actor == actor_id and human.objective_movement_locked
		and not game.player.objective_movement_locked and human.controls_enabled, "plant locks only planter movement, retaining button sampling")
	_check(game._network_owner_feedback(human).action == "plant" and game._network_owner_feedback(game.player).action == "", "plant progress belongs only to planter snapshot")
	_input(human, 0)
	Input.action_press("fire")
	_step()
	Input.action_release("fire")
	_check(game.round_state.plant_actor == "" and not human.objective_movement_locked,
		"remote release aborts planting even while host fire is held")
	for tick in range(101):
		_step()
	_input(human, 1)
	for tick in range(int(game.round_state.config.plant_ticks) + 1):
		_step()
	_check(game.round_state.bomb_state == RoundScript.BOMB_PLANTED and game.round_state.bomb_planter_id == actor_id
		and not human.owns_weapon("c4") and not human.objective_movement_locked,
		"remote plant completes normal duration, removes inventory and unlocks movement")
	# The same staged body now exercises CT use; real side selection remains separate.
	human.configure_identity(Combatant.TEAM_COUNTER_TERRORIST, "Objective Human")
	row.team = Combatant.TEAM_COUNTER_TERRORIST
	human.global_position = game.bomb_position + Vector3(0.0, 0.0, 0.4)
	human._movement_grounded = true
	human.camera.look_at(game.bomb_position)
	_input(human, 16)
	# Host body/camera state must not supply remote range, pitch or grounding.
	# Planting above contrasts a grounded remote with an ungrounded host.
	# Defusing contrasts the reverse. Mark the staged host's floor contact so
	# its own competing +use does not independently invoke movement ground snap.
	game.player._movement_grounded = true
	var grounded_position := human.global_position
	human.global_position = Vector3(0.0, 100.0, 0.0)
	human._movement_grounded = false
	_check(not game._defuse_request(human, true).grounded, "airborne remote cannot borrow host ground contact")
	human.global_position = grounded_position
	human._movement_grounded = true
	human.camera.rotation = Vector3.ZERO
	human.camera.rotate_y(PI)
	_check(not game._defuse_request(human, true).use, "remote looking away cannot borrow host aim")
	human.camera.look_at(game.bomb_position)
	game.player.configure_identity(Combatant.TEAM_COUNTER_TERRORIST, "Player")
	Input.action_press("use")
	var defuse: Dictionary = game._round_tick_command().get("defuse", {})
	Input.action_release("use")
	_check(defuse.get("player_id") == actor_id and defuse.get("use", false) and defuse.get("grounded", false),
		"remote CT acquires C4 with its own eye/pitch/ground even when an out-of-range host holds use")
	_step()
	_check(game._active_round_defuser() == human and human.objective_movement_locked, "active remote defuser resolves through durable roster identity")
	_check(defuse_audio.size() == 1 and defuse_audio[0].sample == "weapons/c4_disarm.wav"
		and defuse_audio[0].channel == 3 and defuse_audio[0].attenuation == 0.8,
		"defuse start emits the original spatial CHAN_ITEM cue once")
	for tick in range(20):
		_step()
	_check(defuse_audio.size() == 1, "holding use does not replay the defuse-start sound")
	_check(game._network_owner_feedback(human).action == "defuse" and game._network_owner_feedback(game.player).action == "", "defuse progress belongs only to defuser snapshot")
	input_time += 250
	network.expire_inputs(input_time)
	human.last_command = human.combat_controller.gather_command(0.01)
	Input.action_press("use")
	for tick in range(RoundScript.DEFUSE_USE_REFRESH_TICKS + 1):
		_step()
	Input.action_release("use")
	_check(game.round_state.defuse_actor == "" and not human.objective_movement_locked,
		"expired remote input times out defuse after normal grace despite host use held")
	_check(defuse_audio.size() == 1, "aborted defuse never emits the success cue")
	_input(human, 16)
	for tick in range(int(game.round_state.config.defuse_ticks) + 1):
		_step()
	_check(game.round_state.bomb_state == RoundScript.BOMB_DEFUSED and game.round_state.players[actor_id].kills == 3,
		"remote defuse completes normal duration and credits its own objective score")
	_check(defuse_audio.size() == 3 and defuse_audio[1].event_name == "c4.disarm"
		and defuse_audio[2].sample == "weapons/c4_disarmed.wav" and defuse_audio[2].channel == 1,
		"restarting emits one new start cue; successful completion emits one CHAN_WEAPON cue")
	_check(not human.objective_movement_locked and not human.controls_enabled and human.can_simulate_movement(),
		"post round clears the objective lock and allows survivor movement without reopening attacks")
	_check(game._network_owner_feedback(human).result == "bomb_defused" and game._network_owner_feedback(human).action == "", "snapshot preserves defused result and clears progress")
	_check(game.player.global_position == host_position and root.get_camera_3d() == host_camera,
		"remote objectives do not move the host or take its camera: before=%s after=%s camera_before=%s camera_after=%s"
		% [host_position, game.player.global_position, host_camera, root.get_camera_3d()])
	game._update_scoreboard()
	var highlighted: Array[String] = []
	for score_row: Node in game.hud.scoreboard_rows.get_children():
		if score_row.get_meta("is_local", false):
			highlighted.append(str(score_row.get_meta("actor_id")))
	_check(highlighted == ["player"], "host scoreboard highlights only the local player, not remote humans")
	human.alive = true
	game.round_state.players[actor_id].alive = true
	human.health = 37
	game.hud.set_scoreboard_held(true)
	game._refresh_visible_scoreboard(0.2)
	var teammate_hp := ""
	for score_row: Node in game.hud.scoreboard_rows.get_children():
		if score_row.get_meta("actor_id", "") == actor_id:
			teammate_hp = score_row.get_node("Health").text
	_check(teammate_hp == "37", "held host scoreboard refreshes real teammate health")
	game._apply_round_phase(RoundScript.PHASE_FREEZE)
	_check(not human.can_simulate_movement() and not game.player.can_simulate_movement(), "next round freeze locks survivors again")
	game._apply_round_phase(RoundScript.PHASE_POST)
	_check(human.can_simulate_movement(), "returning to post permits the surviving remote player to move")
	game._apply_round_phase(RoundScript.PHASE_INTERMISSION)
	_check(not human.can_simulate_movement(), "match intermission is still locked")
	game.queue_free()
	await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_HUMAN_OBJECTIVE_TEST_PASS")
	quit(0 if failures.is_empty() else 1)
