extends TestCase
## The game steps once per rendered frame (Main), so a 144 Hz monitor runs
## the World with dt 1/144 instead of 1/60. CrazyGames requires the same
## physics at any refresh rate: movement, chasing, firing and a whole bot run
## must come out the same within a small tolerance.


func _world(seed_value: int = 7) -> World:
	var w := World.new(GameData.apply_mode(data(), "classic"), seed_value)
	w.emit_events = false
	return w


func _run_for(w: World, seconds: float, hz: float, move: Vector2) -> void:
	var dt := 1.0 / hz
	var n := int(round(seconds * hz))
	for i in n:
		w.step(dt, move)


func test_player_moves_the_same_distance() -> void:
	var a := _world()
	var b := _world()
	_run_for(a, 2.0, 60.0, Vector2.RIGHT)
	_run_for(b, 2.0, 144.0, Vector2.RIGHT)
	var da := a.p_pos.length()
	var db := b.p_pos.length()
	check(da > 50.0, "moved")
	check(absf(da - db) / da < 0.03, "60 Hz %.1f vs 144 Hz %.1f" % [da, db])


func test_a_germ_closes_in_at_the_same_speed() -> void:
	var out := []
	for hz in [60.0, 144.0]:
		var w := _world()
		w._add_enemy("brute", w.p_pos + Vector2(500, 0))
		var i := w.e_pos.size() - 1
		var start := w.e_pos[i].distance_to(w.p_pos)
		var dt: float = 1.0 / hz
		for k in int(round(1.5 * hz)):
			w._rebuild_grid()
			w._update_enemies(dt)
		out.append(start - w.e_pos[i].distance_to(w.p_pos))
	check(out[0] > 20.0, "it moved")
	check(absf(out[0] - out[1]) / out[0] < 0.05, "60 Hz %.1f vs 144 Hz %.1f" % [out[0], out[1]])


## Weapons: the same damage per second into one tough germ held in place.
func test_weapons_fire_at_the_same_rate() -> void:
	var out := []
	for hz in [60.0, 144.0]:
		var w := _world()
		w._add_enemy("brute", w.p_pos + Vector2(160, 0))
		var i := w.e_pos.size() - 1
		w.e_hp[i] = 1.0e5
		var dt: float = 1.0 / hz
		for k in int(round(3.0 * hz)):
			w.e_pos[i] = w.p_pos + Vector2(160, 0)  # held still, out of contact
			w.step(dt, Vector2.ZERO)
		out.append(1.0e5 - w.e_hp[i])
	check(out[0] > 10.0, "it took damage")
	check(absf(out[0] - out[1]) / out[0] < 0.1, "60 Hz %.1f vs 144 Hz %.1f" % [out[0], out[1]])


func test_dash_covers_the_same_distance() -> void:
	var out := []
	for hz in [60.0, 144.0]:
		var w := _world()
		var dt: float = 1.0 / hz
		w.step(dt, Vector2.RIGHT)
		var x0 := w.p_pos.x
		w.dash()
		for k in int(round(0.5 * hz)):
			w.step(dt, Vector2.RIGHT)
		out.append(w.p_pos.x - x0)
	check(out[0] > 100.0, "dashed")
	check(absf(out[0] - out[1]) / out[0] < 0.03, "60 Hz %.1f vs 144 Hz %.1f" % [out[0], out[1]])


func test_gems_fly_in_at_the_same_speed() -> void:
	var out := []
	for hz in [60.0, 144.0]:
		var w := _world()
		w._drop_gem(w.p_pos + Vector2(90, 0), 1.0)
		var dt: float = 1.0 / hz
		var t := 0.0
		while w.g_pos.size() > 0 and t < 3.0:
			w._update_gems(dt)
			t += dt
		out.append(t)
	check(out[0] < 3.0, "picked up")
	check(absf(out[0] - out[1]) < 0.03, "60 Hz %.3f s vs 144 Hz %.3f s" % [out[0], out[1]])
