extends RefCounted

## Owner-only movement prediction. Never enables the pawn's gameplay tick.
## Host snapshots replace the baseline; only unacknowledged movement is replayed.
## Lost input can still cause a correction because the server uses latest-held
## input. The history/time horizon is bounded rather than guessing indefinitely.
const MAX_PENDING := 25
const MAX_HORIZON := 0.25
const STALE_MS := 250
const TELEPORT_DISTANCE := 3.0
var pending: Array[Dictionary] = []
var enabled := false
var last_ack := 0
var _identity := ""
var _received_ms := -1


func clear() -> void:
	pending.clear()
	enabled = false
	last_ack = 0
	_identity = ""
	_received_ms = -1


func reconcile(player: PlayerController, row: Dictionary, motion: Dictionary,
		ack: int, identity: String, now_ms: int) -> void:
	var reset: bool = identity != _identity or not row.alive or not motion.enabled
	reset = reset or player.global_position.distance_to(row.position) > TELEPORT_DISTANCE
	if reset:
		pending.clear()
	_identity = identity
	last_ack = ack
	_received_ms = now_ms
	enabled = bool(row.alive) and bool(motion.enabled)
	while not pending.is_empty() and (int(pending[0].sequence) <= ack \
			or now_ms - int(pending[0].sent_ms) >= STALE_MS):
		pending.pop_front()
	player.global_position = row.position
	player.velocity = row.velocity
	player._standing = motion.standing
	player._duck_elapsed = float(motion.duck_elapsed)
	player._jump_was_down = motion.jump_down
	player.objective_movement_locked = motion.objective_locked
	player.objective_crouch_locked = motion.objective_crouch
	player._max_speed_override_ups = float(motion.max_speed)
	player._apply_hull(player.STAND_HEIGHT if player._standing else player.CROUCH_HIT_HEIGHT)
	# Stair smoothing is presentation state, not part of the authoritative wire
	# snapshot. Rebuild it from the unacknowledged local movement replay.
	player._stair_view_offset = 0.0
	player._set_camera_eye(lerpf(player.STAND_EYE, player.CROUCH_EYE,
		player._spline_fraction(player._duck_elapsed / player.DUCK_TIME)) if player._standing else player.CROUCH_EYE)
	# Ray/sweep queries may see map solids, but this owner is on no collision
	# layer: it cannot trigger pickups, deal damage or push another combatant.
	player.collision_mask = 1 if row.alive else 0
	if enabled:
		for record: Dictionary in pending:
			_step(player, record)


func predict(player: PlayerController, command: Dictionary, sequence: int,
		delta: float, now_ms: int) -> bool:
	if not enabled or sequence <= last_ack or not is_finite(delta) or delta <= 0.0 or delta > 0.05 \
			or now_ms < _received_ms or now_ms - _received_ms >= STALE_MS \
			or pending.size() >= MAX_PENDING:
		return false
	var horizon := delta
	for record: Dictionary in pending:
		horizon += float(record.delta)
	if horizon > MAX_HORIZON + 0.000001 \
			or (not pending.is_empty() and sequence <= int(pending.back().sequence)):
		return false
	var movement: Vector2 = command.get("movement", Vector2.ZERO)
	# Match network sanitization, including diagonal analog movement.
	if not movement.is_finite():
		movement = Vector2.ZERO
	if movement.length_squared() > 1.0:
		movement = movement.normalized()
	var record := {"sequence": sequence, "delta": delta, "sent_ms": now_ms, "yaw": player.input_view_angles().x,
		"command": {"movement": movement, "jump": bool(command.get("jump", false)),
			"crouch": bool(command.get("crouch", false)), "walk": bool(command.get("walk", false))}}
	pending.append(record)
	_step(player, record)
	return true


func _step(player: PlayerController, record: Dictionary) -> void:
	# Replaying a previous movement yaw must not rewind the current mouse aim.
	# Body/collider orientation stays unchanged (the hull is axis-aligned).
	var view_yaw := player._yaw
	player._yaw = float(record.yaw)
	player.simulate_movement(record.command, float(record.delta))
	player._yaw = view_yaw
