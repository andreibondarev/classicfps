class_name Combatant
extends CharacterBody3D

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

var team := TEAM_UNASSIGNED
var display_name := ""
var health := 100
var armor := 0
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
	health = maxi(0, health - remaining)
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
	alive = true
	last_command = {}
	velocity = Vector3.ZERO
	global_position = spawn_position


func is_dead() -> bool:
	return not alive


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 1.43


func head_height() -> float:
	return aim_point().y


func _on_combatant_damaged(
	_attacker: Combatant,
	_hit_position: Vector3,
	_headshot: bool,
) -> void:
	pass


func _on_combatant_eliminated(_attacker: Combatant, _headshot: bool) -> void:
	pass
