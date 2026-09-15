extends SceneTree

## A real running match: normal health, AI, movement, ammo, rounds and effects.
## Only local human intent is automated; it follows a teammate on the navmesh
## and aims/fires at visible opponents through the normal Player command seam.
const MatchDriver = preload("res://tests/live_match_driver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
	var headless := DisplayServer.get_name() == "headless"
	var full_match := OS.get_cmdline_user_args().has("--full-match")
	var require_local_combat := full_match or OS.get_cmdline_user_args().has("--require-local-combat")
	if full_match:
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--frames=") or argument.begins_with("--diagnostic-hide"):
				push_error("Full-match probes require physics-tick limits and intact effects")
				quit(1)
				return
	if headless and not OS.get_cmdline_user_args().has("--cpu-only"):
		push_error("Headless live-match measurements require --cpu-only")
		quit(1)
		return
	var started := Time.get_ticks_usec()
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var profile_phases := OS.get_cmdline_user_args().has("--profile-phases")
	if profile_phases:
		var profile_script := load("res://tests/profiled_match_game.gd") as Script
		if profile_script == null or not profile_script.can_instantiate():
			game.free()
			push_error("Live-match profiling adapter could not load")
			quit(1)
			return
		game.set_script(profile_script)
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	var requested_team := "T"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--team="):
			requested_team = argument.trim_prefix("--team=")
	if requested_team not in ["T", "CT"]:
		push_error("Live-match fixture requires --team=T or --team=CT")
		quit(1)
		return
	if requested_team != game.player.team:
		# Exercise the normal team/class selection path before live measurement.
		game._on_team_selected(2 if requested_team == "CT" else 1)
		game._on_class_selected(1)
		await process_frame
		await physics_frame
	var driver := MatchDriver.new()
	driver.game = game
	game.player.add_child(driver)
	game.player.combat_controller.queue_free()
	driver.possess(game.player)
	game.player.combat_controller = driver
	if not driver.prepare_navigation():
		push_error("Local benchmark navigation graph could not be prepared")
		quit(1)
		return
	var loading_ms := float(Time.get_ticks_usec() - started) / 1000.0
	game.start_match()
	# Automated intent owns this fixture. A real desktop key/mouse event must
	# not pause the clock, open menus or orbit the spectator camera mid-sample.
	game.set_process_unhandled_input(false)
	game.player.set_process_input(false)
	game.spectator_camera.set_process_unhandled_input(false)
	root.gui_disable_input = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not full_match:
		game.player.grant_item("ak47")
		game.player.switch_weapon("ak47")
		game._begin_live()
	var initial_local_weapon: String = game.player.active_weapon
	var initial_local_inventory: Dictionary = game.player.owned_weapons.duplicate(true)
	var initial_phase: String = game.phase
	if full_match and (initial_phase != "freeze" or initial_local_weapon != ("usp" if requested_team == "CT" else "glock18")):
		push_error("Full-match fixture must start with the normal team pistol and freeze phase")
		quit(1)
		return
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var actors: Array = [game.player] + game._all_bots()
	var previous_positions := {}
	var previous_alive := {}
	var distances := {}
	for actor: Combatant in actors:
		previous_positions[actor.name] = actor.global_position
		previous_alive[actor.name] = actor.alive
		distances[actor.name] = 0.0
	var frames := 1800
	# A legal late plant can extend a five-minute round by the full C4 clock.
	# Derive the cap from production rules; never shorten those rules for a test.
	var rules: Dictionary = game.round_state.config
	var full_match_tick_limit := int(rules.max_rounds) * (
		int(rules.freeze_ticks) + int(rules.round_ticks) + int(rules.c4_ticks)
		+ int(rules.restart_ticks) + 1)
	var target_ticks := full_match_tick_limit if full_match else 0
	var report_path := "/tmp/protocol47-live-match-performance.json"
	var capture_path := ""
	var diagnostic_hide := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="):
			frames = clampi(int(argument.trim_prefix("--frames=")), 300, 18000)
		elif argument.begins_with("--ticks="):
			target_ticks = clampi(int(argument.trim_prefix("--ticks=")), 300, full_match_tick_limit if full_match else 12000)
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--capture="):
			capture_path = argument.trim_prefix("--capture=")
		elif argument.begins_with("--diagnostic-hide="):
			diagnostic_hide = argument.trim_prefix("--diagnostic-hide=")
	var samples: Array[float] = []
	var sample_ticks: Array[int] = []
	var sample_effects: Array[int] = []
	var sample_alive: Array[int] = []
	var initial_effects: int = game.combat_effects.total_effect_events
	var slow_frames: Array[Dictionary] = []
	var life_events: Array[Dictionary] = []
	var local_shot_events: Array[Dictionary] = []
	var previous_shot_sequence: int = game.player._shot_sequence
	var objective_events: Array[Dictionary] = []
	var previous_bomb_state: String = game.round_state.bomb_state
	var freeze_observations := 0
	var freeze_control_violations := 0
	var freeze_positions := {}
	var memory_start := Performance.get_monitor(Performance.MEMORY_STATIC)
	var draws_before := Engine.get_frames_drawn()
	var physics_before := Engine.get_physics_frames()
	var kernel_before: int = game.round_state.tick
	var pause_observations := 0
	var maximum_clock_gap := 0
	print("LIVE_MATCH_MEASUREMENT_BEGIN pid=", OS.get_process_id(), " physics_tick=", physics_before)
	var previous := Time.get_ticks_usec()
	var frame := 0
	while (
		not (full_match and game._match_concluded) and (
		(target_ticks > 0 and Engine.get_physics_frames() - physics_before < target_ticks)
		or (target_ticks == 0 and frame < frames)
		)
	):
		await process_frame
		if paused or game._pause_menu_open() or Engine.time_scale != 1.0:
			pause_observations += 1
		if not game._match_concluded:
			maximum_clock_gap = maxi(maximum_clock_gap, (Engine.get_physics_frames() - physics_before) - (int(game.round_state.tick) - kernel_before))
		var now := Time.get_ticks_usec()
		var ms := float(now - previous) / 1000.0
		previous = now
		samples.append(ms)
		sample_ticks.append(Engine.get_physics_frames() - physics_before)
		sample_effects.append(game.combat_effects.total_effect_events)
		var alive_count := 0
		if str(game.round_state.phase) == "freeze":
			freeze_observations += 1
			for bot: TargetActor in game._all_bots():
				if bot.active or (freeze_positions.has(bot.name)
					and bot.global_position != freeze_positions[bot.name]):
					freeze_control_violations += 1
				freeze_positions[bot.name] = bot.global_position
		else:
			freeze_positions.clear()
		for event: Dictionary in objective_events:
			if event.frame_times_ms.size() < 4:
				event.frame_times_ms.append(ms)
		if game.round_state.bomb_state != previous_bomb_state:
			objective_events.append({"frame": frame, "physics_tick": Engine.get_physics_frames() - physics_before,
				"bomb_state": game.round_state.bomb_state, "frame_times_ms": [ms]})
			previous_bomb_state = game.round_state.bomb_state
		if game.player._shot_sequence != previous_shot_sequence:
			local_shot_events.append({"frame": frame, "physics_tick": Engine.get_physics_frames() - physics_before,
				"sequence": game.player._shot_sequence, "weapon": game.player.active_weapon})
			previous_shot_sequence = game.player._shot_sequence
		if ms > 33.333 and slow_frames.size() < 64:
			slow_frames.append({"frame": frame, "ms": ms, "round": game.round_number,
				"physics_tick": Engine.get_physics_frames() - physics_before,
				"effect_events": game.combat_effects.total_effect_events})
		for actor: Combatant in actors:
			if actor.alive:
				alive_count += 1
			# Diagnostic-only exclusions affect presentation, never health,
			# collision, pickup rules, bot intent, or the production scene code.
			if diagnostic_hide == "corpse_models" and actor is TargetActor:
				actor.character_model.visible = actor.alive
			if actor.alive != previous_alive[actor.name]:
				life_events.append({"frame": frame, "physics_tick": Engine.get_physics_frames() - physics_before,
					"actor": actor.name, "alive": actor.alive,
					"weapon": actor.active_weapon_name if actor is TargetActor else game.player.active_weapon})
				previous_alive[actor.name] = actor.alive
			var distance: float = actor.global_position.distance_to(previous_positions[actor.name])
			# Round respawns are teleports, not traveled gameplay distance.
			if distance < 1.0:
				distances[actor.name] += distance
			previous_positions[actor.name] = actor.global_position
		sample_alive.append(alive_count)
		if diagnostic_hide == "world_drops":
			for drop: Node3D in game.dropped_weapons:
				drop.hide()
		elif diagnostic_hide == "viewmodel":
			game.player.viewmodel.hide()
		elif diagnostic_hide == "map":
			game.imported_map.hide()
		elif diagnostic_hide == "effect_lights":
			for effect: Dictionary in game.combat_effects._lights:
				if is_instance_valid(effect.node):
					effect.node.hide()
		elif diagnostic_hide == "muzzle_smoke":
			for effect: Dictionary in game.combat_effects._sprites:
				if is_instance_valid(effect.node) and str(effect.node.name).begins_with("GoldSrcSprite_rifle_smoke"):
					effect.node.hide()
		if frame % 600 == 599:
			print("LIVE_MATCH_PROGRESS frames=", frame + 1, " ticks=", Engine.get_physics_frames() - physics_before,
				" round=", game.round_number, " score=", game.ct_score, ":", game.terrorist_score,
				" effects=", game.combat_effects.total_effect_events, " local_shots=", local_shot_events.size())
		frame += 1
	frames = samples.size()
	var drawn := Engine.get_frames_drawn() - draws_before
	var frame_windows := preload("res://tests/frame_window_metrics.gd").summarize(
		samples, sample_ticks, sample_effects, sample_alive, initial_effects)
	samples.sort()
	var effect_type_counts := {}
	for event: Dictionary in game.combat_effects.event_log:
		var kind := str(event.get("type", ""))
		effect_type_counts[kind] = int(effect_type_counts.get(kind, 0)) + 1
	var parked_frames := 0
	for parked: Dictionary in game.player.viewmodel._parked_weapons.values():
		parked_frames += parked.frames.size()
	var actor_summary: Array[Dictionary] = []
	var navigation_summary: Array[Dictionary] = []
	for actor: Combatant in actors:
		actor_summary.append({"name": str(actor.name), "team": actor.team, "alive": actor.alive,
			"position": [actor.global_position.x, actor.global_position.y, actor.global_position.z]})
		if actor is TargetActor and actor.combat_controller is BotCombatController:
			var bot := actor as TargetActor
			var controller := bot.combat_controller as BotCombatController
			var route_tail: Array = []
			for index in range(controller._objective_route_index, mini(controller._objective_route.size(), controller._objective_route_index + 5)):
				route_tail.append(_vector_report(controller._objective_route[index]))
			navigation_summary.append({"name": str(bot.name), "on_floor": bot.is_on_floor(),
				"velocity": _vector_report(bot.velocity), "combat_state": bot.combat_state,
				"obstructed_ticks": bot._obstructed_ticks,
				"unwedge_blocked_ticks": controller._unwedge_blocked_ticks,
				"route_target": _vector_report(controller._objective_route_target),
				"route_index": controller._objective_route_index,
				"route_points": controller._objective_route.size(), "next_route_points": route_tail})
	var report := {
		"full_match_required": full_match, "match_completed": game._match_concluded,
		"full_match_tick_limit": full_match_tick_limit, "round_rules": rules.duplicate(true),
		"initial_local_weapon": initial_local_weapon, "initial_local_inventory": initial_local_inventory,
		"initial_phase": initial_phase,
		"starting_equipment": "normal_team_pistol" if full_match else "benchmark_granted_ak47",
		"initial_freeze_skipped": not full_match,
		"match_end_events": game.round_state.trace.filter(func(event: Dictionary) -> bool: return event.type == "match_end"),
		"halftime_events": game.round_state.trace.filter(func(event: Dictionary) -> bool: return event.type == "halftime"),
		"memory_scope": "process static memory including retained benchmark frame samples",
		"scenario": "Live 5v5 match; production AI, physics, damage, ammo and rounds; automated local intent",
		"gpu_measured": not headless, "audio_muted": true, "renderer": RenderingServer.get_current_rendering_method(),
		"physics_engine": ProjectSettings.get_setting("physics/3d/physics_engine"),
		"physics_space_class": game.get_world_3d().direct_space_state.get_class(),
		"instrumented": profile_phases or OS.get_cmdline_user_args().has("--instrumented"),
		"phase_cpu_events": game.phase_cpu_events if profile_phases else [],
		"hostage_cpu_totals": game.hostage_cpu_totals if profile_phases else {},
		"bot_cpu_events": game.bot_cpu_events() if profile_phases else [],
		"physics_tick_origin": physics_before,
		"diagnostic_render_exclusions": diagnostic_hide,
		"map": game.map_name, "viewport": str(root.size), "frames": frames, "rendered_frames": drawn,
		"scenario_type": game.scenario, "local_team_start": requested_team, "local_team_end": game.player.team,
		"actors_final": actor_summary,
		"bot_navigation_final": navigation_summary,
		"round_end_events": game.round_state.trace.filter(func(event: Dictionary) -> bool: return event.type == "round_end"),
		"hostages_final": game.hostage_state.snapshot() if game.hostage_state != null else {},
		"hostage_current_round_events": game.hostage_state.trace if game.hostage_state != null else [],
		"physics_ticks": Engine.get_physics_frames() - physics_before, "round": game.round_number,
		"desktop_input_isolated": true, "pause_observations": pause_observations,
		"maximum_clock_gap": maximum_clock_gap, "kernel_ticks": int(game.round_state.tick) - kernel_before,
		"sample_mode": "physics_ticks" if target_ticks > 0 else "render_frames", "target_physics_ticks": target_ticks,
		"loading_ms": loading_ms, "median_ms": samples[frames / 2], "p95_ms": samples[int(frames * 0.95)],
		"bot_asset_preparation": game.bot_asset_preparation,
		"p99_ms": samples[int(frames * 0.99)], "max_ms": samples[-1], "slow_frames": slow_frames,
		"frame_window_ticks": 100, "frame_window_assignment": "frame_end_tick",
		"frame_windows": frame_windows,
		"frames_over_33ms": samples.filter(func(ms: float) -> bool: return ms > 33.333).size(),
		"distance_meters": distances, "effect_events": game.combat_effects.total_effect_events,
		"life_events": life_events,
		"freeze_observations": freeze_observations,
		"freeze_control_violations": freeze_control_violations,
		"local_shot_events": local_shot_events,
		"objective_events": objective_events,
		"retained_effect_type_counts": effect_type_counts,
		"viewmodel_residency": {"active_weapon": game.player.viewmodel.loaded_weapon,
			"active_frames": game.player.viewmodel._frame_mesh_cache.size(),
			"parked_weapons": game.player.viewmodel._parked_weapon_order,
			"parked_frames": parked_frames},
		"memory_start_bytes": memory_start, "memory_end_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"test_driver_cpu_ms": float(driver.cpu_us) / 1000.0, "test_driver_max_cpu_ms": float(driver.max_cpu_us) / 1000.0,
		"test_driver_route_ms": float(driver.route_us) / 1000.0, "test_driver_max_route_ms": float(driver.max_route_us) / 1000.0,
		"test_driver_jump_commands": driver.jump_commands, "test_driver_max_blocked_ticks": driver.max_blocked_ticks,
		"test_driver_solo_objective_commands": driver.solo_objective_commands, "test_driver_use_commands": driver.use_commands,
		"local_combat_covered": not local_shot_events.is_empty(),
		"local_combat_required": require_local_combat,
	}
	var completed_rounds: int = report.round_end_events.size()
	var mr15_complete: bool = (game._match_concluded and report.match_end_events.size() == 1
		and report.halftime_events.size() == 1 and completed_rounds >= 16
		and completed_rounds == game.ct_score + game.terrorist_score
		and (maxi(game.ct_score, game.terrorist_score) == 16 or (game.ct_score == 15 and game.terrorist_score == 15)))
	report.mr15_completion_verified = mr15_complete
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write live-match report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("LIVE_MATCH_PERFORMANCE ", JSON.stringify(report))
	var passed := headless or drawn >= frames - 2
	if pause_observations > 0 or maximum_clock_gap > 0:
		push_error("Live-match measurement was paused or lost authoritative simulation ticks")
		passed = false
	passed = passed and freeze_control_violations == 0
	passed = passed and actors.size() == 10 and float(distances[game.player.name]) > 1.0
	passed = passed and distances.values().filter(func(distance: float) -> bool: return distance > 1.0).size() >= 6
	passed = passed and game.combat_effects.total_effect_events > 0
	if full_match and not mr15_complete:
		push_error("Required full MR15 match did not finish with a valid halftime/end trace within the physics-tick limit")
		passed = false
	if require_local_combat and local_shot_events.is_empty():
		push_error("Required local combat was not covered: no local shots recorded")
		passed = false
	if not capture_path.is_empty() and not headless:
		await process_frame
		passed = root.get_texture().get_image().save_png(capture_path) == OK and passed
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("GAME_LIVE_MATCH_PERFORMANCE_PASS" if passed else "GAME_LIVE_MATCH_PERFORMANCE_FAIL")
	quit(0 if passed else 1)


func _vector_report(value: Vector3) -> Variant:
	return [value.x, value.y, value.z] if value.is_finite() else null
