extends SceneTree

const Prediction = preload("res://scripts/network_movement_prediction.gd")
const State = preload("res://scripts/network_world_state.gd")
class CommandController extends CombatController:
	var next := {}
	func gather_command(delta: float) -> Dictionary:
		var command := super.gather_command(delta)
		command.merge(next, true)
		return command

var failures: Array[String] = []
var world: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _solid(position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)


func _pawn() -> PlayerController:
	var player := PlayerController.new()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.collision_layer = 0
	player.collision_mask = 1
	player.global_position = Vector3.ZERO
	return player


func _baseline(player: PlayerController) -> Dictionary:
	return {"row": {"position": player.global_position, "velocity": player.velocity, "alive": player.alive},
		"motion": State.motion_for(player)}


func _run() -> void:
	var prediction_script: Script = Prediction
	if not prediction_script.can_instantiate():
		push_error("Prediction script did not compile")
		quit(1)
		return
	if AudioServer.get_driver_name() != "Dummy":
		push_error("Prediction test requires Dummy audio")
		quit(1)
		return
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	_solid(Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	_solid(Vector3(1.2, 1, 0), Vector3(0.1, 2, 10))
	var host := _pawn()
	host.controls_enabled = true
	var client := _pawn()
	client.network_read_only = true
	client.controls_enabled = false
	var controller := CommandController.new()
	host.combat_controller.queue_free()
	host.combat_controller = controller
	host.add_child(controller)
	controller.possess(host)
	await physics_frame
	var prediction := Prediction.new()
	var states: Array[Dictionary] = [_baseline(host)]
	prediction.reconcile(client, states[0].row, states[0].motion, 0, "1:owner:1", 1000)
	var initial_clip := client.clip
	var initial_weapon_tick: int = client.weapon_clock.tick
	var peak_error := 0.0
	for tick in range(1, 181):
		var yaw := 0.0 if tick < 60 else PI / 4.0
		var command := {"movement": Vector2(1, -0.25) if tick < 130 else Vector2.ZERO,
			"jump": tick >= 30 and tick < 34, "crouch": tick >= 45 and tick < 75,
			"walk": tick >= 90 and tick < 110, "view_angles": Vector2(yaw, 0)}
		controller.next = command
		host._physics_process(0.01)
		client._apply_command_look(command)
		# Attack fields are deliberately present: prediction must strip them.
		command.fire = true
		command.fire_pressed = true
		command.reload = true
		_check(prediction.predict(client, command, tick, 0.01, 1000 + tick * 10), "fresh movement predicted at tick %d" % tick)
		states.append(_baseline(host))
		if tick % 5 == 0:
			var ack := tick - 5
			prediction.reconcile(client, states[ack].row, states[ack].motion, ack, "1:owner:1", 1000 + tick * 10)
			_check(prediction.pending.size() == 5, "50ms delayed snapshot replays only five unacknowledged steps")
		peak_error = maxf(peak_error, client.global_position.distance_to(host.global_position))
		_check(client.global_position.x < 1.0, "prediction never passes through the solid wall")
		_check(is_equal_approx(client._yaw, yaw), "replaying historical yaw preserves current aim")
	_check(peak_error < 0.002, "delayed snapshot/replay matches normal host movement (peak %.6f)" % peak_error)
	_check(client.clip == initial_clip and client.weapon_clock.tick == initial_weapon_tick and client._shot_sequence == 0,
		"prediction/replay cannot fire, reload or advance the weapon simulation")
	_check(client.network_read_only and not client.is_physics_processing() and client.collision_layer == 0,
		"prediction never enables gameplay authority or collision participation")
	var final: Dictionary = states.back()
	prediction.reconcile(client, final.row, final.motion, 180, "1:owner:1", 3000)
	_check(prediction.pending.is_empty() and client.global_position.distance_to(host.global_position) < 0.00001,
		"full acknowledgment restores exact host state")
	_check(not prediction.predict(client, {}, 180, 0.01, 3000), "acknowledged input cannot be predicted again")
	_check(not prediction.predict(client, {}, 181, 0.01, 3250), "prediction stops at the 250ms stale boundary")
	_check(not prediction.predict(client, {}, 181, 0.1, 3000), "oversized simulation steps are refused")
	for tick in range(181, 206):
		_check(prediction.predict(client, {"movement": Vector2.LEFT}, tick, 0.01, 3000), "bounded pending history accepts its capacity")
	var capped_position := client.global_position
	_check(not prediction.predict(client, {}, 206, 0.01, 3000) and prediction.pending.size() == 25
		and client.global_position == capped_position, "no acknowledgments cannot grow history or move beyond prediction horizon")
	prediction.reconcile(client, final.row, final.motion, 180, "1:owner:1", 3250)
	_check(prediction.pending.is_empty() and client.global_position == final.row.position,
		"late snapshots cannot replay expired movement after a network stall")
	prediction.predict(client, {"movement": Vector2.LEFT}, 206, 0.01, 3250)
	var teleported := final.duplicate(true)
	teleported.row.position = Vector3(-8, 0, 0)
	prediction.reconcile(client, teleported.row, teleported.motion, 180, "1:owner:1", 3260)
	_check(prediction.pending.is_empty() and client.global_position == teleported.row.position,
		"same-life authoritative teleport discards pre-teleport input")
	prediction.predict(client, {"movement": Vector2.LEFT}, 207, 0.01, 3270)
	# A newer life/epoch discards old commands instead of applying them at spawn.
	var respawn := final.duplicate(true)
	respawn.row.position = Vector3(-5, 0, 0)
	respawn.row.velocity = Vector3.ZERO
	prediction.reconcile(client, respawn.row, respawn.motion, 180, "2:owner:2", 4000)
	_check(prediction.pending.is_empty() and client.global_position == respawn.row.position,
		"new life/epoch snaps to host spawn without old input replay")
	var locked := respawn.duplicate(true)
	locked.motion.objective_locked = true
	locked.motion.objective_crouch = true
	prediction.reconcile(client, locked.row, locked.motion, 207, "2:owner:2", 4000)
	for tick in range(208, 218):
		prediction.predict(client, {"movement": Vector2.LEFT}, tick, 0.01, 4000 + tick - 208)
	_check(client.global_position.distance_to(locked.row.position) < 0.002 and client.objective_movement_locked,
		"authoritative plant/defuse movement cap remains in force during prediction")
	var frozen := respawn.duplicate(true)
	frozen.motion.enabled = false
	prediction.reconcile(client, frozen.row, frozen.motion, 206, "2:owner:2", 4100)
	_check(not prediction.predict(client, {"movement": Vector2.ONE}, 207, 0.01, 4100), "freeze/deploy movement remains host-locked")
	var dead := frozen.duplicate(true)
	dead.row.alive = false
	prediction.reconcile(client, dead.row, dead.motion, 207, "2:owner:2", 4200)
	_check(not prediction.enabled and prediction.pending.is_empty() and client.collision_mask == 0,
		"death clears prediction and map collision queries")
	prediction.clear()
	_check(prediction.pending.is_empty() and not prediction.enabled and prediction.last_ack == 0,
		"disconnect clears acknowledgment and prediction state")
	# Post-round movement is independent of attack permission and is replicated
	# through the existing motion-enabled bit (no client-only phase guess).
	host.global_position = Vector3(-5, 0, 0)
	host.velocity = Vector3.ZERO
	host.controls_enabled = false
	host.look_enabled = true
	host.post_round_movement_enabled = true
	var post := _baseline(host)
	prediction.reconcile(client, post.row, post.motion, 0, "post:owner:1", 5000)
	var start_position := host.global_position
	var clip_before := host.clip
	for tick in range(1, 21):
		controller.next = {"movement": Vector2.LEFT, "fire": true, "fire_pressed": true}
		host._physics_process(0.01)
		prediction.predict(client, controller.next, tick, 0.01, 5000 + tick * 10)
	_check(host.global_position.distance_to(start_position) > 0.05 and host.clip == clip_before,
		"survivor moves after the result without enabling post-round attacks")
	_check(client.global_position.distance_to(host.global_position) < 0.002,
		"post-round client prediction matches authoritative survivor movement")
	host.post_round_movement_enabled = false
	var next_freeze := _baseline(host)
	prediction.reconcile(client, next_freeze.row, next_freeze.motion, 20, "freeze:owner:2", 5300)
	_check(not prediction.enabled and not host.can_simulate_movement(), "next freeze locks both host and client again")
	world.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_MOVEMENT_PREDICTION_PASS peak_error=", peak_error)
	quit(0 if failures.is_empty() else 1)
