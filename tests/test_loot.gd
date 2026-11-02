extends TestCase
## Elites, chests, evolutions, rare pickups and dash.

const DT := 1.0 / 60.0


func _world(seed_value: int = 1) -> World:
	var w := World.new(data(), seed_value)
	w.emit_events = false
	return w


func _max(w: World, id: String) -> void:
	w.owned[id] = Upgrades.max_level(w.upgrade_defs[id])
	w._recompute_stats()


func test_scope_evolutions() -> void:
	check(data().evolutions.size() <= 4, "v1 scope: one evolution per weapon")


func test_director_schedules_elites() -> void:
	var d := data()
	var by_id := {}
	for e in d.enemies:
		by_id[e.id] = e
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var dir := SpawnDirector.new(d.waves, by_id, rng)
	var elites := 0
	var t := 0.0
	while t < 200.0:
		for o in dir.update(0.1, t, 0):
			if o.get("elite", false):
				elites += 1
				check(d.waves.elites.types.has(o.id), "elite type %s not allowed" % o.id)
		t += 0.1
	var el: Dictionary = d.waves.elites
	var expected := int(floor((200.0 - float(el.first_s)) / float(el.every_s))) + 1
	check_eq(elites, expected, "elite count by 200s")


func test_elite_is_bigger_tougher_and_drops_chest() -> void:
	var w := _world()
	w._add_enemy("grunt", Vector2(300, 0))
	w._add_enemy("grunt", Vector2(-300, 0), true)
	check(w.enemy_radius(1) > w.enemy_radius(0), "elite radius")
	check(w.e_maxhp[1] > w.e_maxhp[0] * 5.0, "elite hp")
	w._damage(1, 1.0e6, Vector2.ZERO)
	w._process_dead()
	check_eq(w.c_pos.size(), 1, "elite drops a chest")
	check_eq(w.elites_killed, 1)


func test_touching_chest_opens_and_rewards() -> void:
	var w := _world()
	w._drop_chest(w.p_pos + Vector2(10, 0), 1)
	var levels_before := 0
	for id in w.owned:
		levels_before += int(w.owned[id])
	w._update_pickups()
	check_eq(w.state, "chest")
	check_eq(w.chest_rewards.size(), 1)
	var levels_after := 0
	for id in w.owned:
		levels_after += int(w.owned[id])
	check_eq(levels_after, levels_before + 1, "chest grants a level")
	w.close_chest()
	check_eq(w.state, "playing")
	check_eq(w.c_pos.size(), 0)


func test_chest_evolves_ready_weapon() -> void:
	var w := _world()
	_max(w, "bolt")
	w.owned["multishot"] = 1
	w._recompute_stats()
	check_eq(w.ready_evolutions(), ["bolt"])
	var count_before: float = w.wstats.bolt.count
	w._open_chest(1)
	check_eq(w.evolved.get("bolt", ""), "storm")
	check_eq(w.chest_rewards[0].kind, "evolution")
	check(w.wstats.bolt.count > count_before, "evolution adds bolts")
	check(w.ready_evolutions().is_empty(), "no double evolution")


func test_no_evolution_without_passive() -> void:
	var w := _world()
	_max(w, "bolt")
	check(w.ready_evolutions().is_empty())
	w._open_chest(1)
	check(not w.evolved.has("bolt"))


func test_evolved_orbit_heals_and_chain_forks() -> void:
	var w := _world()
	w.owned["orbit"] = 5
	w.owned["vitality"] = 1
	w.owned["chain"] = 5
	w.owned["haste"] = 1
	w._recompute_stats()
	w._open_chest(2)
	check(w.evolved.has("orbit") and w.evolved.has("chain"), "both evolve from a 2-item chest")
	check(w.wstats.orbit.has("heal_on_hit"))
	check_eq(int(w.wstats.chain.forks), 3)
	# Healing: put an enemy on an antibody and step.
	w.close_chest()
	w.p_hp = 10.0
	for i in 40:
		w._add_enemy("brute", w.p_pos + Vector2(110, 0))
	w.time = 0.0
	for i in 30:
		w.step(DT, Vector2.ZERO)
	check(w.p_hp > 10.0, "antibodies heal on hit")


func test_vacuum_pulls_all_gems() -> void:
	var w := _world()
	for k in 10:
		w._drop_gem(Vector2(900 + k * 10, 0), 1.0)
	w._apply_pickup("vacuum", w.p_pos)
	for i in 120:
		w._update_gems(DT)
	check_eq(w.g_pos.size(), 0, "all gems collected")


func test_heal_pickup() -> void:
	var w := _world()
	w.p_hp = 10.0
	w._apply_pickup("heal", w.p_pos)
	check_near(w.p_hp, 10.0 + w.p_max_hp * float(data().balance.pickups.heal_frac))


func test_bomb_kills_normal_but_not_elite() -> void:
	var w := _world()
	w._add_enemy("grunt", Vector2(200, 0))
	w._add_enemy("brute", Vector2(-200, 0), true)
	w._add_enemy("grunt", Vector2(5000, 0))
	w._rebuild_grid()
	w._apply_pickup("bomb", w.p_pos)
	check_eq(w.enemy_count(), 2, "near normal dies, elite and far grunt live")
	check(w.is_elite(0) or w.is_elite(1))


func test_pickup_collected_on_touch() -> void:
	var w := _world()
	w.i_pos.append(w.p_pos + Vector2(5, 0))
	w.i_kind.append(World.PICKUP_KINDS.find("heal"))
	w._update_pickups()
	check_eq(w.i_pos.size(), 0)


func test_dash_moves_fast_with_iframes_and_cooldown() -> void:
	var w := _world()
	w.step(DT, Vector2.RIGHT)
	var x0 := w.p_pos.x
	check(w.dash(), "first dash works")
	check(w.p_iframes > 0.0, "dash gives iframes")
	check(not w.dash(), "cooldown blocks a second dash")
	for i in 6:
		w.step(DT, Vector2.RIGHT)
	var walked := float(data().balance.player.speed) * DT * 6
	check(w.p_pos.x - x0 > walked * 2.5, "dash covers much more ground than walking")
	check_eq(w.dashes, 1)


func test_bot_run_with_loot_is_stable() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 11)
	w.emit_events = false
	var bot := BalanceBot.new(11)
	for i in int(120.0 / DT):
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		elif w.state == "chest":
			w.close_chest()
		elif w.state != "playing":
			break
		w.step(DT, bot.move(w))
	check(w.elites_killed + w.c_pos.size() >= 1 or w.state == "dead", "an elite was met by 2:00")
	check(w.dashes > 0, "bot dashes")


func test_antibodies_destroy_enemy_shots() -> void:
	var w := _world()
	w.owned["orbit"] = 1
	w._recompute_stats()
	w._update_weapons(1.0 / 60.0)
	var orb: Vector2 = w.orbit_points[0]
	w._enemy_shot(orb + Vector2(2, 0), Vector2.RIGHT, 0.0, 10.0)
	w._enemy_shot(w.p_pos + Vector2(600, 0), Vector2.RIGHT, 0.0, 10.0)
	w._update_weapons(0.0)
	check_eq(w.s_pos.size(), 1, "shot touching an antibody is destroyed, far one survives")
