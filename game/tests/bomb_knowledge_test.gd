extends SceneTree

const Knowledge := preload("res://scripts/cs16_bomb_knowledge.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var knowledge = Knowledge.new()
	knowledge.register_actor("t1", Knowledge.TEAM_T)
	knowledge.register_actor("ct_near", Knowledge.TEAM_CT)
	knowledge.register_actor("ct_edge", Knowledge.TEAM_CT)
	knowledge.register_actor("ct_far", Knowledge.TEAM_CT)
	var bomb := Vector3.ZERO
	knowledge.on_bomb_planted(bomb, {
		"t1": Vector3(40.0, 0.0, 0.0),
		"ct_near": Vector3(9.99, 0.0, 0.0),
		"ct_edge": Vector3(10.0, 0.0, 0.0),
		"ct_far": Vector3(14.0, 0.0, 0.0),
	})
	_check(knowledge.knows_exact("t1"), "T knows exact planted C4 immediately")
	_check(
		knowledge.knows_exact("ct_near"),
		"CT strictly inside the 1000-HU initial beep radius learns exact C4",
	)
	_check(
		not knowledge.knows_exact("ct_edge")
		and not knowledge.knows_exact("ct_far"),
		"1000-HU beep radius is strict and does not create CT omniscience",
	)

	# Moving close between beeps must not mutate event-driven knowledge.
	var moved_positions := {
		"ct_edge": Vector3(1.0, 0.0, 0.0),
		"ct_far": Vector3(1.0, 0.0, 0.0),
	}
	_check(
		not knowledge.knows_exact("ct_far"),
		"proximity alone does not continuously reveal the planted C4",
	)
	knowledge.on_bomb_beep(bomb, moved_positions)
	_check(
		knowledge.knows_exact("ct_edge") and knowledge.knows_exact("ct_far"),
		"a later beep reveals the C4 to CTs then inside hearing range",
	)

	knowledge.reset_round()
	knowledge.on_bomb_dropped(Vector3(2.0, 0.0, -1.0))
	_check(
		knowledge.knows_exact("t1") and not knowledge.knows_exact("ct_far"),
		"T radar knows loose C4 while CT remains ignorant before seeing it",
	)
	_check(
		not knowledge.on_visual_contact(
			"ct_far",
			Vector3(2.0, 0.0, -1.0),
			false,
			true,
		),
		"line-of-sight behind the CT fails the required FOV check",
	)
	_check(
		not knowledge.on_visual_contact(
			"ct_far",
			Vector3(2.0, 0.0, -1.0),
			true,
			false,
		),
		"in-FOV C4 behind BSP remains unknown",
	)
	_check(
		knowledge.on_visual_contact(
			"ct_far",
			Vector3(2.0, 0.0, -1.0),
			true,
			true,
		)
		and knowledge.knows_exact("ct_far"),
		"direct FOV plus clear LOS reveals loose C4",
	)

	knowledge.reset_round()
	knowledge.on_bomb_planted(bomb, {"ct_far": Vector3(20.0, 0.0, 0.0)})
	knowledge.broadcast_planted_site("B", ["ct_near", "ct_far"])
	_check(
		knowledge.known_site("ct_far") == "B"
		and not knowledge.knows_exact("ct_far"),
		"radio shares planted site without inventing exact bomb coordinates",
	)

	if failures.is_empty():
		print("GAME_BOMB_KNOWLEDGE_TEST_PASS")
		quit(0)
	else:
		print("GAME_BOMB_KNOWLEDGE_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures.append(message)
	push_error("BOMB KNOWLEDGE TEST: " + message)
