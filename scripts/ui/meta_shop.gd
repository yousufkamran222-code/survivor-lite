class_name MetaShop
extends VBoxContainer
## The permanent-upgrade shop. A drag-scrolling grid of tiles (icon, name,
## tier bar, price; a green badge when you can afford the next level) and a
## detail popup per upgrade: big icon, "now -> next" in words, and a big
## green UPGRADE button with sound, haptics and a particle burst.
## Buying goes through Profile.buy_meta(); main.gd only creates this node.

const GREEN := Color("#3ddc84")
const GREEN_DARK := Color("#1f9d5a")
const GREY := Color("#4a4462")
const GREY_DARK := Color("#332e47")
const TILE_BG := Color("#2a1f4a")
const PANEL_BG := Color("#241a40")
const COLUMNS := 3

var defs: Array
var pal: Dictionary
var popup_layer: Control  # full-screen node the popup is added to
var on_back: Callable

var _scroll: DragScroll
var _grid: GridContainer
var _gold_labels: Array[Label] = []
var _shown_gold := 0
var _popup: Control
var _popup_body: VBoxContainer
var _popup_def: Dictionary
var _burst: Burst


func setup(meta_defs: Array, palette: Dictionary, layer: Control, back: Callable) -> void:
	defs = meta_defs
	pal = palette
	popup_layer = layer
	on_back = back
	_shown_gold = Save.gold
	custom_minimum_size = Vector2(640, 0)
	add_theme_constant_override("separation", 14)
	var head := HBoxContainer.new()
	var title := UiKit.label("UPGRADES", 50, pal.ui_accent)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_gold_pill())
	add_child(head)
	var hint := UiKit.label("Permanent boosts for every run. Tap one to upgrade it.", 21, Color(pal.text, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(hint)
	_scroll = DragScroll.new()
	_scroll.custom_minimum_size = Vector2(640, 870)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_grid)
	add_child(_scroll)
	add_child(UiKit.button("BACK", func() -> void:
		_close_popup()
		on_back.call(), 90))
	_build_tiles(true)


# ------------------------------------------------------------------ tiles

func _build_tiles(animate: bool) -> void:
	UiKit.clear(_grid)
	var k := 0
	for m in defs:
		var t := _tile(m)
		_grid.add_child(t)
		if animate:
			_pop_in(t, 0.03 * k)
		k += 1


func _tile(m: Dictionary) -> Button:
	var lv := Save.meta_level(m.id)
	var total: int = m.costs.size()
	var cost := Progression.meta_next_cost(m, lv)
	var maxed := cost < 0
	var can_buy := not maxed and Save.gold >= cost
	var col := _icon_color(m)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 282)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_PASS  # lets DragScroll see the drag
	b.focus_mode = Control.FOCUS_NONE
	var border: Color = pal.ui_accent if maxed else (GREEN if can_buy else Color(col, 0.3))
	var sb := UiKit._box(TILE_BG, 20, 10)
	sb.set_border_width_all(3)
	sb.border_color = border
	var sbp := sb.duplicate()
	sbp.bg_color = TILE_BG.lightened(0.15)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sbp)
	b.pressed.connect(func() -> void:
		if _scroll.was_dragged():
			return
		Sfx.play("click", 0.0)
		_open(m))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 14
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	b.add_child(v)
	var ic := UpgradeIcon.make(_icon_key(m), col, 84, str(m.stat).begins_with("evo_"))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var name := UiKit.label(m.name, 21, Color.WHITE)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.custom_minimum_size = Vector2(0, 50)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(name)
	# What one level gives, so tiles read without opening the popup.
	var what := _fixed_label(Progression.meta_effect_text(m, 1), 18, Color(col, 0.95))
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	what.clip_text = true
	v.add_child(what)
	var bar := TierBar.new()
	bar.have = lv
	bar.total = total
	bar.color = pal.ui_accent if maxed else col
	bar.custom_minimum_size = Vector2(0, 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	v.add_child(_price_row(cost, can_buy, 24))
	if can_buy:
		var badge := Badge.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.position = Vector2(-40, 8)
		badge.size = Vector2(32, 32)
		b.add_child(badge)
	return b


## Gold coin + cost, "MAXED" when there's nothing left to buy.
func _price_row(cost: int, can_buy: bool, px: int) -> Control:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 6)
	if cost < 0:
		var mx := _fixed_label("MAXED", px, pal.ui_accent)
		h.add_child(mx)
		return h
	h.add_child(UpgradeIcon.make("gold", pal.ui_accent if can_buy else Color(1, 1, 1, 0.35), px + 4))
	h.add_child(_fixed_label(str(cost), px, Color.WHITE if can_buy else Color(1, 1, 1, 0.45)))
	return h


# ------------------------------------------------------------------ popup

func _open(m: Dictionary) -> void:
	_close_popup()
	_popup_def = m
	_popup = Control.new()
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_layer.add_child(_popup)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			_close_popup(true))
	_popup.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(600, 0)
	var sb := UiKit._box(PANEL_BG, 30, 28)
	sb.set_border_width_all(4)
	sb.border_color = Color(_icon_color(m), 0.8)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	_popup_body = VBoxContainer.new()
	_popup_body.add_theme_constant_override("separation", 14)
	panel.add_child(_popup_body)
	_burst = Burst.new()
	_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(_burst)
	_fill_popup(-1)
	# Entrance: fade the dim in, pop the panel.
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.15)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.85, 0.85)
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size / 2.0)
	var tw := panel.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28)


## (Re)builds the popup contents for the current level. `flash` is the tier
## segment that was just bought (-1 = none).
func _fill_popup(flash: int) -> void:
	var m := _popup_def
	var body := _popup_body
	UiKit.clear(body)
	var lv := Save.meta_level(m.id)
	var total: int = m.costs.size()
	var cost := Progression.meta_next_cost(m, lv)
	var maxed := cost < 0
	var col := _icon_color(m)
	# Top row: gold on the left, close on the right.
	var top := HBoxContainer.new()
	top.add_child(_gold_pill())
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var x := UiKit.button("X", func() -> void: _close_popup(true), 64)
	x.custom_minimum_size = Vector2(64, 64)
	x.focus_mode = Control.FOCUS_NONE
	top.add_child(x)
	body.add_child(top)
	# Icon on a glowing halo.
	var halo := Halo.new()
	halo.name = "Halo"
	halo.color = pal.ui_accent if maxed else col
	halo.custom_minimum_size = Vector2(0, 190)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UpgradeIcon.make(_icon_key(m), col, 132, str(m.stat).begins_with("evo_"))
	ic.name = "Icon"
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.position = Vector2(-66, -66)
	ic.size = Vector2(132, 132)
	ic.pivot_offset = Vector2(66, 66)
	halo.add_child(ic)
	body.add_child(halo)
	body.add_child(UiKit.label(m.name, 42, Color.WHITE))
	body.add_child(UiKit.label(m.desc, 23, Color(pal.text, 0.7)))
	# Tier bar + level in words.
	var bar := TierBar.new()
	bar.name = "Bar"
	bar.have = lv
	bar.total = total
	bar.color = pal.ui_accent if maxed else col
	bar.flash_index = flash
	bar.custom_minimum_size = Vector2(0, 24)
	body.add_child(bar)
	body.add_child(UiKit.label("Fully upgraded!" if maxed else "Level %d of %d" % [lv, total], 21, pal.ui_accent if maxed else Color(pal.text, 0.6)))
	# Now -> next, in words.
	var fx := HBoxContainer.new()
	fx.name = "Effect"
	fx.add_theme_constant_override("separation", 10)
	if maxed:
		fx.add_child(_effect_box("YOUR BONUS", Progression.meta_effect_text(m, lv), pal.ui_accent, true))
	else:
		fx.add_child(_effect_box("NOW", Progression.meta_effect_text(m, lv), Color.WHITE if lv > 0 else Color(1, 1, 1, 0.45), false))
		var arrow := Chevron.new()
		arrow.color = GREEN
		arrow.custom_minimum_size = Vector2(28, 0)
		fx.add_child(arrow)
		fx.add_child(_effect_box("NEXT", Progression.meta_effect_text(m, lv + 1), GREEN, true))
	body.add_child(fx)
	# The big button.
	if maxed:
		var done := UiKit.label("MAXED", 44, pal.ui_accent)
		done.custom_minimum_size = Vector2(0, 110)
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.add_child(done)
	else:
		body.add_child(_buy_button(cost, Save.gold >= cost))


func _effect_box(caption: String, value: String, value_col: Color, highlight: bool) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := UiKit._box(Color(1, 1, 1, 0.06), 16, 12)
	if highlight:
		sb.set_border_width_all(2)
		sb.border_color = Color(value_col, 0.6)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.add_child(UiKit.label(caption, 18, Color(pal.text, 0.55)))
	var val := UiKit.label(value, 27, value_col)
	val.name = "Value"
	v.add_child(val)
	p.add_child(v)
	return p


func _buy_button(cost: int, can_buy: bool) -> Button:
	var b := Button.new()
	b.name = "Buy"
	b.custom_minimum_size = Vector2(0, 128)
	b.focus_mode = Control.FOCUS_NONE
	var face := GREEN if can_buy else GREY
	var edge := GREEN_DARK if can_buy else GREY_DARK
	UiKit.style_button(b, "positive", 0, face)  # glossy, like every button (edge unused)
	b.add_theme_stylebox_override("disabled", UiKit.gloss(face))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_bottom = -10
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	var t := _fixed_label("UPGRADE", 44, Color.WHITE if can_buy else Color(1, 1, 1, 0.55))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 8 if can_buy else 0)
	t.add_theme_color_override("font_outline_color", GREEN_DARK.darkened(0.3))
	v.add_child(t)
	if can_buy:
		v.add_child(_price_row(cost, true, 28))
	else:
		var need := _fixed_label("Need %d more gold" % (cost - Save.gold), 24, Color("#ff9a9a"))
		need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(need)
	b.add_child(v)
	b.pressed.connect(_try_buy.bind(b))
	return b


func _try_buy(b: Button) -> void:
	var m := _popup_def
	var gold_before := Save.gold
	var spent := Save.profile.buy_meta(m, Save.now())
	if spent <= 0:
		# Can't afford: a soft "nope" and a head-shake.
		Sfx.play("deny", 0.0)
		Sfx.vibrate(25)
		var x0 := b.position.x
		var tw := b.create_tween()
		for dx in [14.0, -12.0, 8.0, -5.0, 0.0]:
			tw.tween_property(b, "position:x", x0 + dx, 0.05)
		return
	Save.write()
	var lv := Save.meta_level(m.id)
	var maxed: bool = lv >= m.costs.size()
	Analytics.event("meta_buy", {"id": m.id, "level": lv})
	if maxed:
		Sfx.play("evolve", 0.0)
		Sfx.vibrate(120)
	else:
		Sfx.play("upgrade", 0.0, 1.0 + 0.035 * lv)
		Sfx.vibrate(35)
	_fill_popup(lv - 1)
	_tween_gold(gold_before, Save.gold)
	# Let the rebuilt popup lay out (containers sort a frame late).
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_popup) or _popup_body == null:
		return
	var halo := _popup_body.get_node_or_null("Halo") as Halo
	if halo == null:
		return
	halo.boost = 1.0
	var ic: Control = halo.get_node("Icon")
	ic.scale = Vector2(1.35, 1.35)
	ic.create_tween().tween_property(ic, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var at := halo.global_position + halo.size / 2.0 - _burst.global_position
	var col: Color = pal.ui_accent if maxed else _icon_color(m)
	_burst.emit(at, col, 44 if maxed else 26, 1.6 if maxed else 1.0)
	var fx: Control = _popup_body.get_node_or_null("Effect")
	if fx != null:
		fx.pivot_offset = fx.size / 2.0
		fx.scale = Vector2(1.08, 1.08)
		fx.create_tween().tween_property(fx, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if maxed:
		_stamp("MAXED!")


## A big gold word that slams onto the popup.
func _stamp(text: String) -> void:
	var l := UiKit.label(text, 84, pal.ui_accent)
	l.add_theme_constant_override("outline_size", 16)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	l.size = Vector2(600, 120)
	l.position = Vector2(-300, -260)
	l.pivot_offset = l.size / 2.0
	l.rotation = -0.12
	l.scale = Vector2(2.2, 2.2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _close_popup(refresh: bool = false) -> void:
	if _popup == null:
		return
	var p := _popup
	_popup = null
	_popup_body = null
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in p.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 0.0, 0.12)
	tw.tween_callback(p.queue_free)
	if refresh and is_inside_tree():
		var keep := _scroll.scroll_vertical
		_build_tiles(false)
		_refresh_gold()
		_scroll.set_deferred("scroll_vertical", keep)


# ------------------------------------------------------------------ gold

func _gold_pill() -> Control:
	var pill := PanelContainer.new()
	var sb := UiKit._box(Color(0.08, 0.05, 0.14, 0.9), 26, 14)
	sb.set_border_width_all(2)
	sb.border_color = Color(pal.ui_accent, 0.7)
	pill.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UpgradeIcon.make("gold", pal.ui_accent, 36))
	var amount := UiKit.display(_fixed_label(str(_shown_gold), 28, pal.ui_accent))
	h.add_child(amount)
	pill.add_child(h)
	_gold_labels.append(amount)
	return pill


func _refresh_gold() -> void:
	_shown_gold = Save.gold
	_set_gold_text(_shown_gold)


func _set_gold_text(v: int) -> void:
	var live: Array[Label] = []
	for l in _gold_labels:
		if is_instance_valid(l):
			l.text = str(v)
			live.append(l)
	_gold_labels = live


## The gold count ticks down to the new total.
func _tween_gold(from: int, to: int) -> void:
	_shown_gold = to
	var tw := create_tween()
	tw.tween_method(func(f: float) -> void: _set_gold_text(roundi(f)), float(from), float(to), 0.4).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- helpers

func _icon_key(m: Dictionary) -> String:
	return IconArt.META_KEYS.get(m.stat, "")


func _icon_color(m: Dictionary) -> Color:
	if str(m.stat).begins_with("dash"):
		return IconArt.COLORS.dash
	return IconArt.color_for({"id": _icon_key(m)})


func _fixed_label(text: String, px: int, col: Color) -> Label:
	var l := UiKit.label(text, px, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF  # narrow containers: no wrapping
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _pop_in(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	c.scale = Vector2(0.92, 0.92)
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.24).set_delay(delay)


# ---------------------------------------------------------------- widgets

## Segmented level bar: one segment per tier, filled up to `have`.
class TierBar:
	extends Control
	var have := 0
	var total := 5
	var color := Color.WHITE
	var flash_index := -1
	var pulse_index := -1  # a segment that glows on and off (the level you'd get)
	var _flash := 1.0
	var _t := 0.0

	func _process(delta: float) -> void:
		if flash_index >= 0 and _flash > 0.0:
			_flash = maxf(0.0, _flash - delta * 2.0)
			queue_redraw()
		if pulse_index >= 0:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var gap := 4.0 if total <= 10 else 2.0
		var w := (size.x - gap * (total - 1)) / float(total)
		for k in total:
			var rect := Rect2(k * (w + gap), 0, w, size.y)
			# Plain rects: they batch into one draw call (rounded style boxes
			# cost one each, ~80 extra calls across the shop grid).
			if k < have:
				draw_rect(rect, color.lerp(Color.WHITE, _flash if k == flash_index else 0.0))
			elif k == pulse_index:
				draw_rect(rect, Color(color.lerp(Color.WHITE, 0.4), 0.45 + 0.4 * sin(_t * 6.0)))
			else:
				draw_rect(rect, Color(1, 1, 1, 0.12))


## Pulsing green "can upgrade" badge for tiles.
class Badge:
	extends Control
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := 14.0 + sin(_t * 5.0) * 1.5
		draw_circle(c, r + 3.0, Color(MetaShop.GREEN, 0.3))
		draw_circle(c, r, MetaShop.GREEN)
		var s := r * 0.5
		draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.35), c + Vector2(0, -s * 0.65), c + Vector2(s, s * 0.35)]), Color.WHITE, 3.5)
		draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.9), Color.WHITE, 3.5)


## ">" between NOW and NEXT.
class Chevron:
	extends Control
	var color := Color.WHITE

	func _draw() -> void:
		var c := size / 2.0
		draw_polyline(PackedVector2Array([c + Vector2(-7, -13), c + Vector2(7, 0), c + Vector2(-7, 13)]), color, 5.0)


## Soft glow and slowly turning rays behind the popup icon; `boost` flares
## it after a purchase.
class Halo:
	extends Control
	var color := Color.WHITE
	var boost := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		boost = maxf(0.0, boost - delta * 1.5)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var b := boost
		for k in 12:
			var a := _t * 0.4 + k * TAU / 12.0
			var d := Vector2.from_angle(a)
			draw_line(c + d * 62.0, c + d * (88.0 + 14.0 * b), Color(color, 0.16 + 0.4 * b), 5.0)
		draw_circle(c, 82.0 + 12.0 * b, Color(color, 0.08 + 0.15 * b))
		draw_circle(c, 70.0 + 8.0 * b, Color(color, 0.12 + 0.2 * b))


## Particle burst + expanding rings drawn over the popup (menu only, so a
## few dozen draw calls are fine).
class Burst:
	extends Control
	var _p: Array = []  # [pos, vel, life, max_life, radius, color]
	var _rings: Array = []  # [center, life, scale, color]

	func emit(at: Vector2, col: Color, count: int, power: float) -> void:
		for k in count:
			var a := randf() * TAU
			var spd := randf_range(180.0, 520.0) * power
			var life := randf_range(0.45, 0.9)
			var c := col if randf() < 0.65 else Color.WHITE
			_p.append([at, Vector2.from_angle(a) * spd, life, life, randf_range(3.0, 7.0) * sqrt(power), c])
		_rings.append([at, 0.0, power, col])
		_rings.append([at, -0.08, power * 0.7, Color.WHITE])

	func _process(delta: float) -> void:
		if _p.is_empty() and _rings.is_empty():
			return
		for q in _p:
			var v: Vector2 = q[1]
			q[0] = q[0] + v * delta
			v *= exp(-3.5 * delta)
			v.y += 260.0 * delta
			q[1] = v
			q[2] = float(q[2]) - delta
		_p = _p.filter(func(q: Array) -> bool: return q[2] > 0.0)
		for r in _rings:
			r[1] += delta
		_rings = _rings.filter(func(r: Array) -> bool: return r[1] < 0.5)
		queue_redraw()

	func _draw() -> void:
		for r in _rings:
			var t: float = r[1]
			if t < 0.0:
				continue
			var k := t / 0.5
			draw_arc(r[0], (60.0 + 170.0 * k) * float(r[2]), 0, TAU, 48, Color(r[3], 0.8 * (1.0 - k)), 8.0 * (1.0 - k) + 1.0)
		for q in _p:
			var f: float = q[2] / q[3]
			draw_circle(q[0], float(q[4]) * (0.4 + 0.6 * f), Color(q[5], f))
