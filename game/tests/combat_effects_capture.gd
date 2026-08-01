extends SceneTree

## Combat VFX captures staged inside the converted de_dust2 map so sprite
## blending, texel density, and lighting can be judged against authentic
## GoldSrc surfaces instead of a featureless box.

const CombatEffects := preload("res://scripts/cs16_combat_effects.gd")
const BspMapScript := preload("res://scripts/bsp_map.gd")
const ViewModelScript := preload("res://scripts/mdl_viewmodel.gd")
const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")

const MAP_PATH := "res://generated/de_dust2/map.json"
const EYE_HEIGHT := 0.60

var manager: CS16CombatEffects
var output_root := ""
var _last_luminance_spread := 0.0
var stage: Node3D
var camera: Camera3D
var map: BspMap


func _initialize() -> void:
	call_deferred("_run")


func _capture(name: String) -> bool:
	for frame in range(3):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var path := output_root.path_join(name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save combat VFX capture to %s: %s" % [path, error_string(error)])
		return false
	print("COMBAT_VFX_CAPTURE %s" % path)
	return true


func _reset_manager() -> CS16CombatEffects:
	if is_instance_valid(manager):
		manager.free()
	manager = CombatEffects.new()
	manager.name = CombatEffects.NODE_NAME
	manager.set_physics_process(false)
	stage.add_child(manager)
	# Entering the tree re-enables physics processing for nodes overriding
	# _physics_process; freeze the effect clock so advance_tick() alone drives
	# each fixture to a deterministic frame.
	manager.process_mode = Node.PROCESS_MODE_DISABLED
	return manager


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space := stage.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))


func _free_distance(from: Vector3, direction: Vector3, limit := 12.0) -> float:
	var hit := _ray(from, from + direction.normalized() * limit)
	if hit.is_empty():
		return limit
	return from.distance_to(hit.position)


func _open_direction(eye: Vector3) -> Vector3:
	# The horizontal direction with the deepest clearance: a real corridor.
	var best := Vector3.FORWARD
	var best_distance := 0.0
	for step in range(48):
		var yaw := TAU * float(step) / 48.0
		var direction := Vector3(cos(yaw), 0.0, sin(yaw))
		var distance := _free_distance(eye, direction)
		if distance > best_distance:
			best_distance = distance
			best = direction
	return best


func _wall_candidates(eye: Vector3) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for step in range(48):
		var yaw := TAU * float(step) / 48.0
		var direction := Vector3(cos(yaw), 0.0, sin(yaw))
		var hit := _ray(eye, eye + direction * 8.0)
		if hit.is_empty():
			continue
		var normal: Vector3 = Vector3(hit.normal).normalized()
		if absf(normal.y) > 0.35:
			continue
		var distance: float = eye.distance_to(hit.position)
		if distance < 1.4 or distance > 7.0:
			continue
		candidates.append(hit)
	return candidates


func _mean_luminance(wide := false) -> float:
	for frame in range(3):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	# Median luminance. The default central band matches where the fixture
	# lives; `wide` samples most of the frame so a lamp-lit patch in an
	# otherwise pitch-black tunnel cannot pass as a "lit" scene (wall picker).
	var values: Array[float] = []
	var y_low := 0.12 if wide else 0.22
	var y_high := 0.88 if wide else 0.62
	var x_low := 0.12 if wide else 0.30
	var x_high := 0.88 if wide else 0.70
	for y in range(int(image.get_height() * y_low), int(image.get_height() * y_high), 12):
		for x in range(int(image.get_width() * x_low), int(image.get_width() * x_high), 12):
			var color := image.get_pixel(x, y)
			values.append(color.r * 0.35 + color.g * 0.5 + color.b * 0.15)
	if values.is_empty():
		return 0.0
	values.sort()
	# Interquartile spread doubles as a texture-busyness signal: plank crates
	# with deep gaps read high, smooth stucco/brick reads low.
	_last_luminance_spread = (
		values[int(values.size() * 0.75)] - values[int(values.size() * 0.25)]
	)
	return values[values.size() / 2]


func _wall_band_visible(wall_point: Vector3, wall_normal: Vector3) -> bool:
	## Renders a bright magenta probe quad over the decal band and checks the
	## camera actually sees it (catches collisionless visual brushes covering
	## the wall that physics rays pass straight through).
	var probe := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 0.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.0, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = material
	probe.mesh = quad
	stage.add_child(probe)
	probe.global_transform = Transform3D(
		Basis.looking_at(-wall_normal, Vector3.UP),
		wall_point + wall_normal * 0.02 + Vector3.UP * 0.15,
	)
	for frame in range(3):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var magenta := 0
	var samples := 0
	for y in range(int(image.get_height() * 0.30), int(image.get_height() * 0.70), 10):
		for x in range(int(image.get_width() * 0.25), int(image.get_width() * 0.75), 10):
			var color := image.get_pixel(x, y)
			samples += 1
			if color.r > 0.6 and color.b > 0.6 and color.g < 0.35:
				magenta += 1
	probe.queue_free()
	await process_frame
	return samples > 0 and float(magenta) / float(samples) > 0.60


func _find_lit_wall(spawns: Array[Vector3]) -> Dictionary:
	## Picks a wall whose baked lightmap actually reads on camera, so decals
	## judged with multiplicative blending are inspectable.
	var best: Dictionary = {}
	var best_luminance := -1.0
	for spawn_index in range(mini(spawns.size(), 20)):
		var eye: Vector3 = spawns[spawn_index] + Vector3.UP * EYE_HEIGHT
		for hit in _wall_candidates(eye):
			var wall_point: Vector3 = hit.position
			var wall_normal: Vector3 = Vector3(hit.normal).normalized()
			var capture_eye := wall_point + wall_normal * 1.15 + Vector3.UP * 0.06
			# The capture camera stands much closer to the wall than the scouting
			# eye: reject spots where foreground geometry (sand mounds, crates)
			# slips between the camera and the decal band and hides the impacts.
			var occluder := _ray(capture_eye, wall_point + wall_normal * 0.03)
			if (
				not occluder.is_empty()
				and Vector3(occluder.position).distance_to(wall_point) > 0.2
			):
				continue
			camera.look_at_from_position(capture_eye, wall_point, Vector3.UP)
			# Physics rays cannot catch visual-only brushes (func_illusionary
			# style crates carry no collision), so verify VISUALLY that the
			# decal band on the wall is what the camera actually sees: a bright
			# magenta probe quad at the wall must dominate the frame center.
			if not await _wall_band_visible(wall_point, wall_normal):
				continue
			var luminance := await _mean_luminance(true)
			# Prefer well-exposed walls: bright enough for MUL decals to read,
			# not blown out by the strongest baked sun patches. Hard-reject dim
			# interiors outright: a lamp-lit tunnel patch can pass the median
			# test while the surrounding frame stays near-black and the dark
			# bullet-hole decals become illegible.
			if luminance < 0.30:
				continue
			# Busy plank/crate textures camouflage the small dark shot chips;
			# prefer smooth stucco or brick where the burst reads instantly.
			var spread := _last_luminance_spread
			var score := -absf(luminance - 0.42) - maxf(0.0, spread - 0.10)
			if score > best_luminance:
				best_luminance = score
				best = hit
			if luminance > 0.34 and luminance < 0.58 and spread < 0.14:
				return hit
	return best


func _find_lit_corridor(spawns: Array[Vector3]) -> Dictionary:
	## Picks the spawn/direction pair whose corridor view is actually lit, so
	## the sprite fixtures are judged against readable dust2 surfaces.
	var best: Dictionary = {}
	var best_score := -INF
	for spawn_index in range(mini(spawns.size(), 14)):
		var eye: Vector3 = spawns[spawn_index] + Vector3.UP * EYE_HEIGHT
		var open := _open_direction(eye)
		var clearance := _free_distance(eye, open)
		if clearance < 3.0:
			continue
		camera.look_at_from_position(eye, eye + open * 6.0, Vector3.UP)
		var luminance := await _mean_luminance()
		var score := -absf(luminance - 0.36)
		if score > best_score:
			best_score = score
			best = {"eye": eye, "open": open, "clearance": clearance}
		if luminance > 0.28 and luminance < 0.52:
			return {"eye": eye, "open": open, "clearance": clearance}
	return best


func _floor_point(origin: Vector3) -> Vector3:
	var hit := _ray(origin + Vector3.UP * 0.5, origin - Vector3.UP * 4.0)
	if hit.is_empty():
		return origin
	return hit.position


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)

	stage = Node3D.new()
	stage.name = "CombatEffectsCapture"
	root.add_child(stage)
	current_scene = stage

	# Match the in-game presentation environment (game.gd): baked map surfaces
	# are unshaded; ambient and sun only light dynamic props and models.
	var environment := WorldEnvironment.new()
	var world := Environment.new()
	world.background_mode = Environment.BG_COLOR
	world.background_color = Color("#26303a")
	world.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.ambient_light_color = Color("#c8d0ce")
	world.ambient_light_energy = 0.78
	world.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = world
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color("#ffe8c8")
	sun.light_energy = 1.1
	stage.add_child(sun)

	map = BspMapScript.new()
	stage.add_child(map)
	if not map.load_map(MAP_PATH):
		push_error("Combat VFX capture could not load %s" % MAP_PATH)
		quit(1)
		return

	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.02
	stage.add_child(camera)
	camera.current = true

	output_root = ProjectSettings.globalize_path("res://artifacts")
	DirAccess.make_dir_recursive_absolute(output_root)

	# Let physics ingest the map collision before ray queries.
	for frame in range(4):
		await physics_frame

	var spawns := map.spawn_points("info_player_start")
	spawns.append_array(map.spawn_points("info_player_deathmatch"))
	if spawns.is_empty():
		push_error("No spawn points in %s" % MAP_PATH)
		quit(1)
		return

	# Fixture 1: authentic 16-unit bullet-hole decals with their brief gray
	# impact puffs and ricochet sparks on a lit dust2 wall, blood decals to the
	# side. No mid-air blood volume; blood reads as flat dark wall splats.
	var wall := await _find_lit_wall(spawns)
	if wall.is_empty():
		push_error("Combat VFX capture found no wall for the impact fixture")
		quit(1)
		return
	var wall_point: Vector3 = wall.position
	var wall_normal: Vector3 = Vector3(wall.normal).normalized()
	var wall_tangent := wall_normal.cross(Vector3.UP).normalized()
	_reset_manager()
	camera.look_at_from_position(
		wall_point + wall_normal * 1.15 + Vector3.UP * 0.16,
		wall_point + Vector3.UP * 0.15,
		Vector3.UP,
	)
	# A full burst: 8 holes so the shot1-5 decal variety is unmistakable on the
	# lit wall. The first 7 impacts are aged past their dust puffs (which would
	# otherwise cover the very holes they punched), then one fresh impact fires
	# so a live gray wall_puff is also in frame.
	for index in range(7):
		manager.spawn_world_impact(
			wall_point
			+ wall_tangent * (-0.42 + float(index) * 0.13)
			+ Vector3.UP * (0.02 + float((index * 5) % 3) * 0.13),
			wall_normal,
			index,
		)
	manager.advance_tick(24)
	manager.spawn_world_impact(
		wall_point + wall_tangent * 0.49 + Vector3.UP * 0.15,
		wall_normal,
		7,
	)
	for index in range(3):
		manager.spawn_blood_decal(
			wall_point
			+ wall_tangent * (0.52 + float(index) * 0.14)
			+ Vector3.UP * (0.16 - float(index) * 0.12),
			wall_normal,
			index,
		)
	# Mid-life for the fresh puff: the aged decals stay fully readable.
	manager.advance_tick(8)
	var impacts_ok := await _capture("protocol47-combat-vfx-impacts.png")

	# All remaining fixtures shoot from a real spawn eye down the most open,
	# best-lit corridor, so camera and effect sit in valid, readable space.
	var corridor := await _find_lit_corridor(spawns)
	if corridor.is_empty():
		push_error("Combat VFX capture found no open corridor")
		quit(1)
		return
	var eye: Vector3 = corridor.eye
	var open: Vector3 = corridor.open
	var clearance: float = corridor.clearance

	# Fixture 2: HE detonation on real ground: the two original fexplo/eexplo
	# additive temp entities mid-animation, with the scorch decal visible.
	_reset_manager()
	var blast_point := _floor_point(eye + open * minf(2.8, clearance * 0.5))
	camera.look_at_from_position(eye, blast_point + Vector3.UP * 0.7, Vector3.UP)
	manager.spawn_he_explosion(blast_point + Vector3.UP * 0.04, Vector3.UP)
	manager.advance_tick(18)
	var explosion_ok := await _capture("protocol47-combat-vfx-explosion.png")

	# Fixture 3: the smoke grenade cloud fully built: massive, gray-olive,
	# ground-hugging, and vision-blocking in the middle of the corridor.
	_reset_manager()
	var smoke_point := _floor_point(eye + open * minf(3.6, clearance * 0.6))
	camera.look_at_from_position(eye, smoke_point + Vector3.UP * 0.7, Vector3.UP)
	manager.spawn_smoke_cloud(smoke_point)
	manager.advance_tick(260)
	var smoke_ok := await _capture("protocol47-combat-vfx-smoke.png")

	# Fixture 4: the exact firing frame. First person: AK-47 viewmodel in its
	# shoot sequence with the additive muzzleflash sprite at the barrel.
	# Third person: a T model down the lane with the flash at his gun muzzle.
	_reset_manager()
	camera.look_at_from_position(eye, eye + open * 6.0, Vector3.UP)
	var viewmodel: MdlViewModel = ViewModelScript.new()
	camera.add_child(viewmodel)
	viewmodel.load_weapon("ak47")
	if viewmodel._template.animations.has("shoot1"):
		viewmodel._start_animation("shoot1", false)
		viewmodel._animation_time = 0.0
		viewmodel._frame_key = ""
		viewmodel._process(0.0)
	var camera_basis := camera.global_transform.basis
	# Mirror player.gd first_person_shot_effect_origin(): re-base the shot
	# origin so the flash lands on the rendered viewmodel's actual barrel tip
	# (the studio muzzle attachment), not mid-receiver.
	var shot_origin := camera.global_position
	if viewmodel.has_method("muzzle_point_world"):
		shot_origin = (
			viewmodel.muzzle_point_world()
			- (-camera_basis.z * 0.72 + camera_basis.x * 0.235 - camera_basis.y * 0.155)
		)
	manager.spawn_weapon_shot(
		"ak47",
		0,
		shot_origin,
		-camera_basis.z,
		camera_basis.x,
		camera_basis.y,
	)
	var third_person_floor := _floor_point(eye + open * minf(3.1, clearance * 0.55))
	var third_person: MdlCharacterModel = CharacterModelScript.new()
	stage.add_child(third_person)
	third_person.load_character("terror", "ak47")
	third_person.process_mode = Node.PROCESS_MODE_DISABLED
	third_person.set_locomotion(false, false, true)
	third_person.play_action("shoot")
	third_person.advance_animation(0.03)
	third_person.global_position = third_person_floor
	var to_camera := camera.global_position - third_person_floor
	to_camera.y = 0.0
	third_person.rotation.y = atan2(to_camera.x, to_camera.z) + PI * 0.35
	var third_person_forward := Vector3(
		sin(third_person.rotation.y),
		0.0,
		cos(third_person.rotation.y),
	)
	# The world-model flash must sit on the rifle's actual muzzle: read the
	# posed weapon mesh bounds and take their extremity along the aim
	# direction (the studio muzzle attachment lives at the barrel end).
	var third_person_muzzle := (
		third_person_floor + third_person_forward * 0.30 + Vector3.UP * 0.24
	)
	if is_instance_valid(third_person.weapon_instance):
		var weapon_box: AABB = (
			third_person.weapon_instance.global_transform
			* third_person.weapon_instance.get_aabb()
		)
		var best_dot := -INF
		for corner_index in range(8):
			var corner := weapon_box.get_endpoint(corner_index)
			var along := corner.dot(third_person_forward)
			if along > best_dot:
				best_dot = along
				third_person_muzzle = corner
		# The barrel axis midpoint, not a box corner: average the two corners
		# nearest the muzzle plane.
		var plane_center := Vector3.ZERO
		var plane_count := 0
		for corner_index in range(8):
			var corner := weapon_box.get_endpoint(corner_index)
			if corner.dot(third_person_forward) > best_dot - 0.02:
				plane_center += corner
				plane_count += 1
		if plane_count > 0:
			third_person_muzzle = plane_center / float(plane_count)
	manager._spawn_sprite(
		"muzzleflash2",
		third_person_muzzle,
		0.20,
		30.0,
		CombatEffects.EVENT_MUZZLE_FLASH,
		0,
		false,
		Color.WHITE,
		Vector3.ZERO,
		55.0,
	)
	manager.spawn_muzzle_light(third_person_muzzle)
	manager.advance_tick(1)
	var muzzle_ok := await _capture("protocol47-combat-vfx-muzzle.png")
	viewmodel.queue_free()
	third_person.queue_free()

	if impacts_ok and explosion_ok and smoke_ok and muzzle_ok:
		print("GAME_COMBAT_EFFECTS_CAPTURE_PASS")
		stage.free()
		quit(0)
	else:
		stage.free()
		quit(1)
