extends TestCase
## Elite affixes, the Mother Cell's phases and pull, and lulls/surges.

const DT := 1.0 / 60.0


func _world(seed_value: int = 4) -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), seed_value)
	w.emit_events = false
	return w


func _elite(w: World, affix: String, pos: Vector2) -> int:
	w._add_enemy("grunt", pos, true)
	var i := w.e_pos.size() - 1
	w.e_affix[i] = World.AFFIX_IDS.find(affix)
	w.e_atimer[i] = 0.0
	return i


func _steps(w: World, n: int) -> void:
	for k in n:
		w._rebuild_grid()
		w._update_enemies(DT)


func test_every_elite_gets_an_affix() -> void:
	var w := _world()
	for k in 20:
		w._add_enemy("grunt", Vector2(500 + k, 0), true)
	for i in w.e_pos.size():
		check(w.e_affix[i] != World.AFFIX_NONE, "elite %d has a threat" % i)
	w._add_enemy("grunt", Vector2(0, 600))
	check_eq(int(w.e_affix[w.e_pos.size() - 1]), World.AFFIX_NONE, "normal germs don't")


func test_elites_hunt_from_far_away() -> void:
	var a := _world()
	a._add_enemy("grunt", Vector2(900, 0))
	var b := _world()
	_elite(b, "brood", Vector2(900, 0))
	b.e_atimer[0] = 99.0
	_steps(a, 30)
	_steps(b, 30)
	check(900.0 - b.e_pos[0].x > (900.0 - a.e_pos[0].x) * 1.8, "a far elite closes in much faster")


func test_charge_is_telegraphed_then_dashes() -> void:
	var w := _world()
	var i := _elite(w, "charge", Vector2(300, 0))
	_steps(w, 1)
	check_eq(int(w.e_aphase[i]), 1, "winds up first (telegraph)")
	var p0 := w.e_pos[i]
	_steps(w, 20)
	check(w.e_pos[i].distance_to(p0) < 2.0, "stands still during the windup")
	_steps(w, 45)
	check(w.e_pos[i].x < p0.x - 100.0, "then dashes at you")


func test_volley_fires_a_fan() -> void:
	var w := _world()
	_elite(w, "volley", Vector2(400, 0))
	_steps(w, 40)
	check(w.s_pos.size() >= 5, "a 5-shot fan")


func test_brood_spawns_minions() -> void:
	var w := _world()
	_elite(w, "brood", Vector2(400, 0))
	_steps(w, 2)
	check_eq(w.enemy_count(), 3, "2 minions")


func test_magnet_pulls_the_player() -> void:
	var w := _world()
	_elite(w, "magnet", Vector2(200, 0))
	_steps(w, 1)
	check(w.p_pull.x > 10.0, "pulled toward the elite")
	var x0 := w.p_pos.x
	w._update_player(DT, Vector2.ZERO)
	check(w.p_pos.x > x0)


func test_mother_cell_phases_pull_and_slam() -> void:
	var w := _world()
	w._add_enemy("boss", Vector2(400, 0))
	_steps(w, 1)
	check(w.p_pull.x > 10.0, "the Mother Cell drags you in")
	check_eq(w.boss_phase, 1)
	check(w.s_pos.size() >= 3, "aimed spread")
	w.e_hp[0] = w.e_maxhp[0] * 0.5
	w._boss_slam_cd = 0.0
	_steps(w, 1)
	check_eq(w.boss_phase, 2)
	check_eq(w.boss_slam, 1, "slam winds up on your spot")
	check(w.boss_slam_at.distance_to(w.p_pos) < 1.0)
	var shots := w.s_pos.size()
	var n := w.enemy_count()
	_steps(w, 90)
	check(w.e_pos[0].distance_to(w.boss_slam_at) < 60.0, "leaps onto the spot")
	check(w.enemy_count() > n, "lands with minions")
	w.e_hp[0] = w.e_maxhp[0] * 0.2
	_steps(w, 30)
	check_eq(w.boss_phase, 3)


func test_lulls_then_surge() -> void:
	var w := _world()
	var l: Dictionary = w.data.waves.lulls[0]
	w.time = float(l.at) + 1.0
	w._update_lull()
	check_eq(w.lull, 1)
	check_near(w.director.lull_mult, float(l.mult))
	w.time = float(l.at) + float(l.s) + 1.0
	w._update_lull()
	check_eq(w.lull, 2, "a surge follows")
	check(w.director.lull_mult > 1.0)
	w.time = float(l.at) + float(l.s) + float(l.surge_s) + 1.0
	w._update_lull()
	check_eq(w.lull, 0)
	check_near(w.director.lull_mult, 1.0)
