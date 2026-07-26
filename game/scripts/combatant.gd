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
var combat_controller: CombatController
var last_command: Dictionary = {}


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


func _commit_damage(
	health_damage: int,
	hit_position: Vector3,
	headshot: bool,
	attacker: Combatant,
) -> bool:
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
	velocity = Vector3.ZERO
	global_position = spawn_position


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
