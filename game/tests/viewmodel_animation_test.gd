extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var viewmodel := MdlViewModel.new()
	stage.add_child(viewmodel)

	_check(viewmodel.load_weapon("ak47"), "animated AK-47 viewmodel loads")
	_check(
		viewmodel.base_position == MdlViewModel.CLASSIC_BASE_POSITION,
		"AK-47 uses the calibrated classic camera-space placement",
	)
	_check(
		viewmodel.model_root.scale == MdlViewModel.CLASSIC_MODEL_SCALE,
		"AK-47 uses the calibrated mirrored horizontal framing",
	)
	_check(viewmodel._template.animations.has("idle1"), "AK-47 idle sequence is available")
	_check(viewmodel._template.animations.has("reload"), "AK-47 reload sequence is available")
	_check(viewmodel._template.animations.has("shoot1"), "AK-47 fire sequence is available")
	_check(
		viewmodel._frame_mesh_cache.has("shoot1:0")
		and viewmodel._frame_mesh_cache.has("shoot2:0")
		and viewmodel._frame_mesh_cache.has("shoot3:0"),
		"AK-47 trigger frames are prepared before combat",
	)
	_check(
		is_instance_valid(viewmodel._model_instance)
		and viewmodel._model_instance.mesh.get_surface_count() == 11,
		"AK-47 renders all original MDL texture groups",
	)
	for group: Dictionary in viewmodel._template.groups:
		var material := group.material as StandardMaterial3D
		_check(
			material != null and not material.no_depth_test,
			"AK-47 texture groups retain self-depth instead of material-order overpaint",
		)
	viewmodel._start_animation("shoot1", false)
	viewmodel._process(0.01)
	var first_fire_mesh := viewmodel._model_instance.mesh
	_assert_cpu_frame_matches_legacy(viewmodel, "shoot1", 0)
	_assert_cpu_frame_matches_legacy(viewmodel, "reload", 5)
	var first_fire_muzzle := viewmodel.muzzle_point_world()
	viewmodel._start_animation("shoot1", false)
	viewmodel._process(0.01)
	_check(
		viewmodel._model_instance.mesh == first_fire_mesh,
		"replayed fire frames reuse their completed ArrayMesh",
	)
	_check(
		viewmodel.muzzle_point_world().is_equal_approx(first_fire_muzzle),
		"cached fire frames retain their authored muzzle point",
	)
	var queued_fire_frames := viewmodel._fire_prewarm_queue.size()
	viewmodel._start_animation("idle1", true)
	for ignored_frame in range(4):
		viewmodel._process(0.01)
	_check(
		viewmodel._fire_prewarm_queue.size() < queued_fire_frames,
		"idle render slices prepare later fire frames ahead of combat",
	)

	viewmodel.play_action("fire")
	_check(viewmodel._animation_name.begins_with("shoot"), "fire selects an MDL shoot sequence")
	viewmodel._process(0.1)
	_check(viewmodel._frame_key.begins_with("shoot"), "fire advances an animated MDL frame")
	viewmodel._process(2.0)
	_check(viewmodel._animation_name == "idle1", "completed fire returns to looping idle")

	viewmodel.play_action("reload")
	_check(viewmodel._animation_name == "reload", "reload selects the original MDL sequence")
	viewmodel._process(0.25)
	_check(viewmodel._frame_key.begins_with("reload"), "reload advances original MDL frames")

	_check(viewmodel.load_weapon("knife"), "animated knife viewmodel loads")
	_check(not viewmodel._frame_mesh_cache.has("reload:5"), "weapon switch isolates active weapon geometry")
	for group: Dictionary in viewmodel._template.groups:
		var material := group.material as StandardMaterial3D
		_check(
			material != null and not material.no_depth_test,
			"knife texture groups retain self-depth",
		)
	viewmodel.play_action("knife")
	_check(
		viewmodel._animation_name == "midslash1",
		"knife attack selects the full slash, not the two-frame placeholder",
	)
	viewmodel._process(0.2)
	_check(viewmodel._animation_name == "midslash1", "slash continues beyond the old 67ms blink")
	viewmodel.play_action("knife")
	_check(viewmodel._animation_name == "midslash2", "primary slashes alternate")
	for action in ["stab", "stab_miss"]:
		viewmodel.play_action(action)
		viewmodel._process(0.2)
		_check(viewmodel._animation_name == action, "stab plays its distinct hit/miss motion")
		viewmodel._process(2.0)
		_check(viewmodel._animation_name == "idle", "completed knife action returns to idle")
	for weapon in ["m4a1", "usp"]:
		viewmodel.load_weapon(weapon)
		for silenced in [false, true, false]:
			viewmodel.set_silenced(silenced)
			var suffix := "" if silenced else "_unsil"
			for pair in [["switch", "draw"], ["reload", "reload"], ["fire", "shoot1"]]:
				viewmodel.play_action(pair[0])
				_check(viewmodel._animation_name == pair[1] + suffix, weapon + " action matches silencer state")
				viewmodel._process(5.0)
				_check(viewmodel._animation_name == "idle" + suffix, weapon + " returns to matching idle")

	_check(viewmodel.load_weapon("glock18"), "animated Glock viewmodel loads")
	_check(
		viewmodel.base_position == MdlViewModel.GLOCK_BASE_POSITION,
		"Glock uses its measured bottom-edge camera-space placement",
	)
	_check(
		is_instance_valid(viewmodel._model_instance)
		and viewmodel._model_instance.mesh.get_surface_count() == 7,
		"Glock renders all original MDL texture groups",
	)
	for group: Dictionary in viewmodel._template.groups:
		var material := group.material as StandardMaterial3D
		_check(
			material != null and not material.no_depth_test,
			"Glock texture groups retain self-depth",
		)

	_check(viewmodel.load_weapon("c4"), "animated C4 viewmodel loads")
	_check(
		viewmodel.base_position == MdlViewModel.C4_BASE_POSITION
		and viewmodel.model_root.scale == MdlViewModel.C4_MODEL_SCALE,
		"C4 uses its source-model-specific full-frame calibration",
	)
	_check(
		viewmodel._template.animations.has("draw")
		and viewmodel._template.animations.has("pressbutton")
		and viewmodel._template.animations.has("drop"),
		"C4 exposes the original deploy/arming/final-drop sequence strip",
	)
	_check(
		is_instance_valid(viewmodel._model_instance)
		and viewmodel._model_instance.mesh.get_surface_count() == 8,
		"C4 renders every original v_c4 texture group",
	)
	await _assert_weapon_residency(stage)

	for grenade: String in ["hegrenade", "flashbang", "smokegrenade"]:
		_check(viewmodel.load_weapon(grenade), "grenade viewmodel loads: " + grenade)
		for action: String in ["pullpin", "throw"]:
			viewmodel.play_action(action)
			_check(viewmodel._animation_name == action, "original grenade animation selected: " + grenade + "/" + action)
			viewmodel._process(0.1)
			_check(viewmodel._frame_key.begins_with(action + ":"), "grenade animation advances original frames: " + grenade + "/" + action)

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("GAME_VIEWMODEL_ANIMATION_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return

	print("GAME_VIEWMODEL_ANIMATION_TEST_PASS")
	quit()


func _assert_weapon_residency(stage: Node3D) -> void:
	var viewmodel := MdlViewModel.new()
	stage.add_child(viewmodel)
	viewmodel.set_process(false)
	viewmodel.load_weapon("ak47")
	viewmodel._start_animation("shoot1", false)
	viewmodel._process(0.01)
	var ak_root := viewmodel.model_root
	var ak_instance := viewmodel._model_instance
	var fire_mesh := viewmodel._model_instance.mesh
	viewmodel.load_weapon("knife")
	_check(not ak_root.is_visible_in_tree(), "parked weapons are hidden")
	_check(ak_instance.mesh == fire_mesh, "parking keeps the completed frame mesh")
	viewmodel._process(0.2)
	_check(ak_instance.mesh == fire_mesh, "inactive weapons are not animated")
	viewmodel.load_weapon("ak47")
	_check(bool(viewmodel.last_load_timings.reused_model) and viewmodel.model_root == ak_root
		and viewmodel._model_instance == ak_instance, "recent weapon reload reuses its model and material owners")
	_check(viewmodel._animation_name == "idle1" and viewmodel._animation_time == 0.0
		and viewmodel._action_serial == 0 and viewmodel._light_snap, "restoring a weapon resets action and lighting state")
	_check(viewmodel._cached_frame("shoot1", 0).mesh == fire_mesh, "restoring keeps precomputed trigger geometry")
	_assert_cpu_frame_matches_legacy(viewmodel, "shoot1", 0)
	_assert_cpu_frame_matches_legacy(viewmodel, "idle1", 0)
	var other := MdlViewModel.new()
	stage.add_child(other)
	other.set_process(false)
	other.load_weapon("ak47")
	_check(other._cached_frame("shoot1", 0).mesh != fire_mesh, "weapon residency is local to each viewmodel")
	var our_material: Material = ak_instance.get_meta("group_materials")[0]
	var other_material: Material = other._model_instance.get_meta("group_materials")[0]
	_check(our_material != other_material, "different players never share mutable viewmodel tint materials")
	other.queue_free()

	var roots: Array[WeakRef] = [weakref(ak_root)]
	for weapon: String in CS16WeaponRegistry.ROSTER:
		_check(viewmodel.load_weapon(weapon), "residency catalog loads " + weapon)
		roots.append(weakref(viewmodel.model_root))
		await process_frame
		_check(viewmodel._parked_weapons.size() <= MdlViewModel.MAX_PARKED_WEAPONS,
			"parked weapon count remains bounded")
		_check(viewmodel.get_child_count() <= MdlViewModel.MAX_PARKED_WEAPONS + 1,
			"evicted weapon nodes are actually retired")
		var visible_roots := 0
		for child: Node3D in viewmodel.get_children():
			if child.is_visible_in_tree():
				visible_roots += 1
		_check(visible_roots == 1, "only the equipped weapon draws")
		for parked: Dictionary in viewmodel._parked_weapons.values():
			_check(parked.frames.size() <= MdlViewModel.MAX_CACHED_FRAME_MESHES,
				"each parked weapon keeps the existing frame-cache cap")
	_check(not is_instance_valid(ak_root), "least-recently-used weapon is evicted across the catalog")
	# The roster itself can revisit AK late in the traversal. Select an entry
	# that is actually absent now, not a weapon whose earlier instance expired.
	var evicted_weapon := ""
	for weapon: String in CS16WeaponRegistry.ROSTER:
		if weapon != viewmodel.loaded_weapon and not viewmodel._parked_weapons.has(weapon):
			evicted_weapon = weapon
			break
	_check(not evicted_weapon.is_empty(), "catalog traversal exceeds the residency capacity")
	viewmodel.load_weapon(evicted_weapon)
	_check(not bool(viewmodel.last_load_timings.reused_model), "an evicted weapon reloads through normal construction")
	_assert_cpu_frame_matches_legacy(viewmodel, viewmodel._idle_animation(), 0)
	roots.append(weakref(viewmodel.model_root))
	viewmodel.load_weapon("m4a1")
	roots.append(weakref(viewmodel.model_root))
	var initial_keys := viewmodel._frame_mesh_cache.keys()
	var oldest_key: String = viewmodel._frame_mesh_cache_order[0]
	var requested_frames := initial_keys.size()
	for animation_name: String in viewmodel._template.animations:
		var animation: Dictionary = viewmodel._template.animations[animation_name]
		for frame in int(animation.frames):
			if initial_keys.has("%s:%d" % [animation_name, frame]):
				continue
			viewmodel._cached_frame(animation_name, frame)
			requested_frames += 1
			_check(viewmodel._frame_mesh_cache.size() <= MdlViewModel.MAX_CACHED_FRAME_MESHES,
				"frame capacity holds on every insertion")
			if requested_frames > MdlViewModel.MAX_CACHED_FRAME_MESHES:
				break
		if requested_frames > MdlViewModel.MAX_CACHED_FRAME_MESHES:
			break
	_check(requested_frames > MdlViewModel.MAX_CACHED_FRAME_MESHES
		and not viewmodel._frame_mesh_cache.has(oldest_key), "frame-cap boundary actually evicts old geometry")
	viewmodel.load_weapon("knife")
	_check(viewmodel._parked_weapons.m4a1.frames.size() == MdlViewModel.MAX_CACHED_FRAME_MESHES,
		"parking a full frame cache preserves its bound")
	viewmodel.load_weapon("m4a1")
	_check(bool(viewmodel.last_load_timings.reused_model)
		and viewmodel._frame_mesh_cache.size() == MdlViewModel.MAX_CACHED_FRAME_MESHES,
		"restoring a full frame cache rewarms trigger frames within the same bound")
	_assert_cpu_frame_matches_legacy(viewmodel, "shoot1", 0)
	viewmodel.queue_free()
	await process_frame
	for reference: WeakRef in roots:
		_check(reference.get_ref() == null, "viewmodel teardown releases active and parked models")


func _assert_cpu_frame_matches_legacy(viewmodel: MdlViewModel, animation_name: String, frame: int) -> void:
	var legacy := MeshInstance3D.new()
	legacy.mesh = ArrayMesh.new()
	legacy.set_meta("group_materials", viewmodel._model_instance.get_meta("group_materials"))
	MdlCharacterModel._render_frame(
		legacy, viewmodel._template, viewmodel._template.animations[animation_name].positions,
		frame * int(viewmodel._template.vertex_float_count),
	)
	viewmodel._inject_flat_normals(legacy.mesh)
	var cached := viewmodel._cached_frame(animation_name, frame)
	var mesh: ArrayMesh = cached.mesh
	_check(mesh.get_surface_count() == legacy.mesh.get_surface_count(), "CPU frame retains all surfaces")
	for surface in range(mesh.get_surface_count()):
		var actual := mesh.surface_get_arrays(surface)
		var expected := legacy.mesh.surface_get_arrays(surface)
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
			_check(actual[attribute] == expected[attribute], "%s:%d CPU attribute %d matches legacy" % [animation_name, frame, attribute])
		_check(mesh.surface_get_material(surface) == legacy.mesh.surface_get_material(surface), "CPU frame retains material identity")
	_check((cached.muzzle_local as Vector3).is_equal_approx(viewmodel._muzzle_point_for_mesh(legacy.mesh)), "CPU muzzle matches rendered vertices")
	legacy.free()
