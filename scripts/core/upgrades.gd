class_name Upgrades
extends RefCounted
## Upgrade maths. Each upgrade's "levels" array holds stat deltas; the stats at
## level N are the sum of the first N entries.

const GLOBAL_STATS := ["might", "haste", "move", "max_hp", "magnet", "amount", "regen", "xp_gain", "gold_gain", "armor", "convert", "ally_power", "ally_cap", "hive", "convert_heal", "dash_charges", "dash_damage", "dash_decoy", "dash_cd", "dash_reset", "dash_volatile",
	# The Lab (data/lab.json) forks and keystones
	"crit", "max_hp_pct", "elite_damage", "lysis", "shield", "iframes_pct", "second_wind", "dash_cd_pen", "dash_phase", "slipstream", "head_start", "extra_offers", "mutation"]


static func max_level(def: Dictionary) -> int:
	return def.levels.size()


static func stats_at(def: Dictionary, level: int) -> Dictionary:
	var out := {}
	for l in mini(level, def.levels.size()):
		var row: Dictionary = def.levels[l]
		for k in row:
			out[k] = float(out.get(k, 0.0)) + float(row[k])
	return out


## Text for the card offering `def` at `next_level` (1-based).
static func describe(def: Dictionary, next_level: int) -> String:
	var desc: Array = def.desc
	return str(desc[mini(next_level - 1, desc.size() - 1)])


## Global stats from owned passives plus meta-progression bonuses.
static func global_stats(defs_by_id: Dictionary, owned: Dictionary, meta_bonus: Dictionary) -> Dictionary:
	var s := {}
	for k in GLOBAL_STATS:
		s[k] = 0.0
	for id in owned:
		var def: Dictionary = defs_by_id[id]
		if def.type != "passive":
			continue
		var st := stats_at(def, owned[id])
		for k in st:
			s[k] = float(s.get(k, 0.0)) + st[k]
	for k in meta_bonus:
		s[k] = float(s.get(k, 0.0)) + float(meta_bonus[k])
	return s


## Picks up to `count` distinct upgrade ids, weighted, skipping maxed ones and
## new weapons once the weapon slots are full. Owned items are weighted up so
## builds can come together.
static func roll_offers(defs: Array, owned: Dictionary, rng: RandomNumberGenerator, count: int, max_weapons: int, owned_mult: float) -> Array:
	var weapons_owned := 0
	for d in defs:
		if d.type == "weapon" and owned.has(d.id):
			weapons_owned += 1
	var pool := []
	var weights := []
	for d in defs:
		var lv := int(owned.get(d.id, 0))
		if lv >= max_level(d):
			continue
		if lv == 0 and d.type == "weapon" and weapons_owned >= max_weapons:
			continue
		var w := float(d.get("weight", 1.0))
		if lv > 0:
			w *= owned_mult
		pool.append(d.id)
		weights.append(w)
	var out := []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var r := rng.randf() * total
		var pick := pool.size() - 1
		for i in pool.size():
			r -= weights[i]
			if r <= 0.0:
				pick = i
				break
		out.append(pool[pick])
		pool.remove_at(pick)
		weights.remove_at(pick)
	return out
