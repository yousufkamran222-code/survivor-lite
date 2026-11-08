extends TestCase
## Skill moves (balance.skill, D-041): Perfect Dodge, Overdrive, streak
## buffs, Perfect Loop and Clutch Claim.

const DT := 1.0 / 60.0


func _classic(seed_value: int = 1) -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), seed_value)
	w.emit_events = false
	return w


func _infection(seed_value: int = 1) -> World:
	var w := World.new(GameData.apply_mode(data(), "infection"), seed_value)
	w.emit_events = false
	return w


func _walk(w: World, points: Array) -> void:
	for target: Vector2 in points:
		var guard := 0
		while w.p_pos.distance_to(target) > 6.0 and guard < 2000:
			w.p_pos = w.p_pos.move_toward(target, 300.0 * DT)
			w._update_player(DT, Vector2.ZERO)
			w._update_territory(DT)
			guard += 1


func test_perfect_dodge_on_an_incoming_shot() -> void:
	var w := _classic()
	w._enemy_shot(w.p_pos + Vector2(40, 0), Vector2.LEFT, 300.0, 10.0)
	check(w.dash())
	check_eq(w.perfect_dodges, 1)
	check_eq(w.p_dash_charges, w.dash_max_charges(), "the dash comes back")
	check(w.perfect_t > 0.0)
	check(w.skill_damage_mult() > 1.5, "hits harder for a while")
	check(w._frenzy_speed() > 1.3, "fires faster for a while")


func test_no_perfect_dodge_without_a_threat() -> void:
	var w := _classic()
	w._enemy_shot(w.p_pos + Vector2(400, 0), Vector2.UP, 300.0, 10.0)  # far and not aimed at you
	w._add_enemy("grunt", w.p_pos + Vector2(500, 0))
	w.dash()
	check_eq(w.perfect_dodges, 0)
	check_eq(w.p_dash_charges, w.dash_max_charges() - 1)


func test_perfect_dodge_on_contact_with_a_cooldown() -> void:
	var w := _classic()
	w._add_enemy("grunt", w.p_pos + Vector2(30, 0))
	w._rebuild_grid()
	check(w.dash())
	check_eq(w.perfect_dodges, 1, "a germ about to touch you")
	w.p_iframes = 0.0
	w._add_enemy("grunt", w.p_pos + Vector2(30, 0))
	w._rebuild_grid()
	w.dash()
	check_eq(w.perfect_dodges, 1, "not again inside the cooldown")


func test_overdrive_after_four_back_to_back_dashes() -> void:
	var w := _classic()
	for k in 4:
		w.p_dash_charges = 1
		check(w.dash())
		w.time += 0.1
	check(w.overdrive_t > 0.0, "chain of 4 → Overdrive (chain %d)" % w.dash_chain)
	var hp := w.p_hp
	w._add_enemy("brute", w.p_pos)
	w._rebuild_grid()
	w._update_player(DT, Vector2.RIGHT)
	w._contact_damage()
	check_near(w.p_hp, hp, 0.001, "untouchable")
	var p0 := w.p_pos
	w.p_dash_t = 0.0
	w._update_player(0.1, Vector2.RIGHT)
	var fast := w.p_pos.distance_to(p0)
	check(fast > float(data().balance.player.speed) * 0.1 * 2.0, "much faster than walking (%.1f)" % fast)


func test_slow_dashes_never_overdrive() -> void:
	var w := _classic()
	for k in 6:
		w.p_dash_charges = 1
		w._ready_since = w.time
		w.time += 2.0  # waited long after the dash was ready
		w.dash()
	check_eq(w.overdrives, 0)
	check(w.dash_chain <= 1)


func test_overdrive_keeps_slipstream_ramming() -> void:
	var w := _classic()
	w.stats["slipstream"] = 1.0
	w._start_overdrive()
	for k in 60:
		w._update_player(DT, Vector2.RIGHT)
	check(w.slip_t > 0.0, "the wake stays on through Overdrive")


func test_streak_buffs_grow_and_end_with_the_streak() -> void:
	var w := _classic()
	check_near(w.skill_damage_mult(), 1.0)
	for k in 50:
		w._add_streak()
	check_eq(w.streak_buff, 1, "x50 tier")
	check_near(w.skill_damage_mult(), 1.0 + float(w.skill.streak_buffs[1].damage))
	check(w.skill_buff("speed") > 0.0 and w.skill_buff("haste") > 0.0)
	w.streak_t = 99.0
	w.step(DT, Vector2.ZERO)
	check_eq(w.streak, 0)
	check_eq(w.streak_buff, -1, "gone when the streak breaks")


func test_streak_buff_damage_applies_to_hits() -> void:
	var w := _classic()
	w._add_enemy("brute", w.p_pos + Vector2(300, 0))
	var hp0 := w.e_hp[0]
	w._damage(0, 10.0, Vector2.ZERO, false)
	var plain := hp0 - w.e_hp[0]
	for k in 100:
		w._add_streak()
	var hp1 := w.e_hp[0]
	w._damage(0, 10.0, Vector2.ZERO, false)
	check_near((hp1 - w.e_hp[0]) / plain, 1.0 + float(w.skill.streak_buffs[2].damage), 0.01)


func test_perfect_loop_wipes_the_inside() -> void:
	var w := _infection()
	w._add_enemy("brute", Vector2(300, 200))
	w._rebuild_grid()
	_walk(w, [Vector2(150, 0), Vector2(500, 0), Vector2(500, 400), Vector2(0, 400), Vector2(0, 150), Vector2(0, 0)])
	check_eq(w.perfect_loops, 1)
	check_eq(w.hostile_count(), 0, "a no-damage loop kills what's inside")


func test_taking_damage_spoils_the_perfect_loop() -> void:
	var w := _infection()
	w._add_enemy("brute", Vector2(300, 200))
	w._rebuild_grid()
	_walk(w, [Vector2(150, 0), Vector2(500, 0)])
	w._hurt(1.0, "test")
	_walk(w, [Vector2(500, 400), Vector2(0, 400), Vector2(0, 150), Vector2(0, 0)])
	check_eq(w.perfect_loops, 0)
	check_eq(w.hostile_count(), 1, "a normal burst only")


func test_clutch_claim_stuns_whats_inside() -> void:
	var w := _infection()
	w._add_enemy("brute", Vector2(300, 200))
	w._rebuild_grid()
	_walk(w, [Vector2(150, 0), Vector2(500, 0), Vector2(500, 400), Vector2(0, 400)])
	w._trail_hit = true  # not perfect, so the brute survives the burst
	w.terr.trail_age = float(w.bal.territory.trail_timeout_s) - 1.0  # flashing red
	_walk(w, [Vector2(0, 150), Vector2(0, 0)])
	check_eq(w.clutch_claims, 1)
	check(w.e_stun[0] > 1.0, "stunned")
	var p0 := w.e_pos[0]
	w.p_pos = p0
	w._rebuild_grid()
	var hp := w.p_hp
	w._update_enemies(0.2)
	check(w.e_pos[0].distance_to(p0) < 1.0, "doesn't move while stunned")
	w.p_iframes = 0.0
	w._contact_damage()
	check_near(w.p_hp, hp, 0.001, "no contact damage while stunned")


func test_a_calm_claim_is_not_clutch() -> void:
	var w := _infection()
	_walk(w, [Vector2(150, 0), Vector2(500, 0), Vector2(500, 400), Vector2(0, 400), Vector2(0, 150), Vector2(0, 0)])
	check_eq(w.clutch_claims, 0)
