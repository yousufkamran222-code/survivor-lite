class_name TestCase
extends RefCounted
## Minimal assertion base for the headless test runner (tests/run_tests.gd).
## Every method whose name starts with "test_" is run. Keep tests deterministic:
## seed every RandomNumberGenerator.

var failures: Array = []
var _current := ""


func check(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("%s: %s" % [_current, msg if msg != "" else "check failed"])


func check_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s %s" % [_current, str(expected), str(actual), msg])


func check_near(actual: float, expected: float, tol: float = 0.001, msg: String = "") -> void:
	if absf(actual - expected) > tol:
		failures.append("%s: expected ~%s, got %s %s" % [_current, str(expected), str(actual), msg])


func data() -> Dictionary:
	return GameData.load_all()
