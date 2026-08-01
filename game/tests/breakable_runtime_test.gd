extends SceneTree

const EntityWorld := preload("res://scripts/cs16_entity_world.gd")
const BreakableRuntime := preload("res://scripts/cs16_breakable_runtime.gd")
const BspMapScript := preload("res://scripts/bsp_map.gd")
const ASSAULT_MAP := "res://generated/cs_assault/map.json"

var failures: Array[String] = []
var observed: Array[Dictionary] = []


class FakeBrushMap:
	extends RefCounted

	var entities: Array = []
	var entity_models: Dictionary = {}
	var bounds: Dictionary = {}
	var transforms: Dictionary = {}
	var active: Dictionary = {}

	func add_model(entity_id: int, model_index: int, model_bounds: AABB) -> void:
		entity_models[entity_id] = model_index
		bounds[model_index] = model_bounds
		transforms[model_index] = Transform3D.IDENTITY
		active[model_index] = true

	func model_index_for_entity(entity_id: int) -> int:
		return int(entity_models.get(entity_id, -1))

	func model_root(model_index: int) -> Variant:
		return self if bounds.has(model_index) else null

	func initial_transform_for_model(model_index: int) -> Transform3D:
		return transforms.get(model_index, Transform3D.IDENTITY)

	func model_bounds_for_index(model_index: int) -> AABB:
		return bounds.get(model_index, AABB())

	func set_model_runtime_active(model_index: int, value: bool) -> bool:
		if not bounds.has(model_index):
			return false
		active[model_index] = value
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_assert_damage_material_and_trigger_contracts()
	_assert_touch_pressure_reset_and_determinism()
	await _assert_assault_breakables()
	if failures.is_empty():
		print("BREAKABLE_RUNTIME_TEST_PASS")
		quit(0)
	else:
		print("BREAKABLE_RUNTIME_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BREAKABLE RUNTIME TEST: " + message)


func _capture(event: Dictionary) -> void:
	observed.append(event)


func _resolve_actor_id(actor: Variant) -> int:
	if actor is Object and (actor as Object).has_meta("stable_actor_id"):
		return int((actor as Object).get_meta("stable_actor_id"))
	return -1


func _raw_entity(
	entity_index: int,
	classname: String,
	properties: Array = [],
) -> Dictionary:
	var ordered := [["classname", classname]]
	ordered.append_array(properties)
	return {
		"entity_index": entity_index,
		"classname": classname,
		"properties": ordered,
	}


func _event(runtime: RefCounted, name: String, entity_id := -1) -> Dictionary:
	for event: Dictionary in runtime.events:
		if (
			str(event.get("event", "")) == name
			and (entity_id < 0 or int(event.get("entity_id", -1)) == entity_id)
		):
			return event
	return {}


func _make_runtime(fake: FakeBrushMap) -> Array:
	var world := EntityWorld.new()
	world.load_entities(fake.entities)
	var runtime := BreakableRuntime.new()
	runtime.configure(fake, world)
	return [world, runtime]


func _assert_damage_material_and_trigger_contracts() -> void:
	observed.clear()
	var fake := FakeBrushMap.new()
	fake.entities = [
		_raw_entity(
			0,
			"func_breakable",
			[
				["model", "*1"],
				["material", "1"],
				["health", "100"],
				["target", "broken_target"],
			],
		),
		_raw_entity(1, "info_target", [["targetname", "broken_target"]]),
		_raw_entity(
			2,
			"func_breakable",
			[
				["model", "*2"],
				["material", "1"],
				["health", "20"],
				["spawnflags", "1"],
			],
		),
		_raw_entity(
			3,
			"func_breakable",
			[
				["model", "*3"],
				["material", "7"],
				["health", "5"],
			],
		),
		_raw_entity(
			4,
			"func_breakable",
			[
				["model", "*4"],
				["material", "2"],
				["health", "40"],
				["spawnflags", "256"],
			],
		),
	]
	for entity_id in [0, 2, 3, 4]:
		fake.add_model(
			entity_id,
			entity_id + 1,
			AABB(Vector3(-0.5, -0.25, -0.1), Vector3(1.0, 0.5, 0.2)),
		)
	var pair := _make_runtime(fake)
	var world = pair[0]
	var runtime = pair[1]
	world.bind_handler(1, Callable(self, "_capture"))

	var poison: Dictionary = runtime.damage(
		0,
		10,
		10,
		50.0,
		BreakableRuntime.DMG_POISON,
	)
	_check(
		poison.accepted
		and is_equal_approx(float(poison.applied_damage), 5.0)
		and is_equal_approx(float(poison.remaining_health), 95.0),
		"poison damage is reduced to exactly ten percent",
	)
	var club: Dictionary = runtime.damage(
		0,
		10,
		10,
		10.0,
		BreakableRuntime.DMG_CLUB,
	)
	_check(
		is_equal_approx(float(club.applied_damage), 20.0)
		and is_equal_approx(float(club.remaining_health), 75.0),
		"club damage is doubled before health subtraction",
	)
	var bullet: Dictionary = runtime.damage(
		0,
		10,
		11,
		75.0,
		BreakableRuntime.DMG_BULLET,
		Vector3.RIGHT,
	)
	_check(
		bullet.broken
		and not bool(runtime.get_breakable(0).alive)
		and not bool(fake.active[1]),
		"fatal bullet damage removes visibility and collision presence",
	)
	_check(
		observed.size() == 1 and int(observed[0].activator_id) == -1,
		"fatal break emits its target exactly once with GoldSrc's null activator",
	)
	var wood_debris := _event(runtime, "debris", 0)
	_check(
		wood_debris.gib_model == "models/woodgibs.mdl"
		and int(wood_debris.break_flag) == BreakableRuntime.BREAK_WOOD
		and int(wood_debris.randomization) == 10
		and int(wood_debris.shard_count) == 0
		and is_equal_approx(float(wood_debris.duration_seconds), 2.5),
		"wood break emits the complete GoldSrc TE_BREAKMODEL descriptor",
	)

	var trigger_damage: Dictionary = runtime.damage(
		2,
		10,
		10,
		100.0,
		BreakableRuntime.DMG_BULLET,
	)
	_check(
		not bool(trigger_damage.accepted) and bool(runtime.get_breakable(2).alive),
		"TRIGGER_ONLY rejects ordinary damage",
	)
	_check(
		runtime.trigger(2, 10) and not bool(runtime.get_breakable(2).alive),
		"TRIGGER_ONLY still breaks from entity use",
	)
	_check(
		not runtime.damage(
			3,
			10,
			10,
			1000.0,
			BreakableRuntime.DMG_BLAST,
		).accepted
		and not runtime.trigger(3, 10)
		and bool(runtime.get_breakable(3).alive),
		"material 7 remains unbreakable glass for damage and triggers",
	)
	var crowbar: Dictionary = runtime.damage(
		4,
		10,
		10,
		1.0,
		BreakableRuntime.DMG_CLUB,
	)
	_check(
		crowbar.broken
		and is_equal_approx(float(crowbar.applied_damage), 80.0),
		"CROWBAR flag promotes a client club hit to health then applies source double damage",
	)


func _assert_touch_pressure_reset_and_determinism() -> void:
	var fake := FakeBrushMap.new()
	fake.entities = [
		_raw_entity(
			0,
			"func_breakable",
			[
				["model", "*1"],
				["material", "2"],
				["health", "5"],
				["spawnflags", "2"],
			],
		),
		_raw_entity(
			1,
			"func_breakable",
			[
				["model", "*2"],
				["material", "4"],
				["health", "10"],
				["spawnflags", "4"],
				["delay", "0.02"],
				["target", "pressure_done"],
			],
		),
		_raw_entity(
			2,
			"func_breakable",
			[
				["model", "*3"],
				["material", "6"],
				["health", "10"],
				["explosion", "directed"],
				["explodemagnitude", "40"],
				["spawnobject", "31"],
			],
		),
		_raw_entity(3, "info_target", [["targetname", "pressure_done"]]),
	]
	for entity_id in range(3):
		fake.add_model(
			entity_id,
			entity_id + 1,
			AABB(Vector3.ZERO, Vector3(0.4, 0.5, 0.6)),
		)
	var pair := _make_runtime(fake)
	var world = pair[0]
	var runtime = pair[1]
	_check(
		runtime.touch(0, 20, Vector3(499.0, 0.0, 0.0))
		== false
		and bool(runtime.get_breakable(0).alive),
		"crash-through requires speed*0.01 to meet remaining health",
	)
	_check(
		runtime.touch(0, 20, Vector3(500.0, 0.0, 0.0))
		and not bool(runtime.get_breakable(0).alive),
		"TOUCH glass/metal breaks at the exact velocity-derived threshold",
	)
	var player_damage := _event(runtime, "touch_player_damage", 0)
	_check(
		is_equal_approx(float(player_damage.damage), 1.25)
		and int(player_damage.damage_bits) == BreakableRuntime.DMG_SLASH,
		"crash-through reports source quarter-damage slash feedback",
	)
	_check(
		runtime.touch(1, 20, Vector3.ZERO, true),
		"PRESSURE touch arms a deterministic delayed break",
	)
	runtime.advance_tick()
	_check(bool(runtime.get_breakable(1).alive), "pressure delay does not fire early")
	runtime.advance_tick()
	_check(
		not bool(runtime.get_breakable(1).alive)
		and int(_event(runtime, "break", 1).tick) == 2,
		"pressure break fires on its exact 100 Hz deadline",
	)
	var pressure_target_tick := -1
	runtime.advance_ticks(2)
	for event: Dictionary in world.trace:
		if event.event == "use" and int(event.entity_id) == 3:
			pressure_target_tick = int(event.tick)
	_check(
		pressure_target_tick == 4,
		"pressure break preserves its CBaseDelay before endpoint target output",
	)
	runtime.damage(
		2,
		30,
		31,
		10.0,
		BreakableRuntime.DMG_BULLET,
		Vector3(0.0, 0.0, -1.0),
	)
	var directed := _event(runtime, "debris", 2)
	_check(
		(directed.velocity as Vector3).is_equal_approx(Vector3(0.0, 0.0, -2.0))
		and directed.gib_model == "models/computergibs.mdl"
		and directed.break_flag_name == "metal",
		"directed computer debris uses attack direction, 200 HU/s, computer gibs, and metal flags",
	)
	_check(
		_event(runtime, "explosion", 2).magnitude == 40
		and _event(runtime, "spawn_object", 2).classname == "weapon_flashbang",
		"explosion magnitude and bounded spawn-object table produce explicit events",
	)

	var first_debris := directed.duplicate(true)
	runtime.reset_round()
	_check(
		world.tick == 0
		and bool(runtime.get_breakable(0).alive)
		and is_equal_approx(float(runtime.get_breakable(0).health), 5.0)
		and bool(fake.active[1])
		and bool(fake.active[2])
		and bool(fake.active[3]),
		"round reset restores health, model presence, collision presence, and clock",
	)
	runtime.damage(
		2,
		30,
		31,
		10.0,
		BreakableRuntime.DMG_BULLET,
		Vector3(0.0, 0.0, -1.0),
	)
	var replay_debris := _event(runtime, "debris", 2)
	_check(
		int(replay_debris.seed) == int(first_debris.seed)
		and replay_debris.velocity == first_debris.velocity
		and replay_debris.gib_model == first_debris.gib_model,
		"debris descriptors replay identically after round reset",
	)


func _assert_assault_breakables() -> void:
	observed.clear()
	var assault := BspMapScript.new()
	assault.name = "AssaultBreakableRuntimeTest"
	root.add_child(assault)
	_check(assault.load_map(ASSAULT_MAP), "converted stock cs_assault loads")
	if assault.entities.is_empty():
		assault.queue_free()
		await process_frame
		return
	var world := EntityWorld.new()
	world.load_entities(assault.entities)
	var runtime := BreakableRuntime.new()
	_check(
		runtime.configure(assault, world) == 12,
		"Assault exposes all twelve func_breakable BSP entities",
	)
	_check(
		runtime.bind_collision_bodies(Callable(self, "_resolve_actor_id")) == 12,
		"all Assault breakables bind their real imported collision bodies",
	)
	var proxy_body := assault.model_collision_body(61)
	var proxy_face_count := (
		(
			(proxy_body.get_child(0) as CollisionShape3D).shape
			as ConcavePolygonShape3D
		).get_faces().size()
	)
	_check(
		proxy_body.has_method("receive_bullet_damage")
		and proxy_body.has_method("apply_damage")
		and int(proxy_body.get_meta("cs16_breakable_entity_id", -1)) == 114
		and proxy_face_count > 0,
		"collision adapter preserves authentic concave geometry and exposes bullet/knife entry points",
	)
	var attacker := Node3D.new()
	attacker.set_meta("stable_actor_id", 4242)
	attacker.position = Vector3(1.0, 1.0, 1.0)
	root.add_child(attacker)
	var proxy_bullet: Dictionary = proxy_body.call(
		"receive_bullet_damage",
		24,
		0,
		"ak47",
		Vector3.ZERO,
		attacker,
	)
	_check(
		proxy_bullet.accepted
		and is_equal_approx(float(proxy_bullet.remaining_health), 1.0),
		"real collision proxy forwards bullet damage with stable actor resolution",
	)
	var proxy_knife: Dictionary = proxy_body.call(
		"apply_damage",
		15.0,
		Vector3.ZERO,
		false,
		attacker,
	)
	_check(
		proxy_knife.broken
		and is_equal_approx(float(proxy_knife.applied_damage), 30.0)
		and int(_event(runtime, "break", 114).activator_id) == 4242,
		"knife proxy uses DMG_CLUB double damage and preserves the stable attacker id",
	)
	attacker.queue_free()
	var material_counts := {}
	for entity_id in [79, 84, 85, 86, 114, 115, 116, 119, 120, 140, 158, 159]:
		var material := int(runtime.get_breakable(entity_id).material)
		material_counts[material] = int(material_counts.get(material, 0)) + 1
	_check(
		int(material_counts.get(BreakableRuntime.MAT_GLASS, 0)) == 6
		and int(material_counts.get(BreakableRuntime.MAT_WOOD, 0)) == 1
		and int(material_counts.get(BreakableRuntime.MAT_METAL, 0)) == 1
		and int(material_counts.get(BreakableRuntime.MAT_COMPUTER, 0)) == 1
		and int(material_counts.get(BreakableRuntime.MAT_UNBREAKABLE_GLASS, 0)) == 3,
		"Assault material roster matches the twelve authored brushes exactly",
	)

	var computer: Dictionary = runtime.get_breakable(79)
	_check(
		computer.model_index == 54
		and is_equal_approx(float(computer.health), 550.0)
		and int(computer.explosion_magnitude) == 40
		and computer.material_name == "computer",
		"Assault spy computer preserves model, 550 health, material, and explosion magnitude",
	)
	var computer_root := assault.model_root(54)
	var computer_body := assault.model_collision_body(54)
	_check(
		computer_root.visible
		and assault.model_runtime_active(54)
		and computer_body.collision_layer == 1,
		"Assault spy computer starts visible and collidable",
	)
	var almost: Dictionary = runtime.damage(
		79,
		200,
		200,
		549.0,
		BreakableRuntime.DMG_BULLET,
	)
	_check(
		not almost.broken
		and is_equal_approx(float(almost.remaining_health), 1.0)
		and _event(runtime, "damage", 79).sound.begins_with("debris/glass"),
		"Assault computer survives at one health and uses source glass impact sounds",
	)
	runtime.damage(
		79,
		200,
		200,
		1.0,
		BreakableRuntime.DMG_BULLET,
		Vector3.RIGHT,
	)
	_check(
		not computer_root.visible
		and not assault.model_runtime_active(54)
		and computer_body.collision_layer == 0,
		"destroyed Assault computer removes both BSP visuals and collision",
	)
	var computer_debris := _event(runtime, "debris", 79)
	_check(
		computer_debris.gib_model == "models/computergibs.mdl"
		and int(computer_debris.break_flag) == BreakableRuntime.BREAK_METAL,
		"Assault computer emits source computer gibs with metal break semantics",
	)
	_check(
		int(_event(runtime, "explosion", 79).magnitude) == 40,
		"Assault computer emits its authored explosion descriptor",
	)
	var relay_uses := 0
	for event: Dictionary in world.trace:
		if event.event == "use" and int(event.entity_id) == 80:
			relay_uses += 1
	_check(
		relay_uses == 1,
		"Assault computer fires spy_dev_destroyed exactly once when it breaks",
	)

	var unbreakable_damage: Dictionary = runtime.damage(
		120,
		200,
		200,
		1000.0,
		BreakableRuntime.DMG_BLAST,
	)
	_check(
		not unbreakable_damage.accepted
		and bool(runtime.get_breakable(120).alive)
		and assault.model_runtime_active(67),
		"Assault material-7 pane stays intact under arbitrary damage",
	)
	_check(
		runtime.touch(140, 201, Vector3(500.0, 0.0, 0.0))
		and not bool(runtime.get_breakable(140).alive)
		and not assault.model_runtime_active(77),
		"Assault spawnflag-2 metal grate breaks at its exact five-health crash threshold",
	)
	runtime.damage(
		84,
		202,
		202,
		15.0,
		BreakableRuntime.DMG_BULLET,
	)
	_check(
		_event(runtime, "debris", 84).gib_model == "models/glassgibs.mdl"
		and not assault.model_runtime_active(56),
		"Assault glass model 56 produces glass debris and leaves BSP collision",
	)

	runtime.reset_round()
	_check(
		is_equal_approx(float(runtime.get_breakable(79).health), 550.0)
		and assault.model_runtime_active(54)
		and computer_root.visible
		and computer_body.collision_layer == 1
		and assault.model_runtime_active(77)
		and assault.model_runtime_active(56),
		"Assault round reset restores every destroyed brush and original collision layer",
	)
	assault.queue_free()
	await process_frame
