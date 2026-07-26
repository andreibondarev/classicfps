extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const TargetScript = preload("res://scripts/target.gd")
const HUDScript = preload("res://scripts/hud.gd")
const BspMapScript = preload("res://scripts/bsp_map.gd")

const FREEZE_SECONDS := 4.0
const ROUND_SECONDS := 115.0
const BOMB_SECONDS := 35.0
const PLANT_SECONDS := 3.2
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
var bomb_sites: Array[Vector3] = []
var imported_map: BspMap
var player_spawn := FALLBACK_PLAYER_SPAWN
var allied_spawns: Array[Vector3] = []
var target_spawns: Array[Vector3] = []
var using_imported_map := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_environment()
	get_node("/root/GameSettings").changed.connect(_apply_performance_settings)
	if not _build_imported_map():
		_build_arena()
		allied_spawns.assign(FALLBACK_ALLIED_SPAWNS)
		target_spawns.assign(FALLBACK_TARGET_SPAWNS)
	_spawn_player()
	_spawn_targets()
	_build_bomb_sites()
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
	player_spawn = terrorist_spawns[0]
	for spawn_index in range(5):
		target_spawns.append(ct_spawns[spawn_index])
	for spawn_index in range(1, 5):
		allied_spawns.append(terrorist_spawns[spawn_index])
	using_imported_map = true
	return true


func _process(delta: float) -> void:
	if not match_started or round_ending or get_tree().paused:
		return
	seconds_left = max(0.0, seconds_left - delta)
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	match phase:
		"freeze":
			if seconds_left <= 0.0:
				_begin_live()
		"live":
			_update_planting(delta)
			if seconds_left <= 0.0:
				_end_round(false, "COUNTER-TERRORISTS WIN")
		"bomb":
			if seconds_left <= 0.0:
				_explode_bomb()


func _physics_process(delta: float) -> void:
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if not match_started:
			return
		_set_paused(not get_tree().paused)
	elif event is InputEventKey and event.pressed and not event.echo and phase == "freeze":
		match event.keycode:
			KEY_F1:
				_buy("ak47", 2500, "AK-47")
			KEY_F2:
				_buy("deagle", 650, "DESERT EAGLE")
			KEY_F3:
				_buy("armor", 1000, "KEVLAR + HELMET")
			KEY_F4:
				_buy("hegrenade", 300, "HE GRENADE")


func _buy(item: String, price: int, label: String) -> void:
	if money < price:
		hud.show_banner("NOT ENOUGH MONEY", Color("#ff6a62"), 0.75)
		return
	money -= price
	if item == "armor":
		player.refill_armor()
	else:
		player.refill_weapon(item)
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	hud.show_banner("PURCHASED  %s" % label, Color("#77e3ae"), 0.65)


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


func _build_bomb_sites() -> void:
	bomb_sites.clear()
	if using_imported_map:
		bomb_sites.append(Vector3(11.52, 1.52, -24.64))
		bomb_sites.append(Vector3(-15.36, 0.56, -26.88))
	else:
		bomb_sites.append(Vector3(-11, 2.58, -23))
		bomb_sites.append(Vector3(11, 2.58, -23))
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
	_begin_freeze()


func _begin_freeze() -> void:
	phase = "freeze"
	seconds_left = FREEZE_SECONDS
	plant_progress = 0.0
	player.controls_enabled = false
	for target in _all_bots():
		target.active = false
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	hud.show_banner("FREEZE TIME  •  PREPARE TO MOVE", Color("#77d9ff"), 1.4)


func _begin_live() -> void:
	phase = "live"
	seconds_left = ROUND_SECONDS
	player.controls_enabled = player.alive
	for target in _all_bots():
		if target.alive:
			target.active = true
	hud.show_banner("LIVE  •  ELIMINATE OR PLANT", Color("#77e3ae"), 1.25)


func _on_target_damaged(_target: TargetActor, _health: int, headshot: bool) -> void:
	if headshot:
		hud.show_banner("HEADSHOT", Color("#ffca66"), 0.55)


func _on_target_died(target: TargetActor, headshot: bool) -> void:
	if round_ending:
		return
	if target.team == Combatant.TEAM_COUNTER_TERRORIST:
		kills += 1
		money = mini(16000, money + 300)
		hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
		hud.show_banner(
			"HOSTILE DOWN%s" % ("  •  HEADSHOT" if headshot else ""),
			Color("#ffca66"),
			0.7,
		)
	_check_team_elimination()


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
	_check_team_elimination()


func _check_team_elimination() -> void:
	if round_ending:
		return
	if not _team_has_survivors(Combatant.TEAM_COUNTER_TERRORIST):
		_end_round(true, "TERRORISTS WIN")
	elif not bomb_planted and not _team_has_survivors(Combatant.TEAM_TERRORIST):
		_end_round(false, "COUNTER-TERRORISTS WIN")


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
	if round_ending:
		return
	round_ending = true
	phase = "post"
	match_started = false
	player.controls_enabled = false
	for target in _all_bots():
		target.active = false
	if won:
		terrorist_score += 1
		money = mini(16000, money + 3250)
	else:
		ct_score += 1
		money = mini(16000, money + 1400)
	hud.update_match(round_number, phase, 0.0, ct_score, terrorist_score, money)
	hud.show_banner(reason, Color("#77e3ae") if won else Color("#ff6a62"), 2.0)
	await get_tree().create_timer(2.6).timeout
	_reset_round()


func _reset_round() -> void:
	round_number += 1
	kills = 0
	seconds_left = ROUND_SECONDS
	round_ending = false
	bomb_planted = false
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
	hud.update_match(round_number, phase, seconds_left, ct_score, terrorist_score, money)
	start_match()


func _update_planting(delta: float) -> void:
	if not player.alive:
		hud.update_objective("TEAMMATES STILL FIGHTING")
		return
	var site := _nearest_bomb_site()
	var can_plant := site != Vector3.INF and player.global_position.distance_to(site) <= 2.35
	if can_plant and player.last_command.get("use", false):
		plant_progress = minf(PLANT_SECONDS, plant_progress + delta)
		hud.update_objective("PLANTING  %d%%" % int(plant_progress / PLANT_SECONDS * 100.0))
		if plant_progress >= PLANT_SECONDS:
			_plant_bomb(site)
	else:
		plant_progress = 0.0
		hud.update_objective("HOLD E TO PLANT" if can_plant else "ELIMINATE OR PLANT")


func _nearest_bomb_site() -> Vector3:
	var nearest := Vector3.INF
	var nearest_distance := INF
	for site in bomb_sites:
		var candidate := player.global_position.distance_to(site)
		if candidate < nearest_distance:
			nearest_distance = candidate
			nearest = site
	return nearest


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
	hud.show_banner("THE BOMB HAS BEEN PLANTED", Color("#ff9e68"), 1.8)
	hud.update_objective("DEFEND THE BOMB")


func _explode_bomb() -> void:
	if not bomb_planted:
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color("#ff8b38")
	flash.light_energy = 12.0
	flash.omni_range = 18.0
	bomb.add_child(flash)
	_end_round(true, "TARGET BOMBED  •  TERRORISTS WIN")
