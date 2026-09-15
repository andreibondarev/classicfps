class_name CS16WeaponClock
extends RefCounted

const WeaponRegistry := preload("res://scripts/cs16_weapon_registry.gd")

## Deterministic Counter-Strike 1.6 weapon timer state.
##
## This clock advances only in explicit 100 Hz simulation ticks. It never
## reads wall time and never schedules SceneTree timers.
##
## Source parity:
## - ReGameDLL_CS weapons.cpp: DefaultDeploy, DefaultReload,
##   DefaultShotgunReload, ItemPostFrame
## - ReGameDLL_CS wpn_ak47.cpp: fire/reload/idle timing
## - ReGameDLL_CS wpn_deagle.cpp: fire/reload/idle timing
## - ReGameDLL_CS wpn_knife.cpp: swing/idle timing
## - ReGameDLL_CS wpn_hegrenade.cpp: pin, release, throw and retire timing
## - ReGameDLL_CS pm_shared.cpp: PM_DropPunchAngle

const TICK_RATE_HZ := 100
const TICK_SECONDS := 1.0 / float(TICK_RATE_HZ)
const NEVER := -1

const STATE_READY := "ready"
const STATE_DEPLOYING := "deploying"
const STATE_FIRING := "firing"
const STATE_RELOADING := "reloading"
const STATE_GRENADE_PINNED := "grenade_pinned"
const STATE_GRENADE_THROWING := "grenade_throwing"

const EVENT_DEPLOY_COMPLETE := "deploy_complete"
const EVENT_RELOAD_COMPLETE := "reload_complete"
const EVENT_RELOAD_SHELL := "reload_shell"
const EVENT_WEAPON_IDLE := "weapon_idle"
const EVENT_GRENADE_THROW := "grenade_throw"
const EVENT_GRENADE_RETIRE := "grenade_retire"

const DEFAULT_DEPLOY_SECONDS := 0.75
const DEFAULT_DEPLOY_IDLE_SECONDS := 1.5
const EMPTY_FIRE_SECONDS := 0.2
const MUZZLE_FLASH_SECONDS := 0.035
# CM3/CXM1014::WeaponIdle plays the pump animation once the shell loop stops
# and pushes the next idle out by 1.5 seconds.
const SHELL_RELOAD_PUMP_SECONDS := 1.5
const TRACER_SECONDS := 0.055
const IMPACT_SECONDS := 1.4

const TIMINGS := {
	"ak47": {
		# AK47Fire(..., 0.0955, ...).
		"primary_seconds": 0.0955,
		"reload_seconds": 2.45,
		"fire_idle_seconds": 1.9,
		"idle_repeat_seconds": 20.0,
	},
	"deagle": {
		# DEAGLEFire receives 0.3 then subtracts 0.075.
		"primary_seconds": 0.225,
		"reload_seconds": 2.2,
		"fire_idle_seconds": 1.8,
		"idle_repeat_seconds": 3.0625,
	},
	"knife": {
		"primary_miss_seconds": 0.35,
		"primary_hit_seconds": 0.4,
		"fire_idle_seconds": 2.0,
		"idle_repeat_seconds": 20.0,
	},
	"hegrenade": {
		"pin_seconds": 0.5,
		"post_throw_attack_seconds": 0.5,
		"post_throw_idle_seconds": 0.75,
		# Empty HE retires when its post-throw primary/idle timer expires.
		"retire_seconds": 0.5,
		# Original idle is random [10, 15]; deterministic state uses the floor
		# until shared prediction supplies an idle RNG stream.
		"idle_repeat_seconds": 10.0,
	},
}

var tick := 0
var active_weapon := "ak47"
var state := STATE_READY
var next_primary_tick := 0
var next_secondary_tick := 0
var reload_complete_tick := NEVER
var reload_shell_tick := NEVER
var shells_inserted := 0
var weapon_idle_tick := NEVER
var deploy_complete_tick := NEVER
var grenade_pin_ready_tick := NEVER
var grenade_retire_tick := NEVER
var _grenade_released := false
var _grenade_last := true
var _shell_reload := false
var _reload_insert_ticks := 0
var _events: Array[String] = []


static func ticks_from_seconds(seconds: float) -> int:
	if seconds <= 0.0:
		return 0
	# Weapon timers are observed on the next 100 Hz simulation boundary.
	return int(ceil(seconds * float(TICK_RATE_HZ) - 0.000001))


static func seconds_from_ticks(ticks: int) -> float:
	return float(ticks) * TICK_SECONDS


static func timing(weapon_name: String) -> Dictionary:
	var registry_timing := WeaponRegistry.timing(weapon_name)
	if not registry_timing.is_empty():
		return registry_timing
	if not TIMINGS.has(weapon_name):
		return {}
	return (TIMINGS[weapon_name] as Dictionary).duplicate(true)


static func punch_decay_tick(punch_degrees: Vector2) -> Vector2:
	var length := punch_degrees.length()
	if length <= 0.00001:
		return Vector2.ZERO
	var next_length := maxf(
		0.0,
		length - (10.0 + length * 0.5) * TICK_SECONDS,
	)
	return punch_degrees * (next_length / length)


func reset(weapon_name := "ak47", initial_tick := 0, deploy := false) -> void:
	tick = maxi(initial_tick, 0)
	active_weapon = weapon_name
	state = STATE_READY
	next_primary_tick = tick
	next_secondary_tick = tick
	reload_complete_tick = NEVER
	weapon_idle_tick = NEVER
	deploy_complete_tick = NEVER
	grenade_pin_ready_tick = NEVER
	grenade_retire_tick = NEVER
	_grenade_released = false
	_grenade_last = true
	_clear_shell_reload()
	_events.clear()
	if deploy:
		begin_deploy(weapon_name)


func begin_deploy(weapon_name: String) -> void:
	active_weapon = weapon_name
	state = STATE_DEPLOYING
	reload_complete_tick = NEVER
	_clear_shell_reload()
	grenade_pin_ready_tick = NEVER
	grenade_retire_tick = NEVER
	_grenade_released = false
	deploy_complete_tick = tick + ticks_from_seconds(DEFAULT_DEPLOY_SECONDS)
	next_primary_tick = deploy_complete_tick
	next_secondary_tick = deploy_complete_tick
	weapon_idle_tick = tick + ticks_from_seconds(DEFAULT_DEPLOY_IDLE_SECONDS)


func can_primary_attack() -> bool:
	return (
		tick >= next_primary_tick
		and state != STATE_DEPLOYING
		and state != STATE_RELOADING
		and state != STATE_GRENADE_PINNED
		and state != STATE_GRENADE_THROWING
	)


func can_secondary_attack() -> bool:
	return can_primary_attack() and tick >= next_secondary_tick


func begin_primary_attack(hit := false) -> bool:
	if active_weapon == "knife":
		return begin_knife_attack(false, hit)
	if not can_primary_attack():
		return false
	if active_weapon in ["hegrenade", "flashbang", "smokegrenade"]:
		return begin_grenade_pin()
	var profile := timing(active_weapon)
	if profile.is_empty():
		return false
	var cycle_seconds := float(profile.get("primary_seconds", 0.0))
	next_primary_tick = tick + ticks_from_seconds(cycle_seconds)
	next_secondary_tick = next_primary_tick
	weapon_idle_tick = tick + ticks_from_seconds(float(profile.fire_idle_seconds))
	state = STATE_FIRING
	return true


func begin_knife_attack(stab: bool, hit: bool) -> bool:
	if active_weapon != "knife" or not can_primary_attack() or (stab and not can_secondary_attack()):
		return false
	# CKnife::Swing / Stab: slash-to-stab recovery differs from repeat slash.
	var recovery := (1.1 if hit else 1.0) if stab else (0.4 if hit else 0.35)
	next_primary_tick = tick + ticks_from_seconds(recovery)
	next_secondary_tick = next_primary_tick if stab else tick + ticks_from_seconds(0.5)
	weapon_idle_tick = tick + ticks_from_seconds(2.0)
	state = STATE_FIRING
	return true


func begin_empty_fire() -> bool:
	if not can_primary_attack():
		return false
	next_primary_tick = tick + ticks_from_seconds(EMPTY_FIRE_SECONDS)
	state = STATE_FIRING
	return true


func begin_reload() -> bool:
	if not can_primary_attack():
		return false
	var profile := timing(active_weapon)
	var reload_seconds := float(profile.get("reload_seconds", 0.0))
	if reload_seconds <= 0.0:
		return false
	var insert_seconds := float(profile.get("reload_insert_seconds", 0.0))
	state = STATE_RELOADING
	if insert_seconds > 0.0:
		# DefaultShotgunReload: `reload_seconds` is only the start delay that
		# moves the gun aside. Every shell after it costs one insert interval
		# and enters the clip on its own, so the loop can be aborted by firing.
		_shell_reload = true
		shells_inserted = 0
		_reload_insert_ticks = ticks_from_seconds(insert_seconds)
		reload_complete_tick = NEVER
		next_primary_tick = tick + ticks_from_seconds(reload_seconds)
		reload_shell_tick = next_primary_tick + _reload_insert_ticks
		weapon_idle_tick = NEVER
		return true
	reload_complete_tick = tick + ticks_from_seconds(reload_seconds)
	weapon_idle_tick = reload_complete_tick + ticks_from_seconds(0.5)
	return true


func is_shell_reloading() -> bool:
	return _shell_reload


## 1.6 lets a shotgun fire out of its shell loop once a shell is seated; the
## weapon only holds the player still through the initial start delay.
func can_interrupt_reload() -> bool:
	return _shell_reload and shells_inserted > 0


## Ends the shell loop when the magazine is full or the reserve runs dry.
func finish_shell_reload() -> void:
	if not _shell_reload:
		return
	_clear_shell_reload()
	if state == STATE_RELOADING:
		state = STATE_READY
	weapon_idle_tick = tick + ticks_from_seconds(SHELL_RELOAD_PUMP_SECONDS)


func cancel_reload() -> void:
	reload_complete_tick = NEVER
	_clear_shell_reload()
	if state == STATE_RELOADING:
		state = STATE_READY


func _clear_shell_reload() -> void:
	_shell_reload = false
	_reload_insert_ticks = 0
	reload_shell_tick = NEVER
	shells_inserted = 0


func begin_grenade_pin() -> bool:
	if active_weapon not in ["hegrenade", "flashbang", "smokegrenade"] or not can_primary_attack():
		return false
	state = STATE_GRENADE_PINNED
	_grenade_released = false
	grenade_pin_ready_tick = (
		tick
		+ ticks_from_seconds(float(timing(active_weapon).pin_seconds))
	)
	weapon_idle_tick = grenade_pin_ready_tick
	return true


func release_grenade(last_grenade := true) -> void:
	if state != STATE_GRENADE_PINNED:
		return
	_grenade_released = true
	_grenade_last = last_grenade
	_throw_released_grenade_if_ready()


func advance_tick(count := 1) -> Array[String]:
	for step in range(maxi(count, 0)):
		tick += 1
		_process_due_events()
	return take_events()


func take_events() -> Array[String]:
	var result := _events.duplicate()
	_events.clear()
	return result


func _process_due_events() -> void:
	if deploy_complete_tick != NEVER and tick >= deploy_complete_tick:
		deploy_complete_tick = NEVER
		if state == STATE_DEPLOYING:
			state = STATE_READY
		_events.append(EVENT_DEPLOY_COMPLETE)

	if reload_complete_tick != NEVER and tick >= reload_complete_tick:
		reload_complete_tick = NEVER
		if state == STATE_RELOADING:
			state = STATE_READY
			_events.append(EVENT_RELOAD_COMPLETE)

	if (
		reload_shell_tick != NEVER
		and tick >= reload_shell_tick
		and state == STATE_RELOADING
	):
		reload_shell_tick = tick + _reload_insert_ticks
		shells_inserted += 1
		_events.append(EVENT_RELOAD_SHELL)

	if state == STATE_FIRING and tick >= next_primary_tick:
		state = STATE_READY

	_throw_released_grenade_if_ready()

	if grenade_retire_tick != NEVER and tick >= grenade_retire_tick:
		grenade_retire_tick = NEVER
		if state == STATE_GRENADE_THROWING:
			state = STATE_READY
		_events.append(EVENT_GRENADE_RETIRE)

	if (
		weapon_idle_tick != NEVER
		and tick >= weapon_idle_tick
		and state != STATE_RELOADING
		and state != STATE_GRENADE_PINNED
	):
		_events.append(EVENT_WEAPON_IDLE)
		var profile := timing(active_weapon)
		weapon_idle_tick = (
			tick
			+ ticks_from_seconds(float(profile.get("idle_repeat_seconds", 20.0)))
		)


func _throw_released_grenade_if_ready() -> void:
	if (
		state != STATE_GRENADE_PINNED
		or not _grenade_released
		or tick < grenade_pin_ready_tick
	):
		return
	state = STATE_GRENADE_THROWING
	grenade_pin_ready_tick = NEVER
	_events.append(EVENT_GRENADE_THROW)
	next_primary_tick = (
		tick
		+ ticks_from_seconds(float(timing(active_weapon).post_throw_attack_seconds))
	)
	weapon_idle_tick = (
		tick
		+ ticks_from_seconds(
			float(
				timing(active_weapon).retire_seconds
				if _grenade_last
				else timing(active_weapon).post_throw_idle_seconds
			)
		)
	)
	if _grenade_last:
		grenade_retire_tick = (
			tick
			+ ticks_from_seconds(float(timing(active_weapon).retire_seconds))
		)
