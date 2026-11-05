extends TestCase
## Virulence (data/difficulty.json): a 10-level ladder per mode. Level N
## stacks levels 2..N plus a compounding HP/damage ramp; winning unlocks the
## next level; any unlocked level can be picked again.


func _d(mode: String = "classic") -> Dictionary:
	return GameData.apply_mode(data(), mode)


func test_ten_levels_and_level_one_changes_nothing() -> void:
	check_eq(data().difficulty.levels.size(), 10)
	var base := _d()
	var v1 := GameData.apply_virulence(base, 1)
	check_eq(v1.waves, base.waves, "waves untouched")
	check_eq(v1.balance.player, base.balance.player, "player untouched")
	check_near(float(v1.balance.difficulty.gold_mult), 1.0, 0.0001)
	check_eq(int(v1.balance.virulence), 1)


func test_modifiers_stack_up_the_ladder() -> void:
	var base := _d()
	var v5 := GameData.apply_virulence(base, 5)
	var dd: Dictionary = v5.balance.difficulty
	check_near(float(dd.enemy_speed_mult), 1.1, 0.001, "Lv2 quick germs")
	check_near(float(dd.knock_resist_add), 0.3, 0.001, "Lv3 heavy crowd")
	check_near(float(v5.waves.budget_curve[1][1]), float(base.waves.budget_curve[1][1]) * 1.25, 0.001, "Lv4 swarming")
	check_near(float(dd.shot_speed_mult), 1.3, 0.001, "Lv5 spitters")
	check_near(float(v5.balance.player.iframes_s), float(base.balance.player.iframes_s), 0.0001, "Lv6 not yet")
	var v6 := GameData.apply_virulence(base, 6)
	check_near(float(v6.balance.player.iframes_s), float(base.balance.player.iframes_s) * 0.6, 0.0001, "Lv6 thin membrane")
	var hp5 := float(dd.enemy_hp_mult) / float(base.balance.difficulty.get("enemy_hp_mult", 1.0))
	check_near(hp5, pow(float(data().difficulty.hp_growth), 4), 0.01, "compounding HP ramp")
	check(float(v6.balance.difficulty.enemy_hp_mult) > float(dd.enemy_hp_mult), "keeps climbing")


func test_late_levels_move_the_boss_and_the_final_minute() -> void:
	var v10 := GameData.apply_virulence(_d(), 10)
	check_near(float(v10.waves.final_minute_s), 210.0, 0.01)
	var boss_t := 0.0
	for ev in v10.waves.events:
		if ev.enemy == "boss":
			boss_t = float(ev.t)
	check_near(boss_t, 180.0, 0.01, "Mother Cell comes early")
	for e in v10.enemies:
		if e.id == "boss":
			check_eq(int(e.burst_count), 28, "double bursts")


func test_nucleus_ramps_less() -> void:
	var c := float(GameData.apply_virulence(_d("classic"), 5).balance.difficulty.enemy_hp_mult) / float(_d("classic").balance.difficulty.get("enemy_hp_mult", 1.0))
	var n := float(GameData.apply_virulence(_d("nucleus"), 5).balance.difficulty.enemy_hp_mult)
	check(n < c, "Nucleus already scales per wave")


func test_world_applies_speed_and_knock_resist() -> void:
	var w1 := World.new(GameData.apply_virulence(_d(), 1), 1)
	var w3 := World.new(GameData.apply_virulence(_d(), 3), 1)
	w1._add_enemy("grunt", Vector2(400, 0))
	w3._add_enemy("grunt", Vector2(400, 0))
	check_near(w3.e_spd[0] / w1.e_spd[0], 1.1, 0.001)
	w1._damage(0, 0.0, Vector2(100, 0), false)
	w3._damage(0, 0.0, Vector2(100, 0), false)
	check(w3.e_knock[0].x < w1.e_knock[0].x * 0.8, "heavy crowd resists knockback")


func test_gold_and_score_grow_with_the_level() -> void:
	var b1: Dictionary = GameData.apply_virulence(_d(), 1).balance
	var b4: Dictionary = GameData.apply_virulence(_d(), 4).balance
	var g1 := Progression.run_gold(b1, 500, 300.0, true, true, 0.0)
	var g4 := Progression.run_gold(b4, 500, 300.0, true, true, 0.0)
	check_near(float(g4) / float(g1), 1.45, 0.02, "+15% gold per level")
	var w := World.new(GameData.apply_virulence(_d(), 4), 1)
	w.kills = 300
	w.time = 200.0
	var s := Progression.run_summary(w, false, "classic", data().online.score)
	var w1 := World.new(GameData.apply_virulence(_d(), 1), 1)
	w1.kills = 300
	w1.time = 200.0
	var s1 := Progression.run_summary(w1, false, "classic", data().online.score)
	check_eq(int(s.virulence), 4)
	check_near(float(s.score) / float(s1.score), 1.3, 0.02, "+10% score per level")


func test_winning_unlocks_and_older_levels_stay_playable() -> void:
	var p := Profile.new()
	check_eq(p.virulence_unlocked("classic"), 1)
	check_eq(p.virulence_selected("classic"), 1)
	var s := {"mode": "classic", "won": true, "time": 300.0, "kills": 100, "level": 10, "elites": 0, "chests": 0,
		"evolved_ids": [], "conversions": 0, "dashes": 0, "boss_killed": false, "kills_by_type": {}, "infected_pct": 0, "score": 10, "virulence": 1}
	p.record_run(s, [], 1)
	check_eq(p.virulence_cleared("classic"), 1)
	check_eq(p.virulence_unlocked("classic"), 2)
	s.virulence = 2
	p.record_run(s, [], 2)
	check_eq(p.virulence_unlocked("classic"), 3)
	p.set_virulence("classic", 1)
	check_eq(p.virulence_selected("classic"), 1, "can replay an older level")
	p.set_virulence("classic", 9)
	check_eq(p.virulence_selected("classic"), 3, "can't pick a locked level")
	check_eq(p.virulence_unlocked("swarm"), 1, "unlocks are per mode")
	var lose := s.duplicate()
	lose.won = false
	lose.virulence = 3
	p.record_run(lose, [], 3)
	check_eq(p.virulence_cleared("classic"), 2, "a loss doesn't unlock anything")


func test_old_saves_load_and_merge_keeps_the_higher_level() -> void:
	var d := Profile.new().to_dict()
	d.version = 3
	d.records = {"classic": {"runs": 4, "wins": 1, "best_time": 300.0}}
	var p := Profile.from_dict(d)
	check_eq(p.virulence_cleared("classic"), 0, "v3 save: nothing cleared yet")
	check_eq(p.virulence_selected("classic"), 1)
	var a := Profile.new()
	a._record("classic").virulence = 4
	a.updated_at = 1
	var b := Profile.new()
	b._record("classic").virulence = 2
	b.updated_at = 2
	check_eq(Profile.merge(a, b).virulence_cleared("classic"), 4)
	check(Profile.VERSION >= 4)


func test_virulence_achievements() -> void:
	var p := Profile.new()
	p._record("classic").virulence = 5
	var ids := []
	for a in p.check_achievements(data().online.achievements, 1):
		ids.append(a.id)
	check(ids.has("virulence_5"))
	check(not ids.has("virulence_10"))


func test_validation_catches_unknown_modifier() -> void:
	var d := data().duplicate(true)
	d.difficulty.levels[3].mods["laser_mult"] = 2.0
	check(GameData.validate(d).size() > 0)


func test_dev_toggle_unlocks_every_level_without_touching_records() -> void:
	var p := Profile.new()
	check_eq(p.virulence_unlocked("classic"), 1)
	p.settings["dev_all_virulence"] = true
	for m in ["classic", "infection", "swarm", "nucleus"]:
		check_eq(p.virulence_unlocked(m), Profile.MAX_VIRULENCE, "%s: all unlocked" % m)
	p.set_virulence("swarm", 10)
	check_eq(p.virulence_selected("swarm"), 10)
	check_eq(p.virulence_cleared("swarm"), 0, "records untouched")
	check_eq(int(p.flat().best_virulence), 0, "no achievement progress from the toggle")
	p.settings["dev_all_virulence"] = false
	check_eq(p.virulence_selected("swarm"), 1, "back to real progress")


func test_developer_code() -> void:
	SettingsScreen.dev_unlocked = false
	var st := SettingsScreen.new()
	st.dev_password = str(data().balance.debug.dev_password)
	check(not st.check_code("0000"), "wrong code stays locked")
	check(st.check_code(str(data().balance.debug.dev_password)), "right code unlocks")
	SettingsScreen.dev_unlocked = false
	st.free()
