extends TestCase
## Swarm orders (Guard / Hunt / Harvest), ally scaling and the Outbreak boost.

const DT := 1.0 / 60.0


func _world(seed_value: int = 1) -> World:
	var d := GameData.apply_mode(data(), "swarm")
	d.balance.conversion.base_chance = 1.0
	var w := World.new(d, seed_value)
	w.emit_events = false
	return w


## One ally at `at`; conversion is switched off afterwards so later kills stay kills.
func _ally(w: World, at: Vector2, id: String = "grunt") -> int:
	w._add_enemy(id, at)
	var i := w.enemy_count() - 1
	w._damage(i, 1.0e6, Vector2.ZERO, false)
	w._process_dead()
	w.bal.conversion.base_chance = 0.0
	return i


## Moves allies/enemies only (no spawns, weapons or contact damage).
func _move(w: World, seconds: float) -> void:
	for f in int(seconds / DT):
		w._frame += 1
		w._rebuild_grid()
		w._update_enemies(DT)
		w.time += DT


func test_default_order_is_guard() -> void:
	var w := _world()
	check_eq(w.ally_order, World.ORDER_GUARD)
	var classic := World.new(GameData.apply_mode(data(), "classic"), 1)
	check(not classic.set_ally_order(World.ORDER_HUNT), "no orders outside Swarm")


func test_switch_has_a_cooldown() -> void:
	var w := _world()
	check(w.set_ally_order(World.ORDER_HUNT))
	check_eq(w.ally_order, World.ORDER_HUNT)
	check(not w.set_ally_order(World.ORDER_HARVEST), "cooldown blocks a second switch")
	check(not w.set_ally_order(World.ORDER_HUNT), "same order is a no-op")
	w.step(float(data().balance.conversion.order_switch_s) + 0.05, Vector2.ZERO)
	check(w.set_ally_order(World.ORDER_HARVEST), "allowed after the cooldown")
	check_eq(w.order_changes, 2)


func test_hunt_sends_allies_at_nearby_germs() -> void:
	var w := _world()
	var a := _ally(w, w.p_pos + Vector2(100, 0))
	w._add_enemy("brute", w.p_pos + Vector2(0, 300))
	var e := w.enemy_count() - 1
	w.e_spd[e] = 0.0  # keep it parked
	w.set_ally_order(World.ORDER_HUNT)
	_move(w, 1.0)
	check(w.e_pos[a].distance_to(w.e_pos[e]) < 60.0, "ally went for the germ")


func test_guard_holds_the_ring() -> void:
	var w := _world()
	var a := _ally(w, w.p_pos + Vector2(100, 0))
	w._add_enemy("brute", w.p_pos + Vector2(0, 300))
	w.e_spd[w.enemy_count() - 1] = 0.0
	_move(w, 1.0)
	check(w.e_pos[a].distance_to(w.p_pos) < float(data().balance.conversion.ring_radius_max) + 20.0, "guard stays near you")


func test_hunt_ignores_far_germs() -> void:
	var w := _world()
	var a := _ally(w, w.p_pos + Vector2(100, 0))
	var r := float(data().balance.conversion.orders.hunt.radius)
	w._add_enemy("brute", w.p_pos + Vector2(0, r + 200.0))
	w.e_spd[w.enemy_count() - 1] = 0.0
	w.set_ally_order(World.ORDER_HUNT)
	_move(w, 1.0)
	check(w.e_pos[a].distance_to(w.p_pos) < r, "stays leashed to the player")


func test_harvest_fetches_stray_gems() -> void:
	var w := _world()
	_ally(w, w.p_pos + Vector2(100, 0))
	w.g_pos.clear()
	w.g_val.clear()
	w.g_pull.clear()
	w._drop_gem(w.p_pos + Vector2(700, 0), 3.0)
	var xp0 := w.xp
	# Guard leaves it lying there.
	for f in int(2.0 / DT):
		w.step(DT, Vector2.ZERO)
	check_eq(w.g_pull[0], 0, "nobody fetched it under Guard")
	w.set_ally_order(World.ORDER_HARVEST)
	for f in int(6.0 / DT):
		w.step(DT, Vector2.ZERO)
		if w.state == "levelup":
			w.close_levelup()
	check(w.gems_harvested >= 1, "an ally grabbed it")
	check(w.xp > xp0 or w.level > 1, "its XP reached the player")


func test_guard_takes_less_damage_than_hunt() -> void:
	var taken := []
	for o in [World.ORDER_GUARD, World.ORDER_HUNT]:
		var w := _world()
		var a := _ally(w, Vector2(300, 0))
		w._add_enemy("brute", Vector2(305, 0))
		w.set_ally_order(o)
		w._rebuild_grid()
		var hp := w.e_hp[a]
		w._ally_tick = 1.0
		w._update_ally_combat(DT)
		taken.append(hp - w.e_hp[a])
	check(taken[0] > 0.0)
	check_near(taken[0] / taken[1], float(data().balance.conversion.orders.guard.damage_taken_mult), 0.01)


func test_ally_damage_scales_with_enemy_hp_and_might() -> void:
	var w := _world()
	var p0 := w._ally_power()
	w.time = 240.0
	check_near(w._ally_power() / p0, w._hp_mult() / w.director.hp_mult(0.0), 0.01, "keeps pace with enemy HP")
	var p1 := w._ally_power()
	w.stats.might = 0.5
	check_near(w._ally_power() / p1, 1.5, 0.001, "Enzymes/Potency boost allies too")


func test_hunt_and_harvest_damage_mults() -> void:
	var w := _world()
	var g := w._ally_power()
	w.set_ally_order(World.ORDER_HUNT)
	check_near(w._ally_power() / g, float(data().balance.conversion.orders.hunt.damage_mult), 0.001)


func test_outbreak_boosts_allies() -> void:
	var w := _world()
	var p0 := w._ally_power()
	w.outbreak_t = 1.0
	check_near(w._ally_power() / p0, float(data().balance.outbreak.ally_damage_mult), 0.001)


func test_ally_damage_is_tracked() -> void:
	var w := _world()
	_ally(w, Vector2(300, 0))
	w._add_enemy("brute", Vector2(305, 0))
	w._rebuild_grid()
	var before := w.damage_dealt
	w._ally_tick = 1.0
	w._update_ally_combat(DT)
	check(w.ally_damage > 0.0)
	check_near(w.damage_dealt - before, w.ally_damage, 0.001, "ally hits count in both totals")


func test_bot_switches_orders() -> void:
	var w := _world(31)
	w.bal.conversion.base_chance = float(data().balance.conversion.base_chance)
	var bot := BalanceBot.new(31)
	for i in int(120.0 / DT):
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		elif w.state == "chest":
			w.close_chest()
		elif w.state != "playing":
			break
		w.step(DT, bot.move(w))
	check(w.order_changes > 0, "the bot gives orders")


func test_validation_needs_every_order() -> void:
	var d := data().duplicate(true)
	d.balance.conversion.orders.erase("harvest")
	var errs := GameData.validate(d)
	check(errs.size() > 0, "missing order is reported")
