extends SceneTree

## Records HUD-free promo footage on Dust2 under Movie Maker: a slow orbit over
## the map during the buy phase, then the spectator chase camera following the
## Terrorist bots once the human player is removed from the round.
##   godot --path game --write-movie /tmp/cinema.avi --fixed-fps 60 \
##     --resolution 1920x1080 --script res://tests/promo_cinema.gd -- --seconds=240
## Prints PROMO_EVENT lines (frame, kind, detail) for the editor.

var _frame := 0
var _seconds := 240.0
var _orbit_seconds := 9.0
var _game: Node


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_seconds = float(argument.get_slice("=", 1))
		elif argument.begins_with("--orbit="):
			_orbit_seconds = float(argument.get_slice("=", 1))
	_run.call_deferred()


func _event(kind: String, detail: String) -> void:
	print("PROMO_EVENT frame=%d kind=%s %s" % [_frame, kind, detail])


func _centroid(points: Array) -> Vector3:
	var sum := Vector3.ZERO
	for point: Vector3 in points:
		sum += point
	return sum / maxf(1.0, points.size())


func _run() -> void:
	_game = preload("res://scripts/game.gd").new()
	_game.map_name = "de_dust2"
	root.add_child(_game)
	current_scene = _game
	await process_frame
	await physics_frame
	if not _game.combat_effects.presentation_is_ready:
		await _game.combat_effects.presentation_ready
	_game._on_team_selected(1)
	_game._on_class_selected(1)
	_game.start_match()
	var t_center := _centroid(_game.terrorist_team_spawns)
	var ct_center := _centroid(_game.counter_terrorist_team_spawns)
	var focus := (t_center + ct_center) * 0.5
	var span := t_center.distance_to(ct_center)
	print("PROMO_MAP t=%s ct=%s span=%.2f" % [t_center, ct_center, span])
	var orbit := Camera3D.new()
	orbit.fov = 60.0
	orbit.far = 400.0
	_game.add_child(orbit)
	orbit.current = true
	_game.hud.visible = false
	var orbit_frames := int(_orbit_seconds * 60.0)
	var end_frame := int(_seconds * 60.0)  # --fixed-fps 60
	var alive := {}
	var removed := false
	var last_phase := ""
	var bought_round := -1
	while _frame < end_frame:
		await process_frame
		_frame += 1
		_game.hud.visible = false
		if _frame <= orbit_frames:
			var t := float(_frame) / orbit_frames
			var angle := deg_to_rad(-30.0 + 70.0 * t)
			var radius := span * (0.62 - 0.12 * t)
			var height := span * (0.42 - 0.10 * t)
			orbit.global_position = focus + Vector3(cos(angle) * radius, height, sin(angle) * radius)
			orbit.look_at(focus + Vector3(0, -span * 0.05, 0), Vector3.UP)
			orbit.current = true
		elif is_instance_valid(orbit):
			orbit.queue_free()
		var phase := str(_game.phase)
		if phase != last_phase:
			_event("phase", "phase=%s round=%d" % [phase, int(_game.round_state.round_number)])
			last_phase = phase
		var round_number := int(_game.round_state.round_number)
		if phase == "freeze" and bought_round != round_number:
			bought_round = round_number
			for id: String in _game.round_state.players:
				_game.round_state.players[id].money = 16000
		if phase == "live" and _game.player.alive and _frame > orbit_frames:
			# Leave the round so the spectator chase camera follows teammates.
			_game.player.receive_damage(10000.0)
			if not removed:
				_event("spectate", "")
			removed = true
		for actor: Combatant in _game._all_bots():
			var id := actor.get_instance_id()
			if alive.get(id, false) and not actor.alive:
				var followed: bool = is_instance_valid(_game.spectator_camera) \
					and _game.spectator_camera.target == actor
				var killer: Variant = actor.last_damage_attacker
				var by_followed: bool = is_instance_valid(_game.spectator_camera) \
					and is_instance_valid(killer) and _game.spectator_camera.target == killer
				_event("death", "victim=%s followed_victim=%s by_followed=%s" % [actor.name, followed, by_followed])
			alive[id] = actor.alive
	_event("done", "")
	quit()
