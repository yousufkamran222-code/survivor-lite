class_name UiKit
extends RefCounted
## Builds the UI theme and common widgets in code (no .tscn editing needed).
## Sizes are for a 720x1280 portrait canvas; buttons are thumb-sized.
##
## Look (2026-11-06, "glossy chunky"): buttons are generated glossy 9-slice
## textures (dark outline, lighter top with a gloss band, a thick darker 3D
## bottom edge that sinks when pressed); titles, buttons, numbers and chips
## use Lilita One (OFL) with a thick dark outline; cards are
## lighter than the deep background, with a border and a soft shadow.

const DISPLAY_FONT := "res://assets/raw/lilita_one/LilitaOne-Regular.ttf"  # OFL (Yousuf allowed OFL fonts, 2026-11-06)
const OUTLINE := Color("#140a24")  # outline around display text and buttons
## Button kinds: [face colour, text colour].
const KINDS := {
	"primary": [Color("#ffd166"), Color("#3a2200")],
	"secondary": [Color("#6a54c8"), Color("#ffffff")],
	"positive": [Color("#3ddc84"), Color("#ffffff")],
	"danger": [Color("#ff5d73"), Color("#ffffff")],
}
const EDGE := 9  # px of 3D bottom edge (3 when pressed)

static var _display: Font
static var _gloss := {}


static func display_font() -> Font:
	if _display == null:
		var f: FontFile = load(DISPLAY_FONT)
		if f != null:
			f.fallbacks = [ThemeDB.fallback_font]  # any glyph Lilita lacks (arrows etc.)
		_display = f if f != null else ThemeDB.fallback_font
	return _display


static func make_theme(pal: Dictionary) -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var face: Color = KINDS.secondary[0]
	for s in ["normal", "hover", "focus"]:
		t.set_stylebox(s, "Button", gloss(face))
	t.set_stylebox("pressed", "Button", gloss(face, true))
	t.set_stylebox("hover_pressed", "Button", gloss(face, true))
	t.set_stylebox("disabled", "Button", gloss(face.lerp(Color("#4a4462"), 0.7)))
	t.set_font("font", "Button", display_font())
	t.set_constant("outline_size", "Button", 8)
	t.set_color("font_outline_color", "Button", OUTLINE)
	t.set_color("font_color", "Button", pal.text)
	t.set_color("font_hover_color", "Button", pal.text)
	t.set_color("font_pressed_color", "Button", pal.text)
	t.set_color("font_focus_color", "Button", pal.text)
	t.set_color("font_disabled_color", "Button", Color(pal.text, 0.5))
	t.set_stylebox("panel", "PanelContainer", card(pal.ui_panel))
	t.set_color("font_color", "Label", pal.text)
	return t


## A card surface: lighter than the background, a thin light border, a soft
## shadow underneath.
static func card(bg: Color, border: Color = Color(1, 1, 1, 0.1), radius: int = 24, margin: int = 22) -> StyleBoxFlat:
	var sb := _box(bg, radius, margin)
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	return sb


## Gives a button the glossy chunky look: kind = primary | secondary |
## positive | danger (or pass `face` for any colour), display font + outline.
static func style_button(b: Button, kind: String = "secondary", font_size: int = 0, face: Color = Color(0, 0, 0, 0)) -> Button:
	var k: Array = KINDS.get(kind, KINDS.secondary)
	var c: Color = face if face.a > 0.0 else k[0]
	var fc: Color = k[1]
	for s in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(s, gloss(c))
	b.add_theme_stylebox_override("pressed", gloss(c, true))
	b.add_theme_stylebox_override("hover_pressed", gloss(c, true))
	b.add_theme_stylebox_override("disabled", gloss(c.lerp(Color("#4a4462"), 0.7)))
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(n, fc)
	b.add_theme_font_override("font", display_font())
	b.add_theme_constant_override("outline_size", 8 if fc.v > 0.5 else 0)
	if font_size > 0:
		b.add_theme_font_size_override("font_size", font_size)
	press_feedback(b)
	return b


## Glossy 9-slice style for a face colour (cached). Pressed = a short 3D edge
## and the content pushed down, so the button "sinks".
static func gloss(face: Color, pressed: bool = false) -> StyleBoxTexture:
	var key := "%s|%s" % [face.to_html(), pressed]
	if _gloss.has(key):
		return _gloss[key]
	var edge := 3 if pressed else EDGE
	var r := 22
	var w := 64
	var h := 64 + edge
	var body_h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var out := OUTLINE
	var side := face.darkened(0.38)
	var top := face.lightened(0.24)
	for y in h:
		for x in w:
			var d := _rr_dist(Vector2(x + 0.5, y + 0.5), Vector2(w, h), r)
			if d > 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var a := clampf(0.5 - d, 0.0, 1.0)
			var c: Color
			if d > -3.0:
				c = out
			elif y >= body_h - 2:
				c = side  # the 3D edge
			else:
				var t := float(y) / body_h
				c = top.lerp(face, t)
				# Gloss: a soft light band in the upper part of the face.
				var gd := _rr_dist(Vector2(x + 0.5, y + 0.5) - Vector2(7, 6), Vector2(w - 14, body_h * 0.42), r - 8)
				if gd < 0.0:
					c = c.lerp(Color.WHITE, 0.36 * clampf(-gd / 3.0, 0.0, 1.0) * (1.0 - t * 1.6))
			img.set_pixel(x, y, Color(c, c.a * a))
	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = r + 2
	sb.texture_margin_right = r + 2
	sb.texture_margin_top = r + 2
	sb.texture_margin_bottom = r + edge + 2
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10 + (EDGE - edge)
	sb.content_margin_bottom = 10 + edge
	_gloss[key] = sb
	return sb


## Signed distance to a rounded rectangle at the origin of size `size`.
static func _rr_dist(p: Vector2, size: Vector2, r: float) -> float:
	var c := size / 2.0
	var q := (p - c).abs() - (c - Vector2(r, r))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


static func _box(c: Color, radius: int, margin: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	return sb


## Full-screen dimmed overlay with a centred column. Returns [root, column].
static func overlay(parent: Node, dim: float = 0.72) -> Array:
	var root := ColorRect.new()
	root.color = Color(0, 0, 0, dim)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	parent.add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.custom_minimum_size = Vector2(600, 0)
	center.add_child(col)
	return [root, col]


## Text label. 34 px and up counts as a title/number: display font with a
## thick dark outline (the chunky look); smaller text stays in the readable
## body font.
static func label(text: String, size: int = 30, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 34:
		l.add_theme_font_override("font", display_font())
		l.add_theme_constant_override("outline_size", maxi(8, size / 5))
		l.add_theme_color_override("font_outline_color", OUTLINE)
	return l


## Puts any label in the chunky display font with a dark outline.
static func display(l: Label, outline: int = 6) -> Label:
	l.add_theme_font_override("font", display_font())
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_outline_color", OUTLINE)
	return l


static func button(text: String, on_press: Callable, height: float = 96.0, kind: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if kind != "":
		style_button(b, kind)
	b.custom_minimum_size = Vector2(0, height)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		on_press.call())
	press_feedback(b)
	return b


# ------------------------------------------------- motion and small widgets

## Squash and spring: a button squeezes while held and bounces back a
## little past full size on release (every glossy button gets this; safe to
## call twice).
static func press_feedback(b: Control) -> void:
	if b.has_meta("_press_fb"):
		return
	b.set_meta("_press_fb", true)
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	b.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			var tw := b.create_tween()
			if e.pressed:
				tw.tween_property(b, "scale", Vector2(0.93, 0.9), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			else:
				tw.tween_property(b, "scale", Vector2(1.05, 1.05), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## Shows an overlay with a short fade; its column's parts pop in one after
## another.
static func reveal(overlay: Array) -> void:
	var root: Control = overlay[0]
	var col: Control = overlay[1]
	root.visible = true
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.16)
	fade_in(col)


## Entrance for a screen built in place (menu, shop, Lab, settings ...): a
## container's children pop in one after another (fade + springy scale);
## anything else fades and settles as one.
static func fade_in(c: Control, delay: float = 0.0) -> void:
	if (c is BoxContainer or c is GridContainer) and c.get_child_count() > 1:
		stagger(c, delay)
		return
	_pop(c, delay, 0.97)


## Staggered entrance of a container's children (at most `max_items` get
## their own delay; the rest arrive with the last).
static func stagger(c: Control, delay: float = 0.0, step: float = 0.045, max_items: int = 10) -> void:
	var k := 0
	for ch in c.get_children():
		if ch is Control and ch.visible:
			_pop(ch, delay + step * mini(k, max_items), 0.9)
			k += 1


static func _pop(c: Control, delay: float, from_scale: float) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(from_scale, from_scale)
	if not c.resized.is_connected(_center_pivot.bind(c)):
		c.resized.connect(_center_pivot.bind(c))
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(delay).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, 0.32).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size / 2.0


## Rounded panel with an optional coloured border.
static func panel(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 20, margin: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	# PASS, not the default STOP: panels inside a DragScroll must let the drag
	# through, or the list only scrolls from the gaps between them.
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_theme_stylebox_override("panel", card(bg, border if border.a > 0.0 else Color(1, 1, 1, 0.1), radius, margin))
	return p


## Small pill with text ("NEW", "EVOLVES", "x2 picks").
static func chip(text: String, bg: Color, fg: Color = Color(0.1, 0.06, 0.15), size: int = 17) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _box(bg, 12, 8)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, fg)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", display_font())
	p.add_child(l)
	return p


## Counts a label up from `from` to `to` (format with one %d), ticking.
## Counts a label from `from` to `to`. Returns the tween (null if there was
## nothing to count) so a caller can stop it early.
static func count_up(l: Label, from: int, to: int, dur: float, fmt: String, delay: float = 0.0, tick_pitch: float = 1.0) -> Tween:
	l.text = fmt % from
	if to <= from:
		l.text = fmt % to
		return null
	var last := [from]
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(f: float) -> void:
		var v := roundi(f)
		if v != last[0]:
			last[0] = v
			l.text = fmt % v
			Sfx.play("pickup", 0.0, tick_pitch + 0.5 * (f - from) / maxf(to - from, 1.0)), float(from), float(to), dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return tw

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func fmt_time(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]


## Level pips: filled dots for owned levels, a bright one for the level you
## are about to get, hollow for the rest.
class Pips:
	extends Control
	var have := 0
	var next := 0
	var total := 5
	var accent := Color.WHITE

	func _draw() -> void:
		for k in total:
			var p := Vector2(9.0 + k * 20.0, size.y / 2.0)
			if k < have:
				draw_circle(p, 6.0, Color(accent, 0.9))
			elif k < next:
				draw_circle(p, 7.0, Color.WHITE)
			else:
				draw_arc(p, 6.0, 0, TAU, 16, Color(1, 1, 1, 0.35), 2.0)


## A card-style button: icon on the left, then title + level pips, body and
## an optional gold hint. The whole card is the tap target.
static func icon_card(icon: Control, title: String, body: String, hint: String, have: int, next: int, total: int, accent: Color, on_press: Callable, height: float = 150.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, height)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3d2d6b")
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(3)
	sb.border_color = Color(accent, 0.75)
	b.add_theme_stylebox_override("normal", sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color("#5a45a0")
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("hover", sb)
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		on_press.call())
	press_feedback(b)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	b.add_child(m)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 16)
	m.add_child(h)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var t := _card_label(title, 26, Color.WHITE)
	v.add_child(t)
	if total > 1:
		var pips := Pips.new()
		pips.have = have
		pips.next = next
		pips.total = total
		pips.accent = accent
		pips.custom_minimum_size = Vector2(total * 20.0, 16)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pips)
	v.add_child(_card_label(body, 21, Color(1, 1, 1, 0.85)))
	if hint != "":
		v.add_child(_card_label(hint, 19, Color("#ffd166")))
	return b


static func _card_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## An icon on a soft glowing disc (level-up and chest cards).
static func glow_icon(key: String, col: Color, px: float, evolved: bool = false) -> GlowIcon:
	var g := GlowIcon.new()
	g.key = key
	g.color = col
	g.evolved = evolved
	g.custom_minimum_size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


class GlowIcon:
	extends Control
	var key := ""
	var color := Color.WHITE
	var evolved := false

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color(color, 0.10))
		draw_circle(c, r * 0.82, Color(color, 0.14))
		IconArt.draw(self, key, c, r * 1.3, color, evolved)
