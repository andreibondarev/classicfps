class_name BotCombatController
extends CombatController

const BotTacticsScript = preload("res://scripts/cs16_bot_tactics.gd")
const BotPerceptionScript = preload("res://scripts/cs16_bot_perception.gd")
const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")
const AK47_RANGE_METERS := 81.92
const BODY_PROBE_SIDE_HU := 12.0
const BODY_PROBE_CHEST_HU := 40.0
const BODY_PROBE_FEET_HU := 2.0
## Teammate clearance around a planned burst, per grenade kind. HE cannot hurt
## allies through Combatant's damage filter, but a flashbang blinds everyone.
const GRENADE_TEAM_CLEARANCE_METERS := {
	"hegrenade": 6.0,
	"flashbang": 12.0,
	"smokegrenade": 3.0,
}
## Minimum throw distance per kind. The flashbang floor also keeps the thrower
## itself out of the worst of its own burst.
const GRENADE_MIN_THROW_METERS := {
	"hegrenade": 4.5,
	"flashbang": 9.0,
	"smokegrenade": 5.0,
}
## Local avoidance stays off for determinism, so two hulls that meet head-on
## push into each other forever. These drive the deterministic replacement.
const UNWEDGE_MIN_SPEED := 0.5
const UNWEDGE_TRAVEL_FRACTION := 0.25
const UNWEDGE_TRIGGER_TICKS := 20
## A world obstruction gets longer: the actor's own walk resolution must have
## its chance to step or jump the obstacle before the bot gives up on the line.
const UNWEDGE_WORLD_TICKS := 45
const UNWEDGE_DURATION_TICKS := 30
## A bot with right of way keeps pushing this long before it yields too, so a
## standoff the priority rule cannot break still resolves.
const UNWEDGE_PATIENCE_TICKS := 70
## Two 32 HU hulls in contact are 0.32 m apart; allow for the resolution skin.
const UNWEDGE_CONTACT_METERS := 0.85

var navigation_agent: NavigationAgent3D
var current_enemy: Combatant
var bot_index := 0
var aggression := 0.88
var tactics: RefCounted
var perception: RefCounted
var perception_blind_predicate := Callable()
var perception_smoke_predicate := Callable()
var _phase := 0.0
var _next_path_refresh := 0.0
var _objective_tick := 0
var _objective_tick_accumulator := 0.0
var _objective_round := -1
var _plant_not_before_tick := 1000
var _site_safe_since_tick := -1
var _plant_task_started_tick := -1
var _objective_site_round := -1
var _objective_site_target := Vector3.INF
var _objective_graph := AStar3D.new()
var _objective_graph_ready := false
var _objective_polygon_centers := PackedVector3Array()
var _objective_polygon_vertices: Array[PackedVector3Array] = []
var _objective_polygon_indices: Array[PackedInt32Array] = []
var _objective_polygon_components := PackedInt32Array()
var _objective_main_component := -1
var _objective_portals := {}
var _objective_route := PackedVector3Array()
var _objective_route_index := 0
var _objective_route_target := Vector3.INF
var _objective_visibility_next_tick := 0
var _patrol_target := Vector3.INF
var _patrol_generation := 0
var _unwedge_blocked_ticks := 0
var _unwedge_until_tick := -1
var _unwedge_velocity := Vector3.ZERO
var _unwedge_last_position := Vector3.INF


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
	perception = BotPerceptionScript.new()
	perception.configure(
		Callable(self, "_perception_candidates"),
		Callable(self, "_perception_probe_visible"),
		Callable(self, "_perception_is_blind"),
		Callable(self, "_perception_probe_smoked"),
		AK47_RANGE_METERS,
	)
	# Seeded per bot rather than rolled, so a rear hit produces the same turn
	# delay in every replay of the same tick stream.
	perception.damage_reaction_ticks = 18 + (index * 7) % 13


func configure_weapon(weapon_name: String) -> bool:
	if not is_instance_valid(tactics) or not tactics.configure_weapon(weapon_name):
		return false
	var definition := WeaponRegistryScript.definition(weapon_name)
	perception.configure(
		Callable(self, "_perception_candidates"),
		Callable(self, "_perception_probe_visible"),
		Callable(self, "_perception_is_blind"),
		Callable(self, "_perception_probe_smoked"),
		float(definition.range_meters),
	)
	tactics.reset(0xC516 + bot_index * 977, 0.88)
	return true


func reset_tactics() -> void:
	current_enemy = null
	_next_path_refresh = 0.0
	_objective_tick = 0
	_objective_tick_accumulator = 0.0
	_objective_round = -1
	_site_safe_since_tick = -1
	_plant_task_started_tick = -1
	_objective_site_round = -1
	_objective_site_target = Vector3.INF
	_objective_route = PackedVector3Array()
	_objective_route_index = 0
	_objective_route_target = Vector3.INF
	_objective_visibility_next_tick = 0
	_patrol_target = Vector3.INF
	_patrol_generation = 0
	_unwedge_blocked_ticks = 0
	_unwedge_until_tick = -1
	_unwedge_velocity = Vector3.ZERO
	_unwedge_last_position = Vector3.INF
	if is_instance_valid(tactics):
		tactics.reset(0xC516 + bot_index * 977, 0.88)
	if is_instance_valid(perception):
		perception.reset()


func gather_command(delta: float) -> Dictionary:
	var command := super.gather_command(delta)
	if not is_instance_valid(actor) or not actor.alive:
		return command

	_phase += delta * (0.72 + bot_index * 0.035)
	_advance_objective_clock(delta)
	var objective := _objective_context()
	objective = _resolve_objective_site(objective)
	var perception_output: Dictionary = perception.advance_seconds(
		delta,
		actor.aim_point(),
		-actor.global_transform.basis.z,
	)
	var tactics_output := _advance_tactics_from_perception(
		perception_output.get("tick_samples", []),
	)
	command = _apply_tactics_clock(command, tactics_output)
	command = _apply_grenade_intent(command, tactics_output)
	current_enemy = perception_output.get("target") as Combatant
	if not is_instance_valid(current_enemy):
		objective = _apply_plant_patience(objective, false)
		if not objective.is_empty():
			command = _apply_objective(command, objective, delta)
		else:
			command = _apply_patrol(command, delta)
		if bool(perception_output.get("investigating", false)):
			# Shot from an unseen angle: keep the current route but face the hit
			# so the attacker enters the vision cone the normal way.
			command.investigating = true
			command.look_target = perception_output.get(
				"damage_position",
				command.get("look_target", Vector3.INF),
			)
		return _apply_unwedge(command, delta)

	var sees_enemy := bool(perception_output.get("visible", false))
	objective = _apply_plant_patience(objective, sees_enemy)
	var remembered_position: Vector3 = perception_output.get(
		"position",
		actor.global_position,
	)
	var distance := actor.global_position.distance_to(remembered_position)
	var desired_velocity := Vector3.ZERO
	if not sees_enemy:
		# Perception owns this frozen memory for exactly 180 ticks. Objective
		# routing resumes only after it expires; neither route nor look reads the
		# hidden actor's live transform.
		command.state = "search"
		desired_velocity = _navigation_velocity_to(remembered_position, delta)
		command.look_target = remembered_position
		command.fire = false
		command.reload = bool(tactics_output.reload)
	elif str(tactics_output.state) in [
		BotTacticsScript.STATE_REACT,
		BotTacticsScript.STATE_ENGAGE,
		BotTacticsScript.STATE_RELOAD,
	]:
		command.state = str(tactics_output.state)
		desired_velocity = _combat_strafe_to(remembered_position, distance)
		command.fire = bool(tactics_output.fire)
		command.reload = bool(tactics_output.reload)
		command.look_target = tactics_output.aim_target
	else:
		command.state = "search"
		desired_velocity = _navigation_velocity_to(remembered_position, delta)
		command.look_target = remembered_position
	command.world_velocity = desired_velocity
	command.enemy = current_enemy if sees_enemy else null
	return _apply_unwedge(command, delta)


func _advance_tactics_from_perception(samples: Array) -> Dictionary:
	var fire_ticks: Array[int] = []
	var fire_events: Array[Dictionary] = []
	var reload_ticks: Array[int] = []
	var output: Dictionary = tactics.snapshot()
	for raw_sample: Variant in samples:
		var sample: Dictionary = raw_sample
		var sample_target := sample.get("target") as Combatant
		var sample_position: Vector3 = sample.get("position", Vector3.ZERO)
		var distance_hu := (
			actor.global_position.distance_to(sample_position)
			/ Combatant.GOLDSRC_UNIT
			if is_instance_valid(sample_target)
			else INF
		)
		output = tactics.advance_ticks(1, {
			"visible": bool(sample.get("visible", false)),
			"enemy_alive": is_instance_valid(sample_target),
			"enemy_position": sample_position,
			"enemy_velocity": sample.get("velocity", Vector3.ZERO),
			"distance_hu": distance_hu,
		})
		fire_ticks.append_array(output.get("fire_ticks", []))
		fire_events.append_array(output.get("fire_events", []))
		reload_ticks.append_array(output.get("reload_ticks", []))
	output.fire_ticks = fire_ticks
	output.fire_events = fire_events
	output.fire_count = fire_ticks.size()
	output.fire = not fire_ticks.is_empty()
	output.reload_ticks = reload_ticks
	output.reload = not reload_ticks.is_empty()
	return output


func _apply_tactics_clock(command: Dictionary, tactics_output: Dictionary) -> Dictionary:
	# Carry the complete clock result to the pawn; TargetActor must not invent a
	# second cooldown, deploy timer, or magazine.
	command.weapon_clip = int(tactics_output.clip)
	command.weapon_reserve = int(tactics_output.reserve)
	command.weapon_reloading = bool(tactics_output.reloading)
	command.reload_complete_tick = int(tactics_output.reload_complete_tick)
	command.weapon_tick = int(tactics_output.tick)
	command.fire_ticks = tactics_output.fire_ticks
	command.fire_events = tactics_output.fire_events
	command.reload_ticks = tactics_output.reload_ticks
	return command


func _apply_unwedge(command: Dictionary, delta: float) -> Dictionary:
	## Deterministic stand-in for local avoidance. NavigationAgent RVO stays
	## disabled, so nothing here may consult it: the escape is a pure function of
	## the objective tick, the actor indices/names, and the physical hulls.
	if not is_instance_valid(actor):
		return command
	var desired: Vector3 = command.get("world_velocity", Vector3.ZERO)
	desired.y = 0.0
	var travel := 0.0
	if _unwedge_last_position != Vector3.INF:
		var moved := actor.global_position - _unwedge_last_position
		moved.y = 0.0
		travel = moved.length()
	_unwedge_last_position = actor.global_position
	if _objective_tick < _unwedge_until_tick:
		command.world_velocity = _unwedge_velocity
		command.unwedging = true
		return command
	if desired.length() < UNWEDGE_MIN_SPEED:
		_unwedge_blocked_ticks = 0
		return command
	var expected := desired.length() * maxf(delta, 0.001)
	if travel < expected * UNWEDGE_TRAVEL_FRACTION:
		_unwedge_blocked_ticks += 1
	else:
		_unwedge_blocked_ticks = 0
	var blocker := _unwedge_blocking_combatant(desired)
	var trigger := (
		UNWEDGE_TRIGGER_TICKS if blocker != null else UNWEDGE_WORLD_TICKS
	)
	if _unwedge_blocked_ticks < trigger:
		return command
	if (
		blocker != null
		and not _unwedge_yields_to(blocker)
		and _unwedge_blocked_ticks < UNWEDGE_PATIENCE_TICKS
	):
		# Right of way: the lower-index actor holds its line for a moment so the
		# pair cannot sidestep into each other symmetrically.
		return command
	_unwedge_velocity = _unwedge_escape_velocity(desired, blocker)
	_unwedge_until_tick = _objective_tick + UNWEDGE_DURATION_TICKS
	_unwedge_blocked_ticks = 0
	# The corridor the route picked is occupied; force a fresh one on the way out.
	_objective_route = PackedVector3Array()
	_objective_route_target = Vector3.INF
	_patrol_target = Vector3.INF
	command.world_velocity = _unwedge_velocity
	command.unwedging = true
	return command


func _unwedge_blocking_combatant(desired: Vector3) -> Combatant:
	var direction := desired.normalized()
	var nearest: Combatant = null
	var nearest_distance := UNWEDGE_CONTACT_METERS
	for node in actor.get_tree().get_nodes_in_group("combatants"):
		var other := node as Combatant
		if other == null or other == actor or not other.alive:
			continue
		var offset := other.global_position - actor.global_position
		if absf(offset.y) >= Combatant.STANDING_HEAD_HEIGHT:
			continue
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.000001 or distance >= nearest_distance:
			continue
		# Only a body actually in the way counts; a bot walking alongside another
		# must not start sidestepping.
		if offset.normalized().dot(direction) < 0.5:
			continue
		nearest = other
		nearest_distance = distance
	return nearest


func _unwedge_yields_to(blocker: Combatant) -> bool:
	var other_index := int(blocker.get("index")) if blocker.get("index") != null else -1
	if other_index != bot_index:
		return bot_index > other_index
	# Same per-team index on opposite teams: fall back to the stable node name.
	return str(actor.name) > str(blocker.name)


func _unwedge_escape_velocity(desired: Vector3, blocker: Combatant) -> Vector3:
	var direction := desired.normalized()
	var speed := desired.length()
	var side := Vector3(-direction.z, 0.0, direction.x)
	var sign := -1.0 if bot_index % 2 == 0 else 1.0
	if blocker != null:
		var offset := blocker.global_position - actor.global_position
		offset.y = 0.0
		var lateral := side.dot(offset)
		if absf(lateral) > 0.001:
			# Step out on the side the blocker is not standing on.
			sign = -1.0 if lateral > 0.0 else 1.0
	var escape := side * sign * speed * 0.9 - direction * speed * 0.25
	if _unwedge_step_is_blocked(escape):
		escape = side * -sign * speed * 0.9 - direction * speed * 0.25
		if _unwedge_step_is_blocked(escape):
			escape = -direction * speed * 0.6
	return escape


func _unwedge_step_is_blocked(escape: Vector3) -> bool:
	if not actor is CharacterBody3D:
		return false
	# Same 120 ms hull sweep the combat sidestep uses, against the world only:
	# the blocking player is what the bot is trying to get away from.
	var body := actor as CharacterBody3D
	var previous_mask := body.collision_mask
	body.collision_mask = 1
	var world_blocked := body.test_move(
		body.global_transform,
		escape * 0.12,
		null,
		0.015,
	)
	body.collision_mask = previous_mask
	return world_blocked


func notice_damage(attacker: Combatant, _hit_position: Vector3) -> void:
	## Damage from an opponent the bot cannot see is the only stimulus that can
	## look outside the vision cone. The attacker sample is frozen here; the
	## perception clock owns the reaction delay and the memory window.
	if not is_instance_valid(actor) or not is_instance_valid(perception):
		return
	if not is_instance_valid(attacker) or not actor.is_opponent(attacker):
		return
	perception.note_damage(
		attacker,
		attacker.aim_point(),
		str(attacker.name),
	)


func _apply_grenade_intent(
	command: Dictionary,
	tactics_output: Dictionary,
) -> Dictionary:
	var events: Array = tactics_output.get("grenade_events", [])
	if events.is_empty():
		return command
	var request: Dictionary = events[0]
	var kind := str(request.kind)
	var target: Vector3 = request.target
	if not _grenade_throw_is_safe(kind, target):
		tactics.defer_grenade_throw()
		return command
	command.throw_grenade = {"kind": kind, "target": target}
	# One deliberate action per tick: a bot never sprays and lobs together.
	command.fire = false
	command.fire_ticks = []
	command.fire_events = []
	tactics.confirm_grenade_throw(kind)
	return command


func _grenade_throw_is_safe(kind: String, target: Vector3) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	var minimum: float = float(GRENADE_MIN_THROW_METERS.get(kind, 4.5))
	if actor.global_position.distance_to(target) < minimum:
		return false
	# Refuse a throw that would bounce off a wall a step in front of the bot.
	var query := PhysicsRayQueryParameters3D.create(
		actor.aim_point(),
		target,
		1,
		[actor.get_rid()],
	)
	query.collide_with_areas = false
	if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	var clearance: float = float(GRENADE_TEAM_CLEARANCE_METERS.get(kind, 6.0))
	for node in actor.get_tree().get_nodes_in_group("combatants"):
		var other := node as Combatant
		if (
			other == null
			or other == actor
			or not other.alive
			or actor.is_opponent(other)
		):
			continue
		if other.global_position.distance_to(target) < clearance:
			return false
	return true


func _resolve_objective_site(objective: Dictionary) -> Dictionary:
	if str(objective.get("action", "")) != "route_to_site":
		return objective
	var candidates: Array = objective.get("site_candidates", [])
	if candidates.is_empty() or not is_instance_valid(navigation_agent):
		return objective
	var round_number := int(objective.get("round_number", 0))
	if (
		_objective_site_round == round_number
		and _objective_site_target != Vector3.INF
	):
		var cached := objective.duplicate(true)
		cached.target = _objective_site_target
		cached.look_target = _objective_site_target
		return cached
	if not _ensure_objective_graph():
		return objective
	var start_polygon := _nearest_objective_polygon(actor.global_position)
	if start_polygon < 0:
		return objective
	var best_target: Vector3 = objective.get("target", actor.global_position)
	var best_cost := INF
	for raw_candidate: Variant in candidates:
		var candidate: Vector3 = raw_candidate
		var target_polygon := _nearest_objective_polygon(candidate)
		if target_polygon < 0:
			continue
		var path := _objective_graph.get_point_path(
			start_polygon,
			target_polygon,
		)
		if path.is_empty():
			continue
		var cost := 0.0
		for path_index in range(1, path.size()):
			cost += path[path_index - 1].distance_to(path[path_index])
		if cost < best_cost:
			best_cost = cost
			best_target = candidate
	_objective_site_round = round_number
	_objective_site_target = best_target
	var resolved := objective.duplicate(true)
	resolved.target = best_target
	resolved.look_target = best_target
	return resolved


func _advance_objective_clock(delta: float) -> void:
	_objective_tick_accumulator += maxf(0.0, delta) * 100.0
	var elapsed := int(floor(_objective_tick_accumulator + 0.000001))
	if elapsed <= 0:
		return
	_objective_tick += elapsed
	_objective_tick_accumulator -= float(elapsed)


func _apply_plant_patience(
	objective: Dictionary,
	sees_enemy: bool,
) -> Dictionary:
	if objective.is_empty():
		_site_safe_since_tick = -1
		return objective
	var round_number := int(objective.get("round_number", 0))
	if round_number != _objective_round:
		_objective_round = round_number
		_objective_tick = int(objective.get("live_elapsed_ticks", 0))
		_objective_tick_accumulator = 0.0
		# Deterministic equivalent of RANDOM_FLOAT(10, 30), varied by bot and
		# round while remaining host/render-schedule independent.
		_plant_not_before_tick = 1000 + (
			(bot_index * 977 + round_number * 619 + 0xC4) % 2001
		)
		_site_safe_since_tick = -1
	var objective_action := str(objective.get("action", ""))
	if objective_action not in ["route_to_site", "plant"]:
		_site_safe_since_tick = -1
		_plant_task_started_tick = -1
		return objective
	if objective_action == "plant":
		if not bool(objective.get("plant_in_progress", false)):
			_plant_task_started_tick = -1
		elif _plant_task_started_tick < 0:
			_plant_task_started_tick = _objective_tick
		elif _objective_tick - _plant_task_started_tick >= 500:
			# ReGameDLL's PlantBomb task cannot own the bot indefinitely. Drop
			# attack for one command so RoundState aborts and the objective can
			# be selected again on the next decision.
			_plant_task_started_tick = -1
			var timed_out := objective.duplicate(true)
			timed_out.state = "plant_timeout"
			timed_out.action = "hold_site"
			timed_out.equip_c4 = false
			return timed_out
	if (
		objective_action == "route_to_site"
		and _objective_tick < _plant_not_before_tick
	):
		_site_safe_since_tick = -1
		# The chosen planter does not stand motionless at spawn. Before its
		# seeded plant timestamp it remains in normal hunt/self-defense logic;
		# only the objective route is deferred.
		return {}
	if sees_enemy:
		_site_safe_since_tick = -1
	else:
		if _site_safe_since_tick < 0:
			_site_safe_since_tick = _objective_tick
	var safe_ticks := (
		0
		if _site_safe_since_tick < 0
		else _objective_tick - _site_safe_since_tick
	)
	if _objective_tick < _plant_not_before_tick and safe_ticks < 300:
		var waiting := objective.duplicate(true)
		waiting.state = "secure_bombsite"
		waiting.action = "hold_site"
		waiting.equip_c4 = false
		waiting.crouch = false
		return waiting
	return objective


func _objective_context() -> Dictionary:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return {}
	var scene := actor.get_tree().current_scene
	if (
		not is_instance_valid(scene)
		or not scene.has_method("bot_objective_context")
	):
		return {}
	var context: Variant = scene.call("bot_objective_context", actor)
	return context if context is Dictionary else {}


var _snap_raw_target := Vector3.INF
var _snap_polygon := -1


func _snap_objective_target(raw_target: Vector3) -> Vector3:
	## Deterministic replacement for NavigationServer3D.map_get_closest_point.
	## The server merges region polygons on the render loop, so the physics tick
	## at which its projection stops returning Vector3.ZERO (empty map) depends
	## on the render frame rate — and the determinism gate replays the same
	## match at --fixed-fps 30 and 240. Project onto the same baked polygons the
	## objective graph already extracted; that data is available synchronously.
	if not _ensure_objective_graph():
		return raw_target
	if raw_target.distance_squared_to(_snap_raw_target) > 0.0625:
		_snap_polygon = _nearest_objective_polygon(raw_target)
		_snap_raw_target = raw_target
	if _snap_polygon < 0:
		return raw_target
	return _closest_point_on_objective_polygon(raw_target, _snap_polygon)


func _apply_objective(
	command: Dictionary,
	objective: Dictionary,
	delta: float,
) -> Dictionary:
	var target: Vector3 = objective.get("target", actor.global_position)
	target = _snap_objective_target(target)
	var stop_radius := maxf(0.0, float(objective.get("stop_radius", 0.42)))
	var distance := actor.global_position.distance_to(target)
	var objective_action := str(objective.get("action", ""))
	command.state = str(objective.get("state", "objective"))
	command.objective_action = objective_action
	command.objective_id = str(objective.get("objective_id", ""))
	command.objective_target = target
	command.c4_equipped = bool(objective.get("equip_c4", false))
	command.crouch = bool(objective.get("crouch", false))
	command.use = bool(objective.get("use", false))
	command.look_target = objective.get("look_target", target)
	command.world_velocity = (
		Vector3.ZERO
		if distance <= stop_radius
		else _objective_navigation_velocity_to(target, delta)
	)
	command.fire = false
	command.reload = false
	return command


func _objective_navigation_velocity_to(
	target_position: Vector3,
	delta: float,
) -> Vector3:
	# Objective positions come from BSP entities (bomb targets, C4 origin and
	# computed cover points), not from navigation polygons. Godot 4.7's
	# NavigationAgent and NavigationServer corridor query can reject two
	# polygons even when they belong to the same connected NavigationMesh
	# component. Build deterministic A* directly over that exact baked mesh.
	# The resulting velocity flows through the actor's deterministic physical
	# hull; asynchronous NavigationServer RVO is intentionally disabled.
	if not _ensure_objective_graph():
		return Vector3.ZERO
	if (
		_objective_route.is_empty()
		or _objective_route_target == Vector3.INF
		or _objective_route_target.distance_squared_to(target_position) > 0.0625
	):
		_objective_route_target = target_position
		var start_polygon := _nearest_objective_polygon(actor.global_position)
		var target_polygon := _nearest_objective_polygon(target_position)
		if start_polygon < 0 or target_polygon < 0:
			_objective_route = PackedVector3Array()
			return Vector3.ZERO
		var polygon_route := _objective_graph.get_id_path(
			start_polygon,
			target_polygon,
		)
		_objective_route = _funnel_objective_route(
			actor.global_position,
			target_position,
			polygon_route,
		)
		_objective_route_index = mini(1, _objective_route.size() - 1)
	if _objective_route.is_empty():
		return Vector3.ZERO
	_objective_route_index = mini(
		_objective_route_index,
		_objective_route.size() - 1,
	)
	while (
		_objective_route_index + 1 < _objective_route.size()
		and (
			actor.global_position.distance_squared_to(
				_objective_route[_objective_route_index]
			) < 0.16
			or _passed_objective_waypoint(_objective_route_index)
		)
	):
		_objective_route_index += 1
	if _objective_tick >= _objective_visibility_next_tick:
		_objective_visibility_next_tick = _objective_tick + 10
		_skip_visible_objective_waypoints()
	var planar := _objective_route[_objective_route_index] - actor.global_position
	planar.y = 0.0
	if planar.length_squared() <= 0.0025:
		return Vector3.ZERO
	return planar.normalized() * navigation_agent.max_speed


func _ensure_objective_graph() -> bool:
	if _objective_graph_ready:
		return not _objective_polygon_centers.is_empty()
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return false
	var scene := actor.get_tree().current_scene
	if not is_instance_valid(scene):
		return false
	var imported_map: BspMap = scene.get("imported_map") as BspMap
	if (
		not is_instance_valid(imported_map)
		or not is_instance_valid(imported_map.navigation_region)
		or not is_instance_valid(imported_map.navigation_region.navigation_mesh)
	):
		return false
	var navigation_mesh := imported_map.navigation_region.navigation_mesh
	if navigation_mesh.get_polygon_count() == 0:
		return false
	_objective_graph.clear()
	_objective_polygon_centers = PackedVector3Array()
	_objective_polygon_centers.resize(navigation_mesh.get_polygon_count())
	_objective_polygon_vertices.clear()
	_objective_polygon_vertices.resize(navigation_mesh.get_polygon_count())
	_objective_polygon_indices.clear()
	_objective_polygon_indices.resize(navigation_mesh.get_polygon_count())
	_objective_portals.clear()
	var vertices := navigation_mesh.vertices
	var edge_owners := {}
	for polygon_index in navigation_mesh.get_polygon_count():
		var polygon := navigation_mesh.get_polygon(polygon_index)
		var local_center := Vector3.ZERO
		var world_polygon := PackedVector3Array()
		for vertex_index: int in polygon:
			local_center += vertices[vertex_index]
			world_polygon.append(
				imported_map.navigation_region.to_global(vertices[vertex_index])
			)
		local_center /= float(polygon.size())
		var center := imported_map.navigation_region.to_global(local_center)
		_objective_polygon_centers[polygon_index] = center
		_objective_polygon_vertices[polygon_index] = world_polygon
		_objective_polygon_indices[polygon_index] = polygon
		_objective_graph.add_point(polygon_index, center)
		for edge_index in polygon.size():
			var first: int = polygon[edge_index]
			var second: int = polygon[(edge_index + 1) % polygon.size()]
			var edge := Vector2i(mini(first, second), maxi(first, second))
			if edge_owners.has(edge):
				var other_polygon := int(edge_owners[edge])
				_objective_graph.connect_points(
					other_polygon,
					polygon_index,
					true,
				)
				var portal := PackedVector3Array([
					imported_map.navigation_region.to_global(vertices[first]),
					imported_map.navigation_region.to_global(vertices[second]),
				])
				_objective_portals[
					Vector2i(other_polygon, polygon_index)
				] = portal
				_objective_portals[
					Vector2i(polygon_index, other_polygon)
				] = portal
			else:
				edge_owners[edge] = polygon_index
	_build_objective_components()
	_objective_graph_ready = true
	return true


func _nearest_objective_polygon(point: Vector3) -> int:
	var nearest := -1
	var nearest_distance := INF
	for polygon_index in _objective_polygon_vertices.size():
		if (
			_objective_main_component >= 0
			and _objective_polygon_components[polygon_index]
			!= _objective_main_component
		):
			continue
		var polygon := _objective_polygon_vertices[polygon_index]
		if polygon.size() < 3:
			continue
		for triangle_index in range(1, polygon.size() - 1):
			var closest := _closest_point_on_triangle(
				point,
				polygon[0],
				polygon[triangle_index],
				polygon[triangle_index + 1],
			)
			var distance := point.distance_squared_to(closest)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = polygon_index
	return nearest


func _build_objective_components() -> void:
	var polygon_count := _objective_polygon_centers.size()
	_objective_polygon_components.resize(polygon_count)
	_objective_polygon_components.fill(-1)
	_objective_main_component = -1
	var largest_size := 0
	var component := 0
	for polygon_index in polygon_count:
		if _objective_polygon_components[polygon_index] >= 0:
			continue
		var stack := [polygon_index]
		_objective_polygon_components[polygon_index] = component
		var component_size := 0
		while not stack.is_empty():
			var current: int = stack.pop_back()
			component_size += 1
			for neighbor_id: int in _objective_graph.get_point_connections(current):
				if _objective_polygon_components[neighbor_id] >= 0:
					continue
				_objective_polygon_components[neighbor_id] = component
				stack.append(neighbor_id)
		if component_size > largest_size:
			largest_size = component_size
			_objective_main_component = component
		component += 1


func _funnel_objective_route(
	start_position: Vector3,
	target_position: Vector3,
	polygon_route: PackedInt64Array,
) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon_route.is_empty():
		return result
	var projected_start := _closest_point_on_objective_polygon(
		start_position,
		int(polygon_route[0]),
	)
	var projected_target := _closest_point_on_objective_polygon(
		target_position,
		int(polygon_route[polygon_route.size() - 1]),
	)
	var portals: Array[Dictionary] = [{
		"left": projected_start,
		"right": projected_start,
	}]
	for route_index in range(1, polygon_route.size()):
		var previous := int(polygon_route[route_index - 1])
		var current := int(polygon_route[route_index])
		var shared := _shared_objective_portal(previous, current)
		if shared.size() != 2:
			return PackedVector3Array()
		var first: Vector3 = shared[0]
		var second: Vector3 = shared[1]
		var midpoint := (first + second) * 0.5
		var direction := (
			_objective_polygon_centers[current]
			- _objective_polygon_centers[previous]
		)
		var first_is_left := _triarea2_xz(
			midpoint,
			midpoint + direction,
			first,
		) > 0.0
		var left := first if first_is_left else second
		var right := second if first_is_left else first
		# The navmesh has already been eroded by the player radius. A tiny
		# inward portal inset avoids selecting the exact shared-edge endpoint
		# without double-applying hull clearance.
		var inset := minf(0.015, left.distance_to(right) * 0.1)
		if inset > 0.0:
			left = left.move_toward(midpoint, inset)
			right = right.move_toward(midpoint, inset)
		portals.append({"left": left, "right": right})
	portals.append({"left": projected_target, "right": projected_target})
	var pulled := _pull_objective_funnel(portals)
	if _objective_route_is_bsp_clear(pulled):
		return pulled
	# A pure XZ funnel can legally cross a stacked-floor discontinuity even
	# though every individual portal belongs to the polygon corridor. Fall
	# back to consecutive portal midpoints when the full GoldSrc hull proves
	# any pulled segment would touch BSP.
	var fallback := PackedVector3Array([projected_start])
	for portal_index in range(1, portals.size() - 1):
		fallback.append(
			(
				Vector3(portals[portal_index].left)
				+ Vector3(portals[portal_index].right)
			) * 0.5
		)
	fallback.append(projected_target)
	return _compact_objective_route(fallback)


func _shared_objective_portal(first_polygon: int, second_polygon: int) -> PackedVector3Array:
	var key := Vector2i(first_polygon, second_polygon)
	if not _objective_portals.has(key):
		return PackedVector3Array()
	return _objective_portals[key]


func _pull_objective_funnel(portals: Array[Dictionary]) -> PackedVector3Array:
	var route := PackedVector3Array()
	if portals.is_empty():
		return route
	var apex: Vector3 = portals[0].left
	var left: Vector3 = apex
	var right: Vector3 = apex
	var apex_index := 0
	var left_index := 0
	var right_index := 0
	route.append(apex)
	var portal_index := 1
	while portal_index < portals.size():
		var next_left: Vector3 = portals[portal_index].left
		var next_right: Vector3 = portals[portal_index].right
		if _triarea2_xz(apex, right, next_right) <= 0.000001:
			if (
				_same_xz(apex, right)
				or _triarea2_xz(apex, left, next_right) > 0.000001
			):
				right = next_right
				right_index = portal_index
			else:
				if not _same_xz(route[route.size() - 1], left):
					route.append(left)
				apex = left
				apex_index = left_index
				left = apex
				right = apex
				left_index = apex_index
				right_index = apex_index
				portal_index = apex_index + 1
				continue
		if _triarea2_xz(apex, left, next_left) >= -0.000001:
			if (
				_same_xz(apex, left)
				or _triarea2_xz(apex, right, next_left) < -0.000001
			):
				left = next_left
				left_index = portal_index
			else:
				if not _same_xz(route[route.size() - 1], right):
					route.append(right)
				apex = right
				apex_index = right_index
				left = apex
				right = apex
				left_index = apex_index
				right_index = apex_index
				portal_index = apex_index + 1
				continue
		portal_index += 1
	var final_target: Vector3 = portals[portals.size() - 1].left
	if route.is_empty() or not _same_xz(route[route.size() - 1], final_target):
		route.append(final_target)
	return route


func _closest_point_on_objective_polygon(point: Vector3, polygon_index: int) -> Vector3:
	var polygon := _objective_polygon_vertices[polygon_index]
	var closest := _objective_polygon_centers[polygon_index]
	var closest_distance := INF
	for triangle_index in range(1, polygon.size() - 1):
		var candidate := _closest_point_on_triangle(
			point,
			polygon[0],
			polygon[triangle_index],
			polygon[triangle_index + 1],
		)
		var distance := point.distance_squared_to(candidate)
		if distance < closest_distance:
			closest_distance = distance
			closest = candidate
	return closest


func _triarea2_xz(a: Vector3, b: Vector3, c: Vector3) -> float:
	return (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)


func _same_xz(a: Vector3, b: Vector3) -> bool:
	return Vector2(a.x - b.x, a.z - b.z).length_squared() <= 0.000001


func _objective_route_is_bsp_clear(route: PackedVector3Array) -> bool:
	if route.size() < 2 or not is_instance_valid(actor):
		return true
	for route_index in range(1, route.size()):
		if not _objective_segment_is_bsp_clear(
			route[route_index - 1],
			route[route_index],
		):
			return false
	return true


func _compact_objective_route(route: PackedVector3Array) -> PackedVector3Array:
	if route.size() <= 2:
		return route
	var compact := PackedVector3Array([route[0]])
	var source_index := 0
	while source_index < route.size() - 1:
		var next_index := source_index + 1
		for candidate_index in range(route.size() - 1, source_index, -1):
			if _objective_segment_is_bsp_clear(
				route[source_index],
				route[candidate_index],
			):
				next_index = candidate_index
				break
		compact.append(route[next_index])
		source_index = next_index
	return compact


func _objective_segment_is_bsp_clear(start: Vector3, finish: Vector3) -> bool:
	var hull := BoxShape3D.new()
	hull.size = Vector3(32.0, 72.0, 32.0) * Combatant.GOLDSRC_UNIT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull
	query.collision_mask = 1
	query.collide_with_areas = false
	query.transform = Transform3D(
		Basis.IDENTITY,
		start + Vector3.UP * (36.0 * Combatant.GOLDSRC_UNIT + 0.02),
	)
	query.motion = finish - start
	var cast := actor.get_world_3d().direct_space_state.cast_motion(query)
	return not cast.is_empty() and float(cast[0]) >= 0.995


func _skip_visible_objective_waypoints() -> void:
	var candidate := _objective_route_index + 1
	while candidate < _objective_route.size():
		if not _objective_segment_is_bsp_clear(
			actor.global_position,
			_objective_route[candidate],
		):
			break
		_objective_route_index = candidate
		candidate += 1


func _passed_objective_waypoint(waypoint_index: int) -> bool:
	if waypoint_index <= 0 or waypoint_index >= _objective_route.size():
		return false
	var incoming := (
		_objective_route[waypoint_index]
		- _objective_route[waypoint_index - 1]
	)
	incoming.y = 0.0
	if incoming.length_squared() <= 0.000001:
		return true
	var beyond := actor.global_position - _objective_route[waypoint_index]
	beyond.y = 0.0
	return beyond.dot(incoming) > 0.0


func _closest_point_on_triangle(
	point: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3,
) -> Vector3:
	# Ericson's Voronoi-region triangle projection. Unlike center distance,
	# this distinguishes stacked floors and narrow polygons by their real
	# surfaces.
	var ab := b - a
	var ac := c - a
	var ap := point - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := point - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := point - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var edge := c - b
		return b + edge * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denominator := 1.0 / (va + vb + vc)
	var v := vb * denominator
	var w := vc * denominator
	return a + ab * v + ac * w


func set_perception_predicates(
	blind_predicate := Callable(),
	smoke_predicate := Callable(),
) -> void:
	perception_blind_predicate = blind_predicate
	perception_smoke_predicate = smoke_predicate


func _perception_candidates(_tick: int) -> Array:
	var candidates: Array = []
	for candidate_node in actor.get_tree().get_nodes_in_group("combatants"):
		var candidate := candidate_node as Combatant
		if (
			not is_instance_valid(candidate)
			or not candidate.alive
			or not actor.is_opponent(candidate)
		):
			continue
		var chest := (
			candidate.global_position
			+ Vector3.UP * BODY_PROBE_CHEST_HU * Combatant.GOLDSRC_UNIT
		)
		var side := (
			candidate.global_transform.basis.x.normalized()
			* BODY_PROBE_SIDE_HU
			* Combatant.GOLDSRC_UNIT
		)
		candidates.append({
			"target": candidate,
			"id": str(candidate.name),
			"alive": candidate.alive,
			"position": chest,
			"velocity": candidate.velocity,
			"probes": PackedVector3Array([
				Vector3(
					candidate.global_position.x,
					candidate.head_height(),
					candidate.global_position.z,
				),
				chest,
				(
					candidate.global_position
					+ Vector3.UP * BODY_PROBE_FEET_HU * Combatant.GOLDSRC_UNIT
				),
				chest - side,
				chest + side,
			]),
		})
	return candidates


func _perception_probe_visible(
	candidate: Dictionary,
	probe: Vector3,
	_tick: int,
) -> bool:
	var target := candidate.get("target") as Combatant
	if not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		actor.aim_point(),
		probe,
		1 | 2 | 4,
		[actor.get_rid()],
	)
	query.collide_with_areas = false
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == target


func _perception_is_blind(perception_tick: int) -> bool:
	return (
		bool(perception_blind_predicate.call(actor, perception_tick))
		if perception_blind_predicate.is_valid()
		else false
	)


func _perception_probe_smoked(
	origin: Vector3,
	probe: Vector3,
	candidate: Dictionary,
	perception_tick: int,
) -> bool:
	return (
		bool(
			perception_smoke_predicate.call(
				actor,
				candidate.get("target"),
				origin,
				probe,
				perception_tick,
			)
		)
		if perception_smoke_predicate.is_valid()
		else false
	)


func _apply_patrol(command: Dictionary, delta: float) -> Dictionary:
	command.state = "patrol"
	command.fire = false
	command.enemy = null
	if not _ensure_objective_graph():
		return command
	if (
		_patrol_target == Vector3.INF
		or actor.global_position.distance_squared_to(_patrol_target) <= 0.36
	):
		_patrol_target = _choose_patrol_target()
		_patrol_generation += 1
	if _patrol_target == Vector3.INF:
		return command
	command.look_target = _patrol_target
	command.world_velocity = _objective_navigation_velocity_to(
		_patrol_target,
		delta,
	)
	return command


func _choose_patrol_target() -> Vector3:
	var polygon_count := _objective_polygon_centers.size()
	if polygon_count <= 0:
		return Vector3.INF
	var start := posmod(
		bot_index * 997 + _patrol_generation * 619 + 47,
		polygon_count,
	)
	var fallback := Vector3.INF
	for offset in polygon_count:
		var polygon_index := (start + offset) % polygon_count
		if (
			_objective_main_component >= 0
			and _objective_polygon_components[polygon_index]
			!= _objective_main_component
		):
			continue
		var candidate := _objective_polygon_centers[polygon_index]
		if fallback == Vector3.INF:
			fallback = candidate
		if actor.global_position.distance_squared_to(candidate) >= 16.0:
			return candidate
	return fallback


func _combat_strafe_to(enemy_position: Vector3, distance: float) -> Vector3:
	var to_enemy := enemy_position - actor.global_position
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
	# The physical 32x72x32 HU hull resolves player contacts. Refuse a combat
	# sidestep if that same hull would touch BSP within the next 120 ms.
	if actor is CharacterBody3D and (
		actor as CharacterBody3D
	).test_move(actor.global_transform, desired * 0.12, null, 0.015):
		return Vector3.ZERO
	return desired


func _navigation_velocity_to(target_position: Vector3, delta: float) -> Vector3:
	# Godot's NavigationServer query/RVO scheduling is asynchronous and can
	# produce different paths across identical fresh processes. All bot travel
	# uses the same baked-mesh A* and funnel route as objectives, making the
	# full-physics result a deterministic function of fixed ticks.
	return _objective_navigation_velocity_to(target_position, delta)
