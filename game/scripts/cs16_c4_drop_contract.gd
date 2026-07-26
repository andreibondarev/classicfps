class_name CS16C4DropContract
extends RefCounted

## Pure source contract shared by death-drop and the manual `drop` command.

const GOLDSRC_UNIT := 0.01
const FORWARD_OFFSET_HU := 10.0
const FORWARD_SPEED_HU := 400.0


static func build_drop(
	player_origin: Vector3,
	player_forward: Vector3,
) -> Dictionary:
	var forward := player_forward
	forward.y = 0.0
	if forward.is_zero_approx():
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()
	return {
		"origin": (
			player_origin
			+ forward * FORWARD_OFFSET_HU * GOLDSRC_UNIT
		),
		"velocity": forward * FORWARD_SPEED_HU * GOLDSRC_UNIT,
		"forward": forward,
	}


static func kinematics(
	player_origin: Vector3,
	player_forward: Vector3,
) -> Dictionary:
	return build_drop(player_origin, player_forward)


static func resolve_manual_drop(
	active_weapon: String,
	alive: bool,
	is_bomb_owner: bool,
	bomb_state: String,
	player_origin: Vector3,
	player_forward: Vector3,
) -> Dictionary:
	if not alive:
		return {"allowed": false, "reason": "dead"}
	if not is_bomb_owner:
		return {"allowed": false, "reason": "not_bomb_owner"}
	if active_weapon != "c4":
		return {"allowed": false, "reason": "c4_not_active"}
	if bomb_state != "carried":
		return {"allowed": false, "reason": "bomb_not_carried"}
	var result := build_drop(player_origin, player_forward)
	result.allowed = true
	result.reason = "ok"
	result.weapon = "c4"
	return result
