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
## CPU ms spent in this view since Main last read it (fill + draw recording);
## Main resets it each frame (benchmark and perf readout).
var cpu_ms := 0.0


func setup(game_data: Dictionary) -> void:
	bal = game_data.balance
	juice = bal.juice
	for k in bal.palette:
		pal[k] = GameData.color(bal.palette[k])
	enemy_colors.clear()
	for e in game_data.enemies:
		enemy_colors.append(GameData.color(e.color))
	font = ThemeDB.fallback_font
	for ev in game_data.get("evolutions", []):
		evo_colors[ev.weapon] = GameData.color(ev.color)
	elite_color = GameData.color(game_data.waves.elites.color)
	if cam != null:
		return
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var perf: Dictionary = bal.perf
	var disc := ShapeTextures.disc()
	_gems = _batch(ShapeTextures.diamond(), int(bal.xp.max_gems))
	_shots = _batch(disc, int(perf.max_enemy_shots) * 2)
	_enemies = _batch(ShapeTextures.blob(64, ENEMY_DIRS), int(game_data.waves.max_alive) + 120, ENEMY_DIRS)
	_allies = _batch(ShapeTextures.ally_cell(), 64)
	_bullets = _batch(disc, int(perf.max_projectiles) * 2)
	_dots = _batch(disc, int(perf.max_effects))
	_blob_scale = 2.0 / ShapeTextures.BLOB_BODY  # body radius -> quad width
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
	_damage_numbers = 0


func add_shake(amount: float) -> void:
	shake = maxf(shake, amount)


## Turns simulation events into effects. Called by Main after every step.
func consume(events: Array) -> void:
	var max_fx := int(bal.perf.max_effects)
	for ev in events:
		match ev.type:
			"hit":
				if juice.damage_numbers and _damage_numbers < int(bal.perf.max_damage_numbers):
					_damage_numbers += 1
					_add_fx({"kind": "num", "pos": ev.pos + Vector2(randf_range(-8, 8), -10), "text": str(roundi(ev.amount)), "value": roundi(ev.amount), "life": 0.55}, max_fx)
			"kill":
				var c := GameData.color(ev.color)
				for k in int(juice.kill_burst_particles):
					var a := randf() * TAU
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(60, 170), "color": c, "r": randf_range(2.5, 5.0), "life": 0.35}, max_fx)
				_add_fx({"kind": "pop", "pos": ev.pos, "color": c, "r": ev.radius, "life": 0.18}, max_fx)
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
			"ally_lost":
				_add_fx({"kind": "pop", "pos": ev.pos, "color": pal.player_nucleus, "r": 14.0, "life": 0.25}, max_fx)
			"shot_blocked":
				_add_fx({"kind": "pop", "pos": ev.pos, "color": _wcolor("orbit", pal.orbit), "r": 10.0, "life": 0.2}, max_fx)
			"dash":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 46.0, "life": 0.2, "color": pal.player}, max_fx + 4)
			"elite_killed":
				add_shake(10.0)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 150.0, "life": 0.4, "color": elite_color}, max_fx + 4)
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
			"upgrade":
				# Pick burst in the upgrade's colour, right on the player.
				var uc := IconArt.color_for(world.upgrade_defs[ev.id])
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 130.0, "life": 0.45, "color": uc}, max_fx + 4)
				for n in 10:
					var a := TAU * n / 10.0
					_add_fx({"kind": "dot", "pos": world.p_pos, "vel": Vector2(cos(a), sin(a)) * 240.0, "color": uc, "r": 6.0, "life": 0.45}, max_fx + 14)
			"evolution":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 320.0, "life": 0.7, "color": _wcolor(ev.weapon, pal.ui_accent)}, max_fx + 4)
			"hurt":
				add_shake(float(juice.shake_hurt))
				_hurt_t = float(bal.player.iframes_s)
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
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 260.0, "life": 0.6}, max_fx + 4)


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
			fx.remove_at(i)
			continue
		if f.has("vel"):
			f.pos += f.vel * delta
		i += 1
	_hurt_t = maxf(0.0, _hurt_t - delta)
	_core_flash = maxf(0.0, _core_flash - delta)
	if world.p_dash_t > 0.0:
		_add_fx({"kind": "dot", "pos": world.p_pos, "vel": Vector2.ZERO, "color": Color(pal.player, 0.6), "r": world.p_radius, "life": 0.22}, int(bal.perf.max_effects) + 8)
	shake = maxf(0.0, shake - float(juice.shake_decay) * delta)
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	cam.position = (world.core_pos if world.p_down > 0.0 else world.p_pos) + off
	var vp := get_viewport_rect().size
	var view := Rect2(cam.position - vp / 2.0, vp).grow(80)
	_fill_gems(view)
	_fill_shots()
	_fill_enemies(view)
	_fill_bullets()
	_fill_dots()
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
	var vp := get_viewport_rect().size
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
	for i in world.g_pos.size():
		var p := world.g_pos[i]
		if not view.has_point(p):
			continue
		var v := world.g_val[i]
		if v >= 10.0:
			_gems.add(p, 18.0, pal.gem_large)
		elif v >= 3.0:
			_gems.add(p, 14.0, pal.gem_medium)
		else:
			_gems.add(p, 10.0, pal.gem_small)
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
	for i in world.e_pos.size():
		var p := world.e_pos[i]
		var r := world.enemy_radius(i)
		if p.x < view.position.x - r or p.x > view.end.x + r or p.y < view.position.y - r or p.y > view.end.y + r:
			continue
		var t := world.e_type[i]
		var c: Color = enemy_colors[t]
		if world.e_team[i] == 1:
			# Allies: our own cell shape in our colour (type faintly hinted).
			c = pal.player_nucleus.lerp(c, 0.2)
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
		elif world.def_on and world.e_slow[i] > 0.0:
			c = c.lerp(pal.nova, 0.5)  # Fever Node slow
		_enemies.add(p, r * _blob_scale, c, (pp - p).angle())
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
		for f in fx:
			if f.kind == "num":
				var k: float = f.t / f.life
				digits.draw_number(ci, int(f.value), f.pos + Vector2(0, -40.0 * k - 8.0), 26.0, Color(1, 1, 1, 1.0 - k * k))
	var bi := world.boss_index
	if bi >= 0 and bi < world.e_pos.size():
		var p := world.e_pos[bi]
		var r := world.enemy_radius(bi)
		var f := world.e_hp[bi] / world.e_maxhp[bi]
		ci.draw_rect(Rect2(p + Vector2(-r, -r - 18), Vector2(r * 2, 8)), Color(0, 0, 0, 0.5))
		ci.draw_rect(Rect2(p + Vector2(-r, -r - 18), Vector2(r * 2 * f, 8)), pal.hp_bar)


func _draw_player(ci: CanvasItem) -> void:
	if world.p_down > 0.0:
		return  # reforming at the nucleus
	var p := world.p_pos
	var r := world.p_radius
	var body: Color = pal.player
	if _hurt_t > 0.0 and fmod(_hurt_t, 0.12) < 0.06:
		body = pal.player_hurt
	ci.draw_circle(p, r + 3.0, Color(body, 0.3))
	ci.draw_circle(p, r, body)
	ci.draw_circle(p + world.p_facing * r * 0.25, r * 0.42, pal.player_nucleus)
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
