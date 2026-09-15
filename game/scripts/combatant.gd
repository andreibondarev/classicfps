class_name Combatant
extends CharacterBody3D

const Ballistics := preload("res://scripts/cs16_ballistics.gd")

signal combatant_damaged(
	actor: Combatant,
	attacker: Combatant,
	remaining_health: int,
	headshot: bool,
)
signal combatant_eliminated(actor: Combatant, attacker: Combatant, headshot: bool)

const TEAM_TERRORIST := "T"
const TEAM_COUNTER_TERRORIST := "CT"
const TEAM_UNASSIGNED := "UNASSIGNED"
const GOLDSRC_UNIT := 0.01
const STANDING_VIEW_HEIGHT := 53.0 * GOLDSRC_UNIT
const STANDING_HEAD_HEIGHT := 57.0 * GOLDSRC_UNIT

var team := TEAM_UNASSIGNED
var display_name := ""
var health := 100
var armor := 0
var has_helmet := false
var alive := true
var network_read_only := false
# Authoritative vertical view angle used by first-person spectators. Player
# pawns update this from their camera, bots from their look target, and network
# replicas from the pitch carried in each world snapshot.
var spectator_view_pitch := 0.0
var spectator_crouched := false
# Flashbang blindness, expressed in physics frames so bots and the player
# share one clock. -1 = not blinded.
var flash_blind_until_frame := -1
var flash_blind_total_seconds := 0.0


func apply_flash_blind(duration_seconds: float) -> void:
	var until := Engine.get_physics_frames() + int(
		duration_seconds * Engine.physics_ticks_per_second
	)
	if until > flash_blind_until_frame:
		flash_blind_until_frame = until
		flash_blind_total_seconds = duration_seconds


func is_flash_blinded() -> bool:
	return int(Engine.get_physics_frames()) < flash_blind_until_frame
var combat_controller: CombatController
var last_command: Dictionary = {}
var last_damage_attacker: Combatant
var last_damage_weapon := ""
var last_damage_impact_audio := "player.pain"


func _ready() -> void:
	add_to_group("combatants")
	add_to_group("damageable")


func publish_combat_presentation(kind: String, data: Dictionary) -> void:
	if network_read_only:
		return
	var scene := get_tree().current_scene
	if is_instance_valid(scene) and scene.has_method("publish_combat_presentation"):
		scene.publish_combat_presentation(self, kind, data)


func configure_identity(new_team: String, new_display_name: String) -> void:
	team = new_team
	display_name = new_display_name


func is_opponent(other: Combatant) -> bool:
	return (
		is_instance_valid(other)
		and other != self
		and team != TEAM_UNASSIGNED
		and other.team != TEAM_UNASSIGNED
		and other.team != team
	)


func receive_damage(
	amount: float,
	hit_position := Vector3.ZERO,
	headshot := false,
	attacker: Combatant = null,
) -> bool:
	if network_read_only or not alive or amount <= 0.0:
		return false
	if is_instance_valid(attacker) and not is_opponent(attacker):
		return false
	last_damage_impact_audio = "player.pain"

	var remaining := int(round(amount))
	if armor > 0:
		var absorbed := mini(armor, int(round(remaining * 0.55)))
		armor -= absorbed
		remaining -= absorbed
	return _commit_damage(remaining, hit_position, headshot, attacker)


func receive_bullet_damage(
	damage_after_range: int,
	hit_group: int,
	weapon_name: String,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
) -> bool:
	if network_read_only or not alive or damage_after_range <= 0:
		return false
	if is_instance_valid(attacker) and not is_opponent(attacker):
		return false
	var armor_type := (
		Ballistics.ArmorType.VEST_HELMET
		if has_helmet
		else Ballistics.ArmorType.KEVLAR
		if armor > 0
		else Ballistics.ArmorType.NONE
	)
	if hit_group == Ballistics.HitGroup.HEAD and armor_type == Ballistics.ArmorType.VEST_HELMET:
		last_damage_impact_audio = "player.hit_helmet"
	elif armor > 0 and hit_group not in [Ballistics.HitGroup.HEAD, Ballistics.HitGroup.LEFT_LEG, Ballistics.HitGroup.RIGHT_LEG]:
		last_damage_impact_audio = "player.hit_kevlar"
	else:
		last_damage_impact_audio = "player.hit_flesh"
	var result := Ballistics.resolve_bullet_damage(
		damage_after_range,
		hit_group,
		float(armor),
		armor_type,
		weapon_name,
	)
	armor = maxi(0, int(float(result.armor_remaining)))
	return _commit_damage(
		int(result.health_damage),
		hit_position,
		hit_group == Ballistics.HitGroup.HEAD,
		attacker,
		weapon_name,
	)


## Ground-plane facing of this combatant. Player hulls and bot actors both aim
## with their body yaw, so -Z of the body basis is the 1.6 `v_forward`.
func facing_direction() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0000001:
		return Vector3.FORWARD
	return forward.normalized()


func spectator_view_transform() -> Transform3D:
	# PlayerController owns a real eye camera, including crouch height and recoil;
	# use it directly without coupling this base actor to the player script.
	var eye_camera := get_node_or_null("PlayerCamera") as Camera3D
	if is_instance_valid(eye_camera):
		return eye_camera.global_transform
	var eye_height := (
		30.0 * GOLDSRC_UNIT
		if is_crouching() or spectator_crouched
		else STANDING_VIEW_HEIGHT
	)
	var view_basis := Basis.from_euler(Vector3(
		clampf(spectator_view_pitch, deg_to_rad(-89.0), deg_to_rad(89.0)),
		global_rotation.y,
		0.0,
	))
	return Transform3D(view_basis, global_position + Vector3.UP * eye_height)


## Knife hits use TraceAttack with DMG_BULLET, so they share the bullet armor
## branch (and the knife's 1.7 armor ratio) plus hit-group scaling. Only the
## 1.6 backstab multiplier is knife-specific, and it is applied to the base
## damage before any armor math, exactly as CKnife::Stab does.
func receive_melee_damage(
	base_damage: int,
	hit_group: int,
	weapon_name: String,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
	backstab := false,
) -> bool:
	var damage := base_damage
	if backstab:
		damage = int(float(base_damage) * Ballistics.KNIFE_BACKSTAB_MULTIPLIER)
	return receive_bullet_damage(
		damage,
		hit_group,
		weapon_name,
		hit_position,
		attacker,
	)


func receive_explosion_damage(
	raw_damage: float,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
) -> bool:
	if network_read_only or not alive or raw_damage <= 0.0:
		return false
	if is_instance_valid(attacker) and not is_opponent(attacker):
		return false
	last_damage_impact_audio = "player.pain"
	var result := Ballistics.apply_explosion_armor(raw_damage, float(armor))
	armor = maxi(0, int(float(result.armor_remaining)))
	return _commit_damage(
		int(result.health_damage),
		hit_position,
		false,
		attacker,
		"hegrenade",
	)


func receive_c4_explosion_damage(
	raw_damage: float,
	hit_position := Vector3.ZERO,
	attacker: Combatant = null,
) -> bool:
	if network_read_only or not alive or raw_damage <= 0.0:
		return false
	last_damage_impact_audio = "player.pain"
	# C4 RadiusDamage is objective world damage: unlike bullets and grenades it
	# reaches the planter and teammates regardless of the normal ally filter.
	var result := Ballistics.apply_explosion_armor(raw_damage, float(armor))
	armor = maxi(0, int(float(result.armor_remaining)))
	return _commit_damage(
		int(result.health_damage),
		hit_position,
		false,
		attacker,
		"c4",
	)


func _commit_damage(
	health_damage: int,
	hit_position: Vector3,
	headshot: bool,
	attacker: Combatant,
	weapon_name := "",
) -> bool:
	last_damage_attacker = attacker if is_instance_valid(attacker) else null
	last_damage_weapon = weapon_name
	health = maxi(0, health - maxi(health_damage, 0))
	_on_combatant_damaged(attacker, hit_position, headshot)
	combatant_damaged.emit(self, attacker, health, headshot)
	if health <= 0:
		alive = false
		velocity = Vector3.ZERO
		_on_combatant_eliminated(attacker, headshot)
		combatant_eliminated.emit(self, attacker, headshot)
	return true


func reset_combatant(spawn_position: Vector3, starting_armor := 0) -> void:
	flash_blind_until_frame = -1
	health = 100
	armor = starting_armor
	if starting_armor <= 0:
		has_helmet = false
	alive = true
	last_command = {}
	last_damage_attacker = null
	last_damage_weapon = ""
	last_damage_impact_audio = "player.pain"
	velocity = Vector3.ZERO
	global_position = spawn_position
	_drop_spawn_to_floor()


func _drop_spawn_to_floor() -> void:
	## GoldSrc DispatchSpawn drops player entities to the floor (DROP_TO_FLOOR);
	## map spawn points sit a few units above ground. Without this, a combatant
	## that is frozen before its first physics tick renders hovering mid-air.
	## The engine drops the full 32 HU hull, not a point: probe the center and
	## four inset hull corners and rest on the highest walkable support so a
	## spawn beside sloped geometry cannot embed a hull corner in the floor
	## (Godot would then depenetrate the body upward on its first tick,
	## briefly launching it airborne).
	if not is_inside_tree():
		return
	var world := get_world_3d()
	if world == null:
		return
	var half_width := 16.0 * GOLDSRC_UNIT
	var inset := half_width - 0.001
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(inset, 0.0, inset),
		Vector3(inset, 0.0, -inset),
		Vector3(-inset, 0.0, inset),
		Vector3(-inset, 0.0, -inset),
	]
	var highest_floor_y := -INF
	for offset: Vector3 in offsets:
		var from := global_position + offset + Vector3.UP * 0.10
		var query := PhysicsRayQueryParameters3D.create(
			from,
			from + Vector3.DOWN * 1.30,
		)
		query.exclude = [get_rid()]
		var hit := world.direct_space_state.intersect_ray(query)
		if hit.is_empty() or float(hit.normal.y) < 0.7:
			continue
		highest_floor_y = maxf(highest_floor_y, float(hit.position.y))
	if highest_floor_y == -INF:
		return
	if highest_floor_y < global_position.y:
		global_position.y = highest_floor_y + 0.001


func is_dead() -> bool:
	return not alive


func aim_point() -> Vector3:
	return global_position + Vector3.UP * STANDING_VIEW_HEIGHT


func head_height() -> float:
	return global_position.y + (34.0 * GOLDSRC_UNIT if is_crouching() else STANDING_HEAD_HEIGHT)


func is_crouching() -> bool:
	return false


func hit_group_at(world_position: Vector3) -> int:
	# A posture-aware approximation, not bone-attached MDL hitboxes. Side labels
	# belong to the victim's body axes, never the world X axis.
	var local := to_local(world_position) / GOLDSRC_UNIT
	var head_hu := (head_height() - global_position.y) / GOLDSRC_UNIT
	if local.y >= head_hu:
		return Ballistics.HitGroup.HEAD
	var posture_scale := head_hu / 57.0
	if local.y < 30.0 * posture_scale:
		return Ballistics.HitGroup.LEFT_LEG if local.x < 0.0 else Ballistics.HitGroup.RIGHT_LEG
	if local.y < 42.0 * posture_scale:
		return Ballistics.HitGroup.STOMACH
	if absf(local.x) >= 11.0:
		return Ballistics.HitGroup.LEFT_ARM if local.x < 0.0 else Ballistics.HitGroup.RIGHT_ARM
	return Ballistics.HitGroup.CHEST


func _on_combatant_damaged(
	_attacker: Combatant,
	_hit_position: Vector3,
	_headshot: bool,
) -> void:
	pass


func _on_combatant_eliminated(_attacker: Combatant, _headshot: bool) -> void:
	pass
