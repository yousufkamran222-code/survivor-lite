extends TestCase

const DT := 1.0 / 60.0


func _world(seed_value: int = 1) -> World:
	var w := World.new(data(), seed_value)
	w.emit_events = false
	return w


func _run_bot(w: World, seconds: float) -> void:
	var bot := BalanceBot.new(w.rng.seed)
	var steps := int(seconds / DT)
	for i in steps:
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		if w.state == "chest":
			w.close_chest()
		if w.state != "playing":
			break
		w.step(DT, bot.move(w))


func test_starts_with_start_weapon() -> void:
	var w := _world()
	check_eq(w.owned, {data().balance.start_weapon: 1})
	check_near(w.p_hp, w.p_max_hp)


func test_deterministic_for_seed() -> void:
	var a := _world(42)
	var b := _world(42)
	_run_bot(a, 40.0)
	_run_bot(b, 40.0)
	check_eq(a.kills, b.kills, "same seed, same kills")
	check_eq(a.p_pos, b.p_pos, "same seed, same position")
	check_eq(a.enemy_count(), b.enemy_count())


func test_spawns_and_kills_early() -> void:
	var w := _world(5)
	_run_bot(w, 30.0)
	check(w.kills > 5, "bolt should kill early germs, kills=%d" % w.kills)
	check(w.level >= 2, "should level up in the first 30s, level=%d" % w.level)


func test_enemy_cap_respected() -> void:
	var w := _world(9)
	var cap := int(data().waves.max_alive)
	w.time = 250.0
	for i in 600:
		w.step(DT, Vector2.ZERO)
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(w.offers[0])
		if w.state == "dead":
			break
		# Splits and scripted rings may briefly exceed the soft cap; bound it.
		check(w.enemy_count() <= cap + 60, "enemy count %d far above cap" % w.enemy_count())


func test_levelup_flow_banked() -> void:
	var w := _world(3)
	var b: Dictionary = data().balance
	w.xp = Progression.xp_needed(b, 1) + Progression.xp_needed(b, 2) + Progression.xp_needed(b, 3) + 0.5
	w.emit_events = true
	w.step(DT, Vector2.ZERO)
	check_eq(w.state, "playing", "level-ups are banked, the game keeps going")
	check(w.pending_levelups >= 3, "multiple level-ups bank up")
	var lv := w.level
	check(w.open_banked(), "player opens the picker")
	check_eq(w.state, "levelup")
	var first: String = w.offers[0]
	var before := int(w.owned.get(first, 0))
	var banked := w.pending_levelups
	w.choose_upgrade(first)
	check_eq(int(w.owned[first]), before + 1)
	check_eq(w.state, "levelup", "the picker stays open while picks remain")
	check_eq(w.pending_levelups, banked - 1)
	w.close_levelup()
	check_eq(w.state, "playing", "Later closes the picker")
	check_eq(w.pending_levelups, banked - 1, "remaining picks stay banked")
	check_eq(w.level, lv)


func test_choose_ignores_invalid() -> void:
	var w := _world()
	w.choose_upgrade("bolt")  # not in levelup state
	check_eq(int(w.owned.bolt), 1)


func test_damage_kills_and_drops_gem() -> void:
	var w := _world()
	w._add_enemy("grunt", Vector2(100, 0))
	w._rebuild_grid()
	w._damage(0, 1.0e6, Vector2.ZERO)
	w._process_dead()
	check_eq(w.enemy_count(), 0)
	check_eq(w.kills, 1)
	check_eq(w.g_pos.size(), 1)


func test_splitter_splits() -> void:
	var w := _world()
	w._add_enemy("splitter", Vector2(300, 0))
	w._damage(0, 1.0e6, Vector2.ZERO)
	w._process_dead()
	check_eq(w.enemy_count(), int(w.enemy_defs[w.enemy_idx.splitter].split_count))


func test_contact_damage_and_iframes() -> void:
	var w := _world()
	w._add_enemy("grunt", w.p_pos)
	w._rebuild_grid()
	w._contact_damage()
	var hp_after := w.p_hp
	check(hp_after < w.p_max_hp, "touching an enemy hurts")
	w._contact_damage()
	check_near(w.p_hp, hp_after, 0.001, "iframes prevent a second hit")


func test_death_and_revive() -> void:
	var w := _world()
	w._hurt(1.0e6, "test")
	check_eq(w.state, "dead")
	w._add_enemy("grunt", w.p_pos + Vector2(50, 0))
	w.revive()
	check_eq(w.state, "playing")
	check(w.p_hp > 0.0)
	check_eq(w.enemy_count(), 0, "revive clears nearby enemies")
	check_eq(w.revives_used, 1)


func test_vitality_heals_on_pick() -> void:
	var w := _world()
	w.p_hp = 50.0
	w.state = "levelup"
	w.offers = ["vitality"]
	w.pending_levelups = 1
	w.choose_upgrade("vitality")
	check_near(w.p_max_hp, 120.0)
	check_near(w.p_hp, 70.0)


func test_victory_at_run_length() -> void:
	var w := _world()
	w.time = w.run_length - DT * 0.5
	w.step(DT, Vector2.ZERO)
	check_eq(w.state, "won")


func test_gem_magnet_collects() -> void:
	var w := _world()
	w._drop_gem(w.p_pos + Vector2(40, 0), 1.0)
	for i in 30:
		w._update_gems(DT)
	check_eq(w.g_pos.size(), 0)
	check(w.xp > 0.0)


func test_gem_cap_keeps_new_drops_where_the_kill_was() -> void:
	# Regression: at the cap, XP used to merge into a random (often far,
	# off-screen) gem, so nearby kills looked like they dropped nothing.
	var w := World.new(data(), 3)
	w.p_pos = Vector2.ZERO
	var cap := int(w.bal.xp.max_gems)
	for k in cap:
		w._drop_gem(Vector2(100 + k, 0), 1.0)
	w.g_pos[0] = Vector2(9000, 0)  # the farthest gem
	w.g_pos[1] = Vector2(8990, 0)  # its neighbour
	var total := 0.0
	for v in w.g_val:
		total += v
	w._drop_gem(Vector2(50, 50), 5.0)
	check_eq(w.g_pos.size(), cap, "no new slot past the cap")
	check(w.g_pos.has(Vector2(50, 50)), "the new gem lands where the kill was")
	check_near(w.g_val[1], 2.0, 0.001, "the far gem folded into its neighbour")
	var after := 0.0
	for v in w.g_val:
		after += v
	check_near(after, total + 5.0, 0.001, "no XP lost")


func test_volatile_dash_kills_explode_and_chain() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 4)
	w.owned["lunge"] = 1
	w.owned["volatile"] = 1
	w._recompute_stats()
	w.p_pos = Vector2.ZERO
	w._add_enemy("grunt", Vector2(10, 0))  # dash kills this one
	w.e_hp[0] = 1.0
	w._add_enemy("brute", Vector2(40, 0))  # caught in the burst
	var brute_hp := w.e_hp[1]
	w._rebuild_grid()
	w.p_dash_dir = Vector2.RIGHT
	w._lunge_hits()
	w._process_dead()
	check_eq(w.kills, 1)
	check(w.e_hp[0] < brute_hp, "the burst hurt the neighbour")


func test_volatile_needs_dash_damage_to_be_offered() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 4)
	var ids := []
	for d in w._offerable():
		ids.append(d.id)
	check(not ids.has("volatile"), "no dash damage: Volatile is never offered")
	w.owned["lunge"] = 1
	w._recompute_stats()
	ids = []
	for d in w._offerable():
		ids.append(d.id)
	check(ids.has("volatile"), "with Lunge it can be offered")


func test_outbreak_fills_triggers_and_speeds_weapons() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 4)
	var o: Dictionary = w.bal.outbreak
	check(not w.trigger_outbreak(), "not ready at the start")
	for k in int(o.kills_to_fill):
		w._fill_outbreak(false, false)
	check(w.outbreak_ready())
	check(w.trigger_outbreak())
	check_near(w.outbreak_t, float(o.duration_s))
	check_eq(w.outbreak, 0.0)
	w._fill_outbreak(false, false)
	check_eq(w.outbreak, 0.0, "kills during the frenzy don't fill the meter")
	# Weapons recharge faster during the frenzy.
	w.cooldowns["bolt"] = 1.0
	w._update_weapons(0.1)
	check_near(w.cooldowns["bolt"], 1.0 - 0.1 * float(o.weapon_speed), 0.001)
	w.step(float(o.duration_s) + 0.1, Vector2.ZERO)
	check_eq(w.outbreak_t, 0.0, "the frenzy ends")


func test_outbreak_fires_bomb_vacuum_and_heal() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 4)
	w.p_pos = Vector2.ZERO
	w._add_enemy("grunt", Vector2(120, 0))
	w._drop_gem(Vector2(300, 0), 3.0)
	w._drop_gem(Vector2(5000, 0), 3.0)  # far off: Outbreak's vacuum is local
	w.p_hp = 10.0
	w.outbreak = 1.0
	w._rebuild_grid()
	check(w.trigger_outbreak())
	check_eq(w.kills, 1, "bomb: the nearby germ died")
	check_eq(w.g_pull[0], 1, "vacuum: nearby gems are pulled in")
	check_eq(w.g_pull[1], 0, "but not the whole map")
	check(w.p_hp > 10.0, "heal")
	check_eq(w.outbreak, 0.0, "the bomb's kills don't refill the meter")
