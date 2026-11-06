class_name GameData
extends RefCounted
## Loads the JSON tables in res://data and validates cross-references.
## Every tunable number lives in data/, never in code.

const FILES := ["balance", "enemies", "upgrades", "waves", "meta", "evolutions", "modes", "online", "towers", "hints", "difficulty", "lab", "cosmetics"]
const VIRULENCE_MODS := ["enemy_speed_mult", "knock_resist_add", "budget_mult", "ranged_weight_mult", "shot_speed_mult", "iframes_mult",
	"final_minute_s", "breather_mult", "boss_time_s", "boss_burst_mult", "damage_taken_mult", "enemy_hp_mult"]


static func load_all(dir: String = "res://data") -> Dictionary:
	var out := {}
	for f in FILES:
		out[f] = load_json("%s/%s.json" % [dir, f])
	return out


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("GameData: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		push_error("GameData: invalid JSON in %s" % path)
		return {}
	return parsed


## A copy of the game data with a game mode's overrides deep-merged into
## balance. Unknown mode ids return an unmodified copy.
static func apply_mode(d: Dictionary, mode_id: String) -> Dictionary:
	var out := d.duplicate(true)
	for m in d.get("modes", []):
		if m.id == mode_id:
			_merge(out.balance, m.get("overrides", {}))
			out.balance["mode_id"] = mode_id
	return out


## Virulence (data/difficulty.json): level N stacks the modifiers of levels
## 2..N on a mode-applied copy of the data. *_mult multiply, *_add add, and
## the *_s times take the earliest. Also sets balance.virulence and the
## gold/score multipliers. Level 1 changes nothing.
static func virulence_mods(d: Dictionary, level: int) -> Dictionary:
	var m := {}
	var levels: Array = d.get("difficulty", {}).get("levels", [])
	for k in range(1, mini(level, levels.size())):
		var mods: Dictionary = levels[k].get("mods", {})
		for key in mods:
			var v := float(mods[key])
			if key.ends_with("_mult"):
				m[key] = float(m.get(key, 1.0)) * v
			elif key.ends_with("_add"):
				m[key] = float(m.get(key, 0.0)) + v
			else:
				m[key] = minf(float(m.get(key, INF)), v)
	return m


static func apply_virulence(d: Dictionary, level: int) -> Dictionary:
	var out := d.duplicate(true)
	var levels: Array = d.get("difficulty", {}).get("levels", [])
	level = clampi(level, 1, maxi(levels.size(), 1))
	var m := virulence_mods(d, level)
	var b: Dictionary = out.balance
	var w: Dictionary = out.waves
	if not b.has("difficulty"):
		b["difficulty"] = {}
	var diff: Dictionary = b.difficulty
	var mode_hp := float(diff.get("enemy_hp_mult", 1.0))
	b["virulence"] = level
	diff["gold_mult"] = 1.0 + float(d.difficulty.get("gold_per_level", 0.0)) * (level - 1)
	diff["score_mult"] = 1.0 + float(d.difficulty.get("score_per_level", 0.0)) * (level - 1)
	for key in ["enemy_speed_mult", "shot_speed_mult", "damage_taken_mult", "enemy_hp_mult"]:
		if m.has(key):
			diff[key] = float(diff.get(key, 1.0)) * float(m[key])
	# The base ramp under every level's own modifier: tougher, harder-hitting
	# germs (and Mother Cell), compounding per level (gentle early, steep late).
	# Per-mode strength (Nucleus already scales enemies per wave, so it ramps less).
	var steps := (level - 1) * float(d.difficulty.get("ramp_scale", {}).get(str(b.get("mode_id", "")), 1.0))
	var hp_ramp := pow(float(d.difficulty.get("hp_growth", 1.0)), steps)
	var dmg_ramp := pow(float(d.difficulty.get("damage_growth", 1.0)), steps)
	if level > 1:
		diff["enemy_hp_mult"] = float(diff.get("enemy_hp_mult", 1.0)) * hp_ramp
		diff["damage_taken_mult"] = float(diff.get("damage_taken_mult", 1.0)) * dmg_ramp
		diff["boss_hp_mult"] = float(diff.get("boss_hp_mult", 1.0)) * hp_ramp
	# The part of enemy HP that Virulence added (the dash family divides it
	# back out: it keeps up with in-run growth, not with the ladder).
	diff["virulence_hp_mult"] = float(diff.get("enemy_hp_mult", 1.0)) / maxf(mode_hp, 0.0001)
	if m.has("knock_resist_add"):
		diff["knock_resist_add"] = float(m.knock_resist_add)
	if m.has("budget_mult"):
		for p in w.budget_curve:
			p[1] = float(p[1]) * float(m.budget_mult)
		for wv in w.get("defense", {}).get("waves", []):
			wv["budget"] = float(wv.budget) * float(m.budget_mult)
	if m.has("ranged_weight_mult"):
		var ranged := {}
		for e in out.enemies:
			if e.behavior == "ranged":
				ranged[e.id] = true
		for p in w.pool:
			if ranged.has(p.enemy):
				p["weight"] = float(p.weight) * float(m.ranged_weight_mult)
	if m.has("iframes_mult"):
		b.player["iframes_s"] = float(b.player.iframes_s) * float(m.iframes_mult)
	if m.has("final_minute_s"):
		w["final_minute_s"] = minf(float(w.get("final_minute_s", INF)), float(m.final_minute_s))
		if w.has("elites"):
			w.elites["final_from_s"] = minf(float(w.elites.get("final_from_s", INF)), float(m.final_minute_s))
	if m.has("breather_mult") and b.has("defense"):
		for key in ["breather_s", "boss_breather_s", "first_breather_s"]:
			if b.defense.has(key):
				b.defense[key] = float(b.defense[key]) * float(m.breather_mult)
	if m.has("boss_time_s"):
		for ev in w.events:
			if ev.enemy == "boss":
				ev["t"] = minf(float(ev.t), float(m.boss_time_s))
	if m.has("boss_burst_mult"):
		for e in out.enemies:
			if e.behavior == "boss":
				e["burst_count"] = int(round(float(e.burst_count) * float(m.boss_burst_mult)))
	return out


static func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if over[k] is Dictionary and base.get(k) is Dictionary:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]


static func color(hex: String) -> Color:
	return Color.from_string(hex, Color.MAGENTA)


## Returns a list of human-readable problems. Empty list = data is consistent.
static func validate(d: Dictionary) -> Array:
	var errors := []
	var enemy_ids := {}
	for e in d.enemies:
		for key in ["id", "name", "behavior", "hp", "speed", "damage", "radius", "xp", "cost", "color"]:
			if not e.has(key):
				errors.append("enemy %s missing '%s'" % [e.get("id", "?"), key])
		enemy_ids[e.get("id", "")] = e
	for e in d.enemies:
		if e.has("split_into") and not enemy_ids.has(e.split_into):
			errors.append("enemy %s splits into unknown '%s'" % [e.id, e.split_into])
		if float(e.get("radius", 0)) > float(d.balance.perf.max_enemy_radius):
			errors.append("enemy %s radius exceeds perf.max_enemy_radius" % e.id)
	for p in d.waves.pool:
		if not enemy_ids.has(p.enemy):
			errors.append("waves.pool references unknown enemy '%s'" % p.enemy)
	for ev in d.waves.events:
		if not enemy_ids.has(ev.enemy):
			errors.append("waves.events references unknown enemy '%s'" % ev.enemy)
	var up_ids := {}
	for u in d.upgrades:
		up_ids[u.id] = true
		if not (u.type in ["weapon", "passive"]):
			errors.append("upgrade %s has bad type '%s'" % [u.id, u.type])
		if u.levels.is_empty():
			errors.append("upgrade %s has no levels" % u.id)
		if u.get("desc", []).is_empty():
			errors.append("upgrade %s has no desc" % u.id)
	if not up_ids.has(d.balance.start_weapon):
		errors.append("balance.start_weapon '%s' is not an upgrade" % d.balance.start_weapon)
	for m in d.meta:
		if m.costs.is_empty():
			errors.append("meta %s has no costs" % m.id)
		if str(m.get("label", "")) == "":
			errors.append("meta %s needs a short 'label' for the shop" % m.id)
		if not Upgrades.GLOBAL_STATS.has(m.stat):
			errors.append("meta %s uses unknown stat '%s'" % [m.id, m.stat])
		for k in range(1, m.costs.size()):
			if int(m.costs[k]) <= int(m.costs[k - 1]):
				errors.append("meta %s costs must increase" % m.id)
	var evolved_weapons := {}
	for ev in d.evolutions:
		var w: Variant = null
		for u in d.upgrades:
			if u.id == ev.weapon:
				w = u
		if w == null or w.type != "weapon":
			errors.append("evolution %s: '%s' is not a weapon" % [ev.id, ev.weapon])
		if not up_ids.has(ev.requires):
			errors.append("evolution %s requires unknown upgrade '%s'" % [ev.id, ev.requires])
		if evolved_weapons.has(ev.weapon):
			errors.append("weapon %s has more than one evolution" % ev.weapon)
		evolved_weapons[ev.weapon] = true
	var mode_ids := {}
	for m in d.get("modes", []):
		mode_ids[m.id] = true
	for u in d.upgrades:
		for mid in u.get("modes", []):
			if not mode_ids.has(mid):
				errors.append("upgrade %s lists unknown mode '%s'" % [u.id, mid])
	mode_ids = {}
	for m in d.get("modes", []):
		if mode_ids.has(m.id):
			errors.append("duplicate mode id '%s'" % m.id)
		mode_ids[m.id] = true
		for k in m.get("overrides", {}):
			if not d.balance.has(k):
				errors.append("mode %s overrides unknown balance key '%s'" % [m.id, k])
	if d.has("online") and d.online is Dictionary and d.online.has("leaderboards"):
		var ach_ids := {}
		for lb in d.online.leaderboards:
			if not mode_ids.has(lb.mode):
				errors.append("leaderboard %s uses unknown mode '%s'" % [lb.id, lb.mode])
			if not (lb.metric in ["score", "infected_pct", "conversions", "kills", "time"]):
				errors.append("leaderboard %s has unknown metric '%s'" % [lb.id, lb.metric])
		for a in d.online.achievements:
			if ach_ids.has(a.id):
				errors.append("duplicate achievement '%s'" % a.id)
			ach_ids[a.id] = true
			if float(a.goal) <= 0.0:
				errors.append("achievement %s needs a positive goal" % a.id)
	_validate_defense(d, enemy_ids, errors)
	_validate_hints(d, errors)
	_validate_lab(d, errors)
	_validate_cosmetics(d, errors)
	# Virulence: 10 levels, known modifiers only.
	var diffd: Dictionary = d.get("difficulty", {})
	if diffd.get("levels", []).size() != 10:
		errors.append("difficulty.json needs 10 levels")
	for lv in diffd.get("levels", []):
		for key in lv.get("mods", {}):
			if not (key in VIRULENCE_MODS):
				errors.append("difficulty level '%s': unknown modifier '%s'" % [lv.get("name", "?"), key])
	# Boss Rift: every weapon maps to a known power with its numbers.
	var rift: Dictionary = d.balance.get("rift", {})
	if rift.get("enabled", false):
		var weapon_ids := {}
		for u in d.upgrades:
			if u.type == "weapon":
				weapon_ids[u.id] = true
		for wid in rift.get("weapon_power", {}):
			if not weapon_ids.has(wid):
				errors.append("rift.weapon_power: unknown weapon '%s'" % wid)
			var pw: String = rift.weapon_power[wid]
			if not (pw in ["lance", "barrage", "phalanx", "heatwave"]) or not rift.get("powers", {}).has(pw):
				errors.append("rift.weapon_power: unknown power '%s'" % pw)
		for key in ["boss", "powers", "arena_radius", "duration_s", "eject_grace_s"]:
			if not rift.has(key):
				errors.append("rift missing '%s'" % key)
	# Kill streak: ascending milestones and tiers; rewards use known kinds.
	var stk: Dictionary = d.balance.get("streak", {})
	for key in ["window_s", "milestones", "tiers"]:
		if not stk.has(key):
			errors.append("balance.streak missing '%s'" % key)
	var prev := 0
	for m in stk.get("milestones", []):
		if int(m) <= prev:
			errors.append("balance.streak.milestones must increase")
		prev = int(m)
	prev = 0
	for t in stk.get("tiers", []):
		if int(t.at) <= prev or not t.has("name") or not t.has("color"):
			errors.append("balance.streak.tiers: each needs an increasing 'at', a name and a color")
		prev = int(t.at)
	for r in stk.get("rewards", []):
		if not r.has("at"):
			errors.append("balance.streak.rewards entry needs 'at'")
		if r.has("pickup") and not (str(r.pickup) in World.PICKUP_KINDS):
			errors.append("balance.streak.rewards: unknown pickup '%s'" % r.pickup)
		if not (r.has("pickup") or r.has("outbreak")):
			errors.append("balance.streak.rewards entry needs 'pickup' or 'outbreak'")
	# Swarm orders: World needs every order id, and Hunt/Harvest a radius.
	var orders: Dictionary = d.balance.get("conversion", {}).get("orders", {})
	for oid in World.ORDER_IDS:
		if not orders.has(oid):
			errors.append("conversion.orders is missing '%s'" % oid)
			continue
		for key in ["name", "desc", "color"] + (["radius"] if oid != "guard" else []) + (["grab"] if oid == "harvest" else []):
			if not orders[oid].has(key):
				errors.append("conversion.orders.%s missing '%s'" % [oid, key])
	for kind in d.balance.get("outbreak", {}).get("pickups", []):
		if not (kind in World.PICKUP_KINDS):
			errors.append("outbreak.pickups: unknown pickup '%s'" % kind)
	if d.waves.has("elites"):
		for t in d.waves.elites.types:
			if not enemy_ids.has(t):
				errors.append("waves.elites references unknown enemy '%s'" % t)
			elif float(enemy_ids[t].radius) * float(d.waves.elites.radius_mult) > float(d.balance.perf.max_enemy_radius):
				errors.append("elite %s radius exceeds perf.max_enemy_radius" % t)
	return errors


## Nucleus (tower defence) mode: towers and the wave table.
static func _validate_defense(d: Dictionary, enemy_ids: Dictionary, errors: Array) -> void:
	var tower_ids := {}
	for t in d.get("towers", []):
		if tower_ids.has(t.id):
			errors.append("duplicate tower '%s'" % t.id)
		tower_ids[t.id] = true
		if not (t.get("weapon", "") in ["bolt", "orbit", "nova", "chain"]):
			errors.append("tower %s uses unsupported weapon '%s'" % [t.id, t.get("weapon", "")])
		if t.levels.is_empty():
			errors.append("tower %s has no levels" % t.id)
		for k in t.levels.size():
			var need: Array = {"bolt": ["speed", "count", "pierce", "size", "knockback"], "orbit": ["count", "size", "orbit_radius", "spin", "hit_interval", "knockback"],
				"nova": ["area", "knockback"], "chain": ["jumps", "jump_range"]}.get(t.get("weapon", ""), [])
			for key in ["cost", "damage", "cooldown", "range"] + need:
				if not t.levels[k].has(key):
					errors.append("tower %s level %d missing '%s'" % [t.id, k + 1, key])
			if k > 0 and int(t.levels[k].cost) <= int(t.levels[k - 1].cost):
				errors.append("tower %s costs must increase" % t.id)
	if not d.waves.has("defense"):
		return
	var pool_ids := {}
	for p in d.waves.pool:
		pool_ids[p.enemy] = true
	var vents := int(d.balance.get("defense", {}).get("vents", 0))
	var waves: Array = d.waves.defense.waves
	if waves.is_empty():
		errors.append("waves.defense has no waves")
	if d.get("towers", []).is_empty():
		errors.append("the Nucleus mode needs at least one tower")
	for k in waves.size():
		var wv: Dictionary = waves[k]
		for e in wv.enemies:
			if not pool_ids.has(e):
				errors.append("defense wave %d: '%s' is not in waves.pool" % [k + 1, e])
		if wv.vents.is_empty():
			errors.append("defense wave %d has no vents" % [k + 1])
		for v in wv.vents:
			if int(v) < 0 or int(v) >= vents:
				errors.append("defense wave %d uses vent %d (only %d)" % [k + 1, int(v), vents])
		if float(wv.duration) <= 0.0 or float(wv.budget) <= 0.0:
			errors.append("defense wave %d needs a positive duration and budget" % [k + 1])


## First-run hints: a "shared" list plus one per mode, each with an id, text
## and either "at" (run seconds) or "event" (a World event type).
static func _validate_hints(d: Dictionary, errors: Array) -> void:
	var h: Variant = d.get("hints", {})
	if not (h is Dictionary):
		errors.append("hints.json must be an object")
		return
	var mode_ids := {}
	for m in d.get("modes", []):
		mode_ids[m.id] = true
	var seen := {}
	for key in h:
		if key != "shared" and not mode_ids.has(key):
			errors.append("hints: unknown mode '%s'" % key)
		for hint in h[key]:
			var id := str(hint.get("id", ""))
			if id == "" or str(hint.get("text", "")) == "":
				errors.append("hints.%s: every hint needs an id and text" % key)
			if seen.has(id):
				errors.append("hints: duplicate id '%s'" % id)
			seen[id] = true
			if not hint.has("at") and not hint.has("event"):
				errors.append("hints: '%s' needs 'at' or 'event'" % id)


## The Lab (data/lab.json): known stats, unique ids, rising tiers that start
## at 1, a fork pair per branch and costs > 0.
static func _validate_lab(d: Dictionary, errors: Array) -> void:
	if not d.has("lab") or d.lab.is_empty():
		return
	var ids := {}
	for b in d.lab.branches:
		var tiers := {}
		var forks := {}
		for n in b.nodes:
			if ids.has(n.id):
				errors.append("lab node %s is duplicated" % n.id)
			ids[n.id] = true
			tiers[int(n.tier)] = true
			if n.costs.is_empty():
				errors.append("lab node %s has no costs" % n.id)
			for c in n.costs:
				if int(c) <= 0:
					errors.append("lab node %s has a cost <= 0" % n.id)
			if n.has("ability"):
				var ab: Dictionary = d.lab.get("abilities", {}).get(str(n.ability), {})
				if ab.is_empty():
					errors.append("lab node %s unlocks unknown ability '%s'" % [n.id, n.ability])
				elif ab.levels.size() != n.costs.size():
					errors.append("lab node %s needs one cost per level of %s" % [n.id, n.ability])
			elif n.effects.is_empty():
				errors.append("lab node %s has no effects" % n.id)
			for k in n.effects:
				if not Upgrades.GLOBAL_STATS.has(k):
					errors.append("lab node %s uses unknown stat '%s'" % [n.id, k])
			if not n.has("desc") and str(n.get("label", "")) == "":
				errors.append("lab node %s needs a 'desc' or a 'label'" % n.id)
			if n.has("fork"):
				forks[n.fork] = int(forks.get(n.fork, 0)) + 1
		for t in range(1, tiers.size() + 1):
			if not tiers.has(t):
				errors.append("lab branch %s skips tier %d" % [b.id, t])
		for f in forks:
			if int(forks[f]) != 2:
				errors.append("lab fork %s needs exactly 2 nodes" % f)
	for id in d.lab.get("abilities", {}):
		var ab: Dictionary = d.lab.abilities[id]
		if Lab.ability_node(d.lab, id).is_empty():
			errors.append("ability %s has no Lab node that unlocks it" % id)
		for row in ab.levels:
			if float(row.get("duration_s", 0)) <= 0.0 or float(row.get("kills", 0)) <= 0.0:
				errors.append("ability %s levels need duration_s and kills > 0" % id)
	if d.lab.genes.first_clear.size() != Profile.MAX_VIRULENCE:
		errors.append("lab.genes.first_clear needs one entry per Virulence level")


## Cosmetics (data/cosmetics.json): unique ids, known categories and unlock
## types, a free default per category, gold costs > 0, stat goals > 0.
static func _validate_cosmetics(d: Dictionary, errors: Array) -> void:
	var cfg: Dictionary = d.get("cosmetics", {})
	if cfg.is_empty():
		return
	var cats := {}
	for c in cfg.get("categories", []):
		cats[c.id] = true
	var ids := {}
	for it in cfg.get("items", []):
		if ids.has(it.id):
			errors.append("cosmetic %s is duplicated" % it.id)
		ids[it.id] = true
		if not cats.has(it.get("cat", "")):
			errors.append("cosmetic %s has unknown category '%s'" % [it.id, it.get("cat", "")])
		var u: Dictionary = it.get("unlock", {})
		match str(u.get("type", "")):
			"free":
				pass
			"gold":
				if int(u.get("cost", 0)) <= 0:
					errors.append("cosmetic %s needs a gold cost > 0" % it.id)
			"challenge", "prestige":
				if str(u.get("stat", "")) == "" or float(u.get("goal", 0)) <= 0.0 or str(u.get("text", "")) == "":
					errors.append("cosmetic %s needs stat, goal > 0 and text" % it.id)
			_:
				errors.append("cosmetic %s has unknown unlock type '%s'" % [it.id, u.get("type", "")])
	for c in cats:
		var def := Cosmetics.find(cfg, str(cfg.get("defaults", {}).get(c, "")))
		if def.is_empty() or def.cat != c or Cosmetics.unlock_type(def) != "free":
			errors.append("cosmetics: category %s needs a free default item" % c)
