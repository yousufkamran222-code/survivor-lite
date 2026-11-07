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
var cam_zoom := 1.0  # WorldView's camera zoom (arrows map world -> screen with it)
const XP_H := 22.0  # XP bar height
# Danger readability: a red edge vignette at low HP that pulses with the
# heartbeat (Main sets low_hp and calls beat()), and a soft glow at the screen
# edge on the side a hit came from (hit_from). Edges only: cheap fill rate.
var low_hp := 0.0  # 0 = fine .. 1 = nearly dead
var _beat := 0.0
var _hits: Array = []  # [dir: Vector2, t: float]
var _edge_tex: Array = []  # 4 alpha ramps, opaque at the screen edge: left, right, top, bottom
var _blob_tex: Texture2D  # 64x64 soft radial blob
var juice: Dictionary = {}  # set by Main (balance.juice)
var evo_seq: Dictionary = {}  # Main's evolution sequence while it plays (t, dur, burst, name, desc, color, weapon)
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
var coach := {}  # the tutorial's prompt this frame (World.coach(), set by Main)
var _coach_idx := -1
var _coach_t := 0.0  # time the current prompt has been up
var title_t := -1.0  # first-launch title over the dish (>= 0 while showing)
var _hint_t := 0.0  # time the current hint has been up
const HINT_S := 4.5
var streak_show := 10


func flash_xp() -> void:
	_xp_flash = 0.4


## Big centred message, e.g. "ELITE GERM!" or "EVOLUTION READY".
## Small "hit by X" label under the cell (what hurt you), refreshed per hit.
var _hurt_by := ""
var _hurt_by_t := 0.0


func hurt_by(text: String) -> void:
	_hurt_by = text
	_hurt_by_t = 1.0


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


## UPGRADE sits in the right column above Outbreak and DASH (bottom-left
## clashed with the drag-anywhere joystick; the top-right pill was too small
## and too far).
const UPGRADE_R := 54.0


func upgrade_center() -> Vector2:
	return outbreak_center() + Vector2(0, -(OUTBREAK_R + UPGRADE_R + 26.0))


func in_upgrade_button(p: Vector2) -> bool:
	return p.distance_to(upgrade_center()) <= UPGRADE_R * 1.2


## The Outbreak button sits above DASH (right thumb owns both).
const OUTBREAK_R := 46.0


func outbreak_center() -> Vector2:
	return dash_center() + Vector2(0, -(dash_radius + OUTBREAK_R + 26.0))


func outbreak_on() -> bool:
	return world != null and bool(world.bal.get("outbreak", {}).get("enabled", false))


func in_outbreak_button(p: Vector2) -> bool:
	return outbreak_on() and p.distance_to(outbreak_center()) <= OUTBREAK_R * 1.25


## Swarm orders: a button left of Outbreak shows the current order; tapping
## it fans out the three orders and pauses the run (Main stops stepping);
## tap one to switch, or anywhere else to close.
const ORDER_R := 44.0
const ORDER_OPT_R := 42.0
const ORDER_FAN := 124.0
var orders_open := false
var _orders_t := 0.0


func orders_on() -> bool:
	return world != null and world.conv_on


func order_center() -> Vector2:
	return outbreak_center() + Vector2(-(OUTBREAK_R + ORDER_R + 30.0), 0)


## Fan positions: left, up-left, up (clear of UPGRADE on the right).
func order_option_center(k: int) -> Vector2:
	var a := PI + k * PI / 4.0
	return order_center() + Vector2(cos(a), sin(a)) * ORDER_FAN


## -2 = the order button, 0..2 = an option of the open fan, -1 = neither.
func order_button_at(p: Vector2) -> int:
	if not orders_on():
		return -1
	if orders_open:
		for k in World.ORDER_IDS.size():
			if p.distance_to(order_option_center(k)) <= ORDER_OPT_R * 1.2:
				return k
	if p.distance_to(order_center()) <= ORDER_R * 1.2:
		return -2
	return -1


func set_orders_open(on: bool) -> void:
	orders_open = on
	_orders_t = 0.0


func _order_color(k: int) -> Color:
	return GameData.color(world.bal.conversion.orders[World.ORDER_IDS[k]].color)


func _draw_order_icon(key: String, c: Vector2, px: float, col: Color) -> void:
	if icon_atlas != null and icon_atlas.has_icon(key, false):
		icon_atlas.draw_icon(self, key, c, px)
	else:
		IconArt.draw(self, key, c, px, col)


func _draw_orders() -> void:
	if not orders_on():
		return
	var cur := world.ally_order
	var c := order_center()
	var col := _order_color(cur)
	if orders_open:
		# Paused: dim the field and say so.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35 * clampf(_orders_t / 0.12, 0.0, 1.0)))
		var ty := c.y - ORDER_FAN - 90.0
		draw_string_outline(font, Vector2(0, ty), "SWARM ORDERS", HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, 8, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, ty), "SWARM ORDERS", HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color.WHITE)
		draw_string(font, Vector2(0, ty + 34), "Paused. Tap an order, or anywhere to resume.", HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.75))
	draw_circle(c, ORDER_R, Color(col, 0.22 if orders_open else 0.12))
	draw_arc(c, ORDER_R, 0, TAU, 40, Color(col, 0.85), 3.0)
	if world.order_cd > 0.0:
		var f := 1.0 - world.order_cd / maxf(float(world.bal.conversion.get("order_switch_s", 1.0)), 0.01)
		draw_arc(c, ORDER_R - 5.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(1, 1, 1, 0.6), 4.0)
	_draw_order_icon("order_" + World.ORDER_IDS[cur], c, ORDER_R * 1.25, col)
	if not orders_open:
		return
	var grow := clampf(_orders_t / 0.12, 0.0, 1.0)
	for k in World.ORDER_IDS.size():
		var oc := _order_color(k)
		var p := c.lerp(order_option_center(k), grow)
		var on := k == cur
		draw_circle(p, ORDER_OPT_R + 4.0, Color(0, 0, 0, 0.45))
		draw_circle(p, ORDER_OPT_R, Color(oc, 0.35 if on else 0.16))
		draw_arc(p, ORDER_OPT_R, 0, TAU, 36, Color.WHITE if on else Color(oc, 0.9), 4.0 if on else 3.0)
		_draw_order_icon("order_" + World.ORDER_IDS[k], p, ORDER_OPT_R * 1.2, oc)
		var name := str(world.bal.conversion.orders[World.ORDER_IDS[k]].name).to_upper()
		var lp := p + Vector2(-60, ORDER_OPT_R + 22.0)
		draw_string_outline(font, lp, name, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, 5, Color(0, 0, 0, 0.7))
		draw_string(font, lp, name, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color.WHITE if on else oc)


## Small, non-blocking reminder above the UPGRADE button.
func notice(text: String) -> void:
	_notice_text = text
	_notice_t = 1.8


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = UiKit.display_font()  # chunky HUD text (Lilita One)
	_strip_layer = _layer(func() -> void: _draw_strip(_strip_layer))
	_bars_layer = _layer(func() -> void: _draw_bars(_bars_layer))
	_edge_tex = _make_edge_texs()
	_blob_tex = _make_blob_tex()
	_sig_strip.resize(5)
	_sig_bars.resize(17)


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
	_update_streak(delta)
	_beat = maxf(0.0, _beat - delta * 3.0)
	var hl := float(juice.get("hurt_dir_s", 0.45))
	var hi := 0
	while hi < _hits.size():
		_hits[hi][1] += delta
		if _hits[hi][1] >= hl:
			_hits.remove_at(hi)
		else:
			hi += 1
	if orders_open:
		_orders_t += delta
	if _hint_text != "":
		_hint_t += delta
	if int(coach.get("index", -1)) != _coach_idx:
		_coach_idx = int(coach.get("index", -1))
		_coach_t = 0.0
	_coach_t += delta
	if title_t >= 0.0:
		title_t += delta
		if title_t > TITLE_S:
			title_t = -1.0
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
	if world.stasis_on():  # Lab ability: time stopped
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.88, 1.0, 0.15))
	_draw_danger()
	_draw_hurt_info()
	_draw_xp_live(w)
	if world.def_on:
		_draw_defense_live(w)
	_draw_arrows()
	_draw_dash_button()
	_draw_upgrade_button()
	_draw_outbreak_button()
	_draw_rift_power_button()
	_draw_ability_button()
	_draw_rift_hud(w)
	_draw_orders()
	# Toasts.
	var ty := 290.0
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
	_draw_coach(w)
	_draw_title(w)
	# Perf readout for playtests (balance.json debug.show_perf).
	if show_perf:
		draw_string(font, Vector2(0, size.y - 14), _perf_text, HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(1, 1, 0.6, 0.85))
	if bench_text != "":
		draw_string_outline(font, Vector2(0, 200), bench_text, HORIZONTAL_ALIGNMENT_CENTER, w, 34, 8, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, 200), bench_text, HORIZONTAL_ALIGNMENT_CENTER, w, 34, Color(1, 1, 0.6))
	if not evo_seq.is_empty():
		_draw_evolution(w)
		return
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


## Evolution sequence overlay: the field dims while the cell charges
## ("EVOLVING..."), a white flash at the burst, then a banner with the evolved
## icon, "EVOLUTION!", the name (popping in) and what it does.
func _draw_evolution(w: float) -> void:
	var t := float(evo_seq.t)
	var burst := float(evo_seq.burst)
	var dur := float(evo_seq.dur)
	var col: Color = evo_seq.color
	var fade_out := clampf((dur - t) / 0.25, 0.0, 1.0)
	var dim := clampf(t / 0.25, 0.0, 1.0) * fade_out
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.0, 0.06, 0.55 * dim))
	var cy := size.y * 0.30
	if t < burst:
		var pulse := 0.6 + 0.4 * sin(t * 18.0)
		var es := int(36.0 + 10.0 * t / burst)
		draw_string_outline(font, Vector2(0, cy + 40), "EVOLVING...", HORIZONTAL_ALIGNMENT_CENTER, w, es, 9, Color(0, 0, 0, 0.7 * dim))
		draw_string(font, Vector2(0, cy + 40), "EVOLVING...", HORIZONTAL_ALIGNMENT_CENTER, w, es, Color(col.lightened(0.35), (0.7 + 0.3 * pulse) * dim))
		return
	var k := t - burst
	if k < 0.3:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.85 * (1.0 - k / 0.3)))
	var pop := 1.0 + 0.6 * exp(-9.0 * k) * cos(14.0 * k)
	var a := clampf(k / 0.08, 0.0, 1.0) * fade_out
	var ip := 120.0 * minf(pop, 1.3)
	var key: String = evo_seq.weapon
	var ic := Vector2(w / 2.0, cy - 40.0)
	if icon_atlas != null and icon_atlas.has_icon(key, true):
		icon_atlas.draw_icon(self, key, ic, ip, true)
	else:
		IconArt.draw(self, key, ic, ip, col, true)
	var t1 := cy + 60.0
	draw_string_outline(font, Vector2(0, t1), "EVOLUTION!", HORIZONTAL_ALIGNMENT_CENTER, w, 32, 8, Color(0, 0, 0, 0.7 * a))
	draw_string(font, Vector2(0, t1), "EVOLUTION!", HORIZONTAL_ALIGNMENT_CENTER, w, 32, Color(pal.ui_accent, a))
	var fs := int(64.0 * pop)
	var name := str(evo_seq.name).to_upper()
	draw_string_outline(font, Vector2(0, t1 + 76), name, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 12, Color(0, 0, 0, 0.75 * a))
	draw_string(font, Vector2(0, t1 + 76), name, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(col.lightened(0.15), a))
	draw_string_outline(font, Vector2(0, t1 + 122), str(evo_seq.desc), HORIZONTAL_ALIGNMENT_CENTER, w, 24, 6, Color(0, 0, 0, 0.6 * a))
	draw_string(font, Vector2(0, t1 + 122), str(evo_seq.desc), HORIZONTAL_ALIGNMENT_CENTER, w, 24, Color(1, 1, 1, 0.9 * a))


## Rift Power button (left of DASH, once you've won one): kill meter ring,
## the power's weapon icon, level pips; glows when ready.
const POWER_R := 46.0
const POWER_ICON := {"lance": "chain", "barrage": "bolt", "phalanx": "orbit", "heatwave": "nova"}


func power_center() -> Vector2:
	var c := dash_center() + Vector2(-(dash_radius + POWER_R + 26.0), 0)
	if world != null and world.ability != "":
		c.x -= POWER_R * 2.0 + 20.0  # the Lab ability owns the spot next to DASH
	return c


## Lab ability button (left of DASH): kill-meter ring, the ability's icon,
## level pips; glows when ready; while active the ring drains with the time left.
func ability_center() -> Vector2:
	return dash_center() + Vector2(-(dash_radius + POWER_R + 26.0), 0)


func in_ability_button(p: Vector2) -> bool:
	return world != null and world.ability != "" and p.distance_to(ability_center()) <= POWER_R * 1.25


func _draw_ability_button() -> void:
	if world.ability == "":
		return
	var c := ability_center()
	var col := GameData.color(str(world.ab.get("color", "#ffffff")))
	var t := Time.get_ticks_msec() / 1000.0
	if world.ab_t > 0.0:
		var left := clampf(world.ab_t / float(world.ab.duration_s), 0.0, 1.0)
		draw_circle(c, POWER_R + 7.0, Color(col, 0.3))
		_gloss_disc(self, c, POWER_R, col)
		draw_arc(c, POWER_R - 5.0, -PI / 2.0, -PI / 2.0 + TAU * left, 40, Color.WHITE, 6.0)
	elif world.ability_ready():
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		draw_circle(c, POWER_R + 8.0 + 6.0 * pulse, Color(col, 0.16 + 0.14 * pulse))
		_gloss_disc(self, c, POWER_R, col)
	else:
		var f := clampf(world.ab_kills / world.ability_cost(), 0.0, 1.0)
		_gloss_disc(self, c, POWER_R, Color(0.24, 0.2, 0.38, 0.6))
		draw_arc(c, POWER_R - 5.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(col, 0.95), 6.0)
	IconArt.draw(self, world.ability, c, POWER_R * 1.1, Color.WHITE if world.ab_t > 0.0 or world.ability_ready() else col)
	for k in world.ability_lv:
		draw_circle(c + Vector2((k - (world.ability_lv - 1) / 2.0) * 13.0, POWER_R - 2.0), 4.5, col)


func in_power_button(p: Vector2) -> bool:
	return world != null and world.rift_power != "" and p.distance_to(power_center()) <= POWER_R * 1.25


func _draw_rift_power_button() -> void:
	if world.rift_power == "":
		return
	var c := power_center()
	var col := GameData.color(world.bal.rift.boss.color)
	var f := clampf(world.rp_kills / world.rift_power_cost(), 0.0, 1.0)
	var ready := world.rift_power_ready()
	var t := Time.get_ticks_msec() / 1000.0
	if ready:
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		draw_circle(c, POWER_R + 8.0 + 6.0 * pulse, Color(col, 0.16 + 0.14 * pulse))
		draw_circle(c, POWER_R, Color(col, 0.5 + 0.2 * pulse))
		draw_arc(c, POWER_R, 0, TAU, 40, Color.WHITE, 3.0)
	else:
		draw_circle(c, POWER_R, Color(1, 1, 1, 0.06))
		draw_arc(c, POWER_R, 0, TAU, 40, Color(1, 1, 1, 0.14), 3.0)
		draw_arc(c, POWER_R - 4.0, -PI / 2.0, -PI / 2.0 + TAU * f, 40, Color(col, 0.85), 6.0)
	var key: String = POWER_ICON.get(world.rift_power, "outbreak")
	if icon_atlas != null and icon_atlas.has_icon(key, false):
		icon_atlas.draw_icon(self, key, c, POWER_R * 1.1)
	else:
		IconArt.draw(self, key, c, POWER_R * 1.1, Color.WHITE)
	for k in world.rift_power_lv:
		draw_circle(c + Vector2((k - (world.rift_power_lv - 1) / 2.0) * 13.0, POWER_R - 2.0), 4.5, col)


## In the arena: the time left as a bar + seconds. After an ejection: "RUN!"
## and the frozen seconds left.
func _draw_rift_hud(w: float) -> void:
	var col := GameData.color(world.bal.rift.boss.color) if world.rift_on else Color.WHITE
	if world.rift_state == World.RIFT_ACTIVE:
		var dur := float(world.bal.rift.duration_s)
		var left := maxf(dur - world.rift_t, 0.0)
		var r := Rect2(60, 146, w - 120, 6)
		draw_rect(r, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(r.position, Vector2(r.size.x * left / dur, r.size.y)), col if left > 5.0 else pal.player_hurt)
		var txt := "RIFT  %d" % ceili(left)
		draw_string_outline(font, Vector2(0, 184), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 26, 7, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, 184), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 26, col if left > 5.0 else pal.player_hurt)
	elif world.rift_grace > 0.0 and world.rift_ejected:
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 60.0)
		var y := size.y * 0.32
		draw_string_outline(font, Vector2(0, y), "RUN!", HORIZONTAL_ALIGNMENT_CENTER, w, int(84 * pulse), 12, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(0, y), "RUN!", HORIZONTAL_ALIGNMENT_CENTER, w, int(84 * pulse), pal.player_hurt)
		var sub := "%.1f" % world.rift_grace
		draw_string_outline(font, Vector2(0, y + 56), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 40, 8, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(0, y + 56), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 40, Color.WHITE)


func beat() -> void:
	_beat = 1.0


## A hit from direction `dir` (world space; the camera doesn't rotate). Hits
## from nearly the same side refresh one glow instead of stacking.
func hit_from(dir: Vector2) -> void:
	for h in _hits:
		if (h[0] as Vector2).dot(dir) > 0.85:
			h[0] = dir
			h[1] = 0.0
			return
	_hits.append([dir, 0.0])
	if _hits.size() > 3:
		_hits.pop_front()


func _draw_danger() -> void:
	var col: Color = pal.player_hurt
	if low_hp > 0.0:
		var a := float(juice.get("lowhp_alpha", 0.35)) * (0.45 + 0.55 * low_hp) + 0.22 * _beat
		var ew := float(juice.get("lowhp_width", 150.0)) * (0.7 + 0.3 * low_hp + 0.15 * _beat)
		var c := Color(col, minf(a, 0.8))
		draw_texture_rect(_edge_tex[0], Rect2(0, 0, ew, size.y), false, c)
		draw_texture_rect(_edge_tex[1], Rect2(size.x - ew, 0, ew, size.y), false, c)
		draw_texture_rect(_edge_tex[2], Rect2(0, 0, size.x, ew), false, c)
		draw_texture_rect(_edge_tex[3], Rect2(0, size.y - ew, size.x, ew), false, c)
	var life := float(juice.get("hurt_dir_s", 0.45))
	var ha := float(juice.get("hurt_dir_alpha", 0.22))
	var half := size / 2.0
	for h in _hits:
		var d: Vector2 = h[0]
		var k: float = h[1] / life
		# Where the ray from the centre leaves the screen.
		var tx := INF if absf(d.x) < 0.001 else half.x / absf(d.x)
		var ty := INF if absf(d.y) < 0.001 else half.y / absf(d.y)
		var edge := half + d * minf(tx, ty)
		var gs := Vector2(360, 360)
		draw_texture_rect(_blob_tex, Rect2(edge - gs / 2.0, gs), false, Color(col, ha * (1.0 - k) * (1.0 - k)))


func _draw_hurt_info() -> void:
	var font := get_theme_default_font()
	if _hurt_by_t > 0.0 and _hurt_by != "":
		_hurt_by_t -= get_process_delta_time()
		var a := clampf(_hurt_by_t * 2.0, 0.0, 1.0)
		var y := size.y * 0.5 + 64.0
		draw_string_outline(font, Vector2(0, y), _hurt_by, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 6, Color(0, 0, 0, 0.7 * a))
		draw_string(font, Vector2(0, y), _hurt_by, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(pal.player_hurt.lightened(0.3), a))
	if low_hp > 0.35:
		var a := 0.55 + 0.45 * _beat
		var y := size.y * 0.5 - 70.0
		draw_string_outline(font, Vector2(0, y), "LOW HP", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, 8, Color(0, 0, 0, 0.7 * a))
		draw_string(font, Vector2(0, y), "LOW HP", HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, Color(pal.player_hurt.lightened(0.2), a))


static func _make_edge_texs() -> Array:
	var h := Image.create(64, 1, false, Image.FORMAT_RGBA8)
	var v := Image.create(1, 64, false, Image.FORMAT_RGBA8)
	for i in 64:
		var t := 1.0 - i / 63.0
		h.set_pixel(i, 0, Color(1, 1, 1, t * t * t))
		v.set_pixel(0, i, Color(1, 1, 1, t * t * t))
	var out := [ImageTexture.create_from_image(h)]
	h.flip_x()
	out.append(ImageTexture.create_from_image(h))
	out.append(ImageTexture.create_from_image(v))
	v.flip_y()
	out.append(ImageTexture.create_from_image(v))
	return out


static func _make_blob_tex() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


## The animated part of the XP bar (every frame; the bar itself is cached):
## a bright tip at the fill edge, a glow that pulses faster as the bar nears
## full, and a white flash + sweep when it fills.
func _draw_xp_live(_w: float) -> void:
	var r := XP_RECT
	var f := clampf(world.xp / world.xp_next, 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	var x := r.size.x * f
	if f > 0.0:
		draw_rect(Rect2(r.position.x + maxf(x - 8.0, 0.0), r.position.y, minf(8.0, x), r.size.y), Color(1, 1, 1, 0.45))
	if f >= 0.75:
		var near := (f - 0.75) / 0.25
		var pulse := 0.5 + 0.5 * sin(t * (6.0 + 10.0 * near))
		draw_rect(Rect2(r.position, Vector2(x, r.size.y)), Color(1, 1, 1, 0.18 * near * pulse))
	if _xp_flash > 0.0:
		var k := _xp_flash / 0.4
		draw_rect(r.grow(3.0), Color(1, 1, 1, 0.6 * k))
		var sx := r.position.x + r.size.x * (1.0 - k)
		draw_rect(Rect2(sx - 30.0, r.position.y, 60.0, r.size.y), Color(1, 1, 1, 0.8 * k))


## Top bars and readouts (bars layer): XP, level, timer, kills, mode readout,
## Nucleus bars, boss bar. Redrawn only when one of them changes.
## Top panel (bars layer): level badge, HP and XP bars, timer, kills and run
## gold; the mode readout on the second row (right); Nucleus and boss bars
## below. Redrawn only when one of them changes.
func _draw_bars(ci: CanvasItem) -> void:
	var w := size.x
	var o := UiKit.OUTLINE
	# Panel.
	_rrect(ci, TOP_PANEL, 22.0, Color(0.06, 0.03, 0.13, 0.72))
	# Level badge: a glossy gold disc with the level.
	var bc := Vector2(58, 58)
	_gloss_disc(ci, bc, 34.0, pal.ui_accent)
	var lt := str(world.level)
	var lfs := 36 if world.level < 100 else 28
	_text(ci, bc + Vector2(-34, 13), lt, 68.0, lfs, Color("#3a2200"), 0, HORIZONTAL_ALIGNMENT_CENTER)
	# HP bar (with the number) and XP bar.
	var hp_f := clampf(world.p_hp / maxf(world.p_max_hp, 1.0), 0.0, 1.0)
	_bar(ci, HP_RECT, hp_f, pal.hp_bar if hp_f > 0.3 else Color("#ff2e4d"))
	_text(ci, HP_RECT.position + Vector2(10, 19), "%d / %d" % [ceili(world.p_hp), roundi(world.p_max_hp)], HP_RECT.size.x - 20.0, 18, Color.WHITE, 5, HORIZONTAL_ALIGNMENT_LEFT)
	_bar(ci, XP_RECT, clampf(world.xp / world.xp_next, 0.0, 1.0), pal.xp_bar)
	# Timer (red in the final minute) and the Virulence level under it.
	_text(ci, Vector2(372, 74), UiKit.fmt_time(world.time), 156.0, 46, pal.player_hurt if world.final_minute else Color.WHITE, 9, HORIZONTAL_ALIGNMENT_CENTER)
	var vlev := int(world.bal.get("virulence", 1))
	if vlev > 1:
		_text(ci, Vector2(372, 98), "VIRULENCE %d" % vlev, 156.0, 16, Color("#ff5a7a"), 4, HORIZONTAL_ALIGNMENT_CENTER)
	# Kills and run gold (gold brightens in a frenzy).
	_text(ci, Vector2(530, 50), str(world.kills), 72.0, 24, Color.WHITE, 5, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(ci, Vector2(530, 66), "KILLS", 72.0, 13, Color(1, 1, 1, 0.6), 0, HORIZONTAL_ALIGNMENT_RIGHT)
	var gcol: Color = pal.ui_accent if world.outbreak_t <= 0.0 else Color(1, 0.95, 0.6)
	var gtxt := str(world.run_gold_now())
	var gw := font.get_string_size(gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	IconArt.draw(ci, "gold", Vector2(602.0 - gw - 14.0, 87.0), 20.0, pal.ui_accent)
	_text(ci, Vector2(530, 95), gtxt, 72.0, 22, gcol, 5, HORIZONTAL_ALIGNMENT_RIGHT)
	# Second row, right: the mode's readout.
	var readout := ""
	if world.conv_on:
		readout = "SWARM %d/%d" % [world.ally_count, world._ally_cap()]
		if world.swarm_power > 0.0:
			readout += "  +%d%%" % roundi(world.swarm_power * 100.0)
	elif world.terr != null:
		readout = "INFECTED %d%%" % roundi(world.terr.infected_fraction() * 100.0)
	if readout != "":
		_text(ci, Vector2(w - 330.0, 154), readout, 314.0, 24, pal.player_nucleus, 6, HORIZONTAL_ALIGNMENT_RIGHT)
	var by := 214.0
	if world.def_on:
		_draw_defense_bars(ci, w)
		by = 248.0
	if world.boss_index >= 0 and world.boss_index < world.e_hp.size():
		var f := world.e_hp[world.boss_index] / world.e_maxhp[world.boss_index]
		var r := Rect2(60, by, w - 120, 20)
		var bname := str(world.bal.rift.boss.name) if world.rift_state == World.RIFT_ACTIVE else str(world.enemy_defs[world.e_type[world.boss_index]].name)
		_text(ci, Vector2(0, by - 8.0), bname.to_upper(), w, 22, Color.WHITE, 6, HORIZONTAL_ALIGNMENT_CENTER)
		_bar(ci, r, f, pal.hp_bar)


# ---- HUD drawing helpers (glossy chunky look, no textures)

const TOP_PANEL := Rect2(10, 8, 604, 102)
const HP_RECT := Rect2(102, 24, 262, 26)
const XP_RECT := Rect2(102, 60, 262, 16)


## A rounded rectangle (a few rects + 4 circles: cheap, batched).
func _rrect(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) / 2.0)
	ci.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - rad * 2.0, r.size.y), col)
	ci.draw_rect(Rect2(r.position.x, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	ci.draw_rect(Rect2(r.end.x - rad, r.position.y + rad, rad, r.size.y - rad * 2.0), col)
	for p in [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.position.x + rad, r.end.y - rad), r.end - Vector2(rad, rad)]:
		ci.draw_circle(p, rad, col)


## A chunky bar: dark outline, dark track, coloured fill with a light band.
func _bar(ci: CanvasItem, r: Rect2, f: float, col: Color) -> void:
	var rad := r.size.y / 2.0
	_rrect(ci, r.grow(3.0), rad + 3.0, UiKit.OUTLINE)
	_rrect(ci, r, rad, Color(0.16, 0.11, 0.27))
	if f > 0.0:
		var fw := maxf(r.size.x * f, r.size.y)
		_rrect(ci, Rect2(r.position, Vector2(fw, r.size.y)), rad, col)
		_rrect(ci, Rect2(r.position + Vector2(rad * 0.5, 3.0), Vector2(maxf(fw - rad, 2.0), r.size.y * 0.3)), r.size.y * 0.15, Color(1, 1, 1, 0.3))


## Text with an optional dark outline (outline 0 = none).
func _text(ci: CanvasItem, pos: Vector2, txt: String, width: float, fs: int, col: Color, outline: int, align: HorizontalAlignment) -> void:
	if outline > 0:
		ci.draw_string_outline(font, pos, txt, align, width, fs, outline, UiKit.OUTLINE)
	ci.draw_string(font, pos, txt, align, width, fs, col)


## A glossy disc button face: dark outline, a darker lower edge (3D), the
## face, and a soft highlight on top.
func _gloss_disc(ci: CanvasItem, c: Vector2, r: float, face: Color) -> void:
	ci.draw_circle(c + Vector2(0, 3), r + 4.0, Color(0, 0, 0, 0.35 * face.a))
	ci.draw_circle(c, r + 3.0, Color(UiKit.OUTLINE, face.a))
	ci.draw_circle(c, r, Color(face.darkened(0.35), face.a))
	ci.draw_circle(c - Vector2(0, r * 0.1), r * 0.9, face)
	ci.draw_set_transform(c - Vector2(0, r * 0.42), 0.0, Vector2(1.0, 0.5))
	ci.draw_circle(Vector2.ZERO, r * 0.62, Color(1, 1, 1, 0.3 * face.a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Owned-upgrade strip and the DASH / UPGRADE labels (strip layer).
func _draw_strip(ci: CanvasItem) -> void:
	_draw_owned(ci)
	var dc := dash_center()
	_text(ci, dc + Vector2(-dash_radius, 10), "DASH", dash_radius * 2.0, 28, Color(1, 1, 1, 1.0 if world.can_dash() else 0.45), 7 if world.can_dash() else 0, HORIZONTAL_ALIGNMENT_CENTER)
	var uc := upgrade_center()
	var n := world.pending_levelups
	var on := n > 0
	var accent: Color = pal.ui_accent
	_text(ci, uc + Vector2(-UPGRADE_R, 8.0), "UPGRADE", UPGRADE_R * 2.0, 18, Color("#3a2200") if on else Color(1, 1, 1, 0.45), 0, HORIZONTAL_ALIGNMENT_CENTER)
	if on:
		var b := uc + Vector2(UPGRADE_R * 0.72, -UPGRADE_R * 0.72)
		ci.draw_circle(b, 21.0, UiKit.OUTLINE)
		ci.draw_circle(b, 18.0, pal.player_hurt)
		_text(ci, b + Vector2(-20, 8), str(n), 40.0, 22, Color.WHITE, 0, HORIZONTAL_ALIGNMENT_CENTER)


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
	_sig_bars[13] = world.run_gold_now()
	_sig_bars[14] = 1 if world.outbreak_t > 0.0 else 0
	_sig_bars[15] = ceili(world.p_hp)
	_sig_bars[16] = roundi(world.p_max_hp)
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
	if world.rift_state == World.RIFT_OPEN:
		targets.append([world.rift_pos, GameData.color(world.bal.rift.boss.color), false])
	for tg in targets:
		var sp: Vector2 = (tg[0] - cam_pos) * cam_zoom + half
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
	_gloss_disc(self, c, dash_radius, Color(IconArt.COLORS.dash, 0.82) if ready else Color(0.24, 0.2, 0.38, 0.6))
	if world.p_dash_charges < max_c:
		var f := 1.0 - world.p_dash_cd / world.dash_cooldown()
		draw_arc(c, dash_radius - 6.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(f, 0.0, 1.0), 48, Color(pal.xp_bar, 0.8), 6.0)
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
	if on:
		draw_circle(c, UPGRADE_R + 8.0 + 6.0 * pulse, Color(accent, 0.14 + 0.14 * pulse))
	_gloss_disc(self, c, UPGRADE_R, Color(accent, 0.95) if on else Color(0.24, 0.2, 0.38, 0.5))
	if _notice_t > 0.0:
		var a := clampf(_notice_t / 0.5, 0.0, 1.0)
		draw_string(font, Vector2(c.x - UPGRADE_R - 372.0, c.y + 8.0), _notice_text, HORIZONTAL_ALIGNMENT_RIGHT, 360.0, 24, Color(accent, a))


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
		draw_circle(c, r + 8.0 + 4.0 * sin(t * 12.0), Color(col, 0.3))
		_gloss_disc(self, c, r, col)
		draw_arc(c, r - 5.0, -PI / 2.0, -PI / 2.0 + TAU * left, 40, Color.WHITE, 6.0)
	elif world.outbreak_ready():
		var pulse := 0.5 + 0.5 * sin(t * 7.0)
		draw_circle(c, r + 8.0 + 6.0 * pulse, Color(col, 0.18 + 0.15 * pulse))
		_gloss_disc(self, c, r, col)
	else:
		_gloss_disc(self, c, r, Color(0.24, 0.2, 0.38, 0.6))
		if world.outbreak > 0.0:
			draw_arc(c, r - 5.0, -PI / 2.0, -PI / 2.0 + TAU * world.outbreak, 40, Color(col, 0.95), 6.0)
	var ready := world.outbreak_ready() or world.outbreak_t > 0.0
	if icon_atlas != null and icon_atlas.has_icon("outbreak", false):
		icon_atlas.draw_icon(self, "outbreak", c, r * 1.1)
	else:
		IconArt.draw(self, "outbreak", c, r * 1.1, Color.WHITE if ready else Color(1, 1, 1, 0.4))


## Left-edge column of owned upgrades: icon plus level number (weapons
## first, evolved ones starred).
func _draw_owned(ci: CanvasItem) -> void:
	# Weapon strip (second row, left): each weapon as an icon chip with its
	# level as pips (a gold star when evolved), then a "+N" chip for passives.
	# Tapping it opens the paused build overlay (Main / BuildScreen).
	var r := build_rect()
	_rrect(ci, r, 18.0, Color(0.06, 0.03, 0.13, 0.62))
	var px := 40.0
	var x := r.position.x + 8.0 + px / 2.0
	var cy := r.position.y + 24.0
	var passives := 0
	for u in world.upgrade_list:
		if not world.owned.has(u.id):
			continue
		if u.type != "weapon":
			passives += 1
			continue
		var evo: bool = world.evolved.has(u.id)
		var c := Vector2(x, cy)
		if icon_atlas != null and icon_atlas.has_icon(u.id, evo):
			icon_atlas.draw_icon(ci, u.id, c, px, evo)
		else:
			IconArt.draw(ci, u.id, c, px, IconArt.color_for(u), evo)
		var lv := int(world.owned[u.id])
		var tot := Upgrades.max_level(u)
		for k in tot:
			var pp := c + Vector2((k - (tot - 1) / 2.0) * 7.0, px / 2.0 + 6.0)
			ci.draw_circle(pp, 2.6, IconArt.color_for(u) if k < lv else Color(1, 1, 1, 0.22))
		x += px + 10.0
	if passives > 0:
		var c := Vector2(x, cy)
		ci.draw_circle(c, px / 2.0, Color(0.18, 0.12, 0.3, 0.95))
		ci.draw_arc(c, px / 2.0 - 1.0, 0, TAU, 24, Color(pal.ui_accent, 0.8), 2.0)
		_text(ci, c + Vector2(-px / 2.0, 7.0), "+%d" % passives, px, 18, Color.WHITE, 4, HORIZONTAL_ALIGNMENT_CENTER)


const BUILD_RECT := Rect2(12, 116, 284, 60)  # second row, left (tap: build overlay)


## The weapon strip's rect, as wide as its chips (weapons + the passives chip).
func build_rect() -> Rect2:
	if world == null:
		return BUILD_RECT
	var n := 0
	var passives := false
	for id in world.owned:
		if world.upgrade_defs[id].type == "weapon":
			n += 1
		else:
			passives = true
	n += 1 if passives else 0
	return Rect2(BUILD_RECT.position, Vector2(maxf(16.0 + n * 50.0 - 10.0, 60.0), BUILD_RECT.size.y))


func in_build_button(p: Vector2) -> bool:
	return world != null and build_rect().grow(10).has_point(p)


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
	_text(ci, Vector2(w - 330.0, 142), txt, 314.0, 24, pal.core, 6, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(ci, Vector2(w - 330.0, 168), "BIOMASS %d" % floori(wd.biomass), 314.0, 20, pal.pad, 5, HORIZONTAL_ALIGNMENT_RIGHT)
	var f := wd.core_hp / maxf(wd.core_max, 1.0)
	var r := Rect2(60, 204, w - 120, 18)
	var low := f < 0.3 and fmod(Time.get_ticks_msec() / 1000.0, 0.5) < 0.25
	_text(ci, Vector2(0, 197), "NUCLEUS", w, 18, Color.WHITE, 5, HORIZONTAL_ALIGNMENT_CENTER)
	_bar(ci, r, f, pal.player_hurt if low else pal.core)


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

const BAR_W := 122.0
const BAR_H := 118.0
const BAR_GAP := 8.0


## Shown while standing on an empty pad: tap a tower to build it (no pause).
func tower_bar_visible() -> bool:
	return world != null and world.def_on and world.state == "playing" and world.empty_pad_under_player() >= 0


func _tower_rect(i: int) -> Rect2:
	# Left side: the right column holds UPGRADE / Outbreak / DASH.
	return Rect2(20.0 + i * (BAR_W + BAR_GAP), size.y - 540.0, BAR_W, BAR_H)


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
	var bar_w := _tower_rect(world.tower_defs.size() - 1).end.x - first.position.x
	draw_string_outline(font, Vector2(first.position.x, first.position.y - 14), "TAP A TOWER TO BUILD", HORIZONTAL_ALIGNMENT_CENTER, bar_w, 24, 6, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(first.position.x, first.position.y - 14), "TAP A TOWER TO BUILD", HORIZONTAL_ALIGNMENT_CENTER, bar_w, 24, pal.pad)
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
		draw_string(font, r.position + Vector2(0, 86), str(d.name), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(1, 1, 1, a))
		draw_string(font, r.position + Vector2(0, 109), str(cost), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 22, Color(pal.pad, a) if ok else Color("#ff9a9a"))


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
## Kill streak (World.streak): a big "x123" under the pause button that
## punches on every kill, grows and changes colour with the tier
## (balance.streak.tiers), shakes harder the higher it goes, shows the tier
## name and a bar draining until the streak breaks, bursts with a ring on
## milestones, and floats away when the streak ends.
var _shown_streak := 0
var _streak_pop := 0.0
var _streak_burst := 0.0  # milestone ring, 1 -> 0
var _streak_end_n := 0  # last streak, fading out after it broke
var _streak_end_t := 9.0


func streak_burst() -> void:
	_streak_burst = 1.0


func _update_streak(delta: float) -> void:
	_streak_pop = maxf(0.0, _streak_pop - delta * 7.0)
	_streak_burst = maxf(0.0, _streak_burst - delta * 2.2)
	_streak_end_t += delta
	if world == null:
		return
	var n := world.streak
	if n > _shown_streak:
		_streak_pop = 1.0
	elif n < _shown_streak and _shown_streak >= streak_show:
		_streak_end_n = _shown_streak
		_streak_end_t = 0.0
	_shown_streak = n


func _streak_style(n: int) -> Array:
	var tiers: Array = world.bal.streak.tiers
	var t := world.streak_tier(n)
	if t < 0:
		return [Color.WHITE, "", 0]
	var col := GameData.color(tiers[t].color)
	if t == tiers.size() - 1:  # top tier shimmers through the colours
		col = Color.from_hsv(fmod(Time.get_ticks_msec() / 1400.0, 1.0), 0.55, 1.0)
	return [col, str(tiers[t].name), t]


func _draw_streak(w: float) -> void:
	var right := w - 24.0
	var base_y := 380.0  # right edge, below the toasts and the boss bar
	# The last streak floats up and fades after it breaks.
	if _streak_end_t < 0.6 and world.streak < streak_show:
		var k := _streak_end_t / 0.6
		var st0 := _streak_style(_streak_end_n)
		_rtext("x%d" % _streak_end_n, Vector2(right, base_y - 50.0 * k), _streak_font(_streak_end_n), 10, Color(st0[0], 1.0 - k))
	var n := world.streak
	if n < streak_show:
		return
	var st := _streak_style(n)
	var col: Color = st[0]
	var tier: int = st[2]
	var fs := int(_streak_font(n) * (1.0 + 0.32 * _streak_pop * _streak_pop))
	var jit := Vector2.ZERO
	if _streak_pop > 0.0:
		jit = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (1.0 + tier * 1.3) * _streak_pop
	var pos := Vector2(right, base_y) + jit
	var txt := "x%d" % n
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if _streak_burst > 0.0:
		var c := pos + Vector2(-tw / 2.0, -fs * 0.35)
		var rk := 1.0 - _streak_burst
		draw_arc(c, tw * 0.6 + 120.0 * rk, 0, TAU, 40, Color(col, 0.9 * _streak_burst), 6.0 * _streak_burst + 1.0)
		draw_circle(c, tw * 0.5 + 30.0 * rk, Color(col, 0.18 * _streak_burst))
	_rtext(txt, pos, fs, 10, col)
	var name: String = st[1]
	if name != "":
		# The tier name swells on a milestone (that's the milestone call-out).
		_rtext(name, pos + Vector2(0, 30.0 + 18.0 * _streak_burst), int(20.0 + 22.0 * _streak_burst), 6, col)
	# Time left before the streak breaks.
	var left := clampf(1.0 - world.streak_t / float(world.bal.streak.window_s), 0.0, 1.0)
	var bw := 150.0
	var br := Rect2(right - bw, base_y + 44.0 + 18.0 * _streak_burst, bw, 6)
	draw_rect(br, Color(0, 0, 0, 0.45))
	draw_rect(Rect2(br.position + Vector2(bw * (1.0 - left), 0), Vector2(bw * left, 6)), Color(col, 0.9))


## Right-aligned outlined text ending at pos.x (draw_string's RIGHT alignment
## needs a width, so measure instead).
func _rtext(txt: String, pos: Vector2, fs: int, outline: int, col: Color) -> void:
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(pos.x - tw, pos.y)
	draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.7 * col.a))
	draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Bigger as the streak grows (roughly logarithmic), capped.
func _streak_font(n: int) -> int:
	return int(clampf(40.0 + 16.0 * log(maxf(float(n), 1.0) / 10.0) / log(2.0), 40.0, 104.0))


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
	var width := minf(w - 220.0, 540.0)  # the right column holds the buttons
	var fs := 26
	var sz := font.get_multiline_string_size(_hint_text, HORIZONTAL_ALIGNMENT_CENTER, width - 40.0, fs)
	# Above the DASH/UPGRADE buttons; higher when the Nucleus tower bar is up.
	var bottom := size.y - (660.0 if tower_bar_visible() else (520.0 if orders_on() else 360.0))  # above the Swarm order fan
	var rect := Rect2(24.0, bottom - sz.y - 28.0 + 12.0 * (1.0 - a), width, sz.y + 28.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.05, 0.14, 0.88 * a)
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_color = Color(pal.ui_accent, 0.7 * a)
	draw_style_box(sb, rect)
	draw_multiline_string(font, rect.position + Vector2(20, 14 + fs * 0.85), _hint_text, HORIZONTAL_ALIGNMENT_CENTER, width - 40.0, fs, -1, Color(1, 1, 1, a))


# ------------------------------------------------- new-player start (coach)

const TITLE_S := 3.6
var title_text := ""
var title_sub := ""


## The tutorial prompt: a big line of text that pops in, plus a pointer at
## what to touch (a pulsing ring and a bouncing arrow on a button, a ghost
## finger for moving, a circling dot for Infection's loop, a ring on a pad).
func _draw_coach(w: float) -> void:
	if coach.is_empty() or not evo_seq.is_empty():
		return
	var txt := str(coach.get("text", ""))
	var k := _coach_t
	if txt != "":
		# Shrinks to fit one line (down to 30 px), else wraps onto two;
		# below the streak counter, above the cell.
		var pop := 1.0 + 0.35 * exp(-k * 9.0) * cos(k * 22.0)
		var room := w - 60.0
		var base := 46
		while base > 30 and font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, base).x > room:
			base -= 2
		var fs := int(base * pop)
		var a := clampf(k / 0.12, 0.0, 1.0)
		var y := 500.0
		if font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, base).x > room:
			draw_multiline_string_outline(font, Vector2(30, y - fs * 0.6), txt, HORIZONTAL_ALIGNMENT_CENTER, room, fs, -1, 12, Color(UiKit.OUTLINE, 0.9 * a))
			draw_multiline_string(font, Vector2(30, y - fs * 0.6), txt, HORIZONTAL_ALIGNMENT_CENTER, room, fs, -1, Color(1, 1, 1, a))
		else:
			draw_string_outline(font, Vector2(30, y), txt, HORIZONTAL_ALIGNMENT_CENTER, room, fs, 12, Color(UiKit.OUTLINE, 0.9 * a))
			draw_string(font, Vector2(30, y), txt, HORIZONTAL_ALIGNMENT_CENTER, room, fs, Color(1, 1, 1, a))
	var col: Color = pal.ui_accent
	match str(coach.get("target", "none")):
		"upgrade":
			_point_at(upgrade_center(), 66.0, col)
		"dash":
			_point_at(dash_center(), dash_radius, col)
		"outbreak":
			_point_at(outbreak_center(), 58.0, col)
		"orders":
			_point_at(order_center(), 54.0, col)
		"move":
			# Ghost finger dragging left and right, low on the screen.
			var base := Vector2(w * 0.5, size.y * 0.72)
			var off := Vector2(sin(k * 2.6) * 120.0, 0.0)
			draw_arc(base, 90.0, 0, TAU, 40, Color(1, 1, 1, 0.18), 3.0)
			draw_circle(base + off, 34.0, Color(1, 1, 1, 0.35))
			draw_circle(base + off, 22.0, Color(1, 1, 1, 0.6))
		"loop":
			# A dot circling out of the cell and back: draw a loop.
			var c := size / 2.0
			var r := 150.0
			draw_arc(c, r, 0, TAU, 48, Color(col, 0.3), 4.0)
			var a2 := fmod(k * 1.8, TAU)
			draw_circle(c + Vector2.from_angle(a2) * r, 16.0, Color(col, 0.9))
		"pad":
			var best := -1
			var bd := INF
			for i in world.pad_pos.size():
				if world.pad_tower[i] < 0 and world.pad_pos[i].distance_to(world.p_pos) < bd:
					bd = world.pad_pos[i].distance_to(world.p_pos)
					best = i
			if best >= 0:
				var sp: Vector2 = (world.pad_pos[best] - cam_pos) * cam_zoom + size / 2.0
				var inner := Rect2(Vector2(60, 220), size - Vector2(120, 420))
				if inner.has_point(sp):
					_point_at(sp, 70.0 * cam_zoom, Color("#7cff9b"))
				else:
					var dir := (sp - size / 2.0).normalized()
					var edge := size / 2.0 + dir * minf(size.x, size.y) * 0.36
					_arrow(edge, dir, Color("#7cff9b"))


func _point_at(c: Vector2, r: float, col: Color) -> void:
	var k := _coach_t
	var pulse := 0.5 + 0.5 * sin(k * 7.0)
	draw_arc(c, r + 10.0 + 8.0 * pulse, 0, TAU, 40, Color(col, 0.9), 6.0)
	draw_arc(c, r + 26.0 + 14.0 * fmod(k * 1.4, 1.0), 0, TAU, 40, Color(col, 0.5 * (1.0 - fmod(k * 1.4, 1.0))), 3.0)
	var tip := c + Vector2(0, -(r + 30.0 + 12.0 * absf(sin(k * 5.0))))
	_arrow(tip, Vector2.DOWN, col)


func _arrow(tip: Vector2, dir: Vector2, col: Color) -> void:
	var side := dir.orthogonal() * 20.0
	var back := tip - dir * 34.0
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), col)
	draw_line(back, back - dir * 26.0, col, 10.0)


## First-launch title over the dish: the game name and the tagline, fading.
func _draw_title(w: float) -> void:
	if title_t < 0.0 or title_text == "":
		return
	var a := clampf(minf(title_t / 0.5, (TITLE_S - title_t) / 0.8), 0.0, 1.0)
	var rise := 20.0 * (1.0 - clampf(title_t / 0.6, 0.0, 1.0))
	draw_string_outline(font, Vector2(0, 250 + rise), title_text, HORIZONTAL_ALIGNMENT_CENTER, w, 84, 16, Color(UiKit.OUTLINE, a))
	draw_string(font, Vector2(0, 250 + rise), title_text, HORIZONTAL_ALIGNMENT_CENTER, w, 84, Color(pal.ui_accent, a))
	draw_string_outline(font, Vector2(0, 300 + rise), title_sub, HORIZONTAL_ALIGNMENT_CENTER, w, 30, 8, Color(UiKit.OUTLINE, a))
	draw_string(font, Vector2(0, 300 + rise), title_sub, HORIZONTAL_ALIGNMENT_CENTER, w, 30, Color(1, 1, 1, a))
