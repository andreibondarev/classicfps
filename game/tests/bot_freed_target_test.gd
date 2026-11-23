extends SceneTree

## Regression: a remote player whom bots are tracking disconnects and is
## freed mid-round. Bots must forget the stale reference instead of casting it
## (which crashed the release dedicated server on Oct 9 2026).
## Run with: -- --dedicated --port=<free port>

const PerceptionScript = preload("res://scripts/cs16_bot_perception.gd")
const BotControllerScript = preload("res://scripts/bot_controller.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOT FREED TARGET: " + message)


func _run() -> void:
	# Unit level: perception forgets a freed target and damage source.
	var perception := PerceptionScript.new()
	var doomed := Node3D.new()
	perception.current_target = doomed
	perception.current_target_id = "doomed"
	perception.visible = true
	perception._damage_source = doomed
	doomed.free()
	perception.advance_ticks(1, Vector3.ZERO, Vector3.FORWARD)
	_check(perception.current_target == null and perception.current_target_id.is_empty() and not perception.visible,
		"perception clears a freed target")
	_check(perception._damage_source == null, "perception clears a freed damage source")
	var freed := Node.new()
	freed.free()
	_check(BotControllerScript._live_combatant(freed) == null, "a freed reference never casts")

	# Game level: bots tracking a player who disconnects keep running.
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	var network := root.get_node("NetworkSession")
	network._register_input_peer(777, Time.get_ticks_msec())
	game.remote_roster._on_peer_joined(777)
	game.select_remote_join_team(777, "T")
	game.select_remote_join_class(777, 1)
	var human: PlayerController = game._remote_join_actor(777)
	_check(is_instance_valid(human), "remote player joined")
	var hunters: Array = []
	for bot: TargetActor in game._all_bots():
		if bot.team == "CT" and bot.combat_controller is BotCombatController:
			var controller := bot.combat_controller as BotCombatController
			controller.perception.current_target = human
			controller.perception.current_target_id = str(human.name)
			controller.perception.visible = true
			hunters.append(bot)
	_check(not hunters.is_empty(), "CT bots are tracking the player")
	network._remove_input_peer(777)
	game.remote_roster._on_peer_left(777)
	for frame in range(10):
		await physics_frame
	_check(not is_instance_valid(human), "the disconnected player's actor was freed")
	var cleared := true
	for bot: TargetActor in hunters:
		if not is_instance_valid(bot):
			continue
		var controller := bot.combat_controller as BotCombatController
		var command: Dictionary = controller.gather_command(1.0 / 100.0)
		cleared = cleared and controller.perception.current_target_id.is_empty() and command.has("weapon_clip")
	_check(cleared, "bots dropped the stale target and still produce full commands")

	network.disconnect_session()
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("GAME_BOT_FREED_TARGET_PASS")
	quit(0 if failures.is_empty() else 1)
