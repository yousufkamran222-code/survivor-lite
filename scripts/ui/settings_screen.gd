class_name SettingsScreen
extends VBoxContainer
## Settings (from the main menu and the pause screen): music and effects
## volume, vibration, screen shake, frame rate and the FPS readout. Values
## live in Save (profile.settings) and apply immediately through `on_change`;
## they're written to disk when the screen closes.

var pal: Dictionary
var on_change: Callable  # Main re-applies settings (fps cap, shake, fps readout)
var on_back: Callable
var debug_fps_default := false


func setup(palette: Dictionary, changed: Callable, back: Callable, fps_default: bool) -> void:
	pal = palette
	on_change = changed
	on_back = back
	debug_fps_default = fps_default
	custom_minimum_size = Vector2(600, 0)
	add_theme_constant_override("separation", 16)
	_build()


func _build() -> void:
	UiKit.clear(self)
	add_child(UiKit.label("SETTINGS", 52, pal.ui_accent))
	add_child(_slider_row("Music", Save.music_volume, func(v: float) -> void:
		Save.music_volume = v
		Sfx.apply_settings()))
	add_child(_slider_row("Effects", Save.sfx_volume, func(v: float) -> void:
		Save.sfx_volume = v
		Sfx.apply_settings()
		Sfx.play("pickup", 0.0)))
	add_child(_choice_row("Vibration", ["Off", "On"], 1 if Save.vibration else 0, func(i: int) -> void:
		Save.vibration = i == 1
		Sfx.vibrate(40)))
	var shakes := [0.0, 0.5, 1.0, 1.5]
	add_child(_choice_row("Screen shake", ["Off", "Low", "Normal", "High"], maxi(shakes.find(Save.shake), 0), func(i: int) -> void:
		Save.shake = shakes[i]))
	var caps := [30, 60, 0]
	add_child(_choice_row("Frame rate", ["Battery 30", "60", "Max"], maxi(caps.find(Save.fps_cap), 0), func(i: int) -> void:
		Save.fps_cap = caps[i]))
	var fps_on := Save.show_fps == 1 or (Save.show_fps == -1 and debug_fps_default)
	add_child(_choice_row("Show FPS", ["Off", "On"], 1 if fps_on else 0, func(i: int) -> void:
		Save.show_fps = i))
	add_child(UiKit.label("Max uses your screen's full refresh rate (smoothest). Battery 30 saves the most power.", 19, Color(pal.text, 0.55)))
	var tips := UiKit.button("Show tips again", func() -> void: pass, 70)
	tips.add_theme_font_size_override("font_size", 22)
	tips.pressed.connect(func() -> void:
		Save.hints_seen = []
		tips.text = "Tips will show again"
		tips.disabled = true)
	tips.disabled = Save.hints_seen.is_empty()
	add_child(tips)
	add_child(UiKit.button("BACK", func() -> void:
		Save.write()
		on_back.call(), 90))


func _row_label(text: String) -> Label:
	var l := UiKit.label(text, 26, pal.text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(190, 0)
	return l


func _slider_row(text: String, value: float, set_value: Callable) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.add_child(_row_label(text))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 56)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.15)
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	var fill := track.duplicate()
	fill.bg_color = pal.ui_accent
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := ImageTexture.create_from_image(_knob_image(40, Color.WHITE))
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	var pct := UiKit.label("%d%%" % roundi(value * 100.0), 22, Color(pal.text, 0.7))
	pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	pct.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v * 100.0)
		set_value.call(v)
		on_change.call())
	h.add_child(s)
	h.add_child(pct)
	return h


func _choice_row(text: String, options: Array, selected: int, pick: Callable) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(_row_label(text))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var buttons: Array[Button] = []
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 22)
		b.focus_mode = Control.FOCUS_NONE
		buttons.append(b)
		h.add_child(b)
	var paint := func(sel: int) -> void:
		for k in buttons.size():
			var on := k == sel
			var sb := UiKit._box(pal.ui_accent if on else Color("#3d2d6b"), 14, 8)
			for st in ["normal", "hover", "pressed"]:
				buttons[k].add_theme_stylebox_override(st, sb)
			var fc: Color = Color(0.12, 0.07, 0.2) if on else pal.text
			for c in ["font_color", "font_hover_color", "font_pressed_color"]:
				buttons[k].add_theme_color_override(c, fc)
	paint.call(selected)
	for i in buttons.size():
		buttons[i].pressed.connect(func() -> void:
			Sfx.play("click", 0.0)
			paint.call(i)
			pick.call(i)
			on_change.call())
	v.add_child(h)
	return v


static func _knob_image(size: int, c: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - h, y + 0.5 - h).length()
			img.set_pixel(x, y, Color(c, clampf(h - 1.0 - d, 0.0, 1.0)))
	return img
