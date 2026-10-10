extends Node

## Browser builds opened with ?perf print the frame rate to the developer
## console once a second. Everywhere else this node removes itself.

const NetworkSessionScript := preload("res://scripts/network_session.gd")
const CharacterModelScript := preload("res://scripts/mdl_character_model.gd")

var _elapsed := 0.0


func _ready() -> void:
	if NetworkSessionScript.web_page_query("perf") == null:
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 1.0:
		return
	_elapsed = 0.0
	# Character templates built during the last second and their cost.
	var templates := CharacterModelScript.template_build_count
	var template_ms := CharacterModelScript.template_build_usec / 1000.0
	CharacterModelScript.template_build_count = 0
	CharacterModelScript.template_build_usec = 0
	print("PROTOCOL47_PERF fps=%d frame_ms=%.1f draw_calls=%d templates=%d template_ms=%.0f skinning=%s" % [
		Engine.get_frames_per_second(), 1000.0 / maxf(1.0, Engine.get_frames_per_second()),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		templates, template_ms, "gpu" if CharacterModelScript.gpu_skinning else "cpu",
	])
