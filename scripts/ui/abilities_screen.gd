class_name AbilitiesScreen
extends VBoxContainer
## Every Lab ability as a card: icon, name, what it does, level, duration and
## recharge, and EQUIP (one at a time; it goes on the button left of DASH).
## Locked ones say which branch unlocks them. main.gd only creates this node.

var cfg: Dictionary
var pal: Dictionary
var on_back: Callable
var _list: VBoxContainer
var _scroll: DragScroll


func setup(lab_cfg: Dictionary, palette: Dictionary, back: Callable) -> void:
	cfg = lab_cfg
	pal = palette
	on_back = back
	custom_minimum_size = Vector2(640, 0)
	add_theme_constant_override("separation", 12)
	var title := UiKit.label("ABILITIES", 50, LabScreen.GENE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(title)
	var hint := UiKit.label("Equip one. It sits left of DASH and recharges as you kill germs.", 20, Color(pal.text, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(hint)
	var scroll := DragScroll.new()
	_scroll = scroll
	scroll.custom_minimum_size = Vector2(640, 880)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)
	add_child(scroll)
	add_child(UiKit.button("BACK", func() -> void: on_back.call(), 90))
	_build(true)


func _build(animate: bool) -> void:
	UiKit.clear(_list)
	var k := 0
	for id in Lab.ability_ids(cfg):
		var c := _card(id)
		_list.add_child(c)
		if animate:
			UiKit.fade_in(c, 0.05 * k)
		k += 1


func _card(id: String) -> Control:
	var a: Dictionary = cfg.abilities[id]
	var col := GameData.color(a.color)
	var lv := Lab.ability_level(cfg, Save.profile.lab, id)
	var equipped := Save.profile.equipped_ability(cfg) == id
	var p := PanelContainer.new()
	var sb := UiKit._box(MetaShop.TILE_BG, 22, 16)
	sb.set_border_width_all(4 if equipped else 2)
	sb.border_color = col if equipped else Color(col, 0.35 if lv > 0 else 0.15)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.add_child(h)
	var ic := UpgradeIcon.make(id, col if lv > 0 else Color(0.45, 0.42, 0.55), 104)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var name := UiKit.label(str(a.name), 30, Color.WHITE if lv > 0 else Color(1, 1, 1, 0.5))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(name)
	var levels: int = a.levels.size()
	if lv > 0:
		top.add_child(UiKit.chip("LV %d/%d" % [lv, levels], col))
	if equipped:
		top.add_child(UiKit.chip("EQUIPPED", Color.WHITE))
	v.add_child(top)
	var desc := UiKit.label(str(a.desc), 19, Color(1, 1, 1, 0.8 if lv > 0 else 0.5))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(desc)
	var branch := {}
	for b in cfg.branches:
		if b.id == a.branch:
			branch = b
	if lv > 0:
		var stat := UiKit.label(Lab.ability_text(cfg, id, lv), 19, col)
		stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(stat)
		if not equipped:
			var eq := UiKit.button("EQUIP", func() -> void:
				if _scroll.was_dragged():
					return
				Save.profile.equip_ability(cfg, id)
				Save.write()
				Sfx.play("upgrade", 0.0)
				Sfx.vibrate(35)
				Analytics.event("ability_equip", {"id": id})
				_build(false), 70)
			eq.add_theme_font_size_override("font_size", 26)
			eq.mouse_filter = Control.MOUSE_FILTER_PASS  # let drags on the button scroll the list
			v.add_child(eq)
	else:
		var n := Lab.ability_node(cfg, id)
		var lock := UiKit.label("Unlock in the Lab: end of the %s branch (%d Genes)" % [str(branch.get("name", "?")), int(n.costs[0])], 19, Color("#ff9a9a"))
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(lock)
	return p
