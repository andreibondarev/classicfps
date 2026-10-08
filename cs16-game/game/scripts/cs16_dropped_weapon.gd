class_name CS16DroppedWeapon
extends Node3D

signal landed(position: Vector3)

## Source-backed dropped gun world item.
##
## Host-owned toss of the original w_ model. A swept point against map solids
## supplies travel, wall contact and landing; clients only interpolate snapshots.
## The existing game loop owns inventory and hull-touch pickup checks.

const C4WorldScript := preload("res://scripts/cs16_c4_world.gd")
const WeaponRegistryScript := preload("res://scripts/cs16_weapon_registry.gd")

const FLOOR_PROBE_UP := 0.5
const FLOOR_PROBE_DOWN := 4.0
const TOSS_SPEED := 4.0
const TOSS_LIFT := 1.0
const CONTACT_OFFSET := 0.01

var toss_velocity := Vector3.ZERO
var tossing := false

var weapon_name := ""
var clip_ammo := 0
var reserve_ammo := 0
var slot := 0
# Durable Game identity, never a reusable network peer/player slot.
var dropper_id := ""
# Manual G drops suppress only the dropper until it leaves the pickup radius.
# Other humans can collect the item immediately with an empty weapon slot.
var pickup_armed := true


static func is_droppable(weapon: String) -> bool:
	var definition := WeaponRegistryScript.definition(weapon)
	if definition.is_empty():
		return false
	return str(definition.category) not in ["melee", "grenade", "objective"]


func setup(weapon: String, dropped_clip: int, dropped_reserve: int) -> void:
	weapon_name = weapon.to_lower()
	clip_ammo = maxi(dropped_clip, 0)
	reserve_ammo = maxi(dropped_reserve, 0)
	slot = int(WeaponRegistryScript.definition(weapon_name).get("slot", 0))


func start_toss(forward: Vector3) -> void:
	var direction := Vector3(forward.x, 0.0, forward.z).normalized()
	toss_velocity = direction * TOSS_SPEED + Vector3.UP * TOSS_LIFT
	tossing = true
	set_physics_process(true)


func _ready() -> void:
	name = "DroppedWeapon_%s" % weapon_name
	# Deterministic per-drop yaw: the shared RNG stream must not shift under
	# the fixed-fps bot-determinism signature runs.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(weapon_name) ^ hash((position * 64.0).round())
	rotation.y = rng.randf_range(0.0, TAU)
	var model_path := "res://generated/world_weapons/%s/model.json" % weapon_name
	if FileAccess.file_exists(model_path):
		add_child(C4WorldScript.create_source_model(model_path, "WorldModel"))
	# A registry weapon without an exported w_ model stays an invisible but
	# functional pickup; placeholder geometry is deliberately not faked.


func _physics_process(delta: float) -> void:
	if tossing:
		_advance_toss(delta)
		return
	# Space queries need one frame inside the physics world before the raycast
	# can see the imported BSP colliders.
	_snap_to_floor()
	set_physics_process(false)


func _advance_toss(delta: float) -> void:
	toss_velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 8.0)) * delta
	var remaining := delta
	# Sweep the full displacement, including fast throws near thin walls.
	for contact in range(3):
		var origin := global_position + Vector3.UP * CONTACT_OFFSET
		var destination := origin + toss_velocity * remaining
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(origin, destination, 1))
		if hit.is_empty():
			global_position = destination - Vector3.UP * CONTACT_OFFSET
			return
		var normal: Vector3 = hit.normal
		var distance := origin.distance_to(destination)
		remaining *= 1.0 - clampf(origin.distance_to(hit.position) / maxf(distance, 0.00001), 0.0, 1.0)
		global_position = hit.position + normal * CONTACT_OFFSET - Vector3.UP * CONTACT_OFFSET
		if normal.y >= 0.7 and toss_velocity.y <= 0.0:
			toss_velocity = Vector3.ZERO
			tossing = false
			set_physics_process(false)
			landed.emit(global_position)
			return
		toss_velocity = toss_velocity.slide(normal)


func _snap_to_floor() -> void:
	if not is_inside_tree():
		return
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * FLOOR_PROBE_UP,
		global_position - Vector3.UP * FLOOR_PROBE_DOWN,
		1,
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = Vector3(hit.get("position", global_position))
