class_name CombatController
extends Node

var actor: Combatant


func possess(combatant: Combatant) -> void:
	actor = combatant


func ingest_input(_event: InputEvent) -> void:
	pass


func gather_command(_delta: float) -> Dictionary:
	return {
		"movement": Vector2.ZERO,
		"world_velocity": Vector3.ZERO,
		"look_delta": Vector2.ZERO,
		"look_target": Vector3.INF,
		"jump": false,
		"crouch": false,
		"fire": false,
		"fire_pressed": false,
		"reload": false,
		"use": false,
		"weapon": "",
		"state": "idle",
		"enemy": null,
	}
