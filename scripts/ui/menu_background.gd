class_name MenuBackground
extends Control
## Animated main-menu backdrop: a petri dish rim, slowly drifting germs in the
## enemy colours, and a big pulsing hero cell with orbiting antibodies.
## Purely decorative. Every circle is the same disc texture, tinted, so the
## renderer merges them into a few draw calls (draw_circle costs one each,
## which made the menu heavier than a full fight).

static var _disc: Texture2D
static var _glow: Texture2D
static var _blob: Texture2D  # shaded germ atlas (8 eye directions)
const BLOB_DIRS := 8

var pal: Dictionary
var germ_colors: Array = []
var _germs: Array = []  # {p, v, r, c, phase}
var _t := 0.0
var hero_y := 0.36  # hero cell centre, as a fraction of height
var hero_x := 0.5  # ... and of width (the landscape menu puts it in the left column)
var hero_scale := 1.0  # landscape menu: a bigger hero
# Overhaul dark-field look (balance.overhaul.art "darkfield"): the slide floor,
# the rim-lit germ atlas (one row per enemy type) and the rim-lit player cell.
var darkfield := false
var _df_floor: Texture2D
var _df_germs: Texture2D
var _df_cell: Texture2D
var _germ_rows := 1
var show_hero := true
var look := {}  # equipped cosmetics (Cosmetics.look): the hero wears your skin colours and weapon style


func setup(palette: Dictionary, enemy_defs: Array, dark_field: bool = false) -> void:
	pal = palette
	darkfield = dark_field
	var rows := []
	for i in enemy_defs.size():
		var e: Dictionary = enemy_defs[i]
		if e.behavior != "boss":
			germ_colors.append(GameData.color(e.color))
			rows.append(i)
	_germ_rows = enemy_defs.size()
	if darkfield:
		_df_floor = load("res://assets/processed/overhaul/bg_df.png")
		_df_germs = load("res://assets/processed/overhaul/germs_df.png")
		_df_cell = load("res://assets/processed/overhaul/player_df.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 22:
		# depth 0 = far (small, slow, out of focus) .. 1 = near (big, faster, sharp).
		var depth := rng.randf()
		_germs.append({
			"p": Vector2(rng.randf(), rng.randf()), "v": Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * lerpf(0.004, 0.02, depth),
			"r": lerpf(10.0, 30.0, depth), "c": germ_colors[k % germ_colors.size()], "row": rows[k % rows.size()], "phase": rng.randf() * TAU, "depth": depth,
		})
	_germs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.depth < b.depth)  # far first


func _ready() -> void:
	if _disc == null:
		_disc = ShapeTextures.disc(128)
		_glow = ShapeTextures.glow(64)
		_blob = ShapeTextures.blob(48, BLOB_DIRS)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	for g in _germs:
		g.p += g.v * delta
		if g.p.x < -0.05: g.p.x = 1.05
		if g.p.x > 1.05: g.p.x = -0.05
		if g.p.y < -0.05: g.p.y = 1.05
		if g.p.y > 1.05: g.p.y = -0.05
	queue_redraw()


func _draw() -> void:
	if pal.is_empty():
		return
	var s := size
	draw_rect(Rect2(Vector2.ZERO, s), pal.background)
	var dc := Vector2(s.x / 2.0, s.y * 0.5)
	var dr := s.x * 0.62
	if darkfield:
		# The slide floor, tiled by hand (a repeat-enabled node would shift the
		# other small textures) and drifting slowly.
		var tw := float(_df_floor.get_width())
		var off := Vector2(fposmod(_t * 6.0, tw), fposmod(_t * 3.0, tw))
		var y := -off.y
		while y < s.y:
			var x := -off.x
			while x < s.x:
				draw_texture_rect(_df_floor, Rect2(x, y, tw, tw), false)
				x += tw
			y += tw
	else:
		# Dish: soft glow and glass rim.
		_disc_at(dc, dr, Color(pal.background_cells, 0.55))
	# Drifting germs at different depths (dimmed so the UI stays readable):
	# far ones are soft out-of-focus glows, near ones shaded germs whose eyes
	# look where they drift. One quad each.
	for g in _germs:
		var p := Vector2(g.p.x * s.x, g.p.y * s.y)
		var wob := 1.0 + 0.06 * sin(_t * 2.0 + g.phase)
		var c: Color = g.c
		var r: float = g.r * wob
		if g.depth < 0.45:
			var gr := r * 2.2
			draw_texture_rect(_glow, Rect2(p - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(c, 0.22))
		else:
			var dir: Vector2 = g.v
			if darkfield:  # rim-lit germ of its own type (16 facings, body = 0.6 of the frame)
				var fw2 := float(_df_germs.get_height()) / _germ_rows
				var f16 := posmod(roundi(dir.angle() / TAU * 16.0), 16)
				var q := r / 0.6
				draw_texture_rect_region(_df_germs, Rect2(p - Vector2(q, q), Vector2(q, q) * 2.0), Rect2(f16 * fw2, int(g.row) * fw2, fw2, fw2), Color(c, lerpf(0.45, 0.85, g.depth)))
				continue
			var frame := posmod(roundi(dir.angle() / TAU * BLOB_DIRS), BLOB_DIRS)
			var fw := float(_blob.get_height())
			draw_texture_rect_region(_blob, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), Rect2(frame * fw, 0, fw, fw), Color(c, lerpf(0.35, 0.6, g.depth)))
	if show_hero:
		_draw_hero()
	# Rim last: lines break the texture batch, so draw them once at the end.
	if not darkfield:
		draw_arc(dc, dr, 0, TAU, 96, Color(0.75, 0.85, 1.0, 0.18), 8.0)


func _disc_at(p: Vector2, r: float, c: Color) -> void:
	draw_texture_rect(_disc, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, c)


func _draw_hero() -> void:
	var s := size
	# Hero cell with orbiting antibodies.
	var hc := Vector2(s.x * hero_x, s.y * hero_y)
	var hk := hero_scale
	var hr := 46.0 * hk * (1.0 + 0.04 * sin(_t * 2.2))
	var sl := 230.0 * hk * (1.0 + 0.05 * sin(_t * 1.3))  # soft spotlight behind the hero
	var skin: Dictionary = look.get("skin", {})
	var body := CosmeticArt.body_color(skin, pal.player, _t)
	var nuc := CosmeticArt.nucleus_color(skin, pal.player_nucleus)
	var halo: Color = GameData.color(str(skin.glow)) if skin.has("glow") else pal.player_nucleus
	var orb := CosmeticArt.weapon_color(look.get("weapon", {}), "orbit", pal.orbit, false)
	draw_texture_rect(_glow, Rect2(hc - Vector2(sl, sl), Vector2(sl, sl) * 2.0), false, Color(halo, 0.16))
	_disc_at(hc, hr + 22.0 * hk, Color(halo, 0.08))
	if darkfield:  # the rim-lit in-game cell (body = 0.78 of the texture)
		var q := hr / 0.78
		draw_texture_rect(_df_cell, Rect2(hc - Vector2(q, q), Vector2(q, q) * 2.0), false, body)
	else:
		_disc_at(hc, hr + 6.0 * hk, Color(body, 0.25 * body.a))
		_disc_at(hc, hr, body)
	_disc_at(hc + Vector2(cos(_t * 0.7), sin(_t * 0.9)) * 6.0 * hk, hr * 0.42, nuc)
	for k in 3:
		var a := _t * 1.6 + TAU * k / 3.0
		var op := hc + Vector2(cos(a), sin(a)) * (hr + 46.0 * hk)
		_disc_at(op, 15.0 * hk, Color(orb, 0.35))
		_disc_at(op, 11.0 * hk, orb)
