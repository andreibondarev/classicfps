extends SceneTree

## Movement-recovery gates for offline bots: a mutual wedge must resolve without
## local avoidance, a climbable lip must be taken even when it is met at an
## angle, and a ledge above the step height must be jumped rather than ground
## into. Every scenario runs on the real 100 Hz physics hull, not on a model of
## it, because all three defects lived in the physical resolution.

const TargetScript = preload("res://scripts/target.gd")
const WALK_SPEED := 2.21
const STEP_HEIGHT := 0.14
const LEDGE_HEIGHT := 0.30

var failures: Array[String] = []
var scene: Node3D


class ScriptedBotController extends BotCombatController:
	## Drives the actor with a fixed world velocity while still running the
	## controller's own unwedge, so the gate exercises production recovery code
	## without needing a navigation mesh.
	var scripted_velocity := Vector3.ZERO
	var unwedged := false

	func gather_command(delta: float) -> Dictionary:
		var command := {
			"movement": Vector2.ZERO,
			"world_velocity": scripted_velocity,
			"look_delta": Vector2.ZERO,
			"look_target": Vector3.INF,
			"jump": false,
			"crouch": false,
			"walk": false,
			"fire": false,
			"fire_pressed": false,
			"secondary_pressed": false,
			"reload": false,
			"use": false,
			"weapon": "",
			"state": "scripted",
			"enemy": null,
		}
		_advance_objective_clock(delta)
		var result := _apply_unwedge(command, delta)
		if bool(result.get("unwedging", false)):
			unwedged = true
		return result


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOT UNSTICK TEST: " + message)


func _run() -> void:
	scene = Node3D.new()
	scene.name = "BotUnstickTestScene"
	root.add_child(scene)
	current_scene = scene
	_add_box(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	await process_frame
	await physics_frame

	await _test_mutual_wedge_resolves()
	await _test_angled_step_lip()
	await _test_jumpable_ledge()

	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_BOT_UNSTICK_TEST_PASS")
		quit(0)
		return
	quit(1)


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	body.position = center
	scene.add_child(body)
	return body


func _make_bot(
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


func _scripted_controller(actor: TargetActor) -> ScriptedBotController:
	## Replaces the production controller with one that keeps its unwedge but
	## takes its route from the test.
	var previous := actor.combat_controller
	if is_instance_valid(previous):
		actor.remove_child(previous)
		previous.queue_free()
	var controller := ScriptedBotController.new()
	controller.name = "ScriptedController"
	actor.add_child(controller)
	actor.combat_controller = controller
	controller.configure(actor, actor.navigation_agent, actor.index)
	return controller


func _test_mutual_wedge_resolves() -> void:
	var first := _make_bot("Wedge_A", Combatant.TEAM_TERRORIST, 0, Vector3(0.0, 0.2, 0.0))
	var second := _make_bot("Wedge_B", Combatant.TEAM_TERRORIST, 1, Vector3(0.0, 0.2, -0.34))
	await physics_frame
	first.reset_target(Vector3(0.0, 0.05, 0.0))
	second.reset_target(Vector3(0.0, 0.05, -0.34))
	var first_controller := _scripted_controller(first)
	var second_controller := _scripted_controller(second)
	# Head-on: each bot walks straight into the other's 32 HU hull.
	first_controller.scripted_velocity = Vector3(0.0, 0.0, -WALK_SPEED)
	second_controller.scripted_velocity = Vector3(0.0, 0.0, WALK_SPEED)

	var separation := 0.0
	var resolved_tick := -1
	for tick in range(300):
		await physics_frame
		separation = Vector2(
			first.global_position.x - second.global_position.x,
			first.global_position.z - second.global_position.z,
		).length()
		if separation > 0.5 and resolved_tick < 0:
			resolved_tick = tick + 1
			break
	_check(
		resolved_tick > 0,
		"a head-on pair of bots unwedges (separation %.3f m after 300 ticks)"
		% separation,
	)
	_check(
		resolved_tick < 0 or resolved_tick <= 200,
		"the wedge resolves within a bounded 200 ticks (took %d)" % resolved_tick,
	)
	_check(
		first_controller.unwedged or second_controller.unwedged,
		"the recovery came from the deterministic unwedge, not from luck",
	)
	first.queue_free()
	second.queue_free()
	await process_frame


func _test_angled_step_lip() -> void:
	# A 14 HU lip: below the 18 HU step limit, so it must never stop a bot.
	# A 1 m thick slab whose top surface sits exactly at the lip height.
	_add_box(Vector3(0.0, STEP_HEIGHT - 0.5, -6.0), Vector3(12.0, 1.0, 8.0))
	var actor := _make_bot(
		"Stepper",
		Combatant.TEAM_COUNTER_TERRORIST,
		0,
		Vector3(0.0, 0.2, 0.0),
	)
	await physics_frame
	actor.reset_target(Vector3(0.0, 0.05, 0.0))
	var controller := _scripted_controller(actor)
	# Deliberately oblique: one axis stays clear along the lip, which is exactly
	# the case the old "both axes blocked" gate never resolved.
	controller.scripted_velocity = Vector3(0.707, 0.0, -0.707) * WALK_SPEED
	var mounted_tick := -1
	for tick in range(400):
		await physics_frame
		if actor.global_position.y >= STEP_HEIGHT - 0.01:
			mounted_tick = tick + 1
			break
	_check(
		mounted_tick > 0,
		"a bot meeting a 14 HU lip at 45 degrees climbs it (y=%.3f after 400 ticks)"
		% actor.global_position.y,
	)
	# The hull mounts the lip while its origin is still short of the slab edge;
	# give it a moment to walk clear of the boundary.
	for ignored in range(60):
		await physics_frame
	_check(
		actor.global_position.z < -2.0,
		"the climbing bot keeps making progress along its commanded direction",
	)
	actor.queue_free()
	await process_frame


func _test_jumpable_ledge() -> void:
	# 30 HU: above the 18 HU step, inside the 45 HU jump apex.
	_add_box(Vector3(0.0, LEDGE_HEIGHT - 0.5, 8.0), Vector3(12.0, 1.0, 8.0))
	var actor := _make_bot(
		"Jumper",
		Combatant.TEAM_COUNTER_TERRORIST,
		1,
		Vector3(0.0, 0.2, 2.0),
	)
	await physics_frame
	actor.reset_target(Vector3(0.0, 0.05, 2.0))
	var controller := _scripted_controller(actor)
	controller.scripted_velocity = Vector3(0.0, 0.0, WALK_SPEED)
	var airborne := false
	var mounted_tick := -1
	for tick in range(500):
		await physics_frame
		if not actor.is_on_floor():
			airborne = true
		if actor.global_position.y >= LEDGE_HEIGHT - 0.02:
			mounted_tick = tick + 1
			break
	_check(
		mounted_tick > 0,
		"a bot mounts a 30 HU ledge (y=%.3f after 500 ticks)"
		% actor.global_position.y,
	)
	_check(airborne, "the ledge was mounted by jumping, not by a silent teleport")
	_check(
		mounted_tick < 0 or mounted_tick > 20,
		"the jump waits for a sustained obstruction instead of firing instantly",
	)
	actor.queue_free()
	await process_frame
