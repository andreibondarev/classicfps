extends SceneTree

const State = preload("res://scripts/network_world_state.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var row := {"id": "remote_human_1", "kind": "human", "name": "Remote Human", "team": "T",
		"position": Vector3.ZERO, "velocity": Vector3.ZERO, "angles": Vector2.ZERO, "alive": true,
		"visible": true, "health": 100, "armor": 0, "helmet": false, "weapon": "glock18", "clip": 20,
		"reserve": 40, "reloading": false, "skin": "terror", "life": 1, "crouched": false,
		"kills": 0, "deaths": 0, "money": 800, "class_id": 1, "ping": -1}
	var valid := {"version": State.VERSION, "epoch": 2, "tick": 10, "map": "de_dust2", "owner_id": row.id,
		"input_ack": 4, "started": true, "concluded": false, "items": [], "can_buy": true, "feedback": State.empty_feedback(), "broken_brushes": [],
		"motion": {"enabled": true, "standing": true, "duck_elapsed": 0.0, "jump_down": false,
			"objective_locked": false, "objective_crouch": false, "max_speed": 0.0},
		"inventory": {"weapons": [{"weapon": "glock18", "clip": 20, "reserve": 40, "mode": false}],
			"previous": "", "equipment": {"kevlar": false, "helmet": false, "defuser": false, "nvgs": false, "shield": false}},
		"round": {"number": 1, "phase": "live", "seconds": 100.0, "t_score": 0, "ct_score": 0}, "actors": [row]}
	_check(State.validate(valid) == valid, "complete actor state round-trips")
	for field: String in valid.motion:
		var bad := valid.duplicate(true)
		bad.motion.erase(field)
		_check(State.validate(bad).is_empty(), "missing movement field rejected: " + field)
	for pair: Array in [["enabled", 1], ["standing", false], ["duck_elapsed", NAN], ["duck_elapsed", -0.1],
		["duck_elapsed", 1.0], ["jump_down", 1], ["objective_locked", 1], ["objective_crouch", true],
		["max_speed", INF], ["max_speed", -1.0], ["extra", 0]]:
		var bad := valid.duplicate(true)
		bad.motion[pair[0]] = pair[1]
		_check(State.validate(bad).is_empty(), "invalid movement field rejected: " + str(pair[0]))
	for weapon: String in State.Weapons.WEAPONS:
		var armed := valid.duplicate(true)
		armed.actors[0].weapon = weapon
		armed.actors[0].clip = int(State.Weapons.WEAPONS[weapon].magazine)
		armed.actors[0].reserve = int(State.Weapons.WEAPONS[weapon].reserve)
		armed.inventory.weapons = [{"weapon": weapon, "clip": armed.actors[0].clip, "reserve": armed.actors[0].reserve,
			"mode": 0 if State.Weapons.WEAPONS[weapon].secondary == "zoom" else false}]
		_check(not State.validate(armed).is_empty(), "registry ammunition semantics accepted: " + weapon)
	var inventory: Dictionary = valid.inventory
	for value in [null, [], {}, {"weapons": [], "previous": "", "equipment": {}}]:
		_check(not State.valid_inventory(value), "malformed inventory envelope rejected")
	for pair: Array in [["weapon", "unknown"], ["clip", -1], ["reserve", true], ["mode", 1], ["extra", 0]]:
		var bad := inventory.duplicate(true)
		bad.weapons[0][pair[0]] = pair[1]
		_check(not State.valid_inventory(bad), "invalid inventory item rejected: " + str(pair[0]))
	var repeated := inventory.duplicate(true)
	repeated.weapons.append(repeated.weapons[0].duplicate())
	_check(not State.valid_inventory(repeated), "duplicate carried weapon rejected")
	var mismatch := valid.duplicate(true)
	mismatch.inventory.weapons[0].clip = 1
	_check(State.validate(mismatch).is_empty(), "owner ammunition must agree across actor and inventory")
	mismatch.inventory.weapons.clear()
	_check(State.validate(mismatch).is_empty(), "living owner's active weapon must be carried")
	for equipment: String in State.EQUIPMENT:
		var bad := inventory.duplicate(true)
		bad.equipment[equipment] = 1
		_check(not State.valid_inventory(bad), "equipment never coerces integers to flags")
	_check(State.decode(State.encode(valid)) == valid, "bounded compressed wire representation round-trips")
	var with_sprays := valid.duplicate(true)
	with_sprays.sprays = []
	for index in 32:
		with_sprays.sprays.append({"id": index + 1, "position": Vector3(index, 1, 2), "normal": Vector3.BACK})
	_check(State.decode(State.encode(with_sprays)) == with_sprays, "maximum spray history survives bounded world codec")
	with_sprays.sprays.append(with_sprays.sprays[0])
	_check(State.validate(with_sprays).is_empty(), "oversized spray history rejected")
	with_sprays.sprays = [{"id": 1, "position": Vector3.ZERO, "normal": Vector3.ZERO}]
	_check(State.validate(with_sprays).is_empty(), "invalid spray normal rejected before client mutation")
	var world_item := {"id": 1, "kind": "gun", "weapon": "ak47", "position": Vector3.ONE,
		"rotation": Quaternion.IDENTITY, "total": 0.0, "remaining": 0.0}
	_check(State.valid_world_items([world_item]), "known gun world item accepted")
	for value in [null, {}, true, "items"]:
		_check(not State.valid_world_items(value), "world items must be a bounded array")
	for field: String in world_item:
		var missing := world_item.duplicate()
		missing.erase(field)
		_check(not State.valid_world_items([missing]), "missing item field rejected: " + field)
	for pair: Array in [["id", true], ["id", 0], ["id", State.MAX_COUNTER + 1], ["kind", "projectile"],
		["weapon", "../awp"], ["weapon", "knife"], ["weapon", "c4"], ["position", Vector3(INF, 0, 0)],
		["rotation", Vector3.ZERO], ["rotation", Quaternion(0, 0, 0, 0)], ["rotation", Quaternion(NAN, 0, 0, 1)],
		["total", 45.0], ["remaining", -1.0], ["extra", 1]]:
		var bad := world_item.duplicate()
		bad[pair[0]] = pair[1]
		_check(not State.valid_world_items([bad]), "invalid world item field rejected: " + str(pair[0]))
	_check(not State.valid_world_items([world_item, world_item]), "duplicate world IDs rejected")
	var planted := world_item.duplicate()
	planted.kind = "planted_c4"
	planted.weapon = "c4"
	planted.total = 45.0
	planted.remaining = 30.0
	_check(State.valid_world_items([planted]), "planted C4 countdown accepted")
	planted.remaining = 46.0
	_check(not State.valid_world_items([planted]), "countdown cannot exceed total")
	planted.remaining = 30.0
	var backpack := world_item.duplicate()
	backpack.id = 2
	backpack.kind = "dropped_c4"
	backpack.weapon = "c4"
	_check(State.valid_world_items([backpack]) and not State.valid_world_items([planted, backpack]), "C4 cannot be both planted and dropped")
	_check(State.decode({}).is_empty() and State.decode(PackedByteArray([1, 2])).is_empty(), "invalid wire envelope rejected")
	var oversized := PackedByteArray()
	oversized.resize(5)
	oversized.encode_u32(0, State.MAX_DECODED_BYTES + 1)
	_check(State.decode(oversized).is_empty(), "declared decompression bomb rejected before allocation")
	for value in [null, true, [], "snapshot", 1]:
		_check(State.validate(value).is_empty(), "wrong top-level type rejected")
	for field: String in valid:
		var bad := valid.duplicate(true)
		bad.erase(field)
		_check(State.validate(bad).is_empty(), "missing world field rejected: " + field)
	for field: String in row:
		var bad := valid.duplicate(true)
		bad.actors[0].erase(field)
		_check(State.validate(bad).is_empty(), "missing actor field rejected: " + field)
	for pair: Array in [["version", 1], ["epoch", 0], ["epoch", true], ["tick", -1], ["input_ack", 1.5],
		["map", "unknown"], ["owner_id", "missing"], ["actors", []], ["actors", {}], ["started", 1], ["can_buy", 1], ["extra", 1]]:
		var bad := valid.duplicate(true)
		bad[pair[0]] = pair[1]
		_check(State.validate(bad).is_empty(), "invalid world field rejected: " + str(pair[0]))
	for pair: Array in [["id", "../Player"], ["kind", "unknown"], ["name", "x".repeat(65)], ["team", "none"],
		["position", Vector3(NAN, 0, 0)], ["position", Vector3(10001, 0, 0)], ["velocity", Vector3(INF, 0, 0)],
		["angles", Vector2(4, 0)], ["angles", Vector2(0, NAN)], ["health", 0], ["health", 101], ["armor", -1],
		["alive", 1], ["visible", "true"], ["weapon", "invented"], ["clip", -1], ["reserve", 1001], ["skin", "missing"],
		["life", -1], ["class_id", 5], ["ping", -2], ["ping", 10000], ["ping", 1.5], ["money", 16001], ["deaths", -1], ["owner", 1]]:
		var bad := valid.duplicate(true)
		bad.actors[0][pair[0]] = pair[1]
		_check(State.validate(bad).is_empty(), "invalid actor field rejected: " + str(pair[0]))
	for pair: Array in [["number", 0], ["phase", "invalid"], ["seconds", INF], ["t_score", true], ["ct_score", -1]]:
		var bad := valid.duplicate(true)
		bad.round[pair[0]] = pair[1]
		_check(State.validate(bad).is_empty(), "invalid round field rejected: " + str(pair[0]))
	var duplicate := valid.duplicate(true)
	duplicate.actors.append(row.duplicate())
	_check(State.validate(duplicate).is_empty(), "duplicate identities rejected before partial application")
	var full := valid.duplicate(true)
	for index in range(1, State.MAX_ACTORS):
		var actor := row.duplicate()
		actor.id = "remote_human_%d" % (index + 1)
		full.actors.append(actor)
	_check(not State.validate(full).is_empty(), "bounded maximum actor count accepted")
	_check(State.decode(State.encode(full)) == full, "maximum-count state fits bounded compressed codec")
	for index in range(State.MAX_WORLD_ITEMS):
		var item := world_item.duplicate()
		item.id = index + 1
		item.position = Vector3(index * 0.73, index * 0.11, index * -0.31)
		item.rotation = Quaternion.from_euler(Vector3(index * 0.11, index * 0.37, index * 0.07))
		full.items.append(item)
	_check(State.decode(State.encode(full)) == full, "maximum actor/item counts round-trip together within wire envelope")
	full.items.append(world_item)
	_check(State.validate(full).is_empty(), "oversized world item list rejected")
	full.items.clear()
	var extra := row.duplicate()
	extra.id = "overflow"
	full.actors.append(extra)
	_check(State.validate(full).is_empty(), "oversized actor list rejected")
	var network := root.get_node("NetworkSession")
	network.disconnect_session()
	_check(network.accept_world_snapshot(valid), "first complete snapshot accepted")
	_check(not network.accept_world_snapshot(valid), "duplicate frame ignored")
	var malformed := valid.duplicate(true)
	malformed.tick = 999
	malformed.actors[0].health = 999
	_check(not network.accept_world_snapshot(malformed) and network.latest_world_snapshot.tick == 10,
		"invalid late packet cannot poison ordering or partially mutate retained state")
	var next := valid.duplicate(true)
	next.tick = 11
	_check(network.accept_world_snapshot(next), "next valid frame accepted")
	next.actors[0].health = 1
	_check(network.latest_world_snapshot.actors[0].health == 100, "nested retained state detached from caller")
	next.epoch = 3
	next.tick = 0
	_check(network.accept_world_snapshot(next), "new host-world epoch permits a restarted frame counter")
	valid.tick = 1000
	_check(not network.accept_world_snapshot(valid), "old epoch cannot replace newer world even with a higher tick")
	network.disconnect_session()
	_check(network.latest_world_snapshot.is_empty() and network.accept_world_snapshot(valid), "new connection resets world ordering")
	network.disconnect_session()
	_check(network.host_game(0, "127.0.0.1") == OK, "isolated host starts")
	network._register_input_peer(99, Time.get_ticks_msec())
	_check(not network.send_world_snapshot(99, valid), "registered but disconnected destination is not sent an RPC")
	network.disconnect_session()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_WORLD_STATE_PASS")
	quit(0 if failures.is_empty() else 1)
