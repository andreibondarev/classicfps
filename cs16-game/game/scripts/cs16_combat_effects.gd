class_name CS16CombatEffects
extends Node3D

signal presentation_ready
signal network_impact(kind: String, data: Dictionary)
signal world_audio_requested(
	event_name: String,
	channel: int,
	position: Vector3,
	overrides: Dictionary,
)

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
# CS 1.6 smoke grenade contract (CSmokeGrenade / gas cloud temp entities):
# a dense, ground-hugging cloud roughly 200+ units across that blocks vision
# for ~15 seconds before dissipating. Rendered GoldSrc-style as a cluster of
# large individual gas-puff billboards whose overlapping rounded silhouettes
# stay readable (per-puff shading variation), never as one uniform fog slab.
const SMOKE_CLOUD_PUFF_COUNT := 17
const SMOKE_CLOUD_CORE_PUFFS := 7
const SMOKE_CLOUD_LIFETIME_TICKS := 1500
const SMOKE_CLOUD_FADE_IN_TICKS := 60
const SMOKE_CLOUD_FADE_OUT_TICKS := 400
# Flat neutral gray with the faint warm cast of the gas_puff palette.
const SMOKE_CLOUD_COLOR := Color(0.68, 0.66, 0.63)
# GoldSrc muzzle-flash dlights (cl_dlight): ~0.1 s warm orange pop.
const MUZZLE_DLIGHT_TICKS := 9
const MUZZLE_DLIGHT_COLOR := Color8(255, 208, 128)
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
const EVENT_C4_FIREBALL := "c4_fireball"
const EVENT_SMOKE_CLOUD := "smoke_cloud"
const EVENT_IMPACT_PUFF := "impact_puff"
const EVENT_RICOCHET := "ricochet"
const EVENT_SOUND := "sound"

static var _manifest_cache: Dictionary = {}
static var _shell_template_cache: Dictionary = {}
static var _shell_mesh_cache: Dictionary = {}
static var _frame_texture_cache: Dictionary = {}
# BaseMaterial3D deletes its generated shader when the last matching material
# dies. Short-lived muzzle flashes and impact tracers otherwise compile that
# shader again on every volley (hundreds of ms on macOS OpenGL). Keep one
# material per finite render-state variant, not one per effect or shot.
static var _shader_material_cache: Dictionary = {}
static var _edge_faded_texture_cache: Dictionary = {}

var tick := 0
var _event_log := preload("res://scripts/bounded_event_log.gd").new()
var event_log: Array[Dictionary]:
	get:
		return _event_log.snapshot()
var total_effect_events: int:
	get:
		return _event_log.total_events
var _sprites: Array[Dictionary] = []
var _motions: Array[Dictionary] = []
var _lights: Array[Dictionary] = []
var _timed_nodes: Array[Dictionary] = []
var _decal_nodes: Array[Node3D] = []
var _event_serial := 0
var presentation_is_ready := false
var _presentation_warming := false


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
	_shell_mesh_cache.clear()
	_frame_texture_cache.clear()
	_shader_material_cache.clear()
	_manifest_cache.clear()
	_shot_decal_texture_cache.clear()
	_edge_faded_texture_cache.clear()


static func shot_profile(weapon_name: String, shot_sequence: int) -> Dictionary:
	match weapon_name:
		"ak47":
			return {
				# muzzleflash2: the round white-yellow core with short radial
				# spikes. The X-shaped muzzleflash3 frames read as a clip-art
				# star pinned to the handguard instead of a blast at the tip.
				"muzzle": "muzzleflash2",
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


func warm_up_presentation(entry_camera: Camera3D = null) -> void:
	if presentation_is_ready or _presentation_warming:
		return
	_presentation_warming = true
	if DisplayServer.get_name() != "headless":
		var entry_view: SubViewport
		if is_instance_valid(entry_camera) and entry_camera.is_inside_tree():
			# The deployment camera need not see the player's starting geometry
			# or viewmodel. Submit that exact world/projection offscreen as part
			# of loading without switching the visible camera or running AI.
			entry_view = SubViewport.new()
			entry_view.size = Vector2i(get_viewport().get_visible_rect().size)
			entry_view.world_3d = entry_camera.get_world_3d()
			entry_view.msaa_3d = get_viewport().msaa_3d
			entry_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(entry_view)
			var entry_projection := Camera3D.new()
			entry_projection.projection = entry_camera.projection
			entry_projection.keep_aspect = entry_camera.keep_aspect
			entry_projection.fov = entry_camera.fov
			entry_projection.size = entry_camera.size
			entry_projection.near = entry_camera.near
			entry_projection.far = entry_camera.far
			entry_projection.frustum_offset = entry_camera.frustum_offset
			entry_projection.h_offset = entry_camera.h_offset
			entry_projection.v_offset = entry_camera.v_offset
			entry_projection.cull_mask = entry_camera.cull_mask
			entry_projection.environment = entry_camera.environment
			entry_projection.attributes = entry_camera.attributes
			entry_view.add_child(entry_projection)
			entry_projection.global_transform = entry_camera.global_transform
			entry_projection.make_current()
		# Draw the finite effect variants into a tiny, undisplayed viewport while
		# the match is loading. Retained materials then keep their GL shaders
		# alive. Merely loading PNGs cannot warm a first-draw shader compilation.
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64, 64)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(viewport)
		# Environment-dependent GL specialization flags must match the live
		# viewport even for unshaded materials (ambient/radiance/tonemapping).
		var warm_environment := WorldEnvironment.new()
		warm_environment.environment = get_world_3d().environment
		viewport.add_child(warm_environment)
		viewport.msaa_3d = get_viewport().msaa_3d
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.make_current()
		var sun := DirectionalLight3D.new()
		sun.shadow_enabled = true
		viewport.add_child(sun)
		var staging := CS16CombatEffects.new()
		viewport.add_child(staging)
		staging.set_physics_process(false)
		for asset: String in _manifest().sprites:
			var sprite: Dictionary = _manifest().sprites[asset]
			for path: String in sprite.frames:
				_frame_texture("res://assets/vfx/" + path, asset in ["fexplo", "eexplo", "black_smoke3"])
			for variant in range(8):
				staging._spawn_sprite(
					asset, Vector3(0, 0, -2), 0.1, 30.0, "warmup", 0,
					bool(variant & 1), Color.WHITE, Vector3.ZERO,
					37.0 if variant & 2 else 0.0, 0, false, 0, 0, bool(variant & 4),
				)
		staging._spawn_gravity_tracer(Vector3(0, 0, -2), Vector3.RIGHT, 0.0, 10, Color.WHITE, 0.1)
		for decal_name: String in _manifest().decals:
			staging.spawn_decal(decal_name, Vector3(0, 0, -2), Vector3.BACK,
				"blood" if decal_name.begins_with("blood") else "shot", 0)
		staging._spawn_shell("rshell", Vector3(0, 0, -2), Vector3.ZERO, 0)
		staging._spawn_shell("pshell", Vector3(0, 0, -2), Vector3.ZERO, 0)
		# Planting introduces a per-pixel studio material and Sprite3D's LED
		# shader, neither of which is represented by the temp-entity sprites.
		# Keep this real visual as a hidden, inert shader owner after drawing it;
		# freeing its final material owners would discard the warmed GL programs.
		var planted_visual := CS16C4World.create_planted_visual()
		planted_visual.name = "PreparedC4Presentation"
		planted_visual.process_mode = Node.PROCESS_MODE_DISABLED
		viewport.add_child(planted_visual)
		planted_visual.position = Vector3(0, 0, -2)
		# First frame submits resources; the second covers deferred material
		# initialization. The viewport is never attached to a visible control.
		await _draw_preparation_frame()
		staging.spawn_muzzle_light(Vector3(0, 0, -1))
		# Warm the live world's positional-light specialization too. An almost
		# zero-energy light is visually imperceptible but still selects that
		# shader variant. It is removed before deployment, never kept in combat.
		var world_light := OmniLight3D.new()
		world_light.light_energy = 0.000001
		world_light.omni_range = 256.0
		add_child(world_light)
		var live_camera := get_viewport().get_camera_3d()
		if live_camera != null:
			world_light.global_position = live_camera.global_position
		await _draw_preparation_frame()
		await _draw_preparation_frame()
		world_light.queue_free()
		planted_visual.hide()
		planted_visual.reparent(self)
		viewport.queue_free()
		if is_instance_valid(entry_view):
			entry_view.queue_free()
		# Deferred staging teardown also belongs to loading. Do not enable the
		# match in the same frame that still has viewport/mesh frees queued.
		await _draw_preparation_frame()
	presentation_is_ready = true
	_presentation_warming = false
	presentation_ready.emit()


func _draw_preparation_frame() -> void:
	# Native macOS may suspend ordinary drawing while fully occluded. Waiting
	# only for frame_post_draw can then strand loading forever. Explicit draws
	# are confined to preparation, never injected into gameplay/timing samples.
	await get_tree().process_frame
	RenderingServer.force_draw()


func _physics_process(_delta: float) -> void:
	advance_tick()


func clear_event_log() -> void:
	_event_log.clear()


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
	# Anchored at the viewmodel barrel TIP (the GoldSrc muzzle attachment):
	# further forward and only slightly right/below screen center, where the
	# AK barrel actually ends on screen — never centered over the receiver.
	var muzzle_origin := origin + forward * 0.72 + right * 0.235 - up * 0.155
	# The engine muzzle flash: starts on a random frame of the flash sprite
	# with a random per-shot roll, fully additive, playing its painted frames
	# at the TE default 30 fps. A fixed frame-0 with zero roll read as a
	# repeated clip-art stamp; the frame+roll shuffle is exactly what makes
	# GoldSrc flashes look organic shot after shot.
	_spawn_sprite(
		str(profile.muzzle),
		muzzle_origin,
		0.14,
		30.0,
		EVENT_MUZZLE_FLASH,
		0,
		true,
		Color(1.0, 0.92, 0.74),
		Vector3.ZERO,
		_unit_hash(shot_sequence, 7) * 360.0,
		0,
		false,
		0,
		0,
		# Nearest sampling: the low-res additive muzzleflash frames must keep
		# their hard-edged spiky star texels when magnified at the first-person
		# muzzle; linear filtering melted them into a soft modern fireball.
		true,
		shot_sequence + int(_unit_hash(shot_sequence, 11) * 977.0),
	)
	# GoldSrc EV_..._MuzzleFlash also spawns a short-lived warm dlight that
	# visibly brightens the viewmodel and nearby geometry for one flash frame.
	spawn_muzzle_light(muzzle_origin)
	if not str(profile.smoke).is_empty():
		# Faint grey and drifting, and delayed past the flash frame: GoldSrc
		# muzzle smoke trails AFTER the additive flash. A dark alpha-blended
		# puff visible on the same frame as the flash rims its bright arms
		# with a brown fringe — the one artifact additive sprites can't show.
		_spawn_sprite(
			str(profile.smoke),
			muzzle_origin + forward * 0.035,
			0.10,
			30.0,
			EVENT_MUZZLE_SMOKE,
		4,
		false,
		Color(0.58, 0.57, 0.55, 0.30),
		forward * 0.10 + Vector3.UP * 0.16,
		)
	if not str(profile.shell).is_empty():
		# EjectBrass: the casing leaves the ejection PORT (behind the muzzle,
		# on the weapon's right side) and flies right and up. Anchoring off the
		# muzzle keeps the brass beside the receiver for both the first-person
		# viewmodel and third-person shooters.
		_spawn_shell(
			str(profile.shell),
			muzzle_origin - forward * 0.22 + right * 0.02 - up * 0.05,
			right * 1.9 + up * 1.25 + forward * 0.05,
			shot_sequence,
		)


func spawn_world_impact(
	position: Vector3,
	normal: Vector3,
	shot_sequence: int,
	surface := "concrete",
) -> void:
	var decal_name := "shot%d" % (shot_sequence % 5 + 1)
	network_impact.emit("impact", {"position": position, "normal": normal, "sequence": shot_sequence, "surface": surface})
	# Knife wall contact already owns knife_hitwall1.wav. Its impact packet still
	# carries the decal/puff to clients, but must not add a bullet ricochet.
	if surface != "knife":
		var impact_audio := "impact.bullet"
		if surface in ["metal", "grate", "vent", "computer"]:
			impact_audio = "impact.ricochet_metal"
		elif shot_sequence % 3 == 0:
			impact_audio = "impact.ricochet"
		world_audio_requested.emit(
			impact_audio,
			0, # CHAN_AUTO without introducing an effects/router preload cycle.
			position,
			{"pitch_min": 96, "pitch_max": 104},
		)
	spawn_decal(decal_name, position, normal, "shot", shot_sequence)
	var surface_normal := normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	# CS 1.6 wall impacts pair the crisp dark bullet-hole decal with a brief
	# SMALL light-gray dust puff: the original wall_puff1.spr animation, and
	# gone fast — the persistent mark must be the dark {shot chip decal, but
	# the puff itself must clearly read for its few frames.
	_spawn_sprite(
		"wall_puff1",
		position + surface_normal * 0.05,
		0.30,
		60.0,
		EVENT_IMPACT_PUFF,
		0,
		false,
		Color(0.62, 0.61, 0.58, 0.68),
		surface_normal * 0.20 + Vector3.UP * 0.10,
		0.0,
		18,
		false,
		12,
	)
	if shot_sequence % 3 == 0:
		_spawn_sprite(
			"richo1",
			position + surface_normal * 0.02,
			0.10,
			30.0,
			EVENT_RICOCHET,
		)
	_spawn_impact_particles(position, normal, shot_sequence, surface)


func spawn_blood_impact(
	position: Vector3,
	direction: Vector3,
	shot_sequence: int,
) -> void:
	var backwards := -direction.normalized()
	network_impact.emit("blood", {"position": position, "normal": direction, "sequence": shot_sequence, "surface": ""})
	# TE_BLOODSPRITE sprites are brief flat splashes, not large glossy volumes.
	_spawn_sprite(
		"bloodspray",
		position + backwards * 0.015,
		0.30,
		18.0,
		EVENT_BLOOD_SPRITE,
		0,
		false,
		BLOOD_COLOR_RED,
	)
	_spawn_sprite(
		"blood",
		position + backwards * 0.025,
		0.18,
		18.0,
		EVENT_BLOOD_SPRITE,
		1,
		false,
		BLOOD_COLOR_RED,
	)


func spawn_blood_decal(position: Vector3, normal: Vector3, shot_sequence: int) -> void:
	network_impact.emit("blood_decal", {"position": position, "normal": normal, "sequence": shot_sequence, "surface": ""})
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
	# Both stay essentially co-located so the pair superimposes into ONE
	# roughly spherical additive fireball about player height — never a tall
	# fire column with a detached second blob above it.
	# Each fireball is lifted by its own half-height so the billboard quad
	# bottom clears the floor plane: an intersecting quad depth-clips into a
	# razor-straight horizontal line, which GoldSrc additive sprites never show.
	# Scales sized so the taller fexplo billboard stands roughly player height
	# (96 px * 1.9 ≈ 1.8 m): the earlier 2.5/3.0 pair towered past the dust2
	# archways and read as a bonfire column instead of the compact spherical
	# fireball CS 1.6 shows at a detonation point.
	_spawn_te_explosion(
		"fexplo",
		position + Vector3.UP * (_sprite_half_height("fexplo", 1.9) + 0.06),
		1.9,
		30.0,
		serial,
		Color.WHITE,
	)
	var second_offset := Vector3(
		_signed_hash(serial, 17) * 0.26,
		_sprite_half_height("eexplo", 2.2) + 0.10 + _unit_hash(serial, 31) * 0.05,
		_signed_hash(serial, 47) * 0.26,
	)
	# Dim the second co-located additive sprite: two full-brightness stacked
	# fireballs summed to a blown-out white slab instead of keeping the
	# painted zerogxplode-style frame detail readable.
	_spawn_te_explosion(
		"eexplo",
		position + second_offset,
		2.2,
		30.0,
		serial + 1,
		Color(1.0, 1.0, 1.0, 0.62),
	)
	# Smoke3_C runs 0.55 seconds after Explode3 and uses steam1 at 5 fps.
	var steam_scale := 3.5 + _unit_hash(serial, 61)
	_spawn_sprite(
		"steam1",
		position + Vector3.UP * _sprite_half_height("steam1", steam_scale),
		steam_scale,
		5.0,
		EVENT_HE_SMOKE,
		HE_SMOKE_DELAY_TICKS,
		false,
		Color(1.0, 1.0, 1.0, 0.85),
		Vector3.ZERO,
		0.0,
		0,
		false,
		0,
		0,
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


func clear_smoke_clouds() -> void:
	for index in range(_sprites.size() - 1, -1, -1):
		if _sprites[index].event_type == EVENT_SMOKE_CLOUD:
			if is_instance_valid(_sprites[index].node):
				_sprites[index].node.queue_free()
			_sprites.remove_at(index)


func spawn_smoke_cloud(position: Vector3, seed := 0, fixed_seed := false) -> void:
	# CSmokeGrenade builds one large vision-blocking cloud out of overlapping
	# gas puffs. GoldSrc look: 10-15 LARGE billboard puffs whose individual
	# rounded silhouettes and per-puff shading (darker undersides) stay
	# readable against the background — a lumpy boiling cluster, never one
	# saturated featureless fog slab.
	var serial := _next_serial()
	var base_seed := seed * 131 if fixed_seed else serial * 7 + seed * 131
	var rim_count := SMOKE_CLOUD_PUFF_COUNT - SMOKE_CLOUD_CORE_PUFFS
	for index in range(SMOKE_CLOUD_PUFF_COUNT):
		var puff_seed := base_seed + index * 13
		# A few medium puffs pack the core so the interior blocks vision; the
		# rest are rim puffs distributed evenly (with jitter) around the core
		# and pushed well past it, so each rounded billboard silhouette bulges
		# out and the cloud reads as a lumpy cluster of distinct gas_puff
		# sprites, never one smooth slab.
		# Three tiers: packed core puffs that block vision, mid rim puffs whose
		# rounded edges bulge past the core, and small far satellites whose
		# lone translucent silhouettes break the outline into boiling lobes.
		var tier := (
			0
			if index < SMOKE_CLOUD_CORE_PUFFS
			else 1
			if index < SMOKE_CLOUD_CORE_PUFFS + rim_count - 3
			else 2
		)
		var core := tier == 0
		var angle := (
			_unit_hash(puff_seed, 17) * TAU
			if core
			else (
				float(index - SMOKE_CLOUD_CORE_PUFFS) / float(rim_count) * TAU
				+ _signed_hash(puff_seed, 17) * 0.38
			)
		)
		# Spawn radii are constrained so every puff overlaps the mass: CS smoke
		# is ONE ground-hugging cluster. Detached satellites drifting near
		# ceilings or crate tops read as stray blobs and depth-clip against
		# geometry at full prominence, which GoldSrc smoke never shows.
		var radius := 0.10 + _unit_hash(puff_seed, 31) * 0.40
		if tier == 1:
			radius = 0.70 + _unit_hash(puff_seed, 31) * 0.55
		elif tier == 2:
			radius = 1.05 + _unit_hash(puff_seed, 31) * 0.35
		var height := (
			0.25 + _unit_hash(puff_seed, 47) * 0.50
			if core
			else 0.05 + _unit_hash(puff_seed, 47) * (0.65 if tier == 1 else 0.35)
		)
		var offset := Vector3(cos(angle) * radius, height, sin(angle) * radius)
		var puff_scale := 2.3 + _unit_hash(puff_seed, 61) * 0.4
		if tier == 1:
			puff_scale = 1.45 + _unit_hash(puff_seed, 61) * 0.55
		elif tier == 2:
			puff_scale = 1.00 + _unit_hash(puff_seed, 61) * 0.35
		# GoldSrc sprites are fullbright flat gray — no painted-in shading —
		# and each puff is individually translucent (kRenderTransAlpha at
		# partial amount). Density then accumulates where puffs overlap, so
		# the cluster reads as distinct boiling lobes: rim puffs stay wispy
		# against the background while the packed core blocks vision.
		# Strong per-puff shade variance plus darker undersides: this is what
		# separates the overlapping billboard lobes into readable puffy volumes
		# instead of one smooth uniform fog mass. Tone stays muddy gray; the
		# packed core is near-opaque so it genuinely blocks vision.
		var shade := 0.78 + _signed_hash(puff_seed, 103) * 0.20
		shade -= maxf(0.0, 0.70 - height) * 0.12
		# Core puffs at full amount: stacked gas_puff alpha must integrate to a
		# genuinely opaque, vision-blocking center — the CS 1.6 smoke contract.
		var puff_alpha := 1.0
		if tier == 1:
			puff_alpha = 0.82
		elif tier == 2:
			puff_alpha = 0.62
		var puff_color := Color(
			SMOKE_CLOUD_COLOR.r * shade,
			SMOKE_CLOUD_COLOR.g * shade,
			SMOKE_CLOUD_COLOR.b * shade,
			puff_alpha,
		)
		var drift := (
			Vector3(cos(angle), 0.0, sin(angle))
			* (0.012 + _unit_hash(puff_seed, 73) * 0.018)
			+ Vector3.UP * 0.008
		)
		# The original gas_puff_01.spr: a rounded lumpy puff billboard, exactly
		# what CSmokeGrenade's client gas cloud renders. Bilinear sampling,
		# like the GoldSrc GL renderer: nearest magnified the 64px frames
		# into hard diamond texel blocks that read as mesh faceting.
		_spawn_sprite(
			"gas_puff_01",
			position + offset,
			puff_scale,
			2.0,
			EVENT_SMOKE_CLOUD,
			index * 4,
			false,
			puff_color,
			drift,
			_unit_hash(puff_seed, 89) * 360.0,
			SMOKE_CLOUD_LIFETIME_TICKS,
			true,
			SMOKE_CLOUD_FADE_OUT_TICKS,
			SMOKE_CLOUD_FADE_IN_TICKS,
			false,
			index % 2,
		)


func spawn_c4_explosion(position: Vector3, normal: Vector3, underwater := false) -> void:
	var serial := _next_serial()
	# CGrenade::Explode2 emits four large sprites. Scale 25 is derived from the
	# stock 500-damage C4 expression `(dmg - 275) * .6` / ten. Lateral spread
	# stays tight (well under the blast radius) so every fireball hangs in open
	# air near the bomb — a wide spread shoved quads inside nearby brush
	# geometry, smearing fire texture flat across walls.
	var offsets := [
		Vector3(0.0, -0.10, 0.0),
		Vector3(
			_signed_hash(serial, 17) * 0.95,
			_signed_hash(serial, 31) * 0.10,
			_signed_hash(serial, 47) * 0.95,
		),
		Vector3(
			_signed_hash(serial, 61) * 0.95,
			_signed_hash(serial, 73) * 0.10,
			_signed_hash(serial, 89) * 0.95,
		),
		Vector3(
			_signed_hash(serial, 101) * 0.95,
			_signed_hash(serial, 113) * 0.10,
			_signed_hash(serial, 127) * 0.95,
		),
	]
	# The fourth stock sprite is zerogxplode. The CS depot fixture carries only
	# fexplo/eexplo, so retain the exact fourth temp entity with fexplo until
	# that Half-Life base sprite is present in the verified asset corpus.
	var assets := ["fexplo", "eexplo", "fexplo", "fexplo"]
	for index in offsets.size():
		# Lift each fireball by its own billboard half-height (plus a stagger)
		# so no quad bottom ever intersects the floor plane: a floor-clipped
		# additive quad depth-cuts into a razor-straight line, and the tight
		# lateral spread above keeps quads out of nearby brush geometry so no
		# vertical clip edges smear fire across walls.
		var lifted: Vector3 = offsets[index] + Vector3.UP * (
			_sprite_half_height(assets[index], 2.0)
			+ 0.10
			+ 0.30 * float(index % 2)
		)
		var node := _spawn_sprite(
			assets[index],
			position + lifted,
			2.0,
			# All four Explode2 sprites play through their painted frames at the
			# TE default 15 fps; a near-static held first frame reads as a giant
			# white slab instead of the crisp flame tongues. Short per-sprite
			# stagger desynchronizes the four animations so overlapping additive
			# frames keep individual fireball structure instead of stacking into
			# one blown-out cream mass.
			15.0,
			EVENT_C4_FIREBALL,
			index * 4,
			false,
			Color(1.0, 0.86, 0.68, 0.55 if index > 0 else 1.0),
			Vector3.ZERO,
			0.0,
			0,
			false,
			0,
			0,
			false,
			0,
			# Edge fade: the ember/noise frames paint texels to the border;
			# without the rim fade the fireball terminated in straight quad
			# lines against the ground and crates.
			true,
		)
		# One dlight pair for the whole detonation: four stacked pairs turned
		# the pavement incandescent red instead of leaving flat black scorch.
		if index == 0 and is_instance_valid(node):
			_spawn_explosion_lights(node, node.position, 2.4, 70, serial + index)
	# Explode2's aftermath: rolling DARK gray smoke columns framing the orange
	# fireballs, delayed until the flame tongues have developed. Kept smaller
	# and darker than the fireballs so the detonation reads as distinct fire
	# plus structured smoke, never one washed-out cream cloud.
	for smoke_index in range(3):
		var smoke_seed := serial * 19 + smoke_index * 7
		var smoke_offset := Vector3(
			_signed_hash(smoke_seed, 141) * 1.2,
			1.1 + _unit_hash(smoke_seed, 151) * 0.7,
			_signed_hash(smoke_seed, 163) * 1.2,
		)
		# The original black_smoke3.spr rolling-smoke animation, modulated dark
		# gray exactly like GoldSrc black-smoke temp entities (INDEXALPHA base
		# tinted by render color). Kept translucent so it reads as separate
		# rising smoke sprites, never one opaque cotton mass.
		_spawn_sprite(
			"black_smoke3",
			position + smoke_offset,
			2.3 + _unit_hash(smoke_seed, 173) * 0.9,
			15.0,
			EVENT_HE_SMOKE,
			55 + smoke_index * 14,
			false,
			Color(0.34, 0.33, 0.32, 0.58),
			Vector3.UP * 0.22,
			0.0,
			420,
			true,
			160,
			35,
			false,
			0,
			true,
		)
	spawn_decal(
		"scorch%d" % (serial % 2 + 1),
		position,
		normal,
		"scorch",
		serial,
	)
	# Explode2 suppresses only its spark shower when PointContents is water.
	if not underwater:
		_spawn_spark_shower(position, normal, serial % 4, serial)


func _sprite_half_height(asset_name: String, scale_factor: float) -> float:
	# World-space half-height of the sprite's billboard quad; used to lift
	# floor-level effects so their quads never depth-clip against the ground.
	_load_manifest()
	var sprite: Dictionary = _manifest().get("sprites", {}).get(asset_name, {})
	return float(sprite.get("max_height", 0)) * 0.01 * scale_factor * 0.5


func _spawn_te_explosion(
	asset_name: String,
	position: Vector3,
	scale_factor: float,
	fps: float,
	seed: int,
	color_modulate := Color.WHITE,
) -> void:
	var sprite_node := _spawn_sprite(
		asset_name,
		position,
		scale_factor,
		fps,
		EVENT_HE_FIREBALL,
		0,
		false,
		color_modulate,
		Vector3.UP * TE_EXPLOSION_RISE_METERS_PER_SECOND,
		0.0,
		0,
		false,
		0,
		0,
		# Linear sampling: the GoldSrc GL renderer draws sprites bilinearly.
		# Nearest magnified the painted frames into hard chunky noise squares.
		false,
		0,
		# Edge fade: the painted low-level glow must die before the quad edge
		# so no straight billboard boundary shows over sky or brushwork.
		true,
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
	# Blood stamps in CS 1.6 read as several small hard splats, not one large
	# smeared sheet; keep them well under half the exported quad size. Bullet
	# holes get a modest boost: the {shot chip occupies only the middle of its
	# 16x16 canvas, and at source scale the dark hole disappeared into wall
	# noise instead of clearly reading as a hole.
	var family_size_scale := 1.0
	if family == "blood":
		family_size_scale = 0.55
	elif family == "shot":
		# Close to source scale: the earlier 1.4x blow-up magnified the 16x16
		# {shot chip into a blurry palm-sized diamond smudge instead of the
		# small crisp CS 1.6 bullet hole.
		family_size_scale = 0.95
	mesh.size = Vector2(
		float(decal.width) * 0.01 * family_size_scale,
		float(decal.height) * 0.01 * family_size_scale,
	)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	# The destination already contains the surface lighting. Lighting this
	# modulation mask again turns its white surround into a dark rectangle.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Bilinear sampling, exactly like the GoldSrc GL renderer draws decals:
	# nearest sampling magnified the 3-4 texel {shot pockmark into solid hard
	# squares; linear restores the round soft-edged pockmark falloff.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The boosted texture does not retain its source PNG. Keep that source
	# resident too, otherwise every impact reloads it before the boost-cache hit.
	var decal_texture := _frame_texture("res://assets/vfx/%s" % str(decal.texture), false)
	if family == "shot":
		# GoldSrc converts {-prefixed decals into darkness-alpha textures
		# (R_DecalTexture) and stamps them as near-black marks. The straight
		# WAD-RGB export leaves the tiny pockmark at only ~0.4-0.55 multiply,
		# which vanishes into busy wall texels. A gamma curve on the multiply
		# mask restores the original dark shot hole while leaving the white
		# (identity) surround untouched. 1.7 keeps the hole dark without
		# spreading the darkening into the surround (2.4 smeared the whole
		# quad into a soft dark diamond).
		decal_texture = _boosted_decal_texture(decal_name, decal_texture, 1.7)
	elif family == "blood":
		# CS 1.6 {blood decals multiply to a dark dried-maroon stain. The raw
		# WAD RGB stamps as a flat bright red sheet; the same darkness curve
		# restores the maroon tone and the palette-noise variation while the
		# white surround stays identity.
		decal_texture = _boosted_decal_texture(decal_name, decal_texture, 1.8)
	material.albedo_texture = decal_texture
	# The imported PNG retains the original WAD RGB. White is the
	# multiplicative identity, exactly matching GoldSrc decal modulation
	# against the already-lit destination surface.
	material.albedo_color = Color.WHITE
	# Godot 4.7 Mobile divides fragment RGB by two for its non-HDR2D
	# framebuffer before multiply blending. Restore multiplicative identity;
	# the material's color input is sRGB, so express the factor in that space.
	if RenderingServer.get_current_rendering_method() == "mobile" and not get_viewport().use_hdr_2d:
		material.albedo_color = Color(2.0, 2.0, 2.0).linear_to_srgb()
	_retain_shader_material("decal", material)
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
	# R_DecalShoot applies a random full-circle roll per decal; 90-degree
	# steps left every {shot chip with an identical readable orientation.
	basis = basis.rotated(plane_normal, _unit_hash(rotation_seed, 53) * TAU)
	# ~1.2 cm lift off the surface: brush visual faces (breakable crates run
	# through a collision proxy) can sit a few millimetres proud of the physics
	# surface the impact ray hit, and a 2 mm offset left decals buried inside
	# the visible face. Still far below a readable air gap at play distances.
	instance.global_transform = Transform3D(
		basis,
		position + plane_normal * (0.012 + float(_decal_nodes.size() % 4) * 0.0008),
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


static var _shot_decal_texture_cache: Dictionary = {}


static func _boosted_decal_texture(
	decal_name: String,
	source: Texture2D,
	gamma: float,
) -> Texture2D:
	if source == null:
		return source
	if _shot_decal_texture_cache.has(decal_name):
		return _shot_decal_texture_cache[decal_name]
	var image := source.get_image()
	if image == null:
		return source
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			color.r = pow(color.r, gamma)
			color.g = pow(color.g, gamma)
			color.b = pow(color.b, gamma)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	var boosted := ImageTexture.create_from_image(image)
	_shot_decal_texture_cache[decal_name] = boosted
	return boosted


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
	lifetime_ticks_override := 0,
	loop_frames := false,
	fade_out_ticks := 0,
	fade_in_ticks := 0,
	nearest_filter := false,
	frame_offset := 0,
	edge_fade := false,
) -> MeshInstance3D:
	_load_manifest()
	var sprite: Dictionary = _manifest().get("sprites", {}).get(asset_name, {})
	if sprite.is_empty():
		push_error("Missing required combat sprite: " + asset_name)
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
	if frame_offset > 0 and frame_paths.size() > 1:
		# Random start frame (engine muzzle-flash style): rotate the frame ring
		# so playback begins on the requested frame.
		var start := frame_offset % frame_paths.size()
		frame_paths = frame_paths.slice(start) + frame_paths.slice(0, start)
		frame_metadata = frame_metadata.slice(start) + frame_metadata.slice(0, start)
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
	# GoldSrc VP_PARALLEL sprites support per-entity roll (the random muzzle
	# flash roll). Godot's material billboard discards node rotation, so rolled
	# parallel sprites face the camera manually each tick instead.
	var face_camera_roll := (
		(orientation == 2 or orientation == 0 or orientation == 1)
		and absf(source_roll_degrees) > 0.001
	)
	if face_camera_roll:
		material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = no_depth_test
	# GoldSrc sprites are low-res paletted frames; nearest sampling keeps their
	# dithered texel crunch readable when a frame is magnified across the
	# screen (smoke, explosions), while small transient sprites stay linear.
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		if nearest_filter
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	)
	material.albedo_texture = _frame_texture(frame_paths[0], edge_fade)
	material.albedo_color = color_modulate
	_retain_shader_material(
		"sprite:%d:%d:%d:%d" % [
			material.blend_mode, material.billboard_mode,
			int(material.no_depth_test), material.texture_filter,
		],
		material,
	)
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "GoldSrcSprite_%s" % asset_name
	instance.mesh = mesh
	add_child(instance)
	instance.global_position = position
	if orientation == 3 or orientation == 4:
		instance.rotation.z = deg_to_rad(source_roll_degrees)
	elif face_camera_roll:
		_face_camera_with_roll(instance, source_roll_degrees)
	instance.visible = start_delay_ticks <= 0
	var duration_ticks := maxi(1, int(ceil(float(frame_paths.size()) / fps * TICK_RATE_HZ)))
	if lifetime_ticks_override > 0:
		duration_ticks = lifetime_ticks_override
	_sprites.append({
		"event_type": event_type,
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
		"loop_frames": loop_frames,
		"face_camera_roll": face_camera_roll,
		"edge_fade": edge_fade,
		"fade_out_ticks": fade_out_ticks,
		"fade_in_ticks": fade_in_ticks,
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


static func _retain_shader_material(key: String, material: StandardMaterial3D) -> void:
	if not _shader_material_cache.has(key):
		_shader_material_cache[key] = material


static func _frame_texture(path: String, edge_fade: bool) -> Texture2D:
	# Retain source frames between effects. ResourceLoader's cache alone does
	# not keep an otherwise unreferenced frame alive after a sprite advances.
	if edge_fade and _edge_faded_texture_cache.has(path):
		return _edge_faded_texture_cache[path]
	if not _frame_texture_cache.has(path):
		_frame_texture_cache[path] = load(path) as Texture2D
	var source := _frame_texture_cache[path] as Texture2D
	if not edge_fade or source == null:
		return source
	# GoldSrc's big explosion frames paint low-level glow haze right up to the
	# sprite border. At CS scales that reveals the billboard's straight quad
	# edges as hard lines over the sky and against geometry. Rolling the outer
	# rim of every frame smoothly to zero keeps the painted interior intact
	# while guaranteeing the additive/alpha content dies before the quad edge.
	var image := source.get_image()
	if image == null:
		return source
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var width := image.get_width()
	var height := image.get_height()
	var margin := maxf(2.0, minf(width, height) * 0.16)
	for y in range(height):
		for x in range(width):
			var border := float(mini(mini(x, width - 1 - x), mini(y, height - 1 - y)))
			if border >= margin:
				continue
			var fraction := border / margin
			var factor := fraction * fraction * (3.0 - 2.0 * fraction)
			var color := image.get_pixel(x, y)
			color.r *= factor
			color.g *= factor
			color.b *= factor
			color.a *= factor
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	var faded := ImageTexture.create_from_image(image)
	_edge_faded_texture_cache[path] = faded
	return faded


func _face_camera_with_roll(node: Node3D, roll_degrees: float) -> void:
	# Manual VP_PARALLEL billboard with sprite roll: aim the quad's +Z at the
	# active camera, then roll around the view axis.
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if not is_instance_valid(camera):
		return
	var forward := node.global_position - camera.global_position
	if forward.length_squared() < 0.000001:
		return
	forward = forward.normalized()
	var reference_up := (
		Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	)
	var basis := Basis.looking_at(forward, reference_up)
	basis = basis.rotated(basis.z, deg_to_rad(roll_degrees))
	node.global_basis = basis


func _spawn_shell(
	shell_name: String,
	position: Vector3,
	velocity: Vector3,
	shot_sequence: int,
) -> Node3D:
	var template := _shell_template(shell_name)
	if template.is_empty():
		return null
	# Brass has immutable geometry/materials; only its instance transform moves.
	# Upload each shell type once instead of rebuilding it for every bullet.
	if not _shell_mesh_cache.has(shell_name):
		var source := CharacterModelScript._create_instance("ShellTemplate", template)
		_shell_mesh_cache[shell_name] = source.mesh
		source.free()
	var shell := MeshInstance3D.new()
	shell.name = "GoldSrcShell_%s" % shell_name
	shell.mesh = _shell_mesh_cache[shell_name]
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
			10,
			# Dim additive chips: at full brightness the short debris lines read
			# as white wireframe artifacts stamped over nearby decals.
			Color(0.51, 0.45, 0.37, 0.55),
			0.028,
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
	_retain_shader_material("gravity_tracer", material)
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


func spawn_muzzle_light(position: Vector3) -> void:
	# The GoldSrc muzzle-flash dlight: a brief warm point light that visibly
	# brightens the viewmodel and nearby geometry while the flash sprite is up.
	# Intentionally not recorded: it is a client-side dlight, not a temp entity.
	var light := OmniLight3D.new()
	light.name = "GoldSrcMuzzleDLight"
	light.light_color = MUZZLE_DLIGHT_COLOR
	light.light_energy = 1.5
	light.omni_range = 3.2
	light.shadow_enabled = false
	add_child(light)
	light.global_position = position
	_lights.append({
		"node": light,
		"owner": null,
		"start_tick": tick,
		"expire_tick": tick + MUZZLE_DLIGHT_TICKS,
		"energy": light.light_energy,
		"range": light.omni_range,
		"kind": "muzzle_dlight",
	})


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
		# GoldSrc explosion dlights are tight and short-lived; keep them subtle so
		# the hand-painted additive sprite reads instead of blowing every nearby
		# surface out to uniform white.
		light.light_energy = 0.7 if light_index == 0 else 0.35
		light.omni_range = radius_meters * (0.5 if light_index == 0 else 0.25)
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
		if bool(effect.get("face_camera_roll", false)):
			_face_camera_with_roll(node, float(effect.get("source_roll_degrees", 0.0)))
		var fade_in := int(effect.get("fade_in_ticks", 0))
		var fade_out := int(effect.get("fade_out_ticks", 0))
		if fade_in > 0 or fade_out > 0:
			var alpha := 1.0
			var age := tick - start_tick
			if fade_in > 0 and age < fade_in:
				alpha = minf(alpha, float(age) / float(fade_in))
			var remaining := int(effect.expire_tick) - tick
			if fade_out > 0 and remaining < fade_out:
				alpha = minf(alpha, float(remaining) / float(fade_out))
			var base_color: Color = effect.color
			var faded := base_color
			faded.a = base_color.a * clampf(alpha, 0.0, 1.0)
			var fade_material: StandardMaterial3D = effect.material
			fade_material.albedo_color = faded
		var frames: Array[String] = effect.frames
		var raw_frame := int(
			floor(float(tick - start_tick) * float(effect.fps) / TICK_RATE_HZ)
		)
		var frame_index := (
			raw_frame % frames.size()
			if bool(effect.get("loop_frames", false))
			else mini(frames.size() - 1, raw_frame)
		)
		if frame_index != int(effect.frame_index):
			var material: StandardMaterial3D = effect.material
			material.albedo_texture = _frame_texture(
				frames[frame_index],
				bool(effect.get("edge_fade", false)),
			)
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
		# The shooter may have been freed (disconnected) while the light fades;
		# never cast a freed reference.
		var owner_value: Variant = effect.get("owner")
		var owner: Node3D = owner_value as Node3D if is_instance_valid(owner_value) else null
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
	_event_log.append(event)


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
