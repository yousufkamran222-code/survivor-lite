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
var _build: Array  # in-run BUILD overlay (paused)
var _victory: Array  # Nucleus: COLLECT or KEEP GOING
var _countdown := 0
var _bench: Benchmark = null  # on-device benchmark in progress
var _bench_bot: BalanceBot
var _bench_perf := false
var _bench_taps := 0
var _bench_tap_ms := 0
var bench_result := ""  # last benchmark line (also read by tools/sim/bench_render.gd)
var _picking := false  # a level-up pick is animating
var _cards: Array[Button] = []  # the level-up cards on screen
var _evo_by_passive := {}  # passive id -> evolution def
var _evo_by_weapon := {}  # weapon id -> evolution def
var _results_gold := 0
var _results_doubled := false
var _summary := {}
var _menu_bg: MenuBackground
var _new_achievements: Array = []
var _new_best := false
var _virulence_cleared := 0  # results: the Virulence level this win cleared for the first time (0 = none)
var _touch_index := -1
var _evo_moments: Array = []  # evolutions from the open chest, celebrated on close
var _evo_seq: Dictionary = {}  # the evolution sequence playing now (empty = none)
var _results_wallet: Control  # results: wallet pill the gold flies into
var _results_gold_icon: Control
var _results_gold_label: Label
var _results_gold_tween: Tween
var _collecting := false
var _pickup_chain := 0  # gems collected in quick succession (pitch ladder)
var _pickup_ms := 0
var _life_best_streak := 0  # lifetime best at run start (for the NEW BEST STREAK call-out)
var _streak_best_called := false
var _slowmo := 0.0  # boss-kill slow motion left (real seconds)
var _hints: Array = []  # this run's not-yet-seen hints (data/hints.json)
var _hint_queue: Array = []


func _ready() -> void:
	data = GameData.load_all()
	var errors := GameData.validate(data)
	for e in errors:
		push_error("data: " + e)
	bal = data.balance
	# The Lab was reshaped (2026-11-05): refund Genes for removed/repriced nodes.
	var lab_back := Save.profile.migrate_lab(data.lab, Save.now())
	Save.write()
	if lab_back > 0:
		Analytics.event("lab_migrated", {"genes": lab_back})
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
	hud.juice = bal.juice
	hud.streak_show = int(bal.juice.get("streak_show", 10))
	ui_root.add_child(hud)
	# Bake every upgrade icon (and evolved weapon icon) once for the HUD strip.
	var atlas := IconAtlas.new()
	add_child(atlas)
	var entries := []
	for u in data.upgrades:
		entries.append([u.id, IconArt.color_for(u), false])
		if _evo_by_weapon.has(u.id):
			entries.append([u.id, IconArt.color_for(u), true])
	entries.append(["outbreak", Color.WHITE, false])
	for oid in World.ORDER_IDS:
		entries.append(["order_" + oid, GameData.color(bal.conversion.orders[oid].color), false])
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
	_build = UiKit.overlay(ui_root, 0.82)
	if Save.muted:
		# The old SOUND button was a mute toggle; the Settings sliders replace
		# it, so carry "muted" over as both volumes at 0 (visible, fixable).
		Save.muted = false
		Save.music_volume = 0.0
		Save.sfx_volume = 0.0
		Save.write()
	_apply_settings()
	_victory = UiKit.overlay(ui_root, 0.8)
	_show_menu()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if screen == "menu" and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		start_benchmark()
		return
	if screen != "playing" or not _evo_seq.is_empty():
		return
	if hud.orders_open and event is InputEventKey and event.pressed and not event.echo and not (event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3):
		if event.physical_keycode == KEY_ESCAPE:
			hud.set_orders_open(false)
		return  # paused in the order fan: only 1-3 (pick) and Esc (close)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		world.dash()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_B:
		_show_build()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_E, KEY_TAB]:
		_open_banked()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		_use_rift_power()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		_use_ability()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		_trigger_outbreak()
		return
	if event is InputEventKey and event.pressed and not event.echo and world.def_on and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
		_build_tower(event.physical_keycode - KEY_1)
		return
	if event is InputEventKey and event.pressed and not event.echo and world.conv_on and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
		_set_order(event.physical_keycode - KEY_1)
		return
	if event is InputEventScreenTouch:
		# Nucleus tower bar first (any finger), so a build tap never dashes.
		if event.pressed and world.def_on:
			var tb := hud.tower_button_at(event.position)
			if tb >= 0:
				_build_tower(tb)
				return
		# Swarm orders: the button opens the fan, an option switches.
		if event.pressed and world.conv_on:
			var ob := hud.order_button_at(event.position)
			if ob == -2:
				hud.set_orders_open(not hud.orders_open)
				Sfx.play("click", 0.05)
				return
			if ob >= 0:
				_set_order(ob)
				return
			if hud.orders_open:
				hud.set_orders_open(false)  # tap anywhere else: close and resume
				return
		if event.pressed and hud.in_build_button(event.position):
			_show_build()
			return
		# Dash: tap the DASH button, or tap with a second finger while steering.
		if event.pressed and hud.in_upgrade_button(event.position):
			_open_banked()
			return
		if event.pressed and hud.in_outbreak_button(event.position):
			_trigger_outbreak()
			return
		if event.pressed and hud.in_ability_button(event.position):
			_use_ability()
			return
		if event.pressed and hud.in_power_button(event.position):
			_use_rift_power()
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
		# Rescale past the dead zone so speed starts from 0 at its edge (no
		# jump), with a gentle curve for fine control at small tilts.
		var dz := float(bal.juice.stick_deadzone)
		var l := v.length()
		if l < dz:
			v = Vector2.ZERO
		else:
			var k := clampf((l - dz) / (1.0 - dz), 0.0, 1.0)
			v = v / l * pow(k, float(bal.juice.get("stick_curve", 1.0)))
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
		if screen == "playing" and hud.orders_open:
			hud.set_orders_open(false)  # Back closes the order fan first
		elif screen == "playing":
			_pause_run()
		elif screen == "paused":
			_resume()
		elif screen == "build":
			_close_build()


# -------------------------------------------------------------- game loop

## One simulation step per rendered frame, with dt clamped. If the phone
## can't keep up, the game slows slightly instead of running extra catch-up
## steps (which made slow frames slower: the "spiral").
func _process(delta: float) -> void:
	if screen != "playing" or world == null:
		# Not stepping: drop the CPU timers so the perf readout stays honest.
		view.cpu_ms = 0.0
		hud.cpu_ms = 0.0
		SpriteBatch.draw_ms = 0.0
		return
	if not _evo_moments.is_empty():
		_play_evolution_moments()  # back in play after the evolution chest
	if not _evo_seq.is_empty():
		_tick_evolution(delta)
		view.cpu_ms = 0.0
		hud.cpu_ms = 0.0
		return  # the world is frozen for the whole sequence
	_update_heartbeat(delta)
	if hud.orders_open:
		# The Swarm order fan pauses the run while it's open.
		view.cpu_ms = 0.0
		hud.cpu_ms = 0.0
		SpriteBatch.draw_ms = 0.0
		return
	if hitstop > 0.0:
		hitstop -= delta
		return
	var t0 := Time.get_ticks_usec()
	var dt := minf(delta, MAX_STEP_DT)
	if _slowmo > 0.0:
		_slowmo -= delta
		dt *= float(bal.juice.get("slowmo_scale", 1.0))
	world.step(dt, _move_input())
	hud.sim_ms = lerpf(hud.sim_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	hud.cam_pos = view.cam.position
	hud.cam_zoom = view.cam_zoom
	hud.fx_count = view.fx.size()
	_handle_events(world.events)
	view.consume(world.events)
	world.events.clear()
	Sfx.set_boss(world.boss_index >= 0)
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
	_update_hints()
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
		_hint_event(ev.type)
		match ev.type:
			"shoot":
				Sfx.play("shoot")
			"hit":
				Sfx.play("hit")
			"kill":
				_on_kill_streak()
				if ev.get("gilded", false):
					Sfx.play("pickup", 0.05, 1.6)
			"pickup":
				# Gems collected in quick succession climb in pitch.
				var j: Dictionary = bal.juice
				var now := Time.get_ticks_msec()
				_pickup_chain = _pickup_chain + 1 if now - _pickup_ms < int(float(j.get("pickup_chain_s", 0.35)) * 1000.0) else 0
				_pickup_ms = now
				Sfx.play("pickup", 0.03, 1.0 + minf(_pickup_chain * float(j.get("pickup_pitch_step", 0.0)), float(j.get("pickup_pitch_max", 0.0))))
			"nova":
				Sfx.play("nova")
			"chain":
				Sfx.play("chain")
			"shield_block":
				Sfx.play("deny", 0.0, 1.4)
				Sfx.vibrate(25)
			"second_wind":
				Sfx.play("evolve", 0.0, 0.8)
				Sfx.vibrate(150)
				hud.toast("SECOND WIND!", pal.ui_accent, 2.0)
				hitstop = maxf(hitstop, 0.12)
			"slipstream":
				Sfx.play("dash", 0.0, 1.3)
			"dodge":
				Sfx.play("dash", 0.0, 1.6)
				hud.toast("DODGE", Color("#5ce1e6"), 0.6)
			"recoil":
				Sfx.play("nova", 0.0, 1.3)
			"ability_used":
				var ad: Dictionary = data.lab.abilities[ev.ability]
				Sfx.play({"stasis": "boss", "engulf": "convert", "cloak": "vacuum", "mitosis": "evolve"}.get(ev.ability, "nova"), 0.0, 1.1)
				Sfx.vibrate(60)
				hud.toast(str(ad.name).to_upper() + "!", GameData.color(ad.color), 1.4)
				Analytics.event("ability_used", {"id": ev.ability, "t": int(world.time)})
			"ability_end":
				if ev.ability == "cloak":
					hud.toast("AMBUSH!", GameData.color(data.lab.abilities.cloak.color), 1.2)
			"stasis_shock":
				Sfx.play("bomb", 0.0, 0.9)
				Sfx.vibrate(120)
				hitstop = maxf(hitstop, 0.08)
			"engulfed":
				Sfx.play("pickup", 0.03, 0.7)
			"hurt":
				hud.hurt_by(_cause_name(str(ev.get("cause", ""))))
				var from: Vector2 = ev.get("from", Vector2.INF)
				if from != Vector2.INF and from != world.p_pos:
					hud.hit_from((from - world.p_pos).normalized())
				Sfx.play("hurt")
				hitstop = maxf(hitstop, float(bal.juice.hitstop_hurt_s))
				Sfx.vibrate(40)
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
				_slowmo = float(bal.juice.get("slowmo_boss_s", 0.0))
				Analytics.event("boss_killed", {"t": int(world.time)})
			"death":
				Sfx.play("death", 0.0)
				Sfx.vibrate(200)
			"dash":
				Sfx.play("dash")
			"claim":
				Sfx.play("claim", 0.05)
				Sfx.vibrate(30)
				if ev.tiles >= 25:
					hud.toast("CLAIMED +%d%%" % maxi(1, roundi(float(ev.tiles) / world.terr.dish_count * 100.0)), pal.player_nucleus, 1.2)
			"convert":
				Sfx.play("convert", 0.1)
			"ally_order":
				var od: Dictionary = world.bal.conversion.orders[ev.order]
				Sfx.play("convert", 0.0, 1.3)
				Sfx.vibrate(20)
				hud.toast(str(od.name).to_upper(), GameData.color(od.color), 1.0)
				Analytics.event("swarm_order", {"order": ev.order, "t": int(world.time), "allies": world.ally_count})
			"swarm_feed":
				Sfx.play("convert", 0.0)
				var feeds := roundi(float(ev.power) / float(world.bal.conversion.feed_power))
				if feeds == 1 or feeds % 5 == 0:
					hud.toast("SWARM FED +%d%%" % roundi(ev.power * 100.0), pal.player_nucleus, 1.2)
			"trail_lost":
				Sfx.play("hurt", 0.0)
				hud.toast("Trail lost", pal.player_hurt, 1.0)
			"final_minute":
				Sfx.play("boss", 0.0, 1.15)
				Sfx.vibrate(120)
				view.add_shake(8.0)
				hud.toast("FINAL MINUTE!", pal.player_hurt, 2.2)
				hud.toast("Survive the surge", Color(pal.text, 0.9), 2.2)
			"streak":
				_on_streak_milestone(ev)
			"rift_open":
				Sfx.play("evolve", 0.0, 0.6)
				Sfx.vibrate(60)
				hud.toast("A RIFT OPENED!", GameData.color(bal.rift.boss.color), 2.0)
			"rift_closed":
				hud.toast("The rift closed", Color(pal.text, 0.8), 1.2)
			"rift_enter":
				Sfx.play("boss", 0.0, 1.2)
				Sfx.vibrate(80)
				hud.toast(str(bal.rift.boss.name).to_upper(), GameData.color(bal.rift.boss.color), 2.0)
				Analytics.event("rift_enter", {"t": int(world.time), "level": world.level})
			"missile_launch":
				Sfx.play("shoot", 0.0, 0.55)
			"missile_lock":
				Sfx.play("click", 0.0, 1.9)
				Sfx.vibrate(25)
			"missile_fire":
				Sfx.play("dash", 0.0, 0.7)
			"missile_hit_boss":
				Sfx.play("bomb", 0.0, 1.1)
				Sfx.vibrate(90)
				hud.toast("DIRECT HIT!", Color.WHITE, 1.0)
			"missile_hit_player":
				Sfx.play("hurt", 0.0, 0.7)
				Sfx.vibrate(140)
			"rift_power":
				var pd: Dictionary = bal.rift.powers[ev.power]
				hud.toast("%s%s" % [str(pd.name).to_upper(), "" if int(ev.level) <= 1 else "  LV %d" % int(ev.level)], GameData.color(bal.rift.boss.color), 2.4)
				hud.toast(str(pd.desc), Color(pal.text, 0.9), 2.4)
			"rift_exit":
				match str(ev.reason):
					"won":
						Sfx.play("evolve", 0.0, 1.0)
						Sfx.vibrate(160)
						_slowmo = float(bal.juice.get("slowmo_boss_s", 0.0))
					"timeout":
						Sfx.play("deny", 0.0, 0.8)
						hud.toast("TIME'S UP", Color(pal.text, 0.9), 1.6)
					"eject":
						Sfx.play("death", 0.0, 1.3)
						Sfx.vibrate(200)
				Analytics.event("rift_exit", {"reason": ev.reason, "t": int(world.time), "power": ev.power})
			"rift_power_used":
				Sfx.play("nova", 0.0, 0.8)
				Sfx.vibrate(50)
			"elite_spawn":
				Sfx.play("elite", 0.0)
				var an := str(data.waves.elites.get("affixes", {}).get(str(ev.get("affix", "")), {}).get("name", ""))
				hud.toast("ELITE %s!" % an.to_upper() if an != "" else "ELITE GERM!", hud.elite_color, 1.8)
			"elite_windup":
				Sfx.play("deny", 0.0, 0.6 if ev.kind == "charge" else 0.8)
			"boss_windup":
				Sfx.play("boss", 0.0, 1.3)
				Sfx.vibrate(40)
			"boss_slam":
				Sfx.play("bomb", 0.0, 0.7)
				Sfx.vibrate(120)
				hitstop = maxf(hitstop, 0.06)
			"boss_phase":
				Sfx.play("boss", 0.0, 0.8)
				Sfx.vibrate(150)
				hud.toast("THE MOTHER CELL ENRAGES!" if int(ev.phase) == 3 else "THE MOTHER CELL STIRS!", pal.player_hurt, 2.0)
			"lull":
				hud.toast("The dish goes quiet...", Color(pal.text, 0.8), 2.5)
			"surge":
				Sfx.play("elite", 0.0, 0.8)
				Sfx.vibrate(80)
				hud.toast("SURGE!", pal.player_hurt, 1.8)
			"elite_killed":
				Sfx.play("boss", 0.1)
				Sfx.vibrate(60)
				hitstop = maxf(hitstop, float(bal.juice.get("hitstop_elite_s", 0.0)))
			"evolution":
				_evo_moments.append(ev)  # played when the chest closes
			"evolution_ready":
				hud.toast("EVOLUTION READY", pal.ui_accent, 2.4)
				hud.toast("Kill an elite for a chest", Color(pal.text, 0.9), 2.4)
			"outbreak_ready":
				Sfx.play("chest", 0.0, 1.2)
				Sfx.vibrate(40)
				hud.toast("OUTBREAK READY", pal.outbreak, 1.6)
			"outbreak_start":
				Sfx.play("evolve", 0.0)
				Sfx.vibrate(120)
				hud.toast("OUTBREAK!  %d GILDED" % int(ev.get("gilded", 0)), pal.ui_accent, 1.6)
				Analytics.event("outbreak", {"t": int(world.time), "mode": world.bal.get("mode_id", "")})
			"volatile":
				Sfx.play("nova", 0.1, 1.5)
			"wave_start":
				if ev.boss:
					Sfx.play("boss", 0.0)
					Sfx.vibrate(120)
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
				Sfx.vibrate(40)
				hud.toast("%s %s" % [str(ev.name).to_upper(), "BUILT" if ev.type == "tower_built" else "LV %d" % ev.level], GameData.color(ev.color), 1.4)
				Analytics.event("tower_build", {"level": ev.level, "wave": world.wave})
			"player_down":
				Sfx.play("death", 0.0)
				Sfx.vibrate(200)
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
						Sfx.vibrate(120)
				Analytics.event("pickup", {"kind": ev.kind, "t": int(world.time)})


## Kill sound climbs in pitch while the streak (World.streak) keeps going;
## beating your lifetime best streak gets a call-out once per run.
func _on_kill_streak() -> void:
	var n := world.streak
	var j: Dictionary = bal.juice
	var pitch := 1.0 + minf(n * float(j.get("kill_pitch_step", 0.0)), float(j.get("kill_pitch_max", 0.0)))
	Sfx.play("kill2" if n % 2 == 0 else "kill", 0.04, pitch)
	if not _streak_best_called and _life_best_streak >= 25 and n > _life_best_streak:
		_streak_best_called = true
		Sfx.play("level_up", 0.0, 1.2)
		hud.toast("NEW BEST STREAK!", pal.ui_accent, 1.6)


## Streak milestone (balance.streak.milestones): a chime that climbs with
## the tier, a buzz, a shake, and the HUD burst (ring + swelling tier name).
func _on_streak_milestone(ev: Dictionary) -> void:
	var t := int(ev.tier)
	Sfx.play("chest", 0.0, 1.0 + 0.08 * maxi(t, 0))
	if t >= 3:
		Sfx.play("evolve", 0.0, 1.0 + 0.05 * t)
	Sfx.vibrate(30 + 15 * maxi(t, 0))
	view.add_shake(3.0 + 1.5 * maxi(t, 0))
	hud.streak_burst()


func _start_run() -> void:
	var meta := Progression.run_bonus(data, Save.meta_levels, Save.profile.lab)
	var mode_id: String = _current_mode().id
	world = World.new(GameData.apply_virulence(GameData.apply_mode(data, mode_id), Save.profile.virulence_selected(mode_id)), randi(), meta)
	var ab_id := Save.profile.equipped_ability(data.lab)
	world.equip_ability(ab_id, Lab.ability_level(data.lab, Save.profile.lab, ab_id))
	view.set_world(world)
	hud.world = world
	hitstop = 0.0
	_slowmo = 0.0
	hud.set_orders_open(false)
	_evo_moments.clear()
	_evo_seq = {}
	hud.evo_seq = {}
	Sfx.play_music("run")
	_life_best_streak = int(Save.profile.stats.get("best_streak", 0))
	_streak_best_called = false
	Analytics.event("run_start", {"run": Save.runs + 1, "mode": _current_mode().id})
	_load_hints(_current_mode().id)
	_hide_all()
	_set_screen("playing")


func _set_screen(s: String) -> void:
	screen = s
	_apply_fps()
	var in_run := s in ["playing", "levelup", "chest", "dead", "paused", "defense_won", "build"]
	hud.visible = in_run
	pause_btn.visible = s == "playing"
	view.visible = s != "menu"
	if s != "playing":
		_release_stick()


## Battery: gameplay runs at the Frame rate setting (Max = the screen's
## full 90/120 Hz); menus and pickers at most 60; pause barely moves.
func _apply_fps() -> void:
	var cap := Save.fps_cap  # 0 = max
	var limit := cap
	if screen == "paused" or screen == "build":
		limit = int(bal.perf.get("pause_max_fps", 30))
	elif screen != "playing":
		var menu_cap := int(bal.perf.get("menu_max_fps", 0))  # 0 = the display's refresh rate (a 60 cap judders on 90/120 Hz phones)
		limit = menu_cap if cap == 0 else (cap if menu_cap == 0 else mini(cap, menu_cap))
	Engine.max_fps = limit


## Re-applies everything the Settings screen controls.
func _apply_settings() -> void:
	Sfx.apply_settings()
	hud.show_perf = Save.show_fps == 1 or (Save.show_fps == -1 and bool(bal.get("debug", {}).get("show_perf", false)))
	view.shake_setting = Save.shake
	_apply_fps()


func _hide_all() -> void:
	for o in [_menu, _levelup, _dead, _results, _pause, _chest, _victory, _build]:
		o[0].visible = false


# ------------------------------------------------------------------- menu

func _show_menu() -> void:
	Sfx.play_music("menu")
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
	col.add_child(_virulence_row(current.id))
	col.add_child(UiKit.label(current.desc, 22, Color(pal.text, 0.8)))
	var play := Button.new()
	play.text = "PLAY"
	play.custom_minimum_size = Vector2(0, 136)
	UiKit.style_button(play, "primary", 60)
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
	bottom.add_child(_tile_button("lab", LabScreen.GENE, "LAB", _show_lab))
	bottom.add_child(_tile_button("trophy", pal.ui_accent, "PROFILE", _show_profile))
	bottom.add_child(_tile_button("settings", pal.player_nucleus, "SETTINGS", _show_settings))
	col.add_child(bottom)
	# The build label doubles as the hidden benchmark trigger (tap 5 times).
	var build := UiKit.label(_build_label(), 16, Color(pal.text, 0.35))
	build.mouse_filter = Control.MOUSE_FILTER_STOP
	build.gui_input.connect(_on_build_label_input)
	col.add_child(build)
	_menu[0].visible = true
	UiKit.fade_in(col)


func _gold_pill() -> Control:
	var pill := PanelContainer.new()
	var sb := UiKit._box(Color(0.08, 0.05, 0.14, 0.85), 26, 14)
	sb.set_border_width_all(2)
	sb.border_color = Color(pal.ui_accent, 0.7)
	pill.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UpgradeIcon.make("gold", pal.ui_accent, 36))
	var amount := UiKit.display(UiKit.label(str(Save.gold), 28, pal.ui_accent))
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
	var name := UiKit.display(UiKit.label(str(m.name).to_upper(), 22, Color.WHITE if selected else Color(1, 1, 1, 0.75)))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name)
	var rec := Save.profile.record(m.id)
	var sub := "Best %s" % UiKit.fmt_time(float(rec.get("best_time", 0.0)))
	if rec.has(m.get("special", "")) and int(rec[m.special]) > 0:
		sub = str(m.special_label) % int(rec[m.special])
	var subl := UiKit.label(sub if int(rec.get("runs", 0)) > 0 else "Not played yet", 17, Color(accent, 0.9))
	subl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(subl)
	var cleared := Save.profile.virulence_cleared(m.id)
	if cleared > 0:
		var vl := UiKit.label("V%d cleared" % cleared, 15, Color("#ff5a7a"))
		vl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(vl)
	if m.get("tag", "") != "":
		var tag := UiKit.label(m.tag, 15, pal.ui_accent)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tag)
	b.add_child(v)
	return b


## Virulence selector for the selected mode: arrows step through every
## unlocked level (older ones stay playable), the next locked one shows how to
## unlock it, and the line under it says what this level adds.
func _virulence_row(mode_id: String) -> Control:
	var prof := Save.profile
	var sel := prof.virulence_selected(mode_id)
	var top := prof.virulence_unlocked(mode_id)
	var levels: Array = data.difficulty.levels
	var accent: Color = Color("#ff5a7a") if sel > 1 else pal.ui_accent
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	var step := func(dl: int) -> void:
		prof.set_virulence(mode_id, sel + dl)
		Save.write()
		Sfx.play("click", 0.0, 1.0 + 0.04 * (sel + dl))
		_show_menu()
	var left := UiKit.button("<", step.bind(-1), 64)
	left.custom_minimum_size = Vector2(72, 64)
	left.disabled = sel <= 1
	h.add_child(left)
	var lab := UiKit.label("%s %d" % [str(data.difficulty.name).to_upper(), sel], 36, accent)
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	lab.custom_minimum_size = Vector2(300, 0)
	h.add_child(lab)
	var right := UiKit.button(">", step.bind(1), 64)
	right.custom_minimum_size = Vector2(72, 64)
	right.disabled = sel >= top
	h.add_child(right)
	box.add_child(h)
	var lv: Dictionary = levels[sel - 1]
	var info := "Adds %s: %s, on top of every level below." % [lv.name, str(lv.desc).to_lower()] if sel > 1 else "The standard game. Win to unlock Virulence 2."
	if sel > 1:
		var base_dd: Dictionary = GameData.apply_mode(data, mode_id).balance.get("difficulty", {})
		var dd: Dictionary = GameData.apply_virulence(GameData.apply_mode(data, mode_id), sel).balance.difficulty
		info += "\nGerms x%.1f HP, x%.1f damage.  +%d%% gold" % [float(dd.enemy_hp_mult) / float(base_dd.get("enemy_hp_mult", 1.0)), float(dd.damage_taken_mult) / float(base_dd.get("damage_taken_mult", 1.0)), roundi((float(dd.gold_mult) - 1.0) * 100.0)]
	elif top > 1:
		info = "The standard game (no modifiers)."
	var il := UiKit.label(info, 19, Color(pal.text, 0.75))
	box.add_child(il)
	if sel == top and top < Profile.MAX_VIRULENCE and prof.virulence_cleared(mode_id) < top:
		box.add_child(UiKit.label("Win Virulence %d to unlock %d" % [top, top + 1], 17, Color(pal.text, 0.5)))
	return box


## Square-ish button with an icon over a label (menu bottom row).
func _tile_button(icon_key: String, accent: Color, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 120)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiKit.style_button(b, "secondary")
	UiKit.press_feedback(b)
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		on_press.call())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.offset_bottom = -6.0  # sit above the 3D edge
	var ic := UpgradeIcon.make(icon_key, accent, 52)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := UiKit.label(text, 20, Color.WHITE)
	l.add_theme_font_override("font", UiKit.display_font())
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", UiKit.OUTLINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.add_child(v)
	return b


## Lifetime stats, per-mode records and achievements (ProfileScreen).
func _show_profile() -> void:
	_menu_bg.show_hero = false
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	var ps := ProfileScreen.new()
	ps.setup(pal, data, _show_menu)
	col.add_child(ps)
	UiKit.fade_in(ps)


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
	UiKit.fade_in(shop)


## The Lab: Genes-paid skill tree (LabScreen).
func _show_lab() -> void:
	_menu_bg.show_hero = false
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	var lab := LabScreen.new()
	lab.setup(data.lab, pal, _menu[0], _show_menu, _show_abilities)
	col.add_child(lab)
	UiKit.fade_in(lab)


## Lab abilities: pick the one to equip (AbilitiesScreen).
func _show_abilities() -> void:
	_menu_bg.show_hero = false
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	var scr := AbilitiesScreen.new()
	scr.setup(data.lab, pal, _show_lab)
	col.add_child(scr)
	UiKit.fade_in(scr)


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


# --------------------------------------------------------------- level-up

func _show_levelup() -> void:
	_set_screen("levelup")
	var col: VBoxContainer = _levelup[1]
	UiKit.clear(col)
	col.add_theme_constant_override("separation", 16)
	var title := UiKit.label("LEVEL UP!", 66, pal.ui_accent)
	col.add_child(title)
	var sub := HBoxContainer.new()
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.add_theme_constant_override("separation", 10)
	var lv := UiKit.display(UiKit.label("Level %d" % world.level, 26, Color.WHITE))
	lv.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.add_child(lv)
	if world.pending_levelups > 1:
		sub.add_child(UiKit.chip("%d picks" % world.pending_levelups, pal.ui_accent, Color(0.1, 0.06, 0.15), 20))
	col.add_child(sub)
	var buttons: Array[Button] = []
	_cards = []
	var k := 0
	for id in world.offers:
		var b := _upgrade_card(id)
		col.add_child(_card_slot(b))
		buttons.append(b)
		_cards.append(b)
		_slide_in(b, 0.06 + k * 0.08)
		k += 1
	# Reroll / Later: small text buttons, so the cards stay the focus.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	var reroll := _text_button("Reroll (%d free)" % world.free_rerolls if world.free_rerolls > 0 else "Reroll (ad)", _reroll)
	reroll.visible = world.free_rerolls > 0 or Ads.is_rewarded_available()
	row.add_child(reroll)
	buttons.append(reroll)
	var later := _text_button("Later (keep %d)" % world.pending_levelups, _later)
	row.add_child(later)
	buttons.append(later)
	col.add_child(row)
	if not _levelup[0].visible:
		var root: Control = _levelup[0]
		root.visible = true
		root.modulate.a = 0.0
		root.create_tween().tween_property(root, "modulate:a", 1.0, 0.16)
	UiKit._pop(title, 0.0, 0.7)
	# Ignore taps for a moment so a finger still dragging can't mis-pick.
	for b in buttons:
		b.disabled = true
	await get_tree().create_timer(float(bal.juice.levelup_input_delay_s)).timeout
	for b in buttons:
		if is_instance_valid(b):
			b.disabled = false


## A flat text-only button (secondary actions under the level-up cards).
func _text_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 64)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_font_override("font", UiKit.display_font())
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_color_override("font_outline_color", UiKit.OUTLINE)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color(pal.text, 0.8))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(pal.text, 0.35))
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		on_press.call())
	UiKit.press_feedback(b)
	return b


## A plain slot in the column holding one card: the column lays out the
## slot, and the card can move inside it (slide-in, drop-away) without the
## container snapping it back. The slot is as tall as the card needs.
func _card_slot(card: Control) -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	slot.custom_minimum_size.y = card.custom_minimum_size.y
	# Keep the card exactly as wide as the slot (moving it while the slot was
	# still 0 wide baked its min width into the offsets: 24 px too wide), and
	# size its height from its content only once it has its real width: at
	# 0 width the wrapped text measured one word per line, so a second
	# level-up in a row got a 3,800 px column (off-centre, too high).
	slot.resized.connect(func() -> void:
		card.offset_left = 0.0
		card.offset_right = 0.0
		if slot.size.x > 1.0:
			_fit_card.call_deferred(card, slot))
	return slot


func _fit_card(card: Control, slot: Control) -> void:
	if not is_instance_valid(card) or not is_instance_valid(slot):
		return
	var content: Control = card.get_node_or_null("Content")
	if content == null:
		return
	var h := maxf(176.0, content.get_combined_minimum_size().y)
	if absf(h - card.custom_minimum_size.y) > 0.5:
		card.custom_minimum_size.y = h
		slot.custom_minimum_size.y = h


## Cards slide up into place (inside their slot), one after another.
func _slide_in(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	c.position.y = 140.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.16).set_delay(delay)
	tw.tween_property(c, "position:y", 0.0, 0.38).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Category of a card: [tag, colour].
func _card_kind(def: Dictionary) -> Array:
	var id := str(def.id)
	if def.type == "weapon":
		return ["WEAPON", IconArt.color_for(def)]
	if def.has("modes"):
		return ["SWARM", IconArt.COLORS.swarm]
	if id in ["flagella2", "lunge", "afterimage", "adrenaline", "volatile"]:
		return ["DASH", IconArt.COLORS.dash]
	return ["PASSIVE", IconArt.COLORS.passive]


## True if picking this card makes an evolution ready (max weapon + its partner).
func _completes_evolution(id: String, nl: int) -> bool:
	if _evo_by_weapon.has(id):
		var ev: Dictionary = _evo_by_weapon[id]
		return nl == Upgrades.max_level(world.upgrade_defs[id]) and world.owned.has(ev.requires) and not world.evolved.has(id)
	if _evo_by_passive.has(id):
		var ev: Dictionary = _evo_by_passive[id]
		var w := str(ev.weapon)
		return nl == 1 and int(world.owned.get(w, 0)) >= Upgrades.max_level(world.upgrade_defs[w]) and not world.evolved.has(w)
	return false


const STAT_NAMES := {"damage": "Damage", "cooldown": "Cooldown", "count": "Count", "pierce": "Pierce", "area": "Area",
	"jumps": "Jumps", "size": "Size", "range": "Range", "orbit_radius": "Radius", "spin": "Spin", "speed": "Speed",
	"knockback": "Knockback", "jump_range": "Jump range", "hit_interval": "Hit rate", "might": "Damage", "haste": "Weapon speed",
	"move": "Move speed", "max_hp": "Max HP", "magnet": "Pickup range", "amount": "Extra shots", "regen": "Regen/s",
	"xp_gain": "XP", "gold_gain": "Gold", "armor": "Resist", "dash_charges": "Dash charges", "dash_damage": "Dash damage",
	"dash_cd": "Dash recharge", "dash_decoy": "Decoy burst", "convert": "Convert", "ally_power": "Ally power", "ally_cap": "Ally cap",
	"hive": "Hive", "convert_heal": "Convert heal", "dash_reset": "Dash reset", "dash_volatile": "Volatile"}
const PCT_STATS := ["might", "haste", "move", "magnet", "xp_gain", "gold_gain", "armor", "dash_cd", "dash_decoy", "convert", "ally_power", "hive"]


## Up to two "Damage 18 → 26" lines for a card you already own.
func _stat_lines(def: Dictionary, nl: int) -> Array:
	var out := []
	if nl <= 1:
		return out
	var cur := Upgrades.stats_at(def, nl - 1)
	var nxt := Upgrades.stats_at(def, nl)
	var row: Dictionary = def.levels[mini(nl - 1, def.levels.size() - 1)]
	for key in row:
		if out.size() >= 2 or not STAT_NAMES.has(key):
			continue
		out.append("%s  %s → %s" % [STAT_NAMES[key], _fmt_stat(key, float(cur.get(key, 0.0))), _fmt_stat(key, float(nxt.get(key, 0.0)))])
	return out


func _fmt_stat(key: String, v: float) -> String:
	if PCT_STATS.has(key):
		return "+%d%%" % roundi(v * 100.0)
	if key in ["cooldown", "hit_interval"]:
		return "%ss" % str(snappedf(v, 0.01))
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.1))


## One level-up offer: a chunky card framed in its category colour with a
## glowing icon, name + tags, a level bar, "now → next" stats (or the
## description for a new card) and evolution hints. Picking animates.
func _upgrade_card(id: String) -> Button:
	var def: Dictionary = world.upgrade_defs[id]
	var nl := world.next_level_of(id)
	var total := Upgrades.max_level(def)
	var kind := _card_kind(def)
	var accent: Color = kind[1]
	var evo_ready := _completes_evolution(id, nl)
	var mutated: bool = id == world.mutated_offer
	var frame: Color = pal.ui_accent if evo_ready else (LabScreen.GENE if mutated else accent)
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 176)
	b.focus_mode = Control.FOCUS_NONE
	var sb := UiKit.card(Color("#2b2158"), frame, 22, 12)
	sb.set_border_width_all(5 if (evo_ready or mutated) else 4)
	sb.border_width_left = 12
	var sbp := sb.duplicate()
	sbp.bg_color = Color("#3c2f7a")
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("disabled", sb)
	b.pressed.connect(func() -> void:
		Sfx.play("click", 0.0)
		_pick_animated(id, b))
	UiKit.press_feedback(b)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 14)
	m.add_theme_constant_override("margin_left", 22)
	b.add_child(m)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 16)
	m.add_child(h)
	var ic := UiKit.glow_icon(id, accent, 100)
	ic.name = "Icon"
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	var name := UiKit.display(UiKit.label(def.name, 30, Color.WHITE))
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name)
	var boosts := false  # a permanent upgrade already gives this card's effect
	for key in def.levels[0]:
		boosts = boosts or float(world.meta_bonus.get(key, 0.0)) > 0.0
	if mutated:
		top.add_child(UiKit.chip("MUTATED +2 LV", LabScreen.GENE))
	elif nl == 1 and boosts and def.type != "weapon":
		top.add_child(UiKit.chip("BOOST", Color(1, 1, 1, 0.85)))
	elif nl == 1:
		top.add_child(UiKit.chip("NEW", accent))
	else:
		top.add_child(UiKit.chip("LV %d" % nl, Color(1, 1, 1, 0.9)))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	var tag := UiKit.label(kind[0], 14, Color(accent, 0.85))
	tag.add_theme_font_override("font", UiKit.display_font())
	tag.autowrap_mode = TextServer.AUTOWRAP_OFF
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(tag)
	v.add_child(top)
	if total > 1:
		var bar := MetaShop.TierBar.new()
		bar.have = nl - 1
		bar.total = total
		bar.color = accent
		bar.pulse_index = nl - 1
		bar.custom_minimum_size = Vector2(0, 10)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(bar)
	var lines := _stat_lines(def, nl)
	if lines.is_empty():
		var body := UiKit.label(Upgrades.describe(def, nl), 20, Color(1, 1, 1, 0.85))
		body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(body)
	else:
		for line in lines:
			var l := UiKit.label(line, 22, Color("#9dffc4"))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(l)
	if evo_ready:
		var ev: Dictionary = _evo_by_weapon.get(id, _evo_by_passive.get(id, {}))
		var chip := UiKit.chip("EVOLUTION READY: %s" % str(ev.get("name", "")).to_upper(), pal.ui_accent, Color(0.1, 0.06, 0.15), 17)
		v.add_child(chip)
		chip.resized.connect(func() -> void: chip.pivot_offset = chip.size / 2.0)
		var pulse := chip.create_tween().set_loops()
		pulse.tween_property(chip, "scale", Vector2(1.06, 1.06), 0.45).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(chip, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	else:
		var hint := _evolution_hint(id, nl)
		if hint != "":
			v.add_child(UiKit.chip(hint.replace("* ", ""), Color(pal.ui_accent, 0.75), Color(0.1, 0.06, 0.15), 15))
	m.name = "Content"  # _card_slot grows the card to fit this once it knows its width
	return b


## The pick: the chosen card pops, the others drop away, and its icon flies
## into the BUILD box before the next picker (or the run) continues.
func _pick_animated(id: String, card: Button) -> void:
	if _picking:
		return
	_picking = true
	var col: VBoxContainer = _levelup[1]
	for c in col.get_children():
		if c is HBoxContainer:
			for cc in c.get_children():
				if cc is Button:
					cc.disabled = true
	for c in _cards:
		if not is_instance_valid(c):
			continue
		c.disabled = true
		if c != card:
			var tw := c.create_tween().set_parallel(true)
			tw.tween_property(c, "modulate:a", 0.0, 0.16)
			tw.tween_property(c, "position:y", 60.0, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	card.pivot_offset = card.size / 2.0
	var pop := card.create_tween()
	pop.tween_property(card, "scale", Vector2(1.06, 1.06), 0.1).set_trans(Tween.TRANS_SINE)
	pop.tween_property(card, "scale", Vector2.ONE, 0.12)
	Sfx.play("upgrade", 0.0, 1.05)
	Sfx.vibrate(25)
	# Icon flies to the BUILD box (HUD space = screen space).
	var icon_node: Control = card.find_child("Icon", true, false)
	var layer: Node = _levelup[0].get_parent()
	if icon_node != null and layer != null:
		var def: Dictionary = world.upgrade_defs[id]
		var fly := UpgradeIcon.make(id, _card_kind(def)[1], 108)
		fly.position = icon_node.get_global_rect().position
		fly.z_index = 10
		layer.add_child(fly)
		var dst := hud.build_rect().get_center() - Vector2(27, 27)
		var tw := fly.create_tween().set_parallel(true)
		tw.tween_property(fly, "position", dst, 0.34).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(fly, "scale", Vector2(0.5, 0.5), 0.34).set_delay(0.08)
		tw.chain().tween_callback(fly.queue_free)
	await get_tree().create_timer(0.24).timeout
	_picking = false
	_pick(id)


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

## Slot-machine style reveal: each reward card spins through icons and
## names, then lands with a burst (evolutions get a gold banner).
func _show_chest() -> void:
	_set_screen("chest")
	var rewards: Array = world.chest_rewards.duplicate()
	Sfx.play("chest", 0.0)
	Sfx.vibrate(50)
	Analytics.event("chest_open", {"items": rewards.size(), "t": int(world.time)})
	var col: VBoxContainer = _chest[1]
	UiKit.clear(col)
	col.add_theme_constant_override("separation", 16)
	var title := UiKit.label("CHEST!", 64, pal.gem_large)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	col.add_child(title)
	var burst := MetaShop.Burst.new()
	burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chest[0].add_child(burst)
	var cards: Array[PanelContainer] = []
	var slots: Array[Label] = []
	var subs: Array[Label] = []
	var icons: Array = []
	var keys := []
	for u in data.upgrades:
		keys.append(u.id)
	for r in rewards:
		var card := UiKit.panel(Color("#2f2357"), Color(1, 1, 1, 0.15), 22, 16)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var ic := UiKit.glow_icon(keys[0], pal.ui_accent, 112)
		row.add_child(ic)
		icons.append(ic)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var l := UiKit.label("?", 32, pal.text)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size = Vector2(380, 0)
		v.add_child(l)
		var sd := UiKit.label("", 21, Color(pal.text, 0.75))
		sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(sd)
		row.add_child(v)
		card.add_child(row)
		col.add_child(card)
		cards.append(card)
		slots.append(l)
		subs.append(sd)
	UiKit.reveal(_chest)
	var names := []
	for u in data.upgrades:
		names.append(u.name)
	for ev in data.evolutions:
		names.append(ev.name)
	# Spin, slowing down, then land each card in turn.
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
		var ic = icons[k]
		ic.evolved = evo
		var accent: Color = pal.ui_accent
		if evo:
			for ev in data.evolutions:
				if ev.id == r.id:
					ic.key = ev.weapon
					accent = GameData.color(ev.color)
		elif r.kind == "upgrade":
			ic.key = r.id
			accent = IconArt.color_for(world.upgrade_defs[r.id])
		else:
			ic.key = "regen"
			accent = pal.gem_medium
		ic.color = accent
		ic.queue_redraw()
		slots[k].text = ("%s  Lv %d" % [r.name, r.level]) if r.kind == "upgrade" else str(r.name)
		slots[k].add_theme_color_override("font_color", pal.ui_accent if evo else Color.WHITE)
		subs[k].text = r.desc
		var sb := UiKit._box(Color("#3a2a5e") if evo else Color("#2f2357"), 22, 16)
		sb.set_border_width_all(4 if evo else 3)
		sb.border_color = pal.ui_accent if evo else Color(accent, 0.8)
		cards[k].add_theme_stylebox_override("panel", sb)
		if evo:
			var banner := UiKit.chip("EVOLUTION!", pal.ui_accent, Color(0.1, 0.06, 0.15), 22)
			slots[k].get_parent().add_child(banner)
			slots[k].get_parent().move_child(banner, 0)
		cards[k].pivot_offset = cards[k].size / 2.0
		cards[k].scale = Vector2(1.08, 1.08)
		cards[k].create_tween().tween_property(cards[k], "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var at: Vector2 = ic.global_position + ic.size / 2.0 - burst.global_position
		burst.emit(at, pal.ui_accent if evo else accent, 40 if evo else 18, 1.4 if evo else 0.8)
		if evo:
			Sfx.play("evolve", 0.0)
			Sfx.vibrate(150)
			view.add_shake(14.0)
			Analytics.event("evolution", {"id": r.id, "t": int(world.time)})
		else:
			Sfx.play("level_up", 0.0)
		await get_tree().create_timer(0.35).timeout
	if is_instance_valid(col):
		var cont := UiKit.button("CONTINUE", _close_chest, 110)
		col.add_child(cont)
		UiKit.fade_in(cont)


func _close_chest() -> void:
	_chest[0].visible = false
	for c in _chest[0].get_children():
		if c is MetaShop.Burst:
			c.queue_free()
	world.close_chest()
	if world.state == "levelup":
		_show_levelup()
	else:
		_set_screen("playing")


## Low HP (below juice.lowhp_frac): a heartbeat that speeds up as HP drops,
## each beat pulsing the HUD's red vignette.
var _hb_t := 0.0


func _update_heartbeat(delta: float) -> void:
	var j: Dictionary = bal.juice
	var frac := world.p_hp / maxf(world.p_max_hp, 1.0)
	var lim := float(j.get("lowhp_frac", 0.0))
	hud.low_hp = clampf(1.0 - frac / lim, 0.0, 1.0) if lim > 0.0 and world.p_hp > 0.0 and world.p_down <= 0.0 else 0.0
	if hud.low_hp <= 0.0:
		_hb_t = 0.0
		return
	_hb_t -= delta
	if _hb_t <= 0.0:
		_hb_t = lerpf(float(j.get("heartbeat_slow_s", 1.0)), float(j.get("heartbeat_fast_s", 0.5)), hud.low_hp)
		Sfx.play("heartbeat", 0.0)
		hud.beat()


## Evolution moment: a frozen ~1.8 s sequence (juice.evolution_seq_s). Charge:
## the screen dims, the camera pushes in, sparks rush into the glowing cell
## and a chime builds. Burst (juice.evolution_burst_s): white flash, rings,
## a spark explosion, heavy shake and impact. Then the evolution's icon, name
## and effect as a banner while the camera eases back. Input is ignored and
## the world doesn't step until it ends; several evolutions play in turn.
func _play_evolution_moments() -> void:
	if _evo_moments.is_empty() or not _evo_seq.is_empty():
		return
	var ev: Dictionary = _evo_moments.pop_front()
	var def: Dictionary = {}
	for e in data.evolutions:
		if e.id == ev.id:
			def = e
	_release_stick()
	_evo_seq = {"t": 0.0, "dur": float(bal.juice.get("evolution_seq_s", 1.8)), "burst": float(bal.juice.get("evolution_burst_s", 0.75)),
		"weapon": ev.weapon, "name": str(def.get("name", "EVOLVED")), "desc": str(def.get("desc", "")),
		"color": GameData.color(def.get("color", "#ffd166")), "fired": false}
	hud.evo_seq = _evo_seq
	Sfx.play("upgrade", 0.0, 0.75)
	Sfx.vibrate(40)


func _tick_evolution(delta: float) -> void:
	var s := _evo_seq
	s.t = float(s.t) + delta
	view.evolution_seq(float(s.t), s)
	if not s.fired and s.t >= s.burst:
		s.fired = true
		view.evolution_moment(s.weapon)
		Sfx.play("evolve", 0.0, 0.9)
		Sfx.play("bomb", 0.0, 0.8)
		Sfx.vibrate(220)
	if s.t >= s.dur:
		_evo_seq = {}
		hud.evo_seq = {}
		view.evolution_seq(-1.0, {})


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
	if world.free_reroll():  # Lab: Free Rerolls
		_show_levelup()
		return
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
	UiKit.reveal(_dead)


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
	if won:
		Sfx.play_music("ending")
	_results_gold = world.run_gold_now(won)
	_results_doubled = false
	# Progress tracking: lifetime stats, per-mode records, achievements and
	# leaderboard submissions (local stub until Play Games is connected).
	var mid: String = _current_mode().id
	var prev_best := int(Save.profile.record(mid).get("best_score", 0))
	var prev_cleared := Save.profile.virulence_cleared(mid)
	_summary = Progression.run_summary(world, won, mid, data.online.score)
	_new_achievements = Save.profile.record_run(_summary, data.online.achievements, Save.now(), data.lab.genes)
	_virulence_cleared = 0
	if won and Save.profile.virulence_cleared(mid) > prev_cleared:
		_virulence_cleared = Save.profile.virulence_cleared(mid)
		Save.profile.set_virulence(mid, _virulence_cleared + 1)  # next run defaults to the new level
	_new_best = int(_summary.score) > prev_best
	Online.report_run(_summary, data.online.leaderboards, _new_achievements)
	Save.write()
	Analytics.event("run_end", {"won": won, "t": int(world.time), "level": world.level, "kills": world.kills, "gold": _results_gold, "elites": world.elites_killed, "chests": world.chests_opened, "evolutions": world.evolved.size(), "dashes": world.dashes, "infected": snappedf(world.terr.infected_fraction(), 0.01) if world.terr != null else -1.0, "conversions": world.conversions, "mode": _current_mode().id, "virulence": int(world.bal.get("virulence", 1))})
	_build_results(won)


## Results: headline, a stats card, then score and gold counting up with
## ticks; NEW BEST stamps in and new achievements pop in one by one.
## `gold_from` lets the double-gold ad count from the old total.
func _build_results(won: bool, animate: bool = true, gold_from: int = 0) -> void:
	var col: VBoxContainer = _results[1]
	UiKit.clear(col)
	col.add_theme_constant_override("separation", 14)
	var head := "YOU SURVIVED!" if won else "RUN OVER"
	if world.def_on:
		head = "NUCLEUS DEFENDED!" if won and not world.free_mode else ("FREE MODE OVER" if world.free_mode else "NUCLEUS LOST")
	var title := UiKit.label(head, 56, pal.ui_accent if won else pal.text)
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.14))
	col.add_child(title)
	var vl := int(world.bal.get("virulence", 1))
	if _virulence_cleared > 0:
		var txt := "VIRULENCE %d CLEARED!" % _virulence_cleared
		if _virulence_cleared < Profile.MAX_VIRULENCE:
			txt += "  Virulence %d unlocked" % (_virulence_cleared + 1)
		var chip := UiKit.chip(txt, Color("#ff5a7a"), Color(0.1, 0.04, 0.08), 22)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(chip)
		if animate:
			UiKit.fade_in(chip, 0.5)
	elif vl > 1:
		col.add_child(UiKit.label("Virulence %d" % vl, 22, Color("#ff5a7a")))
	if Save.profile.last_genes > 0:
		var gchip := UiKit.chip("+%d GENES  (spend them in the Lab)" % Save.profile.last_genes, LabScreen.GENE, Color(0.04, 0.12, 0.08), 22)
		gchip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(gchip)
		if animate:
			UiKit.fade_in(gchip, 0.7)
	# Stats card.
	var card := UiKit.panel(Color("#2a1f4a"), Color(1, 1, 1, 0.08), 22, 18)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 6)
	var rows := [["Time", UiKit.fmt_time(world.time)], ["Level", str(world.level)], ["Kills", str(world.kills)]]
	if world.terr != null:
		rows.append(["Dish infected", "%d%%" % roundi(world.terr.infected_fraction() * 100.0)])
	if world.conv_on:
		rows.append(["Germs converted", str(world.conversions)])
	if world.def_on:
		if world.free_mode:
			rows.append(["Free Mode wave", str(world.wave)])
		else:
			rows.append(["Waves cleared", "%d / %d" % [world.waves_cleared, world.wave_count]])
		rows.append(["Towers", str(world.towers_built)])
	for r in rows:
		var k := UiKit.label(r[0], 24, Color(pal.text, 0.65))
		k.autowrap_mode = TextServer.AUTOWRAP_OFF
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var v := UiKit.label(r[1], 24, pal.text)
		v.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
	card.add_child(grid)
	col.add_child(card)
	col.add_child(_highlights_card(animate))
	# Score (counts up), NEW BEST stamp.
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 14)
	var score := UiKit.label("", 40, pal.text)
	score.autowrap_mode = TextServer.AUTOWRAP_OFF
	score_row.add_child(score)
	col.add_child(score_row)
	var score_v := int(_summary.score)
	var t := 0.25 if animate else 0.0
	if animate:
		UiKit.count_up(score, 0, score_v, 1.1, "Score %d", t, 1.0)
	else:
		score.text = "Score %d" % score_v
	if _new_best:
		var best := UiKit.chip("NEW BEST!", pal.ui_accent, Color(0.1, 0.06, 0.15), 24)
		score_row.add_child(best)
		if animate:
			best.modulate.a = 0.0
			best.resized.connect(func() -> void: best.pivot_offset = best.size / 2.0)
			var tw := best.create_tween()
			tw.tween_interval(t + 1.15)
			tw.tween_callback(func() -> void:
				best.modulate.a = 1.0
				best.scale = Vector2(1.8, 1.8)
				best.rotation = -0.15
				Sfx.play("upgrade", 0.0)
				Sfx.vibrate(40))
			tw.tween_property(best, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(best, "rotation", 0.0, 0.25)
	# Achievements, staggered.
	var k := 0
	for a in _new_achievements:
		var ach := UiKit.chip("Achievement: %s" % a.name, Color(pal.gem_medium, 0.9), Color(0.08, 0.05, 0.12), 22)
		ach.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(ach)
		if animate:
			UiKit.fade_in(ach, t + 1.3 + 0.2 * k)
		k += 1
	# Gold (counts up).
	var gold_row := HBoxContainer.new()
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override("separation", 10)
	var gold_icon := UpgradeIcon.make("gold", pal.gem_large, 52)
	gold_row.add_child(gold_icon)
	var gold := UiKit.label("", 52, pal.gem_large)
	gold.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Fixed width = the widest the count-up gets, so the row stays centred and
	# never reflows while the number changes.
	var gw := gold.get_theme_font("font").get_string_size("+%d gold" % maxi(_results_gold * 2, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	gold.custom_minimum_size = Vector2(gw + 8.0, 0)
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	gold_row.add_child(gold)
	_results_gold_icon = gold_icon
	# Wallet (top-right): the run's gold flies into it on collect.
	if is_instance_valid(_results_wallet):
		_results_wallet.queue_free()
	var wallet := _gold_pill()
	wallet.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wallet.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	wallet.offset_left = -28.0
	wallet.offset_right = -28.0
	wallet.offset_top = 30.0
	_results[0].add_child(wallet)
	_results_wallet = wallet
	col.add_child(gold_row)
	_results_gold_label = gold
	_results_gold_tween = null
	if animate or gold_from > 0:
		_results_gold_tween = UiKit.count_up(gold, gold_from, _results_gold, 0.9, "+%d gold", t + (0.6 if animate else 0.0), 1.3)
	else:
		gold.text = "+%d gold" % _results_gold
	if not _results_doubled and Ads.is_rewarded_available():
		col.add_child(UiKit.button("DOUBLE GOLD  (watch ad)", func() -> void:
			Ads.show_rewarded("double_gold", func(ok: bool) -> void:
				if ok and not _results_doubled:
					_results_doubled = true
					var before := _results_gold
					_results_gold *= 2
					_build_results(won, false, before)
				else:
					_build_results(won, false)), 120))
	var again := UiKit.button("PLAY AGAIN", _collect.bind(true), 116, "primary")
	again.add_theme_font_size_override("font_size", 40)
	col.add_child(again)
	col.add_child(UiKit.button("Menu", _collect.bind(false), 80))
	if not _results[0].visible:
		UiKit.reveal(_results)


func _collect(again: bool) -> void:
	if _collecting:
		return
	if _results_gold > 0 and is_instance_valid(_results_wallet) and is_instance_valid(_results_gold_icon):
		_collecting = true
		await _gold_fly_in(_results_gold)
		_collecting = false
	if is_instance_valid(_results_wallet):
		_results_wallet.queue_free()
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


## Collect: a stream of coins rises from the run's gold to the wallet pill.
## The run total counts down as each coin leaves, the wallet counts up as it
## lands (climbing chime, little punch), then the game moves on. Buttons are
## locked meanwhile, and a still-running count-up is stopped first.
func _gold_fly_in(amount: int) -> void:
	if _results_gold_tween != null and _results_gold_tween.is_valid():
		_results_gold_tween.kill()
	for c in _results[1].get_children():
		if c is Button:
			c.disabled = true
	var root: Control = _results[0]
	var origin := root.get_global_rect().position
	var src := _results_gold_icon.get_global_rect().get_center() - origin
	var wl: Label = _results_wallet.find_children("*", "Label", true, false)[0]
	wl.custom_minimum_size.x = maxf(wl.size.x, wl.get_theme_font("font").get_string_size(str(Save.gold + amount), HORIZONTAL_ALIGNMENT_LEFT, -1, wl.get_theme_font_size("font_size")).x + 4.0)  # no reflow while it counts up
	var wicon: Control = _results_wallet
	for c in _results_wallet.find_children("*", "", true, false):
		if c is UpgradeIcon:
			wicon = c
			break
	var dst := wicon.get_global_rect().get_center() - origin
	var n := clampi(amount, 1, int(bal.juice.get("gold_fly_max_coins", 20)))
	var fly := float(bal.juice.get("gold_fly_s", 0.6))
	var gap := minf(float(bal.juice.get("gold_fly_gap_s", 0.06)), 1.0 / n)
	var left := [amount]
	var wallet := [Save.gold]
	_results_gold_label.text = "+%d gold" % amount
	_results_wallet.pivot_offset = _results_wallet.size / 2.0
	var sent := 0
	for k in n:
		var part := int(round(float(amount) * (k + 1) / n)) - sent
		sent += part
		var coin := UpgradeIcon.make("gold", pal.ui_accent, 36)
		coin.pivot_offset = Vector2(18, 18)
		var jx := randf_range(-26.0, 26.0)
		var p0 := src - Vector2(18, 18) + Vector2(jx, 0)
		var p2 := dst - Vector2(18, 18)
		var c1 := Vector2(p0.x + jx * 2.0, lerpf(p0.y, p2.y, 0.55))  # rise first, then drift across
		coin.position = p0
		coin.modulate.a = 0.0
		root.add_child(coin)
		var tw := coin.create_tween()
		tw.tween_interval(gap * k)
		tw.tween_callback(func() -> void:
			coin.modulate.a = 1.0
			left[0] -= part
			_results_gold_label.text = "+%d gold" % maxi(left[0], 0))
		tw.tween_method(func(q: float) -> void:
			coin.position = p0.lerp(c1, q).lerp(c1.lerp(p2, q), q)
			coin.scale = Vector2.ONE * lerpf(1.0, 0.75, q), 0.0, 1.0, fly).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		var last := k == n - 1
		tw.tween_callback(func() -> void:
			wallet[0] += part
			wl.text = str(wallet[0])
			Sfx.play("pickup", 0.0, 1.0 + 0.6 * k / maxf(n - 1, 1))
			_results_wallet.scale = Vector2(1.12, 1.12)
			_results_wallet.create_tween().tween_property(_results_wallet, "scale", Vector2.ONE, 0.1)
			if last:
				Sfx.play("upgrade", 0.0, 1.1)
				Sfx.vibrate(30)
			coin.queue_free())
	await get_tree().create_timer(gap * (n - 1) + fly + 0.45).timeout


## Results highlights: damage share per weapon/source as animated bars, plus
## chips for the biggest hit, the best streak and the most-killed germ.
const DMG_LABELS := {"allies": ["Swarm allies", "mode_swarm"], "towers": ["Towers", "mode_nucleus"], "dash": ["Dash", "lunge"],
	"land": ["Infected land", "mode_infection"], "bomb": ["Bombs", "volatile"], "outbreak": ["Plague", "outbreak"]}


func _dmg_label(src: String) -> Array:
	if world.upgrade_defs.has(src):
		var nm: String = world.upgrade_defs[src].name
		if world.evolved.has(src) and _evo_by_weapon.has(src):
			nm = _evo_by_weapon[src].name
		return [nm, src, world.evolved.has(src)]
	var l: Array = DMG_LABELS.get(src, [src.capitalize(), "outbreak"])
	return [l[0], l[1], false]


func _highlights_card(animate: bool) -> Control:
	var card := UiKit.panel(Color("#2a1f4a"), Color(pal.ui_accent, 0.25), 22, 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	var head := UiKit.label("HIGHLIGHTS", 22, pal.ui_accent)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(head)
	var rows := []
	var total := 0.0
	for src in world.damage_by:
		if src in ["revive", "other"]:
			continue
		total += float(world.damage_by[src])
		rows.append([src, float(world.damage_by[src])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	var k := 0
	for r in rows:
		var share: float = r[1] / maxf(total, 1.0)
		if share < 0.01 or k >= 5:
			continue
		var lab := _dmg_label(r[0])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UpgradeIcon.make(lab[1], IconArt.color_for(world.upgrade_defs.get(r[0], {"id": r[0]})), 34, lab[2]))
		var nm := UiKit.label(lab[0], 20, pal.text)
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.custom_minimum_size = Vector2(190, 0)
		nm.clip_text = true
		row.add_child(nm)
		var bar := Control.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 16)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.35)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.add_child(bg)
		var fill := ColorRect.new()
		fill.color = _wcolor_ui(r[0])
		fill.anchor_bottom = 1.0
		fill.anchor_right = 0.0 if animate else share
		bar.add_child(fill)
		row.add_child(bar)
		var pct := UiKit.label("%d%%" % roundi(share * 100.0), 20, pal.text)
		pct.autowrap_mode = TextServer.AUTOWRAP_OFF
		pct.custom_minimum_size = Vector2(56, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct)
		v.add_child(row)
		if animate:
			var tw := fill.create_tween()
			tw.tween_interval(0.3 + 0.12 * k)
			tw.tween_property(fill, "anchor_right", share, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		k += 1
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	if world.biggest_hit > 0.0:
		chips.add_child(UiKit.chip("Biggest hit %d  (%s)" % [roundi(world.biggest_hit), _dmg_label(world.biggest_src)[0]], Color("#ff5a7a"), Color(0.1, 0.05, 0.1), 18))
	if world.best_streak > 0:
		chips.add_child(UiKit.chip("Best streak x%d" % world.best_streak, Color("#5ce1e6"), Color(0.05, 0.08, 0.12), 18))
	var top := ""
	var top_n := 0
	for e in world.kills_by_type:
		if int(world.kills_by_type[e]) > top_n:
			top_n = int(world.kills_by_type[e])
			top = e
	if top != "":
		var ename := top
		for e in data.enemies:
			if e.id == top:
				ename = e.name
		chips.add_child(UiKit.chip("Most killed: %s x%d" % [ename, top_n], Color("#7bd389"), Color(0.05, 0.1, 0.06), 18))
	v.add_child(chips)
	if animate:
		UiKit.fade_in(chips, 0.9)
	return card


func _wcolor_ui(src: String) -> Color:
	if world.upgrade_defs.has(src):
		if world.evolved.has(src) and _evo_by_weapon.has(src):
			return GameData.color(_evo_by_weapon[src].get("color", "#ffd166"))
		return IconArt.color_for(world.upgrade_defs[src])
	return {"allies": pal.player_nucleus, "towers": pal.core, "dash": IconArt.COLORS.dash, "land": pal.player_nucleus, "bomb": pal.enemy_shot, "outbreak": pal.outbreak}.get(src, Color.WHITE)


# ------------------------------------------------------------------ pause

func _pause_run() -> void:
	if screen != "playing":
		return
	_set_screen("paused")
	_build_pause()


func _build_pause() -> void:
	var col: VBoxContainer = _pause[1]
	UiKit.clear(col)
	col.add_child(UiKit.label("PAUSED", 56, pal.ui_accent))
	col.add_child(UiKit.button("RESUME", _resume, 120))
	col.add_child(UiKit.button("SETTINGS", func() -> void:
		UiKit.clear(col)
		col.add_child(_settings_screen(_build_pause)), 90))
	col.add_child(UiKit.button("Quit run", func() -> void: _show_results(false), 80))
	if not _pause[0].visible:
		UiKit.reveal(_pause)
	else:
		UiKit.fade_in(col)


func _settings_screen(back: Callable) -> SettingsScreen:
	var st := SettingsScreen.new()
	st.setup(pal, _apply_settings, back, bool(bal.get("debug", {}).get("show_perf", false)), data.meta if bool(bal.get("debug", {}).get("dev_tools", false)) else [], str(bal.get("debug", {}).get("dev_password", "")))
	return st


func _show_settings() -> void:
	_menu_bg.show_hero = false
	var col: VBoxContainer = _menu[1]
	UiKit.clear(col)
	var st := _settings_screen(_show_menu)
	col.add_child(st)
	UiKit.fade_in(st)


## The BUILD overlay: everything you own, paused (BuildScreen).
func _show_build() -> void:
	if screen != "playing":
		return
	Sfx.play("click", 0.0)
	_set_screen("build")
	var col: VBoxContainer = _build[1]
	UiKit.clear(col)
	var bs := BuildScreen.new()
	bs.setup(pal, world, _evo_by_weapon, _evo_by_passive, _close_build)
	col.add_child(bs)
	UiKit.reveal(_build)
	Analytics.event("build_view", {"t": int(world.time), "level": world.level})


func _close_build() -> void:
	_build[0].visible = false
	_set_screen("playing")


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
			Sfx.vibrate(15)


## Tower bar tap (or keys 1-4): build on the empty pad you're standing on.
## The game keeps running.
func _build_tower(t: int) -> void:
	if not world.build_tower(t):
		Sfx.play("deny", 0.0)
		Sfx.vibrate(25)


## Wave 12 cleared: take the win or keep going into endless waves.
func _show_defense_won() -> void:
	_set_screen("defense_won")
	Sfx.play("evolve", 0.0)
	Sfx.vibrate(150)
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
	UiKit.reveal(_victory)
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
	_hints = []  # no first-run tips during the benchmark
	_hint_queue = []
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


# ------------------------------------------------------- first-run hints

## This run's hints: shared ones plus the mode's, minus those already seen.
func _load_hints(mode_id: String) -> void:
	_hints = []
	_hint_queue = []
	var h: Dictionary = data.get("hints", {})
	for hint in h.get("shared", []) + h.get(mode_id, []):
		if not Save.hints_seen.has(hint.id):
			_hints.append(hint)


func _queue_hint(hint: Dictionary) -> void:
	_hints.erase(hint)
	_hint_queue.append(hint)


func _hint_event(type: String) -> void:
	for hint in _hints.duplicate():
		if hint.get("event", "") == type:
			_queue_hint(hint)


## Timed hints, and one hint on screen at a time (each shown once, ever).
func _update_hints() -> void:
	for hint in _hints.duplicate():
		if hint.has("at") and world.time >= float(hint.at):
			_queue_hint(hint)
	if _hint_queue.is_empty() or hud.hint_showing():
		return
	var next: Dictionary = _hint_queue.pop_front()
	hud.show_hint(str(next.text))
	Save.hints_seen.append(next.id)
	Save.write()


## Outbreak button (or Q): start the frenzy if the meter is full.
## Swarm order from the fan-out menu (or keys 1-3).
func _set_order(o: int) -> void:
	if o == world.ally_order:
		hud.set_orders_open(false)
		return
	if not world.set_ally_order(o):
		Sfx.play("deny", 0.0)
		return
	hud.set_orders_open(false)


func _use_rift_power() -> void:
	if not world.use_rift_power():
		Sfx.play("deny", 0.0)


## "elite_brute" -> "ELITE LUMP", "shot" -> "SHOT": what just hit you.
func _cause_name(cause: String) -> String:
	var elite := cause.begins_with("elite_")
	var id := cause.trim_prefix("elite_")
	for e in data.enemies:
		if e.id == id:
			return ("ELITE " if elite else "") + str(e.name).to_upper()
	return id.to_upper().replace("_", " ")


func _use_ability() -> void:
	if not world.use_ability():
		Sfx.play("deny", 0.0)


func _trigger_outbreak() -> void:
	if not world.trigger_outbreak():
		Sfx.play("deny", 0.0)
