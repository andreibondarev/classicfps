class_name CS16BombKnowledge
extends RefCounted

## Per-bot bomb knowledge driven by Counter-Strike events.
##
## CSGameState does not continuously poll distance to the bomb. Terrorists
## receive exact loose/planted positions, while Counter-Terrorists learn an
## exact planted position from an audible beep or direct visual contact. Radio
## chatter may share the planted site without sharing the exact C4 origin.

const TEAM_T := "T"
const TEAM_CT := "CT"
const GOLDSRC_UNIT := 0.01
const BEEP_HEAR_RANGE_HU := 1000.0
const BEEP_HEAR_RANGE := BEEP_HEAR_RANGE_HU * GOLDSRC_UNIT

const STATE_UNKNOWN := "unknown"
const STATE_CARRIED := "carried"
const STATE_LOOSE := "loose"
const STATE_PLANTED := "planted"

var bomb_state := STATE_UNKNOWN
var bomb_position := Vector3.ZERO
var _actors := {}


func register_actor(actor_id: String, team: String) -> void:
	_actors[actor_id] = {
		"team": team,
		"knows_exact": false,
		"exact_position": Vector3.ZERO,
		"known_site": "",
	}


func reset_round() -> void:
	bomb_state = STATE_UNKNOWN
	bomb_position = Vector3.ZERO
	for actor_id: String in _actors:
		var state: Dictionary = _actors[actor_id]
		state.knows_exact = false
		state.exact_position = Vector3.ZERO
		state.known_site = ""
		_actors[actor_id] = state


func on_bomb_carried() -> void:
	bomb_state = STATE_CARRIED
	_clear_exact_positions()


func on_bomb_dropped(position: Vector3) -> void:
	bomb_state = STATE_LOOSE
	bomb_position = position
	for actor_id: String in _actors:
		var state: Dictionary = _actors[actor_id]
		# Terrorists receive the loose C4 location through the bomb radar.
		if str(state.team) == TEAM_T:
			_set_exact(actor_id, position)
		else:
			state.knows_exact = false
			state.exact_position = Vector3.ZERO
			_actors[actor_id] = state


func on_bomb_picked_up() -> void:
	on_bomb_carried()


func on_bomb_planted(
	position: Vector3,
	positions_by_actor: Dictionary,
) -> void:
	bomb_state = STATE_PLANTED
	bomb_position = position
	for actor_id: String in _actors:
		var state: Dictionary = _actors[actor_id]
		state.knows_exact = false
		state.exact_position = Vector3.ZERO
		_actors[actor_id] = state
		if str(state.team) == TEAM_T:
			_set_exact(actor_id, position)
	# EVENT_BOMB_PLANTED immediately forwards EVENT_BOMB_BEEP to each bot.
	on_bomb_beep(position, positions_by_actor)


func on_bomb_beep(
	position: Vector3,
	positions_by_actor: Dictionary,
) -> Array[String]:
	var newly_informed: Array[String] = []
	if bomb_state != STATE_PLANTED:
		return newly_informed
	bomb_position = position
	for actor_id: String in _actors:
		if knows_exact(actor_id) or not positions_by_actor.has(actor_id):
			continue
		var actor_position: Variant = positions_by_actor[actor_id]
		if not actor_position is Vector3:
			continue
		if (
			(actor_position as Vector3).distance_squared_to(position)
			< BEEP_HEAR_RANGE * BEEP_HEAR_RANGE
		):
			_set_exact(actor_id, position)
			newly_informed.append(actor_id)
	return newly_informed


func on_visual_contact(
	actor_id: String,
	position: Vector3,
	in_fov: bool,
	line_clear: bool,
) -> bool:
	if (
		not _actors.has(actor_id)
		or bomb_state not in [STATE_LOOSE, STATE_PLANTED]
		or not in_fov
		or not line_clear
	):
		return false
	_set_exact(actor_id, position)
	return true


func on_planted_site_radio(actor_id: String, site_id: String) -> void:
	if not _actors.has(actor_id) or bomb_state != STATE_PLANTED:
		return
	var state: Dictionary = _actors[actor_id]
	state.known_site = site_id
	_actors[actor_id] = state


func broadcast_planted_site(site_id: String, receiver_ids: Array[String]) -> void:
	for actor_id: String in receiver_ids:
		on_planted_site_radio(actor_id, site_id)


func knows_exact(actor_id: String) -> bool:
	return (
		_actors.has(actor_id)
		and bool((_actors[actor_id] as Dictionary).knows_exact)
	)


func exact_position(actor_id: String) -> Variant:
	if not knows_exact(actor_id):
		return null
	return (_actors[actor_id] as Dictionary).exact_position


func known_site(actor_id: String) -> String:
	if not _actors.has(actor_id):
		return ""
	return str((_actors[actor_id] as Dictionary).known_site)


func state_for(actor_id: String) -> Dictionary:
	if not _actors.has(actor_id):
		return {}
	return (_actors[actor_id] as Dictionary).duplicate(true)


func _clear_exact_positions() -> void:
	for actor_id: String in _actors:
		var state: Dictionary = _actors[actor_id]
		state.knows_exact = false
		state.exact_position = Vector3.ZERO
		_actors[actor_id] = state


func _set_exact(actor_id: String, position: Vector3) -> void:
	if not _actors.has(actor_id):
		return
	var state: Dictionary = _actors[actor_id]
	state.knows_exact = true
	state.exact_position = position
	_actors[actor_id] = state
