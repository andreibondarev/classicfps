extends SceneTree

const TICK_COUNT := 1000
const TICK_RATE_HZ := 100
const HULL_WIDTH := 32.0 * 0.01
const HULL_HEIGHT := 72.0 * 0.01
const HULL_HALF_WIDTH := HULL_WIDTH * 0.5
const FLOOR_TOLERANCE := 2.0 * 0.01
const WORLD_MASK := 1
const ARTIFACT_PATH := "/tmp/protocol47-bot-crowd-1000-ticks.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOT MOBILITY TEST: " + message)


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		quit(1)
		return

	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	_check(game.using_imported_map, "1000-tick gate uses the original Dust2 spawn set")
	_check(
		Engine.physics_ticks_per_second == TICK_RATE_HZ,
		"fixed physics clock is exactly %d Hz" % TICK_RATE_HZ,
	)
	game.start_match()
	game._begin_live()

	var combatants: Array[Node3D] = [game.player]
	for bot in game._all_bots():
		combatants.append(bot)
	_check(
		combatants.size() == 10,
		"original map spawn set contains all ten combatants (got %d)"
		% combatants.size(),
	)
	# Keep every collision hull in the gate for its full ten seconds. Combat AI
	# still aims, shoots, navigates, and avoids; this only prevents a death from
	# removing the measured hull before tick 1000.
	for combatant: Node3D in combatants:
		combatant.health = 1000000

	var starting_positions: Dictionary = {}
	for bot in game._all_bots():
		starting_positions[bot] = bot.global_position

	var hull_shape := BoxShape3D.new()
	hull_shape.size = Vector3(HULL_WIDTH, HULL_HEIGHT, HULL_WIDTH)
	var minimum_pairwise_axis_separation := INF
	var max_floor_error := 0.0
	var pair_overlap_count := 0
	var missing_floor_count := 0
	var floor_error_count := 0
	var world_intersection_count := 0
	var violation_samples: Array[Dictionary] = []

	for tick in range(TICK_COUNT):
		await physics_frame
		var space_state: PhysicsDirectSpaceState3D = (
			game.get_world_3d().direct_space_state
		)

		for first_index in range(combatants.size()):
			var first := combatants[first_index]
			for second_index in range(first_index + 1, combatants.size()):
				var second := combatants[second_index]
				var dx := absf(first.global_position.x - second.global_position.x)
				var dz := absf(first.global_position.z - second.global_position.z)
				# This is the separating axis for two axis-aligned 32 HU hulls:
				# negative means their X and Z intervals overlap simultaneously.
				var axis_separation := maxf(dx - HULL_WIDTH, dz - HULL_WIDTH)
				minimum_pairwise_axis_separation = minf(
					minimum_pairwise_axis_separation,
					axis_separation,
				)
				if axis_separation < -0.000001:
					pair_overlap_count += 1
					_add_sample(violation_samples, {
						"kind": "pair_hull_overlap",
						"tick": tick + 1,
						"first": first.name,
						"second": second.name,
						"x_overlap_hu": (HULL_WIDTH - dx) / 0.01,
						"z_overlap_hu": (HULL_WIDTH - dz) / 0.01,
					})

		for combatant: Node3D in combatants:
			var feet := combatant.global_position
			# GoldSrc categorizes the floor with the player hull, not a zero-width
			# ray through its center. Probe the center and four inset hull corners
			# and use the highest walkable support plane.
			var floor_hit := _trace_hull_floor(space_state, combatant, feet)
			if floor_hit.is_empty():
				missing_floor_count += 1
				_add_sample(violation_samples, {
					"kind": "missing_floor_trace",
					"tick": tick + 1,
					"combatant": combatant.name,
					"feet": _vector_array(feet),
				})
			else:
				var floor_error := absf(feet.y - float(floor_hit.position_y))
				max_floor_error = maxf(max_floor_error, floor_error)
				if floor_error > FLOOR_TOLERANCE + 0.000001:
					floor_error_count += 1
					_add_sample(violation_samples, {
						"kind": "floor_error",
						"tick": tick + 1,
						"combatant": combatant.name,
						"error_hu": floor_error / 0.01,
					})

			var hull_query := PhysicsShapeQueryParameters3D.new()
			hull_query.shape = hull_shape
			# Lift past the separately audited 2 HU support band so valid floor
			# contact cannot be misreported as BSP wall penetration. The queried
			# shape itself remains the exact 32x72x32 HU source hull.
			hull_query.transform = Transform3D(
				Basis.IDENTITY,
				feet + Vector3.UP * (
					HULL_HEIGHT * 0.5 + FLOOR_TOLERANCE + 0.001
				),
			)
			hull_query.collision_mask = WORLD_MASK
			hull_query.exclude = [combatant.get_rid()]
			hull_query.collide_with_areas = false
			hull_query.collide_with_bodies = true
			hull_query.margin = 0.0
			var world_hits: Array[Dictionary] = space_state.intersect_shape(hull_query, 1)
			if not world_hits.is_empty():
				world_intersection_count += 1
				_add_sample(violation_samples, {
					"kind": "bsp_hull_intersection",
					"tick": tick + 1,
					"combatant": combatant.name,
					"feet": _vector_array(feet),
				})

	var stalled_bots: Array[String] = []
	var travel_hu := {}
	for bot in game._all_bots():
		var distance: float = bot.global_position.distance_to(starting_positions[bot])
		travel_hu[bot.name] = distance / 0.01
		if distance < 1.0:
			stalled_bots.append("%s (%.2f world units)" % [bot.name, distance])

	var artifact := {
		"map": "de_dust2",
		"spawn_set": "original BSP entities",
		"tick_rate_hz": TICK_RATE_HZ,
		"ticks": TICK_COUNT,
		"duration_seconds": float(TICK_COUNT) / float(TICK_RATE_HZ),
		"combatants": combatants.size(),
		"hull_hu": [32, 72, 32],
		"minimum_pairwise_axis_separation_hu": (
			minimum_pairwise_axis_separation / 0.01
		),
		"maximum_floor_error_hu": max_floor_error / 0.01,
		"pair_overlap_count": pair_overlap_count,
		"missing_floor_trace_count": missing_floor_count,
		"floor_error_over_2hu_count": floor_error_count,
		"bsp_hull_intersection_count": world_intersection_count,
		"bot_travel_hu": travel_hu,
		"violation_samples": violation_samples,
	}
	var artifact_file := FileAccess.open(ARTIFACT_PATH, FileAccess.WRITE)
	_check(artifact_file != null, "crowd-gate artifact opens")
	if artifact_file != null:
		artifact_file.store_string(JSON.stringify(artifact, "\t"))

	_check(pair_overlap_count == 0, "32 HU pair hulls never overlap on both X and Z")
	_check(missing_floor_count == 0, "every combatant has a valid BSP floor trace")
	_check(
		floor_error_count == 0,
		"every combatant's feet stay within 2 HU of its BSP floor trace",
	)
	_check(
		world_intersection_count == 0,
		"no 32x72x32 HU combatant hull intersects BSP world geometry",
	)
	_check(
		stalled_bots.is_empty(),
		"every bot leaves its first navmesh waypoint: %s" % ", ".join(stalled_bots),
	)

	if failures.is_empty():
		print(
			"GAME_BOT_MOBILITY_TEST_PASS min_axis=%.3fHU max_floor=%.3fHU artifact=%s"
			% [
				minimum_pairwise_axis_separation / 0.01,
				max_floor_error / 0.01,
				ARTIFACT_PATH,
			],
		)
		current_scene = null
		game.queue_free()
		await process_frame
		quit(0)
	else:
		print("GAME_BOT_MOBILITY_TEST_FAIL: %s" % ", ".join(failures))
		print("GAME_BOT_MOBILITY_TEST_ARTIFACT: %s" % ARTIFACT_PATH)
		current_scene = null
		game.queue_free()
		await process_frame
		quit(1)


func _add_sample(samples: Array[Dictionary], sample: Dictionary) -> void:
	var matching_kind := 0
	for existing: Dictionary in samples:
		if str(existing.kind) == str(sample.kind):
			matching_kind += 1
	if matching_kind < 12:
		samples.append(sample)


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _trace_hull_floor(
	space_state: PhysicsDirectSpaceState3D,
	combatant: Node3D,
	feet: Vector3,
) -> Dictionary:
	var inset := HULL_HALF_WIDTH - 0.001
	var offsets := [
		Vector3.ZERO,
		Vector3(inset, 0.0, inset),
		Vector3(inset, 0.0, -inset),
		Vector3(-inset, 0.0, inset),
		Vector3(-inset, 0.0, -inset),
	]
	var highest := -INF
	for offset: Vector3 in offsets:
		var ray := PhysicsRayQueryParameters3D.create(
			feet + offset + Vector3.UP * 0.08,
			feet + offset + Vector3.DOWN * 1.0,
			WORLD_MASK,
			[combatant.get_rid()],
		)
		var hit: Dictionary = space_state.intersect_ray(ray)
		if hit.is_empty() or float(hit.normal.y) < 0.7:
			continue
		highest = maxf(highest, float(hit.position.y))
	return {} if highest == -INF else {"position_y": highest}
