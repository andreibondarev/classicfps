class_name CS16AudioPlaybackAdapter
extends Node

## Pooled Godot renderer for CS16AudioEventRouter events.
##
## Router origins are expressed in Hammer/GoldSrc units. The project imports
## one HU as 0.01 metres, so this adapter is the single conversion boundary.
## Raw GoldSrc attenuation is rendered with the Quake/GoldSrc-lineage linear
## model: gain = 1 - distance_hu * attenuation / 1000. Godot's own distance
## attenuation is disabled to avoid applying a second, engine-specific curve.
##
## This is an event/level probe implementation, not a PCM-parity claim. Stereo
## panning, PVS/occlusion, mixer quantization, duplicate-start phase offsets,
## and device resampling still require a real GoldSrc reference capture.

const AudioEventRouter := preload("res://scripts/cs16_audio_event_router.gd")

const HU_PER_METER := 100.0
const METERS_PER_HU := 1.0 / HU_PER_METER
const NOMINAL_CLIP_DISTANCE_HU := 1000.0
const SILENCE_DB := -80.0

var playback_enabled := true
var listener_origin_hu := Vector3.ZERO

var _router: CS16AudioEventRouter
var _active: Dictionary = {}
var _free_2d: Array[AudioStreamPlayer] = []
var _free_3d: Array[AudioStreamPlayer3D] = []
var _trace: Array[Dictionary] = []
var _next_pool_slot := 1


func _exit_tree() -> void:
	# A streamed announcer can still be active when a match scene is replaced.
	# Release its AudioStreamPlayback and stream references before Godot tears
	# down the pooled player nodes; otherwise scene changes retain the sample
	# until process exit.
	stop_all("adapter_exit_tree")
	if is_instance_valid(_router):
		if _router.event_started.is_connected(_on_event_started):
			_router.event_started.disconnect(_on_event_started)
		if _router.event_stopped.is_connected(_on_event_stopped):
			_router.event_stopped.disconnect(_on_event_stopped)
	_router = null


static func hu_to_meters(position_hu: Vector3) -> Vector3:
	return position_hu * METERS_PER_HU


static func meters_to_hu(position_meters: Vector3) -> Vector3:
	return position_meters * HU_PER_METER


static func attenuation_gain(distance_hu: float, attenuation: float) -> float:
	if attenuation <= AudioEventRouter.ATTN_NONE:
		return 1.0
	return clampf(
		1.0 - maxf(0.0, distance_hu) * attenuation / NOMINAL_CLIP_DISTANCE_HU,
		0.0,
		1.0,
	)


static func attenuation_probe(
	attenuation: float,
	distances_hu: Array[float],
) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for distance_hu: float in distances_hu:
		output.append({
			"distance_hu": distance_hu,
			"distance_meters": distance_hu * METERS_PER_HU,
			"attenuation": attenuation,
			"gain": attenuation_gain(distance_hu, attenuation),
		})
	return output


func bind_router(router: CS16AudioEventRouter) -> void:
	if is_instance_valid(_router):
		if _router.event_started.is_connected(_on_event_started):
			_router.event_started.disconnect(_on_event_started)
		if _router.event_stopped.is_connected(_on_event_stopped):
			_router.event_stopped.disconnect(_on_event_stopped)
	stop_all("adapter_rebind")
	_router = router
	if not is_instance_valid(_router):
		return
	_router.event_started.connect(_on_event_started)
	_router.event_stopped.connect(_on_event_stopped)


func unbind_router() -> void:
	bind_router(null)


func set_listener_origin_hu(origin_hu: Vector3) -> void:
	listener_origin_hu = origin_hu
	var voice_ids: Array = _active.keys()
	voice_ids.sort()
	for voice_id: Variant in voice_ids:
		_refresh_voice_gain(int(voice_id))


func stop_all(reason := "adapter_stop") -> void:
	var voice_ids: Array = _active.keys()
	voice_ids.sort()
	for voice_id: Variant in voice_ids:
		_release_voice(int(voice_id), reason, -1)


func clear_trace() -> void:
	_trace.clear()


func clear_pool() -> void:
	stop_all("pool_clear")
	for player: AudioStreamPlayer in _free_2d:
		player.free()
	for player: AudioStreamPlayer3D in _free_3d:
		player.free()
	_free_2d.clear()
	_free_3d.clear()
	_next_pool_slot = 1


func active_playback_count() -> int:
	return _active.size()


func active_playbacks() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var voice_ids: Array = _active.keys()
	voice_ids.sort()
	for voice_id: Variant in voice_ids:
		var state: Dictionary = _active[voice_id]
		output.append(_public_state(state))
	return output


func pool_counts() -> Dictionary:
	var active_2d := 0
	var active_3d := 0
	for voice_id: Variant in _active:
		var state: Dictionary = _active[voice_id]
		if str(state.player_kind) == "2d":
			active_2d += 1
		else:
			active_3d += 1
	return {
		"active_2d": active_2d,
		"active_3d": active_3d,
		"free_2d": _free_2d.size(),
		"free_3d": _free_3d.size(),
	}


func trace() -> Array[Dictionary]:
	return _trace.duplicate(true)


func trace_json() -> String:
	return JSON.stringify(_trace)


func _on_event_started(event: Dictionary) -> void:
	var attenuation := float(event.attenuation)
	var player: Node = (
		_acquire_2d()
		if attenuation <= AudioEventRouter.ATTN_NONE
		else _acquire_3d()
	)
	var sample_path := AudioEventRouter.SOUND_ROOT.path_join(str(event.sample))
	var stream := load(sample_path) as AudioStream
	var origin_values: Array = event.origin
	var origin_hu := Vector3(
		float(origin_values[0]),
		float(origin_values[1]),
		float(origin_values[2]),
	)
	var state := {
		"voice_id": int(event.voice_id),
		"event_name": str(event.event_name),
		"tick": int(event.tick),
		"entity_id": int(event.entity_id),
		"channel": int(event.channel),
		"sample": str(event.sample),
		"sample_sha256": str(event.sample_sha256),
		"volume": float(event.volume),
		"attenuation": attenuation,
		"pitch": int(event.pitch),
		"origin_hu": origin_hu,
		"origin_meters": hu_to_meters(origin_hu),
		"gain": 1.0,
		"volume_db": 0.0,
		"player_kind": "2d" if player is AudioStreamPlayer else "3d",
		"pool_slot": int(player.get_meta("pool_slot")),
		"player": player,
	}
	_active[int(event.voice_id)] = state
	if player is AudioStreamPlayer:
		var player_2d := player as AudioStreamPlayer
		player_2d.stream = stream
		player_2d.pitch_scale = float(event.pitch) / float(AudioEventRouter.PITCH_NORM)
	else:
		var player_3d := player as AudioStreamPlayer3D
		player_3d.stream = stream
		player_3d.pitch_scale = float(event.pitch) / float(AudioEventRouter.PITCH_NORM)
		player_3d.position = hu_to_meters(origin_hu)
		player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_refresh_voice_gain(int(event.voice_id))
	state = _active[int(event.voice_id)]
	if playback_enabled:
		if player is AudioStreamPlayer:
			(player as AudioStreamPlayer).play()
		else:
			(player as AudioStreamPlayer3D).play()
	var trace_event := {
		"kind": "start",
		"tick": int(event.tick),
		"voice_id": int(event.voice_id),
		"entity_id": int(event.entity_id),
		"channel": int(event.channel),
		"sample": str(event.sample),
		"sample_sha256": str(event.sample_sha256),
		"player_kind": str(state.player_kind),
		"pool_slot": int(state.pool_slot),
		"origin_hu": _vector_values(state.origin_hu),
		"origin_meters": _vector_values(state.origin_meters),
		"listener_hu": _vector_values(listener_origin_hu),
		"distance_hu": float(state.distance_hu),
		"attenuation": float(state.attenuation),
		"gain": float(state.gain),
		"source_volume": float(state.volume),
		"volume_db": float(state.volume_db),
		"pitch": int(state.pitch),
	}
	_trace.append(trace_event)


func _on_event_stopped(event: Dictionary) -> void:
	_release_voice(
		int(event.voice_id),
		str(event.reason),
		int(event.replaced_by),
		int(event.tick),
	)


func _refresh_voice_gain(voice_id: int) -> void:
	if not _active.has(voice_id):
		return
	var state: Dictionary = _active[voice_id]
	var origin_hu: Vector3 = state.origin_hu
	var distance_hu := listener_origin_hu.distance_to(origin_hu)
	var gain := attenuation_gain(distance_hu, float(state.attenuation))
	var output_gain := float(state.volume) * gain
	var volume_db := SILENCE_DB if output_gain <= 0.0 else linear_to_db(output_gain)
	state.distance_hu = distance_hu
	state.gain = gain
	state.volume_db = volume_db
	var player: Node = state.player
	if player is AudioStreamPlayer:
		(player as AudioStreamPlayer).volume_db = volume_db
	else:
		(player as AudioStreamPlayer3D).volume_db = volume_db
	_active[voice_id] = state


func _release_voice(
	voice_id: int,
	reason: String,
	replaced_by := -1,
	tick := -1,
) -> void:
	if not _active.has(voice_id):
		return
	var state: Dictionary = _active[voice_id]
	_active.erase(voice_id)
	var player: Node = state.player
	if player is AudioStreamPlayer:
		var player_2d := player as AudioStreamPlayer
		player_2d.stop()
		player_2d.stream = null
		player_2d.pitch_scale = 1.0
		player_2d.volume_db = 0.0
		_free_2d.append(player_2d)
	else:
		var player_3d := player as AudioStreamPlayer3D
		player_3d.stop()
		player_3d.stream = null
		player_3d.pitch_scale = 1.0
		player_3d.volume_db = 0.0
		player_3d.position = Vector3.ZERO
		_free_3d.append(player_3d)
	_trace.append({
		"kind": "stop",
		"tick": tick if tick >= 0 else int(state.tick),
		"voice_id": voice_id,
		"entity_id": int(state.entity_id),
		"channel": int(state.channel),
		"player_kind": str(state.player_kind),
		"pool_slot": int(state.pool_slot),
		"reason": reason,
		"replaced_by": replaced_by,
	})


func _acquire_2d() -> AudioStreamPlayer:
	if not _free_2d.is_empty():
		return _free_2d.pop_back()
	var player := AudioStreamPlayer.new()
	player.name = "GoldSrc2D_%d" % _next_pool_slot
	player.set_meta("pool_slot", _next_pool_slot)
	_next_pool_slot += 1
	add_child(player)
	return player


func _acquire_3d() -> AudioStreamPlayer3D:
	if not _free_3d.is_empty():
		return _free_3d.pop_back()
	var player := AudioStreamPlayer3D.new()
	player.name = "GoldSrc3D_%d" % _next_pool_slot
	player.set_meta("pool_slot", _next_pool_slot)
	_next_pool_slot += 1
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	add_child(player)
	return player


func _public_state(state: Dictionary) -> Dictionary:
	return {
		"voice_id": int(state.voice_id),
		"event_name": str(state.event_name),
		"entity_id": int(state.entity_id),
		"channel": int(state.channel),
		"sample": str(state.sample),
		"sample_sha256": str(state.sample_sha256),
		"player_kind": str(state.player_kind),
		"pool_slot": int(state.pool_slot),
		"origin_hu": _vector_values(state.origin_hu),
		"origin_meters": _vector_values(state.origin_meters),
		"listener_hu": _vector_values(listener_origin_hu),
		"distance_hu": float(state.distance_hu),
		"attenuation": float(state.attenuation),
		"gain": float(state.gain),
		"source_volume": float(state.volume),
		"volume_db": float(state.volume_db),
		"pitch": int(state.pitch),
	}


func _vector_values(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]
