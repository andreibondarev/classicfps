extends SceneTree

const State = preload("res://scripts/network_world_state.gd")
var failures: Array[String] = []
var network: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _chunks(snapshot: Dictionary) -> Array:
	var encoded := State.encode(snapshot)
	var count := ceili(float(encoded.size()) / network.WORLD_CHUNK_BYTES)
	var result: Array = []
	for index in range(count):
		result.append([State.VERSION, snapshot.epoch, snapshot.tick, index, count,
			encoded.slice(index * network.WORLD_CHUNK_BYTES, mini((index + 1) * network.WORLD_CHUNK_BYTES, encoded.size()))])
	return result


func _run() -> void:
	network = root.get_node("NetworkSession")
	network.disconnect_session()
	_check(network.MAX_WORLD_CHUNKS == ceili(float(State.MAX_ENCODED_BYTES) / network.WORLD_CHUNK_BYTES), "chunk count matches bounded codec capacity")
	var human := PlayerController.new()
	human._initialize_starting_loadout()
	var snapshot := {"version": State.VERSION, "epoch": 1, "tick": 10, "map": "de_dust2", "owner_id": "remote_human_1",
		"input_ack": 1, "started": true, "concluded": false, "inventory": State.inventory_for(human), "can_buy": false,
		"motion": State.motion_for(human), "feedback": State.empty_feedback(), "broken_brushes": [],
		"round": {"number": 1, "phase": "live", "seconds": 100.0, "t_score": 0, "ct_score": 0}, "actors": [], "items": []}
	for index in range(10):
		snapshot.actors.append({"id": "remote_human_%d" % (index + 1), "kind": "human", "name": "Human %d" % index, "team": "T",
			"position": Vector3(index * 0.71, 0, index * -0.33), "velocity": Vector3.ZERO, "angles": Vector2.ZERO,
			"alive": true, "visible": true, "health": 100, "armor": 0, "helmet": false, "weapon": human.active_weapon,
			"clip": human.clip, "reserve": human.reserve, "reloading": false, "skin": "terror", "life": 1,
			"crouched": false, "kills": 0, "deaths": 0, "money": 800, "class_id": 1, "ping": -1})
	for index in range(State.MAX_WORLD_ITEMS):
		snapshot.items.append({"id": index + 1, "kind": "gun", "weapon": "ak47",
			"position": Vector3(index * 0.33, index * 0.11, index * 0.79),
			"rotation": Quaternion.from_euler(Vector3(index * 0.17, index * 0.31, index * 0.41)), "total": 0.0, "remaining": 0.0})
	human.free()
	_check(not State.validate(snapshot).is_empty(), "chunk fixture starts with valid full world")
	var chunks := _chunks(snapshot)
	_check(chunks.size() > 1 and chunks.size() <= network.MAX_WORLD_CHUNKS, "large world uses multiple bounded datagrams")
	for chunk: Array in chunks:
		_check(var_to_bytes(chunk).size() <= 1200, "each chunk stays below payload target")
	_check(not network.accept_world_chunk(chunks.back(), 1000) and network.latest_world_snapshot.is_empty(), "out-of-order final chunk cannot partially apply world")
	_check(not network.accept_world_chunk(chunks.back(), 1000), "duplicate chunk ignored")
	for index in range(chunks.size() - 1):
		var applied: bool = network.accept_world_chunk(chunks[index], 1001 + index)
		_check(applied == (index == chunks.size() - 2), "only the final missing part applies atomically")
	_check(network.latest_world_snapshot == snapshot and network._world_assemblies.is_empty(), "complete reordered world matches source and releases buffer")
	_check(not network.accept_world_chunk(chunks[0], 1100), "already applied frame never reassembles")
	var next := snapshot.duplicate(true)
	next.tick = 11
	var next_chunks := _chunks(next)
	network.accept_world_chunk(next_chunks[0], 1200)
	_check(network.latest_world_snapshot.tick == 10, "missing parts leave previous complete state untouched")
	network.expire_world_assemblies(1200 + network.WORLD_ASSEMBLY_TIMEOUT_MS)
	_check(network._world_assemblies.is_empty() and network.latest_world_snapshot.tick == 10, "incomplete buffers expire without erasing valid world")
	for tick in [1000, 1001, 1002]:
		var part: Array = next_chunks[0].duplicate(true)
		part[2] = tick
		network.accept_world_chunk(part, 2300 + tick)
		_check(network._world_assemblies.size() <= 2, "in-flight memory stays bounded")
	for chunk: Array in next_chunks:
		network.accept_world_chunk(chunk, 4000)
	_check(network.latest_world_snapshot.tick == 11, "incomplete higher-counter envelope cannot poison valid ordering")
	for value in [null, {}, true, PackedByteArray(), [State.VERSION]]:
		_check(not network.accept_world_chunk(value, 4000), "malformed envelope rejected")
	var overflow := PackedByteArray()
	overflow.resize(State.MAX_ENCODED_BYTES - (network.MAX_WORLD_CHUNKS - 1) * network.WORLD_CHUNK_BYTES + 1)
	_check(not network.accept_world_chunk([State.VERSION, 1, 12, network.MAX_WORLD_CHUNKS - 1, network.MAX_WORLD_CHUNKS, overflow], 4000),
		"oversized final fragment is rejected before assembly allocation")
	for pair: Array in [[0, 0], [1, true], [2, -1], [3, -1], [3, 99], [4, 0], [4, network.MAX_WORLD_CHUNKS + 1], [5, []], [5, PackedByteArray()]]:
		var bad: Array = next_chunks[0].duplicate(true)
		bad[2] = 12
		bad[pair[0]] = pair[1]
		_check(not network.accept_world_chunk(bad, 4000), "invalid chunk field rejected")
	for chunk: Array in next_chunks:
		var mismatched := chunk.duplicate(true)
		mismatched[2] = 12
		_check(not network.accept_world_chunk(mismatched, 4100), "envelope counters must match decoded world")
	_check(network.latest_world_snapshot.tick == 11, "mismatched complete frame does not mutate world")
	network.disconnect_session()
	_check(network._world_assemblies.is_empty() and network.latest_world_snapshot.is_empty(), "disconnect clears assembly and world")
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_WORLD_CHUNKS_PASS chunks=", chunks.size())
	quit(0 if failures.is_empty() else 1)
