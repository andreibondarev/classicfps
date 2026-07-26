extends SceneTree

const C4World := preload("res://scripts/cs16_c4_world.gd")
const CombatantScript := preload("res://scripts/combatant.gd")
const DropContract := preload("res://scripts/cs16_c4_drop_contract.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "C4DropPhysicsStage"
	root.add_child(stage)
	current_scene = stage
	var floor := _make_static_box(
		"Floor",
		Vector3(12.0, 0.20, 12.0),
		Vector3(0.0, -0.10, 0.0),
	)
	stage.add_child(floor)
	var contract: Dictionary = DropContract.resolve_manual_drop(
		"c4",
		true,
		true,
		"carried",
		Vector3(0.0, 1.0, 0.0),
		Vector3(1.0, 0.7, 0.0),
	)
	_check(bool(contract.allowed), "live active carrier may manually drop C4")
	_check(
		(contract.origin as Vector3).distance_to(Vector3(0.10, 1.0, 0.0)) < 0.00001
		and (contract.velocity as Vector3).distance_to(Vector3(4.0, 0.0, 0.0)) < 0.00001,
		"manual/death drop contract is +10 HU and horizontal 400 HU/s",
	)
	for denied: Dictionary in [
		DropContract.resolve_manual_drop(
			"ak47", true, true, "carried", Vector3.ZERO, Vector3.FORWARD
		),
		DropContract.resolve_manual_drop(
			"c4", false, true, "carried", Vector3.ZERO, Vector3.FORWARD
		),
		DropContract.resolve_manual_drop(
			"c4", true, false, "carried", Vector3.ZERO, Vector3.FORWARD
		),
		DropContract.resolve_manual_drop(
			"c4", true, true, "planted", Vector3.ZERO, Vector3.FORWARD
		),
	]:
		_check(not bool(denied.allowed), "invalid manual C4 drop is rejected")

	var dropped = C4World.new()
	stage.add_child(dropped)
	dropped.global_position = contract.origin
	dropped.linear_velocity = contract.velocity
	var landed := false
	for tick in 300:
		await physics_frame
		if dropped.materialized:
			landed = true
			break
	_check(
		landed
		and dropped.pickup_area.monitoring
		and dropped.global_position.y <= 0.04,
		"real 400-HU/s rigid-body toss lands and materializes on floor support",
	)

	var picked: Array[Combatant] = []
	dropped.pickup_requested.connect(
		func(actor: Combatant) -> void:
			picked.append(actor)
	)
	var terrorist := _make_combatant("TouchingT", CombatantScript.TEAM_TERRORIST)
	terrorist.position = dropped.position
	stage.add_child(terrorist)
	for overlap_tick in 10:
		await physics_frame
		if dropped.claimed:
			break
	_check(
		dropped.claimed
		and picked.size() == 1
		and picked[0] == terrorist,
		"real Area3D/body overlap transfers landed C4 to live Terrorist",
	)

	# A wall collision high above any supporting floor must not make the point
	# hull pickable. Use a separate stage without a floor below the wall test.
	var wall_stage := Node3D.new()
	wall_stage.name = "WallOnlyStage"
	root.add_child(wall_stage)
	var wall := _make_static_box(
		"Wall",
		Vector3(0.20, 4.0, 4.0),
		Vector3.ZERO,
	)
	wall_stage.add_child(wall)
	var wall_drop = C4World.new()
	wall_stage.add_child(wall_drop)
	wall_drop.global_position = Vector3(-0.30, 1.5, 0.0)
	wall_drop.linear_velocity = Vector3(4.0, 0.0, 0.0)
	for wall_tick in 25:
		await physics_frame
	_check(
		not wall_drop.materialized and not wall_drop.pickup_area.monitoring,
		"wall-only contact never satisfies the grounded weaponbox gate",
	)

	if failures.is_empty():
		print("GAME_C4_DROP_PHYSICS_TEST_PASS")
		await _finish(stage, wall_stage)
		quit(0)
	else:
		print("GAME_C4_DROP_PHYSICS_TEST_FAIL (%d)" % failures.size())
		await _finish(stage, wall_stage)
		quit(1)


func _make_static_box(
	node_name: String,
	size: Vector3,
	position: Vector3,
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _make_combatant(node_name: String, team: String) -> Combatant:
	var actor := CombatantScript.new()
	actor.name = node_name
	actor.team = team
	actor.collision_layer = 2
	actor.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.32, 0.72, 0.32)
	collision.position.y = 0.36
	collision.shape = shape
	actor.add_child(collision)
	return actor


func _finish(stage: Node, wall_stage: Node) -> void:
	current_scene = null
	stage.queue_free()
	wall_stage.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("C4 DROP PHYSICS TEST: " + message)
