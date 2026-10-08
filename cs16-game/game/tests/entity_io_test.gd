extends SceneTree

const EntityWorld := preload("res://scripts/cs16_entity_world.gd")

var failures: Array[String] = []
var observed: Array[Dictionary] = []
var recursion_uses := 0


func _initialize() -> void:
	_assert_bsp_identity_and_keyvalues()
	_assert_target_and_killtarget_order()
	_assert_use_types_master_and_triggerstate()
	_assert_input_capabilities_and_tick_order()
	_assert_delay_wait_and_one_shot()
	_assert_recursion_guard()
	_assert_round_snapshot_reset()
	if failures.is_empty():
		print("GAME_ENTITY_IO_TEST_PASS")
		quit(0)
	else:
		print("GAME_ENTITY_IO_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("ENTITY I/O TEST: " + message)


func _entity(
	classname: String,
	properties: Array = [],
	capabilities: int = EntityWorld.DEFAULT_CAPABILITIES,
	state := false,
) -> Dictionary:
	var ordered := [["classname", classname]]
	ordered.append_array(properties)
	return {
		"classname": classname,
		"properties": ordered,
		"capabilities": capabilities,
		"state": state,
	}


func _capture(event: Dictionary) -> void:
	observed.append(event)


func _capture_recursion(_event: Dictionary) -> void:
	recursion_uses += 1


func _trace_events(world: RefCounted, event_name: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for event: Dictionary in world.trace:
		if str(event.get("event", "")) == event_name:
			matches.append(event)
	return matches


func _assert_bsp_identity_and_keyvalues() -> void:
	var world := EntityWorld.new()
	world.load_entities([
		_entity("worldspawn", [["message", "first"], ["message", "last"]], 0),
		_entity("info_player_start", [["targetname", "spawn_a"]], 0),
		_entity("info_player_start", [["targetname", "spawn_a"]], 0),
	])
	_check(world.entity_count() == 3, "load preserves every BSP entity")
	_check(
		world.get_entity(0).id == 0
		and world.get_entity(1).id == 1
		and world.get_entity(2).bsp_order == 2,
		"entity ids are stable zero-based BSP order",
	)
	_check(
		world.get_entity(0).keyvalues == [
			["classname", "worldspawn"],
			["message", "first"],
			["message", "last"],
		],
		"ordered keyvalues preserve duplicates without dictionary collapse",
	)
	_check(
		world.keyvalue(0, "message") == "last",
		"keyvalue lookup returns the final parsed duplicate",
	)
	_check(
		world.find_by_targetname("spawn_a") == [1, 2],
		"targetname lookup follows BSP order",
	)


func _assert_target_and_killtarget_order() -> void:
	observed.clear()
	var world := EntityWorld.new()
	world.load_entities([
		_entity(
			"trigger_relay",
			[["target", "fanout"], ["killtarget", "doomed"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity("info_target", [["targetname", "doomed"]], 0),
		_entity("info_target", [["targetname", "fanout"]], 0),
		_entity("info_target", [["targetname", "fanout"]], 0),
	])
	world.bind_handler(2, Callable(self, "_capture"))
	world.bind_handler(3, Callable(self, "_capture"))
	_check(
		world.use_entity(0, 50, 50, EntityWorld.USE_TOGGLE),
		"a relay accepts an explicit use",
	)
	_check(
		not bool(world.get_entity(1).alive),
		"killtarget removes every matching live entity",
	)
	_check(
		observed.size() == 2
		and int(observed[0].entity_id) == 2
		and int(observed[1].entity_id) == 3,
		"target fan-out invokes recipients in BSP order",
	)
	var killed := _trace_events(world, "killed")
	var uses := _trace_events(world, "use")
	_check(
		killed.size() == 1
		and uses.size() == 3
		and int(killed[0].sequence) < int(uses[1].sequence),
		"killtarget resolves before target firing",
	)


func _assert_use_types_master_and_triggerstate() -> void:
	observed.clear()
	var stateful := EntityWorld.CAP_STATEFUL
	var world := EntityWorld.new()
	world.load_entities([
		_entity(
			"multisource",
			[["targetname", "power"]],
			EntityWorld.CAP_MASTER | EntityWorld.CAP_STATEFUL,
		),
		_entity(
			"trigger_relay",
			[["master", "power"], ["target", "lamp"], ["triggerstate", "2"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity("env_global", [["targetname", "lamp"]], stateful),
		_entity(
			"trigger_relay",
			[["target", "lamp"], ["triggerstate", "0"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity(
			"trigger_relay",
			[["target", "lamp"], ["triggerstate", "1"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
	])
	world.bind_handler(2, Callable(self, "_capture"))

	_check(
		not world.use_entity(1, 20, 20, EntityWorld.USE_ON),
		"a false master blocks a dependent entity",
	)
	_check(_trace_events(world, "master_blocked").size() == 1, "master block is observable")
	world.set_entity_state(0, true)
	world.use_entity(1, 20, 20, EntityWorld.USE_OFF)
	_check(
		bool(world.get_entity(2).state),
		"triggerstate 2 converts an incoming use to USE_TOGGLE",
	)
	world.use_entity(1, 20, 20, EntityWorld.USE_OFF)
	_check(
		not bool(world.get_entity(2).state),
		"repeated triggerstate toggle reverses state",
	)
	world.set_entity_state(2, true)
	world.use_entity(3, 20, 20, EntityWorld.USE_TOGGLE)
	_check(
		not bool(world.get_entity(2).state),
		"triggerstate 0 forces USE_OFF",
	)
	world.use_entity(4, 20, 20, EntityWorld.USE_OFF)
	_check(
		bool(world.get_entity(2).state),
		"triggerstate 1 forces USE_ON",
	)

	_check(
		not world.use_entity(2, 20, 20, EntityWorld.USE_ON),
		"USE_ON is ignored when a stateful entity is already on",
	)
	_check(
		world.use_entity(2, 20, 20, EntityWorld.USE_SET, 0.0)
		and not bool(world.get_entity(2).state),
		"USE_SET always dispatches and derives state from its value",
	)
	_check(
		not world.use_entity(2, 20, 20, EntityWorld.USE_OFF),
		"USE_OFF is ignored when a stateful entity is already off",
	)
	_check(
		world.use_entity(2, 20, 20, EntityWorld.USE_TOGGLE)
		and bool(world.get_entity(2).state),
		"USE_TOGGLE always inverts state",
	)
	_check(
		world.has_capability(0, EntityWorld.CAP_MASTER)
		and not world.has_capability(1, EntityWorld.CAP_MASTER),
		"generic capability queries distinguish master providers",
	)


func _assert_input_capabilities_and_tick_order() -> void:
	observed.clear()
	var caps := (
		EntityWorld.CAP_USE_PRESSED
		| EntityWorld.CAP_USE_RELEASED
		| EntityWorld.CAP_TOUCH
	)
	var world := EntityWorld.new()
	world.load_entities([_entity("func_button", [], caps)])
	world.bind_handler(0, Callable(self, "_capture"))
	_check(world.queue_use(0, 7, EntityWorld.INPUT_PRESSED), "pressed capability queues")
	_check(
		not world.queue_use(0, 7, EntityWorld.INPUT_HELD),
		"held input is rejected without CAP_USE_HELD",
	)
	_check(world.queue_touch(0, 8, EntityWorld.TOUCH_ENTER), "touch capability queues")
	_check(world.queue_use(0, 7, EntityWorld.INPUT_RELEASED), "released capability queues")
	_check(observed.is_empty(), "queued input never dispatches between simulation ticks")
	world.advance_tick()
	_check(
		observed.size() == 3
		and observed[0].source_kind == "use_input"
		and observed[0].phase == EntityWorld.INPUT_PRESSED
		and observed[1].source_kind == "touch_input"
		and observed[1].phase == EntityWorld.TOUCH_ENTER
		and observed[2].phase == EntityWorld.INPUT_RELEASED,
		"touch/use dispatch shares one deterministic enqueue order",
	)
	_check(
		int(observed[0].tick) == 1
		and int(observed[1].tick) == 1
		and int(observed[2].tick) == 1,
		"queued input dispatches on a fixed 100 Hz tick",
	)
	_check(
		int(observed[0].use_type) == EntityWorld.USE_SET
		and is_equal_approx(float(observed[0].value), 1.0)
		and is_equal_approx(float(observed[2].value), 0.0),
		"pressed and released map to USE_SET(1) and USE_SET(0)",
	)


func _assert_delay_wait_and_one_shot() -> void:
	observed.clear()
	var world := EntityWorld.new()
	world.load_entities([
		_entity(
			"trigger_multiple",
			[["target", "delayed"], ["delay", "0.02"], ["wait", "0.03"]],
			EntityWorld.CAP_USE_PRESSED | EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity("info_target", [["targetname", "delayed"]], 0),
		_entity(
			"trigger_once",
			[["target", "once"], ["wait", "-1"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity("info_target", [["targetname", "once"]], 0),
	])
	world.bind_handler(1, Callable(self, "_capture"))
	world.bind_handler(3, Callable(self, "_capture"))

	world.queue_use(0, 9, EntityWorld.INPUT_PRESSED)
	world.queue_use(0, 9, EntityWorld.INPUT_PRESSED)
	world.advance_tick()
	_check(
		_trace_events(world, "scheduled").size() == 1
		and _trace_events(world, "wait_blocked").size() == 1,
		"wait gates a second activation on the same tick",
	)
	world.queue_use(0, 9, EntityWorld.INPUT_PRESSED)
	world.advance_tick()
	_check(
		observed.is_empty(),
		"a two-tick delay does not fire one tick early",
	)
	world.queue_use(0, 9, EntityWorld.INPUT_PRESSED)
	var tick_three_trace := world.advance_tick()
	_check(
		observed.size() == 1
		and int(observed[0].entity_id) == 1
		and int(observed[0].tick) == 3,
		"delayed targets fire on the exact 100 Hz deadline",
	)
	var delayed_index := -1
	var blocked_index := -1
	for index in range(tick_three_trace.size()):
		if tick_three_trace[index].event == "use" and delayed_index < 0:
			delayed_index = index
		elif tick_three_trace[index].event == "wait_blocked":
			blocked_index = index
	_check(
		delayed_index >= 0 and blocked_index > delayed_index,
		"due delayed fires resolve before new input on the same tick",
	)
	world.advance_tick()
	world.queue_use(0, 9, EntityWorld.INPUT_PRESSED)
	world.advance_tick()
	_check(
		_trace_events(world, "scheduled").size() == 2,
		"positive wait re-arms exactly at its ready tick",
	)

	observed.clear()
	_check(world.use_entity(2, 9, 9, EntityWorld.USE_TOGGLE), "negative wait fires once")
	_check(
		not world.use_entity(2, 9, 9, EntityWorld.USE_TOGGLE)
		and observed.size() == 1,
		"negative wait permanently disables the entity until round reset",
	)

	observed.clear()
	var stable_world := EntityWorld.new()
	stable_world.load_entities([
		_entity(
			"trigger_relay",
			[["target", "a"], ["delay", "0.01"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity(
			"trigger_relay",
			[["target", "b"], ["delay", "0.01"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity("info_target", [["targetname", "a"]], 0),
		_entity("info_target", [["targetname", "b"]], 0),
	])
	stable_world.bind_handler(2, Callable(self, "_capture"))
	stable_world.bind_handler(3, Callable(self, "_capture"))
	stable_world.use_entity(0, 9, 9, EntityWorld.USE_ON)
	stable_world.use_entity(1, 9, 9, EntityWorld.USE_ON)
	stable_world.advance_tick()
	_check(
		observed.size() == 2
		and int(observed[0].entity_id) == 2
		and int(observed[1].entity_id) == 3,
		"same-deadline delayed fires preserve schedule order",
	)


func _assert_recursion_guard() -> void:
	recursion_uses = 0
	var world := EntityWorld.new()
	world.load_entities([
		_entity(
			"trigger_relay",
			[["targetname", "loop"], ["target", "loop"]],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
	])
	world.bind_handler(0, Callable(self, "_capture_recursion"))
	world.fire_targets("loop", 1, 1, EntityWorld.USE_TOGGLE)
	_check(
		recursion_uses == EntityWorld.MAX_RECURSION_DEPTH,
		"recursive target chains are capped at exactly 128 invocations",
	)
	_check(
		_trace_events(world, "recursion_blocked").size() == 1,
		"recursion guard terminates and traces the rejected 129th fire",
	)


func _assert_round_snapshot_reset() -> void:
	observed.clear()
	var world := EntityWorld.new()
	world.load_entities([
		_entity(
			"trigger_once",
			[
				["target", "recipient"],
				["killtarget", "victim"],
				["delay", "0.05"],
				["wait", "-1"],
			],
			EntityWorld.CAP_FIRE_OUTPUTS,
		),
		_entity("info_target", [["targetname", "victim"]], 0),
		_entity(
			"env_global",
			[["targetname", "recipient"]],
			EntityWorld.CAP_STATEFUL,
			true,
		),
	])
	world.set_runtime_value(2, "counter", 4)
	world.capture_round_start()
	world.bind_handler(2, Callable(self, "_capture"))
	world.use_entity(0, 3, 3, EntityWorld.USE_OFF)
	world.set_entity_state(2, false)
	world.set_runtime_value(2, "counter", 99)
	world.queue_use(0, 3, EntityWorld.INPUT_PRESSED)
	world.reset_round()
	_check(
		world.tick == 0
		and bool(world.get_entity(0).enabled)
		and bool(world.get_entity(1).alive)
		and bool(world.get_entity(2).state)
		and int(world.runtime_value(2, "counter")) == 4,
		"round reset restores enabled/alive/state/runtime snapshot data",
	)
	world.advance_ticks(10)
	_check(
		observed.is_empty(),
		"round reset clears queued input and delayed target fires",
	)
	world.use_entity(2, 3, 3, EntityWorld.USE_SET, 0.0)
	_check(
		observed.size() == 1,
		"handler bindings survive round reset",
	)
