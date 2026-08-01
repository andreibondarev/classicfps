extends SceneTree

const OUTPUT_ROOT := "/tmp"
const RESOLUTIONS := [
	Vector2i(640, 480),
	Vector2i(1280, 720),
]
# glock18 must precede deagle: granting the Desert Eagle replaces the pistol
# slot, and both pistols are captured for review.
const WEAPONS := ["knife", "glock18", "ak47", "deagle", "hegrenade"]
# Per-review artifact captures written into game/artifacts at 1280x720.
const ARTIFACT_ROOT := "res://artifacts"
const ARTIFACT_RESOLUTION := Vector2i(1280, 720)
const ARTIFACT_WEAPONS := ["ak47", "deagle", "knife", "hegrenade"]
# Framing encodes the corrected GoldSrc anchor: guns occupy the lower-right
# quadrant converging on the crosshair; knife/grenade hands span wider. The
# knife is authentically two disconnected hands, hence its low connected floor.
const FRAMING_GATES := {
	"knife": {
		"minimum_width": 0.45,
		"minimum_height": 0.30,
		"minimum_connected": 0.40,
		"minimum_x": 0.0,
	},
	"glock18": {
		"minimum_width": 0.18,
		"minimum_height": 0.28,
		"minimum_connected": 0.85,
		"minimum_x": 0.50,
	},
	"ak47": {
		"minimum_width": 0.24,
		"minimum_height": 0.30,
		"minimum_connected": 0.85,
		"minimum_x": 0.40,
	},
	"deagle": {
		"minimum_width": 0.14,
		"minimum_height": 0.28,
		"minimum_connected": 0.85,
		"minimum_x": 0.50,
	},
	"hegrenade": {
		"minimum_width": 0.14,
		"minimum_height": 0.30,
		"minimum_connected": 0.60,
		"minimum_x": 0.40,
	},
}

var game: Node
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	game = packed.instantiate()
	root.add_child(game)
	current_scene = game
	for _frame in range(8):
		await process_frame

	game.start_match()
	for _frame in range(8):
		await process_frame
	game._begin_live()
	game.player.controls_enabled = false
	game.hud.visible = true
	game.hud.set_deploy_visible(false)
	game.phase = "live"
	game.seconds_left = 278.0
	game.hud.update_match(
		game.round_number,
		game.phase,
		game.seconds_left,
		game.ct_score,
		game.terrorist_score,
		game.money,
	)
	# Freeze round/HUD clocks so a with/without-viewmodel image pair differs
	# only in the production model composite.
	game.match_started = false
	for bot: Node in game.allied_bots + game.targets:
		bot.visible = false
		bot.process_mode = Node.PROCESS_MODE_DISABLED

	var hud_root := game.hud.get_node("HUDRoot") as Control
	for resolution: Vector2i in RESOLUTIONS:
		root.content_scale_size = resolution
		root.size = resolution
		hud_root.size = Vector2(resolution)
		var captures: Array[Image] = []
		for weapon: String in WEAPONS:
			game.player.grant_item(weapon)
			if game.player.active_weapon != weapon:
				game.player.switch_weapon(weapon)
				await create_timer(0.32).timeout
			game.player.viewmodel.position = game.player.viewmodel.base_position
			game.player.viewmodel.rotation = Vector3.ZERO
			game.player.viewmodel._start_animation(
				game.player.viewmodel._idle_animation(),
				true,
			)
			game.hud.update_health(game.player.health, game.player.armor)
			game.hud.update_ammo(
				game.player.clip,
				game.player.reserve,
				false,
			)
			for _frame in range(4):
				await process_frame
			var image := root.get_viewport().get_texture().get_image()
			if image.get_size() != resolution:
				push_error(
					"%s gameplay capture is %s, expected %s"
					% [weapon, image.get_size(), resolution]
				)
				failed = true
				continue
			var path := OUTPUT_ROOT.path_join(
				"protocol47-viewmodel-gameplay-%dx%d-%s.png"
				% [resolution.x, resolution.y, weapon]
			)
			if image.save_png(path) != OK:
				push_error("Could not save %s" % path)
				failed = true
				continue
			print("VIEWMODEL_GAMEPLAY_CAPTURE %s" % path)
			if resolution == ARTIFACT_RESOLUTION and weapon in ARTIFACT_WEAPONS:
				_save_artifact(image, "protocol47-viewmodel-%s.png" % weapon)
			if resolution == ARTIFACT_RESOLUTION and weapon == "ak47":
				await _capture_pose_artifact(
					"shoot1", 0.25, "protocol47-viewmodel-gameplay.png"
				)
				await _capture_pose_artifact(
					"draw", 0.5, "protocol47-viewmodel-draw.png"
				)
				await _capture_fire_artifact()
			game.player.viewmodel.visible = false
			await process_frame
			var background_image := root.get_viewport().get_texture().get_image()
			game.player.viewmodel.visible = true
			var metrics := _difference_metrics(image, background_image)
			if not _framing_passes(weapon, metrics):
				failed = true
			print(
				"VIEWMODEL_GAMEPLAY_FRAMING %dx%d %s pixels=%d connected=%.4f bounds=%s"
				% [
					resolution.x,
					resolution.y,
					weapon,
					int(metrics.foreground_pixels),
					float(metrics.largest_ratio),
					metrics.bounds,
				]
			)
			captures.append(image)
		await _save_resolution_montage(captures, resolution)

	if failed:
		quit(1)
		return
	print("GAME_VIEWMODEL_GAMEPLAY_CAPTURE_PASS")
	quit(0)


func _capture_pose_artifact(
	animation_name: String,
	fraction: float,
	filename: String,
) -> void:
	## Captures a specific mid-animation pose of the active weapon, then
	## returns the viewmodel to its looping idle.
	var viewmodel: MdlViewModel = game.player.viewmodel
	var animation: Dictionary = viewmodel._template.animations.get(animation_name, {})
	if animation.is_empty():
		push_error("%s lacks pose artifact animation %s" % [
			viewmodel.loaded_weapon,
			animation_name,
		])
		failed = true
		return
	var frame_count := int(animation.frames)
	var fps := maxf(1.0, float(animation.fps))
	var frame_index := mini(
		int(round(fraction * float(frame_count - 1))),
		frame_count - 1,
	)
	viewmodel._start_animation(animation_name, false)
	viewmodel._animation_time = (float(frame_index) + 0.01) / fps
	viewmodel._frame_key = ""
	viewmodel._process(0.0)
	for _frame in range(3):
		await process_frame
	_save_artifact(root.get_viewport().get_texture().get_image(), filename)
	viewmodel._start_animation(viewmodel._idle_animation(), true)
	viewmodel._animation_time = 0.0
	viewmodel._frame_key = ""
	viewmodel._process(0.0)
	for _frame in range(2):
		await process_frame


func _capture_fire_artifact() -> void:
	## Captures the AK mid-shot: recoil pose from the authored shoot sequence
	## plus the GoldSrc muzzle flash sprite at the viewmodel muzzle.
	var viewmodel: MdlViewModel = game.player.viewmodel
	var animation: Dictionary = viewmodel._template.animations.get("shoot1", {})
	if animation.is_empty():
		push_error("%s lacks fire artifact animation" % viewmodel.loaded_weapon)
		failed = true
		return
	var fps := maxf(1.0, float(animation.fps))
	viewmodel._start_animation("shoot1", false)
	viewmodel._animation_time = 1.01 / fps
	viewmodel._frame_key = ""
	viewmodel._process(0.0)
	await process_frame
	var camera: Camera3D = game.player.camera
	var basis := camera.global_transform.basis
	var effects: CS16CombatEffects = game.player.combat_effects
	if not is_instance_valid(effects):
		# The headless harness assigns current_scene after _ready, so the
		# player could not resolve the shared effects node on its own.
		effects = CS16CombatEffects.for_scene(game)
		game.player.combat_effects = effects
	effects.spawn_weapon_shot(
		"ak47",
		0,
		game.player.first_person_shot_effect_origin(),
		-basis.z,
		basis.x,
		basis.y,
	)
	await process_frame
	_save_artifact(
		root.get_viewport().get_texture().get_image(),
		"protocol47-viewmodel-fire.png",
	)
	viewmodel._start_animation(viewmodel._idle_animation(), true)
	viewmodel._animation_time = 0.0
	viewmodel._frame_key = ""
	viewmodel._process(0.0)
	for _frame in range(2):
		await process_frame


func _save_artifact(image: Image, filename: String) -> void:
	var path := ARTIFACT_ROOT.path_join(filename)
	if image.save_png(path) != OK:
		push_error("Could not save %s" % path)
		failed = true
	else:
		print("VIEWMODEL_GAMEPLAY_CAPTURE %s" % path)


func _save_resolution_montage(
	captures: Array[Image],
	resolution: Vector2i,
) -> void:
	var montage := Image.create(
		resolution.x * captures.size(),
		resolution.y,
		false,
		Image.FORMAT_RGBA8,
	)
	montage.fill(Color.BLACK)
	for index in captures.size():
		montage.blit_rect(
			captures[index],
			Rect2i(Vector2i.ZERO, resolution),
			Vector2i(index * resolution.x, 0),
		)
	var path := OUTPUT_ROOT.path_join(
		"protocol47-viewmodel-gameplay-%dx%d-matrix.png"
		% [resolution.x, resolution.y]
	)
	if montage.save_png(path) != OK:
		push_error("Could not save %s" % path)
		failed = true
	else:
		print("VIEWMODEL_GAMEPLAY_CAPTURE %s" % path)


func _framing_passes(weapon: String, metrics: Dictionary) -> bool:
	var gate: Dictionary = FRAMING_GATES[weapon]
	var bounds: Rect2 = metrics.bounds
	var passes := (
		int(metrics.foreground_pixels) >= 700
		and float(metrics.largest_ratio) >= float(gate.minimum_connected)
		and bounds.size.x >= float(gate.minimum_width)
		and bounds.size.y >= float(gate.minimum_height)
		and bounds.position.x >= float(gate.minimum_x)
		and bounds.end.x <= 1.0
		and bounds.position.y >= 0.20
		and bounds.end.y >= 0.94
		and bounds.end.y <= 1.0
	)
	if not passes:
		push_error("%s fails in-game framing contract: %s" % [weapon, metrics])
	return passes


func _difference_metrics(image: Image, background: Image) -> Dictionary:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	var foreground_pixels := 0
	var min_x := width
	var min_y := height
	var max_x := -1
	var max_y := -1
	for y in range(height):
		for x in range(width):
			var color := image.get_pixel(x, y)
			var base := background.get_pixel(x, y)
			var difference := maxf(
				maxf(absf(color.r - base.r), absf(color.g - base.g)),
				absf(color.b - base.b),
			)
			if difference <= 0.05:
				continue
			var pixel_index := y * width + x
			mask[pixel_index] = 1
			foreground_pixels += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if foreground_pixels == 0:
		return {
			"foreground_pixels": 0,
			"largest_ratio": 0.0,
			"bounds": Rect2(),
		}
	var largest := _largest_component_pixels(mask, width, height)
	return {
		"foreground_pixels": foreground_pixels,
		"largest_ratio": float(largest) / float(foreground_pixels),
		"bounds": Rect2(
			float(min_x) / float(width),
			float(min_y) / float(height),
			float(max_x - min_x + 1) / float(width),
			float(max_y - min_y + 1) / float(height),
		),
	}


func _largest_component_pixels(
	mask: PackedByteArray,
	width: int,
	height: int,
) -> int:
	var largest := 0
	var queue := PackedInt32Array()
	for start_index in range(mask.size()):
		if mask[start_index] != 1:
			continue
		mask[start_index] = 2
		queue.clear()
		queue.push_back(start_index)
		var head := 0
		var component_size := 0
		while head < queue.size():
			var pixel_index := queue[head]
			head += 1
			component_size += 1
			var x := pixel_index % width
			var y := int(pixel_index / width)
			for offset_y in range(-1, 2):
				var neighbor_y := y + offset_y
				if neighbor_y < 0 or neighbor_y >= height:
					continue
				for offset_x in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					var neighbor_x := x + offset_x
					if neighbor_x < 0 or neighbor_x >= width:
						continue
					var neighbor_index := neighbor_y * width + neighbor_x
					if mask[neighbor_index] != 1:
						continue
					mask[neighbor_index] = 2
					queue.push_back(neighbor_index)
		largest = maxi(largest, component_size)
	return largest
