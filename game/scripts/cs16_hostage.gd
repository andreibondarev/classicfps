class_name CS16Hostage
extends CharacterBody3D

signal use_requested(hostage: CS16Hostage, actor: Node)
signal damage_requested(
	hostage: CS16Hostage,
	damage: int,
	hit_group: int,
	weapon_name: String,
	impact_position: Vector3,
	attacker: Node,
)

const HostageModelScript := preload("res://scripts/mdl_hostage_model.gd")
const HostageStateScript := preload("res://scripts/cs16_hostage_state.gd")
const BrushContactsScript := preload("res://scripts/cs16_brush_contacts.gd")
const GOLDSRC_UNIT := 0.01
const HULL_SIZE := Vector3(20.0, 62.0, 20.0) * GOLDSRC_UNIT
const HULL_CENTER := Vector3(0.0, 31.0, 0.0) * GOLDSRC_UNIT
const DROP_TO_FLOOR_HU := 256.0
const FLOOR_EPSILON := 0.001
const SOURCE_TICK_SECONDS := 0.01
const SOURCE_GRAVITY_HU := 800.0
const SOURCE_STEP_HU := 18.0
const SOURCE_JUMP_HU := 270.0
const SOURCE_BLOCKED_JUMP_TICKS := 25
const LIGHT_GRID_CELL := 0.5
const LIGHT_REFRESH_DISTANCE := 0.2

## Per-map floor lightmap grids keyed by BspMap instance id. Each grid buckets
## upward-facing world vertices (with their baked lightmap vertex colors) into
## XZ cells so actors can sample the light under their origin, matching
## GoldSrc's studio-model lighting sample.
static var _light_grids: Dictionary = {}

var hostage_id := ""
var skin_index := 0
var alive := true
var rescued := false
var health := 100
var armor := 0
var following := false
var leader_id := ""
var motion_velocity_hu := Vector3.ZERO
var auto_advance_animation := true
var _blocked_source_ticks := 0
var _brush_contacts := PackedInt32Array()

var hostage_model: MdlHostageModel
var collision_shape: CollisionShape3D

var _light_map_node: Node3D
var _light_map_resolved := false
var _last_light_sample_position := Vector3.INF


func _ready() -> void:
	name = hostage_id if not hostage_id.is_empty() else name
	collision_layer = 16
	collision_mask = 1
	floor_snap_length = SOURCE_STEP_HU * GOLDSRC_UNIT
	floor_max_angle = deg_to_rad(48.0)
	wall_min_slide_angle = 0.0
	add_to_group("source_use_targets")
	_build_collision()
	hostage_model = HostageModelScript.new()
	hostage_model.name = "SourceHostageModel"
	hostage_model.skin_index = skin_index
	hostage_model.idle_phase_unit = _idle_phase_unit()
	add_child(hostage_model)
	_apply_presence()


func _physics_process(_delta: float) -> void:
	if auto_advance_animation and is_instance_valid(hostage_model):
		hostage_model.set_motion_speed_hu(
			motion_velocity_hu.length() if alive and not rescued else 0.0
		)
		hostage_model.advance_tick()
	if global_position.distance_to(_last_light_sample_position) > LIGHT_REFRESH_DISTANCE:
		refresh_model_lighting()


func configure(id: String, requested_skin := 0) -> void:
	hostage_id = id
	skin_index = posmod(requested_skin, 2)
	if is_inside_tree():
		name = hostage_id
		hostage_model.idle_phase_unit = _idle_phase_unit()
		hostage_model.set_skin(skin_index)


func apply_contract_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	hostage_id = str(state.get("id", hostage_id))
	name = hostage_id if not hostage_id.is_empty() else name
	skin_index = posmod(int(state.get("skin", skin_index)), 2)
	alive = bool(state.get("alive", alive))
	health = int(round(float(state.get("health", health))))
	rescued = bool(state.get("rescued", rescued))
	following = bool(state.get("following", following))
	leader_id = str(state.get("leader_id", leader_id))
	var position_hu: Vector3 = state.get(
		"position_hu",
		global_position / GOLDSRC_UNIT,
	)
	var next_position := position_hu * GOLDSRC_UNIT
	if not alive or rescued or not global_position.is_equal_approx(next_position):
		_brush_contacts.clear()
	global_position = next_position
	rotation.y = deg_to_rad(float(state.get("yaw_degrees", rad_to_deg(rotation.y))))
	if is_instance_valid(hostage_model):
		hostage_model.idle_phase_unit = _idle_phase_unit()
		hostage_model.set_skin(skin_index)
	_apply_presence()
	refresh_model_lighting()


func set_motion_velocity_hu(requested_velocity_hu: Vector3) -> void:
	motion_velocity_hu = requested_velocity_hu
	velocity = requested_velocity_hu * GOLDSRC_UNIT


func move_source_tick(requested_velocity_hu: Vector3) -> void:
	_brush_contacts.clear()
	var start_position := global_position
	var was_grounded := is_on_floor()
	motion_velocity_hu = requested_velocity_hu
	velocity.x = requested_velocity_hu.x * GOLDSRC_UNIT
	velocity.z = requested_velocity_hu.z * GOLDSRC_UNIT
	if was_grounded and velocity.y <= 0.0:
		velocity.y = 0.0
	else:
		velocity.y -= (
			SOURCE_GRAVITY_HU
			* GOLDSRC_UNIT
			* SOURCE_TICK_SECONDS
		)
	move_and_slide()
	BrushContactsScript.append_motion_contacts(self, _brush_contacts)
	var horizontal_travel := Vector2(
		global_position.x - start_position.x,
		global_position.z - start_position.z,
	).length()
	if horizontal_travel >= 0.02:
		_blocked_source_ticks = 0
	if (
		was_grounded
		and horizontal_travel < 0.02
		and Vector2(
			requested_velocity_hu.x,
			requested_velocity_hu.z,
		).length_squared() > 0.0001
	):
		# GoldSrc's step-slide retries a blocked horizontal move from a raised
		# origin. This also clears the tiny top bevel at downward ledges instead
		# of treating the edge as a full-height wall.
		var step_up := Vector3.UP * SOURCE_STEP_HU * GOLDSRC_UNIT
		global_position = start_position
		if not test_move(global_transform, step_up):
			global_position += step_up
			velocity = Vector3(
				requested_velocity_hu.x * GOLDSRC_UNIT,
				0.0,
				requested_velocity_hu.z * GOLDSRC_UNIT,
			)
			move_and_slide()
			BrushContactsScript.append_motion_contacts(self, _brush_contacts)
			var stepped_travel := Vector2(
				global_position.x - start_position.x,
				global_position.z - start_position.z,
			).length()
			if stepped_travel < 0.02:
				global_position = start_position
				velocity = Vector3.ZERO
				_blocked_source_ticks += 1
				if _blocked_source_ticks >= SOURCE_BLOCKED_JUMP_TICKS:
					_blocked_source_ticks = 0
					velocity = Vector3(
						requested_velocity_hu.x * GOLDSRC_UNIT,
						SOURCE_JUMP_HU * GOLDSRC_UNIT,
						requested_velocity_hu.z * GOLDSRC_UNIT,
					)
					move_and_slide()
					BrushContactsScript.append_motion_contacts(self, _brush_contacts)
			else:
				_blocked_source_ticks = 0
	if is_on_floor() and velocity.y < 0.0:
		velocity.y = 0.0


func take_brush_contacts() -> PackedInt32Array:
	var contacts := _brush_contacts
	_brush_contacts = PackedInt32Array()
	return contacts


func advance_hostage_tick() -> void:
	if not is_instance_valid(hostage_model):
		return
	hostage_model.set_motion_speed_hu(
		motion_velocity_hu.length() if alive and not rescued else 0.0
	)
	hostage_model.advance_tick()


func acknowledge() -> void:
	if alive and not rescued:
		hostage_model.play_action("acknowledge")


func cower(enabled := true) -> void:
	if alive and not rescued:
		hostage_model.set_cowering(enabled)


func hurt() -> void:
	if alive and not rescued:
		hostage_model.play_action("flinch")


func die() -> void:
	if not alive or rescued:
		return
	alive = false
	following = false
	leader_id = ""
	motion_velocity_hu = Vector3.ZERO
	_blocked_source_ticks = 0
	hostage_model.play_death()
	# GoldSrc corpses settle on the ground plane: the death sequence's final
	# frame is authored flat at the origin, so the actor origin itself must
	# rest on the floor for the corpse to lie on it.
	drop_to_floor()
	_apply_presence()
	refresh_model_lighting()


func mark_rescued() -> void:
	if rescued:
		return
	rescued = true
	following = false
	leader_id = ""
	motion_velocity_hu = Vector3.ZERO
	_blocked_source_ticks = 0
	_apply_presence()


func reset_actor(requested_skin := -1) -> void:
	if requested_skin >= 0:
		skin_index = posmod(requested_skin, 2)
	alive = true
	health = 100
	rescued = false
	following = false
	leader_id = ""
	motion_velocity_hu = Vector3.ZERO
	_blocked_source_ticks = 0
	hostage_model.set_skin(skin_index)
	hostage_model.reset_animation()
	_apply_presence()


func source_use_origin() -> Vector3:
	return global_position + HULL_CENTER


func drop_to_floor(max_drop_hu := DROP_TO_FLOOR_HU) -> bool:
	if not is_inside_tree() or get_world_3d() == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 2.0 * GOLDSRC_UNIT,
		global_position + Vector3.DOWN * maxf(0.0, max_drop_hu) * GOLDSRC_UNIT,
		1,
		[get_rid()],
	)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	global_position.y = float((hit.position as Vector3).y) + FLOOR_EPSILON
	refresh_model_lighting()
	return true


func source_use_usable(actor: Node) -> bool:
	if not alive or rescued or actor == null:
		return false
	var actor_alive := bool(actor.get("alive")) if "alive" in actor else true
	var actor_team := str(actor.get("team")) if "team" in actor else ""
	return (
		actor_alive
		and actor_team in [
			HostageStateScript.TEAM_CT,
			"Counter-Terrorist",
			"counter-terrorist",
		]
	)


func request_source_use(actor: Node) -> bool:
	if not source_use_usable(actor):
		return false
	use_requested.emit(self, actor)
	acknowledge()
	return true


func head_height() -> float:
	return global_position.y + 52.0 * GOLDSRC_UNIT


func receive_bullet_damage(
	damage: int,
	hit_group: int,
	weapon_name: String,
	impact_position: Vector3,
	attacker: Node,
) -> void:
	if not alive or rescued or damage <= 0:
		return
	damage_requested.emit(
		self,
		damage,
		hit_group,
		weapon_name,
		impact_position,
		attacker,
	)


func source_use_capabilities() -> Dictionary:
	return {
		"id": hostage_id,
		"origin": source_use_origin(),
		"radius_hu": HostageStateScript.USE_RADIUS_HU,
		"view_dot": HostageStateScript.USE_VIEW_DOT,
		"usable": alive and not rescued,
	}


## Re-samples the baked lightmap under the actor and tints the studio model,
## mirroring GoldSrc's per-entity light sample. Safe without a map (tests):
## the model simply stays at full brightness.
func refresh_model_lighting() -> void:
	if not is_inside_tree() or not is_instance_valid(hostage_model):
		return
	_last_light_sample_position = global_position
	var map := _resolve_light_map()
	if map == null:
		return
	hostage_model.set_light_color(
		sample_floor_light(map, global_position + HULL_CENTER)
	)


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


## Samples the baked floor lightmap color of a converted BspMap near a world
## position. Shared by every actor that needs GoldSrc studio-model lighting.
static func sample_floor_light(map: Node3D, world_position: Vector3) -> Color:
	var grid: Dictionary = _light_grid_for_map(map)
	if grid.is_empty():
		return Color(1.0, 1.0, 1.0)
	var best_color := Color(1.0, 1.0, 1.0)
	var best_score := INF
	var center_x := int(floor(world_position.x / LIGHT_GRID_CELL))
	var center_z := int(floor(world_position.z / LIGHT_GRID_CELL))
	for offset_x in range(-1, 2):
		for offset_z in range(-1, 2):
			var key := Vector2i(center_x + offset_x, center_z + offset_z)
			if not grid.has(key):
				continue
			for sample: Array in grid[key]:
				var vertex: Vector3 = sample[0]
				var vertical := world_position.y - vertex.y
				# Prefer floor vertices at or below the actor origin; a small
				# tolerance keeps stairs and lips usable.
				if vertical < -0.35 or vertical > 3.0:
					continue
				var score := (
					Vector2(
						vertex.x - world_position.x,
						vertex.z - world_position.z,
					).length_squared()
					+ vertical * vertical * 0.25
				)
				if score < best_score:
					best_score = score
					best_color = sample[1]
	if not is_finite(best_score):
		return Color(1.0, 1.0, 1.0)
	# Match BspMap's lightmap shader response exactly (lightgamma lift, x2
	# overbright, luma desaturation, warm nudge, soft shoulder, 12% ambient
	# floor) and return the factor in gamma space: Godot's own sRGB→linear
	# albedo conversion then reproduces the shader's pow(factor, 2.2), so a
	# model reads within a fraction of a stop of the floor it stands on
	# instead of double-gamma crushing toward black with a chromatic cast.
	return goldsrc_light_factor(best_color)


## GoldSrc studio-model light response for a baked floor vertex color. The
## converter stores vertex colors as min(luxel * 2, 1): undo that overbright
## clamp first, then follow BspMap.LIGHTMAP_SHADER_SOURCE step for step.
static func goldsrc_light_factor(vertex_color: Color) -> Color:
	var luxel := Color(
		clampf(vertex_color.r, 0.0, 1.0) * 0.5,
		clampf(vertex_color.g, 0.0, 1.0) * 0.5,
		clampf(vertex_color.b, 0.0, 1.0) * 0.5,
	)
	var lifted_r := pow(luxel.r, 0.85) * 2.0
	var lifted_g := pow(luxel.g, 0.85) * 2.0
	var lifted_b := pow(luxel.b, 0.85) * 2.0
	var luma := lifted_r * 0.299 + lifted_g * 0.587 + lifted_b * 0.114
	return Color(
		_light_shoulder(lerpf(lifted_r, luma, 0.5) * 1.03),
		_light_shoulder(lerpf(lifted_g, luma, 0.5) * 0.985),
		_light_shoulder(lerpf(lifted_b, luma, 0.5) * 0.965),
	)


## GoldSrc studio models never receive the world's x2 overbright:
## R_StudioLighting is ambient + lambert shadelight, which averages visibly
## below the surrounding lightmapped surfaces. Without this a model reads
## fullbright and appears to float over the floor it stands on.
const STUDIO_SHADE := 0.72


static func _light_shoulder(value: float) -> float:
	# The knee sits at 0.70 with a short 0.14 tail: GoldSrc's studio light caps
	# near 2x overbright, and anything brighter clips the warm face-skin texels
	# to bone-white under ceiling lights. Compressing the top of the response
	# keeps facial detail alive on the brightest floors while leaving everything
	# below the knee untouched.
	var over := maxf(value - 0.70, 0.0)
	var world_factor := minf(value, 0.70) + (1.0 - exp(-over / 0.16)) * 0.14
	return maxf(world_factor * STUDIO_SHADE, 0.12)


static func _light_grid_for_map(map: Node3D) -> Dictionary:
	var key := map.get_instance_id()
	if _light_grids.has(key):
		return _light_grids[key]
	var grid: Dictionary = {}
	var world_root: Node = map.call("model_root", 0)
	if world_root == null:
		world_root = map
	var pending: Array[Node] = [world_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		pending.append_array(node.get_children())
		if not node is MeshInstance3D:
			continue
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		var to_world := (node as MeshInstance3D).global_transform
		for surface_index in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			if colors.is_empty() or normals.size() != vertices.size():
				continue
			var triangle_count := vertices.size() / 3
			for triangle in range(triangle_count):
				var base := triangle * 3
				var normal := (
					normals[base] + normals[base + 1] + normals[base + 2]
				)
				if normal.y < normal.length() * 0.45:
					continue
				_rasterize_light_triangle(
					grid,
					to_world * vertices[base],
					to_world * vertices[base + 1],
					to_world * vertices[base + 2],
					colors[base],
					colors[base + 1],
					colors[base + 2],
				)
	_light_grids[key] = grid
	return grid


## Splats an upward-facing lightmapped triangle into the sampling grid: the
## three corners plus barycentric-interpolated samples at every covered cell
## center, so wide floor brushes are sampleable across their whole interior.
static func _rasterize_light_triangle(
	grid: Dictionary,
	vertex_a: Vector3,
	vertex_b: Vector3,
	vertex_c: Vector3,
	color_a: Color,
	color_b: Color,
	color_c: Color,
) -> void:
	_append_light_sample(grid, vertex_a, color_a)
	_append_light_sample(grid, vertex_b, color_b)
	_append_light_sample(grid, vertex_c, color_c)
	var a := Vector2(vertex_a.x, vertex_a.z)
	var b := Vector2(vertex_b.x, vertex_b.z)
	var c := Vector2(vertex_c.x, vertex_c.z)
	var denominator := (
		(b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	)
	if absf(denominator) < 0.000001:
		return
	var min_x := int(floor(minf(a.x, minf(b.x, c.x)) / LIGHT_GRID_CELL))
	var max_x := int(floor(maxf(a.x, maxf(b.x, c.x)) / LIGHT_GRID_CELL))
	var min_z := int(floor(minf(a.y, minf(b.y, c.y)) / LIGHT_GRID_CELL))
	var max_z := int(floor(maxf(a.y, maxf(b.y, c.y)) / LIGHT_GRID_CELL))
	for cell_x in range(min_x, max_x + 1):
		for cell_z in range(min_z, max_z + 1):
			var point := Vector2(
				(float(cell_x) + 0.5) * LIGHT_GRID_CELL,
				(float(cell_z) + 0.5) * LIGHT_GRID_CELL,
			)
			var weight_a := (
				(b.y - c.y) * (point.x - c.x)
				+ (c.x - b.x) * (point.y - c.y)
			) / denominator
			var weight_b := (
				(c.y - a.y) * (point.x - c.x)
				+ (a.x - c.x) * (point.y - c.y)
			) / denominator
			var weight_c := 1.0 - weight_a - weight_b
			if weight_a < -0.001 or weight_b < -0.001 or weight_c < -0.001:
				continue
			_append_light_sample(
				grid,
				vertex_a * weight_a + vertex_b * weight_b + vertex_c * weight_c,
				color_a * weight_a + color_b * weight_b + color_c * weight_c,
			)


static func _append_light_sample(
	grid: Dictionary,
	world_vertex: Vector3,
	color: Color,
) -> void:
	var cell := Vector2i(
		int(floor(world_vertex.x / LIGHT_GRID_CELL)),
		int(floor(world_vertex.z / LIGHT_GRID_CELL)),
	)
	if not grid.has(cell):
		grid[cell] = []
	(grid[cell] as Array).append([world_vertex, color])


## Stock CS 1.6 renders nothing under a standing model: cl_shadows' sharp
## stencil polygon defaulted off and the modern soft blob gradient instantly
## reads as non-GoldSrc, so hostages cast no shadow of any kind.
func _idle_phase_unit() -> float:
	# GoldSrc starts each hostage's idle sequence at a random frame; derive a
	# stable per-hostage phase from its id so co-located idle hostages never
	# animate in lockstep while rounds stay deterministic.
	return float(posmod(hash(hostage_id), 977)) / 977.0


func _build_collision() -> void:
	collision_shape = CollisionShape3D.new()
	collision_shape.name = "HostageHull20x20x62HU"
	var shape := BoxShape3D.new()
	shape.size = HULL_SIZE
	collision_shape.shape = shape
	collision_shape.position = HULL_CENTER
	add_child(collision_shape)


func _apply_presence() -> void:
	if not is_instance_valid(hostage_model) or not is_instance_valid(collision_shape):
		return
	hostage_model.visible = not rescued
	collision_shape.disabled = not alive or rescued
