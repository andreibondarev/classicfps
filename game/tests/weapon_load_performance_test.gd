extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var model := MdlViewModel.new()
	root.add_child(model)
	# Freeze animation while checking that preparation itself is non-mutating.
	model.set_process(false)
	for weapon: String in ["ak47", "m4a1", "deagle", "knife", "m4a1"]:
		var started := Time.get_ticks_usec()
		if not model.load_weapon(weapon):
			push_error("Cannot benchmark weapon: " + weapon)
			quit(1)
			return
		model.play_action("switch")
		print("WEAPON_LOAD_CPU ", JSON.stringify({"total_ms": float(Time.get_ticks_usec() - started) / 1000.0, "phases": model.last_load_timings}))
		await process_frame
	var preparation_started := Time.get_ticks_usec()
	var active_root := model.model_root
	var active_mesh := model._model_instance.mesh
	if not await model.prepare_weapon_assets(CS16WeaponRegistry.WEAPONS.keys()):
		quit(1)
		return
	if model.model_root != active_root or model._model_instance.mesh != active_mesh or model.loaded_weapon != "m4a1":
		push_error("Catalog preparation changed the active weapon presentation")
		quit(1)
		return
	var prepared_count := MdlViewModel._prepared_weapon_assets.size()
	if prepared_count != CS16WeaponRegistry.WEAPONS.size() or not await model.prepare_weapon_assets(CS16WeaponRegistry.WEAPONS.keys()):
		push_error("Catalog preparation is incomplete or not repeatable")
		quit(1)
		return
	print("WEAPON_PREPARATION_CPU ", JSON.stringify({"ms": float(Time.get_ticks_usec() - preparation_started) / 1000.0,
		"weapons": MdlViewModel._prepared_weapon_assets.size(), "memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)}))
	_check_prepared_geometry()
	for weapon: String in ["awp", "p90", "famas", "m4a1"]:
		var started := Time.get_ticks_usec()
		if not model.load_weapon(weapon):
			quit(1)
			return
		model.play_action("switch")
		print("PREPARED_WEAPON_LOAD_CPU ", JSON.stringify({"total_ms": float(Time.get_ticks_usec() - started) / 1000.0, "phases": model.last_load_timings}))
		await process_frame
	model.queue_free()
	await process_frame
	MdlViewModel.release_cached_resources()
	_check(MdlViewModel._prepared_weapon_assets.is_empty(), "cache release frees prepared geometry")
	var empty := MdlViewModel.new()
	root.add_child(empty)
	empty.set_process(false)
	_check(await empty.prepare_weapon_assets(["knife"]), "geometry can be prepared before any weapon is equipped")
	_check(empty.loaded_weapon.is_empty() and empty.get_child_count() == 0, "preparation creates no animated weapon nodes")
	var prepared: Dictionary = MdlViewModel._prepared_weapon_assets.knife
	var before_frames := Engine.get_process_frames()
	_check(await empty.prepare_weapon_assets(["knife"]), "repeated empty-model preparation succeeds")
	_check(is_same(prepared, MdlViewModel._prepared_weapon_assets.knife) and Engine.get_process_frames() == before_frames,
		"already prepared geometry is reused without another loading slice")
	empty.free()
	MdlViewModel.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	for failure in failures:
		push_error(failure)
	print("GAME_WEAPON_LOAD_PERFORMANCE_PASS" if failures.is_empty() else "GAME_WEAPON_LOAD_PERFORMANCE_FAIL")
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _check_prepared_geometry() -> void:
	var frames_checked := 0
	var geometry_bytes := 0
	for weapon: String in CS16WeaponRegistry.WEAPONS:
		var candidate := MdlViewModel.new()
		root.add_child(candidate)
		candidate.set_process(false)
		_check(candidate.load_weapon(weapon), "prepared weapon loads: " + weapon)
		var initial: Dictionary = MdlViewModel._prepared_weapon_assets[weapon]
		_check(initial.size() == candidate._template.animations.size(), "every initial animation pose is prepared")
		for name: String in candidate._template.animations:
			var cached := candidate._cached_frame(name, 0)
			_check(bool(cached.prepared_geometry), "frame zero uses prepared geometry: " + weapon + ":" + name)
			var mesh: ArrayMesh = cached.mesh
			# Independent source-to-mesh construction, not the new prepared-array
			# builder. The original shading arithmetic is unchanged by preparation.
			var reference := MeshInstance3D.new()
			reference.mesh = ArrayMesh.new()
			reference.set_meta("group_materials", candidate._model_instance.get_meta("group_materials"))
			MdlCharacterModel._render_frame(reference, candidate._template,
				candidate._template.animations[name].positions, 0)
			candidate._inject_flat_normals(reference.mesh)
			_check(mesh.get_surface_count() == reference.mesh.get_surface_count(), "prepared surface count matches source")
			for surface in mesh.get_surface_count():
				var actual := mesh.surface_get_arrays(surface)
				var expected := reference.mesh.surface_get_arrays(surface)
				for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
					_check(actual[attribute] == expected[attribute], "prepared attribute matches source: %s:%s:%d" % [weapon, name, attribute])
				_check(mesh.surface_get_material(surface) == reference.mesh.surface_get_material(surface), "prepared geometry uses instance material identity")
			var expected_muzzle := candidate._muzzle_point_for_mesh(reference.mesh)
			_check((cached.muzzle_local as Vector3).is_equal_approx(expected_muzzle),
				"prepared muzzle matches source: %s:%s actual=%s expected=%s" % [weapon, name, cached.muzzle_local, expected_muzzle])
			for surface: Array in initial[name].surfaces:
				_check(surface[1] == null, "shared prepared geometry retains no materials")
				for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
					geometry_bytes += surface[0][attribute].to_byte_array().size()
			# Uploading/shading another instance must not mutate shared CPU arrays.
			var before: PackedColorArray = initial[name].surfaces[0][0][Mesh.ARRAY_COLOR].duplicate()
			var changed := mesh.surface_get_arrays(0)
			changed[Mesh.ARRAY_COLOR][0] = Color.MAGENTA
			_check(initial[name].surfaces[0][0][Mesh.ARRAY_COLOR] == before, "mesh reads cannot mutate prepared colors")
			frames_checked += 1
			reference.free()
		var idle := candidate._idle_animation()
		if int(candidate._template.animations[idle].frames) > 1:
			_check(not bool(candidate._cached_frame(idle, 1).prepared_geometry), "later frames retain the bounded on-demand path")
		candidate.free()
	print("PREPARED_GEOMETRY_PARITY ", JSON.stringify({"frames": frames_checked, "packed_geometry_bytes": geometry_bytes}))
