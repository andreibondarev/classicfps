class_name MdlViewModel
extends Node3D

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const MAX_VISUAL_FPS := 60.0
# GoldSrc v_ models are authored in view space with the camera at the origin:
# +X runs forward toward the crosshair, +Z is up, and the weapon body sits on
# the authored (left-hand) side. The converter exports x=forward, y=up,
# z=right, so every weapon shares one rigid re-basing into Godot camera space
# (forward -> -Z) with NO positional fudge and NO per-axis stretching.
const CLASSIC_BASE_POSITION := Vector3.ZERO
const GLOCK_BASE_POSITION := Vector3.ZERO
const CLASSIC_MODEL_SCALE := Vector3.ONE
const C4_BASE_POSITION := Vector3.ZERO
const C4_MODEL_SCALE := Vector3.ONE
# Columns: exported forward (+X) -> camera -Z, exported up (+Y) -> +Y,
# exported right (+Z) -> +X. Built from exact integer axes so the node scale
# decomposes to exactly Vector3.ONE.
const VIEW_BASIS := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))
# Most stock CS 1.6 v_ models are authored on the left of the frame and the
# client's default cl_righthand 1 view mirrors them across the view axis
# (which is why receiver text reads backwards in the original game). A few
# models -- the knife -- are authored already right-handed, so mirroring them
# would swap the blade into the wrong hand on the wrong side of the screen.
const UNMIRRORED_WEAPONS := ["knife"]
# GoldSrc R_StudioLighting: one ambient term plus a single soft directional
# lambert shade from above. The direction lives in view space (matching the
# exported vertices) so the weapon top-facing surfaces catch light like the
# original. The falloff is the engine's half-lambert style ramp -- studio
# models never shade below the ambient floor, so adjacent facets stay within a
# gentle contrast band instead of dropping toward black.
const SHADE_LIGHT_DIRECTION := Vector3(0.30, 0.90, 0.28)
const SHADE_AMBIENT := 0.56
const SHADE_LAMBERT := 0.44
# GoldSrc renders the viewmodel with a 90-degree HORIZONTAL fov regardless of
# the world fov. The production camera uses a vertical fov (74 at 4:3 equals
# exactly horizontal 90), so on wide viewports the camera projects with a WIDER
# horizontal fov than the original and the weapon reads undersized and pushed
# away from the crosshair. For a model anchored in camera space, a projection
# at hfov H draws every point at x / (|z| * tan(H/2)): reproducing the original
# 90-degree framing inside a wider camera therefore requires scaling the
# authored camera-space depth by tan(45 deg) / tan(hfov_camera/2) -- a factor
# BELOW 1.0 on wide viewports (0.746 at 16:9), pulling the weapon nearer so it
# regains the classic 4:3 size and its muzzle reaches toward the crosshair. At
# 4:3 the factor is exactly 1.0 (no change).
const GOLDSRC_VIEWMODEL_HFOV := 90.0
# GoldSrc modulates the whole viewmodel with R_LightPoint: the lightmap sample
# on the floor under the player. Probed from the imported BSP vertex light
# colors on a coarse clock, exactly like the third-person player models.
const LIGHT_REFRESH_INTERVAL := 0.25
const LIGHT_PROBE_CELL := 1.5
# GoldSrc clamps viewmodel illumination so the weapon stays readable even in
# pitch-dark spots (ambient floored around 24/255 BEFORE the shade term, and
# the muzzle dlight brightens it further). 0.35 here, multiplied by the 0.54
# baked ambient shade, lands near that floor instead of a black silhouette.
const LIGHT_TINT_FLOOR := 0.35
# GoldSrc uploads studio textures through the texgamma table: a power lift of
# texgamma(2.0) / gamma(2.5) = 0.8 on the stored palette colors. Without it
# the dark stock skins (knifeskin, he_body) read near-black instead of the
# in-game steel and olive tones. The screen gamma ramp is deliberately NOT
# folded in -- it applies to the whole original frame and the imported world
# already renders at its approved brightness.
const TEXTURE_GAMMA := 0.8
# Animated ArrayMeshes are expensive to rebuild on the render thread. A shot
# restarts one of a small set of authored sequences, so retain the finished
# mesh for each sampled source frame and swap the resource on replay. Keeping
# this per viewmodel also keeps its independently tinted material instances.
const MAX_CACHED_FRAME_MESHES := 256
const MAX_PARKED_WEAPONS := 3

# Gamma-lifted albedo textures, shared across weapon loads (keyed by source
# texture path).
static var _gamma_texture_cache: Dictionary = {}
static var _prepared_weapon_assets: Dictionary = {}

var loaded_weapon := ""
var last_load_timings: Dictionary = {}
var model_root: Node3D
# GoldSrc viewmodels carry their full placement in the baked sequence data;
# the camera-relative anchor is the authored view origin itself.
var base_position := CLASSIC_BASE_POSITION

var _template: Dictionary = {}
var _model_instance: MeshInstance3D
var _animation_name := ""
var _animation_time := 0.0
var _animation_loop := true
var _frame_key := ""
var _action_serial := 0
var weapon_silenced := false
var _light_timer := INF
var _light_snap := true
var _light_tint := Color(1.0, 1.0, 1.0)
var _light_map: BspMap
var _light_map_searched := false
var _light_probe_cells: Dictionary = {}
var _light_probes_built := false
var _frame_mesh_cache: Dictionary = {}
var _frame_mesh_cache_order: Array[String] = []
var _current_muzzle_local := Vector3(0.07, -0.04, -0.30)
var _fire_prewarm_queue: Array[Dictionary] = []
var _prewarm_process_counter := 0
var _parked_weapons: Dictionary = {}
var _parked_weapon_order: Array[String] = []


func _ready() -> void:
	position = base_position
	_update_projection_scale()


func _update_projection_scale() -> void:
	## Emulates the GoldSrc 90-degree-horizontal viewmodel projection (see
	## GOLDSRC_VIEWMODEL_HFOV). Depth-only scaling in camera space maps every
	## authored view ray onto the ray the original renderer would have drawn.
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	var view_camera := viewport.get_camera_3d() if viewport != null else null
	if view_camera == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	if viewport_size.y <= 0.0:
		return
	var aspect := viewport_size.x / viewport_size.y
	var half_horizontal := tan(deg_to_rad(view_camera.fov) * 0.5) * aspect
	var depth := tan(deg_to_rad(GOLDSRC_VIEWMODEL_HFOV) * 0.5) / half_horizontal
	scale = Vector3(1.0, 1.0, clampf(depth, 0.55, 1.0))


func muzzle_point_world() -> Vector3:
	## World-space barrel tip of the current viewmodel pose: the vertex of the
	## rendered mesh furthest along the camera forward axis. GoldSrc anchors
	## muzzle-flash sprites to the studio muzzle attachment; the most-forward
	## vertex of a v_ model is that same barrel tip for every stock weapon.
	var local := _muzzle_point_local()
	return global_transform * local


func _muzzle_point_local() -> Vector3:
	return _current_muzzle_local


func _muzzle_point_for_mesh(mesh: ArrayMesh) -> Vector3:
	if mesh == null or mesh.get_surface_count() == 0:
		return Vector3(0.07, -0.04, -0.30)
	var surfaces: Array = []
	for surface_index in mesh.get_surface_count():
		surfaces.append([mesh.surface_get_arrays(surface_index), null])
	return _muzzle_point_for_surfaces(surfaces)


func _muzzle_point_for_surfaces(surfaces: Array) -> Vector3:
	var to_view := model_root.transform * _model_instance.transform
	var best := Vector3(0.07, -0.04, -0.30)
	var best_depth := INF
	for surface: Array in surfaces:
		var arrays: Array = surface[0]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var view_point := to_view * vertex
			if view_point.z < best_depth:
				best_depth = view_point.z
				best = view_point
	return best


func load_weapon(weapon: String) -> bool:
	if loaded_weapon == weapon:
		return true
	last_load_timings = {"weapon": weapon}
	var phase_started := Time.get_ticks_usec()
	var parked: Dictionary = _parked_weapons.get(weapon, {})
	if not parked.is_empty():
		# Take the requested entry before parking the departing weapon so the
		# LRU cannot evict the model about to become active.
		_parked_weapons.erase(weapon)
		_parked_weapon_order.erase(weapon)
		if is_instance_valid(parked.root):
			phase_started = Time.get_ticks_usec()
			_park_active_weapon()
			last_load_timings.park_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0
			phase_started = Time.get_ticks_usec()
			model_root = parked.root
			_model_instance = parked.instance
			_template = parked.template
			_frame_mesh_cache = parked.frames
			_frame_mesh_cache_order = parked.frame_order
			model_root.basis = VIEW_BASIS
			model_root.show()
			last_load_timings.source_ms = 0.0
			last_load_timings.materials_ms = 0.0
			last_load_timings.reused_model = true
			_finish_weapon_load(weapon, phase_started)
			return true
	var path := "res://generated/weapons/%s/model.json" % weapon
	var source_template: Dictionary = CharacterModelScript._load_template(path)
	last_load_timings.source_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0
	if source_template.is_empty():
		push_warning("Converted animated viewmodel is unavailable: %s" % path)
		return false
	phase_started = Time.get_ticks_usec()
	_park_active_weapon()
	last_load_timings.park_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	_template = _first_person_template(source_template, weapon in UNMIRRORED_WEAPONS)
	last_load_timings.materials_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	model_root = Node3D.new()
	model_root.name = "Authentic_%s" % weapon
	# Re-base the exported view-space vertices so the authored forward axis
	# looks down the crosshair. This is a pure rotation; the authored offsets
	# already place the weapon in the lower-right of a fov-90 frame.
	model_root.basis = VIEW_BASIS
	base_position = CLASSIC_BASE_POSITION
	position = base_position
	add_child(model_root)

	_model_instance = CharacterModelScript._create_instance(
		"Animated_%s" % weapon,
		_template,
	)
	_model_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# CS 1.6 weapon models are (mostly) authored left-handed and the client
	# mirrors them into the default right-hand view (cl_righthand 1).
	# Reproduce that exact reflection before the view rotation, except for the
	# few right-hand-authored models. Culling stays disabled, so the reversed
	# winding is harmless.
	if weapon in UNMIRRORED_WEAPONS:
		_model_instance.transform = Transform3D.IDENTITY
	else:
		_model_instance.transform = Transform3D(Basis.FLIP_Z, Vector3.ZERO)
	model_root.add_child(_model_instance)
	# New containers: clearing the old ones would also erase the parked state.
	_frame_mesh_cache = {}
	_frame_mesh_cache_order = []
	last_load_timings.reused_model = false
	_finish_weapon_load(weapon, phase_started)
	return true


func _finish_weapon_load(weapon: String, phase_started: int) -> void:
	base_position = CLASSIC_BASE_POSITION
	position = base_position

	loaded_weapon = weapon
	weapon_silenced = false
	visible = true
	_fire_prewarm_queue = []
	_prewarm_process_counter = 0
	_current_muzzle_local = Vector3(0.07, -0.04, -0.30)
	_update_projection_scale()
	_action_serial = 0
	# New or restored materials must pick up the current player's lighting on
	# the next processed frame, never keep a tint from the previous location.
	_light_timer = INF
	_light_snap = true
	last_load_timings.instance_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	_start_animation(_idle_animation(), true)
	last_load_timings.idle_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0
	phase_started = Time.get_ticks_usec()
	_prewarm_fire_frames()
	last_load_timings.fire_prewarm_ms = float(Time.get_ticks_usec() - phase_started) / 1000.0


func _park_active_weapon() -> void:
	if loaded_weapon.is_empty() or not is_instance_valid(model_root):
		return
	# Only the active instance is animated by this viewmodel. Hidden roots
	# retain their independently tinted materials and bounded frame meshes.
	model_root.hide()
	_parked_weapons[loaded_weapon] = {
		"root": model_root, "instance": _model_instance, "template": _template,
		"frames": _frame_mesh_cache, "frame_order": _frame_mesh_cache_order,
	}
	_parked_weapon_order.append(loaded_weapon)
	while _parked_weapon_order.size() > MAX_PARKED_WEAPONS:
		var oldest: String = _parked_weapon_order.pop_front()
		var entry: Dictionary = _parked_weapons[oldest]
		if is_instance_valid(entry.root):
			entry.root.queue_free()
		_parked_weapons.erase(oldest)


func prepare_weapon_assets(weapons: Array) -> bool:
	# The finite shipped weapon catalog is resident for a match. Reading binary
	# animation tapes and applying texgamma at the moment of a pickup/switch
	# causes a visible hitch even when the weapon's mesh is inexpensive.
	# Prepare one initial animation pose per loading frame, before deployment
	# is allowed. Keep immutable CPU geometry, not another set of animated nodes
	# or tinted materials. Only frame zero of each finite source tape is resident;
	# later frames still use the bounded per-instance cache.
	for weapon_value: Variant in weapons:
		var weapon := str(weapon_value)
		var source_path := "res://generated/weapons/%s/model.json" % weapon
		var attached_path := "res://generated/player_weapons/%s/model.json" % weapon
		if (_prepared_weapon_assets.has(weapon)
			and CharacterModelScript._template_cache.has(source_path)
			and CharacterModelScript._template_cache.has(attached_path)):
			continue
		var source := CharacterModelScript._load_template(source_path)
		var attached := CharacterModelScript._load_template(attached_path)
		if source.is_empty() or attached.is_empty():
			push_error("Cannot prepare required weapon assets: " + weapon)
			return false
		for group: Dictionary in source.groups:
			var material := group.material as StandardMaterial3D
			if material != null:
				_gamma_lifted_texture(material.albedo_texture)
		var initial_frames := {}
		for animation_name: String in source.animations:
			var animation: Dictionary = source.animations[animation_name]
			var surfaces := _source_frame_surfaces(source, animation.positions, 0)
			_shade_surfaces(surfaces, weapon not in UNMIRRORED_WEAPONS)
			initial_frames[animation_name] = {"surfaces": surfaces}
			await get_tree().process_frame
		_prepared_weapon_assets[weapon] = initial_frames
		await get_tree().process_frame
	return true


static func release_cached_resources() -> void:
	_gamma_texture_cache.clear()
	_prepared_weapon_assets.clear()


func _prewarm_fire_frames() -> void:
	## The trigger frame must never pay mesh construction, normal welding, and
	## two ArrayMesh uploads. Frame zero is synchronous here; remaining fire
	## frames are prepared incrementally while the viewmodel is idling (normally
	## during freeze/buy time) so combat never receives one large loading stall.
	var candidates: Array[String] = []
	if loaded_weapon in ["m4a1", "usp"]:
		candidates.assign(["shoot1", "shoot1_unsil"])
	elif loaded_weapon == "knife":
		candidates.assign(["midslash1", "midslash2", "stab", "stab_miss"])
	else:
		candidates.assign(["shoot1", "shoot2", "shoot3", "shoot", "fire"])
	var available: Array[String] = []
	for animation_name: String in candidates:
		if _template.animations.has(animation_name):
			available.append(animation_name)
			_cached_frame(animation_name, 0)
	var largest_frame_count := 0
	for animation_name: String in available:
		largest_frame_count = maxi(
			largest_frame_count,
			int((_template.animations[animation_name] as Dictionary).frames),
		)
	# Round-robin by source-frame index: every firing variant gets its early,
	# frequently reached frames before any long tail is prepared.
	for frame_index in range(1, largest_frame_count):
		for animation_name: String in available:
			var animation: Dictionary = _template.animations[animation_name]
			if frame_index < int(animation.frames):
				_fire_prewarm_queue.append({
					"animation": animation_name,
					"frame": frame_index,
				})


func _prewarm_next_fire_frame() -> void:
	if not _animation_loop or _fire_prewarm_queue.is_empty():
		return
	_prewarm_process_counter += 1
	# One frame every fourth render keeps the preparation slice bounded while
	# still finishing ordinary fire sequences comfortably inside buy time.
	if _prewarm_process_counter % 4 != 0:
		return
	var pending: Dictionary = _fire_prewarm_queue.pop_front()
	_cached_frame(str(pending.animation), int(pending.frame))


func _cached_frame(animation_name: String, frame_index: int) -> Dictionary:
	var key := "%s:%d" % [animation_name, frame_index]
	if _frame_mesh_cache.has(key):
		return _frame_mesh_cache[key]
	var animation: Dictionary = _template.animations.get(animation_name, {})
	if animation.is_empty() or frame_index < 0 or frame_index >= int(animation.frames):
		return {}
	# Build and shade on the CPU before the single upload. Reading surfaces
	# back from a staging GPU mesh forces a driver round trip on cache misses.
	var prepared: Dictionary = {}
	if frame_index == 0:
		var initial_frames: Dictionary = _prepared_weapon_assets.get(loaded_weapon, {})
		prepared = initial_frames.get(animation_name, {})
	var surfaces: Array
	var muzzle_local: Vector3
	var mesh := ArrayMesh.new()
	if prepared.is_empty():
		surfaces = _frame_surfaces(animation.positions, frame_index)
		muzzle_local = _muzzle_point_for_surfaces(surfaces)
		_write_shaded_surfaces(mesh, surfaces)
	else:
		# The prepared arrays contain no material references. Upload with this
		# instance's independently tinted materials, never a cached scene's tint.
		surfaces = prepared.surfaces
		# Muzzle projection depends on the active instance's handedness/FOV,
		# so it cannot be retained in the shared source-geometry cache.
		muzzle_local = _muzzle_point_for_surfaces(surfaces)
		_upload_surfaces(mesh, surfaces, _model_instance.get_meta("group_materials", []))
	var cached := {
		"mesh": mesh,
		"muzzle_local": muzzle_local,
		"prepared_geometry": not prepared.is_empty(),
	}
	_frame_mesh_cache[key] = cached
	_frame_mesh_cache_order.append(key)
	while _frame_mesh_cache_order.size() > MAX_CACHED_FRAME_MESHES:
		var oldest: String = _frame_mesh_cache_order.pop_front()
		_frame_mesh_cache.erase(oldest)
	return cached


func _frame_surfaces(positions: PackedFloat32Array, frame_index: int) -> Array:
	var surfaces := _source_frame_surfaces(_template, positions, frame_index)
	var materials: Array = _model_instance.get_meta("group_materials", [])
	for surface: Array in surfaces:
		var group_index := int(surface[2])
		surface[1] = materials[group_index] if group_index < materials.size() else _template.groups[group_index].material
	return surfaces


static func _source_frame_surfaces(template: Dictionary, positions: PackedFloat32Array, frame_index: int) -> Array:
	var surfaces: Array = []
	var uvs: PackedFloat32Array = template.uvs
	var base := frame_index * int(template.vertex_float_count)
	for group_index in range(template.groups.size()):
		var group: Dictionary = template.groups[group_index]
		var count := int(group.count)
		if count <= 0:
			continue
		var vertices := PackedVector3Array()
		var texture_uvs := PackedVector2Array()
		vertices.resize(count)
		texture_uvs.resize(count)
		for local_index in range(count):
			var vertex_index := int(group.start) + local_index
			var offset := base + vertex_index * 3
			vertices[local_index] = Vector3(positions[offset], positions[offset + 1], positions[offset + 2])
			texture_uvs[local_index] = Vector2(uvs[vertex_index * 2], uvs[vertex_index * 2 + 1])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = texture_uvs
		surfaces.append([arrays, null, group_index])
	return surfaces


func _first_person_template(source_template: Dictionary, unmirrored: bool) -> Dictionary:
	var view_template := source_template.duplicate()
	var view_groups: Array[Dictionary] = []
	for source_group: Dictionary in source_template.groups:
		var group := source_group.duplicate()
		var source := group.material as StandardMaterial3D
		if source == null:
			view_groups.append(group)
			continue
		var material := source.duplicate() as StandardMaterial3D
		# GoldSrc lights the viewmodel with the light sampled at the player
		# origin (R_LightPoint): an ambient term plus one directional lambert.
		# The lambert shade is baked into per-vertex colors each frame and the
		# R_LightPoint color modulates the whole model via albedo_color, so the
		# weapon picks up the warm/cool tone of the lightmap under the player
		# exactly like the original renderer.
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.roughness = 1.0
		material.metallic = 0.0
		material.metallic_specular = 0.0
		material.disable_receive_shadows = true
		# The baked tristrip decode does NOT carry one consistent front-face
		# winding across the stock v_ models (measured: every model mixes both
		# orientations, and v_deagle's visible slide/grip faces are wound
		# opposite to v_ak47's). Any single-sided cull therefore punches holes
		# into some weapons and exposes the interior of the far side -- exactly
		# the "scrambled slide" corruption the Desert Eagle exhibited under
		# CULL_FRONT. Depth testing already resolves self-occlusion correctly,
		# so double-sided rendering is the artifact-free faithful choice.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Viewmodels are composed from several original MDL texture groups.
		# Disabling depth testing makes those independently submitted surfaces
		# paint over one another in material order, visually detaching hands,
		# magazines, and barrels even though the baked vertices are connected.
		# Keep depth testing enabled so the model self-occludes as authored.
		material.no_depth_test = false
		material.render_priority = 10
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.albedo_texture = _gamma_lifted_texture(material.albedo_texture)
		group.material = material
		view_groups.append(group)
	view_template.groups = view_groups
	return view_template


static func _gamma_lifted_texture(source: Texture2D) -> Texture2D:
	## Applies the GoldSrc texgamma/screen-gamma power lift to a studio texture
	## (see TEXTURE_GAMMA). Results are cached per source texture.
	if source == null:
		return null
	var key := source.resource_path
	if key.is_empty():
		key = str(source.get_instance_id())
	if _gamma_texture_cache.has(key):
		return _gamma_texture_cache[key]
	var image := source.get_image()
	if image == null:
		return source
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if image.has_mipmaps():
		# Imported textures can carry a baked mip chain; get_data() would then
		# return the whole chain and the flat RGBA8 rebuild below would fail,
		# silently replacing the skin with an empty (white) texture.
		image.clear_mipmaps()
	var data := image.get_data()
	var lift := PackedByteArray()
	lift.resize(256)
	for level in range(256):
		lift[level] = int(round(255.0 * pow(float(level) / 255.0, TEXTURE_GAMMA)))
	for index in range(0, data.size(), 4):
		data[index] = lift[data[index]]
		data[index + 1] = lift[data[index + 1]]
		data[index + 2] = lift[data[index + 2]]
	var lifted := Image.create_from_data(
		image.get_width(),
		image.get_height(),
		false,
		Image.FORMAT_RGBA8,
		data,
	)
	lifted.generate_mipmaps()
	var texture := ImageTexture.create_from_image(lifted)
	_gamma_texture_cache[key] = texture
	return texture


func _process(delta: float) -> void:
	if _template.is_empty() or not is_instance_valid(_model_instance):
		return
	_light_timer += delta
	if _light_timer >= LIGHT_REFRESH_INTERVAL:
		_light_timer = 0.0
		_update_light_tint()
		_update_projection_scale()
	_prewarm_next_fire_frame()
	var animation: Dictionary = _template.animations.get(_animation_name, {})
	if animation.is_empty():
		return
	_animation_time += delta
	var frame_count := int(animation.frames)
	var fps := maxf(1.0, float(animation.fps))
	var duration := float(frame_count) / fps
	if not _animation_loop and _animation_time >= duration:
		_start_animation(_idle_animation(), true)
		animation = _template.animations.get(_animation_name, {})
		frame_count = int(animation.get("frames", 0))
		fps = maxf(1.0, float(animation.get("fps", 1.0)))
	if frame_count <= 0:
		return

	var sampled_time: float = floor(_animation_time * MAX_VISUAL_FPS) / MAX_VISUAL_FPS
	var frame_position := maxi(0, int(floor(sampled_time * fps)))
	var frame_index := (
		frame_position % frame_count
		if _animation_loop
		else mini(frame_position, frame_count - 1)
	)
	var next_key := "%s:%d" % [_animation_name, frame_index]
	if next_key == _frame_key:
		return
	var cached := _cached_frame(_animation_name, frame_index)
	if cached.is_empty():
		return
	_model_instance.mesh = cached.mesh
	_current_muzzle_local = cached.muzzle_local
	_frame_key = next_key


func _inject_flat_normals(mesh: ArrayMesh) -> void:
	# Compatibility for pose captures that supply an already constructed mesh.
	if mesh == null:
		return
	var surfaces: Array = []
	for surface_index in mesh.get_surface_count():
		surfaces.append([
			mesh.surface_get_arrays(surface_index),
			mesh.surface_get_material(surface_index),
		])
	_write_shaded_surfaces(mesh, surfaces)


func _write_shaded_surfaces(mesh: ArrayMesh, surfaces: Array) -> void:
	if mesh == null:
		return
	_shade_surfaces(surfaces, is_instance_valid(_model_instance) and _model_instance.basis.determinant() < 0.0)
	_upload_surfaces(mesh, surfaces)


static func _upload_surfaces(mesh: ArrayMesh, surfaces: Array, materials: Array = []) -> void:
	mesh.clear_surfaces()
	for surface: Array in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface[0])
		var material: Material = surface[1]
		if not materials.is_empty():
			material = materials[int(surface[2])]
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


static func _shade_surfaces(surfaces: Array, mirrored: bool) -> void:
	# The baked MDL frames carry positions and UVs only. GoldSrc studio
	# lighting is one ambient term plus a single soft lambert shade, so rebuild
	# each surface with per-vertex normals and bake that shade into vertex
	# colors (the R_LightPoint tint then modulates via albedo_color). The baked
	# tristrip winding is NOT globally consistent, so a raw winding normal
	# points inward on many faces; averaging those against their outward
	# neighbours cancels toward zero and produced flat mid-gray patches. A
	# viewmodel is authored around the camera at the origin, so each face
	# normal is re-oriented toward the camera (against its own centroid)
	# before welding -- the orientation the viewer actually shades against.
	var light_direction := SHADE_LIGHT_DIRECTION.normalized()
	if mirrored:
		# Shade is computed in authored model space; mirror the light with the
		# geometry so the on-screen light always falls from the same side.
		light_direction.z = -light_direction.z
	# GoldSrc shades studio models with per-vertex normals; average the face
	# normals across every vertex sharing a position (across all texture
	# groups) so arms and hands shade as rounded surfaces instead of flat
	# facets. Positions are quantized to weld the tristrip seams.
	var smoothed: Dictionary = {}
	var face_normals: Array[PackedVector3Array] = []
	for surface: Array in surfaces:
		var vertices: PackedVector3Array = surface[0][Mesh.ARRAY_VERTEX]
		var per_face := PackedVector3Array()
		per_face.resize(maxi(0, vertices.size() / 3))
		for triangle_start in range(0, vertices.size() - 2, 3):
			var a := vertices[triangle_start]
			var b := vertices[triangle_start + 1]
			var c := vertices[triangle_start + 2]
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 0.000000000001:
				normal = Vector3.BACK
			else:
				normal = normal.normalized()
			# Camera sits at the authored origin: outward (camera-facing) means
			# pointing against the face centroid. Fixes the inconsistent baked
			# winding without trusting it.
			if normal.dot(a + b + c) > 0.0:
				normal = -normal
			per_face[triangle_start / 3] = normal
			for corner in range(3):
				var cell := _weld_key(vertices[triangle_start + corner])
				smoothed[cell] = smoothed.get(cell, Vector3.ZERO) + normal
		face_normals.append(per_face)
	for surface_index in range(surfaces.size()):
		var surface: Array = surfaces[surface_index]
		var arrays: Array = surface[0]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per_face := face_normals[surface_index]
		var normals := PackedVector3Array()
		normals.resize(vertices.size())
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		for vertex_index in range(vertices.size()):
			var normal: Vector3 = smoothed.get(
				_weld_key(vertices[vertex_index]),
				Vector3.ZERO,
			)
			if normal.length_squared() < 0.000001:
				normal = per_face[vertex_index / 3]
			else:
				normal = normal.normalized()
			# Half-lambert style ramp: surfaces facing away from the light stay
			# on a soft gradient toward the ambient floor rather than clipping
			# to it, matching GoldSrc's low-contrast studio shading.
			var shade := (
				SHADE_AMBIENT
				+ SHADE_LAMBERT * (0.5 + 0.5 * normal.dot(light_direction))
			)
			normals[vertex_index] = normal
			colors[vertex_index] = Color(shade, shade, shade, 1.0)
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors


static func _weld_key(position: Vector3) -> Vector3i:
	return Vector3i(
		int(round(position.x * 2048.0)),
		int(round(position.y * 2048.0)),
		int(round(position.z * 2048.0)),
	)


func _update_light_tint() -> void:
	## GoldSrc R_LightPoint: the viewmodel is modulated with the lightmap
	## sample on the floor under the player. Probe the imported BSP baked
	## vertex light colors below the camera; fall back to the scene ambient
	## when no map is loaded (capture stages, menus).
	if not is_inside_tree():
		return
	var target := Color(1.0, 1.0, 1.0)
	var probed := _probe_map_light()
	if probed.a > 0.0:
		target = Color(probed.r, probed.g, probed.b, 1.0)
	else:
		var world := get_world_3d()
		var environment := world.environment if world != null else null
		if (
			environment != null
			and environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR
		):
			target = environment.ambient_light_color * environment.ambient_light_energy
	target.r = clampf(target.r, LIGHT_TINT_FLOOR, 1.0)
	target.g = clampf(target.g, LIGHT_TINT_FLOOR, 1.0)
	target.b = clampf(target.b, LIGHT_TINT_FLOOR, 1.0)
	target.a = 1.0
	if is_instance_valid(_light_map) and _light_map is BspMap:
		target = BspMap.lift_shadow_tint(target, _light_map.shadow_lift)
	# Smooth like the engine's light interpolation so walking between rooms
	# never pops the weapon brightness.
	_light_tint = target if _light_snap else _light_tint.lerp(target, 0.45)
	_light_snap = false
	if not is_instance_valid(_model_instance):
		return
	for material: StandardMaterial3D in _model_instance.get_meta("group_materials", []):
		material.albedo_color = _light_tint


func _probe_map_light() -> Color:
	## Returns alpha 0 when no probe is available.
	if not _light_map_searched:
		_light_map_searched = true
		_light_map = _find_bsp_map(get_tree().root, 0)
	if not is_instance_valid(_light_map):
		return Color(0, 0, 0, 0)
	if not _light_probes_built:
		_light_probes_built = true
		_build_light_probes()
	if _light_probe_cells.is_empty():
		return Color(0, 0, 0, 0)
	var eye := global_position
	var cell := Vector2i(
		int(floor(eye.x / LIGHT_PROBE_CELL)),
		int(floor(eye.z / LIGHT_PROBE_CELL)),
	)
	# Inverse-distance blend of the nearby floor luxels: a single nearest
	# sample flickers between lit and shadowed texels while walking, and any
	# stray unlit vertex would hard-pop the whole weapon.
	var accumulated := Vector3.ZERO
	var total_weight := 0.0
	for offset_x in range(-1, 2):
		for offset_z in range(-1, 2):
			var samples: PackedFloat32Array = _light_probe_cells.get(
				Vector2i(cell.x + offset_x, cell.y + offset_z),
				PackedFloat32Array(),
			)
			for sample_start in range(0, samples.size(), 6):
				var drop := eye.y - samples[sample_start + 1]
				if drop < -0.25 or drop > 3.2:
					continue
				var dx := samples[sample_start] - eye.x
				var dz := samples[sample_start + 2] - eye.z
				var score := dx * dx + dz * dz + 0.08 * drop * drop
				var weight := 1.0 / (score + 0.04)
				accumulated += weight * Vector3(
					samples[sample_start + 3],
					samples[sample_start + 4],
					samples[sample_start + 5],
				)
				total_weight += weight
	if total_weight <= 0.0:
		return Color(0, 0, 0, 0)
	accumulated /= total_weight
	var best_color := Color(accumulated.x, accumulated.y, accumulated.z, 1.0)
	# Match the world shader's 2x overbright, preserving hue when a channel
	# saturates (Godot converts albedo_color sRGB->linear, mirroring the
	# shader's pow(light, 2.2)).
	var boosted := Vector3(
		minf(best_color.r * 2.0, 1.5),
		minf(best_color.g * 2.0, 1.5),
		minf(best_color.b * 2.0, 1.5),
	)
	var peak := maxf(boosted.x, maxf(boosted.y, boosted.z))
	if peak > 1.0:
		boosted /= peak
	# GoldSrc pushes R_LightPoint through the lightgamma table, which lifts and
	# compresses the channels slightly toward each other. Keep the pull toward
	# neutral small: on dust2 the lightmap under the player is warm orange and
	# the whole weapon must visibly pick up that warm gold cast (a stronger
	# lerp rendered the gun neutral white against the warm scene).
	var luminance := boosted.dot(Vector3(0.299, 0.587, 0.114))
	boosted = boosted.lerp(Vector3(luminance, luminance, luminance), 0.30)
	return Color(boosted.x, boosted.y, boosted.z, 1.0)


func _build_light_probes() -> void:
	## One-time flat spatial hash of upward-facing world vertices carrying the
	## baked lightmap colors: [x, y, z, r, g, b] per probe.
	var world_root := _light_map.runtime_root_for_model(0)
	if world_root == null:
		return
	for child in world_root.get_children():
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or not (mesh_instance.mesh is ArrayMesh):
			continue
		var mesh := mesh_instance.mesh as ArrayMesh
		var to_world := mesh_instance.global_transform
		for surface_index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors.is_empty() or normals.size() != vertices.size():
				continue
			for vertex_index in range(0, vertices.size(), 3):
				if normals[vertex_index].y < 0.65:
					continue
				var world_point := to_world * vertices[vertex_index]
				var color := colors[vertex_index]
				# Exactly-white vertices belong to non-lightmapped surfaces
				# (entity brushes, special textures); GoldSrc R_LightPoint only
				# reads lightmapped world faces, and a full-bright probe would
				# wash out the weapon in shadowed areas.
				if color.r + color.g + color.b >= 2.97:
					continue
				var cell := Vector2i(
					int(floor(world_point.x / LIGHT_PROBE_CELL)),
					int(floor(world_point.z / LIGHT_PROBE_CELL)),
				)
				if not _light_probe_cells.has(cell):
					_light_probe_cells[cell] = PackedFloat32Array()
				var samples: PackedFloat32Array = _light_probe_cells[cell]
				samples.append(world_point.x)
				samples.append(world_point.y)
				samples.append(world_point.z)
				samples.append(color.r)
				samples.append(color.g)
				samples.append(color.b)
				_light_probe_cells[cell] = samples


static func _find_bsp_map(node: Node, depth: int) -> BspMap:
	if node is BspMap:
		return node
	if depth >= 3:
		return null
	for child in node.get_children():
		var found := _find_bsp_map(child, depth + 1)
		if found != null:
			return found
	return null


func play_action(kind: String) -> void:
	if _template.is_empty():
		return
	var animation := _action_animation(kind)
	if animation.is_empty():
		_play_fallback_action(kind)
		return
	_start_animation(animation, false)


func _play_fallback_action(kind: String) -> void:
	var tween := create_tween()
	match kind:
		"fire":
			tween.tween_property(self, "position:z", base_position.z + 0.075, 0.035)
			tween.tween_property(self, "position:z", base_position.z, 0.075)
		"reload":
			tween.tween_property(self, "rotation:z", deg_to_rad(24.0), 0.25)
			tween.tween_property(self, "rotation:z", 0.0, 0.42).set_delay(1.15)
		"switch":
			position.y = base_position.y - 0.14
			tween.tween_property(self, "position:y", base_position.y, 0.22)
		"knife":
			tween.tween_property(self, "rotation:y", deg_to_rad(-32.0), 0.07)
			tween.tween_property(self, "rotation:y", 0.0, 0.15)
		"pullpin":
			tween.tween_property(self, "rotation:x", deg_to_rad(9.0), 0.14)
			tween.tween_property(self, "rotation:z", deg_to_rad(-7.0), 0.10)
		"throw":
			tween.tween_property(self, "rotation:x", deg_to_rad(-35.0), 0.12)
			tween.parallel().tween_property(self, "rotation:z", 0.0, 0.12)
			tween.tween_property(self, "rotation:x", 0.0, 0.2)


func _start_animation(animation: String, loop: bool) -> void:
	if animation.is_empty() or not _template.animations.has(animation):
		return
	_animation_name = animation
	_animation_time = 0.0
	_animation_loop = loop
	_frame_key = ""


func set_silenced(enabled: bool) -> void:
	if weapon_silenced == enabled:
		return
	weapon_silenced = enabled
	if _animation_loop:
		_start_animation(_idle_animation(), true)


func _idle_animation() -> String:
	if loaded_weapon in ["m4a1", "usp"] and not weapon_silenced and _template.animations.has("idle_unsil"):
		return "idle_unsil"
	for candidate in ["idle", "idle1", "idle2", "idle3"]:
		if _template.animations.has(candidate):
			return candidate
	var names: Array = _template.animations.keys()
	return str(names[0]) if not names.is_empty() else ""


func _action_animation(kind: String) -> String:
	if loaded_weapon in ["m4a1", "usp"] and kind in ["fire", "reload", "switch"]:
		var sequence := {"fire": "shoot1", "reload": "reload", "switch": "draw"}[kind] as String
		return sequence if weapon_silenced else sequence + "_unsil"
	var candidates: Array[String] = []
	match kind:
		"fire":
			candidates.assign(["shoot1", "shoot2", "shoot3", "shoot", "fire"])
			var available_fire: Array[String] = []
			for candidate: String in candidates:
				if _template.animations.has(candidate):
					available_fire.append(candidate)
			if not available_fire.is_empty():
				var selected := available_fire[_action_serial % available_fire.size()]
				_action_serial += 1
				return selected
		"reload":
			candidates.assign(["reload", "reload1", "start_reload", "insert"])
		"switch":
			candidates.assign(["draw", "deploy", "up"])
		"knife":
			candidates.assign(["midslash1" if _action_serial % 2 == 0 else "midslash2"])
			_action_serial += 1
		"throw":
			candidates.assign(["throw", "throw1", "release"])
		_:
			candidates.assign([kind])
	for candidate: String in candidates:
		if _template.animations.has(candidate):
			return candidate
	# Sequence naming differs between a few stock weapons. A prefix fallback
	# preserves original MDL content without hardcoding model-specific indices.
	for animation_variant: Variant in _template.animations.keys():
		var animation := str(animation_variant)
		for candidate: String in candidates:
			if animation.begins_with(candidate):
				return animation
	return ""


func set_bob(offset_y: float, sway_x: float) -> void:
	position.y = base_position.y + offset_y
	position.x = base_position.x + sway_x
