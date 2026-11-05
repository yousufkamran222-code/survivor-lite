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
var dev_meta: Array = []  # permanent-upgrade defs when the developer tools are on (balance.debug.dev_tools)
var dev_password := ""  # balance.debug.dev_password; empty = no lock
static var dev_unlocked := false  # entered the password this session (until the app closes)
var _code := ""  # digits typed on the keypad


func setup(palette: Dictionary, changed: Callable, back: Callable, fps_default: bool, dev_meta_defs: Array = [], password: String = "") -> void:
	dev_meta = dev_meta_defs
	dev_password = password
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
	if not dev_meta.is_empty():
		if dev_unlocked or dev_password == "":
			_dev_rows()
		else:
			_dev_lock()
	add_child(UiKit.button("BACK", func() -> void:
		Save.write()
		on_back.call(), 90))


## The Developer section is locked behind a short code, typed on an
## on-screen keypad (works the same on the APK and the web build, no
## keyboard needed). Unlocks until the app is closed.
func _dev_lock() -> void:
	var open := UiKit.button("DEVELOPER", func() -> void: pass, 64)
	open.add_theme_font_size_override("font_size", 20)
	add_child(open)
	open.pressed.connect(func() -> void:
		var at := open.get_index()
		open.queue_free()
		var pad := _keypad()
		add_child(pad)
		move_child(pad, at))


func _keypad() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var shown := UiKit.label("Enter code", 30, Color("#ff7a6b"))
	box.add_child(shown)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "<", "0", "OK"]:
		var b := UiKit.button(key, func() -> void: pass, 52)
		b.custom_minimum_size = Vector2(100, 52)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(func() -> void:
			Sfx.play("click", 0.0)
			if key == "<":
				_code = _code.left(maxi(_code.length() - 1, 0))
			elif key == "OK":
				if check_code(_code):
					Sfx.play("upgrade", 0.0)
					_code = ""
					_build()
					return
				Sfx.play("deny", 0.0)
				_code = ""
				shown.text = "Wrong code"
				return
			elif _code.length() < 8:
				_code += key
			shown.text = "*".repeat(_code.length()) if _code != "" else "Enter code")
		grid.add_child(b)
	box.add_child(grid)
	return box


## True (and unlocks the Developer tools) if `code` matches the password.
func check_code(code: String) -> bool:
	if dev_password != "" and code == dev_password:
		dev_unlocked = true
	return dev_unlocked


## Playtest-only tools: free gold to test permanent upgrades, a refund, and
## every Virulence level unlocked in every mode (records stay untouched).
func _dev_rows() -> void:
	add_child(UiKit.label("DEVELOPER (playtest builds only)", 22, Color("#ff7a6b")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var gold := UiKit.button("+10,000 gold", func() -> void: pass, 70)
	gold.add_theme_font_size_override("font_size", 22)
	gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gold.pressed.connect(func() -> void:
		Save.profile.dev_grant_gold(10000, Save.now())
		Save.write()
		Sfx.play("upgrade", 0.0)
		gold.text = "Gold: %d" % Save.profile.gold)
	row.add_child(gold)
	var refund := UiKit.button("Refund upgrades", func() -> void: pass, 70)
	refund.add_theme_font_size_override("font_size", 22)
	refund.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refund.pressed.connect(func() -> void:
		var back := Save.profile.refund_meta(dev_meta, Save.now())
		Save.write()
		Sfx.play("click", 0.0)
		refund.text = "Refunded %d" % back)
	row.add_child(refund)
	add_child(row)
	var genes_amt := int(GameData.load_json("res://data/lab.json").get("genes", {}).get("dev_grant", 50))
	var genes := UiKit.button("+%d Genes (Lab)" % genes_amt, func() -> void: pass, 70)
	genes.add_theme_font_size_override("font_size", 22)
	genes.pressed.connect(func() -> void:
		Save.profile.dev_grant_genes(genes_amt, Save.now())
		Save.write()
		Sfx.play("upgrade", 0.0)
		genes.text = "Genes: %d" % Save.profile.genes)
	add_child(genes)
	add_child(_choice_row("All Virulence levels", ["Off", "On"], 1 if Save.profile.dev_all_virulence() else 0, func(i: int) -> void:
		Save.profile.settings["dev_all_virulence"] = i == 1
		Save.write()))


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
