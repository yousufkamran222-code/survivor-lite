class_name CosmeticArt
extends RefCounted
## Draws cosmetics (data/cosmetics.json "look" dictionaries): cell skins,
## pop-style bursts and weapon-style colours/shapes. Shared by WorldView (the
## run), CosmeticPreview (the Style screen) and the menu hero, so an item
## looks the same everywhere. Presentation only.

static var _tex := {}


## White particle texture for a shape name (cached).
static func tex(shape: String) -> Texture2D:
	if not _tex.has(shape):
		match shape:
			"star":
				_tex[shape] = ShapeTextures.star()
			"square":
				_tex[shape] = ShapeTextures.square()
			"heart":
				_tex[shape] = ShapeTextures.heart()
			"coin":
				_tex[shape] = ShapeTextures.coin()
			"diamond":
				_tex[shape] = ShapeTextures.diamond()
			"ring":
				_tex[shape] = ShapeTextures.ring()
			_:
				_tex[shape] = ShapeTextures.disc()
	return _tex[shape]


static func _c(v: Variant, fallback: Color) -> Color:
	return GameData.color(str(v)) if v != null and str(v) != "" else fallback


# ------------------------------------------------------------------ skins

## `t` (seconds) animates the Rainbow skin's colour.
static func body_color(skin: Dictionary, fallback: Color, t: float = 0.0) -> Color:
	var c := _c(skin.get("body"), fallback)
	if skin.get("rainbow", false):
		c = Color.from_hsv(fposmod(t * 0.12, 1.0), 0.42, 1.0)
	c.a = float(skin.get("alpha", 1.0))
	return c


static func nucleus_color(skin: Dictionary, fallback: Color) -> Color:
	return _c(skin.get("nucleus"), fallback)


## Soft coloured glow behind the cell (world coordinates).
static func draw_glow(ci: CanvasItem, glow_tex: Texture2D, p: Vector2, r: float, skin: Dictionary, t: float) -> void:
	if not skin.has("glow"):
		return
	var g := r * (2.3 + 0.12 * sin(t * 2.0))
	ci.draw_texture_rect(glow_tex, Rect2(p - Vector2(g, g), Vector2(g, g) * 2.0), false, Color(_c(skin.glow, Color.WHITE), 0.45))


## Cilia around the membrane (local, unscaled coordinates: the caller sets
## the body transform). `speed_k` 0..1 makes them wave faster.
static func draw_cilia(ci: CanvasItem, r: float, skin: Dictionary, body: Color, t: float, speed_k: float, default_n: int) -> void:
	var n := int(skin.get("cilia", default_n))
	if n <= 0:
		return
	var cc := Color(_c(skin.get("cilia_color"), body), 0.55 if not skin.has("cilia_color") else 0.8)
	var length := float(skin.get("cilia_len", 1.32))
	var w := float(skin.get("cilia_w", 2.0))
	var flame := str(skin.get("pattern", "")) == "flame"
	var tip_c := _c(skin.get("pattern_color"), Color.WHITE)
	for k in n:
		var a := TAU * k / n
		var wave := sin(t * (6.0 + 10.0 * speed_k) + k * 1.7) * 0.35
		var base := Vector2.from_angle(a) * r
		var ln := length + 0.08 * speed_k
		if flame:  # flickering flame tongues
			ln += 0.18 * sin(t * 17.0 + k * 2.3) + 0.1 * sin(t * 29.0 + k)
		var tip := Vector2.from_angle(a + wave * 0.5) * r * ln
		ci.draw_line(base, tip, cc, w)
		if flame:
			ci.draw_circle(tip, w * 0.9, Color(tip_c, 0.8))


## Pattern drawn over the body (local coordinates, after the body texture).
static func draw_pattern(ci: CanvasItem, disc: Texture2D, r: float, skin: Dictionary, t: float) -> void:
	var pc := _c(skin.get("pattern_color"), Color.WHITE)
	match str(skin.get("pattern", "")):
		"spots":
			for s in [[Vector2(0.42, -0.3), 0.16], [Vector2(-0.48, -0.18), 0.12], [Vector2(-0.2, 0.5), 0.14], [Vector2(0.38, 0.42), 0.1], [Vector2(-0.05, -0.58), 0.09]]:
				var sr: float = s[1] * r
				_disc(ci, disc, s[0] * r, sr, Color(pc, 0.75))
		"stars":
			var pts := [Vector2(0.5, -0.35), Vector2(-0.45, -0.4), Vector2(-0.55, 0.3), Vector2(0.3, 0.55), Vector2(0.62, 0.15), Vector2(-0.1, -0.65), Vector2(-0.15, 0.62)]
			for k in pts.size():
				var tw := 0.5 + 0.5 * sin(t * 3.0 + k * 1.9)
				_disc(ci, disc, pts[k] * r, r * (0.04 + 0.04 * tw), Color(pc, 0.4 + 0.6 * tw))
		"sparkle":
			for k in 3:
				var ph := fmod(t * 0.7 + k / 3.0, 1.0)
				var a := k * 2.1 + floorf(t * 0.7 + k / 3.0) * 1.3
				var at := Vector2.from_angle(a) * r * 0.55
				var s := r * 0.32 * sin(ph * PI)
				var c := Color(pc, sin(ph * PI))
				ci.draw_line(at - Vector2(s, 0), at + Vector2(s, 0), c, 2.0)
				ci.draw_line(at - Vector2(0, s), at + Vector2(0, s), c, 2.0)
		"stripes":
			# Tiger stripes: wavy dark bands across the body (chords).
			for k in 5:
				var x := (-0.64 + 0.32 * k) * r
				var h := sqrt(maxf(r * r - x * x, 0.0)) * 0.92
				var bend := r * 0.1 * (1.0 if k % 2 == 0 else -1.0)
				ci.draw_polyline(PackedVector2Array([Vector2(x, -h), Vector2(x + bend, 0.0), Vector2(x, h)]), Color(pc, 0.75), r * 0.12)
		"shine":
			# Chrome: a bright highlight sweeping round the rim, plus a glint.
			var a := fmod(t * 1.4, TAU)
			ci.draw_arc(Vector2.ZERO, r * 0.78, a, a + 0.9, 10, Color(pc, 0.75), r * 0.1)
			ci.draw_arc(Vector2.ZERO, r * 0.55, a + PI, a + PI + 0.5, 8, Color(pc, 0.4), r * 0.06)
			_disc(ci, disc, Vector2(-0.38, -0.4) * r, r * 0.12, Color(pc, 0.7))
		"bubbles":
			for k in 4:
				var ph := fmod(t * 0.35 + k * 0.25, 1.0)
				var x := (-0.4 + 0.27 * k) * r
				var y := lerpf(0.55, -0.6, ph) * r
				ci.draw_arc(Vector2(x, y), r * (0.07 + 0.04 * float(k % 2)), 0, TAU, 12, Color(pc, 0.7 * sin(ph * PI)), 1.5)


## Glitch skin: red/cyan ghost copies of the body, offset in short bursts
## (world coordinates; drawn under the real body).
static func draw_glitch(ci: CanvasItem, cell_tex: Texture2D, p: Vector2, q: float, skin: Dictionary, t: float) -> void:
	if str(skin.get("pattern", "")) != "glitch":
		return
	var burst := 1.0 if fmod(t, 1.7) < 0.18 else 0.35
	var o := Vector2(3.0 + 3.0 * burst, 0.0)
	var red := Color(_c(skin.get("pattern_color"), Color("#ff2e88")), 0.45 * burst + 0.15)
	var cyan := Color(nucleus_color(skin, Color.CYAN), 0.45 * burst + 0.15)
	ci.draw_texture_rect(cell_tex, Rect2(p - Vector2(q, q) - o, Vector2(q, q) * 2.0), false, red)
	ci.draw_texture_rect(cell_tex, Rect2(p - Vector2(q, q) + o, Vector2(q, q) * 2.0), false, cyan)


## Glitch nucleus jitter (an offset to add to the nucleus position).
static func nucleus_jitter(skin: Dictionary, t: float, r: float) -> Vector2:
	if str(skin.get("pattern", "")) != "glitch" or fmod(t, 1.7) >= 0.18:
		return Vector2.ZERO
	return Vector2(sin(t * 91.0), cos(t * 77.0)) * r * 0.12


static func _disc(ci: CanvasItem, disc: Texture2D, at: Vector2, rr: float, c: Color) -> void:
	ci.draw_texture_rect(disc, Rect2(at - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, c)


## A whole cell in one call (Style screen preview, menu hero, swatches):
## glow, cilia, body, pattern, nucleus. No weapons or HUD bits.
static func draw_cell(ci: CanvasItem, p: Vector2, r: float, skin: Dictionary, t: float, pal: Dictionary, cell_tex: Texture2D, disc: Texture2D, glow_tex: Texture2D, face: float = 0.0) -> void:
	var body := body_color(skin, pal.get("player", Color.WHITE), t)
	var breathe := 0.03 * float(skin.get("breathe", 1.0)) * sin(t * 2.4)
	var q := r / ShapeTextures.CELL_BODY
	draw_glow(ci, glow_tex, p, r, skin, t)
	draw_glitch(ci, cell_tex, p, q, skin, t)
	ci.draw_set_transform(p, 0.0, Vector2(1.0 + breathe, 1.0 + breathe * 0.5))
	draw_cilia(ci, r, skin, body, t, 0.2, 12)
	ci.draw_texture_rect(cell_tex, Rect2(-q, -q, q * 2.0, q * 2.0), false, body)
	draw_pattern(ci, disc, r, skin, t)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var nr := r * 0.44
	var nc := p + Vector2.from_angle(face) * r * 0.28 + nucleus_jitter(skin, t, r)
	_disc(ci, disc, nc, nr, nucleus_color(skin, pal.get("player_nucleus", Color.CYAN)))
	_disc(ci, disc, nc + Vector2(-0.35, -0.35) * nr, nr * 0.3, Color(1, 1, 1, 0.55))


# ---------------------------------------------------------------- weapons

## A weapon's colour under a weapon style (evolved = the style's evo colour,
## else the evolution's own colour, else the style's base colour).
static func weapon_color(style: Dictionary, weapon: String, base: Color, evolved: bool, evo_color: Variant = null) -> Color:
	if evolved:
		if style.get("evo", {}).has(weapon):
			return _c(style.evo[weapon], base)
		if evo_color != null:
			return evo_color
	return _c(style.get(weapon), base)


static func weapon_shape(style: Dictionary) -> String:
	return str(style.get("shape", "disc"))


# -------------------------------------------------------------------- pops

## True for the default goo pop (WorldView keeps its original burst code).
static func is_default_pop(pop: Dictionary) -> bool:
	return pop.is_empty() or not pop.has("count")


## The particles of one kill under a pop style, as WorldView fx dictionaries:
## a "dot" flash, "pdot" particles (drawn with the style's texture) and an
## optional "kring". `germ` is the dead germ's colour.
static func pop_burst(pop: Dictionary, pos: Vector2, radius: float, germ: Color, speed_mult: float = 1.0) -> Array:
	var out := []
	var flash := _c(pop.get("flash"), Color(1, 1, 1))
	out.append({"kind": "dot", "pos": pos, "vel": Vector2.ZERO, "color": Color(flash, 0.95), "r": radius * float(pop.get("flash_scale", 1.3)), "life": 0.08})
	var cols: Array = pop.get("colors", ["germ"])
	var sp: Array = pop.get("speed", [140, 380])
	var sz: Array = pop.get("size", [3, 6])
	var life := float(pop.get("life", 0.4))
	var same := randi() % cols.size()
	for k in int(pop.get("count", 8)):
		var a := randf() * TAU
		if pop.get("up", false):
			a = -PI / 2.0 + randf_range(-1.1, 1.1)
		var ck: Variant = cols[same if pop.get("same_color", false) and k > 0 else randi() % cols.size()]
		var c := germ if str(ck) == "germ" else GameData.color(str(ck))
		var f := {"kind": "pdot", "pos": pos, "vel": Vector2(cos(a), sin(a)) * randf_range(float(sp[0]), float(sp[1])) * speed_mult,
			"color": c, "r": randf_range(float(sz[0]), float(sz[1])) / 2.0, "life": life * randf_range(0.8, 1.15), "seed": randf() * TAU}
		if pop.has("grav"):
			f["grav"] = float(pop.grav)
		if pop.has("drag"):
			f["drag"] = float(pop.drag)
		if pop.get("flutter", false):
			f["flutter"] = true
		if str(pop.get("shape", "")) == "ring":
			f["grow"] = true
		out.append(f)
	if pop.get("ring", false):
		out.append({"kind": "kring", "pos": pos, "color": _c(pop.get("ring_color"), germ), "r": radius, "life": 0.22})
	return out


## How to draw a "pdot" at its age: [size, colour, aspect].
static func pdot_look(f: Dictionary) -> Array:
	var k: float = f.t / f.life
	var size: float = f.r * 2.0 * ((1.0 + 0.6 * k) if f.has("grow") else (1.0 - 0.45 * k))
	var c: Color = f.color
	c.a = 1.0 - maxf(0.0, (k - 0.55) / 0.45)
	var aspect := 1.0
	if f.has("flutter"):  # confetti: flips as it falls
		aspect = 0.35 + 0.65 * absf(sin(f.t * 14.0 + float(f.seed)))
	return [size, c, aspect]


## The kill sound for a pop style: [sound name ("kill" = the six
## squelches), pitch multiplier, whether the streak/size pitch applies].
## A "scale" (Melody) plays note `n` of it, so a streak of kills is a tune.
static func pop_sound(pop: Dictionary, n: int) -> Array:
	var snd := str(pop.get("sound", "kill"))
	var scale: Array = pop.get("scale", [])
	if not scale.is_empty():
		return [snd, float(scale[posmod(n, scale.size())]) * float(pop.get("pitch", 1.0)), false]
	return [snd, float(pop.get("pitch", 1.0)), true]


# ------------------------------------------------------------------ trails

## Particles a dash trail emits this frame (as "tdot" fx, drawn with the
## trail's shape texture), or [] for a plain afterimage. `body` is the cell
## colour; `dt` scales the spawn count so the trail is the same at any fps.
static func trail_burst(trail: Dictionary, pos: Vector2, body: Color, t: float, dt: float) -> Array:
	var out := []
	if not trail.has("per_frame"):
		return out
	var want := float(trail.per_frame) * dt * 60.0
	var n := int(want) + (1 if randf() < want - floorf(want) else 0)
	var cols: Array = trail.get("colors", ["body"])
	var sz: Array = trail.get("size", [8, 12])
	var sp: Array = trail.get("speed", [0, 0])
	var spread := float(trail.get("spread", 8.0))
	for k in n:
		var c := body
		if trail.get("rainbow", false):
			c = Color.from_hsv(fposmod(t * 1.5 + k * 0.05, 1.0), 0.75, 1.0)
		else:
			var ck := str(cols[randi() % cols.size()])
			c = body if ck == "body" else GameData.color(ck)
		var a := randf() * TAU
		var f := {"kind": "tdot", "pos": pos + Vector2(randf_range(-spread, spread), randf_range(-spread, spread)),
			"vel": Vector2(cos(a), sin(a)) * randf_range(float(sp[0]), float(sp[1])), "color": c,
			"r": randf_range(float(sz[0]), float(sz[1])) / 2.0, "life": float(trail.get("life", 0.4)) * randf_range(0.85, 1.15), "seed": randf() * TAU}
		if trail.has("grav"):
			f["grav"] = float(trail.grav)
		if trail.has("drag"):
			f["drag"] = float(trail.drag)
		if str(trail.get("shape", "")) == "ring":
			f["grow"] = true
		out.append(f)
	return out


## The splat colour for a pop style ("none" = no splat).
static func splat_color(pop: Dictionary, germ: Color) -> Variant:
	var s := str(pop.get("splat", "germ"))
	if s == "none":
		return null
	return germ if s == "germ" else GameData.color(s)
