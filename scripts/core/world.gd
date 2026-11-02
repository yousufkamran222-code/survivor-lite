class_name World
extends RefCounted
## Pure simulation of one run: player, enemies, weapons, pickups, levelling.
## No nodes and no rendering. The game view reads this state each frame; tests
## and the balance bot drive it headlessly. Deterministic for a given seed.
##
## Enemies, bullets and gems are stored as parallel packed arrays (struct of
## arrays) and removed with swap-remove, which keeps per-frame cost low on weak
## phones.

const CELL := 64.0

var data: Dictionary
var bal: Dictionary
var rng := RandomNumberGenerator.new()
var director: SpawnDirector
var upgrade_list: Array = []
var upgrade_defs: Dictionary = {}  # id -> def
var enemy_defs: Array = []  # type index -> def
var enemy_idx: Dictionary = {}  # id -> type index
var _tbeh := PackedInt32Array()  # type index -> BEH_*
const BEH_CHASE := 0
const BEH_RANGED := 1
const BEH_DASH := 2
const BEH_BOSS := 3
const BEHAVIORS := {"chase": BEH_CHASE, "ranged": BEH_RANGED, "dash": BEH_DASH, "boss": BEH_BOSS}
var _frame := 0
const SEP_EVERY := 3  # separation cadence (frames); see _update_enemies

## Set false in headless sims to skip building event dictionaries.
var emit_events := true
var events: Array = []

var time := 0.0
var run_length := 300.0
var state := "playing"  # playing | levelup | chest | dead | won

# --- Player ---
var p_pos := Vector2.ZERO
var p_radius := 18.0
var p_hp := 100.0
var p_max_hp := 100.0
var p_iframes := 0.0
var p_facing := Vector2.RIGHT
var level := 1
var xp := 0.0
var xp_next := 5.0
var kills := 0
var pending_levelups := 0
var offers: Array = []
var owned: Dictionary = {}  # upgrade id -> level
var stats: Dictionary = {}  # global stats (passives + meta)
var meta_bonus: Dictionary = {}
var revives_used := 0
var boss_killed := false
var boss_index := -1  # enemy index of a live boss, for the HUD bar
var death_cause := ""
var elites_killed := 0
var chests_opened := 0
var dashes := 0

# --- Dash ---
var p_move := Vector2.ZERO  # last movement input
var p_dash_t := 0.0  # time left in the current dash
var p_dash_cd := 0.0
var p_dash_dir := Vector2.RIGHT
var p_dash_charges := 1
var _dash_hits := {}  # enemy uids Lunge already hit during this dash
var decoy_pos := Vector2.ZERO  # Afterimage decoy (enemies nearby chase it)
var decoy_t := 0.0

# --- Evolutions ---
var evolution_defs := {}  # weapon id -> evolution def
var evolved := {}  # weapon id -> evolution id
var _evo_announced := {}
var _nova_echo := -1.0

# --- Chests (dropped by elites and the boss) ---
var c_pos := PackedVector2Array()
var c_items := PackedInt32Array()
var chest_rewards: Array = []  # [{kind, id, name, desc, level}] of the chest being opened

# --- Rare pickups ---
const PICKUP_KINDS := ["vacuum", "heal", "bomb"]
var i_pos := PackedVector2Array()
var i_kind := PackedInt32Array()

# --- Weapons ---
var wstats: Dictionary = {}  # weapon id -> final stats (after globals)
var cooldowns: Dictionary = {}
var orbit_angle := 0.0
var orbit_points := PackedVector2Array()
var orbit_size := 0.0

# --- Enemies (struct of arrays) ---
var e_type := PackedInt32Array()
var e_uid := PackedInt32Array()
var e_pos := PackedVector2Array()
var e_knock := PackedVector2Array()
var e_hp := PackedFloat32Array()
var e_maxhp := PackedFloat32Array()
var e_flash := PackedFloat32Array()
var e_timer := PackedFloat32Array()
var e_phase := PackedInt32Array()
var e_dir := PackedVector2Array()
var e_hitcd := PackedFloat32Array()
var e_rad := PackedFloat32Array()  # per enemy (elites are bigger)
var e_spd := PackedFloat32Array()
var e_elite := PackedByteArray()
var e_team := PackedByteArray()  # 0 = enemy, 1 = ally (converted, Swarm mode)
var e_life := PackedFloat32Array()  # ally lifetime left
var _next_uid := 1
var _dead := {}

# --- Player bullets ---
var b_pos := PackedVector2Array()
var b_vel := PackedVector2Array()
var b_dmg := PackedFloat32Array()
var b_pierce := PackedInt32Array()
var b_life := PackedFloat32Array()
var b_rad := PackedFloat32Array()
var b_knock := PackedFloat32Array()
var b_hits: Array = []

# --- Enemy shots ---
var s_pos := PackedVector2Array()
var s_vel := PackedVector2Array()
var s_life := PackedFloat32Array()
var s_dmg := PackedFloat32Array()

# --- XP gems ---
var g_pos := PackedVector2Array()
var g_val := PackedFloat32Array()
var g_pull := PackedByteArray()

var _grid := {}

# --- Territory (prototype 1; null when balance.territory.enabled is false) ---
var terr: Territory = null
var p_on_land := false
var _terr_tick := 0.0

# --- Conversion (prototype 2, Swarm mode; off unless balance.conversion.enabled) ---
var conv_on := false
var ally_count := 0
var swarm_power := 0.0  # grows each time a conversion "feeds" a full swarm
var _ally_slot := 0
var _ally_slots := 1
var _ally_snap := Vector2.INF
var conversions := 0
var _ally_tick := 0.0
var _max_er := 72.0


func _init(game_data: Dictionary, seed_value: int, meta: Dictionary = {}) -> void:
	data = game_data
	bal = data.balance
	rng.seed = seed_value
	meta_bonus = meta
	run_length = float(bal.run_length_s)
	_max_er = float(bal.perf.max_enemy_radius)
	for e in data.enemies:
		enemy_idx[e.id] = enemy_defs.size()
		enemy_defs.append(e)
		_tbeh.append(int(BEHAVIORS.get(e.behavior, BEH_CHASE)))
	var mode_id: String = str(bal.get("mode_id", ""))
	upgrade_list = []
	for u in data.upgrades:
		upgrade_defs[u.id] = u
		if not u.has("modes") or u.modes.has(mode_id):
			upgrade_list.append(u)
	conv_on = bal.has("conversion") and bal.conversion.get("enabled", false)
	for ev in data.get("evolutions", []):
		evolution_defs[ev.weapon] = ev
	var by_id := {}
	for e in enemy_defs:
		by_id[e.id] = e
	director = SpawnDirector.new(data.waves, by_id, rng)
	if bal.has("territory") and bal.territory.get("enabled", false):
		terr = Territory.new(bal.territory)
	p_radius = float(bal.player.radius)
	xp_next = Progression.xp_needed(bal, 1)
	owned[bal.start_weapon] = 1
	_recompute_stats()
	p_hp = p_max_hp
	p_dash_charges = dash_max_charges()  # permanent extra charges start full


# ===================================================================== API

func step(dt: float, move: Vector2) -> void:
	if state != "playing":
		return
	time += dt
	if time >= run_length:
		state = "won"
		_emit({"type": "victory"})
		return
	_update_player(dt, move)
	if terr != null:
		_update_territory(dt)
	_spawn(dt)
	_rebuild_grid()
	_update_enemies(dt)
	if ally_count > 0:
		_update_ally_combat(dt)
	_update_weapons(dt)
	_update_bullets(dt)
	_update_enemy_shots(dt)
	_process_dead()
	_contact_damage()
	_update_gems(dt)
	_update_pickups()
	if pending_levelups > 0 and state == "playing" and not _banking():
		_open_levelup()


func choose_upgrade(id: String) -> void:
	if state != "levelup" or not offers.has(id):
		return
	_apply_level(id)
	pending_levelups -= 1
	offers = []
	state = "playing"
	_emit({"type": "upgrade", "id": id, "level": owned[id]})
	if pending_levelups > 0:
		_open_levelup()


## Level-ups are banked (balance.upgrades.bank_levelups): they don't pause the
## game; the player opens the picker when it suits them.
func _banking() -> bool:
	return bool(bal.upgrades.get("bank_levelups", false))


## Opens the picker for a banked level-up. Returns true if it opened.
func open_banked() -> bool:
	if state != "playing" or pending_levelups <= 0:
		return false
	_open_levelup()
	return state == "levelup"


## Closes the picker keeping the remaining level-ups banked ("Later").
func close_levelup() -> void:
	if state == "levelup":
		offers = []
		state = "playing"


## Starts a dash if it is off cooldown. Returns true if it dashed.
func dash() -> bool:
	if state != "playing" or p_dash_charges <= 0:
		return false
	var pl: Dictionary = bal.player
	p_dash_dir = p_move.normalized() if p_move.length_squared() > 0.01 else p_facing
	p_dash_t = float(pl.dash_s)
	p_dash_charges -= 1
	if p_dash_cd <= 0.0:
		p_dash_cd = dash_cooldown()
	p_iframes = maxf(p_iframes, float(pl.dash_iframes_s))
	_dash_hits = {}
	dashes += 1
	if float(stats.get("dash_decoy", 0.0)) > 0.0:
		decoy_pos = p_pos
		decoy_t = float(pl.decoy_s)
		_emit({"type": "decoy", "pos": p_pos})
	_emit({"type": "dash", "pos": p_pos, "dir": p_dash_dir})
	return true


func can_dash() -> bool:
	return p_dash_charges > 0


func dash_max_charges() -> int:
	return 1 + int(stats.get("dash_charges", 0.0))


func dash_cooldown() -> float:
	return float(bal.player.dash_cooldown_s) * maxf(0.4, 1.0 - float(stats.get("dash_cd", 0.0)))


## Called when the chest reveal has been shown. Rewards were already applied.
func close_chest() -> void:
	if state != "chest":
		return
	chest_rewards = []
	state = "playing"
	if pending_levelups > 0 and not _banking():
		_open_levelup()


## Weapons that are maxed and have their paired passive, not yet evolved.
func ready_evolutions() -> Array:
	var out := []
	for wid in evolution_defs:
		var ev: Dictionary = evolution_defs[wid]
		if evolved.has(wid) or not owned.has(ev.requires):
			continue
		if int(owned.get(wid, 0)) >= Upgrades.max_level(upgrade_defs[wid]):
			out.append(wid)
	return out


func is_elite(i: int) -> bool:
	return e_elite[i] == 1


func reroll_offers() -> void:
	if state == "levelup":
		offers = _roll()


func revive() -> void:
	if state != "dead":
		return
	revives_used += 1
	p_hp = p_max_hp * float(bal.revive.hp_frac)
	p_iframes = float(bal.revive.iframes_s)
	state = "playing"
	var r := float(bal.revive.clear_radius)
	_rebuild_grid()
	for i: int in query(p_pos, r):
		if enemy_defs[e_type[i]].behavior == "boss":
			e_knock[i] += (e_pos[i] - p_pos).normalized() * 400.0
		else:
			_damage(i, 1.0e6, Vector2.ZERO, false)
	s_pos.clear(); s_vel.clear(); s_life.clear(); s_dmg.clear()
	_process_dead()
	_emit({"type": "nova", "pos": p_pos, "radius": r})
	_emit({"type": "revive"})


func next_level_of(id: String) -> int:
	return int(owned.get(id, 0)) + 1


func enemy_count() -> int:
	return e_pos.size()


## Hostile enemies only (excludes converted allies).
func hostile_count() -> int:
	return e_pos.size() - ally_count


func is_ally(i: int) -> bool:
	return e_team[i] == 1


func enemy_radius(i: int) -> float:
	return e_rad[i]


## Indices of enemies whose circle overlaps the circle (center, radius).
## team 0 = hostile enemies (default), 1 = allies.
func query(center: Vector2, radius: float, team: int = 0) -> Array:
	var out := []
	var r := radius + _max_er
	var x0 := floori((center.x - r) / CELL)
	var x1 := floori((center.x + r) / CELL)
	var y0 := floori((center.y - r) / CELL)
	var y1 := floori((center.y + r) / CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell: Variant = _grid.get(_key(cx, cy))
			if cell == null:
				continue
			for i: int in cell:
				if e_team[i] != team:
					continue
				var rr := radius + e_rad[i]
				if e_pos[i].distance_squared_to(center) <= rr * rr:
					out.append(i)
	return out


# ================================================================ internals

func _emit(ev: Dictionary) -> void:
	if emit_events:
		events.append(ev)


func _recompute_stats() -> void:
	stats = Upgrades.global_stats(upgrade_defs, owned, meta_bonus)
	p_max_hp = float(bal.player.max_hp) + float(stats.max_hp)
	wstats.clear()
	for id in owned:
		var def: Dictionary = upgrade_defs[id]
		if def.type != "weapon":
			continue
		var w := Upgrades.stats_at(def, owned[id])
		if evolved.has(id):
			var ev: Dictionary = evolution_defs[id]
			for k in ev.stats:
				w[k] = float(w.get(k, 0.0)) + float(ev.stats[k])
			for k in ["heal_on_hit", "pulses", "forks"]:
				if ev.has(k):
					w[k] = float(ev[k])
		var dmg_mult := 1.0 + float(stats.might)
		var cd_mult := maxf(0.35, 1.0 - float(stats.haste))
		if w.has("damage"):
			w.damage *= dmg_mult
		if w.has("cooldown"):
			w.cooldown = maxf(0.1, w.cooldown * cd_mult)
		if w.has("count"):
			w.count += float(stats.amount)
		if w.has("jumps"):
			w.jumps += float(stats.amount)
		wstats[id] = w
		if not cooldowns.has(id):
			cooldowns[id] = 0.5


func _update_player(dt: float, move: Vector2) -> void:
	var m := move.limit_length(1.0)
	p_move = m
	if p_dash_charges < dash_max_charges():
		p_dash_cd -= dt
		if p_dash_cd <= 0.0:
			p_dash_charges += 1
			p_dash_cd = dash_cooldown() if p_dash_charges < dash_max_charges() else 0.0
	else:
		p_dash_cd = 0.0
	if decoy_t > 0.0:
		decoy_t -= dt
		if decoy_t <= 0.0:
			_decoy_blast()
	if p_dash_t > 0.0:
		p_dash_t -= dt
		p_pos += p_dash_dir * float(bal.player.dash_speed) * dt
		if float(stats.get("dash_damage", 0.0)) > 0.0:
			_lunge_hits()
	else:
		var spd := float(bal.player.speed) * (1.0 + float(stats.move))
		p_pos += m * spd * dt
	if m.length_squared() > 0.01:
		p_facing = m.normalized()
	var regen := float(bal.player.regen) + float(stats.regen)
	if terr != null:
		p_pos = terr.clamp_inside(p_pos, p_radius)
		p_on_land = terr.is_owned(p_pos)
		if p_on_land:
			regen += float(bal.territory.player_regen)
	if regen > 0.0:
		p_hp = minf(p_max_hp, p_hp + regen * dt)
	if p_iframes > 0.0:
		p_iframes -= dt


func _spawn_point() -> Vector2:
	var a := rng.randf() * TAU
	var d := rng.randf_range(float(bal.perf.spawn_min_distance), float(bal.perf.spawn_max_distance))
	var p := p_pos + Vector2(cos(a), sin(a)) * d
	if terr == null:
		return p
	# In the dish: off-screen, inside the rim and never on our land.
	for attempt in 12:
		if p.length() < terr.radius - 40.0 and not terr.is_owned(p):
			return p
		a = rng.randf() * TAU
		d = rng.randf_range(float(bal.perf.spawn_min_distance) * 0.8, float(bal.perf.spawn_max_distance))
		p = p_pos + Vector2(cos(a), sin(a)) * d
	# Fallback: a random point on the rim.
	a = rng.randf() * TAU
	return Vector2(cos(a), sin(a)) * (terr.radius - 60.0)


## Ring spawns and splits can land on bad spots in the dish; fix them up.
func _valid_spawn(p: Vector2) -> Vector2:
	if terr == null:
		return p
	if p.length() > terr.radius - 40.0 or terr.is_owned(p):
		return _spawn_point()
	return p


func _spawn(dt: float) -> void:
	for order in director.update(dt, time, hostile_count()):
		var n := int(order.count)
		match order.pattern:
			"ring":
				var d := float(bal.perf.spawn_min_distance)
				var a0 := rng.randf() * TAU
				for k in n:
					var a := a0 + TAU * k / n
					_add_enemy(order.id, _valid_spawn(p_pos + Vector2(cos(a), sin(a)) * d))
			"single":
				var elite: bool = order.get("elite", false)
				_add_enemy(order.id, _spawn_point(), elite)
				if elite:
					_emit({"type": "elite_spawn", "id": order.id})
				elif enemy_defs[enemy_idx[order.id]].behavior == "boss":
					_emit({"type": "boss_spawn"})
			_:
				var c := _spawn_point()
				for k in n:
					_add_enemy(order.id, c + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)))


func _add_enemy(id: String, pos: Vector2, elite: bool = false) -> void:
	var t: int = enemy_idx[id]
	var d: Dictionary = enemy_defs[t]
	var hp := float(d.hp)
	if not d.get("fixed_hp", false):
		hp *= director.hp_mult(time) * _pressure(float(bal.territory.get("pressure_hp_per_infected", 0.0)) if terr != null else 0.0)
	var r := float(d.radius)
	var spd := float(d.speed)
	if elite:
		var el: Dictionary = data.waves.elites
		hp *= float(el.hp_mult)
		r *= float(el.radius_mult)
		spd *= float(el.speed_mult)
	e_rad.append(r)
	e_spd.append(spd)
	e_elite.append(1 if elite else 0)
	e_team.append(0)
	e_life.append(0.0)
	e_type.append(t)
	e_uid.append(_next_uid)
	_next_uid += 1
	e_pos.append(pos)
	e_knock.append(Vector2.ZERO)
	e_hp.append(hp)
	e_maxhp.append(hp)
	e_flash.append(0.0)
	e_timer.append(rng.randf_range(0.5, 1.5))
	e_phase.append(0)
	e_dir.append(Vector2.ZERO)
	e_hitcd.append(0.0)


func _remove_enemy(i: int) -> void:
	var last := e_pos.size() - 1
	if i != last:
		e_type[i] = e_type[last]
		e_uid[i] = e_uid[last]
		e_pos[i] = e_pos[last]
		e_knock[i] = e_knock[last]
		e_hp[i] = e_hp[last]
		e_maxhp[i] = e_maxhp[last]
		e_flash[i] = e_flash[last]
		e_timer[i] = e_timer[last]
		e_phase[i] = e_phase[last]
		e_dir[i] = e_dir[last]
		e_hitcd[i] = e_hitcd[last]
		e_rad[i] = e_rad[last]
		e_spd[i] = e_spd[last]
		e_elite[i] = e_elite[last]
		e_team[i] = e_team[last]
		e_life[i] = e_life[last]
	e_team.resize(last)
	e_life.resize(last)
	e_rad.resize(last)
	e_spd.resize(last)
	e_elite.resize(last)
	e_type.resize(last)
	e_uid.resize(last)
	e_pos.resize(last)
	e_knock.resize(last)
	e_hp.resize(last)
	e_maxhp.resize(last)
	e_flash.resize(last)
	e_timer.resize(last)
	e_phase.resize(last)
	e_dir.resize(last)
	e_hitcd.resize(last)


## Integer grid key: much cheaper to hash than Vector2i.
static func _key(cx: int, cy: int) -> int:
	return (cx + 32768) * 65536 + (cy + 32768)


func _rebuild_grid() -> void:
	_grid.clear()
	for i in e_pos.size():
		var p := e_pos[i]
		var k := _key(floori(p.x / CELL), floori(p.y / CELL))
		var cell: Variant = _grid.get(k)
		if cell == null:
			_grid[k] = [i]
		else:
			cell.append(i)


func _update_enemies(dt: float) -> void:
	var decay := maxf(0.0, 1.0 - float(bal.juice.knockback_decay) * dt)
	var despawn2 := float(bal.perf.despawn_distance) ** 2
	boss_index = -1
	_frame += 1
	var phase := _frame % SEP_EVERY
	_ally_slot = 0
	_ally_slots = maxi(ally_count, 1)
	for i in e_pos.size():
		var t := e_type[i]
		var beh := _tbeh[t]
		var pos := e_pos[i]
		var to_p := p_pos - pos
		var dist2 := to_p.length_squared()
		var dist := sqrt(dist2)
		var dir := to_p / dist if dist > 0.001 else Vector2.ZERO
		var spd := e_spd[i]
		var vel := Vector2.ZERO
		if e_team[i] == 1:
			_ally_snap = Vector2.INF
			vel = _ally_velocity(i, t, beh, pos, to_p, dist, dt)
			if _ally_snap != Vector2.INF:
				pos = _ally_snap
				vel = Vector2.ZERO
			beh = BEH_CHASE  # never treated as a boss below
		else:
			if decoy_t > 0.0 and beh != BEH_BOSS and pos.distance_squared_to(decoy_pos) < float(bal.player.decoy_radius) ** 2:
				dir = (decoy_pos - pos).normalized()
			if terr != null and terr.is_owned(pos):
				spd *= 1.0 - float(bal.territory.enemy_slow)
			vel = dir * spd
			if beh != BEH_CHASE:
				vel = _special_behavior(i, t, beh, pos, dir, dist, spd, vel, dt)
		# Soft separation so swarms read as a crowd, not one blob. Each enemy
		# resolves overlaps every SEP_EVERY frames, with a matching push strength.
		var sep := Vector2.ZERO
		if i % SEP_EVERY == phase:
			var ri := e_rad[i]
			var cx := floori(pos.x / CELL)
			var cy := floori(pos.y / CELL)
			var found := 0
			for ox in range(-1, 2):
				for oy in range(-1, 2):
					var cell: Variant = _grid.get(_key(cx + ox, cy + oy))
					if cell == null:
						continue
					for j: int in cell:
						if j == i:
							continue
						var off := pos - e_pos[j]
						var md := ri + e_rad[j]
						var d2 := off.length_squared()
						if d2 < md * md and d2 > 0.0001:
							var dd := sqrt(d2)
							sep += off / dd * (md - dd) * (0.5 * SEP_EVERY)
							found += 1
							if found >= 6:
								break
					if found >= 6:
						break
				if found >= 6:
					break
		var kn := e_knock[i]
		if kn != Vector2.ZERO:
			pos += (vel + kn) * dt
			e_knock[i] = kn * decay if kn.length_squared() > 1.0 else Vector2.ZERO
		else:
			pos += vel * dt
		if sep != Vector2.ZERO:
			pos += sep.limit_length(12.0)
		if dist2 > despawn2 and beh != BEH_BOSS:
			pos = _spawn_point() if e_team[i] == 0 else p_pos + to_p.normalized() * -60.0
		if terr != null:
			pos = terr.clamp_inside(pos, e_rad[i])
		e_pos[i] = pos
		if e_flash[i] > 0.0:
			e_flash[i] -= dt
		if e_hitcd[i] > 0.0:
			e_hitcd[i] -= dt


## Non-chase behaviours (ranged, dash, boss). Returns the velocity to use.
func _special_behavior(i: int, t: int, beh: int, pos: Vector2, dir: Vector2, dist: float, spd: float, vel: Vector2, dt: float) -> Vector2:
	var d: Dictionary = enemy_defs[t]
	match beh:
		BEH_RANGED:
			var keep := float(d.keep_distance)
			if dist < keep - 30.0:
				vel = -dir * spd * 0.7
			elif dist < keep + 30.0:
				vel = dir.orthogonal() * spd * 0.5
			e_timer[i] -= dt
			if e_timer[i] <= 0.0 and dist < keep + 220.0:
				e_timer[i] = float(d.fire_cooldown)
				_enemy_shot(pos, dir, float(d.shot_speed), float(d.shot_damage))
		BEH_DASH:
			e_timer[i] -= dt
			match e_phase[i]:
				0:
					if dist < float(d.dash_range) and e_timer[i] <= 0.0:
						e_phase[i] = 1
						e_timer[i] = float(d.windup_s)
						e_dir[i] = dir
				1:
					vel = Vector2.ZERO
					if e_timer[i] <= 0.0:
						e_phase[i] = 2
						e_timer[i] = float(d.dash_s)
				2:
					vel = e_dir[i] * float(d.dash_speed)
					if e_timer[i] <= 0.0:
						e_phase[i] = 0
						e_timer[i] = float(d.dash_cooldown_s)
		BEH_BOSS:
			boss_index = i
			e_timer[i] -= dt
			if e_timer[i] <= 0.0:
				e_timer[i] = float(d.burst_cooldown_s)
				var n := int(d.burst_count)
				var a0 := rng.randf() * TAU
				for k in n:
					var a := a0 + TAU * k / n
					_enemy_shot(pos, Vector2(cos(a), sin(a)), float(d.shot_speed), float(d.shot_damage))
	return vel


func _enemy_shot(pos: Vector2, dir: Vector2, speed: float, dmg: float) -> void:
	if s_pos.size() >= int(bal.perf.max_enemy_shots):
		return
	s_pos.append(pos)
	s_vel.append(dir * speed)
	s_life.append(4.0)
	s_dmg.append(dmg)


func _damage(i: int, amount: float, knock: Vector2, show: bool = true) -> void:
	if e_hp[i] <= 0.0:
		return
	var d: Dictionary = enemy_defs[e_type[i]]
	if p_on_land:
		amount *= 1.0 + float(bal.territory.player_damage_bonus)
	if ally_count > 0:
		amount *= 1.0 + float(stats.get("hive", 0.0)) * ally_count
	e_hp[i] -= amount
	e_flash[i] = float(bal.juice.flash_s)
	var resist := float(d.get("knock_resist", 0.0))
	if e_elite[i] == 1:
		resist = maxf(resist, float(data.waves.elites.knock_resist))
	e_knock[i] += knock * (1.0 - resist)
	if show:
		_emit({"type": "hit", "pos": e_pos[i], "amount": amount})
	if e_hp[i] <= 0.0:
		_dead[i] = true


## Weapons focus big threats: the nearest elite or boss in range, else the
## nearest enemy.
func _priority_target(from: Vector2, max_range: float) -> int:
	var best := -1
	var best_d := max_range * max_range
	for i in e_pos.size():
		if e_hp[i] <= 0.0 or e_team[i] == 1 or (e_elite[i] == 0 and _tbeh[e_type[i]] != BEH_BOSS):
			continue
		var d2 := e_pos[i].distance_squared_to(from)
		if d2 < best_d:
			best_d = d2
			best = i
	return best if best >= 0 else _nearest_enemy(from, max_range)


func _nearest_enemy(from: Vector2, max_range: float, exclude: Dictionary = {}) -> int:
	var best := -1
	var best_d := max_range * max_range
	for i in e_pos.size():
		if e_hp[i] <= 0.0 or e_team[i] == 1 or exclude.has(e_uid[i]):
			continue
		var d2 := e_pos[i].distance_squared_to(from)
		if d2 < best_d:
			best_d = d2
			best = i
	return best


func _update_weapons(dt: float) -> void:
	orbit_points.clear()
	for id in wstats:
		var w: Dictionary = wstats[id]
		match id:
			"bolt":
				cooldowns[id] -= dt
				if cooldowns[id] > 0.0:
					continue
				var tgt := _priority_target(p_pos, w.range)
				if tgt < 0:
					cooldowns[id] = 0.0
					continue
				cooldowns[id] = w.cooldown
				var base := (e_pos[tgt] - p_pos).normalized()
				var n := int(w.count)
				for k in n:
					var ang := deg_to_rad(11.0) * (k - (n - 1) / 2.0)
					_spawn_bullet(base.rotated(ang) * w.speed, w)
				_emit({"type": "shoot"})
			"orbit":
				orbit_angle = fmod(orbit_angle + w.spin * dt, TAU)
				orbit_size = w.size
				var n := int(w.count)
				for k in n:
					var a := orbit_angle + TAU * k / n
					var c: Vector2 = p_pos + Vector2(cos(a), sin(a)) * w.orbit_radius
					orbit_points.append(c)
					if w.get("blocks_shots", 0.0) > 0.0:
						_block_shots(c, w.size)
					for i: int in query(c, w.size):
						if e_hitcd[i] <= 0.0 and e_hp[i] > 0.0:
							e_hitcd[i] = w.hit_interval
							_damage(i, w.damage, (e_pos[i] - p_pos).normalized() * w.knockback)
							if w.has("heal_on_hit"):
								p_hp = minf(p_max_hp, p_hp + w.heal_on_hit)
			"nova":
				if _nova_echo > 0.0:
					_nova_echo -= dt
					if _nova_echo <= 0.0:
						_fire_nova(w)
				cooldowns[id] -= dt
				if cooldowns[id] > 0.0:
					continue
				cooldowns[id] = w.cooldown
				_fire_nova(w)
				if w.get("pulses", 1.0) > 1.0:
					_nova_echo = 0.3
			"chain":
				cooldowns[id] -= dt
				if cooldowns[id] > 0.0:
					continue
				var tgt := _priority_target(p_pos, w.range)
				if tgt < 0:
					cooldowns[id] = 0.0
					continue
				cooldowns[id] = w.cooldown
				var hit := {}
				var cur := tgt
				for f in int(w.get("forks", 1.0)):
					if f > 0:
						cur = _nearest_enemy(p_pos, w.range, hit)
						if cur < 0:
							break
					var pts := PackedVector2Array([p_pos])
					for k in int(w.jumps) + 1:
						hit[e_uid[cur]] = true
						pts.append(e_pos[cur])
						_damage(cur, w.damage, Vector2.ZERO)
						cur = _nearest_enemy(e_pos[cur], w.jump_range, hit)
						if cur < 0:
							break
					_emit({"type": "chain", "points": pts, "evolved": evolved.has(id)})


## Antibodies destroy enemy shots that touch them (counter to Spitters).
func _block_shots(c: Vector2, size: float) -> void:
	var r := size + 8.0
	var r2 := r * r
	var i := s_pos.size() - 1
	while i >= 0:
		if s_pos[i].distance_squared_to(c) < r2:
			_emit({"type": "shot_blocked", "pos": s_pos[i]})
			var last := s_pos.size() - 1
			s_pos[i] = s_pos[last]
			s_vel[i] = s_vel[last]
			s_life[i] = s_life[last]
			s_dmg[i] = s_dmg[last]
			s_pos.resize(last)
			s_vel.resize(last)
			s_life.resize(last)
			s_dmg.resize(last)
		i -= 1


func _fire_nova(w: Dictionary) -> void:
	for i: int in query(p_pos, w.area):
		_damage(i, w.damage, (e_pos[i] - p_pos).normalized() * w.knockback)
	_emit({"type": "nova", "pos": p_pos, "radius": w.area})


func _spawn_bullet(vel: Vector2, w: Dictionary) -> void:
	if b_pos.size() >= int(bal.perf.max_projectiles):
		return
	b_pos.append(p_pos)
	b_vel.append(vel)
	b_dmg.append(w.damage)
	b_pierce.append(int(w.pierce))
	b_life.append(w.range / w.speed + 0.15)
	b_rad.append(w.size)
	b_knock.append(w.knockback)
	b_hits.append({})


func _remove_bullet(i: int) -> void:
	var last := b_pos.size() - 1
	if i != last:
		b_pos[i] = b_pos[last]
		b_vel[i] = b_vel[last]
		b_dmg[i] = b_dmg[last]
		b_pierce[i] = b_pierce[last]
		b_life[i] = b_life[last]
		b_rad[i] = b_rad[last]
		b_knock[i] = b_knock[last]
		b_hits[i] = b_hits[last]
	b_pos.resize(last)
	b_vel.resize(last)
	b_dmg.resize(last)
	b_pierce.resize(last)
	b_life.resize(last)
	b_rad.resize(last)
	b_knock.resize(last)
	b_hits.resize(last)


func _update_bullets(dt: float) -> void:
	var i := 0
	while i < b_pos.size():
		b_pos[i] = b_pos[i] + b_vel[i] * dt
		b_life[i] -= dt
		var gone := b_life[i] <= 0.0
		if not gone:
			var hits: Dictionary = b_hits[i]
			for j: int in query(b_pos[i], b_rad[i]):
				if e_hp[j] <= 0.0 or hits.has(e_uid[j]):
					continue
				hits[e_uid[j]] = true
				_damage(j, b_dmg[i], b_vel[i].normalized() * b_knock[i])
				if b_pierce[i] <= 0:
					gone = true
					break
				b_pierce[i] -= 1
		if gone:
			_remove_bullet(i)
		else:
			i += 1


func _update_enemy_shots(dt: float) -> void:
	var i := 0
	var hit_r := p_radius + 6.0
	while i < s_pos.size():
		s_pos[i] = s_pos[i] + s_vel[i] * dt
		s_life[i] -= dt
		var gone := s_life[i] <= 0.0
		if not gone and s_pos[i].distance_squared_to(p_pos) < hit_r * hit_r:
			gone = true
			if p_iframes <= 0.0:
				_hurt(s_dmg[i], "shot")
		if gone:
			var last := s_pos.size() - 1
			s_pos[i] = s_pos[last]
			s_vel[i] = s_vel[last]
			s_life[i] = s_life[last]
			s_dmg[i] = s_dmg[last]
			s_pos.resize(last)
			s_vel.resize(last)
			s_life.resize(last)
			s_dmg.resize(last)
		else:
			i += 1


func _process_dead() -> void:
	if _dead.is_empty():
		return
	var idx: Array = _dead.keys()
	idx.sort()
	idx.reverse()
	_dead = {}
	for i: int in idx:
		var d: Dictionary = enemy_defs[e_type[i]]
		var pos := e_pos[i]
		var elite := e_elite[i] == 1
		if e_team[i] == 1:
			ally_count -= 1
			_emit({"type": "ally_lost", "pos": pos})
			_remove_enemy(i)
			continue
		kills += 1
		_emit({"type": "kill", "pos": pos, "color": d.color, "radius": e_rad[i], "elite": elite})
		if elite:
			elites_killed += 1
			_drop_gem(pos, float(data.waves.elites.xp))
			_drop_chest(pos, int(bal.chests.elite_items))
			if float(stats.get("dash_reset", 0.0)) > 0.0:
				p_dash_charges = dash_max_charges()
				p_dash_cd = 0.0
			_emit({"type": "elite_killed", "pos": pos})
		elif d.behavior == "boss":
			boss_killed = true
			_drop_gem(pos, float(d.xp))
			_drop_chest(pos, int(bal.chests.boss_items))
			_emit({"type": "boss_killed", "pos": pos})
		else:
			_drop_gem(pos, float(d.xp))
			_roll_pickup(pos)
			if _try_convert(i, d):
				continue
		_remove_enemy(i)
		if d.has("split_into"):
			for k in int(d.split_count):
				_add_enemy(d.split_into, pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)))
	# Indices moved: keep the spatial grid valid for the rest of this step.
	_rebuild_grid()


func _hurt(amount: float, cause: String) -> void:
	if bal.get("debug", {}).get("invincible", false):
		return
	p_hp -= amount * director.damage_mult(time) * (1.0 - clampf(float(stats.armor), 0.0, 0.8))
	p_iframes = float(bal.player.iframes_s)
	_emit({"type": "hurt", "amount": amount})
	if p_hp <= 0.0:
		p_hp = 0.0
		state = "dead"
		death_cause = cause
		_emit({"type": "death"})


func _contact_damage() -> void:
	if p_iframes > 0.0 or state != "playing":
		return
	for i: int in query(p_pos, p_radius):
		if e_hp[i] > 0.0:
			var d: Dictionary = enemy_defs[e_type[i]]
			if e_elite[i] == 1:
				_hurt(float(d.damage) * float(data.waves.elites.damage_mult), "elite_" + d.id)
			else:
				_hurt(float(d.damage), d.id)
			return


func _drop_gem(pos: Vector2, value: float) -> void:
	if g_pos.size() >= int(bal.xp.max_gems):
		# Merge into an existing gem instead of growing without bound.
		var j := rng.randi() % g_pos.size()
		g_val[j] += value
		return
	g_pos.append(pos)
	g_val.append(value)
	g_pull.append(0)


func _update_gems(dt: float) -> void:
	var pr := float(bal.player.pickup_radius) * (1.0 + float(stats.magnet))
	var speed := float(bal.xp.gem_speed)
	var gain := 1.0 + float(stats.xp_gain)
	var i := 0
	while i < g_pos.size():
		var off := p_pos - g_pos[i]
		var d := off.length()
		if g_pull[i] == 0 and d < pr:
			g_pull[i] = 1
		if g_pull[i] == 1:
			if d < p_radius + 8.0:
				xp += g_val[i] * gain
				_emit({"type": "pickup", "value": g_val[i]})
				var last := g_pos.size() - 1
				g_pos[i] = g_pos[last]
				g_val[i] = g_val[last]
				g_pull[i] = g_pull[last]
				g_pos.resize(last)
				g_val.resize(last)
				g_pull.resize(last)
				continue
			g_pos[i] = g_pos[i] + off / d * minf(d, speed * dt)
		i += 1
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = Progression.xp_needed(bal, level)
		pending_levelups += 1
		_emit({"type": "level_gained", "level": level, "banked": pending_levelups})


func _roll() -> Array:
	var u: Dictionary = bal.upgrades
	return Upgrades.roll_offers(upgrade_list, owned, rng, int(u.offers_per_level), int(u.max_weapons), float(u.owned_weight_mult))


func _open_levelup() -> void:
	offers = _roll()
	if offers.is_empty():
		pending_levelups = 0
		p_hp = minf(p_max_hp, p_hp + p_max_hp * float(bal.upgrades.heal_when_all_maxed))
		return
	state = "levelup"
	_emit({"type": "level_up", "level": level})


# ===================================================== upgrades and chests

## Raises an upgrade one level (level-up pick or chest), healing on max HP gain.
func _apply_level(id: String) -> void:
	owned[id] = int(owned.get(id, 0)) + 1
	var old_max := p_max_hp
	_recompute_stats()
	if p_max_hp > old_max:
		p_hp += p_max_hp - old_max
	for wid in ready_evolutions():
		if not _evo_announced.has(wid):
			_evo_announced[wid] = true
			_emit({"type": "evolution_ready", "weapon": wid, "name": evolution_defs[wid].name})


func _drop_chest(pos: Vector2, items: int) -> void:
	c_pos.append(pos)
	c_items.append(items)


func _open_chest(items: int) -> void:
	chests_opened += 1
	chest_rewards = []
	for k in items:
		chest_rewards.append(_chest_reward())
	state = "chest"
	_emit({"type": "chest", "rewards": chest_rewards})


## One chest item: an evolution if one is ready, else a level of something
## you already own, else a new item, else a heal.
func _chest_reward() -> Dictionary:
	var ready := ready_evolutions()
	if not ready.is_empty():
		var wid: String = ready[0]
		var ev: Dictionary = evolution_defs[wid]
		evolved[wid] = ev.id
		_recompute_stats()
		_emit({"type": "evolution", "id": ev.id, "weapon": wid})
		return {"kind": "evolution", "id": ev.id, "name": ev.name, "desc": ev.desc, "level": 0}
	var pool := []
	for u in upgrade_list:
		var lv := int(owned.get(u.id, 0))
		if lv > 0 and lv < Upgrades.max_level(u):
			pool.append(u.id)
	if pool.is_empty():
		pool = _roll()
	if pool.is_empty():
		p_hp = minf(p_max_hp, p_hp + p_max_hp * float(bal.chests.heal_when_nothing))
		return {"kind": "heal", "id": "", "name": "Nutrients", "desc": "Restores health", "level": 0}
	var id: String = pool[rng.randi() % pool.size()]
	_apply_level(id)
	var def: Dictionary = upgrade_defs[id]
	return {"kind": "upgrade", "id": id, "name": def.name, "desc": Upgrades.describe(def, owned[id]), "level": owned[id]}


func _roll_pickup(pos: Vector2) -> void:
	var pk: Dictionary = bal.pickups
	if i_pos.size() >= int(pk.max_on_map):
		return
	var r := rng.randf()
	var acc := 0.0
	for k in PICKUP_KINDS.size():
		acc += float(pk.chances.get(PICKUP_KINDS[k], 0.0))
		if r < acc:
			i_pos.append(pos)
			i_kind.append(k)
			return


func _update_pickups() -> void:
	if state != "playing":
		return
	var cr := p_radius + float(bal.chests.pickup_radius)
	for i in range(c_pos.size() - 1, -1, -1):
		if c_pos[i].distance_squared_to(p_pos) < cr * cr:
			var n := c_items[i]
			c_pos.remove_at(i)
			c_items.remove_at(i)
			_open_chest(n)
			return
	var ir := p_radius + float(bal.pickups.pickup_radius)
	for i in range(i_pos.size() - 1, -1, -1):
		if i_pos[i].distance_squared_to(p_pos) < ir * ir:
			var kind: String = PICKUP_KINDS[i_kind[i]]
			var pos := i_pos[i]
			i_pos.remove_at(i)
			i_kind.remove_at(i)
			_apply_pickup(kind, pos)


func _apply_pickup(kind: String, pos: Vector2) -> void:
	var pk: Dictionary = bal.pickups
	match kind:
		"vacuum":
			g_pull.fill(1)
		"heal":
			p_hp = minf(p_max_hp, p_hp + p_max_hp * float(pk.heal_frac))
		"bomb":
			var r := float(pk.bomb_radius)
			for i: int in query(p_pos, r):
				var tough := e_elite[i] == 1 or _tbeh[e_type[i]] == BEH_BOSS
				var push := (e_pos[i] - p_pos).normalized() * 300.0
				_damage(i, float(pk.bomb_damage) if tough else 1.0e6, push, tough)
			_process_dead()
	_emit({"type": "pickup_item", "kind": kind, "pos": pos})


# ================================================================ territory

## Holding more of the dish makes the infection fight back harder.
func _pressure(per_infected: float) -> float:
	if terr == null:
		return 1.0
	return 1.0 + per_infected * terr.infected_fraction()


func _update_territory(dt: float) -> void:
	director.budget_mult = _pressure(float(bal.territory.get("pressure_budget_per_infected", 0.0)))
	var lost_before := terr.trails_lost
	var claimed := terr.update_player(p_pos, dt)
	if terr.trails_lost > lost_before:
		_emit({"type": "trail_lost"})
	if not claimed.is_empty():
		_on_claim(claimed)
	_terr_tick += dt
	var tick := float(bal.territory.tick_s)
	if _terr_tick < tick:
		return
	_terr_tick -= tick
	# Enemies on our land take damage and eat it back.
	var t: Dictionary = bal.territory
	var dmg := float(t.enemy_dps) * tick
	var erode := float(t.erosion_per_s) * tick
	var lost := 0
	for i in e_pos.size():
		if e_team[i] == 1:
			continue
		var ti := terr.index_of(e_pos[i])
		if ti < 0 or terr.tiles[ti] != Territory.OWNED:
			continue
		_damage(i, dmg, Vector2.ZERO, false)
		var mult := 1.0
		if e_elite[i] == 1:
			mult = float(t.elite_erosion_mult)
		elif _tbeh[e_type[i]] == BEH_BOSS:
			mult = float(t.boss_erosion_mult)
		if terr.erode(ti, erode * mult):
			lost += 1
	if lost > 0:
		_emit({"type": "land_lost", "tiles": lost})
	_process_dead()


## Newly enclosed land bursts: enemies standing on it lose a chunk of max HP.
func _on_claim(claimed: PackedInt32Array) -> void:
	var set := {}
	for i in claimed:
		set[i] = true
	var frac := float(bal.territory.claim_burst_frac)
	for i in e_pos.size():
		if e_team[i] == 0 and set.has(terr.index_of(e_pos[i])) and _tbeh[e_type[i]] != BEH_BOSS:
			_damage(i, e_maxhp[i] * frac, Vector2.ZERO)
	_process_dead()
	# Bigger loops pay out: XP per claimed tile.
	xp += claimed.size() * float(bal.territory.get("claim_xp_per_tile", 0.0)) * (1.0 + float(stats.xp_gain))
	_emit({"type": "claim", "tiles": claimed.size(), "cells": claimed, "infected": terr.infected_fraction()})


# =============================================================== conversion

func _ally_cap() -> int:
	return int(bal.conversion.max_allies) + int(stats.get("ally_cap", 0.0))


## A killed (non-elite, non-boss) enemy may rise again on our side. If the
## swarm is full, the conversion "feeds" it instead: a lasting power boost to
## every ally plus a heal, so late conversions still count.
func _try_convert(i: int, d: Dictionary) -> bool:
	if not conv_on or d.behavior == "boss":
		return false
	var chance := float(bal.conversion.base_chance) + float(stats.get("convert", 0.0))
	if rng.randf() >= chance:
		return false
	var c: Dictionary = bal.conversion
	p_hp = minf(p_max_hp, p_hp + float(stats.get("convert_heal", 0.0)))
	if ally_count >= _ally_cap():
		swarm_power = minf(swarm_power + float(c.feed_power), float(c.feed_power_max))
		for k in e_pos.size():
			if e_team[k] == 1:
				e_hp[k] = minf(e_maxhp[k], e_hp[k] + e_maxhp[k] * float(c.feed_heal_frac))
				e_flash[k] = 0.1
		_emit({"type": "swarm_feed", "pos": e_pos[i], "power": swarm_power})
		return false
	e_team[i] = 1
	e_hp[i] = e_maxhp[i] * float(c.ally_hp_mult) * (1.0 + float(stats.get("ally_power", 0.0)) + swarm_power)
	e_maxhp[i] = e_hp[i]
	e_spd[i] = maxf(float(d.speed) * float(c.ally_speed_mult), float(bal.player.speed) * 1.5)
	e_life[i] = float(c.ally_lifetime_s) * (1.0 + float(stats.get("ally_cap", 0.0)) / 20.0)
	e_knock[i] = Vector2.ZERO
	e_timer[i] = 0.5
	e_flash[i] = 0.2
	ally_count += 1
	conversions += 1
	_emit({"type": "convert", "pos": e_pos[i]})
	return true


## Bodyguard formation: each ally holds a slot on a slowly turning ring around
## the player, so the swarm helps while you kite. Melee allies body-block
## (and brawl with whatever reaches them); ranged allies fire outward.
## Allies also soak enemy shots that hit them.
func _ally_velocity(i: int, t: int, beh: int, pos: Vector2, to_p: Vector2, dist: float, dt: float) -> Vector2:
	var c: Dictionary = bal.conversion
	e_life[i] -= dt
	if e_life[i] <= 0.0 and e_hp[i] > 0.0:
		e_hp[i] = 0.0
		_dead[i] = true
	var ring := minf(float(c.ring_radius) + float(c.ring_radius_per_ally) * _ally_slots, float(c.ring_radius_max))
	var ang := TAU * _ally_slot / _ally_slots + time * float(c.ring_spin)
	_ally_slot += 1
	var slot := p_pos + Vector2(cos(ang), sin(ang)) * ring
	if dist > float(c.teleport_distance):
		_ally_snap = slot
		return Vector2.ZERO
	_ally_block_shots(i, pos)
	if beh == BEH_RANGED:
		e_timer[i] -= dt
		if e_timer[i] <= 0.0:
			var tgt := _nearest_enemy(pos, float(c.ally_shot_range))
			if tgt >= 0:
				var d: Dictionary = enemy_defs[t]
				e_timer[i] = float(d.fire_cooldown) * 0.6
				_ally_shot(pos, (e_pos[tgt] - pos).normalized(), float(d.shot_damage) * _ally_power())
	var to_slot := slot - pos
	var len := to_slot.length()
	if len < 1.0:
		return Vector2.ZERO
	return to_slot / len * minf(e_spd[i], len / maxf(dt, 0.001))


## Enemy shots that hit an ally are absorbed by it (the ally takes the damage).
func _ally_block_shots(i: int, pos: Vector2) -> void:
	var r := e_rad[i] + 6.0
	var r2 := r * r
	var k := s_pos.size() - 1
	while k >= 0:
		if s_pos[k].distance_squared_to(pos) < r2:
			e_hp[i] -= s_dmg[k] * director.damage_mult(time)
			e_flash[i] = 0.06
			if e_hp[i] <= 0.0:
				_dead[i] = true
			_emit({"type": "shot_blocked", "pos": s_pos[k]})
			var last := s_pos.size() - 1
			s_pos[k] = s_pos[last]
			s_vel[k] = s_vel[last]
			s_life[k] = s_life[last]
			s_dmg[k] = s_dmg[last]
			s_pos.resize(last)
			s_vel.resize(last)
			s_life.resize(last)
			s_dmg.resize(last)
		k -= 1


func _ally_power() -> float:
	return float(bal.conversion.ally_damage_mult) * (1.0 + float(stats.get("ally_power", 0.0)) + swarm_power) * director.damage_mult(time)


func _ally_shot(from: Vector2, dir: Vector2, dmg: float) -> void:
	if b_pos.size() >= int(bal.perf.max_projectiles):
		return
	var c: Dictionary = bal.conversion
	b_pos.append(from)
	b_vel.append(dir * float(c.ally_shot_speed))
	b_dmg.append(dmg)
	b_pierce.append(0)
	b_life.append(float(c.ally_shot_range) / float(c.ally_shot_speed))
	b_rad.append(6.0)
	b_knock.append(60.0)
	b_hits.append({})


## Melee between allies and the enemies touching them, on a short tick.
func _update_ally_combat(dt: float) -> void:
	_ally_tick += dt
	var tick := float(bal.conversion.tick_s)
	if _ally_tick < tick:
		return
	_ally_tick -= tick
	var power := _ally_power()
	var hostile_mult := director.damage_mult(time)
	for i in e_pos.size():
		if e_team[i] != 1 or e_hp[i] <= 0.0:
			continue
		var hits := query(e_pos[i], e_rad[i] + 2.0)
		if hits.is_empty():
			continue
		var j: int = hits[0]
		var mine: Dictionary = enemy_defs[e_type[i]]
		var theirs: Dictionary = enemy_defs[e_type[j]]
		_damage(j, float(mine.damage) * power * tick, (e_pos[j] - e_pos[i]).normalized() * 40.0, false)
		var taken := float(theirs.damage) * hostile_mult * tick
		if e_elite[j] == 1:
			taken *= float(data.waves.elites.damage_mult)
		e_hp[i] -= taken
		e_flash[i] = 0.06
		if e_hp[i] <= 0.0:
			_dead[i] = true
	_process_dead()


# ===================================================================== dash

## Damage scaled like the enemies' HP so dash upgrades stay relevant late.
func _dash_power(base: float) -> float:
	return base * (1.0 + float(stats.might)) * director.hp_mult(time)


## Lunge: everything the dash passes through takes damage once per dash.
func _lunge_hits() -> void:
	var dmg := _dash_power(float(stats.get("dash_damage", 0.0)))
	for i: int in query(p_pos, p_radius + 12.0):
		if _dash_hits.has(e_uid[i]):
			continue
		_dash_hits[e_uid[i]] = true
		_damage(i, dmg, p_dash_dir * 260.0)


## Afterimage: the decoy pops when it expires, hurting what it lured.
func _decoy_blast() -> void:
	var pl: Dictionary = bal.player
	var dmg := _dash_power(float(pl.decoy_blast_damage) * float(stats.get("dash_decoy", 1.0)))
	for i: int in query(decoy_pos, float(pl.decoy_blast_radius)):
		_damage(i, dmg, (e_pos[i] - decoy_pos).normalized() * 220.0)
	_emit({"type": "nova", "pos": decoy_pos, "radius": float(pl.decoy_blast_radius)})
