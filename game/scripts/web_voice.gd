extends Node

## Browser voice bridge. Capture, Opus coding and playback live in the page's
## voice.js (window.P47Voice); this node moves encoded frames between it and
## NetworkSession, which relays them through the host. Inert off the web or
## when the page lacks the module or WebCodecs.

var session: Node
var _voice: JavaScriptObject
var _frame_callback: JavaScriptObject
var _transmitting := false


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_voice = JavaScriptBridge.get_interface("P47Voice")
	if _voice == null or not bool(_voice.supported()):
		_voice = null
		return
	# The callback must stay referenced for as long as JavaScript may call it.
	_frame_callback = JavaScriptBridge.create_callback(_on_js_frame)
	_voice.setFrameCallback(_frame_callback)


func available() -> bool:
	return _voice != null


func is_transmitting() -> bool:
	return _transmitting


func set_transmitting(on: bool) -> void:
	if _voice == null or on == _transmitting:
		return
	_transmitting = on
	_voice.setTransmitting(on)


func play(sender_id: String, sequence: int, frame: PackedByteArray) -> void:
	if _voice != null:
		_voice.play(sender_id, sequence, Marshalls.raw_to_base64(frame))


## Actor IDs heard within the last moment, for the HUD's talking list.
func talking() -> PackedStringArray:
	if _voice == null:
		return PackedStringArray()
	var text := str(_voice.talking())
	return PackedStringArray() if text.is_empty() else text.split(",")


func set_receive_volume(volume: float) -> void:
	if _voice != null:
		_voice.setReceiveVolume(volume)


func set_transmit_gain(gain: float) -> void:
	if _voice != null:
		_voice.setTransmitGain(gain)


func mic_level() -> float:
	return float(_voice.micLevel()) if _voice != null else 0.0


func open_microphone() -> void:
	if _voice != null:
		_voice.openMicrophone()


func _on_js_frame(args: Array) -> void:
	if not _transmitting or args.is_empty() or not is_instance_valid(session):
		return
	var frame := Marshalls.base64_to_raw(str(args[0]))
	if not frame.is_empty():
		session.submit_voice_frame(frame)
