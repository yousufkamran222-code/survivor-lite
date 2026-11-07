class_name Tutorial
extends RefCounted
## Scripted beats inside a real run (data/onboarding.json): the Patient Zero
## prologue and the first-run coaches of each mode. Pure logic owned by the
## World (World.start_tutorial): each beat runs its start actions, an optional
## repeating spawn, shows a prompt, and waits for one condition (counted from
## the beat's start) or max_s. Gameplay effects (spawns, fixed offers, XP
## boosts, a full Outbreak meter, the boss, the finale) happen here; Main and
## the HUD only read `prompt` (text, target, slowmo) to present it.

## Conditions read as an absolute value instead of "since the beat started".
const ABSOLUTE := ["on_pad", "streak", "time"]

var beats: Array = []
var showcase := "bolt"  # the weapon this prologue evolves (rotates on replays)
var partner := "multishot"  # its evolution partner
var affix := "charge"  # the prologue elite's affix
var elite_type := "grunt"
var index := -1  # current beat
var t := 0.0  # time in the current beat
var done := false
var prompt := {}  # {id, text, target, slowmo}; empty = nothing to show
var boss_t0 := -1.0  # run time the boss appeared
var boss_s := 0.0  # seconds the boss took to kill (prologue score)
var _base := {}
var _rep_t := 0.0
var _moved := 0.0
var _last := Vector2.INF


func _init(beat_list: Array, opts: Dictionary = {}) -> void:
	beats = beat_list
	showcase = str(opts.get("showcase", showcase))
	partner = str(opts.get("partner", partner))
	affix = str(opts.get("affix", affix))
	elite_type = str(opts.get("elite_type", elite_type))


func beat() -> Dictionary:
	return beats[index] if index >= 0 and index < beats.size() else {}


## One step (World.step calls it while playing).
func update(w: World, dt: float) -> void:
	if done:
		return
	if _last != Vector2.INF:
		_moved += w.p_pos.distance_to(_last)
	_last = w.p_pos
	if index < 0:
		_start(w, 0)
		if done:
			return
	t += dt
	var b := beat()
	if w.boss_killed and boss_t0 >= 0.0 and boss_s <= 0.0:
		boss_s = w.time - boss_t0
	var rep: Dictionary = b.get("repeat", {})
	if not rep.is_empty():
		_rep_t += dt
		if _rep_t >= float(rep.every_s):
			_rep_t = 0.0
			_spawn(w, rep.get("spawn", []))
	var met := _met(w, b)
	var timeout := t >= float(b.get("max_s", INF))
	if (met and t >= float(b.get("min_s", 0.0))) or timeout:
		_finish(w, b)
		_start(w, index + 1)
		return
	# Text fades after show_s (if set); slow motion only while waiting.
	prompt.text = str(b.get("text", "")) if t < float(b.get("show_s", INF)) else ""
	prompt.slowmo = bool(b.get("slowmo", false)) and not met


## The run should crawl right now (a beat waits for the player to act).
func slowmo() -> bool:
	return not done and bool(prompt.get("slowmo", false))


func counters(w: World) -> Dictionary:
	return {
		"moved": _moved, "kills": w.kills, "picks": w.picks, "dashes": w.dashes, "chests": w.chests_opened,
		"evolved": w.evolved.size(), "streak": w.streak, "outbreaks": w.outbreaks, "boss_killed": 1 if w.boss_killed else 0,
		"claims": w.claims, "conversions": w.conversions, "orders": w.order_changes,
		"on_pad": 1 if w.def_on and w.empty_pad_under_player() >= 0 else 0, "towers": w.towers_built, "time": t,
	}


func _met(w: World, b: Dictionary) -> bool:
	var until: Dictionary = b.get("until", {})
	if until.is_empty():
		return false
	var c := counters(w)
	for k in until:
		var v := float(c.get(k, 0.0))
		if not ABSOLUTE.has(k):
			v -= float(_base.get(k, 0.0))
		if v < float(until[k]):
			return false
	return true


func _start(w: World, k: int) -> void:
	index = k
	t = 0.0
	_rep_t = 0.0
	if k >= beats.size():
		done = true
		prompt = {}
		w.director.script_mult = 1.0
		return
	var b := beat()
	_base = counters(w)
	var s: Dictionary = b.get("start", {})
	if s.has("ambient"):
		w.director.script_mult = float(s.ambient)
	if s.has("xp_mult"):
		w.tut_xp_mult = float(s.xp_mult)
	if s.has("offers"):
		w.forced_offers = []
		for row in s.offers:
			w.forced_offers.append(_resolve(row))
	_spawn(w, s.get("spawn", []))
	if s.has("grant_levels"):
		while w.pending_levelups < int(s.grant_levels):
			w.grant_level()
	if s.get("elite", false):
		w._add_enemy(elite_type, w._valid_spawn(_ahead(w, float(s.get("elite_dist", 480.0)))), true)
		var last := w.e_pos.size() - 1
		var a := World.AFFIX_IDS.find(affix)
		if a > 0:
			w.e_affix[last] = a
		if float(s.get("elite_life_s", 0.0)) > 0.0:  # a tutorial elite: a short, readable fight
			var hp := maxf(30.0, w.player_dps_estimate() * float(s.elite_life_s))
			w.e_hp[last] = hp
			w.e_maxhp[last] = hp
		w._emit({"type": "elite_spawn", "id": elite_type, "affix": affix})
	if s.get("boss", false):
		w._add_enemy("boss", w._valid_spawn(_ahead(w, 520.0)))
		boss_t0 = w.time
		w._emit({"type": "boss_spawn"})
	if s.get("outbreak_full", false) and w.bal.get("outbreak", {}).get("enabled", false):
		w.outbreak = 1.0
		w._emit({"type": "outbreak_ready"})
	if s.get("clear", false):
		for i in w.e_pos.size():
			if w.e_team[i] == 0:
				w._damage(i, 1.0e6, Vector2.ZERO, false)
		w._process_dead()
	prompt = {"id": str(b.id), "index": k, "text": str(b.get("text", "")), "target": str(b.get("target", "none")), "slowmo": bool(b.get("slowmo", false))}
	w._emit({"type": "coach", "id": str(b.id), "text": prompt.text, "target": prompt.target})


func _finish(w: World, b: Dictionary) -> void:
	var d: Dictionary = b.get("done", {})
	if d.get("bomb", false):
		w._apply_pickup("bomb", w.p_pos)
	if d.get("win", false):
		w.state = "won"
		w._emit({"type": "victory"})


## Offer tokens: "showcase" / "partner" become this prologue's weapon and its
## evolution partner; duplicates are swapped for another starter card.
func _resolve(row: Array) -> Array:
	var out := []
	var spare := ["orbit", "nova", "chain", "might", "swift", "haste"]
	for id in row:
		var real := showcase if id == "showcase" else (partner if id == "partner" else str(id))
		if out.has(real):
			for s in spare:
				if not out.has(s) and not row.has(s):
					real = s
					break
		out.append(real)
	return out


func _ahead(w: World, dist: float) -> Vector2:
	var dir := w.p_move.normalized() if w.p_move.length_squared() > 0.01 else w.p_facing.normalized()
	return w.p_pos + dir * dist


func _spawn(w: World, list: Array) -> void:
	for sp in list:
		var n := int(sp.get("n", 1))
		var dist := float(sp.get("dist", 420.0))
		match str(sp.get("pattern", "cluster")):
			"front":
				var dir := (_ahead(w, 1.0) - w.p_pos).normalized()
				var perp := dir.orthogonal()
				for k in n:
					w._add_enemy(sp.id, w._valid_spawn(w.p_pos + dir * dist + perp * (k - (n - 1) / 2.0) * 46.0))
			"ring":
				var a0 := w.rng.randf() * TAU
				for k in n:
					var a := a0 + TAU * k / n
					w._add_enemy(sp.id, w._valid_spawn(w.p_pos + Vector2(cos(a), sin(a)) * dist))
			_:
				var a := w.rng.randf() * TAU
				var c := w.p_pos + Vector2(cos(a), sin(a)) * dist
				for k in n:
					w._add_enemy(sp.id, w._valid_spawn(c + Vector2(w.rng.randf_range(-40, 40), w.rng.randf_range(-40, 40))))
