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
const TERRORIST_SKINS := ["terror", "leet", "arctic", "guerilla"]
const COUNTER_TERRORIST_SKINS := ["urban", "gsg9", "sas", "gign"]
const STANDING_HULL_SIZE := Vector3(32, 72, 32) * GOLDSRC_UNIT
const STANDING_HULL_CENTER_Y := 36.0 * GOLDSRC_UNIT
const PLAYER_GRAVITY := 800.0 * GOLDSRC_UNIT
const AK47_MAX_SPEED := 221.0 * GOLDSRC_UNIT
const FLOOR_NORMAL_MINIMUM := 0.7
const FLOOR_CATEGORIZE_DISTANCE := 2.0 * GOLDSRC_UNIT
const FOOTSTEP_MINIMUM_SPEED := 220.0 * GOLDSRC_UNIT
const FOOTSTEP_INTERVAL_TICKS := 30

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
var shot_trace: Array[Dictionary] = []

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
var _last_fire_tick := -1000
var _next_footstep_tick := 0
var _left_foot := false
var _footstep_serial := 0
var combat_effects: CS16CombatEffects
var audio_router: CS16AudioEventRouter


func _ready() -> void:
	if team == TEAM_UNASSIGNED:
		configure_identity(TEAM_COUNTER_TERRORIST, "CT Bot %02d" % (index + 1))
	super._ready()
	add_to_group("bots")
	add_to_group("targets")
	collision_layer = 2
	# GoldSrc player hulls are solid to the BSP and to every live player. RVO is
	# still used to choose smooth velocities, while the physical mask provides
	# the authoritative no-overlap backstop for bots, allies, and the player.
	collision_mask = 1 | 2 | 4
	floor_max_angle = acos(FLOOR_NORMAL_MINIMUM)
	floor_snap_length = FLOOR_CATEGORIZE_DISTANCE
	floor_stop_on_slope = true
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
	navigation_agent.avoidance_enabled = true
	navigation_agent.velocity_computed.connect(_on_safe_velocity_computed)
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

	player_skin = _skin_for_identity()
	character_model = CharacterModelScript.new()
	character_model.name = "PlayerModel"
	add_child(character_model)
	_fallback_visual.visible = not character_model.load_character(player_skin, "ak47")

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
	last_command = command
	combat_state = command.state
	var look_target: Vector3 = command.look_target
	if look_target != Vector3.INF:
		face_aim_target(look_target)
	var desired_velocity: Vector3 = command.world_velocity
	navigation_agent.velocity = desired_velocity
	var movement_velocity := (
		_safe_navigation_velocity
		if _navigation_velocity_ready
		else desired_velocity
	)
	# RVO may rotate the controller's already-validated strafe velocity toward
	# a wall. Validate the final avoidance output against the physical GoldSrc
	# hull as well, otherwise a distant engagement can wedge a bot a fraction
	# of a unit into BSP.
	var planar_motion := Vector3(
		movement_velocity.x,
		0.0,
		movement_velocity.z,
	) * maxf(delta, 0.12)
	if test_move(global_transform, planar_motion, null, 0.015):
		movement_velocity = Vector3.ZERO
	velocity.x = movement_velocity.x
	velocity.z = movement_velocity.z
	if not is_on_floor():
		velocity.y -= PLAYER_GRAVITY * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	_update_footstep_audio()
	if is_instance_valid(character_model):
		character_model.set_locomotion(
			Vector2(velocity.x, velocity.z).length() > 0.18,
			bool(command.crouch),
			is_on_floor(),
		)
	consume_combat_weapon_command(command)


func consume_combat_weapon_command(command: Dictionary) -> void:
	var command_aim_target: Vector3 = command.get("look_target", Vector3.INF)
	var was_reloading := weapon_reloading
	weapon_clip = int(command.get("weapon_clip", weapon_clip))
	weapon_reserve = int(command.get("weapon_reserve", weapon_reserve))
	weapon_reloading = bool(command.get("weapon_reloading", weapon_reloading))
	weapon_tick = int(command.get("weapon_tick", weapon_tick))
	if bool(command.reload):
		if is_instance_valid(character_model):
			character_model.play_action("reload")
		_emit_audio("ak47.clip_out", AudioRouterScript.CHAN_ITEM)
	elif was_reloading and not weapon_reloading:
		_emit_audio("ak47.clip_in", AudioRouterScript.CHAN_ITEM)

	var enemy := command.enemy as Combatant
	if command.fire and is_instance_valid(enemy):
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
	if is_instance_valid(character_model):
		character_model.set_aim_pitch(atan2(delta.y, planar_distance))
	var yaw_target := world_target
	yaw_target.y = global_position.y
	look_at(yaw_target, Vector3.UP)
	# GoldSrc player hulls stay axis-aligned as view yaw changes. Counter-rotate
	# this child so aiming only rotates the actor's visuals, never its 32 HU hull.
	if is_instance_valid(_collision_shape):
		_collision_shape.rotation.y = -rotation.y


func _on_safe_velocity_computed(safe_velocity: Vector3) -> void:
	if active and alive:
		_safe_navigation_velocity = safe_velocity
		_navigation_velocity_ready = true
	else:
		_safe_navigation_velocity = Vector3.ZERO
		_navigation_velocity_ready = false


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
	if fire_tick - _last_fire_tick > 40:
		_ak_burst_shots = 0
	_ak_burst_shots += 1
	_last_fire_tick = fire_tick
	var accuracy := minf(
		1.25,
		float(_ak_burst_shots * _ak_burst_shots * _ak_burst_shots) / 200.0 + 0.35,
	)
	var spread := 0.0275 * accuracy
	var forward := origin.direction_to(aim_target)
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
	_emit_audio("ak47.fire", AudioRouterScript.CHAN_WEAPON)
	if is_instance_valid(combat_effects):
		combat_effects.spawn_weapon_shot(
			"ak47",
			effect_sequence,
			origin,
			direction,
			right,
			up,
		)
	if is_instance_valid(character_model):
		character_model.play_action("shoot")
	var result := _fire_cs_bullet(origin, direction, effect_sequence)
	shot_trace.append({
		"tick": fire_tick,
		"sequence": effect_sequence,
		"clip_after": weapon_clip,
		"reserve_after": weapon_reserve,
		"aim_target": aim_target,
		"direction": direction,
		"spread": spread,
		"hit": bool(result.hit),
		"hit_actor": str(result.hit_actor),
		"hit_group": int(result.hit_group),
		"health_damage": int(result.health_damage),
		"armor_damage": int(result.armor_damage),
		"trace_end": result.trace_end,
	})
	fired.emit()


func _fire_cs_bullet(
	origin: Vector3,
	direction: Vector3,
	effect_sequence: int,
) -> Dictionary:
	var profile := BallisticsScript.weapon_profile("ak47")
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
			1 | 2 | 4,
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
		var step := BallisticsScript.penetration_step(
			current_damage,
			float(profile.range_modifier),
			traveled,
			str(profile.bullet_type),
			BallisticsScript.SURFACE_DEFAULT
			if damageable
			else BallisticsScript.SURFACE_CONCRETE,
			not damageable,
			penetrations,
			penetration_power,
			damage_modifier,
		)
		if damageable:
			var hit_group := _hit_group_for_impact(hit_collider, hit.position)
			var health_before := int(hit_collider.get("health"))
			var armor_before := int(hit_collider.get("armor"))
			hit_collider.call(
				"receive_bullet_damage",
				int(step.damage_at_hit),
				hit_group,
				"ak47",
				hit.position,
				self,
			)
			result.hit = true
			result.hit_actor = str((hit_collider as Node).name)
			result.hit_group = hit_group
			result.health_damage = maxi(
				0,
				health_before - int(hit_collider.get("health")),
			)
			result.armor_damage = maxi(
				0,
				armor_before - int(hit_collider.get("armor")),
			)
			if is_instance_valid(combat_effects):
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
	if not hit_collider is Combatant:
		return BallisticsScript.HitGroup.GENERIC
	var victim := hit_collider as Combatant
	var relative_hu := (
		(hit_position - victim.global_position) / Combatant.GOLDSRC_UNIT
	)
	if hit_position.y >= victim.head_height():
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
	_attacker: Combatant,
	_hit_position: Vector3,
	headshot: bool,
) -> void:
	_emit_audio("player.pain", AudioRouterScript.CHAN_VOICE)
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
	reset_combatant(spawn_position)
	active = true
	collision_layer = 2
	_anchor = spawn_position
	rotation = Vector3.ZERO
	if is_instance_valid(_collision_shape):
		_collision_shape.rotation = Vector3.ZERO
	combat_state = "idle"
	if is_instance_valid(navigation_agent):
		navigation_agent.target_position = spawn_position
		navigation_agent.velocity = Vector3.ZERO
	_safe_navigation_velocity = Vector3.ZERO
	_navigation_velocity_ready = false
	_effect_shot_sequence = 0
	_ak_burst_shots = 0
	_last_fire_tick = -1000
	weapon_clip = BotTacticsScript.AK_CLIP_SIZE
	weapon_reserve = BotTacticsScript.AK_RESERVE_SIZE
	weapon_reloading = false
	weapon_tick = 0
	shot_trace.clear()
	_next_footstep_tick = audio_router.current_tick if is_instance_valid(audio_router) else 0
	_left_foot = false
	_footstep_serial = 0
	if is_instance_valid(combat_controller):
		(combat_controller as BotCombatController).reset_tactics()
	if is_instance_valid(character_model):
		character_model.reset_animation()
	if is_instance_valid(_body_material):
		_body_material.albedo_color = _team_color()


func _team_color() -> Color:
	return (
		Color("#d85b3f")
		if team == TEAM_TERRORIST
		else Color("#416f9d")
	)


func _skin_for_identity() -> String:
	var skins := (
		TERRORIST_SKINS
		if team == TEAM_TERRORIST
		else COUNTER_TERRORIST_SKINS
	)
	return skins[index % skins.size()]


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
