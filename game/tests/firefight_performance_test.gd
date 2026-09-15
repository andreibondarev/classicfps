extends SceneTree

## Presentation probe. --headless --fixed-fps 60 with --cpu-only measures CPU
## work only; a real rendered run is required to establish GPU frame pacing.
var game: Node
var report := {}
var fire_tick := 1000
var diagnostic_hide := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loading_started := Time.get_ticks_usec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--diagnostic-hide="):
			diagnostic_hide = argument.trim_prefix("--diagnostic-hide=")
	if diagnostic_hide not in ["", "effect_lights"]:
		push_error("Stationary render exclusions support effect_lights only")
		quit(1)
		return
	# Exercise audio routing/playback allocation without audible test gunfire.
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var headless := DisplayServer.get_name() == "headless"
	if headless and not OS.get_cmdline_user_args().has("--cpu-only"):
		push_error("Headless measurements require --cpu-only and cannot validate GPU performance.")
		quit(1)
		return
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	# Manual SceneTree fixtures assign current_scene after _ready(). Explicitly
	# attach the same scene effects service used by a normally launched match.
	var effects := CS16CombatEffects.for_scene(game)
	game.player.combat_effects = effects
	for bot: Node in game.allied_bots + game.targets:
		bot.combat_effects = effects
	if not effects.presentation_is_ready:
		await effects.presentation_ready
	for ignored in range(8):
		await process_frame
	report.loading_ms = float(Time.get_ticks_usec() - loading_started) / 1000.0
	var open_view: Transform3D = game.deploy_camera.global_transform if is_instance_valid(game.deploy_camera) else game.player.camera.global_transform
	game.start_match()
	game._begin_live()
	game.match_started = false
	game.player.controls_enabled = false
	game.player.set_physics_process(false)
	game.player.grant_item("ak47")
	game.player.switch_weapon("ak47")
	game.player.weapon_clock.next_primary_tick = 0
	game.player.camera.rotation.x = 0.0
	for bot: Node in game.allied_bots + game.targets:
		bot.set_physics_process(false)
		bot.health = 1000000
		bot.active = false
	game.player.health = 1000000
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	report.renderer = RenderingServer.get_current_rendering_method()
	report.physics_engine = ProjectSettings.get_setting("physics/3d/physics_engine")
	report.physics_space_class = game.get_world_3d().direct_space_state.get_class()
	report.headless = DisplayServer.get_name() == "headless"
	report.gpu_measured = not headless
	report.audio_muted = true
	report.instrumented = OS.get_cmdline_user_args().has("--instrumented")
	report.diagnostic_render_exclusions = diagnostic_hide
	report.resident_weapon_assets = MdlViewModel._prepared_weapon_assets.size()
	report.static_memory_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	report.warmed_shader_variants = CS16CombatEffects._shader_material_cache.keys()
	report.viewport = str(root.size)
	report.scenario = "Stationary ten-actor scene; synchronized scripted volleys; AI and player movement disabled"
	if game.allied_bots.size() + game.targets.size() != 9 or not game.player.viewmodel.loaded_weapon == "ak47":
		push_error("Incomplete firefight fixture")
		quit(1)
		return
	await _sample("idle", false, 180)
	await _sample("firefight", true, 360)
	await _sample("repeated_firefight", true, 360)
	var switched := Time.get_ticks_usec()
	game.player.grant_item("m4a1")
	game.player.switch_weapon("m4a1")
	report.weapon_switch_cpu_ms = float(Time.get_ticks_usec() - switched) / 1000.0
	report.weapon_switch_phases = game.player.viewmodel.last_load_timings.duplicate()
	game.player.weapon_clock.next_primary_tick = 0
	# Start at the switch, not after it: the first presented interval must pay
	# for loading/equipping as well as firing and rendering the new weapon.
	await _sample("cold_weapon_firefight", true, 180, switched)
	report.cold_weapon_firefight.includes_weapon_switch = true
	# The original spawn faces a nearby wall. Move to the open deployment vista
	# for the smoke stage so opaque BSP cannot hide the cloud being measured.
	game.player.global_position = open_view.origin - game.player.camera.position
	# Firing updates the player's authoritative yaw/pitch, so updating only
	# Camera3D would snap this view back toward the spawn wall on the next shot.
	game.player._yaw = atan2(open_view.basis.z.x, open_view.basis.z.z)
	game.player._pitch = asin(-open_view.basis.z.y)
	game.player._punch_degrees = Vector2.ZERO
	game.player.camera.rotation = Vector3.ZERO
	game.player._sync_view_angles()
	game.player.reset_physics_interpolation()
	game.player.camera.reset_physics_interpolation()
	game.player.camera.make_current()
	report.smoke_camera = str(game.player.camera.global_transform)
	await _sample("open_view_idle", false, 60)
	var smoke_events_before: int = game.player.combat_effects.total_effect_events
	var smoke_position: Vector3 = game.player.camera.global_position - game.player.camera.global_basis.z * 3.0
	var floor_hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(smoke_position + Vector3.UP * 0.5, smoke_position - Vector3.UP * 8.0, 1))
	if floor_hit.is_empty():
		push_error("Smoke benchmark cannot find ground below the cloud")
		quit(1)
		return
	smoke_position = floor_hit.position
	report.smoke_origin = str(smoke_position)
	game.player.combat_effects.spawn_smoke_cloud(smoke_position, 47)
	if game.player.combat_effects.total_effect_events <= smoke_events_before:
		push_error("Smoke benchmark did not create any smoke effects")
		quit(1)
		return
	await _sample("smoke_firefight", true, 360)
	var path := "/tmp/protocol47-firefight-performance.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			path = argument.trim_prefix("--report=")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write performance report: " + path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("FIREFIGHT_PERFORMANCE ", JSON.stringify(report))
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture=") and not headless:
			print("FIREFIGHT_CAPTURE_WAIT")
			await process_frame
			print("FIREFIGHT_CAPTURE_READ")
			var capture_error := root.get_texture().get_image().save_png(argument.trim_prefix("--capture="))
			if capture_error != OK:
				push_error("Could not write benchmark capture: " + error_string(capture_error))
				quit(1)
				return
			print("FIREFIGHT_CAPTURE_DONE")
	game.queue_free()
	await process_frame
	# Playback stops are consumed on the audio mixing thread. Allow that thread
	# to release stopped WAV playbacks before shutting the engine down.
	await create_timer(0.2).timeout
	print("GAME_FIREFIGHT_PERFORMANCE_PASS")
	quit()


func _sample(label: String, firing: bool, frames: int, interval_started_usec: int = 0) -> void:
	var intervals: Array[float] = []
	var shot_costs: Array[float] = []
	var process_costs: Array[float] = []
	var physics_costs: Array[float] = []
	var slow_frames: Array[Dictionary] = []
	var draws_before := Engine.get_frames_drawn()
	if report.instrumented:
		print("FIREFIGHT_PHASE_BEGIN label=", label, " usec=", Time.get_ticks_usec())
	var previous := interval_started_usec if interval_started_usec > 0 else Time.get_ticks_usec()
	for frame in range(frames):
		if firing and frame % 8 == 0:
			var started := Time.get_ticks_usec()
			game.player.weapon_clock.advance_tick(10)
			game.player.clip = 30
			game.player._try_fire()
			fire_tick += 10
			for bot: Node in game.allied_bots + game.targets:
				bot._try_fire(game.player, game.player.aim_point(), fire_tick)
			shot_costs.append(float(Time.get_ticks_usec() - started) / 1000.0)
		if diagnostic_hide == "effect_lights":
			# Attribution only: preserve spawning/lifetime work but exclude the
			# lights from presentation. Never used by normal gameplay or evidence
			# claiming production frame pacing.
			for effect: Dictionary in game.player.combat_effects._lights:
				if is_instance_valid(effect.node):
					effect.node.hide()
		await process_frame
		process_costs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics_costs.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		var now := Time.get_ticks_usec()
		var elapsed_ms := float(now - previous) / 1000.0
		intervals.append(elapsed_ms)
		if elapsed_ms > 33.333 and slow_frames.size() < 64:
			slow_frames.append({"frame": frame, "ms": elapsed_ms, "fired": firing and frame % 8 == 0})
		previous = now
	var first_frame_ms := intervals[0]
	intervals.sort()
	shot_costs.sort()
	process_costs.sort()
	physics_costs.sort()
	report[label] = {
		"frames": frames,
		"first_frame_ms": first_frame_ms,
		"rendered_frames": Engine.get_frames_drawn() - draws_before,
		"median_ms": intervals[frames / 2],
		"p95_ms": intervals[int(frames * 0.95)],
		"p99_ms": intervals[int(frames * 0.99)],
		"max_ms": intervals[-1],
		"frames_over_33ms": intervals.filter(func(value: float) -> bool: return value > 33.333).size(),
		"shot_p95_ms": shot_costs[int(shot_costs.size() * 0.95)] if firing else 0.0,
		"effect_events": game.player.combat_effects.total_effect_events,
		"retained_effect_events": game.player.combat_effects.event_log.size(),
		"process_max_ms": process_costs[-1],
		"physics_max_ms": physics_costs[-1],
		"slow_frames": slow_frames,
		"shader_variants": CS16CombatEffects._shader_material_cache.size(),
	}
	if not report.headless and int(report[label].rendered_frames) < frames - 2:
		push_error("GPU benchmark did not render each sampled frame: %s (%d/%d)" % [label, report[label].rendered_frames, frames])
		quit(1)
		return
	if firing and game.player.combat_effects.total_effect_events == 0:
		push_error("Firefight did not exercise combat effects")
		quit(1)
	print(label, " ", JSON.stringify(report[label]))
