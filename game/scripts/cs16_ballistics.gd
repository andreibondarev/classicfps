class_name CS16Ballistics
extends RefCounted

## Counter-Strike 1.6 ballistics constants and deterministic pure helpers.
##
## Source parity:
## - ReGameDLL_CS cbase.cpp: CBaseEntity::FireBullets3
## - ReGameDLL_CS player.cpp: CBasePlayer::TraceAttack/TakeDamage/IsArmored
## - ReGameDLL_CS util.cpp: UTIL_SharedRandomFloat
## - ReGameDLL_CS wpn_hegrenade.cpp and ggrenade.cpp
##
## Distances exposed by this class are Godot metres unless the name explicitly
## ends in `_units`. The converted BSP uses 0.01 m per GoldSrc unit.

const METERS_PER_GOLDSRC_UNIT := 0.01
const RANGE_DAMAGE_INTERVAL_UNITS := 500.0
const RANGE_DAMAGE_INTERVAL_METERS := RANGE_DAMAGE_INTERVAL_UNITS * METERS_PER_GOLDSRC_UNIT

const ARMOR_RATIO := 0.5
const ARMOR_BONUS := 0.5

const BULLET_9MM := "9mm"
const BULLET_45ACP := "45acp"
const BULLET_50AE := "50ae"
const BULLET_762MM := "762mm"
const BULLET_556MM := "556mm"
const BULLET_338MAG := "338mag"
const BULLET_57MM := "57mm"
const BULLET_357SIG := "357sig"

const SURFACE_DEFAULT := "default"
const SURFACE_METAL := "metal"
const SURFACE_CONCRETE := "concrete"
const SURFACE_GRATE := "grate"
const SURFACE_VENT := "vent"
const SURFACE_TILE := "tile"
const SURFACE_COMPUTER := "computer"
const SURFACE_WOOD := "wood"

const HE_FUSE_SECONDS := 1.5
const HE_BASE_DAMAGE := 100.0
const HE_RADIUS_UNITS := 350.0
const HE_RADIUS_METERS := HE_RADIUS_UNITS * METERS_PER_GOLDSRC_UNIT
const HE_DAMAGE_ORIGIN_LIFT_UNITS := 1.0
const HE_DAMAGE_ORIGIN_LIFT_METERS := (
	HE_DAMAGE_ORIGIN_LIFT_UNITS * METERS_PER_GOLDSRC_UNIT
)
const HE_GRAVITY_MULTIPLIER := 0.55
const GOLDSRC_DEFAULT_GRAVITY_UNITS := 800.0
const HE_GRAVITY_METERS_PER_SECOND_SQUARED := (
	GOLDSRC_DEFAULT_GRAVITY_UNITS
	* METERS_PER_GOLDSRC_UNIT
	* HE_GRAVITY_MULTIPLIER
)
const HE_FRICTION := 0.7
const HE_BOUNCE_OVERBOUNCE := 2.0 - HE_FRICTION
const HE_GROUND_VELOCITY_RETENTION := 0.8
const HE_STOP_SPEED_UNITS := 30.0
const HE_STOP_SPEED_METERS := HE_STOP_SPEED_UNITS * METERS_PER_GOLDSRC_UNIT
const GOLDSRC_STOP_EPSILON_UNITS := 0.1
const GOLDSRC_STOP_EPSILON_METERS := (
	GOLDSRC_STOP_EPSILON_UNITS * METERS_PER_GOLDSRC_UNIT
)
const HE_MAX_THROW_SPEED_UNITS := 750.0
const HE_MAX_THROW_SPEED_METERS := HE_MAX_THROW_SPEED_UNITS * METERS_PER_GOLDSRC_UNIT
const HE_MUZZLE_OFFSET_UNITS := 16.0
const HE_MUZZLE_OFFSET_METERS := HE_MUZZLE_OFFSET_UNITS * METERS_PER_GOLDSRC_UNIT

enum HitGroup {
	GENERIC,
	HEAD,
	CHEST,
	STOMACH,
	LEFT_ARM,
	RIGHT_ARM,
	LEFT_LEG,
	RIGHT_LEG,
	SHIELD,
}

enum ArmorType {
	NONE,
	KEVLAR,
	VEST_HELMET,
}

const WEAPON_PROFILES := {
	"ak47": {
		"base_damage": 36,
		"range_modifier": 0.98,
		"penetrations": 2,
		"range_units": 8192.0,
		"range_meters": 81.92,
		"bullet_type": BULLET_762MM,
		"armor_ratio_multiplier": 1.55,
	},
	"deagle": {
		"base_damage": 54,
		"range_modifier": 0.81,
		"penetrations": 2,
		"range_units": 4096.0,
		"range_meters": 40.96,
		"bullet_type": BULLET_50AE,
		"armor_ratio_multiplier": 1.5,
	},
}

const BULLET_PROFILES := {
	BULLET_9MM: {"penetration_power_units": 21, "penetration_distance_units": 800.0},
	BULLET_45ACP: {"penetration_power_units": 15, "penetration_distance_units": 500.0},
	BULLET_50AE: {"penetration_power_units": 30, "penetration_distance_units": 1000.0},
	BULLET_762MM: {"penetration_power_units": 39, "penetration_distance_units": 5000.0},
	BULLET_556MM: {"penetration_power_units": 35, "penetration_distance_units": 4000.0},
	BULLET_338MAG: {"penetration_power_units": 45, "penetration_distance_units": 8000.0},
	BULLET_57MM: {"penetration_power_units": 30, "penetration_distance_units": 2000.0},
	BULLET_357SIG: {"penetration_power_units": 25, "penetration_distance_units": 800.0},
}

const _SEED_TABLE := [
	28985, 27138, 26457, 9451, 17764, 10909, 28790, 8716,
	6361, 4853, 17798, 21977, 19643, 20662, 10834, 20103,
	27067, 28634, 18623, 25849, 8576, 26234, 23887, 18228,
	32587, 4836, 3306, 1811, 3035, 24559, 18399, 315,
	26766, 907, 24102, 12370, 9674, 2972, 10472, 16492,
	22683, 11529, 27968, 30406, 13213, 2319, 23620, 16823,
	10013, 23772, 21567, 1251, 19579, 20313, 18241, 30130,
	8402, 20807, 27354, 7169, 21211, 17293, 5410, 19223,
	10255, 22480, 27388, 9946, 15628, 24389, 17308, 2370,
	9530, 31683, 25927, 23567, 11694, 26397, 32602, 15031,
	18255, 17582, 1422, 28835, 23607, 12597, 20602, 10138,
	5212, 1252, 10074, 23166, 19823, 31667, 5902, 24630,
	18948, 14330, 14950, 8939, 23540, 21311, 22428, 22391,
	3583, 29004, 30498, 18714, 4278, 2437, 22430, 3439,
	28313, 23161, 25396, 13471, 19324, 15287, 2563, 18901,
	13103, 16867, 9714, 14322, 15197, 26889, 19372, 26241,
	31925, 14640, 11497, 8941, 10056, 6451, 28656, 10737,
	13874, 17356, 8281, 25937, 1661, 4850, 7448, 12744,
	21826, 5477, 10167, 16705, 26897, 8839, 30947, 27978,
	27283, 24685, 32298, 3525, 12398, 28726, 9475, 10208,
	617, 13467, 22287, 2376, 6097, 26312, 2974, 9114,
	21787, 28010, 4725, 15387, 3274, 10762, 31695, 17320,
	18324, 12441, 16801, 27376, 22464, 7500, 5666, 18144,
	15314, 31914, 31627, 6495, 5226, 31203, 2331, 4668,
	12650, 18275, 351, 7268, 31319, 30119, 7600, 2905,
	13826, 11343, 13053, 15583, 30055, 31093, 5067, 761,
	9685, 11070, 21369, 27155, 3663, 26542, 20169, 12161,
	15411, 30401, 7580, 31784, 8985, 29367, 20989, 14203,
	29694, 21167, 10337, 1706, 28578, 887, 3373, 19477,
	14382, 675, 7033, 15111, 26138, 12252, 30996, 21409,
	25678, 18555, 13256, 23316, 22407, 16727, 991, 9236,
	5373, 29402, 6117, 15241, 27715, 19291, 19888, 19847,
]


static func weapon_profile(weapon_name: String) -> Dictionary:
	var normalized := weapon_name.to_lower()
	if not WEAPON_PROFILES.has(normalized):
		return {}
	return (WEAPON_PROFILES[normalized] as Dictionary).duplicate(true)


static func bullet_profile(bullet_type: String) -> Dictionary:
	if not BULLET_PROFILES.has(bullet_type):
		return {
			"penetration_power_units": 0,
			"penetration_power_meters": 0.0,
			"penetration_distance_units": 0.0,
			"penetration_distance_meters": 0.0,
		}
	var profile := (BULLET_PROFILES[bullet_type] as Dictionary).duplicate(true)
	profile.penetration_power_meters = (
		float(profile.penetration_power_units) * METERS_PER_GOLDSRC_UNIT
	)
	profile.penetration_distance_meters = (
		float(profile.penetration_distance_units) * METERS_PER_GOLDSRC_UNIT
	)
	return profile


## FireBullets3 truncates back into its integer damage accumulator after each
## range segment. Keep that truncation here; rounding produces different kills.
static func range_damage(
	base_damage: int,
	range_modifier: float,
	distance_meters: float,
) -> int:
	if base_damage <= 0:
		return 0
	var exponent := maxf(distance_meters, 0.0) / RANGE_DAMAGE_INTERVAL_METERS
	return int(float(base_damage) * pow(range_modifier, exponent))


static func hitgroup_multiplier(hit_group: HitGroup) -> float:
	match hit_group:
		HitGroup.HEAD:
			return 4.0
		HitGroup.STOMACH:
			return 1.25
		HitGroup.LEFT_LEG, HitGroup.RIGHT_LEG:
			return 0.75
		_:
			return 1.0


## TraceAttack applies hit location before TakeDamage applies armor.
static func hitgroup_damage(damage_after_range: float, hit_group: HitGroup) -> float:
	return damage_after_range * hitgroup_multiplier(hit_group)


static func is_hitgroup_armored(hit_group: HitGroup, armor_type: ArmorType) -> bool:
	if armor_type == ArmorType.NONE:
		return false
	match hit_group:
		HitGroup.HEAD:
			return armor_type == ArmorType.VEST_HELMET
		HitGroup.GENERIC, HitGroup.CHEST, HitGroup.STOMACH, HitGroup.LEFT_ARM, HitGroup.RIGHT_ARM:
			return true
		_:
			return false


static func weapon_armor_ratio(weapon_name: String) -> float:
	var profile := weapon_profile(weapon_name)
	if profile.is_empty():
		return ARMOR_RATIO
	return ARMOR_RATIO * float(profile.armor_ratio_multiplier)


## Applies the regular bullet branch of CBasePlayer::TakeDamage. The returned
## float mirrors the pre-integer health damage; `health_damage` mirrors the
## critical final C++ int cast.
static func apply_bullet_armor(
	hitgroup_adjusted_damage: float,
	armor_points: float,
	hit_group: HitGroup,
	armor_type: ArmorType,
	weapon_name: String,
) -> Dictionary:
	var result := {
		"health_damage_float": maxf(hitgroup_adjusted_damage, 0.0),
		"health_damage": int(maxf(hitgroup_adjusted_damage, 0.0)),
		"armor_damage": 0.0,
		"armor_remaining": maxf(armor_points, 0.0),
		"armored": false,
	}
	if (
		hitgroup_adjusted_damage <= 0.0
		or armor_points <= 0.0
		or not is_hitgroup_armored(hit_group, armor_type)
	):
		return result

	var health_damage := weapon_armor_ratio(weapon_name) * hitgroup_adjusted_damage
	var armor_cost := (hitgroup_adjusted_damage - health_damage) * ARMOR_BONUS
	var remaining_armor := armor_points
	if armor_cost > armor_points:
		armor_cost = armor_points
		health_damage = hitgroup_adjusted_damage - armor_cost / ARMOR_BONUS
		remaining_armor = 0.0
	else:
		remaining_armor -= armor_cost

	result.health_damage_float = health_damage
	result.health_damage = int(health_damage)
	result.armor_damage = armor_cost
	result.armor_remaining = remaining_armor
	result.armored = true
	return result


static func resolve_bullet_damage(
	damage_after_range: int,
	hit_group: HitGroup,
	armor_points: float,
	armor_type: ArmorType,
	weapon_name: String,
) -> Dictionary:
	var located_damage := hitgroup_damage(float(damage_after_range), hit_group)
	var result := apply_bullet_armor(
		located_damage,
		armor_points,
		hit_group,
		armor_type,
		weapon_name,
	)
	result.range_damage = damage_after_range
	result.hitgroup_damage = located_damage
	return result


## Returns the state after one FireBullets3 impact. This deliberately exposes
## both damage at this hit and damage carried into the next trace.
static func penetration_step(
	current_damage: int,
	range_modifier: float,
	traveled_distance_meters: float,
	bullet_type: String,
	surface_type: String,
	is_world_surface: bool,
	penetrations_before_hit: int,
	penetration_power_units := -1,
	current_damage_modifier := 0.5,
) -> Dictionary:
	var profile := bullet_profile(bullet_type)
	var power := (
		int(profile.penetration_power_units)
		if penetration_power_units < 0
		else penetration_power_units
	)
	var damage_at_hit := range_damage(current_damage, range_modifier, traveled_distance_meters)
	var response := _surface_penetration_response(
		surface_type,
		power,
		current_damage_modifier,
	)
	power = int(response.penetration_power_units)
	var damage_modifier := float(response.damage_modifier)
	var penetrations_remaining := maxi(penetrations_before_hit - 1, 0)
	var can_continue := (
		penetrations_remaining > 0
		and traveled_distance_meters <= float(profile.penetration_distance_meters)
	)
	var remaining_distance_scale := 0.5

	# FireBullets3 treats entities, or the final allowed hit, as a shallow
	# 42-unit continuation with a 0.75 damage/distance modifier.
	if not is_world_surface or penetrations_remaining == 0:
		power = 42
		damage_modifier = 0.75
		remaining_distance_scale = 0.75

	return {
		"damage_at_hit": damage_at_hit,
		"next_damage": int(float(damage_at_hit) * damage_modifier),
		"penetration_power_units": power,
		"penetration_power_meters": float(power) * METERS_PER_GOLDSRC_UNIT,
		"damage_modifier": damage_modifier,
		"remaining_distance_scale": remaining_distance_scale,
		"penetrations_remaining": penetrations_remaining,
		"can_continue": can_continue,
	}


static func _surface_penetration_response(
	surface_type: String,
	penetration_power_units: int,
	current_damage_modifier: float,
) -> Dictionary:
	var power := penetration_power_units
	var damage_modifier := current_damage_modifier
	match surface_type:
		SURFACE_METAL:
			power = int(float(power) * 0.15)
			damage_modifier = 0.2
		SURFACE_CONCRETE:
			power = int(float(power) * 0.25)
		SURFACE_GRATE:
			power = int(float(power) * 0.5)
			damage_modifier = 0.4
		SURFACE_VENT:
			power = int(float(power) * 0.5)
			damage_modifier = 0.45
		SURFACE_TILE:
			power = int(float(power) * 0.65)
			damage_modifier = 0.3
		SURFACE_COMPUTER:
			power = int(float(power) * 0.4)
			damage_modifier = 0.45
		SURFACE_WOOD:
			damage_modifier = 0.6
	return {
		"penetration_power_units": power,
		"damage_modifier": damage_modifier,
	}


## Exact GoldSrc client/server shared random float, including float32 bit
## seeding and uint32 overflow.
static func shared_random_float(seed: int, low: float, high: float) -> float:
	var low_bits := PackedFloat32Array([low]).to_byte_array().decode_u32(0)
	var high_bits := PackedFloat32Array([high]).to_byte_array().decode_u32(0)
	var state := int(_SEED_TABLE[(seed + low_bits + high_bits) & 0xff])
	var random_result := _u_random(state)
	state = int(random_result[0])
	random_result = _u_random(state)
	state = int(random_result[0])
	random_result = _u_random(state)

	# ReGameDLL declares this as unsigned int, intentionally truncating the
	# float difference before applying the random fraction.
	var unsigned_range := int(high - low) & 0xffffffff
	if unsigned_range == 0:
		return low
	var fraction := float(int(random_result[1]) & 0xffff) / 65536.0
	return low + fraction * float(unsigned_range)


## FireBullets3 uses four adjacent shared seeds and does not perform the
## rejection loop used for non-player shooters.
static func spread_sample(shared_seed: int, spread: float) -> Vector2:
	var x := (
		shared_random_float(shared_seed, -0.5, 0.5)
		+ shared_random_float(shared_seed + 1, -0.5, 0.5)
	)
	var y := (
		shared_random_float(shared_seed + 2, -0.5, 0.5)
		+ shared_random_float(shared_seed + 3, -0.5, 0.5)
	)
	return Vector2(x, y) * spread


static func spread_direction(
	forward: Vector3,
	right: Vector3,
	up: Vector3,
	shared_seed: int,
	spread: float,
) -> Vector3:
	var offset := spread_sample(shared_seed, spread)
	# FireBullets3 traces this vector without normalizing it.
	return forward + right * offset.x + up * offset.y


static func _u_random(state: int) -> Array:
	var next_state := (
		state * 69069
		+ int(_SEED_TABLE[state & 0xff])
		+ 1
	) & 0xffffffff
	return [next_state, next_state & 0xfffffff]


static func remap_he_throw_pitch(view_pitch_degrees: float) -> float:
	if view_pitch_degrees < 0.0:
		return -10.0 + view_pitch_degrees * (80.0 / 90.0)
	return -10.0 + view_pitch_degrees * (100.0 / 90.0)


static func he_throw_speed_meters(view_pitch_degrees: float) -> float:
	var remapped_pitch := remap_he_throw_pitch(view_pitch_degrees)
	var speed_units := minf(
		(90.0 - remapped_pitch) * 6.0,
		HE_MAX_THROW_SPEED_UNITS,
	)
	return maxf(speed_units, 0.0) * METERS_PER_GOLDSRC_UNIT


## GoldSrc angles transformed to this project's coordinates: (x, z, -y).
static func he_throw_direction(view_pitch_degrees: float, view_yaw_degrees: float) -> Vector3:
	var pitch := deg_to_rad(remap_he_throw_pitch(view_pitch_degrees))
	var yaw := deg_to_rad(view_yaw_degrees)
	var horizontal := cos(pitch)
	return Vector3(
		horizontal * cos(yaw),
		-sin(pitch),
		-horizontal * sin(yaw),
	)


static func he_throw_velocity(
	view_pitch_degrees: float,
	view_yaw_degrees: float,
	player_velocity_meters_per_second := Vector3.ZERO,
) -> Vector3:
	return (
		he_throw_direction(view_pitch_degrees, view_yaw_degrees)
		* he_throw_speed_meters(view_pitch_degrees)
		+ player_velocity_meters_per_second
	)


static func he_throw_origin(
	eye_position: Vector3,
	view_pitch_degrees: float,
	view_yaw_degrees: float,
) -> Vector3:
	return (
		eye_position
		+ he_throw_direction(view_pitch_degrees, view_yaw_degrees) * HE_MUZZLE_OFFSET_METERS
	)


static func he_radius_damage(distance_meters: float) -> float:
	if distance_meters >= HE_RADIUS_METERS:
		return 0.0
	var falloff := HE_BASE_DAMAGE / HE_RADIUS_METERS
	return maxf(HE_BASE_DAMAGE - maxf(distance_meters, 0.0) * falloff, 0.0)


static func he_damage_origin(grenade_position: Vector3) -> Vector3:
	# RadiusDamage lifts a grenade lying on the ground by one GoldSrc unit.
	return grenade_position + Vector3.UP * HE_DAMAGE_ORIGIN_LIFT_METERS


## ReHLDS SV_Physics_Bounce calls SV_ClipVelocity with
## `overbounce = 2 - friction`. This is useful for deterministic prediction;
## the live RigidBody uses the equivalent 0.3 restitution.
static func he_bounce_velocity(velocity: Vector3, surface_normal: Vector3) -> Vector3:
	var normal := surface_normal.normalized()
	var result := velocity - normal * velocity.dot(normal) * HE_BOUNCE_OVERBOUNCE
	if absf(result.x) < GOLDSRC_STOP_EPSILON_METERS:
		result.x = 0.0
	if absf(result.y) < GOLDSRC_STOP_EPSILON_METERS:
		result.y = 0.0
	if absf(result.z) < GOLDSRC_STOP_EPSILON_METERS:
		result.z = 0.0
	return result


static func he_should_stop_after_ground_bounce(
	velocity: Vector3,
	surface_normal: Vector3,
) -> bool:
	return (
		surface_normal.y > 0.7
		and velocity.length_squared() < HE_STOP_SPEED_METERS * HE_STOP_SPEED_METERS
	)


## HE grenades use the explosion-specific armor branch in TakeDamage.
static func apply_explosion_armor(raw_damage: float, armor_points: float) -> Dictionary:
	var damage := maxf(raw_damage, 0.0)
	var armor := maxf(armor_points, 0.0)
	if damage <= 0.0 or armor <= 0.0:
		return {
			"health_damage_float": damage,
			"health_damage": int(damage),
			"armor_damage": 0.0,
			"armor_remaining": armor,
		}

	var health_damage := ARMOR_RATIO * damage
	var armor_cost := (damage - health_damage) * ARMOR_BONUS
	if armor_cost > armor:
		# This intentionally differs from the regular bullet branch.
		health_damage = damage - armor
		armor_cost = armor
		armor = 0.0
	else:
		armor -= armor_cost
	return {
		"health_damage_float": health_damage,
		"health_damage": int(health_damage),
		"armor_damage": armor_cost,
		"armor_remaining": armor,
	}
