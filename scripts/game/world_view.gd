class_name WorldView
extends Node2D
## Draws the World with immediate-mode shapes (one CanvasItem, no sprites):
## cheap on old GPUs and keeps the flat art style consistent. Also owns
## short-lived visual effects (kill bursts, rings, sparks, damage numbers)
## and camera shake, all driven by World events and data/balance.json "juice".

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


func setup(game_data: Dictionary) -> void:
	bal = game_data.balance
	juice = bal.juice
	for k in bal.palette:
		pal[k] = GameData.color(bal.palette[k])
	enemy_colors.clear()
	for e in game_data.enemies:
		enemy_colors.append(GameData.color(e.color))
	font = ThemeDB.fallback_font
	if cam == null:
		cam = Camera2D.new()
		add_child(cam)
	cam.make_current()


func set_world(w: World) -> void:
	world = w
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
					_add_fx({"kind": "num", "pos": ev.pos + Vector2(randf_range(-8, 8), -10), "text": str(roundi(ev.amount)), "life": 0.55}, max_fx)
			"kill":
				var c := GameData.color(ev.color)
				for k in int(juice.kill_burst_particles):
					var a := randf() * TAU
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(60, 170), "color": c, "r": randf_range(2.5, 5.0), "life": 0.35}, max_fx)
				_add_fx({"kind": "pop", "pos": ev.pos, "color": c, "r": ev.radius, "life": 0.18}, max_fx)
			"nova":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius, "life": 0.3}, max_fx)
				add_shake(float(juice.shake_nova))
			"chain":
				_add_fx({"kind": "chain", "points": ev.points, "life": 0.16}, max_fx)
			"hurt":
				add_shake(float(juice.shake_hurt))
			"boss_killed":
				add_shake(float(juice.shake_boss_kill))
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 260.0, "life": 0.6}, max_fx + 1)


func _add_fx(f: Dictionary, cap: int) -> void:
	if fx.size() >= cap:
		return
	f["t"] = 0.0
	fx.append(f)


func _process(delta: float) -> void:
	if world == null:
		return
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
	shake = maxf(0.0, shake - float(juice.shake_decay) * delta)
	var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	cam.position = world.p_pos + off
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var vp := get_viewport_rect().size
	var view := Rect2(cam.position - vp / 2.0, vp).grow(80)
	_draw_background(view)
	_draw_gems(view)
	_draw_enemy_shots()
	_draw_enemies(view)
	_draw_weapons()
	_draw_player()
	_draw_fx()


func _hash(x: int, y: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663)
	return float(absi(h) % 1000) / 1000.0


func _draw_background(view: Rect2) -> void:
	draw_rect(view, pal.background)
	var step := 110.0
	var x0 := floori(view.position.x / step)
	var y0 := floori(view.position.y / step)
	var x1 := ceili(view.end.x / step)
	var y1 := ceili(view.end.y / step)
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var h := _hash(gx, gy)
			var p := Vector2(gx + h * 0.8, gy + _hash(gy, gx) * 0.8) * step
			if h > 0.82:
				draw_circle(p, 18.0 + h * 26.0, pal.background_cells)
			else:
				draw_circle(p, 2.0 + h * 2.5, pal.background_dots)


func _draw_gems(view: Rect2) -> void:
	for i in world.g_pos.size():
		var p := world.g_pos[i]
		if not view.has_point(p):
			continue
		var v := world.g_val[i]
		var c: Color = pal.gem_small
		var r := 5.0
		if v >= 10.0:
			c = pal.gem_large
			r = 9.0
		elif v >= 3.0:
			c = pal.gem_medium
			r = 7.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.8, 0), p + Vector2(0, r), p + Vector2(-r * 0.8, 0)]), c)


func _draw_enemy_shots() -> void:
	var c: Color = pal.enemy_shot
	for i in world.s_pos.size():
		draw_circle(world.s_pos[i], 8.0, c.darkened(0.3))
		draw_circle(world.s_pos[i], 5.0, c)


func _draw_enemies(view: Rect2) -> void:
	var white := Color.WHITE
	for i in world.e_pos.size():
		var p := world.e_pos[i]
		var t := world.e_type[i]
		var r := world.enemy_radius(i)
		if not view.grow(r).has_point(p):
			continue
		var c: Color = enemy_colors[t]
		var d: Dictionary = world.enemy_defs[t]
		if world.e_flash[i] > 0.0:
			c = white
		elif d.behavior == "dash" and world.e_phase[i] == 1:
			c = c.lerp(white, 0.5 + 0.5 * sin(world.time * 40.0))
		# Squash a little toward movement for life; outline for readability.
		draw_circle(p, r + 2.5, c.darkened(0.45))
		draw_circle(p, r, c)
		if r >= 12.0:
			var to_p := (world.p_pos - p).normalized()
			var side := to_p.orthogonal() * r * 0.32
			var eye := p + to_p * r * 0.35
			draw_circle(eye + side, r * 0.2, Color(0.08, 0.05, 0.12))
			draw_circle(eye - side, r * 0.2, Color(0.08, 0.05, 0.12))
		if d.behavior == "boss":
			var f := world.e_hp[i] / world.e_maxhp[i]
			draw_rect(Rect2(p + Vector2(-r, -r - 18), Vector2(r * 2, 8)), Color(0, 0, 0, 0.5))
			draw_rect(Rect2(p + Vector2(-r, -r - 18), Vector2(r * 2 * f, 8)), pal.hp_bar)


func _draw_weapons() -> void:
	var bc: Color = pal.bolt
	for i in world.b_pos.size():
		var p := world.b_pos[i]
		var r := world.b_rad[i]
		draw_line(p, p - world.b_vel[i].normalized() * r * 2.5, Color(bc, 0.45), r * 1.2)
		draw_circle(p, r, bc)
	var oc: Color = pal.orbit
	for p in world.orbit_points:
		draw_circle(p, world.orbit_size + 3.0, Color(oc, 0.35))
		draw_circle(p, world.orbit_size, oc)


func _draw_player() -> void:
	var p := world.p_pos
	var r := world.p_radius
	var body: Color = pal.player
	if world.p_iframes > 0.0 and fmod(world.p_iframes, 0.12) < 0.06:
		body = pal.player_hurt
	draw_circle(p, r + 3.0, Color(body, 0.3))
	draw_circle(p, r, body)
	draw_circle(p + world.p_facing * r * 0.25, r * 0.42, pal.player_nucleus)
	# HP bar under the player (only when hurt).
	if world.p_hp < world.p_max_hp:
		var w := 48.0
		var pos := p + Vector2(-w / 2.0, r + 10.0)
		draw_rect(Rect2(pos, Vector2(w, 6)), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(pos, Vector2(w * world.p_hp / world.p_max_hp, 6)), pal.hp_bar)


func _draw_fx() -> void:
	for f in fx:
		var k: float = f.t / f.life
		match f.kind:
			"dot":
				draw_circle(f.pos, f.r * (1.0 - k), Color(f.color, 1.0 - k))
			"pop":
				draw_arc(f.pos, f.r * (1.0 + k), 0, TAU, 24, Color(f.color, 1.0 - k), 3.0)
			"ring":
				var c: Color = pal.nova
				draw_circle(f.pos, f.r * (0.4 + 0.6 * k), Color(c, 0.18 * (1.0 - k)))
				draw_arc(f.pos, f.r * (0.4 + 0.6 * k), 0, TAU, 48, Color(c, 0.9 * (1.0 - k)), 5.0)
			"chain":
				var pts: PackedVector2Array = f.points
				var c: Color = pal.chain
				for j in pts.size() - 1:
					var a := pts[j]
					var b := pts[j + 1]
					var mid := (a + b) / 2.0 + (b - a).orthogonal().normalized() * randf_range(-14, 14)
					draw_polyline(PackedVector2Array([a, mid, b]), Color(c, 1.0 - k), 4.0)
			"num":
				var pos: Vector2 = f.pos + Vector2(0, -40.0 * k)
				draw_string(font, pos + Vector2(-20, 0), f.text, HORIZONTAL_ALIGNMENT_CENTER, 40, 22, Color(1, 1, 1, 1.0 - k * k))
