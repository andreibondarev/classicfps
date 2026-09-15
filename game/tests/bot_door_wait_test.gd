extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var record := {"classname": "func_door_rotating", "state": "open",
		"no_auto_return": false, "start_open": false, "return_tick": 500,
		"open_angle": 90.0, "speed": 100.0, "motion_total": 90.0,
		"motion_progress": 30.0, "motion_per_tick": 1.0}
	_check(BotCombatController._returning_door_wait_ticks(record, 100) == 492,
		"wait includes the scheduled return and normal closing duration")
	var closing := record.duplicate()
	closing.state = "closing"
	_check(BotCombatController._returning_door_wait_ticks(closing, 100) == 62,
		"already-closing door waits only for remaining movement")
	for patch: Dictionary in [{"classname": "func_button"}, {"state": "closed"},
		{"state": "opening"}, {"no_auto_return": true}, {"start_open": true},
		{"return_tick": -1}, {"return_tick": 99}, {"return_tick": 1000}, {"speed": 0.0}]:
		var changed := record.duplicate()
		changed.merge(patch, true)
		_check(BotCombatController._returning_door_wait_ticks(changed, 100) == 0,
			"do not wait for an unsuitable/unbounded door: " + str(patch))
	var actor := Combatant.new()
	root.add_child(actor)
	var controller := BotCombatController.new()
	actor.add_child(controller)
	controller.possess(actor)
	controller._objective_tick = 20
	controller._door_wait_until_tick = 40
	var result := controller._apply_unwedge({"world_velocity": Vector3.RIGHT * 2.0,
		"fire": true, "reload": true, "look_target": Vector3.FORWARD}, 0.01)
	_check(result.world_velocity == Vector3.ZERO and result.waiting_for_door,
		"an active door wait suppresses movement only")
	_check(result.fire and result.reload and result.look_target == Vector3.FORWARD,
		"self-defense and aiming remain available during a door wait")
	controller._objective_tick = 40
	result = controller._apply_unwedge({"world_velocity": Vector3.RIGHT * 2.0}, 0.01)
	_check(result.world_velocity == Vector3.RIGHT * 2.0 and not result.has("waiting_for_door"),
		"movement resumes at the bounded deadline")
	controller._door_wait_until_tick = 100
	controller.reset_tactics()
	_check(controller._door_wait_until_tick == -1, "round/tactics reset cancels stale waits")
	actor.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_BOT_DOOR_WAIT_PASS")
	quit(0 if failures.is_empty() else 1)
