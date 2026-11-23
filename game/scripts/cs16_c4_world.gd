class_name CS16C4World
extends RigidBody3D

## Source-backed dropped C4 weaponbox.
##
## DropPlayerItem wraps models/w_backpack.mdl in CWeaponBox: MOVETYPE_TOSS,
## SOLID_TRIGGER, a point hull, and no pickup before FL_ONGROUND. The rigid
## body supplies the toss/floor contact; the child Area3D supplies the
## non-blocking player touch contract after landing.

signal pickup_requested(actor: Combatant)

const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")
const BACKPACK_MODEL := "res://generated/world_weapons/backpack/model.json"
const PLANTED_MODEL := "res://generated/world_weapons/c4/model.json"
const PICKUP_SIZE := Vector3.ONE * 2.0 * Combatant.GOLDSRC_UNIT
const FALL_POINT_RADIUS := 1.0 * Combatant.GOLDSRC_UNIT

var claimed := false
var materialized := false
var pickup_area: Area3D
var world_shape_node: CollisionShape3D
var _flight_ticks := 0


func _ready() -> void:
	name = "DroppedC4"
	collision_layer = 8
	collision_mask = 1
	mass = 2.0
	gravity_scale = 1.0
	linear_damp = 0.35
	angular_damp = 0.8
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_fall_body_entered)

	world_shape_node = CollisionShape3D.new()
	world_shape_node.name = "FallPointCollision"
	var world_shape := SphereShape3D.new()
	world_shape.radius = FALL_POINT_RADIUS
	world_shape_node.shape = world_shape
	world_shape_node.position.y = FALL_POINT_RADIUS
	add_child(world_shape_node)

	var visual := create_source_model(BACKPACK_MODEL, "BackpackModel")
	# The converted w_backpack geometry has a floor-space minimum at zero.
	# Offsetting it upward produced a detached shadow/visible 2.5 HU air gap.
	visual.position.y = 0.0
	add_child(visual)

	pickup_area = Area3D.new()
	pickup_area.name = "PickupTrigger"
	pickup_area.collision_layer = 0
	pickup_area.collision_mask = 2 | 4
	pickup_area.monitoring = false
	pickup_area.monitorable = true
	var pickup_shape_node := CollisionShape3D.new()
	var pickup_shape := BoxShape3D.new()
	pickup_shape.size = PICKUP_SIZE
	pickup_shape_node.shape = pickup_shape
	pickup_shape_node.position.y = 1.0 * Combatant.GOLDSRC_UNIT
	pickup_area.add_child(pickup_shape_node)
	pickup_area.body_entered.connect(_on_pickup_body_entered)
	add_child(pickup_area)


func _physics_process(_delta: float) -> void:
	_flight_ticks += 1
	# MOVETYPE_TOSS receives its launch velocity before FL_ONGROUND can be set.
	# Give the rigid body one integration step so a ground-height manual drop
	# actually travels instead of materializing at its spawn coordinate.
	if _flight_ticks <= 1:
		return
	if not materialized and _has_floor_support():
		_materialize()


func _on_fall_body_entered(body: Node) -> void:
	if materialized or not body is CollisionObject3D:
		return
	if ((body as CollisionObject3D).collision_layer & 1) != 0:
		# A wall touch must not make the weaponbox pickable. Defer the space
		# query until the collision callback has finished and require support
		# directly below the point hull (GoldSrc's FL_ONGROUND gate).
		call_deferred("_materialize_if_grounded")


func _materialize_if_grounded() -> void:
	if not materialized and _has_floor_support():
		_materialize()


func _has_floor_support() -> bool:
	if not is_inside_tree() or linear_velocity.y > 0.05:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * FALL_POINT_RADIUS,
		global_position - Vector3.UP * (FALL_POINT_RADIUS + 2.0 * Combatant.GOLDSRC_UNIT),
		1,
		[get_rid()],
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return Vector3(hit.get("normal", Vector3.ZERO)).dot(Vector3.UP) >= 0.7


func _materialize() -> void:
	if materialized:
		return
	materialized = true
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	world_shape_node.set_deferred("disabled", true)
	pickup_area.set_deferred("monitoring", true)


func _on_pickup_body_entered(body: Node3D) -> void:
	if not materialized or claimed or not body is Combatant:
		return
	var actor := body as Combatant
	if not actor.alive or actor.team != Combatant.TEAM_TERRORIST:
		return
	claimed = true
	pickup_area.set_deferred("monitoring", false)
	pickup_requested.emit(actor)


static func create_source_model(model_path: String, model_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = model_name
	var template := _load_static_template(model_path)
	if template.is_empty():
		return root
	var instance := CharacterModelScript._create_instance(model_name + "Mesh", template)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(instance)
	return root


static func _load_static_template(model_path: String) -> Dictionary:
	var file := FileAccess.open(model_path, FileAccess.READ)
	if file == null:
		push_error("Missing original C4 world model export: %s" % model_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if (
		not parsed is Dictionary
		or str(parsed.get("format", "")) != "protocol47-mdl"
		or int(parsed.get("version", 0)) < 1
	):
		push_error("Invalid original C4 world model export: %s" % model_path)
		return {}
	# Static world exports are protocol47-mdl v1. Their base geometry is the
	# same schema as animated v2 models, but they intentionally have no tapes.
	return CharacterModelScript._build_template(model_path, parsed)


static func create_planted_visual() -> Node3D:
	var visual := PlantedC4Visual.new()
	visual.name = "PlantedC4Model"
	# The converted w_c4.mdl surfaces (c4base satchel, c4timer keypad face with
	# its red 0:00 digits, c4wires) render with their unmodified source texels
	# and nearest filtering — no albedo tint: the earlier down-tint flattened
	# the bevel shading painted into c4base.bmp until the satchel read as an
	# untextured gray-box primitive.
	var body := create_source_model(PLANTED_MODEL, "PlantedC4Body")
	# The shared MDL pipeline ships unshaded meshes without normals, which
	# rendered the satchel as one uniform unlit olive slab — a soap bar. The
	# GoldSrc studiomodel renderer lambert-lights each facet, which is what
	# makes w_c4's hard low-poly bevels and the black detonator unit read.
	# Rebuild the planted body with flat per-facet normals and diffuse-only
	# shading (roughness 1, no specular — studio models have no highlight).
	_apply_studio_lambert_shading(body)
	visual.add_child(body)
	return visual


static func _apply_studio_lambert_shading(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var source := mesh_instance.mesh as ArrayMesh
		if source != null and source.get_surface_count() > 0:
			var rebuilt := ArrayMesh.new()
			for surface in range(source.get_surface_count()):
				var tool := SurfaceTool.new()
				tool.create_from(source, surface)
				# Deindex first: on indexed geometry generate_normals() averages
				# across shared vertices, which melted the satchel's hard bevels
				# into a smooth rounded soap-bar. Unindexed triangles get true
				# per-facet normals, matching the low-poly studio silhouette.
				tool.deindex()
				tool.generate_normals()
				var material := source.surface_get_material(surface)
				if material is StandardMaterial3D:
					var shaded := (material as StandardMaterial3D).duplicate()
					shaded.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					shaded.roughness = 1.0
					shaded.metallic = 0.0
					shaded.metallic_specular = 0.0
					material = shaded
				tool.set_material(material)
				tool.commit(rebuilt)
			mesh_instance.mesh = rebuilt
	for child in node.get_children():
		_apply_studio_lambert_shading(child)


class PlantedC4Visual:
	extends Node3D

	## Planted C4 with the CS 1.6 red status LED: a small bright light sprite
	## that pulses, accelerating as the bomb timer runs down (mirrors the
	## grenade.cpp C4Think blink cadence).

	const LED_ON_SECONDS := 0.12
	const LED_COLOR := Color8(255, 44, 32)

	var total_seconds := 45.0
	var seconds_remaining := 45.0
	var _cycle_clock := 0.0
	var _led: Sprite3D
	var _led_core: Sprite3D
	var _led_light: OmniLight3D

	func _ready() -> void:
		# A Sprite3D deliberately: the planted bomb contract exposes exactly the
		# three source w_c4 mesh surfaces; the LED is a light sprite, not a
		# fourth model surface.
		_led = Sprite3D.new()
		_led.name = "C4BlinkLed"
		_led.texture = _led_glow_texture()
		_led.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_led.shaded = false
		_led.transparent = true
		_led.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		_led.render_priority = 2
		_led.modulate = LED_COLOR
		# A small SOFT glow: CS 1.6's blink is a tiny round additive glow sprite
		# at the LED, never a spiky lens-flare streak — but it must genuinely
		# READ as a lit diode at review distance, so a hot near-white core sits
		# inside the red halo.
		_led.pixel_size = 0.0018
		_led.position = Vector3(0.045, 0.082, 0.012)
		add_child(_led)
		_led_core = Sprite3D.new()
		_led_core.name = "C4BlinkLedCore"
		_led_core.texture = _led_glow_texture()
		_led_core.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_led_core.shaded = false
		_led_core.transparent = true
		_led_core.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		_led_core.render_priority = 3
		_led_core.modulate = Color(1.0, 0.62, 0.5)
		_led_core.pixel_size = 0.0007
		_led_core.position = _led.position
		add_child(_led_core)
		_led_light = OmniLight3D.new()
		_led_light.name = "C4BlinkLight"
		_led_light.light_color = LED_COLOR
		_led_light.light_energy = 0.3
		_led_light.omni_range = 0.16
		# The diode itself must not floodlight the (lambert-shaded) satchel
		# red — in CS 1.6 the blink is only the glow sprite. Restrict the
		# light to render layer 2, which no world/prop mesh occupies.
		_led_light.light_cull_mask = 1 << 1
		_led_light.shadow_enabled = false
		_led_light.position = _led.position + Vector3(0.0, 0.02, 0.0)
		add_child(_led_light)
		_set_led(true)

	func set_countdown(total: float, remaining: float) -> void:
		total_seconds = maxf(total, 0.001)
		seconds_remaining = clampf(remaining, 0.0, total_seconds)

	func blink_interval() -> float:
		# ~0.75 s pulses right after the plant, accelerating toward a rapid
		# ~0.1 s strobe in the final seconds.
		var fraction := clampf(seconds_remaining / total_seconds, 0.0, 1.0)
		return lerpf(0.09, 0.75, fraction)

	func _process(delta: float) -> void:
		seconds_remaining = maxf(seconds_remaining - delta, 0.0)
		_cycle_clock += delta
		var interval := blink_interval()
		while _cycle_clock >= interval:
			_cycle_clock -= interval
		_set_led(_cycle_clock < LED_ON_SECONDS)

	func _set_led(lit: bool) -> void:
		if is_instance_valid(_led):
			_led.visible = lit
		if is_instance_valid(_led_core):
			_led_core.visible = lit
		if is_instance_valid(_led_light):
			_led_light.visible = lit

	static func _led_glow_texture() -> Texture2D:
		# Tiny radial falloff so the LED reads as a bright sprite point, not a
		# hard-edged quad. Generated once; no external asset dependency.
		var size := 32
		var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y in range(size):
			for x in range(size):
				var distance := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length()
				var intensity := clampf(1.0 - distance / (size * 0.5), 0.0, 1.0)
				# Steeper falloff: a round soft diode glow with no visible quad
				# edge and no streaky arms.
				intensity = pow(intensity, 2.4)
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, intensity))
		return ImageTexture.create_from_image(image)
