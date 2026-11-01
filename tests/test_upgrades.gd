extends TestCase


func _by_id(d: Dictionary) -> Dictionary:
	var out := {}
	for u in d.upgrades:
		out[u.id] = u
	return out


func test_stats_stack_by_level() -> void:
	var bolt: Dictionary = _by_id(data()).bolt
	var l1 := Upgrades.stats_at(bolt, 1)
	var l2 := Upgrades.stats_at(bolt, 2)
	check_near(l2.damage - l1.damage, float(bolt.levels[1].damage))
	check_near(Upgrades.stats_at(bolt, 99).damage, Upgrades.stats_at(bolt, bolt.levels.size()).damage, 0.001, "clamped at max")


func test_global_stats_combine_passives_and_meta() -> void:
	var ups := _by_id(data())
	var s := Upgrades.global_stats(ups, {"might": 2, "bolt": 3}, {"might": 0.05})
	check_near(s.might, float(ups.might.levels[0].might) * 2 + 0.05)
	check_near(s.haste, 0.0)


func test_offers_distinct_and_valid() -> void:
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		var offers := Upgrades.roll_offers(d.upgrades, {"bolt": 1}, rng, 3, 4, 1.6)
		check_eq(offers.size(), 3)
		var seen := {}
		for o in offers:
			check(not seen.has(o), "duplicate offer %s" % o)
			seen[o] = true


func test_offers_skip_maxed() -> void:
	var d := data()
	var owned := {}
	for u in d.upgrades:
		owned[u.id] = u.levels.size()
	owned.erase("haste")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	check_eq(Upgrades.roll_offers(d.upgrades, owned, rng, 3, 4, 1.6), ["haste"])


func test_offers_respect_weapon_slots() -> void:
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ups := _by_id(d)
	for i in 100:
		for o in Upgrades.roll_offers(d.upgrades, {"bolt": 1}, rng, 3, 1, 1.6):
			check(ups[o].type == "passive" or o == "bolt", "offered new weapon %s with slots full" % o)
