class_name MdlCharacterModel
extends Node3D

const PoseSampler := preload("res://scripts/mdl_pose_sampler.gd")
const RigidSkin := preload("res://scripts/mdl_rigid_skin.gd")

# BSP geometry and converted MDL vertices both use 0.01 Godot units for one
# GoldSrc unit. Keeping this at 1.0 preserves the original player-to-map ratio.
const MODEL_SCALE := 1.0
# The original low-poly player meshes read a little too narrow in a native
# widescreen third-person view, most noticeably in the front-facing pistol
# stance. Add a restrained horizontal-only presentation correction while
# preserving authored height, foot grounding, camera height, and gameplay hulls.
const SILHOUETTE_WIDTH_SCALE := 1.08
const PRESENTATION_SCALE := Vector3(
	MODEL_SCALE * SILHOUETTE_WIDTH_SCALE,
	MODEL_SCALE,
	MODEL_SCALE * SILHOUETTE_WIDTH_SCALE,
)
const AIM_PITCH_SCALE := 3.0
const BLEND_KEY_STEPS := 1024.0
const FRAME_KEY_STEPS := 4096.0
# GoldSrc third-person poses are authored per weapon activity family; the body
# and the bone-merged p_ model must sample the SAME family or the gun detaches
# from the hands. Mirrors attached_weapon_family in the Rust exporter.
const WEAPON_FAMILIES := {
	# The standing ref_aim_ak47/ref_shoot_ak47 tapes appended to the stock 1.6
	# player MDLs pose the torso off the gait facing (their crouch twins are
	# fine); on screen the AK reads as a gun carried across the hips instead of
	# a shouldered rifle. Re-measured after _blend_position started
	# interpolating the STUDIO_XR pitch blends, so it is not a blend-sampling
	# artifact: ref_aim_ak47 frame 0 center blend puts "Bip01 Spine" at yaw -61
	# degrees versus -12 for ref_aim_carbine, and rendering all nine pitch
	# blends shows the same yaw offset at every pitch.
	# CS 1.6's carbine family carries the same two-handed forward aim the game
	# shows for rifles, so the AK samples that family instead. Mirrors
	# attached_weapon_family in crate/src/mdl.rs.
	"ak47": "carbine",
	"aug": "carbine",
	"famas": "carbine",
	"galil": "carbine",
	"m4a1": "carbine",
	"sg552": "carbine",
	"awp": "rifle",
	"g3sg1": "rifle",
	"scout": "rifle",
	"sg550": "rifle",
	"deagle": "onehanded",
	"fiveseven": "onehanded",
	"glock18": "onehanded",
	"p228": "onehanded",
	"usp": "onehanded",
	"elite": "dualpistols",
	"mac10": "mp5",
	"mp5": "mp5",
	"p90": "mp5",
	"tmp": "mp5",
	"ump45": "mp5",
	"m3": "shotgun",
	"xm1014": "shotgun",
	"m249": "m249",
	"flashbang": "grenade",
	"hegrenade": "grenade",
	"smokegrenade": "grenade",
	"c4": "c4",
	"knife": "knife",
}
# GoldSrc modulates the whole player model with the lightmap sample under its
# origin. Approximated here with a sun-occlusion ray against the map colliders:
# the baked lightmap shadows and this ray derive from the same brush geometry
# and sun angles, so the model darkens exactly where the floor shadow lies.
const TINT_REFRESH_INTERVAL := 0.25
const TINT_FLOOR := 0.28
# de_dust2 light_environment: angle 43, pitch -60 (GoldSrc x,y,z), converted to
# Godot (x, z, -y): the direction from a model toward the sun. Only used when
# no baked lightmap is available to sample directly.
const FALLBACK_SUN_DIRECTION := Vector3(-0.36575, 0.86603, 0.34101)
# Floor-luxel probe grid resolution (Godot meters; 32 GoldSrc units).
const LIGHT_PROBE_CELL := 0.32
# Lightmap luxels inside the dust2 sun shadow settle around half brightness
# with a slightly cool cast; sunlit luxels render the model unmodulated.
const SHADOW_TINT := Color(0.50, 0.52, 0.57)
const LIT_TINT := Color(1.0, 1.0, 1.0)
# GoldSrc holds the weapon aim layer (ref_aim_*, approximated by frame 0 of the
# baked ref_shoot_* tape with its 9-way STUDIO_XR pitch blend) over the gait
# sequence whenever a player simply carries the weapon: both hands stay on the
# gun and the barrel tracks aim yaw/pitch. The base idle1/run tapes alone would
# sling the rifle across the chest with the support arm hanging free.
const AIM_LAYER_FOR := {
	"idle": "shoot",
	"run": "shoot",
	"crouchidle": "crouchshoot",
	"crouchrun": "crouchshoot",
}
# GoldSrc drives the legs from gaitsequence while ref_shoot/ref_reload style
# action tapes animate only the upper body (their authored legs are a raised
# reference pose that never renders in-engine). These action states composite
# the current locomotion tape below the belt line, mirroring StudioSetupBones'
# gait split at the pelvis.
const GAIT_COMPOSITE_STATES := ["shoot", "reload", "crouchshoot", "crouchreload"]
# Belt line in reference-pose units above the feet (~34 GoldSrc units).
const LOWER_BODY_SPLIT := 0.34
# CS 1.6 removes the bone-merged p_ model the instant a player dies and the gun
# reappears as a separate ground item; sidearm-less carry items simply vanish.
const UNDROPPABLE_WEAPONS := ["knife", "hegrenade", "flashbang", "smokegrenade", "c4"]
# CS 1.6 tosses the dropped weapon entity with inherited momentum: it arcs from
# the hands, bounces off the floor and only then settles. Closed-form ballistic
# constants (Godot meters, 0.01/GoldSrc unit; sv_gravity 800 → 8.0).
const DROP_GRAVITY := 8.0
const DROP_START := Vector3(0.14, 0.34, 0.16)
const DROP_REST := Vector3(0.10, 0.0, 0.26)
const DROP_LAUNCH_UP := 0.10
const DROP_RESTITUTION := 0.30
const DROP_MIN_BOUNCE := 0.60

static var _template_cache: Dictionary = {}
## Microseconds spent building templates, and how many were built (for ?perf).
static var template_build_usec := 0
static var template_build_count := 0
static var _shadow_light_tree_id := 0
static var _shadow_lights: Dictionary = {}


static func release_cached_resources() -> void:
	# The runtime shares immutable player/weapon meshes across every combatant.
	# Whole-scene teardown (tests and hot reload) owns the matching release.
	_template_cache.clear()
	_chrome_texture_cache.clear()
	_light_probe_grid.clear()
	_light_probe_map_id = 0
	_release_shadow_light_registry()


static func _release_shadow_light_registry() -> void:
	if is_instance_id_valid(_shadow_light_tree_id):
		var tree := instance_from_id(_shadow_light_tree_id) as SceneTree
		tree.node_added.disconnect(_register_shadow_light)
		tree.node_removed.disconnect(_unregister_shadow_light)
	_shadow_light_tree_id = 0
	_shadow_lights.clear()


static func _ensure_shadow_light_registry(tree: SceneTree) -> void:
	if _shadow_light_tree_id == tree.get_instance_id():
		return
	_release_shadow_light_registry()
	_shadow_light_tree_id = tree.get_instance_id()
	# Scan once, then track additions/removals. Never scan the BSP node hierarchy
	# per actor/frame; runtime muzzle lights and staging worlds also live here.
	for light: Node in tree.root.find_children("*", "Light3D", true, false):
		_register_shadow_light(light)
	tree.node_added.connect(_register_shadow_light)
	tree.node_removed.connect(_unregister_shadow_light)


static func _register_shadow_light(node: Node) -> void:
	if node is Light3D:
		_shadow_lights[node.get_instance_id()] = node


static func _unregister_shadow_light(node: Node) -> void:
	_shadow_lights.erase(node.get_instance_id())


var skin_name := ""
var weapon_name := ""
var model_loaded := false
var animation_state := "idle"
var available_animations: Array[String] = []

var body_instance: MeshInstance3D
var weapon_instance: MeshInstance3D
var dropped_weapon_instance: MeshInstance3D
var _body_template: Dictionary = {}
var _weapon_template: Dictionary = {}
var _animation_time := 0.0
var _action_state := ""
var _action_time := 0.0
var _dead := false
var _moving := false
var _crouched := false
var _grounded := true
var _aim_pitch_degrees := 0.0
var _death_ground_offset := NAN
var _drop_elapsed := 0.0
var _body_frame_key := ""
var _weapon_frame_key := ""
var _flash_material: StandardMaterial3D
var _tint_timer := INF
var _tint_refresh_position := Vector3(INF, INF, INF)
var _environment_tint := Color(1.0, 1.0, 1.0)


func _ready() -> void:
	rotation.y = PI * 0.5
	scale = PRESENTATION_SCALE


static func body_asset_path(requested_skin: String, requested_weapon: String) -> String:
	var body_path := "res://generated/players/%s/model.json" % requested_skin
	var family := str(WEAPON_FAMILIES.get(requested_weapon, "rifle"))
	var family_body_path := (
		"res://generated/player_action_families/%s/%s/model.json"
		% [family, requested_skin]
	)
	if FileAccess.file_exists(family_body_path):
		body_path = family_body_path
	return body_path


static func character_assets_prepared(requested_skin: String, requested_weapon: String) -> bool:
	return _template_cache.has(body_asset_path(requested_skin, requested_weapon)) and _template_cache.has(
		"res://generated/player_weapons/%s/model.json" % requested_weapon)


static func prepare_character_assets(requested_skin: String, requested_weapon: String) -> bool:
	# Only immutable source templates; no actor, animated mesh, or actor-owned
	# material is created or changed. load_character consumes these same entries.
	var body := _load_template(body_asset_path(requested_skin, requested_weapon))
	var weapon := _load_template("res://generated/player_weapons/%s/model.json" % requested_weapon)
	return not body.is_empty() and not weapon.is_empty()


func load_character(requested_skin: String, requested_weapon := "ak47") -> bool:
	var body_template := _load_template(body_asset_path(requested_skin, requested_weapon))
	if body_template.is_empty():
		return false
	var weapon_path := "res://generated/player_weapons/%s/model.json" % requested_weapon
	var weapon_template := _load_template(weapon_path)
	# Team/class changes can reload this node in place. Validate first so a
	# failed replacement leaves the usable model intact, then detach old mesh
	# owners immediately: queued deletion alone leaves overlapping renderers
	# until the end of the frame. The immutable source cache remains shared.
	for instance: MeshInstance3D in [body_instance, weapon_instance, dropped_weapon_instance]:
		if is_instance_valid(instance):
			remove_child(instance)
			instance.queue_free()
	body_instance = null
	weapon_instance = null
	dropped_weapon_instance = null
	skin_name = requested_skin
	weapon_name = requested_weapon
	_body_template = body_template
	_weapon_template = weapon_template
	_environment_tint = Color.WHITE
	_tint_timer = INF
	_tint_refresh_position = Vector3.INF
	body_instance = _create_instance("Authentic_%s" % skin_name, _body_template)
	add_child(body_instance)

	if not _weapon_template.is_empty():
		weapon_instance = _create_instance("Attached_%s" % weapon_name, _weapon_template)
		add_child(weapon_instance)

	available_animations.assign(_body_template.animations.keys())
	model_loaded = true
	reset_animation()
	return true


func set_locomotion(moving: bool, crouched := false, grounded := true) -> void:
	_moving = moving
	_crouched = crouched
	_grounded = grounded


func set_aim_pitch(pitch_radians: float) -> void:
	_aim_pitch_degrees = rad_to_deg(pitch_radians)


func play_action(action: String) -> void:
	if _dead:
		return
	var requested := action
	var crouched_action := "crouch%s" % action
	if _crouched and _body_template.animations.has(crouched_action):
		requested = crouched_action
	if not _body_template.animations.has(requested):
		return
	_action_state = requested
	_action_time = 0.0


func play_death() -> void:
	_dead = true
	_action_state = ""
	_animation_time = 0.0
	animation_state = "die"
	_death_ground_offset = NAN
	# Establish the source sequence's first grounded pose immediately. This also
	# freezes the death sequence's initial ground reference before root motion.
	_body_frame_key = _set_frame(
		body_instance,
		_body_template,
		animation_state,
		0.0,
		false,
		"",
	)
	# CS 1.6 detaches the bone-merged p_ model the instant the death sequence
	# starts: corpses are always empty-handed and the gun becomes a ground item.
	if is_instance_valid(weapon_instance):
		weapon_instance.visible = false
	# Gameplay owns the pickup (and clients render its replicated world item).
	# The decorative toss exists only for standalone force_pose captures.
	if is_instance_valid(dropped_weapon_instance):
		dropped_weapon_instance.visible = false
		dropped_weapon_instance.queue_free()
		dropped_weapon_instance = null


func _spawn_dropped_weapon() -> void:
	if (
		_weapon_template.is_empty()
		or UNDROPPABLE_WEAPONS.has(weapon_name)
		or is_instance_valid(dropped_weapon_instance)
	):
		return
	var flattened := _flattened_weapon_positions(_weapon_template)
	if flattened.is_empty():
		return
	dropped_weapon_instance = _create_instance(
		"Dropped_%s" % weapon_name,
		_weapon_template,
	)
	_render_frame(dropped_weapon_instance, _weapon_template, flattened, 0)
	add_child(dropped_weapon_instance)
	_drop_elapsed = 0.0
	_update_dropped_weapon()


func _update_dropped_weapon() -> void:
	## Closed-form dropped-weapon toss: arc from the hands, bounce on the floor
	## plane, settle at the rest spot. Being a pure function of elapsed time it
	## stays deterministic under any delta partitioning (100 Hz game ticks or a
	## capture's single large advance).
	if not is_instance_valid(dropped_weapon_instance):
		return
	# Local space: the model root is already yawed and lifted by the death
	# ground offset, so compensate y to land on the actual floor plane.
	var floor_y := -position.y + 0.004
	var vertical := DROP_START.y - floor_y
	var speed := DROP_LAUNCH_UP
	var elapsed := _drop_elapsed
	var settled := false
	var flight_time := 0.0
	# Walk the bounce segments analytically until the toss clock lands inside
	# one (or the arc has decayed into rest).
	while true:
		var segment := (
			(speed + sqrt(speed * speed + 2.0 * DROP_GRAVITY * vertical))
			/ DROP_GRAVITY
		)
		if elapsed < segment:
			break
		elapsed -= segment
		flight_time += segment
		speed = (speed - DROP_GRAVITY * segment) * -DROP_RESTITUTION
		vertical = 0.0
		if speed < DROP_MIN_BOUNCE:
			settled = true
			break
	var height := floor_y
	if not settled:
		height = (
			floor_y
			+ vertical
			+ speed * elapsed
			- 0.5 * DROP_GRAVITY * elapsed * elapsed
		)
	# Horizontal slide decays toward the rest offset over the toss.
	var slide := clampf(_drop_elapsed / 0.55, 0.0, 1.0)
	slide = 1.0 - (1.0 - slide) * (1.0 - slide)
	dropped_weapon_instance.position = Vector3(
		lerpf(DROP_START.x, DROP_REST.x, slide),
		maxf(height, floor_y),
		lerpf(DROP_START.z, DROP_REST.z, slide),
	)
	dropped_weapon_instance.rotation.y = 0.9
	if settled:
		dropped_weapon_instance.rotation.x = 0.0
	else:
		# One full tumble across the first flight segment reads as inherited
		# momentum and still meets the floor flat at first impact.
		var first_flight := (
			(
				DROP_LAUNCH_UP
				+ sqrt(
					DROP_LAUNCH_UP * DROP_LAUNCH_UP
					+ 2.0 * DROP_GRAVITY * (DROP_START.y - floor_y)
				)
			)
			/ DROP_GRAVITY
		)
		dropped_weapon_instance.rotation.x = (
			TAU * clampf(_drop_elapsed / maxf(first_flight, 0.001), 0.0, 1.0)
		)


static func _flattened_weapon_positions(template: Dictionary) -> PackedFloat32Array:
	## Re-poses the baked in-hands reference vertices as a ground item: longest
	## axis (barrel) horizontal, thinnest axis (receiver side) vertical, lowest
	## point on the floor — the way GoldSrc w_ ground models lie on their side.
	var source: PackedFloat32Array = template.positions
	var vertex_count := source.size() / 3
	if vertex_count < 4:
		return PackedFloat32Array()
	var points: Array[Vector3] = []
	points.resize(vertex_count)
	var centroid := Vector3.ZERO
	for index in range(vertex_count):
		var point := Vector3(
			source[index * 3],
			source[index * 3 + 1],
			source[index * 3 + 2],
		)
		points[index] = point
		centroid += point
	centroid /= float(vertex_count)
	# Longest axis from the farthest vertex pair (subsampled for cost).
	var stride := maxi(1, vertex_count / 160)
	var barrel_axis := Vector3.RIGHT
	var longest := 0.0
	for a in range(0, vertex_count, stride):
		for b in range(a + stride, vertex_count, stride):
			var separation := points[b] - points[a]
			var length := separation.length_squared()
			if length > longest:
				longest = length
				barrel_axis = separation
	if longest <= 0.0:
		return PackedFloat32Array()
	barrel_axis = barrel_axis.normalized()
	# Thinnest in-plane direction perpendicular to the barrel becomes "up".
	var plane_u := barrel_axis.cross(Vector3.UP)
	if plane_u.length_squared() < 0.001:
		plane_u = barrel_axis.cross(Vector3.RIGHT)
	plane_u = plane_u.normalized()
	var plane_v := barrel_axis.cross(plane_u).normalized()
	var up_axis := plane_u
	var thinnest := INF
	for step in range(36):
		var angle := PI * float(step) / 36.0
		var direction := plane_u * cos(angle) + plane_v * sin(angle)
		var low := INF
		var high := -INF
		for index in range(0, vertex_count, stride):
			var extent := (points[index] - centroid).dot(direction)
			low = minf(low, extent)
			high = maxf(high, extent)
		if high - low < thinnest:
			thinnest = high - low
			up_axis = direction
	var side_axis := barrel_axis.cross(up_axis).normalized()
	var flattened := PackedFloat32Array()
	flattened.resize(source.size())
	var minimum_y := INF
	for index in range(vertex_count):
		var local := points[index] - centroid
		var reposed := Vector3(
			local.dot(barrel_axis),
			local.dot(up_axis),
			local.dot(side_axis),
		)
		flattened[index * 3] = reposed.x
		flattened[index * 3 + 1] = reposed.y
		flattened[index * 3 + 2] = reposed.z
		minimum_y = minf(minimum_y, reposed.y)
	for index in range(vertex_count):
		flattened[index * 3 + 1] -= minimum_y
	return flattened


func reset_animation() -> void:
	_dead = false
	_moving = false
	_crouched = false
	_grounded = true
	_aim_pitch_degrees = 0.0
	_action_state = ""
	_animation_time = 0.0
	_action_time = 0.0
	_death_ground_offset = NAN
	_drop_elapsed = 0.0
	animation_state = "idle"
	_body_frame_key = ""
	_weapon_frame_key = ""
	if is_instance_valid(dropped_weapon_instance):
		dropped_weapon_instance.queue_free()
		dropped_weapon_instance = null
	if is_instance_valid(weapon_instance):
		weapon_instance.visible = true
	_body_frame_key = _set_frame(body_instance, _body_template, "idle", 0.0, true, "")
	_weapon_frame_key = _set_frame(
		weapon_instance,
		_weapon_template,
		"idle",
		0.0,
		true,
		"",
	)


func force_pose(state: String, frame_fraction := 0.0, aim_pitch_degrees := 0.0) -> void:
	## Deterministic source-pose hook for regression captures. It deliberately
	## bypasses transition timing while using the exact production sampler.
	if not model_loaded or not _body_template.animations.has(state):
		return
	_aim_pitch_degrees = aim_pitch_degrees
	animation_state = state
	var animation: Dictionary = _body_template.animations[state]
	var frame_index := mini(
		int(floor(clampf(frame_fraction, 0.0, 1.0) * float(animation.frames - 1))),
		int(animation.frames) - 1,
	)
	var pose_time := float(frame_index) / maxf(float(animation.fps), 1.0)
	_body_frame_key = _set_frame(
		body_instance,
		_body_template,
		state,
		pose_time,
		false,
		"",
	)
	if state == "die":
		# Standalone capture preview: there is no Game-owned pickup in this hook.
		if is_instance_valid(weapon_instance):
			weapon_instance.visible = false
		_spawn_dropped_weapon()
		_drop_elapsed = pose_time
		_update_dropped_weapon()
		return
	if is_instance_valid(weapon_instance):
		weapon_instance.visible = true
	if is_instance_valid(dropped_weapon_instance):
		dropped_weapon_instance.queue_free()
		dropped_weapon_instance = null
	_weapon_frame_key = _set_frame(
		weapon_instance,
		_weapon_template,
		state,
		pose_time,
		false,
		"",
	)


func flash_hit(headshot: bool) -> void:
	if not is_instance_valid(body_instance):
		return
	if not is_instance_valid(_flash_material):
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = (
		Color(1.0, 1.0, 1.0, 0.62)
		if headshot
		else Color(1.0, 0.48, 0.30, 0.48)
	)
	body_instance.material_overlay = _flash_material
	get_tree().create_timer(0.07).timeout.connect(func() -> void:
		if is_instance_valid(body_instance):
			body_instance.material_overlay = null
	)


func _process(delta: float) -> void:
	var pose_visible := _pose_may_be_visible()
	advance_animation(delta, pose_visible)
	_tint_timer += delta
	if not pose_visible:
		return
	# Refresh on the coarse clock, and immediately after teleports (round
	# resets, staged captures) so the lightmap modulation never lags a warp.
	if (
		_tint_timer >= TINT_REFRESH_INTERVAL
		or global_position.distance_squared_to(_tint_refresh_position) > 0.09
	):
		_tint_timer = 0.0
		_tint_refresh_position = global_position
		_update_environment_tint()


func _update_environment_tint() -> void:
	## GoldSrc samples the lightmap under the player and modulates the whole
	## model with that color. The primary path samples the map's actual baked
	## floor luxels under the entity (via the exported UV2 lightmap atlas);
	## when no lightmap exists the fallback occludes a ray toward the map's
	## authored sun so shadows still register against the same brush geometry.
	if not model_loaded or not is_inside_tree():
		return
	var tint := LIT_TINT
	if _ensure_light_probe_grid(get_tree().root):
		var sample := _sample_floor_light()
		if sample.a > 0.5:
			tint = sample
	else:
		var world := get_world_3d()
		if world == null:
			return
		var space := world.direct_space_state
		if space == null:
			return
		var origin := global_position + Vector3.UP * 0.52
		var query := PhysicsRayQueryParameters3D.create(
			origin,
			origin + FALLBACK_SUN_DIRECTION * 60.0,
		)
		query.collide_with_areas = false
		var owning_body := _owning_collision_body()
		if owning_body != null:
			query.exclude = [owning_body.get_rid()]
		if not space.intersect_ray(query).is_empty():
			tint = SHADOW_TINT
	tint.r = clampf(tint.r, TINT_FLOOR, 1.0)
	tint.g = clampf(tint.g, TINT_FLOOR, 1.0)
	tint.b = clampf(tint.b, TINT_FLOOR, 1.0)
	tint.a = 1.0
	var lighting_map := instance_from_id(_light_probe_map_id) as BspMap if is_instance_id_valid(_light_probe_map_id) else null
	if lighting_map != null:
		tint = BspMap.lift_shadow_tint(tint, lighting_map.shadow_lift)
	if tint.is_equal_approx(_environment_tint):
		return
	_environment_tint = tint
	for instance in [body_instance, weapon_instance, dropped_weapon_instance]:
		if not is_instance_valid(instance):
			continue
		for material: StandardMaterial3D in instance.get_meta("group_materials", []):
			material.albedo_color = tint


func _owning_collision_body() -> CollisionObject3D:
	var node: Node = get_parent()
	while node != null:
		if node is CollisionObject3D:
			return node
		node = node.get_parent()
	return null


# Shared floor-luxel probe grid: cell (x,z) -> flat [y, r, g, b, ...] entries
# collected once per map from upward-facing lightmapped vertices.
static var _light_probe_grid: Dictionary = {}
static var _light_probe_map_id := 0


static func _ensure_light_probe_grid(tree_root: Node) -> bool:
	var map := _find_bsp_map(tree_root)
	if map == null:
		_light_probe_map_id = 0
		return false
	if map.get_instance_id() == _light_probe_map_id:
		return not _light_probe_grid.is_empty()
	_light_probe_map_id = map.get_instance_id()
	_light_probe_grid = {}
	var atlas: Texture2D = map.get("_lightmap_texture")
	if atlas == null:
		return false
	var image := atlas.get_image()
	if image == null:
		return false
	if image.is_compressed():
		image.decompress()
	_collect_floor_luxels(map, image)
	return not _light_probe_grid.is_empty()


static func _find_bsp_map(node: Node) -> Node3D:
	if node is BspMap:
		return node
	for child in node.get_children():
		var found := _find_bsp_map(child)
		if found != null:
			return found
	return null


static func _collect_floor_luxels(node: Node, image: Image) -> void:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh as ArrayMesh
		if mesh != null:
			var transform: Transform3D = (node as MeshInstance3D).global_transform
			for surface_index in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
				var uv2s: Variant = arrays[Mesh.ARRAY_TEX_UV2]
				if not normals is PackedVector3Array or not uv2s is PackedVector2Array:
					continue
				var surface_normals: PackedVector3Array = normals
				var surface_uv2s: PackedVector2Array = uv2s
				if surface_uv2s.size() != vertices.size():
					continue
				var indices := PackedInt32Array()
				var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
				if raw_indices is PackedInt32Array:
					indices = raw_indices
				else:
					indices.resize(vertices.size())
					for sequential in range(vertices.size()):
						indices[sequential] = sequential
				for triangle in range(0, indices.size() - 2, 3):
					_rasterize_floor_triangle(
						image,
						transform * vertices[indices[triangle]],
						transform * vertices[indices[triangle + 1]],
						transform * vertices[indices[triangle + 2]],
						surface_normals[indices[triangle]],
						surface_uv2s[indices[triangle]],
						surface_uv2s[indices[triangle + 1]],
						surface_uv2s[indices[triangle + 2]],
					)
	for child in node.get_children():
		_collect_floor_luxels(child, image)


static func _rasterize_floor_triangle(
	image: Image,
	point_a: Vector3,
	point_b: Vector3,
	point_c: Vector3,
	normal: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2,
) -> void:
	## Splats one upward-facing lightmapped triangle into the probe grid at
	## cell-center resolution (BSP floor polygons span many cells, so vertex
	## samples alone leave holes).
	if normal.y < 0.6:
		return
	var edge_ab := Vector2(point_b.x - point_a.x, point_b.z - point_a.z)
	var edge_ac := Vector2(point_c.x - point_a.x, point_c.z - point_a.z)
	var denominator := edge_ab.x * edge_ac.y - edge_ab.y * edge_ac.x
	if absf(denominator) < 0.000001:
		return
	var min_cell_x := floori(minf(point_a.x, minf(point_b.x, point_c.x)) / LIGHT_PROBE_CELL)
	var max_cell_x := floori(maxf(point_a.x, maxf(point_b.x, point_c.x)) / LIGHT_PROBE_CELL)
	var min_cell_z := floori(minf(point_a.z, minf(point_b.z, point_c.z)) / LIGHT_PROBE_CELL)
	var max_cell_z := floori(maxf(point_a.z, maxf(point_b.z, point_c.z)) / LIGHT_PROBE_CELL)
	var width := image.get_width()
	var height := image.get_height()
	for cell_x in range(min_cell_x, max_cell_x + 1):
		for cell_z in range(min_cell_z, max_cell_z + 1):
			var probe := Vector2(
				(float(cell_x) + 0.5) * LIGHT_PROBE_CELL - point_a.x,
				(float(cell_z) + 0.5) * LIGHT_PROBE_CELL - point_a.z,
			)
			var weight_b := (probe.x * edge_ac.y - probe.y * edge_ac.x) / denominator
			var weight_c := (edge_ab.x * probe.y - edge_ab.y * probe.x) / denominator
			var weight_a := 1.0 - weight_b - weight_c
			# Slight negative margin keeps coverage along shared cell edges.
			if weight_a < -0.12 or weight_b < -0.12 or weight_c < -0.12:
				continue
			weight_a = clampf(weight_a, 0.0, 1.0)
			weight_b = clampf(weight_b, 0.0, 1.0)
			weight_c = clampf(weight_c, 0.0, 1.0)
			var total := weight_a + weight_b + weight_c
			if total <= 0.0:
				continue
			weight_a /= total
			weight_b /= total
			weight_c /= total
			var floor_y := (
				point_a.y * weight_a + point_b.y * weight_b + point_c.y * weight_c
			)
			var uv := uv_a * weight_a + uv_b * weight_b + uv_c * weight_c
			var luxel := image.get_pixel(
				clampi(int(uv.x * float(width)), 0, width - 1),
				clampi(int(uv.y * float(height)), 0, height - 1),
			)
			var key := Vector2i(cell_x, cell_z)
			var bucket: PackedFloat32Array = _light_probe_grid.get(
				key,
				PackedFloat32Array(),
			)
			bucket.append(floor_y)
			bucket.append(luxel.r)
			bucket.append(luxel.g)
			bucket.append(luxel.b)
			_light_probe_grid[key] = bucket


func _sample_floor_light() -> Color:
	## Nearest baked floor luxel at or below the entity origin — the sample
	## GoldSrc's R_LightPoint would take. Alpha 0 signals "no data here".
	var origin := global_position
	var cell_x := floori(origin.x / LIGHT_PROBE_CELL)
	var cell_z := floori(origin.z / LIGHT_PROBE_CELL)
	var best_y := -INF
	var best := Color(0.0, 0.0, 0.0, 0.0)
	for offset_x in range(-1, 2):
		for offset_z in range(-1, 2):
			var bucket: PackedFloat32Array = _light_probe_grid.get(
				Vector2i(cell_x + offset_x, cell_z + offset_z),
				PackedFloat32Array(),
			)
			for entry in range(0, bucket.size(), 4):
				var floor_y := bucket[entry]
				if floor_y > origin.y + 0.4 or floor_y <= best_y:
					continue
				best_y = floor_y
				best = Color(
					bucket[entry + 1],
					bucket[entry + 2],
					bucket[entry + 3],
					1.0,
				)
	if best.a < 0.5:
		return best
	# Mirror the map shader's lightgamma treatment (pow 0.85 lift, partial
	# desaturation) so the model modulation tracks what the floor shows.
	var lifted := Color(
		pow(best.r, 0.85) * 1.9,
		pow(best.g, 0.85) * 1.9,
		pow(best.b, 0.85) * 1.9,
	)
	var luma := lifted.r * 0.299 + lifted.g * 0.587 + lifted.b * 0.114
	return Color(
		clampf(lerpf(lifted.r, luma, 0.5), 0.0, 1.0),
		clampf(lerpf(lifted.g, luma, 0.5), 0.0, 1.0),
		clampf(lerpf(lifted.b, luma, 0.5), 0.0, 1.0),
		1.0,
	)


func _pose_may_be_visible() -> bool:
	if not is_inside_tree():
		return true
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	# A deliberately conservative two-metre sphere covers the complete stock
	# actor, attached rifle, crouch/death poses, and animation origin correction.
	# Only skip mesh deformation, never the animation/action clock or drop motion.
	var center := global_position + Vector3.UP * 0.4
	var world_scale := global_basis.get_scale().abs()
	var radius := 2.0 * maxf(world_scale.x, maxf(world_scale.y, world_scale.z))
	var frustum := camera.get_frustum()
	if _sphere_intersects_frustum(center, radius, frustum):
		return true
	var caster_layers := 0
	for instance: MeshInstance3D in [body_instance, weapon_instance]:
		if (
			is_instance_valid(instance)
			and instance.is_visible_in_tree()
			and instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		):
			caster_layers |= instance.layers
	if caster_layers == 0:
		return false
	_ensure_shadow_light_registry(get_tree())
	var world := get_world_3d()
	for light: Light3D in _shadow_lights.values():
		if (
			not light.shadow_enabled
			or not light.is_visible_in_tree()
			or light.get_world_3d() != world
		):
			continue
		if (light.shadow_caster_mask & caster_layers) == 0:
			continue
		if light is DirectionalLight3D:
			# A caster outside the camera can project a shadow into it. Clip its
			# swept bounding sphere along the light's -Z ray against all six planes.
			if _shadow_ray_intersects_frustum(
				center, radius, -light.global_basis.z.normalized(), frustum,
			):
				return true
		else:
			# A positional light's entire influence sphere conservatively bounds
			# its receivers (also for spots). No receiver/cone approximation may
			# freeze a visible shadow; false positives only cost mesh updates.
			var light_range := light.get_param(Light3D.PARAM_RANGE)
			if (
				center.distance_to(light.global_position) <= radius + light_range
				and _sphere_intersects_frustum(light.global_position, light_range, frustum)
			):
				return true
	return false


static func _sphere_intersects_frustum(
	center: Vector3, radius: float, frustum: Array[Plane],
) -> bool:
	for plane: Plane in frustum:
		if plane.distance_to(center) > radius:
			return false
	return true


static func _shadow_ray_intersects_frustum(
	center: Vector3, radius: float, direction: Vector3, frustum: Array[Plane],
) -> bool:
	var minimum := 0.0
	var maximum := INF
	for plane: Plane in frustum:
		var remaining := radius - plane.distance_to(center)
		var slope := plane.normal.dot(direction)
		if slope == 0.0:
			if remaining < 0.0:
				return false
		elif slope > 0.0:
			maximum = minf(maximum, remaining / slope)
		else:
			minimum = maxf(minimum, remaining / slope)
		if maximum < minimum:
			return false
	return true


func advance_animation(delta: float, render_pose := true) -> void:
	## Advances the authoritative animation clock. Tests and fixed-tick gameplay
	## can call this directly; rendering always samples the same continuous time.
	if not model_loaded:
		return
	_animation_time += delta
	var loop := true
	var state_time := _animation_time
	if _dead:
		animation_state = "die"
		loop = false
	elif not _action_state.is_empty():
		animation_state = _action_state
		_action_time += delta
		state_time = _action_time
		loop = false
		var action_meta: Dictionary = _body_template.animations.get(_action_state, {})
		var body_duration := (
			float(action_meta.frames) / maxf(1.0, float(action_meta.fps))
			if not action_meta.is_empty()
			else 0.0
		)
		var weapon_action_meta: Dictionary = _weapon_template.animations.get(
			_action_state,
			{},
		)
		var weapon_duration := (
			float(weapon_action_meta.frames)
			/ maxf(1.0, float(weapon_action_meta.fps))
			if not weapon_action_meta.is_empty()
			else 0.0
		)
		# p_c4 carries the authored four/five-second plant activity while the
		# base player model's generic shoot alias is much shorter. The attached
		# weapon animation is not allowed to disappear after the body's first
		# 0.167 s; both samplers remain active for the longest source tape.
		var duration := maxf(body_duration, weapon_duration)
		if _action_time >= duration:
			_action_state = ""
			_action_time = 0.0
	else:
		animation_state = _locomotion_state()
	if render_pose:
		_body_frame_key = _set_frame(
			body_instance, _body_template, animation_state, state_time, loop, _body_frame_key,
		)
	if _dead:
		# The p_ model is detached at the moment of death; the corpse tape only
		# ever drives the body while the dropped gun finishes its toss.
		_drop_elapsed += delta
		_update_dropped_weapon()
		return
	if render_pose:
		_weapon_frame_key = _set_frame(
			weapon_instance, _weapon_template, animation_state, state_time, loop, _weapon_frame_key,
		)


func _set_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	state: String,
	time: float,
	loop: bool,
	previous_key: String,
) -> String:
	if not is_instance_valid(instance) or template.is_empty():
		return ""
	var animations: Dictionary = template.animations
	var animation: Dictionary = animations.get(state, {})
	var resolved_state := state
	if animation.is_empty():
		resolved_state = _locomotion_state()
		animation = animations.get(resolved_state, {})
	if animation.is_empty():
		resolved_state = "idle"
		animation = animations.get(resolved_state, {})
	if animation.is_empty():
		return previous_key
	# Locomotion states composite GoldSrc-style: the aim layer (the ref_shoot
	# tape held at its first frame with the STUDIO_XR pitch blend) drives the
	# torso/arms and the bone-merged p_ weapon while the authored locomotion
	# tape keeps its clock and only survives below the pelvis. The gait tape
	# remains the authoritative frame clock in the cache key.
	var aim_animation: Dictionary = {}
	var aim_state := str(AIM_LAYER_FOR.get(resolved_state, ""))
	if not aim_state.is_empty() and animations.has(aim_state):
		aim_animation = animations[aim_state]
	var frame_count := int(animation.frames)
	if frame_count <= 0:
		return previous_key
	var frame_sample := maxf(0.0, time * float(animation.fps))
	var frame_position := maxi(0, int(floor(frame_sample)))
	var frame_alpha := frame_sample - float(frame_position)
	# Accumulated 100 Hz time can land one float ULP below an exact source-frame
	# boundary. Canonicalize that sample so the key and source indices agree.
	if frame_alpha >= 1.0 - 0.5 / FRAME_KEY_STEPS:
		frame_position += 1
		frame_alpha = 0.0
	elif frame_alpha <= 0.5 / FRAME_KEY_STEPS:
		frame_alpha = 0.0
	var frame_index := 0
	var next_frame_index := 0
	if loop:
		frame_index = frame_position % frame_count
		next_frame_index = (frame_index + 1) % frame_count
	else:
		frame_index = mini(frame_position, frame_count - 1)
		next_frame_index = mini(frame_index + 1, frame_count - 1)
		if frame_index == frame_count - 1:
			frame_alpha = 0.0
	var blend_position := _blend_position(
		aim_animation if not aim_animation.is_empty() else animation
	)
	var blend_low := int(floor(blend_position))
	var blend_high := int(ceil(blend_position))
	var blend_alpha := blend_position - float(blend_low)
	var lower_overlay := {}
	if instance == body_instance:
		if not aim_animation.is_empty() and template.has("lower_mask"):
			# The legs render the locomotion tape sampled above; the aim layer
			# replaces everything above the pelvis.
			lower_overlay = {
				"animation": animation,
				"positions": animation.positions,
				"frame_index": frame_index,
				"next_frame_index": next_frame_index,
				"current_offset": _pose_float_offset(template, animation, frame_index, 0),
				"next_offset": _pose_float_offset(template, animation, next_frame_index, 0),
				"frame_alpha": frame_alpha,
				"mask": template.lower_mask,
				"key": "aim",
			}
		elif aim_animation.is_empty() and GAIT_COMPOSITE_STATES.has(resolved_state):
			lower_overlay = _gait_overlay(
				template,
				_action_gait_state(resolved_state),
				_animation_time,
			)
	var frame_key := "%s:%d:%d:%d:%d:%d:%d:%s" % [
		resolved_state,
		frame_index,
		next_frame_index,
		int(round(frame_alpha * FRAME_KEY_STEPS)),
		blend_low,
		blend_high,
		int(round(blend_alpha * BLEND_KEY_STEPS)),
		"aim" if not aim_animation.is_empty() else str(lower_overlay.get("key", "")),
	]
	if frame_key == previous_key:
		return previous_key
	var base_animation := animation
	var base_frame := frame_index
	var base_next := next_frame_index
	var base_alpha := frame_alpha
	if not aim_animation.is_empty():
		base_animation = aim_animation
		base_frame = 0
		base_next = 0
		base_alpha = 0.0
	_render_interpolated_frame(
		instance,
		template,
		base_animation.positions,
		_pose_float_offset(template, base_animation, base_frame, blend_low),
		_pose_float_offset(template, base_animation, base_frame, blend_high),
		_pose_float_offset(template, base_animation, base_next, blend_low),
		_pose_float_offset(template, base_animation, base_next, blend_high),
		base_alpha,
		blend_alpha,
		lower_overlay,
		_animation_culling_bounds(base_animation, base_frame, base_next, base_alpha,
			blend_low, blend_high, blend_alpha, lower_overlay),
	)
	if instance == body_instance:
		if lower_overlay.is_empty():
			_align_body_feet(
				animation,
				frame_index,
				next_frame_index,
				frame_alpha,
				blend_low,
				blend_high,
				blend_alpha,
			)
		else:
			# The legs on screen come from the gait tape, so the ground contact
			# must be measured on that tape, not the action's authored legs.
			_align_body_feet(
				lower_overlay.animation,
				int(lower_overlay.frame_index),
				int(lower_overlay.next_frame_index),
				float(lower_overlay.frame_alpha),
				0,
				0,
				0.0,
			)
	return frame_key


static func _animation_culling_bounds(animation: Dictionary, frame: int, next_frame: int,
		alpha: float, low: int, high: int, pitch: float, overlay: Dictionary = {}) -> AABB:
	var frames := int(animation.frames)
	var bounds := PoseSampler.interpolated_bounds(animation.pose_bounds,
		low * frames + frame, high * frames + frame,
		low * frames + next_frame, high * frames + next_frame, alpha, pitch)
	if not overlay.is_empty():
		var gait: Dictionary = overlay.animation
		var gait_frame := int(overlay.frame_index)
		var gait_next := int(overlay.next_frame_index)
		bounds = bounds.merge(PoseSampler.interpolated_bounds(gait.pose_bounds,
			gait_frame, gait_frame, gait_next, gait_next, float(overlay.frame_alpha), 0.0))
	return bounds


func _action_gait_state(action_state: String) -> String:
	var crouched := action_state.begins_with("crouch") or _crouched
	return (
		("crouchrun" if _moving else "crouchidle")
		if crouched
		else ("run" if _moving else "idle")
	)


func _gait_overlay(
	template: Dictionary,
	gait_state: String,
	gait_seconds: float,
) -> Dictionary:
	## Samples the requested locomotion tape for the lower body while an
	## upper-body tape (aim layer or action) plays — GoldSrc's gaitsequence
	## split at the pelvis.
	if not template.has("lower_mask"):
		return {}
	var animations: Dictionary = template.animations
	var animation: Dictionary = animations.get(gait_state, animations.get("idle", {}))
	if animation.is_empty():
		return {}
	var frame_count := int(animation.frames)
	if frame_count <= 0:
		return {}
	var frame_sample := maxf(0.0, gait_seconds * float(animation.fps))
	var frame_position := maxi(0, int(floor(frame_sample)))
	var frame_alpha := frame_sample - float(frame_position)
	if frame_alpha >= 1.0 - 0.5 / FRAME_KEY_STEPS:
		frame_position += 1
		frame_alpha = 0.0
	elif frame_alpha <= 0.5 / FRAME_KEY_STEPS:
		frame_alpha = 0.0
	var frame_index := frame_position % frame_count
	var next_frame_index := (frame_index + 1) % frame_count
	return {
		"animation": animation,
		"positions": animation.positions,
		"frame_index": frame_index,
		"next_frame_index": next_frame_index,
		"current_offset": _pose_float_offset(template, animation, frame_index, 0),
		"next_offset": _pose_float_offset(template, animation, next_frame_index, 0),
		"frame_alpha": frame_alpha,
		"mask": template.lower_mask,
		"key": "%s:%d:%d:%d" % [
			gait_state,
			frame_index,
			next_frame_index,
			int(round(frame_alpha * FRAME_KEY_STEPS)),
		],
	}


func _locomotion_state() -> String:
	return (
		"crouchrun"
		if _crouched and _moving
		else "crouchidle"
		if _crouched
		else "run"
		if _moving
		else "idle"
	)


func _blend_position(animation: Dictionary) -> float:
	var blend_count := maxi(1, int(animation.get("blends", 1)))
	if blend_count <= 1 or int(animation.get("blend_type", [0, 0])[0]) != 8:
		return 0.0
	var blend_start := float(animation.get("blend_start", [0.0, 0.0])[0])
	var blend_end := float(animation.get("blend_end", [1.0, 0.0])[0])
	if is_equal_approx(blend_start, blend_end):
		return 0.5 * float(blend_count - 1)
	# GoldSrc StudioPlayerBlend feeds entity pitch * 3 into STUDIO_XR. Godot's
	# positive aim pitch points upward, opposite GoldSrc's positive PITCH.
	var controller := -_aim_pitch_degrees * AIM_PITCH_SCALE
	var normalized := clampf(
		(controller - blend_start) / (blend_end - blend_start),
		0.0,
		1.0,
	)
	return normalized * float(blend_count - 1)


static func _pose_float_offset(
	template: Dictionary,
	animation: Dictionary,
	frame_index: int,
	blend_index: int,
) -> int:
	return (
		(blend_index * int(animation.frames) + frame_index)
		* int(template.vertex_float_count)
	)


func _align_body_feet(
	animation: Dictionary,
	frame_index: int,
	next_frame_index: int,
	frame_alpha: float,
	blend_low: int,
	blend_high: int,
	blend_alpha: float,
) -> void:
	if not _grounded and not _dead:
		return
	var minimum_y := _blended_minimum_y(
		_body_template,
		animation,
		frame_index,
		next_frame_index,
		frame_alpha,
		blend_low,
		blend_high,
		blend_alpha,
	)
	var offset := -minimum_y * MODEL_SCALE
	if _dead:
		if is_nan(_death_ground_offset):
			_death_ground_offset = offset
		position.y = _death_ground_offset
	else:
		position.y = offset


static func _blended_minimum_y(
	template: Dictionary,
	animation: Dictionary,
	frame_index: int,
	next_frame_index: int,
	frame_alpha: float,
	blend_low: int,
	blend_high: int,
	blend_alpha: float,
) -> float:
	var positions: PackedFloat32Array = animation.positions
	var low_offset := _pose_float_offset(template, animation, frame_index, blend_low)
	var next_low_offset := _pose_float_offset(
		template,
		animation,
		next_frame_index,
		blend_low,
	)
	var minimum_y := INF
	# Gait grounding and hostage poses use a single pitch sample. Preserve the
	# exact vertex-wise minimum, but avoid reading/interpolating identical pitch
	# samples. Endpoint minima cannot be interpolated: the lowest vertex may
	# change between frames.
	if blend_alpha == 0.0 or blend_low == blend_high:
		if frame_alpha == 0.0 or low_offset == next_low_offset:
			# An unblended source frame has an exact cached minimum. Interpolated
			# poses still require the vertex-wise scan below: the lowest vertex
			# can change between endpoints, so blending endpoint minima is wrong.
			var pose_index := low_offset / int(template.vertex_float_count)
			var min_cache: Array = animation.get("pose_min_y", [])
			if pose_index < min_cache.size():
				if min_cache[pose_index] == null:
					for vertex_float in range(1, int(template.vertex_float_count), 3):
						minimum_y = minf(minimum_y, positions[low_offset + vertex_float])
					min_cache[pose_index] = minimum_y
				return float(min_cache[pose_index])
			if animation.has("pose_bounds"):
				var source_bounds: AABB = animation.pose_bounds[pose_index]
				return source_bounds.position.y
			for vertex_float in range(1, int(template.vertex_float_count), 3):
				minimum_y = minf(minimum_y, positions[low_offset + vertex_float])
		else:
			for vertex_float in range(1, int(template.vertex_float_count), 3):
				minimum_y = minf(minimum_y, lerpf(positions[low_offset + vertex_float],
					positions[next_low_offset + vertex_float], frame_alpha))
		return minimum_y
	var high_offset := _pose_float_offset(template, animation, frame_index, blend_high)
	var next_high_offset := _pose_float_offset(
		template,
		animation,
		next_frame_index,
		blend_high,
	)
	for vertex_float in range(1, int(template.vertex_float_count), 3):
		var current_y := lerpf(
			positions[low_offset + vertex_float],
			positions[high_offset + vertex_float],
			blend_alpha,
		)
		var next_y := lerpf(
			positions[next_low_offset + vertex_float],
			positions[next_high_offset + vertex_float],
			blend_alpha,
		)
		minimum_y = minf(minimum_y, lerpf(current_y, next_y, frame_alpha))
	return minimum_y


static func _create_instance(instance_name: String, template: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = ArrayMesh.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Every combatant owns its own material copies (textures stay shared) so
	# the GoldSrc-style whole-model light modulate never leaks across players.
	var materials: Array[StandardMaterial3D] = []
	for group: Dictionary in template.groups:
		materials.append((group.material as StandardMaterial3D).duplicate())
	instance.set_meta("group_materials", materials)
	_render_frame(instance, template, template.positions, 0)
	return instance


static func _load_template(path: String) -> Dictionary:
	if _template_cache.has(path):
		return _template_cache[path]
	if not FileAccess.file_exists(path):
		push_warning("Converted character model is unavailable: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or parsed.get("format", "") != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 2
	):
		push_error("Invalid animated character export: %s" % path)
		return {}
	var started := Time.get_ticks_usec()
	var template := _build_template(path, parsed)
	template_build_usec += Time.get_ticks_usec() - started
	template_build_count += 1
	if not template.is_empty():
		_template_cache[path] = template
	return template


static func _build_template(path: String, parsed: Dictionary) -> Dictionary:
	var source_positions: Array = parsed.get("positions", [])
	var source_uvs: Array = parsed.get("uvs", [])
	if source_positions.is_empty() or source_positions.size() % 3 != 0:
		return {}
	var positions := PackedFloat32Array()
	positions.resize(source_positions.size())
	for index in range(source_positions.size()):
		positions[index] = float(source_positions[index])
	var uvs := PackedFloat32Array()
	uvs.resize(source_uvs.size())
	for index in range(source_uvs.size()):
		uvs[index] = float(source_uvs[index])

	var rigid_skin := RigidSkin.load_skin(path, parsed, positions.size() / 3)
	if rigid_skin.has("error"):
		return {}
	var animation_map := {}
	for animation_data in parsed.get("animations", []):
		var animation_file := path.get_base_dir().path_join(str(animation_data.get("file", "")))
		var source := FileAccess.open(animation_file, FileAccess.READ)
		if source == null:
			push_error("Missing character animation: %s" % animation_file)
			return {}
		var animation_bytes := source.get_buffer(source.get_length())
		var frame_count := int(animation_data.get("frames", 0))
		var blend_count := maxi(1, int(animation_data.get("blends", 1)))
		var animation_positions := PackedFloat32Array()
		var pose_bounds: Array[AABB] = []
		if not rigid_skin.is_empty() and bool(rigid_skin.quantized):
			animation_positions = RigidSkin.rebuild_q16(rigid_skin, animation_bytes, frame_count * blend_count, pose_bounds)
		elif not rigid_skin.is_empty():
			animation_positions = RigidSkin.rebuild(rigid_skin, animation_bytes.to_float32_array(),
				frame_count * blend_count, pose_bounds)
		else:
			animation_positions = animation_bytes.to_float32_array()
			pose_bounds = PoseSampler.source_bounds(animation_positions, positions.size() / 3)
		# Rigid poses get bone-box culling bounds, which may exceed the vertices;
		# grounding needs each pose's exact lowest point, computed when first
		# asked for (null until then).
		var pose_min_y: Array = []
		if not rigid_skin.is_empty():
			pose_min_y.resize(pose_bounds.size())
		if animation_positions.size() != frame_count * blend_count * positions.size():
			push_error("Invalid character animation frame data: %s" % animation_file)
			return {}
		animation_map[str(animation_data.get("name", ""))] = {
			"source_label": str(
				animation_data.get("source_label", animation_data.get("name", ""))
			),
			"sequence_index": int(animation_data.get("sequence_index", -1)),
			"fps": float(animation_data.get("fps", 15.0)),
			"frames": frame_count,
			"looping": bool(animation_data.get("looping", false)),
			"blends": blend_count,
			"blend_type": animation_data.get("blend_type", [0, 0]),
			"blend_start": animation_data.get("blend_start", [0.0, 0.0]),
			"blend_end": animation_data.get("blend_end", [1.0, 0.0]),
			"positions": animation_positions,
			"pose_bounds": pose_bounds,
			"pose_min_y": pose_min_y,
		}

	var groups: Array[Dictionary] = []
	for group_data in parsed.get("groups", []):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# GoldSrc renders studio models with backface culling; keeping culling
		# on hides interior vest/strap triangles that otherwise poke through
		# at the neck and shoulders.
		material.cull_mode = BaseMaterial3D.CULL_BACK
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		var texture_name := str(group_data.get("texture", ""))
		if not texture_name.is_empty():
			var texture_path := path.get_base_dir().path_join(texture_name)
			if texture_name.contains("knifeskin"):
				# The p_knife blade is a GoldSrc CHROME env-map (silver); the
				# converted sheet carries the raw teal palette instead. Rebuild
				# it as neutral chrome so the blade reads as polished steel.
				material.albedo_texture = _chrome_texture(texture_path)
			else:
				material.albedo_texture = load(texture_path)
		groups.append({
			"start": int(group_data.get("vert_start", 0)),
			"count": int(group_data.get("vert_count", 0)),
			"material": material,
		})

	# Player exports preserve actual bone ownership, including entire thighs
	# and the pelvis. A height cutoff can split one rigidly bound limb in two.
	# Retain the old fallback for legacy/non-player assets without that metadata.
	var lower_mask := PackedByteArray()
	if parsed.has("lower_body_mask"):
		var source_mask: Array = parsed.lower_body_mask
		if source_mask.size() != positions.size() / 3 or not source_mask.all(func(value: Variant) -> bool: return value == 0 or value == 1):
			push_error("Invalid source lower-body mask: " + path)
			return {}
		lower_mask = PackedByteArray(source_mask)
	else:
		lower_mask.resize(positions.size() / 3)
		var reference_minimum_y := INF
		for index in range(1, positions.size(), 3):
			reference_minimum_y = minf(reference_minimum_y, positions[index])
		for vertex in range(lower_mask.size()):
			lower_mask[vertex] = int(positions[vertex * 3 + 1] < reference_minimum_y + LOWER_BODY_SPLIT)

	return {
		"positions": positions,
		"uvs": uvs,
		"vertex_float_count": positions.size(),
		"groups": groups,
		"animations": animation_map,
		"lower_mask": lower_mask,
	}


static var _chrome_texture_cache: Dictionary = {}


static func _chrome_texture(texture_path: String) -> Texture2D:
	if _chrome_texture_cache.has(texture_path):
		return _chrome_texture_cache[texture_path]
	var source := load(texture_path) as Texture2D
	if source == null:
		return null
	var image := source.get_image()
	if image == null:
		_chrome_texture_cache[texture_path] = source
		return source
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			# Luma with a chrome-style highlight lift and a faint steel-blue
			# cast; dark handle texels stay dark.
			var luma := (
				pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114
			)
			var value := clampf(luma * 1.55 + 0.04, 0.0, 1.0)
			image.set_pixel(
				x,
				y,
				Color(value, value, minf(value * 1.06, 1.0), pixel.a),
			)
	image.generate_mipmaps()
	var chrome := ImageTexture.create_from_image(image)
	_chrome_texture_cache[texture_path] = chrome
	return chrome


static func _render_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	positions: PackedFloat32Array,
	frame_float_offset: int,
) -> void:
	_render_blended_frame(
		instance,
		template,
		positions,
		frame_float_offset,
		frame_float_offset,
		0.0,
	)


static func _render_blended_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	positions: PackedFloat32Array,
	low_float_offset: int,
	high_float_offset: int,
	blend_alpha: float,
) -> void:
	_render_interpolated_frame(
		instance,
		template,
		positions,
		low_float_offset,
		high_float_offset,
		low_float_offset,
		high_float_offset,
		0.0,
		blend_alpha,
	)


static func _render_interpolated_frame(
	instance: MeshInstance3D,
	template: Dictionary,
	positions: PackedFloat32Array,
	current_low_float_offset: int,
	current_high_float_offset: int,
	next_low_float_offset: int,
	next_high_float_offset: int,
	frame_alpha: float,
	blend_alpha: float,
	lower_overlay: Dictionary = {},
	pose_bounds: Variant = null,
) -> void:
	if not is_instance_valid(instance):
		return
	var mesh := instance.mesh as ArrayMesh
	# Keep GPU surfaces/material bindings alive while animating. Only positions
	# change in these baked tapes; recreating every surface forces allocation
	# and driver synchronization for every visible actor on every frame.
	var update_existing: bool = (
		DisplayServer.get_name() != "headless"
		and instance.get_meta("pose_mesh_id", 0) == mesh.get_instance_id()
		and mesh.get_surface_count() == int(instance.get_meta("pose_surface_count", -1))
	)
	if not update_existing:
		mesh.clear_surfaces()
	var bounds := AABB()
	var has_bounds := false
	var surface_index := 0
	var uvs: PackedFloat32Array = template.uvs
	var instance_materials: Array = instance.get_meta("group_materials", [])
	for group_index in range(template.groups.size()):
		var group: Dictionary = template.groups[group_index]
		var start := int(group.start)
		var count := int(group.count)
		if count <= 0:
			continue
		var vertices := PoseSampler.sample(positions, start, count,
			current_low_float_offset, current_high_float_offset,
			next_low_float_offset, next_high_float_offset, frame_alpha, blend_alpha, lower_overlay)
		var texture_uvs := PackedVector2Array()
		if not update_existing:
			texture_uvs.resize(count)
			for local_index in count:
				var vertex_index := start + local_index
				texture_uvs[local_index] = Vector2(uvs[vertex_index * 2], uvs[vertex_index * 2 + 1])
		# Region updates do not recalculate the culling box. Normal animation
		# supplies enclosing source-derived bounds; direct/custom callers retain
		# the exact vertex scan so every pose still has a valid culling box.
		if pose_bounds == null:
			for vertex in vertices:
				if not has_bounds:
					bounds = AABB(vertex, Vector3.ZERO)
					has_bounds = true
				else:
					bounds = bounds.expand(vertex)
		if update_existing:
			mesh.surface_update_vertex_region(surface_index, 0, vertices.to_byte_array())
			surface_index += 1
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE,
		)
		mesh.surface_set_material(
			mesh.get_surface_count() - 1,
			instance_materials[group_index]
			if group_index < instance_materials.size()
			else group.material,
		)
		surface_index += 1
	mesh.custom_aabb = bounds if pose_bounds == null else pose_bounds as AABB
	instance.set_meta("pose_mesh_id", mesh.get_instance_id())
	instance.set_meta("pose_surface_count", surface_index)
