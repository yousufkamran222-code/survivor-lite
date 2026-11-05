extends TestCase
## The Lab (data/lab.json): tiers, forks, Genes, respec, Profile v5, merge,
## and the World hooks for each fork and keystone.

const DT := 1.0 / 60.0


func _cfg() -> Dictionary:
	return data().lab


func _node(id: String) -> Dictionary:
	return Lab.find(_cfg(), id)


## A classic-mode World with a Lab bonus (only the given node ids, maxed).
func _world(ids: Array, seed_value: int = 3) -> World:
	var owned := {}
	for id in ids:
		owned[id] = Lab.max_level(_node(id))
	var d := GameData.apply_mode(data(), "classic")
	var w := World.new(d, seed_value, Progression.run_bonus(d, {}, owned))
	w.emit_events = false
	return w


func _rich(genes: int = 999) -> Profile:
	var p := Profile.new()
	p.genes = genes
	return p


# ---------------------------------------------------------------- logic

func test_branches_have_stat_nodes_fork_and_keystone() -> void:
	check_eq(_cfg().branches.size(), 4)
	for b in _cfg().branches:
		var forks := 0
		var keys := 0
		for n in b.nodes:
			forks += 1 if n.has("fork") else 0
			keys += 1 if n.get("keystone", false) else 0
		check_eq(forks, 2, "%s: one fork pair" % b.id)
		check_eq(keys, 1, "%s: one keystone" % b.id)


func test_tiers_gate_nodes() -> void:
	var p := _rich()
	var cfg := _cfg()
	check_eq(p.buy_lab(cfg, _node("tox_rapid"), 1), 0, "tier 2 locked before tier 1")
	check(p.buy_lab(cfg, _node("tox_venom"), 1) > 0)
	check(p.buy_lab(cfg, _node("tox_rapid"), 2) > 0, "tier 2 opens once tier 1 is owned")
	check_eq(p.buy_lab(cfg, _node("tox_lysis"), 3), 0, "keystone needs the fork")


func test_fork_is_exclusive() -> void:
	var p := _rich()
	var cfg := _cfg()
	for id in ["mem_bulk", "mem_wall", "mem_mend", "mem_biofilm"]:
		check(p.buy_lab(cfg, _node(id), 1) > 0, id)
	check_eq(p.buy_lab(cfg, _node("mem_thick"), 2), 0, "other side of the fork is blocked")
	check(Lab.fork_blocked(cfg, _node("mem_thick"), p.lab))
	check(p.buy_lab(cfg, _node("mem_second_wind"), 3) > 0, "either fork side opens the keystone")


func test_genes_and_costs() -> void:
	var p := _rich(2)
	var cfg := _cfg()
	check_eq(p.buy_lab(cfg, _node("gen_growth"), 1), 1)
	check_eq(p.genes, 1)
	check_eq(p.buy_lab(cfg, _node("gen_growth"), 1), 0, "level 2 costs 2, only 1 left")
	check_eq(p.lab_level("gen_growth"), 1)


func test_respec_refunds_genes_for_gold() -> void:
	var p := _rich(40)
	var cfg := _cfg()
	for id in ["fla_glide", "fla_glide", "fla_whip"]:
		p.buy_lab(cfg, _node(id), 1)
	var spent := 40 - p.genes
	check(spent > 0)
	p.gold = 10
	check_eq(p.respec_lab(cfg, 2), -1, "not enough gold")
	check_eq(p.genes, 40 - spent, "nothing changed")
	p.gold = int(cfg.respec_gold) + 5
	check_eq(p.respec_lab(cfg, 3), spent)
	check_eq(p.genes, 40)
	check_eq(p.gold, 5)
	check(p.lab.is_empty())


func test_full_lab_costs_and_bonus() -> void:
	var cfg := _cfg()
	var full := Lab.full_owned(cfg)
	check_eq(Lab.full_cost(cfg), 180, "full Lab price (one side of each fork, abilities maxed)")
	var bon := Lab.bonus(cfg, full)
	check_near(float(bon.might), 0.12)
	check_near(float(bon.max_hp), 30.0)
	check(bon.has("lysis") and bon.has("second_wind") and bon.has("slipstream") and bon.has("mutation"))
	var rb := Progression.run_bonus(data(), {"meta_might": 2}, full)
	check_near(float(rb.might), 0.12 + 0.08, 0.0001, "shop + Lab add up")


func test_effect_text() -> void:
	check_eq(Lab.effect_text(_node("tox_venom"), 2), "+8% damage")
	check_eq(Lab.effect_text(_node("mem_mend"), 2), "+0.3 HP per second")
	check_eq(Lab.effect_text(_node("mem_bulk"), 0), "None yet")


# ---------------------------------------------------------------- Genes

func _win(p: Profile, level: int, won: bool = true) -> void:
	var s := {"mode": "classic", "won": won, "time": 300.0, "kills": 300, "level": 20, "elites": 1, "chests": 1,
		"evolved_ids": [], "conversions": 0, "dashes": 10, "boss_killed": false, "kills_by_type": {}, "infected_pct": 0,
		"score": 100, "virulence": level}
	p.record_run(s, [], 10, _cfg().genes)


func test_genes_first_clear_then_repeat() -> void:
	var p := Profile.new()
	var fc: Array = _cfg().genes.first_clear
	_win(p, 1)
	check_eq(p.last_genes, int(fc[0]), "first clear of V1")
	_win(p, 1)
	check_eq(p.last_genes, int(_cfg().genes.repeat_win), "repeat win")
	_win(p, 2)
	check_eq(p.last_genes, int(fc[1]))
	_win(p, 3, false)
	check_eq(p.last_genes, 0, "a loss pays nothing")
	check_eq(p.genes, int(fc[0]) + int(_cfg().genes.repeat_win) + int(fc[1]))
	check_eq(int(p.stats.genes_earned), p.genes)


func test_no_genes_without_cfg() -> void:
	var p := Profile.new()
	var s := {"mode": "classic", "won": true, "time": 300.0, "kills": 1, "level": 1, "elites": 0, "chests": 0,
		"evolved_ids": [], "conversions": 0, "dashes": 0, "boss_killed": false, "kills_by_type": {}, "infected_pct": 0, "score": 1}
	p.record_run(s, [], 1)
	check_eq(p.genes, 0)


# ------------------------------------------------------------ save format

func test_v4_save_loads_with_empty_lab() -> void:
	var p := Profile.from_dict({"version": 4, "gold": 50, "meta_levels": {"meta_hp": 2}})
	check_eq(p.genes, 0)
	check(p.lab.is_empty())
	check(p.abilities.is_empty())
	check_eq(p.gold, 50)
	check_eq(int(p.stats.genes_earned), 0)


func test_lab_roundtrips() -> void:
	var p := _rich(9)
	p.lab = {"tox_venom": 2, "tox_rapid": 1}
	p.abilities = {"stasis": 1}
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check_eq(q.genes, 9)
	check_eq(q.lab_level("tox_venom"), 2)
	check_eq(int(q.abilities.stasis), 1)
	check_eq(int(q.to_dict().version), Profile.VERSION)
	check_eq(Profile.VERSION, 5)


func test_merge_keeps_max_and_newer_fork() -> void:
	var a := Profile.new()
	a.lab = {"mem_bulk": 3, "mem_biofilm": 1}
	a.genes = 4
	a.updated_at = 100
	var b := Profile.new()
	b.lab = {"mem_bulk": 1, "mem_thick": 1, "tox_venom": 2}
	b.genes = 20
	b.updated_at = 50
	var m := Profile.merge(a, b, _cfg())
	check_eq(m.lab_level("mem_bulk"), 3, "keeps the higher level")
	check_eq(m.lab_level("tox_venom"), 2, "keeps nodes only the older copy had")
	check_eq(m.lab_level("mem_thick"), 0, "the newer copy's fork choice wins")
	check_eq(m.lab_level("mem_biofilm"), 1)
	check_eq(m.genes, 4, "spendable Genes come from the newer copy")


# ------------------------------------------------------------ World hooks

func test_overclock_cuts_max_hp() -> void:
	var base := _world([])
	var w := _world(["tox_overclock"])
	check_near(w.p_max_hp, base.p_max_hp * 0.9)
	check_near(w.p_hp, w.p_max_hp)
	check_near(float(w.stats.haste), float(base.stats.haste) + 0.15)


func test_crit_and_precision() -> void:
	var w := _world(["tox_burst"])
	w.stats["crit"] = 1.0  # always crit
	w._add_enemy("brute", Vector2(300, 0))
	var hp := w.e_hp[0]
	w._damage(0, 10.0, Vector2.ZERO)
	check_near(hp - w.e_hp[0], 10.0 * float(_cfg().tuning.crit_mult))
	check_eq(w.crits, 1)
	var p := _world(["tox_precision"])
	p._add_enemy("brute", Vector2(300, 0), true)
	p._add_enemy("brute", Vector2(-300, 0))
	var e0 := p.e_hp[0]
	var e1 := p.e_hp[1]
	p._damage(0, 10.0, Vector2.ZERO)
	p._damage(1, 10.0, Vector2.ZERO)
	check_near(e0 - p.e_hp[0], 12.5, 0.001, "elite takes +25%")
	check_near(e1 - p.e_hp[1], 10.0, 0.001, "normal germ unchanged")


func test_lysis_hurts_neighbours() -> void:
	var w := _world(["tox_lysis"])
	w._add_enemy("brute", Vector2(400, 0))
	w._add_enemy("grunt", Vector2(420, 0))
	var max0 := w.e_maxhp[0]
	var hp1 := w.e_hp[1]
	w._damage(0, 1.0e4, Vector2.ZERO)
	w._process_dead()
	check_eq(w.lysis_bursts, 1)
	check_eq(w.enemy_count(), 1)
	check_near(hp1 - w.e_hp[0], minf(hp1, max0 * 0.08), 0.01, "neighbour took 8% of the dead germ's max HP")


func test_biofilm_blocks_one_hit_then_recharges() -> void:
	var w := _world(["mem_biofilm"])
	var hp := w.p_hp
	w._hurt(30.0, "grunt")
	check_near(w.p_hp, hp, 0.001, "shield ate the hit")
	check(w.shield_cd > 0.0)
	w.p_iframes = 0.0
	w._hurt(30.0, "grunt")
	check(w.p_hp < hp, "second hit lands")
	w.shield_cd = 0.01
	w.step(DT, Vector2.ZERO)
	check(w.shield_cd <= 0.0, "recharges over time")


func test_thick_skin_longer_iframes() -> void:
	var w := _world(["mem_thick"])
	w._hurt(5.0, "grunt")
	check_near(w.p_iframes, float(w.bal.player.iframes_s) * 1.5)


func test_second_wind_once() -> void:
	var w := _world(["mem_second_wind"])
	w._add_enemy("grunt", Vector2(60, 0))
	w._rebuild_grid()
	w._hurt(1.0e5, "grunt")
	check_eq(w.state, "playing", "survived the killing blow")
	check(w.second_wind_used)
	check_near(w.p_hp, w.p_max_hp * 0.3, 0.01)
	check(w.e_hp[0] < w.e_maxhp[0] or w.e_knock[0].length() > 0.0, "shockwave hit the germ")
	w.p_iframes = 0.0
	w._hurt(1.0e5, "grunt")
	check_eq(w.state, "dead", "only once per run")


func test_twin_flagella() -> void:
	var base := _world([])
	var w := _world(["fla_twin"])
	check_eq(w.dash_max_charges(), base.dash_max_charges() + 1)
	check_near(w.dash_cooldown(), base.dash_cooldown() * 1.2)


func test_phase_destroys_shots_while_dashing() -> void:
	var w := _world(["fla_phase"])
	w._enemy_shot(Vector2(20, 0), Vector2.LEFT, 0.0, 10.0)
	check_eq(w.s_pos.size(), 1)
	w.dash()
	w._update_player(DT, Vector2.ZERO)
	check_eq(w.s_pos.size(), 0)


func test_slipstream_boost_after_dash() -> void:
	var w := _world(["fla_slipstream"])
	w.p_facing = Vector2.RIGHT
	w.dash()
	for i in 30:
		if w.p_dash_t <= 0.0:
			break
		w._update_player(DT, Vector2.RIGHT)
	check(w.slip_t > 0.0, "boost starts when the dash ends")
	w._add_enemy("grunt", w.p_pos + Vector2(10, 0))
	w._rebuild_grid()
	var hp := w.e_hp[0]
	w._update_player(DT, Vector2.RIGHT)
	check(w.e_hp[0] < hp, "the wake hurts germs you pass")


func test_head_start_second_weapon() -> void:
	var w := _world(["gen_head_start"])
	check_eq(w.owned.size(), 2)
	check(w.head_start_weapon != "" and w.head_start_weapon != str(w.bal.start_weapon))
	check_eq(int(w.owned[w.head_start_weapon]), 2)
	check_eq(w.upgrade_defs[w.head_start_weapon].type, "weapon")


func test_lucky_strain_four_offers() -> void:
	var w := _world(["gen_lucky"])
	w.pending_levelups = 1
	w.open_banked()
	check_eq(w.offers.size(), 4)


func test_mutation_gives_two_levels() -> void:
	var w := _world(["gen_mutation"])
	w.pending_levelups = 1
	w.open_banked()
	check(w.mutated_offer != "", "one offer is mutated")
	var id := w.mutated_offer
	var before := int(w.owned.get(id, 0))
	w.choose_upgrade(id)
	check_eq(int(w.owned[id]), before + 2)
	check_eq(w.mutated_offer, "")


func test_no_lab_no_change() -> void:
	var w := _world([])
	check_eq(w.owned.size(), 1)
	w.pending_levelups = 1
	w.open_banked()
	check_eq(w.offers.size(), int(w.bal.upgrades.offers_per_level))
	check_eq(w.mutated_offer, "")
