class_name Cosmetics
extends RefCounted
## Cosmetics rules (pure logic, data/cosmetics.json): what is unlocked, what
## is equipped, and the resolved look a run is drawn with. Visual only: no
## cosmetic ever changes a stat, so World and the balance sims never see them.
##
## Unlocks: "free"; "gold" (bought, kept in Profile.cosmetics); "challenge"
## and "prestige" (a Profile.flat() stat reaching `goal`, so past play counts
## and nothing extra is saved). The developer toggle
## settings.dev_all_cosmetics unlocks everything without changing the save;
## turning it off puts back whatever you really own.

const WEAPONS := ["bolt", "orbit", "nova", "chain"]


static func items(cfg: Dictionary, cat: String = "") -> Array:
	var out := []
	for it in cfg.get("items", []):
		if cat == "" or it.cat == cat:
			out.append(it)
	return out


static func find(cfg: Dictionary, id: String) -> Dictionary:
	for it in cfg.get("items", []):
		if it.id == id:
			return it
	return {}


static func unlock_type(item: Dictionary) -> String:
	return str(item.get("unlock", {}).get("type", "free"))


static func cost(item: Dictionary) -> int:
	return int(item.get("unlock", {}).get("cost", 0)) if unlock_type(item) == "gold" else 0


## Unlocked by its own rule (ignores the developer toggle). `flat` is
## Profile.flat(); pass it in when checking many items at once.
static func earned(item: Dictionary, p: Profile, flat: Dictionary = {}) -> bool:
	match unlock_type(item):
		"free":
			return true
		"gold":
			return p.cosmetics.has(str(item.id))
		"challenge", "prestige":
			if flat.is_empty():
				flat = p.flat()
			return float(flat.get(str(item.unlock.stat), 0)) >= float(item.unlock.goal)
	return false


static func is_unlocked(item: Dictionary, p: Profile, flat: Dictionary = {}) -> bool:
	return p.dev_all_cosmetics() or earned(item, p, flat)


## 0..1 towards a challenge or prestige goal (1 for anything else unlocked).
static func progress(item: Dictionary, p: Profile, flat: Dictionary = {}) -> float:
	if not item.get("unlock", {}).has("stat"):
		return 1.0 if earned(item, p, flat) else 0.0
	if flat.is_empty():
		flat = p.flat()
	return clampf(float(flat.get(str(item.unlock.stat), 0)) / maxf(float(item.unlock.goal), 0.0001), 0.0, 1.0)


## "1,234 / 5,000" for a challenge (current value capped at the goal).
static func progress_text(item: Dictionary, p: Profile, flat: Dictionary = {}) -> String:
	if not item.get("unlock", {}).has("stat"):
		return ""
	if flat.is_empty():
		flat = p.flat()
	var goal := int(item.unlock.goal)
	return "%s / %s" % [_thousands(mini(int(flat.get(str(item.unlock.stat), 0)), goal)), _thousands(goal)]


## What to do to unlock it, in words.
static func unlock_text(item: Dictionary) -> String:
	match unlock_type(item):
		"free":
			return "Free"
		"gold":
			return "%s gold" % _thousands(cost(item))
	return str(item.get("unlock", {}).get("text", ""))


## The equipped item id for a category: settings.cosmetics[cat] if it is
## still unlocked, else the category default.
static func equipped(cfg: Dictionary, p: Profile, cat: String) -> String:
	var sel: Variant = p.settings.get("cosmetics", {})
	var id := str(sel.get(cat, "")) if sel is Dictionary else ""
	var it := find(cfg, id)
	if not it.is_empty() and it.cat == cat and is_unlocked(it, p):
		return id
	return str(cfg.get("defaults", {}).get(cat, ""))


## Equips an unlocked item. Returns false (and changes nothing) if locked.
static func equip(cfg: Dictionary, p: Profile, id: String) -> bool:
	var it := find(cfg, id)
	if it.is_empty() or not is_unlocked(it, p):
		return false
	if not (p.settings.get("cosmetics", null) is Dictionary):
		p.settings["cosmetics"] = {}
	p.settings.cosmetics[str(it.cat)] = id
	return true


## Buys a gold item. Returns the gold spent (0 = not bought: not a gold
## item, already owned, or too poor).
static func buy(cfg: Dictionary, p: Profile, id: String, now: int) -> int:
	var it := find(cfg, id)
	if it.is_empty() or unlock_type(it) != "gold" or p.cosmetics.has(id):
		return 0
	var c := cost(it)
	if p.gold < c:
		return 0
	p.gold -= c
	p.cosmetics[id] = now
	p.updated_at = now
	return c


## The free pick that comes with the Style unlock (Onboarding.free_pick):
## any gold item up to `max_cost`, owned without paying. Returns true if
## granted (and uses up the pick).
static func take_free(cfg: Dictionary, p: Profile, id: String, max_cost: int, now: int) -> bool:
	var it := find(cfg, id)
	if it.is_empty() or unlock_type(it) != "gold" or p.cosmetics.has(id) or cost(it) > max_cost or not Onboarding.free_pick(p):
		return false
	p.cosmetics[id] = now
	p.onboarding["free_pick"] = false
	p.updated_at = now
	return true


## Ids of every item earned (own rule; the developer toggle doesn't count).
static func earned_ids(cfg: Dictionary, p: Profile) -> Array:
	var f := p.flat()
	var out := []
	for it in cfg.get("items", []):
		if earned(it, p, f):
			out.append(str(it.id))
	return out


## Items earned in `after` that weren't in `before` (e.g. around a run).
static func newly_earned(cfg: Dictionary, before: Array, after: Array) -> Array:
	var out := []
	for id in after:
		if not before.has(id):
			out.append(find(cfg, id))
	return out


## The look a run (or the preview) is drawn with: {skin, weapon, pop}, each
## the equipped item's `look` dictionary. `override` ({cat: id}) previews
## an item without equipping it.
static func look(cfg: Dictionary, p: Profile, override: Dictionary = {}) -> Dictionary:
	var out := {}
	for c in cfg.get("categories", []):
		var id := str(override.get(c.id, equipped(cfg, p, c.id)))
		out[c.id] = find(cfg, id).get("look", {})
	return out


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
