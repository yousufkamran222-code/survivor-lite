extends SceneTree
## Headless balance simulator: plays many seeded runs with BalanceBot and
## reports survival-time distribution, levels, death causes and upgrade impact.
##
## Usage:
##   godot --headless --path . -s res://tools/sim/balance_sim.gd -- --runs 40 --seed 1000
## Options: --runs N, --seed S, --meta (use maxed meta upgrades),
## --mode ID (data/modes.json, default: first mode), --classic (= --mode classic),
## --json PATH, --free (Nucleus: keep going into Free Mode after the win),
## --order guard|hunt|harvest (Swarm: the bot keeps that order),
## --set key.path=value,... (override balance numbers, or waves.* ones, for a tuning run),
## --level N (Virulence level, 1-10),
## --lab all|alt (a maxed Lab on top of --meta or alone; all = first side of each fork, alt = second side)

const DT := 1.0 / 30.0


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", 30))
	var seed0 := int(args.get("seed", 1000))
	var mode_id := "classic" if args.has("classic") else str(args.get("mode", ""))
	free = args.has("free")
	var d := GameData.load_all()
	if mode_id == "":
		mode_id = d.modes[0].id
	d = GameData.apply_mode(d, mode_id)
	if args.has("level"):  # Virulence level (data/difficulty.json)
		d = GameData.apply_virulence(d, int(args.level))
	if args.has("set"):
		for pair in str(args.set).split(","):
			var kv := pair.split("=")
			var keys := kv[0].split(".")
			var node: Dictionary = d.balance
			var k0 := 0
			if keys[0] == "waves":  # waves.* keys go to data/waves.json
				node = d.waves
				k0 = 1
			for k in range(k0, keys.size() - 1):
				node = node[keys[k]]
			node[keys[keys.size() - 1]] = float(kv[1])
	force_order = World.ORDER_IDS.find(str(args.get("order", "")))
	nobait = args.has("nobait")
	var meta := {}
	if args.has("meta"):
		var levels := {}
		for m in d.meta:
			levels[m.id] = m.costs.size()
		meta = Progression.meta_bonus(d.meta, levels)
	if args.has("lab"):
		var owned := Lab.full_owned(d.lab)
		if str(args.lab) == "alt":
			for n in Lab.nodes(d.lab):
				if n.has("fork"):
					if owned.has(n.id):
						owned.erase(n.id)
					else:
						owned[n.id] = Lab.max_level(n)
		var lb := Lab.bonus(d.lab, owned)
		for k in lb:
			meta[k] = float(meta.get(k, 0.0)) + float(lb[k])
	var results := []
	var t0 := Time.get_ticks_msec()
	for r in runs:
		results.append(_play(d, seed0 + r, meta))
	var ms := Time.get_ticks_msec() - t0
	var report := _report(results, d)
	report["runs"] = runs
	report["mode"] = mode_id
	report["sim_ms_per_run"] = ms / maxf(runs, 1)
	print(JSON.stringify(report, "  "))
	if args.has("json"):
		var f := FileAccess.open(str(args.json), FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "  "))
	quit(0)


func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if i + 1 < argv.size() and not argv[i + 1].begins_with("--"):
				out[key] = argv[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out


var free := false  # --free: Nucleus runs continue into Free Mode after the win
var force_order := -1  # --order: Swarm bot keeps this order
var nobait := false  # --nobait: the bot doesn't lure the Seeker Phage (rift tuning)


func _play(d: Dictionary, seed_value: int, meta: Dictionary) -> Dictionary:
	var w := World.new(d, seed_value, meta)
	w.emit_events = false
	var bot := BalanceBot.new(seed_value)
	bot.force_order = force_order
	bot.bait = not nobait
	if force_order >= 0:
		w.set_ally_order(force_order)
	var peak_enemies := 0
	var peak_allies := 0
	var hp_at_boss := -1.0
	var levels_2min := -1
	while w.state in ["playing", "levelup", "chest", "defense_won"] and w.time < 1800.0:
		if w.state == "defense_won":
			if free:
				w.start_free_mode()
			else:
				w.collect_win()
				break
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
			continue
		if w.state == "chest":
			w.close_chest()
			continue
		w.step(DT, bot.move(w))
		peak_enemies = maxi(peak_enemies, w.enemy_count())
		peak_allies = maxi(peak_allies, w.ally_count)
		if levels_2min < 0 and w.time >= 120.0:
			levels_2min = w.level - 1
		if hp_at_boss < 0.0 and w.boss_index >= 0:
			hp_at_boss = w.p_hp / w.p_max_hp
	return {
		"seed": seed_value, "time": w.time, "won": w.state == "won", "level": w.level,
		"kills": w.kills, "cause": w.death_cause, "owned": w.owned.duplicate(),
		"peak_enemies": peak_enemies, "boss_killed": w.boss_killed,
		"evolutions": w.evolved.size(), "chests": w.chests_opened, "elites": w.elites_killed,
		"infected": w.terr.infected_fraction() if w.terr != null else 0.0,
		"conversions": w.conversions, "peak_allies": peak_allies,
		"rift": [w.rifts_opened, w.rifts_entered, w.rifts_won, w.rifts_timeout, w.rifts_ejected, w.missile_hits_boss, w.rp_uses],
		"best_streak": w.best_streak, "sec_per_level": w.time / maxf(w.level - 1, 1), "levels_2min": levels_2min,
		"ally_share": w.ally_damage / maxf(w.damage_dealt, 1.0), "harvested": w.gems_harvested, "orders": w.order_changes,
		"waves_cleared": w.waves_cleared, "towers": w.towers_built, "core_left": w.core_hp / w.core_max if w.def_on else 0.0,
		"gold": Progression.run_gold(d.balance, w.kills, w.time, w.boss_killed, w.state == "won", 0.0, w.bonus_gold_kills()),
	}


func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(round(p * (sorted.size() - 1))), 0, sorted.size() - 1)]


func _report(results: Array, d: Dictionary) -> Dictionary:
	var times := []
	var levels := []
	var causes := {}
	var wins := 0
	var bosses := 0
	var peak := 0
	var gold := 0
	var kills := 0
	var evos := 0
	var chests := 0
	var infected := 0.0
	var convs := 0
	var allies := 0
	var ally_share := 0.0
	var spl := 0.0
	var rift_tot := [0, 0, 0, 0, 0, 0, 0]
	var streaks := []
	var l2 := 0.0
	var harvested := 0
	var order_n := 0
	var waves := []
	var towers := 0
	var core_left := 0.0
	for r in results:
		waves.append(r.waves_cleared)
		towers += r.towers
		core_left += r.core_left
		times.append(r.time)
		levels.append(r.level)
		peak = maxi(peak, r.peak_enemies)
		gold += r.gold
		kills += r.kills
		evos += r.evolutions
		chests += r.chests
		infected += r.infected
		convs += r.conversions
		allies += r.peak_allies
		ally_share += r.ally_share
		spl += r.sec_per_level
		for q in 7:
			rift_tot[q] += int(r.rift[q])
		streaks.append(r.best_streak)
		l2 += maxi(r.levels_2min, 0)
		harvested += r.harvested
		order_n += r.orders
		if r.won:
			wins += 1
		else:
			causes[r.cause] = int(causes.get(r.cause, 0)) + 1
		if r.boss_killed:
			bosses += 1
	times.sort()
	levels.sort()
	waves.sort()
	streaks.sort()
	# Upgrade impact: mean survival time of runs that owned each upgrade.
	var impact := {}
	for u in d.upgrades:
		var sum := 0.0
		var n := 0
		for r in results:
			if r.owned.has(u.id):
				sum += r.time
				n += 1
		impact[u.id] = {"runs": n, "mean_time": snappedf(sum / maxf(n, 1), 0.1)}
	var buckets := {}
	for t in times:
		var b := "%d-%ds" % [int(t / 30) * 30, int(t / 30) * 30 + 30]
		buckets[b] = int(buckets.get(b, 0)) + 1
	return {
		"time_p10": snappedf(_pct(times, 0.1), 0.1),
		"time_p50": snappedf(_pct(times, 0.5), 0.1),
		"time_p90": snappedf(_pct(times, 0.9), 0.1),
		"win_rate": snappedf(float(wins) / maxf(results.size(), 1), 0.01),
		"boss_kill_rate": snappedf(float(bosses) / maxf(results.size(), 1), 0.01),
		"level_p50": _pct(levels, 0.5),
		"mean_kills": snappedf(float(kills) / maxf(results.size(), 1), 0.1),
		"mean_gold": snappedf(float(gold) / maxf(results.size(), 1), 0.1),
		"mean_infected": snappedf(infected / maxf(results.size(), 1), 0.001),
		"mean_conversions": snappedf(float(convs) / maxf(results.size(), 1), 0.1),
		"mean_peak_allies": snappedf(float(allies) / maxf(results.size(), 1), 0.1),
		"best_streak_p50": _pct(streaks, 0.5), "best_streak_p90": _pct(streaks, 0.9),
		"rifts": {"opened": rift_tot[0], "entered": rift_tot[1], "won": rift_tot[2], "timeout": rift_tot[3], "ejected": rift_tot[4], "missile_hits": rift_tot[5], "power_uses": rift_tot[6]},
		"mean_sec_per_level": snappedf(spl / maxf(results.size(), 1), 0.1),
		"mean_levels_by_2min": snappedf(l2 / maxf(results.size(), 1), 0.1),
		"mean_ally_damage_share": snappedf(ally_share / maxf(results.size(), 1), 0.001),
		"mean_gems_harvested": snappedf(float(harvested) / maxf(results.size(), 1), 0.1),
		"mean_order_changes": snappedf(float(order_n) / maxf(results.size(), 1), 0.1),
		"mean_chests": snappedf(float(chests) / maxf(results.size(), 1), 0.1),
		"mean_evolutions": snappedf(float(evos) / maxf(results.size(), 1), 0.01),
		"waves_cleared_p50": _pct(waves, 0.5),
		"waves_cleared_p10": _pct(waves, 0.1),
		"mean_towers": snappedf(float(towers) / maxf(results.size(), 1), 0.1),
		"mean_core_left": snappedf(core_left / maxf(results.size(), 1), 0.01),
		"peak_enemies": peak,
		"death_causes": causes,
		"death_time_buckets": buckets,
		"upgrade_mean_time": impact,
	}
