class_name GameData
extends RefCounted
## Loads the JSON tables in res://data and validates cross-references.
## Every tunable number lives in data/, never in code.

const FILES := ["balance", "enemies", "upgrades", "waves", "meta"]


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
	return errors
