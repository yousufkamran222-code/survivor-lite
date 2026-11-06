class_name StyleScreen
extends VBoxContainer
## Cosmetics (data/cosmetics.json): a live preview on top, the selected
## item's name, how to get it and an action (EQUIP / BUY / challenge
## progress), category tabs, and a grid of every item. Tapping any item, even
## a locked one, previews it. main.gd only creates this node.

const COLUMNS := 3
const PINK := Color("#ff7ac8")

var cfg: Dictionary
var pal: Dictionary
var on_back: Callable
var _cat := "skin"
var _sel := ""  # selected (previewed) item id
var _preview: CosmeticPreview
var _info: VBoxContainer
var _tabs: HBoxContainer
var _grid: GridContainer
var _scroll: DragScroll
var _gold: Label
var _flat := {}


func setup(cosmetics_cfg: Dictionary, palette: Dictionary, back: Callable) -> void:
	cfg = cosmetics_cfg
	pal = palette
	on_back = back
	custom_minimum_size = Vector2(640, 0)
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	var title := UiKit.display(UiKit.label("STYLE", 50, PINK))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_gold_pill())
	add_child(head)
	_preview = CosmeticPreview.new()
	_preview.pal = pal
	for e in GameData.load_json("res://data/enemies.json"):
		if str(e.get("id", "")) != "boss":
			_preview.germ_colors.append(GameData.color(e.color))
	_preview.custom_minimum_size = Vector2(640, 260)
	add_child(_preview)
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 6)
	_info.custom_minimum_size = Vector2(640, 168)
	add_child(_info)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 10)
	add_child(_tabs)
	_scroll = DragScroll.new()
	_scroll.custom_minimum_size = Vector2(640, 380)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)
	add_child(_scroll)
	add_child(UiKit.button("BACK", func() -> void:
		Save.write()
		on_back.call(), 90))
	_select_cat("skin", true)


func _prof() -> Profile:
	return Save.profile


func _select_cat(cat: String, animate: bool = false) -> void:
	_cat = cat
	_sel = Cosmetics.equipped(cfg, _prof(), cat)
	_flat = _prof().flat()
	_build_tabs()
	_build_grid(animate)
	_show_selected()


func _build_tabs() -> void:
	UiKit.clear(_tabs)
	for c in cfg.categories:
		var b := Button.new()
		b.text = str(c.name).to_upper()
		b.custom_minimum_size = Vector2(0, 66)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		UiKit.style_button(b, "primary" if c.id == _cat else "secondary", 24)
		UiKit.press_feedback(b)
		var id: String = c.id
		b.pressed.connect(func() -> void:
			Sfx.play("click", 0.0)
			_select_cat(id))
		_tabs.add_child(b)


func _build_grid(animate: bool) -> void:
	UiKit.clear(_grid)
	var k := 0
	for it in Cosmetics.items(cfg, _cat):
		var t := _tile(it)
		_grid.add_child(t)
		if animate:
			UiKit.fade_in(t, 0.03 * k)
		k += 1


func _tile(it: Dictionary) -> Button:
	var id := str(it.id)
	var unlocked := Cosmetics.is_unlocked(it, _prof(), _flat)
	var equipped := Cosmetics.equipped(cfg, _prof(), _cat) == id
	var selected := id == _sel
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 180)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS  # drags on a tile scroll the list
	var sb := UiKit._box(MetaShop.TILE_BG if unlocked else Color("#1f1738"), 20, 8)
	sb.set_border_width_all(4 if selected else 2)
	sb.border_color = Color.WHITE if selected else (PINK if equipped else Color(1, 1, 1, 0.12))
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(func() -> void:
		if _scroll.was_dragged():
			return
		Sfx.play("click", 0.0)
		_sel = id
		_build_grid(false)
		_show_selected())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	var sw := Swatch.new()
	sw.item = it
	sw.pal = pal
	sw.locked = not unlocked
	sw.custom_minimum_size = Vector2(0, 100)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sw)
	var name := UiKit.label(str(it.name), 21, Color.WHITE if unlocked else Color(1, 1, 1, 0.55))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	var status := ""
	var sc := Color(1, 1, 1, 0.6)
	if equipped:
		status = "EQUIPPED"
		sc = PINK
	elif unlocked:
		status = "Owned"
	elif Cosmetics.unlock_type(it) == "gold":
		status = "%s gold" % Cosmetics._thousands(Cosmetics.cost(it))
		sc = pal.ui_accent
	else:
		status = "%d%%" % roundi(Cosmetics.progress(it, _prof(), _flat) * 100.0)
		sc = Color("#ff9a9a") if Cosmetics.unlock_type(it) == "challenge" else Color("#ff5a7a")
	var sl := UiKit.label(status, 17, sc)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sl)
	b.add_child(v)
	return b


## The info area for the selected item, and the preview showing it.
func _show_selected() -> void:
	var it := Cosmetics.find(cfg, _sel)
	_preview.set_look(Cosmetics.look(cfg, _prof(), {_cat: _sel}))
	UiKit.clear(_info)
	if it.is_empty():
		return
	var unlocked := Cosmetics.is_unlocked(it, _prof(), _flat)
	var equipped := Cosmetics.equipped(cfg, _prof(), _cat) == _sel
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var name := UiKit.display(UiKit.label(str(it.name), 34, Color.WHITE))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(name)
	var kind := Cosmetics.unlock_type(it)
	if kind == "prestige":
		top.add_child(UiKit.chip("PRESTIGE", Color("#ff5a7a")))
	elif kind == "challenge":
		top.add_child(UiKit.chip("CHALLENGE", Color("#ff9a9a")))
	_info.add_child(top)
	var desc := UiKit.label(str(it.desc), 20, Color(1, 1, 1, 0.75))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info.add_child(desc)
	if equipped:
		var b := UiKit.button("EQUIPPED", func() -> void: pass, 72, "secondary")
		b.disabled = true
		_info.add_child(b)
	elif unlocked:
		_info.add_child(UiKit.button("EQUIP", _equip, 72, "primary"))
	elif kind == "gold":
		var c := Cosmetics.cost(it)
		var b := UiKit.button("BUY  %s gold" % Cosmetics._thousands(c), _buy, 72, "positive" if Save.gold >= c else "secondary")
		_info.add_child(b)
	else:
		var how := UiKit.label("To unlock: %s" % Cosmetics.unlock_text(it), 21, Color("#ff9a9a"))
		how.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_info.add_child(how)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = Cosmetics.progress(it, _prof(), _flat)
		bar.custom_minimum_size = Vector2(0, 22)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := UiKit._box(Color(1, 1, 1, 0.12), 11, 0)
		var fill := UiKit._box(Color("#ff9a9a"), 11, 0)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		var pt := UiKit.label(Cosmetics.progress_text(it, _prof(), _flat), 19, Color(1, 1, 1, 0.7))
		pt.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(pt)
		_info.add_child(row)


func _equip() -> void:
	if Cosmetics.equip(cfg, _prof(), _sel):
		Save.write()
		Sfx.play("upgrade", 0.0)
		Sfx.vibrate(35)
		Analytics.event("cosmetic_equip", {"id": _sel})
		_build_grid(false)
		_show_selected()


func _buy() -> void:
	var spent := Cosmetics.buy(cfg, _prof(), _sel, Save.now())
	if spent <= 0:
		Sfx.play("deny", 0.0)
		return
	Cosmetics.equip(cfg, _prof(), _sel)  # bought = put it on straight away
	Save.write()
	Sfx.play("upgrade", 0.0)
	Sfx.vibrate(60)
	Analytics.event("cosmetic_buy", {"id": _sel, "cost": spent})
	_gold.text = Cosmetics._thousands(Save.gold)
	_build_grid(false)
	_show_selected()


func _gold_pill() -> Control:
	var pill := PanelContainer.new()
	var sb := UiKit._box(Color(0.08, 0.05, 0.14, 0.9), 26, 14)
	sb.set_border_width_all(2)
	sb.border_color = Color(pal.ui_accent, 0.7)
	pill.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UpgradeIcon.make("gold", pal.ui_accent, 36))
	_gold = UiKit.display(UiKit.label(Cosmetics._thousands(Save.gold), 28, pal.ui_accent))
	_gold.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(_gold)
	pill.add_child(h)
	return pill


## A still thumbnail of one item: a mini cell for skins, the four weapon
## colours in the style's shape, or a burst of the pop's particles.
class Swatch extends Control:
	var item := {}
	var pal := {}
	var locked := false
	static var _cell: Texture2D
	static var _disc: Texture2D
	static var _glow: Texture2D

	func _draw() -> void:
		if _cell == null:
			_cell = ShapeTextures.player_cell()
			_disc = ShapeTextures.disc()
			_glow = ShapeTextures.glow(64)
		var c := size / 2.0
		var lk: Dictionary = item.get("look", {})
		match str(item.get("cat", "")):
			"skin":
				CosmeticArt.draw_cell(self, c, 30.0, lk, 0.8, pal, _cell, _disc, _glow, -0.6)
			"weapon":
				var tx := CosmeticArt.tex(CosmeticArt.weapon_shape(lk))
				var k := 0
				for w in Cosmetics.WEAPONS:
					var col := CosmeticArt.weapon_color(lk, w, pal.get(w, Color.WHITE), false)
					var at := c + Vector2.from_angle(-PI / 2.0 + TAU * k / 4.0) * 30.0
					draw_texture_rect(tx, Rect2(at - Vector2(15, 15), Vector2(30, 30)), false, col)
					k += 1
				var ev := CosmeticArt.weapon_color(lk, "bolt", Color("#ff6bd6"), true, Color("#ff6bd6"))
				draw_texture_rect(_disc, Rect2(c - Vector2(9, 9), Vector2(18, 18)), false, ev)
			"pop":
				var tx := CosmeticArt.tex(str(lk.get("shape", "disc")))
				var cols: Array = lk.get("colors", ["germ"])
				for k in 9:
					var ck := str(cols[k % cols.size()])
					var col := Color("#ff5d73") if ck == "germ" else GameData.color(ck)
					var at := c + Vector2.from_angle(k * 2.4) * (12.0 + 4.0 * k)
					var s := 20.0 - k
					draw_texture_rect(tx, Rect2(at - Vector2(s, s) / 2.0, Vector2(s, s)), false, col)
		if locked:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.05, 0.14, 0.45))
			# Padlock.
			var p := c + Vector2(size.x * 0.32, size.y * 0.28)
			draw_arc(p + Vector2(0, -6), 7.0, PI, TAU, 10, Color.WHITE, 3.0)
			draw_rect(Rect2(p + Vector2(-10, -6), Vector2(20, 16)), Color.WHITE)
