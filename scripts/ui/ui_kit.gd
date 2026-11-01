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
