class_name BspMap
extends Node3D

const SPAWN_FLOOR_EPSILON := 0.001
const DUST2_SHADOW_LIFT := 0.14

## Legacy-style surface shader: WAD texture (trilinear mipmaps, like
## gl_texturemode GL_LINEAR_MIPMAP_LINEAR) multiplied by the per-face lightmap
## atlas sampled via UV2. The raw dust2 luxels carry the map's yellow-green
## `_light 255 255 128` sun verbatim; GoldSrc never shows that raw product —
## its lightgamma/gamma table (texgamma 2.0, lightgamma 2.5, gamma 2.5) lifts
## shadows and compresses channel ratios before GL_MODULATE, which is why real
## 1.6 walls read desaturated warm tan, mid-door interiors stay readable, and
## full sun never flattens to clipped yellow. We reproduce that response:
## gamma-lift the luxel, desaturate its tint, roll the x2 overbright into a
## soft shoulder instead of a hard per-channel clip (preserves brick detail in
## sun), and keep GoldSrc's ambient floor so shade never crushes to black.
## Evaluate the authored response in the same encoded space on every backend.
## Only the final product is converted for a linear-output renderer. This
## preserves Compatibility's material response; the response itself still
## needs comparison with original-engine reference captures.
const LIGHTMAP_SHADER_FRAGMENT := """
// Deliberately raw data sampling: this legacy response and its filtering are
// defined on encoded WAD texels, not automatically decoded sRGB texels.
uniform sampler2D albedo_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : filter_linear, repeat_disable;
uniform float shadow_lift = 0.0;

vec3 bsp_output_color(vec3 encoded) {
	if (OUTPUT_IS_SRGB) {
		return encoded;
	}
	return mix(pow((encoded + vec3(0.055)) / 1.055, vec3(2.4)),
		encoded / 12.92, lessThanEqual(encoded, vec3(0.04045)));
}

// GoldSrc uploads WAD textures through its texgamma 2.0 / gamma 2.5 ramp:
// on screen every texel is lifted by ~pow 0.85, which flattens the speckly
// high-contrast stone into the smoother, evenly toned plaster real 1.6 shows.
vec3 goldsrc_texture_wash(vec3 albedo) {
	// 0.90 keeps the texgamma lift but preserves more micro-contrast; the
	// 0.85 wash read as blur on large magnified wall surfaces.
	return pow(albedo, vec3(0.90));
}

vec3 goldsrc_light(vec2 uv2) {
	// Sharpened bilinear at authentic 16-unit luxel density: re-center the
	// fractional blend on a sub-luxel window so shadow boundaries keep
	// GoldSrc's GL_LINEAR softness but still read as defined, slightly blocky
	// luxel edges instead of a magnified airbrush gradient.
	vec2 lm_size = vec2(textureSize(lightmap_tex, 0));
	vec2 texel = uv2 * lm_size - 0.5;
	vec2 blend = clamp((fract(texel) - 0.5) / 0.58 + 0.5, 0.0, 1.0);
	vec3 luxel = texture(
		lightmap_tex,
		(floor(texel) + 0.5 + blend) / lm_size
	).rgb;
	// GoldSrc lightgamma lift on gamma-space luxels. Keep the exponent near 1
	// and the overbright multiplier moderate: pushing every mid luxel into the
	// shoulder is what flattened sun-facing and shaded walls to one brightness.
	vec3 light_factor = pow(luxel, vec3(0.92)) * 1.72;
	// The engine gamma table compresses channel ratios: dust2's 255/255/128
	// sun displays as desaturated sand-tan, not gold-green. Pull the tint
	// toward its luma and nudge warm (R over G) to match the des palette.
	float luma = dot(light_factor, vec3(0.299, 0.587, 0.114));
	light_factor = mix(light_factor, vec3(luma), 0.42);
	light_factor *= vec3(1.03, 0.985, 0.965);
	// Soft shoulder above 0.82 with a ~0.95 ceiling: GoldSrc's overbright
	// keeps full-sun dust walls cream-tan — sunlit texel detail must never
	// wash to white, so the multiplier tops out below 1. Only genuinely
	// sun-struck luxels reach the shoulder; radiosity mid-tones stay below it
	// so opposing lane walls keep their sun/shade differentiation.
	vec3 over = max(light_factor - vec3(0.82), vec3(0.0));
	light_factor = min(light_factor, vec3(0.82))
		+ (vec3(1.0) - exp(-over / 0.15)) * 0.13;
	// GoldSrc ambient floor: dust2's interiors carry baked texlights, and the
	// engine gamma ramp keeps every shadow readable — the darkest luxels show
	// as warm dim brown (~RGB 90,70,50 on screen), never a black void. Lift
	// only the dark end so lit areas and shadow gradients are untouched.
	light_factor += vec3(0.30, 0.24, 0.175) * exp(-light_factor / vec3(0.16));
	// Dust2 readability adjustment, not an engine-parity claim. Preserve the
	// baked gradients and leave bright surfaces/texlights completely unchanged.
	float shadow_weight = 1.0 - smoothstep(0.18, 0.65,
		dot(light_factor, vec3(0.299, 0.587, 0.114)));
	light_factor += vec3(shadow_lift * shadow_weight);
	return pow(light_factor, vec3(2.2));
}
"""

const LIGHTMAP_SHADER_SOURCE := (
	"""
shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled;
"""
	+ LIGHTMAP_SHADER_FRAGMENT
	+ """
void fragment() {
	vec4 albedo = texture(albedo_tex, UV);
	ALBEDO = bsp_output_color(goldsrc_texture_wash(albedo.rgb) * goldsrc_light(UV2));
}
"""
)

## Masked ('{') world faces: GoldSrc alpha-tests these at texture resolution.
## Straight discard at the mip-selected alpha produces melted pixel stairs at
## range; sharpening the mask against its screen-space footprint keeps the
## silhouette at the crisp polygon-like edge veterans expect, and alpha
## scissor keeps the face in the opaque depth-writing pass.
const LIGHTMAP_CUTOUT_SHADER_SOURCE := (
	"""
shader_type spatial;
render_mode unshaded, cull_disabled, specular_disabled, depth_prepass_alpha;
"""
	+ LIGHTMAP_SHADER_FRAGMENT
	+ """
void fragment() {
	vec4 albedo = texture(albedo_tex, UV);
	float mask = albedo.a;
	// Re-center the mip-blurred mask on its 0.5 isoline over one pixel of
	// screen-space footprint: an antialiased, stair-free cutout silhouette.
	float width = max(fwidth(mask), 0.0001);
	ALPHA = clamp((mask - 0.5) / min(width, 0.35) + 0.5, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.05;
	ALBEDO = bsp_output_color(goldsrc_texture_wash(albedo.rgb) * goldsrc_light(UV2));
}
"""
)

var entities: Array = []
var bounds_min := Vector3.ZERO
var bounds_max := Vector3.ZERO
var source_path := ""
var surface_count := 0
var collision_face_count := 0
var world_collision_face_count := 0
var submodel_collision_face_count := 0
var navigation_region: NavigationRegion3D
var navigation_links: Array[NavigationLink3D] = []
var collision_face_textures: Array[String] = []
var _collision_faces := PackedVector3Array()
var _model_bounds := {}
var _model_roots := {}
var _model_collision_bodies := {}
var _model_collision_faces := {}
var _model_collision_face_textures := {}
var _model_entity_indices := {}
var _entity_model_indices := {}
var _model_classnames := {}
var _model_properties := {}
var _model_pivots := {}
var _model_initial_transforms := {}
var _world_root: Node3D
var _lightmap_texture: Texture2D
var _lightmap_shader: Shader
var _lightmap_cutout_shader: Shader
var shadow_lift := 0.0


static func lift_shadow_tint(tint: Color, amount: float) -> Color:
	# Same encoded-light adjustment as the BSP shader, before material color
	# conversion. Alpha is preserved, including the missing-probe sentinel.
	var luma := tint.r * 0.299 + tint.g * 0.587 + tint.b * 0.114
	var lift := amount * (1.0 - smoothstep(0.18, 0.65, luma))
	return Color(tint.r + lift, tint.g + lift, tint.b + lift, tint.a)


func load_map(map_path: String) -> bool:
	source_path = map_path
	shadow_lift = DUST2_SHADOW_LIFT if map_path.get_base_dir().get_file() == "de_dust2" else 0.0
	var file := FileAccess.open(map_path, FileAccess.READ)
	if file == null:
		push_error("Could not open converted map: %s" % map_path)
		return false
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Dictionary:
		push_error("Converted map JSON is invalid: %s" % map_path)
		return false
	var data := decoded as Dictionary
	if data.get("format", "") != "protocol47-bsp" or int(data.get("version", 0)) != 1:
		push_error("Unsupported converted map format: %s" % map_path)
		return false

	var raw_positions := data.get("positions", []) as Array
	var raw_normals := data.get("normals", []) as Array
	var raw_colors := data.get("colors", []) as Array
	var raw_uvs := data.get("uvs", []) as Array
	var raw_uv2s := data.get("uv2s", []) as Array
	entities = data.get("entities", []) as Array
	bounds_min = _vec3_from_dictionary(data.get("bounds_min", {}))
	bounds_max = _vec3_from_dictionary(data.get("bounds_max", {}))
	var map_root := map_path.get_base_dir()
	surface_count = 0
	collision_face_count = 0
	world_collision_face_count = 0
	submodel_collision_face_count = 0
	_collision_faces.clear()
	collision_face_textures.clear()
	_model_bounds.clear()
	_model_roots.clear()
	_model_collision_bodies.clear()
	_model_collision_faces.clear()
	_model_collision_face_textures.clear()
	_model_entity_indices.clear()
	_entity_model_indices.clear()
	_model_classnames.clear()
	_model_properties.clear()
	_model_pivots.clear()
	_model_initial_transforms.clear()
	_lightmap_texture = null
	var raw_lightmap: Variant = data.get("lightmap")
	if raw_lightmap is Dictionary:
		var lightmap_path := map_root.path_join(str((raw_lightmap as Dictionary).get("texture", "")))
		if ResourceLoader.exists(lightmap_path):
			_lightmap_texture = ResourceLoader.load(lightmap_path) as Texture2D
	if _lightmap_texture != null and _lightmap_shader == null:
		_lightmap_shader = Shader.new()
		_lightmap_shader.code = LIGHTMAP_SHADER_SOURCE
		_lightmap_cutout_shader = Shader.new()
		_lightmap_cutout_shader.code = LIGHTMAP_CUTOUT_SHADER_SOURCE
	_index_brush_entities()
	for raw_bounds in data.get("model_bounds", []):
		var model_bounds := raw_bounds as Dictionary
		var model_index := int(model_bounds.get("model_index", -1))
		var minimum := _vec3_from_dictionary(model_bounds.get("mins", {}))
		var maximum := _vec3_from_dictionary(model_bounds.get("maxs", {}))
		_model_bounds[model_index] = AABB(
			minimum,
			maximum - minimum,
		)
		var raw_entity_index: Variant = model_bounds.get("entity_index")
		if raw_entity_index != null:
			var entity_index := int(raw_entity_index)
			if entity_index >= 0:
				_model_entity_indices[model_index] = entity_index
				_entity_model_indices[entity_index] = model_index
		var pivot := _vec3_from_dictionary(model_bounds.get("pivot", {}))
		if not model_bounds.has("pivot"):
			pivot = _fallback_model_pivot(model_index, model_bounds)
		_model_pivots[model_index] = pivot
	_build_navigation_region()
	_build_model_roots()

	for raw_group in data.get("groups", []):
		var group := raw_group as Dictionary
		var model_index := int(group.get("model_index", -1))
		var start := int(group.get("vert_start", 0))
		var count := int(group.get("vert_count", 0))
		if count <= 0:
			continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var uv2s := PackedVector2Array()
		var has_uv2 := raw_uv2s.size() >= (start + count) * 2
		vertices.resize(count)
		normals.resize(count)
		colors.resize(count)
		uvs.resize(count)
		if has_uv2:
			uv2s.resize(count)
		for local_index in range(count):
			var vertex_index := start + local_index
			var position_offset := vertex_index * 3
			var uv_offset := vertex_index * 2
			if position_offset + 2 >= raw_positions.size():
				break
			var vertex := Vector3(
				float(raw_positions[position_offset]),
				float(raw_positions[position_offset + 1]),
				float(raw_positions[position_offset + 2]),
			)
			vertices[local_index] = vertex
			normals[local_index] = Vector3(
				float(raw_normals[position_offset]),
				float(raw_normals[position_offset + 1]),
				float(raw_normals[position_offset + 2]),
			)
			colors[local_index] = Color(
				float(raw_colors[position_offset]),
				float(raw_colors[position_offset + 1]),
				float(raw_colors[position_offset + 2]),
				1.0,
			)
			uvs[local_index] = Vector2(
				float(raw_uvs[uv_offset]),
				float(raw_uvs[uv_offset + 1]),
			)
			if has_uv2:
				uv2s[local_index] = Vector2(
					float(raw_uv2s[uv_offset]),
					float(raw_uv2s[uv_offset + 1]),
				)
		if not vertices.is_empty():
			var group_bounds := AABB(vertices[0], Vector3.ZERO)
			for vertex: Vector3 in vertices:
				group_bounds = group_bounds.expand(vertex)
			if _model_bounds.has(model_index):
				var existing_bounds: AABB = _model_bounds[model_index]
				_model_bounds[model_index] = existing_bounds.merge(group_bounds)
			else:
				_model_bounds[model_index] = group_bounds
		if model_index == 0 or _brush_model_is_solid(model_index):
			if not _model_collision_faces.has(model_index):
				_model_collision_faces[model_index] = PackedVector3Array()
				_model_collision_face_textures[model_index] = []
			var model_faces: PackedVector3Array = _model_collision_faces[model_index]
			model_faces.append_array(vertices)
			var texture_name := str(group.get("name", ""))
			for ignored_face in range(int(count / 3)):
				(_model_collision_face_textures[model_index] as Array).append(texture_name)
		if _brush_model_is_invisible(model_index):
			# Still solid (collision above), but GoldSrc draws nothing.
			continue

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		if has_uv2:
			arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := _material_for_group(group, map_root, has_uv2)
		mesh.surface_set_material(0, material)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = _safe_node_name(str(group.get("name", "surface")))
		mesh_instance.mesh = mesh
		var model_root := runtime_root_for_model(model_index)
		if model_root == null:
			push_warning("Skipping BSP surface for unknown model %d" % model_index)
			continue
		model_root.add_child(mesh_instance)
		surface_count += 1

	_build_collision_bodies()
	navigation_region.bake_navigation_mesh(false)
	_load_navigation_links()
	return get_child_count() > 0


func _load_navigation_links() -> void:
	# Hand-authored traversal metadata lives outside regenerated BSP exports.
	# A link expresses a real jump/drop, never a change to hull or step height.
	var path := "res://assets/navigation/%s.tscn" % source_path.get_base_dir().get_file()
	if not ResourceLoader.exists(path):
		return
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Invalid map traversal scene: " + path)
		return
	var owner := scene.instantiate()
	add_child(owner)
	for link: NavigationLink3D in owner.find_children("*", "NavigationLink3D", true, false):
		navigation_links.append(link)


func texture_name_for_face(face_index: int) -> String:
	if face_index < 0 or face_index >= collision_face_textures.size():
		return ""
	return collision_face_textures[face_index]


func brush_entity_regions(classname: String) -> Array[Dictionary]:
	## Resolves brush entities such as func_bomb_target and func_buyzone to the
	## exact AABBs of their imported BSP submodels.
	var regions: Array[Dictionary] = []
	for raw_entity in entities:
		var entity := raw_entity as Dictionary
		if str(entity.get("classname", "")) != classname:
			continue
		var properties := _entity_properties(entity)
		var model_name := str(properties.get("model", ""))
		if not model_name.begins_with("*"):
			continue
		var model_index := int(model_name.trim_prefix("*"))
		if not _model_bounds.has(model_index):
			continue
		regions.append({
			"classname": classname,
			"model_index": model_index,
			"bounds": _model_bounds[model_index],
			"team": int(properties.get("team", 0)),
			"target": str(properties.get("target", "")),
			# Source trigger contracts consumed by Game. The exported BSP model
			# bounds stay byte-for-byte derived from the map submodel; these
			# tags prevent callers from regressing to a center-point test.
			"touch_mode": "player_hull",
			"horizontal_hull_containment": classname == "func_bomb_target",
		})
	return regions


func _entity_properties(entity: Dictionary) -> Dictionary:
	var result := {}
	for raw_pair in entity.get("properties", []):
		if raw_pair is Array and raw_pair.size() >= 2:
			result[str(raw_pair[0])] = str(raw_pair[1])
	return result


func _build_navigation_region() -> void:
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "Navigation"
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh.geometry_collision_mask = 1
	navigation_mesh.cell_size = 0.04
	navigation_mesh.cell_height = 0.02
	# Derive the CS hull dimensions from the raster itself so Recast receives
	# exact voxel multiples instead of ceiling a decimal approximation.
	navigation_mesh.agent_height = navigation_mesh.cell_height * 36.0
	navigation_mesh.agent_radius = navigation_mesh.cell_size * 4.0
	navigation_mesh.agent_max_climb = navigation_mesh.cell_height * 9.0
	navigation_mesh.agent_max_slope = 48.0
	navigation_mesh.edge_max_length = 8.0
	navigation_mesh.detail_sample_distance = 2.51
	navigation_mesh.detail_sample_max_error = 0.8
	navigation_region.navigation_mesh = navigation_mesh
	add_child(navigation_region)


func _material_for_group(group: Dictionary, map_root: String, has_uv2: bool = false) -> Material:
	var material := StandardMaterial3D.new()
	var model_index := int(group.get("model_index", 0))
	var properties: Dictionary = _model_properties.get(model_index, {})
	var render_mode := int(properties.get("rendermode", 0))
	var render_amount := _render_amount(properties)
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# GoldSrc BSP lighting is already baked into the exported vertex colors.
	# Lighting these surfaces a second time with Godot's sun/ambient pass causes
	# the blown-out, flat look visible in early captures. Render the baked light
	# directly and use trilinear mipmaps (GoldSrc gl_texturemode
	# GL_LINEAR_MIPMAP_LINEAR) to remove crawl at oblique angles.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = (
		BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	)
	material.albedo_color = _fallback_color(str(group.get("name", "")))
	var albedo_texture: Texture2D = null
	var raw_texture: Variant = group.get("texture")
	if raw_texture is String and not raw_texture.is_empty():
		var texture_path := raw_texture as String
		var resource_path := map_root.path_join(texture_path)
		if ResourceLoader.exists(resource_path):
			albedo_texture = ResourceLoader.load(resource_path) as Texture2D
	material.albedo_texture = albedo_texture
	# Opaque BSP surfaces sample the per-face lightmap atlas via UV2 — that
	# is where dust2's hard, luxel-quantized baked shadow edges live. This
	# covers the world model AND plain opaque brush submodels (doors, walls):
	# GoldSrc lightmaps those exactly the same way, and the vertex-color
	# fallback's smooth gradients read as fake soft shadow blobs. Breakables
	# and pushables keep StandardMaterial (debris presenter re-tints them at
	# runtime), as do render-mode entities and liquids.
	var runtime_tinted: bool = str(_model_classnames.get(model_index, "")) in [
		"func_breakable",
		"func_pushable",
	]
	if (
		has_uv2
		and _lightmap_texture != null
		and albedo_texture != null
		and render_mode == 0
		and not runtime_tinted
		and not bool(group.get("liquid", false))
	):
		var lightmapped := ShaderMaterial.new()
		lightmapped.shader = (
			_lightmap_cutout_shader
			if bool(group.get("transparent", false))
			else _lightmap_shader
		)
		lightmapped.set_shader_parameter("albedo_tex", albedo_texture)
		lightmapped.set_shader_parameter("lightmap_tex", _lightmap_texture)
		lightmapped.set_shader_parameter("shadow_lift", shadow_lift)
		return lightmapped
	if bool(group.get("transparent", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.alpha_antialiasing_mode = (
			BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		)
		material.alpha_antialiasing_edge = 0.45
	# GoldSrc brush render modes are entity properties, not texture metadata.
	# Stock Assault's windows use kRenderTransTexture at renderamt 96; treating
	# every `{` texture as an opaque cutout makes those panes visibly wrong.
	match render_mode:
		1: # kRenderTransColor
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = _render_color(properties, render_amount)
			material.albedo_texture = null
		2: # kRenderTransTexture
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = render_amount
		3: # kRenderGlow
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = _render_color(properties, render_amount)
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		4: # kRenderTransAlpha
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.5
		5: # kRenderTransAdd
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.albedo_color = _render_color(properties, render_amount)
	if bool(group.get("liquid", false)):
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.76
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _render_amount(properties: Dictionary) -> float:
	# entvars_t is zero-initialised, so an entity that sets a render mode but
	# omits renderamt blends at 0 (de_inferno's lamp-post clip walls). Only
	# kRenderNormal ignores the amount, so it keeps the opaque default.
	var fallback := 255.0 if int(properties.get("rendermode", 0)) == 0 else 0.0
	return clampf(float(properties.get("renderamt", fallback)) / 255.0, 0.0, 1.0)


func _brush_model_is_invisible(model_index: int) -> bool:
	# Blended modes at renderamt 0 draw nothing. kRenderTransAlpha stays an
	# alpha-tested cutout here (every stock use authors renderamt 255).
	var properties: Dictionary = _model_properties.get(model_index, {})
	var render_mode := int(properties.get("rendermode", 0))
	return render_mode in [1, 2, 3, 5] and is_zero_approx(_render_amount(properties))


func _render_color(properties: Dictionary, alpha: float) -> Color:
	var parts := str(properties.get("rendercolor", "255 255 255")).split(
		" ",
		false,
	)
	var red := float(parts[0]) / 255.0 if parts.size() > 0 else 1.0
	var green := float(parts[1]) / 255.0 if parts.size() > 1 else 1.0
	var blue := float(parts[2]) / 255.0 if parts.size() > 2 else 1.0
	# Hammer commonly writes 0 0 0 for an unset rendercolor. GoldSrc treats
	# that as neutral white for textured modes rather than multiplying to black.
	if is_zero_approx(red) and is_zero_approx(green) and is_zero_approx(blue):
		red = 1.0
		green = 1.0
		blue = 1.0
	return Color(red, green, blue, alpha)


func _index_brush_entities() -> void:
	for array_index in range(entities.size()):
		var entity := entities[array_index] as Dictionary
		var entity_index := int(entity.get("entity_index", array_index))
		var properties := _entity_properties(entity)
		var model_name := str(properties.get("model", ""))
		if not model_name.begins_with("*"):
			continue
		var raw_model_index := model_name.trim_prefix("*")
		if not raw_model_index.is_valid_int():
			continue
		var model_index := int(raw_model_index)
		_model_entity_indices[model_index] = entity_index
		_entity_model_indices[entity_index] = model_index
		_model_classnames[model_index] = str(entity.get("classname", ""))
		_model_properties[model_index] = properties


func _fallback_model_pivot(model_index: int, model_bounds: Dictionary) -> Vector3:
	var entity_index := int(_model_entity_indices.get(model_index, -1))
	if entity_index >= 0:
		for array_index in range(entities.size()):
			var entity := entities[array_index] as Dictionary
			if int(entity.get("entity_index", array_index)) != entity_index:
				continue
			var raw_origin: Variant = entity.get("origin")
			if raw_origin is Dictionary:
				return _godot_position_from_goldsrc(_vec3_from_dictionary(raw_origin))
			break
	if model_bounds.has("origin"):
		return _vec3_from_dictionary(model_bounds.get("origin", {}))
	return Vector3.ZERO


func _build_model_roots() -> void:
	_world_root = Node3D.new()
	_world_root.name = "WorldModel"
	navigation_region.add_child(_world_root)
	_model_roots[0] = _world_root
	_model_pivots[0] = Vector3.ZERO
	_model_initial_transforms[0] = _world_root.transform

	var model_indices: Array = _model_bounds.keys()
	model_indices.sort()
	for raw_model_index in model_indices:
		var model_index := int(raw_model_index)
		if model_index <= 0:
			continue
		var root := Node3D.new()
		var classname := str(_model_classnames.get(model_index, "brush"))
		root.name = "Model_%03d_%s" % [model_index, _safe_node_name(classname)]
		root.position = _model_pivots.get(model_index, Vector3.ZERO) as Vector3
		root.set_meta("model_index", model_index)
		root.set_meta("entity_index", int(_model_entity_indices.get(model_index, -1)))
		root.set_meta("classname", classname)
		add_child(root)
		_model_roots[model_index] = root
		_model_initial_transforms[model_index] = root.transform


func _build_collision_bodies() -> void:
	var world_faces: PackedVector3Array = _model_collision_faces.get(
		0,
		PackedVector3Array(),
	)
	_collision_faces = world_faces
	if not world_faces.is_empty():
		var world_body := StaticBody3D.new()
		world_body.name = "WorldCollision"
		world_body.collision_layer = 1
		world_body.collision_mask = 0
		world_body.set_meta("model_index", 0)
		var world_shape := CollisionShape3D.new()
		var world_concave := ConcavePolygonShape3D.new()
		world_concave.set_faces(world_faces)
		world_shape.shape = world_concave
		world_body.add_child(world_shape)
		_world_root.add_child(world_body)
		_model_collision_bodies[0] = world_body
		world_collision_face_count = int(world_faces.size() / 3)
		for texture_name in _model_collision_face_textures.get(0, []):
			collision_face_textures.append(str(texture_name))

	var model_indices: Array = _model_collision_faces.keys()
	model_indices.sort()
	for raw_model_index in model_indices:
		var model_index := int(raw_model_index)
		if model_index <= 0:
			continue
		var model_faces: PackedVector3Array = _model_collision_faces[model_index]
		if model_faces.is_empty():
			continue
		var root := runtime_root_for_model(model_index)
		if root == null:
			continue
		var body := AnimatableBody3D.new()
		body.name = "ModelCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		# The source brush clock already updates on physics ticks. Godot's
		# sync_to_physics listens for LOCAL transform changes, not movement of
		# this parent root; enabling it leaves the collider at its old pose.
		body.sync_to_physics = false
		body.set_meta("model_index", model_index)
		body.set_meta("entity_index", int(_model_entity_indices.get(model_index, -1)))
		body.set_meta("classname", str(_model_classnames.get(model_index, "")))
		body.set_meta("face_textures", _model_collision_face_textures.get(model_index, []).duplicate())
		var collision := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(model_faces)
		collision.shape = shape
		body.add_child(collision)
		root.add_child(body)
		# Collision lives as an identity-local child of the shared model root:
		# brush-runtime motion applied to the root carries the visual and the
		# collider together through ordinary global-transform notifications.
		_model_collision_bodies[model_index] = body
		submodel_collision_face_count += int(model_faces.size() / 3)
	collision_face_count = world_collision_face_count + submodel_collision_face_count


func _brush_model_is_solid(model_index: int) -> bool:
	if model_index == 0:
		return true
	var classname := str(_model_classnames.get(model_index, ""))
	var properties: Dictionary = _model_properties.get(model_index, {})
	var spawnflags := int(properties.get("spawnflags", 0))
	match classname:
		"func_door", "func_door_rotating", "func_train", "func_tracktrain":
			return (spawnflags & 8) == 0
		"func_rot_button":
			return (spawnflags & 1) == 0
		"func_rotating":
			return (spawnflags & 64) == 0
		"func_wall_toggle":
			return (spawnflags & 1) == 0
		"func_breakable", "func_button", "func_conveyor", \
		"func_pendulum", "func_plat", "func_platrot", "func_pushable", \
		"func_vehicle", "func_wall", "momentary_door", "momentary_rot_button":
			return true
	return false


func runtime_root_for_model(model_index: int) -> Node3D:
	return _model_roots.get(model_index) as Node3D


func model_root(model_index: int) -> Node3D:
	return runtime_root_for_model(model_index)


func runtime_root_for_entity(entity_index: int) -> Node3D:
	return runtime_root_for_model(model_index_for_entity(entity_index))


func model_root_for_entity(entity_index: int) -> Node3D:
	return runtime_root_for_entity(entity_index)


func model_index_for_entity(entity_index: int) -> int:
	return int(_entity_model_indices.get(entity_index, -1))


func entity_index_for_model(model_index: int) -> int:
	return int(_model_entity_indices.get(model_index, -1))


func collision_body_for_model(model_index: int) -> CollisionObject3D:
	return _model_collision_bodies.get(model_index) as CollisionObject3D


func model_collision_body(model_index: int) -> CollisionObject3D:
	return collision_body_for_model(model_index)


func initial_transform_for_model(model_index: int) -> Transform3D:
	return _model_initial_transforms.get(model_index, Transform3D.IDENTITY) as Transform3D


func set_model_runtime_transform(model_index: int, value: Transform3D) -> bool:
	if model_index <= 0:
		return false
	var root := runtime_root_for_model(model_index)
	if root == null:
		return false
	root.transform = value
	return true


func set_model_runtime_position(model_index: int, value: Vector3) -> bool:
	var root := runtime_root_for_model(model_index)
	if model_index <= 0 or root == null:
		return false
	root.position = value
	return true


func set_model_runtime_rotation(model_index: int, value: Vector3) -> bool:
	var root := runtime_root_for_model(model_index)
	if model_index <= 0 or root == null:
		return false
	root.rotation = value
	return true


func reset_model_runtime_transform(model_index: int) -> bool:
	if model_index <= 0 or not _model_initial_transforms.has(model_index):
		return false
	return set_model_runtime_transform(
		model_index,
		_model_initial_transforms[model_index] as Transform3D,
	)


## Atomically exposes or removes a BSP submodel's rendered and collidable
## presence. Runtime state remains on the stable model root so round reset can
## restore the same object without rebuilding meshes or physics resources.
func set_model_runtime_active(model_index: int, active: bool) -> bool:
	if model_index <= 0:
		return false
	var model_root := runtime_root_for_model(model_index)
	if model_root == null:
		return false
	model_root.visible = active
	var body := collision_body_for_model(model_index)
	if body != null:
		if not body.has_meta("initial_collision_layer"):
			body.set_meta("initial_collision_layer", body.collision_layer)
		body.collision_layer = (
			int(body.get_meta("initial_collision_layer", 1))
			if active
			else 0
		)
	model_root.set_meta("runtime_active", active)
	return true


func model_runtime_active(model_index: int) -> bool:
	var model_root := runtime_root_for_model(model_index)
	if model_root == null:
		return false
	return bool(model_root.get_meta("runtime_active", model_root.visible))


func runtime_model_indices() -> Array[int]:
	var indices: Array[int] = []
	for raw_model_index in _model_roots.keys():
		var model_index := int(raw_model_index)
		if model_index > 0:
			indices.append(model_index)
	indices.sort()
	return indices


func model_bounds_for_index(model_index: int) -> AABB:
	return _model_bounds.get(model_index, AABB()) as AABB


func model_classname(model_index: int) -> String:
	return str(_model_classnames.get(model_index, ""))


func _fallback_color(texture_name: String) -> Color:
	var normalized := texture_name.to_lower()
	if normalized == "black":
		return Color("#111315")
	if normalized == "white" or normalized.begins_with("generic"):
		return Color("#a6a29a")
	return Color.WHITE


func spawn_points(classname: String) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for raw_entity in entities:
		var entity := raw_entity as Dictionary
		if str(entity.get("classname", "")) != classname:
			continue
		var raw_origin: Variant = entity.get("origin")
		if not raw_origin is Dictionary:
			continue
		var origin := _vec3_from_dictionary(raw_origin)
		# GoldSrc point entities describe a centered player origin and are dropped
		# to the BSP floor when spawned. Our CharacterBody origin is at its feet,
		# so resolve the same floor against the imported source triangles instead
		# of treating the entity origin as feet (which spawned actors 48-72 HU
		# above Dust2).
		var centered_origin := Vector3(
			origin.x * 0.01,
			origin.z * 0.01,
			-origin.y * 0.01,
		)
		var floor_y := _hull_floor_below(centered_origin)
		if not is_nan(floor_y):
			centered_origin.y = floor_y + SPAWN_FLOOR_EPSILON
		points.append(centered_origin)
	return points


func _hull_floor_below(point: Vector3) -> float:
	## GoldSrc DROP_TO_FLOOR drops the whole 32 HU player hull, not a point.
	## Rest the spawn on the highest support under the hull footprint (center
	## plus four inset corners) so a spawn beside sloped geometry never embeds
	## a hull corner in the floor — the physics engine would depenetrate the
	## body upward on its first tick and briefly launch it airborne.
	var inset := 16.0 * 0.01 - SPAWN_FLOOR_EPSILON
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(inset, 0.0, inset),
		Vector3(inset, 0.0, -inset),
		Vector3(-inset, 0.0, inset),
		Vector3(-inset, 0.0, -inset),
	]
	var highest := -INF
	for offset: Vector3 in offsets:
		var corner_floor := _floor_below(point + offset)
		if not is_nan(corner_floor):
			highest = maxf(highest, corner_floor)
	return highest if highest > -INF else NAN


func _floor_below(point: Vector3) -> float:
	var highest_floor := -INF
	for face_offset in range(0, _collision_faces.size(), 3):
		var a := _collision_faces[face_offset]
		var b := _collision_faces[face_offset + 1]
		var c := _collision_faces[face_offset + 2]
		var normal := (b - a).cross(c - a)
		if absf(normal.y) <= 0.000001:
			continue
		var denominator := (
			(b.z - c.z) * (a.x - c.x)
			+ (c.x - b.x) * (a.z - c.z)
		)
		if absf(denominator) <= 0.000001:
			continue
		var alpha := (
			(b.z - c.z) * (point.x - c.x)
			+ (c.x - b.x) * (point.z - c.z)
		) / denominator
		var beta := (
			(c.z - a.z) * (point.x - c.x)
			+ (a.x - c.x) * (point.z - c.z)
		) / denominator
		var gamma := 1.0 - alpha - beta
		if alpha < -0.00001 or beta < -0.00001 or gamma < -0.00001:
			continue
		var plane_y := alpha * a.y + beta * b.y + gamma * c.y
		if plane_y <= point.y + 0.00001:
			highest_floor = maxf(highest_floor, plane_y)
	return highest_floor if highest_floor > -INF else NAN


func _vec3_from_dictionary(raw: Variant) -> Vector3:
	if not raw is Dictionary:
		return Vector3.ZERO
	var data := raw as Dictionary
	return Vector3(float(data.get("x", 0)), float(data.get("y", 0)), float(data.get("z", 0)))


func _godot_position_from_goldsrc(source: Vector3) -> Vector3:
	return Vector3(source.x * 0.01, source.z * 0.01, -source.y * 0.01)


func _safe_node_name(value: String) -> String:
	var output := ""
	for character in value:
		output += character if character.is_valid_identifier() or character.is_valid_int() else "_"
	return output if not output.is_empty() else "Surface"
