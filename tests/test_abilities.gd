extends TestCase
## Lab phase 2: abilities (Stasis, Engulf, Cloak, Mitosis), their Lab nodes,
## equipping, the kill meter and each effect.

const DT := 1.0 / 60.0


func _world(id: String, lv: int = 1, seed_value: int = 5) -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), seed_value)
	w.emit_events = false
	w.equip_ability(id, lv)
	return w


## Fills the meter and fires.
func _fire(w: World) -> void:
	w.ab_kills = w.ability_cost()
	check(w.use_ability(), "ability fires when the meter is full")


func test_every_ability_has_a_branch_node() -> void:
	var cfg: Dictionary = data().lab
	check_eq(Lab.ability_ids(cfg).size(), 4)
	for id in Lab.ability_ids(cfg):
		var n := Lab.ability_node(cfg, id)
		check(not n.is_empty(), id)
		check_eq(str(Lab.branch_of(cfg, n.id).id), str(cfg.abilities[id].branch), "%s sits in its own branch" % id)


func test_unlock_and_equip() -> void:
	var cfg: Dictionary = data().lab
	var p := Profile.new()
	p.genes = 999
	check(not p.equip_ability(cfg, "stasis"), "locked abilities can't be equipped")
	for b in cfg.branches:
		if b.id != "toxin":
			continue
		for n in b.nodes:
			if n.get("fork", "") == "toxin" and n.id != "tox_overclock":
				continue
			p.buy_lab(cfg, n, 1)
	check_eq(Lab.ability_level(cfg, p.lab, "stasis"), 1, "the tier-6 node unlocks it at level 1")
	check(p.equip_ability(cfg, "stasis"))
	check_eq(p.equipped_ability(cfg), "stasis")
	p.gold = 9999
	p.respec_lab(cfg, 2)
	check_eq(p.equipped_ability(cfg), "", "a respec un-equips (it's locked again)")


func test_ability_stats_per_level() -> void:
	var cfg: Dictionary = data().lab
	var a1 := Lab.ability_stats(cfg, "cloak", 1)
	var a3 := Lab.ability_stats(cfg, "cloak", 3)
	check(float(a3.duration_s) > float(a1.duration_s), "longer at higher levels")
	check(float(a3.kills) < float(a1.kills), "recharges faster at higher levels")


func test_meter_fills_with_kills() -> void:
	var w := _world("cloak")
	check(not w.ability_ready(), "starts empty")
	check(not w.use_ability())
	for k in int(w.ability_cost()):
		w._add_enemy("grunt", Vector2(300, 0))
		w._damage(w.e_pos.size() - 1, 1.0e6, Vector2.ZERO)
		w._process_dead()
	check(w.ability_ready(), "ready after `kills` kills")


func test_no_ability_no_change() -> void:
	var w := _world("")
	check_eq(w.ability, "")
	check(not w.ability_ready())


func test_stasis_freezes_and_shocks() -> void:
	var w := _world("stasis")
	w._add_enemy("grunt", Vector2(250, 0))
	w._enemy_shot(Vector2(200, 0), Vector2.LEFT, 100.0, 5.0)
	_fire(w)
	var e0 := w.e_pos[0]
	var s0 := w.s_pos[0]
	var hp := w.e_hp[0]
	w.p_hp = w.p_max_hp
	for i in 30:
		w.step(DT, Vector2.ZERO)
	if w.e_pos.size() > 0 and w.e_hp[0] >= hp:
		check_eq(w.e_pos[0], e0, "germs don't move")
	if w.s_pos.size() > 0:
		check_eq(w.s_pos[0], s0, "shots don't move")
	w.stasis_kills = 5
	w.ab_t = DT * 0.5
	w._add_enemy("brute", w.p_pos + Vector2(100, 0))
	var bi := w.e_pos.size() - 1
	var bhp := w.e_hp[bi]
	w.step(DT, Vector2.ZERO)
	check(not w.stasis_on(), "time restarts")
	check(w.e_pos.size() <= bi or w.e_hp[bi] < bhp, "the shockwave hits (or kills)")
	check(w.e_pos.size() <= bi or w.e_knock[bi].length() > 0.0, "and throws germs back")


func test_engulf_swallows_and_heals() -> void:
	var w := _world("engulf")
	var r0 := w.p_radius
	_fire(w)
	check_near(w.p_radius, r0 * 3.0)
	w.p_hp = 50.0
	w._add_enemy("grunt", w.p_pos + Vector2(r0 * 2.0, 0))
	w._add_enemy("brute", w.p_pos + Vector2(-r0 * 2.0, 0), true)
	w._rebuild_grid()
	var elite_hp := w.e_hp[1]
	w._update_ability(DT)
	check(w.e_hp[0] <= 0.0, "the germ is swallowed whole")
	check(w.e_hp[1] > 0.0 and w.e_hp[1] < elite_hp, "the elite only takes a bite")
	check(w.p_hp > 50.0, "swallowing heals")
	w.ab_t = DT * 0.5
	w._update_ability(DT)
	check_near(w.p_radius, r0, 0.001, "back to normal size")


func test_cloak_loses_germs_and_ambush() -> void:
	var w := _world("cloak")
	w._add_enemy("grunt", Vector2(400, 0))
	_fire(w)
	w.p_pos = Vector2(-600, 0)  # sneak away
	for i in 60:
		w._rebuild_grid()
		w._update_enemies(DT)
	check(w.e_pos[0].distance_to(w.cloak_pos) < w.e_pos[0].distance_to(w.p_pos), "germs go to where they last saw you")
	w.ab_t = DT * 0.5
	w._update_ability(DT)
	check(w.ambush_t > 0.0, "ambush window after uncloaking")
	var hp := w.e_hp[0]
	w._damage(0, 2.0, Vector2.ZERO)
	check_near(hp - w.e_hp[0], 4.0, 0.001, "first hit x2")
	hp = w.e_hp[0]
	w._damage(0, 2.0, Vector2.ZERO)
	check_near(hp - w.e_hp[0], 2.0, 0.001, "second hit normal")


func test_mitosis_clone_fires() -> void:
	var w := _world("mitosis")
	_fire(w)
	check(not w._clone_w.is_empty())
	var wid: String = w.bal.start_weapon
	check_near(float(w._clone_w[wid].damage), float(w.wstats[wid].damage) * 0.5, 0.001, "half power")
	w._add_enemy("grunt", Vector2(150, 0))
	var shots := 0
	for i in 120:
		var before := w.b_pos.size()
		w.step(DT, Vector2.ZERO)
		shots = maxi(shots, w.b_pos.size())
	check(shots >= 1, "weapons fire")
	check(w.clone_pos.distance_to(w.p_pos) > 10.0, "the clone stands beside you")
	check_eq(w.cooldowns.size(), w.wstats.size(), "player cooldowns untouched")
