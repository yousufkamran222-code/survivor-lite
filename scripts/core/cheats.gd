class_name Cheats
extends RefCounted
## TEMPORARY playtest cheats (Yousuf, 2026-11-28: "so I can test everything
## quickly"). Only reachable when balance.crazygames.cheats is true on the
## CrazyGames build (Main.cheats_on, CheatMenu). Turn that flag off to remove
## the menu; the World hooks (cheat_god / cheat_dmg / cheat_no_spawn) then stay
## at their defaults and change nothing. Pure logic, no Nodes.

## Session toggles, copied onto every new World (Main._start_run).
static var god := false
static var dmg := 1.0  # 1, 10 or 1e6 (one-hit kills)
static var no_spawn := false
static var speed := 1.0  # game speed (Main scales/steps the World by it)
static var xp := 1.0  # x XP from gems


static func apply_flags(w: World) -> void:
	w.cheat_god = god
	w.cheat_dmg = dmg
	w.cheat_no_spawn = no_spawn
	if w.tut == null:
		w.tut_xp_mult = xp


# ------------------------------------------------------------- in-run

static func levels(w: World, n: int) -> void:
	for k in n:
		w.grant_level()


## Every weapon and passive you own jumps to its max level.
static func max_owned(w: World) -> void:
	for id in w.owned.keys():
		var def: Dictionary = w.upgrade_defs[id]
		while int(w.owned.get(id, 0)) < Upgrades.max_level(def):
			w._apply_level(id)


## The weapon (added if missing) goes to max, its partner passive is added,
## and it evolves right away.
static func evolve(w: World, weapon: String) -> void:
	if not w.evolution_defs.has(weapon) or w.evolved.has(weapon):
		return
	var ev: Dictionary = w.evolution_defs[weapon]
	while int(w.owned.get(weapon, 0)) < Upgrades.max_level(w.upgrade_defs[weapon]):
		w._apply_level(weapon)
	if not w.owned.has(str(ev.requires)):
		w._apply_level(str(ev.requires))
	w.evolved[weapon] = ev.id
	w._evo_announced[weapon] = true
	w._recompute_stats()
	w._emit({"type": "evolution", "id": ev.id, "weapon": weapon})


static func evolve_all(w: World) -> void:
	for weapon in w.evolution_defs.keys():
		evolve(w, weapon)


## Adds one level of an upgrade (a weapon you don't own counts as new).
static func add_upgrade(w: World, id: String) -> void:
	if w.upgrade_defs.has(id) and int(w.owned.get(id, 0)) < Upgrades.max_level(w.upgrade_defs[id]):
		w._apply_level(id)


static func heal(w: World) -> void:
	w.p_hp = w.p_max_hp
	if w.def_on:
		w.core_hp = w.core_max


static func fill_meters(w: World) -> void:
	w.outbreak = 1.0
	w.ab_kills = maxf(w.ab_kills, w.ability_cost()) if w.ability != "" else w.ab_kills
	w.p_dash_charges = w.dash_max_charges()
	w.p_dash_cd = 0.0


static func kill_all(w: World) -> void:
	for i in w.e_pos.size():
		if w.e_team[i] == 0:
			w._damage(i, 1.0e7, Vector2.ZERO, false)
	w.s_pos.clear(); w.s_vel.clear(); w.s_life.clear(); w.s_dmg.clear()
	w._process_dead()


static func collect_gems(w: World) -> void:
	w._apply_pickup("vacuum", w.p_pos, false)


static func chest(w: World, items: int = 3) -> void:
	w._drop_chest(w.p_pos + w.p_facing * 90.0, items)


static func pickup(w: World, kind: String) -> void:
	var k := World.PICKUP_KINDS.find(kind)
	if k >= 0:
		w.i_pos.append(w.p_pos + w.p_facing.rotated(0.6) * 110.0)
		w.i_kind.append(k)


## A germ type near you (`elite` with a forced affix, "" = random).
static func spawn(w: World, id: String, count: int = 1, elite: bool = false, affix: String = "") -> void:
	if not w.enemy_idx.has(id):
		return
	for k in count:
		var a := TAU * k / maxf(count, 1) + w.rng.randf() * 0.3
		w._add_enemy(id, w._valid_spawn(w.p_pos + Vector2.from_angle(a) * 380.0), elite)
		var i := w.e_pos.size() - 1
		if elite and affix != "":
			w.e_affix[i] = World.AFFIX_IDS.find(affix)
		if elite:
			w._emit({"type": "elite_spawn", "id": id, "affix": w.affix_id(i)})
		elif w.enemy_defs[w.e_type[i]].behavior == "boss":
			w._emit({"type": "boss_spawn"})


## Jumps the run clock forward. Skipped scripted spawns are dropped (the
## Mother Cell is kept, so jumping past it still brings her), and the elite
## timer restarts, so a jump never dumps every missed spawn at once.
static func skip_time(w: World, secs: float) -> void:
	if w.def_on:
		return
	var to := minf(w.time + secs, w.run_length - 1.0)
	var evs: Array = w.data.waves.get("events", [])
	for i in evs.size():
		if float(evs[i].t) <= to and str(evs[i].enemy) != "boss":
			w.director._done_events[i] = true
	w.time = to
	w.director._next_elite_t = to + 3.0


static func set_time(w: World, t: float) -> void:
	if t > w.time:
		skip_time(w, t - w.time)


## Starts a Symptom now (its warning first), even below Virulence 5.
static func symptom(w: World, id: String) -> void:
	var sc: Dictionary = w.bal.get("symptoms", {})
	if w.sym_state != 0:
		w._end_symptom()
	for e in sc.get("events", []):
		if str(e.id) != id:
			continue
		w.sym_on = true
		w._sym = e
		w.sym_id = id
		w.sym_state = 1
		w.sym_t = float(sc.get("warn_s", 2.5))
		if id == "antibiotics":
			w.beam_dir = Vector2.from_angle(w.rng.randf() * TAU)
			w.beam_w = float(e.width)
			w.beam_pos = w.p_pos - w.beam_dir * (float(e.speed) * float(e.s) / 2.0)
		w._emit({"type": "symptom_warn", "id": id, "name": str(e.name), "desc": str(e.get("desc", ""))})
		return


## Nucleus: biomass for towers.
static func biomass(w: World, amount: float) -> void:
	w.biomass += amount


## Nucleus: ends the current wave's spawning and clears the dish.
static func skip_wave(w: World) -> void:
	if not w.def_on:
		return
	if w.wave_state == "breather":
		w.wave_t = 0.01
		return
	w.director._wave_left = 0.0
	w.director.budget = 0.0
	w.director._next_pick = {}
	kill_all(w)
	w.wave_state = "fighting"


static func win(w: World) -> void:
	if w.def_on:
		w.wave = w.wave_count
		w.state = "defense_won"
	else:
		w.state = "won"
	w._emit({"type": "victory"})


static func die(w: World) -> void:
	w.p_hp = 0.0
	w.death_cause = "cheat"
	w.state = "dead"


# ------------------------------------------------------------- profile

static func max_shop(p: Profile, meta: Array, now: int) -> void:
	for d in meta:
		p.meta_levels[d.id] = d.costs.size()
	p.updated_at = now


## Every mode and menu tile open, no coaches (Onboarding "all").
static func unlock_menus(p: Profile) -> void:
	p.onboarding["prologue_done"] = true
	p.onboarding["all"] = true
