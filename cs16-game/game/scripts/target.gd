class_name TargetActor
extends Combatant

signal died(actor: TargetActor, headshot: bool)
signal damaged(actor: TargetActor, health: int, headshot: bool)
signal fired

const CharacterModelScript = preload("res://scripts/mdl_character_model.gd")
const CombatEffectsScript = preload("res://scripts/cs16_combat_effects.gd")
const AudioRouterScript = preload("res://scripts/cs16_audio_event_router.gd")
const AudioCatalogScript = preload("res://scripts/cs16_audio_catalog.gd")
const BallisticsScript = preload("res://scripts/cs16_ballistics.gd")
const BotTacticsScript = preload("res://scripts/cs16_bot_tactics.gd")
const WeaponRegistryScript = preload("res://scripts/cs16_weapon_registry.gd")
const GrenadeScript = preload("res://scripts/grenade.gd")
const BrushContactsScript = preload("res://scripts/cs16_brush_contacts.gd")
const TERRORIST_SKINS := ["terror", "leet", "arctic", "guerilla"]
const COUNTER_TERRORIST_SKINS := ["urban", "gsg9", "sas", "gign"]
const STANDING_HULL_SIZE := Vector3(32, 72, 32) * GOLDSRC_UNIT
const STANDING_HULL_CENTER_Y := 36.0 * GOLDSRC_UNIT
const PLAYER_GRAVITY := 800.0 * GOLDSRC_UNIT
const AK47_MAX_SPEED := 221.0 * GOLDSRC_UNIT
const FLOOR_NORMAL_MINIMUM := 0.7
const FLOOR_CATEGORIZE_DISTANCE := 2.0 * GOLDSRC_UNIT
const FOOTSTEP_MINIMUM_SPEED := 150.0 * GOLDSRC_UNIT
const FOOTSTEP_INTERVAL_TICKS := 30
const LANDING_MINIMUM_SPEED_UPS := 350.0
const LANDING_FULL_VOLUME_SPEED_UPS := 500.0
## Fraction of the wanted planar motion a clipped slide must keep before the
## walk resolution is considered good enough to skip the step-up attempt.
const STEP_CLIMB_SLIDE_FRACTION := 0.9
## PM_Jump's 268 u/s impulse; against 800 u/s^2 gravity it clears about 45 HU.
const JUMP_SPEED := 268.0 * GOLDSRC_UNIT
## Probe height for a jumpable ledge, kept under the real apex for margin.
const JUMP_PROBE_HEIGHT := 42.0 * GOLDSRC_UNIT
## Ticks a bot must stay obstructed by world geometry before it jumps, and the
## cooldown afterwards. Both keep bots from bunny-hopping or drumming a wall.
const JUMP_BLOCKED_TICKS := 25
const JUMP_COOLDOWN_TICKS := 150

var active := false
var index := 0
var combat_state := "idle"
var navigation_agent: NavigationAgent3D
var player_skin := ""
var character_model: MdlCharacterModel
var weapon_clip := BotTacticsScript.AK_CLIP_SIZE
var weapon_reserve := BotTacticsScript.AK_RESERVE_SIZE
var weapon_reloading := false
var weapon_tick := 0
var _reload_audio_schedule: Array[Dictionary] = []
var active_weapon_name := "ak47"
var grenade_counts := {}
var shot_trace: Array[Dictionary] = []
var grenade_trace: Array[Dictionary] = []
var owns_c4 := false
var c4_equipped := false
var c4_deploy_ready_tick := -1
## Layer of authored bot-clip walls (assets/navigation/<map>.tscn): invisible
## barriers only bots collide with, like GoldSrc's CLIP brushes for bots, e.g.
## keeping them out of pockets they cannot climb back out of.
const BOT_CLIP_LAYER := 8
var objective_movement_locked := false
var objective_crouch := false
var objective_look_target := Vector3.INF

var _anchor := Vector3.ZERO
var _body_material: StandardMaterial3D
var _body_mesh: MeshInstance3D
var _collision_shape: CollisionShape3D
var _muzzle: OmniLight3D
var _fallback_visual: Node3D
var _safe_navigation_velocity := Vector3.ZERO
var _navigation_velocity_ready := false
var _effect_shot_sequence := 0
var _ak_burst_shots := 0
var _rifle_accuracy := 0.2
var _pistol_accuracy := 0.9
var _last_fire_tick := -1000
var _next_footstep_tick := 0
var _movement_tick := 0
var _obstructed_ticks := 0
var _next_jump_tick := 0
var _movement_probe_result := KinematicCollision3D.new()
var _brush_contacts := PackedInt32Array()
var _left_foot := false
var _footstep_serial := 0
var _fall_velocity_ups := 0.0
var combat_effects: CS16CombatEffects
var audio_router: CS16AudioEventRouter


func _is_dedicated_server() -> bool:
	var session := get_node_or_null("/root/NetworkSession")
	return is_instance_valid(session) and bool(session.get("dedicated_server"))


func _ready() -> void:
	if team == TEAM_UNASSIGNED:
		configure_identity(TEAM_COUNTER_TERRORIST, "CT Bot %02d" % (index + 1))
	super._ready()
	add_to_group("bots")
	add_to_group("targets")
	collision_layer = 2
	# GoldSrc player hulls are solid to the BSP and to every live player.
	# CharacterBody collision is authoritative; asynchronous RVO is deliberately
	# disabled because identical 100 Hz replays must produce identical travel.
	collision_mask = 1 | 2 | 4 | BOT_CLIP_LAYER
	# Keep the swept 32 HU hull a half-unit off BSP planes. This matches the
	# separation epsilon GoldSrc's PMove retains after clipping and prevents a
	# solved wall contact from being reported as a one-frame penetration.
	safe_margin = 0.25 * GOLDSRC_UNIT
	floor_max_angle = acos(FLOOR_NORMAL_MINIMUM)
	floor_snap_length = FLOOR_CATEGORIZE_DISTANCE
	floor_stop_on_slope = true
	# PM_ClipVelocity retains tangential movement (down to STOP_EPSILON),
	# even when walking almost straight into a wall. Godot's default 15-degree
	# guard discards the small lateral correction needed in narrow corridors.
	wall_min_slide_angle = 0.0
	_anchor = global_position
	_build_actor()
	combat_effects = CombatEffectsScript.for_scene(get_tree().current_scene)
	audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	_build_navigation_agent()
	combat_controller = BotCombatController.new()
	combat_controller.name = "BotController"
	add_child(combat_controller)
	(combat_controller as BotCombatController).configure(self, navigation_agent, index)


func _build_navigation_agent() -> void:
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "NavigationAgent"
	# CharacterBody3D uses a feet-level origin while Godot returns navmesh path
	# points about one agent radius above it. Remove that vertical discrepancy
	# so the agent can actually consume its first waypoint.
	navigation_agent.path_height_offset = 0.16
	navigation_agent.radius = 16.0 * GOLDSRC_UNIT
	navigation_agent.height = 72.0 * GOLDSRC_UNIT
	navigation_agent.path_desired_distance = 32.0 * GOLDSRC_UNIT
	navigation_agent.target_desired_distance = 5.5
	navigation_agent.max_speed = AK47_MAX_SPEED
	navigation_agent.neighbor_distance = 2.2
	navigation_agent.max_neighbors = 8
	navigation_agent.time_horizon_agents = 0.65
	navigation_agent.avoidance_enabled = false
	add_child(navigation_agent)


func _build_actor() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "PlayerCollider"
	var shape := BoxShape3D.new()
	shape.size = STANDING_HULL_SIZE
	shape_node.shape = shape
	shape_node.position.y = STANDING_HULL_CENTER_Y
	add_child(shape_node)
	_collision_shape = shape_node

	_fallback_visual = Node3D.new()
	_fallback_visual.name = "FallbackVisual"
	add_child(_fallback_visual)
	# Skin identity is gameplay/network state even when the dedicated export
	# omits its corresponding mesh and animation assets.
	player_skin = _skin_for_identity()
	if _is_dedicated_server():
		return
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _team_color()
	_body_material.roughness = 0.64
	_body_mesh = MeshInstance3D.new()
	_body_mesh.name = "Body"
	var body := CapsuleMesh.new()
	body.radius = 16.0 * GOLDSRC_UNIT
	body.height = 72.0 * GOLDSRC_UNIT
	body.material = _body_material
	_body_mesh.mesh = body
	_body_mesh.position.y = STANDING_HULL_CENTER_Y
	_fallback_visual.add_child(_body_mesh)

	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color("#151c24")
	visor_material.metallic = 0.65
	visor_material.roughness = 0.25
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.18, 0.07, 0.04)
	visor_mesh.material = visor_material
	visor.mesh = visor_mesh
	visor.position = Vector3(0, 0.61, -0.13)
	_fallback_visual.add_child(visor)

	character_model = CharacterModelScript.new()
	character_model.name = "PlayerModel"
	add_child(character_model)
	_fallback_visual.visible = not character_model.load_character(
		player_skin,
		active_weapon_name,
	)

	_muzzle = OmniLight3D.new()
	_muzzle.position = Vector3(0.10, 0.46, -0.23)
	_muzzle.light_color = Color("#ff685d")
	_muzzle.light_energy = 2.2
	_muzzle.omni_range = 1.2
	_muzzle.visible = false
	add_child(_muzzle)


func _physics_process(delta: float) -> void:
	if not active or not alive:
		velocity = Vector3.ZERO
		last_command = {}
		combat_state = "idle"
		_safe_navigation_velocity = Vector3.ZERO
		_navigation_velocity_ready = false
		if is_instance_valid(navigation_agent):
			navigation_agent.velocity = Vector3.ZERO
		if is_instance_valid(character_model):
			character_model.set_locomotion(false, false, is_on_floor())
		return
	var command := combat_controller.gather_command(delta)
	if objective_movement_locked:
		command.world_velocity = Vector3.ZERO
		command.fire = false
		command.reload = false
		command.throw_grenade = {}
		command.crouch = objective_crouch
		if objective_look_target != Vector3.INF:
			command.look_target = objective_look_target
	last_command = command
	combat_state = command.state
	var look_target: Vector3 = command.look_target
	if look_target != Vector3.INF:
		face_aim_target(look_target)
	var desired_velocity: Vector3 = command.world_velocity
	var movement_velocity := desired_velocity
	var planar_motion := Vector3(
		movement_velocity.x,
		0.0,
		movement_velocity.z,
	) * maxf(delta, 0.02)
	# Walking uphill, a purely horizontal probe collides with the walkable
	# ramp itself and every axis reads "blocked" — bots then stall at the
	# base of any climb (CT spawn ramps). Sweep along the floor plane so
	# only genuine walls register as obstructions.
	if is_on_floor():
		var floor_normal := get_floor_normal()
		if floor_normal.y >= FLOOR_NORMAL_MINIMUM:
			planar_motion = planar_motion - floor_normal * planar_motion.dot(floor_normal)
	var wanted_motion := Vector2(planar_motion.x, planar_motion.z).length()
	var climbed := false
	var blocked := test_move(global_transform, planar_motion, _movement_probe_result, 0.015)
	var brush_contact := blocked and _movement_probe_result.get_collider() is AnimatableBody3D
	if blocked:
		var x_motion := planar_motion
		x_motion.z = 0.0
		var z_motion := planar_motion
		z_motion.x = 0.0
		var x_clear := (
			absf(x_motion.x) > 0.000001
			and not test_move(global_transform, x_motion, null, 0.015)
		)
		var z_clear := (
			absf(z_motion.z) > 0.000001
			and not test_move(global_transform, z_motion, null, 0.015)
		)
		if x_clear and z_clear:
			# Two clear axis sweeps can recombine into a blocked convex-corner
			# diagonal. GoldSrc clips one contact plane at a time, so keep only
			# the dominant component for this tick.
			if absf(x_motion.x) >= absf(z_motion.z):
				movement_velocity.z = 0.0
			else:
				movement_velocity.x = 0.0
		else:
			movement_velocity.x = movement_velocity.x if x_clear else 0.0
			movement_velocity.z = movement_velocity.z if z_clear else 0.0
		# PM_WalkMove attempts the up-forward-down resolution whenever the flat
		# move is obstructed, not only when every axis is blocked. Gating the
		# climb on a fully zeroed slide left a bot that met a climbable lip at an
		# angle sliding along it forever, because one axis still read "clear".
		var slide_motion := Vector2(
			movement_velocity.x,
			movement_velocity.z,
		).length() * maxf(delta, 0.02)
		if (
			slide_motion <= wanted_motion * STEP_CLIMB_SLIDE_FRACTION
			and _try_step_climb(planar_motion)
		):
			# The stair step consumed this tick's planar motion by teleport,
			# exactly like PM_WalkMove's up-forward-down resolution.
			climbed = true
			movement_velocity.x = 0.0
			movement_velocity.z = 0.0
		elif brush_contact:
			# Lookahead clipping stops short of movable brushes and prevents
			# touch-operated doors from ever receiving contact. Let the actual
			# body solver reach/slide against them; never move through them.
			movement_velocity = desired_velocity
	velocity.x = movement_velocity.x
	velocity.z = movement_velocity.z
	_update_obstruction_clock(planar_motion, wanted_motion, blocked, climbed)
	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y -= PLAYER_GRAVITY * delta
		_fall_velocity_ups = maxf(
			_fall_velocity_ups,
			maxf(0.0, -velocity.y / GOLDSRC_UNIT),
		)
	else:
		velocity.y = -0.1
		if _should_jump_obstacle(planar_motion):
			velocity.y = JUMP_SPEED
			_next_jump_tick = _movement_tick + JUMP_COOLDOWN_TICKS
			_obstructed_ticks = 0
	move_and_slide()
	if is_on_floor():
		if not was_on_floor:
			_emit_landing_audio(_fall_velocity_ups)
		_fall_velocity_ups = 0.0
	_record_brush_contacts()
	_resolve_combatant_hull_overlap()
	_update_footstep_audio()
	if is_instance_valid(character_model):
		character_model.set_locomotion(
			Vector2(velocity.x, velocity.z).length() > 0.18,
			bool(command.crouch),
			is_on_floor(),
		)
	if command.has("c4_equipped"):
		set_c4_state(owns_c4, bool(command.c4_equipped))
	consume_combat_weapon_command(command)


func _record_brush_contacts() -> void:
	_brush_contacts.clear()
	BrushContactsScript.append_motion_contacts(self, _brush_contacts)


func take_brush_contacts() -> PackedInt32Array:
	# Consume actual movement contacts once. A collision solver can stop short
	# of mathematical AABB overlap; its reported contact still owns Touch.
	# Consuming also prevents old contacts persisting while an actor is frozen.
	var contacts := _brush_contacts
	_brush_contacts = PackedInt32Array()
	return contacts


func _damage_pool(target: Object, property: String) -> int:
	## Reads a health/armor pool from any damageable. Breakable brush proxies
	## implement receive_bullet_damage without these properties.
	if target == null:
		return 0
	var value: Variant = target.get(property)
	return int(value) if value != null else 0


const STEP_CLIMB_HEIGHT := 18.0 * GOLDSRC_UNIT


func _update_obstruction_clock(
	planar_motion: Vector3,
	wanted_motion: float,
	blocked: bool,
	climbed: bool,
) -> void:
	## Counts consecutive physics ticks on which the bot wanted to walk and the
	## world - not another player - refused the move. Everything here is driven
	## by the fixed 100 Hz physics tick, never by the render schedule.
	_movement_tick += 1
	if (
		not blocked
		or climbed
		or wanted_motion <= 0.000001
		or not _world_blocks_motion(planar_motion)
	):
		_obstructed_ticks = 0
		return
	_obstructed_ticks += 1


func _world_blocks_motion(planar_motion: Vector3) -> bool:
	## Reclassifies an obstruction as BSP-only. A standoff with another player is
	## resolved by the controller's unwedge, never by climbing or jumping.
	var previous_mask := collision_mask
	collision_mask = 1
	var world_blocked := test_move(global_transform, planar_motion, null, 0.015)
	collision_mask = previous_mask
	return world_blocked


func _should_jump_obstacle(planar_motion: Vector3) -> bool:
	if (
		_obstructed_ticks < JUMP_BLOCKED_TICKS
		or _movement_tick < _next_jump_tick
		or objective_movement_locked
	):
		return false
	return _jump_landing_available(planar_motion)


func _jump_landing_available(planar_motion: Vector3) -> bool:
	## True only for a ledge the bot genuinely cannot walk or step onto but can
	## land on: taller than the 18 HU step, under the jump apex, walkable on top,
	## and with the headroom to rise in the first place.
	if planar_motion.length_squared() <= 0.000001:
		return false
	var params := PhysicsTestMotionParameters3D.new()
	params.margin = 0.015
	var result := PhysicsTestMotionResult3D.new()
	params.from = global_transform
	params.motion = Vector3.UP * JUMP_PROBE_HEIGHT
	PhysicsServer3D.body_test_motion(get_rid(), params, result)
	var rise := result.get_travel().y
	if rise <= STEP_CLIMB_HEIGHT + 0.02:
		return false
	var apex := global_transform.translated(Vector3(0.0, rise, 0.0))
	# A jump carries the bot farther than one tick of walking; probe the reach
	# it actually has at the top of the arc.
	var reach := planar_motion.normalized() * maxf(planar_motion.length(), 0.35)
	params.from = apex
	params.motion = reach
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		if result.get_travel().length() < reach.length() * 0.9:
			return false
		apex = apex.translated(result.get_travel())
	else:
		apex = apex.translated(reach)
	params.from = apex
	params.motion = Vector3.DOWN * rise
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return false
	if result.get_collision_normal().y < FLOOR_NORMAL_MINIMUM:
		return false
	var landing_y := apex.origin.y + result.get_travel().y
	# Below the step height the walk resolution owns the move; a bot must never
	# hop up ordinary stairs.
	return landing_y > global_position.y + STEP_CLIMB_HEIGHT


func _try_step_climb(planar_motion: Vector3) -> bool:
	## move_and_slide has no stair handling; the human player climbs steps via
	## the GoldSrc kernel's up-forward-down walk resolution. Mirror it here so
	## bots can take dust2's stairs and ledges (up to 18 HU, like PM_WalkMove).
	if not is_on_floor() or planar_motion.length_squared() <= 0.000001:
		return false
	var params := PhysicsTestMotionParameters3D.new()
	params.margin = 0.015
	var result := PhysicsTestMotionResult3D.new()
	params.from = global_transform
	params.motion = Vector3.UP * STEP_CLIMB_HEIGHT
	PhysicsServer3D.body_test_motion(get_rid(), params, result)
	var up_travel := result.get_travel()
	if up_travel.y <= 0.005:
		return false
	var stepped := global_transform.translated(up_travel)
	params.from = stepped
	params.motion = planar_motion
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		# Now that a partially clipped slide also reaches this resolution, a
		# half-completed forward sweep is refused: landing inside the lip it just
		# entered would leave the hull embedded in BSP.
		if result.get_travel().length() < planar_motion.length() * 0.95:
			return false
		stepped = stepped.translated(result.get_travel())
	else:
		stepped = stepped.translated(planar_motion)
	params.from = stepped
	params.motion = Vector3.DOWN * (up_travel.y + 0.01)
	if not PhysicsServer3D.body_test_motion(get_rid(), params, result):
		return false
	if result.get_collision_normal().y < FLOOR_NORMAL_MINIMUM:
		return false
	var landed := stepped.translated(result.get_travel())
	if not _hull_is_clear_of_world(landed.origin):
		return false
	global_transform = landed
	return true


func _hull_is_clear_of_world(feet: Vector3) -> bool:
	## Final guard on a teleporting resolution: the 32x72x32 HU hull must not
	## overlap BSP at the destination. Framed exactly like the crowd gate's
	## audit, including its 2 HU support band, so a legal floor contact is not
	## mistaken for penetration.
	if not is_inside_tree() or get_world_3d() == null:
		return true
	var hull := BoxShape3D.new()
	hull.size = STANDING_HULL_SIZE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = hull
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.0
	query.exclude = [get_rid()]
	query.transform = Transform3D(
		Basis.IDENTITY,
		feet + Vector3.UP * (
			STANDING_HULL_SIZE.y * 0.5 + FLOOR_CATEGORIZE_DISTANCE + 0.001
		),
	)
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _resolve_combatant_hull_overlap() -> void:
	## GoldSrc player hulls are mutually solid: PM_PlayerTrace stops every move
	## DIST_EPSILON short of another player's hull, so hulls never interpenetrate.
	## Two CharacterBody3D boxes sweeping toward each other in the same physics
	## tick can both finish inside Godot's contact-recovery skin (safe_margin),
	## leaving a residual sub-half-HU overlap. Resolve it deterministically: the
	## later-processed body steps out along the shallower penetrated axis. The
	## step is swept against the world so separation never trades a combatant
	## overlap for BSP penetration.
	var hull_width := STANDING_HULL_SIZE.x
	var hull_height := STANDING_HULL_SIZE.y
	var epsilon := 0.05 * GOLDSRC_UNIT
	for node in get_tree().get_nodes_in_group("combatants"):
		var other := node as Combatant
		if other == null or other == self or not other.alive:
			continue
		if absf(other.global_position.y - global_position.y) >= hull_height:
			continue
		var dx := global_position.x - other.global_position.x
		var dz := global_position.z - other.global_position.z
		var x_overlap := hull_width - absf(dx)
		var z_overlap := hull_width - absf(dz)
		if x_overlap <= 0.0 or z_overlap <= 0.0:
			continue
		var push := Vector3.ZERO
		if x_overlap <= z_overlap:
			push.x = (x_overlap + epsilon) * (1.0 if dx >= 0.0 else -1.0)
		else:
			push.z = (z_overlap + epsilon) * (1.0 if dz >= 0.0 else -1.0)
		# Sweep against the BSP only (layer 1): the overlapping combatant would
		# otherwise block the separating step at fraction zero.
		var previous_mask := collision_mask
		collision_mask = 1
		move_and_collide(push, false, 0.0)
		collision_mask = previous_mask


func consume_combat_weapon_command(command: Dictionary) -> void:
	var command_aim_target: Vector3 = command.get("look_target", Vector3.INF)
	weapon_clip = int(command.get("weapon_clip", weapon_clip))
	weapon_reserve = int(command.get("weapon_reserve", weapon_reserve))
	weapon_reloading = bool(command.get("weapon_reloading", weapon_reloading))
	weapon_tick = int(command.get("weapon_tick", weapon_tick))
	if bool(command.reload):
		_ak_burst_shots = 0
		_rifle_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
		_pistol_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
		_last_fire_tick = -1
		_reload_audio_schedule.clear()
		var reload_ticks: Array = command.get("reload_ticks", [])
		var start_tick := int(reload_ticks[-1]) if not reload_ticks.is_empty() else weapon_tick
		for stage: Dictionary in AudioCatalogScript.RELOAD_AUDIO_STAGES.get(active_weapon_name, []):
			_reload_audio_schedule.append({"tick": start_tick + int(stage.offset), "event": stage.event})
		if active_weapon_name in ["m3", "xm1014"]:
			_emit_audio("shotgun.insert", AudioRouterScript.CHAN_WEAPON)
		publish_combat_presentation("reload", {"weapon": active_weapon_name})
		if is_instance_valid(character_model):
			character_model.play_action("reload")
	if not alive or bool(command.fire):
		_reload_audio_schedule.clear()
	while not _reload_audio_schedule.is_empty() and int(_reload_audio_schedule[0].tick) <= weapon_tick:
		var stage: Dictionary = _reload_audio_schedule.pop_front()
		_emit_audio(str(stage.event), AudioRouterScript.CHAN_WEAPON)

	var throw_request: Dictionary = command.get("throw_grenade", {})
	if not throw_request.is_empty() and not c4_equipped:
		throw_grenade(
			str(throw_request.get("kind", "")),
			throw_request.get("target", Vector3.INF),
		)

	var enemy := command.enemy as Combatant
	if command.fire and not c4_equipped and is_instance_valid(enemy):
		var fire_events: Array = command.get("fire_events", [])
		if fire_events.is_empty():
			fire_events = [{
				"tick": weapon_tick,
				"aim_target": command_aim_target,
				"clip_after": weapon_clip,
				"reserve_after": weapon_reserve,
			}]
		for fire_event: Dictionary in fire_events:
			weapon_clip = int(fire_event.get("clip_after", weapon_clip))
			weapon_reserve = int(fire_event.get("reserve_after", weapon_reserve))
			_try_fire(
				enemy,
				fire_event.get("aim_target", command_aim_target),
				int(fire_event.get("tick", weapon_tick)),
			)


func face_aim_target(world_target: Vector3) -> void:
	var delta := world_target - global_position
	var planar_distance := Vector2(delta.x, delta.z).length()
	if planar_distance <= 0.001:
		return
	spectator_view_pitch = atan2(delta.y, planar_distance)
	if is_instance_valid(character_model):
		character_model.set_aim_pitch(spectator_view_pitch)
	var yaw_target := world_target
	yaw_target.y = global_position.y
	look_at(yaw_target, Vector3.UP)
	# GoldSrc player hulls stay axis-aligned as view yaw changes. Counter-rotate
	# this child so aiming only rotates the actor's visuals, never its 32 HU hull.
	if is_instance_valid(_collision_shape):
		_collision_shape.rotation.y = -rotation.y


func is_crouching() -> bool:
	return objective_crouch or bool(last_command.get("crouch", false))


func _try_fire(
	enemy: Combatant,
	aim_target := Vector3.INF,
	fire_tick := -1,
) -> void:
	if not is_instance_valid(enemy) or not enemy.alive:
		return
	var origin := aim_point()
	if aim_target == Vector3.INF:
		# Compatibility for focused audio/VFX probes. Live combat always passes
		# the tactic event's sampled aim target through the command.
		aim_target = enemy.aim_point()
	if fire_tick < 0:
		fire_tick = weapon_tick
	if origin.distance_squared_to(aim_target) <= 0.000001:
		return
	if fire_tick - _last_fire_tick > 40 and BallisticsScript.AUTOMATIC_ACCURACY.has(active_weapon_name):
		_ak_burst_shots = maxi(0, mini(15, _ak_burst_shots) - ceili(float(fire_tick - _last_fire_tick - 40) / 3.0))
		if _ak_burst_shots == 0:
			_rifle_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
	if active_weapon_name == "g3sg1":
		_rifle_accuracy = BallisticsScript.sniper_accuracy(active_weapon_name,
			float(fire_tick - _last_fire_tick) / 100.0 if _last_fire_tick >= 0 else -1.0)
	var spread := BallisticsScript.weapon_spread(
		active_weapon_name, is_on_floor(), Vector2(velocity.x, velocity.z).length(),
		bool(last_command.get("crouch", false)), false,
		_rifle_accuracy, _pistol_accuracy,
	)
	if BallisticsScript.AUTOMATIC_ACCURACY.has(active_weapon_name):
		_ak_burst_shots += 1
		_rifle_accuracy = BallisticsScript.automatic_accuracy(active_weapon_name, _ak_burst_shots)
	elif active_weapon_name == "sg550":
		_rifle_accuracy = BallisticsScript.sniper_accuracy(active_weapon_name,
			float(fire_tick - _last_fire_tick) / 100.0 if _last_fire_tick >= 0 else -1.0)
	elif _last_fire_tick >= 0:
		_pistol_accuracy = BallisticsScript.pistol_accuracy(active_weapon_name,
			_pistol_accuracy, float(fire_tick - _last_fire_tick) / 100.0)
	_last_fire_tick = fire_tick
	var forward := origin.direction_to(aim_target)
	if forward.is_zero_approx():
		forward = -global_basis.z
	var right := forward.cross(Vector3.UP).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up := right.cross(forward).normalized()
	var effect_sequence := _effect_shot_sequence
	var direction := BallisticsScript.spread_direction(
		forward,
		right,
		up,
		effect_sequence,
		spread,
	)
	_effect_shot_sequence = (_effect_shot_sequence + 1) & 0xff
	publish_combat_presentation("shot", {"weapon": active_weapon_name, "sequence": effect_sequence,
		"origin": origin, "direction": direction, "right": right, "up": up, "punch": Vector2.ZERO})
	_emit_audio("%s.fire" % active_weapon_name, AudioRouterScript.CHAN_WEAPON)
	if is_instance_valid(combat_effects):
		combat_effects.spawn_weapon_shot(
			active_weapon_name,
			effect_sequence,
			origin,
			direction,
			right,
			up,
		)
	if is_instance_valid(character_model):
		character_model.play_action("shoot")
	var pellet_count := int(WeaponRegistryScript.definition(active_weapon_name).get("pellets", 1))
	var result: Dictionary = {}
	var health_damage := 0
	var armor_damage := 0
	for pellet_index in range(pellet_count):
		var pellet_direction := direction
		if pellet_count > 1:
			pellet_direction = BallisticsScript.spread_direction(
				forward, right, up, (effect_sequence * 16 + pellet_index) & 0xff, spread,
			)
		var pellet_result := _fire_cs_bullet(origin, pellet_direction, effect_sequence)
		health_damage += int(pellet_result.health_damage)
		armor_damage += int(pellet_result.armor_damage)
		# Keep the first successful pellet's hit details and total shell damage.
		if result.is_empty() or not bool(result.hit):
			result = pellet_result
	shot_trace.append({
		"tick": fire_tick,
		"sequence": effect_sequence,
		"clip_after": weapon_clip,
		"reserve_after": weapon_reserve,
		"aim_target": aim_target,
		"direction": direction,
		"spread": spread,
		"pellet_count": pellet_count,
		"hit": bool(result.hit),
		"hit_actor": str(result.hit_actor),
		"hit_group": int(result.hit_group),
		"health_damage": health_damage,
		"armor_damage": armor_damage,
		"trace_end": result.trace_end,
	})
	fired.emit()


func _fire_cs_bullet(
	origin: Vector3,
	direction: Vector3,
	effect_sequence: int,
) -> Dictionary:
	var profile := BallisticsScript.weapon_profile(active_weapon_name)
	var remaining_distance := float(profile.range_meters)
	var current_damage := int(profile.base_damage)
	var penetrations := maxi(int(profile.penetrations), 1)
	var penetration_power := -1
	var damage_modifier := 0.5
	var trace_origin := origin
	var trace_end := origin + direction * remaining_distance
	var exclusions: Array[RID] = [get_rid()]
	var result := {
		"hit": false,
		"hit_actor": "",
		"hit_group": BallisticsScript.HitGroup.GENERIC,
		"health_damage": 0,
		"armor_damage": 0,
		"trace_end": trace_end,
	}
	while penetrations > 0 and remaining_distance > 0.0 and current_damage > 0:
		var end := trace_origin + direction * remaining_distance
		var query := PhysicsRayQueryParameters3D.create(
			trace_origin,
			end,
			1 | 2 | 4 | 16,
			exclusions,
		)
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			trace_end = end
			break

		trace_end = hit.position
		var hit_collider: Object = hit.collider
		var traveled := trace_origin.distance_to(hit.position)
		var damageable := (
			hit_collider != null
			and hit_collider.has_method("receive_bullet_damage")
		)
		var surface_type := BallisticsScript.SURFACE_DEFAULT if damageable else BallisticsScript.surface_for_hit(hit)
		var step := BallisticsScript.penetration_step(
			current_damage,
			float(profile.range_modifier),
			traveled,
			str(profile.bullet_type),
			surface_type,
			not damageable,
			penetrations,
			penetration_power,
			damage_modifier,
		)
		if damageable:
			var hit_group := _hit_group_for_impact(hit_collider, hit.position)
			# Not every damageable is a Combatant: func_breakable proxies accept
			# receive_bullet_damage without carrying health/armor properties, and
			# int(null) is a hard error. Treat a missing pool as zero.
			var health_before := _damage_pool(hit_collider, "health")
			var armor_before := _damage_pool(hit_collider, "armor")
			hit_collider.call(
				"receive_bullet_damage",
				int(step.damage_at_hit),
				hit_group,
				active_weapon_name,
				hit.position,
				self,
			)
			result.hit = true
			result.hit_actor = str((hit_collider as Node).name)
			result.hit_group = hit_group
			result.health_damage = maxi(
				0,
				health_before - _damage_pool(hit_collider, "health"),
			)
			result.armor_damage = maxi(
				0,
				armor_before - _damage_pool(hit_collider, "armor"),
			)
			if is_instance_valid(combat_effects) and (hit_collider is Combatant or hit_collider is CS16Hostage):
				combat_effects.spawn_blood_impact(
					hit.position,
					direction,
					effect_sequence,
				)
				var blood_exclusions: Array[RID] = [get_rid()]
				if hit_collider is CollisionObject3D:
					blood_exclusions.append(
						(hit_collider as CollisionObject3D).get_rid(),
					)
				var blood_query := PhysicsRayQueryParameters3D.create(
					hit.position + direction * 0.03,
					hit.position + direction * 2.0,
					1,
					blood_exclusions,
				)
				var blood_surface := (
					get_world_3d().direct_space_state.intersect_ray(blood_query)
				)
				if not blood_surface.is_empty():
					combat_effects.spawn_blood_decal(
						blood_surface.position,
						blood_surface.normal,
						effect_sequence,
					)
		elif is_instance_valid(combat_effects):
			combat_effects.spawn_world_impact(
				hit.position,
				hit.normal,
				effect_sequence,
				surface_type,
			)
		if not bool(step.can_continue):
			break
		if damageable and hit_collider is CollisionObject3D:
			exclusions.append((hit_collider as CollisionObject3D).get_rid())
		remaining_distance = maxf(
			0.0,
			(remaining_distance - traveled) * float(step.remaining_distance_scale),
		)
		current_damage = int(step.next_damage)
		penetrations = int(step.penetrations_remaining)
		penetration_power = int(step.penetration_power_units)
		damage_modifier = float(step.damage_modifier)
		trace_origin = (
			hit.position
			+ direction * float(step.penetration_power_meters)
		)
	result.trace_end = trace_end
	return result


func _hit_group_for_impact(hit_collider: Object, hit_position: Vector3) -> int:
	if hit_collider is Combatant:
		return hit_collider.hit_group_at(hit_position)
	if (
		not hit_collider is Node3D
		or not hit_collider.has_method("head_height")
	):
		return BallisticsScript.HitGroup.GENERIC
	var victim := hit_collider as Node3D
	var relative_hu := (
		(hit_position - victim.global_position) / Combatant.GOLDSRC_UNIT
	)
	if hit_position.y >= float(hit_collider.call("head_height")):
		return BallisticsScript.HitGroup.HEAD
	if relative_hu.y < 30.0:
		return (
			BallisticsScript.HitGroup.LEFT_LEG
			if relative_hu.x < 0.0
			else BallisticsScript.HitGroup.RIGHT_LEG
		)
	if relative_hu.y < 42.0:
		return BallisticsScript.HitGroup.STOMACH
	if absf(relative_hu.x) >= 11.0:
		return (
			BallisticsScript.HitGroup.LEFT_ARM
			if relative_hu.x < 0.0
			else BallisticsScript.HitGroup.RIGHT_ARM
		)
	return BallisticsScript.HitGroup.CHEST


func apply_damage(
	amount: float,
	hit_position: Vector3,
	headshot: bool,
	attacker: Combatant = null,
) -> void:
	receive_damage(amount, hit_position, headshot, attacker)


func _on_combatant_damaged(
	attacker: Combatant,
	hit_position: Vector3,
	headshot: bool,
) -> void:
	_emit_audio(last_damage_impact_audio, AudioRouterScript.CHAN_VOICE)
	# A hit is the bot's only cue about an enemy behind it: the controller turns
	# it toward the source instead of discarding the attacker.
	if (
		alive
		and is_instance_valid(attacker)
		and is_opponent(attacker)
		and combat_controller is BotCombatController
	):
		(combat_controller as BotCombatController).notice_damage(
			attacker,
			hit_position,
		)
	damaged.emit(self, health, headshot)


func _on_combatant_eliminated(_attacker: Combatant, headshot: bool) -> void:
	active = false
	collision_layer = 0
	_emit_audio(
		"player.headshot_death" if headshot else "player.death",
		AudioRouterScript.CHAN_VOICE,
	)
	if is_instance_valid(character_model):
		character_model.play_death()
	died.emit(self, headshot)


func reset_target(spawn_position: Vector3) -> void:
	flash_blind_until_frame = -1
	flash_blind_total_seconds = 0.0
	reset_combatant(spawn_position)
	active = true
	collision_layer = 2
	_anchor = spawn_position
	rotation = Vector3.ZERO
	if is_instance_valid(_collision_shape):
		_collision_shape.rotation = Vector3.ZERO
	combat_state = "idle"
	if is_instance_valid(navigation_agent):
		navigation_agent.avoidance_enabled = false
		navigation_agent.target_position = spawn_position
		navigation_agent.velocity = Vector3.ZERO
	_safe_navigation_velocity = Vector3.ZERO
	_navigation_velocity_ready = false
	_effect_shot_sequence = 0
	_ak_burst_shots = 0
	_rifle_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
	_pistol_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
	_last_fire_tick = -1000
	_movement_tick = 0
	_obstructed_ticks = 0
	_next_jump_tick = 0
	_brush_contacts.clear()
	var weapon_definition := WeaponRegistryScript.definition(active_weapon_name)
	weapon_clip = int(
		weapon_definition.get("magazine", BotTacticsScript.AK_CLIP_SIZE)
	)
	weapon_reserve = int(
		weapon_definition.get("reserve", BotTacticsScript.AK_RESERVE_SIZE)
	)
	weapon_reloading = false
	weapon_tick = 0
	_reload_audio_schedule.clear()
	shot_trace.clear()
	grenade_trace.clear()
	# Utility does not survive a round; CS16BotBuyPlan re-buys it after this
	# reset, exactly like the primary and armor.
	grenade_counts.clear()
	set_objective_lock(false)
	set_c4_state(false, false)
	_next_footstep_tick = audio_router.current_tick if is_instance_valid(audio_router) else 0
	_left_foot = false
	_footstep_serial = 0
	_fall_velocity_ups = 0.0
	if is_instance_valid(combat_controller):
		(combat_controller as BotCombatController).reset_tactics()
	if is_instance_valid(character_model):
		character_model.reset_animation()
	if is_instance_valid(_body_material):
		_body_material.albedo_color = _team_color()


func configure_weapon(weapon_name: String, update_presentation := true) -> bool:
	var definition := WeaponRegistryScript.definition(weapon_name)
	if definition.is_empty() or str(definition.category) in ["melee", "objective"]:
		return false
	if str(definition.category) == "grenade":
		# The round buy applier grants every purchased item through this one
		# entry point. A grenade joins the utility inventory; it must not
		# replace the primary the bot just bought.
		return grant_grenade(str(definition.weapon))
	active_weapon_name = str(definition.weapon)
	_reload_audio_schedule.clear()
	_ak_burst_shots = 0
	_rifle_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
	_pistol_accuracy = BallisticsScript.base_accuracy(active_weapon_name)
	_last_fire_tick = -1000
	if is_instance_valid(combat_controller):
		(combat_controller as BotCombatController).configure_weapon(
			active_weapon_name,
		)
	weapon_clip = int(definition.magazine)
	weapon_reserve = int(definition.reserve)
	weapon_reloading = false
	if is_instance_valid(navigation_agent):
		navigation_agent.max_speed = float(definition.max_speed) * GOLDSRC_UNIT
	if update_presentation:
		refresh_weapon_presentation()
	# Reconfiguring the gun re-seeds the tactic clock, which clears its utility
	# mirror; the actor inventory stays authoritative.
	_sync_tactics_grenades()
	return true


func refresh_weapon_presentation() -> void:
	# Round buying applies several inventory operations synchronously. Only its
	# final carried gun needs a model; all weapon/ammo/tactic updates still run.
	if is_instance_valid(character_model) and not c4_equipped:
		_replace_character_weapon(active_weapon_name)


func grant_grenade(kind: String, count := 1) -> bool:
	var definition := WeaponRegistryScript.definition(kind)
	if definition.is_empty() or str(definition.category) != "grenade":
		return false
	var equipment: Dictionary = WeaponRegistryScript.EQUIPMENT.get(kind, {})
	var carry_max := int(equipment.get("carry_max", 1))
	var held := int(grenade_counts.get(kind, 0))
	if held >= carry_max:
		return false
	grenade_counts[kind] = mini(carry_max, held + maxi(1, count))
	_sync_tactics_grenades()
	return true


func grenade_count(kind: String) -> int:
	return int(grenade_counts.get(kind, 0))


func _sync_tactics_grenades() -> void:
	if combat_controller is BotCombatController:
		var tactics: RefCounted = (combat_controller as BotCombatController).tactics
		if is_instance_valid(tactics):
			tactics.set_grenade_inventory(grenade_counts)


func throw_grenade(kind: String, target_position: Vector3) -> bool:
	if not alive or not is_inside_tree() or grenade_count(kind) <= 0:
		return false
	if not target_position.is_finite():
		return false
	var eye := aim_point()
	var to_target := target_position - eye
	var horizontal := Vector2(to_target.x, to_target.z).length()
	if horizontal <= 0.05:
		return false
	# GoldSrc throw angles: yaw runs counter-clockwise from +X, and the pitch
	# this project feeds Ballistics is the inverted GoldSrc one.
	var yaw_degrees := rad_to_deg(atan2(-to_target.z, to_target.x))
	var elevation := _throw_elevation_degrees(horizontal, to_target.y)
	var view_pitch := _view_pitch_for_elevation(elevation)
	var grenade: HEGrenade = GrenadeScript.new()
	get_tree().current_scene.add_child(grenade)
	grenade.launch(
		BallisticsScript.he_throw_origin(eye, view_pitch, yaw_degrees),
		BallisticsScript.he_throw_velocity(view_pitch, yaw_degrees),
		self,
		kind,
	)
	grenade_counts[kind] = grenade_count(kind) - 1
	if grenade_count(kind) <= 0:
		grenade_counts.erase(kind)
	_sync_tactics_grenades()
	grenade_trace.append({
		"tick": weapon_tick,
		"kind": kind,
		"target": target_position,
		"elevation": elevation,
	})
	if is_instance_valid(character_model):
		character_model.play_action("throw")
	publish_combat_presentation("grenade_action", {"weapon": kind, "action": "throw"})
	return true


func _view_pitch_for_elevation(elevation_degrees: float) -> float:
	## Inverse of Ballistics.remap_he_throw_pitch for a wanted launch elevation.
	var remapped := -elevation_degrees
	if remapped < -10.0:
		return (remapped + 10.0) * (90.0 / 80.0)
	return (remapped + 10.0) * (90.0 / 100.0)


func _throw_elevation_degrees(
	horizontal_distance: float,
	height_delta: float,
) -> float:
	## Pick the flattest launch elevation whose ballistic range lands closest to
	## the requested spot. Pure arithmetic on the fixed throw table, so the same
	## request always produces the same arc.
	var gravity := BallisticsScript.HE_GRAVITY_METERS_PER_SECOND_SQUARED
	var best_elevation := 25.0
	var best_error := INF
	for step in range(14):
		var elevation := 12.0 + float(step) * 2.5
		var speed := BallisticsScript.he_throw_speed_meters(
			_view_pitch_for_elevation(elevation),
		)
		var vertical := speed * sin(deg_to_rad(elevation))
		var discriminant := vertical * vertical - 2.0 * gravity * height_delta
		if discriminant < 0.0:
			continue
		var flight := (vertical + sqrt(discriminant)) / gravity
		var reach := speed * cos(deg_to_rad(elevation)) * flight
		var error := absf(reach - horizontal_distance)
		if error < best_error:
			best_error = error
			best_elevation = elevation
	return best_elevation


func set_c4_state(owned: bool, equipped: bool) -> void:
	owns_c4 = owned
	var next_equipped := owned and equipped
	if c4_equipped == next_equipped:
		return
	c4_equipped = next_equipped
	c4_deploy_ready_tick = weapon_tick + 75 if c4_equipped else -1
	if is_instance_valid(navigation_agent):
		navigation_agent.max_speed = (
			250.0 * GOLDSRC_UNIT
			if c4_equipped
			else float(
				WeaponRegistryScript.definition(active_weapon_name).get(
					"max_speed",
					221.0,
				)
			) * GOLDSRC_UNIT
		)
	if is_instance_valid(character_model):
		_replace_character_weapon("c4" if c4_equipped else active_weapon_name)
		if c4_equipped:
			character_model.set_locomotion(false, true, is_on_floor())
			character_model.play_action("shoot")


func c4_ready_for_plant() -> bool:
	return c4_equipped and c4_deploy_ready_tick >= 0 and weapon_tick >= c4_deploy_ready_tick


func _replace_character_weapon(weapon_name: String) -> void:
	if _is_dedicated_server():
		return
	if (is_instance_valid(character_model) and character_model.model_loaded
		and character_model.skin_name == player_skin and character_model.weapon_name == weapon_name):
		# Re-equipping the same gun resets the presentation state, but does not
		# need another body, attached mesh, material set, or scene-tree teardown.
		character_model.reset_animation()
		return
	if is_instance_valid(character_model):
		remove_child(character_model)
		character_model.queue_free()
	character_model = CharacterModelScript.new()
	character_model.name = "PlayerModel"
	add_child(character_model)
	_fallback_visual.visible = not character_model.load_character(
		player_skin,
		weapon_name,
	)


func set_objective_lock(
	locked: bool,
	crouched := false,
	look_target := Vector3.INF,
) -> void:
	objective_movement_locked = locked
	objective_crouch = locked and crouched
	objective_look_target = look_target if locked else Vector3.INF
	if locked:
		velocity.x = 0.0
		velocity.z = 0.0


func _team_color() -> Color:
	return (
		Color("#d85b3f")
		if team == TEAM_TERRORIST
		else Color("#416f9d")
	)


func _skin_for_identity() -> String:
	return skin_for_team(team, index)


static func skin_for_team(actor_team: String, bot_index: int) -> String:
	var skins := (
		TERRORIST_SKINS
		if actor_team == TEAM_TERRORIST
		else COUNTER_TERRORIST_SKINS
	)
	return skins[bot_index % skins.size()]


func audio_entity_id() -> int:
	return (100 if team == TEAM_TERRORIST else 200) + index


func _emit_audio(
	event_name: String,
	channel: int,
	overrides := {},
) -> int:
	if not is_instance_valid(audio_router):
		audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	if not is_instance_valid(audio_router):
		return -1
	return audio_router.emit_catalog_event(
		event_name,
		audio_entity_id(),
		channel,
		AudioRouterScript.meters_to_hu(global_position),
		overrides,
	)


func _emit_audio_descriptor(event_name: String, descriptor: Dictionary) -> int:
	if not is_instance_valid(audio_router):
		audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	if not is_instance_valid(audio_router):
		return -1
	return audio_router.emit_descriptor(
		event_name,
		audio_entity_id(),
		descriptor,
		AudioRouterScript.meters_to_hu(global_position),
	)


func _update_footstep_audio() -> void:
	if not is_instance_valid(audio_router):
		return
	if audio_router.current_tick < _next_footstep_tick:
		return
	_next_footstep_tick = audio_router.current_tick + FOOTSTEP_INTERVAL_TICKS
	if (
		not is_on_floor()
		or Vector2(velocity.x, velocity.z).length() <= FOOTSTEP_MINIMUM_SPEED
	):
		return
	var texture_name := _ground_texture_name()
	var descriptor := AudioCatalogScript.footstep_descriptor(
		texture_name,
		_left_foot,
		AudioCatalogScript.footstep_volume(texture_name),
	)
	if AudioCatalogScript.material_code(texture_name) == AudioCatalogScript.TILE:
		if _footstep_serial % 5 == 0:
			descriptor.variant_index = 2
		else:
			(descriptor.samples as Array).resize(2)
	_emit_audio_descriptor(
		"player.step.%s" % AudioCatalogScript.material_code(texture_name),
		descriptor,
	)
	_left_foot = not _left_foot
	_footstep_serial += 1


func _emit_landing_audio(fall_speed_ups: float) -> void:
	if fall_speed_ups < LANDING_MINIMUM_SPEED_UPS:
		return
	var texture_name := _ground_texture_name()
	var descriptor := AudioCatalogScript.footstep_descriptor(
		texture_name,
		_left_foot,
		1.0 if fall_speed_ups > LANDING_FULL_VOLUME_SPEED_UPS else 0.85,
	)
	_emit_audio_descriptor(
		"player.step.%s" % AudioCatalogScript.material_code(texture_name),
		descriptor,
	)
	_left_foot = not _left_foot
	_footstep_serial += 1
	_next_footstep_tick = audio_router.current_tick + FOOTSTEP_INTERVAL_TICKS


func _ground_texture_name() -> String:
	if not is_inside_tree() or get_world_3d() == null:
		return ""
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.08,
		global_position - Vector3.UP * 0.28,
		1,
		[get_rid()],
	)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var face_index := int(hit.get("face_index", -1))
	var node := hit.collider as Node
	while is_instance_valid(node):
		if node.has_method("texture_name_for_face"):
			return str(node.call("texture_name_for_face", face_index))
		node = node.get_parent()
	return str((hit.collider as Node).name) if hit.collider is Node else ""
