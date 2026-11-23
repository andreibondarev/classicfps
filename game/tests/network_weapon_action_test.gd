extends SceneTree

var failures: Array[String] = []
var game: Node
var network: Node
var human: PlayerController
var sequence := 0
var now := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _send(action: String, weapon: String) -> Dictionary:
	sequence += 1
	now += 1000
	return network.accept_peer_action(99, {"version": 1, "sequence": sequence, "action": action, "value": weapon}, now)


func _settle() -> void:
	human._advance_weapon_simulation_tick(400)


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "weapon fixture must be silent")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	for actor: Node in game._all_bots() + game._human_players_stable():
		actor.set_physics_process(false)
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	now = Time.get_ticks_msec()
	network._register_input_peer(99, now)
	game.remote_roster._on_peer_joined(99)
	human = game.remote_roster.actor_for_peer(99)
	_check(not _send("secondary", "glock18").accepted, "pending human cannot attack")
	_check(game.select_remote_join_team(99, "T").accepted and game.select_remote_join_class(99, 1).spawned,
		"real host admission creates live human")
	human.set_physics_process(false)
	_settle()
	var host_mode: Dictionary = game.player.weapon_modes.duplicate(true)
	_check(_send("secondary", "glock18").accepted and human.weapon_modes.glock18,
		"reliable secondary selects burst on the owned host pawn")
	for event: Dictionary in game.audio_router.trace():
		_check(event.kind != "start" or event.event_name != "weapon.mode_switch",
			"remote mode change cannot play a confirmation in the host's local audio")
	var deadline: int = human.weapon_clock.next_secondary_tick
	_check(network.accept_peer_action(99, {"version": 1, "sequence": sequence, "action": "secondary", "value": "glock18"}, now).is_empty()
		and human.weapon_modes.glock18 and human.weapon_clock.next_secondary_tick == deadline, "replay cannot toggle again or reset cooldown")
	_check(_send("secondary", "glock18").reason == "action_unavailable" and human.weapon_modes.glock18,
		"new request cannot bypass weapon cooldown")
	_settle()
	human.controls_enabled = false
	_check(_send("secondary", "glock18").reason == "action_unavailable"
		and _send("drop_weapon", "glock18").reason == "action_unavailable", "freeze withholds attacks and gun drops")
	human.controls_enabled = true
	_check(_send("secondary", "glock18").accepted and not human.weapon_modes.glock18 and human.clip == 20
		and human._shot_sequence == 0 and game.player.weapon_modes == host_mode, "mode toggle cannot fire or mutate host's local pawn")
	_check(human.weapon_clock.can_primary_attack() and not human.weapon_clock.can_secondary_attack(),
		"host mode toggle locks secondary only, leaving primary ready")
	var input_now := Time.get_ticks_msec()
	var fire: Dictionary = network.sanitize_input({"movement": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0, "buttons": 1}, 1)
	_check(network.accept_peer_input(99, fire, input_now), "host accepts primary immediately after mode toggle")
	human._physics_process(0.01)
	_check(human.clip == 19 and human._shot_sequence == 1, "remote Glock fires immediately after returning to semi-auto")
	fire = network.sanitize_input({"movement": Vector2.ZERO, "yaw": 0.0, "pitch": 0.0, "buttons": 0}, 2)
	network.accept_peer_input(99, fire, input_now + 1)
	human._physics_process(0.01)
	_check(_send("reload_weapon", "glock18").reason == "action_unavailable", "reliable reload respects shot cooldown")
	_settle()
	_check(_send("reload_weapon", "glock18").accepted and human.reloading, "reliable reload starts on owned host pawn")
	_check(network.accept_peer_action(99, {"version": 1, "sequence": sequence, "action": "reload_weapon", "value": "glock18"}, now).is_empty(),
		"reliable reload replay is ignored")
	_check(_send("reload_weapon", "glock18").reason == "action_unavailable", "new reload request cannot restart active reload")
	_settle()
	_check(not human.reloading and human.clip == 20, "host completes reliable reload with normal ammunition rules")
	human.grant_item("awp")
	_check(_send("select_weapon", "awp").accepted, "select granted sniper")
	_settle()
	human._movement_grounded = true
	human.velocity = Vector3.ZERO
	human.camera.fov = 74.0
	var unzoomed_speed := human._maximum_speed(false)
	var unzoomed_spread := human._weapon_spread()
	human.camera.fov = 110.0
	_check(not human.weapon_is_zoomed() and is_equal_approx(unzoomed_speed, human._maximum_speed(false))
		and is_equal_approx(unzoomed_spread, human._weapon_spread()) and unzoomed_spread > 0.0,
		"display FOV cannot grant scoped sniper accuracy or alter authoritative movement speed")
	_check(_send("secondary", "awp").accepted and human.weapon_is_zoomed() and human.camera.fov == 40.0
		and human._weapon_spread() < unzoomed_spread and human._maximum_speed(false) < unzoomed_speed,
		"host zoom state controls scope, accuracy and movement")
	_settle()
	_check(_send("secondary", "awp").accepted and human.camera.fov == 10.0, "second zoom level")
	_settle()
	_check(_send("secondary", "awp").accepted and not human.weapon_is_zoomed(), "third click unzooms")
	_settle()
	_send("secondary", "awp")
	_send("select_weapon", "knife")
	_send("select_weapon", "awp")
	_check(not human.weapon_is_zoomed() and human.weapon_modes.awp == 0, "switching back resets authoritative zoom")
	_check(_send("secondary", "glock18").reason == "weapon_changed"
		and _send("reload_weapon", "glock18").reason == "weapon_changed"
		and _send("drop_weapon", "glock18").reason == "weapon_changed", "late action cannot apply to a different held weapon")
	human.grant_item("m4a1")
	_send("select_weapon", "m4a1")
	_settle()
	_check(human.weapon_modes.m4a1, "fresh remote M4 starts silenced")
	_check(_send("secondary", "m4a1").accepted and not human.weapon_modes.m4a1, "silencer removal reaches host")
	human.clip = 7
	human.reserve = 29
	var drops: int = game.dropped_weapons.size()
	_check(_send("drop_weapon", "m4a1").accepted and not human.owns_weapon("m4a1")
		and human.active_weapon == "glock18" and game.dropped_weapons.size() == drops + 1, "host drops exactly one owned gun and selects remaining pistol")
	var item: Node = game.dropped_weapons.back()
	_check(item.clip_ammo == 7 and item.reserve_ammo == 29 and item.dropper_id == game._round_id_for_actor(human),
		"world drop preserves exact ammo and durable dropper ownership")
	_check(network.accept_peer_action(99, {"version": 1, "sequence": sequence, "action": "drop_weapon", "value": "m4a1"}, now).is_empty()
		and game.dropped_weapons.size() == drops + 1, "drop replay cannot duplicate world item")
	_send("select_weapon", "knife")
	_settle()
	_check(_send("drop_weapon", "knife").reason == "not_droppable", "knife cannot be dropped")
	_check(_send("secondary", "knife").accepted and not human.weapon_clock.can_primary_attack(), "secondary reaches authoritative knife stab/cooldown")
	human.alive = false
	_check(_send("secondary", "knife").reason == "action_unavailable"
		and _send("drop_weapon", "knife").reason == "action_unavailable", "dead human cannot attack or drop")
	game.queue_free()
	await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_WEAPON_ACTION_PASS")
	quit(0 if failures.is_empty() else 1)
