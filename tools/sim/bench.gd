extends SceneTree
## Performance benchmark for World.step: plays a "kiting" run (player keeps
## running, so enemies pile up behind) and reports the time per subsystem.
##
## Usage: godot --headless --path . -s res://tools/sim/bench.gd -- [--seconds 200] [--mode swarm] [--loaded]

const DT := 1.0 / 60.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := 200.0
	var i := args.find("--seconds")
	if i >= 0 and i + 1 < args.size():
		seconds = float(args[i + 1])
	var mode := "classic"
	var mi := args.find("--mode")
	if mi >= 0 and mi + 1 < args.size():
		mode = args[mi + 1]
	var w := World.new(GameData.apply_mode(GameData.load_all(), mode), 7)
	var events_seen := 0
	if args.has("--loaded"):
		# Late-game stress: every weapon maxed and evolved, passives up.
		for u in w.upgrade_list:
			w.owned[u.id] = Upgrades.max_level(u)
		for wid in w.evolution_defs:
			w.evolved[wid] = w.evolution_defs[wid].id
		w._recompute_stats()
	var parts := ["spawn", "grid", "enemies", "weapons", "bullets", "shots", "dead", "contact", "gems"]
	var cost := {}
	for p in parts:
		cost[p] = 0
	var steps := 0
	var dense_steps := 0
	var dense_us := 0
	var t_all := Time.get_ticks_usec()
	while w.time < seconds and w.state != "dead":
		if w.state == "levelup":
			w.choose_upgrade(w.offers[0])
			continue
		# Run in a slow circle: the classic "kite and let them pile up" pattern.
		var move := Vector2(cos(w.time * 0.25), sin(w.time * 0.25))
		w.time += DT
		var t0 := Time.get_ticks_usec()
		w._update_player(DT, move)
		var t1 := Time.get_ticks_usec(); w._spawn(DT)
		var t2 := Time.get_ticks_usec(); w._rebuild_grid()
		var t3 := Time.get_ticks_usec(); w._update_enemies(DT)
		var t4 := Time.get_ticks_usec(); w._update_weapons(DT)
		var t5 := Time.get_ticks_usec(); w._update_bullets(DT)
		var t6 := Time.get_ticks_usec(); w._update_enemy_shots(DT)
		var t7 := Time.get_ticks_usec(); w._process_dead()
		var t8 := Time.get_ticks_usec(); w._contact_damage()
		var t9 := Time.get_ticks_usec(); w._update_gems(DT)
		var t10 := Time.get_ticks_usec()
		if w.pending_levelups > 0 and w.state == "playing":
			w._open_levelup()
		w.p_hp = w.p_max_hp  # immortal: we want peak density, not a death
		events_seen += w.events.size()
		w.events.clear()
		var ts := [t1, t2, t3, t4, t5, t6, t7, t8, t9, t10]
		for k in parts.size():
			cost[parts[k]] += ts[k + 1] - ts[k] if k + 1 < ts.size() else 0
		steps += 1
		if w.enemy_count() >= 150:
			dense_steps += 1
			dense_us += t10 - t0
	var total := Time.get_ticks_usec() - t_all
	print("mode %s  steps: %d  enemies at end: %d (allies %d)  total: %.1f ms" % [mode, steps, w.enemy_count(), w.ally_count, total / 1000.0])
	print("avg step: %.3f ms   avg step with 150+ enemies: %.3f ms (%d steps)" % [total / 1000.0 / steps, dense_us / 1000.0 / maxi(dense_steps, 1), dense_steps])
	for p in parts:
		print("  %-8s %6.3f ms/step" % [p, cost[p] / 1000.0 / steps])
	print("  events/step %.1f  bullets at end %d" % [float(events_seen) / steps, w.b_pos.size()])
	quit(0)
