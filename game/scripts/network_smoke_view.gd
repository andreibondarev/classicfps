extends "res://scripts/cs16_combat_effects.gd"

## Visual-only cloud, reconstructible from any complete host snapshot.
var _origins: Dictionary = {}

func configure(position: Vector3, seed: int, age_seconds: float) -> void:
	spawn_smoke_cloud(position, seed, true)
	for sprite: Dictionary in _sprites:
		_origins[sprite.node.get_instance_id()] = sprite.node.global_position
	seek_age(age_seconds)

func seek_age(age_seconds: float) -> void:
	tick = maxi(0, int(age_seconds * 100.0))
	for sprite: Dictionary in _sprites:
		if is_instance_valid(sprite.node):
			var age := maxi(0, tick - int(sprite.start_tick))
			sprite.node.global_position = _origins[sprite.node.get_instance_id()] + sprite.velocity * float(age) * 0.01
	_update_sprites()
