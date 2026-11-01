extends TestCase


func test_xp_curve_strictly_increasing() -> void:
	var b: Dictionary = data().balance
	var prev := 0.0
	for l in range(1, 60):
		var x := Progression.xp_needed(b, l)
		check(x > prev, "xp_needed(%d)=%s not above previous %s" % [l, x, prev])
		prev = x


func test_xp_curve_first_level_quick() -> void:
	check(Progression.xp_needed(data().balance, 1) <= 8.0, "first level-up should come within ~8 kills")


func test_run_gold() -> void:
	var b: Dictionary = data().balance
	var base := Progression.run_gold(b, 100, 120.0, false, false, 0.0)
	check(base > 0)
	check(Progression.run_gold(b, 100, 120.0, true, false, 0.0) > base, "boss bonus")
	check(Progression.run_gold(b, 100, 120.0, false, false, 0.5) >= int(base * 1.5) - 1, "gold_gain")


func test_meta_bonus_and_cost() -> void:
	var meta: Array = data().meta
	var hp_def: Dictionary = meta[0]
	var bonus := Progression.meta_bonus(meta, {hp_def.id: 2})
	check_near(bonus[hp_def.stat], float(hp_def.per_level) * 2)
	check_eq(Progression.meta_next_cost(hp_def, 0), int(hp_def.costs[0]))
	check_eq(Progression.meta_next_cost(hp_def, hp_def.costs.size()), -1)
	# Levels beyond the max are clamped.
	var over := Progression.meta_bonus(meta, {hp_def.id: 99})
	check_near(over[hp_def.stat], float(hp_def.per_level) * hp_def.costs.size())
