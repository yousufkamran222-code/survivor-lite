extends TestCase
## Daily missions (data/missions.json, Missions): picked by the date, one per
## tier, progress from run summaries, gold paid once, a bonus for all three.


func _cfg() -> Dictionary:
	return data().missions


func _run(over: Dictionary = {}) -> Dictionary:
	var s := {"mode": "classic", "won": false, "time": 120.0, "kills": 100, "level": 8, "elites": 1, "chests": 1,
		"evolved_ids": [], "conversions": 0, "dashes": 10, "boss_killed": false, "best_streak": 30,
		"outbreaks": 1, "perfect_dodges": 0, "infected_pct": 0}
	for k in over:
		s[k] = over[k]
	return s


func test_data_is_valid() -> void:
	check(GameData.validate(data()).is_empty(), str(GameData.validate(data())))


func test_same_day_same_missions_one_per_tier() -> void:
	var a := Missions.pick(_cfg(), "2026-11-15", ["classic"])
	var b := Missions.pick(_cfg(), "2026-11-15", ["classic"])
	check_eq(a, b, "seeded by the date")
	check_eq(a.size(), int(_cfg().per_day))
	var tiers := {}
	for id in a:
		tiers[int(Missions.find(_cfg(), id).tier)] = true
	check_eq(tiers.size(), a.size(), "one per tier")
	var differs := false
	for k in 10:
		if Missions.pick(_cfg(), "2026-12-%02d" % (k + 1), ["classic"]) != a:
			differs = true
	check(differs, "other days get other missions")


func test_locked_modes_are_skipped() -> void:
	for k in 40:
		for id in Missions.pick(_cfg(), "2027-01-%02d" % (k % 28 + 1) + str(k), ["classic"]):
			check(not Missions.find(_cfg(), id).has("requires"), "no Infection/Swarm mission before they unlock")


func test_progress_pays_once_and_bonus() -> void:
	var p := Profile.new()
	var day := "2026-11-15"
	var st := Missions.today(p, _cfg(), day, ["classic"])
	# Force a known set: one sum, one best, one win.
	st.ids = ["kill_300", "level_15", "win_1"]
	var g0 := p.gold
	var r1 := Missions.record_run(p, _cfg(), _run({"kills": 200}), day, ["classic"], 1)
	check(r1.is_empty(), "200/300 kills: not yet")
	var r2 := Missions.record_run(p, _cfg(), _run({"kills": 150, "level": 16}), day, ["classic"], 2)
	check_eq(r2.size(), 2, "kills add up over runs; level 16 in one run")
	check_eq(p.gold - g0, 160)
	var r3 := Missions.record_run(p, _cfg(), _run({"kills": 999, "level": 30}), day, ["classic"], 3)
	check(r3.is_empty(), "a finished mission never pays twice")
	var r4 := Missions.record_run(p, _cfg(), _run({"won": true}), day, ["classic"], 4)
	check_eq(r4.size(), 2, "the win + the all-done bonus")
	check_eq(str(r4[1].id), "all")
	check_eq(p.gold - g0, 160 + 160 + int(_cfg().all_bonus))
	check_eq(Missions.done_count(Missions.today(p, _cfg(), day, ["classic"])), 3)


func test_new_day_resets() -> void:
	var p := Profile.new()
	Missions.record_run(p, _cfg(), _run({"kills": 5000}), "2026-11-15", ["classic"], 1)
	var st := Missions.today(p, _cfg(), "2026-11-16", ["classic"])
	check_eq(str(st.day), "2026-11-16")
	check(st.done.is_empty() and st.progress.is_empty(), "fresh missions every day")


func test_state_survives_a_save() -> void:
	var p := Profile.new()
	Missions.record_run(p, _cfg(), _run({"kills": 120}), "2026-11-15", ["classic"], 1)
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	var a := Missions.today(p, _cfg(), "2026-11-15", ["classic"])
	var b := Missions.today(q, _cfg(), "2026-11-15", ["classic"])
	check_eq(b.ids, a.ids, "the same missions after a reload")
	for id in a.ids:
		var m := Missions.find(_cfg(), str(id))
		check_eq(Missions.progress(b, m), Missions.progress(a, m), "progress kept")


func test_text() -> void:
	check_eq(Missions.text(Missions.find(_cfg(), "kill_300")), "Kill 300 germs")
	check_eq(Missions.text(Missions.find(_cfg(), "infect_50")), "Infect 50% of the dish in one run")
