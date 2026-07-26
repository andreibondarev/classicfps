class_name CS16C4World
extends RigidBody3D

## Source-backed dropped C4 weaponbox.
##
## DropPlayerItem wraps models/w_backpack.mdl in CWeaponBox: MOVETYPE_TOSS,
## SOLID_TRIGGER, a point hull, and no pickup before FL_ONGROUND. The rigid
## body supplies the toss/floor contact; the child Area3D supplies the
## non-blocking player touch contract after landing.

signal pickup_requested(actor: Combatant)

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const BACKPACK_MODEL := "res://generated/world_weapons/backpack/model.json"
const PLANTED_MODEL := "res://generated/world_weapons/c4/model.json"
const PICKUP_SIZE := Vector3.ONE * 2.0 * Combatant.GOLDSRC_UNIT
const FALL_POINT_RADIUS := 1.0 * Combatant.GOLDSRC_UNIT

var claimed := false
var materialized := false
var pickup_area: Area3D
var world_shape_node: CollisionShape3D
var _flight_ticks := 0


func _ready() -> void:
	name = "DroppedC4"
	collision_layer = 8
	collision_mask = 1
	mass = 2.0
	gravity_scale = 1.0
	linear_damp = 0.35
	angular_damp = 0.8
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_fall_body_entered)

	world_shape_node = CollisionShape3D.new()
	world_shape_node.name = "FallPointCollision"
	var world_shape := SphereShape3D.new()
	world_shape.radius = FALL_POINT_RADIUS
	world_shape_node.shape = world_shape
	world_shape_node.position.y = FALL_POINT_RADIUS
	add_child(world_shape_node)

	var visual := create_source_model(BACKPACK_MODEL, "BackpackModel")
	# The converted w_backpack geometry has a floor-space minimum at zero.
	# Offsetting it upward produced a detached shadow/visible 2.5 HU air gap.
	visual.position.y = 0.0
	add_child(visual)

	pickup_area = Area3D.new()
	pickup_area.name = "PickupTrigger"
	pickup_area.collision_layer = 0
	pickup_area.collision_mask = 2 | 4
	pickup_area.monitoring = false
	pickup_area.monitorable = true
	var pickup_shape_node := CollisionShape3D.new()
	var pickup_shape := BoxShape3D.new()
	pickup_shape.size = PICKUP_SIZE
	pickup_shape_node.shape = pickup_shape
	pickup_shape_node.position.y = 1.0 * Combatant.GOLDSRC_UNIT
	pickup_area.add_child(pickup_shape_node)
	pickup_area.body_entered.connect(_on_pickup_body_entered)
	add_child(pickup_area)


func _physics_process(_delta: float) -> void:
	_flight_ticks += 1
	# MOVETYPE_TOSS receives its launch velocity before FL_ONGROUND can be set.
	# Give the rigid body one integration step so a ground-height manual drop
	# actually travels instead of materializing at its spawn coordinate.
	if _flight_ticks <= 1:
		return
	if not materialized and _has_floor_support():
		_materialize()


func _on_fall_body_entered(body: Node) -> void:
	if materialized or not body is CollisionObject3D:
		return
	if ((body as CollisionObject3D).collision_layer & 1) != 0:
		# A wall touch must not make the weaponbox pickable. Defer the space
		# query until the collision callback has finished and require support
		# directly below the point hull (GoldSrc's FL_ONGROUND gate).
		call_deferred("_materialize_if_grounded")


func _materialize_if_grounded() -> void:
	if not materialized and _has_floor_support():
		_materialize()


func _has_floor_support() -> bool:
	if not is_inside_tree() or linear_velocity.y > 0.05:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * FALL_POINT_RADIUS,
		global_position - Vector3.UP * (FALL_POINT_RADIUS + 2.0 * Combatant.GOLDSRC_UNIT),
		1,
		[get_rid()],
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return Vector3(hit.get("normal", Vector3.ZERO)).dot(Vector3.UP) >= 0.7


func _materialize() -> void:
	if materialized:
		return
	materialized = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	world_shape_node.set_deferred("disabled", true)
	pickup_area.set_deferred("monitoring", true)


func _on_pickup_body_entered(body: Node3D) -> void:
	if not materialized or claimed or not body is Combatant:
		return
	var actor := body as Combatant
	if not actor.alive or actor.team != Combatant.TEAM_TERRORIST:
		return
	claimed = true
	pickup_area.set_deferred("monitoring", false)
	pickup_requested.emit(actor)


static func create_source_model(model_path: String, model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = model_name
	var template := _load_static_template(model_path)
	if template.is_empty():
		return root
	var instance := CharacterModelScript._create_instance(model_name + "Mesh", template)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)
	return root


static func _load_static_template(model_path: String) -> Dictionary:
	var file := FileAccess.open(model_path, FileAccess.READ)
	if file == null:
		push_error("Missing original C4 world model export: %s" % model_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or str(parsed.get("format", "")) != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 1
	):
		push_error("Invalid original C4 world model export: %s" % model_path)
		return {}
	# Static world exports are protocol47-mdl v1. Their base geometry is the
	# same schema as animated v2 models, but they intentionally have no tapes.
	return CharacterModelScript._build_template(model_path, parsed)


static func create_planted_visual() -> Node3D:
	return create_source_model(PLANTED_MODEL, "PlantedC4Model")
