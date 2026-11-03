extends Node
## Game flow: menu -> run -> level-ups -> death/victory -> results -> menu.
## Owns the World (simulation), WorldView (rendering) and all UI screens.
## Everything is built in code so this file plus data/ describes the game.

var data: Dictionary
var bal: Dictionary
var pal := {}
var world: World
var view: WorldView
var hud_layer: CanvasLayer
var hud: HudOverlay
var ui_root: Control
var pause_btn: Button
var screen := "menu"  # menu | playing | levelup | chest | dead | results | paused
var hitstop := 0.0
const MAX_STEP_DT := 1.0 / 30.0

var _menu: Array
var _levelup: Array
var _dead: Array
var _results: Array
var _pause: Array
var _chest: Array
var _victory: Array  # Nucleus: COLLECT or KEEP GOING
var _countdown := 0
var _bench: Benchmark = null  # on-device benchmark in progress
var _bench_bot: BalanceBot
var _bench_perf := false
var _bench_taps := 0
var _bench_tap_ms := 0
var bench_result := ""  # last benchmark line (also read by tools/sim/bench_render.gd)
var _evo_by_passive := {}  # passive id -> evolution def
var _evo_by_weapon := {}  # weapon id -> evolution def
var _results_gold := 0
var _results_doubled := false
var _summary := {}
var _menu_bg: MenuBackground
var _new_achievements: Array = []
var _new_best := false
var _touch_index := -1


func _ready() -> void:
	data = GameData.load_all()
	var errors := GameData.validate(data)
	for e in errors:
		push_error("data: " + e)
	bal = data.balance
	for k in bal.palette:
		pal[k] = GameData.color(bal.palette[k])
	RenderingServer.set_default_clear_color(pal.background)

	view = WorldView.new()
	add_child(view)
	view.setup(data)

	hud_layer = CanvasLayer.new()
	add_child(hud_layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiKit.make_theme(pal)
	hud_layer.add_child(ui_root)

	hud = HudOverlay.new()
	hud.pal = pal
	hud.stick_radius = float(bal.juice.stick_radius)
	hud.dash_radius = float(bal.juice.dash_button_radius)
	hud.dash_margin = float(bal.juice.dash_button_margin)
	hud.elite_color = GameData.color(data.waves.elites.color)
	for ev in data.evolutions:
		_evo_by_passive[ev.requires] = ev
		_evo_by_weapon[ev.weapon] = ev
	hud.show_perf = bool(bal.get("debug", {}).get("show_perf", false))
	ui_root.add_child(hud)
	# Bake every upgrade icon (and evolved weapon icon) once for the HUD strip.
	var atlas := IconAtlas.new()
	add_child(atlas)
	var entries := []
	for u in data.upgrades:
		entries.append([u.id, IconArt.color_for(u), false])
		if _evo_by_weapon.has(u.id):
			entries.append([u.id, IconArt.color_for(u), true])
	atlas.bake(entries)
	hud.icon_atlas = atlas
	var digits := DigitAtlas.new()
	add_child(digits)
	digits.bake()
	view.digits = digits

	pause_btn = UiKit.button("II", _pause_run, 72)
	pause_btn.custom_minimum_size = Vector2(72, 72)
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-90, 28)
	ui_root.add_child(pause_btn)

	_menu = UiKit.overlay(ui_root, 0.0)
	_menu_bg = MenuBackground.new()
	_menu_bg.setup(pal, data.enemies)
	_menu[0].add_child(_menu_bg)
	_menu[0].move_child(_menu_bg, 0)
	_levelup = UiKit.overlay(ui_root)
	_dead = UiKit.overlay(ui_root)
	_results = UiKit.overlay(ui_root)
	_pause = UiKit.overlay(ui_root)
	_chest = UiKit.overlay(ui_root, 0.8)
	_victory = UiKit.overlay(ui_root, 0.8)
	_show_menu()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if screen == "menu" and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		start_benchmark()
		return
	if screen != "playing":
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		world.dash()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_E, KEY_TAB]:
		_open_banked()
		return
	if event is InputEventKey and event.pressed and not event.echo and world.def_on and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
		_build_tower(event.physical_keycode - KEY_1)
		return
	if event is InputEventScreenTouch:
		# Nucleus tower bar first (any finger), so a build tap never dashes.
		if event.pressed and world.def_on:
			var tb := hud.tower_button_at(event.position)
			if tb >= 0:
				_build_tower(tb)
				return
		# Dash: tap the DASH button, or tap with a second finger while steering.
		if event.pressed and hud.in_upgrade_button(event.position):
			_open_banked()
			return
		if event.pressed and (hud.in_dash_button(event.position) or (_touch_index != -1 and event.index != _touch_index)):
			world.dash()
			return
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			hud.stick_active = true
			hud.stick_origin = event.position
			hud.stick_pos = event.position
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			hud.stick_active = false
	elif event is InputEventScreenDrag and event.index == _touch_index:
		hud.stick_pos = event.position
		# The base appears where you touch and stays put while you hold
		# (juice.stick_follow = true restores the old drag-along base).
		if bal.juice.get("stick_follow", false):
			var off: Vector2 = hud.stick_pos - hud.stick_origin
			if off.length() > hud.stick_radius:
				hud.stick_origin = hud.stick_pos - off.normalized() * hud.stick_radius


func _move_input() -> Vector2:
	if _bench != null:
		return _bench_bot.move(world)
	var v := Vector2.ZERO
	if hud.stick_active:
		v = (hud.stick_pos - hud.stick_origin) / hud.stick_radius
		if v.length() < float(bal.juice.stick_deadzone):
			v = Vector2.ZERO
	var k := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if k != Vector2.ZERO:
		v = k.normalized()
	return v.limit_length(1.0)


func _release_stick() -> void:
	_touch_index = -1
	hud.stick_active = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if screen == "playing":
			_pause_run()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen == "playing":
			_pause_run()
		elif screen == "paused":
			_resume()


# -------------------------------------------------------------- game loop

## One simulation step per rendered frame, with dt clamped. If the phone
## can't keep up, the game slows slightly instead of running extra catch-up
## steps (which made slow frames slower: the "spiral").
func _process(delta: float) -> void:
	if screen != "playing" or world == null:
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	var t0 := Time.get_ticks_usec()
	world.step(minf(delta, MAX_STEP_DT), _move_input())
	hud.sim_ms = lerpf(hud.sim_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	hud.cam_pos = view.cam.position
	hud.fx_count = view.fx.size()
	_handle_events(world.events)
	view.consume(world.events)
	world.events.clear()
	view.cpu_ms += SpriteBatch.draw_ms  # batched sprite layers count as view too
	SpriteBatch.draw_ms = 0.0
	hud.view_ms = lerpf(hud.view_ms, view.cpu_ms, 0.1)
	if _bench != null:
		_bench_frame(delta, (Time.get_ticks_usec() - t0) / 1000.0)
		view.cpu_ms = 0.0
		hud.cpu_ms = 0.0
		return
	view.cpu_ms = 0.0
	hud.cpu_ms = 0.0
	if world.def_on:
		_tick_countdown()
	match world.state:
		"defense_won":
			_show_defense_won()
		"levelup":
			_show_levelup()
		"chest":
			_show_chest()
		"dead":
			_on_death()
		"won":
			_show_results(true)


func _handle_events(events: Array) -> void:
	for ev in events:
		match ev.type:
			"shoot":
				Sfx.play("shoot")
			"hit":
				Sfx.play("hit")
			"kill":
				Sfx.play("kill")
			"pickup":
				Sfx.play("pickup", 0.15)
			"nova":
				Sfx.play("nova")
			"chain":
				Sfx.play("chain")
			"hurt":
				Sfx.play("hurt")
				hitstop = maxf(hitstop, float(bal.juice.hitstop_hurt_s))
				Input.vibrate_handheld(40)
			"level_gained":
				Sfx.play("level_up", 0.0)
				hud.notice("LEVEL %d  +1 upgrade" % ev.level)
				hud.flash_xp()
			"upgrade":
				var def: Dictionary = world.upgrade_defs[ev.id]
				hud.notice("%s  Lv %d" % [def.name, ev.level])
			"boss_spawn":
				Sfx.play("boss", 0.0)
				Analytics.event("boss_spawn", {"t": int(world.time)})
			"boss_killed":
				Sfx.play("boss", 0.0)
				hitstop = maxf(hitstop, float(bal.juice.hitstop_boss_kill_s))
				Analytics.event("boss_killed", {"t": int(world.time)})
			"death":
				Sfx.play("death", 0.0)
				Input.vibrate_handheld(200)
			"dash":
				Sfx.play("dash")
			"claim":
				Sfx.play("claim", 0.05)
				Input.vibrate_handheld(30)
				if ev.tiles >= 25:
					hud.toast("CLAIMED +%d%%" % maxi(1, roundi(float(ev.tiles) / world.terr.dish_count * 100.0)), pal.player_nucleus, 1.2)
			"convert":
				Sfx.play("convert", 0.1)
			"swarm_feed":
				Sfx.play("convert", 0.0)
				var feeds := roundi(float(ev.power) / float(world.bal.conversion.feed_power))
				if feeds == 1 or feeds % 5 == 0:
					hud.toast("SWARM FED +%d%%" % roundi(ev.power * 100.0), pal.player_nucleus, 1.2)
			"trail_lost":
				Sfx.play("hurt", 0.0)
				hud.toast("Trail lost", pal.player_hurt, 1.0)
			"elite_spawn":
				Sfx.play("elite", 0.0)
				hud.toast("ELITE GERM!", hud.elite_color, 1.8)
			"elite_killed":
				Sfx.play("boss", 0.1)
				Input.vibrate_handheld(60)
			"evolution_ready":
				hud.toast("EVOLUTION READY", pal.ui_accent, 2.4)
				hud.toast("Kill an elite for a chest", Color(pal.text, 0.9), 2.4)
			"wave_start":
				if ev.boss:
					Sfx.play("boss", 0.0)
					Input.vibrate_handheld(120)
					view.add_shake(10.0)
					hud.toast("MOTHER CELL!", pal.player_hurt, 2.2)
				else:
					Sfx.play("elite", 0.0)
					hud.toast("WAVE %d" % ev.wave, pal.core, 1.6)
			"free_mode":
				hud.toast("FREE MODE", pal.core, 2.0)
				hud.toast("Endless waves. How far can you go?", Color(pal.text, 0.9), 2.4)
				Analytics.event("free_mode_start", {"t": int(world.time)})
			"wave_clear":
				Sfx.play("level_up", 0.0)
				hud.toast("WAVE %d CLEARED  +%d biomass" % [ev.wave, ev.bonus], pal.pad, 1.6)
				Analytics.event("wave_clear", {"wave": ev.wave, "t": int(world.time), "core": roundi(world.core_hp)})
			"core_hit":
				Sfx.play("hurt", 0.2, 0.7)
			"tower_built", "tower_upgraded":
				Sfx.play("upgrade", 0.0, 1.0 + 0.08 * ev.level)
				Input.vibrate_handheld(40)
				hud.toast("%s %s" % [str(ev.name).to_upper(), "BUILT" if ev.type == "tower_built" else "LV %d" % ev.level], GameData.color(ev.color), 1.4)
				Analytics.event("tower_build", {"level": ev.level, "wave": world.wave})
			"player_down":
				Sfx.play("death", 0.0)
				Input.vibrate_handheld(200)
			"respawn":
				Sfx.play("heal", 0.0)
			"pickup_item":
				match ev.kind:
					"vacuum":
						Sfx.play("vacuum", 0.0)
						hud.toast("VACUUM!", pal.gem_small, 1.2)
					"heal":
						Sfx.play("heal", 0.0)
						hud.toast("+HEALTH", pal.gem_medium, 1.2)
					"bomb":
						Sfx.play("bomb", 0.0)
						hud.toast("BOOM!", pal.enemy_shot, 1.2)
						Input.vibrate_handheld(120)
				Analytics.event("pickup", {"kind": ev.kind, "t": int(world.time)})


func _start_run() -> void:
	var meta := Progression.meta_bonus(data.meta, Save.meta_levels)
	world = World.new(GameData.apply_mode(data, _current_mode().id), randi(), meta)
	view.set_world(world)
	hud.world = world
	hitstop = 0.0
	Analytics.event("run_start", {"run": Save.runs + 1, "mode": _current_mode().id})
	if world.terr != null:
		hud.toast("Loop out and back to claim land", pal.player_nucleus, 3.0)
	if world.conv_on:
		hud.toast("Kills join your swarm. They guard you.", pal.player_nucleus, 3.0)
	_hide_all()
	_set_screen("playing")


func _set_screen(s: String) -> void:
	screen = s
	# Battery: only gameplay runs at the screen's full rate (90/120 Hz).
	# Menus and pickers still animate smoothly at 60; pause barely moves.
	Engine.max_fps = int(bal.perf.get("menu_max_fps", 60)) if s != "playing" else 0
	if s == "paused":
		Engine.max_fps = int(bal.perf.get("pause_max_fps", 30))
	var in_run := s in ["playing", "levelup", "chest", "dead", "paused", "defense_won"]
	hud.visible = in_run
	pause_btn.visible = s == "playing"
	view.visible = s != "menu"
	if s != "playing":
		_release_stick()


func _hide_all() -> void:
	for o in [_menu, _levelup, _dead, _results, _pause, _chest, _victory]:
		o[0].visible = false


# ------------------------------------------------------------------- menu

func _show_menu() -> void:
	_hide_all()
	_set_screen("menu")
	_menu_bg.visible = true
	_menu_bg.show_hero = true
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	col.add_theme_constant_override("separation", 16)
	# Top row: gold pill on the right.
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(_gold_pill())
	col.add_child(top)
	var title := UiKit.label(str(bal.title).to_upper(), 82, pal.ui_accent)
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.14))
	col.add_child(title)
	col.add_child(UiKit.label("You are the infection.", 26, Color(pal.text, 0.75)))
	# Room for the animated hero cell drawn by the background.
	var hero := Control.new()
	hero.custom_minimum_size = Vector2(0, 230)
	hero.item_rect_changed.connect(func() -> void:
		if _menu_bg.size.y > 0.0:
			_menu_bg.hero_y = (hero.global_position.y + hero.size.y / 2.0) / _menu_bg.size.y)
	col.add_child(hero)
	# Mode cards.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var current := _current_mode()
	for m in data.modes:
		row.add_child(_mode_card(m, m.id == current.id))
	col.add_child(row)
	col.add_child(UiKit.label(current.desc, 22, Color(pal.text, 0.8)))
	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(0, 130)
	play.add_theme_font_size_override("font_size", 52)
	var ps := UiKit._box(pal.ui_accent, 26)
	play.add_theme_stylebox_override("normal", ps)
	play.add_theme_stylebox_override("hover", ps)
	play.add_theme_stylebox_override("pressed", UiKit._box(pal.ui_accent.darkened(0.15), 26))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		play.add_theme_color_override(c, Color(0.12, 0.07, 0.2))
	play.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		_start_run())
	col.add_child(play)
	play.resized.connect(func() -> void: play.pivot_offset = play.size / 2.0)
	var pulse := play.create_tween().set_loops()
	pulse.tween_property(play, "scale", Vector2(1.03, 1.03), 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(play, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	# Bottom row: upgrades, profile, sound.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	bottom.add_child(_tile_button("gold", pal.ui_accent, "UPGRADES", _show_shop))
	bottom.add_child(_tile_button("trophy", pal.ui_accent, "PROFILE", _show_profile))
	bottom.add_child(_tile_button("sound_off" if Save.muted else "sound_on", pal.player_nucleus, "SOUND", _toggle_mute))
	col.add_child(bottom)
	# The build label doubles as the hidden benchmark trigger (tap 5 times).
	var build := UiKit.label(_build_label(), 16, Color(pal.text, 0.35))
	build.mouse_filter = Control.MOUSE_FILTER_STOP
	build.gui_input.connect(_on_build_label_input)
	col.add_child(build)
	_menu[0].visible = true


func _gold_pill() -> Control:
	var pill := PanelContainer.new()
	var sb := UiKit._box(Color(0.08, 0.05, 0.14, 0.85), 26, 14)
	sb.set_border_width_all(2)
	sb.border_color = Color(pal.ui_accent, 0.7)
	pill.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UpgradeIcon.make("gold", pal.ui_accent, 36))
	var amount := UiKit.label(str(Save.gold), 28, pal.ui_accent)
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(amount)
	pill.add_child(h)
	return pill


## A selectable mode card: icon, name, tag and the mode's own best record.
func _mode_card(m: Dictionary, selected: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 196)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent := GameData.color(m.get("color", "#ffd166"))
	var sb := UiKit._box(Color("#3d2d6b") if selected else Color("#2a1f4a"), 20, 10)
	sb.set_border_width_all(4 if selected else 2)
	sb.border_color = accent if selected else Color(accent, 0.3)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		_select_mode(m.id))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	var ic := UpgradeIcon.make(m.get("icon", ""), accent, 72)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var name := UiKit.label(str(m.name).to_upper(), 24, Color.WHITE if selected else Color(1, 1, 1, 0.75))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	var rec := Save.profile.record(m.id)
	var sub := "Best %s" % UiKit.fmt_time(float(rec.get("best_time", 0.0)))
	if rec.has(m.get("special", "")) and int(rec[m.special]) > 0:
		sub = str(m.special_label) % int(rec[m.special])
	var subl := UiKit.label(sub if int(rec.get("runs", 0)) > 0 else "Not played yet", 17, Color(accent, 0.9))
	subl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(subl)
	if m.get("tag", "") != "":
		var tag := UiKit.label(m.tag, 15, pal.ui_accent)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag)
	b.add_child(v)
	return b


## Square-ish button with an icon over a label (menu bottom row).
func _tile_button(icon_key: String, accent: Color, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 112)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		on_press.call())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UpgradeIcon.make(icon_key, accent, 52)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UiKit.label(text, 20, Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.add_child(v)
	return b


## Lifetime stats, per-mode records and achievements.
func _show_profile() -> void:
	_menu_bg.show_hero = false
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	col.add_theme_constant_override("separation", 12)
	col.add_child(UiKit.label("PROFILE", 52, pal.ui_accent))
	var online := "Local profile" if not Online.is_signed_in() else Online.player_name()
	col.add_child(UiKit.label(online + "  -  Play Games sync coming soon", 18, Color(pal.text, 0.5)))
	var scroll := DragScroll.new()
	scroll.custom_minimum_size = Vector2(600, 900)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	col.add_child(scroll)
	var st: Dictionary = Save.profile.stats
	list.add_child(_section("LIFETIME"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for pair in [["Runs", st.runs], ["Wins", st.wins], ["Germs killed", st.kills], ["Time played", UiKit.fmt_time(float(st.time_played))],
			["Elites killed", st.elites], ["Mother Cells", st.bosses], ["Evolutions found", "%d / %d" % [st.evolved_ids.size(), data.evolutions.size()]],
			["Germs converted", st.conversions], ["Dashes", st.dashes], ["Gold earned", st.gold_earned], ["Highest level", st.best_level]]:
		var k := UiKit.label(str(pair[0]), 22, Color(pal.text, 0.7))
		k.autowrap_mode = TextServer.AUTOWRAP_OFF
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var v := UiKit.label(str(pair[1]), 22, pal.text)
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
	list.add_child(grid)
	list.add_child(_section("BEST RUNS"))
	for m in data.modes:
		var r := Save.profile.record(m.id)
		var line := "%s:  %s, %d kills, score %d" % [m.name, UiKit.fmt_time(float(r.get("best_time", 0.0))), int(r.get("best_kills", 0)), int(r.get("best_score", 0))]
		if int(r.get(m.get("special", ""), 0)) > 0 and m.special != "best_kills":
			line += ", " + (str(m.special_label) % int(r[m.special])).to_lower()
		var l := UiKit.label(line if int(r.get("runs", 0)) > 0 else "%s:  not played yet" % m.name, 21, pal.text)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(l)
	var achs: Array = data.online.achievements
	list.add_child(_section("ACHIEVEMENTS  %d / %d" % [Save.profile.achievements.size(), achs.size()]))
	for a in achs:
		var done: bool = Save.profile.achievements.has(a.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(UpgradeIcon.make("trophy", pal.ui_accent if done else Color(1, 1, 1, 0.25), 48))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm := UiKit.label(a.name, 22, pal.ui_accent if done else pal.text)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(nm)
		var prog := Save.profile.achievement_progress(a)
		var have := minf(float(Save.profile.flat().get(a.stat, 0)), float(a.goal))
		var ds := UiKit.label("%s   %s" % [a.desc, "done" if done else "%d / %d" % [int(have), int(a.goal)]], 18, Color(pal.text, 0.65))
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(ds)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE  # don't block drag-scrolling
		bar.value = prog * 100.0
		v.add_child(bar)
		row.add_child(v)
		list.add_child(row)
	col.add_child(UiKit.button("BACK", _show_menu, 90))


func _section(text: String) -> Label:
	var l := UiKit.label(text, 24, pal.ui_accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _current_mode() -> Dictionary:
	for m in data.modes:
		if m.id == Save.mode:
			return m
	return data.modes[0]


func _select_mode(id: String) -> void:
	Save.mode = id
	Save.write()
	_show_menu()


## Permanent upgrades bought with gold: tile grid + detail popup (MetaShop).
func _show_shop() -> void:
	_menu_bg.show_hero = false
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	var shop := MetaShop.new()
	shop.setup(data.meta, pal, _menu[0], _show_menu)
	col.add_child(shop)


## "build abc1234 #12" from data/build_info.json (written by CI), else "dev build".
func _build_label() -> String:
	if not FileAccess.file_exists("res://data/build_info.json"):
		return "dev build"
	var info: Variant = GameData.load_json("res://data/build_info.json")
	if info is Dictionary and info.has("sha"):
		return "build %s  #%s" % [info.sha, str(info.get("run", "?"))]
	return "dev build"


func world_length() -> float:
	return float(bal.run_length_s)


func _toggle_mute() -> void:
	Save.muted = not Save.muted
	Save.write()
	_show_menu()


# --------------------------------------------------------------- level-up

func _show_levelup() -> void:
	_set_screen("levelup")
	var col: VBoxContainer = _levelup[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("UPGRADE", 56, pal.ui_accent))
	col.add_child(UiKit.label("Choose one  -  %d to spend" % world.pending_levelups, 26, Color(pal.text, 0.8)))
	var buttons: Array[Button] = []
	var k := 0
	for id in world.offers:
		var def: Dictionary = world.upgrade_defs[id]
		var nl := world.next_level_of(id)
		var tag := ("NEW " + ("WEAPON" if def.type == "weapon" else "PASSIVE")) if nl == 1 else "Lv %d" % nl
		var accent := IconArt.color_for(def)
		var icon := UpgradeIcon.make(id, accent, 96)
		var b := UiKit.icon_card(icon, "%s   %s" % [def.name, tag], Upgrades.describe(def, nl), _evolution_hint(id, nl),
			nl - 1, nl, Upgrades.max_level(def), accent, _pick.bind(id), 160)
		col.add_child(b)
		buttons.append(b)
		_pop_in(b, k * 0.07)
		k += 1
	var reroll := UiKit.button("Reroll  (watch ad)", _reroll, 80)
	reroll.add_theme_font_size_override("font_size", 24)
	reroll.visible = Ads.is_rewarded_available()
	col.add_child(reroll)
	buttons.append(reroll)
	var later := UiKit.button("Later  (keep %d banked)" % world.pending_levelups, _later, 72)
	later.add_theme_font_size_override("font_size", 22)
	col.add_child(later)
	buttons.append(later)
	_levelup[0].visible = true
	# Ignore taps for a moment so a finger still dragging can't mis-pick.
	for b in buttons:
		b.disabled = true
	await get_tree().create_timer(float(bal.juice.levelup_input_delay_s)).timeout
	for b in buttons:
		if is_instance_valid(b):
			b.disabled = false


## "Evolves with X" style hint for a level-up card, or "".
func _evolution_hint(id: String, next_level: int) -> String:
	if _evo_by_passive.has(id):
		var ev: Dictionary = _evo_by_passive[id]
		if not world.evolved.has(ev.weapon):
			return "* Evolves max %s" % world.upgrade_defs[ev.weapon].name
	if _evo_by_weapon.has(id) and next_level == Upgrades.max_level(world.upgrade_defs[id]):
		var ev: Dictionary = _evo_by_weapon[id]
		return "* MAX: + %s = %s" % [world.upgrade_defs[ev.requires].name, ev.name]
	return ""


# ------------------------------------------------------------------ chest

## Slot-machine style reveal: names spin, then the real rewards land.
func _show_chest() -> void:
	_set_screen("chest")
	var rewards: Array = world.chest_rewards.duplicate()
	Sfx.play("chest", 0.0)
	Input.vibrate_handheld(50)
	Analytics.event("chest_open", {"items": rewards.size(), "t": int(world.time)})
	var col: VBoxContainer = _chest[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("CHEST!", 60, pal.gem_large))
	var slots: Array[Label] = []
	var icons: Array[UpgradeIcon] = []
	var keys := []
	for u in data.upgrades:
		keys.append(u.id)
	for r in rewards:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 18)
		var ic := UpgradeIcon.make(keys[0], pal.ui_accent, 104)
		row.add_child(ic)
		icons.append(ic)
		var l := UiKit.label("?", 36, pal.text)
		l.custom_minimum_size = Vector2(380, 120)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		col.add_child(row)
		slots.append(l)
	_chest[0].visible = true
	var names := []
	for u in data.upgrades:
		names.append(u.name)
	for ev in data.evolutions:
		names.append(ev.name)
	# Spin, slowing down, then land each slot in turn.
	var delay := 0.05
	for step in 12:
		for k in slots.size():
			if is_instance_valid(slots[k]):
				slots[k].text = names[randi() % names.size()]
				icons[k].key = keys[randi() % keys.size()]
				icons[k].color = IconArt.color_for(world.upgrade_defs[icons[k].key])
				icons[k].queue_redraw()
		Sfx.play("click", 0.3)
		await get_tree().create_timer(delay).timeout
		delay *= 1.13
	for k in slots.size():
		if not is_instance_valid(slots[k]):
			return
		var r: Dictionary = rewards[k]
		var evo: bool = r.kind == "evolution"
		var head := "EVOLUTION!\n" if evo else ""
		var lvl := "  Lv %d" % r.level if r.kind == "upgrade" else ""
		slots[k].text = "%s%s%s\n%s" % [head, r.name, lvl, r.desc]
		var ic := icons[k]
		ic.evolved = evo
		if evo:
			for ev in data.evolutions:
				if ev.id == r.id:
					ic.key = ev.weapon
					ic.color = GameData.color(ev.color)
		elif r.kind == "upgrade":
			ic.key = r.id
			ic.color = IconArt.color_for(world.upgrade_defs[r.id])
		else:
			ic.key = "regen"
			ic.color = pal.gem_medium
		ic.queue_redraw()
		var tw := ic.create_tween()
		ic.pivot_offset = ic.size / 2.0
		ic.scale = Vector2(1.35, 1.35)
		tw.tween_property(ic, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		slots[k].add_theme_color_override("font_color", pal.ui_accent if evo else pal.text)
		slots[k].add_theme_font_size_override("font_size", 40 if evo else 32)
		if evo:
			Sfx.play("evolve", 0.0)
			Input.vibrate_handheld(150)
			view.add_shake(14.0)
			Analytics.event("evolution", {"id": r.id, "t": int(world.time)})
		else:
			Sfx.play("level_up", 0.0)
		await get_tree().create_timer(0.35).timeout
	if is_instance_valid(col):
		col.add_child(UiKit.button("CONTINUE", _close_chest, 110))


func _close_chest() -> void:
	_chest[0].visible = false
	world.close_chest()
	if world.state == "levelup":
		_show_levelup()
	else:
		_set_screen("playing")


## Opens the picker for a banked level-up (UPGRADE button, E or Tab).
func _open_banked() -> void:
	if screen == "playing" and world.open_banked():
		_release_stick()
		_show_levelup()


func _later() -> void:
	world.close_levelup()
	_levelup[0].visible = false
	_set_screen("playing")


## Card entrance: fade and scale in, staggered.
func _pop_in(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.9, 0.9)
	c.resized.connect(func() -> void: c.pivot_offset = c.size / 2.0)
	var tw := c.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.18).set_delay(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.25).set_delay(delay)


func _pick(id: String) -> void:
	world.choose_upgrade(id)
	Analytics.event("upgrade_pick", {"id": id, "level": world.owned[id], "t": int(world.time)})
	if world.state == "levelup":
		_show_levelup()
	else:
		_levelup[0].visible = false
		_set_screen("playing")


func _reroll() -> void:
	Ads.show_rewarded("reroll", func(ok: bool) -> void:
		if ok:
			world.reroll_offers()
		_show_levelup())


# ------------------------------------------------------------ death / end

func _on_death() -> void:
	_set_screen("dead")
	Analytics.event("death", {"t": int(world.time), "level": world.level, "cause": world.death_cause})
	# Nucleus mode: the run ends with the nucleus (the player respawns), so
	# there is nothing to revive (a nucleus-repair ad comes in step 3).
	var can_revive := not world.def_on and world.revives_used < int(bal.revive.max_per_run) and Ads.is_rewarded_available()
	if not can_revive:
		_show_results(world.free_mode)  # losing the nucleus in Free Mode is still a won run
		return
	var col: VBoxContainer = _dead[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("YOU WERE CONSUMED", 48, pal.player_hurt))
	col.add_child(UiKit.label("Survived %s" % UiKit.fmt_time(world.time), 32))
	col.add_child(UiKit.button("REVIVE  (watch ad)", _revive, 130))
	col.add_child(UiKit.button("No thanks", func() -> void: _show_results(false), 80))
	_dead[0].visible = true


func _revive() -> void:
	Ads.show_rewarded("revive", func(ok: bool) -> void:
		if not ok:
			return
		world.revive()
		view.consume(world.events)
		world.events.clear()
		_dead[0].visible = false
		_set_screen("playing"))


func _show_results(won: bool) -> void:
	_hide_all()
	_set_screen("results")
	_results_gold = Progression.run_gold(bal, world.kills, world.time, world.boss_killed, won, float(world.stats.gold_gain))
	_results_doubled = false
	# Progress tracking: lifetime stats, per-mode records, achievements and
	# leaderboard submissions (local stub until Play Games is connected).
	var mid: String = _current_mode().id
	var prev_best := int(Save.profile.record(mid).get("best_score", 0))
	_summary = Progression.run_summary(world, won, mid, data.online.score)
	_new_achievements = Save.profile.record_run(_summary, data.online.achievements, Save.now())
	_new_best = int(_summary.score) > prev_best
	Online.report_run(_summary, data.online.leaderboards, _new_achievements)
	Save.write()
	Analytics.event("run_end", {"won": won, "t": int(world.time), "level": world.level, "kills": world.kills, "gold": _results_gold, "elites": world.elites_killed, "chests": world.chests_opened, "evolutions": world.evolved.size(), "dashes": world.dashes, "infected": snappedf(world.terr.infected_fraction(), 0.01) if world.terr != null else -1.0, "conversions": world.conversions, "mode": _current_mode().id})
	_build_results(won)


func _build_results(won: bool) -> void:
	var col: VBoxContainer = _results[1]
	UiKit.clear(col)
	var head := "YOU SURVIVED!" if won else "RUN OVER"
	if world.def_on:
		head = "NUCLEUS DEFENDED!" if won and not world.free_mode else ("FREE MODE OVER" if world.free_mode else "NUCLEUS LOST")
	col.add_child(UiKit.label(head, 56, pal.ui_accent))
	col.add_child(UiKit.label("Time %s    Level %d    Kills %d" % [UiKit.fmt_time(world.time), world.level, world.kills], 28))
	if world.terr != null:
		col.add_child(UiKit.label("Dish infected: %d%%" % roundi(world.terr.infected_fraction() * 100.0), 32, pal.player_nucleus))
	if world.conv_on:
		col.add_child(UiKit.label("Germs converted: %d" % world.conversions, 32, pal.player_nucleus))
	if world.def_on:
		if world.free_mode:
			col.add_child(UiKit.label("Free Mode: reached wave %d    Towers: %d" % [world.wave, world.towers_built], 30, pal.core))
		else:
			col.add_child(UiKit.label("Waves cleared: %d / %d    Towers: %d" % [world.waves_cleared, world.wave_count, world.towers_built], 30, pal.core))
	col.add_child(UiKit.label("Score %d%s" % [int(_summary.score), "   NEW BEST!" if _new_best else ""], 32, pal.ui_accent if _new_best else pal.text))
	for a in _new_achievements:
		col.add_child(UiKit.label("Achievement: %s" % a.name, 26, pal.gem_medium))
	col.add_child(UiKit.label("+%d gold" % _results_gold, 48, pal.gem_large))
	if not _results_doubled and Ads.is_rewarded_available():
		col.add_child(UiKit.button("DOUBLE GOLD  (watch ad)", func() -> void:
			Ads.show_rewarded("double_gold", func(ok: bool) -> void:
				if ok and not _results_doubled:
					_results_doubled = true
					_results_gold *= 2
				_build_results(won)), 120))
	col.add_child(UiKit.button("PLAY AGAIN", _collect.bind(true), 110))
	col.add_child(UiKit.button("Menu", _collect.bind(false), 80))
	_results[0].visible = true


func _collect(again: bool) -> void:
	Save.profile.add_gold(_results_gold, Save.now())
	_results_gold = 0
	Save.write()
	var next := _start_run if again else _show_menu
	var a: Dictionary = bal.ads
	var due := Save.deaths > 0 and Save.deaths % int(a.interstitial_every_deaths) == 0
	if due and Save.runs >= int(a.min_runs_before_interstitial) and not _results_doubled:
		Ads.show_interstitial("between_runs", next)
	else:
		next.call()


# ------------------------------------------------------------------ pause

func _pause_run() -> void:
	if screen != "playing":
		return
	_set_screen("paused")
	var col: VBoxContainer = _pause[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("PAUSED", 56, pal.ui_accent))
	col.add_child(UiKit.button("RESUME", _resume, 120))
	col.add_child(UiKit.button("Quit run", func() -> void: _show_results(false), 80))
	_pause[0].visible = true


func _resume() -> void:
	_pause[0].visible = false
	_set_screen("playing")


# ------------------------------------------------------- Nucleus mode UI

## 3-2-1 ticks at the end of each breather (the HUD draws the big numbers).
func _tick_countdown() -> void:
	var n := ceili(world.wave_t) if world.wave_state == "breather" and world.state == "playing" else 0
	if n != _countdown:
		_countdown = n
		if n >= 1 and n <= 3:
			Sfx.play("click", 0.0, 1.6 - 0.15 * n)
			Input.vibrate_handheld(15)


## Tower bar tap (or keys 1-4): build on the empty pad you're standing on.
## The game keeps running.
func _build_tower(t: int) -> void:
	if not world.build_tower(t):
		Sfx.play("deny", 0.0)
		Input.vibrate_handheld(25)


## Wave 12 cleared: take the win or keep going into endless waves.
func _show_defense_won() -> void:
	_set_screen("defense_won")
	Sfx.play("evolve", 0.0)
	Input.vibrate_handheld(150)
	var col: VBoxContainer = _victory[1]
	UiKit.clear(col)
	var head := UiKit.label("NUCLEUS DEFENDED!", 56, pal.ui_accent)
	head.add_theme_constant_override("outline_size", 12)
	head.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.14))
	col.add_child(head)
	col.add_child(UiKit.label("All %d waves cleared in %s" % [world.wave_count, UiKit.fmt_time(world.time)], 30))
	col.add_child(UiKit.label("Keep going for endless waves: bigger swarms, more elites, a Mother Cell every %d waves. The run already counts as a win." % int(bal.defense.free_boss_every), 24, Color(pal.text, 0.8)))
	var keep := UiKit.button("KEEP GOING  (Free Mode)", _keep_going, 130)
	var sb := UiKit._box(MetaShop.GREEN, 26)
	keep.add_theme_stylebox_override("normal", sb)
	keep.add_theme_stylebox_override("hover", sb)
	keep.add_theme_stylebox_override("pressed", UiKit._box(MetaShop.GREEN_DARK, 26))
	col.add_child(keep)
	col.add_child(UiKit.button("COLLECT", _collect_win, 100))
	_victory[0].visible = true
	_pop_in(head, 0.0)


func _keep_going() -> void:
	world.start_free_mode()
	_victory[0].visible = false
	_set_screen("playing")


func _collect_win() -> void:
	world.collect_win()
	_victory[0].visible = false
	_show_results(true)


# ------------------------------------------------- on-device benchmark

func _on_build_label_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	var now := Time.get_ticks_msec()
	_bench_taps = _bench_taps + 1 if now - _bench_tap_ms < 1500 else 1
	_bench_tap_ms = now
	if _bench_taps >= 5:
		_bench_taps = 0
		start_benchmark()


## Fixed, bot-driven, invincible Classic fight at a high-load moment, 45 s.
## Nothing is saved or reported as a run. See Benchmark and docs/POLISH_PLAN.md.
func start_benchmark() -> void:
	var d := GameData.apply_mode(data, Benchmark.MODE)
	d.balance.debug.invincible = true
	world = World.new(d, Benchmark.SEED, {})
	world.time = Benchmark.START_TIME
	for id in Benchmark.LOADOUT:
		world.owned[id] = int(Benchmark.LOADOUT[id])
	world._recompute_stats()
	world.p_hp = world.p_max_hp
	view.set_world(world)
	hud.world = world
	hitstop = 0.0
	_bench = Benchmark.new()
	_bench.platform = OS.get_name().to_lower()
	_bench.build = _build_label().replace("build ", "")
	_bench.refresh = DisplayServer.screen_get_refresh_rate()
	_bench_bot = BalanceBot.new(Benchmark.SEED)
	_bench_perf = hud.show_perf
	hud.show_perf = false  # same HUD load on every device
	_hide_all()
	_set_screen("playing")


func _bench_frame(delta: float, sim_ms: float) -> void:
	# Upgrades and chests are applied silently so the scenario never stops.
	if world.pending_levelups > 0 and world.state == "playing":
		world.open_banked()
	while world.state == "levelup":
		world.choose_upgrade(_bench_bot.pick(world))
	if world.state == "chest":
		world.close_chest()
	if _bench.advance(delta):
		_bench.add(delta * 1000.0, sim_ms, view.cpu_ms, hud.cpu_ms,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), world.enemy_count(), view.fx.size())
	hud.bench_text = "BENCHMARK  %d" % _bench.seconds_left() if _bench.t > Benchmark.WARMUP_S else "BENCHMARK  warming up"
	if _bench.is_done():
		_finish_benchmark()


func _finish_benchmark() -> void:
	bench_result = _bench.line()
	print(bench_result)
	var s := _bench.summary()
	Analytics.event("benchmark", {"v": s.version, "fps": s.fps, "p95": s.frame_p95, "slow": s.slow_pct, "refresh": s.refresh, "sim": s.sim, "view": s.view})
	_bench = null
	hud.show_perf = _bench_perf
	hud.bench_text = ""
	_set_screen("results")
	var col: VBoxContainer = _results[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("BENCHMARK DONE", 52, pal.ui_accent))
	col.add_child(UiKit.label("%.0f fps average  (screen: %s)" % [s.fps, ("%d Hz" % s.refresh) if s.refresh > 0 else "rate unknown"], 30))
	var l := UiKit.label(bench_result, 20, Color(pal.text, 0.85))
	col.add_child(l)
	col.add_child(UiKit.label("Copy this line and paste it to Claude.", 22, Color(pal.text, 0.6)))
	col.add_child(UiKit.button("COPY", func() -> void:
		DisplayServer.clipboard_set(bench_result)
		hud.toast("Copied", pal.ui_accent, 1.0), 100))
	col.add_child(UiKit.button("DONE", _show_menu, 80))
	_results[0].visible = true
