extends TestCase
## Prototype 2: Swarm mode (conversion of killed enemies into allies).

const DT := 1.0 / 60.0


func _world(chance: float = 1.0, seed_value: int = 1) -> World:
	var d := GameData.apply_mode(data(), "swarm")
	d.balance.conversion.base_chance = chance
	var w := World.new(d, seed_value)
	w.emit_events = false
	return w


func _kill(w: World, i: int) -> void:
	w._damage(i, 1.0e6, Vector2.ZERO, false)
	w._process_dead()


func test_classic_never_converts() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 1)
	w._add_enemy("grunt", Vector2(300, 0))
	_kill(w, 0)
	check_eq(w.enemy_count(), 0)
	check_eq(w.ally_count, 0)


func test_kill_converts_into_ally() -> void:
	var w := _world()
	w._add_enemy("grunt", Vector2(300, 0))
	var hp_enemy := w.e_maxhp[0]
	_kill(w, 0)
	check_eq(w.enemy_count(), 1, "body stays")
	check(w.is_ally(0), "now on our side")
	check_eq(w.ally_count, 1)
	check_eq(w.hostile_count(), 0)
	check_eq(w.kills, 1, "still counts as a kill")
	check_eq(w.g_pos.size(), 1, "still drops XP")
	check(w.e_hp[0] > hp_enemy, "allies are sturdier")


func test_elites_and_boss_never_convert() -> void:
	var w := _world()
	w._add_enemy("brute", Vector2(300, 0), true)
	w._add_enemy("boss", Vector2(-300, 0))
	_kill(w, 1)
	_kill(w, 0)
	check_eq(w.ally_count, 0)
	check_eq(w.c_pos.size(), 2, "both still drop chests")


func test_ally_cap() -> void:
	var w := _world()
	var cap := int(data().balance.conversion.max_allies)
	for k in cap + 5:
		w._add_enemy("grunt", Vector2(300 + k, 0))
	# Kill every hostile one at a time.
	var guard := 0
	while w.hostile_count() > 0 and guard < 100:
		for i in w.enemy_count():
			if not w.is_ally(i):
				_kill(w, i)
				break
		guard += 1
	check_eq(w.ally_count, cap, "never more allies than the cap")


func test_weapons_and_contact_ignore_allies() -> void:
	var w := _world()
	w._add_enemy("grunt", w.p_pos + Vector2(40, 0))
	_kill(w, 0)
	w.e_pos[0] = w.p_pos
	w._rebuild_grid()
	check_eq(w._nearest_enemy(w.p_pos, 500.0), -1, "weapons don't target allies")
	check(w.query(w.p_pos, 50.0).is_empty(), "default query skips allies")
	var hp := w.p_hp
	w._contact_damage()
	check_near(w.p_hp, hp, 0.001, "touching an ally doesn't hurt")


func test_allies_fight_enemies() -> void:
	var w := _world(0.0)
	w._add_enemy("grunt", Vector2(300, 0))
	w.conv_on = true
	w.bal.conversion.base_chance = 1.0
	_kill(w, 0)
	w.bal.conversion.base_chance = 0.0
	w._add_enemy("brute", Vector2(305, 0))
	w._rebuild_grid()
	var brute := 1
	var bhp := w.e_hp[brute]
	var ahp := w.e_hp[0]
	w._ally_tick = 1.0
	w._update_ally_combat(DT)
	check(w.e_hp[brute] < bhp, "ally hits the enemy")
	check(w.e_hp[0] < ahp, "enemy hits back")


func test_allies_expire() -> void:
	var w := _world()
	w._add_enemy("grunt", Vector2(100, 0))
	_kill(w, 0)
	w.e_life[0] = 0.05
	for k in 10:
		w._rebuild_grid()
		w._update_enemies(DT)
		w._process_dead()
	check_eq(w.ally_count, 0)
	check_eq(w.enemy_count(), 0)


func test_ranged_ally_shoots() -> void:
	var w := _world()
	w._add_enemy("spitter", Vector2(100, 0))
	_kill(w, 0)
	w._add_enemy("grunt", Vector2(100, 200))
	w._rebuild_grid()
	w.e_timer[0] = 0.0
	w._update_enemies(DT)
	check(w.b_pos.size() >= 1, "converted Spitter fires at enemies")


func test_swarm_upgrades_only_in_swarm() -> void:
	var swarm := _world()
	var classic := World.new(GameData.apply_mode(data(), "classic"), 1)
	var in_swarm := []
	for u in swarm.upgrade_list:
		in_swarm.append(u.id)
	var in_classic := []
	for u in classic.upgrade_list:
		in_classic.append(u.id)
	check(in_swarm.has("viral") and in_swarm.has("hijack"))
	check(not in_classic.has("viral"), "Swarm-only upgrades stay out of other modes")


func test_bot_swarm_run() -> void:
	var w := _world(float(data().balance.conversion.base_chance), 31)
	var bot := BalanceBot.new(31)
	var peak := 0
	for i in int(120.0 / DT):
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		elif w.state == "chest":
			w.close_chest()
		elif w.state != "playing":
			break
		w.step(DT, bot.move(w))
		peak = maxi(peak, w.ally_count)
		check(w.ally_count >= 0 and w.ally_count <= w._ally_cap(), "ally count in range")
	check(w.conversions > 0, "conversions happen in a normal run")
	check(peak > 0)
