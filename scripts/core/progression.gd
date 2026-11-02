class_name Progression
extends RefCounted
## XP curve, gold rewards and the between-run (meta) upgrade shop.


static func xp_needed(balance: Dictionary, level: int) -> float:
	var x: Dictionary = balance.xp
	var l := float(level - 1)
	return floor(float(x.base) + float(x.linear) * l + float(x.quad) * l * l)


static func run_gold(balance: Dictionary, kills: int, time_s: float, boss_killed: bool, won: bool, gold_gain: float) -> int:
	var e: Dictionary = balance.economy
	var g := kills * float(e.gold_per_kill) + time_s / 60.0 * float(e.gold_per_minute)
	if boss_killed:
		g += float(e.gold_boss_bonus)
	if won:
		g += float(e.gold_victory_bonus)
	return int(floor(g * (1.0 + gold_gain)))


## meta_levels: { meta_id: level }. Returns { stat: total_bonus }.
static func meta_bonus(meta_defs: Array, meta_levels: Dictionary) -> Dictionary:
	var out := {}
	for m in meta_defs:
		var lv := mini(int(meta_levels.get(m.id, 0)), m.costs.size())
		if lv > 0:
			out[m.stat] = float(out.get(m.stat, 0.0)) + float(m.per_level) * lv
	return out


## Human-readable current total, e.g. "+12%" or "+30" ("" at level 0).
static func meta_total_text(meta_def: Dictionary, level: int) -> String:
	if level <= 0:
		return ""
	var v := float(meta_def.per_level) * level
	if meta_def.get("fmt", "flat") == "pct":
		return "+%d%%" % roundi(v * 100.0)
	return "+%s" % (str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v)


## Everything about a finished run that profiles, leaderboards and analytics
## need (one dictionary, no references into the World).
static func run_summary(w: World, won: bool, mode_id: String, scoring: Dictionary) -> Dictionary:
	var evolved_ids := []
	for wid in w.evolved:
		evolved_ids.append(w.evolved[wid])
	var s := {
		"mode": mode_id, "won": won, "time": w.time, "kills": w.kills, "level": w.level,
		"elites": w.elites_killed, "chests": w.chests_opened, "evolved_ids": evolved_ids,
		"conversions": w.conversions, "dashes": w.dashes, "boss_killed": w.boss_killed,
		"kills_by_type": w.kills_by_type.duplicate(),
		"infected_pct": roundi(w.terr.infected_fraction() * 100.0) if w.terr != null else 0,
	}
	s["score"] = run_score(s, scoring)
	return s


## Leaderboard score: rewards killing, surviving and the mode's own goal.
static func run_score(s: Dictionary, k: Dictionary) -> int:
	var v := float(s.kills) * float(k.per_kill) + float(s.time) * float(k.per_second)
	v += float(s.elites) * float(k.per_elite) + float(s.evolved_ids.size()) * float(k.per_evolution)
	v += float(s.infected_pct) * float(k.per_infected_pct) + float(s.conversions) * float(k.per_conversion)
	if s.boss_killed:
		v += float(k.boss)
	if s.won:
		v += float(k.win)
	return int(v)


static func metric_value(s: Dictionary, metric: String) -> int:
	match metric:
		"score":
			return int(s.score)
		"infected_pct":
			return int(s.infected_pct)
		"conversions":
			return int(s.conversions)
		"kills":
			return int(s.kills)
		"time":
			return int(s.time)
	return 0


## Cost of the next level, or -1 if maxed.
static func meta_next_cost(meta_def: Dictionary, level: int) -> int:
	if level >= meta_def.costs.size():
		return -1
	return int(meta_def.costs[level])
