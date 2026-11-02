class_name GameData
extends RefCounted
## Loads the JSON tables in res://data and validates cross-references.
## Every tunable number lives in data/, never in code.

const FILES := ["balance", "enemies", "upgrades", "waves", "meta", "evolutions", "modes"]


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
	if d.waves.has("elites"):
		for t in d.waves.elites.types:
			if not enemy_ids.has(t):
				errors.append("waves.elites references unknown enemy '%s'" % t)
			elif float(enemy_ids[t].radius) * float(d.waves.elites.radius_mult) > float(d.balance.perf.max_enemy_radius):
				errors.append("elite %s radius exceeds perf.max_enemy_radius" % t)
	return errors
