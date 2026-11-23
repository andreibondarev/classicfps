extends "res://scripts/game.gd"

## Optional fixture-only timings. Every override calls the production method;
## no simulation decisions or scheduling are substituted. Bot controllers use
## the same implementation through a timing-only subclass, configured at spawn.
var phase_cpu_events: Array[Dictionary] = []
var hostage_cpu_totals: Dictionary = {}


func _record_hostage_cpu(label: String, started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	if not hostage_cpu_totals.has(label):
		hostage_cpu_totals[label] = {"calls": 0, "total_us": 0, "max_us": 0}
	var entry: Dictionary = hostage_cpu_totals[label]
	entry.calls += 1
	entry.total_us += elapsed
	entry.max_us = maxi(entry.max_us, elapsed)


func _advance_hostages() -> void:
	var started := Time.get_ticks_usec()
	super._advance_hostages()
	_record_hostage_cpu("advance_including_sync", started)


func _sync_hostage_actors() -> void:
	var started := Time.get_ticks_usec()
	super._sync_hostage_actors()
	_record_hostage_cpu("contract_sync", started)


func _make_bot(bot_name: String, bot_team: String, bot_index: int, spawn_position: Vector3) -> TargetActor:
	var bot := super._make_bot(bot_name, bot_team, bot_index, spawn_position)
	# This runs synchronously during scene construction, before any decisions or
	# navigation preparation. Reconfigure rather than copying state containing
	# perception Callables bound to the departing controller.
	var original := bot.combat_controller
	bot.remove_child(original)
	original.free()
	var controller := preload("res://tests/profiled_bot_controller.gd").new()
	controller.name = "BotController"
	bot.add_child(controller)
	controller.configure(bot, bot.navigation_agent, bot.index)
	controller.configure_weapon(bot.active_weapon_name)
	controller.set_perception_predicates(Callable(self, "_perception_flash_blind"), Callable())
	bot.combat_controller = controller
	return bot


func bot_cpu_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for bot: TargetActor in _all_bots():
		events.append_array(bot.combat_controller.cpu_events)
	return events


func _record_phase(label: String, started: int) -> Dictionary:
	if phase_cpu_events.size() < 128:
		var event := {"phase": label, "ms": float(Time.get_ticks_usec() - started) / 1000.0,
			"engine_physics_tick": Engine.get_physics_frames(),
			"round": round_state.round_number if is_instance_valid(round_state) else round_number}
		phase_cpu_events.append(event)
		return event
	return {}


func _reset_combatants_for_round(keep_surviving_loadouts := true) -> void:
	var started := Time.get_ticks_usec()
	super._reset_combatants_for_round(keep_surviving_loadouts)
	var event := _record_phase("reset_combatants", started)
	event["viewmodel_last_load"] = player.viewmodel.last_load_timings.duplicate()


func _apply_bot_round_buy(carried_loadouts: Dictionary, next_round: int) -> void:
	var known_templates := MdlCharacterModel._template_cache.keys()
	var started := Time.get_ticks_usec()
	super._apply_bot_round_buy(carried_loadouts, next_round)
	var event := _record_phase("bot_round_buy", started)
	var new_templates: Array[String] = []
	for path: String in MdlCharacterModel._template_cache:
		if not known_templates.has(path):
			new_templates.append(path)
	event["new_template_paths"] = new_templates


func _apply_round_phase(next_phase: String) -> void:
	var started := Time.get_ticks_usec()
	super._apply_round_phase(next_phase)
	_record_phase("apply_phase:" + next_phase, started)


func _consume_round_events(events: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	super._consume_round_events(events)
	if Time.get_ticks_usec() - started > 15000:
		_record_phase("consume_round_events", started)


func _physics_process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	super._physics_process(delta)
	if Time.get_ticks_usec() - started > 15000:
		_record_phase("game_physics", started)
