extends SceneTree

const Events = preload("res://scripts/network_combat_events.gd")
class SpyView extends "res://scripts/network_client_view.gd":
	var observed: Array[Dictionary] = []
	func _present_combat(event: Dictionary, _row: Dictionary) -> void:
		observed.append(event)

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _packet(kind: String, data: Dictionary) -> Dictionary:
	return {"version": Events.VERSION, "epoch": 2, "sequence": 1, "tick": 10,
		"actor": "remote_human_1", "life": 1, "kind": kind, "data": data}

func _run() -> void:
	_check(AudioServer.get_driver_name() == "Dummy", "fixture must be silent")
	var shot := _packet("shot", {"weapon": "glock18", "sequence": 0, "origin": Vector3.ZERO,
		"direction": Vector3.FORWARD, "right": Vector3.RIGHT, "up": Vector3.UP, "punch": Vector2(-1.4, 0)})
	var audio := _packet("audio", {"name": "glock18.fire", "sample": "weapons/glock18-2.wav",
		"channel": 1, "volume": 1.0, "attenuation": 0.8, "pitch": 100, "origin": Vector3.ZERO})
	_check(Events.validate(shot) == shot and Events.validate(audio) == audio, "shot and exact sample round-trip")
	var reload_event := _packet("reload", {"weapon": "ak47"})
	_check(Events.validate(reload_event) == reload_event, "reload uses a known weapon")
	var radio := _packet("radio", {"sample": "ct_coverme", "sender_name": "Andrei",
		"team": "CT", "text": "Cover me!"})
	_check(Events.validate(radio) == radio, "team radio presentation round-trips")
	for pair in [["sample", "../ct_coverme"], ["sender_name", ""], ["team", "CT2"], ["text", "forged"]]:
		var bad_radio := radio.duplicate(true)
		bad_radio.data[pair[0]] = pair[1]
		_check(Events.validate(bad_radio).is_empty(), "forged radio field rejected: " + str(pair[0]))
	for kind in ["impact", "blood", "blood_decal"]:
		var impact := _packet(kind, {"position": Vector3.ZERO, "normal": Vector3.UP, "sequence": 17, "surface": "concrete"})
		impact.actor = ""
		_check(Events.validate(impact) == impact, "world effect round-trips: " + kind)
		impact.data.normal = Vector3(NAN, 0, 0)
		_check(Events.validate(impact).is_empty(), "invalid effect normal rejected")
	var kill := _packet("kill", {"killer": "Player", "killer_team": "T", "weapon": "GLOCK 18",
		"victim": "CT Bot", "victim_team": "CT", "headshot": true})
	kill.actor = ""
	_check(Events.validate(kill) == kill, "kill preserves teams and headshot flag")
	kill.data.headshot = 1
	_check(Events.validate(kill).is_empty(), "kill flag cannot coerce from a number")
	for field: String in shot:
		var bad := shot.duplicate(true)
		bad.erase(field)
		_check(Events.validate(bad).is_empty(), "missing envelope field rejected: " + field)
	for pair in [["sequence", -1], ["sequence", 1.0], ["tick", NAN], ["epoch", 0], ["version", 99],
		["actor", "../evil"], ["kind", "damage"], ["life", -1], ["extra", true]]:
		var bad := shot.duplicate(true)
		bad[pair[0]] = pair[1]
		_check(Events.validate(bad).is_empty(), "invalid envelope rejected: " + str(pair[0]))
	for pair in [["weapon", "bogus"], ["direction", Vector3.INF], ["up", Vector3.ZERO],
		["origin", Vector3(10001, 0, 0)], ["punch", Vector2(NAN, 0)], ["sequence", 256]]:
		var bad := shot.duplicate(true)
		bad.data[pair[0]] = pair[1]
		_check(Events.validate(bad).is_empty(), "invalid shot rejected: " + str(pair[0]))
	for pair in [["sample", "../../secret.wav"], ["sample", "weapons/glock18-1.wav"],
		["name", "weapon.mode_switch"], ["pitch", 0], ["volume", 2.0], ["attenuation", INF], ["channel", 7]]:
		var bad := audio.duplicate(true)
		bad.data[pair[0]] = pair[1]
		_check(Events.validate(bad).is_empty(), "invalid audio rejected: " + str(pair[0]))
	var network := root.get_node("NetworkSession")
	network.disconnect_session()
	var view := SpyView.new()
	view.set_process(false)
	network.combat_event_received.connect(view.queue_combat_event)
	_check(network.accept_combat_event(shot), "first host event accepted")
	_check(not network.accept_combat_event(shot), "duplicate rejected before presentation")
	_check(view.observed.is_empty() and view._pending_combat.size() == 1, "event waits for world snapshot")
	view._epoch = 2
	view.snapshot = {"tick": 10, "round": {"number": 1}, "actors": [{"id": shot.actor, "life": 1}]}
	view._drain_combat_events()
	_check(view.observed.size() == 1 and view._pending_combat.is_empty(), "queued event plays once after matching world")
	var next := shot.duplicate(true)
	next.sequence = 2
	next.life = 2
	_check(network.accept_combat_event(next), "new event accepted by transport")
	_check(view.observed.size() == 1, "wrong life cannot animate current pawn")
	next.sequence = 3
	next.life = 1
	next.tick = 20
	network.accept_combat_event(next)
	_check(view._pending_combat.size() == 1, "event newer than world waits")
	view._pending_combat[0].received_ms -= 1001
	view._drain_combat_events()
	_check(view._pending_combat.is_empty(), "stalled snapshot expires pending feedback")
	view.snapshot.tick = 200
	next.sequence = 4
	network.accept_combat_event(next)
	_check(view.observed.size() == 1, "old shot cannot replay after a long delivery delay")
	for index in range(Events.MAX_PENDING + 20):
		next.sequence = index + 5
		next.tick = 300
		network.accept_combat_event(next)
	_check(view._pending_combat.size() == Events.MAX_PENDING, "pending event memory remains bounded")
	view._epoch = 3
	view._drain_combat_events()
	_check(view._pending_combat.is_empty(), "new world drops old epoch events")
	# Kill notices have a longer useful lifetime than transient shot effects.
	view._epoch = 2
	kill.data.headshot = true
	kill.tick = 300
	view.queue_combat_event(kill)
	view._pending_combat[0].received_ms -= 2000
	view.snapshot.tick = 500
	view._drain_combat_events()
	_check(view.observed.size() == 2 and view.observed[-1].kind == "kill", "kill notice survives a two-second presentation stall")
	kill.life = 2
	view.queue_combat_event(kill)
	_check(view.observed.size() == 2, "kill notice still cannot leak across rounds")
	view._epoch = 3
	next.epoch = 3
	next.sequence = 1
	_check(network.accept_combat_event(next), "new epoch accepts fresh sequence")
	_check(not network.accept_combat_event(shot), "previous epoch cannot return")
	network.disconnect_session()
	_check(network.accept_combat_event(shot), "disconnect resets receive counters")
	network.combat_event_received.disconnect(view.queue_combat_event)
	view.free()
	for failure in failures:
		push_error(failure)
	if failures.is_empty():
		print("GAME_NETWORK_COMBAT_EVENTS_PASS")
	quit(0 if failures.is_empty() else 1)
