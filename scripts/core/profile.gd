class_name Profile
extends RefCounted
## The player's persistent progress, as plain data (pure logic, no I/O).
## SaveService loads/stores it as versioned JSON; the Online service will sync
## it with Play Games Saved Games later (see merge()).
##
## - stats: lifetime counters (runs, kills, kills_by_type, time_played, ...)
## - records: per game mode bests (best_time, best_score, best_infected_pct, ...)
## - achievements: id -> unix time unlocked (definitions in data/online.json)

const VERSION := 7  # 3: best_streak; 4: per-mode "virulence" (highest level cleared) + settings.virulence (selected); 5: the Lab (genes, lab, abilities, stats.genes_earned); 6: shop tiers split in two; 7: cosmetics (bought) + settings.cosmetics (equipped). Older saves load 0 / empty
## v6 split these shop upgrades into twice as many tiers of half the bonus
## (same cap): a v5 level N becomes 2N, so nobody loses a bonus.
const META_SPLIT_V6 := ["meta_hp", "meta_might", "meta_haste", "meta_armor", "meta_regen", "meta_move", "meta_magnet", "meta_growth", "meta_greed", "meta_dash_cd", "meta_dash_dmg", "meta_dash_decoy", "meta_convert"]
const MAX_VIRULENCE := 10
## Lifetime counters that only ever grow (summed per run).
const COUNTERS := ["runs", "wins", "deaths", "kills", "time_played", "elites", "chests", "evolutions", "conversions", "dashes", "bosses", "gold_earned", "genes_earned"]
## Per-mode record fields (kept as maximums).
const RECORD_FIELDS := ["runs", "wins", "best_time", "best_score", "best_kills", "best_level", "best_infected_pct", "best_conversions", "best_streak", "virulence"]

var version := VERSION
var gold := 0
var meta_levels := {}  # meta id -> level
var settings := {"muted": false, "mode": "infection"}
var stats := {}  # COUNTERS + "kills_by_type" {enemy: n} + "evolved_ids" {evo: true} + "best_level" + "best_streak"
var records := {}  # mode id -> {RECORD_FIELDS}
var achievements := {}  # achievement id -> unix time
var genes := 0  # Lab currency, earned on Virulence wins (data/lab.json genes)
var lab := {}  # Lab node id -> level
var abilities := {}  # reserved: ability levels live in `lab` (their unlock nodes); equipped one in settings.equipped_ability
var cosmetics := {}  # cosmetic id -> unix time bought with gold (challenge unlocks come from stats; see Cosmetics)
var last_genes := 0  # Genes the last record_run() granted (results screen)
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
		"genes": genes, "lab": lab, "abilities": abilities, "cosmetics": cosmetics,
	}


static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.gold = int(d.get("gold", 0))
	p.meta_levels = _int_values(d.get("meta_levels", {}))
	if int(d.get("version", 0)) < 6:
		_split_meta(p.meta_levels)
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
	p.genes = int(d.get("genes", 0))  # v4 saves: no Lab yet
	p.lab = _int_values(d.get("lab", {}))
	p.abilities = _int_values(d.get("abilities", {}))
	p.cosmetics = _int_values(d.get("cosmetics", {}))  # v6 saves: none bought yet
	return p


## Builds a profile from the old ConfigFile-era fields (save.cfg, v1).
static func from_legacy(gold: int, meta_levels: Dictionary, best_time: float, runs: int, deaths: int, muted: bool, mode: String, best_times: Dictionary) -> Profile:
	var p := Profile.new()
	p.gold = gold
	p.meta_levels = _int_values(meta_levels)
	_split_meta(p.meta_levels)
	p.settings.muted = muted
	p.settings.mode = mode
	p.stats.runs = runs
	p.stats.deaths = deaths
	for m in best_times:
		p._record(str(m)).best_time = float(best_times[m])
	if best_times.is_empty() and best_time > 0.0:
		p._record("classic").best_time = best_time
	return p


static func _split_meta(levels: Dictionary) -> void:
	for id in levels:
		if META_SPLIT_V6.has(id):
			levels[id] = int(levels[id]) * 2


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


# ------------------------------------------------------------------ the Lab

func lab_level(id: String) -> int:
	return int(lab.get(id, 0))


## Buys the next level of a Lab node if it's open, not maxed, not the other
## side of a taken fork, and the Genes cover it. Returns the Genes spent.
func buy_lab(cfg: Dictionary, node: Dictionary, now: int) -> int:
	if not Lab.can_buy(cfg, node, lab, genes):
		return 0
	var cost := Lab.next_cost(node, lab)
	genes -= cost
	lab[node.id] = lab_level(node.id) + 1
	updated_at = now
	return cost


## Resets the whole Lab for gold (cfg.respec_gold) and refunds every Gene.
## Returns the Genes refunded, or -1 if the gold doesn't cover it.
func respec_lab(cfg: Dictionary, now: int) -> int:
	var price := int(cfg.get("respec_gold", 0))
	if gold < price:
		return -1
	var back := Lab.spent(cfg, lab)
	gold -= price
	genes += back
	lab = {}
	updated_at = now
	return back


## The equipped ability (settings.equipped_ability), or "" if none is set or
## it's no longer unlocked (e.g. after a respec).
func equipped_ability(cfg: Dictionary) -> String:
	var id := str(settings.get("equipped_ability", ""))
	return id if id != "" and Lab.ability_level(cfg, lab, id) > 0 else ""


## Equips an unlocked ability ("" unequips). Returns false if it's locked.
func equip_ability(cfg: Dictionary, id: String) -> bool:
	if id != "" and Lab.ability_level(cfg, lab, id) <= 0:
		return false
	settings["equipped_ability"] = id
	return true


## Lab nodes that were removed (cfg.retired: id -> old costs) are refunded in
## full; nodes whose costs changed (cfg.repriced: id -> old costs) refund the
## difference. Safe to call on every load. Returns the Genes refunded.
func migrate_lab(cfg: Dictionary, now: int) -> int:
	var back := 0
	var retired: Dictionary = cfg.get("retired", {})
	var repriced: Dictionary = cfg.get("repriced", {})
	for id in lab.keys():
		var lv := lab_level(id)
		if retired.has(id) or Lab.find(cfg, id).is_empty():
			var old: Array = retired.get(id, [])
			for k in mini(lv, old.size()):
				back += int(old[k])
			lab.erase(id)
		elif repriced.has(id) and not settings.get("lab_repriced", {}).has(id):
			var old: Array = repriced[id]
			var node := Lab.find(cfg, id)
			for k in mini(lv, old.size()):
				back += int(old[k])
			lv = mini(lv, Lab.max_level(node))
			lab[id] = lv
			for k in lv:
				back -= int(node.costs[k])
	for id in repriced:
		if not settings.has("lab_repriced"):
			settings["lab_repriced"] = {}
		settings.lab_repriced[id] = true  # only once per node
	if back != 0:
		genes = maxi(0, genes + back)
		updated_at = now
	return back


## Developer tools: free Genes that don't count as earned.
func dev_grant_genes(amount: int, now: int) -> void:
	genes += amount
	updated_at = now


## Genes for winning `mode` at Virulence `level`: the first clear of a level
## pays genes_cfg.first_clear[level - 1], a repeat win genes_cfg.repeat_win.
## Call before record_run() updates the record.
func genes_for_win(genes_cfg: Dictionary, mode: String, level: int) -> int:
	if genes_cfg.is_empty():
		return 0
	if level > virulence_cleared(mode):
		var fc: Array = genes_cfg.first_clear
		return int(fc[clampi(level, 1, fc.size()) - 1])
	return int(genes_cfg.get("repeat_win", 0))


## Genes for time survived (won or lost) at Virulence per_minute_from_v+:
## per_minute per completed minute, at most per_minute_max per run. Keeps the
## Lab moving while a player is stuck below a new clear.
func genes_for_time(genes_cfg: Dictionary, level: int, time_s: float) -> int:
	if genes_cfg.is_empty() or level < int(genes_cfg.get("per_minute_from_v", 99)):
		return 0
	return mini(int(floor(time_s / 60.0)) * int(genes_cfg.get("per_minute", 0)), int(genes_cfg.get("per_minute_max", 0)))


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
	var vmax := 0
	for m in records:
		vmax = maxi(vmax, int(records[m].get("virulence", 0)))
	out["best_virulence"] = vmax
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
## Genes from a win (genes_cfg = data/lab.json "genes") ARE added here; the
## amount is left in last_genes for the results screen.
## Returns the achievement definitions newly unlocked by this run.
func record_run(s: Dictionary, achievement_defs: Array, now: int, genes_cfg: Dictionary = {}) -> Array:
	last_genes = genes_for_win(genes_cfg, str(s.mode), int(s.get("virulence", 1))) if s.won else 0
	last_genes += genes_for_time(genes_cfg, int(s.get("virulence", 1)), float(s.time))
	genes += last_genes
	stats.genes_earned = int(stats.genes_earned) + last_genes
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
	if s.won:
		r.virulence = maxi(int(r.get("virulence", 0)), int(s.get("virulence", 1)))
	updated_at = now
	return check_achievements(achievement_defs, now)


# ---------------------------------------------------------------- Virulence

## Highest Virulence level won in a mode (0 = none yet).
func virulence_cleared(mode: String) -> int:
	return int(records.get(mode, {}).get("virulence", 0))


## Highest level you may pick: one above the best cleared (1..10), or all of
## them with the developer toggle (which never touches the records).
func virulence_unlocked(mode: String) -> int:
	if dev_all_virulence():
		return MAX_VIRULENCE
	return clampi(virulence_cleared(mode) + 1, 1, MAX_VIRULENCE)


func dev_all_virulence() -> bool:
	return bool(settings.get("dev_all_virulence", false))


## Developer toggle: every cosmetic usable (nothing is bought or saved as
## owned, so turning it off restores the real collection).
func dev_all_cosmetics() -> bool:
	return bool(settings.get("dev_all_cosmetics", false))


## The level picked on the mode card (defaults to the highest unlocked; any
## unlocked level can be replayed).
func virulence_selected(mode: String) -> int:
	var sel: Dictionary = settings.get("virulence", {})
	return clampi(int(sel.get(mode, virulence_unlocked(mode))), 1, virulence_unlocked(mode))


func set_virulence(mode: String, level: int) -> void:
	if not settings.has("virulence") or not (settings.virulence is Dictionary):
		settings["virulence"] = {}
	settings.virulence[mode] = clampi(level, 1, virulence_unlocked(mode))


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
## lab_cfg (data/lab.json) lets it tell fork partners apart.
static func merge(a: Profile, b: Profile, lab_cfg: Dictionary = {}) -> Profile:
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
	# Lab: nodes keep the higher level, unless the older copy took the other
	# side of a fork (the newer copy's choice wins). Genes are spendable, so
	# they come from the newer copy like gold.
	for id in older.lab:
		var other_side := false
		for nid in m.lab:
			var na := Lab.find(lab_cfg, id)
			var nb := Lab.find(lab_cfg, nid)
			if nid != id and m.lab_level(nid) > 0 and na.has("fork") and nb.get("fork", "") == na.fork:
				other_side = true
		if not other_side:
			m.lab[id] = maxi(m.lab_level(id), int(older.lab[id]))
	for id in older.abilities:
		m.abilities[id] = maxi(int(m.abilities.get(id, 0)), int(older.abilities[id]))
	for id in older.cosmetics:  # bought cosmetics are never lost
		if not m.cosmetics.has(id):
			m.cosmetics[id] = older.cosmetics[id]
	for id in older.achievements:
		if not m.achievements.has(id):
			m.achievements[id] = older.achievements[id]
	return m

