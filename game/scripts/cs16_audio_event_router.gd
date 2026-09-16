class_name CS16AudioEventRouter
extends Node

## Deterministic GoldSrc-style audio event plane.
##
## This node owns the authoritative 100 Hz event trace and entity/channel voice
## lifecycle. It deliberately does not guess a Godot attenuation curve.
## Rendering code can subscribe to event_started/event_stopped and translate
## the preserved source descriptor after that curve is calibrated.

signal event_started(event: Dictionary)
signal event_stopped(event: Dictionary)
signal router_error(message: String)

const AudioCatalog := preload("res://scripts/cs16_audio_catalog.gd")

const TICK_RATE_HZ := 100
const SOUND_ROOT := "res://assets/sounds/classic/"
const NODE_NAME := "CS16AudioEventRouter"

# Valve common/const.h channel values.
const CHAN_AUTO := 0
const CHAN_WEAPON := 1
const CHAN_VOICE := 2
const CHAN_ITEM := 3
const CHAN_BODY := 4
const CHAN_STREAM := 5
const CHAN_STATIC := 6

# Valve common/const.h attenuation, pitch, volume, and sound flags.
const ATTN_NONE := 0.0
const ATTN_NORM := 0.8
const ATTN_STATIC := 1.25
const ATTN_IDLE := 2.0
const PITCH_NORM := 100
const PITCH_LOW := 95
const PITCH_HIGH := 120
const VOL_NORM := 1.0
const HU_PER_METER := 100.0
const SND_STOP := 1 << 5
const SND_CHANGE_VOL := 1 << 6
const SND_CHANGE_PITCH := 1 << 7
const SND_SPAWNING := 1 << 8

var current_tick := 0
var deterministic_seed := 0xC516
var last_error := ""

var _next_voice_id := 1
var _tick_accumulator := 0.0
var _rng := RandomNumberGenerator.new()
var _voices: Dictionary = {}
var _active_by_channel: Dictionary = {}
var _trace := preload("res://scripts/bounded_event_log.gd").new()
var _sample_hashes: Dictionary = {}


static func for_scene(scene: Node) -> CS16AudioEventRouter:
	if not is_instance_valid(scene):
		return null
	var router := scene.get_node_or_null(NODE_NAME)
	return router as CS16AudioEventRouter if router is CS16AudioEventRouter else null


static func meters_to_hu(position_meters: Vector3) -> Vector3:
	return position_meters * HU_PER_METER


func _ready() -> void:
	_rng.seed = deterministic_seed


func _process(delta: float) -> void:
	_tick_accumulator += delta * float(TICK_RATE_HZ)
	var elapsed_ticks := int(floor(_tick_accumulator))
	if elapsed_ticks <= 0:
		return
	_tick_accumulator -= float(elapsed_ticks)
	advance_ticks(elapsed_ticks)


func reset(seed := 0xC516) -> void:
	# Notify a bound playback adapter before discarding authoritative voices.
	# Reset events themselves are intentionally excluded from the new trace.
	stop_all("router_reset")
	_voices.clear()
	_active_by_channel.clear()
	_trace.clear()
	_sample_hashes.clear()
	current_tick = 0
	_next_voice_id = 1
	_tick_accumulator = 0.0
	deterministic_seed = seed
	_rng.seed = seed
	last_error = ""


func emit_catalog_event(
	event_name: String,
	entity_id: int,
	channel: int,
	origin := Vector3.ZERO,
	overrides := {},
) -> int:
	var samples: Array = AudioCatalog.EVENT_SAMPLES.get(event_name, [])
	if samples.is_empty():
		return _fail("Unknown or empty catalog audio event: %s" % event_name)
	var descriptor := {
		"samples": samples.duplicate(),
		"channel": channel,
		"volume": VOL_NORM,
		"attenuation": ATTN_NORM,
		"pitch_min": PITCH_NORM,
		"pitch_max": PITCH_NORM,
		"flags": 0,
	}
	for key: Variant in overrides:
		descriptor[key] = overrides[key]
	return emit_descriptor(event_name, entity_id, descriptor, origin)


func emit_descriptor(
	event_name: String,
	entity_id: int,
	descriptor: Dictionary,
	origin := Vector3.ZERO,
) -> int:
	if entity_id < 0:
		return _fail("%s has invalid entity id %d" % [event_name, entity_id])
	var validation_error := _validate_descriptor(event_name, descriptor)
	if not validation_error.is_empty():
		return _fail(validation_error)

	var samples: Array = descriptor.samples
	var variant_index := int(descriptor.get("variant_index", -1))
	if variant_index < 0:
		variant_index = _rng.randi_range(0, samples.size() - 1)
	else:
		variant_index = posmod(variant_index, samples.size())
	var relative_sample := str(samples[variant_index])
	var sample_path := _sample_path(relative_sample)
	# Exported PCKs retain imported AudioStreams behind resource remaps, not the
	# original WAV as a directly openable file. FileAccess therefore reports a
	# false negative in release builds even though load() can resolve the sample.
	if not ResourceLoader.exists(sample_path):
		return _fail("Missing classic audio sample: %s" % sample_path)

	var pitch_min := int(descriptor.get("pitch_min", PITCH_NORM))
	var pitch_max := int(descriptor.get("pitch_max", pitch_min))
	var pitch := _rng.randi_range(pitch_min, pitch_max)
	var duration_seconds := float(descriptor.get("duration_seconds", -1.0))
	if duration_seconds < 0.0:
		var stream := load(sample_path) as AudioStream
		if stream == null:
			return _fail("Classic audio sample could not be loaded: %s" % sample_path)
		duration_seconds = stream.get_length()
	var duration_ticks := maxi(
		1,
		int(ceil(duration_seconds * float(TICK_RATE_HZ) * float(PITCH_NORM) / float(pitch))),
	)

	var voice_id := _next_voice_id
	_next_voice_id += 1
	var channel := int(descriptor.channel)
	var channel_key := _channel_key(entity_id, channel)
	if channel != CHAN_AUTO and _active_by_channel.has(channel_key):
		_stop_voice_internal(
			int(_active_by_channel[channel_key]),
			"replaced",
			voice_id,
		)

	var origin_values := [origin.x, origin.y, origin.z]
	var voice := {
		"voice_id": voice_id,
		"event_name": event_name,
		"entity_id": entity_id,
		"channel": channel,
		"sample": relative_sample,
		"sample_path": sample_path,
		"sample_sha256": _sample_sha256(sample_path),
		"variant_index": variant_index,
		"volume": float(descriptor.get("volume", VOL_NORM)),
		"attenuation": float(descriptor.get("attenuation", ATTN_NORM)),
		"pitch": pitch,
		"pitch_scale": float(pitch) / float(PITCH_NORM),
		"flags": int(descriptor.get("flags", 0)),
		"origin": origin_values,
		"started_tick": current_tick,
		"duration_ticks": duration_ticks,
		"expected_end_tick": current_tick + duration_ticks,
	}
	_voices[voice_id] = voice
	if channel != CHAN_AUTO:
		_active_by_channel[channel_key] = voice_id
	var trace_event := _start_trace_event(voice)
	_trace.append(trace_event)
	event_started.emit(trace_event.duplicate(true))
	return voice_id


func stop_channel(entity_id: int, channel: int, reason := "stopped") -> bool:
	if channel == CHAN_AUTO:
		return false
	var channel_key := _channel_key(entity_id, channel)
	if not _active_by_channel.has(channel_key):
		return false
	_stop_voice_internal(int(_active_by_channel[channel_key]), reason)
	return true


func stop_voice(voice_id: int, reason := "stopped") -> bool:
	if not _voices.has(voice_id):
		return false
	_stop_voice_internal(voice_id, reason)
	return true


func stop_all(reason := "stopped") -> void:
	var voice_ids: Array = _voices.keys()
	voice_ids.sort()
	for voice_id: Variant in voice_ids:
		_stop_voice_internal(int(voice_id), reason)


func advance_ticks(tick_count: int) -> void:
	if tick_count <= 0:
		return
	for ignored_tick in range(tick_count):
		current_tick += 1
		var expired_ids: Array[int] = []
		for voice_id: Variant in _voices:
			var voice: Dictionary = _voices[voice_id]
			if current_tick >= int(voice.expected_end_tick):
				expired_ids.append(int(voice_id))
		expired_ids.sort()
		for voice_id: int in expired_ids:
			_stop_voice_internal(voice_id, "finished")


func active_voice_count() -> int:
	return _voices.size()


func active_voices() -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var voice_ids: Array = _voices.keys()
	voice_ids.sort()
	for voice_id: Variant in voice_ids:
		output.append((_voices[voice_id] as Dictionary).duplicate(true))
	return output


func trace() -> Array[Dictionary]:
	return _trace.snapshot()


func trace_json() -> String:
	return JSON.stringify(trace())


func _validate_descriptor(event_name: String, descriptor: Dictionary) -> String:
	if event_name.is_empty():
		return "Audio event name cannot be empty"
	var samples: Array = descriptor.get("samples", [])
	if samples.is_empty():
		return "%s has no samples" % event_name
	for sample: Variant in samples:
		var relative_sample := str(sample).replace("\\", "/")
		var classic_relative := relative_sample.trim_prefix(SOUND_ROOT)
		if (
			relative_sample.is_empty()
			or (
				relative_sample.begins_with("res://")
				and not relative_sample.begins_with(SOUND_ROOT)
			)
			or relative_sample.begins_with("/")
			or classic_relative.split("/").has("..")
		):
			return "%s has non-classic sample path %s" % [event_name, relative_sample]
	var channel := int(descriptor.get("channel", -1))
	if channel < CHAN_AUTO or channel > CHAN_STATIC:
		return "%s has invalid GoldSrc channel %d" % [event_name, channel]
	var volume := float(descriptor.get("volume", VOL_NORM))
	if volume < 0.0 or volume > VOL_NORM:
		return "%s has volume %.3f outside 0..1" % [event_name, volume]
	var attenuation := float(descriptor.get("attenuation", ATTN_NORM))
	if attenuation < ATTN_NONE:
		return "%s has negative attenuation %.3f" % [event_name, attenuation]
	var pitch_min := int(descriptor.get("pitch_min", PITCH_NORM))
	var pitch_max := int(descriptor.get("pitch_max", pitch_min))
	if pitch_min < 1 or pitch_max > 255 or pitch_max < pitch_min:
		return "%s has invalid pitch range %d..%d" % [event_name, pitch_min, pitch_max]
	var duration_seconds := float(descriptor.get("duration_seconds", 0.0))
	if descriptor.has("duration_seconds") and duration_seconds <= 0.0:
		return "%s has non-positive duration" % event_name
	return ""


func _stop_voice_internal(
	voice_id: int,
	reason: String,
	replaced_by := -1,
) -> void:
	if not _voices.has(voice_id):
		return
	var voice: Dictionary = _voices[voice_id]
	_voices.erase(voice_id)
	var channel := int(voice.channel)
	if channel != CHAN_AUTO:
		var channel_key := _channel_key(int(voice.entity_id), channel)
		if int(_active_by_channel.get(channel_key, -1)) == voice_id:
			_active_by_channel.erase(channel_key)
	var trace_event := {
		"kind": "stop",
		"tick": current_tick,
		"voice_id": voice_id,
		"event_name": str(voice.event_name),
		"entity_id": int(voice.entity_id),
		"channel": channel,
		"reason": reason,
		"replaced_by": replaced_by,
	}
	_trace.append(trace_event)
	event_stopped.emit(trace_event.duplicate(true))


func _start_trace_event(voice: Dictionary) -> Dictionary:
	return {
		"kind": "start",
		"tick": current_tick,
		"voice_id": int(voice.voice_id),
		"event_name": str(voice.event_name),
		"entity_id": int(voice.entity_id),
		"channel": int(voice.channel),
		"sample": str(voice.sample),
		"sample_sha256": str(voice.sample_sha256),
		"variant_index": int(voice.variant_index),
		"volume": float(voice.volume),
		"attenuation": float(voice.attenuation),
		"pitch": int(voice.pitch),
		"flags": int(voice.flags),
		"origin": voice.origin.duplicate(),
		"duration_ticks": int(voice.duration_ticks),
		"expected_end_tick": int(voice.expected_end_tick),
	}


func _channel_key(entity_id: int, channel: int) -> String:
	return "%d:%d" % [entity_id, channel]


func _sample_path(relative_sample: String) -> String:
	if relative_sample.begins_with(SOUND_ROOT):
		return relative_sample
	return SOUND_ROOT.path_join(relative_sample.trim_prefix("/"))


func _sample_sha256(path: String) -> String:
	if _sample_hashes.has(path):
		return str(_sample_hashes[path])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	var hash_value := context.finish().hex_encode()
	_sample_hashes[path] = hash_value
	return hash_value


func _fail(message: String) -> int:
	last_error = message
	router_error.emit(message)
	return -1
