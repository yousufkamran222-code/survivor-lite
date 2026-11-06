class_name IconArt
extends RefCounted
## Flat vector icons for upgrades, evolutions and permanent upgrades, drawn
## with CanvasItem primitives (no image files, matches the shape art style).
## draw(ci, key, center, size, color): a dark disc with a coloured rim and a
## white/coloured glyph. Unknown keys fall back to a simple dot.

## Meta (permanent) upgrades reuse the glyph of the matching stat.
const META_KEYS := {
	"max_hp": "vitality", "might": "might", "haste": "haste", "armor": "armor",
	"regen": "regen", "move": "swift", "magnet": "magnet", "xp_gain": "growth",
	"gold_gain": "gold", "amount": "multishot", "dash_cd": "adrenaline",
	"dash_charges": "flagella2", "dash_damage": "lunge", "dash_decoy": "afterimage",
	"convert": "viral",
	"evo_bolt": "bolt", "evo_orbit": "orbit", "evo_nova": "nova", "evo_chain": "chain",
}

const COLORS := {
	"bolt": Color("#e8fbff"), "orbit": Color("#9be7ff"), "nova": Color("#7cc6ff"), "chain": Color("#c8a6ff"),
	"dash": Color("#5ce1e6"), "swarm": Color("#7cff9b"), "passive": Color("#ffd166"), "gold": Color("#ffd166"),
}


## Category colour for an upgrade id / def.
static func color_for(def: Dictionary) -> Color:
	var id: String = def.get("id", "")
	if COLORS.has(id):
		return COLORS[id]
	if def.has("modes"):
		return COLORS.swarm
	if id in ["flagella2", "lunge", "afterimage", "adrenaline", "volatile"]:
		return COLORS.dash
	return COLORS.passive


static func draw(ci: CanvasItem, key: String, c: Vector2, size: float, col: Color, evolved: bool = false) -> void:
	var r := size * 0.5
	ci.draw_circle(c, r, Color(0.08, 0.05, 0.14, 0.92))
	ci.draw_arc(c, r - 2.0, 0, TAU, 32, col, maxf(2.0, size * 0.06))
	var k := r * 0.55
	var w := Color(1, 1, 1, 0.95)
	var lw := maxf(2.0, size * 0.07)
	match key:
		"bolt":
			ci.draw_line(c + Vector2(-k, k * 0.5), c + Vector2(k * 0.3, -k * 0.2), Color(col, 0.6), lw * 1.6)
			ci.draw_circle(c + Vector2(k * 0.45, -k * 0.3), k * 0.38, w)
		"orbit":
			ci.draw_arc(c, k * 0.85, 0, TAU, 24, Color(col, 0.5), lw * 0.6)
			ci.draw_circle(c, k * 0.25, w)
			for a in [0.3, 2.4, 4.5]:
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * k * 0.85, k * 0.24, col)
		"nova":
			ci.draw_circle(c, k * 0.22, w)
			ci.draw_arc(c, k * 0.55, 0, TAU, 24, col, lw)
			ci.draw_arc(c, k * 0.95, 0, TAU, 28, Color(col, 0.6), lw * 0.8)
		"chain":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-k, -k * 0.6), c + Vector2(-k * 0.2, k * 0.1), c + Vector2(k * 0.1, -k * 0.4), c + Vector2(k, k * 0.6)]), col, lw * 1.2)
			ci.draw_circle(c + Vector2(k, k * 0.6), k * 0.2, w)
		"might":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k * 0.75, 0), c + Vector2(-k * 0.75, 0)]), col)
			ci.draw_rect(Rect2(c + Vector2(-k * 0.3, 0), Vector2(k * 0.6, k * 0.85)), col)
		"haste":
			ci.draw_arc(c, k * 0.9, 0, TAU, 28, w, lw)
			ci.draw_line(c, c + Vector2(0, -k * 0.65), col, lw)
			ci.draw_line(c, c + Vector2(k * 0.5, k * 0.15), col, lw)
		"swift":
			for row in [-0.5, 0.0, 0.5]:
				var pts := PackedVector2Array()
				for t in 7:
					var x := -k + t * k / 3.0
					pts.append(c + Vector2(x, row * k + sin(t * 1.4) * k * 0.15))
				ci.draw_polyline(pts, col if row == 0.0 else Color(col, 0.6), lw)
		"vitality":
			ci.draw_rect(Rect2(c - Vector2(k * 0.85, k * 0.28), Vector2(k * 1.7, k * 0.56)), col)
			ci.draw_rect(Rect2(c - Vector2(k * 0.28, k * 0.85), Vector2(k * 0.56, k * 1.7)), col)
		"regen":
			ci.draw_circle(c + Vector2(-k * 0.38, -k * 0.2), k * 0.45, col)
			ci.draw_circle(c + Vector2(k * 0.38, -k * 0.2), k * 0.45, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.82, -k * 0.05), c + Vector2(k * 0.82, -k * 0.05), c + Vector2(0, k * 0.85)]), col)
		"magnet":
			ci.draw_arc(c + Vector2(0, -k * 0.1), k * 0.65, 0, PI, 20, col, lw * 2.2)
			ci.draw_rect(Rect2(c + Vector2(-k * 0.85, -k * 0.75), Vector2(k * 0.4, k * 0.6)), w)
			ci.draw_rect(Rect2(c + Vector2(k * 0.45, -k * 0.75), Vector2(k * 0.4, k * 0.6)), w)
		"multishot":
			for a in [-0.45, 0.0, 0.45]:
				var d := Vector2(sin(a), -cos(a))
				ci.draw_line(c + Vector2(0, k * 0.6), c + Vector2(0, k * 0.6) + d * k * 1.2, Color(col, 0.7), lw)
				ci.draw_circle(c + Vector2(0, k * 0.6) + d * k * 1.25, k * 0.2, w)
		"flagella2":
			for dx in [-0.45, 0.25]:
				var o := c + Vector2(dx * k, 0)
				ci.draw_polyline(PackedVector2Array([o + Vector2(-k * 0.35, -k * 0.6), o + Vector2(k * 0.25, 0), o + Vector2(-k * 0.35, k * 0.6)]), col, lw * 1.3)
		"lunge":
			ci.draw_line(c + Vector2(-k, 0), c + Vector2(k * 0.6, 0), col, lw * 1.5)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(k, 0), c + Vector2(k * 0.45, -k * 0.4), c + Vector2(k * 0.45, k * 0.4)]), w)
			for x in [-0.6, -0.2]:
				ci.draw_line(c + Vector2(x * k, -k * 0.5), c + Vector2(x * k + k * 0.2, -k * 0.1), w, lw * 0.7)
				ci.draw_line(c + Vector2(x * k, k * 0.5), c + Vector2(x * k + k * 0.2, k * 0.1), w, lw * 0.7)
		"afterimage":
			ci.draw_circle(c + Vector2(-k * 0.35, 0), k * 0.5, Color(col, 0.35))
			ci.draw_circle(c + Vector2(k * 0.3, 0), k * 0.5, w)
		"volatile":
			# A cell bursting into shards.
			ci.draw_circle(c, k * 0.32, col)
			for t in 8:
				var a := TAU * t / 8.0 + 0.2
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * k * 0.5, c + d * k * (0.85 if t % 2 == 0 else 0.7), w if t % 2 == 0 else col, lw * 1.2)
		"outbreak":
			# A biohazard-ish burst: ring of three blobs around a core.
			ci.draw_arc(c, k * 0.8, 0, TAU, 28, col, lw)
			for t in 3:
				var a := -PI / 2.0 + TAU * t / 3.0
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * k * 0.42, k * 0.26, col)
			ci.draw_circle(c, k * 0.16, w)
		"order_guard":
			# A shield with a cell inside: hold the ring around you.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.75, -k * 0.8), c + Vector2(k * 0.75, -k * 0.8), c + Vector2(k * 0.75, 0), c + Vector2(0, k * 0.95), c + Vector2(-k * 0.75, 0)]), col)
			ci.draw_circle(c + Vector2(0, -k * 0.1), k * 0.3, w)
		"order_hunt":
			# Crosshair: go out and fight.
			ci.draw_arc(c, k * 0.62, 0, TAU, 24, col, lw * 1.2)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * k * 0.3, c + d * k * 0.98, w, lw)
			ci.draw_circle(c, k * 0.14, col)
		"order_harvest":
			# An XP gem with an arrow pulling it in.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(k * 0.15, -k * 0.85), c + Vector2(k * 0.7, -k * 0.2), c + Vector2(k * 0.15, k * 0.45), c + Vector2(-k * 0.4, -k * 0.2)]), col)
			ci.draw_line(c + Vector2(-k * 0.05, k * 0.25), c + Vector2(-k * 0.7, k * 0.85), w, lw * 1.2)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.85, k * 1.0), c + Vector2(-k * 0.85, k * 0.45), c + Vector2(-k * 0.3, k * 1.0)]), w)
		"adrenaline":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(k * 0.2, -k), c + Vector2(-k * 0.5, k * 0.1), c + Vector2(0, k * 0.1), c + Vector2(-k * 0.2, k), c + Vector2(k * 0.5, -k * 0.1), c + Vector2(0, -k * 0.1)]), col)
		"viral":
			for t in 8:
				var a := TAU * t / 8.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * k * 0.5, c + Vector2(cos(a), sin(a)) * k * 0.95, col, lw)
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * k * 0.95, k * 0.12, col)
			ci.draw_circle(c, k * 0.5, w)
		"hive":
			var hex := PackedVector2Array()
			for t in 7:
				var a := TAU * t / 6.0 + PI / 6.0
				hex.append(c + Vector2(cos(a), sin(a)) * k * 0.85)
			ci.draw_polyline(hex, col, lw * 1.3)
			ci.draw_circle(c, k * 0.25, w)
		"incubate":
			var egg := PackedVector2Array()
			for t in 24:
				var a := TAU * t / 24.0
				egg.append(c + Vector2(cos(a) * k * 0.62, sin(a) * k * (0.85 if sin(a) < 0.0 else 0.7)))
			ci.draw_colored_polygon(egg, w)
			ci.draw_circle(c + Vector2(0, k * 0.1), k * 0.22, col)
		"armor":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.75, -k * 0.75), c + Vector2(k * 0.75, -k * 0.75), c + Vector2(k * 0.75, 0), c + Vector2(0, k * 0.95), c + Vector2(-k * 0.75, 0)]), col)
		"growth":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -k), c + Vector2(k * 0.7, 0), c + Vector2(0, k), c + Vector2(-k * 0.7, 0)]), col)
		"gold":
			ci.draw_circle(c, k * 0.85, col)
			ci.draw_arc(c, k * 0.55, 0, TAU, 20, Color(0.45, 0.3, 0.05), lw)
		"mode_infection":
			# A dish with a claimed wedge of land.
			ci.draw_arc(c, k * 0.9, 0, TAU, 28, w, lw)
			var wedge := PackedVector2Array([c])
			for t in 13:
				var a := -PI * 0.15 + PI * 1.1 * t / 12.0
				wedge.append(c + Vector2(cos(a), sin(a)) * k * 0.78)
			ci.draw_colored_polygon(wedge, Color(col, 0.85))
		"mode_swarm":
			ci.draw_circle(c, k * 0.32, w)
			for t in 6:
				var a := TAU * t / 6.0
				ci.draw_arc(c + Vector2(cos(a), sin(a)) * k * 0.78, k * 0.2, 0, TAU, 12, col, lw * 0.8)
		"mode_nucleus":
			# The nucleus ringed by tower pads.
			ci.draw_circle(c, k * 0.42, col)
			ci.draw_circle(c, k * 0.18, w)
			for t in 6:
				var a := -PI / 2.0 + TAU * t / 6.0
				ci.draw_arc(c + Vector2(cos(a), sin(a)) * k * 0.8, k * 0.14, 0, TAU, 10, w, lw * 0.8)
		"mode_classic":
			ci.draw_arc(c, k * 0.7, 0, TAU, 24, col, lw)
			for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(c + d * k * 0.45, c + d * k * 1.0, w, lw)
			ci.draw_circle(c, k * 0.14, w)
		"settings":
			# A cog: ring with teeth and a hole.
			for t in 8:
				var a := TAU * t / 8.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * k * 0.45, c + d * k * 0.88, col, lw * 2.2)
			ci.draw_circle(c, k * 0.62, col)
			ci.draw_circle(c, k * 0.26, Color(0.12, 0.08, 0.22))
		"lab":
			# A round flask with bubbling liquid.
			ci.draw_rect(Rect2(c + Vector2(-k * 0.18, -k * 0.95), Vector2(k * 0.36, k * 0.5)), w)
			ci.draw_circle(c + Vector2(0, k * 0.25), k * 0.62, w)
			ci.draw_circle(c + Vector2(0, k * 0.32), k * 0.48, col)
			ci.draw_circle(c + Vector2(-k * 0.15, k * 0.2), k * 0.1, w)
			ci.draw_circle(c + Vector2(k * 0.18, k * 0.42), k * 0.07, w)
		"gene":
			# A short double helix.
			var a1 := PackedVector2Array()
			var a2 := PackedVector2Array()
			for t in 13:
				var y := -k * 0.9 + k * 1.8 * t / 12.0
				var x := sin(t / 12.0 * TAU) * k * 0.5
				a1.append(c + Vector2(x, y))
				a2.append(c + Vector2(-x, y))
				if t % 2 == 1:
					ci.draw_line(c + Vector2(x, y), c + Vector2(-x, y), Color(w, 0.6), lw * 0.6)
			ci.draw_polyline(a1, col, lw)
			ci.draw_polyline(a2, w, lw)
		"stasis":
			# An hourglass.
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.6, -k * 0.85), c + Vector2(k * 0.6, -k * 0.85), c + Vector2(0, 0)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0), c + Vector2(k * 0.6, k * 0.85), c + Vector2(-k * 0.6, k * 0.85)]), w)
			ci.draw_line(c + Vector2(-k * 0.75, -k * 0.9), c + Vector2(k * 0.75, -k * 0.9), w, lw)
			ci.draw_line(c + Vector2(-k * 0.75, k * 0.9), c + Vector2(k * 0.75, k * 0.9), w, lw)
		"engulf":
			# A big cell swallowing a small germ.
			ci.draw_arc(c, k * 0.9, 0, TAU, 28, col, lw * 1.3)
			ci.draw_circle(c + Vector2(k * 0.25, k * 0.15), k * 0.3, w)
			ci.draw_circle(c + Vector2(-k * 0.3, -k * 0.25), k * 0.14, col)
		"cloak":
			# A dashed cell outline with an eye.
			for t in 8:
				var a := TAU * t / 8.0
				ci.draw_arc(c, k * 0.9, a, a + TAU / 16.0, 4, col, lw)
			ci.draw_arc(c, k * 0.4, PI * 0.15, PI * 0.85, 10, w, lw)
			ci.draw_arc(c, k * 0.4, PI * 1.15, PI * 1.85, 10, w, lw)
			ci.draw_circle(c, k * 0.16, w)
		"mitosis":
			# Two cells pinching apart.
			ci.draw_circle(c + Vector2(-k * 0.42, 0), k * 0.48, col)
			ci.draw_circle(c + Vector2(k * 0.42, 0), k * 0.48, w)
			ci.draw_circle(c + Vector2(-k * 0.42, 0), k * 0.16, w)
			ci.draw_circle(c + Vector2(k * 0.42, 0), k * 0.16, col)
		"keystone":
			var star := PackedVector2Array()
			for t in 10:
				var a := -PI / 2.0 + TAU * t / 10.0
				star.append(c + Vector2(cos(a), sin(a)) * k * (0.95 if t % 2 == 0 else 0.42))
			ci.draw_colored_polygon(star, col)
			ci.draw_circle(c, k * 0.2, w)
		"trophy":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.6, -k * 0.75), c + Vector2(k * 0.6, -k * 0.75), c + Vector2(k * 0.4, -k * 0.05), c + Vector2(-k * 0.4, -k * 0.05)]), col)
			ci.draw_circle(c + Vector2(0, -k * 0.1), k * 0.4, col)
			ci.draw_rect(Rect2(c + Vector2(-k * 0.12, k * 0.2), Vector2(k * 0.24, k * 0.35)), col)
			ci.draw_rect(Rect2(c + Vector2(-k * 0.45, k * 0.55), Vector2(k * 0.9, k * 0.22)), w)
		"sound_on", "sound_off":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.8, -k * 0.3), c + Vector2(-k * 0.4, -k * 0.3), c + Vector2(k * 0.1, -k * 0.75), c + Vector2(k * 0.1, k * 0.75), c + Vector2(-k * 0.4, k * 0.3), c + Vector2(-k * 0.8, k * 0.3)]), w)
			if key == "sound_on":
				ci.draw_arc(c + Vector2(k * 0.1, 0), k * 0.45, -0.9, 0.9, 10, col, lw)
				ci.draw_arc(c + Vector2(k * 0.1, 0), k * 0.75, -0.9, 0.9, 12, col, lw)
			else:
				ci.draw_line(c + Vector2(k * 0.35, -k * 0.4), c + Vector2(k * 0.95, k * 0.4), Color("#ff5d73"), lw)
				ci.draw_line(c + Vector2(k * 0.35, k * 0.4), c + Vector2(k * 0.95, -k * 0.4), Color("#ff5d73"), lw)
		_:
			ci.draw_circle(c, k * 0.5, col)
	if evolved:
		# Gold star badge for evolutions.
		var s := c + Vector2(r * 0.62, -r * 0.62)
		var star := PackedVector2Array()
		for t in 10:
			var a := -PI / 2.0 + TAU * t / 10.0
			star.append(s + Vector2(cos(a), sin(a)) * r * (0.32 if t % 2 == 0 else 0.14))
		ci.draw_colored_polygon(star, COLORS.gold)
