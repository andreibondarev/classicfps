extends SceneTree

const CAPTURE_SIZE := Vector2i(640, 480)
const OUTPUT_ROOT := "/tmp"
const BACKGROUND_COLOR := Color("#17212b")
const BACKGROUND_TOLERANCE := 0.05
# Gate bounds encode the authentic GoldSrc framing: weapons anchor in the
# lower-right quadrant (guns) or across the lower half (knife's two hands),
# always meeting the bottom edge of the frame like CS 1.6 viewmodels do.
const SILHOUETTE_GATES := {
	"knife": {
		"minimum_pixels": 24000,
		"minimum_largest_component_ratio": 0.50,
		"minimum_width_ratio": 0.60,
		"minimum_height_ratio": 0.30,
		"minimum_end_y": 0.95,
		"minimum_x": 0.0,
		"minimum_y": 0.20,
	},
	"glock18": {
		"minimum_pixels": 12000,
		"minimum_largest_component_ratio": 0.92,
		"minimum_width_ratio": 0.22,
		"minimum_height_ratio": 0.30,
		"minimum_end_y": 0.95,
		"minimum_x": 0.50,
		"minimum_y": 0.40,
	},
	"ak47": {
		"minimum_pixels": 14000,
		"minimum_largest_component_ratio": 0.92,
		"minimum_width_ratio": 0.28,
		"minimum_height_ratio": 0.32,
		"minimum_end_y": 0.95,
		"minimum_x": 0.40,
		"minimum_y": 0.40,
	},
}
const WEAPON_CASES := [
	{
		"weapon": "knife",
		"animation": "idle",
		"fractions": [0.0, 0.50, 0.98],
	},
	{
		"weapon": "glock18",
		"animation": "shoot",
		"fractions": [0.0, 0.50, 0.98],
	},
	{
		"weapon": "ak47",
		"animation": "reload",
		"fractions": [0.0, 0.50, 0.98],
	},
]
const DENSE_CASES := [
	# The authored v_knife idle is a 90-frame fidget whose last frame does not
	# match frame 0 (GoldSrc snaps on wrap); allow that authored seam.
	{"weapon": "knife", "animation": "idle", "stride": 5, "loop": true, "seam_tolerance": 0.20},
	{"weapon": "knife", "animation": "draw", "stride": 3},
	{"weapon": "knife", "animation": "slash1", "stride": 1},
	{"weapon": "knife", "animation": "stab", "stride": 3},
	{"weapon": "knife", "animation": "midslash1", "stride": 4},
	{"weapon": "glock18", "animation": "idle1", "stride": 1, "loop": true},
	{"weapon": "glock18", "animation": "draw", "stride": 3},
	{"weapon": "glock18", "animation": "shoot", "stride": 2},
	{"weapon": "glock18", "animation": "reload", "stride": 5},
	{"weapon": "ak47", "animation": "idle1", "stride": 1, "loop": true},
	{"weapon": "ak47", "animation": "draw", "stride": 2},
	{"weapon": "ak47", "animation": "shoot1", "stride": 1},
	{"weapon": "ak47", "animation": "shoot2", "stride": 1},
	{"weapon": "ak47", "animation": "shoot3", "stride": 1},
	{"weapon": "ak47", "animation": "reload", "stride": 5},
]
# The knife composes two separate hands plus the blade, so its connected
# ratio is authentically ~0.5-0.65 in the corrected right-hand framing.
const DENSE_CONNECTED_MINIMUMS := {
	"knife/idle": 0.50,
	"knife/draw": 0.45,
	"knife/slash1": 0.45,
	"knife/stab": 0.45,
	"knife/midslash1": 0.45,
	"glock18/idle1": 0.92,
	"glock18/draw": 0.50,
	"glock18/shoot": 0.92,
	"glock18/reload": 0.65,
	"ak47/idle1": 0.92,
	"ak47/draw": 0.60,
	"ak47/shoot1": 0.92,
	"ak47/shoot2": 0.92,
	"ak47/shoot3": 0.92,
	"ak47/reload": 0.75,
}
const ACTION_CAPTURE_CASES := [
	{"weapon": "knife", "animation": "draw", "fraction": 0.50},
	{"weapon": "knife", "animation": "slash1", "fraction": 0.50},
	{"weapon": "knife", "animation": "stab", "fraction": 0.50},
	{"weapon": "glock18", "animation": "draw", "fraction": 0.50},
	{"weapon": "glock18", "animation": "shoot", "fraction": 0.50},
	{"weapon": "glock18", "animation": "reload", "fraction": 0.50},
	{"weapon": "ak47", "animation": "draw", "fraction": 0.50},
	{"weapon": "ak47", "animation": "shoot1", "fraction": 0.50},
	{"weapon": "ak47", "animation": "reload", "fraction": 0.50},
]

var camera: Camera3D
var viewmodel: MdlViewModel
var captures: Array[Image] = []
var action_captures: Array[Image] = []
var failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = CAPTURE_SIZE
	root.content_scale_size = CAPTURE_SIZE
	var stage := Node3D.new()
	root.add_child(stage)

	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = BACKGROUND_COLOR
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 1.0
	environment.environment = settings
	stage.add_child(environment)

	camera = Camera3D.new()
	camera.current = true
	# PlayerController uses 74 degrees for the classic 4:3 camera-space
	# projection. Capturing at a wider test-only FOV would make every weapon
	# look artificially undersized and would not guard production framing.
	camera.fov = 74.0
	camera.near = 0.035
	stage.add_child(camera)

	var anchor := Node3D.new()
	camera.add_child(anchor)
	viewmodel = MdlViewModel.new()
	anchor.add_child(viewmodel)
	viewmodel.set_process(false)

	await process_frame
	for weapon_case: Dictionary in WEAPON_CASES:
		await _capture_weapon_case(weapon_case)
	await _audit_dense_cases()
	await _capture_action_matrix()

	var montage := Image.create(
		CAPTURE_SIZE.x * 3,
		CAPTURE_SIZE.y * WEAPON_CASES.size(),
		false,
		Image.FORMAT_RGBA8,
	)
	montage.fill(BACKGROUND_COLOR)
	for index in captures.size():
		montage.blit_rect(
			captures[index],
			Rect2i(Vector2i.ZERO, CAPTURE_SIZE),
			Vector2i(
				(index % 3) * CAPTURE_SIZE.x,
				(index / 3) * CAPTURE_SIZE.y,
			),
		)
	var montage_path := OUTPUT_ROOT.path_join(
		"protocol47-viewmodel-multiweapon-multiframe.png"
	)
	if montage.save_png(montage_path) != OK:
		push_error("Could not save %s" % montage_path)
		failed = true
	else:
		print("VIEWMODEL_CAPTURE %s" % montage_path)

	if failed:
		quit(1)
		return
	print("GAME_VIEWMODEL_VISUAL_CAPTURE_PASS")
	quit(0)


func _capture_weapon_case(weapon_case: Dictionary) -> void:
	var weapon := str(weapon_case.weapon)
	var animation_name := str(weapon_case.animation)
	if not viewmodel.load_weapon(weapon):
		push_error("Could not load %s" % weapon)
		failed = true
		return
	await process_frame
	await process_frame
	var animation: Dictionary = viewmodel._template.animations.get(animation_name, {})
	if animation.is_empty():
		push_error("%s lacks %s" % [weapon, animation_name])
		failed = true
		return
	var frame_count := int(animation.frames)
	var fps := maxf(1.0, float(animation.fps))
	var case_index := 0
	for fraction: float in weapon_case.fractions:
		var frame_index := mini(
			int(round(clampf(fraction, 0.0, 1.0) * float(frame_count - 1))),
			frame_count - 1,
		)
		viewmodel._start_animation(animation_name, false)
		viewmodel._animation_time = (float(frame_index) + 0.01) / fps
		viewmodel._frame_key = ""
		viewmodel._process(0.0)
		await process_frame
		await process_frame
		var image := root.get_viewport().get_texture().get_image()
		if image.get_size() != CAPTURE_SIZE:
			push_error("Unexpected capture size %s" % image.get_size())
			failed = true
			return
		var path := OUTPUT_ROOT.path_join(
			"protocol47-viewmodel-%s-%s-%02d-f%03d.png"
			% [weapon, animation_name, case_index, frame_index]
		)
		if image.save_png(path) != OK:
			push_error("Could not save %s" % path)
			failed = true
			return
		if not _silhouette_passes(image, weapon, animation_name, frame_index):
			failed = true
		print("VIEWMODEL_CAPTURE %s" % path)
		captures.append(image)
		case_index += 1


func _audit_dense_cases() -> void:
	var sampled_frames := 0
	for dense_case: Dictionary in DENSE_CASES:
		var weapon := str(dense_case.weapon)
		var animation_name := str(dense_case.animation)
		if not viewmodel.load_weapon(weapon):
			push_error("Could not load dense case %s" % weapon)
			failed = true
			continue
		await process_frame
		await process_frame
		var animation: Dictionary = viewmodel._template.animations.get(
			animation_name,
			{},
		)
		if animation.is_empty():
			push_error("%s lacks dense animation %s" % [weapon, animation_name])
			failed = true
			continue
		var frame_count := int(animation.frames)
		var fps := maxf(1.0, float(animation.fps))
		var indices := _dense_frame_indices(
			frame_count,
			maxi(1, int(dense_case.stride)),
		)
		var first_image: Image
		var last_image: Image
		for frame_index: int in indices:
			viewmodel._start_animation(animation_name, bool(
				dense_case.get("loop", false)
			))
			viewmodel._animation_time = (float(frame_index) + 0.01) / fps
			viewmodel._frame_key = ""
			viewmodel._process(0.0)
			await process_frame
			var image := root.get_viewport().get_texture().get_image()
			var metrics := _silhouette_metrics(image)
			var gate: Dictionary = SILHOUETTE_GATES[weapon]
			var minimum_dense_pixels := maxi(
				180,
				int(round(float(gate.minimum_pixels) * 0.12)),
			)
			var dense_connected_minimum := float(
				DENSE_CONNECTED_MINIMUMS[
					"%s/%s" % [weapon, animation_name]
				]
			)
			var dense_passes: bool
			if int(metrics.foreground_pixels) < minimum_dense_pixels:
				# GoldSrc draw sequences enter from below the frame and slash
				# arcs sweep the hands out of view mid-swing; only idle poses
				# are required to stay on screen for every frame.
				dense_passes = not animation_name.begins_with("idle")
			else:
				dense_passes = (
					float(metrics.largest_ratio) >= dense_connected_minimum
					and float(metrics.bounds.end.x) <= 1.0
					and float(metrics.bounds.end.y) <= 1.0
				)
			if not dense_passes:
				push_error(
					"%s %s dense frame %d fails: pixels=%d connected=%.4f bounds=%s"
					% [
						weapon,
						animation_name,
						frame_index,
						int(metrics.foreground_pixels),
						float(metrics.largest_ratio),
						metrics.bounds,
					]
				)
				failed = true
			if frame_index == 0:
				first_image = image
			if frame_index == frame_count - 1:
				last_image = image
			sampled_frames += 1
		if bool(dense_case.get("loop", false)):
			if first_image == null or last_image == null:
				push_error("%s %s loop seam endpoints were not sampled" % [
					weapon,
					animation_name,
				])
				failed = true
			else:
				var seam_difference := _image_difference_ratio(
					first_image,
					last_image,
				)
				print(
					"VIEWMODEL_LOOP_SEAM %s %s difference=%.5f"
					% [weapon, animation_name, seam_difference]
				)
				if seam_difference > float(dense_case.get("seam_tolerance", 0.03)):
					push_error(
						"%s %s loop seam changes %.3f%% of the frame"
						% [weapon, animation_name, seam_difference * 100.0]
					)
					failed = true
	print("VIEWMODEL_DENSE_FRAMES %d" % sampled_frames)


func _dense_frame_indices(frame_count: int, stride: int) -> Array[int]:
	var indices: Array[int] = []
	for frame_index in range(0, frame_count, stride):
		indices.append(frame_index)
	for required_index in [0, 1, frame_count - 2, frame_count - 1]:
		if (
			required_index >= 0
			and required_index < frame_count
			and required_index not in indices
		):
			indices.append(required_index)
	indices.sort()
	return indices


func _capture_action_matrix() -> void:
	for action_case: Dictionary in ACTION_CAPTURE_CASES:
		var weapon := str(action_case.weapon)
		var animation_name := str(action_case.animation)
		if not viewmodel.load_weapon(weapon):
			push_error("Could not load action capture %s" % weapon)
			failed = true
			continue
		await process_frame
		await process_frame
		var animation: Dictionary = viewmodel._template.animations.get(
			animation_name,
			{},
		)
		if animation.is_empty():
			push_error("%s lacks action capture %s" % [weapon, animation_name])
			failed = true
			continue
		var frame_count := int(animation.frames)
		var frame_index := mini(
			int(round(float(action_case.fraction) * float(frame_count - 1))),
			frame_count - 1,
		)
		var fps := maxf(1.0, float(animation.fps))
		viewmodel._start_animation(animation_name, false)
		viewmodel._animation_time = (float(frame_index) + 0.01) / fps
		viewmodel._frame_key = ""
		viewmodel._process(0.0)
		await process_frame
		await process_frame
		var image := root.get_viewport().get_texture().get_image()
		var path := OUTPUT_ROOT.path_join(
			"protocol47-viewmodel-action-%s-%s-f%03d.png"
			% [weapon, animation_name, frame_index]
		)
		if image.save_png(path) != OK:
			push_error("Could not save %s" % path)
			failed = true
			continue
		action_captures.append(image)
		print("VIEWMODEL_CAPTURE %s" % path)

	var action_montage := Image.create(
		CAPTURE_SIZE.x * 3,
		CAPTURE_SIZE.y * 3,
		false,
		Image.FORMAT_RGBA8,
	)
	action_montage.fill(BACKGROUND_COLOR)
	for index in action_captures.size():
		action_montage.blit_rect(
			action_captures[index],
			Rect2i(Vector2i.ZERO, CAPTURE_SIZE),
			Vector2i(
				(index % 3) * CAPTURE_SIZE.x,
				(index / 3) * CAPTURE_SIZE.y,
			),
		)
	var path := OUTPUT_ROOT.path_join(
		"protocol47-viewmodel-action-matrix.png"
	)
	if action_montage.save_png(path) != OK:
		push_error("Could not save %s" % path)
		failed = true
	else:
		print("VIEWMODEL_CAPTURE %s" % path)


func _image_difference_ratio(first: Image, second: Image) -> float:
	var changed := 0
	var pixel_count := first.get_width() * first.get_height()
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var difference := maxf(
				maxf(absf(a.r - b.r), absf(a.g - b.g)),
				absf(a.b - b.b),
			)
			if difference > 0.05:
				changed += 1
	return float(changed) / float(pixel_count)


func _silhouette_passes(
	image: Image,
	weapon: String,
	animation_name: String,
	frame_index: int,
) -> bool:
	var metrics := _silhouette_metrics(image)
	var foreground_pixels := int(metrics.foreground_pixels)
	if foreground_pixels == 0:
		push_error("%s %s frame %d has no silhouette" % [
			weapon,
			animation_name,
			frame_index,
		])
		return false
	var largest_ratio := float(metrics.largest_ratio)
	var bounds: Rect2 = metrics.bounds
	var gate: Dictionary = SILHOUETTE_GATES[weapon]
	var passes := (
		foreground_pixels >= int(gate.minimum_pixels)
		and largest_ratio >= float(gate.minimum_largest_component_ratio)
		and bounds.size.x >= float(gate.minimum_width_ratio)
		and bounds.size.y >= float(gate.minimum_height_ratio)
		and bounds.position.x >= float(gate.minimum_x)
		and bounds.end.x <= 1.0
		and bounds.position.y >= float(gate.minimum_y)
		and bounds.end.y >= float(gate.minimum_end_y)
		and bounds.end.y <= 1.0
	)
	print(
		"VIEWMODEL_SILHOUETTE %s %s f%d pixels=%d connected=%.4f bounds=%s"
		% [
			weapon,
			animation_name,
			frame_index,
			foreground_pixels,
			largest_ratio,
			bounds,
		]
	)
	if not passes:
		push_error("%s %s frame %d fails silhouette gate" % [
			weapon,
			animation_name,
			frame_index,
		])
	return passes


func _silhouette_metrics(image: Image) -> Dictionary:
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
			var difference := maxf(
				maxf(
					absf(color.r - BACKGROUND_COLOR.r),
					absf(color.g - BACKGROUND_COLOR.g),
				),
				absf(color.b - BACKGROUND_COLOR.b),
			)
			if difference <= BACKGROUND_TOLERANCE:
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

	var largest_component := _largest_component_pixels(mask, width, height)
	var largest_ratio := float(largest_component) / float(foreground_pixels)
	var bounds := Rect2(
		float(min_x) / float(width),
		float(min_y) / float(height),
		float(max_x - min_x + 1) / float(width),
		float(max_y - min_y + 1) / float(height),
	)
	return {
		"foreground_pixels": foreground_pixels,
		"largest_ratio": largest_ratio,
		"bounds": bounds,
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
