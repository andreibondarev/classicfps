class_name CS16BreakableDebrisPresenter
extends Node3D

## Visual consumer for CS16BreakableRuntime's deterministic TE_BREAKMODEL
## descriptors. Every shard uses converted stock MDL geometry; unsupported
## source paths produce an explicit missing-asset record and no placeholder.

signal presentation_event(event: Dictionary)

const CharacterModel := preload("res://scripts/mdl_character_model.gd")
const HostageActor := preload("res://scripts/cs16_hostage.gd")

const TICK_RATE := 100
const TICK_SECONDS := 1.0 / float(TICK_RATE)
const GOLDSRC_UNIT := 0.01
const SOURCE_CLIENT_SHARD_COUNT := 8
const MAX_SHARDS_PER_EVENT := 32
## GoldSrc's client derives the shard count from the brush extents when the
## TE_BREAKMODEL count byte is zero; one shard per ~12 summed HU reproduces the
## stock burst density (a destroyed crate showers 8-16 chunky gibs, a full
## window far more glass than a small pane).
const SHARD_COUNT_SIZE_DIVISOR_HU := 8.0
## Some gib bodies are authored far larger than they ever read in CS 1.6
## (glassgibs' ~46x74 HU curved pane, computergibs' full keyboard and case
## panels). Clamp each family's longest shard extent to fist-sized chunks.
const FAMILY_MAX_EXTENT_HU := {
	"glassgibs": 30.0,
	"computergibs": 15.0,
}
## computergibs.mdl bodies 7 and 14 are curled 1-texel-wide wire bundles that
## rasterize as red/blue hairline glitches at playfield distance; GoldSrc gets
## away with them at 640x480 additive blur, a crisp renderer does not.
const SKIPPED_BODY_VARIANTS := {
	"computergibs": [7, 14],
}
## kRenderTransTexture (the TE_BREAKMODEL BREAK_TRANS render mode) draws glass
## translucent: texture color at ~45% alpha with the faint blue-green cast of
## the chrome-glass skin, so the floor reads through every shard.
const GLASS_ALPHA := 0.45
const GLASS_LIGHT_MIX := 0.2
## The converted chome_glass sheet is near-white (GoldSrc darkens it through
## chrome env-mapping at runtime); pre-darken toward 1.6's mid blue-green glass
## so a translucent shard never reads brighter than the surface behind it.
const GLASS_TINT := Color(0.44, 0.60, 0.58)
## GoldSrc maps chome_glass through screen-space chrome UVs, so every shard
## catches a different band of the gradient. World-triplanar sampling of the
## same sheet reproduces that: each facet's orientation/position picks its own
## band, giving the specular-looking streaks of 1.6 glass instead of one flat
## average color. Scale chosen so a fist-sized shard spans about half the
## 64x64 gradient sheet.
const GLASS_CHROME_UV_SCALE := Vector3(2.4, 2.4, 2.4)
## Per-shard chrome response spread: shards angled toward the light source in
## GoldSrc read brighter than edge-on ones. A deterministic brightness spread
## sells the varied gradient banding across a pile of settled shards.
const GLASS_SHINE_MIN := 0.72
const GLASS_SHINE_MAX := 1.35
## GoldSrc gib bodies are authored volumetric, but the thinnest wood/crate
## splinters are ~1 HU deep and vanish edge-on in a crisp renderer. Thicken the
## model's thin axis to a minimum prism depth (glass stays authored-thin).
const MIN_SOLID_THICKNESS := 0.022
## TE_BREAKMODEL sizes each shard by a random 0.5..1.5-ish factor server-side;
## a deterministic per-shard spread keeps sibling splinters from reading as
## clones of one authored body.
const SHARD_SCALE_MIN := 0.68
const SHARD_SCALE_MAX := 1.32
## Settled shards must not interpenetrate: GoldSrc gibs scatter over a radius
## and rest as discrete pieces, never as one starburst clump. When a shard
## grounds inside another settled shard's footprint it slides out along the
## floor until the pieces are separated.
const REST_SEPARATION_SCALE := 0.38
const REST_SEPARATION_PASSES := 4
const GRAVITY := Vector3(0.0, -8.0, 0.0)
const COLLISION_MASK := 1
const COLLISION_EPSILON := 0.002
const BOUNCE_RESTITUTION := 0.34
const SURFACE_FRICTION := 0.72
const BOUNCE_SPIN_DAMPING := 0.55
## Generous settle window: bounce damping kills tumble in a couple of hits,
## and a slow shard frozen mid-tumble reads as debris balanced on end. Once a
## shard is this slow on a walkable surface it lies down immediately, like
## GoldSrc gibs that stop simulating and rest flat.
const SETTLE_SPEED := 0.35
const SETTLE_NORMAL_Y := 0.62
const SETTLE_BOUNCE_LIMIT := 3
const LIGHT_FLOOR := 0.12
const MISSED_LIGHT_FALLBACK := Color(0.4, 0.4, 0.4)

const SUPPORTED_GIBS := [
	"ceilinggibs",
	"cindergibs",
	"computergibs",
	"fleshgibs",
	"glassgibs",
	"metalplategibs",
	"mil_crategibs",
	"woodgibs",
]

static var _template_cache: Dictionary = {}
static var _variant_cache: Dictionary = {}
static var _bounds_cache: Dictionary = {}

var presentation_log: Array[Dictionary] = []

var _runtime: RefCounted
var _motions: Dictionary = {}
var _shard_serial := 0
var _light_map_node: Node3D
var _light_map_resolved := false


static func release_cached_resources() -> void:
	_template_cache.clear()
	_variant_cache.clear()
	_bounds_cache.clear()


func bind_runtime(runtime: RefCounted) -> void:
	var callback := Callable(self, "_on_runtime_event")
	if (
		_runtime != null
		and _runtime.is_connected("runtime_event", callback)
	):
		_runtime.disconnect("runtime_event", callback)
	_runtime = runtime
	if (
		_runtime != null
		and not _runtime.is_connected("runtime_event", callback)
	):
		_runtime.connect("runtime_event", callback)


func present_debris(descriptor: Dictionary) -> int:
	if str(descriptor.get("event", "")) != "debris":
		return 0
	var source_model := str(descriptor.get("gib_model", ""))
	var gib_name := source_model.get_file().get_basename()
	if gib_name not in SUPPORTED_GIBS:
		_record({
			"event": "asset_missing",
			"gib_model": source_model,
			"entity_id": int(descriptor.get("entity_id", -1)),
		})
		return 0
	var gib_root := "res://generated/gibs/%s" % gib_name
	var variant_paths := _load_variant_paths(gib_root)
	if variant_paths.is_empty():
		_record({
			"event": "asset_missing",
			"gib_model": source_model,
			"model_path": gib_root.path_join("variants.json"),
			"entity_id": int(descriptor.get("entity_id", -1)),
		})
		return 0

	var seed := int(descriptor.get("seed", 0))
	var origin: Vector3 = descriptor.get("origin", Vector3.ZERO)
	var size: Vector3 = descriptor.get("size", Vector3.ZERO)
	var base_velocity: Vector3 = descriptor.get("velocity", Vector3.ZERO)
	var is_glass := str(descriptor.get("break_flag_name", "")) == "glass"
	var requested_count := int(descriptor.get("shard_count", 0))
	var shard_count := requested_count
	if requested_count <= 0:
		# Source client behavior for count 0: shard density scales with the
		# broken brush's extents, so a full window showers far more glass than
		# a small crate.
		var summed_extents_hu := (size.x + size.y + size.z) / GOLDSRC_UNIT
		shard_count = clampi(
			roundi(summed_extents_hu / SHARD_COUNT_SIZE_DIVISOR_HU),
			SOURCE_CLIENT_SHARD_COUNT,
			MAX_SHARDS_PER_EVENT,
		)
	shard_count = clampi(shard_count, 1, MAX_SHARDS_PER_EVENT)
	var randomization_hu := float(descriptor.get("randomization", 10))
	var lifetime_ticks := maxi(
		1,
		roundi(
			float(descriptor.get("duration_seconds", 2.5))
			* float(TICK_RATE)
		),
	)
	var allowed_variants: Array[int] = []
	var skipped: Array = SKIPPED_BODY_VARIANTS.get(gib_name, [])
	for candidate_index in range(variant_paths.size()):
		if candidate_index not in skipped:
			allowed_variants.append(candidate_index)
	if allowed_variants.is_empty():
		return 0
	var presented_variants: Array[int] = []
	# GoldSrc lights break debris like any studio model: from the lightmap of
	# the floor beneath the gib itself. A wall panel breaking over a dark alley
	# floor must shed dark planks, so each shard samples under its own spawn
	# point (and re-samples where it finally settles) instead of inheriting the
	# possibly sunlit brightness of the break center.
	var light_color := _break_site_light(origin)
	for shard_index in range(shard_count):
		var ring_position := posmod(
			_hash_int(seed, 17) + shard_index,
			allowed_variants.size(),
		)
		var variant_index := allowed_variants[ring_position]
		var model_path := gib_root.path_join(str(variant_paths[variant_index]))
		var template := _load_template(model_path)
		# glassgibs contains one authored blank body. GoldSrc can select it, but
		# a presentation shard must never fall back to a primitive or duplicate
		# body zero. Walk the authored ring to the next renderable body.
		var attempts := 1
		while template.is_empty() and attempts < allowed_variants.size():
			ring_position = (ring_position + 1) % allowed_variants.size()
			variant_index = allowed_variants[ring_position]
			model_path = gib_root.path_join(str(variant_paths[variant_index]))
			template = _load_template(model_path)
			attempts += 1
		if template.is_empty():
			continue
		var shard := Node3D.new()
		shard.name = "Authentic_%s_%03d" % [gib_name, _shard_serial]
		var mesh := CharacterModel._create_instance(
			"%sMesh" % gib_name,
			template,
		)
		# GoldSrc never shadow-casts temp-entity gibs; debris brightness comes
		# solely from the baked break-site light modulate.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shard.add_child(mesh)
		add_child(shard)
		# Deterministic per-shard size spread mirrors TE_BREAKMODEL's random
		# shard sizing and stops sibling splinters reading as clones.
		var shard_scale := lerpf(
			SHARD_SCALE_MIN,
			SHARD_SCALE_MAX,
			_unit_hash(seed, shard_index * 31 + 12),
		)
		var max_extent := (
			float(FAMILY_MAX_EXTENT_HU.get(gib_name, 0.0)) * GOLDSRC_UNIT
		)
		if max_extent > 0.0:
			var extents := _template_bounds(model_path).size
			var longest := maxf(extents.x, maxf(extents.y, extents.z))
			if longest * shard_scale > max_extent:
				shard_scale = max_extent / longest
		shard.scale = Vector3.ONE * shard_scale
		var thin_axis := _template_thin_axis(model_path)
		var half_thickness := _template_half_thickness(model_path) * shard_scale
		if not is_glass:
			# Thicken paper-thin authored splinters into shallow prisms so an
			# edge-on shard keeps a visible silhouette; glass stays sheet-thin.
			var thin_extent := half_thickness * 2.0
			if thin_extent < MIN_SOLID_THICKNESS and thin_extent > 0.0:
				var thicken := MIN_SOLID_THICKNESS / thin_extent
				var mesh_scale := Vector3.ONE
				mesh_scale[thin_axis] = thicken
				mesh.scale = mesh_scale
				half_thickness = MIN_SOLID_THICKNESS * 0.5
		var spawn_offset := Vector3(
			_signed_hash(seed, shard_index * 11 + 1) * size.x * 0.45,
			_unit_hash(seed, shard_index * 11 + 2) * size.y * 0.35,
			_signed_hash(seed, shard_index * 11 + 3) * size.z * 0.45,
		)
		# Never materialize a shard inside a neighboring brush: walk the spawn
		# ray from the break center and stop just short of the first surface.
		var clearance := _trace_world(origin, origin + spawn_offset, shard)
		if not clearance.is_empty() and clearance.get("normal", Vector3.ZERO) != Vector3.ZERO:
			spawn_offset = (
				(clearance.get("position", origin) as Vector3) - origin
			) * 0.8
		shard.global_position = origin + spawn_offset
		var glass_shine := lerpf(
			GLASS_SHINE_MIN,
			GLASS_SHINE_MAX,
			_unit_hash(seed, shard_index * 47 + 3),
		)
		shard.set_meta("glass_shine", glass_shine)
		_apply_shard_material(
			mesh,
			_shard_site_light(shard.global_position, light_color),
			is_glass,
			glass_shine,
		)
		# Long gib slivers read wrong when their long axis spawns upright, so
		# pitch/roll start shy of vertical while spin still tumbles them
		# through every orientation in flight.
		shard.rotation = Vector3(
			_signed_hash(seed, shard_index * 19 + 4) * 0.28 * PI,
			_unit_hash(seed, shard_index * 23 + 5) * TAU,
			_signed_hash(seed, shard_index * 29 + 6) * 0.28 * PI,
		)
		# GoldSrc gives every shard an independent outward fling plus upward
		# pop, both scaled by the TE_BREAKMODEL randomization byte, so debris
		# scatters over roughly a meter instead of collapsing into one clump.
		var outward := Vector3(spawn_offset.x, 0.0, spawn_offset.z)
		if outward.length_squared() < 0.000001:
			var scatter_yaw := _unit_hash(seed, shard_index * 11 + 10) * TAU
			outward = Vector3(cos(scatter_yaw), 0.0, sin(scatter_yaw))
		else:
			outward = outward.normalized()
		var random_scale := randomization_hu * 0.01
		# Stock break bursts fling gibs at roughly 50-150 HU/s outward; the
		# wide spread (plus per-shard jitter) scatters rest positions over a
		# metre-scale radius instead of one shared interpenetrating pile.
		var velocity := base_velocity + (
			outward
			* (0.55 + 0.95 * _unit_hash(seed, shard_index * 11 + 7))
			+ Vector3.UP
			* (0.25 + 0.55 * _unit_hash(seed, shard_index * 11 + 8))
			+ Vector3(
				_signed_hash(seed, shard_index * 11 + 9) * 0.42,
				0.0,
				_signed_hash(seed, shard_index * 13 + 5) * 0.42,
			)
		) * random_scale * 10.0
		var spin := Vector3(
			_signed_hash(seed, shard_index * 17 + 1) * 1.2,
			_signed_hash(seed, shard_index * 17 + 2) * 2.0,
			_signed_hash(seed, shard_index * 17 + 3) * 1.2,
		) * TAU
		shard.set_meta("half_thickness", half_thickness)
		shard.set_meta("thin_axis", thin_axis)
		shard.set_meta("is_glass", is_glass)
		shard.set_meta("source_gib_model", source_model)
		shard.set_meta("generated_model_path", model_path)
		shard.set_meta("body_variant", variant_index)
		shard.set_meta("debris_seed", seed)
		shard.set_meta("shard_index", shard_index)
		_motions[shard.get_instance_id()] = {
			"node": shard,
			"velocity": velocity,
			"spin": spin,
			"remaining_ticks": lifetime_ticks,
			"initial_position": shard.global_position,
			"initial_rotation": shard.rotation,
			"grounded": false,
			"bounce_count": 0,
		}
		_shard_serial += 1
		presented_variants.append(variant_index)
	_record({
		"event": "debris_presented",
		"entity_id": int(descriptor.get("entity_id", -1)),
		"gib_model": source_model,
		"variant_manifest": gib_root.path_join("variants.json"),
		"body_variants": presented_variants,
		"seed": seed,
		"shard_count": shard_count,
		"lifetime_ticks": lifetime_ticks,
	})
	return shard_count


func advance_tick() -> void:
	var ids: Array = _motions.keys()
	ids.sort()
	for raw_id in ids:
		var instance_id := int(raw_id)
		var motion: Dictionary = _motions[instance_id]
		var shard: Node3D = motion["node"]
		if not is_instance_valid(shard):
			_motions.erase(instance_id)
			continue
		var velocity: Vector3 = motion["velocity"]
		var spin: Vector3 = motion["spin"]
		if not bool(motion.get("grounded", false)):
			velocity += GRAVITY * TICK_SECONDS
			var half_thickness := maxf(
				0.004,
				float(shard.get_meta("half_thickness", 0.004)),
			)
			var start := shard.global_position
			var proposed := start + velocity * TICK_SECONDS
			var collision := _trace_world(start, proposed, shard)
			var inside_normal: Vector3 = collision.get("normal", Vector3.UP)
			if not collision.is_empty() and inside_normal == Vector3.ZERO:
				# Trace started inside a brush (hit_from_inside): a real shard
				# is never wedged into a surface. Pop it clear in one step and
				# shed the accumulated fall speed, otherwise it creeps upward
				# for many ticks reading as a splinter balanced on end (or a
				# fragment half-embedded in a desk).
				shard.global_position = (
					start + Vector3.UP * maxf(0.02, half_thickness * 2.0)
				)
				if velocity.y < 0.0:
					velocity.y = 0.0
			elif collision.is_empty():
				shard.global_position = proposed
			else:
				var normal: Vector3 = collision.get("normal", Vector3.UP)
				shard.global_position = (
					collision.get("position", proposed)
					+ normal * maxf(COLLISION_EPSILON, half_thickness * 0.5)
				)
				var normal_velocity := normal * velocity.dot(normal)
				var tangent_velocity := velocity - normal_velocity
				velocity = (
					tangent_velocity * SURFACE_FRICTION
					- normal_velocity * BOUNCE_RESTITUTION
				)
				spin *= BOUNCE_SPIN_DAMPING
				motion["bounce_count"] = int(motion.get("bounce_count", 0)) + 1
				if (
					normal.y >= SETTLE_NORMAL_Y
					and (
						velocity.length() <= SETTLE_SPEED
						or int(motion.get("bounce_count", 0))
						>= SETTLE_BOUNCE_LIMIT
					)
				):
					velocity = Vector3.ZERO
					spin = Vector3.ZERO
					motion["grounded"] = true
					_rest_shard_flat(
						shard,
						(collision.get("position", proposed) as Vector3),
						half_thickness,
					)
					# Discrete resting pieces: slide out of any other settled
					# shard's footprint so the pile never freezes as one
					# interpenetrating starburst clump.
					_separate_settled(shard, half_thickness)
					# GoldSrc lights a gib from the surface under its current
					# origin; once the shard comes to rest, re-sample so debris
					# that tumbled from a lit break into a dark corner darkens
					# to match the floor it lies on.
					_relight_shard(shard)
		motion["velocity"] = velocity
		motion["spin"] = spin
		shard.rotation += spin * TICK_SECONDS
		motion["remaining_ticks"] = int(motion["remaining_ticks"]) - 1
		if int(motion["remaining_ticks"]) <= 0:
			_motions.erase(instance_id)
			shard.queue_free()


func advance_ticks(count: int) -> void:
	for _step in range(maxi(0, count)):
		advance_tick()


func active_shard_count() -> int:
	return _motions.size()


func motion_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _motions.keys()
	ids.sort()
	for raw_id in ids:
		var motion: Dictionary = _motions[int(raw_id)]
		var shard: Node3D = motion["node"]
		if not is_instance_valid(shard):
			continue
		result.append({
			"name": shard.name,
			"position": shard.global_position,
			"rotation": shard.rotation,
			"velocity": motion["velocity"],
			"spin": motion["spin"],
			"remaining_ticks": int(motion["remaining_ticks"]),
			"grounded": bool(motion.get("grounded", false)),
			"bounce_count": int(motion.get("bounce_count", 0)),
			"gib_model": str(shard.get_meta("source_gib_model", "")),
			"model_path": str(shard.get_meta("generated_model_path", "")),
			"body_variant": int(shard.get_meta("body_variant", -1)),
			"seed": int(shard.get_meta("debris_seed", 0)),
			"shard_index": int(shard.get_meta("shard_index", -1)),
		})
	return result


## Overrides the shared template materials with per-event duplicates carrying
## the sampled break-site light tint and GoldSrc-crisp nearest-neighbor mip
## filtering, so small authored skins (44x66 wood grain, 64x48 circuit board)
## keep visible texel detail instead of smearing into a flat average color.
## Gib shells are open one-sided strips, so culling is disabled to keep the
## textured face visible from behind; glass shards additionally get the
## TE_BREAKMODEL BREAK_TRANS translucent render mode with a faint glass cast.
func _apply_shard_material(
	mesh: MeshInstance3D,
	light_color: Color,
	is_glass: bool,
	glass_shine := 1.0,
) -> void:
	var tint := light_color
	if is_glass:
		tint = (
			light_color.lerp(Color(1.0, 1.0, 1.0), GLASS_LIGHT_MIX)
			* GLASS_TINT
			* glass_shine
		)
	var tinted := Color(
		tint.r,
		tint.g,
		tint.b,
		GLASS_ALPHA if is_glass else 1.0,
	)
	for material: StandardMaterial3D in mesh.get_meta("group_materials", []):
		_configure_shard_material(material, tinted, is_glass)
	if mesh.mesh == null:
		return
	for surface_index in range(mesh.mesh.get_surface_count()):
		var source := mesh.mesh.surface_get_material(surface_index)
		if not source is StandardMaterial3D:
			continue
		var override := mesh.get_surface_override_material(surface_index)
		var material: StandardMaterial3D = (
			override
			if override is StandardMaterial3D
			else (source as StandardMaterial3D).duplicate()
		)
		_configure_shard_material(material, tinted, is_glass)
		mesh.set_surface_override_material(surface_index, material)


static func _configure_shard_material(
	material: StandardMaterial3D,
	tinted: Color,
	is_glass: bool,
) -> void:
	material.albedo_color = tinted
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Plain nearest sampling: the converted gib skins ship without mipmaps, and
	# any mip/linear averaging bleeds neighbor texels into silhouette edges
	# (the pink fringe on circuit boards). GoldSrc software rendering was
	# point-sampled anyway.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if is_glass:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Both faces of a double-sided glass sheet (plus overlapping shards in
		# a pile) otherwise stack translucent layers into a near-opaque pale
		# wall; writing depth keeps each pixel one authentic
		# kRenderTransTexture blend over the surface behind it.
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		# GoldSrc chrome UVs regenerate per-orientation; world-triplanar
		# sampling of the chome_glass gradient reproduces the per-facet
		# banding, so settled shards at different angles catch different
		# bright/dark streaks instead of one flat average color.
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = GLASS_CHROME_UV_SCALE


## Light for one shard: sampled from the floor directly beneath its own
## position (a wall-mounted panel showers planks onto the floor below, so the
## floor's light level is what GoldSrc would light them with). Falls back to
## the break-site sample when no floor is found under the shard.
func _shard_site_light(position: Vector3, break_light: Color) -> Color:
	var map := _resolve_light_map()
	if map == null:
		return break_light
	var floor_hit := _trace_world(position, position + Vector3.DOWN * 6.0, null)
	if floor_hit.is_empty():
		return break_light
	var sampled := HostageActor.sample_floor_light(
		map,
		(floor_hit.get("position", position) as Vector3) + Vector3.UP * 0.05,
	)
	if _is_missed_light_sample(sampled):
		return break_light
	return Color(
		clampf(sampled.r, LIGHT_FLOOR, 1.0),
		clampf(sampled.g, LIGHT_FLOOR, 1.0),
		clampf(sampled.b, LIGHT_FLOOR, 1.0),
	)


func _relight_shard(shard: Node3D) -> void:
	if shard.get_child_count() == 0:
		return
	var mesh := shard.get_child(0) as MeshInstance3D
	if mesh == null:
		return
	var rest_light := _shard_site_light(
		shard.global_position + Vector3.UP * 0.03,
		MISSED_LIGHT_FALLBACK,
	)
	_apply_shard_material(
		mesh,
		rest_light,
		bool(shard.get_meta("is_glass", false)),
		float(shard.get_meta("glass_shine", 1.0)),
	)


func _break_site_light(origin: Vector3) -> Color:
	var map := _resolve_light_map()
	if map == null:
		return Color(1.0, 1.0, 1.0)
	var sampled := HostageActor.sample_floor_light(map, origin)
	if _is_missed_light_sample(sampled):
		# Wall-mounted breakables (windows, consoles) can sit above the floor
		# grid's vertical window; re-sample from the actual floor under the
		# break before giving up, and never fall back to fullbright debris.
		var floor_hit := _trace_world(
			origin,
			origin + Vector3.DOWN * 6.0,
			null,
		)
		if not floor_hit.is_empty():
			sampled = HostageActor.sample_floor_light(
				map,
				(floor_hit.get("position", origin) as Vector3)
				+ Vector3.UP * 0.05,
			)
		if _is_missed_light_sample(sampled):
			sampled = MISSED_LIGHT_FALLBACK
	# sample_floor_light already applies the GoldSrc studio shade (models are
	# never lit fullbright), so debris shares the exact response of every
	# other studio model standing on the same surface.
	return Color(
		clampf(sampled.r, LIGHT_FLOOR, 1.0),
		clampf(sampled.g, LIGHT_FLOOR, 1.0),
		clampf(sampled.b, LIGHT_FLOOR, 1.0),
	)


static func _is_missed_light_sample(sampled: Color) -> bool:
	return (
		is_equal_approx(sampled.r, 1.0)
		and is_equal_approx(sampled.g, 1.0)
		and is_equal_approx(sampled.b, 1.0)
	)


## Settled GoldSrc gibs come to rest lying on the surface: keep the shard's
## yaw but rotate its thinnest authored axis upright and seat it half a
## thickness above the contact point so nothing stays wedged in the floor.
func _rest_shard_flat(
	shard: Node3D,
	contact: Vector3,
	half_thickness: float,
) -> void:
	var yaw := shard.rotation.y
	match int(shard.get_meta("thin_axis", 1)):
		0:
			shard.rotation = Vector3(0.0, yaw, PI * 0.5)
		2:
			shard.rotation = Vector3(PI * 0.5, yaw, 0.0)
		_:
			shard.rotation = Vector3(0.0, yaw, 0.0)
	shard.global_position = contact + Vector3.UP * half_thickness


## Horizontal footprint of a settled shard: a fraction of its longest scaled
## extent (splinters overlap tips like real debris, but never share a center).
func _rest_footprint_radius(shard: Node3D) -> float:
	var bounds := _template_bounds(
		str(shard.get_meta("generated_model_path", ""))
	)
	var longest := maxf(
		bounds.size.x,
		maxf(bounds.size.y, bounds.size.z),
	) * maxf(shard.scale.x, 0.001)
	return maxf(0.03, longest * REST_SEPARATION_SCALE)


## GoldSrc gibs come to rest as discrete scattered pieces. When a settling
## shard lands inside another settled shard's footprint, slide it outward
## along the floor (stopping short of walls) until the pieces separate, then
## reseat it on the surface beneath its new spot.
func _separate_settled(shard: Node3D, half_thickness: float) -> void:
	var radius := _rest_footprint_radius(shard)
	var moved := false
	for _pass in range(REST_SEPARATION_PASSES):
		var pushed := false
		for motion: Dictionary in _motions.values():
			var other: Node3D = motion["node"]
			if other == shard or not is_instance_valid(other):
				continue
			if not bool(motion.get("grounded", false)):
				continue
			var away := shard.global_position - other.global_position
			away.y = 0.0
			var min_distance := radius + _rest_footprint_radius(other)
			var distance := away.length()
			if distance >= min_distance:
				continue
			if distance < 0.001:
				var yaw := _unit_hash(
					int(shard.get_meta("debris_seed", 0)),
					int(shard.get_meta("shard_index", 0)) * 41 + 7,
				) * TAU
				away = Vector3(cos(yaw), 0.0, sin(yaw))
			var target := (
				shard.global_position
				+ away.normalized() * (min_distance - distance)
			)
			var sweep := _trace_world(
				shard.global_position + Vector3.UP * 0.05,
				target + Vector3.UP * 0.05,
				shard,
			)
			if not sweep.is_empty():
				var normal: Vector3 = sweep.get("normal", Vector3.ZERO)
				if normal == Vector3.ZERO:
					continue
				target = (
					(sweep.get("position", target) as Vector3)
					- Vector3.UP * 0.05
					+ normal * 0.02
				)
			shard.global_position = Vector3(
				target.x,
				shard.global_position.y,
				target.z,
			)
			pushed = true
			moved = true
		if not pushed:
			break
	if not moved:
		return
	var floor_hit := _trace_world(
		shard.global_position + Vector3.UP * 0.1,
		shard.global_position + Vector3.DOWN * 1.5,
		shard,
	)
	if (
		not floor_hit.is_empty()
		and (floor_hit.get("normal", Vector3.ZERO) as Vector3).y
		>= SETTLE_NORMAL_Y
	):
		shard.global_position = (
			(floor_hit.get("position") as Vector3)
			+ Vector3.UP * half_thickness
		)


static func _template_bounds(model_path: String) -> AABB:
	if _bounds_cache.has(model_path):
		return _bounds_cache[model_path]
	var template: Dictionary = _template_cache.get(model_path, {})
	var bounds := AABB()
	if not template.is_empty():
		var positions: PackedFloat32Array = template.positions
		if positions.size() >= 3:
			bounds = AABB(
				Vector3(positions[0], positions[1], positions[2]),
				Vector3.ZERO,
			)
			for index in range(3, positions.size() - 2, 3):
				bounds = bounds.expand(Vector3(
					positions[index],
					positions[index + 1],
					positions[index + 2],
				))
	_bounds_cache[model_path] = bounds
	return bounds


static func _template_half_thickness(model_path: String) -> float:
	var size := _template_bounds(model_path).size
	return maxf(0.004, minf(size.x, minf(size.y, size.z)) * 0.5)


static func _template_thin_axis(model_path: String) -> int:
	var size := _template_bounds(model_path).size
	if size.x <= size.y and size.x <= size.z:
		return 0
	if size.z <= size.x and size.z <= size.y:
		return 2
	return 1


func _resolve_light_map() -> Node3D:
	if _light_map_resolved:
		return _light_map_node
	_light_map_resolved = true
	var ancestor := get_parent()
	while ancestor != null:
		var candidate: Variant = ancestor.get("imported_map")
		if candidate is Node3D and (candidate as Node3D).has_method("model_root"):
			_light_map_node = candidate
			break
		ancestor = ancestor.get_parent()
	return _light_map_node


func _trace_world(
	start: Vector3,
	end: Vector3,
	shard: Node3D,
) -> Dictionary:
	if not is_inside_tree() or start.distance_squared_to(end) <= 0.00000001:
		return {}
	var world := get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		start,
		end,
		COLLISION_MASK,
	)
	query.collide_with_areas = false
	query.hit_from_inside = true
	# Shards are currently visual Node3Ds. Keep this exclusion hook so adding
	# an authored collision proxy later cannot make the shard trace itself.
	if shard is CollisionObject3D:
		query.exclude = [(shard as CollisionObject3D).get_rid()]
	return world.direct_space_state.intersect_ray(query)


func reset() -> void:
	for motion: Dictionary in _motions.values():
		var shard: Node3D = motion["node"]
		if is_instance_valid(shard):
			shard.queue_free()
	_motions.clear()
	presentation_log.clear()
	_shard_serial = 0


func _on_runtime_event(event: Dictionary) -> void:
	if str(event.get("event", "")) == "debris":
		present_debris(event)


func _record(event: Dictionary) -> void:
	presentation_log.append(event)
	presentation_event.emit(event.duplicate(true))


static func _load_template(model_path: String) -> Dictionary:
	if _template_cache.has(model_path):
		return _template_cache[model_path]
	var file := FileAccess.open(model_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or str(parsed.get("format", "")) != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 1
	):
		return {}
	var template := CharacterModel._build_template(model_path, parsed)
	if not template.is_empty():
		_template_cache[model_path] = template
	return template


static func _load_variant_paths(gib_root: String) -> Array:
	if _variant_cache.has(gib_root):
		return _variant_cache[gib_root]
	var manifest_path := gib_root.path_join("variants.json")
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or str(parsed.get("format", "")) != "protocol47-mdl-body-variants"
		or int(parsed.get("version", 0)) != 1
	):
		return []
	var variants: Array = parsed.get("variants", [])
	if not variants.is_empty():
		_variant_cache[gib_root] = variants
	return variants


static func _hash_int(seed: int, salt: int) -> int:
	# splitmix-style avalanche: the old LCG kept strong low-bit correlation
	# between neighboring salts, which made sibling shards spawn with nearly
	# aligned tumble orientations.
	var value := (seed * 1103515245 + salt * 2654435761 + 1013904223) & 0xffffffffffff
	value = (value ^ (value >> 15)) * 2246822519
	value = (value ^ (value >> 13)) * 3266489917
	value = value ^ (value >> 16)
	return value & 0x7fffffff


static func _unit_hash(seed: int, salt: int) -> float:
	var value := _hash_int(seed, salt)
	return float(value % 10000) / 9999.0


static func _signed_hash(seed: int, salt: int) -> float:
	return _unit_hash(seed, salt) * 2.0 - 1.0
