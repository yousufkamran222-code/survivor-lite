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


## The banked-upgrades button mirrors DASH on the left.
func upgrade_center() -> Vector2:
	return Vector2(dash_margin + dash_radius, size.y - dash_margin - dash_radius - 40.0)


func in_upgrade_button(p: Vector2) -> bool:
	return p.distance_to(upgrade_center()) <= dash_radius * 1.15


## Small, non-blocking reminder above the UPGRADE button.
func notice(text: String) -> void:
	_notice_text = text
	_notice_t = 1.8


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_notice_t = maxf(0.0, _notice_t - delta)
	_xp_flash = maxf(0.0, _xp_flash - delta)
	var i := 0
	while i < toasts.size():
		toasts[i].t += delta
		if toasts[i].t >= toasts[i].life:
			toasts.remove_at(i)
		else:
			i += 1
	if visible:
		queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var w := size.x
	# XP bar along the top edge.
	var xp_f := clampf(world.xp / world.xp_next, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, 16), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(0, 0, w * xp_f, 16), pal.xp_bar)
	if _xp_flash > 0.0:
		draw_rect(Rect2(0, 0, w, 16), Color(1, 1, 1, _xp_flash * 1.5))
	_draw_owned()
	draw_string(font, Vector2(16, 58), "LV %d" % world.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, pal.text)
	draw_string(font, Vector2(0, 62), UiKit.fmt_time(world.time), HORIZONTAL_ALIGNMENT_CENTER, w, 40, pal.text)
	draw_string(font, Vector2(16, 96), "%d kills" % world.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(pal.text, 0.7))
	if world.conv_on:
		var txt := "SWARM %d/%d" % [world.ally_count, world._ally_cap()]
		if world.swarm_power > 0.0:
			txt += "  +%d%%" % roundi(world.swarm_power * 100.0)
		draw_string(font, Vector2(0, 96), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 24, pal.player_nucleus)
	if world.terr != null:
		var pct := roundi(world.terr.infected_fraction() * 100.0)
		draw_string(font, Vector2(0, 96), "INFECTED %d%%" % pct, HORIZONTAL_ALIGNMENT_CENTER, w, 24, pal.player_nucleus)
	if world.def_on:
		_draw_defense(w)
	# Boss bar.
	if world.boss_index >= 0 and world.boss_index < world.e_hp.size():
		var f := world.e_hp[world.boss_index] / world.e_maxhp[world.boss_index]
		var r := Rect2(60, 120, w - 120, 18)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), pal.hp_bar)
		draw_string(font, Vector2(0, 112), str(world.enemy_defs[world.e_type[world.boss_index]].name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 22, pal.text)
	_draw_arrows()
	_draw_dash_button()
	_draw_upgrade_button()
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
	# Perf readout for playtests (balance.json debug.show_perf).
	if show_perf:
		var txt := "%d fps  %d enemies  sim %.1f ms  dc %d  fx %d" % [Engine.get_frames_per_second(), world.enemy_count(), sim_ms, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), fx_count]
		draw_string(font, Vector2(0, size.y - 14), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(1, 1, 0.6, 0.85))
	# Floating joystick.
	if stick_active:
		draw_circle(stick_origin, stick_radius, Color(1, 1, 1, 0.08))
		draw_arc(stick_origin, stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
		var knob := stick_origin + (stick_pos - stick_origin).limit_length(stick_radius)
		draw_circle(knob, 34, Color(1, 1, 1, 0.35))


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
	draw_string(font, c + Vector2(-dash_radius, 9), "DASH", HORIZONTAL_ALIGNMENT_CENTER, dash_radius * 2.0, 24, Color(1, 1, 1, 0.9 if ready else 0.35))
	# Charge pips under the label when you have more than one.
	if max_c > 1:
		for k in max_c:
			var p := c + Vector2((k - (max_c - 1) / 2.0) * 16.0, 28.0)
			draw_circle(p, 5.0, Color(pal.xp_bar, 0.9) if k < world.p_dash_charges else Color(1, 1, 1, 0.2))


func _draw_upgrade_button() -> void:
	var c := upgrade_center()
	var n := world.pending_levelups
	var on := n > 0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0) if on else 0.0
	var accent: Color = pal.ui_accent
	draw_circle(c, dash_radius, Color(accent, 0.1 + 0.12 * pulse) if on else Color(1, 1, 1, 0.05))
	draw_arc(c, dash_radius, 0, TAU, 48, Color(accent, 0.6 + 0.4 * pulse) if on else Color(1, 1, 1, 0.12), 3.0)
	draw_string(font, c + Vector2(-dash_radius, 9), "UPGRADE", HORIZONTAL_ALIGNMENT_CENTER, dash_radius * 2.0, 20, Color(1, 1, 1, 0.95 if on else 0.3))
	# Badge with the number of banked level-ups (always shown).
	var b := c + Vector2(dash_radius * 0.72, -dash_radius * 0.72)
	draw_circle(b, 19.0, accent if on else Color(1, 1, 1, 0.15))
	draw_string(font, b + Vector2(-19, 8), str(n), HORIZONTAL_ALIGNMENT_CENTER, 38, 22, Color(0.1, 0.06, 0.15) if on else Color(1, 1, 1, 0.5))
	if _notice_t > 0.0:
		var a := clampf(_notice_t / 0.5, 0.0, 1.0)
		draw_string(font, c + Vector2(-dash_radius, -dash_radius - 18.0), _notice_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(accent, a))


## Left-edge column of owned upgrades: icon plus level number (weapons
## first, evolved ones starred).
func _draw_owned() -> void:
	var y := 152.0
	var px := 34.0
	for pass_type in ["weapon", "passive"]:
		for u in world.upgrade_list:
			if u.type != pass_type or not world.owned.has(u.id):
				continue
			var c := Vector2(10.0 + px / 2.0, y)
			IconArt.draw(self, u.id, c, px, IconArt.color_for(u), world.evolved.has(u.id))
			draw_string(font, c + Vector2(px * 0.3, px * 0.55), str(world.owned[u.id]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.85))
			y += px + 8.0
		y += 6.0


## Nucleus mode: wave counter / countdown, nucleus health, biomass, the pad
## you're standing on, and the respawn countdown.
func _draw_defense(w: float) -> void:
	var wd := world
	var txt := ""
	if wd.wave_state == "breather":
		txt = "WAVE %d IN %d" % [wd.wave + 1, ceili(wd.wave_t)]
	elif wd.free_mode:
		txt = "FREE MODE  WAVE %d" % wd.wave
	else:
		txt = "FINAL WAVE" if wd.wave >= wd.wave_count else "WAVE %d / %d" % [wd.wave, wd.wave_count]
	draw_string(font, Vector2(0, 96), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 26, pal.core)
	draw_string(font, Vector2(16, 128), "BIOMASS %d" % floori(wd.biomass), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, pal.pad)
	var f := wd.core_hp / maxf(wd.core_max, 1.0)
	var r := Rect2(60, 150, w - 120, 16)
	draw_rect(r, Color(0, 0, 0, 0.55))
	var low := f < 0.3 and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
	draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), pal.player_hurt if low else pal.core)
	draw_string(font, Vector2(0, 145), "NUCLEUS", HORIZONTAL_ALIGNMENT_CENTER, w, 18, Color(pal.text, 0.8))
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
	var pad := wd.pad_under_player()
	if pad >= 0:
		var cost := wd.pad_next_cost(pad)
		var hint := "Fully upgraded" if cost < 0 else ("Hold to build" if wd.pad_tower[pad] < 0 else "Hold to upgrade") if wd.biomass >= cost else "Need %d biomass" % cost
		draw_string_outline(font, Vector2(0, size.y * 0.5 + 100.0), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 30, 6, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y * 0.5 + 100.0), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 30, pal.pad if cost >= 0 and wd.biomass >= cost else Color(pal.text, 0.75))
	if wd.p_down > 0.0:
		draw_string_outline(font, Vector2(0, size.y * 0.42), "REFORMING  %d" % ceili(wd.p_down), HORIZONTAL_ALIGNMENT_CENTER, w, 46, 8, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, size.y * 0.42), "REFORMING  %d" % ceili(wd.p_down), HORIZONTAL_ALIGNMENT_CENTER, w, 46, pal.player)
