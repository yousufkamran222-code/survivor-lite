extends TestCase
## Boss Rift: opening after an Outbreak, the arena, the Phage Carrier's Seeker
## Phage, the 1-HP ejection with its frozen grace, and Rift Powers.

const DT := 1.0 / 30.0


func _world(seed_value: int = 3) -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), seed_value)
	w.emit_events = true
	w.rift_on = true  # the rift is switched off in data (shelved); its rules stay tested
	w.owned["bolt"] = 3
	w._recompute_stats()
	return w


func _rc() -> Dictionary:
	return data().balance.rift


func _events(w: World, type: String) -> Array:
	var out := []
	for ev in w.events:
		if ev.type == type:
			out.append(ev)
	return out


func test_outbreak_schedules_a_rift_that_opens_away_from_you() -> void:
	var w := _world()
	w.outbreak = 1.0
	check(w.trigger_outbreak())
	check_eq(w.rift_state, World.RIFT_PENDING)
	check(w.rift_timer >= float(_rc().delay_min_s) and w.rift_timer <= float(_rc().delay_max_s), "opens 5-10 s later")
	w.rift_timer = 0.01
	w.step(DT, Vector2.ZERO)
	check_eq(w.rift_state, World.RIFT_OPEN)
	check(w.rift_pos.distance_to(w.p_pos) >= float(_rc().spawn_min) - 5.0, "not right next to the player")


func test_rift_closes_if_ignored() -> void:
	var w := _world()
	w.rift_state = World.RIFT_OPEN
	w.rift_pos = w.p_pos + Vector2(600, 0)
	w.rift_timer = 0.05
	w.step(DT, Vector2.ZERO)
	w.step(DT, Vector2.ZERO)
	check_eq(w.rift_state, World.RIFT_NONE)


func test_entering_freezes_the_run() -> void:
	var w := _world()
	w._add_enemy("grunt", w.p_pos + Vector2(200, 0))
	var germ_pos := w.e_pos[0]
	w._enemy_shot(w.p_pos + Vector2(300, 0), Vector2.LEFT, 100.0, 5.0)
	var home := w.p_pos
	w.rift_state = World.RIFT_OPEN
	w.rift_pos = w.p_pos
	w.rift_timer = 5.0
	w.step(DT, Vector2.ZERO)
	var t0 := w.time
	check_eq(w.rift_state, World.RIFT_ACTIVE)
	check(w.p_pos.distance_to(World.RIFT_CENTER) < float(_rc().arena_radius), "player is in the arena")
	check(w.rift_boss_index() >= 0, "the Carrier is there")
	check_eq(w.s_pos.size(), 0, "the run's shots are set aside")
	for f in 30:
		w.step(DT, Vector2.ZERO)
	check_near(w.time, t0, 0.001, "run clock frozen")
	check(w.e_pos[0].distance_to(germ_pos) < 0.01, "germs frozen")
	w._rift_exit("timeout")
	check(w.p_pos.distance_to(home) < 1.0, "back where you left")
	check_eq(w.s_pos.size(), 1, "shots restored")
	check(w.rift_grace > 0.0, "short freeze on the way out")


func test_rift_times_out() -> void:
	var w := _world()
	w.owned.clear()  # no weapons: the Carrier can't die
	w._recompute_stats()
	w._rift_enter()
	w.bal.debug.invincible = true
	for f in int((float(_rc().duration_s) + 0.5) / DT):
		w.step(DT, Vector2.ZERO)
	check_eq(w.rift_state, World.RIFT_NONE)
	check_eq(w.rifts_timeout, 1)


func test_seeker_phage_tracks_locks_and_hits_the_carrier() -> void:
	var w := _world()
	w._rift_enter()
	var bi := w.rift_boss_index()
	# Line up: phage, then the player, then the Carrier; the player stands aside on fire.
	w.m_state = 3
	w.m_t = 0.0
	w.m_pos = w.e_pos[bi] + Vector2(-400, 0)
	w.m_dir = Vector2.RIGHT
	w.p_pos = w.e_pos[bi] + Vector2(-200, 120)
	var hp := w.e_hp[bi]
	for f in 30:
		w._update_rift_boss(DT)
		if w.m_state == 0:
			break
	check(w.e_hp[bi] < hp - w.e_maxhp[bi] * float(_rc().boss.missile.boss_damage_frac) * 0.9, "big hit on its creator")
	check(w.rb_stun > 0.0, "Carrier stunned")
	check_eq(w.missile_hits_boss, 1)


func test_phage_locks_after_tracking() -> void:
	var w := _world()
	w._rift_enter()
	w.m_state = 1
	w.m_t = 0.0
	w.m_pos = w.p_pos + Vector2(300, 0)
	w.m_dir = Vector2.LEFT
	var locked_at := -1.0
	for f in int((float(_rc().boss.missile.track_s) + 0.2) / DT):
		w._update_rift_boss(DT)
		if w.m_state >= 2 and locked_at < 0.0:
			locked_at = f * DT
	check(locked_at > 0.0, "locked by the end of tracking")
	check(locked_at >= float(_rc().boss.missile.min_track_s) - 0.05, "not before the minimum tracking time")


func test_dying_in_the_rift_ejects_at_1_hp_with_a_frozen_grace() -> void:
	var w := _world()
	w._add_enemy("grunt", w.p_pos + Vector2(150, 0))
	var germ_pos := w.e_pos[0]
	w._rift_enter()
	w._hurt(1.0e6, "test")
	check_eq(w.state, "playing", "not dead")
	check_near(w.p_hp, 1.0, 0.001)
	check_eq(w.rift_state, World.RIFT_NONE)
	check(w.rift_ejected)
	check_near(w.rift_grace, float(_rc().eject_grace_s), 0.001)
	var p0 := w.p_pos
	for f in 20:
		w.step(DT, Vector2.RIGHT)
	check(w.p_pos.x > p0.x + 10.0, "you can move during the grace")
	check(w.e_pos[0].distance_to(germ_pos) < 0.01, "everyone else stays frozen")
	check_eq(w.rifts_ejected, 1)


func test_win_grants_the_power_of_your_strongest_weapon() -> void:
	var w := _world()
	w.owned["chain"] = 5
	w._recompute_stats()
	w._rift_enter()
	var bi := w.rift_boss_index()
	w._damage(bi, 1.0e9, Vector2.ZERO, false)
	w.step(DT, Vector2.ZERO)
	check_eq(w.rifts_won, 1)
	check_eq(w.rift_power, "lance", "Nerve Spark is the strongest -> Lightning Lance")
	check_eq(w.rift_power_lv, 1)
	check(w.rp_kills >= w.rift_power_cost(), "the meter starts full")
	check(not w.rift_power_ready(), "but not during the exit freeze")
	# Winning again with the same strongest weapon levels it up.
	w.rift_grace = 0.0
	w._rift_enter()
	w._damage(w.rift_boss_index(), 1.0e9, Vector2.ZERO, false)
	w.step(DT, Vector2.ZERO)
	check_eq(w.rift_power_lv, 2)


func test_ties_pick_one_of_the_tied_weapons() -> void:
	var seen := {}
	for s in 12:
		var w := _world(40 + s)
		w.owned["nova"] = 3  # ties with bolt 3
		w._recompute_stats()
		w._grant_rift_power()
		seen[w.rift_power] = true
	check(seen.has("barrage") and seen.has("heatwave"), "either tied weapon can be picked")
	check(not seen.has("lance"))


func test_each_power_hurts_germs_and_refills_with_kills() -> void:
	for pw in ["lance", "barrage", "phalanx", "heatwave"]:
		var w := _world()
		w.rift_power = pw
		w.rift_power_lv = 1
		w.rp_kills = w.rift_power_cost()
		w.p_facing = Vector2.RIGHT
		for k in 6:
			w._add_enemy("brute", w.p_pos + Vector2(120 + 30 * k, 0))
		var hp := 0.0
		for i in w.enemy_count():
			hp += w.e_hp[i]
		check(w.use_rift_power(), "%s fires" % pw)
		check(not w.rift_power_ready(), "%s: meter empties" % pw)
		for f in 45:
			w.step(DT, Vector2.ZERO)
		var after := 0.0
		for i in w.enemy_count():
			after += w.e_hp[i]
		check(after < hp, "%s damages germs" % pw)
		check(float(w.damage_by.get("power", 0.0)) > 0.0, "%s damage is tagged" % pw)


func test_validation_catches_bad_power() -> void:
	var d := data().duplicate(true)
	d.balance.rift.enabled = true
	d.balance.rift.weapon_power.bolt = "laser"
	check(GameData.validate(d).size() > 0)


func test_bot_rift_run_is_stable() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 77)
	w.emit_events = false
	var bot := BalanceBot.new(77)
	w.owned["bolt"] = 3
	w._recompute_stats()
	w._rift_enter()
	for f in int(30.0 / DT):
		if w.state == "levelup":
			w.close_levelup()
		w.step(DT, bot.move(w))
		if w.rift_state != World.RIFT_ACTIVE and w.rift_grace <= 0.0:
			break
	check(w.rift_state != World.RIFT_ACTIVE, "the fight ends")
	check_eq(w.state, "playing")


func test_rift_is_off_in_every_mode() -> void:
	for m in data().modes:
		var w := World.new(GameData.apply_mode(data(), m.id), 1)
		check(not w.rift_on, "no rift in %s (shelved 2026-11-04)" % m.id)
		w.outbreak = 1.0
		w.trigger_outbreak()
		check_eq(w.rift_state, World.RIFT_NONE)
