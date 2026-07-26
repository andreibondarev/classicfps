class_name BotCombatController
extends CombatController

var navigation_agent: NavigationAgent3D
var current_enemy: Combatant
var bot_index := 0
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
	var desired_velocity := Vector3.ZERO
	if sees_enemy and distance <= 22.0:
		command.state = "engage"
		desired_velocity = _combat_strafe(current_enemy, distance)
		command.fire = distance <= 38.0
		command.look_target = current_enemy.aim_point()
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
	if origin.distance_squared_to(target) > 48.0 * 48.0:
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
	return desired


func _navigation_velocity(enemy: Combatant, delta: float) -> Vector3:
	if not is_instance_valid(navigation_agent):
		return Vector3.ZERO
	_next_path_refresh -= delta
	if _next_path_refresh <= 0.0:
		_next_path_refresh = 0.28 + float(bot_index) * 0.015
		navigation_agent.target_position = enemy.global_position
	if navigation_agent.is_navigation_finished():
		return Vector3.ZERO
	var planar := navigation_agent.get_next_path_position() - actor.global_position
	planar.y = 0.0
	if planar.length_squared() <= 0.0025:
		return Vector3.ZERO
	return planar.normalized() * navigation_agent.max_speed
