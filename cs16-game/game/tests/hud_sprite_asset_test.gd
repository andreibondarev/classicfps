extends SceneTree

const EXPECTED_SOURCE_HUD_SHA256 := "0c85c594323d9a19cbb53907fe0a6f6aab3070583dc9e99cd64ae343a095141e"
const REQUIRED_CORE := [
	"number_0", "number_1", "number_2", "number_3", "number_4",
	"number_5", "number_6", "number_7", "number_8", "number_9",
	"divider", "cross", "dollar", "stopwatch", "suit_full", "radar", "defuser", "c4",
]
const CAPTURE_RESOLUTIONS := [
	Vector2i(640, 480),
	Vector2i(1024, 768),
	Vector2i(1280, 720),
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _sha256(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	return context.finish().hex_encode()


func _visual_bounds(control: Control) -> Rect2:
	var bounds := Rect2()
	var found := false
	var pending: Array[Node] = [control]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			pending.append(child)
		if not node is Control or not (node as Control).visible:
			continue
		var visual := false
		if node is TextureRect:
			visual = (node as TextureRect).texture != null
		elif node is ColorRect:
			visual = (node as ColorRect).color.a > 0.0
		if not visual:
			continue
		var rect := (node as Control).get_global_rect()
		bounds = bounds.merge(rect) if found else rect
		found = true
	return bounds


func _run() -> void:
	var manifest_path := ProjectSettings.globalize_path("res://assets/hud/classic/manifest.json")
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	_check(manifest_file != null, "classic HUD manifest exists")
	if manifest_file == null:
		_finish()
		return
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text())
	_check(manifest.get("format", "") == "protocol47-cs16-hud", "manifest format is canonical")
	_check(int(manifest.get("resolution", 0)) == 640, "manifest selects the original 640 HUD atlas")
	_check(
		str(manifest.get("source_hud_sha256", "")) == EXPECTED_SOURCE_HUD_SHA256,
		"manifest pins the validated App 90 hud.txt hash",
	)
	var repo_root := ProjectSettings.globalize_path("res://").path_join("../..").simplify_path()
	var source_root := repo_root.path_join("cs16-demo-player/public/sprites/classic")
	_check(
		_sha256(source_root.path_join("hud.txt")) == EXPECTED_SOURCE_HUD_SHA256,
		"staged hud.txt matches the manifest hash",
	)
	var sprites: Dictionary = manifest.get("sprites", {})
	_check(sprites.size() == 37, "manifest contains all 37 core HUD masks")
	for sprite_name in REQUIRED_CORE:
		_check(sprites.has(sprite_name), "manifest contains %s" % sprite_name)
	var verified_sheets := {}
	for sprite_variant in sprites:
		var sprite_name := str(sprite_variant)
		var metadata: Dictionary = sprites[sprite_name]
		var png_path := manifest_path.get_base_dir().path_join(str(metadata.file))
		var image := Image.load_from_file(png_path)
		_check(not image.is_empty(), "%s mask loads" % sprite_name)
		_check(
			image.get_width() == int(metadata.width)
			and image.get_height() == int(metadata.height),
			"%s mask dimensions match its atlas region" % sprite_name,
		)
		var opaque_pixels := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.0:
					opaque_pixels += 1
		_check(opaque_pixels > 0, "%s atlas region contains visible geometry" % sprite_name)
		var sheet := str(metadata.sheet)
		if verified_sheets.has(sheet):
			continue
		verified_sheets[sheet] = true
		_check(
			_sha256(source_root.path_join(sheet)) == str(metadata.source_sha256),
			"%s source sheet matches the validated App 90 hash" % sheet,
		)

	var hud := GameHUD.new()
	root.add_child(hud)
	await process_frame
	hud.set_deploy_visible(false)
	hud.update_health(100, 100)
	hud.update_ammo(30, 90, false)
	hud.update_match(1, "live", 84.0, 0, 0, 800)
	var hud_root := hud.get_node("HUDRoot") as Control
	for resolution in CAPTURE_RESOLUTIONS:
		root.size = resolution
		hud_root.size = Vector2(resolution)
		await process_frame
		await process_frame
		var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
		var regions := [
			_visual_bounds(hud_root.get_node("ClassicRadar")),
			_visual_bounds(hud_root.get_node("ClassicMoney")),
			_visual_bounds(hud_root.get_node("ClassicVitals")),
			_visual_bounds(hud_root.get_node("ClassicTimer")),
			_visual_bounds(hud_root.get_node("ClassicAmmo")),
		]
		for region in regions:
			_check(
				viewport_rect.encloses(region),
				"%s HUD region remains inside %s" % [region, resolution],
			)
		for first in range(regions.size()):
			for second in range(first + 1, regions.size()):
				_check(
					not regions[first].intersects(regions[second]),
					"core HUD regions %d/%d do not overlap at %s" % [first, second, resolution],
				)
	for row in [
		hud.health_digits,
		hud.armor_digits,
		hud.ammo_digits,
		hud.reserve_digits,
		hud.timer_digits,
		hud.money_digits,
	]:
		_check(bool(row.get_meta("uses_original_digits", false)), "numeric row uses original masks")
		for child in row.get_children():
			if child is TextureRect:
				_check(
					str(child.get_meta("classic_sprite", "")).begins_with("number_"),
					"numeric texture is an original number atlas region",
				)

	hud.free()
	_finish()


func _finish() -> void:
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("HUD_SPRITE_ASSET_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return
	print("HUD_SPRITE_ASSET_TEST_PASS")
	quit(0)
