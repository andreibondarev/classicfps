extends SceneTree

const RESOLUTIONS := [
	Vector2i(640, 480),
	Vector2i(1024, 768),
	Vector2i(1280, 720),
]
const SCOREBOARD_PLAYERS := [
	{"name": "SpawN", "team": 2, "score": 12, "deaths": 5, "latency": 24, "alive": true, "vip": true},
	{"name": "HeatoN", "team": 2, "score": 9, "deaths": 6, "latency": 31, "alive": false},
	{"name": "Potti", "team": 2, "score": 8, "deaths": 7, "latency": 29, "alive": true},
	{"name": "fisker", "team": 1, "score": 11, "deaths": 7, "latency": 36, "alive": true, "bomb": true},
	{"name": "ahl", "team": 1, "score": 7, "deaths": 9, "latency": 42, "alive": false},
	{"name": "HLTV Proxy", "team": 0, "score": 0, "deaths": 0, "latency": 8, "alive": true},
]
const CAPTURE_STATES := [
	"team",
	"team_briefing_end",
	"class_t",
	"class_ct",
	"buy",
	"buy_t_pistols",
	"buy_t_shotguns",
	"buy_t_smg",
	"buy_t_rifles",
	"buy_t_machineguns",
	"buy_t_equipment",
	"buy_t_pistols_unaffordable",
	"buy_ct_pistols",
	"buy_ct_shotguns",
	"buy_ct_smg",
	"buy_ct_rifles",
	"buy_ct_machineguns",
	"buy_ct_equipment",
	"scoreboard",
	"scoreboard_1",
	"scoreboard_10",
	"scoreboard_20",
	"scoreboard_32",
	"scoreboard_voice",
	"escape",
	"options_multiplayer",
	"options_keyboard",
	"options_mouse",
	"options_audio",
	"options_video",
	"options_voice",
	"accessibility",
]
const RESIDUAL_CAPTURE_STATES := [
	"team",
	"team_briefing_end",
	"buy_t_pistols_unaffordable",
	"scoreboard_1",
	"scoreboard_10",
	"scoreboard_20",
	"scoreboard_32",
	"scoreboard_voice",
	"options_keyboard",
	"options_mouse",
	"options_voice",
]

var hud: GameHUD
var hud_root: Control
var output_root := ""


func _initialize() -> void:
	call_deferred("_run")


func _make_backdrop() -> Control:
	var backdrop := Control.new()
	backdrop.name = "CaptureBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Menus in CS 1.6 overlay the live textured map. Reuse the freshly captured
	# HUD-FREE in-game frame (produced by game:capture just before this harness
	# runs) as the backdrop so every menu screenshot sits over real dust2
	# texturing. The frame must not carry a baked HUD: this harness renders its
	# own live HUD, and a second baked copy double-exposes digits under menus.
	var frame_path := ProjectSettings.globalize_path(
		"res://artifacts/protocol47-menu-backdrop-1280x720.png"
	)
	var frame_image := Image.load_from_file(frame_path)
	if frame_image == null or frame_image.is_empty():
		push_warning("HUD-free menu backdrop missing; run game:capture first")
	if frame_image != null and not frame_image.is_empty():
		var scene_rect := TextureRect.new()
		scene_rect.name = "CapturedMapFrame"
		scene_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scene_rect.texture = ImageTexture.create_from_image(frame_image)
		scene_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scene_rect.stretch_mode = TextureRect.STRETCH_SCALE
		backdrop.add_child(scene_rect)
		return backdrop
	var sky := ColorRect.new()
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.color = Color("#7f98a0")
	backdrop.add_child(sky)
	var wall_left := ColorRect.new()
	wall_left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	wall_left.position = Vector2(0, -340)
	wall_left.size = Vector2(360, 340)
	wall_left.color = Color("#8a714a")
	backdrop.add_child(wall_left)
	var wall_right := ColorRect.new()
	wall_right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	wall_right.position = Vector2(-420, -390)
	wall_right.size = Vector2(420, 390)
	wall_right.color = Color("#66543b")
	backdrop.add_child(wall_right)
	var ground := ColorRect.new()
	ground.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	ground.offset_top = -150
	ground.offset_bottom = 0
	ground.color = Color("#b49c6c")
	backdrop.add_child(ground)
	return backdrop


func _configure_state(state: String) -> void:
	hud.set_deploy_visible(false)
	hud.set_buy_menu_visible(false)
	hud.set_scoreboard_visible(false)
	hud.set_paused_visible(false)
	match state:
		"team":
			hud.set_deploy_visible(true)
			hud.show_team_menu()
		"team_briefing_end":
			hud.set_deploy_visible(true)
			hud.show_team_menu()
			hud.team_briefing_scroll.set_deferred("scroll_vertical", 10000)
		"class_t":
			hud.set_deploy_visible(true)
			hud.show_class_menu(1)
		"class_ct":
			hud.set_deploy_visible(true)
			hud.show_class_menu(2)
		"scoreboard":
			hud.show_scoreboard(
				SCOREBOARD_PLAYERS,
				"Counter-Strike 1.6",
				"de_dust2",
				5,
				4,
			)
		"scoreboard_reference":
			var players := _scoreboard_fixture(16)
			players.append({"id": "observer", "name": "Observer", "team": 0, "score": 0, "deaths": 0, "latency": 12})
			hud.show_scoreboard(players, "Protocol 47 | Dust2", "de_dust2", 2, 5)
		"scoreboard_1":
			hud.show_scoreboard(_scoreboard_fixture(1), "Counter-Strike 1.6", "de_dust2", 1, 0)
		"scoreboard_10":
			hud.show_scoreboard(_scoreboard_fixture(10), "Counter-Strike 1.6", "de_dust2", 5, 4)
		"scoreboard_20":
			hud.show_scoreboard(_scoreboard_fixture(20), "Counter-Strike 1.6", "de_dust2", 8, 9)
		"scoreboard_32":
			var players: Array = []
			for index in range(14):
				players.append({
					"name": "CT %02d" % (index + 1),
					"team": 2,
					"score": 20 - index,
					"deaths": index,
					"latency": 18 + index,
					"alive": index % 4 != 0,
					"vip": index == 1,
				})
				players.append({
					"name": "T %02d" % (index + 1),
					"team": 1,
					"score": 19 - index,
					"deaths": index + 1,
					"latency": 24 + index,
					"alive": index % 3 != 0,
					"bomb": index == 2,
				})
			for index in range(4):
				players.append({"name": "HLTV %d" % (index + 1), "team": 0, "latency": 8 + index})
			hud.show_scoreboard(players, "Counter-Strike 1.6", "de_dust2", 12, 11)
		"scoreboard_voice":
			hud.show_scoreboard(_scoreboard_fixture(10, true), "Counter-Strike 1.6", "de_dust2", 5, 4)
		"buy":
			hud.show_buy_menu(2, 10000)
		"escape":
			hud.set_paused_visible(true)
		"accessibility":
			hud.set_paused_visible(true)
			hud._show_pause_options()
			hud._show_accessibility()
		_:
			if state.begins_with("buy_"):
				var team_token := state.trim_prefix("buy_").get_slice("_", 0)
				var team_id := 1 if team_token == "t" else 2
				var category := state.trim_prefix("buy_%s_" % team_token)
				var money := 600 if category.ends_with("_unaffordable") else 10000
				category = category.trim_suffix("_unaffordable")
				hud.show_buy_menu(team_id, money)
				hud._show_buy_category(category)
			elif state.begins_with("options_"):
				hud.set_paused_visible(true)
				hud._show_pause_options()
				hud._show_options_tab(state.trim_prefix("options_"))


func _scoreboard_fixture(count: int, voice_states := false) -> Array:
	var players: Array = []
	for index in count:
		var team_id := 2 if index % 2 == 0 else 1
		players.append({
			"id": index + 1,
			"name": "Player %02d" % (index + 1),
			"team": team_id,
			"score": count - index,
			"deaths": index / 2,
			"latency": 18 + index,
			"alive": index % 4 != 0,
			"voice_active": voice_states and index % 3 == 0,
			"voice_muted": voice_states and index % 3 == 1,
			"vip": team_id == 2 and index == 2,
			"bomb": team_id == 1 and index == 3,
			"health": 100 - index * 2,
			"money": 16000 - index * 200,
			"show_private_stats": team_id == 1,
			"is_local": index == 1,
		})
	return players


func _capture(state: String, resolution: Vector2i) -> bool:
	root.content_scale_size = resolution
	root.size = resolution
	hud.layout_for_viewport(Vector2(resolution))
	_configure_state(state)
	for frame in range(4):
		await process_frame
	RenderingServer.force_draw()
	var image := root.get_viewport().get_texture().get_image()
	if image.get_size() != resolution:
		push_error(
			"Classic UI capture is %s, expected %s for %s"
			% [image.get_size(), resolution, state]
		)
		return false
	var path := output_root.path_join(
		"protocol47-ui-%s-%dx%d.png"
		% [state, resolution.x, resolution.y]
	)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return false
	print("CLASSIC_UI_CAPTURE %s" % path)
	return true


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var stage := Control.new()
	stage.name = "ClassicUICapture"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(stage)
	current_scene = stage
	stage.add_child(_make_backdrop())
	hud = GameHUD.new()
	stage.add_child(hud)
	hud_root = hud.get_node("HUDRoot") as Control
	hud.update_health(100, 100)
	hud.update_ammo(30, 90, false)
	hud.update_match(6, "live", 84.0, 5, 4, 3350)
	hud.update_objective("")
	# Populate the radar with a plausible squad snapshot so any state that
	# keeps the gameplay HUD visible (scoreboard) shows live blips.
	var radar_contacts: Array[Dictionary] = [
		{"id": "SpawN", "position": Vector3(4.0, 0.0, -6.0), "alive": true},
		{"id": "HeatoN", "position": Vector3(-5.0, 1.4, -3.0), "alive": true},
		{"id": "Potti", "position": Vector3(2.5, -1.6, 5.0), "alive": true},
	]
	hud.update_tactical_display(Vector3.ZERO, 0.0, radar_contacts, [])
	output_root = ProjectSettings.globalize_path("res://artifacts")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_root = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_root)
	var passed := true
	var capture_resolutions := RESOLUTIONS
	var capture_states := CAPTURE_STATES
	if "--residual" in OS.get_cmdline_user_args():
		capture_states = RESIDUAL_CAPTURE_STATES
	if "--scoreboard-only" in OS.get_cmdline_user_args():
		capture_states = ["scoreboard_reference", "scoreboard_32"]
	for resolution in capture_resolutions:
		for state in capture_states:
			passed = await _capture(state, resolution) and passed
	stage.queue_free()
	await process_frame
	await process_frame
	if passed:
		print("CLASSIC_UI_FLOW_CAPTURE_PASS")
		quit(0)
	else:
		quit(1)
