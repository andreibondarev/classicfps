extends SceneTree

const WeaponClock := preload("res://scripts/cs16_weapon_clock.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("WEAPON TIMING TEST: " + message)


func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(
		absf(actual - expected) <= tolerance,
		"%s (got %.8f, expected %.8f)" % [message, actual, expected],
	)


func _run() -> void:
	_test_source_constants()
	_test_primary_and_reload_boundaries()
	_test_deploy_idle_and_grenade_states()
	_test_render_rate_independent_tapes()
	_test_recoil_tape()

	if failures.is_empty():
		print("GAME_WEAPON_TIMING_TEST_PASS")
		quit(0)
	else:
		print("GAME_WEAPON_TIMING_TEST_FAIL: %s" % ", ".join(failures))
		quit(1)


func _test_source_constants() -> void:
	_check(WeaponClock.TICK_RATE_HZ == 100, "authoritative weapon clock is 100 Hz")
	_check(WeaponClock.ticks_from_seconds(0.0955) == 10, "AK 0.0955 cycle quantizes to tick 10")
	_check(WeaponClock.ticks_from_seconds(0.225) == 23, "Deagle 0.225 cycle quantizes to tick 23")
	_check(WeaponClock.ticks_from_seconds(2.45) == 245, "AK reload is exactly 245 ticks")
	_check(WeaponClock.ticks_from_seconds(2.2) == 220, "Deagle reload is exactly 220 ticks")
	_check(WeaponClock.ticks_from_seconds(0.35) == 35, "knife miss recovery is 35 ticks")
	_check(WeaponClock.ticks_from_seconds(0.4) == 40, "knife hit recovery is 40 ticks")
	_check(WeaponClock.ticks_from_seconds(0.5) == 50, "HE pin/retire timing is 50 ticks")
	_check(WeaponClock.ticks_from_seconds(0.75) == 75, "default deploy lock is 75 ticks")


func _test_primary_and_reload_boundaries() -> void:
	var clock := WeaponClock.new()
	clock.reset("ak47")
	_check(clock.begin_primary_attack(), "AK fires on ready tick zero")
	_check(clock.next_primary_tick == 10, "AK next-primary deadline is absolute tick 10")
	clock.advance_tick(9)
	_check(not clock.can_primary_attack(), "AK is blocked through tick nine")
	clock.advance_tick()
	_check(clock.can_primary_attack(), "AK is ready exactly on tick ten")

	clock.reset("deagle")
	_check(clock.begin_primary_attack(), "Deagle fires on ready tick zero")
	clock.advance_tick(22)
	_check(not clock.can_primary_attack(), "Deagle is blocked through tick 22")
	clock.advance_tick()
	_check(clock.can_primary_attack(), "Deagle is ready exactly on tick 23")

	clock.reset("ak47")
	_check(clock.begin_empty_fire(), "empty primary attack starts its dry-fire gate")
	clock.advance_tick(19)
	_check(not clock.can_primary_attack(), "empty primary remains blocked through tick 19")
	clock.advance_tick()
	_check(clock.can_primary_attack(), "empty primary recovers exactly on tick 20")

	clock.reset("knife")
	_check(clock.begin_primary_attack(false), "knife miss starts its recovery")
	_check(clock.next_primary_tick == 35, "knife miss uses 0.35 second recovery")
	clock.reset("knife")
	_check(clock.begin_primary_attack(true), "knife hit starts its recovery")
	_check(clock.next_primary_tick == 40, "knife hit uses 0.4 second recovery")

	clock.reset("ak47")
	_check(clock.begin_reload(), "AK reload starts when ready")
	var events := clock.advance_tick(244)
	_check(not events.has(WeaponClock.EVENT_RELOAD_COMPLETE), "AK reload is incomplete at tick 244")
	events = clock.advance_tick()
	_check(events.has(WeaponClock.EVENT_RELOAD_COMPLETE), "AK reload completes exactly at tick 245")
	_check(clock.state == WeaponClock.STATE_READY, "reload completion returns clock to ready")


func _test_deploy_idle_and_grenade_states() -> void:
	var clock := WeaponClock.new()
	clock.reset("deagle", 0, true)
	_check(not clock.can_primary_attack(), "deploy blocks primary attack")
	var events := clock.advance_tick(74)
	_check(not events.has(WeaponClock.EVENT_DEPLOY_COMPLETE), "deploy remains active through tick 74")
	events = clock.advance_tick()
	_check(events.has(WeaponClock.EVENT_DEPLOY_COMPLETE), "deploy completes on tick 75")
	_check(clock.can_primary_attack(), "weapon can fire after deploy completes")
	events = clock.advance_tick(75)
	_check(events.has(WeaponClock.EVENT_WEAPON_IDLE), "default deploy idle occurs at tick 150")

	clock.reset("hegrenade")
	_check(clock.begin_primary_attack(), "HE primary pulls the pin")
	_check(clock.state == WeaponClock.STATE_GRENADE_PINNED, "HE remains pinned while fire is held")
	clock.advance_tick(20)
	clock.release_grenade(true)
	_check(
		not clock.take_events().has(WeaponClock.EVENT_GRENADE_THROW),
		"early HE release waits for the 0.5 second pin animation",
	)
	events = clock.advance_tick(29)
	_check(not events.has(WeaponClock.EVENT_GRENADE_THROW), "HE is not thrown at tick 49")
	events = clock.advance_tick()
	_check(events.has(WeaponClock.EVENT_GRENADE_THROW), "HE is thrown exactly at tick 50")
	_check(clock.state == WeaponClock.STATE_GRENADE_THROWING, "HE enters post-throw state")
	events = clock.advance_tick(50)
	_check(events.has(WeaponClock.EVENT_GRENADE_RETIRE), "empty HE retires 0.5 seconds after throw")

	clock.reset("hegrenade")
	_check(clock.begin_grenade_pin(), "HE can begin another deterministic pin state")
	clock.advance_tick(80)
	_check(clock.state == WeaponClock.STATE_GRENADE_PINNED, "holding fire keeps the HE pinned indefinitely")
	clock.release_grenade(true)
	_check(
		clock.take_events().has(WeaponClock.EVENT_GRENADE_THROW),
		"release after pin-ready throws immediately on the current tick",
	)


func _run_auto_fire_tape(render_delta: float, duration_ticks: int) -> Array[int]:
	var clock := WeaponClock.new()
	clock.reset("ak47")
	var accumulator := 0.0
	var shots: Array[int] = []
	while clock.tick < duration_ticks:
		accumulator += render_delta
		while accumulator + 0.000000001 >= WeaponClock.TICK_SECONDS and clock.tick < duration_ticks:
			accumulator -= WeaponClock.TICK_SECONDS
			if clock.begin_primary_attack():
				shots.append(clock.tick)
			clock.advance_tick()
	return shots


func _test_render_rate_independent_tapes() -> void:
	var tape_30 := _run_auto_fire_tape(1.0 / 30.0, 100)
	var tape_60 := _run_auto_fire_tape(1.0 / 60.0, 100)
	var tape_144 := _run_auto_fire_tape(1.0 / 144.0, 100)
	_check(tape_30 == tape_60, "AK cadence tape is identical at 30 and 60 render fps")
	_check(tape_60 == tape_144, "AK cadence tape is identical at 60 and 144 render fps")
	_check(
		tape_30 == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90],
		"AK held-fire tape uses exact 10-tick cadence",
	)


func _run_recoil_tape(render_delta: float, duration_ticks: int) -> Vector2:
	var accumulator := 0.0
	var simulated_ticks := 0
	var punch := Vector2(-5.75, 1.75)
	while simulated_ticks < duration_ticks:
		accumulator += render_delta
		while accumulator + 0.000000001 >= WeaponClock.TICK_SECONDS and simulated_ticks < duration_ticks:
			accumulator -= WeaponClock.TICK_SECONDS
			punch = WeaponClock.punch_decay_tick(punch)
			simulated_ticks += 1
	return punch


func _test_recoil_tape() -> void:
	var recoil_30 := _run_recoil_tape(1.0 / 30.0, 30)
	var recoil_144 := _run_recoil_tape(1.0 / 144.0, 30)
	_near(recoil_30.x, recoil_144.x, 0.000001, "recoil X decay is render-rate independent")
	_near(recoil_30.y, recoil_144.y, 0.000001, "recoil Y decay is render-rate independent")
	_check(recoil_30.length() < Vector2(-5.75, 1.75).length(), "PM_DropPunchAngle reduces recoil")
