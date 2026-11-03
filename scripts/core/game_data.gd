class_name GameData
extends RefCounted
## Loads the JSON tables in res://data and validates cross-references.
## Every tunable number lives in data/, never in code.

const FILES := ["balance", "enemies", "upgrades", "waves", "meta", "evolutions", "modes", "online", "towers", "hints"]


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
