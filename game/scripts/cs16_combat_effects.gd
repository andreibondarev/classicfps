class_name CS16CombatEffects
extends Node3D

## GoldSrc-style combat temp entities driven by the game's fixed 100 Hz tick.
##
## Source parity:
## - ReGameDLL_CS cbase.cpp: FireBullets3 / DecalGunshot
## - ReGameDLL_CS util.cpp: UTIL_BloodDrips / UTIL_BloodDecalTrace
## - ReGameDLL_CS ggrenade.cpp: Explode3 / Smoke3_C
## - ReGameDLL_CS weapons.cpp: EjectBrass

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const TICK_RATE_HZ := 100
const TICK_SECONDS := 0.01
const NODE_NAME := "CS16CombatEffects"
const MANIFEST_PATH := "res://assets/vfx/manifest.json"
const MAX_WORLD_DECALS := 300 # mp_decals' CS 1.6 default.
const SHELL_LIFETIME_TICKS := 250
const HE_SMOKE_DELAY_TICKS := 55
const HE_SPARK_MAX := 3
const TE_EXPLOSION_RISE_METERS_PER_SECOND := 8.0 * 0.01
const TE_EXPLOSION_DLIGHT_COUNT := 2
const TE_EXPLOSION_FLICKER_COUNT := 16
const TE_EXPLOSION_FLICKER_STEP_TICKS := 2
const TE_EXPLOSION_FLICKER_PALETTE := [
	Color8(255, 224, 128, 232),
	Color8(255, 167, 17, 184),
	Color8(255, 96, 8, 112),
	Color8(128, 32, 0, 52),
]
const TE_SPARK_TRACER_COUNT := 8
const TE_SPARK_LIFETIME_TICKS := 50
# BLOOD_COLOR_RED is palette index 247: RGB (103, 0, 0) in cstrike/gfx/palette.lmp.
const BLOOD_COLOR_RED := Color8(103, 0, 0)

const EVENT_MUZZLE_FLASH := "muzzle_flash"
const EVENT_MUZZLE_SMOKE := "muzzle_smoke"
const EVENT_SHELL := "shell"
const EVENT_WORLD_DECAL := "world_decal"
const EVENT_BLOOD_SPRITE := "blood_sprite"
const EVENT_IMPACT_PARTICLES := "impact_particles"
const EVENT_HE_FIREBALL := "he_fireball"
const EVENT_HE_SMOKE := "he_smoke"
const EVENT_HE_SPARKS := "he_sparks"
const EVENT_HE_FLICKER := "he_flicker"
const EVENT_HE_LIGHT := "he_light"
const EVENT_RICOCHET := "ricochet"
const EVENT_SOUND := "sound"

static var _manifest_cache: Dictionary = {}
static var _shell_template_cache: Dictionary = {}

var tick := 0
var event_log: Array[Dictionary] = []
var _sprites: Array[Dictionary] = []
var _motions: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _timed_nodes: Array[Dictionary] = []
var _decal_nodes: Array[Node3D] = []
var _event_serial := 0


static func for_scene(scene: Node) -> CS16CombatEffects:
	if not is_instance_valid(scene):
		return null
	var existing := scene.get_node_or_null(NODE_NAME)
	if existing is CS16CombatEffects:
		return existing as CS16CombatEffects
	var effects := CS16CombatEffects.new()
	effects.name = NODE_NAME
	scene.add_child(effects)
	return effects


static func release_cached_resources() -> void:
	# Exported meshes are immutable and intentionally cached between effect
	# instances. Test harnesses and hot-reload hosts can release them explicitly
	# when tearing down the entire game scene.
	_shell_template_cache.clear()
	_manifest_cache.clear()


static func shot_profile(weapon_name: String, shot_sequence: int) -> Dictionary:
	match weapon_name:
		"ak47":
			return {
				"muzzle": "muzzleflash3",
				"smoke": "rifle_smoke%d" % (shot_sequence % 3 + 1),
				"shell": "rshell",
				# CS's AK event does not request a TE_TRACER for each round.
				"tracer_frequency": 0,
			}
		"deagle":
			return {
				"muzzle": "muzzleflash2",
				"smoke": "pistol_smoke%d" % (shot_sequence % 2 + 1),
				"shell": "pshell",
				"tracer_frequency": 0,
			}
	return {
		"muzzle": "muzzleflash1",
		"smoke": "",
		"shell": "",
		"tracer_frequency": 0,
	}


static func emits_tracer(weapon_name: String, shot_sequence: int) -> bool:
	var profile := shot_profile(weapon_name, shot_sequence)
	var frequency := int(profile.tracer_frequency)
	return frequency > 0 and shot_sequence % frequency == 0


static func sprite_frame_geometry(frame: Dictionary, scale_factor: float) -> Dictionary:
	var width := float(frame.get("width", 0)) * 0.01 * scale_factor
	var height := float(frame.get("height", 0)) * 0.01 * scale_factor
	var center_x := (
		float(frame.get("origin_x", 0))
		+ float(frame.get("width", 0)) * 0.5
	) * 0.01 * scale_factor
	var center_y := (
		float(frame.get("origin_y", 0))
		- float(frame.get("height", 0)) * 0.5
	) * 0.01 * scale_factor
	return {
		"size": Vector2(width, height),
		"center_offset": Vector3(center_x, center_y, 0.0),
	}


static func billboard_mode_for_orientation(orientation: int) -> int:
	# Valve utils/sprgen/spritegn.h:
	# 0 VP_PARALLEL_UPRIGHT, 1 FACING_UPRIGHT, 2 VP_PARALLEL,
	# 3 ORIENTED, 4 VP_PARALLEL_ORIENTED.
	match orientation:
		0, 1:
			return BaseMaterial3D.BILLBOARD_FIXED_Y
		3:
			return BaseMaterial3D.BILLBOARD_DISABLED
		2, 4:
			return BaseMaterial3D.BILLBOARD_ENABLED
	return BaseMaterial3D.BILLBOARD_ENABLED


func _ready() -> void:
	_load_manifest()


func _physics_process(_delta: float) -> void:
	advance_tick()


func clear_event_log() -> void:
	event_log.clear()


func advance_tick(count := 1) -> void:
	for step in range(maxi(count, 0)):
		tick += 1
		_update_sprites()
		_update_motions()
		_update_lights()
		_update_timed_nodes()


func spawn_weapon_shot(
	weapon_name: String,
	shot_sequence: int,
	origin: Vector3,
	direction: Vector3,
	right: Vector3,
	up: Vector3,
) -> void:
	var profile := shot_profile(weapon_name, shot_sequence)
	var forward := direction.normalized()
	var muzzle_origin := origin + forward * 0.38 + right * 0.12 - up * 0.08
	_spawn_sprite(
		str(profile.muzzle),
		muzzle_origin,
		0.26,
		30.0,
		EVENT_MUZZLE_FLASH,
		0,
		true,
	)
	if not str(profile.smoke).is_empty():
		_spawn_sprite(
			str(profile.smoke),
			muzzle_origin + forward * 0.035,
			0.18,
			30.0,
			EVENT_MUZZLE_SMOKE,
		2,
		false,
		)
	if not str(profile.shell).is_empty():
		_spawn_shell(
			str(profile.shell),
			origin + right * 0.15 - up * 0.07 + forward * 0.12,
			right * 1.35 + up * 1.1 - forward * 0.25,
			shot_sequence,
		)


func spawn_world_impact(
	position: Vector3,
	normal: Vector3,
	shot_sequence: int,
	surface := "concrete",
) -> void:
	var decal_name := "shot%d" % (shot_sequence % 5 + 1)
	spawn_decal(decal_name, position, normal, "shot", shot_sequence)
	_spawn_impact_particles(position, normal, shot_sequence, surface)


func spawn_blood_impact(
	position: Vector3,
	direction: Vector3,
	shot_sequence: int,
) -> void:
	var backwards := -direction.normalized()
	_spawn_sprite(
		"bloodspray",
		position + backwards * 0.015,
		0.55,
		18.0,
		EVENT_BLOOD_SPRITE,
		0,
		false,
		BLOOD_COLOR_RED,
	)
	_spawn_sprite(
		"blood",
		position + backwards * 0.025,
		0.32,
		18.0,
		EVENT_BLOOD_SPRITE,
		1,
		false,
		BLOOD_COLOR_RED,
	)


func spawn_blood_decal(position: Vector3, normal: Vector3, shot_sequence: int) -> void:
	spawn_decal(
		"blood%d" % (shot_sequence % 6 + 1),
		position,
		normal,
		"blood",
		shot_sequence,
	)


func spawn_he_explosion(position: Vector3, normal: Vector3) -> void:
	var serial := _next_serial()
	# Explode3 sends two independent TE_EXPLOSION messages: fexplo at scale
	# 2.5, then eexplo at scale 3.0 with a deterministic testable offset.
	_spawn_te_explosion(
		"fexplo",
		position + Vector3.UP * 0.20,
		2.5,
		30.0,
		serial,
	)
	var second_offset := Vector3(
		_signed_hash(serial, 17) * 0.64,
		0.30 + _unit_hash(serial, 31) * 0.05,
		_signed_hash(serial, 47) * 0.64,
	)
	_spawn_te_explosion(
		"eexplo",
		position + second_offset,
		3.0,
		30.0,
		serial + 1,
	)
	# Smoke3_C runs 0.55 seconds after Explode3 and uses steam1 at 5 fps.
	_spawn_sprite(
		"steam1",
		position - Vector3.UP * 0.05,
		3.5 + _unit_hash(serial, 61),
		5.0,
		EVENT_HE_SMOKE,
		HE_SMOKE_DELAY_TICKS,
		false,
	)
	spawn_decal(
		"scorch%d" % (serial % 2 + 1),
		position,
		normal,
		"scorch",
		serial,
	)
	var spark_count := serial % (HE_SPARK_MAX + 1)
	_spawn_spark_shower(position, normal, spark_count, serial)
	_spawn_sound(
		"res://assets/sounds/classic/weapons/explode3.wav",
		position,
		"explode3",
	)
	_spawn_sound(
		"res://assets/sounds/classic/weapons/debris%d.wav" % (serial % 3 + 1),
		position,
		"debris%d" % (serial % 3 + 1),
	)


func _spawn_te_explosion(
	asset_name: String,
	position: Vector3,
	scale_factor: float,
	fps: float,
	seed: int,
) -> void:
	var sprite_node := _spawn_sprite(
		asset_name,
		position,
		scale_factor,
		fps,
		EVENT_HE_FIREBALL,
		0,
		false,
		Color.WHITE,
		Vector3.UP * TE_EXPLOSION_RISE_METERS_PER_SECOND,
	)
	if not is_instance_valid(sprite_node) or _sprites.is_empty():
		return
	var sprite_state: Dictionary = _sprites[-1]
	var lifetime_ticks := int(sprite_state.expire_tick) - int(sprite_state.start_tick)
	var sprite: Dictionary = _manifest().get("sprites", {}).get(asset_name, {})
	var radius_meters := (
		float(sprite.get("bounding_radius", 0.0))
		* scale_factor
		* 0.01
	)
	_spawn_explosion_lights(
		sprite_node,
		position,
		maxf(radius_meters, 0.01),
		lifetime_ticks,
		seed,
	)
	_spawn_flicker_particles(position, lifetime_ticks, seed)


func spawn_decal(
	decal_name: String,
	position: Vector3,
	normal: Vector3,
	family: String,
	rotation_seed := 0,
) -> Node3D:
	_load_manifest()
	var decal: Dictionary = _manifest().get("decals", {}).get(decal_name, {})
	if decal.is_empty():
		return null
	var mesh := QuadMesh.new()
	mesh.size = Vector2(
		float(decal.width) * 0.01,
		float(decal.height) * 0.01,
	)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.albedo_texture = load("res://assets/vfx/%s" % str(decal.texture))
	# The imported PNG retains the original WAD RGB. White is the
	# multiplicative identity, exactly matching GoldSrc decal modulation
	# against the already-lit destination surface.
	material.albedo_color = Color.WHITE
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "GoldSrcDecal_%s" % decal_name
	instance.mesh = mesh
	add_child(instance)
	var plane_normal := normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var orientation_up := (
		Vector3.RIGHT
		if absf(plane_normal.dot(Vector3.UP)) > 0.94
		else Vector3.UP
	)
	var basis := Basis.looking_at(-plane_normal, orientation_up)
	basis = basis.rotated(plane_normal, float(rotation_seed % 4) * PI * 0.5)
	instance.global_transform = Transform3D(
		basis,
		position + plane_normal * (0.002 + float(_decal_nodes.size() % 4) * 0.0002),
	)
	_decal_nodes.append(instance)
	while _decal_nodes.size() > MAX_WORLD_DECALS:
		var evicted: Node3D = _decal_nodes.pop_front()
		if is_instance_valid(evicted):
			evicted.queue_free()
	_record(EVENT_WORLD_DECAL, {
		"asset": decal_name,
		"family": family,
		"position": position,
		"normal": plane_normal,
		"source_rgb": true,
		"blend_mode": BaseMaterial3D.BLEND_MODE_MUL,
	})
	return instance


func _spawn_sprite(
	asset_name: String,
	position: Vector3,
	scale_factor: float,
	fps: float,
	event_type: String,
	start_delay_ticks := 0,
	no_depth_test := false,
	color_modulate := Color.WHITE,
	velocity := Vector3.ZERO,
	source_roll_degrees := 0.0,
) -> MeshInstance3D:
	_load_manifest()
	var sprite: Dictionary = _manifest().get("sprites", {}).get(asset_name, {})
	if sprite.is_empty():
		return null
	var frame_paths: Array[String] = []
	for frame_path: Variant in sprite.frames:
		frame_paths.append("res://assets/vfx/%s" % str(frame_path))
	var frame_metadata: Array[Dictionary] = []
	for frame_data: Variant in sprite.get("frame_metadata", []):
		frame_metadata.append(frame_data)
	if frame_metadata.size() != frame_paths.size():
		for frame_path in frame_paths:
			frame_metadata.append({
				"texture": frame_path,
				"origin_x": -int(sprite.max_width) / 2,
				"origin_y": int(sprite.max_height) / 2,
				"width": int(sprite.max_width),
				"height": int(sprite.max_height),
			})
	var mesh := QuadMesh.new()
	var first_geometry := sprite_frame_geometry(frame_metadata[0], scale_factor)
	mesh.size = first_geometry.size
	mesh.center_offset = first_geometry.center_offset
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = (
		BaseMaterial3D.BLEND_MODE_ADD
		if int(sprite.texture_format) == 1
		else BaseMaterial3D.BLEND_MODE_MIX
	)
	var orientation := int(sprite.get("orientation", 2))
	material.billboard_mode = billboard_mode_for_orientation(orientation)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = no_depth_test
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.albedo_texture = load(frame_paths[0])
	material.albedo_color = color_modulate
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "GoldSrcSprite_%s" % asset_name
	instance.mesh = mesh
	add_child(instance)
	instance.global_position = position
	if orientation == 3 or orientation == 4:
		instance.rotation.z = deg_to_rad(source_roll_degrees)
	instance.visible = start_delay_ticks <= 0
	var duration_ticks := maxi(1, int(ceil(float(frame_paths.size()) / fps * TICK_RATE_HZ)))
	_sprites.append({
		"node": instance,
		"material": material,
		"frames": frame_paths,
		"frame_metadata": frame_metadata,
		"mesh": mesh,
		"scale_factor": scale_factor,
		"fps": fps,
		"color": color_modulate,
		"orientation": orientation,
		"source_roll_degrees": source_roll_degrees,
		"velocity": velocity,
		"start_tick": tick + start_delay_ticks,
		"expire_tick": tick + start_delay_ticks + duration_ticks,
		"frame_index": -1,
	})
	_record(event_type, {
		"asset": asset_name,
		"position": position,
		"scale": scale_factor,
		"fps": fps,
		"color": color_modulate,
		"orientation": orientation,
		"source_roll_degrees": source_roll_degrees,
		"velocity": velocity,
		"start_tick": tick + start_delay_ticks,
		"expire_tick": tick + start_delay_ticks + duration_ticks,
	})
	return instance


func _spawn_shell(
	shell_name: String,
	position: Vector3,
	velocity: Vector3,
	shot_sequence: int,
) -> Node3D:
	var template := _shell_template(shell_name)
	if template.is_empty():
		return null
	var shell := CharacterModelScript._create_instance(
		"GoldSrcShell_%s" % shell_name,
		template,
	)
	add_child(shell)
	shell.global_position = position
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motions.append({
		"node": shell,
		"velocity": velocity,
		"gravity": 8.0,
		"angular_velocity": Vector3(13.0, 21.0, 8.0)
			* (-1.0 if shot_sequence % 2 else 1.0),
		"expire_tick": tick + SHELL_LIFETIME_TICKS,
	})
	_record(EVENT_SHELL, {
		"asset": shell_name,
		"position": position,
		"velocity": velocity,
		"expire_tick": tick + SHELL_LIFETIME_TICKS,
	})
	return shell


func _spawn_impact_particles(
	position: Vector3,
	normal: Vector3,
	shot_sequence: int,
	surface: String,
) -> void:
	var particle_count := TE_SPARK_TRACER_COUNT if surface == "metal" else 3
	if surface == "metal":
		_spawn_spark_contract(position, normal, shot_sequence)
		_record(EVENT_IMPACT_PARTICLES, {
			"position": position,
			"normal": normal,
			"surface": surface,
			"count": particle_count,
			"shape": "gravity_tracer",
			"ricochet_count": 1,
		})
		return
	var tangent := normal.cross(
		Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	).normalized()
	var bitangent := normal.cross(tangent).normalized()
	for index in range(particle_count):
		var spread := (
			tangent * _signed_hash(shot_sequence + index, 73)
			+ bitangent * _signed_hash(shot_sequence + index, 89)
		)
		_spawn_gravity_tracer(
			position + normal * 0.01,
			normal * (0.35 + 0.1 * index) + spread * 0.22,
			3.0,
			12,
			Color("#83745f"),
			0.035,
		)
	_record(EVENT_IMPACT_PARTICLES, {
		"position": position,
		"normal": normal,
		"surface": surface,
		"count": particle_count,
		"shape": "gravity_tracer",
		"ricochet_count": 0,
	})


func _spawn_spark_shower(
	position: Vector3,
	normal: Vector3,
	count: int,
	seed: int,
) -> void:
	for shower_index in range(count):
		_spawn_spark_contract(position, normal, seed + shower_index * 11)
	_record(EVENT_HE_SPARKS, {
		"position": position,
		"normal": normal,
		"count": count,
		"tracer_count": count * TE_SPARK_TRACER_COUNT,
		"ricochet_count": count,
		"gravity": 8.0,
		"lifetime_ticks": TE_SPARK_LIFETIME_TICKS,
	})


func _spawn_spark_contract(
	position: Vector3,
	normal: Vector3,
	seed: int,
) -> void:
	var source_normal := normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var tangent := source_normal.cross(
		Vector3.UP if absf(source_normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	).normalized()
	var bitangent := source_normal.cross(tangent).normalized()
	for tracer_index in range(TE_SPARK_TRACER_COUNT):
		var trace_seed := seed * 31 + tracer_index
		var lateral := (
			tangent * _signed_hash(trace_seed, 101)
			+ bitangent * _signed_hash(trace_seed, 137)
		)
		var velocity := (
			source_normal * (0.4 + _unit_hash(trace_seed, 167) * 1.6)
			+ lateral * 2.0
		)
		_spawn_gravity_tracer(
			position,
			velocity,
			8.0,
			TE_SPARK_LIFETIME_TICKS,
			Color8(255, 167, 17),
			0.08,
		)
	_spawn_sprite(
		"richo1",
		position + source_normal * 0.01,
		0.35,
		10.0,
		EVENT_RICOCHET,
	)


func _spawn_gravity_tracer(
	position: Vector3,
	velocity: Vector3,
	gravity: float,
	lifetime_ticks: int,
	color: Color,
	length_meters: float,
	flicker_seed := -1,
) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(-velocity.normalized() * length_meters)
	mesh.surface_end()
	var tracer := MeshInstance3D.new()
	tracer.name = "GoldSrcGravityTracer"
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tracer)
	tracer.global_position = position
	_motions.append({
		"node": tracer,
		"velocity": velocity,
		"gravity": gravity,
		"angular_velocity": Vector3.ZERO,
		"material": material,
		"start_tick": tick,
		"flicker_seed": flicker_seed,
		"expire_tick": tick + lifetime_ticks,
	})
	return tracer


func _spawn_explosion_lights(
	owner: Node3D,
	position: Vector3,
	radius_meters: float,
	lifetime_ticks: int,
	seed: int,
) -> void:
	for light_index in range(TE_EXPLOSION_DLIGHT_COUNT):
		var light := OmniLight3D.new()
		light.name = (
			"GoldSrcExplosionDLight"
			if light_index == 0
			else "GoldSrcExplosionELight"
		)
		light.light_color = (
			Color8(255, 180, 80)
			if light_index == 0
			else Color8(255, 224, 160)
		)
		light.light_energy = 4.0 if light_index == 0 else 2.0
		light.omni_range = radius_meters * (1.0 if light_index == 0 else 0.5)
		light.shadow_enabled = false
		add_child(light)
		light.global_position = position
		_lights.append({
			"node": light,
			"owner": owner,
			"start_tick": tick,
			"expire_tick": tick + lifetime_ticks,
			"energy": light.light_energy,
			"range": light.omni_range,
			"kind": "dlight" if light_index == 0 else "elight",
		})
		_record(EVENT_HE_LIGHT, {
			"seed": seed,
			"kind": "dlight" if light_index == 0 else "elight",
			"position": position,
			"range": light.omni_range,
			"start_tick": tick,
			"expire_tick": tick + lifetime_ticks,
		})


func _spawn_flicker_particles(
	position: Vector3,
	lifetime_ticks: int,
	seed: int,
) -> void:
	var particle_lifetime := mini(lifetime_ticks, 50)
	for particle_index in range(TE_EXPLOSION_FLICKER_COUNT):
		var particle_seed := seed * 43 + particle_index
		var direction := Vector3(
			_signed_hash(particle_seed, 181),
			_signed_hash(particle_seed, 211),
			_signed_hash(particle_seed, 239),
		).normalized()
		_spawn_gravity_tracer(
			position,
			direction * (0.12 + _unit_hash(particle_seed, 251) * 0.28),
			0.0,
			particle_lifetime,
			Color8(255, 167, 17, 196),
			0.018,
			particle_seed,
		)
	_record(EVENT_HE_FLICKER, {
		"position": position,
		"count": TE_EXPLOSION_FLICKER_COUNT,
		"gravity": 0.0,
		"step_ticks": TE_EXPLOSION_FLICKER_STEP_TICKS,
		"palette": TE_EXPLOSION_FLICKER_PALETTE,
		"time_varying": true,
		"start_tick": tick,
		"expire_tick": tick + particle_lifetime,
	})


func _spawn_sound(path: String, position: Vector3, asset_name: String) -> void:
	# Audio playback is owned by CS16AudioEventRouter. Retain this semantic
	# record so VFX reference traces still prove which source temp-entity
	# requested each coupled sound without creating a second live voice.
	_record(EVENT_SOUND, {
		"asset": asset_name,
		"path": path,
		"position": position,
	})


func _update_sprites() -> void:
	for index in range(_sprites.size() - 1, -1, -1):
		var effect := _sprites[index]
		var node: MeshInstance3D = effect.node
		if not is_instance_valid(node) or tick >= int(effect.expire_tick):
			if is_instance_valid(node):
				node.queue_free()
			_sprites.remove_at(index)
			continue
		var start_tick := int(effect.start_tick)
		node.visible = tick >= start_tick
		if not node.visible:
			continue
		var velocity: Vector3 = effect.get("velocity", Vector3.ZERO)
		node.global_position += velocity * TICK_SECONDS
		var frames: Array[String] = effect.frames
		var frame_index := mini(
			frames.size() - 1,
			int(floor(float(tick - start_tick) * float(effect.fps) / TICK_RATE_HZ)),
		)
		if frame_index != int(effect.frame_index):
			var material: StandardMaterial3D = effect.material
			material.albedo_texture = load(frames[frame_index])
			var frame_metadata: Array[Dictionary] = effect.frame_metadata
			var geometry := sprite_frame_geometry(
				frame_metadata[frame_index],
				float(effect.scale_factor),
			)
			var mesh: QuadMesh = effect.mesh
			mesh.size = geometry.size
			mesh.center_offset = geometry.center_offset
			effect.frame_index = frame_index


func _update_motions() -> void:
	for index in range(_motions.size() - 1, -1, -1):
		var motion := _motions[index]
		var node: Node3D = motion.node
		if not is_instance_valid(node) or tick >= int(motion.expire_tick):
			if is_instance_valid(node):
				node.queue_free()
			_motions.remove_at(index)
			continue
		var velocity: Vector3 = motion.velocity
		node.global_position += velocity * TICK_SECONDS
		velocity.y -= float(motion.gravity) * TICK_SECONDS
		motion.velocity = velocity
		var angular_velocity: Vector3 = motion.angular_velocity
		node.rotation += angular_velocity * TICK_SECONDS
		var flicker_seed := int(motion.get("flicker_seed", -1))
		if flicker_seed >= 0:
			var age := tick - int(motion.start_tick)
			var phase := (
				age / TE_EXPLOSION_FLICKER_STEP_TICKS
				+ flicker_seed
			) % TE_EXPLOSION_FLICKER_PALETTE.size()
			var flicker_material: StandardMaterial3D = motion.material
			flicker_material.albedo_color = TE_EXPLOSION_FLICKER_PALETTE[phase]


func _update_lights() -> void:
	for index in range(_lights.size() - 1, -1, -1):
		var effect := _lights[index]
		var light: OmniLight3D = effect.node
		if not is_instance_valid(light) or tick >= int(effect.expire_tick):
			if is_instance_valid(light):
				light.queue_free()
			_lights.remove_at(index)
			continue
		var fraction := (
			float(tick - int(effect.start_tick))
			/ float(int(effect.expire_tick) - int(effect.start_tick))
		)
		var owner := effect.get("owner") as Node3D
		if is_instance_valid(owner):
			light.global_position = owner.global_position
		light.light_energy = float(effect.energy) * (1.0 - fraction)
		light.omni_range = float(effect.range) * (1.0 - fraction)


func _update_timed_nodes() -> void:
	for index in range(_timed_nodes.size() - 1, -1, -1):
		var timed := _timed_nodes[index]
		var node: Node = timed.node
		if not is_instance_valid(node) or tick >= int(timed.expire_tick):
			if is_instance_valid(node):
				node.queue_free()
			_timed_nodes.remove_at(index)


func _record(event_type: String, payload: Dictionary) -> void:
	var event := payload.duplicate(true)
	event.type = event_type
	event.tick = tick
	event.serial = _next_serial()
	event_log.append(event)


func _next_serial() -> int:
	var serial := _event_serial
	_event_serial += 1
	return serial


func _manifest() -> Dictionary:
	return _manifest_cache


func _load_manifest() -> void:
	if not _manifest_cache.is_empty():
		return
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing original combat VFX manifest: %s" % MANIFEST_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_manifest_cache = parsed


func _shell_template(shell_name: String) -> Dictionary:
	if _shell_template_cache.has(shell_name):
		return _shell_template_cache[shell_name]
	var path := "res://generated/effects/%s/model.json" % shell_name
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Missing original shell export: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or str(parsed.get("format", "")) != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 1
	):
		push_error("Invalid original shell export: %s" % path)
		return {}
	# The static world-model importer emits protocol47-mdl v1. Its geometry
	# schema is the same base schema consumed by the animated v2+ builder; it
	# simply has no external animation tapes.
	var template: Dictionary = CharacterModelScript._build_template(path, parsed)
	_shell_template_cache[shell_name] = template
	return template


static func _unit_hash(seed: int, salt: int) -> float:
	var value := (seed * 1103515245 + salt * 12345 + 1013904223) & 0x7fffffff
	return float(value % 10000) / 9999.0


static func _signed_hash(seed: int, salt: int) -> float:
	return _unit_hash(seed, salt) * 2.0 - 1.0
