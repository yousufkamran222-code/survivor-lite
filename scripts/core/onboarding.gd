class_name Onboarding
extends RefCounted
## New-player start rules (data/onboarding.json, pure logic): whether the
## prologue has been played, what the menu has unlocked (modes, tiles,
## Virulence), which unlocks still need their "NEW!" announcement, which mode
## coaches are due, the prologue's rotating showcase, score and medal, and
## when ad prompts may start. State lives in Profile.onboarding.
##
## Unlocks come from lifetime stats (real runs, wins, Genes), so they can't
## be lost; Profile.onboarding only remembers what was announced/coached.
## Saves from before v8 that had played get `all` (everything open).


static func _ob(p: Profile) -> Dictionary:
	return p.onboarding


static func prologue_done(p: Profile) -> bool:
	return bool(_ob(p).get("prologue_done", false))


## Times the prologue was finished (rotates the showcase and the elite).
static func prologue_runs(p: Profile) -> int:
	return int(p.record("prologue").get("runs", 0))


## Options for World.start_tutorial: replay n shows the n-th showcase weapon
## (first time: Pulse Bolt → Cytotoxic Storm) and the n-th elite affix.
static func prologue_opts(d: Dictionary, p: Profile) -> Dictionary:
	var pc: Dictionary = d.onboarding.prologue
	var n := prologue_runs(p)
	var shows: Array = pc.get("showcases", ["bolt"])
	var affs: Array = pc.get("affixes", ["charge"])
	var w := str(shows[n % shows.size()])
	var partner := "multishot"
	for ev in d.evolutions:
		if ev.weapon == w:
			partner = str(ev.requires)
	return {"showcase": w, "partner": partner, "affix": str(affs[n % affs.size()]), "elite_type": str(pc.get("elite_type", "grunt"))}


## Prologue score: kills + peak streak + a bonus for a quick boss kill.
static func prologue_score(pc: Dictionary, kills: int, best_streak: int, boss_s: float) -> int:
	var k: Dictionary = pc.get("score", {})
	var v := kills * float(k.get("per_kill", 1)) + best_streak * float(k.get("per_streak", 3))
	if boss_s > 0.0:
		v += maxf(0.0, float(k.get("boss_par_s", 40)) - boss_s) * float(k.get("per_boss_s", 15))
	return int(v)


## The best medal a score earns ({} = none).
static func medal(pc: Dictionary, score: int) -> Dictionary:
	var best := {}
	for m in pc.get("medals", []):
		if score >= int(m.score):
			best = m
	return best


## Saves a finished prologue: its own record (runs, best score, best kills)
## that never counts as a real run, win or mode won. Returns true if the
## score is a new best.
static func record_prologue(p: Profile, score: int, kills: int, now: int) -> bool:
	var r := p._record("prologue")
	var best := score > int(r.get("best_score", 0))
	r.runs = int(r.get("runs", 0)) + 1
	r.best_score = maxi(int(r.get("best_score", 0)), score)
	r.best_kills = maxi(int(r.get("best_kills", 0)), kills)
	_ob(p)["prologue_done"] = true
	p.updated_at = now
	return best


# ------------------------------------------------------------- unlocks

static func entry(d: Dictionary, id: String) -> Dictionary:
	for u in d.onboarding.get("unlocks", []):
		if u.id == id:
			return u
	return {}


## Whether a mode / tile / feature is open. Anything without a rule is open.
static func unlocked(d: Dictionary, p: Profile, id: String) -> bool:
	var u := entry(d, id)
	if u.is_empty() or bool(_ob(p).get("all", false)):
		return true
	if not prologue_done(p):
		return false
	var runs := int(p.stats.runs)
	var wins := int(p.stats.wins)
	if u.has("runs") and runs >= int(u.runs):
		return true
	if u.has("or_wins") and wins >= int(u.or_wins):
		return true
	if u.has("wins") and wins >= int(u.wins):
		return true
	if u.has("genes") and int(p.stats.genes_earned) >= int(u.genes):
		return true
	return false


## How to open a locked mode / tile: "Play 2 more runs or win once to
## unlock" (the toast), or the short form for a locked card ("2 more runs
## or a win").
static func unlock_text(d: Dictionary, p: Profile, id: String, short: bool = false) -> String:
	var u := entry(d, id)
	var parts := []
	if u.has("runs"):
		var left := maxi(int(u.runs) - int(p.stats.runs), 0)
		parts.append(("%d more run%s" if short else "play %d more run%s") % [left, "" if left == 1 else "s"])
	if u.has("or_wins") or u.has("wins") or u.has("genes"):
		parts.append("a win" if short and not parts.is_empty() else ("Win a run" if short else "win a run" + (" (it earns Genes)" if u.has("genes") else "")))
	if parts.is_empty():
		return ""
	if short:
		return " or ".join(parts)
	var t := " or ".join(parts) + " to unlock"
	return t.left(1).to_upper() + t.substr(1)


## Unlocked entries the player hasn't been shown yet (in data order).
static func pending_announcements(d: Dictionary, p: Profile) -> Array:
	var out := []
	if not prologue_done(p) or bool(_ob(p).get("all", false)):
		return out  # veterans had everything before it existed: nothing to announce
	var seen: Dictionary = _ob(p).get("announced", {})
	for u in d.onboarding.get("unlocks", []):
		if not seen.has(u.id) and unlocked(d, p, u.id):
			out.append(u)
	return out


static func mark_announced(p: Profile, id: String) -> void:
	if not (_ob(p).get("announced", null) is Dictionary):
		_ob(p)["announced"] = {}
	_ob(p).announced[id] = true
	if id == "style":
		_ob(p)["free_pick"] = true  # the Style unlock comes with one free item


## A "NEW" badge until the player opens it once.
static func is_new(p: Profile, id: String) -> bool:
	return bool(_ob(p).get("announced", {}).get(id, false)) and not bool(_ob(p).get("opened", {}).get(id, false)) and not bool(_ob(p).get("all", false))


static func mark_opened(p: Profile, id: String) -> void:
	if not (_ob(p).get("opened", null) is Dictionary):
		_ob(p)["opened"] = {}
	_ob(p).opened[id] = true


# ------------------------------------------------------------ coaches, ads

## The first real run of a mode with a coach gets it, once.
static func coach_due(d: Dictionary, p: Profile, mode: String) -> bool:
	return d.onboarding.get("coaches", {}).has(mode) and not bool(_ob(p).get("coached", {}).get(mode, false)) and not bool(_ob(p).get("all", false))


static func mark_coached(p: Profile, mode: String) -> void:
	if not (_ob(p).get("coached", null) is Dictionary):
		_ob(p)["coached"] = {}
	_ob(p).coached[mode] = true


## No ad prompts (reroll, double gold, between-run ads) in the first runs.
static func ads_allowed(d: Dictionary, p: Profile) -> bool:
	return bool(_ob(p).get("all", false)) or int(p.stats.runs) >= int(d.onboarding.get("ads_from_runs", 0))


## The level-up card's build hint ("Dash build: ..."), shown in Patient Zero
## and a player's first `card_hint_runs` real runs ("" otherwise).
static func card_hint(d: Dictionary, p: Profile, id: String, prologue: bool) -> String:
	var ob: Dictionary = d.get("onboarding", {})
	if not prologue and (bool(_ob(p).get("all", false)) or int(p.stats.runs) >= int(ob.get("card_hint_runs", 0))):
		return ""
	return str(ob.get("card_hints", {}).get(id, ""))


static func free_pick(p: Profile) -> bool:
	return bool(_ob(p).get("free_pick", false))


## Developer tool: forget the tutorial flags so the next launch starts with
## the prologue and coaches again (unlocks still follow your stats).
static func reset(p: Profile) -> void:
	p.onboarding = {}
