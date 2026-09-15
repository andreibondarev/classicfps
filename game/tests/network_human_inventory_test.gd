extends SceneTree

## Staged host-Game inventory/death seam, not reliable remote action transport.
const RoundScript = preload("res://scripts/cs16_round_state.gd")
var failures: Array[String] = []
var game: Node
var network: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _stage(human: PlayerController, team: String, position: Vector3) -> void:
	var actor_id: String = game._round_id_for_actor(human)
	human.configure_identity(team, "Inventory Human " + actor_id)
	human.reset_player(position, false)
	human.controls_enabled = true
	human.collision_layer = 2
	game.round_state.players[actor_id].team = team
	game.round_state.players[actor_id].alive = true
	game.round_state.players[actor_id].choosing_appearance = false


func _gun(human: PlayerController, weapon: String, clip: int, reserve: int) -> void:
	human.grant_item(weapon)
	human.switch_weapon(weapon)
	human.clip = clip
	human.reserve = reserve


func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "inventory fixture must be silent")
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	game.start_match()
	game._begin_live()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot in game._all_bots():
		bot.set_physics_process(false)
		bot.active = false
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	network.is_host = true
	for peer_id in [99, 100, 101]:
		network._register_input_peer(peer_id, 1000)
		game.remote_roster._on_peer_joined(peer_id)
	var first: PlayerController = game.remote_roster.actor_for_peer(99)
	var second: PlayerController = game.remote_roster.actor_for_peer(100)
	var pending: PlayerController = game.remote_roster.actor_for_peer(101)
	var first_id: String = game._round_id_for_actor(first)
	var second_id: String = game._round_id_for_actor(second)
	_stage(first, Combatant.TEAM_TERRORIST, Vector3(0, 100, 0))
	_stage(second, Combatant.TEAM_COUNTER_TERRORIST, Vector3(3, 100, 0))
	var host_origin: Vector3 = game.player.global_position
	var host_camera: Camera3D = root.get_camera_3d()
	var host_weapon: String = game.player.active_weapon
	var host_clip: int = game.player.clip
	# Production pawn removes inventory and emits its bound Game drop signal.
	_gun(first, "galil", 17, 63)
	first._try_drop_active_weapon()
	_check(game.dropped_weapons.size() == 1 and not first.owns_weapon("galil"), "remote gun drop creates exactly one world item")
	var item: CS16DroppedWeapon = game.dropped_weapons[0]
	_check(item.dropper_id == first_id and item.clip_ammo == 17 and item.reserve_ammo == 63
		and item.global_position.distance_to(first.global_position) > 0.25, "drop retains remote identity, live ammo and its own forward toss")
	game._process_weapon_pickups()
	_check(not first.owns_weapon("galil") and not item.pickup_armed, "dropper cannot immediately vacuum its gun back")
	pending.global_position = item.global_position
	game._process_weapon_pickups()
	_check(not pending.owns_weapon("galil") and game.dropped_weapons.size() == 1, "pending pawn cannot collect a gun")
	second.global_position = item.global_position
	game._process_weapon_pickups()
	_check(second.owns_weapon("galil") and second.clip == 17 and second.reserve == 63
		and game.dropped_weapons.is_empty(), "another human can pick up immediately while original dropper still overlaps")
	# Only the actual dropper's departure from the radius rearms self pickup.
	_gun(first, "ak47", 9, 42)
	first._try_drop_active_weapon()
	item = game.dropped_weapons[0]
	game.player.global_position = item.global_position + Vector3(30, 0, 0)
	game._process_weapon_pickups()
	_check(not item.pickup_armed and not first.owns_weapon("ak47"), "host position does not rearm a remote drop")
	first.global_position += Vector3(2, 0, 0)
	game._process_weapon_pickups()
	_check(item.pickup_armed, "remote dropper leaving rearms its own item")
	first.global_position = item.global_position
	game._process_weapon_pickups()
	_check(first.owns_weapon("ak47") and first.clip == 9 and first.reserve == 42, "remote can return and recover exact ammo")
	game.player.global_position = host_origin
	# Two simultaneous eligible touches claim once in stable human order.
	first._try_drop_active_weapon()
	game._clear_dropped_weapons()
	second._try_drop_active_weapon()
	game._clear_dropped_weapons()
	game._spawn_weapon_drop("m4a1", 11, 38, first.global_position, Vector3.ZERO)
	second.global_position = first.global_position
	game._process_weapon_pickups()
	game._process_weapon_pickups()
	_check(first.owns_weapon("m4a1") and not second.owns_weapon("m4a1") and game.dropped_weapons.is_empty(), "simultaneous pickup has one deterministic winner and cannot duplicate")
	game._spawn_weapon_drop("ak47", 5, 20, first.global_position, Vector3.ZERO)
	second.global_position += Vector3(5, 0, 0)
	game._process_weapon_pickups()
	_check(first.owns_weapon("m4a1") and not first.owns_weapon("ak47") and game.dropped_weapons.size() == 1, "occupied slot is not replaced automatically")
	game._clear_dropped_weapons()
	# Actual damage -> combatant signal -> Game death -> account/item changes.
	_gun(second, "ak47", 12, 64)
	var killer_money: int = game.round_state.players[first_id].money
	var notice_count: int = game.hud.kill_feed_box.get_child_count()
	_check(second.receive_bullet_damage(200, 1, "m4a1", second.aim_point(), first), "opposing human receives lethal headshot")
	_check(not second.alive and second.collision_layer == 0 and not game.round_state.players[second_id].alive
		and game.round_state.players[second_id].deaths == 1 and game.round_state.players[first_id].kills == 1
		and game.round_state.players[first_id].money == killer_money + 300, "remote death updates only victim and real killer round accounts")
	_check(game.dropped_weapons.size() == 1 and game.dropped_weapons[0].weapon_name == "ak47"
		and game.dropped_weapons[0].clip_ammo == 12 and game.dropped_weapons[0].reserve_ammo == 64
		and game.dropped_weapons[0].dropper_id == second_id, "remote death drops its own carried gun and live ammunition")
	_check(second.character_model.animation_state == "die", "ordinary remote death retains corpse presentation")
	_check(not second.character_model.weapon_instance.visible
		and not is_instance_valid(second.character_model.dropped_weapon_instance),
		"remote corpse has neither a held gun nor a decorative duplicate of the pickup")
	_check(game.hud.kill_feed_box.get_child_count() == notice_count + 1
		and game.hud.kill_feed_box.get_child(-1).get_meta("weapon_icon") == "m4a1"
		and game.hud.kill_feed_box.get_child(-1).get_meta("headshot"), "human kill notice retains attacker's weapon and headshot icons")
	game._on_human_died(second, true)
	_check(game.dropped_weapons.size() == 1 and game.round_state.players[second_id].deaths == 1
		and game.round_state.players[first_id].kills == 1, "duplicate death callback cannot duplicate gun, score or reward")
	_check(game.player.global_position == host_origin and root.get_camera_3d() == host_camera
		and not game.spectator_camera.is_engaged()
		and game.player.active_weapon == host_weapon and game.player.clip == host_clip, "remote inventory/death does not alter host inventory, position or spectator camera")
	game._clear_dropped_weapons()
	# Manual and death C4 paths resolve the remote owner, not the host row.
	for actor_id: String in game.round_state.players:
		game.round_state.players[actor_id].has_c4 = actor_id == first_id
	game.round_state.bomb_owner = first_id
	game.round_state.bomb_state = RoundScript.BOMB_CARRIED
	game._sync_round_public_state()
	first.switch_weapon("c4")
	_check(not game._request_human_c4_drop(pending) and game._request_human_c4_drop(first)
		and is_instance_valid(game.dropped_c4) and not first.owns_weapon("c4"), "manual C4 drop validates actual remote ownership")
	game.round_state.bomb_position = first.global_position
	game._on_dropped_c4_pickup(first)
	_check(game.round_state.bomb_owner == first_id and first.owns_weapon("c4"), "remote C4 pickup restores only its own inventory")
	first.switch_weapon("c4")
	_stage(second, Combatant.TEAM_COUNTER_TERRORIST, Vector3(4, 100, 0))
	first.receive_bullet_damage(200, 1, "usp", first.aim_point(), second)
	_check(game.round_state.bomb_state == RoundScript.BOMB_DROPPED and is_instance_valid(game.dropped_c4)
		and not first.owns_weapon("c4") and game.dropped_weapons.size() == 1
		and game.dropped_weapons[0].weapon_name == "m4a1", "dead remote C4 holder releases bomb and best carried gun")
	_check(first.character_model.animation_state == "die", "C4 inventory cleanup must not revive remote corpse animation")
	_check(not is_instance_valid(first.character_model.dropped_weapon_instance),
		"dead C4 holder's weapon refresh does not create a second gun")
	game._clear_dropped_weapons()
	# A reconnect may reuse a slot, but never the old dropper suppression ID.
	_gun(second, "galil", 7, 19)
	second._try_drop_active_weapon()
	item = game.dropped_weapons[0]
	var old_audio := second.audio_entity_id()
	network._remove_input_peer(100)
	network.peer_left.emit(100)
	network._register_input_peer(100, 1000)
	game.remote_roster._on_peer_joined(100)
	var replacement: PlayerController = game.remote_roster.actor_for_peer(100)
	_stage(replacement, Combatant.TEAM_COUNTER_TERRORIST, item.global_position)
	_check(replacement.audio_entity_id() == old_audio and game._round_id_for_actor(replacement) != item.dropper_id, "replacement reuses slot but not old dropper identity")
	game._process_weapon_pickups()
	_check(replacement.owns_weapon("galil") and replacement.clip == 7 and replacement.reserve == 19
		and game.dropped_weapons.is_empty(), "departed dropper cannot strand its ground gun or suppress a replacement")
	game.queue_free()
	await process_frame
	network.disconnect_session()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_HUMAN_INVENTORY_TEST_PASS")
	quit(0 if failures.is_empty() else 1)
