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
var _trad := PackedFloat32Array()  # type index -> radius

## Set false in headless sims to skip building event dictionaries.
var emit_events := true
var events: Array = []

var time := 0.0
var run_length := 300.0
var state := "playing"  # playing | levelup | dead | won

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
		_trad.append(float(e.radius))
	upgrade_list = data.upgrades
	for u in upgrade_list:
		upgrade_defs[u.id] = u
	var by_id := {}
	for e in enemy_defs:
		by_id[e.id] = e
	director = SpawnDirector.new(data.waves, by_id, rng)
	p_radius = float(bal.player.radius)
	xp_next = Progression.xp_needed(bal, 1)
	owned[bal.start_weapon] = 1
	_recompute_stats()
	p_hp = p_max_hp


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
	_spawn(dt)
	_rebuild_grid()
	_update_enemies(dt)
	_update_weapons(dt)
	_update_bullets(dt)
	_update_enemy_shots(dt)
	_process_dead()
	_contact_damage()
	_update_gems(dt)
	if pending_levelups > 0 and state == "playing":
		_open_levelup()


func choose_upgrade(id: String) -> void:
	if state != "levelup" or not offers.has(id):
		return
	var was := int(owned.get(id, 0))
	owned[id] = was + 1
	var old_max := p_max_hp
	_recompute_stats()
	if p_max_hp > old_max:
		p_hp += p_max_hp - old_max
	pending_levelups -= 1
	offers = []
	state = "playing"
	_emit({"type": "upgrade", "id": id, "level": owned[id]})
	if pending_levelups > 0:
		_open_levelup()


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


func enemy_radius(i: int) -> float:
	return _trad[e_type[i]]


## Indices of enemies whose circle overlaps the circle (center, radius).
func query(center: Vector2, radius: float) -> Array:
	var out := []
	var r := radius + _max_er
	var x0 := floori((center.x - r) / CELL)
	var x1 := floori((center.x + r) / CELL)
	var y0 := floori((center.y - r) / CELL)
	var y1 := floori((center.y + r) / CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var cell: Variant = _grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for i: int in cell:
				var rr := radius + _trad[e_type[i]]
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
	var spd := float(bal.player.speed) * (1.0 + float(stats.move))
	p_pos += m * spd * dt
	if m.length_squared() > 0.01:
		p_facing = m.normalized()
	var regen := float(bal.player.regen) + float(stats.regen)
	if regen > 0.0:
		p_hp = minf(p_max_hp, p_hp + regen * dt)
	if p_iframes > 0.0:
		p_iframes -= dt


func _spawn_point() -> Vector2:
	var a := rng.randf() * TAU
	var d := rng.randf_range(float(bal.perf.spawn_min_distance), float(bal.perf.spawn_max_distance))
	return p_pos + Vector2(cos(a), sin(a)) * d


func _spawn(dt: float) -> void:
	for order in director.update(dt, time, e_pos.size()):
		var n := int(order.count)
		match order.pattern:
			"ring":
				var d := float(bal.perf.spawn_min_distance)
				var a0 := rng.randf() * TAU
				for k in n:
					var a := a0 + TAU * k / n
					_add_enemy(order.id, p_pos + Vector2(cos(a), sin(a)) * d)
			"single":
				_add_enemy(order.id, _spawn_point())
				if enemy_defs[enemy_idx[order.id]].behavior == "boss":
					_emit({"type": "boss_spawn"})
			_:
				var c := _spawn_point()
				for k in n:
					_add_enemy(order.id, c + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)))


func _add_enemy(id: String, pos: Vector2) -> void:
	var t: int = enemy_idx[id]
	var d: Dictionary = enemy_defs[t]
	var hp := float(d.hp)
	if not d.get("fixed_hp", false):
		hp *= director.hp_mult(time)
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


func _rebuild_grid() -> void:
	_grid.clear()
	for i in e_pos.size():
		var k := Vector2i(floori(e_pos[i].x / CELL), floori(e_pos[i].y / CELL))
		var cell: Variant = _grid.get(k)
		if cell == null:
			_grid[k] = [i]
		else:
			cell.append(i)


func _update_enemies(dt: float) -> void:
	var decay := float(bal.juice.knockback_decay)
	var despawn := float(bal.perf.despawn_distance)
	boss_index = -1
	for i in e_pos.size():
		var t := e_type[i]
		var d: Dictionary = enemy_defs[t]
		var pos := e_pos[i]
		var to_p := p_pos - pos
		var dist := to_p.length()
		var dir := to_p / dist if dist > 0.001 else Vector2.ZERO
		var spd := float(d.speed)
		var vel := dir * spd
		match d.behavior:
			"ranged":
				var keep := float(d.keep_distance)
				if dist < keep - 30.0:
					vel = -dir * spd * 0.7
				elif dist < keep + 30.0:
					vel = dir.orthogonal() * spd * 0.5
				e_timer[i] -= dt
				if e_timer[i] <= 0.0 and dist < keep + 220.0:
					e_timer[i] = float(d.fire_cooldown)
					_enemy_shot(pos, dir, float(d.shot_speed), float(d.shot_damage))
			"dash":
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
			"boss":
				boss_index = i
				e_timer[i] -= dt
				if e_timer[i] <= 0.0:
					e_timer[i] = float(d.burst_cooldown_s)
					var n := int(d.burst_count)
					var a0 := rng.randf() * TAU
					for k in n:
						var a := a0 + TAU * k / n
						_enemy_shot(pos, Vector2(cos(a), sin(a)), float(d.shot_speed), float(d.shot_damage))
		# Soft separation so swarms read as a crowd, not a single blob.
		var sep := Vector2.ZERO
		var ri := _trad[t]
		var ck := Vector2i(floori(pos.x / CELL), floori(pos.y / CELL))
		for ox in range(-1, 2):
			for oy in range(-1, 2):
				var cell: Variant = _grid.get(Vector2i(ck.x + ox, ck.y + oy))
				if cell == null:
					continue
				for j: int in cell:
					if j == i:
						continue
					var off := pos - e_pos[j]
					var md := ri + _trad[e_type[j]]
					var d2 := off.length_squared()
					if d2 < md * md and d2 > 0.0001:
						var dd := sqrt(d2)
						sep += off / dd * (md - dd) * 0.5
		pos += (vel + e_knock[i]) * dt + sep.limit_length(6.0)
		e_knock[i] = e_knock[i] * maxf(0.0, 1.0 - decay * dt)
		if dist > despawn and d.behavior != "boss":
			pos = _spawn_point()
		e_pos[i] = pos
		if e_flash[i] > 0.0:
			e_flash[i] -= dt
		if e_hitcd[i] > 0.0:
			e_hitcd[i] -= dt


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
	e_hp[i] -= amount
	e_flash[i] = float(bal.juice.flash_s)
	e_knock[i] += knock * (1.0 - float(d.get("knock_resist", 0.0)))
	if show:
		_emit({"type": "hit", "pos": e_pos[i], "amount": amount})
	if e_hp[i] <= 0.0:
		_dead[i] = true


func _nearest_enemy(from: Vector2, max_range: float, exclude: Dictionary = {}) -> int:
	var best := -1
	var best_d := max_range * max_range
	for i in e_pos.size():
		if e_hp[i] <= 0.0 or exclude.has(e_uid[i]):
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
				var tgt := _nearest_enemy(p_pos, w.range)
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
					for i: int in query(c, w.size):
						if e_hitcd[i] <= 0.0 and e_hp[i] > 0.0:
							e_hitcd[i] = w.hit_interval
							_damage(i, w.damage, (e_pos[i] - p_pos).normalized() * w.knockback)
			"nova":
				cooldowns[id] -= dt
				if cooldowns[id] > 0.0:
					continue
				cooldowns[id] = w.cooldown
				for i: int in query(p_pos, w.area):
					_damage(i, w.damage, (e_pos[i] - p_pos).normalized() * w.knockback)
				_emit({"type": "nova", "pos": p_pos, "radius": w.area})
			"chain":
				cooldowns[id] -= dt
				if cooldowns[id] > 0.0:
					continue
				var tgt := _nearest_enemy(p_pos, w.range)
				if tgt < 0:
					cooldowns[id] = 0.0
					continue
				cooldowns[id] = w.cooldown
				var hit := {}
				var pts := PackedVector2Array([p_pos])
				var cur := tgt
				for k in int(w.jumps) + 1:
					hit[e_uid[cur]] = true
					pts.append(e_pos[cur])
					_damage(cur, w.damage, Vector2.ZERO)
					cur = _nearest_enemy(e_pos[cur], w.jump_range, hit)
					if cur < 0:
						break
				_emit({"type": "chain", "points": pts})


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
		kills += 1
		_drop_gem(pos, float(d.xp))
		_emit({"type": "kill", "pos": pos, "color": d.color, "radius": float(d.radius)})
		if d.behavior == "boss":
			boss_killed = true
			_emit({"type": "boss_killed", "pos": pos})
		_remove_enemy(i)
		if d.has("split_into"):
			for k in int(d.split_count):
				_add_enemy(d.split_into, pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-14, 14)))
	# Indices moved: keep the spatial grid valid for the rest of this step.
	_rebuild_grid()


func _hurt(amount: float, cause: String) -> void:
	p_hp -= amount * (1.0 - clampf(float(stats.armor), 0.0, 0.8))
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
