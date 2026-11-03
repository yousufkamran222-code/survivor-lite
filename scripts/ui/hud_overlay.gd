class_name HudOverlay
extends Control
## In-run HUD drawn directly: XP bar, level, timer, kills, boss bar, the
## floating virtual joystick, the dash button, off-screen arrows to loot and
## elites, and short toasts. Ignores input; Main handles touches.

var world: World
var pal: Dictionary
var font: Font
var stick_active := false
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_radius := 90.0
var show_perf := false
var sim_ms := 0.0
var fx_count := 0
var cam_pos := Vector2.ZERO  # world position at the screen centre
var dash_radius := 72.0
var dash_margin := 40.0
var elite_color := Color("#ffd166")
var toasts: Array = []  # {text, color, t, life}
var _notice_text := ""
var _notice_t := 0.0
var _xp_flash := 0.0
var cpu_ms := 0.0  # CPU ms spent drawing the HUD since Main last read it
var view_ms := 0.0  # set by Main (smoothed WorldView CPU ms)
var bench_text := ""  # "BENCHMARK 32" while the benchmark runs
var _perf_text := ""
var _perf_t := 0.0
var _perf_worst := 0.0  # longest frame in the current 1 s window
var _perf_min_fps := 0.0
# Layers that redraw only when what they show changes (cheap HUD, see
# docs/POLISH_PLAN.md Phase 1): the owned-upgrade strip + button labels, and
# the top bars/readouts (at most 20x a second). Everything that animates every
# frame stays in this node's own _draw.
var _strip_layer: Control
var _bars_layer: Control
var _sig_strip := PackedInt32Array()
var _sig_strip_drawn := PackedInt32Array()
var _sig_bars := PackedInt32Array()
var _sig_bars_drawn := PackedInt32Array()
var _bars_wait := 0.0
var _sig_world: World = null
var icon_atlas: IconAtlas  # set by Main; baked icons for the strip
var _hint_text := ""
var _hint_t := 0.0  # time the current hint has been up
const HINT_S := 4.5
var _streak := 0
var _streak_t := 99.0  # time since the streak last grew
var streak_show := 10
var streak_window := 1.2


func flash_xp() -> void:
	_xp_flash = 0.4


## Big centred message, e.g. "ELITE GERM!" or "EVOLUTION READY".
func toast(text: String, color: Color, life: float = 2.0) -> void:
	for t in toasts:
		if t.text == text:
			t.t = 0.0
			return
	toasts.append({"text": text, "color": color, "t": 0.0, "life": life})
	if toasts.size() > 3:
		toasts.pop_front()


func dash_center() -> Vector2:
	return Vector2(size.x - dash_margin - dash_radius, size.y - dash_margin - dash_radius - 40.0)


func in_dash_button(p: Vector2) -> bool:
	return p.distance_to(dash_center()) <= dash_radius * 1.15


## The banked-upgrades pill sits top-right beside the pause button, out of
## the thumb zone (bottom-left clashed with the drag-anywhere joystick).
func upgrade_rect() -> Rect2:
	return Rect2(size.x - 90.0 - 14.0 - 200.0, 32.0, 200.0, 64.0)


func in_upgrade_button(p: Vector2) -> bool:
	return upgrade_rect().grow(10.0).has_point(p)


## The Outbreak button sits above DASH (right thumb owns both).
const OUTBREAK_R := 46.0


func outbreak_center() -> Vector2:
	return dash_center() + Vector2(0, -(dash_radius + OUTBREAK_R + 26.0))


func outbreak_on() -> bool:
	return world != null and bool(world.bal.get("outbreak", {}).get("enabled", false))


func in_outbreak_button(p: Vector2) -> bool:
	return outbreak_on() and p.distance_to(outbreak_center()) <= OUTBREAK_R * 1.25


## Small, non-blocking reminder above the UPGRADE button.
func notice(text: String) -> void:
	_notice_text = text
	_notice_t = 1.8


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font
	_strip_layer = _layer(func() -> void: _draw_strip(_strip_layer))
	_bars_layer = _layer(func() -> void: _draw_bars(_bars_layer))
	_sig_strip.resize(5)
	_sig_bars.resize(16)


func _layer(painter: Callable) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.draw.connect(func() -> void:
		if world != null:
			var t0 := Time.get_ticks_usec()
			painter.call()
			cpu_ms += (Time.get_ticks_usec() - t0) / 1000.0)
	add_child(c)
	return c

func _process(delta: float) -> void:
	_notice_t = maxf(0.0, _notice_t - delta)
	_xp_flash = maxf(0.0, _xp_flash - delta)
	_streak_t += delta
	if _hint_text != "":
		_hint_t += delta
	if show_perf and world != null:
		_update_perf(delta)
	var i := 0
	while i < toasts.size():
		toasts[i].t += delta
		if toasts[i].t >= toasts[i].life:
			toasts.remove_at(i)
		else:
			i += 1
	if visible:
		queue_redraw()
		if world != null:
			_update_layers(delta)


func _draw() -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	_draw_hud()
	cpu_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _draw_hud() -> void:
	var w := size.x
	if world.def_on:
		_draw_defense_live(w)
	_draw_arrows()
	_draw_dash_button()
	_draw_upgrade_button()
	_draw_outbreak_button()
	# Toasts.
	var ty := 240.0
	for t in toasts:
		var k: float = t.t / t.life
		var pop := 1.0 + 0.25 * maxf(0.0, 1.0 - t.t * 6.0)
		var a := clampf((1.0 - k) * 3.0, 0.0, 1.0)
		var fs := int(40 * pop)
		draw_string_outline(font, Vector2(0, ty), t.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 8, Color(0, 0, 0, 0.6 * a))
		draw_string(font, Vector2(0, ty), t.text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(t.color, a))
		ty += 52.0
	_draw_streak(w)
	_draw_hint(w)
	# Perf readout for playtests (balance.json debug.show_perf).
	if show_perf:
		draw_string(font, Vector2(0, size.y - 14), _perf_text, HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(1, 1, 0.6, 0.85))
	if bench_text != "":
		draw_string_outline(font, Vector2(0, 200), bench_text, HORIZONTAL_ALIGNMENT_CENTER, w, 34, 8, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, 200), bench_text, HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(1, 1, 0.6))
	# Floating joystick.
	if stick_active:
		draw_circle(stick_origin, stick_radius, Color(1, 1, 1, 0.08))
		draw_arc(stick_origin, stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
		var off := (stick_pos - stick_origin).limit_length(stick_radius)
		var knob := stick_origin + off
		draw_circle(knob, 34, Color(1, 1, 1, 0.35))
		# Direction marker on the base rim once you're past the dead zone.
		if off.length() > stick_radius * 0.15:
			var d := off.normalized()
			var tip := stick_origin + d * (stick_radius + 14.0)
			var side := d.orthogonal() * 9.0
			draw_colored_polygon(PackedVector2Array([tip, tip - d * 14.0 + side, tip - d * 14.0 - side]), Color(1, 1, 1, 0.5))


## Top bars and readouts (bars layer): XP, level, timer, kills, mode readout,
## Nucleus bars, boss bar. Redrawn only when one of them changes.
func _draw_bars(ci: CanvasItem) -> void:
	var w := size.x
	var xp_f := clampf(world.xp / world.xp_next, 0.0, 1.0)
	ci.draw_rect(Rect2(0, 0, w, 16), Color(0, 0, 0, 0.5))
	ci.draw_rect(Rect2(0, 0, w * xp_f, 16), pal.xp_bar)
	if _xp_flash > 0.0:
		ci.draw_rect(Rect2(0, 0, w, 16), Color(1, 1, 1, _xp_flash * 1.5))
	ci.draw_string(font, Vector2(16, 58), "LV %d" % world.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, pal.text)
	ci.draw_string(font, Vector2(0, 62), UiKit.fmt_time(world.time), HORIZONTAL_ALIGNMENT_CENTER, w, 40, pal.text)
	ci.draw_string(font, Vector2(16, 96), "%d kills" % world.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(pal.text, 0.7))
	if world.conv_on:
		var txt := "SWARM %d/%d" % [world.ally_count, world._ally_cap()]
		if world.swarm_power > 0.0:
			txt += "  +%d%%" % roundi(world.swarm_power * 100.0)
		ci.draw_string(font, Vector2(0, 96), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 24, pal.player_nucleus)
	if world.terr != null:
		var pct := roundi(world.terr.infected_fraction() * 100.0)
		ci.draw_string(font, Vector2(0, 96), "INFECTED %d%%" % pct, HORIZONTAL_ALIGNMENT_CENTER, w, 24, pal.player_nucleus)
	if world.def_on:
		_draw_defense_bars(ci, w)
	if world.boss_index >= 0 and world.boss_index < world.e_hp.size():
		var f := world.e_hp[world.boss_index] / world.e_maxhp[world.boss_index]
		var r := Rect2(60, 120, w - 120, 18)
		ci.draw_rect(r, Color(0, 0, 0, 0.55))
		ci.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), pal.hp_bar)
		ci.draw_string(font, Vector2(0, 112), str(world.enemy_defs[world.e_type[world.boss_index]].name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 22, pal.text)


## Owned-upgrade strip and the DASH / UPGRADE labels (strip layer).
func _draw_strip(ci: CanvasItem) -> void:
	_draw_owned(ci)
	var dc := dash_center()
	ci.draw_string(font, dc + Vector2(-dash_radius, 9), "DASH", HORIZONTAL_ALIGNMENT_CENTER, dash_radius * 2.0, 24, Color(1, 1, 1, 0.9 if world.can_dash() else 0.35))
	var rc := upgrade_rect()
	var n := world.pending_levelups
	var on := n > 0
	var accent: Color = pal.ui_accent
	ci.draw_string(font, Vector2(rc.position.x + 16.0, rc.get_center().y + 9.0), "UPGRADE", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.95 if on else 0.35))
	var b := Vector2(rc.end.x - 34.0, rc.get_center().y)
	ci.draw_circle(b, 21.0, accent if on else Color(1, 1, 1, 0.15))
	ci.draw_string(font, b + Vector2(-21, 9), str(n), HORIZONTAL_ALIGNMENT_CENTER, 42, 24, Color(0.1, 0.06, 0.15) if on else Color(1, 1, 1, 0.5))


## Decides which cached layers need a redraw this frame.
func _update_layers(delta: float) -> void:
	var fresh := world != _sig_world
	_sig_world = world
	var owned_sum := 0
	for id in world.owned:
		owned_sum = owned_sum * 31 + int(world.owned[id]) + id.hash() % 997
	_sig_strip[0] = owned_sum
	_sig_strip[1] = world.evolved.size()
	_sig_strip[2] = world.pending_levelups
	_sig_strip[3] = 1 if world.can_dash() else 0
	_sig_strip[4] = 1 if icon_atlas != null and icon_atlas.baked else 0
	if fresh or _sig_strip != _sig_strip_drawn:
		_sig_strip_drawn = _sig_strip.duplicate()
		_strip_layer.queue_redraw()
	var w := size.x
	_sig_bars[0] = int(clampf(world.xp / world.xp_next, 0.0, 1.0) * w)
	_sig_bars[1] = int(_xp_flash * 20.0)
	_sig_bars[2] = world.level
	_sig_bars[3] = int(world.time)
	_sig_bars[4] = world.kills
	_sig_bars[5] = world.ally_count * 1000 + roundi(world.swarm_power * 100.0)
	_sig_bars[6] = roundi(world.terr.infected_fraction() * 100.0) if world.terr != null else 0
	var bi := world.boss_index
	_sig_bars[7] = int(world.e_hp[bi] / world.e_maxhp[bi] * w) if bi >= 0 and bi < world.e_hp.size() else -1
	if world.def_on:
		_sig_bars[8] = world.wave * 4 + (0 if world.wave_state == "breather" else 1) + (2 if world.free_mode else 0)
		_sig_bars[9] = ceili(world.wave_t) if world.wave_state == "breather" else 0
		_sig_bars[10] = floori(world.biomass)
		_sig_bars[11] = int(world.core_hp / maxf(world.core_max, 1.0) * w)
		_sig_bars[12] = int(fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25) if world.core_hp < world.core_max * 0.3 else 0
	_bars_wait -= delta
	if fresh or (_bars_wait <= 0.0 and _sig_bars != _sig_bars_drawn):
		_sig_bars_drawn = _sig_bars.duplicate()
		_bars_wait = 0.05
		_bars_layer.queue_redraw()


## Arrows at the screen edge pointing to off-screen chests, elites and boss.
func _draw_arrows() -> void:
	var half := size / 2.0
	var inset := Rect2(Vector2(36, 150), size - Vector2(72, 330))
	var targets := []
	for p in world.c_pos:
		targets.append([p, pal.gem_large, true])
	for i in world.e_pos.size():
		if world.is_elite(i):
			targets.append([world.e_pos[i], elite_color, false])
	if world.boss_index >= 0 and world.boss_index < world.e_pos.size():
		targets.append([world.e_pos[world.boss_index], pal.hp_bar, false])
	if world.def_on:
		targets.append([world.core_pos, pal.core, false])
	for tg in targets:
		var sp: Vector2 = tg[0] - cam_pos + half
		if Rect2(Vector2.ZERO, size).grow(-10).has_point(sp):
			continue
		var dir := (sp - half).normalized()
		# Walk from the centre to the inset rect edge along dir.
		var tx := INF
		var tyy := INF
		if dir.x != 0.0:
			tx = ((inset.end.x if dir.x > 0.0 else inset.position.x) - half.x) / dir.x
		if dir.y != 0.0:
			tyy = ((inset.end.y if dir.y > 0.0 else inset.position.y) - half.y) / dir.y
		var edge := half + dir * minf(tx, tyy)
		var c: Color = tg[1]
		var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
		var tip := edge + dir * 18.0
		var side := dir.orthogonal() * 13.0
		draw_colored_polygon(PackedVector2Array([tip, edge - dir * 8.0 + side, edge - dir * 8.0 - side]), Color(c, pulse))
		if tg[2]:
			draw_rect(Rect2(edge - dir * 28.0 - Vector2(9, 7), Vector2(18, 14)), Color(c, pulse))


func _draw_dash_button() -> void:
	var c := dash_center()
	var ready := world.can_dash()
	var max_c := world.dash_max_charges()
	draw_circle(c, dash_radius, Color(1, 1, 1, 0.16 if ready else 0.07))
	draw_arc(c, dash_radius, 0, TAU, 48, Color(1, 1, 1, 0.45 if ready else 0.15), 3.0)
	if world.p_dash_charges < max_c:
		var f := 1.0 - world.p_dash_cd / world.dash_cooldown()
		draw_arc(c, dash_radius - 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(f, 0.0, 1.0), 48, Color(pal.xp_bar, 0.8), 6.0)
	# Charge pips under the label when you have more than one.
	if max_c > 1:
		for k in max_c:
			var p := c + Vector2((k - (max_c - 1) / 2.0) * 16.0, 28.0)
			draw_circle(p, 5.0, Color(pal.xp_bar, 0.9) if k < world.p_dash_charges else Color(1, 1, 1, 0.2))


func _draw_upgrade_button() -> void:
	var rc := upgrade_rect()
	var n := world.pending_levelups
	var on := n > 0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0) if on else 0.0
	var accent: Color = pal.ui_accent
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(32)
	sb.bg_color = Color(accent, 0.16 + 0.14 * pulse) if on else Color(1, 1, 1, 0.05)
	sb.set_border_width_all(3)
	sb.border_color = Color(accent, 0.6 + 0.4 * pulse) if on else Color(1, 1, 1, 0.14)
	draw_style_box(sb, rc)
	if _notice_t > 0.0:
		var a := clampf(_notice_t / 0.5, 0.0, 1.0)
		draw_string(font, Vector2(rc.end.x - 360.0, rc.end.y + 28.0), _notice_text, HORIZONTAL_ALIGNMENT_RIGHT, 360.0, 24, Color(accent, a))


## Outbreak: the rim fills with kills, the button glows when ready, and
## during the frenzy the rim shows the time left.
func _draw_outbreak_button() -> void:
	if not outbreak_on():
		return
	var c := outbreak_center()
	var col: Color = pal.get("outbreak", Color("#ff5dd6"))
	var r := OUTBREAK_R
	var t := Time.get_ticks_msec() / 1000.0
	if world.outbreak_t > 0.0:
		var left := world.outbreak_t / float(world.bal.outbreak.duration_s)
		draw_circle(c, r + 6.0 + 4.0 * sin(t * 12.0), Color(col, 0.25))
		draw_circle(c, r, Color(col, 0.45))
		draw_arc(c, r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * left, 40, Color.WHITE, 6.0)
	elif world.outbreak_ready():
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		draw_circle(c, r + 8.0 + 6.0 * pulse, Color(col, 0.18 + 0.15 * pulse))
		draw_circle(c, r, Color(col, 0.55 + 0.25 * pulse))
		draw_arc(c, r, 0, TAU, 40, Color.WHITE, 3.0)
	else:
		draw_circle(c, r, Color(1, 1, 1, 0.06))
		draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.14), 3.0)
		if world.outbreak > 0.0:
			draw_arc(c, r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * world.outbreak, 40, Color(col, 0.85), 6.0)
	var ready := world.outbreak_ready() or world.outbreak_t > 0.0
	if icon_atlas != null and icon_atlas.has_icon("outbreak", false):
		icon_atlas.draw_icon(self, "outbreak", c, r * 1.1)
	else:
		IconArt.draw(self, "outbreak", c, r * 1.1, Color.WHITE if ready else Color(1, 1, 1, 0.4))


## Left-edge column of owned upgrades: icon plus level number (weapons
## first, evolved ones starred).
func _draw_owned(ci: CanvasItem) -> void:
	var px := 34.0
	# Icons first (baked atlas: one batched draw call), then all the level
	# numbers (one text batch), so the two never interleave.
	var slots := []
	var y := 152.0
	for pass_type in ["weapon", "passive"]:
		for u in world.upgrade_list:
			if u.type != pass_type or not world.owned.has(u.id):
				continue
			slots.append([u, Vector2(10.0 + px / 2.0, y)])
			y += px + 8.0
		y += 6.0
	for sl in slots:
		var u: Dictionary = sl[0]
		var evo: bool = world.evolved.has(u.id)
		if icon_atlas != null and icon_atlas.has_icon(u.id, evo):
			icon_atlas.draw_icon(ci, u.id, sl[1], px, evo)
		else:
			IconArt.draw(ci, u.id, sl[1], px, IconArt.color_for(u), evo)
	for sl in slots:
		ci.draw_string(font, sl[1] + Vector2(px * 0.3, px * 0.55), str(world.owned[sl[0].id]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))


## Nucleus mode: wave counter / countdown, nucleus health, biomass, the pad
## you're standing on, and the respawn countdown.
func _draw_defense_bars(ci: CanvasItem, w: float) -> void:
	var wd := world
	var txt := ""
	if wd.wave_state == "breather":
		txt = "WAVE %d IN %d" % [wd.wave + 1, ceili(wd.wave_t)]
	elif wd.free_mode:
		txt = "FREE MODE  WAVE %d" % wd.wave
	else:
		txt = "FINAL WAVE" if wd.wave >= wd.wave_count else "WAVE %d / %d" % [wd.wave, wd.wave_count]
	ci.draw_string(font, Vector2(0, 96), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 26, pal.core)
	ci.draw_string(font, Vector2(16, 128), "BIOMASS %d" % floori(wd.biomass), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, pal.pad)
	var f := wd.core_hp / maxf(wd.core_max, 1.0)
	var r := Rect2(60, 150, w - 120, 16)
	ci.draw_rect(r, Color(0, 0, 0, 0.55))
	var low := f < 0.3 and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), pal.player_hurt if low else pal.core)
	ci.draw_string(font, Vector2(0, 145), "NUCLEUS", HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(pal.text, 0.8))


## Nucleus mode parts that animate every frame.
func _draw_defense_live(w: float) -> void:
	var wd := world
	# Big 3-2-1 before each wave, and a warning before the boss.
	if wd.wave_state == "breather" and wd.state == "playing":
		if wd.next_wave_is_boss():
			var a := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 150.0)
			draw_string_outline(font, Vector2(0, 202), "MOTHER CELL INCOMING", HORIZONTAL_ALIGNMENT_CENTER, w, 34, 8, Color(0, 0, 0, 0.6 * a))
			draw_string(font, Vector2(0, 202), "MOTHER CELL INCOMING", HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(pal.player_hurt, a))
		if wd.wave_t <= 3.0 and wd.wave_t > 0.0:
			var frac := wd.wave_t - floorf(wd.wave_t)
			var fs := int(96.0 * (1.0 + 0.35 * frac))
			var num := str(ceili(wd.wave_t))
			draw_string_outline(font, Vector2(0, size.y * 0.3 + fs * 0.35), num, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 12, Color(0, 0, 0, 0.55 * (1.0 - frac * 0.5)))
			draw_string(font, Vector2(0, size.y * 0.3 + fs * 0.35), num, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(pal.core, 1.0 - frac * 0.5))
	if tower_bar_visible():
		_draw_tower_bar()
	var pad := wd.pad_under_player()
	if pad >= 0 and wd.pad_tower[pad] >= 0:
		var cost := wd.pad_next_cost(pad)
		var hint := "Fully upgraded" if cost < 0 else "Hold to upgrade" if wd.biomass >= cost else "Need %d biomass" % cost
		draw_string_outline(font, Vector2(0, size.y * 0.5 + 100.0), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 30, 6, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y * 0.5 + 100.0), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 30, pal.pad if cost >= 0 and wd.biomass >= cost else Color(pal.text, 0.75))
	if wd.p_down > 0.0:
		draw_string_outline(font, Vector2(0, size.y * 0.42), "REFORMING  %d" % ceili(wd.p_down), HORIZONTAL_ALIGNMENT_CENTER, w, 46, 8, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y * 0.42), "REFORMING  %d" % ceili(wd.p_down), HORIZONTAL_ALIGNMENT_CENTER, w, 46, pal.player)


# ---------------------------------------------------- Nucleus tower bar

const BAR_W := 150.0
const BAR_H := 124.0
const BAR_GAP := 10.0


## Shown while standing on an empty pad: tap a tower to build it (no pause).
func tower_bar_visible() -> bool:
	return world != null and world.def_on and world.state == "playing" and world.empty_pad_under_player() >= 0


func _tower_rect(i: int) -> Rect2:
	var n := world.tower_defs.size()
	var total := n * BAR_W + (n - 1) * BAR_GAP
	var x0 := (size.x - total) / 2.0
	return Rect2(x0 + i * (BAR_W + BAR_GAP), size.y - 540.0, BAR_W, BAR_H)


## Index of the tower button under a screen point, or -1.
func tower_button_at(p: Vector2) -> int:
	if not tower_bar_visible():
		return -1
	for i in world.tower_defs.size():
		if _tower_rect(i).grow(6).has_point(p):
			return i
	return -1


func _draw_tower_bar() -> void:
	var first := _tower_rect(0)
	draw_string_outline(font, Vector2(0, first.position.y - 14), "TAP A TOWER TO BUILD", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, 6, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(0, first.position.y - 14), "TAP A TOWER TO BUILD", HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, pal.pad)
	for i in world.tower_defs.size():
		var d: Dictionary = world.tower_defs[i]
		var r := _tower_rect(i)
		var cost := world.tower_cost(i)
		var ok := world.biomass >= float(cost)
		var tc := GameData.color(d.get("color", "#ffffff"))
		var a := 1.0 if ok else 0.4
		draw_rect(r, Color(0.16, 0.11, 0.29, 0.9))
		draw_rect(r, Color(tc, 0.85 * a), false, 3.0)
		IconArt.draw(self, d.weapon, r.position + Vector2(r.size.x / 2.0, 40), 52, Color(tc, a))
		draw_string(font, r.position + Vector2(0, 88), str(d.name), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color(1, 1, 1, a))
		draw_string(font, r.position + Vector2(0, 113), str(cost), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, Color(pal.pad, a) if ok else Color("#ff9a9a"))


## Perf readout (debug.show_perf): FPS with the worst 1 s minimum, the
## screen's refresh rate, and CPU ms per part. Rebuilt 4x a second so the
## readout itself costs almost nothing.
func _update_perf(delta: float) -> void:
	_perf_worst = maxf(_perf_worst, delta)
	_perf_t += delta
	if _perf_t < 0.25:
		return
	_perf_t = 0.0
	_perf_min_fps = 1.0 / maxf(_perf_worst, 0.001)
	_perf_worst = 0.0
	var hz := DisplayServer.screen_get_refresh_rate()
	_perf_text = "%d fps (min %d) %s | sim %.1f view %.1f hud %.1f ms | dc %d | %d enemies fx %d" % [
		Engine.get_frames_per_second(), roundi(_perf_min_fps), ("%dHz" % roundi(hz)) if hz > 0.0 else "?Hz",
		sim_ms, view_ms, cpu_ms, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		world.enemy_count(), fx_count]


## Cosmetic kill streak ("x25"), shown from juice.streak_show kills.
func set_streak(n: int) -> void:
	if n > _streak or n == 0:
		_streak_t = 0.0 if n > 0 else 99.0
	_streak = n


func _draw_streak(w: float) -> void:
	if _streak < streak_show or _streak_t > streak_window + 0.4:
		return
	var a := clampf((streak_window + 0.4 - _streak_t) / 0.4, 0.0, 1.0)
	var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - _streak_t / 0.12)
	var milestone := _streak >= 50
	var fs := int((34.0 + minf(_streak, 100) * 0.12) * pop)
	var col: Color = pal.ui_accent if milestone else Color(1, 1, 1)
	var pos := Vector2(w - 24.0, 205.0)
	draw_string_outline(font, pos, "x%d" % _streak, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, 8, Color(0, 0, 0, 0.6 * a))
	draw_string(font, pos, "x%d" % _streak, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, Color(col, a))


## First-run hint banner (Main queues them, one at a time).
func show_hint(text: String) -> void:
	_hint_text = text
	_hint_t = 0.0


func hint_showing() -> bool:
	return _hint_text != "" and _hint_t < HINT_S


func _draw_hint(w: float) -> void:
	if not hint_showing():
		return
	var a := clampf(minf(_hint_t / 0.25, (HINT_S - _hint_t) / 0.4), 0.0, 1.0)
	var width := minf(w - 60.0, 600.0)
	var fs := 26
	var sz := font.get_multiline_string_size(_hint_text, HORIZONTAL_ALIGNMENT_CENTER, width - 40.0, fs)
	# Above the DASH/UPGRADE buttons; higher when the Nucleus tower bar is up.
	var bottom := size.y - (660.0 if tower_bar_visible() else 360.0)
	var rect := Rect2((w - width) / 2.0, bottom - sz.y - 28.0 + 12.0 * (1.0 - a), width, sz.y + 28.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.14, 0.88 * a)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color(pal.ui_accent, 0.7 * a)
	draw_style_box(sb, rect)
	draw_multiline_string(font, rect.position + Vector2(20, 14 + fs * 0.85), _hint_text, HORIZONTAL_ALIGNMENT_CENTER, width - 40.0, fs, -1, Color(1, 1, 1, a))
