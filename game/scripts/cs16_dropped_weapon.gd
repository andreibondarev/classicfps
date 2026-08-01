class_name CS16DroppedWeapon
extends Node3D

## Source-backed dropped gun world item.
##
## CS 1.6's DropPlayerItem wraps the gun's w_ model in a CWeaponBox that
## settles almost immediately, so the runtime item is a static floor-snapped
## model with the weaponbox's random yaw. The game loop performs the CS 1.6
## hull-touch pickup check over the live drop list.

const C4WorldScript := preload("res://scripts/cs16_c4_world.gd")
const WeaponRegistryScript := preload("res://scripts/cs16_weapon_registry.gd")

const FLOOR_PROBE_UP := 0.5
const FLOOR_PROBE_DOWN := 4.0

var weapon_name := ""
var clip_ammo := 0
var reserve_ammo := 0
var slot := 0
# Manual G drops land inside the pickup radius; the dropper must leave it
# once before touch pickup re-arms, or the drop would bounce straight back.
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


func _physics_process(_delta: float) -> void:
	# Space queries need one frame inside the physics world before the raycast
	# can see the imported BSP colliders.
	_snap_to_floor()
	set_physics_process(false)


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
