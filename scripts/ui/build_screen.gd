class_name BuildScreen
extends VBoxContainer
## In-run "your build" overlay (opened from the HUD's BUILD button; the run
## is paused while it's up): every weapon and upgrade you own with its icon,
## level, tier bar, what it does, and how it evolves. Read-only.

const ROW_BG := Color("#2a1f4a")

var pal: Dictionary
var world: World


## evo_by_weapon / evo_by_passive: evolution defs keyed by weapon / passive id.
func setup(palette: Dictionary, w: World, evo_by_weapon: Dictionary, evo_by_passive: Dictionary, resume: Callable) -> void:
	pal = palette
	world = w
	custom_minimum_size = Vector2(640, 0)
	add_theme_constant_override("separation", 12)
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 14)
	var title := UiKit.label("YOUR BUILD", 50, pal.ui_accent)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(title)
	head.add_child(UiKit.chip("LV %d" % w.level, pal.ui_accent, Color(0.1, 0.06, 0.15), 22))
	add_child(head)
	var scroll := DragScroll.new()
	scroll.custom_minimum_size = Vector2(640, 900)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	add_child(scroll)
	var weapons := []
	var passives := []
	for u in w.upgrade_list:
		if w.owned.has(u.id):
			(weapons if u.type == "weapon" else passives).append(u)
	list.add_child(_section("WEAPONS  %d / %d" % [weapons.size(), int(w.bal.upgrades.max_weapons)]))
	for u in weapons:
		list.add_child(_weapon_row(u, evo_by_weapon))
	list.add_child(_section("UPGRADES  %d" % passives.size()))
	if passives.is_empty():
		list.add_child(_note("None yet. Level up and tap UPGRADE to pick some."))
	for u in passives:
		list.add_child(_passive_row(u, evo_by_passive))
	add_child(UiKit.button("RESUME", resume, 100))


func _section(text: String) -> Label:
	var l := UiKit.label(text, 24, pal.ui_accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _note(text: String) -> Label:
	var l := UiKit.label(text, 20, Color(pal.text, 0.6))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _weapon_row(u: Dictionary, evo_by_weapon: Dictionary) -> Control:
	var lvl := int(world.owned[u.id])
	var total := Upgrades.max_level(u)
	var evo_id: String = world.evolved.get(u.id, "")
	if evo_id != "":
		var ev: Dictionary = evo_by_weapon[u.id]
		return _row(u.id, true, GameData.color(ev.get("color", "#ffd166")), str(ev.name), "EVOLVED", lvl, total, str(ev.desc), "")
	var chip := ""
	if evo_by_weapon.has(u.id):
		var ev: Dictionary = evo_by_weapon[u.id]
		var need: String = world.upgrade_defs[ev.requires].name
		if lvl >= total and world.owned.has(ev.requires):
			chip = "READY: kill an elite for a chest = %s" % ev.name
		elif lvl >= total:
			chip = "Evolve: + %s = %s" % [need, ev.name]
		else:
			chip = "Evolves at Lv %d + %s" % [total, need]
	return _row(u.id, false, IconArt.color_for(u), str(u.name), "MAX" if lvl >= total else "LV %d / %d" % [lvl, total], lvl, total, Upgrades.describe(u, 1), chip)


func _passive_row(u: Dictionary, evo_by_passive: Dictionary) -> Control:
	var lvl := int(world.owned[u.id])
	var total := Upgrades.max_level(u)
	var chip := ""
	if evo_by_passive.has(u.id):
		var ev: Dictionary = evo_by_passive[u.id]
		if not world.evolved.has(ev.weapon):
			chip = "Pairs with %s (evolution)" % world.upgrade_defs[ev.weapon].name
	return _row(u.id, false, IconArt.color_for(u), str(u.name), "MAX" if lvl >= total else "LV %d / %d" % [lvl, total], lvl, total, Upgrades.describe(u, lvl), chip)


## One row: glowing icon, name + level chip, tier bar, effect text, and an
## optional gold evolution chip.
func _row(key: String, evolved: bool, accent: Color, name: String, level_text: String, lvl: int, total: int, body: String, chip: String) -> Control:
	var p := UiKit.panel(ROW_BG, Color(accent, 0.55), 18, 12)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)
	var ic := UiKit.glow_icon(key, accent, 76, evolved)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 5)
	h.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 10)
	var nl := UiKit.label(name, 25, pal.ui_accent if evolved else Color.WHITE)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(nl)
	top.add_child(UiKit.chip(level_text, pal.ui_accent if (evolved or lvl >= total) else Color(1, 1, 1, 0.85)))
	v.add_child(top)
	if total > 1:
		var bar := MetaShop.TierBar.new()
		bar.have = lvl
		bar.total = total
		bar.color = accent
		bar.custom_minimum_size = Vector2(0, 10)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bar)
	var bl := UiKit.label(body, 19, Color(1, 1, 1, 0.8))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bl)
	if chip != "":
		v.add_child(UiKit.chip(chip, Color(pal.ui_accent, 0.9), Color(0.1, 0.06, 0.15), 15))
	return p
