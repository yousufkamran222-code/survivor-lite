extends TestCase


func test_data_validates() -> void:
	var errors := GameData.validate(data())
	check(errors.is_empty(), "data errors: %s" % str(errors))


func test_scope_caps() -> void:
	var d := data()
	check(d.enemies.size() <= 8, "v1 scope: at most 8 enemy types")
	var general := 0
	for u in d.upgrades:
		if not u.has("modes"):
			general += 1
	check(general <= 16, "scope: about 15 upgrades shared by all modes (incl. 4 dash cards)")


func test_budget_curve_increases() -> void:
	var curve: Array = data().waves.budget_curve
	for i in range(1, curve.size()):
		check(float(curve[i][1]) >= float(curve[i - 1][1]), "budget curve should not drop at t=%s" % curve[i][0])


func test_modes_apply_overrides() -> void:
	var d := data()
	check(d.modes.size() >= 2, "at least two game modes")
	var classic := GameData.apply_mode(d, "classic")
	var infection := GameData.apply_mode(d, "infection")
	check(not classic.balance.territory.enabled, "classic: no territory")
	check(infection.balance.territory.enabled, "infection: territory on")
	check_eq(classic.balance.territory.dish_radius, d.balance.territory.dish_radius, "deep merge keeps other keys")
	check(World.new(classic, 1).terr == null)
	check(World.new(infection, 1).terr != null)
	# apply_mode must not mutate the shared data.
	d.balance.territory.enabled = true
	GameData.apply_mode(d, "classic")
	check(d.balance.territory.enabled, "original data untouched")
