extends SceneTree

const UseResolver := preload("res://scripts/cs16_player_use_resolver.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var user := Vector3.ZERO
	var eye := Vector3(0.0, 0.53, 0.0)
	var forward := Vector3(0.0, 0.0, -1.0)
	var c4 := {
		"id": "c4",
		"origin": Vector3(0.05, 0.0, -0.60),
		"usable": true,
	}
	var button := {
		"id": "button",
		"origin": Vector3(0.02, 0.45, -0.45),
		"usable": true,
	}
	_check(
		UseResolver.selected_id(user, eye, forward, [c4, button]) == "button",
		"higher-dot button beats planted C4 inside the same use sphere",
	)
	_check(
		UseResolver.selected_id(
			user,
			eye,
			forward,
			[
				{"id": "edge", "origin": Vector3(0.0, 0.0, -0.64), "usable": true},
			],
		) == "edge",
		"candidate at exactly 64 HU remains in the use sphere",
	)
	_check(
		UseResolver.selected_id(
			user,
			eye,
			forward,
			[
				{"id": "outside", "origin": Vector3(0.0, 0.0, -0.6401), "usable": true},
			],
		).is_empty(),
		"candidate beyond 64 HU is rejected",
	)
	var exact_dot_direction := Vector3(sqrt(0.51), 0.0, -0.7)
	_check(
		UseResolver.selected_id(
			user,
			eye,
			forward,
			[
				{
					"id": "dot_edge",
					"origin": eye + exact_dot_direction * 0.2,
					"usable": true,
				},
			],
		).is_empty(),
		"view dot exactly 0.7 fails the strict narrow-FOV comparison",
	)
	_check(
		UseResolver.selected_id(
			user,
			eye,
			forward,
			[
				{"id": "first", "origin": Vector3(0.0, 0.23, -0.40), "usable": true},
				{"id": "second", "origin": Vector3(0.0, 0.17, -0.48), "usable": true},
			],
		) == "first",
		"equal-dot candidates preserve stable entity-search order",
	)
	_check(
		UseResolver.selected_id(
			user,
			eye,
			forward,
			[
				{"id": "disabled", "origin": Vector3(0.0, 0.53, -0.2), "usable": false},
				c4,
			],
		) == "c4",
		"non-usable entity cannot steal +use",
	)

	if failures.is_empty():
		print("GAME_PLAYER_USE_RESOLVER_TEST_PASS")
		quit(0)
	else:
		print("GAME_PLAYER_USE_RESOLVER_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("PLAYER USE RESOLVER TEST: " + message)
