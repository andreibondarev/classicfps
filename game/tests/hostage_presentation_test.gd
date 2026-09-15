extends SceneTree

class ReferenceHostage extends MdlHostageModel:
	func _pose_may_be_visible() -> bool:
		return true

class CountedHostage extends ReferenceHostage:
	var submissions := 0
	func _render_current_pose() -> void:
		var before := current_frame_key
		super._render_current_pose()
		if current_frame_key != before:
			submissions += 1

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	root.size = Vector2i(640, 480)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	_assert_batched_submission(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(0, 0.5, 0)
	camera.make_current()
	var model := MdlHostageModel.new()
	stage.add_child(model)
	model.set_process(false)
	model.position = Vector3(30, 0, -5)
	var reference := ReferenceHostage.new()
	stage.add_child(reference)
	reference.set_process(false)
	reference.hide()
	_check(model.model_loaded and reference.model_loaded, "both source models load")
	_check(not model._pose_may_be_visible(), "offscreen source envelope is culled")
	_assert_bounds(reference)
	for actor: MdlHostageModel in [model, reference]:
		actor.force_state("idle")
		actor.set_motion_speed_hu(250.0)
	_advance_pair(model, reference, 30)
	var stale_key := model.current_frame_key
	_check(stale_key != reference.current_frame_key, "offscreen mesh stays unsubmitted while clock advances")
	model.set_skin(model.skin_index + 2)
	_check(model.current_frame_key == stale_key, "equivalent skin update does not defeat offscreen pose skipping")
	for actor: MdlHostageModel in [model, reference]:
		actor.play_action("acknowledge")
	_advance_pair(model, reference, 220)
	_check(model._action_state.is_empty() and model.animation_state == "run", "offscreen action expires and returns to locomotion")
	for actor: MdlHostageModel in [model, reference]:
		actor.set_cowering(true)
	_advance_pair(model, reference, 30)
	for actor: MdlHostageModel in [model, reference]:
		actor.play_death()
	_advance_pair(model, reference, 200)
	camera.look_at(model.global_position + Vector3.UP * 0.4)
	_check(model._pose_may_be_visible(), "camera turn makes the envelope visible")
	model._process(0.0)
	_assert_same_pose(model, reference, "reentry without a physics tick")
	model.hide()
	_check(not model._pose_may_be_visible(), "rescued/hidden mesh skips deformation")
	model.force_state("walk", 13)
	_check(model.current_frame_key == "walk:2:3:2458", "explicit capture pose remains synchronous while hidden")
	model.show()
	camera.rotation = Vector3.ZERO
	model.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_check(model._pose_may_be_visible(), "unexpected shadow caster fails open")
	model.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_assert_other_viewports(stage, model)
	# Changing the ancestor basis must not underbound nonuniform scale or shear.
	model.basis = Basis(Vector3(2, 0, 0), Vector3(1, 0.5, 0), Vector3(0, 0, 3))
	camera.look_at(model.global_position)
	_check(model._pose_may_be_visible(), "affine-transformed source envelope remains visible")
	model.basis = reference.basis
	model.set_skin(1)
	var retired := model.mesh_instance
	_check(model.load_hostage(1), "same-skin reload succeeds")
	_check(retired.get_parent() == null and model.get_child_count() == 1, "reload immediately retires the old visual")
	_check(model.current_frame_key.begins_with("idle:"), "reload initializes its current pose")
	for material: StandardMaterial3D in model.mesh_instance.get_meta("group_materials"):
		_check(material.albedo_texture.resource_path.contains("skin1"), "same-skin reload binds both authored textures")
	var render_report := {}
	if DisplayServer.get_name() != "headless":
		render_report = await _assert_rendered_reentry(model, camera)
	print("HOSTAGE_PRESENTATION ", JSON.stringify(render_report))
	stage.queue_free()
	await process_frame
	_check(MdlHostageModel._pose_cameras.is_empty(), "removed cameras leave no registry references")
	MdlHostageModel.release_camera_registry()
	MdlCharacterModel.release_cached_resources()
	for failure: String in failures:
		push_error(failure)
	print("GAME_HOSTAGE_PRESENTATION_PASS" if failures.is_empty() else "GAME_HOSTAGE_PRESENTATION_FAIL")
	quit(0 if failures.is_empty() else 1)


func _advance_pair(model: MdlHostageModel, reference: MdlHostageModel, ticks: int) -> void:
	for tick in ticks:
		model.advance_tick()
		reference.advance_tick()
		# Reference intentionally submits every tick, as the old live path did.
		reference._process(0.0)
		_check(model._state_time == reference._state_time and model.animation_state == reference.animation_state
			and model._action_state == reference._action_state and model.playback_rate == reference.playback_rate,
			"culled and unconditional logical animation agree at every tick")


func _assert_batched_submission(stage: Node3D) -> void:
	var model := CountedHostage.new()
	var reference := ReferenceHostage.new()
	for actor: MdlHostageModel in [model, reference]:
		stage.add_child(actor)
		actor.set_process(false)
		actor.force_state("run")
		actor.set_motion_speed_hu(MdlHostageModel.RUN_SOURCE_SPEED_HU)
	model.submissions = 0
	var original_key := model.current_frame_key
	for tick in 7:
		model.advance_tick()
		reference.advance_tick()
		reference._process(0.0)
		_check(model._state_time == reference._state_time, "batched submission preserves every 100 Hz clock tick")
	_check(model.submissions == 0 and model.current_frame_key == original_key,
		"catch-up physics does not rebuild undisplayed intermediate meshes")
	_check(reference.current_frame_key != original_key, "per-tick reference actually advances its rendered pose")
	model._process(0.0)
	_check(model.submissions == 1, "one render update submits the latest of seven ticks")
	_assert_same_pose(model, reference, "batched render matches per-tick reference")
	model._process(0.0)
	_check(model.submissions == 1, "render without a new tick reuses the submitted pose")
	for actor: MdlHostageModel in [model, reference]:
		stage.remove_child(actor)
		actor.queue_free()


func _assert_same_pose(model: MdlHostageModel, reference: MdlHostageModel, label: String) -> void:
	_check(model.current_frame_key == reference.current_frame_key, label + " frame key")
	_check(model.mesh_instance.position == reference.mesh_instance.position, label + " grounding")
	for surface in model.mesh_instance.mesh.get_surface_count():
		_check(model.mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			== reference.mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX], label + " vertices")


func _assert_bounds(model: MdlHostageModel) -> void:
	var samples := 0
	for state: String in model._template.animations:
		var animation: Dictionary = model._template.animations[state]
		model.force_state(state)
		for frame in int(animation.frames):
			for alpha in [0.0, 0.25, 0.5, 0.75]:
				model._state_time = (float(frame) + alpha) / float(animation.fps)
				model._render_current_pose()
				# Dynamic vertex-region writes leave ArrayMesh.get_aabb()'s
				# creation-time box unchanged; rendering uses custom_aabb.
				var posed: AABB = (model.mesh_instance.mesh as ArrayMesh).custom_aabb
				posed.position += model.mesh_instance.position
				_check(model._grounded_bounds.encloses(posed), "authored/interpolated grounded pose fits source envelope: " + state)
				samples += 1
	print("HOSTAGE_BOUNDS samples=", samples, " bounds=", model._grounded_bounds)


func _assert_other_viewports(stage: Node3D, model: MdlHostageModel) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(320, 240)
	view.world_3d = model.get_world_3d()
	stage.add_child(view)
	var second := Camera3D.new()
	view.add_child(second)
	second.position = model.global_position + Vector3(0, 0.5, 3)
	second.look_at(model.global_position + Vector3.UP * 0.4)
	second.make_current()
	_check(model._pose_may_be_visible(), "new shared-world camera prevents culling outside the main view")
	second.cull_mask = 0
	_check(not model._pose_may_be_visible(), "all camera layer masks are respected")
	second.cull_mask = 1
	view.own_world_3d = true
	_check(not model._pose_may_be_visible(), "separate staging world camera cannot keep this model active")
	stage.remove_child(view)
	view.queue_free()
	_check(not model._pose_may_be_visible(), "removed camera no longer affects visibility")


func _capture() -> Image:
	for frame in range(4):
		await process_frame
	return root.get_texture().get_image()


func _different_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.0 / 255.0:
				count += 1
	return count


func _assert_rendered_reentry(model: MdlHostageModel, camera: Camera3D) -> Dictionary:
	model.position = Vector3(0, 0, -2)
	camera.position = Vector3(0, 0.4, 0)
	camera.rotation = Vector3.ZERO
	model.force_state("run")
	model.set_motion_speed_hu(MdlHostageModel.RUN_SOURCE_SPEED_HU)
	var draws := Engine.get_frames_drawn()
	var initial := await _capture()
	camera.rotation.y = PI
	for tick in 13:
		model.advance_tick()
	camera.rotation.y = 0.0
	# Deliberately omit the process update for a stale-pose negative control.
	var stale := await _capture()
	model._process(0.0)
	var optimized := await _capture()
	model.current_frame_key = ""
	model._render_current_pose()
	var reference := await _capture()
	model.hide()
	var background := await _capture()
	var result := {"rendered_frames": Engine.get_frames_drawn() - draws,
		"mismatch_pixels": _different_pixels(optimized, reference),
		"stale_mismatch_pixels": _different_pixels(stale, reference),
		"animated_pixels": _different_pixels(initial, reference),
		"hostage_pixels": _different_pixels(reference, background), "audio_muted": true,
		"finished_at_utc": Time.get_datetime_string_from_system(true)}
	_check(result.rendered_frames >= 19, "pixel checks actually rendered")
	_check(result.mismatch_pixels == 0, "reentry matches unconditional pose pixels")
	_check(result.stale_mismatch_pixels > 20 and result.animated_pixels > 20, "negative control detects stale animation")
	_check(result.hostage_pixels > 100, "hostage is visibly rendered")
	_check(reference.save_png("/tmp/protocol47-hostage-reentry.png") == OK, "save hostage reference capture")
	var file := FileAccess.open("res://artifacts/hostage-render-test-report.json", FileAccess.WRITE)
	_check(file != null, "open hostage rendered report")
	if file != null:
		result.ok = failures.is_empty()
		file.store_string(JSON.stringify(result, "  "))
		file.close()
	return result
