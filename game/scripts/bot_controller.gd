class_name BotCombatController
extends CombatController

const BotTacticsScript = preload("res://scripts/cs16_bot_tactics.gd")
const AK47_RANGE_METERS := 81.92

var navigation_agent: NavigationAgent3D
var current_enemy: Combatant
var bot_index := 0
var tactics: RefCounted
var _phase := 0.0
var _next_target_refresh := 0.0
var _next_path_refresh := 0.0


func configure(
	combatant: Combatant,
	agent: NavigationAgent3D,
	index: int,
) -> void:
	possess(combatant)
	navigation_agent = agent
	bot_index = index
	_phase = float(index) * 1.13
	tactics = BotTacticsScript.new()
	tactics.reset(0xC516 + index * 977, 0.88)


func reset_tactics() -> void:
	current_enemy = null
	_next_target_refresh = 0.0
	_next_path_refresh = 0.0
	if is_instance_valid(tactics):
		tactics.reset(0xC516 + bot_index * 977, 0.88)


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	if not is_instance_valid(actor) or not actor.alive:
		return command

	_phase += delta * (0.72 + bot_index * 0.035)
	_next_target_refresh -= delta
	if (
		_next_target_refresh <= 0.0
		or not is_instance_valid(current_enemy)
		or not current_enemy.alive
	):
		_next_target_refresh = 0.18
		current_enemy = _select_enemy()
	if not is_instance_valid(current_enemy):
		return command

	var sees_enemy := _has_line_of_sight(current_enemy)
	var distance := actor.global_position.distance_to(current_enemy.global_position)
	var tactics_output: Dictionary = tactics.advance_seconds(delta, {
		"visible": sees_enemy,
		"enemy_alive": current_enemy.alive,
		"enemy_position": current_enemy.aim_point(),
		"enemy_velocity": current_enemy.velocity,
		"distance_hu": distance / Combatant.GOLDSRC_UNIT,
	})
	# The tactics clock is the bot's authoritative AK inventory/weapon clock.
	# Carry its complete result to the pawn; TargetActor must not invent a
	# second cooldown or a second magazine.
	command.weapon_clip = int(tactics_output.clip)
	command.weapon_reserve = int(tactics_output.reserve)
	command.weapon_reloading = bool(tactics_output.reloading)
	command.reload_complete_tick = int(tactics_output.reload_complete_tick)
	command.weapon_tick = int(tactics_output.tick)
	command.fire_ticks = tactics_output.fire_ticks
	command.fire_events = tactics_output.fire_events
	command.reload_ticks = tactics_output.reload_ticks
	var desired_velocity := Vector3.ZERO
	if str(tactics_output.state) in [
		BotTacticsScript.STATE_REACT,
		BotTacticsScript.STATE_ENGAGE,
		BotTacticsScript.STATE_RELOAD,
	]:
		command.state = str(tactics_output.state)
		desired_velocity = _combat_strafe(current_enemy, distance)
		command.fire = bool(tactics_output.fire)
		command.reload = bool(tactics_output.reload)
		command.look_target = tactics_output.aim_target
	elif str(tactics_output.state) == BotTacticsScript.STATE_SEARCH:
		command.state = "search"
		desired_velocity = _navigation_velocity_to(
			tactics_output.last_seen_position,
			delta,
		)
		command.look_target = tactics_output.aim_target
	else:
		command.state = "hunt"
		desired_velocity = _navigation_velocity(current_enemy, delta)
		command.look_target = current_enemy.global_position
	command.world_velocity = desired_velocity
	command.enemy = current_enemy
	return command


func _select_enemy() -> Combatant:
	var nearest: Combatant
	var nearest_distance := INF
	for candidate_node in actor.get_tree().get_nodes_in_group("combatants"):
		var candidate := candidate_node as Combatant
		if (
			not is_instance_valid(candidate)
			or not candidate.alive
			or not actor.is_opponent(candidate)
		):
			continue
		var distance := actor.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _has_line_of_sight(enemy: Combatant) -> bool:
	var origin := actor.aim_point()
	var target := enemy.aim_point()
	if origin.distance_squared_to(target) > AK47_RANGE_METERS * AK47_RANGE_METERS:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		target,
		1 | 2 | 4,
		[actor.get_rid()],
	)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == enemy


func _combat_strafe(enemy: Combatant, distance: float) -> Vector3:
	var to_enemy := enemy.global_position - actor.global_position
	to_enemy.y = 0.0
	if to_enemy.is_zero_approx():
		return Vector3.ZERO
	var tangent := Vector3(-to_enemy.z, 0.0, to_enemy.x).normalized()
	var direction_sign := -1.0 if bot_index % 2 == 0 else 1.0
	var desired := tangent * direction_sign * cos(_phase) * 1.9
	if distance > 16.0:
		desired += to_enemy.normalized() * 1.4
	elif distance < 8.0:
		desired -= to_enemy.normalized() * 1.4
	# RVO prevents player-player overlap but does not keep an arbitrary strafe
	# vector inside the baked walkable corridor. Refuse a combat sidestep if
	# the physical 32x72x32 HU body would touch BSP within the next 120 ms.
	if actor is CharacterBody3D and (
		actor as CharacterBody3D
	).test_move(actor.global_transform, desired * 0.12, null, 0.015):
		return Vector3.ZERO
	return desired


func _navigation_velocity(enemy: Combatant, delta: float) -> Vector3:
	return _navigation_velocity_to(enemy.global_position, delta)


func _navigation_velocity_to(target_position: Vector3, delta: float) -> Vector3:
	if not is_instance_valid(navigation_agent):
		return Vector3.ZERO
	_next_path_refresh -= delta
	if _next_path_refresh <= 0.0:
		_next_path_refresh = 0.28 + float(bot_index) * 0.015
		navigation_agent.target_position = target_position
	if navigation_agent.is_navigation_finished():
		return Vector3.ZERO
	var planar := navigation_agent.get_next_path_position() - actor.global_position
	planar.y = 0.0
	if planar.length_squared() <= 0.0025:
		return Vector3.ZERO
	return planar.normalized() * navigation_agent.max_speed
