class_name CS16RadarDisplay
extends Control

## GameHUD owns the classic green radar disc; this control draws live contacts
## clamped to its rim. The panel is player-centric: its center means "you".

const SOURCE_SIZE := Vector2(128.0, 128.0)
const CENTER := Vector2(64.0, 64.0)
const CLIP_RADIUS := 58.0
const RADAR_RANGE_HU := 2048.0
const GOLDSRC_UNIT := 0.01
# Classic radar blips are white; the bomb blinks red and hostages read as
# smaller pale dots. No project-invented palette.
const TEAMMATE_COLOR := Color(0.92, 0.92, 0.92, 0.95)
const BOMB_COLOR := Color(1.0, 0.15, 0.10, 0.98)
const HOSTAGE_COLOR := Color(0.98, 0.95, 0.80, 0.95)
const BOMB_BLINK_PERIOD := 0.5

var observer_position := Vector3.ZERO
var observer_yaw := 0.0
var contacts: Array[Dictionary] = []
var _has_blinking_contact := false


static func bomb_contact(team: String, alive: bool, state: String, position: Vector3) -> Array[Dictionary]:
	# Original client radar: loose/planted C4 is Terrorist-only information.
	if team != "T" or not alive or state not in ["dropped", "planted"]:
		return []
	return [{"id": "bomb", "kind": "bomb", "state": state, "position": position, "alive": true}]


func _ready() -> void:
	custom_minimum_size = SOURCE_SIZE
	size = SOURCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)


func _process(_delta: float) -> void:
	# Only the blinking bomb blip needs continuous redraws.
	queue_redraw()


func set_snapshot(
	position: Vector3,
	yaw_radians: float,
	new_contacts: Array[Dictionary],
) -> void:
	observer_position = position
	observer_yaw = yaw_radians
	contacts = new_contacts.duplicate(true)
	_has_blinking_contact = false
	for contact: Dictionary in contacts:
		if str(contact.get("kind", "teammate")) == "bomb":
			_has_blinking_contact = true
			break
	set_process(_has_blinking_contact)
	queue_redraw()


func contact_screen_position(world_position: Vector3) -> Vector2:
	var delta := world_position - observer_position
	var cosine := cos(observer_yaw)
	var sine := sin(observer_yaw)
	# A zero-yaw Godot camera faces -Z. Rotate into that view basis so forward
	# always remains the top of the player-centric classic radar.
	var local_right := delta.x * cosine - delta.z * sine
	var local_back := delta.x * sine + delta.z * cosine
	var pixels_per_meter := CLIP_RADIUS / (RADAR_RANGE_HU * GOLDSRC_UNIT)
	var offset := Vector2(local_right, local_back) * pixels_per_meter
	# Distant contacts pin to the rim of the classic green disc.
	if offset.length() > CLIP_RADIUS:
		offset = offset.normalized() * CLIP_RADIUS
	return CENTER + offset


func _draw() -> void:
	# No self-marker: the classic green disc is player-centric, its cross
	# lines meet where "you" are.
	for contact: Dictionary in contacts:
		if not bool(contact.get("alive", true)):
			continue
		var kind := str(contact.get("kind", "teammate"))
		if kind == "bomb":
			# Dropped/planted bomb blips blink red at a half-second beat.
			var phase := fmod(
				float(Time.get_ticks_msec()) / 1000.0, BOMB_BLINK_PERIOD * 2.0
			)
			if phase >= BOMB_BLINK_PERIOD:
				continue
		var world_position: Vector3 = contact.get("position", Vector3.ZERO)
		var point := contact_screen_position(world_position)
		var height_hu := (
			(world_position.y - observer_position.y) / GOLDSRC_UNIT
		)
		var color := TEAMMATE_COLOR
		match kind:
			"bomb":
				color = BOMB_COLOR
			"hostage":
				color = HOSTAGE_COLOR
		# Classic blips are small solid squares; contacts above/below the
		# observer grow a "T" bar pointing at their altitude.
		if kind == "bomb" and contact.get("state", "planted") == "planted":
			draw_line(point - Vector2(3, 3), point + Vector2(3, 3), color, 2.0)
			draw_line(point + Vector2(-3, 3), point + Vector2(3, -3), color, 2.0)
			continue
		draw_rect(Rect2(point + Vector2(-2.0, -2.0), Vector2(4.0, 4.0)), color)
		if kind not in ["teammate", "bomb"]:
			continue
		if height_hu > 64.0:
			draw_rect(Rect2(point + Vector2(-1.0, -8.0), Vector2(2.0, 6.0)), color)
			draw_rect(Rect2(point + Vector2(-3.0, -9.0), Vector2(6.0, 2.0)), color)
		elif height_hu < -64.0:
			draw_rect(Rect2(point + Vector2(-1.0, 2.0), Vector2(2.0, 6.0)), color)
			draw_rect(Rect2(point + Vector2(-3.0, 7.0), Vector2(6.0, 2.0)), color)
