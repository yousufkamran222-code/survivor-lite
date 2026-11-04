extends TestCase
## Progress tracking: Profile (stats, records, achievements, merge), run
## summaries and scores, legacy save import.


func _summary(mode: String = "classic", won: bool = false, kills: int = 120, time: float = 150.0) -> Dictionary:
	var s := {
		"mode": mode, "won": won, "time": time, "kills": kills, "level": 12, "elites": 2, "chests": 2,
		"evolved_ids": ["storm"], "conversions": 0, "dashes": 30, "boss_killed": false,
		"kills_by_type": {"grunt": 100, "charger": 20}, "infected_pct": 0,
	}
	s["score"] = Progression.run_score(s, data().online.score)
	return s


func test_new_profile_is_empty() -> void:
	var p := Profile.new()
	check_eq(int(p.stats.runs), 0)
	check_eq(p.gold, 0)
	check(p.records.is_empty())


func test_record_run_updates_stats_and_records() -> void:
	var p := Profile.new()
	p.record_run(_summary("classic", false, 120, 150.0), [], 100)
	p.record_run(_summary("classic", true, 300, 300.0), [], 200)
	check_eq(int(p.stats.runs), 2)
	check_eq(int(p.stats.wins), 1)
	check_eq(int(p.stats.deaths), 1)
	check_eq(int(p.stats.kills), 420)
	check_near(float(p.stats.time_played), 450.0)
	check_eq(int(p.stats.kills_by_type.charger), 40)
	check_eq(p.stats.evolved_ids.size(), 1, "distinct evolutions")
	var r := p.record("classic")
	check_eq(int(r.runs), 2)
	check_near(float(r.best_time), 300.0)
	check_eq(int(r.best_kills), 300)
	check_eq(p.updated_at, 200)


func test_achievements_unlock_once() -> void:
	var defs: Array = data().online.achievements
	var p := Profile.new()
	var fresh := p.record_run(_summary("classic", false, 150), defs, 10)
	var ids := []
	for a in fresh:
		ids.append(a.id)
	check(ids.has("first_blood"), "100 kills unlocks First Blood")
	check(ids.has("evolved"))
	check(not ids.has("survivor"), "not won yet")
	var again := p.record_run(_summary("classic", false, 150), defs, 20)
	for a in again:
		check(a.id != "first_blood", "never unlocks twice")
	check_eq(int(p.achievements.first_blood), 10, "keeps the first unlock time")


func test_achievement_progress() -> void:
	var p := Profile.new()
	p.record_run(_summary("classic", false, 2500), [], 1)
	var def := {"id": "x", "stat": "kills", "goal": 5000}
	check_near(p.achievement_progress(def), 0.5)


func test_gold_and_roundtrip() -> void:
	var p := Profile.new()
	p.add_gold(120, 5)
	p.meta_levels = {"meta_hp": 3}
	p.record_run(_summary("swarm"), data().online.achievements, 6)
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check_eq(q.gold, 120)
	check_eq(int(q.stats.gold_earned), 120)
	check_eq(q.meta_level("meta_hp"), 3)
	check_eq(int(q.record("swarm").runs), 1)
	check_eq(q.achievements.size(), p.achievements.size())
	check_eq(int(q.stats.kills_by_type.grunt), 100)


func test_merge_keeps_all_progress() -> void:
	var phone := Profile.new()
	phone.record_run(_summary("classic", true, 400, 300.0), [], 100)
	phone.gold = 50
	phone.meta_levels = {"meta_hp": 2, "meta_might": 4}
	phone.achievements = {"survivor": 100}
	var cloud := Profile.new()
	for k in 3:
		cloud.record_run(_summary("infection", false, 100, 120.0), [], 200 + k)
	cloud.gold = 999
	cloud.meta_levels = {"meta_hp": 5}
	cloud.achievements = {"regular": 150}
	var m := Profile.merge(phone, cloud)
	check_eq(m.gold, 999, "gold from the newer copy")
	check_eq(int(m.stats.runs), 3, "counters keep the larger value")
	check_eq(m.meta_level("meta_hp"), 5)
	check_eq(m.meta_level("meta_might"), 4, "meta levels: max per upgrade")
	check(m.achievements.has("survivor") and m.achievements.has("regular"), "achievements unioned")
	check_eq(int(m.record("classic").wins), 1, "records from both")
	check_eq(int(m.record("infection").runs), 3)


func test_legacy_import() -> void:
	var p := Profile.from_legacy(230, {"meta_hp": 2}, 250.0, 14, 11, true, "swarm", {"classic": 250.0, "infection": 180.0})
	check_eq(p.gold, 230)
	check_eq(p.meta_level("meta_hp"), 2)
	check_eq(int(p.stats.runs), 14)
	check_eq(p.settings.mode, "swarm")
	check(p.settings.muted)
	check_near(p.best_time_any(), 250.0)
	check_near(float(p.record("infection").best_time), 180.0)


func test_run_summary_and_score_from_world() -> void:
	var w := World.new(GameData.apply_mode(data(), "infection"), 3)
	w.emit_events = false
	w._add_enemy("charger", Vector2(300, 0))
	w._damage(0, 1.0e6, Vector2.ZERO)
	w._process_dead()
	w.time = 100.0
	var s := Progression.run_summary(w, false, "infection", data().online.score)
	check_eq(s.mode, "infection")
	check_eq(int(s.kills_by_type.charger), 1)
	check(int(s.infected_pct) >= 0)
	check(int(s.score) > 0)
	var better := s.duplicate(true)
	better.won = true
	check(Progression.run_score(better, data().online.score) > int(s.score), "winning scores more")
	check_eq(Progression.metric_value(s, "kills"), 1)


func test_leaderboards_cover_every_mode() -> void:
	var modes := {}
	for lb in data().online.leaderboards:
		modes[lb.mode] = true
	for m in data().modes:
		check(modes.has(m.id), "mode %s has a leaderboard" % m.id)


func _save_service(tag: String) -> Node:
	var sv: Node = load("res://scripts/autoload/save_service.gd").new()
	sv.path = "user://test_%s.json" % tag
	sv.backup = "user://test_%s.bak" % tag
	sv.legacy = "user://test_%s.cfg" % tag
	for f in [sv.path, sv.backup, sv.legacy]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	return sv


func test_save_file_roundtrip_and_backup() -> void:
	var sv := _save_service("io")
	sv.profile.add_gold(77, 1)
	sv.write()
	sv.profile.add_gold(10, 2)
	sv.write()  # second write keeps the first as backup
	var sv2: Node = load("res://scripts/autoload/save_service.gd").new()
	sv2.path = sv.path
	sv2.backup = sv.backup
	sv2.legacy = sv.legacy
	sv2.load_save()
	check_eq(sv2.gold, 87)
	# Corrupt main file: the backup (77) is used.
	var f := FileAccess.open(sv.path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var sv3: Node = load("res://scripts/autoload/save_service.gd").new()
	sv3.path = sv.path
	sv3.backup = sv.backup
	sv3.legacy = sv.legacy
	sv3.load_save()
	check_eq(sv3.gold, 77, "falls back to the backup")
	for n in [sv, sv2, sv3]:
		n.free()


func test_legacy_cfg_is_imported() -> void:
	var sv := _save_service("legacy")
	var cf := ConfigFile.new()
	cf.set_value("progress", "gold", 300)
	cf.set_value("progress", "meta_levels", {"meta_might": 2})
	cf.set_value("stats", "runs", 9)
	cf.set_value("settings", "mode", "classic")
	cf.save(sv.legacy)
	sv.load_save()
	check_eq(sv.gold, 300)
	check_eq(sv.meta_level("meta_might"), 2)
	check_eq(sv.runs, 9)
	check_eq(sv.mode, "classic")
	check(FileAccess.file_exists(sv.path), "imported profile written as JSON")
	sv.free()


func test_json_roundtrip_keeps_integers() -> void:
	var p := Profile.new()
	p.record_run(_summary("classic", true, 300, 300.0), data().online.achievements, 9)
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check_eq(typeof(q.stats.runs), TYPE_INT, "counters stay ints after JSON")
	check_eq(typeof(q.record("classic").best_kills), TYPE_INT)
	check_eq(typeof(q.record("classic").best_time), TYPE_FLOAT)
	check_eq(str(q.stats.kills), "300")


func test_buy_meta_spends_gold_and_respects_max() -> void:
	var p := Profile.new()
	var def := {"id": "meta_x", "costs": [30, 50]}
	check_eq(p.buy_meta(def, 10), 0, "no gold: nothing bought")
	check_eq(p.meta_level("meta_x"), 0)
	p.gold = 100
	check_eq(p.buy_meta(def, 11), 30)
	check_eq(p.gold, 70)
	check_eq(p.meta_level("meta_x"), 1)
	check_eq(p.updated_at, 11)
	check_eq(p.buy_meta(def, 12), 50)
	check_eq(p.gold, 20)
	check_eq(p.buy_meta(def, 13), 0, "maxed: nothing bought")
	check_eq(p.gold, 20, "maxed: gold untouched")
	check_eq(p.meta_level("meta_x"), 2)


func test_dev_gold_and_refund() -> void:
	var p := Profile.new()
	p.dev_grant_gold(10000, 5)
	check_eq(p.gold, 10000)
	check_eq(int(p.stats.gold_earned), 0, "dev gold isn't counted as earned")
	var defs: Array = data().meta
	var spent := 0
	for k in 3:
		spent += p.buy_meta(defs[0], 6)
	check_eq(p.meta_level(defs[0].id), 3)
	var back := p.refund_meta(defs, 7)
	check_eq(back, spent, "refund returns exactly what was spent")
	check_eq(p.gold, 10000)
	check_eq(p.meta_level(defs[0].id), 0)


func test_dev_tools_flag_exists() -> void:
	check(data().balance.debug.has("dev_tools"), "balance.debug.dev_tools controls the Settings developer tools")
