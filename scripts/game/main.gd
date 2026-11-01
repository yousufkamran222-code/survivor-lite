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
var screen := "menu"  # menu | playing | levelup | dead | results | paused
var hitstop := 0.0

var _menu: Array
var _levelup: Array
var _dead: Array
var _results: Array
var _pause: Array
var _results_gold := 0
var _results_doubled := false
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
	ui_root.add_child(hud)

	pause_btn = UiKit.button("II", _pause_run, 72)
	pause_btn.custom_minimum_size = Vector2(72, 72)
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-90, 28)
	ui_root.add_child(pause_btn)

	_menu = UiKit.overlay(ui_root, 0.0)
	_levelup = UiKit.overlay(ui_root)
	_dead = UiKit.overlay(ui_root)
	_results = UiKit.overlay(ui_root)
	_pause = UiKit.overlay(ui_root)
	_show_menu()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if screen != "playing":
		return
	if event is InputEventScreenTouch:
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
		# Floating stick: the base follows the finger past the rim.
		var off: Vector2 = hud.stick_pos - hud.stick_origin
		if off.length() > hud.stick_radius:
			hud.stick_origin = hud.stick_pos - off.normalized() * hud.stick_radius


func _move_input() -> Vector2:
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

func _physics_process(delta: float) -> void:
	if screen != "playing" or world == null:
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	world.step(delta, _move_input())
	_handle_events(world.events)
	view.consume(world.events)
	world.events.clear()
	match world.state:
		"levelup":
			_show_levelup()
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
			"level_up":
				Sfx.play("level_up", 0.0)
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


func _start_run() -> void:
	var meta := Progression.meta_bonus(data.meta, Save.meta_levels)
	world = World.new(data, randi(), meta)
	view.set_world(world)
	hud.world = world
	hitstop = 0.0
	Save.runs += 1
	Save.write()
	Analytics.event("run_start", {"run": Save.runs})
	_hide_all()
	_set_screen("playing")


func _set_screen(s: String) -> void:
	screen = s
	var in_run := s in ["playing", "levelup", "dead", "paused"]
	hud.visible = in_run
	pause_btn.visible = s == "playing"
	view.visible = s != "menu"
	if s != "playing":
		_release_stick()


func _hide_all() -> void:
	for o in [_menu, _levelup, _dead, _results, _pause]:
		o[0].visible = false


# ------------------------------------------------------------------- menu

func _show_menu() -> void:
	_hide_all()
	_set_screen("menu")
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	col.add_child(UiKit.label(str(bal.title).to_upper(), 64, pal.ui_accent))
	col.add_child(UiKit.label("Survive %s. Drag anywhere to move." % UiKit.fmt_time(world_length()), 26, Color(pal.text, 0.8)))
	col.add_child(UiKit.label("Gold: %d     Best: %s" % [Save.gold, UiKit.fmt_time(Save.best_time)], 28))
	col.add_child(UiKit.button("PLAY", _start_run, 130))
	col.add_child(UiKit.label("UPGRADES", 28, pal.ui_accent))
	for m in data.meta:
		var lv := Save.meta_level(m.id)
		var cost := Progression.meta_next_cost(m, lv)
		var txt := "%s  %d/%d\n%s" % [m.name, lv, m.costs.size(), m.desc]
		txt += ("   -  MAX" if cost < 0 else "   -  %d gold" % cost)
		var b := UiKit.button(txt, _buy_meta.bind(m.id), 84)
		b.add_theme_font_size_override("font_size", 22)
		b.disabled = cost < 0 or Save.gold < cost
		col.add_child(b)
	var mute := UiKit.button("Sound: %s" % ("OFF" if Save.muted else "ON"), _toggle_mute, 64)
	mute.add_theme_font_size_override("font_size", 22)
	col.add_child(mute)
	col.add_child(UiKit.label(_build_label(), 18, Color(pal.text, 0.4)))
	_menu[0].visible = true


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


func _buy_meta(id: String) -> void:
	for m in data.meta:
		if m.id != id:
			continue
		var lv := Save.meta_level(id)
		var cost := Progression.meta_next_cost(m, lv)
		if cost >= 0 and Save.gold >= cost:
			Save.gold -= cost
			Save.meta_levels[id] = lv + 1
			Save.write()
			Analytics.event("meta_buy", {"id": id, "level": lv + 1})
	_show_menu()


func _toggle_mute() -> void:
	Save.muted = not Save.muted
	Save.write()
	_show_menu()


# --------------------------------------------------------------- level-up

func _show_levelup() -> void:
	_set_screen("levelup")
	var col: VBoxContainer = _levelup[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("LEVEL %d!" % world.level, 56, pal.ui_accent))
	col.add_child(UiKit.label("Choose one", 26, Color(pal.text, 0.8)))
	var buttons: Array[Button] = []
	for id in world.offers:
		var def: Dictionary = world.upgrade_defs[id]
		var nl := world.next_level_of(id)
		var tag := "NEW " + ("WEAPON" if def.type == "weapon" else "PASSIVE") if nl == 1 else "Lv %d" % nl
		var b := UiKit.button("%s   (%s)\n%s" % [def.name, tag, Upgrades.describe(def, nl)], _pick.bind(id), 150)
		col.add_child(b)
		buttons.append(b)
	var reroll := UiKit.button("Reroll  (watch ad)", _reroll, 80)
	reroll.add_theme_font_size_override("font_size", 24)
	reroll.visible = Ads.is_rewarded_available()
	col.add_child(reroll)
	buttons.append(reroll)
	_levelup[0].visible = true
	# Ignore taps for a moment so a finger still dragging can't mis-pick.
	for b in buttons:
		b.disabled = true
	await get_tree().create_timer(float(bal.juice.levelup_input_delay_s)).timeout
	for b in buttons:
		if is_instance_valid(b):
			b.disabled = false


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
	var can_revive := world.revives_used < int(bal.revive.max_per_run) and Ads.is_rewarded_available()
	if not can_revive:
		_show_results(false)
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
	if not won:
		Save.deaths += 1
	Save.best_time = maxf(Save.best_time, world.time)
	Analytics.event("run_end", {"won": won, "t": int(world.time), "level": world.level, "kills": world.kills, "gold": _results_gold})
	_build_results(won)


func _build_results(won: bool) -> void:
	var col: VBoxContainer = _results[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("YOU SURVIVED!" if won else "RUN OVER", 56, pal.ui_accent))
	col.add_child(UiKit.label("Time %s    Level %d    Kills %d" % [UiKit.fmt_time(world.time), world.level, world.kills], 28))
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
	Save.gold += _results_gold
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
