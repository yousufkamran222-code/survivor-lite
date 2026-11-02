extends SceneTree
## Headless balance simulator: plays many seeded runs with BalanceBot and
## reports survival-time distribution, levels, death causes and upgrade impact.
##
## Usage:
##   godot --headless --path . -s res://tools/sim/balance_sim.gd -- --runs 40 --seed 1000
## Options: --runs N, --seed S, --meta (use maxed meta upgrades),
## --mode ID (data/modes.json, default: first mode), --classic (= --mode classic),
## --json PATH

const DT := 1.0 / 30.0


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", 30))
	var seed0 := int(args.get("seed", 1000))
	var mode_id := "classic" if args.has("classic") else str(args.get("mode", ""))
	var d := GameData.load_all()
	if mode_id == "":
		mode_id = d.modes[0].id
	d = GameData.apply_mode(d, mode_id)
	var meta := {}
	if args.has("meta"):
		var levels := {}
		for m in d.meta:
			levels[m.id] = m.costs.size()
		meta = Progression.meta_bonus(d.meta, levels)
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


func _play(d: Dictionary, seed_value: int, meta: Dictionary) -> Dictionary:
	var w := World.new(d, seed_value, meta)
	w.emit_events = false
	var bot := BalanceBot.new(seed_value)
	var peak_enemies := 0
	var peak_allies := 0
	var hp_at_boss := -1.0
	while w.state in ["playing", "levelup", "chest"]:
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
		if hp_at_boss < 0.0 and w.boss_index >= 0:
			hp_at_boss = w.p_hp / w.p_max_hp
	return {
		"seed": seed_value, "time": w.time, "won": w.state == "won", "level": w.level,
		"kills": w.kills, "cause": w.death_cause, "owned": w.owned.duplicate(),
		"peak_enemies": peak_enemies, "boss_killed": w.boss_killed,
		"evolutions": w.evolved.size(), "chests": w.chests_opened, "elites": w.elites_killed,
		"infected": w.terr.infected_fraction() if w.terr != null else 0.0,
		"conversions": w.conversions, "peak_allies": peak_allies,
		"waves_cleared": w.waves_cleared, "towers": w.towers_built, "core_left": w.core_hp / w.core_max if w.def_on else 0.0,
		"gold": Progression.run_gold(d.balance, w.kills, w.time, w.boss_killed, w.state == "won", 0.0),
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
		if r.won:
			wins += 1
		else:
			causes[r.cause] = int(causes.get(r.cause, 0)) + 1
		if r.boss_killed:
			bosses += 1
	times.sort()
	levels.sort()
	waves.sort()
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
