extends SceneTree

## Records promo footage: a bot match (Dust2 unless --map=) where the human player is played by
## the live match driver, so the camera is a real first-person view with HUD.
## Run under Movie Maker, e.g.
##   godot --path game --write-movie /tmp/promo.avi --fixed-fps 60 \
##     --resolution 1920x1080 --script res://tests/promo_capture.gd -- --seconds=180
## Prints PROMO_EVENT lines (frame, kind, detail) so an editor can find kills.

var _frame := 0
var _seconds := 180.0
var _game: Node
var _map := "de_dust2"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			_map = argument.get_slice("=", 1)
		elif argument.begins_with("--seconds="):
			_seconds = float(argument.get_slice("=", 1))
	_run.call_deferred()


func _event(kind: String, detail: String) -> void:
	print("PROMO_EVENT frame=%d kind=%s %s" % [_frame, kind, detail])


func _run() -> void:
	_game = preload("res://scripts/game.gd").new()
	_game.map_name = _map
	root.add_child(_game)
	current_scene = _game
	await process_frame
	await physics_frame
	if not _game.combat_effects.presentation_is_ready:
		await _game.combat_effects.presentation_ready
	_game._on_team_selected(1)
	_game._on_class_selected(1)
	var driver := preload("res://tests/live_match_driver.gd").new()
	driver.game = _game
	_game.player.add_child(driver)
	_game.player.combat_controller.queue_free()
	driver.possess(_game.player)
	_game.player.combat_controller = driver
	driver.prepare_navigation()
	driver.planner.reset_tactics()
	_game.start_match()
	var last_phase := ""
	var bought_round := -1
	var end_frame := int(_seconds * 60.0)  # --fixed-fps 60
	var alive := {}
	while _frame < end_frame:
		await process_frame
		_frame += 1
		var phase := str(_game.phase)
		if phase != last_phase:
			_event("phase", "phase=%s round=%d" % [phase, int(_game.round_state.round_number)])
			last_phase = phase
		for actor: Combatant in [_game.player] + _game._all_bots():
			var id := actor.get_instance_id()
			if alive.get(id, false) and not actor.alive:
				var by_player: bool = actor.last_damage_attacker == _game.player
				_event("death", "victim=%s by_player=%s player_alive=%s" % [actor.name, by_player, _game.player.alive])
			alive[id] = actor.alive
		var round_number := int(_game.round_state.round_number)
		if phase == "freeze" and bought_round != round_number:
			bought_round = round_number
			for id: String in _game.round_state.players:
				_game.round_state.players[id].money = 16000
			_game.money = 16000
			for item in ["ak47", "assaultsuit", "hegrenade", "flashbang", "smokegrenade"]:
				_game._on_buy_item_requested(item)
	_event("done", "")
	quit()
