extends SceneTree

const Ballistics := preload("res://scripts/cs16_ballistics.gd")
const GrenadeScript := preload("res://scripts/grenade.gd")
const PlayerScript := preload("res://scripts/player.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BALLISTICS TEST: " + message)


func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(
		absf(actual - expected) <= tolerance,
		"%s (got %.8f, expected %.8f)" % [message, actual, expected],
	)


func _run() -> void:
	_test_weapon_constants_and_range()
	_test_hitgroups_and_armor()
	_test_knife_backstab_and_armor()
	_test_penetration()
	_test_shared_spread()
	_test_live_spread_and_materials()
	await _test_ray_material_faces()
	_test_he_grenade_math()
	await _test_grenade_configuration()

	if failures.is_empty():
		print("GAME_BALLISTICS_TEST_PASS")
		quit(0)
	else:
		print("GAME_BALLISTICS_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)


func _test_live_spread_and_materials() -> void:
	_near(Ballistics.weapon_spread("ak47", true, 0.0, false, false, 0.2, 0.9), 0.0055, 0.000001, "rested AK first-shot cone")
	_near(Ballistics.weapon_spread("mp5", true, 0.0, false, false, 0.75, 0.55), 0.03, 0.000001, "MP5 uses its canonical weapon ID and accuracy-scaled cone")
	_near(Ballistics.weapon_spread("mp5", false, 0.0, false, false, 0.75, 0.9), 0.15, 0.000001, "airborne SMG penalty scales with its own accuracy")
	_near(Ballistics.weapon_spread("awp", true, 0.0, false, true, 0.2, 0.9), 0.001, 0.000001, "standing scoped AWP retains source minimum spread")
	_check(Ballistics.weapon_spread("deagle", true, 0.0, true, false, 0.2, 0.9) < Ballistics.weapon_spread("deagle", true, 0.0, false, false, 0.2, 0.9), "crouching tightens pistol spread")
	var world := Node3D.new()
	world.set_meta("face_textures", ["concrete"])
	var brush := StaticBody3D.new()
	world.add_child(brush)
	brush.set_meta("face_textures", ["wood", "metal", "grate", "vent", "tile", "computer"])
	for face in range(6):
		_check(Ballistics.surface_for_hit({"collider": brush, "face_index": face}) == [Ballistics.SURFACE_WOOD, Ballistics.SURFACE_METAL, Ballistics.SURFACE_GRATE, Ballistics.SURFACE_VENT, Ballistics.SURFACE_TILE, Ballistics.SURFACE_COMPUTER][face], "bullet material uses collider-local face %d" % face)
	_check(Ballistics.surface_for_hit({"collider": brush, "face_index": -1}) == Ballistics.SURFACE_CONCRETE, "missing face has safe concrete fallback")
	brush.remove_meta("face_textures")
	_check(Ballistics.surface_for_hit({"collider": brush, "face_index": 0}) == Ballistics.SURFACE_CONCRETE, "world texture lookup walks collider ancestors")
	world.free()


func _test_ray_material_faces() -> void:
	# Fabricated hit dictionaries cannot catch a backend returning face_index=-1
	# or a collision accelerator reordering the collider-local triangle indices.
	var textures := ["wood", "metal", "grate", "vent", "tile", "computer"]
	var surfaces := [Ballistics.SURFACE_WOOD, Ballistics.SURFACE_METAL,
		Ballistics.SURFACE_GRATE, Ballistics.SURFACE_VENT,
		Ballistics.SURFACE_TILE, Ballistics.SURFACE_COMPUTER]
	var faces := PackedVector3Array()
	for face in range(textures.size()):
		var center := Vector3(float(face) * 2.0, 0, 0)
		faces.append(center + Vector3(-0.4, -0.4, 0))
		faces.append(center + Vector3(0.4, -0.4, 0))
		faces.append(center + Vector3(0, 0.4, 0))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var world := Node3D.new()
	world.set_meta("face_textures", textures)
	root.add_child(world)
	var world_body := StaticBody3D.new()
	var brush := AnimatableBody3D.new()
	brush.sync_to_physics = false
	var brush_textures := textures.duplicate()
	brush_textures.reverse()
	brush.set_meta("face_textures", brush_textures)
	brush.position = Vector3(0, 0, -5)
	var bodies: Array[PhysicsBody3D] = [world_body, brush]
	for body: PhysicsBody3D in bodies:
		body.collision_layer = 1
		body.collision_mask = 0
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		world.add_child(body)
	for placement in range(2):
		if placement == 1:
			brush.position = Vector3(0.5, 1, -6)
			brush.rotation.y = 0.3
		# physics_frame is emitted before physics callbacks/server synchronization;
		# allow a completed step to publish the brush's updated transform.
		await physics_frame
		await physics_frame
		for body: PhysicsBody3D in bodies:
			for face in range(textures.size()):
				var center := body.to_global(Vector3(float(face) * 2.0, 0, 0))
				var direction := body.global_basis.z
				var hit := world.get_world_3d().direct_space_state.intersect_ray(
					PhysicsRayQueryParameters3D.create(center + direction, center - direction, 1))
				_check(not hit.is_empty(), "material ray hits triangle %d at placement %d" % [face, placement])
				if hit.is_empty():
					continue
				_check(hit.get("collider") == body, "material ray resolves the intended collision body")
				_check(int(hit.get("face_index", -1)) == face, "ray preserves collider-local face index %d" % face)
				var expected: String = surfaces[face if body == world_body else surfaces.size() - 1 - face]
				_check(Ballistics.surface_for_hit(hit) == expected,
					"real ray resolves %s from the correct body's texture table" % expected)
	world.queue_free()
	await process_frame


func _test_weapon_constants_and_range() -> void:
	var ak := Ballistics.weapon_profile("ak47")
	_check(int(ak.base_damage) == 36, "AK-47 base damage matches weapons.h")
	_near(float(ak.range_modifier), 0.98, 0.000001, "AK-47 range modifier matches weapons.h")
	_check(int(ak.penetrations) == 2, "AK-47 penetration count matches wpn_ak47.cpp")
	_near(float(ak.range_units), 8192.0, 0.001, "AK-47 trace range matches wpn_ak47.cpp")
	_near(float(ak.range_meters), 81.92, 0.001, "AK-47 trace range uses the BSP world scale")

	var deagle := Ballistics.weapon_profile("deagle")
	_check(int(deagle.base_damage) == 54, "Desert Eagle base damage matches weapons.h")
	_near(float(deagle.range_modifier), 0.81, 0.000001, "Desert Eagle range modifier matches weapons.h")
	_check(int(deagle.penetrations) == 2, "Desert Eagle penetration count matches wpn_deagle.cpp")
	_near(float(deagle.range_units), 4096.0, 0.001, "Desert Eagle trace range matches wpn_deagle.cpp")
	_near(float(deagle.range_meters), 40.96, 0.001, "Desert Eagle trace range uses the BSP world scale")

	_check(Ballistics.range_damage(36, 0.98, 0.0) == 36, "zero-distance AK damage is unchanged")
	_check(Ballistics.range_damage(36, 0.98, 5.0) == 35, "AK range damage truncates at 500 units")
	_check(Ballistics.range_damage(54, 0.81, 5.0) == 43, "Desert Eagle loses 19% per 500 units")


func _test_hitgroups_and_armor() -> void:
	_near(
		Ballistics.hitgroup_damage(36.0, Ballistics.HitGroup.HEAD),
		144.0,
		0.0001,
		"head multiplier is applied before armor",
	)
	_near(
		Ballistics.hitgroup_damage(36.0, Ballistics.HitGroup.STOMACH),
		45.0,
		0.0001,
		"stomach multiplier is 1.25",
	)
	_near(
		Ballistics.hitgroup_damage(36.0, Ballistics.HitGroup.LEFT_LEG),
		27.0,
		0.0001,
		"leg multiplier is 0.75",
	)

	var helmet_head := Ballistics.resolve_bullet_damage(
		36,
		Ballistics.HitGroup.HEAD,
		100.0,
		Ballistics.ArmorType.VEST_HELMET,
		"ak47",
	)
	_near(float(helmet_head.hitgroup_damage), 144.0, 0.0001, "helmet does not alter hitgroup multiplication")
	_near(float(helmet_head.health_damage_float), 111.6, 0.0001, "AK armor ratio applies after head multiplier")
	_check(int(helmet_head.health_damage) == 111, "bullet health damage uses the original integer truncation")
	_near(float(helmet_head.armor_damage), 16.2, 0.0001, "AK helmet armor consumption matches TakeDamage")

	var kevlar_head := Ballistics.resolve_bullet_damage(
		36,
		Ballistics.HitGroup.HEAD,
		100.0,
		Ballistics.ArmorType.KEVLAR,
		"ak47",
	)
	_check(int(kevlar_head.health_damage) == 144, "kevlar without helmet does not protect the head")

	var armored_chest := Ballistics.resolve_bullet_damage(
		36,
		Ballistics.HitGroup.CHEST,
		100.0,
		Ballistics.ArmorType.KEVLAR,
		"ak47",
	)
	_near(float(armored_chest.health_damage_float), 27.9, 0.0001, "AK chest armor ratio is 0.775")
	_near(float(armored_chest.armor_damage), 4.05, 0.0001, "AK chest armor consumption matches TakeDamage")

	var armored_leg := Ballistics.resolve_bullet_damage(
		36,
		Ballistics.HitGroup.RIGHT_LEG,
		100.0,
		Ballistics.ArmorType.VEST_HELMET,
		"ak47",
	)
	_check(int(armored_leg.health_damage) == 27, "armor never protects legs")
	_check(not bool(armored_leg.armored), "leg result records that armor was bypassed")


func _test_knife_backstab_and_armor() -> void:
	# weapons.h: KNIFE_STAB_DAMAGE 65, KNIFE_SWING_DAMAGE 15,
	# KNIFE_BACKSTAB_MULTIPLIER 3, backstab when the 2D dot of the two forward
	# vectors exceeds 0.8 (CKnife::Stab).
	_check(Ballistics.KNIFE_STAB_DAMAGE == 65, "knife stab base damage is 65")
	_check(Ballistics.KNIFE_SWING_DAMAGE == 15, "knife swing base damage is 15")
	_near(Ballistics.KNIFE_BACKSTAB_MULTIPLIER, 3.0, 0.000001, "backstab multiplier is 3")
	var forward := Vector3(0.0, 0.0, -1.0)
	_check(
		Ballistics.is_backstab(forward, forward),
		"stabbing a victim who faces the same way is a backstab",
	)
	_check(
		Ballistics.is_backstab(forward, Vector3(0.3, 0.9, -0.95).normalized()),
		"backstab test ignores pitch, exactly like Make2D",
	)
	_check(
		not Ballistics.is_backstab(forward, Vector3(0.0, 0.0, 1.0)),
		"stabbing a victim face to face is never a backstab",
	)
	_check(
		not Ballistics.is_backstab(forward, Vector3(1.0, 0.0, 0.0)),
		"a 90 degree flank is outside the 0.8 backstab cone",
	)
	_check(
		not Ballistics.is_backstab(forward, Vector3(0.7, 0.0, -0.7).normalized()),
		"a 45 degree flank is outside the 0.8 backstab cone",
	)
	_check(Ballistics.knife_damage(true, true) == 195, "backstab deals 195 damage")
	_check(Ballistics.knife_damage(true, false) == 65, "front stab deals 65 damage")
	_check(Ballistics.knife_damage(false, true) == 15, "swings carry no backstab bonus")

	# The knife runs through the bullet armor branch with its 1.7 armor ratio.
	_near(
		Ballistics.weapon_armor_ratio("knife"),
		0.85,
		0.000001,
		"knife armor ratio is 0.5 x 1.7",
	)
	var front := Ballistics.resolve_bullet_damage(
		65,
		Ballistics.HitGroup.CHEST,
		100.0,
		Ballistics.ArmorType.VEST_HELMET,
		"knife",
	)
	_check(
		int(front.health_damage) == 55,
		"front stab through kevlar+helmet deals 55, not the flat 65",
	)
	var backstab := Ballistics.resolve_bullet_damage(
		195,
		Ballistics.HitGroup.CHEST,
		100.0,
		Ballistics.ArmorType.VEST_HELMET,
		"knife",
	)
	_check(
		int(backstab.health_damage) >= 100,
		"a backstab kills a full health kevlar+helmet player",
	)
	var unarmored := Ballistics.resolve_bullet_damage(
		195,
		Ballistics.HitGroup.CHEST,
		0.0,
		Ballistics.ArmorType.NONE,
		"knife",
	)
	_check(int(unarmored.health_damage) == 195, "an unarmored backstab deals the full 195")
	var legs := Ballistics.resolve_bullet_damage(
		65,
		Ballistics.HitGroup.LEFT_LEG,
		0.0,
		Ballistics.ArmorType.NONE,
		"knife",
	)
	_check(int(legs.health_damage) == 48, "knife hit groups scale like bullets (0.75 leg)")


func _test_penetration() -> void:
	var ak_bullet := Ballistics.bullet_profile(Ballistics.BULLET_762MM)
	_check(int(ak_bullet.penetration_power_units) == 39, "7.62mm penetration power is 39 units")
	_near(
		float(ak_bullet.penetration_distance_meters),
		50.0,
		0.0001,
		"7.62mm penetration distance is scaled from 5000 units",
	)

	var metal := Ballistics.penetration_step(
		36,
		0.98,
		10.0,
		Ballistics.BULLET_762MM,
		Ballistics.SURFACE_METAL,
		true,
		2,
	)
	_check(int(metal.damage_at_hit) == 34, "range falloff is applied before penetration damage")
	_check(int(metal.penetration_power_units) == 5, "metal leaves 15% integer penetration power")
	_check(int(metal.next_damage) == 6, "metal leaves 20% integer damage")
	_near(float(metal.remaining_distance_scale), 0.5, 0.0001, "world penetration halves remaining range")
	_check(bool(metal.can_continue), "AK can continue through a nearby metal world surface")

	var wood := Ballistics.penetration_step(
		36,
		0.98,
		10.0,
		Ballistics.BULLET_762MM,
		Ballistics.SURFACE_WOOD,
		true,
		2,
	)
	_check(int(wood.penetration_power_units) == 39, "wood does not reduce penetration step distance")
	_check(int(wood.next_damage) == 20, "wood leaves 60% integer damage")

	var player_hit := Ballistics.penetration_step(
		36,
		0.98,
		1.0,
		Ballistics.BULLET_762MM,
		Ballistics.SURFACE_DEFAULT,
		false,
		2,
	)
	_check(int(player_hit.penetration_power_units) == 42, "entity hit uses the original 42-unit continuation")
	_near(float(player_hit.damage_modifier), 0.75, 0.0001, "entity hit carries 75% damage")
	_near(float(player_hit.remaining_distance_scale), 0.75, 0.0001, "entity hit carries 75% remaining range")


func _test_shared_spread() -> void:
	_near(
		Ballistics.shared_random_float(0, -0.5, 0.5),
		0.3615264892578125,
		0.00000001,
		"GoldSrc shared random seed zero matches util.cpp",
	)
	var sample_zero := Ballistics.spread_sample(0, 1.0)
	_near(sample_zero.x, -0.10296630859375, 0.00000001, "seed-zero shared spread X is stable")
	_near(sample_zero.y, -0.07537841796875, 0.00000001, "seed-zero shared spread Y is stable")
	var sample_42 := Ballistics.spread_sample(42, 1.0)
	_near(sample_42.x, 0.255950927734375, 0.00000001, "seed-42 shared spread X is stable")
	_near(sample_42.y, 0.577117919921875, 0.00000001, "seed-42 shared spread Y is stable")
	_check(sample_42 == Ballistics.spread_sample(42, 1.0), "shared spread is deterministic")

	var direction := Ballistics.spread_direction(
		Vector3.FORWARD,
		Vector3.RIGHT,
		Vector3.UP,
		42,
		0.1,
	)
	_near(direction.x, sample_42.x * 0.1, 0.0000001, "spread direction applies right offset")
	_near(direction.y, sample_42.y * 0.1, 0.0000001, "spread direction applies up offset")
	_near(direction.z, -1.0, 0.0000001, "spread direction preserves the forward component")


func _test_he_grenade_math() -> void:
	_near(Ballistics.HE_FUSE_SECONDS, 1.5, 0.0001, "HE fuse matches ShootTimed2")
	_near(Ballistics.HE_RADIUS_METERS, 3.5, 0.0001, "HE radius is 100 damage times 3.5 units")
	_near(
		Ballistics.HE_GRAVITY_METERS_PER_SECOND_SQUARED,
		4.4,
		0.0001,
		"HE gravity is 0.55 times 800 units/s squared",
	)
	_near(Ballistics.he_radius_damage(0.0), 100.0, 0.0001, "HE damage is 100 at its origin")
	_near(Ballistics.he_radius_damage(1.75), 50.0, 0.0001, "HE radius damage falls off linearly")
	_near(Ballistics.he_radius_damage(3.5), 0.0, 0.0001, "HE damage reaches zero at 350 units")
	_near(
		Ballistics.he_damage_origin(Vector3.ZERO).y,
		0.01,
		0.0001,
		"grounded HE damage origin is lifted by one converted unit",
	)

	_near(Ballistics.remap_he_throw_pitch(0.0), -10.0, 0.0001, "level HE throw pitch remaps to -10 degrees")
	_near(Ballistics.he_throw_speed_meters(0.0), 6.0, 0.0001, "level HE throw speed is 600 units/s")
	_near(Ballistics.he_throw_speed_meters(-90.0), 7.5, 0.0001, "upward HE throw caps at 750 units/s")
	_near(Ballistics.he_throw_speed_meters(90.0), 0.0, 0.0001, "straight-down HE throw has zero launch speed")
	var upward_angles := PlayerScript.grenade_goldsrc_angles(Vector2(0.0, deg_to_rad(45.0)))
	var downward_angles := PlayerScript.grenade_goldsrc_angles(Vector2(0.0, deg_to_rad(-45.0)))
	_near(upward_angles.x, -45.0, 0.0001, "Godot look-up pitch converts to GoldSrc's negative pitch")
	_near(downward_angles.x, 45.0, 0.0001, "Godot look-down pitch converts to GoldSrc's positive pitch")
	_check(
		Ballistics.he_throw_velocity(upward_angles.x, upward_angles.y, Vector3.ZERO).y > 0.0,
		"looking up launches a grenade upward",
	)
	_check(
		Ballistics.he_throw_velocity(downward_angles.x, downward_angles.y, Vector3.ZERO).y < 0.0,
		"looking down launches a grenade downward",
	)
	var throw_velocity := Ballistics.he_throw_velocity(0.0, 0.0, Vector3(1.0, 0.0, 0.0))
	_near(throw_velocity.x, 6.9088465, 0.0001, "HE inherits full player velocity")
	_near(throw_velocity.y, 1.0418891, 0.0001, "level HE throw has the original upward bias")
	var bounced := Ballistics.he_bounce_velocity(Vector3(1.0, -2.0, 0.0), Vector3.UP)
	_near(bounced.x, 1.0, 0.0001, "HE bounce preserves tangential velocity")
	_near(bounced.y, 0.6, 0.0001, "HE bounce uses 2 minus friction overbounce")
	_check(
		Ballistics.he_should_stop_after_ground_bounce(Vector3(0.29, 0.0, 0.0), Vector3.UP),
		"HE stops below the original 30 unit/s ground threshold",
	)
	_check(
		not Ballistics.he_should_stop_after_ground_bounce(Vector3(0.31, 0.0, 0.0), Vector3.UP),
		"HE continues above the original 30 unit/s ground threshold",
	)

	var armored_blast := Ballistics.apply_explosion_armor(100.0, 100.0)
	_near(float(armored_blast.health_damage_float), 50.0, 0.0001, "armor halves a full HE blast")
	_near(float(armored_blast.armor_damage), 25.0, 0.0001, "full HE blast consumes 25 armor")
	var depleted_armor_blast := Ballistics.apply_explosion_armor(100.0, 10.0)
	_near(
		float(depleted_armor_blast.health_damage_float),
		90.0,
		0.0001,
		"explosion armor depletion follows its distinct TakeDamage branch",
	)


func _test_grenade_configuration() -> void:
	var grenade: HEGrenade = GrenadeScript.new()
	root.add_child(grenade)
	await process_frame
	_check(GrenadeScript.FUSE_TICKS == 150, "HE fuse is exactly 150 authoritative ticks")
	_check(GrenadeScript.CLEANUP_TICKS == 150, "HE cleanup is exactly 150 authoritative ticks")
	var world_gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_near(
		grenade.gravity_scale * world_gravity,
		Ballistics.HE_GRAVITY_METERS_PER_SECOND_SQUARED,
		0.0001,
		"HE rigid body applies GoldSrc gravity in scaled world units",
	)
	_near(
		grenade.physics_material_override.bounce,
		1.0 - Ballistics.HE_FRICTION,
		0.0001,
		"HE rigid body converts inverse elasticity to Godot restitution",
	)
	_near(
		(grenade.get_child(0) as CollisionShape3D).shape.radius,
		Ballistics.METERS_PER_GOLDSRC_UNIT,
		0.0001,
		"HE uses the smallest robust approximation of GoldSrc's point hull",
	)
	grenade._simulation_tick = GrenadeScript.FUSE_TICKS - 1
	grenade._physics_process(0.5)
	_check(grenade._exploded, "HE fuse expires on tick 150 regardless of supplied frame delta")
	_check(
		grenade._cleanup_tick == grenade._simulation_tick + GrenadeScript.CLEANUP_TICKS,
		"exploded HE cleanup is scheduled on the same authoritative clock",
	)
	grenade.queue_free()
	await process_frame
