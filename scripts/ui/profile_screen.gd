class_name ProfileScreen
extends VBoxContainer
## Profile: lifetime stat tiles, a best-run card per mode, and achievements
## with progress bars. Same visual language as the upgrades shop. Read-only;
## everything comes from Save.profile and the data tables.

const TILE_BG := Color("#2a1f4a")

var pal: Dictionary
var data: Dictionary


func setup(palette: Dictionary, game_data: Dictionary, back: Callable) -> void:
	pal = palette
	data = game_data
	custom_minimum_size = Vector2(640, 0)
	add_theme_constant_override("separation", 12)
	add_child(UiKit.label("PROFILE", 50, pal.ui_accent))
	var who := "Local profile" if not Online.is_signed_in() else Online.player_name()
	add_child(UiKit.label(who + "  -  Play Games sync coming soon", 18, Color(pal.text, 0.5)))
	var scroll := DragScroll.new()
	scroll.custom_minimum_size = Vector2(640, 920)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)
	add_child(scroll)
	_lifetime(list)
	_best_runs(list)
	_achievements(list)
	add_child(UiKit.button("BACK", back, 90))


func _section(text: String) -> Label:
	var l := UiKit.label(text, 24, pal.ui_accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _fixed(text: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _lifetime(list: VBoxContainer) -> void:
	var st: Dictionary = Save.profile.stats
	list.add_child(_section("LIFETIME"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var tiles := [
		["Runs", str(st.runs)], ["Wins", str(st.wins)], ["Germs killed", str(st.kills)],
		["Time played", UiKit.fmt_time(float(st.time_played))], ["Elites", str(st.elites)], ["Mother Cells", str(st.bosses)],
		["Evolutions", "%d / %d" % [st.evolved_ids.size(), data.evolutions.size()]], ["Converted", str(st.conversions)], ["Dashes", str(st.dashes)],
		["Gold earned", str(st.gold_earned)], ["Best level", str(st.best_level)],
	]
	for t in tiles:
		var p := UiKit.panel(TILE_BG, Color(1, 1, 1, 0.06), 16, 10)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(_fixed(str(t[1]), 30, pal.text, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_fixed(str(t[0]), 17, Color(pal.text, 0.6), HORIZONTAL_ALIGNMENT_CENTER))
		p.add_child(v)
		grid.add_child(p)
	list.add_child(grid)


func _best_runs(list: VBoxContainer) -> void:
	list.add_child(_section("BEST RUNS"))
	for m in data.modes:
		var r := Save.profile.record(m.id)
		var accent := GameData.color(m.get("color", "#ffd166"))
		var played := int(r.get("runs", 0)) > 0
		var p := UiKit.panel(TILE_BG, Color(accent, 0.6 if played else 0.2), 18, 12)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var ic := UpgradeIcon.make(m.get("icon", ""), accent if played else Color(accent, 0.4), 60)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 2)
		v.add_child(_fixed(str(m.name).to_upper(), 24, pal.text))
		if played:
			var line := "Score %d  ·  %d kills  ·  %d %s" % [int(r.get("best_score", 0)), int(r.get("best_kills", 0)), int(r.runs), "run" if int(r.runs) == 1 else "runs"]
			if int(r.get(m.get("special", ""), 0)) > 0 and m.special != "best_kills":
				line += "  ·  " + (str(m.special_label) % int(r[m.special])).to_lower()
			v.add_child(_fixed(line, 18, Color(pal.text, 0.65)))
		else:
			v.add_child(_fixed("Not played yet", 18, Color(pal.text, 0.45)))
		h.add_child(v)
		if played:
			var best := _fixed(UiKit.fmt_time(float(r.get("best_time", 0.0))), 32, accent, HORIZONTAL_ALIGNMENT_RIGHT)
			best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(best)
		p.add_child(h)
		list.add_child(p)


func _achievements(list: VBoxContainer) -> void:
	var achs: Array = data.online.achievements
	var done_n := Save.profile.achievements.size()
	list.add_child(_section("ACHIEVEMENTS  %d / %d" % [done_n, achs.size()]))
	var total := Bar.new()
	total.value = float(done_n) / maxf(achs.size(), 1)
	total.color = pal.ui_accent
	total.custom_minimum_size = Vector2(0, 12)
	list.add_child(total)
	# Done ones first, then by progress.
	var rows := []
	for a in achs:
		rows.append([Save.profile.achievements.has(a.id), Save.profile.achievement_progress(a), a])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] and not y[0] or (x[0] == y[0] and x[1] > y[1]))
	var flat := Save.profile.flat()
	for row in rows:
		var done: bool = row[0]
		var a: Dictionary = row[2]
		var p := UiKit.panel(TILE_BG, Color(pal.ui_accent, 0.7) if done else Color(1, 1, 1, 0.05), 16, 12)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var ic := UpgradeIcon.make("trophy", pal.ui_accent if done else Color(1, 1, 1, 0.25), 48)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 4)
		var top := HBoxContainer.new()
		var nm := _fixed(a.name, 22, pal.ui_accent if done else pal.text)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var have := minf(float(flat.get(a.stat, 0)), float(a.goal))
		top.add_child(_fixed("DONE" if done else "%d / %d" % [int(have), int(a.goal)], 18, pal.ui_accent if done else Color(pal.text, 0.6), HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(top)
		var ds := UiKit.label(a.desc, 18, Color(pal.text, 0.6))
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(ds)
		if not done:
			var bar := Bar.new()
			bar.value = float(row[1])
			bar.color = Color(pal.player_nucleus, 0.9)
			bar.custom_minimum_size = Vector2(0, 8)
			v.add_child(bar)
		h.add_child(v)
		p.add_child(h)
		list.add_child(p)


## Rounded progress bar (ignores input so it never blocks drag-scrolling).
class Bar:
	extends Control
	var value := 0.0
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := size.y / 2.0
		_pill(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.1), r)
		if value > 0.0:
			_pill(Rect2(Vector2.ZERO, Vector2(maxf(size.x * clampf(value, 0.0, 1.0), size.y), size.y)), color, r)

	func _pill(rc: Rect2, c: Color, r: float) -> void:
		draw_rect(Rect2(rc.position + Vector2(r, 0), rc.size - Vector2(r * 2.0, 0)), c)
		draw_circle(rc.position + Vector2(r, r), r, c)
		draw_circle(rc.position + Vector2(rc.size.x - r, r), r, c)
