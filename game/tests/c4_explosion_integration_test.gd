extends SceneTree

const EffectsScript := preload("res://scripts/cs16_combat_effects.gd")
const RoundStateScript := preload("res://scripts/cs16_round_state.gd")


class WaterVolume:
	extends Node

	var bounds: AABB

	func _init(next_bounds: AABB) -> void:
		bounds = next_bounds

	func contains_point(point: Vector3) -> bool:
		return bounds.has_point(point)

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("C4 EXPLOSION INTEGRATION TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var planter = game.allied_bots[0]
	var teammate = game.allied_bots[1]
	var victim = game.targets[0]
	var outside = game.targets[1]
	var origin: Vector3 = victim.global_position
	planter.global_position = origin + Vector3(2.0, 0.0, 0.0)
	teammate.global_position = origin + Vector3(3.0, 0.0, 0.0)
	victim.health = 1
	outside.global_position = origin + Vector3(30.0, 0.0, 0.0)
	var elimination := {"attacker": null}
	victim.combatant_eliminated.connect(
		func(_actor: Combatant, attacker: Combatant, _headshot: bool) -> void:
			elimination.attacker = attacker
	)
	game._spawn_bomb_visual(origin)
	var planted_model = game.bomb
	game._apply_c4_explosion({
		"position": origin,
		"damage": RoundStateScript.C4_DAMAGE,
		"radius_hu": RoundStateScript.C4_RADIUS_HU,
		"attacker_id": planter.name,
		"planter_id": planter.name,
		"cleanup_world_c4": true,
	})
	var effects: CS16CombatEffects = EffectsScript.for_scene(game)
	var fireballs := effects.event_log.filter(
		func(event: Dictionary) -> bool:
			return str(event.get("type", "")) == EffectsScript.EVENT_C4_FIREBALL
	)
	_check(not victim.alive, "inside-radius CT takes production C4 damage")
	_check(outside.health == 100, "outside-radius combatant takes no C4 damage")
	_check(
		not planter.alive and planter.last_damage_attacker == planter,
		"C4 damages its own planter while retaining self attribution",
	)
	_check(
		teammate.health < 100 and teammate.last_damage_attacker == planter,
		"C4 bypasses the normal ally filter and attributes team damage to planter",
	)
	_check(
		elimination.attacker == planter
		and victim.last_damage_attacker == planter,
		"C4 RadiusDamage preserves the planter as attacker",
	)
	_check(
		not planted_model.visible
		and not is_instance_valid(game.bomb)
		and not game.bomb_planted,
		"Explode2 hides/removes the planted model before completing damage",
	)
	_check(
		fireballs.size() == 4,
		"production C4 explosion emits the four stock Explode2 fireballs",
	)

	var water_target = game.targets[2]
	water_target.reset_target(origin + Vector3(1.0, 0.0, 0.0))
	water_target.set_meta("source_water_level", 3)
	game._apply_c4_explosion({
		"position": origin,
		"damage": RoundStateScript.C4_DAMAGE,
		"radius_hu": RoundStateScript.C4_RADIUS_HU,
		"attacker_id": planter.name,
	})
	_check(
		water_target.health == 100,
		"dry C4 blast skips a fully submerged combatant",
	)

	var volume := WaterVolume.new(
		AABB(origin - Vector3.ONE * 0.10, Vector3.ONE * 0.20),
	)
	volume.add_to_group("water_volumes")
	game.add_child(volume)
	var dry_target = game.targets[3]
	dry_target.reset_target(origin + Vector3(1.2, 0.0, 0.0))
	dry_target.set_meta("source_water_level", 0)
	effects.event_log.clear()
	game._apply_c4_explosion({
		"position": origin,
		"damage": RoundStateScript.C4_DAMAGE,
		"radius_hu": RoundStateScript.C4_RADIUS_HU,
		"attacker_id": planter.name,
	})
	_check(
		dry_target.health == 100,
		"underwater C4 blast skips a dry combatant",
	)
	water_target.reset_target(origin + Vector3(1.0, 0.0, 0.0))
	water_target.set_meta("source_water_level", 3)
	game._apply_c4_explosion({
		"position": origin,
		"damage": RoundStateScript.C4_DAMAGE,
		"radius_hu": RoundStateScript.C4_RADIUS_HU,
		"attacker_id": planter.name,
	})
	_check(
		water_target.health < 100,
		"underwater C4 blast damages a fully submerged combatant",
	)
	var underwater_sparks := effects.event_log.filter(
		func(event: Dictionary) -> bool:
			return str(event.get("type", "")) == EffectsScript.EVENT_HE_SPARKS
	)
	_check(
		underwater_sparks.is_empty(),
		"PointContents water suppresses the Explode2 spark shower",
	)

	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_C4_EXPLOSION_INTEGRATION_TEST_PASS")
		quit(0)
	else:
		print("GAME_C4_EXPLOSION_INTEGRATION_TEST_FAIL: " + ", ".join(failures))
		quit(1)
