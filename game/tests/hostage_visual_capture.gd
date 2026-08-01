extends SceneTree

const GameScript := preload("res://scripts/game.gd")
const HostageScript := preload("res://scripts/cs16_hostage.gd")
const CELL_SIZE := Vector2i(640, 520)
const GAME_SIZE := Vector2i(640, 480)
const FIRST_PERSON_CELL_SIZE := Vector2i(640, 568)
const OUTPUT_ROOT := "res://artifacts"

var game: Node3D
var camera: Camera3D
var evidence_label: Label
var trace_label: Label
var capture_shell: Control
var capture_background: ColorRect
var game_viewport: SubViewport
var images: Array[Image] = []
var first_person_images: Array[Image] = []
var output_paths: Array[String] = []
var capture_failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = CELL_SIZE
	root.content_scale_size = CELL_SIZE
	_build_capture_shell()
	await _build_production_game()
	if game == null or not game.using_imported_map or game.hostage_actors.size() != 4:
		push_error("Hostage visual capture could not load production cs_assault")
		quit(1)
		return
	if "--probe" in OS.get_cmdline_user_args():
		await _capture_camera_probe()
		var probe_path := OUTPUT_ROOT.path_join("protocol47-hostage-camera-probe.png")
		_save_montage(images, 4, CELL_SIZE, probe_path)
		print("HOSTAGE_VISUAL_CAPTURE_PROBE " + probe_path)
		quit(0)
		return

	await _capture_hostage_lifecycle()
	await _capture_assault_brush_states()
	var hostage_matrix_path := OUTPUT_ROOT.path_join(
		"protocol47-hostage-lifecycle-matrix.png"
	)
	if not _save_montage(
		images.slice(0, 9),
		3,
		CELL_SIZE,
		hostage_matrix_path,
	):
		quit(1)
		return
	output_paths.append(hostage_matrix_path)
	var brush_matrix_path := OUTPUT_ROOT.path_join(
		"protocol47-assault-brush-state-matrix.png"
	)
	if not _save_montage(
		images.slice(9),
		3,
		CELL_SIZE,
		brush_matrix_path,
	):
		quit(1)
		return
	output_paths.append(brush_matrix_path)
	var matrix_path := OUTPUT_ROOT.path_join(
		"protocol47-hostage-rescue-evidence-matrix.png"
	)
	if not _save_montage(images, 3, CELL_SIZE, matrix_path):
		quit(1)
		return
	output_paths.append(matrix_path)
	await _capture_first_person_gameplay()
	var first_person_path := OUTPUT_ROOT.path_join(
		"protocol47-assault-first-person-proof-matrix.png"
	)
	if not _save_montage(
		first_person_images,
		3,
		FIRST_PERSON_CELL_SIZE,
		first_person_path,
	):
		quit(1)
		return
	output_paths.append(first_person_path)
	if capture_failed:
		push_error("First-person production interaction proof failed an assertion")
		quit(1)
		return
	print("HOSTAGE_VISUAL_CAPTURE_PASS " + " ".join(output_paths))
	quit(0)


func _capture_camera_probe() -> void:
	var hostage_ids: Array = game.hostage_actors.keys()
	hostage_ids.sort()
	var primary: CS16Hostage = game.hostage_actors[str(hostage_ids[0])]
	for actor: CS16Hostage in game.hostage_actors.values():
		actor.visible = actor == primary
	var offsets := [
		Vector3(0.0, 0.48, 0.72),
		Vector3(0.0, 0.48, -0.72),
		Vector3(0.72, 0.48, 0.0),
		Vector3(-0.72, 0.48, 0.0),
		Vector3(0.52, 0.48, 0.52),
		Vector3(-0.52, 0.48, 0.52),
		Vector3(0.52, 0.48, -0.52),
		Vector3(-0.52, 0.48, -0.52),
	]
	for offset: Vector3 in offsets:
		_frame_subjects([primary], offset)
		await _capture(
			"protocol47-probe-hostage-%02d.png" % images.size(),
			"HOSTAGE PROBE  offset=(%.2f, %.2f, %.2f)"
			% [offset.x, offset.y, offset.z],
		)
	var door_bounds: AABB = game._brush_world_aabb(11)
	var door_target := door_bounds.get_center()
	for offset: Vector3 in offsets:
		camera.look_at_from_position(
			door_target + offset * 3.0,
			door_target,
			Vector3.UP,
		)
		await _capture(
			"protocol47-probe-door-%02d.png" % images.size(),
			"DOOR PROBE  offset=(%.2f, %.2f, %.2f)"
			% [offset.x * 3.0, offset.y * 3.0, offset.z * 3.0],
		)
	var linear_bounds: AABB = game._brush_world_aabb(124)
	var linear_target := linear_bounds.get_center()
	for offset: Vector3 in offsets:
		camera.look_at_from_position(
			linear_target + offset * 1.65,
			linear_target,
			Vector3.UP,
		)
		await _capture(
			"protocol47-probe-linear-door-%02d.png" % images.size(),
			"LINEAR DOOR PROBE  offset=(%.2f, %.2f, %.2f)"
			% [offset.x * 1.65, offset.y * 1.65, offset.z * 1.65],
		)


func _build_capture_shell() -> void:
	capture_shell = Control.new()
	capture_shell.size = Vector2(CELL_SIZE)
	root.add_child(capture_shell)

	capture_background = ColorRect.new()
	capture_background.color = Color("#111820")
	capture_background.size = Vector2(CELL_SIZE)
	capture_shell.add_child(capture_background)

	var container := SubViewportContainer.new()
	container.size = Vector2(GAME_SIZE)
	container.stretch = true
	capture_shell.add_child(container)
	game_viewport = SubViewport.new()
	game_viewport.size = GAME_SIZE
	game_viewport.own_world_3d = true
	game_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(game_viewport)

	var divider := ColorRect.new()
	divider.color = Color("#4f6877")
	divider.position = Vector2(0.0, 480.0)
	divider.size = Vector2(640.0, 2.0)
	capture_shell.add_child(divider)
	evidence_label = Label.new()
	evidence_label.position = Vector2(14.0, 488.0)
	evidence_label.size = Vector2(612.0, 28.0)
	evidence_label.add_theme_font_size_override("font_size", 17)
	evidence_label.add_theme_color_override("font_color", Color("#edf4f7"))
	evidence_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	evidence_label.add_theme_constant_override("shadow_offset_x", 1)
	evidence_label.add_theme_constant_override("shadow_offset_y", 1)
	capture_shell.add_child(evidence_label)
	trace_label = Label.new()
	trace_label.visible = false
	trace_label.position = Vector2(14.0, 518.0)
	trace_label.size = Vector2(612.0, 46.0)
	trace_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trace_label.add_theme_font_size_override("font_size", 12)
	trace_label.add_theme_color_override("font_color", Color("#9dd9ff"))
	trace_label.add_theme_color_override("font_shadow_color", Color("#000000"))
	trace_label.add_theme_constant_override("shadow_offset_x", 1)
	trace_label.add_theme_constant_override("shadow_offset_y", 1)
	capture_shell.add_child(trace_label)


func _build_production_game() -> void:
	game = GameScript.new()
	game.map_name = "cs_assault"
	game_viewport.add_child(game)
	await process_frame
	await physics_frame
	if not is_instance_valid(game):
		return
	game.hud.visible = false
	game.match_started = false
	for actor: Node in [game.player] + game.allied_bots + game.targets:
		if not is_instance_valid(actor):
			continue
		actor.visible = false
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	camera = Camera3D.new()
	camera.name = "HostageEvidenceCamera"
	camera.fov = 90.0
	camera.near = 0.03
	game.add_child(camera)
	camera.current = true
	await _settle(4)


func _capture_hostage_lifecycle() -> void:
	var hostage_ids: Array = game.hostage_actors.keys()
	hostage_ids.sort()
	var primary_id := str(hostage_ids[0])
	var primary: CS16Hostage = game.hostage_actors[primary_id]
	var rescuer: TargetActor = game.targets[0]

	# Live actors run the authored idle sequence; stage a mid-cycle breathing
	# frame per hostage so stills do not read as a stiff bind-adjacent pose.
	for hostage_index in range(hostage_ids.size()):
		game.hostage_actors[str(hostage_ids[hostage_index])].hostage_model.force_state(
			"idle",
			40 + hostage_index * 37,
		)
	for hostage_id: String in hostage_ids:
		game.hostage_actors[hostage_id].visible = (
			hostage_id == str(hostage_ids[0])
			or hostage_id == str(hostage_ids[1])
		)
	_frame_subjects(
		[
			game.hostage_actors[str(hostage_ids[0])],
			game.hostage_actors[str(hostage_ids[1])],
		],
		Vector3(0.0, 0.50, 0.84),
	)
	await _capture(
		"protocol47-hostage-01a-establish-pair-a.png",
		"01A  ESTABLISH  ·  cs_assault BSP spawn pair A  ·  both source skin families",
	)
	if not images.is_empty():
		var idle_path := OUTPUT_ROOT.path_join("protocol47-hostage-idle.png")
		if images[-1].save_png(idle_path) == OK:
			output_paths.append(idle_path)
	for hostage_id: String in hostage_ids:
		game.hostage_actors[hostage_id].visible = (
			hostage_id == str(hostage_ids[2])
			or hostage_id == str(hostage_ids[3])
		)
	_frame_subjects(
		[
			game.hostage_actors[str(hostage_ids[2])],
			game.hostage_actors[str(hostage_ids[3])],
		],
		Vector3(0.0, 0.50, 0.84),
	)
	await _capture(
		"protocol47-hostage-01b-establish-pair-b.png",
		"01B  ESTABLISH  ·  cs_assault BSP spawn pair B  ·  exact BSP entity origins",
	)

	for hostage_id: String in hostage_ids:
		game.hostage_actors[hostage_id].visible = hostage_id == primary_id
	rescuer.visible = true
	rescuer.global_position = primary.global_position + Vector3(0.85, 0.0, 0.38)
	rescuer.face_aim_target(primary.global_position)
	_modulate_leader_by_floor_light(rescuer)
	game._on_hostage_use_requested(primary, rescuer)
	primary.hostage_model.force_state("acknowledge", 24)
	_frame_subjects([primary, rescuer], Vector3(0.0, 0.50, 0.92))
	await _capture(
		"protocol47-hostage-02-ct-use-acknowledge.png",
		"02  CT USE  ·  acknowledge response  ·  authoritative follow state begins",
	)

	game.phase = "live"
	rescuer.global_position = primary.global_position + Vector3(0.68, 0.0, 0.08)
	rescuer.face_aim_target(rescuer.global_position + Vector3(1.0, 0.0, 0.0))
	# The CT leader must read grounded and floor-lit like GoldSrc renders him:
	# plant a mid-stride run frame with feet aligned to the floor and modulate
	# his materials by the lightmap sample under his origin.
	if is_instance_valid(rescuer.character_model):
		rescuer.character_model.set_locomotion(true, false, true)
		rescuer.character_model.force_pose("run", 0.0)
	_modulate_leader_by_floor_light(rescuer)
	primary.set_motion_velocity_hu(Vector3(185.0, 0.0, 0.0))
	primary.hostage_model.force_state("run", 18)
	_frame_subjects([primary, rescuer], Vector3(0.0, 0.50, 0.92))
	await _capture(
		"protocol47-hostage-03-follow.png",
		"03  FOLLOW  ·  hostage run cycle tracks a living CT leader",
	)
	if not images.is_empty():
		var follow_path := OUTPUT_ROOT.path_join("protocol47-hostage-follow.png")
		if images[-1].save_png(follow_path) == OK:
			output_paths.append(follow_path)

	rescuer.visible = false
	primary.set_motion_velocity_hu(Vector3.ZERO)
	primary.receive_bullet_damage(
		10,
		4,
		"ak47",
		primary.global_position + Vector3.UP * 0.40,
		rescuer,
	)
	# Tick 12 = frame ~4 of the authored 31-frame flinch: the onset head and
	# shoulder recoil of the hit reaction. Later frames (8+) raise both fists
	# into a boxing-guard pose that reads wrong as a still, and the deeper
	# frame-12 head-covering crouch shows a face-texture wedge from behind.
	primary.hostage_model.force_state("flinch", 12)
	_frame_subjects([primary], Vector3(0.0, 0.48, 0.72))
	await _capture(
		"protocol47-hostage-04-damage-flinch.png",
		"04  DAMAGE  ·  nonlethal arm hit  ·  flinch pose / hostage penalty path",
	)

	primary.receive_bullet_damage(
		100,
		1,
		"ak47",
		primary.global_position + Vector3.UP * 0.55,
		rescuer,
	)
	# Past the 20-frame diesimple duration: the corpse rests on its final
	# authored frame, flat on the floor like GoldSrc leaves it.
	primary.hostage_model.force_state("die", 200)
	primary.drop_to_floor()
	# Raised three-quarter view: the sprawled diesimple final frame must read
	# as a full extended corpse; a floor-level view foreshortens it into a
	# crumpled pile.
	camera.look_at_from_position(
		primary.global_position + Vector3(0.72, 0.62, 0.84),
		primary.global_position + Vector3.UP * 0.05,
		Vector3.UP,
	)
	await _capture(
		"protocol47-hostage-05-death.png",
		"05  DEATH  ·  lethal head hit  ·  visible corpse / collision disabled",
	)

	game.hostage_state.start_round()
	game._sync_hostage_actors()
	primary.visible = true
	primary.hostage_model.force_state("idle", 31)
	_frame_subjects([primary], Vector3(0.0, 0.48, 0.72))
	await _capture(
		"protocol47-hostage-06-round-reset.png",
		"06  ROUND RESET  ·  hostage restored alive, visible, solid, idle",
	)

	# The first CT spawn sits in a near-black corner and produced unusable
	# evidence frames; stage the rescue at the brightest-lit CT spawn of the
	# same rescue volume (still authentic map light — no artificial fill).
	var rescue_position: Vector3 = game.counter_terrorist_team_spawns[0]
	var best_brightness := -1.0
	for spawn: Vector3 in game.counter_terrorist_team_spawns:
		var spawn_light := HostageScript.sample_floor_light(
			game.imported_map,
			spawn,
		)
		var brightness := spawn_light.r + spawn_light.g + spawn_light.b
		if brightness > best_brightness:
			best_brightness = brightness
			rescue_position = spawn
	game.hostage_state.use_hostage(
		primary_id,
		rescuer.name,
		"CT",
		true,
	)
	game.hostage_state.set_position(
		primary_id,
		rescue_position / HostageScript.GOLDSRC_UNIT,
	)
	game._sync_hostage_actors()
	primary.visible = true
	primary.drop_to_floor()
	primary.hostage_model.force_state("walk", 20)
	_frame_subjects([primary], Vector3(0.0, 0.48, -0.72))
	await _capture(
		"protocol47-hostage-07-rescue-threshold.png",
		"07  RESCUE THRESHOLD  ·  following hostage enters CT rescue volume",
	)
	game._check_hostage_rescue(primary_id)
	await _capture(
		"protocol47-hostage-08-rescued.png",
		"08  RESCUED  ·  same camera  ·  hostage hidden and desolidified",
	)

	game.hostage_state.start_round()
	game._sync_hostage_actors()
	_show_all_hostages()


## GoldSrc samples model lighting from the lightmap under the model origin;
## two characters in one corridor must read within a fraction of a stop of
## each other. Applied to the staged CT leader in every panel he appears in.
func _modulate_leader_by_floor_light(rescuer: TargetActor) -> void:
	if not is_instance_valid(rescuer.character_model):
		return
	var leader_light := HostageScript.sample_floor_light(
		game.imported_map,
		rescuer.global_position,
	)
	for instance: Variant in [
		rescuer.character_model.body_instance,
		rescuer.character_model.weapon_instance,
	]:
		if instance is MeshInstance3D:
			for material: StandardMaterial3D in (
				(instance as MeshInstance3D).get_meta("group_materials", [])
			):
				material.albedo_color = leader_light


func _capture_assault_brush_states() -> void:
	for actor: CS16Hostage in game.hostage_actors.values():
		actor.visible = false
	var left_door_id := 124
	var right_door_id := 125
	var bounds: AABB = game._brush_world_aabb(left_door_id)
	var target := bounds.get_center()
	camera.look_at_from_position(
		target + Vector3(-1.19, 0.79, 0.0),
		target,
		Vector3.UP,
	)
	await _capture(
		"protocol47-assault-door-01-closed.png",
		"09  BSP DOORS  ·  cs_assault paired security doors  ·  closed / solid",
	)
	game.entity_world.queue_touch(
		left_door_id,
		game.entity_world.entity_count() + 500,
		"enter",
	)
	game.entity_world.queue_touch(
		right_door_id,
		game.entity_world.entity_count() + 500,
		"enter",
	)
	game.brush_runtime.advance_ticks(31)
	await _capture(
		"protocol47-assault-door-02-mid-travel.png",
		"10  BSP DOORS  ·  deterministic tick 31 / 62  ·  paired mid-travel",
	)
	game.brush_runtime.advance_ticks(31)
	await _capture(
		"protocol47-assault-door-03-open.png",
		"11  BSP DOORS  ·  deterministic tick 62 / 62  ·  paired open endpoints",
	)

	var button_id := 51
	var button_bounds: AABB = game._brush_world_aabb(button_id)
	var button_target := button_bounds.get_center()
	camera.look_at_from_position(
		button_target + Vector3(0.72, 0.52, 0.88),
		button_target,
		Vector3.UP,
	)
	await _capture(
		"protocol47-assault-button-01-rest.png",
		"12  BSP BUTTON  ·  camera selector at rest  ·  source DONT_MOVE toggle",
	)
	game.entity_world.queue_use(
		button_id,
		game.entity_world.entity_count() + 501,
		"pressed",
	)
	game.brush_runtime.advance_tick()
	await _capture(
		"protocol47-assault-button-02-active.png",
		"13  BSP BUTTON  ·  active state / target fired  ·  intentionally no travel",
	)


func _capture_first_person_gameplay() -> void:
	_configure_first_person_shell()
	game.brush_runtime.reset_round()
	game.hostage_state.start_round()
	game._sync_hostage_actors()
	for actor: Node in game.allied_bots + game.targets:
		actor.visible = false
	game.player.process_mode = Node.PROCESS_MODE_INHERIT
	game.player.visible = true
	game.player.camera.current = true
	camera.current = false
	game.hud.visible = true
	game.hud.set_deploy_visible(false)
	# The earlier brush-state pass pressed the cs_assault camera selector; its
	# transient "SECURITY CAMERA" objective toast must not linger over
	# first-person evidence frames (CS 1.6 has no persistent objective text).
	game.hud.update_objective("")
	game.phase = "live"
	game.seconds_left = 278.0
	game.hud.update_match(
		game.round_number,
		game.phase,
		game.seconds_left,
		game.ct_score,
		game.terrorist_score,
		game.money,
	)
	game.player.controls_enabled = true
	game.player.camera.fov = 90.0
	game.hud.banner_label.text = ""
	game.hud.banner_label.modulate.a = 0.0

	var hostage_ids: Array = game.hostage_actors.keys()
	hostage_ids.sort()
	var hostage_id := str(hostage_ids[0])
	var hostage: CS16Hostage = game.hostage_actors[hostage_id]
	for actor: CS16Hostage in game.hostage_actors.values():
		actor.visible = actor == hostage

	await _capture_first_person_ct_use(hostage_id, hostage)
	await _capture_first_person_rescue(hostage_id, hostage)
	await _capture_first_person_damage(hostage_id, hostage)
	await _capture_first_person_doors()
	await _capture_first_person_button()


func _capture_first_person_ct_use(
	hostage_id: String,
	hostage: CS16Hostage,
) -> void:
	game._on_team_selected(2)
	game._on_class_selected(1)
	game.player.controls_enabled = true
	game.player.grant_item("knife")
	game.player.switch_weapon("knife")
	await _settle_viewmodel_idle()
	game.player.camera.fov = 90.0
	game.hostage_state.start_round()
	game._sync_hostage_actors()
	hostage.visible = true
	_place_player_looking_at(
		hostage.global_position + Vector3(0.0, 0.0, 0.52),
		hostage.source_use_origin(),
	)
	game._player_use_was_down = false
	await _capture_first_person_panel(
		"protocol47-fp-hostage-use-01-before.png",
		"FP HOSTAGE USE  ·  BEFORE  ·  CT crosshair on usable hostage",
		"STATE  following=false · player team=CT · resolver idle",
	)
	var before_trace: int = game.entity_world.trace.size()
	Input.action_press("use")
	game.player.last_command = game.player.combat_controller.gather_command(0.01)
	Input.action_release("use")
	game._process_player_world_use()
	_require(
		bool(game.hostage_state.hostages[hostage_id].following)
		and str(game.hostage_state.hostages[hostage_id].leader_id) == "player",
		"actual Player use resolver starts hostage following",
	)
	await _capture_first_person_panel(
		"protocol47-fp-hostage-use-02-action.png",
		"FP HOSTAGE USE  ·  ACTION  ·  +use acknowledge / HUD banner",
		"USE RESOLVER  pressed=true · following=true · leader=player"
		+ " · entity-world delta=%s" % _entity_trace_since(before_trace),
	)
	game.player.last_command = {"use": false}
	game._process_player_world_use()
	game.player.global_position = hostage.global_position + Vector3(0.58, 0.0, 0.40)
	game.player.face_toward(hostage.source_use_origin())
	hostage.set_motion_velocity_hu(Vector3(160.0, 0.0, 0.0))
	hostage.hostage_model.force_state("run", 18)
	game.hud.banner_label.modulate.a = 0.0
	await _capture_first_person_panel(
		"protocol47-fp-hostage-use-03-after-follow.png",
		"FP HOSTAGE USE  ·  AFTER  ·  escort view with running follower",
		"STATE  following=true · leader=Player · source run cycle=160 HU/s",
	)


func _capture_first_person_rescue(
	hostage_id: String,
	hostage: CS16Hostage,
) -> void:
	var rescue_position: Vector3 = game.counter_terrorist_team_spawns[0]
	game.hostage_state.set_position(
		hostage_id,
		rescue_position / HostageScript.GOLDSRC_UNIT,
	)
	game._sync_hostage_actors()
	hostage.visible = true
	hostage.hostage_model.force_state("walk", 18)
	_place_player_looking_at(
		hostage.global_position + Vector3(0.0, 0.0, -0.55),
		hostage.source_use_origin(),
	)
	await _capture_first_person_panel(
		"protocol47-fp-rescue-01-before.png",
		"FP RESCUE  ·  BEFORE  ·  escort enters legacy CT rescue radius",
		"STATE  rescued=false · distance to CT spawn=0 HU",
	)
	var trace_start: int = game.round_state.trace.size()
	game._check_hostage_rescue(hostage_id)
	_require(
		bool(game.hostage_state.hostages[hostage_id].rescued),
		"first-person escort resolves hostage rescue",
	)
	await _capture_first_person_panel(
		"protocol47-fp-rescue-02-action-banner.png",
		"FP RESCUE  ·  ACTION  ·  actual HUD HOSTAGE RESCUED banner",
		"ROUND TRACE  %s · rescued=true / actor hidden"
		% _round_trace_since(trace_start),
	)
	game.hud.banner_label.modulate.a = 0.0
	await _capture_first_person_panel(
		"protocol47-fp-rescue-03-after.png",
		"FP RESCUE  ·  AFTER  ·  same Player camera / rescued actor absent",
		"STATE  rescued=true · visible=false · collision disabled=true",
	)


func _capture_first_person_damage(
	hostage_id: String,
	hostage: CS16Hostage,
) -> void:
	game._on_team_selected(1)
	game._on_class_selected(1)
	game.player.controls_enabled = true
	game.player.grant_item("ak47")
	game.player.switch_weapon("ak47")
	await _settle_viewmodel_idle()
	game.player.camera.fov = 90.0
	game.hostage_state.start_round()
	game._sync_hostage_actors()
	hostage.visible = true
	_place_player_looking_at(
		hostage.global_position + Vector3(0.0, 0.0, 0.52),
		hostage.source_use_origin(),
	)
	await _capture_first_person_panel(
		"protocol47-fp-hostage-damage-01-before.png",
		"FP HOSTAGE DAMAGE  ·  BEFORE  ·  T crosshair / AK-47 viewmodel",
		"STATE  health=100 · alive=true · attacker team=T",
	)
	hostage.receive_bullet_damage(
		10,
		4,
		"ak47",
		hostage.global_position + Vector3.UP * 0.40,
		game.player,
	)
	hostage.hostage_model.force_state("flinch", 12)
	_require(
		float(game.hostage_state.hostages[hostage_id].health) < 100.0,
		"actual Player damage path applies nonlethal hostage damage",
	)
	await _capture_first_person_panel(
		"protocol47-fp-hostage-damage-02-flinch.png",
		"FP HOSTAGE DAMAGE  ·  ACTION  ·  flinch / HOSTAGE INJURED banner",
		"STATE  health=%.1f · flinch animation · attacker money penalty"
		% float(game.hostage_state.hostages[hostage_id].health),
	)
	hostage.receive_bullet_damage(
		100,
		1,
		"ak47",
		hostage.global_position + Vector3.UP * 0.55,
		game.player,
	)
	hostage.hostage_model.force_state("die", 200)
	hostage.drop_to_floor()
	_place_player_looking_at(
		hostage.global_position + Vector3(0.0, 0.0, 0.82),
		hostage.global_position + Vector3.UP * 0.18,
	)
	_require(
		not bool(game.hostage_state.hostages[hostage_id].alive),
		"actual Player lethal damage leaves a hostage corpse",
	)
	await _capture_first_person_panel(
		"protocol47-fp-hostage-damage-03-death.png",
		"FP HOSTAGE DAMAGE  ·  AFTER  ·  corpse / HOSTAGE KILLED banner",
		"STATE  alive=false · corpse visible=true · collision disabled=true",
	)


func _capture_first_person_doors() -> void:
	game.brush_runtime.reset_round()
	game.hud.banner_label.modulate.a = 0.0
	game.player.grant_item("knife")
	game.player.switch_weapon("knife")
	await _settle_viewmodel_idle()
	game.player.camera.fov = 90.0
	var left_id := 124
	var right_id := 125
	var left_bounds: AABB = game._brush_world_aabb(left_id)
	var right_bounds: AABB = game._brush_world_aabb(right_id)
	var target := left_bounds.get_center()
	var vantage := target + Vector3(
		-1.19,
		0.79 - game.player.camera.position.y,
		0.0,
	)
	_place_player_looking_at(vantage, target)
	await _capture_first_person_panel(
		"protocol47-fp-doors-01-before.png",
		"FP BSP DOORS  ·  BEFORE  ·  Player approaches closed security doors",
		"BRUSH STATE  entity 124=closed · entity 125=closed",
	)
	var trace_start: int = game.entity_world.trace.size()
	var contact_y := minf(left_bounds.position.y, right_bounds.position.y) + 0.02
	game.player.global_position = Vector3(
		left_bounds.get_center().x,
		contact_y,
		left_bounds.get_center().z,
	)
	game._queue_brush_touches()
	game.brush_runtime.advance_tick()
	game.player.global_position = Vector3(
		right_bounds.get_center().x,
		contact_y,
		right_bounds.get_center().z,
	)
	game._queue_brush_touches()
	game.brush_runtime.advance_tick()
	game.brush_runtime.advance_ticks(29)
	_place_player_looking_at(vantage, target)
	_require(
		str(game.brush_runtime.get_brush(left_id).state) == "opening"
		and str(game.brush_runtime.get_brush(right_id).state) == "opening",
		"physical Player touch starts both security doors",
	)
	await _capture_first_person_panel(
		"protocol47-fp-doors-02-action.png",
		"FP BSP DOORS  ·  ACTION  ·  Player TOUCH_ENTER / paired mid-travel",
		"ENTITY TRACE  %s · states=opening/opening"
		% _entity_trace_since(trace_start),
	)
	game.brush_runtime.advance_ticks(32)
	_require(
		str(game.brush_runtime.get_brush(left_id).state) == "open"
		and str(game.brush_runtime.get_brush(right_id).state) == "open",
		"physically triggered paired doors reach open endpoints",
	)
	await _capture_first_person_panel(
		"protocol47-fp-doors-03-after.png",
		"FP BSP DOORS  ·  AFTER  ·  clear doorway at exact open endpoints",
		"BRUSH STATE  entity 124=open · entity 125=open · collision moved",
	)


func _capture_first_person_button() -> void:
	game.brush_runtime.reset_round()
	game.player.camera.fov = 90.0
	var button_id := 51
	var button_bounds: AABB = game._brush_world_aabb(button_id)
	var button_target := button_bounds.get_center()
	var direction := Vector3(0.72, 0.0, 0.88).normalized()
	var camera_position := button_target + direction * 0.30 + Vector3.UP * 0.18
	var player_position: Vector3 = (
		camera_position - Vector3.UP * game.player.camera.position.y
	)
	_place_player_looking_at(player_position, button_target)
	game._player_use_was_down = false
	game.player.last_command = {"use": false}
	game._process_player_world_use()
	await _capture_first_person_panel(
		"protocol47-fp-button-01-before.png",
		"FP BSP BUTTON  ·  BEFORE  ·  crosshair on camera selector",
		"ENTITY TRACE  button 51 state=closed · no use dispatched",
	)
	var trace_start: int = game.entity_world.trace.size()
	Input.action_press("use")
	game.player.last_command = game.player.combat_controller.gather_command(0.01)
	Input.action_release("use")
	game._process_player_world_use()
	game.brush_runtime.advance_tick()
	var action_trace := _entity_trace_since(trace_start)
	_require(
		str(game.brush_runtime.get_brush(button_id).state) == "open"
		and game.entity_world.trace.size() > trace_start,
		"physical Player +use activates DONT_MOVE button and fires its target",
	)
	await _capture_first_person_panel(
		"protocol47-fp-button-02-action.png",
		"FP BSP BUTTON  ·  ACTION  ·  Player +use (DONT_MOVE visual)",
		"ENTITY TRACE  %s" % action_trace,
	)
	game.player.last_command = {"use": false}
	game._process_player_world_use()
	await _capture_first_person_panel(
		"protocol47-fp-button-03-after-trace.png",
		"FP BSP BUTTON  ·  AFTER  ·  unchanged pixels, authoritative active state",
		"BRUSH STATE  entity 51=open · target=cam4 fired · trace events=%d"
		% (game.entity_world.trace.size() - trace_start),
	)


## switch_weapon queues the authentic draw sequence through the weapon clock a
## few ticks later; captured stills must show the settled idle pose instead of
## a mid-draw frame that reads as a floating weapon.
func _settle_viewmodel_idle() -> void:
	await _settle(12)
	game.player.viewmodel._start_animation(
		game.player.viewmodel._idle_animation(),
		true,
	)
	await _settle(2)


func _configure_first_person_shell() -> void:
	root.size = FIRST_PERSON_CELL_SIZE
	root.content_scale_size = FIRST_PERSON_CELL_SIZE
	capture_shell.size = Vector2(FIRST_PERSON_CELL_SIZE)
	capture_background.size = Vector2(FIRST_PERSON_CELL_SIZE)
	trace_label.visible = true


func _place_player_looking_at(position: Vector3, target: Vector3) -> void:
	game.player.global_position = position
	game.player.velocity = Vector3.ZERO
	game.player.face_toward(target)
	game.player.camera.look_at(target, Vector3.UP)
	game.player.camera.current = true


func _capture_first_person_panel(
	file_name: String,
	label_text: String,
	trace_text: String,
) -> void:
	evidence_label.text = label_text
	trace_label.text = trace_text
	await _settle(5)
	var raw_image := game_viewport.get_texture().get_image()
	var raw_path := "/tmp".path_join(
		file_name.trim_suffix(".png") + "-raw-4x3.png"
	)
	var raw_error := raw_image.save_png(raw_path)
	if raw_error != OK:
		push_error("Could not save %s: %s" % [raw_path, error_string(raw_error)])
		capture_failed = true
	else:
		output_paths.append(raw_path)
	var image := root.get_viewport().get_texture().get_image()
	var path := OUTPUT_ROOT.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		capture_failed = true
	else:
		output_paths.append(path)
		first_person_images.append(image)


func _entity_trace_since(start_index: int) -> String:
	var parts: Array[String] = []
	for event: Dictionary in game.entity_world.trace.slice(start_index):
		var piece := str(event.get("event", "?"))
		if event.has("entity_id"):
			piece += "#%d" % int(event.entity_id)
		if event.has("phase") and not str(event.phase).is_empty():
			piece += "/%s" % str(event.phase)
		if event.has("targetname") and not str(event.targetname).is_empty():
			piece += "→%s" % str(event.targetname)
		parts.append(piece)
	if parts.is_empty():
		return "none"
	return " | ".join(parts).left(190)


func _round_trace_since(start_index: int) -> String:
	var parts: Array[String] = []
	for event: Dictionary in game.round_state.trace.slice(start_index):
		parts.append(str(event.get("type", "?")))
	if parts.is_empty():
		return "none"
	return " | ".join(parts).left(160)


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	capture_failed = true
	push_error("HOSTAGE FP CAPTURE: " + message)


func _show_all_hostages() -> void:
	for actor: CS16Hostage in game.hostage_actors.values():
		actor.visible = true


func _frame_hostage_room() -> void:
	var subjects: Array[Node3D] = []
	for actor: CS16Hostage in game.hostage_actors.values():
		subjects.append(actor)
	var target := _subjects_center(subjects) + Vector3.UP * 0.38
	camera.look_at_from_position(
		target + Vector3(0.20, 0.78, 3.05),
		target,
		Vector3.UP,
	)


func _frame_subjects(subjects: Array, offset: Vector3) -> void:
	var typed_subjects: Array[Node3D] = []
	for subject: Variant in subjects:
		if subject is Node3D:
			typed_subjects.append(subject)
	var target := _subjects_center(typed_subjects) + Vector3.UP * 0.34
	camera.look_at_from_position(target + offset, target, Vector3.UP)


func _subjects_center(subjects: Array[Node3D]) -> Vector3:
	var center := Vector3.ZERO
	for subject: Node3D in subjects:
		center += subject.global_position
	return center / maxf(1.0, float(subjects.size()))


func _capture(file_name: String, label_text: String) -> void:
	evidence_label.text = label_text
	await _settle(6)
	var raw_image := game_viewport.get_texture().get_image()
	var raw_path := "/tmp".path_join(
		file_name.trim_suffix(".png") + "-raw-4x3.png"
	)
	var raw_error := raw_image.save_png(raw_path)
	if raw_error != OK:
		push_error("Could not save %s: %s" % [raw_path, error_string(raw_error)])
	else:
		output_paths.append(raw_path)
	var image := root.get_viewport().get_texture().get_image()
	var path := OUTPUT_ROOT.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
	else:
		output_paths.append(path)
		images.append(image)


func _settle(frame_count: int) -> void:
	for _frame in frame_count:
		await process_frame


func _save_montage(
	source_images: Array[Image],
	columns: int,
	cell_size: Vector2i,
	path: String,
) -> bool:
	var rows := int(ceil(float(source_images.size()) / float(columns)))
	var montage := Image.create(
		cell_size.x * columns,
		cell_size.y * rows,
		false,
		Image.FORMAT_RGBA8,
	)
	montage.fill(Color("#111820"))
	for index in source_images.size():
		montage.blit_rect(
			source_images[index],
			Rect2i(Vector2i.ZERO, cell_size),
			Vector2i(
				(index % columns) * cell_size.x,
				(index / columns) * cell_size.y,
			),
		)
	var error := montage.save_png(path)
	if error != OK:
		push_error("Could not save montage %s: %s" % [path, error_string(error)])
		return false
	return true
