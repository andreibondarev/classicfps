extends SceneTree

const BombEscape := preload("res://scripts/cs16_bomb_escape.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_assert_thresholds()
	_assert_decision_priority()
	if failures.is_empty():
		print("GAME_BOMB_ESCAPE_TEST_PASS")
		quit(0)
	else:
		print("GAME_BOMB_ESCAPE_TEST_FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("BOMB ESCAPE TEST: " + message)


func _assert_thresholds() -> void:
	_check(
		BombEscape.threshold_ticks(0.0) == 800,
		"passive bot begins escape at exactly eight seconds",
	)
	_check(
		BombEscape.threshold_ticks(0.5) == 700,
		"mid-aggression bot uses the exact 8 - 2 * aggression rule",
	)
	_check(
		BombEscape.threshold_ticks(1.0) == 600,
		"fully aggressive bot waits until exactly six seconds",
	)
	_check(
		BombEscape.threshold_ticks(0.0, true) == 528,
		"defuse kit scales the eight-second threshold by exactly 0.66",
	)
	_check(
		BombEscape.threshold_ticks(1.0, true) == 396,
		"defuse kit scales the six-second threshold by exactly 0.66",
	)
	_check(
		BombEscape.threshold_ticks(-9.0) == 800
		and BombEscape.threshold_ticks(9.0) == 600,
		"aggression is source-bounded to the zero-through-one range",
	)


func _assert_decision_priority() -> void:
	_check(
		not BombEscape.should_escape(701, 0.5)
		and BombEscape.should_escape(700, 0.5),
		"escape switches on at the exact threshold tick",
	)
	_check(
		not BombEscape.should_escape(700, 0.5, false, true, false),
		"an active attack suppresses bomb escape",
	)
	_check(
		not BombEscape.should_escape(700, 0.5, false, false, true),
		"an active defuse suppresses bomb escape",
	)
	_check(
		not BombEscape.should_escape(528, 0.0, true, true, true),
		"combat and defuse priority remain authoritative with a kit",
	)
