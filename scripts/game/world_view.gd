class_name WorldView
extends Node2D
## Draws the World. Performance matters most here on phones, so anything that
## exists in large numbers (enemies, gems, bullets, shots, particles) is drawn
## through SpriteBatch (same-texture rects the renderer merges, using generated
## white textures tinted per sprite). The background is one tiled texture. Only a handful of
## things (player, orbit, nova rings, chain sparks, damage numbers, boss bar)
## use immediate _draw calls on the top layer.
## Also owns short-lived effects and camera shake, driven by World events and
## data/balance.json "juice".

const BG_TILE := preload("res://assets/processed/bg_tile.png")
const ENEMY_DIRS := 16  # eye directions baked into the enemy atlas

var world: World
var bal: Dictionary
var juice: Dictionary
var pal := {}
var enemy_colors: Array = []
var cam: Camera2D
var cam_zoom := 1.0  # current zoom (HUD arrows need it)
var _look := Vector2.ZERO  # camera look-ahead offset (juice.cam_lead_s)
var _zoom_crowd := 1.0  # eases out as the crowd grows (juice.cam_crowd_zoom)
var _zoom_punch := 0.0  # short zoom-in on big moments
var font: Font
var fx: Array = []
var shake := 0.0
var _damage_numbers := 0

var _gems: SpriteBatch
var _shots: SpriteBatch
var _enemies: SpriteBatch
var _allies: SpriteBatch
var _bullets: SpriteBatch
var _dots: SpriteBatch
var _top: Node2D
var evo_colors := {}  # weapon id -> Color of its evolution
var elite_color := Color("#ffd166")
var _hurt_t := 0.0  # blink only after real hits, not during dash iframes
var _terr_img: Image
var _terr_tex: ImageTexture
var _land_color := Color(0.36, 0.88, 0.9, 0.3)
var _blob_scale := 1.0
var _core_flash := 0.0
var digits: DigitAtlas  # set by Main; baked digits for damage numbers
var _splats: SpriteBatch  # goo left on the floor by kills (under everything)
var _plague: SpriteBatch  # Outbreak's toxic trail
var _rings: SpriteBatch  # kill rings (batched ring texture)
var _sp_pos := PackedVector2Array()
var _sp_size := PackedFloat32Array()
var _sp_col := PackedColorArray()
var _sp_t := PackedFloat32Array()
var _sp_next := 0
var _num_by_uid := {}  # enemy uid -> its live damage number (merging)
var _sparks_left := 0  # hit sparks still allowed this frame
var _kills_this_frame := 0  # multi-kill punch (juice.multikill_*)
var _kill_sum := Vector2.ZERO
var _shake_t := 0.0
var shake_setting := 1.0  # Settings → Screen shake (0, 0.5, 1, 1.5)
var _cell_tex: Texture2D
var _disc_tex: Texture2D
var _face := 0.0  # smoothed facing angle (visual only; World's aim snaps)
var _squash := 0.0  # current stretch along the movement direction
var _move_ang := 0.0
var _hurt_squish := 0.0
var _cell_t := 0.0
# Telegraph data per enemy type (from enemies.json): Lancer dash lane length
# and wind-up, Spitter fire range.
var _dash_len := PackedFloat32Array()
var _windup := PackedFloat32Array()
var _fire_range := PackedFloat32Array()
## CPU ms spent in this view since Main last read it (fill + draw recording);
## Main resets it each frame (benchmark and perf readout).
var cpu_ms := 0.0


func setup(game_data: Dictionary) -> void:
	bal = game_data.balance
	juice = bal.juice
	for k in bal.palette:
		pal[k] = GameData.color(bal.palette[k])
	enemy_colors.clear()
	_dash_len.clear()
	_windup.clear()
	_fire_range.clear()
	for e in game_data.enemies:
		enemy_colors.append(GameData.color(e.color))
		_dash_len.append(float(e.get("dash_speed", 0.0)) * float(e.get("dash_s", 0.0)))
		_windup.append(float(e.get("windup_s", 1.0)))
		_fire_range.append(float(e.get("keep_distance", 0.0)) + 220.0)
	font = ThemeDB.fallback_font
	for ev in game_data.get("evolutions", []):
		evo_colors[ev.weapon] = GameData.color(ev.color)
	elite_color = GameData.color(game_data.waves.elites.color)
	if cam != null:
		return
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var perf: Dictionary = bal.perf
	var disc := ShapeTextures.disc()
	_splats = _batch(ShapeTextures.splat(), int(juice.get("splat_max", 50)))
	_plague = _batch(ShapeTextures.splat(), 200)
	_gems = _batch(ShapeTextures.diamond(), int(bal.xp.max_gems))
	_shots = _batch(disc, int(perf.max_enemy_shots) * 2)
	_enemies = _batch(ShapeTextures.blob(64, ENEMY_DIRS), int(game_data.waves.max_alive) + 120, ENEMY_DIRS)
	_allies = _batch(ShapeTextures.ally_cell(), 64)
	_bullets = _batch(disc, int(perf.max_projectiles) * 2)
	_dots = _batch(disc, int(perf.max_effects) + 40)
	_rings = _batch(ShapeTextures.ring(), 48)
	_blob_scale = 2.0 / ShapeTextures.BLOB_BODY  # body radius -> quad width
	_cell_tex = ShapeTextures.player_cell()
	_disc_tex = disc
	_top = Node2D.new()
	_top.draw.connect(_draw_top)
	add_child(_top)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()


func _batch(tex: Texture2D, cap: int, dirs: int = 1) -> SpriteBatch:
	var b := SpriteBatch.new()
	b.setup(tex, cap, dirs)
	b.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED  # parent repeats for the bg tile
	add_child(b)
	return b


func set_world(w: World) -> void:
	world = w
	_terr_tex = null
	if w.terr != null:
		# One pixel per tile; linear filtering softens edges into a "culture".
		var n := w.terr.n
		_terr_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
		_land_color = Color(pal.player_nucleus, 0.3)
		for i in n * n:
			_terr_img.set_pixel(i % n, i / n, _land_color if w.terr.tiles[i] == Territory.OWNED else Color(0, 0, 0, 0))
		_terr_tex = ImageTexture.create_from_image(_terr_img)
		w.terr.dirty.clear()
	fx.clear()
	shake = 0.0
	_num_by_uid.clear()
	_damage_numbers = 0
	_sp_pos.clear()
	_sp_size.clear()
	_sp_col.clear()
	_sp_t.clear()
	_sp_next = 0
	_damage_numbers = 0


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## Turns simulation events into effects. Called by Main after every step.
func consume(events: Array) -> void:
	var max_fx := int(bal.perf.max_effects)
	_kills_this_frame = 0
	_kill_sum = Vector2.ZERO
	for ev in events:
		match ev.type:
			"hit":
				_on_hit(ev, max_fx)
			"kill":
				var c := GameData.color(ev.color)
				_kills_this_frame += 1
				_kill_sum += ev.pos
				# White flash where it died, then a fast burst that slows down
				# (drag), a couple of white sparks among the coloured bits.
				_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2.ZERO, "color": Color(1, 1, 1, 0.95), "r": ev.radius * float(juice.get("kill_flash_scale", 1.3)), "life": 0.08}, max_fx + 10)
				var sp := float(juice.get("kill_burst_speed", 1.0))
				for k in int(juice.kill_burst_particles):
					var a := randf() * TAU
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(140, 380) * sp, "drag": float(juice.get("kill_burst_drag", 0.0)),
						"color": Color(1, 0.97, 0.9) if k < 2 else c, "r": randf_range(3.0, 6.0), "life": 0.4}, max_fx)
				_mark_killing_blow(int(ev.get("uid", -1)))
				_add_fx({"kind": "pop", "pos": ev.pos, "color": c, "r": ev.radius, "life": 0.18}, max_fx)
				_add_fx({"kind": "kring", "pos": ev.pos, "color": c, "r": ev.radius, "life": 0.22}, max_fx + 10)
				_add_splat(ev.pos, ev.radius * (3.4 if ev.elite else 2.6), c)
				if ev.get("gilded", false):
					# Gold coin sparkle: the germ paid out.
					for n in 6:
						var a := -PI / 2.0 + randf_range(-1.2, 1.2)
						_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(140, 260), "grav": 520.0, "color": pal.ui_accent, "r": 4.0, "life": 0.45}, max_fx + 20)
			"nova":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius, "life": 0.3, "color": _wcolor("nova", pal.nova)}, max_fx + 4)
				if not ev.get("tower", false):
					add_shake(float(juice.shake_nova))
			"chain":
				_add_fx({"kind": "chain", "points": ev.points, "life": 0.16, "color": _wcolor("chain", pal.chain)}, max_fx + 4)
			"convert":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 60.0, "life": 0.35, "color": pal.player_nucleus}, max_fx + 4)
			"swarm_feed":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 170.0, "life": 0.35, "color": pal.player_nucleus}, max_fx + 4)
			"ally_order":
				var oc := GameData.color(world.bal.conversion.orders[ev.order].color)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 150.0, "life": 0.35, "color": oc}, max_fx + 4)
			"ally_lost":
				_add_fx({"kind": "pop", "pos": ev.pos, "color": pal.player_nucleus, "r": 14.0, "life": 0.25}, max_fx)
			"shot_blocked":
				_add_fx({"kind": "pop", "pos": ev.pos, "color": _wcolor("orbit", pal.orbit), "r": 10.0, "life": 0.2}, max_fx)
			"dash":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 46.0, "life": 0.2, "color": pal.player}, max_fx + 4)
			"elite_killed":
				add_shake(10.0)
				add_zoom_punch(float(juice.get("cam_punch_elite", 0.0)))
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 150.0, "life": 0.4, "color": elite_color}, max_fx + 4)
				# Gold shower: sparks burst up and fall.
				for n in 18:
					var a := -PI / 2.0 + randf_range(-1.1, 1.1)
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(220, 420), "grav": 700.0, "color": elite_color, "r": randf_range(3.0, 6.0), "life": 0.7}, max_fx + 30)
			"pickup_item":
				match ev.kind:
					"vacuum":
						_add_fx({"kind": "ring", "pos": world.p_pos, "r": 900.0, "life": 0.6, "color": pal.gem_small}, max_fx + 4)
					"heal":
						_add_fx({"kind": "ring", "pos": world.p_pos, "r": 90.0, "life": 0.45, "color": pal.gem_medium}, max_fx + 4)
					"bomb":
						add_shake(float(juice.shake_bomb))
						_add_fx({"kind": "ring", "pos": world.p_pos, "r": float(bal.pickups.bomb_radius), "life": 0.5, "color": pal.enemy_shot}, max_fx + 4)
			"claim":
				_add_fx({"kind": "claim", "cells": ev.cells, "life": 0.5}, max_fx + 4)
				add_shake(minf(3.0 + ev.tiles * 0.05, 12.0))
			"level_gained":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 70.0, "life": 0.35, "color": pal.ui_accent}, max_fx + 4)
				add_zoom_punch(float(juice.get("cam_punch_level", 0.0)))
			"levelup_wave":
				# The shove ring: fast, bright, sized to the push radius.
				_add_fx({"kind": "ring", "pos": ev.pos, "r": float(ev.radius), "life": 0.32, "color": Color(pal.xp_bar.lightened(0.4), 0.95)}, max_fx + 4)
				_add_fx({"kind": "pop", "pos": ev.pos, "color": pal.xp_bar, "r": float(ev.radius) * 0.35, "life": 0.25}, max_fx + 4)
			"streak":
				add_zoom_punch(float(juice.get("cam_punch_streak", 0.0)))
			"upgrade":
				# Pick burst in the upgrade's colour, right on the player.
				var uc := IconArt.color_for(world.upgrade_defs[ev.id])
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 130.0, "life": 0.45, "color": uc}, max_fx + 4)
				for n in 10:
					var a := TAU * n / 10.0
					_add_fx({"kind": "dot", "pos": world.p_pos, "vel": Vector2(cos(a), sin(a)) * 240.0, "color": uc, "r": 6.0, "life": 0.45}, max_fx + 14)
			"evolution":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 320.0, "life": 0.7, "color": _wcolor(ev.weapon, pal.ui_accent)}, max_fx + 4)
				add_zoom_punch(float(juice.get("cam_punch_evolution", 0.0)))
			"hurt":
				add_shake(float(juice.shake_hurt))
				_hurt_t = float(bal.player.iframes_s)
				_hurt_squish = 1.0
			"core_hit":
				_core_flash = 0.2
				add_shake(2.5)
			"tower_built", "tower_upgraded":
				var tc := GameData.color(ev.color)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 110.0, "life": 0.45, "color": tc}, max_fx + 4)
				for n in 12:
					var a := TAU * n / 12.0
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * 260.0, "color": tc, "r": 6.0, "life": 0.45}, max_fx + 16)
				add_shake(5.0)
			"volatile":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius, "life": 0.25, "color": IconArt.COLORS.dash}, max_fx + 4)
				for n in 6:
					var a := randf() * TAU
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(200, 360), "color": IconArt.COLORS.dash, "r": 4.0, "life": 0.3}, max_fx + 20)
				add_shake(3.0)
			"outbreak_start":
				add_shake(6.0)
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": maxf(float(ev.get("radius", 0.0)), 200.0), "life": 0.55, "color": pal.ui_accent}, max_fx + 4)
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 160.0, "life": 0.4, "color": pal.outbreak}, max_fx + 4)
			"respawn":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 120.0, "life": 0.5, "color": pal.player}, max_fx + 4)
			"player_down":
				_add_fx({"kind": "pop", "pos": world.p_pos, "color": pal.player_hurt, "r": 40.0, "life": 0.4}, max_fx + 4)
				add_shake(8.0)
			"wave_start":
				for v in world.vents_active:
					_add_fx({"kind": "ring", "pos": world.vent_pos[v], "r": 150.0, "life": 0.5, "color": pal.vent}, max_fx + 4)
			"boss_killed":
				add_shake(float(juice.shake_boss_kill))
				add_zoom_punch(float(juice.get("cam_punch_boss", 0.0)))
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 260.0, "life": 0.6}, max_fx + 4)
	# Many kills in one frame (a nova or bomb clearing a crowd): a small shake
	# and a ring sized by how many died.
	var mk := int(juice.get("multikill_min", 0))
	if mk > 0 and _kills_this_frame >= mk:
		add_shake(minf(float(_kills_this_frame) * float(juice.get("multikill_shake", 0.0)), float(juice.get("multikill_shake_max", 0.0))))
		_add_fx({"kind": "ring", "pos": _kill_sum / _kills_this_frame, "r": minf(60.0 + 12.0 * _kills_this_frame, 320.0), "life": 0.3, "color": Color(1, 1, 1, 0.8)}, max_fx + 4)


## Short zoom-in for a big moment (decays at juice.cam_punch_decay per s).
func add_zoom_punch(amount: float) -> void:
	_zoom_punch = maxf(_zoom_punch, amount * float(juice.get("cam_punch_mult", 1.0)))


## Weapon colour, switched to its evolution colour once evolved.
func _wcolor(weapon: String, base: Color) -> Color:
	if world != null and world.evolved.has(weapon) and evo_colors.has(weapon):
		return evo_colors[weapon]
	return base


func _add_fx(f: Dictionary, cap: int) -> void:
	if fx.size() >= cap:
		return
	f["t"] = 0.0
	fx.append(f)


func _process(delta: float) -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	_process_view(delta)
	cpu_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _process_view(delta: float) -> void:
	var i := 0
	while i < fx.size():
		var f: Dictionary = fx[i]
		f.t += delta
		if f.t >= f.life:
			if f.kind == "num":
				_damage_numbers -= 1
				if _num_by_uid.get(f.uid) == f:
					_num_by_uid.erase(f.uid)
			fx.remove_at(i)
			continue
		if f.has("vel"):
			if f.has("grav"):
				f.vel.y += f.grav * delta
			if f.has("drag"):
				f.vel *= exp(-float(f.drag) * delta)
			f.pos += f.vel * delta
		i += 1
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_update_cell_pose(delta)
	_core_flash = maxf(0.0, _core_flash - delta)
	if world.p_dash_t > 0.0:
		_add_fx({"kind": "dot", "pos": world.p_pos, "vel": Vector2.ZERO, "color": Color(pal.player, 0.6), "r": world.p_radius, "life": 0.22}, int(bal.perf.max_effects) + 8)
	_sparks_left = int(juice.get("hit_sparks_per_frame", 6))
	_age_splats(delta)
	# Smooth shake: layered sines instead of a new random offset every frame
	# (which buzzes at 90/120 fps), scaled by the shake setting.
	shake = maxf(0.0, shake - float(juice.shake_decay) * delta)
	_shake_t += delta
	var off := Vector2(sin(_shake_t * 47.0) * 0.6 + sin(_shake_t * 21.0 + 1.7) * 0.4,
		cos(_shake_t * 43.0) * 0.6 + sin(_shake_t * 19.0 + 0.4) * 0.4) * shake * float(juice.get("shake_mult", 1.0)) * shake_setting
	# Camera: leads a little where you're heading, eases out as the crowd
	# grows, and punches in on big moments (add_zoom_punch). Knobs in juice.
	var lead := world.p_vel * float(juice.get("cam_lead_s", 0.0))
	_look = _look.lerp(lead, 1.0 - exp(-float(juice.get("cam_lead_rate", 4.0)) * delta))
	var crowd_k := clampf((float(world.hostile_count()) - float(juice.get("cam_crowd_from", 60))) / maxf(float(juice.get("cam_crowd_span", 100)), 1.0), 0.0, 1.0)
	_zoom_crowd = lerpf(_zoom_crowd, 1.0 - float(juice.get("cam_crowd_zoom", 0.0)) * crowd_k, 1.0 - exp(-0.8 * delta))
	_zoom_punch = maxf(0.0, _zoom_punch - delta * float(juice.get("cam_punch_decay", 0.25)))
	cam_zoom = _zoom_crowd * (1.0 + _zoom_punch)
	cam.zoom = Vector2.ONE * cam_zoom
	var focus := world.core_pos if world.p_down > 0.0 else world.p_pos + _look
	cam.position = focus + off
	var vp := get_viewport_rect().size / cam_zoom
	var view := Rect2(cam.position - vp / 2.0, vp).grow(80)
	_fill_gems(view)
	_fill_shots()
	_fill_enemies(view)
	_fill_bullets()
	_fill_dots()
	_fill_splats()
	_fill_plague()
	queue_redraw()
	_top.queue_redraw()


# ------------------------------------------------------------ batched layers

func _draw() -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	_draw_world()
	cpu_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _draw_world() -> void:
	# One tiled texture, anchored to the world grid so it scrolls correctly.
	var vp := get_viewport_rect().size / cam_zoom
	var tile := float(BG_TILE.get_width())
	var tl := cam.position - vp / 2.0 - Vector2(64, 64)
	var origin := Vector2(floorf(tl.x / tile), floorf(tl.y / tile)) * tile
	var size := Vector2(ceilf((vp.x + 128.0) / tile) + 1.0, ceilf((vp.y + 128.0) / tile) + 1.0) * tile
	draw_texture_rect(BG_TILE, Rect2(origin, size), true)
	if world.terr != null:
		_draw_territory()
	elif world.dish_r > 0.0:
		_draw_rim(world.dish_r)
	if world.def_on:
		_draw_defense()


func _draw_territory() -> void:
	var t := world.terr
	if not t.dirty.is_empty():
		for i in t.dirty:
			_terr_img.set_pixel(i % t.n, i / t.n, _land_color if t.tiles[i] == Territory.OWNED else Color(0, 0, 0, 0))
		t.dirty.clear()
		_terr_tex.update(_terr_img)
	draw_texture_rect(_terr_tex, Rect2(t.origin, Vector2.ONE * t.cell * t.n), false)
	_draw_rim(t.radius)


## Darken everything outside the dish and draw the glass rim.
func _draw_rim(radius: float) -> void:
	draw_arc(Vector2.ZERO, radius + 700.0, 0, TAU, 96, Color(0.04, 0.02, 0.08, 0.9), 1400.0)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 128, Color(0.75, 0.85, 1.0, 0.35), 10.0)


## Nucleus mode: vents, build pads and towers, and the nucleus itself. Drawn
## under the enemies (only a handful of shapes).
func _draw_defense() -> void:
	var w := world
	var now := Time.get_ticks_msec() / 1000.0
	var pulse := 0.5 + 0.5 * sin(now * (7.0 if w.wave_state == "breather" else 3.0))
	for v in w.vents_active:
		var vp := w.vent_pos[v]
		draw_circle(vp, 70.0 + 12.0 * pulse, Color(pal.vent, 0.10 + 0.12 * pulse))
		draw_arc(vp, 52.0, 0, TAU, 32, Color(pal.vent, 0.5 + 0.4 * pulse), 5.0)
	var on := w.pad_under_player()
	var ps := float(w.dcfg.pad_size)
	for k in w.pad_pos.size():
		var pos := w.pad_pos[k]
		var cost := w.pad_next_cost(k)
		var afford := cost >= 0 and w.biomass >= float(cost)
		var lv := w.pad_level[k]
		if w.pad_tower[k] < 0:
			draw_circle(pos, ps, Color(pal.pad, 0.10 if afford else 0.05))
			draw_arc(pos, ps, 0, TAU, 32, Color(pal.pad, 0.75 if afford else 0.3), 4.0)
			draw_string(font, pos + Vector2(-40, 9), str(cost), HORIZONTAL_ALIGNMENT_CENTER, 80, 26, Color(1, 1, 1, 0.9 if afford else 0.45))
		else:
			var t: Dictionary = w.tower_defs[w.pad_tower[k]]
			var tc := GameData.color(t.get("color", "#ffffff"))
			var maxed := cost < 0
			draw_circle(pos, ps * 0.78, Color(0, 0, 0, 0.35))
			draw_circle(pos, ps * 0.66, Color("#3d2d6b"))
			draw_arc(pos, ps * 0.66, 0, TAU, 28, pal.ui_accent if maxed else tc, 4.0)
			IconArt.draw(self, t.weapon, pos, ps * (0.85 + 0.1 * lv), tc)
			for j in lv:
				draw_circle(pos + Vector2((j - (lv - 1) / 2.0) * 13.0, ps * 0.66 + 12.0), 4.5, pal.ui_accent if maxed else tc)
			if k == on or w.p_pos.distance_squared_to(pos) < 160.0 * 160.0:
				var label := "MAX" if maxed else "UP %d" % cost
				draw_string(font, pos + Vector2(-60, -ps - 10), label, HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(pal.pad if afford else Color(1, 1, 1, 0.5)) if not maxed else pal.ui_accent)
		if w.pad_progress[k] > 0.0:
			draw_arc(pos, ps + 8.0, -PI / 2.0, -PI / 2.0 + TAU * minf(w.pad_progress[k], 1.0), 32, pal.pad, 7.0)
	# The nucleus: soft glow, membrane, nucleus; flashes when hit.
	var c := w.core_pos
	var r := w.core_r * (1.0 + 0.025 * sin(now * 2.0))
	var hpf := w.core_hp / maxf(w.core_max, 1.0)
	var body: Color = pal.core.lerp(pal.player_hurt, clampf(_core_flash * 5.0, 0.0, 1.0))
	draw_circle(c, r + 22.0, Color(pal.core, 0.10))
	draw_circle(c, r + 8.0, Color(body, 0.35))
	draw_circle(c, r, body)
	draw_circle(c + Vector2(cos(now * 0.6), sin(now * 0.8)) * 5.0, r * 0.45, pal.core_nucleus.darkened(0.4 * (1.0 - hpf)))


func _fill_gems(view: Rect2) -> void:
	_gems.begin()
	var hop_s := float(juice.get("gem_hop_s", 0.0))
	var hop_h := float(juice.get("gem_hop_h", 0.0))
	for i in world.g_pos.size():
		var p := world.g_pos[i]
		if not view.has_point(p):
			continue
		var v := world.g_val[i]
		# Pop out of the kill: a short hop with a squash on landing (view only).
		var age := world.time - world.g_born[i] if i < world.g_born.size() else 1.0
		var sz := 1.0
		if age < hop_s:
			var k := age / hop_s
			p.y -= sin(k * PI) * hop_h
			sz = 0.4 + 0.8 * k if k < 0.5 else 1.0 + 0.25 * sin((k - 0.5) * 2.0 * PI)
		if v >= 10.0:
			_gems.add(p, 18.0 * sz, pal.gem_large)
		elif v >= 3.0:
			_gems.add(p, 14.0 * sz, pal.gem_medium)
		else:
			_gems.add(p, 10.0 * sz, pal.gem_small)
	_gems.commit()


func _fill_shots() -> void:
	_shots.begin()
	var c: Color = pal.enemy_shot
	var dark := c.darkened(0.3)
	for i in world.s_pos.size():
		_shots.add(world.s_pos[i], 16.0, dark)
		_shots.add(world.s_pos[i], 10.0, c)
	_shots.commit()


func _fill_enemies(view: Rect2) -> void:
	_enemies.begin()
	_allies.begin()
	var white := Color.WHITE
	var pp := world.p_pos
	var pulse_k := float(juice.get("hit_pulse", 0.0)) / maxf(float(juice.flash_s), 0.001)
	# Allies wear the current order's colour (Guard = our plain colour) and
	# shimmer during an Outbreak frenzy (they're boosted too).
	var ally_base: Color = pal.player_nucleus
	if world.conv_on:
		if world.ally_order != World.ORDER_GUARD:
			ally_base = GameData.color(world.bal.conversion.orders[World.ORDER_IDS[world.ally_order]].color)
		if world.outbreak_t > 0.0:
			ally_base = ally_base.lerp(white, 0.25 + 0.15 * sin(world.time * 14.0))
	for i in world.e_pos.size():
		var p := world.e_pos[i]
		var r := world.enemy_radius(i)
		if p.x < view.position.x - r or p.x > view.end.x + r or p.y < view.position.y - r or p.y > view.end.y + r:
			continue
		var t := world.e_type[i]
		var c: Color = enemy_colors[t]
		if world.e_team[i] == 1:
			# Allies: our own cell shape in our colour (type faintly hinted).
			c = ally_base.lerp(c, 0.2)
			if world.e_flash[i] > 0.0:
				c = white
			if world.e_life[i] < 3.0 and fmod(world.time, 0.3) < 0.15:
				c.a = 0.35
			_allies.add(p, r * 2.0 / ShapeTextures.BLOB_OUTER, c)
			continue
		if world.e_flash[i] > 0.0:
			c = white
		elif world.e_phase[i] == 1 and world._tbeh[t] == World.BEH_DASH:
			c = c.lerp(white, 0.5 + 0.5 * sin(world.time * 40.0))
		elif world.e_gild[i] == 1:
			c = c.lerp(pal.ui_accent, 0.7)  # coated in gold by an Outbreak
		elif world.e_plague[i] > 0.0:
			c = c.lerp(pal.outbreak, 0.7)  # infected by the Plague Trail
		elif world.def_on and world.e_slow[i] > 0.0:
			c = c.lerp(pal.nova, 0.5)  # Fever Node slow
		var pulse := 1.0 + pulse_k * maxf(world.e_flash[i], 0.0)  # pops a little when hit
		_enemies.add(p, r * _blob_scale * pulse, c, (pp - p).angle())
	_enemies.commit()
	_allies.commit()


func _fill_bullets() -> void:
	_bullets.begin()
	var bc: Color = _wcolor("bolt", pal.bolt)
	var trail := Color(bc, 0.35)
	for i in world.b_pos.size():
		var p := world.b_pos[i]
		var r := world.b_rad[i]
		_bullets.add(p - world.b_vel[i].normalized() * r * 1.6, r * 2.2, trail)
		_bullets.add(p, r * 2.0, bc)
	_bullets.commit()


func _fill_dots() -> void:
	_dots.begin()
	for f in fx:
		var k: float = f.t / f.life
		if f.kind == "dot":
			_dots.add(f.pos, f.r * 2.0 * (1.0 - k), Color(f.color, 1.0 - k))
		elif f.kind == "pop":
			_dots.add(f.pos, f.r * 2.0 * (1.0 + k), Color(f.color, 0.45 * (1.0 - k)))
	_dots.commit()
	_rings.begin()
	for f in fx:
		if f.kind == "kring":
			var k: float = f.t / f.life
			_rings.add(f.pos, f.r * 2.0 * (1.0 + 1.6 * k), Color(f.color.lightened(0.3), 0.9 * (1.0 - k)))
	_rings.commit()


# ------------------------------------------------- immediate top layer (few)

func _draw_top() -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	_draw_top_layer()
	cpu_ms += (Time.get_ticks_usec() - t0) / 1000.0


func _draw_top_layer() -> void:
	var ci := _top
	var now := Time.get_ticks_msec() / 1000.0
	_draw_trail(ci, now)
	_draw_loot(ci, now)
	# Elite aura: pulsing ring so they read as "big target, big reward".
	# Ally ring: thin outline in our colour so the swarm reads as ours.
	for i in world.e_pos.size():
		if world.ally_count > 0 and world.is_ally(i):
			continue
		if world.is_elite(i):
			var r := world.enemy_radius(i) * 1.25 + 4.0 * sin(now * 8.0)
			ci.draw_arc(world.e_pos[i], r, 0, TAU, 32, Color(elite_color, 0.9), 4.0)
			ci.draw_circle(world.e_pos[i], r + 10.0, Color(elite_color, 0.12))
		_draw_telegraph(ci, i)
	for j in world.tower_orbs.size():
		var tc := GameData.color(world.tower_defs[world.tower_orb_type[j]].get("color", "#ffffff"))
		ci.draw_circle(world.tower_orbs[j], world.tower_orb_r[j] + 3.0, Color(tc, 0.35))
		ci.draw_circle(world.tower_orbs[j], world.tower_orb_r[j], tc)
	var oc: Color = _wcolor("orbit", pal.orbit)
	for p in world.orbit_points:
		ci.draw_circle(p, world.orbit_size + 3.0, Color(oc, 0.35))
		ci.draw_circle(p, world.orbit_size, oc)
	_draw_player(ci)
	for f in fx:
		var k: float = f.t / f.life
		match f.kind:
			"ring":
				var c: Color = f.get("color", pal.nova)
				# Translucent fills are only for small rings: a big one (Fever
				# Spike, vacuum, bomb) covers the screen and costs phones a lot
				# of fill rate, which showed up as frame-time spikes.
				if f.r < 160.0:
					ci.draw_circle(f.pos, f.r * (0.4 + 0.6 * k), Color(c, 0.18 * (1.0 - k)))
				ci.draw_arc(f.pos, f.r * (0.4 + 0.6 * k), 0, TAU, 40, Color(c, 0.9 * (1.0 - k)), 5.0)
			"chain":
				var pts: PackedVector2Array = f.points
				var c: Color = f.get("color", pal.chain)
				for j in pts.size() - 1:
					var a := pts[j]
					var b := pts[j + 1]
					var mid := (a + b) / 2.0 + (b - a).orthogonal().normalized() * randf_range(-14, 14)
					ci.draw_polyline(PackedVector2Array([a, mid, b]), Color(c, 1.0 - k), 4.0)
			"claim":
				if world.terr != null:
					var t := world.terr
					var c := Color(1, 1, 1, 0.45 * (1.0 - k))
					for i: int in f.cells:
						ci.draw_rect(Rect2(t.center_of(i) - Vector2.ONE * t.cell * 0.5, Vector2.ONE * t.cell), c)
			"num":
				if digits == null or not digits.baked:
					var pos: Vector2 = f.pos + Vector2(0, -40.0 * k)
					ci.draw_string(font, pos + Vector2(-20, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 40, 22, Color(1, 1, 1, 1.0 - k * k))
	# Damage numbers last, from the baked digit texture: one batch, no text
	# layout per frame (same look: rise 40 px and fade).
	if digits != null and digits.baked:
		var gold: Color = pal.ui_accent
		var pop := float(juice.get("num_pop", 0.0))
		var big_k := float(juice.get("num_big_scale", 0.0))
		var kill_k := float(juice.get("num_kill_scale", 0.0))
		for f in fx:
			if f.kind == "num":
				var k: float = f.t / f.life
				var big := clampf(float(f.frac), 0.0, 1.0)
				# Springy pop: starts big, squashes a little below size, settles.
				var x: float = f.t / 0.22
				var punch := pop * exp(-5.0 * x) * cos(9.0 * x)
				var h := 26.0 * (1.0 + big_k * big) * (1.0 + punch)
				if f.killed:
					h *= 1.0 + kill_k
				h *= 1.0 - 0.6 * maxf(0.0, (k - 0.7) / 0.3)  # shrink away at the end
				var col := _num_color(big, f.killed)
				col.a = 1.0 - maxf(0.0, (k - 0.6) / 0.4)
				digits.draw_number(ci, int(f.value), f.pos, h, col)
	var bi := world.boss_index
	if bi >= 0 and bi < world.e_pos.size():
		var p := world.e_pos[bi]
		var r := world.enemy_radius(bi)
		var f := world.e_hp[bi] / world.e_maxhp[bi]
		ci.draw_rect(Rect2(p + Vector2(-r, -r - 18), Vector2(r * 2, 8)), Color(0, 0, 0, 0.5))
		ci.draw_rect(Rect2(p + Vector2(-r, -r - 18), Vector2(r * 2 * f, 8)), pal.hp_bar)


## Smoothed pose for the player cell: the nucleus swings toward where you
## steer instead of snapping, the body stretches along the movement (more
## in a dash), breathes when idle, and squishes when hurt. Visual only.
func _update_cell_pose(delta: float) -> void:
	_cell_t += delta
	var target := world.p_facing.angle()
	var turn := float(juice.get("turn_rate", 14.0)) * delta
	_face = rotate_toward(_face, target, turn)
	var spd := float(bal.player.speed)
	var v := world.p_vel
	var stretch := 0.0
	if world.p_dash_t > 0.0:
		stretch = float(juice.get("dash_stretch", 0.3))
		_move_ang = world.p_dash_dir.angle()
	elif v.length_squared() > 1.0:
		stretch = float(juice.get("cell_squash", 0.1)) * clampf(v.length() / spd, 0.0, 1.0)
		_move_ang = rotate_toward(_move_ang, v.angle(), turn)
	_squash = lerpf(_squash, stretch, 1.0 - exp(-14.0 * delta))
	_hurt_squish = maxf(0.0, _hurt_squish - delta * 5.0)


func _draw_player(ci: CanvasItem) -> void:
	if world.p_down > 0.0:
		return  # reforming at the nucleus
	var p := world.p_pos
	var r := world.p_radius
	var body: Color = pal.player
	if _hurt_t > 0.0 and fmod(_hurt_t, 0.12) < 0.06:
		body = pal.player_hurt
	var breathe := float(juice.get("cell_breathe", 0.03)) * sin(_cell_t * 2.4) * (1.0 - clampf(_squash * 8.0, 0.0, 1.0))
	var squish := 0.18 * _hurt_squish
	var sx := 1.0 + _squash + breathe - squish
	var sy := 1.0 - _squash * 0.6 + breathe * 0.5 + squish * 0.6
	# Cilia: short hairs around the membrane that wave faster with speed.
	var speed_k := clampf(world.p_vel.length() / float(bal.player.speed), 0.0, 1.0)
	var n := int(juice.get("cilia", 12))
	var cc := Color(body, 0.55)
	ci.draw_set_transform(p, _move_ang, Vector2(sx, sy))
	for k in n:
		var a := TAU * k / n
		var wave := sin(_cell_t * (6.0 + 10.0 * speed_k) + k * 1.7) * 0.35
		var base := Vector2.from_angle(a) * r * 1.0
		var tip := Vector2.from_angle(a + wave * 0.5) * r * (1.32 + 0.08 * speed_k)
		ci.draw_line(base, tip, cc, 2.0)
	if world.outbreak_t > 0.0:
		# Frenzy aura: a pulsing glow behind the cell.
		var gr := r * (1.9 + 0.15 * sin(_cell_t * 14.0))
		ci.draw_texture_rect(_disc_tex, Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(pal.outbreak, 0.35))
	var q := r / ShapeTextures.CELL_BODY
	ci.draw_texture_rect(_cell_tex, Rect2(-q, -q, q * 2.0, q * 2.0), false, body)
	ci.draw_set_transform(p, 0.0, Vector2(sx * 0.5 + 0.5, sy * 0.5 + 0.5))
	# Nucleus leads the turn, with a small highlight.
	var nc := Vector2.from_angle(_face) * r * 0.28
	var nr := r * 0.44
	ci.draw_texture_rect(_disc_tex, Rect2(nc - Vector2(nr, nr), Vector2(nr, nr) * 2.0), false, pal.player_nucleus)
	var hl := nc + Vector2(-0.35, -0.35) * nr
	ci.draw_texture_rect(_disc_tex, Rect2(hl - Vector2(nr, nr) * 0.3, Vector2(nr, nr) * 0.6), false, Color(1, 1, 1, 0.55))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if world.p_hp < world.p_max_hp:
		var w := 48.0
		var pos := p + Vector2(-w / 2.0, r + 10.0)
		ci.draw_rect(Rect2(pos, Vector2(w, 6)), Color(0, 0, 0, 0.55))
		ci.draw_rect(Rect2(pos, Vector2(w * world.p_hp / world.p_max_hp, 6)), pal.hp_bar)


## Chests (gold, bobbing, glowing) and rare pickups (simple icons).
func _draw_loot(ci: CanvasItem, now: float) -> void:
	var gold: Color = pal.gem_large
	for k in world.c_pos.size():
		var p := world.c_pos[k] + Vector2(0, -6.0 * sin(now * 4.0 + k))
		ci.draw_circle(p, 38.0 + 4.0 * sin(now * 6.0), Color(gold, 0.18))
		ci.draw_rect(Rect2(p - Vector2(20, 14), Vector2(40, 28)), gold.darkened(0.25))
		ci.draw_rect(Rect2(p - Vector2(20, 14), Vector2(40, 10)), gold)
		ci.draw_rect(Rect2(p - Vector2(4, 6), Vector2(8, 10)), Color(0.25, 0.15, 0.05))
	for k in world.i_pos.size():
		var p := world.i_pos[k] + Vector2(0, -4.0 * sin(now * 5.0 + k))
		var kind: String = World.PICKUP_KINDS[world.i_kind[k]]
		match kind:
			"vacuum":
				var c: Color = pal.gem_small
				ci.draw_circle(p, 22.0, Color(c, 0.2))
				ci.draw_arc(p, 14.0, 0, TAU, 24, c, 4.0)
				ci.draw_circle(p, 5.0, c)
			"heal":
				var c: Color = pal.gem_medium
				ci.draw_circle(p, 22.0, Color(c, 0.2))
				ci.draw_rect(Rect2(p - Vector2(12, 4), Vector2(24, 8)), c)
				ci.draw_rect(Rect2(p - Vector2(4, 12), Vector2(8, 24)), c)
			"bomb":
				var c: Color = pal.enemy_shot
				ci.draw_circle(p, 22.0, Color(c, 0.2))
				ci.draw_circle(p, 13.0, Color(0.15, 0.1, 0.12))
				ci.draw_circle(p + Vector2(7, -11), 5.0 + 2.0 * sin(now * 20.0), c)


## The trail you're drawing outside your land; blinks when about to fade.
func _draw_trail(ci: CanvasItem, now: float) -> void:
	var t := world.terr
	if t == null or t.trail_points.is_empty():
		return
	var pts := t.trail_points.duplicate()
	pts.append(world.p_pos)
	var c: Color = pal.player_nucleus
	var left := t.trail_time_left()
	if left < 2.5 and fmod(now, 0.25) < 0.12:
		c = pal.player_hurt
	ci.draw_polyline(pts, Color(c, 0.85), 7.0)


## Damage numbers merge per enemy while hits keep landing (one growing total
## instead of a spray), and each hit throws a couple of sparks (budgeted per
## frame).
func _on_hit(ev: Dictionary, max_fx: int) -> void:
	if juice.damage_numbers:
		var uid := int(ev.get("uid", -1))
		var old: Variant = _num_by_uid.get(uid)
		if old != null and old.t < float(juice.get("num_merge_s", 0.0)) and not old.killed:
			old.value += roundi(ev.amount)
			old.frac += float(ev.get("frac", 0.0))
			old.t = 0.0
			old.vel = Vector2(old.vel.x * 0.5, -float(juice.get("num_rise", 0.0)) * 0.6)  # hop again
		elif _damage_numbers < int(bal.perf.max_damage_numbers):
			_damage_numbers += 1
			# Numbers hop out sideways and fall back under gravity (instead of
			# a straight rise), so a burst of hits sprays instead of stacking.
			var spread := float(juice.get("num_spread", 0.0))
			var f := {"kind": "num", "pos": ev.pos + Vector2(randf_range(-8, 8), -14), "text": str(roundi(ev.amount)),
				"value": roundi(ev.amount), "frac": float(ev.get("frac", 0.0)), "uid": uid, "life": float(juice.get("num_life_s", 0.55)),
				"vel": Vector2(randf_range(-spread, spread), -float(juice.get("num_rise", 0.0))), "grav": float(juice.get("num_grav", 0.0)), "killed": false}
			_add_fx(f, max_fx)
			_num_by_uid[uid] = f
	if _sparks_left > 0:
		_sparks_left -= 1
		for n in 2:
			var a := randf() * TAU
			_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(180, 320), "color": Color(1, 0.95, 0.75), "r": 2.5, "life": 0.14}, max_fx + 20)


## Damage number colour by how big the hit was (share of the germ's max HP):
## white -> yellow -> orange -> hot pink; the killing blow is always hot.
func _num_color(big: float, killed: bool) -> Color:
	if killed:
		return Color("#ff5a7a").lerp(Color("#ffd166"), 0.25 * (1.0 - big))
	if big < 0.25:
		return Color.WHITE.lerp(Color("#fff07a"), big / 0.25)
	if big < 0.6:
		return Color("#fff07a").lerp(Color("#ffab4d"), (big - 0.25) / 0.35)
	return Color("#ffab4d").lerp(Color("#ff5a7a"), clampf((big - 0.6) / 0.4, 0.0, 1.0))


## The number on a germ that just died becomes the killing blow: hot colour,
## a fresh pop, a bit bigger, and it hangs on a little longer.
func _mark_killing_blow(uid: int) -> void:
	var f: Variant = _num_by_uid.get(uid)
	if f == null or f.killed:
		return
	f.killed = true
	f.t = 0.0
	f.life = float(f.life) + 0.15
	f.vel = Vector2(f.vel.x * 0.4, -float(juice.get("num_rise", 0.0)) * 0.8)


## Floor goo: a fixed-size ring buffer, faded out over juice.splat_s.
func _add_splat(pos: Vector2, size: float, c: Color) -> void:
	var cap := int(juice.get("splat_max", 0))
	if cap <= 0:
		return
	var col := Color(c.darkened(0.15), 0.6)
	if _sp_pos.size() < cap:
		_sp_pos.append(pos)
		_sp_size.append(size)
		_sp_col.append(col)
		_sp_t.append(0.0)
	else:
		_sp_pos[_sp_next] = pos
		_sp_size[_sp_next] = size
		_sp_col[_sp_next] = col
		_sp_t[_sp_next] = 0.0
		_sp_next = (_sp_next + 1) % cap


func _age_splats(delta: float) -> void:
	for i in _sp_t.size():
		_sp_t[i] += delta


func _fill_splats() -> void:
	_splats.begin()
	var life := float(juice.get("splat_s", 3.0))
	for i in _sp_pos.size():
		var k := _sp_t[i] / life
		if k < 1.0:
			var c := _sp_col[i]
			c.a *= 1.0 - k * k
			_splats.add(_sp_pos[i], _sp_size[i] * (1.0 + 0.15 * minf(_sp_t[i] * 8.0, 1.0)), c)
	_splats.commit()


## Warnings before enemy attacks (visual only; timings come from the World):
## a Lancer's dash lane fills during its wind-up, a Spitter's mouth glows as
## its shot charges (and stays lit while ready), and the Mother Cell shows a
## closing ring before its burst.
func _draw_telegraph(ci: CanvasItem, i: int) -> void:
	var t := world.e_type[i]
	var beh := world._tbeh[t]
	if beh == World.BEH_CHASE:
		return
	var p := world.e_pos[i]
	var r := world.enemy_radius(i)
	match beh:
		World.BEH_DASH:
			if world.e_phase[i] != 1:
				return
			var k := clampf(1.0 - world.e_timer[i] / maxf(_windup[t], 0.01), 0.0, 1.0)
			var d := world.e_dir[i]
			var end := p + d * _dash_len[t]
			var warn: Color = pal.player_hurt
			ci.draw_line(p, end, Color(warn, 0.10 + 0.18 * k), r * 2.0)
			ci.draw_line(p, p + (end - p) * k, Color(warn, 0.55), 4.0)
			var side := d.orthogonal() * r * 0.8
			ci.draw_colored_polygon(PackedVector2Array([end + d * r, end - side, end + side]), Color(warn, 0.25 + 0.5 * k))
		World.BEH_RANGED:
			if world.e_team[i] != 0:
				return
			var tele := float(juice.get("spit_telegraph_s", 0.5))
			var k := clampf(1.0 - world.e_timer[i] / tele, 0.0, 1.0)
			if k <= 0.0:
				return
			var target := world.p_pos
			if world.def_on and (world.p_down > 0.0 or p.distance_squared_to(world.p_pos) > float(world.dcfg.aggro_radius) ** 2):
				target = world.core_pos
			if p.distance_squared_to(target) > _fire_range[t] * _fire_range[t]:
				return
			var mouth := p + (target - p).normalized() * r * 0.9
			var c: Color = pal.enemy_shot
			ci.draw_circle(mouth, 4.0 + 8.0 * k, Color(c, 0.3 + 0.4 * k))
			ci.draw_circle(mouth, 2.5 + 4.0 * k, Color(1, 1, 0.85, 0.35 + 0.6 * k))
			ci.draw_arc(p, r + 4.0 + 10.0 * (1.0 - k), 0, TAU, 24, Color(c, 0.6 * k), 2.5)
		World.BEH_BOSS:
			var tele := float(juice.get("boss_telegraph_s", 0.7))
			if world.e_timer[i] > tele:
				return
			var k := clampf(1.0 - world.e_timer[i] / tele, 0.0, 1.0)
			ci.draw_arc(p, r * (2.6 - 1.4 * k), 0, TAU, 48, Color(pal.enemy_shot, 0.25 + 0.6 * k), 3.0 + 4.0 * k)


## The Plague Trail: soft green blobs that fade as they age (one batch).
func _fill_plague() -> void:
	_plague.begin()
	var life := float(bal.get("outbreak", {}).get("trail_life_s", 3.0))
	var r := float(bal.get("outbreak", {}).get("trail_radius", 30.0))
	var c: Color = pal.outbreak
	for k in world.pt_pos.size():
		var f := 1.0 - world.pt_age[k] / life
		_plague.add(world.pt_pos[k], r * 2.6 * (0.7 + 0.3 * f), Color(c, 0.45 * f))
	_plague.commit()
