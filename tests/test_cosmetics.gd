extends TestCase
## Cosmetics (data/cosmetics.json, Cosmetics, Profile v7): unlock rules,
## buying, equipping, the developer toggle, saves and merges.


func cfg() -> Dictionary:
	return data().cosmetics


func test_data_is_valid_and_v1_sized() -> void:
	var errors := GameData.validate(data())
	check(errors.is_empty(), str(errors))
	var c := cfg()
	check_eq(c.categories.size(), 3)
	for cat in ["skin", "weapon", "pop"]:
		var n := Cosmetics.items(c, cat).size()
		check(n >= 6 and n <= 12, "%s has %d items" % [cat, n])
		check_eq(Cosmetics.unlock_type(Cosmetics.find(c, str(c.defaults[cat]))), "free")
	for it in c.items:
		check(not it.has("stats") and not it.get("look", {}).has("damage"), "cosmetics never carry stats")


func test_validation_catches_bad_items() -> void:
	var d := data().duplicate(true)
	d.cosmetics.items.append({"id": "white", "cat": "hat", "name": "x", "unlock": {"type": "gold", "cost": 0}})
	var errors := GameData.validate(d)
	var text := str(errors)
	check(text.contains("duplicated"), text)
	check(text.contains("unknown category"), text)
	check(text.contains("gold cost"), text)


func test_defaults_are_equipped_on_a_new_profile() -> void:
	var p := Profile.new()
	check_eq(Cosmetics.equipped(cfg(), p, "skin"), "white")
	check_eq(Cosmetics.equipped(cfg(), p, "weapon"), "standard")
	check_eq(Cosmetics.equipped(cfg(), p, "pop"), "goo")
	var look := Cosmetics.look(cfg(), p)
	check(look.has("skin") and look.has("weapon") and look.has("pop"))


func test_buy_with_gold() -> void:
	var p := Profile.new()
	p.gold = 1000
	check_eq(Cosmetics.buy(cfg(), p, "mint", 5), 0, "too poor")
	check_eq(p.gold, 1000)
	p.gold = 2000
	check_eq(Cosmetics.buy(cfg(), p, "mint", 5), 1200)
	check_eq(p.gold, 800)
	check(Cosmetics.is_unlocked(Cosmetics.find(cfg(), "mint"), p))
	check_eq(Cosmetics.buy(cfg(), p, "mint", 6), 0, "never twice")
	check_eq(Cosmetics.buy(cfg(), p, "golden", 6), 0, "prestige items can't be bought")
	check_eq(p.gold, 800)


func test_equip_only_unlocked() -> void:
	var p := Profile.new()
	check(not Cosmetics.equip(cfg(), p, "golden"), "locked")
	check_eq(Cosmetics.equipped(cfg(), p, "skin"), "white")
	p.gold = 5000
	Cosmetics.buy(cfg(), p, "ember", 1)
	check(Cosmetics.equip(cfg(), p, "ember"))
	check_eq(Cosmetics.equipped(cfg(), p, "skin"), "ember")
	check_eq(Cosmetics.equipped(cfg(), p, "pop"), "goo", "other categories untouched")


func test_challenges_and_prestige_come_from_stats() -> void:
	var p := Profile.new()
	var pix := Cosmetics.find(cfg(), "pixels")  # 5,000 kills
	check(not Cosmetics.earned(pix, p))
	p.stats.kills = 2500
	check_near(Cosmetics.progress(pix, p), 0.5)
	check_eq(Cosmetics.progress_text(pix, p), "2,500 / 5,000")
	p.stats.kills = 5000
	check(Cosmetics.earned(pix, p))
	var gold := Cosmetics.find(cfg(), "golden")  # Virulence 10 in any mode
	p._record("swarm").virulence = 9
	check(not Cosmetics.earned(gold, p))
	p._record("classic").virulence = 10
	check(Cosmetics.earned(gold, p))


func test_newly_earned_around_a_run() -> void:
	var p := Profile.new()
	p.stats.kills = 4990
	var before := Cosmetics.earned_ids(cfg(), p)
	p.record_run({"mode": "classic", "won": false, "time": 60.0, "kills": 20, "level": 3, "elites": 0, "chests": 0,
		"evolved_ids": [], "conversions": 0, "dashes": 0, "boss_killed": false, "kills_by_type": {}, "infected_pct": 0, "score": 1}, [], 1)
	var fresh := Cosmetics.newly_earned(cfg(), before, Cosmetics.earned_ids(cfg(), p))
	check_eq(fresh.size(), 1)
	check_eq(str(fresh[0].id), "pixels")


func test_dev_toggle_unlocks_all_and_turns_off_cleanly() -> void:
	var p := Profile.new()
	p.settings["dev_all_cosmetics"] = true
	for it in cfg().items:
		check(Cosmetics.is_unlocked(it, p), str(it.id))
	check(Cosmetics.equip(cfg(), p, "golden"))
	check(Cosmetics.equip(cfg(), p, "supernova"))
	check_eq(Cosmetics.equipped(cfg(), p, "skin"), "golden")
	check(p.cosmetics.is_empty(), "nothing is saved as bought")
	p.settings["dev_all_cosmetics"] = false
	check_eq(Cosmetics.equipped(cfg(), p, "skin"), "white", "falls back to the default")
	check_eq(Cosmetics.equipped(cfg(), p, "pop"), "goo")


func test_save_round_trip_and_old_saves() -> void:
	var p := Profile.new()
	p.gold = 3000
	Cosmetics.buy(cfg(), p, "confetti", 7)
	Cosmetics.equip(cfg(), p, "confetti")
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check_eq(int(q.cosmetics.confetti), 7)
	check_eq(Cosmetics.equipped(cfg(), q, "pop"), "confetti")
	check_eq(int(q.to_dict().version), Profile.VERSION)
	var old := Profile.from_dict({"version": 6, "gold": 50})
	check(old.cosmetics.is_empty())
	check_eq(old.gold, 50)
	check_eq(Cosmetics.equipped(cfg(), old, "skin"), "white")


func test_merge_keeps_bought_cosmetics_from_both() -> void:
	var a := Profile.new()
	a.cosmetics["mint"] = 1
	a.updated_at = 10
	var b := Profile.new()
	b.cosmetics["confetti"] = 2
	b.updated_at = 20
	var m := Profile.merge(a, b)
	check(m.cosmetics.has("mint") and m.cosmetics.has("confetti"))


func test_thousands() -> void:
	check_eq(Cosmetics._thousands(0), "0")
	check_eq(Cosmetics._thousands(999), "999")
	check_eq(Cosmetics._thousands(20000), "20,000")
	check_eq(Cosmetics._thousands(1234567), "1,234,567")


func test_looks_use_known_sounds_and_shapes() -> void:
	var sounds: Dictionary = load("res://scripts/autoload/sfx.gd").get_script_constant_map().SOUNDS
	var shapes := ["disc", "square", "star", "heart", "coin", "diamond", "ring"]
	for it in cfg().items:
		var lk: Dictionary = it.get("look", {})
		if it.cat == "pop":
			var snd := str(lk.get("sound", "kill"))
			check(snd == "kill" or sounds.has(snd), "%s: sound %s" % [it.id, snd])
		if lk.has("shape"):
			check(shapes.has(str(lk.shape)), "%s: shape %s" % [it.id, lk.shape])
		for k in ["body", "nucleus", "glow", "pattern_color", "cilia_color", "bolt", "orbit", "nova", "chain", "flash", "ring_color"]:
			if lk.has(k):
				check(str(lk[k]).begins_with("#"), "%s.%s is a colour" % [it.id, k])


func test_pop_burst_follows_the_style() -> void:
	var pop: Dictionary = Cosmetics.find(cfg(), "confetti").look
	check(CosmeticArt.is_default_pop(Cosmetics.find(cfg(), "goo").look))
	check(not CosmeticArt.is_default_pop(pop))
	var fx := CosmeticArt.pop_burst(pop, Vector2(10, 20), 16.0, Color.RED)
	var n := 0
	for f in fx:
		if f.kind == "pdot":
			n += 1
			check(f.has("flutter"))
	check_eq(n, int(pop.count))
	check(CosmeticArt.splat_color(pop, Color.RED) == null, "confetti leaves no splat")
