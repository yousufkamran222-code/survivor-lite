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
	check(general <= 16, "scope: about 16 upgrades shared by all modes (incl. 5 dash cards)")


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


func test_hint_events_exist_in_the_world() -> void:
	# An event-triggered hint with a typo would silently never show.
	var src := FileAccess.get_file_as_string("res://scripts/core/world.gd")
	var h: Dictionary = data().hints
	var n := 0
	for key in h:
		for hint in h[key]:
			if hint.has("event"):
				n += 1
				check(('"type": "%s"' % hint.event) in src, "hint '%s' waits for unknown event '%s'" % [hint.id, hint.event])
	check(n > 0, "some hints are event-triggered")


func test_store_builds_force_debug_off() -> void:
	var d := data()
	d.balance.debug.dev_tools = true
	d.balance.debug.show_perf = true
	d.balance.debug.invincible = true
	GameData.apply_store_build(d, false)
	check(d.balance.debug.dev_tools, "playtest builds keep the dev tools")
	GameData.apply_store_build(d, true)
	check(not d.balance.debug.dev_tools and not d.balance.debug.show_perf and not d.balance.debug.invincible)
