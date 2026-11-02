extends TestCase
## Nucleus mode (tower defence): targeting, nucleus damage and loss, pads and
## towers, biomass, respawn, the wave table. See docs/ROADMAP.md "Prototype 3".

const DT := 1.0 / 60.0


func _world(seed_value: int = 5) -> World:
	var w := World.new(GameData.apply_mode(data(), "nucleus"), seed_value)
	w.emit_events = false
	return w


func _steps(w: World, seconds: float, move: Vector2 = Vector2.ZERO) -> void:
	for i in int(seconds / DT):
		if w.state != "playing":
			return
		w.step(DT, move)


func test_mode_sets_up_nucleus_pads_and_vents() -> void:
	var w := _world()
	var dc: Dictionary = w.bal.defense
	check(w.def_on)
	check(w.terr == null, "no territory claiming in Nucleus mode")
	check_near(w.core_hp, float(dc.core_hp))
	check_eq(w.pad_pos.size(), int(dc.pads))
	check_eq(w.vent_pos.size(), int(dc.vents))
	check_eq(w.wave_count, data().waves.defense.waves.size())
	check_near(w.dish_r, float(dc.dish_radius))
	for v in w.vent_pos:
		check(v.length() < w.dish_r, "vents sit inside the dish")
	var classic := World.new(GameData.apply_mode(data(), "classic"), 5)
	check(not classic.def_on, "other modes are unaffected")


func test_time_alone_does_not_win() -> void:
	var w := _world()
	w.time = w.run_length + 1.0
	w.step(DT, Vector2.ZERO)
	check(w.state != "won", "Nucleus is won by clearing waves, not by the clock")


func test_enemies_march_on_nucleus_unless_player_is_close() -> void:
	var w := _world()
	w.p_pos = Vector2(-600, 0)
	w._add_enemy("grunt", Vector2(500, 0))
	w._add_enemy("grunt", Vector2(-600, 160))
	var far_before := w.e_pos[0].distance_to(w.core_pos)
	var near_before := w.e_pos[1].distance_to(w.p_pos)
	w._rebuild_grid()
	for i in 30:
		w._update_enemies(DT)
	check(w.e_pos[0].distance_to(w.core_pos) < far_before - 20.0, "a far germ heads for the nucleus")
	check(w.e_pos[1].distance_to(w.p_pos) < near_before - 20.0, "a germ near the player goes for the player")


func test_germs_touching_nucleus_damage_it_and_losing_it_ends_the_run() -> void:
	var w := _world()
	w.p_pos = Vector2(0, 700)
	w._add_enemy("brute", w.core_pos + Vector2(w.core_r + 10.0, 0))
	w._rebuild_grid()
	var before := w.core_hp
	w._update_core(1.0)
	check(w.core_hp < before, "contact damages the nucleus")
	w.core_hp = 1.0
	w._core_tick = 1.0
	w._update_core(0.1)
	check_eq(w.state, "dead")
	check_eq(w.death_cause, "nucleus")


func test_enemy_shots_hit_the_nucleus() -> void:
	var w := _world()
	w.p_pos = Vector2(0, 700)
	w._enemy_shot(w.core_pos + Vector2(w.core_r - 5.0, 0), Vector2.RIGHT, 0.0, 20.0)
	var before := w.core_hp
	w._update_enemy_shots(DT)
	check(w.core_hp < before)
	check_eq(w.s_pos.size(), 0, "the shot is used up")


func test_player_death_respawns_at_nucleus() -> void:
	var w := _world()
	w.p_pos = Vector2(400, 400)
	w._hurt(1.0e6, "grunt")
	check_eq(w.state, "playing", "only the nucleus ends the run")
	check(w.p_down > 0.0)
	check(not w.dash(), "can't dash while reforming")
	_steps(w, float(w.bal.defense.respawn_s) + 0.1)
	check_eq(w.p_down, 0.0)
	check_near(w.p_hp, w.p_max_hp)
	check(w.p_pos.distance_to(w.core_pos) < 200.0, "reforms next to the nucleus")


func test_standing_on_pad_builds_then_needs_stepping_off() -> void:
	var w := _world()
	var cost := w.pad_next_cost(0)
	check(cost > 0)
	w.biomass = float(cost) * 10.0
	w.wave_t = 999.0  # stay in the breather
	var pad := w.pad_pos[0]
	w.p_pos = pad
	_steps(w, float(w.bal.defense.build_s) + 0.1)
	check_eq(w.pad_tower[0], 0, "a tower stands on the pad")
	check_eq(w.pad_level[0], 1)
	check_near(w.biomass, float(cost) * 10.0 - cost)
	check_eq(w.towers_built, 1)
	_steps(w, float(w.bal.defense.build_s) * 2.0)
	check_eq(w.pad_level[0], 1, "staying on the pad does not keep upgrading")
	w.p_pos = Vector2(0, 600)
	w.step(DT, Vector2.ZERO)
	w.p_pos = pad
	_steps(w, float(w.bal.defense.build_s) + 0.1)
	check_eq(w.pad_level[0], 2, "step off and back on to upgrade")


func test_pad_needs_enough_biomass() -> void:
	var w := _world()
	w.biomass = 0.0
	w.wave_t = 999.0
	w.p_pos = w.pad_pos[1]
	_steps(w, 2.0)
	check_eq(w.pad_tower[1], -1, "no biomass, no tower")


func test_maxed_tower_has_no_cost() -> void:
	var w := _world()
	w.pad_tower[2] = 0
	w.pad_level[2] = w.tower_defs[0].levels.size()
	check_eq(w.pad_next_cost(2), -1)


func test_tower_shoots_from_its_pad() -> void:
	var w := _world()
	w.p_pos = Vector2(0, 700)
	w.pad_tower[0] = 0
	w.pad_level[0] = 1
	w._add_enemy("grunt", w.pad_pos[0] + Vector2(150, 0))
	w._rebuild_grid()
	w._update_towers(DT)
	check(w.b_pos.size() >= 1, "fired")
	check(w.b_pos[0].distance_to(w.pad_pos[0]) < 1.0, "from the pad, not the player")
	var hp := w.e_hp[0]
	for i in 30:
		w._update_bullets(DT)
	check(w.e_hp[0] < hp, "and hit the germ")


func test_kills_give_biomass() -> void:
	var w := _world()
	var before := w.biomass
	w._add_enemy("brute", Vector2(500, 0))
	w._damage(0, 1.0e6, Vector2.ZERO)
	w._process_dead()
	check_near(w.biomass - before, float(data().enemies.filter(func(e: Dictionary) -> bool: return e.id == "brute")[0].cost))


func test_waves_start_spawn_at_vents_and_clear() -> void:
	var w := _world()
	w.p_pos = Vector2(0, 700)
	_steps(w, float(w.bal.defense.first_breather_s) + 0.1)
	check_eq(w.wave, 1)
	check(w.wave_state != "breather")
	_steps(w, 3.0)
	check(w.hostile_count() > 0, "wave 1 spawned")
	for i in w.e_pos.size():
		var near_vent := false
		for v in w.vent_pos:
			near_vent = near_vent or w.e_pos[i].distance_to(v) < 400.0
		check(near_vent, "spawned at a vent")
	# Kill everything once the wave has finished spawning: it clears.
	for i in 2000:
		if w.wave_state == "fighting":
			break
		w.step(DT, Vector2.ZERO)
	for i in w.e_pos.size():
		w._damage(i, 1.0e6, Vector2.ZERO)
	w._process_dead()
	var bio := w.biomass
	w.step(DT, Vector2.ZERO)
	check_eq(w.waves_cleared, 1)
	check_eq(w.wave_state, "breather")
	check(w.biomass > bio, "clear bonus")


func test_clearing_the_last_wave_wins() -> void:
	var w := _world()
	w.wave = w.wave_count
	w.wave_state = "fighting"
	w.step(DT, Vector2.ZERO)
	check_eq(w.state, "won")


func test_wave_spawning_is_deterministic() -> void:
	var a := _world(9)
	var b := _world(9)
	_steps(a, 12.0, Vector2(0.3, 0.2))
	_steps(b, 12.0, Vector2(0.3, 0.2))
	check_eq(a.e_pos.size(), b.e_pos.size())
	check_eq(a.wave, b.wave)
	if a.e_pos.size() > 0:
		check_eq(a.e_pos[0], b.e_pos[0])


func test_bot_defends_and_builds() -> void:
	var w := _world(21)
	var bot := BalanceBot.new(21)
	for i in int(150.0 / DT):
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		elif w.state == "chest":
			w.close_chest()
		elif w.state != "playing":
			break
		w.step(DT, bot.move(w))
	check(w.towers_built >= 1, "the bot builds towers")
	check(w.waves_cleared >= 3, "and clears early waves (%d)" % w.waves_cleared)


func test_wave_finishes_spawning_with_unaffordable_leftover() -> void:
	# Regression: a picked enemy costing more than the leftover budget kept
	# the wave "spawning" forever.
	var by_id := {}
	for e in data().enemies:
		by_id[e.id] = e
	var sd := SpawnDirector.new(data().waves, by_id, RandomNumberGenerator.new())
	sd.start_wave({"duration": 1.0, "budget": 4.5, "enemies": ["grunt", "brute"], "vents": [0]})
	for i in 200:
		sd.update_wave(1.0 / 60.0, 0)
	check(sd.wave_spawned(), "wave ends even if the leftover can't buy the picked enemy")
