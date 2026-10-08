extends SceneTree

## Offline promotional capture, not a real-time performance benchmark.
## Uses the existing automated human intent with ordinary bot match rules.
const MatchDriver = preload("res://tests/live_match_driver.gd")
const FPS := 30

class RecordingDriver extends MatchDriver:
	func gather_command(delta: float) -> Dictionary:
		var command := super.gather_command(delta)
		# Ordinary reload input between engagements; no animation/weapon override.
		if not command.fire and actor.clip > 0 and actor.clip < 20:
			command.reload = true
		return command

func _initialize() -> void:
	_run.call_deferred()

func _mark(event: String, detail: Variant = null) -> void:
	print("SOCIAL_CAPTURE ", JSON.stringify({"seconds": float(Engine.get_process_frames()) / FPS,
		"event": event, "detail": detail}))

func _run() -> void:
	if Engine.get_write_movie_path().is_empty() or DisplayServer.get_name() == "headless":
		push_error("Use rendered --write-movie with --fixed-fps 30 for this capture")
		quit(1)
		return
	seed(47)
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	if not game.combat_effects.presentation_is_ready:
		await game.combat_effects.presentation_ready
	# Leave headroom for overlapping shots in the recorded mix only.
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), -8.0)
	var driver := RecordingDriver.new()
	driver.game = game
	game.player.add_child(driver)
	game.player.combat_controller.queue_free()
	driver.possess(game.player)
	game.player.combat_controller = driver
	if not driver.prepare_navigation():
		push_error("Capture navigation could not be prepared")
		quit(1)
		return
	game.start_match()
	game.set_process_unhandled_input(false)
	game.player.set_process_input(false)
	game.spectator_camera.set_process_unhandled_input(false)
	root.gui_disable_input = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	game.player.grant_item("ak47")
	game.player.grant_item("ammo_762nato", 3)
	game.player.switch_weapon("ak47")
	game._begin_live()
	game.player.ammo_changed.connect(func(clip: int, reserve: int, reloading: bool) -> void:
		_mark("ammo", [clip, reserve, reloading]))
	game.player.hit_confirmed.connect(func(headshot: bool) -> void: _mark("hit", headshot))
	game.player.died.connect(func() -> void: _mark("death"))
	_mark("gameplay_start")
	for frame in 50 * FPS:
		await process_frame
	_mark("gameplay_end")
	game.audio_router.stop_all("capture_end")
	game.audio_playback.clear_pool()
	game.queue_free()
	await process_frame
	await process_frame
	CS16CombatEffects.release_cached_resources()
	MdlCharacterModel.release_cached_resources()
	print("SOCIAL_CAPTURE_PASS")
	quit(0)
