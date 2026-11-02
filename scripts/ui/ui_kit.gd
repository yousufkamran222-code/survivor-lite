class_name UiKit
extends RefCounted
## Builds the UI theme and common widgets in code (no .tscn editing needed).
## Sizes are for a 720x1280 portrait canvas; buttons are thumb-sized.


static func make_theme(pal: Dictionary) -> Theme:
	var t := Theme.new()
	t.default_font_size = 30
	var normal := _box(pal.ui_button, 18)
	var pressed := _box(pal.ui_button_pressed, 18)
	var disabled := _box(Color(pal.ui_button, 0.45), 18)
	for s in ["normal", "hover", "focus"]:
		t.set_stylebox(s, "Button", normal)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", pal.text)
	t.set_color("font_hover_color", "Button", pal.text)
	t.set_color("font_pressed_color", "Button", pal.text)
	t.set_color("font_focus_color", "Button", pal.text)
	t.set_color("font_disabled_color", "Button", Color(pal.text, 0.5))
	t.set_stylebox("panel", "PanelContainer", _box(pal.ui_panel, 24, 28))
	t.set_color("font_color", "Label", pal.text)
	return t


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


static func label(text: String, size: int = 30, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, height: float = 96.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		on_press.call())
	return b


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
