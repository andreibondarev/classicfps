extends SceneTree

const TargetScript = preload("res://scripts/target.gd")
const TacticsScript = preload("res://scripts/cs16_bot_tactics.gd")
const BallisticsScript = preload("res://scripts/cs16_ballistics.gd")

var failures: Array[String] = []
var scene: Node3D
var shooter: TargetActor
var victim: TargetActor


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOT COMBAT INTEGRATION TEST: " + message)


func _run() -> void:
	scene = Node3D.new()
	scene.name = "BotCombatTestScene"
	root.add_child(scene)
	current_scene = scene
	shooter = _make_actor(
		"Shooter",
		Combatant.TEAM_TERRORIST,
		0,
		Vector3.ZERO,
	)
	victim = _make_actor(
		"Victim",
		Combatant.TEAM_COUNTER_TERRORIST,
		1,
		Vector3(0.0, 0.0, -10.0),
	)
	await process_frame
	await physics_frame
	shooter.set_physics_process(false)
	victim.set_physics_process(false)
	shooter.active = true
	victim.active = false

	_test_live_clock_inventory_and_reload()
	_test_aim_error_controls_actual_ray()
	_test_damage_armor_and_hitgroups()
	_test_actor_render_schedule_equivalence()

	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_BOT_COMBAT_INTEGRATION_TEST_PASS")
		quit(0)
		return
	quit(1)


func _make_actor(
	actor_name: String,
	actor_team: String,
	actor_index: int,
	position: Vector3,
) -> TargetActor:
	var actor := TargetScript.new() as TargetActor
	actor.name = actor_name
	actor.index = actor_index
	actor.configure_identity(actor_team, actor_name)
	actor.position = position
	scene.add_child(actor)
	return actor


func _prepare_duel(clip: int, reserve: int) -> BotCombatController:
	shooter.reset_target(Vector3.ZERO)
	victim.reset_target(Vector3(0.0, 0.0, -10.0))
	shooter.set_physics_process(false)
	victim.set_physics_process(false)
	shooter.active = true
	victim.active = false
	victim.health = 1000000
	victim.armor = 100
	victim.has_helmet = true
	var controller := shooter.combat_controller as BotCombatController
	controller.reset_tactics()
	controller.current_enemy = victim
	controller._next_target_refresh = 1000.0
	controller.tactics.clip = clip
	controller.tactics.reserve = reserve
	shooter.weapon_clip = clip
	shooter.weapon_reserve = reserve
	return controller


func _drive_tick(
	controller: BotCombatController,
	delta: float,
) -> Dictionary:
	var command := controller.gather_command(delta)
	if command.look_target != Vector3.INF:
		shooter.face_aim_target(command.look_target)
	shooter.consume_combat_weapon_command(command)
	return command


func _test_live_clock_inventory_and_reload() -> void:
	var controller := _prepare_duel(3, 6)
	var actor_fire_ticks: Array[int] = []
	var reload_tick := -1
	var reload_complete_tick := -1
	for ignored in range(600):
		var was_reloading := shooter.weapon_reloading
		var command := _drive_tick(controller, 0.01)
		for fire_event: Dictionary in command.get("fire_events", []):
			actor_fire_ticks.append(int(fire_event.tick))
		if command.reload and reload_tick < 0:
			reload_tick = int(command.weapon_tick)
		if was_reloading and not shooter.weapon_reloading and reload_complete_tick < 0:
			reload_complete_tick = int(command.weapon_tick)
		_check(
			shooter.weapon_clip == int(controller.tactics.clip)
			and shooter.weapon_reserve == int(controller.tactics.reserve),
			"actor clip/reserve stay connected to the authoritative tactic clock",
		)
	_check(
		shooter.shot_trace.size() == controller.tactics.shots_fired,
		"every accepted 100 Hz tactic pulse reaches TargetActor gameplay",
	)
	_check(
		actor_fire_ticks.size() >= 6,
		"actor fires the initial and post-reload magazines",
	)
	if actor_fire_ticks.size() >= 3:
		_check(
			actor_fire_ticks[1] - actor_fire_ticks[0] == TacticsScript.AK_FIRE_TICKS
			and actor_fire_ticks[2] - actor_fire_ticks[1] == TacticsScript.AK_FIRE_TICKS,
			"live actor preserves the 100 ms AK cadence without a second throttle",
		)
		_check(reload_tick > actor_fire_ticks[2], "empty live actor magazine starts reload")
	_check(
		reload_complete_tick - reload_tick == TacticsScript.AK_RELOAD_TICKS,
		"live actor reload gap is exactly the 2.45 second AK deadline",
	)
	_check(
		shooter.weapon_clip == 0 and shooter.weapon_reserve == 0,
		"actor consumes its connected three-plus-six round test inventory exactly",
	)


func _test_aim_error_controls_actual_ray() -> void:
	_prepare_duel(30, 90)
	var before := victim.health
	var deliberately_bad_aim := victim.aim_point() + Vector3(2.0, 0.0, 0.0)
	shooter._try_fire(victim, deliberately_bad_aim, 1000)
	var shot: Dictionary = shooter.shot_trace.back()
	_check(not bool(shot.hit), "bot aim error can produce a real gameplay miss")
	_check(victim.health == before, "missed bot ray applies no exact-target shortcut damage")
	var ray_direction: Vector3 = shot.direction
	_check(
		ray_direction.dot(shooter.aim_point().direction_to(deliberately_bad_aim)) > 0.99,
		"actual bullet direction follows the tactic aim target",
	)


func _test_damage_armor_and_hitgroups() -> void:
	_prepare_duel(30, 90)
	var chest_direction := shooter.aim_point().direction_to(victim.aim_point())
	var chest := shooter._fire_cs_bullet(
		shooter.aim_point(),
		chest_direction,
		47,
	)
	_check(bool(chest.hit), "shared AK ray hits a visible combatant")
	_check(
		int(chest.hit_group) == BallisticsScript.HitGroup.CHEST,
		"torso impact resolves the chest hit group",
	)
	_check(
		int(chest.health_damage) > 20 and int(chest.health_damage) < 36,
		"AK range and kevlar reduce live chest health damage through shared ballistics",
	)
	_check(int(chest.armor_damage) > 0, "AK chest hit consumes live armor")

	victim.reset_target(Vector3(0.0, 0.0, -10.0))
	victim.set_physics_process(false)
	victim.active = false
	victim.armor = 100
	victim.has_helmet = true
	var head_point := Vector3(
		victim.global_position.x,
		victim.head_height() + 0.08,
		victim.global_position.z,
	)
	var head := shooter._fire_cs_bullet(
		shooter.aim_point(),
		shooter.aim_point().direction_to(head_point),
		48,
	)
	_check(
		int(head.hit_group) == BallisticsScript.HitGroup.HEAD,
		"high impact resolves the head hit group",
	)
	_check(
		int(head.health_damage) >= 100 and not victim.alive,
		"helmeted AK headshot uses the four-times hitgroup path and can kill",
	)


func _actor_trace_at_fps(fps: int) -> Array[Dictionary]:
	var controller := _prepare_duel(30, 90)
	var result: Array[Dictionary] = []
	for ignored in range(fps * 4):
		var command := _drive_tick(controller, 1.0 / float(fps))
		for event: Dictionary in command.get("fire_events", []):
			var live_shot: Dictionary = shooter.shot_trace.back()
			result.append({
				"tick": int(event.tick),
				"clip": int(event.clip_after),
				"reserve": int(event.reserve_after),
				"hit": bool(live_shot.hit),
				"hit_group": int(live_shot.hit_group),
			})
		for reload_tick: int in command.get("reload_ticks", []):
			result.append({"tick": reload_tick, "reload": true})
	return result


func _test_actor_render_schedule_equivalence() -> void:
	var at_30 := _actor_trace_at_fps(30)
	var at_60 := _actor_trace_at_fps(60)
	var at_144 := _actor_trace_at_fps(144)
	_check(
		at_30 == at_60 and at_30 == at_144,
		"real TargetActor fire/hit/ammo trace is identical at 30/60/144 Hz",
	)
