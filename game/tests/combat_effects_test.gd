extends SceneTree

const CombatEffects := preload("res://scripts/cs16_combat_effects.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("COMBAT EFFECTS TEST: " + message)


func _run() -> void:
	_test_complete_effect_assets()
	_test_source_profiles()
	_test_sprite_orientations()
	_test_weapon_event_tape()
	_test_impact_and_decal_budget()
	_test_source_spark_contract()
	_test_blood_event_tape()
	_test_he_event_tape()
	_test_render_rate_independence()
	_test_immutable_asset_reuse()
	await _test_presentation_warmup()

	if failures.is_empty():
		print("GAME_COMBAT_EFFECTS_TEST_PASS")
		quit(0)
	else:
		print("GAME_COMBAT_EFFECTS_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)


func _test_complete_effect_assets() -> void:
	var manager := _manager()
	var sprites: Dictionary = manager._manifest().sprites
	for required: String in ["muzzleflash1", "muzzleflash2", "rifle_smoke1", "rifle_smoke2", "rifle_smoke3", "pistol_smoke1", "pistol_smoke2", "blood", "bloodspray", "richo1", "fexplo", "eexplo", "steam1", "wall_puff1", "gas_puff_01", "black_smoke3"]:
		_check(sprites.has(required), "runtime effect %s is declared by the asset manifest" % required)
		if not sprites.has(required):
			continue
		for path: String in sprites[required].frames:
			_check(ResourceLoader.exists("res://assets/vfx/" + path), "effect frame exists: " + path)
	manager.spawn_smoke_cloud(Vector3.ZERO, 47)
	_check(_events_of_type(manager.event_log, CombatEffects.EVENT_SMOKE_CLOUD).size() == CombatEffects.SMOKE_CLOUD_PUFF_COUNT, "smoke grenade creates all vision-obscuring puffs")
	manager.clear_event_log()
	var impact_audio: Array[String] = []
	manager.world_audio_requested.connect(func(event_name: String, _channel: int,
			_position: Vector3, _overrides: Dictionary) -> void: impact_audio.append(event_name))
	manager.spawn_world_impact(Vector3.ZERO, Vector3.BACK, 0)
	_check(_events_of_type(manager.event_log, CombatEffects.EVENT_IMPACT_PUFF).size() == 1, "world impact includes the source wall puff")
	manager.spawn_world_impact(Vector3.RIGHT, Vector3.BACK, 1, "metal")
	_check(impact_audio == ["impact.ricochet", "impact.ricochet_metal"],
		"world impacts request deterministic concrete and metal audio")
	manager.queue_free()


func _test_presentation_warmup() -> void:
	var manager := _manager()
	var display_camera := Camera3D.new()
	manager.add_child(display_camera)
	display_camera.make_current()
	var entry_camera := Camera3D.new()
	manager.add_child(entry_camera)
	entry_camera.position = Vector3(3, 1, -5)
	entry_camera.fov = 74.0
	entry_camera.near = 0.035
	var entry_transform := entry_camera.global_transform
	manager.warm_up_presentation(entry_camera)
	if not manager.presentation_is_ready:
		await manager.presentation_ready
	_check(manager.presentation_is_ready, "presentation warmup completes before live combat")
	_check(manager.event_log.is_empty(), "warmup emits no live gameplay effects")
	_check(manager._sprites.is_empty() and manager._motions.is_empty(), "warmup leaves no simulated objects in the live world")
	_check(root.get_camera_3d() == display_camera, "entry-view preparation never switches the visible camera")
	_check(entry_camera.global_transform == entry_transform and is_equal_approx(entry_camera.fov, 74.0) and is_equal_approx(entry_camera.near, 0.035), "entry-view preparation preserves player camera state")
	await process_frame
	_check(manager.find_children("*", "SubViewport", true, false).is_empty(), "warmup retires staging viewports before deployment")
	var prepared := manager.get_node_or_null("PreparedC4Presentation") as Node3D
	var prepared_reference: WeakRef
	if DisplayServer.get_name() != "headless":
		_check(is_instance_valid(prepared), "rendered warmup retains the real planted-C4 shader owners")
		if is_instance_valid(prepared):
			prepared_reference = weakref(prepared)
			_check(not prepared.is_visible_in_tree() and prepared.process_mode == Node.PROCESS_MODE_DISABLED,
				"retained C4 presentation is hidden and cannot advance a countdown")
			_check(prepared.find_children("*", "CollisionObject3D", true, false).is_empty(),
				"retained C4 presentation has no gameplay collision or pickup")
			_check(prepared.find_children("*", "Sprite3D", true, false).size() == 2,
				"both C4 LED shader owners survive staging teardown")
			for light: Node3D in prepared.find_children("*", "Light3D", true, false):
				_check(not light.is_visible_in_tree(), "retained C4 cannot illuminate the live world")
			var remaining: float = prepared.seconds_remaining
			await process_frame
			_check(prepared.seconds_remaining == remaining, "retained C4 countdown remains frozen")
	else:
		_check(prepared == null, "headless tests do not allocate rendered C4 warmup owners")
	var child_count := manager.get_child_count()
	manager.warm_up_presentation()
	_check(manager.presentation_is_ready, "repeated warmup is idempotent")
	_check(manager.get_child_count() == child_count, "repeated warmup does not accumulate shader owners")
	manager.queue_free()
	await process_frame
	if prepared_reference != null:
		_check(prepared_reference.get_ref() == null, "scene teardown releases the retained C4 presentation")


func _manager() -> CS16CombatEffects:
	var manager := CombatEffects.new()
	manager.set_physics_process(false)
	root.add_child(manager)
	return manager


func _test_immutable_asset_reuse() -> void:
	CombatEffects.release_cached_resources()
	var manager := _manager()
	var first := manager._spawn_shell("rshell", Vector3.ZERO, Vector3.RIGHT, 0) as MeshInstance3D
	var second := manager._spawn_shell("rshell", Vector3.ONE, Vector3.LEFT, 1) as MeshInstance3D
	_check(first != second and first.mesh == second.mesh, "shell instances share immutable GPU geometry")
	manager.advance_tick()
	_check(first.position != second.position, "shared shell geometry retains independent motion")
	var manifest := manager._manifest()
	var path := "res://assets/vfx/%s" % str(manifest.sprites.muzzleflash2.frames[0])
	var texture := CombatEffects._frame_texture(path, false)
	var reference: WeakRef = weakref(texture)
	texture = null
	_check(reference.get_ref() != null, "sprite frame stays resident between effects")
	_check(CombatEffects._frame_texture(path, false) == reference.get_ref(), "later effects reuse resident texture")
	var decal_path := "res://assets/vfx/%s" % str(manifest.decals.shot1.texture)
	manager.spawn_decal("shot1", Vector3.ZERO, Vector3.UP, "shot")
	_check(CombatEffects._frame_texture_cache.has(decal_path), "boosted decals retain their source PNG between impacts")
	var decal_reference: WeakRef = weakref(CombatEffects._frame_texture_cache[decal_path])
	manager.spawn_decal("shot1", Vector3.ONE, Vector3.UP, "shot")
	_check(CombatEffects._frame_texture_cache[decal_path] == decal_reference.get_ref(), "repeated impacts reuse the same source texture")
	var first_sprite := manager._spawn_sprite("muzzleflash2", Vector3.ZERO, 0.14, 30.0, "test")
	var material := (first_sprite.mesh as QuadMesh).material as StandardMaterial3D
	var material_reference: WeakRef = weakref(material)
	material = null
	_check(CombatEffects._shader_material_cache.values().has(material_reference.get_ref()), "effect shader retains a material owner between volleys")
	var shader_variants := CombatEffects._shader_material_cache.size()
	for shot in range(20):
		manager._spawn_sprite("muzzleflash2", Vector3.ZERO, 0.14, 30.0, "test", 0, false, Color(0.5, 0.2, 0.1))
	_check(CombatEffects._shader_material_cache.size() == shader_variants, "shader retention is bounded by render state, not shot count or color")
	CombatEffects.release_cached_resources()
	_check(CombatEffects._frame_texture_cache.is_empty() and CombatEffects._shell_mesh_cache.is_empty()
		and CombatEffects._shader_material_cache.is_empty(), "explicit teardown releases presentation caches")
	manager.queue_free()


func _events_of_type(events: Array[Dictionary], event_type: String) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for event in events:
		if str(event.type) == event_type:
			selected.append(event)
	return selected


func _has_authored_decal_pixel(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and (pixel.r < 0.99 or pixel.g < 0.99 or pixel.b < 0.99):
				return true
	return false


func _test_source_profiles() -> void:
	var ak := CombatEffects.shot_profile("ak47", 0)
	var deagle := CombatEffects.shot_profile("deagle", 0)
	_check(str(ak.muzzle) == "muzzleflash2", "AK uses the round-core muzzleflash2 sprite")
	_check(str(ak.shell) == "rshell", "AK ejects the original rifle shell model")
	_check(str(deagle.muzzle) == "muzzleflash2", "Deagle uses the original muzzleflash2 sprite")
	_check(str(deagle.shell) == "pshell", "Deagle ejects the original pistol shell model")
	for shot_sequence in range(32):
		_check(
			not CombatEffects.emits_tracer("ak47", shot_sequence),
			"AK does not emit an unconditional bright-line tracer",
		)
		_check(
			not CombatEffects.emits_tracer("deagle", shot_sequence),
			"Deagle does not emit an unconditional bright-line tracer",
		)
	var authored_geometry := CombatEffects.sprite_frame_geometry({
		"origin_x": -4,
		"origin_y": 14,
		"width": 20,
		"height": 12,
	}, 2.0)
	_check(
		authored_geometry.size == Vector2(0.4, 0.24),
		"sprite geometry uses the authored per-frame width and height",
	)
	_check(
		authored_geometry.center_offset.is_equal_approx(Vector3(0.12, 0.16, 0.0)),
		"non-centered GoldSrc frame origins produce the authored quad offset",
	)


func _test_sprite_orientations() -> void:
	_check(
		CombatEffects.billboard_mode_for_orientation(0)
			== BaseMaterial3D.BILLBOARD_FIXED_Y,
		"SPR_VP_PARALLEL_UPRIGHT maps to an upright billboard",
	)
	_check(
		CombatEffects.billboard_mode_for_orientation(1)
			== BaseMaterial3D.BILLBOARD_FIXED_Y,
		"SPR_FACING_UPRIGHT maps to an upright billboard",
	)
	_check(
		CombatEffects.billboard_mode_for_orientation(2)
			== BaseMaterial3D.BILLBOARD_ENABLED,
		"SPR_VP_PARALLEL maps to a view-plane billboard",
	)
	_check(
		CombatEffects.billboard_mode_for_orientation(3)
			== BaseMaterial3D.BILLBOARD_DISABLED,
		"SPR_ORIENTED preserves world orientation",
	)
	_check(
		CombatEffects.billboard_mode_for_orientation(4)
			== BaseMaterial3D.BILLBOARD_ENABLED,
		"SPR_VP_PARALLEL_ORIENTED maps to view-plane plus authored roll",
	)
	var manager := _manager()
	var steam := manager._spawn_sprite(
		"steam1",
		Vector3.ZERO,
		1.0,
		5.0,
		CombatEffects.EVENT_HE_SMOKE,
		0,
		false,
		Color.WHITE,
		Vector3.ZERO,
		37.0,
	)
	var steam_event: Dictionary = manager.event_log[-1]
	var steam_material := (steam.mesh as QuadMesh).material as StandardMaterial3D
	_check(int(steam_event.orientation) == 4, "steam1 retains imported orientation 4")
	_check(
		steam_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED,
		"steam1 uses view-plane-parallel orientation",
	)
	_check(
		is_equal_approx(rad_to_deg(steam.rotation.z), 37.0),
		"orientation 4 retains the authored roll",
	)
	manager.queue_free()


func _test_weapon_event_tape() -> void:
	var manager := _manager()
	manager.spawn_weapon_shot(
		"ak47",
		0,
		Vector3.ZERO,
		Vector3.FORWARD,
		Vector3.RIGHT,
		Vector3.UP,
	)
	_check(manager.event_log.size() == 3, "AK shot emits muzzle, smoke, and shell events only")
	var event_types: Array[String] = []
	for event in manager.event_log:
		event_types.append(str(event.type))
	_check(
		event_types == [
			CombatEffects.EVENT_MUZZLE_FLASH,
			CombatEffects.EVENT_MUZZLE_SMOKE,
			CombatEffects.EVENT_SHELL,
		],
		"AK effect event ordering is deterministic",
	)
	_check(str(manager.event_log[0].asset) == "muzzleflash2", "AK muzzle event names original asset")
	_check(str(manager.event_log[1].asset) == "rifle_smoke1", "AK first shot uses rifle_smoke1")
	_check(int(manager.event_log[1].start_tick) == 4, "weapon smoke trails the flash by fixed ticks")
	_check(str(manager.event_log[2].asset) == "rshell", "AK shell event names original asset")
	_check(
		int(manager.event_log[2].expire_tick) == CombatEffects.SHELL_LIFETIME_TICKS,
		"shell lifetime is the original 2.5 seconds",
	)
	_check(
		_events_of_type(manager.event_log, "tracer").is_empty(),
		"shot tape contains no placeholder tracer event",
	)
	manager.advance_tick(9)
	_check(manager._sprites.size() == 2, "muzzle is alive through tick nine")
	manager.advance_tick()
	_check(manager._sprites.size() == 1, "three-frame 30 fps muzzle expires exactly at tick ten")
	manager.queue_free()


func _test_impact_and_decal_budget() -> void:
	var manager := _manager()
	manager.spawn_world_impact(Vector3.ZERO, Vector3.BACK, 0)
	var decals := _events_of_type(manager.event_log, CombatEffects.EVENT_WORLD_DECAL)
	var particles := _events_of_type(manager.event_log, CombatEffects.EVENT_IMPACT_PARTICLES)
	_check(decals.size() == 1, "world impact creates one original decal")
	_check(str(decals[0].asset) == "shot1", "first world impact uses shot1")
	_check(particles.size() == 1, "world impact creates restrained material particles")
	_check(int(particles[0].count) == 3, "concrete impact uses three small particles")
	_check(str(particles[0].shape) == "gravity_tracer", "impact particles use tracer geometry")
	for child in manager.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			_check(not mesh is SphereMesh, "bullet impacts never create glowing spheres")
			_check(not mesh is BoxMesh, "bullet impacts never use synthetic cube particles")
			if mesh is ImmediateMesh:
				_check(
					mesh.get_surface_count() == 1,
					"impact tracer owns one deterministic line surface",
				)

	var decal_mesh := (manager._decal_nodes[0] as MeshInstance3D).mesh as QuadMesh
	var decal_material := decal_mesh.material as StandardMaterial3D
	_check(
		decal_material.blend_mode == BaseMaterial3D.BLEND_MODE_MUL,
		"decal uses GoldSrc-style multiplicative modulation",
	)
	_check(
		decal_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"decal modulates the already-lit destination without double lighting",
	)
	var decal_image := (
		load("res://assets/vfx/decals/shot1.png") as Texture2D
	).get_image()
	_check(
		decal_image.get_pixel(8, 8).is_equal_approx(Color8(140, 140, 140, 255)),
		"shot1 retains its original WAD RGB instead of white-alpha replacement",
	)
	_check(bool(decals[0].source_rgb), "decal trace records source RGB preservation")
	var decal_families := {
		"shot1": {"family": "shot", "pixel": Vector2i(8, 8)},
		"blood1": {"family": "blood", "pixel": Vector2i(8, 8)},
		"scorch1": {"family": "scorch", "pixel": Vector2i(8, 8)},
	}
	var expected_modulation := Color.WHITE
	if RenderingServer.get_current_rendering_method() == "mobile" and not root.use_hdr_2d:
		expected_modulation = Color(2.0, 2.0, 2.0).linear_to_srgb()
	for decal_name: String in decal_families:
		var family: Dictionary = decal_families[decal_name]
		var node := manager.spawn_decal(
			decal_name,
			Vector3.ZERO,
			Vector3.BACK,
			str(family.family),
		)
		_check(is_instance_valid(node), "%s decal has a renderable source texture" % family.family)
		if is_instance_valid(node):
			var family_material := (
				((node as MeshInstance3D).mesh as QuadMesh).material
				as StandardMaterial3D
			)
			_check(
				family_material.blend_mode == BaseMaterial3D.BLEND_MODE_MUL
				and family_material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				and family_material.albedo_color == expected_modulation,
				"%s decal keeps source RGB and unshaded multiplicative material" % family.family,
			)
			var family_image := (family_material.albedo_texture as Texture2D).get_image()
			_check(
				_has_authored_decal_pixel(family_image),
				"%s probe samples authored non-white source pixels" % family.family,
			)

	var first_decal: Node3D = manager._decal_nodes[0]
	for index in range(CombatEffects.MAX_WORLD_DECALS):
		manager.spawn_decal(
			"shot%d" % (index % 5 + 1),
			Vector3(float(index) * 0.001, 0.0, 0.0),
			Vector3.BACK,
			"shot",
			index,
		)
	_check(
		manager._decal_nodes.size() == CombatEffects.MAX_WORLD_DECALS,
		"world decals obey the original mp_decals 300 budget",
	)
	_check(first_decal.is_queued_for_deletion(), "oldest world decal is evicted first")
	manager.queue_free()


func _test_source_spark_contract() -> void:
	var manager := _manager()
	manager._spawn_spark_shower(Vector3.ZERO, Vector3.UP, 2, 19)
	var showers := _events_of_type(manager.event_log, CombatEffects.EVENT_HE_SPARKS)
	var ricochets := _events_of_type(manager.event_log, CombatEffects.EVENT_RICOCHET)
	_check(showers.size() == 1, "spark contract records one TE_SPARKS batch")
	_check(int(showers[0].count) == 2, "spark shower count is retained")
	_check(
		int(showers[0].tracer_count) == 2 * CombatEffects.TE_SPARK_TRACER_COUNT,
		"each TE_SPARKS emits exactly eight gravity tracers",
	)
	_check(int(showers[0].ricochet_count) == 2, "each TE_SPARKS emits one ricochet sprite")
	_check(ricochets.size() == 2, "ricochet sprite events match shower count")
	_check(
		ricochets.all(func(event: Dictionary) -> bool: return str(event.asset) == "richo1"),
		"TE_SPARKS uses the original App 90 richo1 sprite",
	)
	var tracer_count := 0
	for child in manager.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is ImmediateMesh:
			tracer_count += 1
	_check(
		tracer_count == 2 * CombatEffects.TE_SPARK_TRACER_COUNT,
		"spark runtime owns sixteen deterministic tracer nodes",
	)
	manager.queue_free()


func _test_blood_event_tape() -> void:
	var manager := _manager()
	manager.spawn_blood_impact(Vector3.ZERO, Vector3.FORWARD, 9)
	manager.spawn_blood_decal(Vector3.BACK, Vector3.FORWARD, 9)
	var blood := _events_of_type(manager.event_log, CombatEffects.EVENT_BLOOD_SPRITE)
	_check(blood.size() == 2, "player impact emits bloodspray and blood sprites")
	_check(str(blood[0].asset) == "bloodspray", "blood spray names original bloodspray.spr")
	_check(str(blood[1].asset) == "blood", "blood core names original blood.spr")
	_check(
		blood[0].color == CombatEffects.BLOOD_COLOR_RED
		and blood[1].color == CombatEffects.BLOOD_COLOR_RED,
		"TE_BLOODSPRITE assets receive GoldSrc's red blood-color modulation",
	)
	var decals := _events_of_type(manager.event_log, CombatEffects.EVENT_WORLD_DECAL)
	_check(decals.size() == 1 and str(decals[0].family) == "blood", "blood trace leaves a blood decal")
	manager.queue_free()


func _test_he_event_tape() -> void:
	var manager := _manager()
	manager.spawn_he_explosion(Vector3.ZERO, Vector3.UP)
	var fireballs := _events_of_type(manager.event_log, CombatEffects.EVENT_HE_FIREBALL)
	var smoke := _events_of_type(manager.event_log, CombatEffects.EVENT_HE_SMOKE)
	var sparks := _events_of_type(manager.event_log, CombatEffects.EVENT_HE_SPARKS)
	var flicker := _events_of_type(manager.event_log, CombatEffects.EVENT_HE_FLICKER)
	var lights := _events_of_type(manager.event_log, CombatEffects.EVENT_HE_LIGHT)
	var sounds := _events_of_type(manager.event_log, CombatEffects.EVENT_SOUND)
	_check(fireballs.size() == 2, "HE explosion emits the two original fireball temp entities")
	_check(str(fireballs[0].asset) == "fexplo", "HE first fireball uses fexplo.spr")
	_check(is_equal_approx(float(fireballs[0].scale), 1.9), "fexplo sized to a player-height fireball")
	_check(str(fireballs[1].asset) == "eexplo", "HE second fireball uses eexplo.spr")
	_check(is_equal_approx(float(fireballs[1].scale), 2.2), "eexplo sized to a player-height fireball")
	_check(smoke.size() == 1 and str(smoke[0].asset) == "steam1", "HE delayed smoke uses steam1.spr")
	_check(int(smoke[0].orientation) == 4, "HE smoke obeys steam1 orientation 4")
	_check(
		int(smoke[0].start_tick) == CombatEffects.HE_SMOKE_DELAY_TICKS,
		"HE smoke starts at the authoritative 0.55 second boundary",
	)
	_check(sparks.size() == 1, "HE records a deterministic spark-shower event")
	_check(int(sparks[0].count) >= 0 and int(sparks[0].count) <= 3, "HE emits GoldSrc's zero-to-three spark showers")
	_check(sounds.size() == 2, "HE plays explosion and debris sounds")
	_check(str(sounds[0].asset) == "explode3", "HE uses the original explode3 sound")
	_check(str(sounds[1].asset).begins_with("debris"), "HE uses an original debris sound")
	_check(lights.size() == 4, "two independent TE_EXPLOSIONs each own two dynamic lights")
	var dlight_count := 0
	var elight_count := 0
	for light_event: Dictionary in lights:
		if str(light_event.kind) == "dlight":
			dlight_count += 1
		elif str(light_event.kind) == "elight":
			elight_count += 1
	_check(
		dlight_count == 2 and elight_count == 2,
		"each temp entity owns one dlight and one elight",
	)
	_check(flicker.size() == 2, "each TE_EXPLOSION emits a flicker-particle batch")
	var flicker_counts_match := true
	for flicker_event: Dictionary in flicker:
		if int(flicker_event.count) != CombatEffects.TE_EXPLOSION_FLICKER_COUNT:
			flicker_counts_match = false
	_check(
		flicker_counts_match,
		"flicker-particle count is deterministic per temp entity",
	)
	var flicker_timing_matches := true
	for flicker_event: Dictionary in flicker:
		if (
			not bool(flicker_event.time_varying)
			or int(flicker_event.step_ticks)
				!= CombatEffects.TE_EXPLOSION_FLICKER_STEP_TICKS
		):
			flicker_timing_matches = false
	_check(flicker_timing_matches, "flicker trace declares source-tick palette animation")
	var flicker_motion: Dictionary
	for motion: Dictionary in manager._motions:
		if int(motion.get("flicker_seed", -1)) >= 0:
			flicker_motion = motion
			break
	_check(not flicker_motion.is_empty(), "explosion owns live flicker material state")
	var first_fireball_node := manager.get_node("GoldSrcSprite_fexplo") as MeshInstance3D
	var initial_fireball_height := first_fireball_node.global_position.y
	if not flicker_motion.is_empty():
		var flicker_material: StandardMaterial3D = flicker_motion.material
		var color_tick_zero := flicker_material.albedo_color
		manager.advance_tick(CombatEffects.TE_EXPLOSION_FLICKER_STEP_TICKS)
		_check(
			not flicker_material.albedo_color.is_equal_approx(color_tick_zero),
			"flicker brightness, palette, and alpha change on fixed source ticks",
		)
	manager.advance_tick(25 - CombatEffects.TE_EXPLOSION_FLICKER_STEP_TICKS)
	_check(
		is_equal_approx(
			first_fireball_node.global_position.y - initial_fireball_height,
			0.02,
		),
		"TE_EXPLOSION rises at exactly 8 HU/s",
	)
	_check(manager._lights.size() == 4, "source-lifetime lights survive tick 25")
	manager.advance_tick(59)
	_check(manager._lights.size() == 2, "eexplo lights expire with its 84-tick sprite")
	manager.advance_tick(16)
	_check(manager._lights.is_empty(), "fexplo lights expire with its 100-tick sprite")
	manager.queue_free()

	manager = _manager()
	manager.spawn_he_explosion(Vector3.ZERO, Vector3.UP)
	manager.advance_tick(54)
	var steam_node: MeshInstance3D = manager.get_node_or_null("GoldSrcSprite_steam1")
	_check(is_instance_valid(steam_node) and not steam_node.visible, "steam remains hidden through tick 54")
	manager.advance_tick()
	_check(steam_node.visible, "steam becomes visible exactly on tick 55")
	manager.queue_free()


func _run_he_tape(render_delta: float, duration_ticks: int) -> Array[String]:
	var manager := _manager()
	manager.spawn_he_explosion(Vector3.ZERO, Vector3.UP)
	var accumulator := 0.0
	while manager.tick < duration_ticks:
		accumulator += render_delta
		while (
			accumulator + 0.000000001 >= CombatEffects.TICK_SECONDS
			and manager.tick < duration_ticks
		):
			accumulator -= CombatEffects.TICK_SECONDS
			manager.advance_tick()
	var tape: Array[String] = []
	for event in manager.event_log:
		tape.append(
			"%d:%s:%s:%d" % [
				int(event.tick),
				str(event.type),
				str(event.get("asset", "")),
				int(event.get("start_tick", event.tick)),
			]
		)
	manager.queue_free()
	return tape


func _test_render_rate_independence() -> void:
	var tape_30 := _run_he_tape(1.0 / 30.0, 100)
	var tape_144 := _run_he_tape(1.0 / 144.0, 100)
	_check(tape_30 == tape_144, "HE effect-event tape is identical at 30 and 144 render fps")
