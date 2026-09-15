extends CombatController

## Test-only human intent. Reuse production hull-clear navigation, but send
## mouse/movement/jump commands through PlayerController; never move the pawn.
class IntentPlanner extends BotCombatController:
	func _objective_waypoint_reached(index: int) -> bool:
		if _objective_required_waypoints.has(index):
			# Center the human hull before crossing a narrow authored link. The
			# bot's 12-cm steering radius can cut this approach into a door jamb.
			var offset := actor.global_position - _objective_route[index]
			return Vector2(offset.x, offset.z).length_squared() < 0.0004 and absf(offset.y) < 0.08
		return super._objective_waypoint_reached(index)

	func _objective_navigation_velocity_to(target_position: Vector3, delta: float) -> Vector3:
		var desired := super._objective_navigation_velocity_to(target_position, delta)
		if not desired.is_zero_approx() or delta <= 0.0 or _objective_route.is_empty():
			return desired
		if _objective_required_waypoints.has(_objective_route_index) and not _objective_waypoint_reached(_objective_route_index):
			# The base bot stops planar steering within five centimeters. Keep
			# moving inside that band until this planner's tighter endpoint is met.
			var offset := _objective_route[_objective_route_index] - actor.global_position
			offset.y = 0.0
			if not offset.is_zero_approx():
				return offset.normalized() * minf(navigation_agent.max_speed, offset.length() / delta)
		return desired


var game: Node
var combat_enabled := true
var tick := 0
var cpu_us := 0
var max_cpu_us := 0
var route_us := 0
var max_route_us := 0
var jump_commands := 0
var max_blocked_ticks := 0
var recovery_commands := 0
var solo_objective_commands := 0
var use_commands := 0
var planner: BotCombatController
var _route_target := Vector3.INF
var _route_refresh_tick := -1
var _round := -1
var _previous_position := Vector3.INF
var _previous_wish := Vector3.ZERO
var _blocked_ticks := 0
var _next_jump_tick := -1
var _solo_rescue_target := Vector3.INF


func prepare_navigation() -> bool:
	if planner == null:
		var agent := NavigationAgent3D.new()
		agent.name = "BenchmarkLocalNavigation"
		agent.avoidance_enabled = false
		agent.max_speed = PlayerController.RUN_SPEED
		actor.add_child(agent)
		planner = IntentPlanner.new()
		add_child(planner)
		planner.configure(actor, agent, 91)
	return planner._ensure_objective_graph()


func gather_command(delta: float) -> Dictionary:
	var started := Time.get_ticks_usec()
	var command := _gather_match_command(delta)
	var elapsed := Time.get_ticks_usec() - started
	cpu_us += elapsed
	max_cpu_us = maxi(max_cpu_us, elapsed)
	return command


func _gather_match_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	var player := actor as PlayerController
	if player == null or not player.alive or not player.controls_enabled:
		_previous_wish = Vector3.ZERO
		return command
	tick += 1
	if planner == null and not prepare_navigation():
		return command
	if _round != game.round_number or (_previous_position.is_finite()
		and player.global_position.distance_to(_previous_position) > 1.0):
		planner.reset_tactics()
		_round = game.round_number
		_route_target = Vector3.INF
		_route_refresh_tick = -1
		_blocked_ticks = 0
		_solo_rescue_target = Vector3.INF
	var traveled := Vector2.ZERO
	if _previous_position.is_finite():
		traveled = Vector2(player.global_position.x - _previous_position.x, player.global_position.z - _previous_position.z)
	if _previous_wish.length_squared() > 0.1 and traveled.length() < PlayerController.RUN_SPEED * delta * 0.2:
		_blocked_ticks += 1
	else:
		_blocked_ticks = 0
	max_blocked_ticks = maxi(max_blocked_ticks, _blocked_ticks)
	_previous_position = player.global_position
	planner._objective_tick = tick
	var camera := player.camera
	var enemy: Combatant
	var leader: Combatant
	var enemy_distance := INF
	var space := player.get_world_3d().direct_space_state
	for bot: Combatant in game._all_bots():
		if not bot.alive:
			continue
		if bot.team == player.team:
			if leader == null:
				leader = bot
			continue
		if not combat_enabled or player.is_flash_blinded():
			continue
		var distance := camera.global_position.distance_to(bot.aim_point())
		if distance >= enemy_distance:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position, bot.aim_point(), 3))
		if not hit.is_empty() and hit.collider == bot:
			enemy = bot
			enemy_distance = distance
	var direction := Vector3.ZERO
	var look := -camera.global_basis.z
	var solo_objective := {}
	if leader == null and enemy == null:
		solo_objective = _solo_hostage_objective(player)
	if enemy != null:
		look = (enemy.aim_point() - camera.global_position).normalized()
		command.fire = true
		command.fire_pressed = tick % 10 == 0
	elif leader != null or not solo_objective.is_empty():
		var stop_radius := 0.5
		var look_override := Vector3.INF
		if not solo_objective.is_empty():
			solo_objective_commands += 1
			_route_target = planner._snap_objective_target(solo_objective.target)
			stop_radius = float(solo_objective.stop_radius)
			command.state = solo_objective.state
			command.use = bool(solo_objective.get("use", false))
			look_override = solo_objective.get("look_direction", Vector3.INF)
		elif tick >= _route_refresh_tick:
			_route_refresh_tick = tick + 50
			_route_target = leader.global_position
			# Share the ally's objective, not its occupied standing position.
			# Stopping beside an ally queued at a doorway blocks both pawns.
			var ally_controller := leader.combat_controller as BotCombatController
			if ally_controller != null and ally_controller._objective_route_target.is_finite():
				_route_target = ally_controller._objective_route_target
		if player.global_position.distance_to(_route_target) > stop_radius:
			var query_started := Time.get_ticks_usec()
			direction = planner._objective_navigation_velocity_to(_route_target, delta).normalized()
			var elapsed := Time.get_ticks_usec() - query_started
			route_us += elapsed
			max_route_us = maxi(max_route_us, elapsed)
			# A human can back up or sidestep a crowded entrance. Reuse the
			# production hull-based avoidance for that intent as well as routing;
			# jumping alone can pin this pawn against a teammate indefinitely.
			# Give the normal jump attempt priority before declaring a jam. The
			# bot's 20-tick player-yield threshold otherwise preempts our jump.
			if _blocked_ticks >= 75 or tick < planner._unwedge_until_tick or tick < planner._door_wait_until_tick:
				var avoidance := planner._apply_unwedge({"world_velocity": direction * PlayerController.RUN_SPEED}, delta)
				direction = (avoidance.world_velocity as Vector3).normalized()
				if bool(avoidance.get("unwedging", false)):
					recovery_commands += 1
			else:
				planner._unwedge_blocked_ticks = 0
				planner._unwedge_last_position = player.global_position
			if not direction.is_zero_approx():
				look = direction
			if _blocked_ticks >= 25 and tick >= _next_jump_tick and player._movement_grounded:
				_next_jump_tick = tick + 150
				if _jump_landing_available(player, direction):
						command.jump = true
						jump_commands += 1
		if look_override.is_finite():
			look = look_override
	if bool(command.use):
		use_commands += 1
	_previous_wish = direction
	if not look.is_zero_approx():
		var yaw := atan2(-look.x, -look.z)
		var pitch := asin(clampf(look.y, -1.0, 1.0))
		var radians_per_pixel := deg_to_rad(player.settings.mouse_sensitivity)
		var vertical_sign := -1.0 if player.settings.invert_y else 1.0
		command.look_delta = Vector2(-angle_difference(player._yaw, yaw),
			-(pitch - player._pitch) / vertical_sign) / maxf(radians_per_pixel, 0.000001)
		var local := direction.rotated(Vector3.UP, -yaw)
		command.movement = Vector2(local.x, local.z)
	command.reload = player.clip == 0
	return command


func _solo_hostage_objective(player: PlayerController) -> Dictionary:
	# Map objectives are known destinations; never chase a hidden opponent's
	# transform to repair an idle benchmark. Team-mate following stays unchanged.
	if game.scenario != "hostage_rescue" or player.team != Combatant.TEAM_COUNTER_TERRORIST:
		return {}
	var selected: CS16Hostage
	var nearest := INF
	var followers := 0
	for hostage: CS16Hostage in game.hostage_actors.values():
		if not hostage.alive or hostage.rescued:
			continue
		if hostage.following:
			if hostage.leader_id == "player":
				followers += 1
			continue
		var distance := player.global_position.distance_squared_to(hostage.global_position)
		if distance < nearest:
			selected = hostage
			nearest = distance
	# Collect the remaining nearby room occupants before starting the escort;
	# an immediate return after every use can waste the entire legal round.
	if selected != null:
		var use_origin := selected.source_use_origin()
		var in_use_range := player.global_position.distance_to(use_origin) <= CS16Hostage.HostageStateScript.USE_RADIUS_HU * 0.01
		return {"target": selected.global_position, "stop_radius": 0.40,
			"state": "benchmark_collect_hostages",
			"look_direction": (use_origin - player.camera.global_position).normalized() if in_use_range else Vector3.INF,
			# +use is edge-triggered. Retry with releases, never toggle followers.
			"use": in_use_range and tick % 20 == 0}
	if followers > 0:
		if not _solo_rescue_target.is_finite():
			_solo_rescue_target = game._hostage_rescue_position(player.global_position)
		return {"target": _solo_rescue_target,
			"stop_radius": 0.32, "state": "benchmark_escort_hostages"}
	return {}


func _jump_landing_available(player: PlayerController, direction: Vector3) -> bool:
	if direction.is_zero_approx():
		return false
	var params := PhysicsTestMotionParameters3D.new()
	params.margin = 0.015
	var result := PhysicsTestMotionResult3D.new()
	params.from = player.global_transform
	params.motion = Vector3.UP * 0.42
	PhysicsServer3D.body_test_motion(player.get_rid(), params, result)
	var rise := result.get_travel().y
	if rise <= PlayerController.STEP_HEIGHT + 0.02:
		return false
	params.from = player.global_transform.translated(Vector3.UP * rise)
	params.motion = direction * 0.64
	if PhysicsServer3D.body_test_motion(player.get_rid(), params, result):
		return false
	params.from = params.from.translated(params.motion)
	params.motion = Vector3.DOWN * (rise + 0.02)
	if not PhysicsServer3D.body_test_motion(player.get_rid(), params, result):
		return false
	return (result.get_collision_normal().y >= PlayerController.FLOOR_NORMAL_MINIMUM
		and rise + result.get_travel().y > PlayerController.STEP_HEIGHT)
