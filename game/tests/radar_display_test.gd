extends SceneTree

const RadarScript := preload("res://scripts/cs16_radar_display.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("RADAR DISPLAY: %s" % message)


func _run() -> void:
	var radar: CS16RadarDisplay = RadarScript.new()
	root.add_child(radar)
	await process_frame
	radar.set_snapshot(Vector3.ZERO, 0.0, [])
	_check(
		radar.contact_screen_position(Vector3(0.0, 0.0, -1.0)).y < 64.0,
		"zero-yaw forward contact projects toward radar top",
	)
	_check(
		radar.contact_screen_position(Vector3(1.0, 0.0, 0.0)).x > 64.0,
		"zero-yaw right contact projects toward radar right",
	)
	radar.set_snapshot(Vector3.ZERO, PI * 0.5, [])
	_check(
		radar.contact_screen_position(Vector3(-1.0, 0.0, 0.0)).y < 64.0,
		"yaw rotation keeps camera-forward contact at radar top",
	)
	var clipped := radar.contact_screen_position(Vector3(1000.0, 0.0, 0.0))
	_check(
		absf(clipped.distance_to(Vector2(64.0, 64.0)) - 58.0) < 0.01,
		"distant contacts clamp to source radar circle",
	)
	radar.set_snapshot(Vector3.ZERO, 0.0, [{
		"id": "ally",
		"position": Vector3(1.0, 1.0, -1.0),
		"alive": true,
	}])
	_check(radar.contacts.size() == 1, "live tactical snapshot is retained")

	radar.free()
	if _failed:
		quit(1)
	else:
		print("RADAR_DISPLAY_TEST_PASS")
		quit(0)
