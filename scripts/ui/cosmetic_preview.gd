class_name CosmeticPreview
extends Control
## A small live scene for the Style screen: your cell (skin) in a tiny dish,
## orbiting antibodies and bolts (weapon style) shooting germs that burst
## with the pop style (and its sound). Uses CosmeticArt, the same drawing
## the run uses. Presentation only; no World.

## The default goo pop, as a pop-style look (the run keeps its own code).
const GOO := {"shape": "disc", "colors": ["germ"], "count": 8, "speed": [140, 380], "drag": 3.0, "life": 0.4, "size": [6, 12], "ring": true, "sparks": 2}

var look := {}  # {skin, weapon, pop} (Cosmetics.look)
var pal := {}
var germ_colors: Array = []  # Color per enemy type
var sound := true

var _t := 0.0
var _cell_tex: Texture2D
var _disc: Texture2D
var _glow: Texture2D
var _ring: Texture2D
var _germs: Array = []  # {pos, r, c, dead_t}
var _bullets: Array = []  # {pos, vel, target}
var _fx: Array = []
var _splats: Array = []  # {pos, r, c, t}
var _fire_t := 0.3
var _path := 0.0  # where the cell is on its little loop
var _dash_t := 1.0  # time to the next dash
var _dashing := 0.0  # > 0 while dashing (trail on)
var _pos := Vector2.ZERO
var _note := 0  # Melody: next note of the scale
var _nova_t := 1.2
var _nova := -1.0
var _chain_t := 2.0
var _chain := -1.0
var _chain_pts := PackedVector2Array()


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cell_tex = ShapeTextures.player_cell()
	_disc = ShapeTextures.disc()
	_glow = ShapeTextures.glow(64)
	_ring = ShapeTextures.ring()
	for k in 4:
		_germs.append({"pos": Vector2.ZERO, "r": 0.0, "c": Color.WHITE, "dead_t": 0.2 * k})


func set_look(l: Dictionary) -> void:
	look = l
	_fx.clear()
	_splats.clear()


## The cell drifts on a small figure-eight and dashes every couple of
## seconds (so trails show), always in the left part of the dish.
func _cell_pos() -> Vector2:
	return _pos


func _move(delta: float) -> void:
	_dash_t -= delta
	if _dash_t <= 0.0:
		_dash_t = 2.2
		_dashing = 0.28
	var speed := 0.6
	if _dashing > 0.0:
		_dashing -= delta
		speed = 6.5
	_path += delta * speed
	_pos = Vector2(size.x * 0.3 + cos(_path) * size.x * 0.13, size.y * 0.52 + sin(_path * 2.0) * size.y * 0.2)
	if _dashing > 0.0:
		var trail: Dictionary = look.get("trail", {})
		var body := CosmeticArt.body_color(look.get("skin", {}), pal.get("player", Color.WHITE), _t)
		if trail.is_empty() or trail.get("afterimage", false):
			_fx.append({"kind": "dot", "pos": _pos, "vel": Vector2.ZERO, "color": Color(body, 0.6), "r": 30.0, "life": 0.22, "t": 0.0})
		for f in CosmeticArt.trail_burst(trail, _pos, body, _t, delta):
			f["t"] = 0.0
			_fx.append(f)


func _spawn(g: Dictionary) -> void:
	g.pos = Vector2(randf_range(size.x * 0.55, size.x * 0.92), randf_range(size.y * 0.2, size.y * 0.82))
	g.r = randf_range(14.0, 22.0)
	g.c = germ_colors[randi() % germ_colors.size()] if not germ_colors.is_empty() else Color("#ff5d73")
	g.dead_t = 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree() or size.x <= 0.0:
		return
	_t += delta
	_move(delta)
	var cp := _cell_pos()
	for g in _germs:
		if g.dead_t > 0.0:
			g.dead_t -= delta
			if g.dead_t <= 0.0:
				_spawn(g)
		else:
			g.pos += Vector2(-1, sin(_t * 2.0 + g.r)) * 10.0 * delta  # creep toward you
	_fire_t -= delta
	if _fire_t <= 0.0:
		_fire_t = 0.42
		var tgt := _pick()
		if tgt >= 0:
			_bullets.append({"pos": cp, "vel": (_germs[tgt].pos - cp).normalized() * 520.0, "target": tgt})
	var i := 0
	while i < _bullets.size():
		var b: Dictionary = _bullets[i]
		b.pos += b.vel * delta
		var g: Dictionary = _germs[b.target]
		if g.dead_t <= 0.0 and b.pos.distance_to(g.pos) < g.r:
			_pop(g)
			_bullets.remove_at(i)
			continue
		if not Rect2(Vector2.ZERO, size).grow(40).has_point(b.pos):
			_bullets.remove_at(i)
			continue
		i += 1
	_nova_t -= delta
	if _nova_t <= 0.0:
		_nova_t = 2.6
		_nova = 0.0
	if _nova >= 0.0:
		_nova += delta / 0.35
		if _nova >= 1.0:
			_nova = -1.0
	_chain_t -= delta
	if _chain_t <= 0.0:
		_chain_t = 1.9
		var tgt := _pick()
		if tgt >= 0:
			_chain = 0.0
			var a := cp
			var b2: Vector2 = _germs[tgt].pos
			var mid := (a + b2) / 2.0 + (b2 - a).orthogonal().normalized() * 16.0
			_chain_pts = PackedVector2Array([a, mid, b2])
	if _chain >= 0.0:
		_chain += delta / 0.18
		if _chain >= 1.0:
			_chain = -1.0
	i = 0
	while i < _fx.size():
		var f: Dictionary = _fx[i]
		f.t += delta
		if f.t >= f.life:
			_fx.remove_at(i)
			continue
		if f.has("vel"):
			if f.has("grav"):
				f.vel.y += f.grav * delta
			if f.has("drag"):
				f.vel *= exp(-float(f.drag) * delta)
			f.pos += f.vel * delta
		i += 1
	i = 0
	while i < _splats.size():
		_splats[i].t += delta
		if _splats[i].t > 2.5:
			_splats.remove_at(i)
			continue
		i += 1
	queue_redraw()


func _pick() -> int:
	var alive := []
	for k in _germs.size():
		if _germs[k].dead_t <= 0.0:
			alive.append(k)
	return alive[randi() % alive.size()] if not alive.is_empty() else -1


func _pop(g: Dictionary) -> void:
	var pop: Dictionary = look.get("pop", {})
	var styled := not CosmeticArt.is_default_pop(pop)
	var burst := CosmeticArt.pop_burst(pop if styled else GOO, g.pos, g.r, g.c)
	for f in burst:
		f["t"] = 0.0
		_fx.append(f)
	var sc: Variant = CosmeticArt.splat_color(pop if styled else {"splat": "germ"}, g.c)
	if sc != null:
		_splats.append({"pos": g.pos, "r": g.r * 1.3 * float(pop.get("splat_scale", 1.0)), "c": sc, "t": 0.0})
	g.dead_t = 0.7
	if sound:
		var snd := str(pop.get("sound", "kill"))
		var ps := CosmeticArt.pop_sound(pop, _note)
		_note += 1
		snd = str(ps[0])
		Sfx.play(Sfx.KILLS[randi() % Sfx.KILLS.size()] if snd == "kill" else snd, 0.05 if ps[2] else 0.0, float(ps[1]))


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#150e2b")
	bg.set_corner_radius_all(24)
	bg.border_color = Color(1, 1, 1, 0.12)
	bg.set_border_width_all(2)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))
	for x in range(30, int(size.x), 60):  # faint dish dots
		for y in range(30, int(size.y), 60):
			draw_texture_rect(_disc, Rect2(Vector2(x, y) - Vector2(3, 3), Vector2(6, 6)), false, Color("#2a1e48"))
	for s in _splats:
		var a: float = 0.45 * (1.0 - s.t / 2.5)
		draw_texture_rect(_disc, Rect2(s.pos - Vector2(s.r, s.r), Vector2(s.r, s.r) * 2.0), false, Color(s.c, a))
	for g in _germs:
		if g.dead_t > 0.0:
			continue
		draw_texture_rect(_disc, Rect2(g.pos - Vector2(g.r + 2, g.r + 2), Vector2(g.r + 2, g.r + 2) * 2.0), false, Color(0.08, 0.04, 0.14))
		draw_texture_rect(_disc, Rect2(g.pos - Vector2(g.r, g.r), Vector2(g.r, g.r) * 2.0), false, g.c)
		for e in [-1.0, 1.0]:
			var ep: Vector2 = g.pos + Vector2(-g.r * 0.35, e * g.r * 0.3)
			draw_texture_rect(_disc, Rect2(ep - Vector2(3, 3), Vector2(6, 6)), false, Color(0.08, 0.04, 0.14))
	var w: Dictionary = look.get("weapon", {})
	var shape := CosmeticArt.weapon_shape(w)
	var stex := CosmeticArt.tex(shape)
	var cp := _cell_pos()
	var r := 30.0
	if _nova >= 0.0:
		var nc := CosmeticArt.weapon_color(w, "nova", pal.get("nova", Color.SKY_BLUE), false)
		draw_arc(cp, r * (1.5 + 3.0 * _nova), 0, TAU, 40, Color(nc, 0.9 * (1.0 - _nova)), 5.0)
	var face := 0.0
	var best := INF
	for g in _germs:  # the nucleus looks at the nearest germ
		if g.dead_t <= 0.0 and g.pos.distance_to(cp) < best:
			best = g.pos.distance_to(cp)
			face = (g.pos - cp).angle()
	var ttex := CosmeticArt.tex(str(look.get("trail", {}).get("shape", "disc")))
	for f in _fx:  # dash trail, under the cell
		if f.kind == "tdot":
			var lk := CosmeticArt.pdot_look(f)
			var hs: float = lk[0] / 2.0
			draw_texture_rect(ttex, Rect2(f.pos - Vector2(hs, hs), Vector2(hs, hs) * 2.0), false, lk[1])
	CosmeticArt.draw_cell(self, cp, r, look.get("skin", {}), _t, pal, _cell_tex, _disc, _glow, face)
	var oc := CosmeticArt.weapon_color(w, "orbit", pal.get("orbit", Color.LIGHT_BLUE), false)
	for k in 3:
		var op := cp + Vector2.from_angle(_t * 2.4 + TAU * k / 3.0) * r * 2.1
		draw_texture_rect(_disc, Rect2(op - Vector2(11, 11), Vector2(22, 22)), false, Color(oc, 0.35))
		if shape != "disc":
			draw_texture_rect(stex, Rect2(op - Vector2(12, 12), Vector2(24, 24)), false, oc)
		else:
			draw_texture_rect(_disc, Rect2(op - Vector2(8, 8), Vector2(16, 16)), false, oc)
	var bc := CosmeticArt.weapon_color(w, "bolt", pal.get("bolt", Color.WHITE), false)
	for b in _bullets:
		var back: Vector2 = b.vel.normalized() * 7.0
		draw_texture_rect(_disc, Rect2(b.pos - back * 1.6 - Vector2(8, 8), Vector2(16, 16)), false, Color(bc, 0.35))
		var hs := 11.0 if shape != "disc" else 7.0
		draw_texture_rect(stex if shape != "disc" else _disc, Rect2(b.pos - Vector2(hs, hs), Vector2(hs, hs) * 2.0), false, bc)
	if _chain >= 0.0:
		var chc := CosmeticArt.weapon_color(w, "chain", pal.get("chain", Color.MEDIUM_PURPLE), false)
		draw_polyline(_chain_pts, Color(chc, 1.0 - _chain), 4.0)
	var ptex := CosmeticArt.tex(str(look.get("pop", {}).get("shape", "disc")))
	for f in _fx:
		var k: float = f.t / f.life
		match str(f.kind):
			"dot":
				var rr: float = f.r * (1.0 - k)
				draw_texture_rect(_disc, Rect2(f.pos - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(f.color, 1.0 - k))
			"pdot":
				var lk := CosmeticArt.pdot_look(f)
				var tx: Texture2D = ptex if not CosmeticArt.is_default_pop(look.get("pop", {})) else _disc
				var wd: float = lk[0] * lk[2]
				var ht: float = lk[0] / lk[2]
				draw_texture_rect(tx, Rect2(f.pos - Vector2(wd, ht) / 2.0, Vector2(wd, ht)), false, lk[1])
			"kring":
				var rr: float = f.r * (1.0 + 1.6 * k)
				draw_texture_rect(_ring, Rect2(f.pos - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(f.color.lightened(0.3), 0.9 * (1.0 - k)))
