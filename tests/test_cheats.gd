extends TestCase
## TEMPORARY playtest cheats (Cheats, balance.crazygames.cheats): each one
## does what its button says, and with every toggle off a World is unchanged.

const DT := 1.0 / 60.0


func _classic(seed_value: int = 1) -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), seed_value)
	w.emit_events = false
	return w


func _reset() -> void:
	Cheats.god = false
	Cheats.dmg = 1.0
	Cheats.no_spawn = false
	Cheats.speed = 1.0
	Cheats.xp = 1.0


func test_defaults_change_nothing() -> void:
	_reset()
	var a := _classic(7)
	var b := _classic(7)
	Cheats.apply_flags(b)
	for k in 1200:
		a.step(DT, Vector2(1, 0.3))
		b.step(DT, Vector2(1, 0.3))
		if a.state == "levelup":
			a.choose_upgrade(a.offers[0])
		if b.state == "levelup":
			b.choose_upgrade(b.offers[0])
	check_eq(a.kills, b.kills)
	check_eq(a.p_hp, b.p_hp)
	check_eq(a.level, b.level)


func test_god_mode_and_damage() -> void:
	_reset()
	var w := _classic()
	Cheats.god = true
	Cheats.dmg = 1.0e6
	Cheats.apply_flags(w)
	var hp := w.p_hp
	w._hurt(50.0, "test")
	check_eq(w.p_hp, hp, "god mode takes no damage")
	Cheats.spawn(w, "brute", 3)
	check_eq(w.hostile_count(), 3)
	w._damage(0, 1.0, Vector2.ZERO)
	check(w.e_hp[0] <= 0.0, "one-hit kills")
	_reset()


func test_levels_evolve_and_kill_all() -> void:
	_reset()
	var w := _classic()
	Cheats.levels(w, 3)
	check_eq(w.pending_levelups, 3)
	Cheats.evolve_all(w)
	check_eq(w.evolved.size(), w.evolution_defs.size(), "every weapon evolved")
	Cheats.spawn(w, "grunt", 10)
	Cheats.spawn(w, "grunt", 1, true, "magnet")
	check_eq(w.affix_id(w.e_pos.size() - 1), "magnet")
	Cheats.kill_all(w)
	check_eq(w.hostile_count(), 0)


func test_skip_time_drops_missed_spawns() -> void:
	_reset()
	var w := _classic()
	w.step(DT, Vector2.ZERO)
	Cheats.set_time(w, 225.0)
	w.step(DT, Vector2.ZERO)
	check(w.time >= 225.0)
	check(w.hostile_count() < 40, "no flood of missed rings and elites")
	var boss := false
	for i in 300:
		w.step(DT, Vector2.ZERO)
		if w.boss_index >= 0:
			boss = true
			break
	check(boss, "the Mother Cell still comes")


func test_symptom_any_virulence_and_win() -> void:
	_reset()
	var w := _classic()
	Cheats.symptom(w, "fever")
	check_eq(w.sym_id, "fever")
	check_eq(w.sym_state, 1)
	Cheats.win(w)
	check_eq(w.state, "won")
