extends SceneTree

## Real 100 Hz navigation/use/escort/rescue from the untouched map spawns.
## Blind perception isolates traversal from random encounter deaths; no pawn,
## hostage, route waypoint, physics hull, or objective clock is teleported.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _blind(_actor: Combatant, _tick: int) -> bool:
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var game := preload("res://scripts/game.gd").new()
	game.map_name = "cs_assault"
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var requested_team := "T"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--team="):
			requested_team = argument.trim_prefix("--team=")
	_check(requested_team in ["T", "CT"], "traversal fixture requires a supported player team")
	if requested_team in ["T", "CT"] and requested_team != game.player.team:
		game._on_team_selected(2 if requested_team == "CT" else 1)
		game._on_class_selected(1)
		await process_frame
		await physics_frame
	_check(game.player.team == requested_team, "normal team/class selection applies the requested side")
	_check(game.imported_map.navigation_links.size() == 1, "Assault loads its authored warehouse transition")
	for bot: TargetActor in game._all_bots():
		bot.combat_controller.set_perception_predicates(Callable(self, "_blind"))
	game.start_match()
	game._begin_live()
	for bot: TargetActor in game._all_bots():
		_check(bot.combat_controller._ensure_objective_graph(), "all authored traversal endpoints bind to clear polygons")
	if not failures.is_empty():
		game.queue_free()
		await process_frame
		await create_timer(0.2).timeout
		for failure: String in failures:
			push_error(failure)
		quit(1)
		return
	var first_use := -1
	var first_rescue := -1
	var door_open_tick := -1
	var jumpers := {}
	var last_positions := {}
	var max_displacement := 0.0
	var link: NavigationLink3D = game.imported_map.navigation_links[0]
	var link_center := (link.get_global_start_position() + link.get_global_end_position()) * 0.5
	var pawns: Array = game._all_bots() + game.hostage_actors.values()
	for pawn: Node3D in pawns:
		last_positions[pawn.name] = pawn.global_position
	var ticks := 0
	var checkpoints: Array = []
	for tick in 18000:
		await physics_frame
		ticks = tick + 1
		for pawn: Node3D in pawns:
			max_displacement = maxf(max_displacement, pawn.global_position.distance_to(last_positions[pawn.name]))
			last_positions[pawn.name] = pawn.global_position
			if (pawn is TargetActor and pawn.team == Combatant.TEAM_COUNTER_TERRORIST
				and pawn.velocity.y > 1.5 and pawn.global_position.distance_to(link_center) < 1.5):
				jumpers[pawn.name] = true
		if door_open_tick < 0 and game.brush_runtime.get_brush(11).state == "open":
			door_open_tick = ticks
		for hostage: Dictionary in game.hostage_state.hostages.values():
			if bool(hostage.ever_used) and first_use < 0:
				first_use = ticks
		if game.hostage_state.rescued_count > 0 and first_rescue < 0:
			first_rescue = ticks
		if ticks % 2000 == 0:
			var snapshot := _snapshot(game)
			snapshot.tick = ticks
			checkpoints.append(snapshot)
			print("ASSAULT_HOSTAGE_TRAVERSAL_PROGRESS ", JSON.stringify(snapshot))
		if game.round_state.phase == CS16RoundState.PHASE_POST:
			break
	_check(first_use > 0, "CT bots reach and use the real hostages from normal spawn")
	_check(door_open_tick > 0, "real pawn contact opens the source warehouse door")
	_check(not jumpers.is_empty(), "CTs cross the entrance using the existing jump impulse")
	_check(max_displacement < 0.25, "no pawn or hostage teleports through a traversal link")
	_check(game.hostage_state.rescued_count == 4, "all four hostages physically reach rescue zones")
	_check(game.round_state.round_reason == "all_hostages_rescued", "actual rescue flow resolves the round")
	var report := {"ok": failures.is_empty(), "player_team": requested_team, "ticks": ticks, "first_use_tick": first_use,
		"door_open_tick": door_open_tick, "jumpers": jumpers.keys(), "max_tick_displacement_m": max_displacement,
		"first_rescue_tick": first_rescue, "round_reason": game.round_state.round_reason,
		"final": _snapshot(game), "checkpoints": checkpoints,
		"hostage_trace": game.hostage_state.trace, "failures": failures}
	var report_path := "/tmp/protocol47-assault-hostage-traversal%s.json" % ("-ct" if requested_team == "CT" else "")
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("ASSAULT_HOSTAGE_TRAVERSAL ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	for failure: String in failures:
		push_error(failure)
	print("GAME_ASSAULT_HOSTAGE_TRAVERSAL_PASS" if failures.is_empty() else "GAME_ASSAULT_HOSTAGE_TRAVERSAL_FAIL")
	quit(0 if failures.is_empty() else 1)


func _snapshot(game: Node) -> Dictionary:
	var actors: Array = []
	var hostage_navigation := {}
	for hostage_id: String in game.hostage_actors:
		var pawn: CS16Hostage = game.hostage_actors[hostage_id]
		var path: PackedVector3Array = game._hostage_paths.get(hostage_id, PackedVector3Array())
		var index := int(game._hostage_path_indices.get(hostage_id, 0))
		var points: Array[String] = []
		for point in range(maxi(0, index), mini(path.size(), index + 5)):
			points.append(str(path[point]))
		hostage_navigation[hostage_id] = {"position": str(pawn.global_position),
			"velocity": str(pawn.velocity), "requested_velocity_hu": str(pawn.motion_velocity_hu),
			"path_index": index, "path_size": path.size(), "next_points": points,
			"blocked_ticks": pawn._blocked_source_ticks}
	for bot: TargetActor in game._all_bots():
		var controller := bot.combat_controller as BotCombatController
		var next := Vector3.INF
		if controller._objective_route_index >= 0 and controller._objective_route_index < controller._objective_route.size():
			next = controller._objective_route[controller._objective_route_index]
		actors.append({"name": str(bot.name), "team": bot.team, "position": str(bot.global_position),
			"state": bot.combat_state, "next": str(next), "route_index": controller._objective_route_index,
			"route_size": controller._objective_route.size(), "obstructed_ticks": bot._obstructed_ticks})
	return {"actors": actors, "hostages": game.hostage_state.snapshot(),
		"hostage_navigation": hostage_navigation, "entrance_door": game.brush_runtime.get_brush(11).state}
