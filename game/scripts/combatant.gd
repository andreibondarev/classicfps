class_name Combatant
extends CharacterBody3D

const Ballistics := preload("res://scripts/cs16_ballistics.gd")

signal combatant_damaged(
	actor: Combatant,
	attacker: Combatant,
	remaining_health: int,
	headshot: bool,
)
signal combatant_eliminated(actor: Combatant, attacker: Combatant, headshot: bool)

const TEAM_TERRORIST := "T"
const TEAM_COUNTER_TERRORIST := "CT"
const TEAM_UNASSIGNED := "UNASSIGNED"
const GOLDSRC_UNIT := 0.01
const STANDING_VIEW_HEIGHT := 53.0 * GOLDSRC_UNIT
const STANDING_HEAD_HEIGHT := 57.0 * GOLDSRC_UNIT

var team := TEAM_UNASSIGNED
var display_name := ""
var health := 100
var armor := 0
var has_helmet := false
var alive := true
# Flashbang blindness, expressed in physics frames so bots and the player
# share one clock. -1 = not blinded.
var flash_blind_until_frame := -1


func apply_flash_blind(duration_seconds: float) -> void:
	var until := Engine.get_physics_frames() + int(
		duration_seconds * Engine.physics_ticks_per_second
	)
	flash_blind_until_frame = maxi(flash_blind_until_frame, until)


func is_flash_blinded() -> bool:
	return int(Engine.get_physics_frames()) < flash_blind_until_frame
var combat_controller: CombatController
var last_command: Dictionary = {}
var last_damage_attacker: Combatant


func _ready() -> void:
	add_to_group("combatants")
	add_to_group("damageable")


func configure_identity(new_team: String, new_display_name: String) -> void:
	team = new_team
	display_name = new_display_name


func is_opponent(other: Combatant) -> bool:
	return (
		is_instance_valid(other)
		and other != self
		and team != TEAM_UNASSIGNED
		and other.team != TEAM_UNASSIGNED
		and other.team != team
	)


func receive_damage(
	amount: float,
	hit_position := Vector3.ZERO,
	headshot := false,
	attacker: Combatant = null,
) -> bool:
	if not alive or amount <= 0.0:
		return false
	if is_instance_valid(attacker) and not is_opponent(attacker):
		return false

	var remaining := int(round(amount))
	if armor > 0:
		var absorbed := mini(armor, int(round(remaining * 0.55)))
		armor -= absorbed
		remaining -= absorbed
	return _commit_damage(remaining, hit_position, headshot, attacker)


func receive_bullet_damage(
	damage_after_range: int,
	hit_group: int,
	weapon_name: String,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
) -> bool:
	if not alive or damage_after_range <= 0:
		return false
	if is_instance_valid(attacker) and not is_opponent(attacker):
		return false
	var armor_type := (
		Ballistics.ArmorType.VEST_HELMET
		if has_helmet
		else Ballistics.ArmorType.KEVLAR
		if armor > 0
		else Ballistics.ArmorType.NONE
	)
	var result := Ballistics.resolve_bullet_damage(
		damage_after_range,
		hit_group,
		float(armor),
		armor_type,
		weapon_name,
	)
	armor = maxi(0, int(float(result.armor_remaining)))
	return _commit_damage(
		int(result.health_damage),
		hit_position,
		hit_group == Ballistics.HitGroup.HEAD,
		attacker,
	)


## Ground-plane facing of this combatant. Player hulls and bot actors both aim
## with their body yaw, so -Z of the body basis is the 1.6 `v_forward`.
func facing_direction() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0000001:
		return Vector3.FORWARD
	return forward.normalized()


## Knife hits use TraceAttack with DMG_BULLET, so they share the bullet armor
## branch (and the knife's 1.7 armor ratio) plus hit-group scaling. Only the
## 1.6 backstab multiplier is knife-specific, and it is applied to the base
## damage before any armor math, exactly as CKnife::Stab does.
func receive_melee_damage(
	base_damage: int,
	hit_group: int,
	weapon_name: String,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
	backstab := false,
) -> bool:
	var damage := base_damage
	if backstab:
		damage = int(float(base_damage) * Ballistics.KNIFE_BACKSTAB_MULTIPLIER)
	return receive_bullet_damage(
		damage,
		hit_group,
		weapon_name,
		hit_position,
		attacker,
	)


func receive_explosion_damage(
	raw_damage: float,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
) -> bool:
	if not alive or raw_damage <= 0.0:
		return false
	if is_instance_valid(attacker) and not is_opponent(attacker):
		return false
	var result := Ballistics.apply_explosion_armor(raw_damage, float(armor))
	armor = maxi(0, int(float(result.armor_remaining)))
	return _commit_damage(
		int(result.health_damage),
		hit_position,
		false,
		attacker,
	)


func receive_c4_explosion_damage(
	raw_damage: float,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
) -> bool:
	if not alive or raw_damage <= 0.0:
		return false
	# C4 RadiusDamage is objective world damage: unlike bullets and grenades it
	# reaches the planter and teammates regardless of the normal ally filter.
	var result := Ballistics.apply_explosion_armor(raw_damage, float(armor))
	armor = maxi(0, int(float(result.armor_remaining)))
	return _commit_damage(
		int(result.health_damage),
		hit_position,
		false,
		attacker,
	)


func _commit_damage(
	health_damage: int,
	hit_position: Vector3,
	headshot: bool,
	attacker: Combatant,
) -> bool:
	last_damage_attacker = attacker if is_instance_valid(attacker) else null
	health = maxi(0, health - maxi(health_damage, 0))
	_on_combatant_damaged(attacker, hit_position, headshot)
	combatant_damaged.emit(self, attacker, health, headshot)
	if health <= 0:
		alive = false
		velocity = Vector3.ZERO
		_on_combatant_eliminated(attacker, headshot)
		combatant_eliminated.emit(self, attacker, headshot)
	return true


func reset_combatant(spawn_position: Vector3, starting_armor := 0) -> void:
	health = 100
	armor = starting_armor
	if starting_armor <= 0:
		has_helmet = false
	alive = true
	last_command = {}
	last_damage_attacker = null
	velocity = Vector3.ZERO
	global_position = spawn_position
	_drop_spawn_to_floor()


func _drop_spawn_to_floor() -> void:
	## GoldSrc DispatchSpawn drops player entities to the floor (DROP_TO_FLOOR);
	## map spawn points sit a few units above ground. Without this, a combatant
	## that is frozen before its first physics tick renders hovering mid-air.
	## The engine drops the full 32 HU hull, not a point: probe the center and
	## four inset hull corners and rest on the highest walkable support so a
	## spawn beside sloped geometry cannot embed a hull corner in the floor
	## (Godot would then depenetrate the body upward on its first tick,
	## briefly launching it airborne).
	if not is_inside_tree():
		return
	var world := get_world_3d()
	if world == null:
		return
	var half_width := 16.0 * GOLDSRC_UNIT
	var inset := half_width - 0.001
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(inset, 0.0, inset),
		Vector3(inset, 0.0, -inset),
		Vector3(-inset, 0.0, inset),
		Vector3(-inset, 0.0, -inset),
	]
	var highest_floor_y := -INF
	for offset: Vector3 in offsets:
		var from := global_position + offset + Vector3.UP * 0.10
		var query := PhysicsRayQueryParameters3D.create(
			from,
			from + Vector3.DOWN * 1.30,
		)
		query.exclude = [get_rid()]
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty() or float(hit.normal.y) < 0.7:
			continue
		highest_floor_y = maxf(highest_floor_y, float(hit.position.y))
	if highest_floor_y == -INF:
		return
	if highest_floor_y < global_position.y:
		global_position.y = highest_floor_y + 0.001


func is_dead() -> bool:
	return not alive


func aim_point() -> Vector3:
	return global_position + Vector3.UP * STANDING_VIEW_HEIGHT


func head_height() -> float:
	return global_position.y + STANDING_HEAD_HEIGHT


func _on_combatant_damaged(
	_attacker: Combatant,
	_hit_position: Vector3,
	_headshot: bool,
) -> void:
	pass


func _on_combatant_eliminated(_attacker: Combatant, _headshot: bool) -> void:
	pass
