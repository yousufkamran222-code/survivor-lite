extends TestCase


func test_data_validates() -> void:
	var errors := GameData.validate(data())
	check(errors.is_empty(), "data errors: %s" % str(errors))


func test_scope_caps() -> void:
	var d := data()
	check(d.enemies.size() <= 8, "v1 scope: at most 8 enemy types")
	check(d.upgrades.size() <= 12, "v1 scope: about 10 upgrades")


func test_budget_curve_increases() -> void:
	var curve: Array = data().waves.budget_curve
	for i in range(1, curve.size()):
		check(float(curve[i][1]) >= float(curve[i - 1][1]), "budget curve should not drop at t=%s" % curve[i][0])
