extends TestCase
## Kill streak (balance.streak): counting, breaking, milestones, tiers, the
## rewards hook, and the best streak as a saved stat with achievements.

const DT := 1.0 / 60.0


func _world() -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), 5)
	w.emit_events = true
	w.bal.debug.invincible = true
	return w


## Kills one fresh germ far from the player (no gem pickup, no contact).
func _kill(w: World) -> void:
	w._add_enemy("grunt", w.p_pos + Vector2(900, 0))
	var i := w.enemy_count() - 1
	w._damage(i, 1.0e6, Vector2.ZERO, false)
	w._process_dead()


func _events(w: World, type: String) -> Array:
	var out := []
	for ev in w.events:
		if ev.type == type:
			out.append(ev)
	return out


func test_kills_chain_and_break() -> void:
	var w := _world()
	for k in 5:
		_kill(w)
	check_eq(w.streak, 5)
	w.streak_t = float(w.bal.streak.window_s) * 0.9
	_kill(w)
	check_eq(w.streak, 6, "a kill inside the window extends it")
	w.events.clear()
	w.streak_t = float(w.bal.streak.window_s) + 0.01
	w.step(DT, Vector2.ZERO)
	check_eq(w.streak, 0, "too slow: the streak breaks")
	var ends := _events(w, "streak_end")
	check_eq(ends.size(), 1)
	check_eq(int(ends[0].n), 6)
	check_eq(w.best_streak, 6, "best survives the break")
	_kill(w)
	check_eq(w.streak, 1, "a new streak starts at 1")


func test_milestones_and_tiers() -> void:
	var w := _world()
	var ms: Array = w.bal.streak.milestones
	var last := int(ms[-1])
	var rep := int(w.bal.streak.repeat_every)
	for k in last + rep:
		_kill(w)
	var hits := []
	for ev in _events(w, "streak"):
		hits.append(int(ev.n))
	var want := []
	for m in ms:
		want.append(int(m))
	want.append(last + rep)
	check_eq(hits, want, "every milestone fires once, then every repeat_every")
	var tiers: Array = w.bal.streak.tiers
	check_eq(w.streak_tier(int(tiers[0].at) - 1), -1)
	check_eq(w.streak_tier(int(tiers[0].at)), 0)
	check_eq(w.streak_tier(100000), tiers.size() - 1)


func test_rewards_hook_fires_at_its_streak() -> void:
	var w := _world()
	w.bal.streak.rewards = [{"at": 25, "pickup": "heal"}, {"at": 50, "outbreak": 0.5}]
	w.p_hp = 10.0
	w.outbreak = 0.0
	for k in 25:
		_kill(w)
	w.step(DT, Vector2.ZERO)  # rewards run after the kill pass
	check(w.p_hp > 10.0, "heal reward at x25")
	var o := w.outbreak
	for k in 25:
		_kill(w)
	w.step(DT, Vector2.ZERO)
	check(w.outbreak >= o + 0.49, "outbreak reward at x50")
	check_eq(_events(w, "streak_reward").size(), 2)


func test_no_rewards_by_default() -> void:
	check(data().balance.streak.get("rewards", []).is_empty(), "streak is cosmetic until an upgrade/ability uses the hook")


func test_validation_catches_bad_reward() -> void:
	var d := data().duplicate(true)
	d.balance.streak.rewards = [{"at": 10, "pickup": "laser"}]
	check(GameData.validate(d).size() > 0)


func test_best_streak_is_saved_and_unlocks_achievements() -> void:
	var w := _world()
	for k in 120:
		_kill(w)
	var s := Progression.run_summary(w, false, "classic", data().online.score)
	check_eq(int(s.best_streak), 120)
	var p := Profile.new()
	var fresh := p.record_run(s, data().online.achievements, 10)
	check_eq(int(p.stats.best_streak), 120)
	check_eq(int(p.record("classic").best_streak), 120)
	var ids := []
	for a in fresh:
		ids.append(a.id)
	check(ids.has("streak_100"), "100-kill streak achievement")
	check(not ids.has("streak_250"))
	# A smaller streak later never lowers the record.
	s.best_streak = 30
	p.record_run(s, [], 20)
	check_eq(int(p.stats.best_streak), 120)


func test_old_saves_load_and_merge_best_streak() -> void:
	var p := Profile.new()
	var d := p.to_dict()
	d.version = 2
	d.stats.erase("best_streak")
	var q := Profile.from_dict(d)
	check_eq(int(q.stats.best_streak), 0, "v2 save: no streak yet")
	var a := Profile.new()
	a.stats.best_streak = 80
	a.updated_at = 1
	var b := Profile.new()
	b.stats.best_streak = 40
	b.updated_at = 2
	check_eq(int(Profile.merge(a, b).stats.best_streak), 80, "merge keeps the higher streak")
	check(Profile.VERSION >= 3)
