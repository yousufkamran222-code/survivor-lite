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


func test_meta_shop_is_deep() -> void:
	var meta: Array = data().meta
	var tiers := 0
	var dash := 0
	for m in meta:
		tiers += m.costs.size()
		if str(m.stat).begins_with("dash_"):
			dash += 1
	check(meta.size() >= 12, "plenty of permanent upgrades")
	check(tiers >= 80, "many tiers in total")
	check(dash >= 3, "dash-based permanent upgrades exist")


func test_meta_total_text() -> void:
	var pct := {"per_level": 0.04, "fmt": "pct"}
	var flat := {"per_level": 10, "fmt": "flat"}
	check_eq(Progression.meta_total_text(pct, 3), "+12%")
	check_eq(Progression.meta_total_text(flat, 2), "+20")
	check_eq(Progression.meta_total_text(flat, 0), "")


func test_meta_dash_charge_starts_full() -> void:
	var meta := Progression.meta_bonus(data().meta, {"meta_dash_charge": 1})
	var w := World.new(data(), 1, meta)
	check_eq(w.dash_max_charges(), 2)
	check_eq(w.p_dash_charges, 2, "run starts with both charges")


func test_meta_dash_damage_enables_lunge() -> void:
	var meta := Progression.meta_bonus(data().meta, {"meta_dash_dmg": 2})
	var w := World.new(data(), 1, meta)
	w.emit_events = false
	w._add_enemy("brute", w.p_pos + Vector2(60, 0))
	var hp := w.e_hp[0]
	w.p_move = Vector2.RIGHT
	w.dash()
	for i in 10:
		w._rebuild_grid()
		w._update_player(1.0 / 60.0, Vector2.RIGHT)
	check(w.e_hp[0] < hp, "permanent Spiked Membrane makes the dash hurt")


func test_meta_effect_text_reads_as_words() -> void:
	var pct := {"per_level": 0.04, "fmt": "pct", "label": "damage"}
	check_eq(Progression.meta_effect_text(pct, 3), "+12% damage")
	check_eq(Progression.meta_effect_text(pct, 0), "None yet")
	for m in data().meta:
		check(str(m.get("label", "")) != "", "%s has a shop label" % m.id)
