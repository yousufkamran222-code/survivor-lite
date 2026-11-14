class_name Missions
extends RefCounted
## Daily missions (data/missions.json). Pure rules, no Nodes.
##
## Each day gets one mission per tier, picked from the pool with a seed made
## from the date (so everyone sees the same three that day). The day's
## missions and progress live in Profile.settings["missions"] (free-form
## settings: no save-format change), as
##   {"day": "2026-11-15", "ids": [...], "progress": {id: n}, "done": [ids], "bonus": bool}
## The ids are fixed the first time a day is opened, so unlocking a mode
## mid-day doesn't reshuffle them. Runs report through record_run(); gold is
## paid at once when a mission completes (and all_bonus for the third).


## The pool entries open to this player (missions needing a locked mode are skipped).
static func pool(cfg: Dictionary, open_modes: Array) -> Array:
	var out := []
	for m in cfg.get("pool", []):
		if m.has("requires") and not open_modes.has(str(m.requires)):
			continue
		out.append(m)
	return out


## The day's mission ids: one per tier (1, 2, 3...), chosen by the date.
static func pick(cfg: Dictionary, day: String, open_modes: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("missions:" + day)
	var by_tier := {}
	for m in pool(cfg, open_modes):
		var t := int(m.get("tier", 1))
		if not by_tier.has(t):
			by_tier[t] = []
		by_tier[t].append(m)
	var tiers := by_tier.keys()
	tiers.sort()
	var ids := []
	for t in tiers:
		var list: Array = by_tier[t]
		ids.append(str(list[rng.randi_range(0, list.size() - 1)].id))
		if ids.size() >= int(cfg.get("per_day", 3)):
			break
	return ids


static func find(cfg: Dictionary, id: String) -> Dictionary:
	for m in cfg.get("pool", []):
		if str(m.id) == id:
			return m
	return {}


## Today's state, created (and stored in settings) on first use of the day.
static func today(p: Profile, cfg: Dictionary, day: String, open_modes: Array) -> Dictionary:
	var st: Variant = p.settings.get("missions", {})
	if not (st is Dictionary) or str(st.get("day", "")) != day:
		st = {"day": day, "ids": pick(cfg, day, open_modes), "progress": {}, "done": [], "bonus": false}
		p.settings["missions"] = st
	return st


## Progress toward one mission (clamped to its goal).
static func progress(st: Dictionary, m: Dictionary) -> int:
	return mini(int(st.get("progress", {}).get(str(m.id), 0)), int(m.n))


static func is_done(st: Dictionary, id: String) -> bool:
	return st.get("done", []).has(id)


## How much one run adds to a stat (won / boss_killed count as 1, the
## evolved list as its size, a run as 1).
static func run_value(s: Dictionary, stat: String) -> int:
	match stat:
		"runs":
			return 1
		"won", "boss_killed":
			return 1 if bool(s.get(stat, false)) else 0
		"evolutions":
			return s.get("evolved_ids", []).size()
	return int(s.get(stat, 0))


## Applies a finished run. Returns the missions it completed, each as
## {id, text, reward}, plus a {"id": "all", ...} entry when the day is done;
## their gold is already paid into the profile.
static func record_run(p: Profile, cfg: Dictionary, s: Dictionary, day: String, open_modes: Array, now: int) -> Array:
	var st := today(p, cfg, day, open_modes)
	var prog: Dictionary = st.progress
	var done: Array = st.done
	var out := []
	for id in st.ids:
		var m := find(cfg, str(id))
		if m.is_empty() or done.has(id):
			continue
		var v := run_value(s, str(m.stat))
		if str(m.get("agg", "sum")) == "best":
			prog[id] = maxi(int(prog.get(id, 0)), v)
		else:
			prog[id] = int(prog.get(id, 0)) + v
		if int(prog[id]) >= int(m.n):
			done.append(id)
			p.add_gold(int(m.reward), now)
			out.append({"id": id, "text": text(m), "reward": int(m.reward)})
	if not bool(st.get("bonus", false)) and done.size() >= st.ids.size() and not st.ids.is_empty():
		st.bonus = true
		var b := int(cfg.get("all_bonus", 0))
		if b > 0:
			p.add_gold(b, now)
			out.append({"id": "all", "text": "All daily missions", "reward": b})
	return out


## "Kill 300 germs" (the goal number goes into %d).
static func text(m: Dictionary) -> String:
	var t := str(m.get("text", m.id))
	return t % int(m.n) if t.contains("%d") else t


## Missions done today / per day.
static func done_count(st: Dictionary) -> int:
	return st.get("done", []).size()
