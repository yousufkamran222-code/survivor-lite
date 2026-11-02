extends TestCase
## Prototype 1: bounded dish, loop-claiming, land effects, erosion.

const DT := 1.0 / 60.0


func _world(seed_value: int = 1) -> World:
	var d := data()
	d.balance.territory.enabled = true
	var w := World.new(d, seed_value)
	w.emit_events = false
	return w


## Walk the player along a list of waypoints at walking speed.
func _walk(w: World, points: Array) -> void:
	for target: Vector2 in points:
		var guard := 0
		while w.p_pos.distance_to(target) > 6.0 and guard < 2000:
			w.p_pos = w.p_pos.move_toward(target, 300.0 * DT)
			w._update_player(DT, Vector2.ZERO)
			w._update_territory(DT)
			guard += 1


func test_disabled_means_no_territory() -> void:
	var d := data()
	d.balance.territory.enabled = false
	check(World.new(d, 1).terr == null)


func test_home_patch_owned() -> void:
	var w := _world()
	check(w.terr.is_owned(Vector2.ZERO))
	check(not w.terr.is_owned(Vector2(600, 0)))
	check(w.terr.infected_fraction() > 0.0 and w.terr.infected_fraction() < 0.05)


func test_loop_claims_enclosed_area() -> void:
	var w := _world()
	var before := w.terr.owned_count
	# A square loop out of home and back: (0,0) -> right -> around -> home.
	_walk(w, [Vector2(150, 0), Vector2(500, 0), Vector2(500, 400), Vector2(0, 400), Vector2(0, 150), Vector2(0, 0)])
	check(w.terr.is_owned(Vector2(300, 200)), "enclosed interior is claimed")
	check(w.terr.is_owned(Vector2(500, 200)), "trail itself is claimed")
	check(not w.terr.is_owned(Vector2(800, 200)), "outside the loop stays neutral")
	check(w.terr.owned_count > before + 40, "a real chunk was claimed")
	check(w.terr.trail_cells.is_empty(), "trail cleared after claiming")


func test_trail_times_out() -> void:
	var w := _world()
	_walk(w, [Vector2(400, 0)])
	check(not w.terr.trail_cells.is_empty())
	var t := 0.0
	while t < float(data().balance.territory.trail_timeout_s) + 0.5:
		w._update_territory(DT)
		t += DT
	check_eq(w.terr.trails_lost, 1, "unclosed trail fades")
	check(w.terr.trail_age < 1.0, "a fresh trail starts after the old one fades")


func test_player_and_enemies_stay_in_dish() -> void:
	var w := _world()
	w.p_pos = Vector2(5000, 0)
	w._update_player(DT, Vector2.RIGHT)
	check(w.p_pos.length() <= w.terr.radius, "player clamped")
	w._add_enemy("grunt", Vector2(0, 4000))
	w._rebuild_grid()
	w._update_enemies(DT)
	check(w.e_pos[0].length() <= w.terr.radius, "enemy clamped")


func test_no_spawns_on_land_or_outside() -> void:
	var w := _world(3)
	for k in 300:
		var p := w._spawn_point()
		check(p.length() <= w.terr.radius, "spawn inside dish")
		check(not w.terr.is_owned(p), "spawn not on our land")


func test_enemy_slowed_on_land() -> void:
	var w := _world()
	w.p_pos = Vector2(0, 0)
	w._add_enemy("grunt", Vector2(100, 0))  # on home land
	w._add_enemy("grunt", Vector2(1000, 0))  # neutral
	w._rebuild_grid()
	var a0 := w.e_pos[0]
	var b0 := w.e_pos[1]
	w._update_enemies(DT)
	var slow := (w.e_pos[0] - a0).length()
	var fast := (w.e_pos[1] - b0).length()
	check(slow < fast * 0.85, "slowed on land (%.2f vs %.2f)" % [slow, fast])


func test_land_damages_and_erodes() -> void:
	var w := _world()
	var p := Vector2(130, 0)  # home land, outside the indestructible core
	var ti := w.terr.index_of(p)
	check_eq(w.terr.tiles[ti], Territory.OWNED)
	w._add_enemy("brute", p, true)  # elite: tanky and erodes fast
	var hp0 := w.e_hp[0]
	for k in 240:
		w.e_pos[0] = p
		w._terr_tick = 1.0
		w._update_territory(DT)
	check(w.e_hp[0] < hp0, "land damages enemies")
	check_eq(w.terr.tiles[ti], Territory.NEUTRAL, "elite erodes the tile")


func test_core_never_erodes() -> void:
	var w := _world()
	var ti := w.terr.index_of(Vector2.ZERO)
	for k in 100:
		w.terr.erode(ti, 1.0)
	check_eq(w.terr.tiles[ti], Territory.OWNED)


func test_claim_burst_hurts_enclosed_enemies() -> void:
	var w := _world()
	w._add_enemy("brute", Vector2(300, 200))
	var hp0 := w.e_hp[0]
	w._rebuild_grid()
	_walk(w, [Vector2(150, 0), Vector2(500, 0), Vector2(500, 400), Vector2(0, 400), Vector2(0, 150), Vector2(0, 0)])
	check(w.e_hp[0] < hp0 * 0.7, "enclosed brute lost ~40%% (%.1f -> %.1f)" % [hp0, w.e_hp[0]])


func test_damage_bonus_on_land() -> void:
	var w := _world()
	w._add_enemy("brute", Vector2(900, 0))
	w.p_on_land = true
	var hp0 := w.e_hp[0]
	w._damage(0, 10.0, Vector2.ZERO, false)
	check_near(hp0 - w.e_hp[0], 10.0 * (1.0 + float(data().balance.territory.player_damage_bonus)), 0.01)


func test_bot_claims_land_in_a_run() -> void:
	var w := _world(21)
	var bot := BalanceBot.new(21)
	var start := w.terr.owned_count
	for i in int(90.0 / DT):
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		elif w.state == "chest":
			w.close_chest()
		elif w.state != "playing":
			break
		w.step(DT, bot.move(w))
	check(w.terr.owned_count > start, "bot loops and claims land (%d -> %d)" % [start, w.terr.owned_count])


func test_claim_grants_xp() -> void:
	var w := _world()
	var xp0 := w.xp
	_walk(w, [Vector2(150, 0), Vector2(500, 0), Vector2(500, 400), Vector2(0, 400), Vector2(0, 150), Vector2(0, 0)])
	check(w.xp > xp0 + 10.0, "a big loop pays XP (%.1f)" % (w.xp - xp0))


func test_more_land_means_more_pressure() -> void:
	var w := _world()
	w._update_territory(DT)
	var low := w.director.budget_mult
	var hp_low := 0.0
	w._add_enemy("grunt", Vector2(900, 0))
	hp_low = w.e_maxhp[0]
	# Claim a big chunk directly.
	for i in w.terr.n * w.terr.n:
		if w.terr.tiles[i] == Territory.NEUTRAL and w.terr.center_of(i).x < 0.0:
			w.terr.tiles[i] = Territory.OWNED
			w.terr.owned_count += 1
	w._update_territory(DT)
	check(w.director.budget_mult > low + 0.5, "spawn budget grows with land")
	w._add_enemy("grunt", Vector2(900, 0))
	check(w.e_maxhp[1] > hp_low * 1.3, "enemy hp grows with land")
