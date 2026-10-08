extends SceneTree

## Negative control for periodic native rendering stalls, not a gameplay gate.
## No logging, sorting, file access, or game callbacks inside the measured loop.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var duration_seconds := 95
	var report_path := "/tmp/protocol47-render-baseline.json"
	var vsync_enabled := false
	var vsync_seen := false
	var instrumented := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			duration_seconds = argument.trim_prefix("--seconds=").to_int()
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")
		elif argument.begins_with("--vsync="):
			var value := argument.trim_prefix("--vsync=")
			if vsync_seen or value not in ["enabled", "disabled"]:
				push_error("Use one --vsync=enabled or --vsync=disabled")
				quit(1)
				return
			vsync_seen = true
			vsync_enabled = value == "enabled"
		elif argument == "--instrumented":
			instrumented = true
		else:
			push_error("Unknown render baseline argument: " + argument)
			quit(1)
			return
	if duration_seconds < 60 or duration_seconds > 180 or DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() != "Dummy":
		push_error("Render baseline requires native rendering, Dummy audio, and 60–180 seconds")
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position.z = 4.0
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.65, 0.8)
	mesh.material_override = material
	scene.add_child(mesh)
	# Finish startup/shader work before collecting intervals.
	for index in 120:
		await process_frame
	var samples := PackedFloat64Array()
	var slow_frames: Array[Dictionary] = []
	var draws_before := Engine.get_frames_drawn()
	# A profiler can attach after startup without launching through Instruments.
	# Emit this before starting either measurement clock, never in the live loop.
	print("RENDER_BASELINE_READY pid=", OS.get_process_id())
	var started := Time.get_ticks_usec()
	var previous := started
	var started_unix := Time.get_unix_time_from_system()
	while previous - started < duration_seconds * 1000000:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - previous) / 1000.0
		previous = now
		samples.append(ms)
		mesh.rotation.y = float(now - started) / 1000000.0
		if ms > 25.0:
			slow_frames.append({"elapsed_seconds": float(now - started) / 1000000.0, "ms": ms})
	var rendered_frames := Engine.get_frames_drawn() - draws_before
	samples.sort()
	var report := {
		"scenario": "standalone_render_environment_control", "game_loaded": false,
		"instrumented": instrumented,
		"audio_driver": AudioServer.get_driver_name(), "engine": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"vsync_requested": "enabled" if vsync_enabled else "disabled",
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
		"device": RenderingServer.get_video_adapter_name(), "viewport": [root.size.x, root.size.y],
		"started_unix": started_unix, "duration_seconds": float(previous - started) / 1000000.0,
		"frames": samples.size(), "rendered_frames": rendered_frames,
		"median_ms": samples[samples.size() / 2], "p95_ms": samples[int(samples.size() * 0.95)],
		"p99_ms": samples[int(samples.size() * 0.99)], "max_ms": samples[-1],
		"frames_over_25ms": slow_frames.size(), "slow_frames": slow_frames,
	}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write render baseline report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if rendered_frames < samples.size() * 0.98:
		push_error("Render baseline lost draw coverage; report is not valid timing evidence")
		quit(1)
		return
	print("RENDER_BASELINE_COLLECTED ", report_path)
	quit()
