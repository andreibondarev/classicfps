extends SceneTree

const WEAPONS := [
	"p228",
	"glock18",
	"scout",
	"hegrenade",
	"xm1014",
	"c4",
	"mac10",
	"aug",
	"smokegrenade",
	"elite",
	"fiveseven",
	"ump45",
	"sg550",
	"galil",
	"famas",
	"usp",
	"awp",
	"mp5",
	"m249",
	"m3",
	"m4a1",
	"tmp",
	"g3sg1",
	"flashbang",
	"deagle",
	"sg552",
	"ak47",
	"p90",
	"knife",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _load_manifest(path: String) -> Dictionary:
	_check(FileAccess.file_exists(path), "%s exists" % path)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "%s opens" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary, "%s contains valid JSON" % path)
	return parsed as Dictionary if parsed is Dictionary else {}


func _validate_model(weapon: String, family: String) -> void:
	var root := "res://generated/%s/%s" % [family, weapon]
	var manifest := _load_manifest("%s/model.json" % root)
	if manifest.is_empty():
		return
	_check(manifest.get("format") == "protocol47-mdl", "%s uses the MDL format" % root)
	# The animated exporter emits version 5 (16-bit rigid bone tapes) for every
	# animated model.json; versions 2-3 baked per-vertex frames and version 4
	# stored float matrices; no generated asset ships those anymore (assets and
	# converter are re-synced together).
	var expected_version := 5
	_check(
		int(manifest.get("version", 0)) == expected_version,
		"%s uses supported version %d" % [root, expected_version],
	)
	_check(manifest.get("frame_format") == "rigid_bones_q16", "%s stores q16 rigid bone tapes" % root)
	var bone_count := int(manifest.get("bone_count", 0))
	_check(bone_count > 0, "%s declares its bone count" % root)
	var vertex_bones: Array = manifest.get("vertex_bones", [])
	var skin_path := "%s/%s" % [root, str(manifest.get("skin_file", ""))]
	_check(FileAccess.file_exists(skin_path), "%s rigid skin exists" % skin_path)
	var positions: Array = manifest.get("positions", [])
	var groups: Array = manifest.get("groups", [])
	var sequences: Array = manifest.get("sequences", [])
	var animations: Array = manifest.get("animations", [])
	_check(not positions.is_empty(), "%s contains geometry" % root)
	_check(not groups.is_empty(), "%s contains render groups" % root)
	_check(not sequences.is_empty(), "%s contains named sequences" % root)
	_check(not animations.is_empty(), "%s contains animation sequences" % root)
	_check(vertex_bones.size() * 3 == positions.size(), "%s assigns every vertex a bone" % root)
	if FileAccess.file_exists(skin_path):
		var skin_file := FileAccess.open(skin_path, FileAccess.READ)
		_check(
			skin_file != null and skin_file.get_length() == positions.size() * 4,
			"%s stores one local position per vertex" % skin_path,
		)
	for group_variant: Variant in groups:
		_check(group_variant is Dictionary, "%s group metadata is valid" % root)
		if not group_variant is Dictionary:
			continue
		var group := group_variant as Dictionary
		var texture_path := "%s/%s" % [root, str(group.get("texture", ""))]
		_check(FileAccess.file_exists(texture_path), "%s texture exists" % texture_path)
	for animation_variant: Variant in animations:
		_check(animation_variant is Dictionary, "%s animation metadata is valid" % root)
		if not animation_variant is Dictionary:
			continue
		var animation := animation_variant as Dictionary
		var animation_path := "%s/%s" % [root, str(animation.get("file", ""))]
		_check(FileAccess.file_exists(animation_path), "%s animation exists" % animation_path)
		var frame_count := int(animation.get("frames", 0))
		var blend_count := int(animation.get("blends", 1))
		_check(float(animation.get("fps", 0.0)) > 0.0, "%s animation FPS is positive" % root)
		_check(frame_count > 0, "%s animation frame count is positive" % root)
		_check(blend_count > 0, "%s animation blend count is positive" % root)
		if FileAccess.file_exists(animation_path):
			var animation_file := FileAccess.open(animation_path, FileAccess.READ)
			_check(animation_file != null, "%s animation opens" % animation_path)
			if animation_file != null:
				var expected_bytes := bone_count * 7 * frame_count * blend_count * 2
				_check(
					animation_file.get_length() == expected_bytes,
					"%s stores every frame and authored blend (%d bytes)"
					% [animation_path, expected_bytes],
				)
		if family == "player_weapons":
			_validate_player_animation(weapon, root, sequences, animation)


func _validate_player_animation(
	weapon: String,
	root: String,
	sequences: Array,
	animation: Dictionary,
) -> void:
	var name := str(animation.get("name", ""))
	var source_label := str(animation.get("source_label", ""))
	_check(not source_label.is_empty(), "%s %s exposes its source label" % [root, name])
	_check(source_label in sequences, "%s %s source label exists in MDL table" % [root, name])
	_check(
		int(animation.get("sequence_index", -1)) >= 0,
		"%s %s exposes its source sequence index" % [root, name],
	)
	_check(animation.has("looping"), "%s %s exposes its looping flag" % [root, name])
	for field: String in ["blend_type", "blend_start", "blend_end"]:
		var values: Variant = animation.get(field, [])
		_check(
			values is Array and (values as Array).size() == 2,
			"%s %s exposes two-value %s metadata" % [root, name, field],
		)
	var blend_count := int(animation.get("blends", 0))
	if blend_count > 1:
		var blend_type: Array = animation.get("blend_type", [])
		var blend_start: Array = animation.get("blend_start", [])
		var blend_end: Array = animation.get("blend_end", [])
		_check(
			blend_count == 9
			and blend_type.size() == 2
			and int(blend_type[0]) == 8
			and blend_start.size() == 2
			and is_equal_approx(float(blend_start[0]), -90.0)
			and blend_end.size() == 2
			and is_equal_approx(float(blend_end[0]), 90.0),
			"%s %s preserves the authored nine-way STUDIO_XR -90..90 blend"
			% [root, name],
		)
	var activity_prefix: String = str({
		"shoot": "ref_shoot_",
		"crouchshoot": "crouch_shoot_",
		"reload": "ref_reload_",
		"crouchreload": "crouch_reload_",
	}.get(name, ""))
	if not activity_prefix.is_empty():
		_check(
			source_label == "%s%s" % [activity_prefix, _player_activity_family(weapon)],
			"%s %s uses the %s player activity family"
			% [root, name, _player_activity_family(weapon)],
		)


func _player_activity_family(weapon: String) -> String:
	# The AK is baked on the carbine family on purpose: the stock
	# ref_aim_ak47/ref_shoot_ak47 tapes pose the torso off the gait facing
	# (Bip01 Spine yaw -61 degrees versus -12 for ref_aim_carbine, at every one
	# of the nine STUDIO_XR pitch blends), so the rifle reads as carried across
	# the hips instead of shouldered. Mirrors WEAPON_FAMILIES in
	# game/scripts/mdl_character_model.gd and attached_weapon_family in
	# crate/src/mdl.rs; all three must agree or the gun leaves the hands.
	if weapon in ["ak47", "aug", "famas", "galil", "m4a1", "sg552"]:
		return "carbine"
	if weapon in ["awp", "g3sg1", "scout", "sg550"]:
		return "rifle"
	if weapon in ["deagle", "fiveseven", "glock18", "p228", "usp"]:
		return "onehanded"
	if weapon == "elite":
		return "dualpistols"
	if weapon in ["mac10", "mp5", "p90", "tmp", "ump45"]:
		return "mp5"
	if weapon in ["m3", "xm1014"]:
		return "shotgun"
	if weapon == "m249":
		return "m249"
	if weapon in ["flashbang", "hegrenade", "smokegrenade"]:
		return "grenade"
	return weapon


func _run() -> void:
	for weapon: String in WEAPONS:
		_validate_model(weapon, "weapons")
		_validate_model(weapon, "player_weapons")

	if not _failures.is_empty():
		for failure: String in _failures:
			push_error(failure)
		print("GAME_WEAPON_ASSET_COVERAGE_TEST_FAIL (%d)" % _failures.size())
		quit(1)
		return

	print(
		"GAME_WEAPON_ASSET_COVERAGE_TEST_PASS (%d viewmodels, %d player models)"
		% [WEAPONS.size(), WEAPONS.size()]
	)
	quit()
