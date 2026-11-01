class_name HudOverlay
extends Control
## In-run HUD drawn directly: XP bar, level, timer, kills, boss bar and the
## floating virtual joystick. Ignores input; Main handles touches.

var world: World
var pal: Dictionary
var font: Font
var stick_active := false
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var stick_radius := 90.0
var show_perf := false
var sim_ms := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
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
	draw_string(font, Vector2(16, 58), "LV %d" % world.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, pal.text)
	draw_string(font, Vector2(0, 62), UiKit.fmt_time(world.time), HORIZONTAL_ALIGNMENT_CENTER, w, 40, pal.text)
	draw_string(font, Vector2(16, 96), "%d kills" % world.kills, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(pal.text, 0.7))
	# Boss bar.
	if world.boss_index >= 0 and world.boss_index < world.e_hp.size():
		var f := world.e_hp[world.boss_index] / world.e_maxhp[world.boss_index]
		var r := Rect2(60, 120, w - 120, 18)
		draw_rect(r, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), pal.hp_bar)
		draw_string(font, Vector2(0, 112), str(world.enemy_defs[world.e_type[world.boss_index]].name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, 22, pal.text)
	# Perf readout for playtests (balance.json debug.show_perf).
	if show_perf:
		var txt := "%d fps  %d enemies  sim %.1f ms" % [Engine.get_frames_per_second(), world.enemy_count(), sim_ms]
		draw_string(font, Vector2(0, size.y - 14), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 20, Color(1, 1, 0.6, 0.85))
	# Floating joystick.
	if stick_active:
		draw_circle(stick_origin, stick_radius, Color(1, 1, 1, 0.08))
		draw_arc(stick_origin, stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.25), 3.0)
		draw_circle(stick_pos, 34, Color(1, 1, 1, 0.35))
