class_name Territory
extends RefCounted
## Territory on a bounded round dish (prototype 1, see docs/ROADMAP.md).
## A square grid covers the dish; each tile is OUTSIDE (beyond the rim),
## NEUTRAL or OWNED. Leaving owned land draws a trail; stepping back onto
## owned land claims the trail plus everything it encloses (flood fill from
## the outside). Enemies standing on owned tiles erode them back to neutral.
## Pure logic: World drives it, WorldView draws it.

const NEUTRAL := 0
const OWNED := 1
const OUTSIDE := 255

var cfg: Dictionary
var radius := 1500.0
var n := 64  # tiles per side
var cell := 47.0
var origin := Vector2.ZERO  # world position of tile (0, 0)'s corner
var tiles := PackedByteArray()
var core := PackedByteArray()  # 1 = can never be eroded (home core)
var erosion := PackedFloat32Array()
var owned_count := 0
var dish_count := 0
var version := 0  # bumps on every tile change
var dirty := PackedInt32Array()  # tiles changed since the view last looked

var trail_points := PackedVector2Array()  # for drawing
var trail_cells := {}  # tile index -> true
var trail_age := 0.0
var trails_lost := 0
var _last_trail_pos := Vector2.INF


func _init(config: Dictionary) -> void:
	cfg = config
	radius = float(cfg.dish_radius)
	n = int(cfg.grid)
	cell = radius * 2.0 / n
	origin = Vector2(-radius, -radius)
	tiles.resize(n * n)
	core.resize(n * n)
	erosion.resize(n * n)
	for y in n:
		for x in n:
			var i := y * n + x
			var c := center_of(i)
			if c.length() > radius - cell * 0.5:
				tiles[i] = OUTSIDE
			else:
				tiles[i] = NEUTRAL
				dish_count += 1
				if c.length() <= float(cfg.home_radius):
					tiles[i] = OWNED
					owned_count += 1
				if c.length() <= float(cfg.core_radius):
					core[i] = 1


func index_of(p: Vector2) -> int:
	var x := floori((p.x - origin.x) / cell)
	var y := floori((p.y - origin.y) / cell)
	if x < 0 or y < 0 or x >= n or y >= n:
		return -1
	return y * n + x


func center_of(i: int) -> Vector2:
	return origin + Vector2((i % n) + 0.5, (i / n) + 0.5) * cell


func is_owned(p: Vector2) -> bool:
	var i := index_of(p)
	return i >= 0 and tiles[i] == OWNED


func infected_fraction() -> float:
	return float(owned_count) / maxf(dish_count, 1)


## Keeps a circle of radius r inside the dish.
func clamp_inside(p: Vector2, r: float) -> Vector2:
	var lim := radius - r
	if p.length_squared() > lim * lim:
		return p.normalized() * lim
	return p


## Called every step with the player's position. Returns the list of tile
## indices claimed this step (empty if nothing was claimed).
func update_player(p: Vector2, dt: float) -> PackedInt32Array:
	var claimed := PackedInt32Array()
	if is_owned(p):
		if not trail_cells.is_empty():
			claimed = _claim()
		_clear_trail()
		return claimed
	# Outside our land: extend the trail.
	trail_age += dt
	if trail_age > float(cfg.trail_timeout_s):
		_clear_trail()
		trails_lost += 1
		trail_age = -0.5  # brief grace so a new trail starts cleanly
		return claimed
	if trail_age < 0.0:
		return claimed
	if _last_trail_pos == Vector2.INF:
		_last_trail_pos = p
		trail_points.append(p)
	# Rasterise the segment so fast moves leave no gaps in the wall.
	var seg := p - _last_trail_pos
	var steps := maxi(1, ceili(seg.length() / (cell * 0.4)))
	for k in range(1, steps + 1):
		var q := _last_trail_pos + seg * (float(k) / steps)
		var i := index_of(q)
		if i >= 0 and tiles[i] == NEUTRAL:
			trail_cells[i] = true
	if seg.length() >= float(cfg.trail_point_spacing):
		trail_points.append(p)
		_last_trail_pos = p
	return claimed


func trail_time_left() -> float:
	return float(cfg.trail_timeout_s) - trail_age


func _clear_trail() -> void:
	trail_cells.clear()
	trail_points.clear()
	trail_age = 0.0
	_last_trail_pos = Vector2.INF


## Trail tiles become owned, then every neutral tile that can't reach the
## outside (4-neighbour flood fill through non-owned tiles) is owned too.
func _claim() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in trail_cells:
		if tiles[i] == NEUTRAL:
			tiles[i] = OWNED
			out.append(i)
	var reach := PackedByteArray()
	reach.resize(n * n)
	var queue := PackedInt32Array()
	for i in n * n:
		if tiles[i] == OUTSIDE:
			reach[i] = 1
			queue.append(i)
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % n
		var y := i / n
		for d in 4:
			var nx := x + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny := y + (1 if d == 2 else (-1 if d == 3 else 0))
			if nx < 0 or ny < 0 or nx >= n or ny >= n:
				continue
			var j := ny * n + nx
			if reach[j] == 0 and tiles[j] != OWNED:
				reach[j] = 1
				queue.append(j)
	for i in n * n:
		if tiles[i] == NEUTRAL and reach[i] == 0:
			tiles[i] = OWNED
			out.append(i)
	owned_count += out.size()
	for i in out:
		erosion[i] = 0.0
	dirty.append_array(out)
	if not out.is_empty():
		version += 1
	return out


## An enemy stands on tile i for dt seconds with the given erosion weight.
## Returns true if the tile was lost.
func erode(i: int, amount: float) -> bool:
	if i < 0 or tiles[i] != OWNED or core[i] == 1:
		return false
	erosion[i] += amount
	if erosion[i] >= 1.0:
		erosion[i] = 0.0
		tiles[i] = NEUTRAL
		owned_count -= 1
		version += 1
		dirty.append(i)
		return true
	return false
