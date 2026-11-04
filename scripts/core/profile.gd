class_name Profile
extends RefCounted
## The player's persistent progress, as plain data (pure logic, no I/O).
## SaveService loads/stores it as versioned JSON; the Online service will sync
## it with Play Games Saved Games later (see merge()).
##
## - stats: lifetime counters (runs, kills, kills_by_type, time_played, ...)
## - records: per game mode bests (best_time, best_score, best_infected_pct, ...)
## - achievements: id -> unix time unlocked (definitions in data/online.json)

const VERSION := 3  # 3: best_streak (lifetime stat + per-mode record); older saves load it as 0
## Lifetime counters that only ever grow (summed per run).
const COUNTERS := ["runs", "wins", "deaths", "kills", "time_played", "elites", "chests", "evolutions", "conversions", "dashes", "bosses", "gold_earned"]
## Per-mode record fields (kept as maximums).
const RECORD_FIELDS := ["runs", "wins", "best_time", "best_score", "best_kills", "best_level", "best_infected_pct", "best_conversions", "best_streak"]

var version := VERSION
var gold := 0
var meta_levels := {}  # meta id -> level
var settings := {"muted": false, "mode": "infection"}
var stats := {}  # COUNTERS + "kills_by_type" {enemy: n} + "evolved_ids" {evo: true} + "best_level" + "best_streak"
var records := {}  # mode id -> {RECORD_FIELDS}
var achievements := {}  # achievement id -> unix time
var updated_at := 0  # unix time of the last change (cloud conflict resolution)


func _init() -> void:
	for k in COUNTERS:
		stats[k] = 0
	stats["kills_by_type"] = {}
	stats["evolved_ids"] = {}
	stats["best_level"] = 0
	stats["best_streak"] = 0


# ------------------------------------------------------------ serialisation

func to_dict() -> Dictionary:
	return {
		"version": version, "gold": gold, "meta_levels": meta_levels, "settings": settings,
		"stats": stats, "records": records, "achievements": achievements, "updated_at": updated_at,
	}


static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.gold = int(d.get("gold", 0))
	p.meta_levels = _int_values(d.get("meta_levels", {}))
	var st: Dictionary = d.get("settings", {})
	for k in st:
		p.settings[k] = st[k]
	var s: Dictionary = d.get("stats", {})
	# JSON turns every number into a float: restore ints for counters.
	for k in COUNTERS:
		p.stats[k] = float(s.get(k, 0)) if k == "time_played" else int(s.get(k, 0))
	p.stats["kills_by_type"] = _int_values(s.get("kills_by_type", {}))
	p.stats["evolved_ids"] = s.get("evolved_ids", {}).duplicate()
	p.stats["best_level"] = int(s.get("best_level", 0))
	p.stats["best_streak"] = int(s.get("best_streak", 0))  # v2 saves: 0
	for mode in d.get("records", {}):
		var r := p._record(str(mode))
		var src: Dictionary = d.records[mode]
		for f in src:
			r[f] = float(src[f]) if f == "best_time" else int(src[f])
	for id in d.get("achievements", {}):
		p.achievements[str(id)] = int(d.achievements[id])
	p.updated_at = int(d.get("updated_at", 0))
	return p


## Builds a profile from the old ConfigFile-era fields (save.cfg, v1).
static func from_legacy(gold: int, meta_levels: Dictionary, best_time: float, runs: int, deaths: int, muted: bool, mode: String, best_times: Dictionary) -> Profile:
	var p := Profile.new()
	p.gold = gold
	p.meta_levels = _int_values(meta_levels)
	p.settings.muted = muted
	p.settings.mode = mode
	p.stats.runs = runs
	p.stats.deaths = deaths
	for m in best_times:
		p._record(str(m)).best_time = float(best_times[m])
	if best_times.is_empty() and best_time > 0.0:
		p._record("classic").best_time = best_time
	return p


static func _int_values(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = int(d[k])
	return out


# ---------------------------------------------------------------- queries

func meta_level(id: String) -> int:
	return int(meta_levels.get(id, 0))


## Developer tools (playtest builds only, balance.debug.dev_tools): free gold
## that doesn't count as earned, and a full refund of permanent upgrades.
func dev_grant_gold(amount: int, now: int) -> void:
	gold += amount
	updated_at = now


func refund_meta(defs: Array, now: int) -> int:
	var back := 0
	for d in defs:
		var lv := meta_level(d.id)
		for k in mini(lv, d.costs.size()):
			back += int(d.costs[k])
		meta_levels.erase(d.id)
	gold += back
	updated_at = now
	return back


## Buys the next level of a permanent upgrade if it isn't maxed and the gold
## covers it. Returns the gold spent (0 = nothing bought).
func buy_meta(def: Dictionary, now: int) -> int:
	var lv := meta_level(def.id)
	if lv >= def.costs.size() or gold < int(def.costs[lv]):
		return 0
	var cost := int(def.costs[lv])
	gold -= cost
	meta_levels[def.id] = lv + 1
	updated_at = now
	return cost


func best_time_any() -> float:
	var best := 0.0
	for m in records:
		best = maxf(best, float(records[m].get("best_time", 0.0)))
	return best


func record(mode: String) -> Dictionary:
	return records.get(mode, {})


## One flat dictionary of every trackable number, for achievements and the
## profile screen: lifetime counters, "kills_<enemy>", "best_<field>_<mode>",
## "evolutions_distinct", "modes_won", "best_level", "best_streak".
func flat() -> Dictionary:
	var out := {}
	for k in COUNTERS:
		out[k] = stats[k]
	out["best_level"] = stats.best_level
	out["best_streak"] = stats.best_streak
	for e in stats.kills_by_type:
		out["kills_" + str(e)] = stats.kills_by_type[e]
	out["evolutions_distinct"] = stats.evolved_ids.size()
	var won := 0
	for m in records:
		var r: Dictionary = records[m]
		for f in r:
			out["%s_%s" % [f, m]] = r[f]
		if int(r.get("wins", 0)) > 0:
			won += 1
	out["modes_won"] = won
	return out


func achievement_progress(def: Dictionary) -> float:
	return clampf(float(flat().get(def.stat, 0)) / maxf(float(def.goal), 0.0001), 0.0, 1.0)


# ---------------------------------------------------------------- updates

func _record(mode: String) -> Dictionary:
	if not records.has(mode):
		var r := {}
		for f in RECORD_FIELDS:
			r[f] = 0
		records[mode] = r
	return records[mode]


## Applies one finished run (see Progression.run_summary). Gold is NOT added
## here: the results screen adds it when collected (after a possible 2x ad).
## Returns the achievement definitions newly unlocked by this run.
func record_run(s: Dictionary, achievement_defs: Array, now: int) -> Array:
	stats.runs += 1
	if s.won:
		stats.wins += 1
	else:
		stats.deaths += 1
	stats.kills += int(s.kills)
	stats.time_played = float(stats.time_played) + float(s.time)
	stats.elites += int(s.elites)
	stats.chests += int(s.chests)
	stats.evolutions += int(s.evolved_ids.size())
	stats.conversions += int(s.conversions)
	stats.dashes += int(s.dashes)
	if s.boss_killed:
		stats.bosses += 1
	stats.best_level = maxi(int(stats.best_level), int(s.level))
	stats.best_streak = maxi(int(stats.best_streak), int(s.get("best_streak", 0)))
	for e in s.kills_by_type:
		stats.kills_by_type[e] = int(stats.kills_by_type.get(e, 0)) + int(s.kills_by_type[e])
	for evo in s.evolved_ids:
		stats.evolved_ids[evo] = true
	var r := _record(str(s.mode))
	r.runs = int(r.runs) + 1
	if s.won:
		r.wins = int(r.wins) + 1
	r.best_time = maxf(float(r.best_time), float(s.time))
	r.best_score = maxi(int(r.best_score), int(s.score))
	r.best_kills = maxi(int(r.best_kills), int(s.kills))
	r.best_level = maxi(int(r.best_level), int(s.level))
	r.best_infected_pct = maxi(int(r.best_infected_pct), int(s.infected_pct))
	r.best_conversions = maxi(int(r.best_conversions), int(s.conversions))
	r.best_streak = maxi(int(r.get("best_streak", 0)), int(s.get("best_streak", 0)))
	updated_at = now
	return check_achievements(achievement_defs, now)


func add_gold(amount: int, now: int) -> void:
	gold += amount
	stats.gold_earned = int(stats.gold_earned) + amount
	updated_at = now


## Unlocks every achievement whose goal is met; returns the new ones.
func check_achievements(defs: Array, now: int) -> Array:
	var f := flat()
	var fresh := []
	for a in defs:
		if achievements.has(a.id):
			continue
		if float(f.get(a.stat, 0)) >= float(a.goal):
			achievements[a.id] = now
			fresh.append(a)
	return fresh


## Combines two copies of a profile (e.g. this phone and the cloud save) so
## no progress is lost: counters, records and meta levels keep the larger
## value, achievements are unioned, and spendable gold/settings come from the
## more recently updated copy.
static func merge(a: Profile, b: Profile) -> Profile:
	var newer := a if a.updated_at >= b.updated_at else b
	var older := b if newer == a else a
	var m := Profile.from_dict(newer.to_dict())
	for k in COUNTERS:
		m.stats[k] = maxf(float(newer.stats[k]), float(older.stats[k])) if k == "time_played" else maxi(int(newer.stats[k]), int(older.stats[k]))
	m.stats.best_level = maxi(int(newer.stats.best_level), int(older.stats.best_level))
	m.stats.best_streak = maxi(int(newer.stats.best_streak), int(older.stats.best_streak))
	for e in older.stats.kills_by_type:
		m.stats.kills_by_type[e] = maxi(int(m.stats.kills_by_type.get(e, 0)), int(older.stats.kills_by_type[e]))
	for evo in older.stats.evolved_ids:
		m.stats.evolved_ids[evo] = true
	for id in older.meta_levels:
		m.meta_levels[id] = maxi(m.meta_level(id), int(older.meta_levels[id]))
	for mode in older.records:
		var r := m._record(mode)
		for f in older.records[mode]:
			r[f] = maxf(float(r.get(f, 0)), float(older.records[mode][f])) if f == "best_time" else maxi(int(r.get(f, 0)), int(older.records[mode][f]))
	for id in older.achievements:
		if not m.achievements.has(id):
			m.achievements[id] = older.achievements[id]
	return m
