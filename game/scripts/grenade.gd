class_name HEGrenade
extends RigidBody3D

const Ballistics := preload("res://scripts/cs16_ballistics.gd")
const WeaponClock := preload("res://scripts/cs16_weapon_clock.gd")
const CombatEffectsScript := preload("res://scripts/cs16_combat_effects.gd")
const AudioRouterScript := preload("res://scripts/cs16_audio_event_router.gd")
const FUSE_SECONDS := Ballistics.HE_FUSE_SECONDS
# ShootTimed2's 1.5-second fuse at the authoritative 100 Hz clock.
const FUSE_TICKS := 150
const BLAST_RADIUS := Ballistics.HE_RADIUS_METERS
const MAX_DAMAGE := Ballistics.HE_BASE_DAMAGE
const CLEANUP_TICKS := 150

var _exploded := false
var thrower: Combatant
var _ground_slowdown_armed := true
var _simulation_tick := 0
var _cleanup_tick := WeaponClock.NEVER
var _last_surface_normal := Vector3.UP
var audio_router: CS16AudioEventRouter
var grenade_kind := "hegrenade"


func _ready() -> void:
	name = "HEGrenade"
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	linear_damp = 0.0
	angular_damp = 0.0
	var world_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	gravity_scale = Ballistics.HE_GRAVITY_METERS_PER_SECOND_SQUARED / world_gravity
	var physics_material := PhysicsMaterial.new()
	# GoldSrc uses pev->friction as inverse elasticity, not as tangential
	# friction. Godot's equivalent bounce is therefore 1 - 0.7.
	physics_material.friction = 0.0
	physics_material.bounce = 1.0 - Ballistics.HE_FRICTION
	physics_material_override = physics_material

	var collider := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	# GoldSrc gives grenades a point-sized bbox. One converted unit is the
	# smallest robust Godot approximation.
	shape.radius = Ballistics.METERS_PER_GOLDSRC_UNIT
	collider.shape = shape
	add_child(collider)
	var model := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.085
	mesh.height = 0.17
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#26352d")
	material.metallic = 0.28
	mesh.material = material
	model.mesh = mesh
	add_child(model)
	audio_router = AudioRouterScript.for_scene(get_tree().current_scene)
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	_simulation_tick += 1
	if not _exploded and _simulation_tick >= FUSE_TICKS:
		explode()
	elif _exploded and _cleanup_tick != WeaponClock.NEVER and _simulation_tick >= _cleanup_tick:
		queue_free()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var grounded := false
	for contact_index in range(state.get_contact_count()):
		if state.get_contact_local_normal(contact_index).y > 0.7:
			grounded = true
			_last_surface_normal = state.get_contact_local_normal(contact_index).normalized()
			break
	if grounded and _ground_slowdown_armed:
		if Ballistics.he_should_stop_after_ground_bounce(linear_velocity, Vector3.UP):
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
		else:
			linear_velocity *= Ballistics.HE_GROUND_VELOCITY_RETENTION
		_ground_slowdown_armed = false
	elif not grounded:
		_ground_slowdown_armed = true


func launch(
	origin: Vector3,
	impulse: Vector3,
	thrower_combatant: Combatant = null,
	kind := "hegrenade",
) -> void:
	thrower = thrower_combatant
	grenade_kind = kind
	name = "HEGrenade" if kind == "hegrenade" else kind
	global_position = origin
	linear_velocity = impulse
	angular_velocity = Vector3.ZERO
	_simulation_tick = 0
	_cleanup_tick = WeaponClock.NEVER
	_last_surface_normal = Vector3.UP


func _on_body_entered(_body: Node) -> void:
	if linear_velocity.length() > 1.5:
		_emit_audio(
			"he.bounce",
			AudioRouterScript.CHAN_VOICE,
			{"volume": 0.25},
		)


func _audio_entity_id() -> int:
	if is_instance_valid(thrower) and thrower.has_method("audio_entity_id"):
		return 1000 + int(thrower.call("audio_entity_id"))
	return 1000 + get_instance_id() % 1000000


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
		_audio_entity_id(),
		channel,
		AudioRouterScript.meters_to_hu(global_position),
		overrides,
	)


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	_cleanup_tick = _simulation_tick + CLEANUP_TICKS
	freeze = true
	visible = false
	_emit_audio(
		"he.explode",
		AudioRouterScript.CHAN_WEAPON,
		{"variant_index": 0},
	)
	_emit_audio(
		"he.debris",
		AudioRouterScript.CHAN_VOICE,
		{"volume": 0.55},
	)
	var combat_effects := CombatEffectsScript.for_scene(get_tree().current_scene)
	if grenade_kind == "flashbang":
		if is_instance_valid(combat_effects):
			combat_effects._spawn_sprite(
				"muzzleflash1", global_position, 4.0, 30.0,
				CombatEffectsScript.EVENT_MUZZLE_FLASH, 0, true,
			)
		_blind_combatants()
		queue_free()
		return
	if grenade_kind == "smokegrenade":
		if is_instance_valid(combat_effects):
			# CS 1.6 smoke: a massive, ground-hugging, vision-blocking gray-olive
			# cloud that persists ~15 seconds, not a single small puff.
			combat_effects.spawn_smoke_cloud(global_position)
		queue_free()
		return
	if is_instance_valid(combat_effects):
		combat_effects.spawn_he_explosion(global_position, _last_surface_normal)
	var damage_origin := Ballistics.he_damage_origin(global_position)
	for actor in get_tree().get_nodes_in_group("damageable"):
		if not actor is Combatant or not actor.has_method("receive_explosion_damage"):
			continue
		var distance: float = damage_origin.distance_to(actor.global_position)
		if distance >= BLAST_RADIUS:
			continue
		var damage_target: Vector3 = actor.aim_point()
		var query := PhysicsRayQueryParameters3D.create(
			damage_origin,
			damage_target,
			1 | 2 | 4,
			[get_rid()],
		)
		var obstruction := get_world_3d().direct_space_state.intersect_ray(query)
		if not obstruction.is_empty() and obstruction.collider != actor:
			continue
		actor.call(
			"receive_explosion_damage",
			Ballistics.he_radius_damage(distance),
			global_position,
			thrower,
		)


func _blind_combatants() -> void:
	# CS 1.6 flashbang: everyone within range is blinded — the thrower and
	# teammates included. Duration scales with distance and with how directly
	# the victim faces the burst; a blocked line of sight nearly negates it.
	const FLASH_RANGE := 15.0
	const FULL_BLIND_SECONDS := 4.2
	for actor_node in get_tree().get_nodes_in_group("combatants"):
		var actor := actor_node as Combatant
		if not is_instance_valid(actor) or not actor.alive:
			continue
		var eye := actor.global_position + Vector3.UP * 0.5
		var distance := eye.distance_to(global_position)
		if distance >= FLASH_RANGE:
			continue
		var query := PhysicsRayQueryParameters3D.create(
			eye, global_position, 1, [get_rid(), actor.get_rid()],
		)
		var blocked := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
		var facing := 1.0
		var to_burst := (global_position - eye).normalized()
		var forward := -actor.global_transform.basis.z
		var dot := forward.dot(to_burst)
		if dot < -0.2:
			facing = 0.35
		elif dot < 0.4:
			facing = 0.65
		var strength := (1.0 - distance / FLASH_RANGE) * facing
		if blocked:
			strength *= 0.1
		var seconds := FULL_BLIND_SECONDS * strength
		if seconds < 0.1:
			continue
		actor.apply_flash_blind(seconds)
		if actor.is_in_group("player") and actor.has_signal("flash_blinded"):
			actor.emit_signal("flash_blinded", seconds)
