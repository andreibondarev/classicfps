extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const HostageScript := preload("res://scripts/cs16_hostage.gd")

const GAME_SIZE := Vector2i(640, 480)
const PANEL_SIZE := Vector2i(640, 568)
const OUTPUT_ROOT := "/tmp"

var game: Node3D
var game_viewport: SubViewport
var panel_root: Control
var caption: Label
var evidence: Label
var frames: Array[Image] = []
var outputs: Array[String] = []
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_build_shell()
	await _build_live_game()
	if not failures.is_empty():
		_finish()
		return
	await _capture_live_hostage_use_and_rescue()
	await _capture_live_hostage_fire()
	await _capture_live_doors()
	await _capture_live_button_camera()
	var matrix_path := OUTPUT_ROOT.path_join(
		"protocol47-assault-live-first-person-matrix.png"
	)
	if _save_montage(frames, 3, PANEL_SIZE, matrix_path):
		outputs.append(matrix_path)
	else:
		_fail("could not save live first-person matrix")
	_finish()


func _build_shell() -> void:
	root.size = PANEL_SIZE
	root.content_scale_size = PANEL_SIZE
	panel_root = Control.new()
	panel_root.size = Vector2(PANEL_SIZE)
	root.add_child(panel_root)
	var background := ColorRect.new()
	background.color = Color("#101820")
	background.size = Vector2(PANEL_SIZE)
	panel_root.add_child(background)
	var container := SubViewportContainer.new()
	container.size = Vector2(GAME_SIZE)
	container.stretch = true
	panel_root.add_child(container)
	game_viewport = SubViewport.new()
	game_viewport.size = GAME_SIZE
	game_viewport.own_world_3d = true
	game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(game_viewport)
	var divider := ColorRect.new()
	divider.position = Vector2(0.0, 480.0)
	divider.size = Vector2(640.0, 2.0)
	divider.color = Color("#537186")
	panel_root.add_child(divider)
	caption = Label.new()
	caption.position = Vector2(14.0, 487.0)
	caption.size = Vector2(612.0, 26.0)
	caption.add_theme_font_size_override("font_size", 17)
	caption.add_theme_color_override("font_color", Color("#f2f6f8"))
	panel_root.add_child(caption)
	evidence = Label.new()
	evidence.position = Vector2(14.0, 518.0)
	evidence.size = Vector2(612.0, 45.0)
	evidence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evidence.add_theme_font_size_override("font_size", 12)
	evidence.add_theme_color_override("font_color", Color("#9dd9ff"))
	panel_root.add_child(evidence)


func _build_live_game() -> void:
	game = GameScript.new()
	game.map_name = "cs_assault"
	game_viewport.add_child(game)
	await process_frame
	await physics_frame
	await physics_frame
	_check(
		game.using_imported_map and game.hostage_actors.size() == 4,
		"production cs_assault and its four hostages load",
	)
	if not failures.is_empty():
		return
	game._on_team_selected(2)
	game._on_class_selected(1)
	for bot: Node in game.allied_bots + game.targets:
		bot.visible = false
		bot.process_mode = Node.PROCESS_MODE_DISABLED
	game.player.controls_enabled = true
	game.player.camera.fov = 90.0
	game.start_match()
	var live := false
	for _tick in 750:
		await physics_frame
		if game.phase == "live":
			live = true
			break
	_check(live, "normal round clock reaches live play after freeze time")
	game.hud.banner_label.text = ""
	game.hud.banner_label.modulate.a = 0.0


func _capture_live_hostage_use_and_rescue() -> void:
	var ids: Array = game.hostage_actors.keys()
	ids.sort()
	var hostage_id := str(ids[0])
	var hostage: CS16Hostage = game.hostage_actors[hostage_id]
	game.player.grant_item("usp")
	game.player.switch_weapon("usp")
	await _physics_ticks(100)
	game.player.camera.fov = 90.0
	_place_player(
		hostage.global_position + Vector3(0.0, 0.0, 0.53),
		hostage.source_use_origin(),
	)
	await _capture(
		"protocol47-live-hostage-01-before-use.png",
		"LIVE HOSTAGE  ·  BEFORE  ·  CT crosshair on usable hostage",
		"INPUT  normal live round · Player controls enabled · following=false",
	)
	for _attempt in 3:
		Input.action_press("use")
		await _physics_ticks(3)
		Input.action_release("use")
		await _physics_ticks(3)
		if bool(game.hostage_state.hostages[hostage_id].following):
			break
		_place_player(
			hostage.global_position + Vector3(0.0, 0.0, 0.53),
			hostage.source_use_origin(),
		)
	_check(
		bool(game.hostage_state.hostages[hostage_id].following)
		and str(game.hostage_state.hostages[hostage_id].leader_id) == "player",
		"HumanController +use starts authoritative following",
	)
	await _capture(
		"protocol47-live-hostage-02-use-action.png",
		"LIVE HOSTAGE  ·  ACTION  ·  HumanController +use / acknowledge",
		"STATE  following=true · leader=player · HUD banner from production use",
	)
	game.hud.banner_label.modulate.a = 0.0
	Input.action_press("move_back")
	await _physics_ticks(65)
	Input.action_release("move_back")
	await _physics_ticks(4)
	game.player.face_toward(hostage.source_use_origin())
	await _capture(
		"protocol47-live-hostage-03-follow.png",
		"LIVE HOSTAGE  ·  FOLLOW  ·  Player movement pulls running escort",
		"INPUT  65 live move_back ticks · no forced pose or state mutation",
	)

	# The west CT spawn selects Assault's full-height loading-dock route. The
	# east spawn's closest island is the crouch-height ventilation route, which
	# a standing hostage must never be asked to traverse.
	var rescue_position: Vector3 = game.counter_terrorist_team_spawns[3]
	var navigation_map: RID = (
		game.imported_map.navigation_region.get_navigation_map()
	)
	var raw_escort_route := NavigationServer3D.map_get_path(
		navigation_map,
		game.player.global_position,
		rescue_position,
		false,
	)
	_check(
		raw_escort_route.size() >= 20,
		"Assault navigation supplies a continuous live escort route",
	)
	# Recast exposes the split security door as disconnected moving polygons.
	# Keep its generated route on both sides, but route the live Player through
	# the authored left doorway center while the func_door physically opens.
	var escort_route := PackedVector3Array()
	for route_index in mini(6, raw_escort_route.size()):
		escort_route.append(raw_escort_route[route_index])
	escort_route.append(Vector3(-7.38, 3.40, -25.28))
	escort_route.append(Vector3(-6.56, 3.40, -25.28))
	for route_index in range(18, raw_escort_route.size()):
		escort_route.append(raw_escort_route[route_index])
	escort_route.append(rescue_position)
	var threshold_captured := false
	var rescued := false
	var printed_escort_door_open := false
	Input.action_press("walk")
	for route_index in range(1, escort_route.size()):
		var route_point: Vector3 = escort_route[route_index]
		var reached_waypoint := false
		Input.action_press("move_forward")
		for _tick in 520:
			if not is_instance_valid(hostage):
				break
			var contract: Dictionary = game.hostage_state.hostages[hostage_id]
			if bool(contract.rescued):
				rescued = true
				break
			var flat_target := Vector3(
				route_point.x,
				game.player.global_position.y,
				route_point.z,
			)
			game.player.face_toward(flat_target)
			var door_124_state := str(
				game.brush_runtime.get_brush(124).state
			)
			var door_125_state := str(
				game.brush_runtime.get_brush(125).state
			)
			if (
				not printed_escort_door_open
				and (door_124_state == "open" or door_125_state == "open")
			):
				printed_escort_door_open = true
				print(
					"ESCORT_DOOR_OPEN player=%s velocity=%s bounds124=%s bounds125=%s"
					% [
						game.player.global_position,
						game.player.velocity,
						game._brush_world_aabb(124),
						game._brush_world_aabb(125),
					]
				)
				var door_ray := PhysicsRayQueryParameters3D.create(
					Vector3(-7.24, 3.72, -25.28),
					Vector3(-6.48, 3.72, -25.28),
					1,
				)
				var door_hit: Dictionary = (
					game.player.get_world_3d().direct_space_state.intersect_ray(
						door_ray
					)
				)
				var door_collider: Object = door_hit.get("collider")
				print(
					"ESCORT_DOOR_RAY hit=%s collider=%s model=%s"
					% [
						door_hit,
						door_collider,
						(
							door_collider.get_meta("model_index", -1)
							if door_collider != null
							else -1
						),
					]
				)
			if (
				door_124_state in ["opening", "closing"]
				or door_125_state in ["opening", "closing"]
			):
				# GoldSrc players stop pushing while the split door clears their
				# hull. The next live movement tick resumes through the opening.
				Input.action_release("move_forward")
				await physics_frame
				Input.action_press("move_forward")
				continue
			await physics_frame
			var player_distance := Vector2(
				game.player.global_position.x - route_point.x,
				game.player.global_position.z - route_point.z,
			).length()
			var hostage_distance := hostage.global_position.distance_to(
				rescue_position
			)
			if (
				not threshold_captured
				and not bool(contract.rescued)
				and hostage_distance < 3.30
				and hostage_distance > 2.58
			):
				Input.action_release("move_forward")
				game.player.face_toward(hostage.source_use_origin())
				await _capture(
					"protocol47-live-rescue-01-approach.png",
					"LIVE RESCUE  ·  BEFORE  ·  follower approaches rescue radius",
					"PHYSICS  navigation escort distance=%.2f m · threshold=2.56 m"
					% hostage_distance,
				)
				Input.action_press("move_forward")
				threshold_captured = true
			# Navigation corners lie on wall seams; a GoldSrc player hull cannot
			# put its origin directly on those points. Accept one hull radius.
			var waypoint_radius := 0.85
			if player_distance <= waypoint_radius:
				reached_waypoint = true
				break
		Input.action_release("move_forward")
		if not reached_waypoint and not rescued:
			print(
				"ESCORT_STUCK waypoint=%d target=%s player=%s hostage=%s hostage_floor=%s hostage_velocity=%s hostage_blocked=%s doors=%s/%s"
				% [
					route_index,
					route_point,
					game.player.global_position,
					hostage.global_position,
					hostage.is_on_floor(),
					hostage.velocity,
					hostage._blocked_source_ticks,
					game.brush_runtime.get_brush(124).state,
					game.brush_runtime.get_brush(125).state,
				]
			)
			await _capture(
				"protocol47-live-escort-stuck-debug.png",
				"DEBUG  ·  live escort obstruction at waypoint %d"
				% route_index,
				"Player=%s · target=%s"
				% [game.player.global_position, route_point],
			)
		_check(
			reached_waypoint or rescued,
			"live Player walk reaches escort waypoint %d/%d"
			% [route_index, escort_route.size() - 1],
		)
		if rescued or not failures.is_empty():
			break
	Input.action_release("move_forward")
	Input.action_release("walk")
	if not rescued:
		for _tick in 900:
			await physics_frame
			var contract: Dictionary = game.hostage_state.hostages[hostage_id]
			var distance := hostage.global_position.distance_to(rescue_position)
			if (
				not threshold_captured
				and not bool(contract.rescued)
				and distance < 3.30
				and distance > 2.58
			):
				game.player.face_toward(hostage.source_use_origin())
				await _capture(
					"protocol47-live-rescue-01-approach.png",
					"LIVE RESCUE  ·  BEFORE  ·  follower approaches rescue radius",
					"PHYSICS  navigation escort distance=%.2f m · threshold=2.56 m"
					% distance,
				)
				threshold_captured = true
			if bool(contract.rescued):
				rescued = true
				break
	if not threshold_captured:
		game.player.face_toward(hostage.source_use_origin())
		await _capture(
			"protocol47-live-rescue-01-approach.png",
			"LIVE RESCUE  ·  BEFORE  ·  last live escort sample",
			"PHYSICS  follower advanced by production navigation",
		)
	if not rescued:
		print(
			"ESCORT_NOT_RESCUED player=%s hostage=%s rescue=%s contract=%s"
			% [
				game.player.global_position,
				hostage.global_position,
				rescue_position,
				game.hostage_state.hostages[hostage_id],
			]
		)
	_check(rescued, "normal hostage think/rescue loop completes the escort")
	await _capture(
		"protocol47-live-rescue-02-action.png",
		"LIVE RESCUE  ·  ACTION  ·  automatic HOSTAGE RESCUED consequence",
		"STATE  rescued=true · actor hidden · collision disabled · reward applied",
	)
	await _physics_ticks(180)
	await _capture(
		"protocol47-live-rescue-03-after.png",
		"LIVE RESCUE  ·  AFTER  ·  Player view restored after banner",
		"STATE  same live round · rescued actor remains absent",
	)


func _capture_live_hostage_fire() -> void:
	var ids: Array = game.hostage_actors.keys()
	ids.sort()
	var hostage_id := str(ids[1])
	var hostage: CS16Hostage = game.hostage_actors[hostage_id]
	game._on_team_selected(1)
	game._on_class_selected(1)
	game.player.controls_enabled = true
	game.player.grant_item("ak47")
	game.player.switch_weapon("ak47")
	await _physics_ticks(110)
	game.player.camera.fov = 90.0
	_place_player(
		hostage.global_position + Vector3(0.0, 0.0, 0.82),
		hostage.global_position + Vector3.UP * 0.45,
	)
	await _capture(
		"protocol47-live-damage-01-before.png",
		"LIVE FIRE  ·  BEFORE  ·  T crosshair / production AK-47",
		"INPUT  live HumanController fire path · hostage health=100",
	)
	var health_before := float(game.hostage_state.hostages[hostage_id].health)
	Input.action_press("fire")
	await _physics_ticks(2)
	Input.action_release("fire")
	await _physics_ticks(6)
	var health_after := float(game.hostage_state.hostages[hostage_id].health)
	_check(health_after < health_before, "real AK-47 shot damages the hostage")
	await _capture(
		"protocol47-live-damage-02-flinch.png",
		"LIVE FIRE  ·  ACTION  ·  real bullet / flinch / money penalty",
		"STATE  health %.1f → %.1f · no direct receive_bullet_damage call"
		% [health_before, health_after],
	)
	for _shot in 18:
		if not bool(game.hostage_state.hostages[hostage_id].alive):
			break
		Input.action_press("fire")
		await _physics_ticks(2)
		Input.action_release("fire")
		await _physics_ticks(10)
	_check(
		not bool(game.hostage_state.hostages[hostage_id].alive),
		"repeated production weapon fire kills the hostage",
	)
	await _physics_ticks(120)
	game.player.face_toward(hostage.global_position + Vector3.UP * 0.08)
	await _capture(
		"protocol47-live-damage-03-death.png",
		"LIVE FIRE  ·  AFTER  ·  grounded corpse from real weapon damage",
		"STATE  alive=false · collision disabled · death animation naturally advanced",
	)


func _capture_live_doors() -> void:
	game.player.grant_item("usp")
	game.player.switch_weapon("usp")
	await _physics_ticks(100)
	game.player.camera.fov = 90.0
	var left_id := 124
	var right_id := 125
	var left_bounds: AABB = game._brush_world_aabb(left_id)
	var right_bounds: AABB = game._brush_world_aabb(right_id)
	var target := (
		left_bounds.get_center() + right_bounds.get_center()
	) * 0.5
	var start := target + Vector3(
		-0.86,
		0.72 - game.player.camera.position.y,
		0.0,
	)
	_place_player(start, target)
	await _capture(
		"protocol47-live-doors-01-before.png",
		"LIVE DOORS  ·  BEFORE  ·  Player approaches closed security doors",
		"STATE  entity124=closed · entity125=closed · collision blocks corridor",
	)
	Input.action_press("move_forward")
	var opening := false
	for _tick in 160:
		await physics_frame
		if (
			str(game.brush_runtime.get_brush(left_id).state) == "opening"
			or str(game.brush_runtime.get_brush(right_id).state) == "opening"
		):
			opening = true
			break
	await _physics_ticks(18)
	Input.action_release("move_forward")
	_check(opening, "normal Player hull touch opens the security doors")
	await _capture(
		"protocol47-live-doors-02-action.png",
		"LIVE DOORS  ·  ACTION  ·  physical Player touch / mid-travel",
		"INPUT  move_forward held · mover state generated by overlap, not direct queue",
	)
	Input.action_press("move_forward")
	var open := false
	for _tick in 180:
		await physics_frame
		if (
			str(game.brush_runtime.get_brush(left_id).state) == "open"
			and str(game.brush_runtime.get_brush(right_id).state) == "open"
		):
			open = true
			break
	await _physics_ticks(35)
	Input.action_release("move_forward")
	_check(open, "normal mover physics reaches both open endpoints")
	await _capture(
		"protocol47-live-doors-03-walkthrough.png",
		"LIVE DOORS  ·  AFTER  ·  Player physically walks through open doorway",
		"STATE  both movers=open · Player position advanced through collision portal",
	)


func _capture_live_button_camera() -> void:
	game.player.camera.current = true
	var button_id := 51
	var bounds: AABB = game._brush_world_aabb(button_id)
	var target := bounds.get_center()
	var direction := Vector3(0.72, 0.0, 0.88).normalized()
	var camera_position := target + direction * 0.30 + Vector3.UP * 0.18
	var player_position: Vector3 = (
		camera_position - Vector3.UP * game.player.camera.position.y
	)
	_place_player(player_position, target)
	var trace_start: int = game.entity_world.trace.size()
	await _capture(
		"protocol47-live-button-01-before.png",
		"LIVE CAMERA BUTTON  ·  BEFORE  ·  stable Player view / crosshair",
		"STATE  button51=closed · trigger_camera inactive · input idle",
	)
	Input.action_press("use")
	await _physics_ticks(3)
	Input.action_release("use")
	await _physics_ticks(3)
	_check(
		game.trigger_camera_entity_id == 110 and game.trigger_camera.current,
		"normal +use activates visible cam4 trigger_camera",
	)
	await _capture(
		"protocol47-live-button-02-cam4.png",
		"LIVE CAMERA BUTTON  ·  ACTION  ·  visible authored cam4 feed",
		"ENTITY TRACE  %s" % _entity_trace_since(trace_start),
	)
	var returned := false
	for _tick in 1100:
		await physics_frame
		if game.trigger_camera_entity_id < 0:
			returned = true
			break
	_check(returned, "normal ten-second trigger_camera wait restores Player view")
	await _capture(
		"protocol47-live-button-03-return.png",
		"LIVE CAMERA BUTTON  ·  AFTER  ·  automatic return to Player camera",
		"STATE  cam4 inactive · Player controls/camera restored by production timer",
	)


func _place_player(position: Vector3, target: Vector3) -> void:
	game.player.global_position = position
	game.player.velocity = Vector3.ZERO
	game.player.face_toward(target)
	game.player.camera.look_at(target, Vector3.UP)
	game.player.camera.current = true


func _physics_ticks(count: int) -> void:
	for _tick in count:
		await physics_frame


func _capture(file_name: String, title: String, evidence_text: String) -> void:
	caption.text = title
	evidence.text = evidence_text
	for _frame in 5:
		await process_frame
	var raw := game_viewport.get_texture().get_image()
	var raw_path := OUTPUT_ROOT.path_join(
		file_name.trim_suffix(".png") + "-raw-4x3.png"
	)
	if raw.save_png(raw_path) != OK:
		_fail("could not save %s" % raw_path)
	else:
		outputs.append(raw_path)
	var panel := root.get_viewport().get_texture().get_image()
	var panel_path := OUTPUT_ROOT.path_join(file_name)
	if panel.save_png(panel_path) != OK:
		_fail("could not save %s" % panel_path)
	else:
		outputs.append(panel_path)
		frames.append(panel)


func _entity_trace_since(start_index: int) -> String:
	var parts: Array[String] = []
	for event: Dictionary in game.entity_world.trace.slice(start_index):
		var part := str(event.get("event", "?"))
		if event.has("entity_id"):
			part += "#%d" % int(event.entity_id)
		if event.has("phase") and not str(event.phase).is_empty():
			part += "/%s" % str(event.phase)
		parts.append(part)
	return " | ".join(parts).left(210) if not parts.is_empty() else "none"


func _save_montage(
	images: Array[Image],
	columns: int,
	cell_size: Vector2i,
	path: String,
) -> bool:
	var rows := int(ceil(float(images.size()) / float(columns)))
	var montage := Image.create(
		cell_size.x * columns,
		cell_size.y * rows,
		false,
		Image.FORMAT_RGBA8,
	)
	montage.fill(Color("#101820"))
	for index in images.size():
		montage.blit_rect(
			images[index],
			Rect2i(Vector2i.ZERO, cell_size),
			Vector2i(
				(index % columns) * cell_size.x,
				(index / columns) * cell_size.y,
			),
		)
	return montage.save_png(path) == OK


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	push_error("HOSTAGE LIVE CAPTURE: " + message)


func _finish() -> void:
	if failures.is_empty():
		print("HOSTAGE_LIVE_VISUAL_CAPTURE_PASS " + " ".join(outputs))
		quit(0)
	else:
		print(
			"HOSTAGE_LIVE_VISUAL_CAPTURE_FAIL (%d) " % failures.size()
			+ " | ".join(failures)
		)
		quit(1)
