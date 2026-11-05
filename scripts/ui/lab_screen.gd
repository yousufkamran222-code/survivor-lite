class_name LabScreen
extends VBoxContainer
## The Lab (data/lab.json): four branch columns of nodes joined by lines.
## Tiers run top to bottom; tier 4 is a fork (two nodes side by side, the
## one not taken greys out) and tier 5 the keystone (gold frame). Tapping a
## node opens a shop-style popup (now -> next, cost in Genes, big button).
## A Genes counter at the top, RESPEC (paid in gold) at the bottom.
## Buying goes through Profile.buy_lab(); main.gd only creates this node.

const GENE := Color("#5cf0a8")
const GENE_DARK := Color("#239a63")
const COL_W := 152.0
const ROW_Y := [44.0, 190.0, 336.0, 490.0, 652.0, 818.0]  # node centres per tier (below the 50 px header)
const SIZES := [76.0, 76.0, 76.0, 60.0, 96.0, 84.0]  # icon size per tier (6 = the ability)

var cfg: Dictionary
var pal: Dictionary
var popup_layer: Control
var on_back: Callable

var _cols: HBoxContainer
var _genes_labels: Array[Label] = []
var _popup: Control
var _popup_body: VBoxContainer
var _node: Dictionary
var _burst: MetaShop.Burst
var _respec_armed := false


var on_abilities: Callable


func setup(lab_cfg: Dictionary, palette: Dictionary, layer: Control, back: Callable, abilities: Callable = Callable()) -> void:
	on_abilities = abilities
	cfg = lab_cfg
	pal = palette
	popup_layer = layer
	on_back = back
	custom_minimum_size = Vector2(640, 0)
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	var title := UiKit.label("THE LAB", 50, GENE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_genes_pill())
	add_child(head)
	var hint := UiKit.label("Win Virulence levels to earn Genes. Tap a node.", 20, Color(pal.text, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(hint)
	var scroll := DragScroll.new()
	scroll.custom_minimum_size = Vector2(640, 830)
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", 10)
	_cols.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(_cols)
	add_child(scroll)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	var respec := UiKit.button(_respec_text(), func() -> void: pass, 90)
	respec.add_theme_font_size_override("font_size", 20)
	respec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	respec.pressed.connect(_respec.bind(respec))
	bottom.add_child(respec)
	if on_abilities.is_valid():
		var abl := UiKit.button("ABILITIES", func() -> void:
			_close_popup()
			on_abilities.call(), 90)
		abl.add_theme_font_size_override("font_size", 24)
		abl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(abl)
	var back_b := UiKit.button("BACK", func() -> void:
		_close_popup()
		on_back.call(), 90)
	back_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(back_b)
	add_child(bottom)
	_build(true)


# ---------------------------------------------------------------- columns

func _build(animate: bool) -> void:
	UiKit.clear(_cols)
	var k := 0
	for b in cfg.branches:
		var col := _column(b)
		_cols.add_child(col)
		if animate:
			UiKit.fade_in(col, 0.05 * k)
		k += 1


func _column(b: Dictionary) -> Control:
	var owned: Dictionary = Save.profile.lab
	var col := Column.new()
	col.color = GameData.color(b.color)
	col.custom_minimum_size = Vector2(COL_W, ROW_Y[ROW_Y.size() - 1] + 50.0 + SIZES[SIZES.size() - 1] / 2.0 + 56.0)
	var name := UiKit.label(str(b.name).to_upper(), 24, col.color)
	name.position = Vector2(0, -6)
	name.size = Vector2(COL_W, 30)
	col.add_child(name)
	var role := UiKit.label(str(b.role), 16, Color(pal.text, 0.5))
	role.position = Vector2(0, 20)
	role.size = Vector2(COL_W, 20)
	col.add_child(role)
	# Group nodes by tier; a tier with two nodes is drawn side by side.
	var tiers := {}
	for n in b.nodes:
		if not tiers.has(int(n.tier)):
			tiers[int(n.tier)] = []
		tiers[int(n.tier)].append(n)
	for t in tiers:
		var row: Array = tiers[t]
		var y: float = ROW_Y[mini(t - 1, ROW_Y.size() - 1)] + 50.0
		var px: float = SIZES[mini(t - 1, SIZES.size() - 1)]
		var xs := []
		for i in row.size():
			xs.append(COL_W * (0.5 if row.size() == 1 else (0.25 + 0.5 * i)))
		col.tier_points.append([xs, y, px * 0.5, Lab.tier_open(cfg, row[0], owned), px * 0.5 + (62.0 if row.size() > 1 else 48.0)])
		for i in row.size():
			col.add_child(_node_button(row[i], b, Vector2(xs[i], y), px))
	return col


func _node_button(n: Dictionary, b: Dictionary, at: Vector2, px: float) -> Button:
	var owned: Dictionary = Save.profile.lab
	var lv := Lab.level(owned, n.id)
	var open := Lab.tier_open(cfg, n, owned)
	var blocked := Lab.fork_blocked(cfg, n, owned)
	var maxed := lv >= Lab.max_level(n)
	var can := Lab.can_buy(cfg, n, owned, Save.profile.genes)
	var accent: Color = pal.ui_accent if n.get("keystone", false) else GameData.color(b.color)
	var fork := n.has("fork")
	var w := COL_W * 0.5 if fork else COL_W
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.position = at - Vector2(w / 2.0, px / 2.0 + 4.0)
	btn.size = Vector2(w, px + 66.0)
	var empty := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, empty)
	btn.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		_open(n, b))
	var ic := NodeIcon.new()
	ic.key = _icon_key(n, b)
	ic.color = accent
	ic.state = 3 if maxed else (2 if lv > 0 else (1 if open and not blocked else 0))
	ic.keystone = bool(n.get("keystone", false))
	ic.can_buy = can
	ic.position = Vector2((w - px) / 2.0, 4.0)
	ic.size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(ic)
	var name := UiKit.label(str(n.name).replace(" ", "\n") if fork else str(n.name), 14 if fork else 17, Color.WHITE if (open and not blocked) else Color(1, 1, 1, 0.4))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.add_theme_constant_override("line_spacing", -4)
	name.position = Vector2(0, px + 6.0)
	name.size = Vector2(w, 20)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name)
	var sub := "%d/%d" % [lv, Lab.max_level(n)] if Lab.max_level(n) > 1 else ("TAKEN" if lv > 0 else ("-" if blocked else "%d" % Lab.next_cost(n, owned)))
	if Lab.max_level(n) > 1 and maxed:
		sub = "MAX"
	var subl := UiKit.label(sub, 15, GENE if can else Color(1, 1, 1, 0.5))
	subl.position = Vector2(0, px + (40.0 if fork else 28.0))
	subl.size = Vector2(w, 18)
	subl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(subl)
	return btn


# ------------------------------------------------------------------ popup

func _open(n: Dictionary, b: Dictionary) -> void:
	_close_popup()
	_node = n
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
	var sb := UiKit._box(MetaShop.PANEL_BG, 30, 28)
	sb.set_border_width_all(4)
	sb.border_color = Color(pal.ui_accent if n.get("keystone", false) else GameData.color(b.color), 0.85)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	_popup_body = VBoxContainer.new()
	_popup_body.add_theme_constant_override("separation", 14)
	panel.add_child(_popup_body)
	_burst = MetaShop.Burst.new()
	_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.add_child(_burst)
	_fill_popup(-1)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.15)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.85, 0.85)
	panel.resized.connect(func() -> void: panel.pivot_offset = panel.size / 2.0)
	var tw := panel.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.28)


func _fill_popup(flash: int) -> void:
	var n := _node
	var b := Lab.branch_of(cfg, n.id)
	var owned: Dictionary = Save.profile.lab
	var body := _popup_body
	UiKit.clear(body)
	var lv := Lab.level(owned, n.id)
	var total := Lab.max_level(n)
	var cost := Lab.next_cost(n, owned)
	var maxed := cost < 0
	var keystone := bool(n.get("keystone", false))
	var col: Color = pal.ui_accent if keystone else GameData.color(b.color)
	var top := HBoxContainer.new()
	top.add_child(_genes_pill())
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var x := UiKit.button("X", func() -> void: _close_popup(true), 64)
	x.custom_minimum_size = Vector2(64, 64)
	x.focus_mode = Control.FOCUS_NONE
	top.add_child(x)
	body.add_child(top)
	var halo := MetaShop.Halo.new()
	halo.name = "Halo"
	halo.color = col
	halo.custom_minimum_size = Vector2(0, 190)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UpgradeIcon.make(_icon_key(n, b), col, 132)
	ic.name = "Icon"
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.position = Vector2(-66, -66)
	ic.size = Vector2(132, 132)
	ic.pivot_offset = Vector2(66, 66)
	halo.add_child(ic)
	body.add_child(halo)
	var kind := "KEYSTONE" if keystone else ("FORK: PICK ONE" if n.has("fork") else ("ABILITY" if n.has("ability") else str(b.name).to_upper()))
	var chip := UiKit.chip(kind, col, Color(0.1, 0.06, 0.15), 18)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(chip)
	body.add_child(UiKit.label(n.name, 42, Color.WHITE))
	if n.has("ability"):
		body.add_child(UiKit.label(str(cfg.abilities[n.ability].desc), 21, Color(pal.text, 0.75)))
	if total > 1:
		var bar := MetaShop.TierBar.new()
		bar.have = lv
		bar.total = total
		bar.color = col
		bar.flash_index = flash
		bar.custom_minimum_size = Vector2(0, 24)
		body.add_child(bar)
		var fx := HBoxContainer.new()
		fx.name = "Effect"
		fx.add_theme_constant_override("separation", 10)
		if maxed:
			fx.add_child(_effect_box("YOUR BONUS", _fx_text(n, lv), pal.ui_accent, true))
		else:
			fx.add_child(_effect_box("NOW", _fx_text(n, lv), Color.WHITE if lv > 0 else Color(1, 1, 1, 0.45), false))
			var arrow := MetaShop.Chevron.new()
			arrow.color = GENE
			arrow.custom_minimum_size = Vector2(28, 0)
			fx.add_child(arrow)
			fx.add_child(_effect_box("NEXT", _fx_text(n, lv + 1), GENE, true))
		body.add_child(fx)
	else:
		var fx := _effect_box("TAKEN" if lv > 0 else "EFFECT", Lab.effect_text(n, 1), pal.ui_accent if lv > 0 else Color.WHITE, lv > 0)
		fx.name = "Effect"
		body.add_child(fx)
	# Why it can't be bought, or the big button.
	if maxed:
		var done := UiKit.label("TAKEN" if total == 1 else "MAXED", 44, pal.ui_accent)
		done.custom_minimum_size = Vector2(0, 110)
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.add_child(done)
	elif Lab.fork_blocked(cfg, n, owned):
		body.add_child(_reason("You took the other side of this fork. RESPEC to switch."))
	elif not Lab.tier_open(cfg, n, owned):
		body.add_child(_reason("Locked: buy a node in every row above it first."))
	else:
		body.add_child(_buy_button(cost, Save.profile.genes >= cost))


func _reason(text: String) -> Control:
	var l := UiKit.label(text, 24, Color("#ff9a9a"))
	l.custom_minimum_size = Vector2(0, 110)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


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
	v.add_child(UiKit.label(value, 26, value_col))
	p.add_child(v)
	return p


func _buy_button(cost: int, can_buy: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 128)
	b.focus_mode = Control.FOCUS_NONE
	var face := GENE if can_buy else MetaShop.GREY
	var edge := GENE_DARK if can_buy else MetaShop.GREY_DARK
	var sb := UiKit._box(face, 26, 14)
	sb.border_width_bottom = 10
	sb.border_color = edge
	var sbp := sb.duplicate()
	sbp.border_width_bottom = 3
	sbp.content_margin_top = sb.content_margin_top + 7
	sbp.bg_color = face.darkened(0.08)
	for s in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(s, sb)
	b.add_theme_stylebox_override("pressed", sbp)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_bottom = -10
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _fixed_label("EVOLVE", 44, Color.WHITE if can_buy else Color(1, 1, 1, 0.55))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 8 if can_buy else 0)
	t.add_theme_color_override("font_outline_color", GENE_DARK.darkened(0.3))
	v.add_child(t)
	var price := HBoxContainer.new()
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_theme_constant_override("separation", 6)
	if can_buy:
		price.add_child(UpgradeIcon.make("gene", Color.WHITE, 32))
		price.add_child(_fixed_label("%d Gene%s" % [cost, "" if cost == 1 else "s"], 26, Color.WHITE))
	else:
		price.add_child(_fixed_label("Need %d more Genes" % (cost - Save.profile.genes), 24, Color("#ff9a9a")))
	v.add_child(price)
	b.add_child(v)
	b.pressed.connect(_try_buy.bind(b))
	return b


func _try_buy(b: Button) -> void:
	var n := _node
	var before := Save.profile.genes
	if Save.profile.buy_lab(cfg, n, Save.now()) <= 0:
		Sfx.play("deny", 0.0)
		Sfx.vibrate(25)
		var x0 := b.position.x
		var tw := b.create_tween()
		for dx in [14.0, -12.0, 8.0, -5.0, 0.0]:
			tw.tween_property(b, "position:x", x0 + dx, 0.05)
		return
	Save.write()
	var lv := Lab.level(Save.profile.lab, n.id)
	var big: bool = n.get("keystone", false) or n.has("fork") or lv >= Lab.max_level(n)
	Analytics.event("lab_buy", {"id": n.id, "level": lv})
	if n.has("ability") and Save.profile.equipped_ability(cfg) == "":
		Save.profile.equip_ability(cfg, str(n.ability))  # the first ability you unlock is equipped
		Save.write()
	Sfx.play("evolve" if big else "upgrade", 0.0, 1.0 + 0.04 * lv)
	Sfx.vibrate(120 if big else 35)
	_fill_popup(lv - 1)
	_set_genes_text(Save.profile.genes)
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_popup) or _popup_body == null:
		return
	var halo := _popup_body.get_node_or_null("Halo") as MetaShop.Halo
	if halo == null:
		return
	halo.boost = 1.0
	var ic: Control = halo.get_node("Icon")
	ic.scale = Vector2(1.35, 1.35)
	ic.create_tween().tween_property(ic, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var at := halo.global_position + halo.size / 2.0 - _burst.global_position
	_burst.emit(at, pal.ui_accent if n.get("keystone", false) else GENE, 50 if big else 26, 1.7 if big else 1.0)
	if before != Save.profile.genes and n.get("keystone", false):
		_stamp("KEYSTONE!")


func _stamp(text: String) -> void:
	var l := UiKit.label(text, 76, pal.ui_accent)
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
		_build(false)


# ------------------------------------------------------------------ respec

func _respec_text() -> String:
	return "RESPEC  (%d gold)" % int(cfg.get("respec_gold", 0))


## Two taps: the first arms it ("tap again"), the second refunds every Gene.
func _respec(b: Button) -> void:
	if Lab.spent(cfg, Save.profile.lab) <= 0:
		Sfx.play("deny", 0.0)
		b.text = "Nothing to reset"
		return
	if not _respec_armed:
		_respec_armed = true
		b.text = "Tap again to reset"
		Sfx.play("click", 0.0)
		return
	_respec_armed = false
	var back := Save.profile.respec_lab(cfg, Save.now())
	if back < 0:
		Sfx.play("deny", 0.0)
		b.text = "Need %d gold" % int(cfg.get("respec_gold", 0))
		return
	Save.write()
	Analytics.event("lab_respec", {"genes": back})
	Sfx.play("upgrade", 0.0)
	b.text = "+%d Genes back" % back
	_set_genes_text(Save.profile.genes)
	_build(true)


# ------------------------------------------------------------------ genes

func _genes_pill() -> Control:
	var pill := PanelContainer.new()
	var sb := UiKit._box(Color(0.04, 0.1, 0.08, 0.9), 26, 14)
	sb.set_border_width_all(2)
	sb.border_color = Color(GENE, 0.7)
	pill.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UpgradeIcon.make("gene", GENE, 36))
	var amount := _fixed_label(str(Save.profile.genes), 28, GENE)
	h.add_child(amount)
	pill.add_child(h)
	_genes_labels.append(amount)
	return pill


func _set_genes_text(v: int) -> void:
	var live: Array[Label] = []
	for l in _genes_labels:
		if is_instance_valid(l):
			l.text = str(v)
			live.append(l)
	_genes_labels = live


# ---------------------------------------------------------------- helpers

## Stat nodes reuse the shop glyph for their stat; forks and keystones use
## their own "icon" or the branch's.
func _icon_key(n: Dictionary, b: Dictionary) -> String:
	if n.has("icon"):
		return str(n.icon)
	if n.has("ability"):
		return str(n.ability)
	if n.get("keystone", false):
		return "keystone"
	var k: String = n.effects.keys()[0]
	if IconArt.META_KEYS.has(k) and not n.has("fork"):
		return IconArt.META_KEYS[k]
	return str(b.get("icon", "lab"))


func _fx_text(n: Dictionary, lv: int) -> String:
	return Lab.ability_text(cfg, str(n.ability), lv) if n.has("ability") else Lab.effect_text(n, lv)


func _fixed_label(text: String, px: int, col: Color) -> Label:
	var l := UiKit.label(text, px, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- widgets

## A branch column: draws the lines between tiers (lit once the next tier
## is open); the node buttons are its children.
class Column:
	extends Control
	var color := Color.WHITE
	var tier_points: Array = []  # [xs, y, radius, open, label bottom below the centre]

	func _draw() -> void:
		for t in range(1, tier_points.size()):
			var a: Array = tier_points[t - 1]
			var b: Array = tier_points[t]
			var lit: bool = b[3]
			for xa in a[0]:
				for xb in b[0]:
					var p0 := Vector2(xa, a[1] + a[4])
					var p1 := Vector2(xb, b[1] - b[2] - 6.0)
					draw_line(p0, p1, Color(color, 0.85) if lit else Color(1, 1, 1, 0.12), 4.0 if lit else 3.0)


## A node: icon disc with a state ring. state 0 locked, 1 open, 2 owned, 3 maxed.
class NodeIcon:
	extends Control
	var key := ""
	var color := Color.WHITE
	var state := 0
	var keystone := false
	var can_buy := false
	var _t := 0.0

	func _process(delta: float) -> void:
		if can_buy:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if can_buy:
			draw_circle(c, r + 6.0 + sin(_t * 4.0) * 2.0, Color(LabScreen.GENE, 0.25))
		var col := color if state >= 1 else Color(0.45, 0.42, 0.55)
		IconArt.draw(self, key, c, r * 2.0, col if state >= 2 else Color(col, 0.55))
		if state == 0:
			draw_circle(c, r, Color(0.05, 0.03, 0.1, 0.55))
		if keystone:
			draw_arc(c, r + 3.0, 0, TAU, 40, Color("#ffd166") if state >= 2 else Color("#ffd166", 0.45), 5.0)
		elif state >= 2:
			draw_arc(c, r + 2.0, 0, TAU, 32, Color.WHITE, 3.0)
