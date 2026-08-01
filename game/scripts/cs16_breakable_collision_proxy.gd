class_name CS16BreakableCollisionProxy
extends AnimatableBody3D

## Adapter attached to BspMap's existing func_breakable collision body. It
## preserves the imported concave shape while exposing the same damage methods
## already consumed by player hitscan and knife traces.

const DMG_BULLET := 1 << 1
const DMG_CLUB := 1 << 7

var breakable_runtime: RefCounted
var breakable_entity_id := -1
var actor_id_resolver := Callable()


func bind_breakable(
	runtime: RefCounted,
	entity_id: int,
	resolver := Callable(),
) -> void:
	breakable_runtime = runtime
	breakable_entity_id = entity_id
	actor_id_resolver = resolver
	set_meta("cs16_breakable_entity_id", entity_id)


func receive_bullet_damage(
	damage: int,
	_hit_group: Variant,
	_weapon_name: String,
	hit_position: Vector3,
	attacker: Variant,
) -> Dictionary:
	return _apply_source_damage(
		float(damage),
		hit_position,
		attacker,
		DMG_BULLET,
	)


func apply_damage(
	damage: float,
	hit_position: Vector3,
	_headshot := false,
	attacker: Variant = null,
) -> Dictionary:
	# ReGameDLL classifies crowbar/knife-style direct melee as DMG_CLUB.
	return _apply_source_damage(
		damage,
		hit_position,
		attacker,
		DMG_CLUB,
	)


func _apply_source_damage(
	damage: float,
	hit_position: Vector3,
	attacker: Variant,
	damage_bits: int,
) -> Dictionary:
	if breakable_runtime == null or breakable_entity_id < 0:
		return {}
	var attacker_id := _resolve_actor_id(attacker)
	var attack_direction := Vector3.RIGHT
	if attacker is Node3D:
		# CBreakable uses inflictor origin minus brush center for directed gibs.
		attack_direction = (
			(attacker as Node3D).global_position - hit_position
		).normalized()
	return breakable_runtime.damage(
		breakable_entity_id,
		attacker_id,
		attacker_id,
		damage,
		damage_bits,
		attack_direction,
		attacker is Node,
	)


func _resolve_actor_id(actor: Variant) -> int:
	if actor is int:
		return int(actor)
	if actor_id_resolver.is_valid():
		return int(actor_id_resolver.call(actor))
	if actor is Object:
		var object := actor as Object
		if object.has_meta("actor_id"):
			return int(object.get_meta("actor_id"))
	return -1
