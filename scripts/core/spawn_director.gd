class_name SpawnDirector
extends RefCounted
## Decides what spawns when. A spawn budget accrues along waves.budget_curve and
## is spent on enemies from the pool (each has a cost). Scripted events (rings,
## boss) fire once at fixed times. Respects the on-screen cap (waves.max_alive).

var waves: Dictionary
var enemies: Dictionary  # id -> def
var rng: RandomNumberGenerator
var budget := 0.0
var _done_events := {}
var _next_pick: Dictionary = {}


func _init(waves_data: Dictionary, enemies_by_id: Dictionary, random: RandomNumberGenerator) -> void:
	waves = waves_data
	enemies = enemies_by_id
	rng = random


func budget_rate(t: float) -> float:
	var curve: Array = waves.budget_curve
	if t <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var t1 := float(curve[i][0])
		if t <= t1:
			var t0 := float(curve[i - 1][0])
			var f := (t - t0) / maxf(t1 - t0, 0.001)
			return lerpf(float(curve[i - 1][1]), float(curve[i][1]), f)
	return float(curve[-1][1])


func pool_at(t: float) -> Array:
	var out := []
	for p in waves.pool:
		if t >= float(p.from) and t < float(p.until):
			out.append(p)
	return out


func hp_mult(t: float) -> float:
	return 1.0 + float(waves.hp_growth_per_min) * t / 60.0


## Returns spawn orders: [{id, count, pattern}] for this tick.
func update(dt: float, t: float, alive: int) -> Array:
	var out := []
	for i in waves.events.size():
		var ev: Dictionary = waves.events[i]
		if not _done_events.has(i) and t >= float(ev.t):
			_done_events[i] = true
			out.append({"id": ev.enemy, "count": int(ev.count), "pattern": ev.get("pattern", "ring")})
	budget = minf(budget + budget_rate(t) * dt, float(waves.max_budget_bank))
	var cap := int(waves.max_alive)
	var pool := pool_at(t)
	if pool.is_empty():
		return out
	var guard := 0
	while alive < cap and guard < 64:
		guard += 1
		if _next_pick.is_empty() or not pool.has(_next_pick):
			_next_pick = _weighted(pool)
		var n := int(_next_pick.get("group", 1))
		var cost := float(enemies[_next_pick.enemy].cost) * n
		if cost > budget:
			break
		budget -= cost
		out.append({"id": _next_pick.enemy, "count": n, "pattern": "cluster"})
		alive += n
		_next_pick = {}
	return out


func _weighted(pool: Array) -> Dictionary:
	var total := 0.0
	for p in pool:
		total += float(p.weight)
	var r := rng.randf() * total
	for p in pool:
		r -= float(p.weight)
		if r <= 0.0:
			return p
	return pool[-1]
