extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _set_lift(node: Node, amount: float) -> void:
	if node is BspMap:
		node.shadow_lift = amount
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			var material := node.get_active_material(surface) as ShaderMaterial
			if material != null and material.shader.code.contains("uniform float shadow_lift"):
				material.set_shader_parameter("shadow_lift", amount)
	for child in node.get_children():
		_set_lift(child, amount)

func _run() -> void:
	for value in [0.0, 0.1, 0.28, 0.4, 0.55]:
		var input := Color(value, value, value, 1.0)
		var result := BspMap.lift_shadow_tint(input, BspMap.DUST2_SHADOW_LIFT)
		_check(result.r > input.r and result.r <= input.r + 0.140001, "dark tones receive a bounded lift")
	for value in [0.65, 0.8, 1.0]:
		var input := Color(value, value, value, 1.0)
		_check(BspMap.lift_shadow_tint(input, 0.14) == input, "bright tones unchanged")
	var previous := -1.0
	for step in range(101):
		var value := float(step) / 100.0
		var result := BspMap.lift_shadow_tint(Color(value, value, value, 1), 0.14)
		_check(result.r >= previous, "shadow curve preserves gradient ordering")
		_check(BspMap.lift_shadow_tint(result, 0.0) == result, "other maps unchanged")
		previous = result.r
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	await process_frame
	_check(is_equal_approx(game.imported_map.shadow_lift, 0.14), "Dust2 enables shadow lift")
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.player.viewmodel._start_animation(game.player.viewmodel._idle_animation(), true)
	game.player.viewmodel._process(0.0)
	game.player.viewmodel.set_process(false)
	for bot in game._all_bots():
		bot.process_mode = Node.PROCESS_MODE_DISABLED
		bot.hide()
	var shaded_actor = game._all_bots()[0]
	shaded_actor.global_position = Vector3(2.56, -1.28, -24.64)
	game.imported_map.shadow_lift = 0.0
	shaded_actor.character_model._update_environment_tint()
	var original_tint: Color = shaded_actor.character_model._environment_tint
	game.imported_map.shadow_lift = BspMap.DUST2_SHADOW_LIFT
	shaded_actor.character_model._update_environment_tint()
	_check(shaded_actor.character_model._environment_tint.r > original_tint.r, "player models receive the Dust2 shadow lift")
	if OS.get_cmdline_user_args().has("--capture"):
		_check(DisplayServer.get_name() != "headless", "capture requires GPU rendering")
		root.size = Vector2i(1280, 720)
		game.hud.hide()
		game.player.weapon_anchor.show()
		game.player.camera.make_current()
		var views := [
			["ct-spawn", Vector3(2.56, -1.28, -24.64), Vector3(3.2, -0.75, -20)],
			["upper-tunnel", Vector3(-19.84, 0.32, -12.0), Vector3(-15.0, 0.85, -12.0)],
			["lower-tunnel", Vector3(-9.36, -1.28, -15.32), Vector3(-9.36, -0.75, -11.0)],
			["sunlight", game.player_spawn, game.player_spawn + Vector3(0, 0.53, -5)],
		]
		for view in views:
			game.player.global_position = view[1]
			game.player.camera.look_at(view[2])
			var before: Image
			for amount in [0.0, BspMap.DUST2_SHADOW_LIFT]:
				_set_lift(game.imported_map, amount)
				game.player.viewmodel._light_snap = true
				game.player.viewmodel._update_light_tint()
				for frame in range(4):
					await process_frame
				RenderingServer.force_draw()
				var capture := root.get_texture().get_image()
				if amount == 0.0:
					before = capture
				else:
					var lighter := 0
					var bright_unchanged := 0
					for y in range(0, 400, 4):
						for x in range(0, 1280, 4):
							var old := before.get_pixel(x, y)
							var updated := capture.get_pixel(x, y)
							if updated.r > old.r + 0.01: lighter += 1
							if old.r > 0.55 and old.is_equal_approx(updated): bright_unchanged += 1
					_check(lighter > 50, "shadow detail lifted in " + str(view[0]))
					if view[0] == "sunlight":
						_check(bright_unchanged > 100, "sunlit pixels remain unchanged")
				var path := "/tmp/protocol47-%s-%s.png" % [view[0], "before" if amount == 0.0 else "after"]
				_check(capture.save_png(path) == OK, "saved " + path)
	game.queue_free()
	await process_frame
	if failures.is_empty(): print("GAME_DUST2_SHADOW_LIGHTING_PASS")
	quit(0 if failures.is_empty() else 1)
