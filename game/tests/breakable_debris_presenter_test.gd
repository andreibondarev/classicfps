extends SceneTree

const PresenterScript := preload("res://scripts/cs16_breakable_debris_presenter.gd")
const GameScript := preload("res://scripts/game.gd")
const GIB_ROOT := "res://generated/gibs"
const CAPTURE_PATH := "res://artifacts/protocol47-breakable-debris.png"
const MOTION_CAPTURE_PATH := "res://artifacts/protocol47-breakable-debris-motion.png"
const REQUIRE_VISUAL_ARG := "--require-visual-capture"
const CELL_SIZE := Vector2i(640, 520)
const GAME_SIZE := Vector2i(640, 480)

## cs_assault func_breakables staged for the in-map family-match proof:
## entity id -> [gib family, camera offset from brush center, settle frames,
## look-target offset from brush center].
const MAP_BREAKS := [
	# Capture wood after the planks land: entity 114 is a wall-mounted panel
	# ~1.4m up, so its grained plank fragments rain to the floor and settle
	# there (~tick 122) — aim at the floor beneath the break, like the pile
	# CS 1.6 leaves behind, not a frozen mid-air burst.
	[114, "woodgibs", Vector3(0.38, -0.83, 0.60), 60, Vector3(-0.17, -1.43, -0.25)],
	[115, "glassgibs", Vector3(-1.15, 0.42, -0.45), 30, Vector3.ZERO],
	[79, "computergibs", Vector3(-0.72, 0.42, 0.66), 34, Vector3.ZERO],
]

const EXPECTED_VARIANTS := {
	"ceilinggibs": 4,
	"cindergibs": 9,
	"computergibs": 15,
	"fleshgibs": 4,
	"glassgibs": 8,
	"metalplategibs": 13,
	"mil_crategibs": 17,
	"woodgibs": 3,
}

var failures: Array[String] = []


class FakeRuntime:
	extends RefCounted
	signal runtime_event(event: Dictionary)

	func emit_descriptor(event: Dictionary) -> void:
		runtime_event.emit(event)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_variant_exports()
	_assert_deterministic_presentation()
	_assert_runtime_binding_and_missing_asset_gate()
	await _assert_world_collision_and_settling()
	await _assert_visual_render()
	PresenterScript.release_cached_resources()
	if failures.is_empty():
		print("BREAKABLE_DEBRIS_PRESENTER_TEST_PASS")
		quit(0)
	else:
		print("BREAKABLE_DEBRIS_PRESENTER_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BREAKABLE DEBRIS PRESENTER TEST: " + message)


func _descriptor(gib_name := "woodgibs", seed := 12345) -> Dictionary:
	return {
		"event": "debris",
		"entity_id": 79,
		"model_index": 54,
		"material": 1,
		"material_name": "wood",
		"origin": Vector3.ZERO,
		"size": Vector3(0.4, 0.3, 0.5),
		"velocity": Vector3(0.25, 1.2, -0.15),
		"randomization": 10,
		"gib_model": "models/%s.mdl" % gib_name,
		"shard_count": 0,
		"duration_seconds": 2.5,
		"break_flag": 8,
		"break_flag_name": "wood",
		"seed": seed,
	}


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _assert_variant_exports() -> void:
	var total_variants := 0
	var nonempty_variants := 0
	for gib_name: String in EXPECTED_VARIANTS:
		var root_path := "%s/%s" % [GIB_ROOT, gib_name]
		var manifest := _load_json(root_path.path_join("variants.json"))
		var expected := int(EXPECTED_VARIANTS[gib_name])
		_check(
			manifest.format == "protocol47-mdl-body-variants"
			and int(manifest.version) == 1
			and manifest.variants.size() == expected,
			"%s exports all %d authored body variants" % [gib_name, expected],
		)
		total_variants += manifest.get("variants", []).size()
		for relative_path: String in manifest.get("variants", []):
			var model_path := root_path.path_join(relative_path)
			var model := _load_json(model_path)
			_check(
				model.format == "protocol47-mdl" and int(model.version) == 1,
				"%s contains a valid static MDL variant" % model_path,
			)
			if not model.get("positions", []).is_empty():
				nonempty_variants += 1
				_check(
					not model.get("groups", []).is_empty(),
					"%s renderable geometry retains original texture groups"
					% model_path,
				)
				for group: Dictionary in model.get("groups", []):
					var texture_path := str(group.get("texture", ""))
					if not texture_path.is_empty():
						_check(
							FileAccess.file_exists(
								model_path.get_base_dir().path_join(texture_path),
							),
							"%s retains its converted stock texture" % model_path,
						)
	_check(total_variants == 73, "all eight gib MDLs expose 73 authored body variants")
	_check(
		nonempty_variants == 72,
		"only the stock glass model's intentional blank body lacks geometry",
	)


func _assert_deterministic_presentation() -> void:
	var presenter_a := PresenterScript.new()
	presenter_a.name = "DebrisPresenterA"
	root.add_child(presenter_a)
	var presenter_b := PresenterScript.new()
	presenter_b.name = "DebrisPresenterB"
	root.add_child(presenter_b)
	var descriptor := _descriptor("woodgibs", 99173)
	_check(
		presenter_a.present_debris(descriptor) == 15
		and presenter_b.present_debris(descriptor) == 15,
		"TE_BREAKMODEL shard count zero selects the size-derived burst count",
	)
	var initial_a := presenter_a.motion_snapshot()
	var initial_b := presenter_b.motion_snapshot()
	_check(initial_a == initial_b, "equal debris descriptors produce identical initial shards")
	var body_variants := {}
	for shard: Dictionary in initial_a:
		body_variants[int(shard.body_variant)] = true
		var node := presenter_a.get_node(NodePath(str(shard.name))) as Node3D
		var mesh := node.get_child(0) as MeshInstance3D
		_check(
			mesh != null
			and mesh.mesh != null
			and mesh.mesh.get_surface_count() > 0
			and shard.model_path.contains("/variants/"),
			"every debris shard is authentic converted variant geometry",
		)
	_check(
		body_variants.size() == 3,
		"wood debris selects all three authored submodels instead of cloning body zero",
	)
	presenter_a.advance_tick()
	presenter_b.advance_tick()
	var advanced_a := presenter_a.motion_snapshot()
	var advanced_b := presenter_b.motion_snapshot()
	_check(advanced_a == advanced_b, "fixed impulses and spins replay exactly at 100 Hz")
	_check(
		advanced_a[0].position != initial_a[0].position
		and advanced_a[0].rotation != initial_a[0].rotation,
		"debris advances both ballistic position and authored-shard spin",
	)
	presenter_a.advance_ticks(248)
	_check(
		presenter_a.active_shard_count() == 15,
		"2.5-second debris remains visible through tick 249",
	)
	presenter_a.advance_tick()
	_check(
		presenter_a.active_shard_count() == 0,
		"debris lifetime expires exactly on fixed tick 250",
	)
	presenter_a.queue_free()
	presenter_b.queue_free()


func _assert_runtime_binding_and_missing_asset_gate() -> void:
	var presenter := PresenterScript.new()
	presenter.name = "BoundDebrisPresenter"
	root.add_child(presenter)
	var runtime := FakeRuntime.new()
	presenter.bind_runtime(runtime)
	runtime.emit_descriptor(_descriptor("computergibs", 551))
	_check(
		presenter.active_shard_count() == 15
		and presenter.presentation_log[0].event == "debris_presented",
		"runtime debris signal is consumed without Game-specific wiring",
	)
	var children_before := presenter.get_child_count()
	runtime.emit_descriptor(_descriptor("rockgibs", 552))
	_check(
		presenter.active_shard_count() == 15
		and presenter.get_child_count() == children_before
		and presenter.presentation_log[-1].event == "asset_missing",
		"unsupported rockgibs descriptor fails explicitly without placeholder primitives",
	)
	presenter.queue_free()


func _assert_world_collision_and_settling() -> void:
	var floor := StaticBody3D.new()
	floor.name = "DebrisCollisionFloor"
	floor.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.05, 4.0)
	floor_shape.shape = box
	floor_shape.position.y = -0.025
	floor.add_child(floor_shape)
	root.add_child(floor)

	var presenter := PresenterScript.new()
	presenter.name = "CollidingDebrisPresenter"
	root.add_child(presenter)
	await physics_frame
	var descriptor := _descriptor("woodgibs", 9011)
	descriptor.origin = Vector3(0.0, 0.22, 0.0)
	descriptor.size = Vector3.ZERO
	descriptor.velocity = Vector3.ZERO
	descriptor.randomization = 0
	descriptor.shard_count = 1
	_check(presenter.present_debris(descriptor) == 1, "collision probe spawns one stock shard")
	presenter.advance_ticks(140)
	var snapshot := presenter.motion_snapshot()
	_check(
		snapshot.size() == 1
		and int(snapshot[0].bounce_count) > 0
		and bool(snapshot[0].grounded)
		and float((snapshot[0].position as Vector3).y) > 0.0
		and float((snapshot[0].position as Vector3).y) <= 0.02,
		"ballistic stock gib collides, bounces, and settles on world geometry",
	)
	presenter.queue_free()
	floor.queue_free()
	await process_frame


## In-map proof: shooting real cs_assault func_breakables must shed debris of
## the family matching the broken surface (wood crate -> woodgibs, window ->
## glassgibs, console -> computergibs), lit by the map at the break site.
func _assert_visual_render() -> void:
	if DisplayServer.get_name() == "headless":
		if OS.get_cmdline_user_args().has(REQUIRE_VISUAL_ARG):
			_check(false, "visual capture gate requires a production display driver")
		else:
			print(
				"BREAKABLE_DEBRIS_VISUAL_CAPTURE_SKIP "
				+ "(rerun with a production display driver and %s)" % REQUIRE_VISUAL_ARG
			)
		return
	root.size = CELL_SIZE
	root.content_scale_size = CELL_SIZE
	var shell := Control.new()
	shell.size = Vector2(CELL_SIZE)
	root.add_child(shell)
	var background := ColorRect.new()
	background.color = Color("#111820")
	background.size = Vector2(CELL_SIZE)
	shell.add_child(background)
	var container := SubViewportContainer.new()
	container.size = Vector2(GAME_SIZE)
	container.stretch = true
	shell.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = GAME_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var label := Label.new()
	label.position = Vector2(14.0, 488.0)
	label.size = Vector2(612.0, 28.0)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("#edf4f7"))
	shell.add_child(label)

	var game := GameScript.new()
	game.map_name = "cs_assault"
	viewport.add_child(game)
	await process_frame
	await physics_frame
	if not bool(game.using_imported_map) or game.breakable_runtime == null:
		_check(false, "in-map debris capture loads production cs_assault")
		return
	game.hud.visible = false
	game.match_started = false
	for actor: Node in [game.player] + game.allied_bots + game.targets:
		if not is_instance_valid(actor):
			continue
		actor.visible = false
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.fov = 90.0
	camera.near = 0.03
	game.add_child(camera)
	camera.current = true
	for _i in range(4):
		await process_frame

	var cells: Array[Image] = []
	var motion_image: Image = null
	for break_spec: Array in MAP_BREAKS:
		var entity_id := int(break_spec[0])
		var family := str(break_spec[1])
		var offset: Vector3 = break_spec[2]
		var settle_frames := int(break_spec[3])
		var record: Dictionary = game.breakable_runtime.get_breakable(entity_id)
		_check(
			not record.is_empty(),
			"cs_assault exposes staged func_breakable %d" % entity_id,
		)
		if record.is_empty():
			continue
		var center: Vector3 = record.center
		var look_offset: Vector3 = break_spec[4]
		camera.look_at_from_position(
			center + offset,
			center + look_offset,
			Vector3.UP,
		)
		var log_start := game.breakable_debris.presentation_log.size()
		var result: Dictionary = game.breakable_runtime.damage(
			entity_id,
			900,
			900,
			2000.0,
			2,
			(center - (center + offset)).normalized(),
		)
		_check(
			bool(result.get("broken", false)),
			"live bullet damage breaks func_breakable %d in-map" % entity_id,
		)
		var presented := false
		for event: Dictionary in game.breakable_debris.presentation_log.slice(log_start):
			if (
				str(event.get("event", "")) == "debris_presented"
				and str(event.get("gib_model", "")).contains(family)
			):
				presented = true
		_check(
			presented,
			"%s break sheds %s debris at the break site" % [
				str(record.material_name),
				family,
			],
		)
		game.breakable_debris.advance_ticks(10)
		# The staged capture documents debris material matching; hide the
		# separate explosion/impact VFX layer so it cannot obscure the shards
		# (the console's env_explosion fireball fills the whole frame).
		var effects_overlay := game.get_node_or_null("CS16CombatEffects")
		if effects_overlay is Node3D:
			(effects_overlay as Node3D).visible = false
		label.text = (
			"IN-MAP BREAK  ·  entity %d  ·  material=%s  ·  debris=%s"
			% [entity_id, str(record.material_name), family]
		)
		if entity_id == int((MAP_BREAKS[-1] as Array)[0]):
			# The motion frame must evidence the burst itself: grab it ~0.16s
			# after the break impulse while the gibs are still mid-air and
			# tumbling, before the settle loop lays them to rest.
			game.breakable_debris.advance_ticks(6)
			for _i in range(2):
				await process_frame
			RenderingServer.force_draw()
			motion_image = root.get_viewport().get_texture().get_image()
		for _i in range(settle_frames):
			await process_frame
			game.breakable_debris.advance_ticks(2)
		RenderingServer.force_draw()
		var shell_image := root.get_viewport().get_texture().get_image()
		_check(
			shell_image != null and not shell_image.is_empty(),
			"production renderer returns in-map debris pixels",
		)
		if shell_image != null:
			cells.append(shell_image)

	_check(cells.size() == MAP_BREAKS.size(), "every staged in-map break captured a frame")
	if cells.size() == MAP_BREAKS.size():
		var montage := Image.create(
			CELL_SIZE.x * cells.size(),
			CELL_SIZE.y,
			false,
			Image.FORMAT_RGBA8,
		)
		montage.fill(Color("#111820"))
		for cell_index in cells.size():
			montage.blit_rect(
				cells[cell_index],
				Rect2i(Vector2i.ZERO, CELL_SIZE),
				Vector2i(cell_index * CELL_SIZE.x, 0),
			)
		_check(
			montage.save_png(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK,
			"in-map debris family-match capture is writable",
		)
	_check(
		motion_image != null and not motion_image.is_empty(),
		"in-map debris motion frame captured",
	)
	if motion_image != null and not motion_image.is_empty():
		_check(
			motion_image.save_png(
				ProjectSettings.globalize_path(MOTION_CAPTURE_PATH)
			) == OK,
			"ballistic debris motion capture is writable",
		)
	game.queue_free()
	viewport.queue_free()
	await process_frame
