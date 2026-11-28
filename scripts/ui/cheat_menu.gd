class_name CheatMenu
extends ColorRect
## TEMPORARY playtest cheat menu (balance.crazygames.cheats, Main.cheats_on).
## Opened with the CHEATS button, F2 or the ` key; the run is paused while
## it's open. Run cheats show only when opened from a run; account cheats
## always. Logic lives in Cheats (scripts/core/cheats.gd).

var pal: Dictionary
var data: Dictionary
var world: World  # null when opened from the menu
var on_close: Callable
var _scroll: DragScroll
var _body: VBoxContainer
var _cols := 3
var _toast: Label


func setup(palette: Dictionary, game_data: Dictionary, w: World, close: Callable) -> void:
	pal = palette
	data = game_data
	world = w
	on_close = close
	color = Color(0, 0, 0, 0.82)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	margin.add_child(outer)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var title := UiKit.label("CHEATS (temporary)", 38, Color("#ff7a6b"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_toast = UiKit.label("", 20, Color("#8ef0a0"))
	_toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	top.add_child(_toast)
	var close_b := UiKit.button("CLOSE (F2)", close_menu, 60, "primary")
	close_b.custom_minimum_size = Vector2(200, 60)
	close_b.add_theme_font_size_override("font_size", 22)
	top.add_child(close_b)
	outer.add_child(top)
	_scroll = DragScroll.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	_scroll.add_child(_body)
	_build.call_deferred()


func close_menu() -> void:
	Save.write()
	on_close.call()


func _build() -> void:
	var keep := _scroll.get_v_scroll_bar().value
	UiKit.clear(_body)
	_cols = clampi(int((size.x - 48.0) / 250.0), 2, 7)
	if world != null:
		_run_sections()
	_account_section()
	_body.add_child(UiKit.label("Turn this menu off for release: balance.json crazygames.cheats = false.", 18, Color(1, 1, 1, 0.45)))
	await get_tree().process_frame
	_scroll.get_v_scroll_bar().value = keep


func _section(title: String) -> GridContainer:
	var l := UiKit.label(title, 24, pal.get("ui_accent", Color.WHITE))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_body.add_child(l)
	var g := GridContainer.new()
	g.columns = _cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	_body.add_child(g)
	return g


## A cheat button. `rebuild` refreshes the labels (toggles show their state).
func _add(g: GridContainer, text: String, act: Callable, rebuild: bool = false, kind: String = "secondary") -> void:
	var b := UiKit.button(text, func() -> void: pass, 54, kind)
	b.add_theme_font_size_override("font_size", 19)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 54)
	b.mouse_filter = Control.MOUSE_FILTER_PASS  # lets DragScroll see the drag
	b.pressed.connect(func() -> void:
		if _scroll.was_dragged():
			return
		act.call()
		_say(text)
		if rebuild:
			_build())
	g.add_child(b)


func _say(text: String) -> void:
	_toast.text = "Done: " + text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func _onoff(on: bool) -> String:
	return "ON" if on else "off"


func _run_sections() -> void:
	var w := world
	var g := _section("PLAYER")
	_add(g, "God mode: " + _onoff(Cheats.god), func() -> void:
		Cheats.god = not Cheats.god
		Cheats.apply_flags(w), true, "positive" if Cheats.god else "secondary")
	var dmg_names := {1.0: "x1", 10.0: "x10", 1.0e6: "ONE-HIT"}
	_add(g, "Damage: " + str(dmg_names.get(Cheats.dmg, "x1")), func() -> void:
		Cheats.dmg = 10.0 if Cheats.dmg == 1.0 else (1.0e6 if Cheats.dmg == 10.0 else 1.0)
		Cheats.apply_flags(w), true, "positive" if Cheats.dmg != 1.0 else "secondary")
	_add(g, "XP gain: x%d" % int(Cheats.xp), func() -> void:
		Cheats.xp = 5.0 if Cheats.xp == 1.0 else (20.0 if Cheats.xp == 5.0 else 1.0)
		Cheats.apply_flags(w), true, "positive" if Cheats.xp != 1.0 else "secondary")
	_add(g, "Full heal", func() -> void: Cheats.heal(w))
	_add(g, "Fill Outbreak + ability + dash", func() -> void: Cheats.fill_meters(w))
	_add(g, "Collect all XP", func() -> void: Cheats.collect_gems(w))

	g = _section("LEVELS AND BUILD")
	_add(g, "+1 level", func() -> void: Cheats.levels(w, 1))
	_add(g, "+5 levels", func() -> void: Cheats.levels(w, 5))
	_add(g, "+10 levels", func() -> void: Cheats.levels(w, 10))
	_add(g, "Max everything owned", func() -> void: Cheats.max_owned(w))
	_add(g, "Drop a chest (3 items)", func() -> void: Cheats.chest(w, 3))
	_add(g, "Drop a chest (1 item)", func() -> void: Cheats.chest(w, 1))

	g = _section("EVOLVE NOW (maxes the weapon, adds its partner)")
	for ev in data.evolutions:
		var wid := str(ev.weapon)
		var done := w.evolved.has(wid)
		_add(g, ("EVOLVED: " if done else "") + str(ev.name), func() -> void: Cheats.evolve(w, wid), true, "positive" if done else "secondary")
	_add(g, "All evolutions", func() -> void: Cheats.evolve_all(w), true)

	g = _section("ADD ONE LEVEL OF")
	for d in w.upgrade_list:
		var id := str(d.id)
		var lv := int(w.owned.get(id, 0))
		var mx := Upgrades.max_level(d)
		_add(g, "%s  %d/%d" % [str(d.name), lv, mx], func() -> void: Cheats.add_upgrade(w, id), true, "positive" if lv >= mx else "secondary")

	g = _section("SPAWN AND CLEAR")
	_add(g, "Kill every germ", func() -> void: Cheats.kill_all(w), false, "danger")
	_add(g, "Mother Cell (boss)", func() -> void: Cheats.spawn(w, "boss"))
	_add(g, "Elite (random affix)", func() -> void: Cheats.spawn(w, _elite_type(), 1, true))
	for affix in ["charge", "brood", "volley", "magnet"]:
		var a: String = affix
		_add(g, "Elite: " + a, func() -> void: Cheats.spawn(w, _elite_type(), 1, true, a))
	_add(g, "Ring of 30 swarmers", func() -> void: Cheats.spawn(w, "swarm", 30))
	_add(g, "8 brutes", func() -> void: Cheats.spawn(w, "brute", 8))
	_add(g, "6 spitters", func() -> void: Cheats.spawn(w, "spitter", 6))
	_add(g, "6 lancers", func() -> void: Cheats.spawn(w, "charger", 6))
	_add(g, "Pickup: vacuum", func() -> void: Cheats.pickup(w, "vacuum"))
	_add(g, "Pickup: heal", func() -> void: Cheats.pickup(w, "heal"))
	_add(g, "Pickup: bomb", func() -> void: Cheats.pickup(w, "bomb"))

	g = _section("SYMPTOMS (any Virulence)")
	for e in w.bal.get("symptoms", {}).get("events", []):
		var sid := str(e.id)
		_add(g, str(e.name), func() -> void: Cheats.symptom(w, sid))

	if w.def_on:
		g = _section("NUCLEUS")
		_add(g, "+500 biomass", func() -> void: Cheats.biomass(w, 500.0))
		_add(g, "+5000 biomass", func() -> void: Cheats.biomass(w, 5000.0))
		_add(g, "Skip this wave", func() -> void: Cheats.skip_wave(w))

	g = _section("TIME AND RUN")
	_add(g, "Game speed: x%s" % str(Cheats.speed).trim_suffix(".0"), func() -> void:
		var speeds := [1.0, 2.0, 4.0, 0.5]
		Cheats.speed = speeds[(speeds.find(Cheats.speed) + 1) % speeds.size()], true, "positive" if Cheats.speed != 1.0 else "secondary")
	_add(g, "Stop spawns: " + _onoff(Cheats.no_spawn), func() -> void:
		Cheats.no_spawn = not Cheats.no_spawn
		Cheats.apply_flags(w), true, "positive" if Cheats.no_spawn else "secondary")
	if not w.def_on:
		_add(g, "+30 s", func() -> void: Cheats.skip_time(w, 30.0))
		_add(g, "+1:00", func() -> void: Cheats.skip_time(w, 60.0))
		_add(g, "Jump to 3:45 (boss)", func() -> void: Cheats.set_time(w, 225.0))
		_add(g, "Jump to 4:00 (final min)", func() -> void: Cheats.set_time(w, 240.0))
		_add(g, "Jump to 4:50", func() -> void: Cheats.set_time(w, 290.0))
	_add(g, "WIN this run", func() -> void:
		Cheats.win(w)
		close_menu(), false, "positive")
	_add(g, "DIE now", func() -> void:
		Cheats.die(w)
		close_menu(), false, "danger")


func _elite_type() -> String:
	var types: Array = data.waves.elites.types
	return str(types[randi() % types.size()])


func _account_section() -> void:
	var p := Save.profile
	var g := _section("ACCOUNT (saved; the menu refreshes on close)")
	_add(g, "+10,000 gold", func() -> void: p.dev_grant_gold(10000, Save.now()))
	_add(g, "+100,000 gold", func() -> void: p.dev_grant_gold(100000, Save.now()))
	_add(g, "+100 Genes", func() -> void: p.dev_grant_genes(100, Save.now()))
	_add(g, "+1,000 Genes", func() -> void: p.dev_grant_genes(1000, Save.now()))
	_add(g, "Max the whole shop", func() -> void: Cheats.max_shop(p, data.meta, Save.now()))
	_add(g, "Refund the shop", func() -> void: p.refund_meta(data.meta, Save.now()))
	_add(g, "Unlock every mode + menu", func() -> void: Cheats.unlock_menus(p))
	_add(g, "All Virulence levels: " + _onoff(p.dev_all_virulence()), func() -> void:
		p.settings["dev_all_virulence"] = not p.dev_all_virulence(), true, "positive" if p.dev_all_virulence() else "secondary")
	_add(g, "All cosmetics: " + _onoff(p.dev_all_cosmetics()), func() -> void:
		p.settings["dev_all_cosmetics"] = not p.dev_all_cosmetics(), true, "positive" if p.dev_all_cosmetics() else "secondary")
	_add(g, "Replay new-player start (restart game)", func() -> void: Onboarding.reset(p))
	_add(g, "Show FPS: " + _onoff(Save.show_fps == 1), func() -> void:
		Save.show_fps = 0 if Save.show_fps == 1 else 1, true)
