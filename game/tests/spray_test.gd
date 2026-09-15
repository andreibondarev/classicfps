extends SceneTree

const Spray = preload("res://scripts/cs16_spray.gd")
var failures: Array[String] = []
var spray_sounds := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _run() -> void:
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	game.start_match()
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for bot: TargetActor in game._all_bots():
		bot.set_physics_process(false)
	game.audio_router.event_started.connect(func(event: Dictionary) -> void:
		if event.event_name == "player.spray": spray_sounds += 1)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(4, 3, 0.1)
	wall.add_child(shape)
	game.add_child(wall)
	wall.position = Vector3(0, 100, 0)
	await physics_frame
	var painter: CS16Spray = game.sprays
	_check(not painter.placement(Vector3(0, 100, 1), Vector3.FORWARD, []).is_empty(), "close flat wall accepts spray")
	_check(painter.placement(Vector3(0, 100, 3), Vector3.FORWARD, []).is_empty(), "range is limited")
	_check(painter.placement(Vector3(1.9, 100, 1), Vector3.FORWARD, []).is_empty(), "unsupported wall-edge footprint is rejected")
	wall.set_meta("model_index", 2)
	_check(painter.placement(Vector3(0, 100, 1), Vector3.FORWARD, []).is_empty(), "moving/breakable brush models are rejected")
	wall.set_meta("model_index", 0)
	var player: PlayerController = game.player
	player.global_position = Vector3(0, 100 - PlayerController.STAND_EYE, 0.8)
	player.camera.global_rotation = Vector3.ZERO
	var key := InputEventKey.new()
	key.keycode = KEY_T
	key.pressed = true
	game._unhandled_input(key)
	_check(painter.records.size() == 1 and spray_sounds == 1, "T places one spray and plays original sprayer sound")
	game._unhandled_input(key)
	_check(painter.records.size() == 1 and spray_sounds == 1, "cooldown suppresses repeat decal and sound")
	key.echo = true
	painter._cooldowns.clear()
	game._unhandled_input(key)
	_check(painter.records.size() == 1, "held-key echo does not repeat spray")
	key.echo = false
	game.hud.set_paused_visible(true)
	game._unhandled_input(key)
	_check(painter.records.size() == 1, "open menu does not paint")
	game.hud.set_paused_visible(false)
	player.alive = false
	_check(not game._spray_for_human(player), "dead players cannot spray")
	player.alive = true
	player.team = "UNASSIGNED"
	_check(not game._spray_for_human(player), "spectators cannot spray")
	player.team = "T"
	_test_remote_spray(game)
	var records: Array = painter.records.duplicate(true)
	var replica := Spray.new()
	game.add_child(replica)
	replica.apply_records(records)
	var first: Node = replica._nodes[records[0].id]
	replica.apply_records(records)
	_check(replica._nodes.size() == records.size() and replica._nodes[records[0].id] == first, "late join/repeated snapshots retain exactly one node per spray")
	var malformed: Array = records.duplicate(true)
	malformed[0].normal = Vector3.ZERO
	_check(not Spray.valid_records(malformed) and not Spray.valid_records([records[0], records[0]]), "reject malformed normals and duplicate IDs")
	var texture: Texture2D = painter._material.albedo_texture
	var image := texture.get_image()
	_check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(image.get_width() / 2, image.get_height() / 2).a > 0.0, "generated spray retains genuine alpha and visible paint")
	for index in 34:
		_check(painter.try_place(player, 1000000 + index * Spray.COOLDOWN_MS), "cooldown permits subsequent placement")
	_check(painter.records.size() == Spray.MAX_SPRAYS and painter._nodes.size() == Spray.MAX_SPRAYS, "spray history and meshes are bounded")
	game._reset_combatants_for_round()
	_check(painter.records.is_empty() and painter._nodes.is_empty(), "next round clears sprays")
	replica.apply_records([])
	_check(replica._nodes.is_empty(), "authoritative empty snapshot removes client sprays")
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_dust2(game)
	game.queue_free()
	await process_frame
	MdlCharacterModel.release_cached_resources()
	for failure in failures:
		push_error(failure)
	print("GAME_SPRAY_PASS" if failures.is_empty() else "GAME_SPRAY_FAIL")
	quit(0 if failures.is_empty() else 1)


func _test_remote_spray(game: Node) -> void:
	var session := root.get_node("NetworkSession")
	session.is_host = true
	var now := Time.get_ticks_msec()
	session._register_input_peer(77, now)
	game.remote_roster._on_peer_joined(77)
	var human: PlayerController = game.remote_roster.actor_for_peer(77)
	human.team = "T"
	human.alive = true
	human.look_enabled = true
	human.global_position = Vector3(0, 100 - PlayerController.STAND_EYE, 0.8)
	human.camera.global_rotation = Vector3.ZERO
	var local_layer: int = game.player.collision_layer
	game.player.collision_layer = 0
	var count: int = game.sprays.records.size()
	var packet := {"version": session.PROTOCOL_VERSION, "sequence": 1, "action": "spray", "value": ""}
	var result: Dictionary = session.accept_peer_action(77, packet, now)
	_check(result.get("accepted", false) and game.sprays.records.size() == count + 1, "registered remote spray uses host-owned eye ray and independent cooldown")
	_check(session.accept_peer_action(77, packet, now).is_empty(), "replayed spray action cannot duplicate decal")
	packet.sequence = 2
	packet.value = {"position": Vector3.ZERO, "actor": "player"}
	_check(session.validate_action(packet).is_empty(), "client cannot supply spray position or another owner")
	session._remove_input_peer(77)
	game.remote_roster._on_peer_left(77)
	session.is_host = false
	game.player.collision_layer = local_layer


func _capture_dust2(game: Node) -> void:
	var player: PlayerController = game.player
	var origin: Vector3 = game.player_spawn + Vector3.UP * PlayerController.STAND_EYE
	var placed := false
	for index in 32:
		var direction := Vector3(sin(index * TAU / 32), 0, cos(index * TAU / 32))
		var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * 5.0, 1))
		if hit.is_empty(): continue
		var view: Vector3 = hit.position + hit.normal * 0.9
		var placement: Dictionary = game.sprays.placement(view, -hit.normal)
		if placement.is_empty(): continue
		player.global_position = view - Vector3.UP * PlayerController.STAND_EYE
		player.camera.look_at(hit.position)
		player.camera.make_current()
		game.sprays._cooldowns.clear()
		placed = game._spray_for_human(player)
		if placed: break
	_check(placed, "find and spray an actual Dust2 wall")
	game.hud.banner_label.hide()
	for frame in 5:
		await process_frame
		RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png("/tmp/protocol47-dust2-spray.png") == OK, "save native Dust2 spray capture")
