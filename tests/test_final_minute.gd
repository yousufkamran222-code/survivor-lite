extends TestCase
## Timed modes end on a climax: from waves.final_minute_s germs move faster,
## elites come every waves.elites.final_every_s, and a "final_minute" event fires.


func _elite_times(until: float) -> Array:
	var d := data()
	var by_id := {}
	for e in d.enemies:
		by_id[e.id] = e
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var dir := SpawnDirector.new(d.waves, by_id, rng)
	var out := []
	var t := 0.0
	while t < until:
		for o in dir.update(0.1, t, 0):
			if o.get("elite", false):
				out.append(t)
		t += 0.1
	return out


func test_elites_speed_up_in_the_final_minute() -> void:
	var el: Dictionary = data().waves.elites
	var times := _elite_times(300.0)
	var late := []
	for t: float in times:
		if t >= float(el.final_from_s):
			late.append(t)
	check(late.size() >= 2, "several elites in the final minute")
	for k in range(1, late.size()):
		check_near(late[k] - late[k - 1], float(el.final_every_s), 0.15, "final-minute elite gap")
	check(late[0] - float(el.final_from_s) <= float(el.final_every_s) + 0.15, "first one comes soon after the warning")


func test_final_minute_event_and_speed() -> void:
	var w := World.new(GameData.apply_mode(data(), "classic"), 3)
	var at := float(data().waves.final_minute_s)
	w.time = at - 0.05
	w.step(0.1, Vector2.ZERO)
	check(w.final_minute, "flag set")
	var found := false
	for ev in w.events:
		if ev.type == "final_minute":
			found = true
	check(found, "event fired once")
	check_near(w.final_speed, float(data().waves.final_speed_mult), 0.001)
	w.events.clear()
	w.step(0.1, Vector2.ZERO)
	for ev in w.events:
		check(ev.type != "final_minute", "not fired twice")


func test_germs_move_faster_in_the_final_minute() -> void:
	var dist := []
	for late in [false, true]:
		var w := World.new(GameData.apply_mode(data(), "classic"), 3)
		w.emit_events = false
		w._add_enemy("grunt", w.p_pos + Vector2(600, 0))
		if late:
			w.final_minute = true
			w.final_speed = float(data().waves.final_speed_mult)
		var p0 := w.e_pos[0]
		for f in 30:
			w._rebuild_grid()
			w._update_enemies(1.0 / 60.0)
		dist.append(w.e_pos[0].distance_to(p0))
	check_near(dist[1] / dist[0], float(data().waves.final_speed_mult), 0.02)


func test_nucleus_has_no_final_minute() -> void:
	var w := World.new(GameData.apply_mode(data(), "nucleus"), 3)
	w.time = float(data().waves.final_minute_s) + 10.0
	w.step(0.1, Vector2.ZERO)
	check(not w.final_minute, "wave mode keeps its own finale")
