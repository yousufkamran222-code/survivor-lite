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
var _nova_flash := 0.0  # weapon auras: brief flashes when the weapon fires
var _seq_zoom := 0.0  # evolution sequence: extra camera push-in
var _seq_glow := 0.0  # evolution sequence: glow on the cell (0..1)
var _seq_color := Color.WHITE
var _chain_flash := 0.0
var _spark_ang := 0.0  # where the Nerve Spark crackle shows on the rim
var _spark_t := 0.0
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
# Animated claim fill (Infection): newly claimed tiles appear in a wave that
# spreads from where the loop closed (juice.claim_fill_speed px/s, capped at
# claim_fill_max_s), each flashing white as the wave reaches it.
var _claim_pending := {}  # tile -> view time it appears
var _claim_wave: Array = []  # [tile, age] of tiles that just appeared (flash)
var _view_t := 0.0
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
var _glow_tex: Texture2D  # soft radial glow (under elites, the boss and the player)
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
## Cosmetics (data/cosmetics.json via Cosmetics.look; set by Main with
## set_look). Visual only.
var _skin := {}
var _wstyle := {}
var _pop := {}
var _trail := {}  # dash trail look
var _trails: SpriteBatch  # dash-trail particles (the trail's shape texture)
var _pops: SpriteBatch  # pop-style particles (the style's shape texture)
var _bolt_heads: SpriteBatch  # weapon-style bolt shapes (stars, hearts, ...)
var _shaped := false  # the weapon style has its own bolt/orbit shape


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
	_bolt_heads = _batch(disc, int(perf.max_projectiles))
	_dots = _batch(disc, int(perf.max_effects) + 40)
	_pops = _batch(disc, int(perf.max_effects) + 40)
	_trails = _batch(disc, 120)
	_rings = _batch(ShapeTextures.ring(), 48)
	_blob_scale = 2.0 / ShapeTextures.BLOB_BODY  # body radius -> quad width
	_cell_tex = ShapeTextures.player_cell()
	_disc_tex = disc
	_glow_tex = ShapeTextures.glow(64)
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
	_seq_zoom = 0.0
	_seq_glow = 0.0
	_claim_pending.clear()
	_claim_wave.clear()
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


## Applies the equipped cosmetics ({skin, weapon, pop} looks, see
## Cosmetics.look). Call after setup().
func set_look(look: Dictionary) -> void:
	_skin = look.get("skin", {})
	_wstyle = look.get("weapon", {})
	_pop = look.get("pop", {})
	_trail = look.get("trail", {})
	_trails.setup(CosmeticArt.tex(str(_trail.get("shape", "disc"))), 120)
	_shaped = CosmeticArt.weapon_shape(_wstyle) != "disc"
	var cap := int(bal.perf.max_effects) + 40
	_pops.setup(CosmeticArt.tex(str(_pop.get("shape", "disc"))), cap)
	_bolt_heads.setup(CosmeticArt.tex(CosmeticArt.weapon_shape(_wstyle)), int(bal.perf.max_projectiles))


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
				if not CosmeticArt.is_default_pop(_pop):
					_styled_pop(ev, c, max_fx)
					continue
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
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius, "life": 0.3, "color": _wcolor("nova", pal.nova), "w": 9.0 if _evo("nova") and not ev.get("tower", false) else 5.0}, max_fx + 4)
				if _evo("nova") and not ev.get("tower", false):
					_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius * 0.72, "life": 0.36, "color": Color.WHITE, "w": 3.0}, max_fx + 4)
				_nova_flash = 1.0
				if not ev.get("tower", false):
					add_shake(float(juice.shake_nova))
			"chain":
				_add_fx({"kind": "chain", "points": ev.points, "life": 0.16, "color": _wcolor("chain", pal.chain), "evo": _evo("chain") and not ev.get("tower", false)}, max_fx + 4)
				_chain_flash = 1.0
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
			"perfect_dodge":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": float(ev.radius), "life": 0.35, "color": Color("#e8fbff"), "w": 8.0}, max_fx + 6)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": float(ev.radius) * 0.6, "life": 0.28, "color": pal.ui_accent, "w": 5.0}, max_fx + 6)
				add_zoom_punch(0.06)
				add_shake(6.0)
			"overdrive":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 150.0, "life": 0.4, "color": Color("#7af0ff"), "w": 10.0}, max_fx + 6)
				add_zoom_punch(0.08)
				add_shake(9.0)
			"clutch_claim":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 260.0, "life": 0.45, "color": Color("#9be7ff"), "w": 8.0}, max_fx + 6)
				add_shake(7.0)
			"perfect_loop":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 220.0, "life": 0.45, "color": pal.ui_accent, "w": 8.0}, max_fx + 6)
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
				var t := world.terr
				var speed := maxf(float(juice.get("claim_fill_speed", 1600.0)), 1.0)
				var cap := float(juice.get("claim_fill_max_s", 0.7))
				var far := 1.0
				for i: int in ev.cells:
					far = maxf(far, t.center_of(i).distance_to(world.p_pos))
				var k_scale := minf(1.0, cap * speed / far)  # big loops: same wave, a bit faster
				for i: int in ev.cells:
					_claim_pending[i] = _view_t + t.center_of(i).distance_to(world.p_pos) * k_scale / speed
				add_shake(minf(3.0 + ev.tiles * 0.05, 12.0))
			"level_gained":
				_add_fx({"kind": "ring", "pos": world.p_pos, "r": 70.0, "life": 0.35, "color": pal.ui_accent}, max_fx + 4)
				add_zoom_punch(float(juice.get("cam_punch_level", 0.0)))
			"missile_hit_boss":
				var rc := GameData.color(world.bal.rift.boss.color)
				add_shake(14.0)
				add_zoom_punch(0.05)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 200.0, "life": 0.45, "color": Color.WHITE, "w": 9.0}, max_fx + 10)
				for n in 20:
					var a := TAU * n / 20.0
					_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(260, 480), "drag": 3.0, "color": rc if n % 2 else Color.WHITE, "r": 6.0, "life": 0.6}, max_fx + 30)
			"missile_hit_player":
				add_shake(16.0)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 120.0, "life": 0.35, "color": pal.player_hurt, "w": 8.0}, max_fx + 10)
			"missile_lock":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 60.0, "life": 0.3, "color": Color.WHITE, "w": 4.0}, max_fx + 10)
			"rift_open":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 160.0, "life": 0.6, "color": GameData.color(world.bal.rift.boss.color), "w": 8.0}, max_fx + 10)
			"rift_enter", "rift_exit":
				add_zoom_punch(0.12)
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 260.0, "life": 0.55, "color": GameData.color(world.bal.rift.boss.color), "w": 10.0}, max_fx + 10)
				_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2.ZERO, "color": Color(1, 1, 1, 0.9), "r": 70.0, "life": 0.25}, max_fx + 10)
			"power_lance":
				var pts := PackedVector2Array()
				var a: Vector2 = ev.from
				var b: Vector2 = ev.to
				var n := 14
				for k in n + 1:
					var q := float(k) / n
					var j := 0.0 if k == 0 or k == n else randf_range(-22.0, 22.0)
					pts.append(a.lerp(b, q) + (b - a).orthogonal().normalized() * j)
				_add_fx({"kind": "lance", "points": pts, "width": float(ev.width), "life": 0.35, "color": _wcolor("chain", pal.chain)}, max_fx + 10)
				add_shake(10.0)
			"power_barrage", "power_phalanx":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 140.0, "life": 0.35, "color": Color.WHITE, "w": 6.0}, max_fx + 10)
				add_shake(5.0)
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
				pass  # played by Main via evolution_moment() once the chest closes
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
			# The Lab (data/lab.json): forks and keystones.
			"lysis":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius, "life": 0.22, "color": Color("#ff6b8a"), "w": 3.0}, max_fx)
			"shield_block":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": world.p_radius * 2.4, "life": 0.3, "color": Color("#7cc6ff"), "w": 6.0}, max_fx + 4)
				for n in 8:
					var a := TAU * n / 8.0
					_add_fx({"kind": "dot", "pos": ev.pos + Vector2(cos(a), sin(a)) * world.p_radius * 1.6, "vel": Vector2(cos(a), sin(a)) * 200.0, "color": Color("#7cc6ff"), "r": 4.0, "life": 0.3}, max_fx + 12)
				add_shake(4.0)
			"second_wind":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius * 0.6, "life": 0.5, "color": Color.WHITE, "w": 8.0}, max_fx + 4)
				add_shake(14.0)
				add_zoom_punch(float(juice.get("cam_punch_elite", 0.0)))
			"ability_used":
				var acol := GameData.color(str(world.ab.get("color", "#ffffff")))
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 140.0, "life": 0.35, "color": acol, "w": 6.0}, max_fx + 4)
				add_shake(5.0)
			"engulfed":
				_add_fx({"kind": "pop", "pos": ev.pos, "color": GameData.color(str(world.ab.get("color", "#ffffff"))), "r": 12.0, "life": 0.18}, max_fx)
			"boss_slam":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius * 1.6, "life": 0.35, "color": pal.player_hurt, "w": 9.0}, max_fx + 10)
				add_shake(12.0)
			"boss_phase":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 260.0, "life": 0.5, "color": pal.player_hurt, "w": 10.0}, max_fx + 10)
				add_shake(10.0)
			"elite_brood":
				_add_fx({"kind": "pop", "pos": ev.pos, "color": elite_color, "r": 24.0, "life": 0.25}, max_fx)
			"recoil":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": ev.radius, "life": 0.25, "color": Color("#7cc6ff"), "w": 5.0}, max_fx + 4)
			"dodge":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 40.0, "life": 0.2, "color": IconArt.COLORS.dash, "w": 3.0}, max_fx + 4)
			"slipstream":
				_add_fx({"kind": "ring", "pos": ev.pos, "r": 60.0, "life": 0.25, "color": IconArt.COLORS.dash, "w": 3.0}, max_fx + 4)
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


## Per-weapon touches on the cell, one per owned weapon, each in its own
## zone so any combination stacks cleanly (1-3 cheap draws each):
##   Fever Pulse: a warm glow behind the cell that swells as it charges
##   Antibodies:  three thin arcs turning just outside the cilia
##   Pulse Bolt:  the nucleus charges up and flashes on each shot
##   Nerve Spark: a tiny zig-zag crackle on the rim every few frames
## Evolved weapons use their evolution colour and a little more intensity.
func _wcharge(id: String) -> float:
	if not world.wstats.has(id):
		return -1.0
	var cd := float(world.wstats[id].get("cooldown", 1.0))
	return clampf(1.0 - float(world.cooldowns.get(id, 0.0)) / maxf(cd, 0.01), 0.0, 1.0)


func _evo(id: String) -> bool:
	return world.evolved.has(id)


func _draw_weapon_auras_back(ci: CanvasItem, p: Vector2, r: float) -> void:
	if _seq_glow > 0.0:  # evolution sequence: the cell lights up in its colour
		var g := r * (1.6 + 1.6 * _seq_glow)
		ci.draw_texture_rect(_disc_tex, Rect2(p - Vector2(g, g), Vector2(g, g) * 2.0), false, Color(_seq_color, 0.55 * _seq_glow))
		var g2 := r * (1.2 + 0.5 * _seq_glow)
		ci.draw_texture_rect(_disc_tex, Rect2(p - Vector2(g2, g2), Vector2(g2, g2) * 2.0), false, Color(1, 1, 1, 0.5 * _seq_glow))
	var nova := _wcharge("nova")
	if nova >= 0.0:
		var c := _wcolor("nova", pal.nova)
		var gr := r * (1.25 + 0.55 * nova * nova) * (1.0 + 0.25 * _nova_flash)
		var a := (0.07 + 0.16 * nova * nova + 0.25 * _nova_flash) * (1.4 if _evo("nova") else 1.0)
		ci.draw_texture_rect(_disc_tex, Rect2(p - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(c, a))
	if world.wstats.has("orbit"):
		var c := _wcolor("orbit", pal.orbit)
		var rr := r * 1.62
		var a0 := -world.orbit_angle * 0.5
		var w := 3.0 if _evo("orbit") else 2.0
		for k in 3:
			var s := a0 + TAU * k / 3.0
			ci.draw_arc(p, rr, s, s + 0.9, 8, Color(c, 0.45), w)


func _draw_weapon_auras_front(ci: CanvasItem, p: Vector2, r: float, nc: Vector2, nr: float) -> void:
	var bolt := _wcharge("bolt")
	if bolt >= 0.0:
		var c := _wcolor("bolt", pal.bolt)
		var fire := clampf(1.0 - bolt * 6.0, 0.0, 1.0)  # just fired: flash
		var cr := nr * (0.25 + 0.3 * bolt + 0.35 * fire)
		var cp := p + nc
		ci.draw_texture_rect(_disc_tex, Rect2(cp - Vector2(cr, cr), Vector2(cr, cr) * 2.0), false, Color(c.lightened(0.4), 0.35 + 0.5 * bolt + 0.4 * fire))
	if world.wstats.has("chain") and (_chain_flash > 0.0 or fmod(_cell_t, 0.22 if _evo("chain") else 0.4) < 0.07):
		var c := _wcolor("chain", pal.chain)
		var a := _spark_ang
		var d := Vector2.from_angle(a)
		var o := d.orthogonal()
		var b := p + d * r * 1.05
		var pts := PackedVector2Array([b, b + d * 6.0 + o * 5.0, b + d * 11.0 - o * 4.0, b + d * 17.0 + o * 2.0])
		ci.draw_polyline(pts, Color(c.lightened(0.3), 0.9), 2.5 if _evo("chain") else 2.0)


## Evolution sequence driven by Main every frame (t < 0 ends it): the camera
## pushes in and the cell glows while sparks rush inward until the burst,
## then everything eases back. Main calls evolution_moment() at the burst.
func evolution_seq(t: float, s: Dictionary) -> void:
	if t < 0.0:
		_seq_zoom = 0.0
		_seq_glow = 0.0
		return
	var burst := float(s.burst)
	var dur := float(s.dur)
	_seq_color = _wcolor(s.weapon, s.color)
	var push := float(juice.get("evolution_zoom", 0.35))
	if t < burst:
		var k := t / burst
		_seq_zoom = push * (1.0 - pow(1.0 - k, 3.0))
		_seq_glow = k * k
		# Sparks rushing into the cell (a couple per frame, cheap dots).
		var p := world.p_pos
		for n in 2:
			var a := randf() * TAU
			var d := randf_range(170.0, 260.0)
			var from := p + Vector2(cos(a), sin(a)) * d
			var life := 0.22
			_add_fx({"kind": "dot", "pos": from, "vel": (p - from) / life, "color": _seq_color if n == 0 else Color.WHITE, "r": 4.0, "life": life}, int(bal.perf.max_effects) + 40)
		add_shake(1.5 * k)
	else:
		var k := clampf((t - burst) / maxf(dur - burst, 0.01), 0.0, 1.0)
		if k < 0.15:  # punch in at the burst...
			_seq_zoom = push * (1.0 + 0.4 * (1.0 - k / 0.15))
		else:  # ...then ease back out
			_seq_zoom = push * pow(1.0 - (k - 0.15) / 0.85, 2.0)
		_seq_glow = maxf(0.0, 1.0 - k * 2.5)


## The evolution moment (Main calls it at the burst of the sequence): white flash, two rings and a burst in the evolution's colour, and
## a big zoom punch.
func evolution_moment(weapon: String) -> void:
	var c := _wcolor(weapon, pal.ui_accent)
	var max_fx := int(bal.perf.max_effects) + 40
	var p := world.p_pos
	_add_fx({"kind": "dot", "pos": p, "vel": Vector2.ZERO, "color": Color(1, 1, 1, 0.9), "r": 90.0, "life": 0.25}, max_fx)
	_add_fx({"kind": "ring", "pos": p, "r": 150.0, "life": 0.45, "color": Color.WHITE, "w": 8.0}, max_fx)
	_add_fx({"kind": "ring", "pos": p, "r": 340.0, "life": 0.8, "color": c, "w": 10.0}, max_fx)
	for n in 24:
		var a := TAU * n / 24.0
		_add_fx({"kind": "dot", "pos": p, "vel": Vector2(cos(a), sin(a)) * randf_range(300, 520), "drag": 3.0, "color": c if n % 3 else Color.WHITE, "r": 6.0, "life": 0.8}, max_fx)
	add_zoom_punch(float(juice.get("cam_punch_evolution", 0.0)))
	add_shake(8.0)


## Boss Rift: the portal while it's open (a swirl whose outer ring shows the
## time left), the Seeker Phage and its telegraphs (faint tracking line ->
## bright locked lane -> streak), and the Phalanx power's orbs.
func _draw_rift(ci: CanvasItem, now: float) -> void:
	var rc := GameData.color(world.bal.rift.boss.color) if world.rift_on else Color.WHITE
	if world.rift_state == World.RIFT_OPEN:
		var p := world.rift_pos
		var left := world.rift_timer / float(world.bal.rift.open_s)
		ci.draw_texture_rect(_disc_tex, Rect2(p - Vector2(90, 90), Vector2(180, 180)), false, Color(rc, 0.18 + 0.08 * sin(now * 4.0)))
		for k in 3:
			var s := now * (2.0 + k) + TAU * k / 3.0
			ci.draw_arc(p, 34.0 + 14.0 * k, s, s + 2.2, 16, Color(rc.lightened(0.2 * k), 0.85), 5.0 - k)
		ci.draw_circle(p, 16.0 + 3.0 * sin(now * 8.0), Color(1, 1, 1, 0.9))
		ci.draw_arc(p, 82.0, -PI / 2.0, -PI / 2.0 + TAU * left, 48, Color(1, 1, 1, 0.6), 4.0)
	if world.rift_state == World.RIFT_ACTIVE and world.m_state > 0:
		var mc: Dictionary = world.bal.rift.boss.missile
		var m := world.m_pos
		match world.m_state:
			1:
				var k := clampf(world.m_t / float(mc.track_s), 0.0, 1.0)
				ci.draw_line(m, world.p_pos, Color(pal.player_hurt, 0.12 + 0.35 * k), 2.0 + 2.0 * k)
			2:
				var flash := 0.6 + 0.4 * sin(now * 40.0)
				ci.draw_line(m, m + world.m_dir * 1400.0, Color(1, 1, 1, 0.25 * flash), 30.0)
				ci.draw_line(m, m + world.m_dir * 1400.0, Color(1, 1, 1, 0.9 * flash), 4.0)
			3:
				ci.draw_line(m - world.m_dir * 90.0, m, Color(rc, 0.7), 14.0)
		ci.draw_texture_rect(_disc_tex, Rect2(m - Vector2(26, 26), Vector2(52, 52)), false, Color(rc, 0.4))
		ci.draw_circle(m, float(mc.radius), Color(1, 1, 1) if world.m_state >= 2 else rc.lightened(0.3))
	if not world.phalanx_points.is_empty():
		var oc := _wcolor("orbit", pal.orbit)
		var sz := float(world.bal.rift.powers.phalanx.size)
		for p in world.phalanx_points:
			ci.draw_circle(p, sz + 4.0, Color(oc, 0.35))
			ci.draw_circle(p, sz, Color(1, 1, 1, 0.9))


## The claim wave's front: each tile flashes white for a moment as it appears.
func _draw_claim_wave(ci: CanvasItem) -> void:
	if _claim_wave.is_empty() or world.terr == null:
		return
	var t := world.terr
	var half := Vector2.ONE * t.cell * 0.5
	for w in _claim_wave:
		var k: float = w[1] / 0.3
		ci.draw_rect(Rect2(t.center_of(w[0]) - half, half * 2.0), Color(1, 1, 1, 0.55 * (1.0 - k)))


## MEGA KILL (Main decides when): a white flash where the crowd died and a
## shockwave racing out across the screen (outline rings only: no big fills).
func mega_kill(at: Vector2) -> void:
	var max_fx := int(bal.perf.max_effects) + 10
	add_shake(float(juice.get("mega_shake", 12.0)))
	add_zoom_punch(float(juice.get("cam_punch_mega", 0.0)))
	_add_fx({"kind": "pop", "pos": at, "color": Color.WHITE, "r": 70.0, "life": 0.3}, max_fx)
	_add_fx({"kind": "ring", "pos": at, "r": float(juice.get("mega_ring_r", 700.0)), "life": 0.6, "color": Color.WHITE, "w": 14.0}, max_fx)
	_add_fx({"kind": "ring", "pos": at, "r": float(juice.get("mega_ring_r", 700.0)) * 0.6, "life": 0.5, "color": pal.ui_accent, "w": 8.0}, max_fx)


## Short zoom-in for a big moment (decays at juice.cam_punch_decay per s).
func add_zoom_punch(amount: float) -> void:
	_zoom_punch = maxf(_zoom_punch, amount * float(juice.get("cam_punch_mult", 1.0)))


## Weapon colour, switched to its evolution colour once evolved.
func _wcolor(weapon: String, base: Color) -> Color:
	var evolved := world != null and world.evolved.has(weapon)
	return CosmeticArt.weapon_color(_wstyle, weapon, base, evolved, evo_colors.get(weapon))


## A kill under a non-default pop style (Cosmetics): the style's burst, ring
## and splat; the killing-blow mark and gold sparkle stay the same.
func _styled_pop(ev: Dictionary, c: Color, max_fx: int) -> void:
	var sp := float(juice.get("kill_burst_speed", 1.0))
	var k := 0
	for f in CosmeticArt.pop_burst(_pop, ev.pos, ev.radius, c, sp):
		_add_fx(f, max_fx + (10 if k == 0 or f.kind == "kring" else 0))
		k += 1
	_mark_killing_blow(int(ev.get("uid", -1)))
	var sc: Variant = CosmeticArt.splat_color(_pop, c)
	if sc != null:
		_add_splat(ev.pos, ev.radius * (3.4 if ev.elite else 2.6) * float(_pop.get("splat_scale", 1.0)), sc)
	if ev.get("gilded", false):
		for n in 6:
			var a := -PI / 2.0 + randf_range(-1.2, 1.2)
			_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(140, 260), "grav": 520.0, "color": pal.ui_accent, "r": 4.0, "life": 0.45}, max_fx + 20)


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
	_view_t += delta
	var wi := 0
	while wi < _claim_wave.size():
		_claim_wave[wi][1] += delta
		if _claim_wave[wi][1] >= 0.3:
			_claim_wave.remove_at(wi)
		else:
			wi += 1
	_nova_flash = maxf(0.0, _nova_flash - delta * 4.0)
	_chain_flash = maxf(0.0, _chain_flash - delta * 8.0)
	_spark_t -= delta
	if _spark_t <= 0.0:
		_spark_t = 0.11
		_spark_ang = randf() * TAU
	_update_cell_pose(delta)
	_core_flash = maxf(0.0, _core_flash - delta)
	if world.p_dash_t > 0.0 or world.overdrive_t > 0.0:  # dash trail (Cosmetics: afterimage and/or particles); Overdrive keeps it on
		var bc := CosmeticArt.body_color(_skin, pal.player, _cell_t)
		if _trail.is_empty() or _trail.get("afterimage", false):
			_add_fx({"kind": "dot", "pos": world.p_pos, "vel": Vector2.ZERO, "color": Color(bc, 0.6), "r": world.p_radius, "life": 0.22}, int(bal.perf.max_effects) + 8)
		for f in CosmeticArt.trail_burst(_trail, world.p_pos, bc, _cell_t, delta):
			_add_fx(f, int(bal.perf.max_effects) + 30)
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
	cam_zoom = _zoom_crowd * (1.0 + _zoom_punch) * (1.0 + _seq_zoom)
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
	if world.rift_state == World.RIFT_ACTIVE:
		# The arena: dark outside, a glowing pink membrane.
		var ar := float(world.bal.rift.arena_radius)
		var rc := GameData.color(world.bal.rift.boss.color)
		draw_arc(World.RIFT_CENTER, ar + 700.0, 0, TAU, 96, Color(0.04, 0.02, 0.08, 0.92), 1400.0)
		draw_arc(World.RIFT_CENTER, ar, 0, TAU, 128, Color(rc, 0.5 + 0.2 * sin(_view_t * 3.0)), 12.0)
		draw_arc(World.RIFT_CENTER, ar - 18.0, 0, TAU, 128, Color(rc, 0.15), 22.0)
	_draw_glows()


## Soft glows on the floor under the player, elites and the boss (drawn by
## this node, so under the sprite batches). A handful of quads per frame.
func _draw_glows() -> void:
	if world.p_down <= 0.0:
		var pr := world.p_radius * 3.2
		draw_texture_rect(_glow_tex, Rect2(world.p_pos - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false, Color(pal.player_nucleus, 0.22))
	for i in world.e_pos.size():
		if world.e_elite[i] == 1 and world.e_team[i] == 0:
			var r := world.e_rad[i] * 2.6
			draw_texture_rect(_glow_tex, Rect2(world.e_pos[i] - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(elite_color, 0.3))
	var bi := world.boss_index
	if bi >= 0 and bi < world.e_pos.size():
		var r := world.e_rad[bi] * 2.4
		draw_texture_rect(_glow_tex, Rect2(world.e_pos[bi] - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(pal.player_hurt, 0.35))


func _draw_territory() -> void:
	var t := world.terr
	var changed := false
	if not t.dirty.is_empty():
		for i in t.dirty:
			var owned := t.tiles[i] == Territory.OWNED
			if owned and _claim_pending.has(i):
				continue  # shown when the claim wave reaches it
			_claim_pending.erase(i)
			_terr_img.set_pixel(i % t.n, i / t.n, _land_color if owned else Color(0, 0, 0, 0))
		t.dirty.clear()
		changed = true
	if not _claim_pending.is_empty():
		for i: int in _claim_pending.keys():
			if _claim_pending[i] > _view_t:
				continue
			_claim_pending.erase(i)
			if t.tiles[i] == Territory.OWNED:
				_terr_img.set_pixel(i % t.n, i / t.n, _land_color)
				if _claim_wave.size() < 400:
					_claim_wave.append([i, 0.0])
				changed = true
	if changed:
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
	# Hit squash: a germ being knocked back squashes along the push (axis-
	# aligned, so it stays one rect) and springs back as the knock decays.
	var sq_max := float(juice.get("hit_squash", 0.0))
	var sq_ref := 1.0 / maxf(float(juice.get("hit_squash_ref", 350.0)), 1.0)
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
		if world.e_uid[i] == world.rift_uid:
			c = GameData.color(world.bal.rift.boss.color)  # the Phage Carrier
			if world.rb_stun > 0.0:
				c = c.lerp(Color.WHITE, 0.4 + 0.3 * sin(_view_t * 30.0))
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
		elif world.e_stun[i] > 0.0:
			c = Color("#bdf3ff").lerp(c, 0.15 + 0.15 * sin(_view_t * 18.0))  # Clutch Claim stun: icy flicker
		elif world.e_gild[i] == 1:
			c = c.lerp(pal.ui_accent, 0.7)  # coated in gold by an Outbreak
		elif world.e_plague[i] > 0.0:
			c = c.lerp(pal.outbreak, 0.7)  # infected by the Plague Trail
		elif world.def_on and world.e_slow[i] > 0.0:
			c = c.lerp(pal.nova, 0.5)  # Fever Node slow
		var pulse := 1.0 + pulse_k * maxf(world.e_flash[i], 0.0)  # pops a little when hit
		var asp := 1.0
		var kn := world.e_knock[i]
		if sq_max > 0.0 and kn != Vector2.ZERO:
			var m := minf(kn.length() * sq_ref, 1.0) * sq_max
			var kl := absf(kn.x) + absf(kn.y)
			asp = 1.0 - m * (absf(kn.x) - absf(kn.y)) / kl  # pushed sideways = narrower and taller
		_enemies.add(p, r * _blob_scale * pulse, c, (pp - p).angle(), asp)
	_enemies.commit()
	_allies.commit()


func _fill_bullets() -> void:
	_bullets.begin()
	_bolt_heads.begin()
	var bc: Color = _wcolor("bolt", pal.bolt)
	var trail := Color(bc, 0.35)
	var evo := _evo("bolt")
	var glow := Color(bc, 0.22)
	var faint := Color(bc, 0.15)
	var white := Color(1, 1, 1, 0.9)
	for i in world.b_pos.size():
		var p := world.b_pos[i]
		var r := world.b_rad[i]
		var back := world.b_vel[i].normalized() * r
		if evo and world.b_ally[i] == 0:
			# Evolved: a soft glow, a longer comet tail and a white-hot core.
			_bullets.add(p, r * 4.2, glow)
			_bullets.add(p - back * 3.2, r * 1.6, faint)
		_bullets.add(p - back * 1.6, r * 2.2, trail)
		if _shaped and world.b_ally[i] == 0:  # weapon style: star/heart/... heads
			_bolt_heads.add(p, r * 3.0, bc)
		else:
			_bullets.add(p, r * 2.0, bc)
		if evo and world.b_ally[i] == 0:
			_bullets.add(p, r * 0.9, white)
	_bullets.commit()
	_bolt_heads.commit()


func _fill_dots() -> void:
	_dots.begin()
	for f in fx:
		var k: float = f.t / f.life
		if f.kind == "dot":
			_dots.add(f.pos, f.r * 2.0 * (1.0 - k), Color(f.color, 1.0 - k))
		elif f.kind == "pop":
			_dots.add(f.pos, f.r * 2.0 * (1.0 + k), Color(f.color, 0.45 * (1.0 - k)))
	_dots.commit()
	_pops.begin()
	for f in fx:
		if f.kind == "pdot":
			var lk := CosmeticArt.pdot_look(f)
			_pops.add(f.pos, lk[0], lk[1], 0.0, lk[2])
	_pops.commit()
	_trails.begin()
	for f in fx:
		if f.kind == "tdot":
			var lk := CosmeticArt.pdot_look(f)
			_trails.add(f.pos, lk[0], lk[1])
	_trails.commit()
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
	var orbit_evo := _evo("orbit")
	var orb_tex := CosmeticArt.tex(CosmeticArt.weapon_shape(_wstyle)) if _shaped else null
	for p in world.orbit_points:
		if orbit_evo:  # evolved: a wide soft halo and a white core
			ci.draw_texture_rect(_disc_tex, Rect2(p - Vector2.ONE * (world.orbit_size + 12.0), Vector2.ONE * (world.orbit_size + 12.0) * 2.0), false, Color(oc, 0.3))
		ci.draw_circle(p, world.orbit_size + 3.0, Color(oc, 0.35))
		if orb_tex != null:  # weapon style shape
			var os := world.orbit_size * 1.5
			ci.draw_texture_rect(orb_tex, Rect2(p - Vector2(os, os), Vector2(os, os) * 2.0), false, oc)
		else:
			ci.draw_circle(p, world.orbit_size, oc)
		if orbit_evo:
			ci.draw_circle(p, world.orbit_size * 0.45, Color(1, 1, 1, 0.85))
	_draw_rift(ci, now)
	_draw_threats(ci)
	_draw_clone(ci)
	_draw_player(ci)
	_draw_claim_wave(ci)
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
				ci.draw_arc(f.pos, f.r * (0.4 + 0.6 * k), 0, TAU, 40, Color(c, 0.9 * (1.0 - k)), float(f.get("w", 5.0)))
			"chain":
				var pts: PackedVector2Array = f.points
				var c: Color = f.get("color", pal.chain)
				for j in pts.size() - 1:
					var a := pts[j]
					var b := pts[j + 1]
					var mid := (a + b) / 2.0 + (b - a).orthogonal().normalized() * randf_range(-14, 14)
					var seg := PackedVector2Array([a, mid, b])
					if f.get("evo", false):  # evolved: wide glow + white-hot core
						ci.draw_polyline(seg, Color(c, 0.3 * (1.0 - k)), 12.0)
						ci.draw_polyline(seg, Color(c, 1.0 - k), 5.0)
						ci.draw_polyline(seg, Color(1, 1, 1, 1.0 - k), 2.0)
					else:
						ci.draw_polyline(seg, Color(c, 1.0 - k), 4.0)
			"lance":
				var lp: PackedVector2Array = f.points
				var lc: Color = f.color
				ci.draw_polyline(lp, Color(lc, 0.3 * (1.0 - k)), float(f.width) * 2.2)
				ci.draw_polyline(lp, Color(lc, 1.0 - k), float(f.width) * 0.6)
				ci.draw_polyline(lp, Color(1, 1, 1, 1.0 - k), 4.0)
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
		var crit_k := float(juice.get("num_crit_scale", 0.0))
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
				if f.crit:  # Lab crit: a big gold number
					h *= 1.0 + crit_k
					col = gold
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
	var body: Color = CosmeticArt.body_color(_skin, pal.player, _cell_t)
	if _hurt_t > 0.0 and fmod(_hurt_t, 0.12) < 0.06:
		body = pal.player_hurt
	if world.ability == "cloak" and world.ab_t > 0.0:
		body = Color(body, 0.3 + 0.08 * sin(_cell_t * 9.0))  # Lab ability: Cloak
	var breathe := float(juice.get("cell_breathe", 0.03)) * float(_skin.get("breathe", 1.0)) * sin(_cell_t * 2.4) * (1.0 - clampf(_squash * 8.0, 0.0, 1.0))
	var squish := 0.18 * _hurt_squish
	var sx := 1.0 + _squash + breathe - squish
	var sy := 1.0 - _squash * 0.6 + breathe * 0.5 + squish * 0.6
	# Cilia: short hairs around the membrane that wave faster with speed.
	var speed_k := clampf(world.p_vel.length() / float(bal.player.speed), 0.0, 1.0)
	CosmeticArt.draw_glow(ci, _glow_tex, p, r, _skin, _cell_t)
	_draw_weapon_auras_back(ci, p, r)
	CosmeticArt.draw_glitch(ci, _cell_tex, p, r / ShapeTextures.CELL_BODY, _skin, _cell_t)
	ci.draw_set_transform(p, _move_ang, Vector2(sx, sy))
	CosmeticArt.draw_cilia(ci, r, _skin, body, _cell_t, speed_k, int(juice.get("cilia", 12)))
	if world.perfect_t > 0.0:  # Perfect Dodge buff: a gold halo while it lasts
		var pr := r * (1.7 + 0.12 * sin(_cell_t * 12.0))
		ci.draw_texture_rect(_disc_tex, Rect2(-pr, -pr, pr * 2.0, pr * 2.0), false, Color(pal.ui_accent, 0.22 + 0.1 * minf(world.perfect_t, 1.0)))
	if world.overdrive_t > 0.0:  # Overdrive: a bright cyan core glow
		var orr := r * (2.0 + 0.2 * sin(_cell_t * 30.0))
		ci.draw_texture_rect(_disc_tex, Rect2(-orr, -orr, orr * 2.0, orr * 2.0), false, Color("#7af0ff", 0.35))
	if world.outbreak_t > 0.0:
		# Frenzy aura: a pulsing glow behind the cell.
		var gr := r * (1.9 + 0.15 * sin(_cell_t * 14.0))
		ci.draw_texture_rect(_disc_tex, Rect2(-gr, -gr, gr * 2.0, gr * 2.0), false, Color(pal.outbreak, 0.35))
	var q := r / ShapeTextures.CELL_BODY
	ci.draw_texture_rect(_cell_tex, Rect2(-q, -q, q * 2.0, q * 2.0), false, body)
	CosmeticArt.draw_pattern(ci, _disc_tex, r, _skin, _cell_t)
	if float(world.stats.get("shield", 0.0)) > 0.0 and world.shield_cd <= 0.0:
		ci.draw_arc(Vector2.ZERO, r * 1.45, 0, TAU, 28, Color("#7cc6ff", 0.55 + 0.2 * sin(_cell_t * 3.0)), 3.0)  # Lab: Biofilm is up
	if world.slip_t > 0.0:
		ci.draw_arc(Vector2.ZERO, r * 1.3, 0, TAU, 24, Color(IconArt.COLORS.dash, 0.6), 2.0)  # Lab: Slipstream
	ci.draw_set_transform(p, 0.0, Vector2(sx * 0.5 + 0.5, sy * 0.5 + 0.5))
	# Nucleus leads the turn, with a small highlight.
	var nc := Vector2.from_angle(_face) * r * 0.28 + CosmeticArt.nucleus_jitter(_skin, _cell_t, r)
	var nr := r * 0.44
	ci.draw_texture_rect(_disc_tex, Rect2(nc - Vector2(nr, nr), Vector2(nr, nr) * 2.0), false, CosmeticArt.nucleus_color(_skin, pal.player_nucleus))
	var hl := nc + Vector2(-0.35, -0.35) * nr
	ci.draw_texture_rect(_disc_tex, Rect2(hl - Vector2(nr, nr) * 0.3, Vector2(nr, nr) * 0.6), false, Color(1, 1, 1, 0.55))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_weapon_auras_front(ci, p, r, nc, nr)
	if world.p_hp < world.p_max_hp:
		var w := 48.0
		var pos := p + Vector2(-w / 2.0, r + 10.0)
		ci.draw_rect(Rect2(pos, Vector2(w, 6)), Color(0, 0, 0, 0.55))
		ci.draw_rect(Rect2(pos, Vector2(w * world.p_hp / world.p_max_hp, 6)), pal.hp_bar)


## Elite and boss telegraphs (state read from World each frame): a Rammer's
## charge lane, a Spiker's windup ring, a Magnet's pull radius, and the
## Mother Cell's slam target filling up.
func _draw_threats(ci: CanvasItem) -> void:
	var t := _cell_t
	var red: Color = pal.player_hurt
	var aff: Dictionary = world.elite_cfg.get("affixes", {})
	for i in world.e_pos.size():
		if world.e_affix[i] == World.AFFIX_NONE:
			continue
		var p := world.e_pos[i]
		var r := world.e_rad[i]
		match world.affix_id(i):
			"charge":
				if world.e_aphase[i] == 1:
					var c: Dictionary = aff.charge
					var k := 1.0 - world.e_atimer[i] / maxf(float(c.windup_s), 0.01)
					var len := float(c.dash_speed) * float(c.dash_s)
					var end := p + world.e_adir[i] * len
					ci.draw_line(p, end, Color(red, 0.18 + 0.25 * k), r * 1.6)
					ci.draw_line(p, p + world.e_adir[i] * len * k, Color(red, 0.55), 4.0)
			"volley":
				if world.e_aphase[i] == 1:
					var k := 1.0 - world.e_atimer[i] / maxf(float(aff.volley.windup_s), 0.01)
					ci.draw_arc(p, r * (2.2 - 0.9 * k), 0, TAU, 28, Color(1.0, 0.85, 0.3, 0.4 + 0.5 * k), 4.0)
			"magnet":
				ci.draw_arc(p, float(aff.magnet.radius), 0, TAU, 48, Color(0.75, 0.55, 1.0, 0.22 + 0.08 * sin(t * 4.0)), 4.0)
	# Elite health bars (the boss has its own bar and the HUD one).
	for i in world.e_pos.size():
		if world.e_elite[i] != 1 or world.e_team[i] != 0:
			continue
		var p := world.e_pos[i]
		var r := world.e_rad[i]
		var f := clampf(world.e_hp[i] / maxf(world.e_maxhp[i], 1.0), 0.0, 1.0)
		var bw := maxf(r * 2.0, 44.0)
		var at := p + Vector2(-bw / 2.0, -r - 16.0)
		ci.draw_rect(Rect2(at - Vector2(2, 2), Vector2(bw + 4, 10)), Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(at, Vector2(bw * f, 6)), elite_color)
	if world.boss_slam == 1:
		var d := world.boss_def
		var k := 1.0 - world.boss_slam_t / maxf(float(d.slam_windup_s), 0.01)
		var sr := float(d.slam_radius)
		ci.draw_circle(world.boss_slam_at, sr * k, Color(red, 0.22))
		ci.draw_arc(world.boss_slam_at, sr, 0, TAU, 40, Color(red, 0.5 + 0.4 * sin(t * 18.0)), 4.0)
	var bi := world.boss_index
	if bi >= 0 and bi < world.e_pos.size() and world.boss_def.has("pull_radius"):
		ci.draw_arc(world.e_pos[bi], float(world.boss_def.pull_radius), 0, TAU, 64, Color(red, 0.08 + 0.04 * sin(t * 3.0)), 3.0)


## Mitosis clone (Lab ability): a paler copy of the cell beside you.
func _draw_clone(ci: CanvasItem) -> void:
	if world.ability != "mitosis" or world.ab_t <= 0.0:
		return
	var r := world.p_radius * 0.9
	var q := r / ShapeTextures.CELL_BODY
	var fade := clampf(world.ab_t / 0.4, 0.0, 1.0)
	var col := GameData.color(str(world.ab.get("color", "#7cff9b")))
	ci.draw_texture_rect(_disc_tex, Rect2(world.clone_pos - Vector2(r, r) * 1.5, Vector2(r, r) * 3.0), false, Color(col, 0.18 * fade))
	ci.draw_texture_rect(_cell_tex, Rect2(world.clone_pos - Vector2(q, q), Vector2(q, q) * 2.0), false, Color(pal.player.lerp(col, 0.35), 0.75 * fade))
	ci.draw_circle(world.clone_pos, r * 0.3, Color(col, 0.9 * fade))


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
			if ev.get("crit", false):
				old.crit = true
			old.frac += float(ev.get("frac", 0.0))
			old.t = 0.0
			old.vel = Vector2(old.vel.x * 0.5, -float(juice.get("num_rise", 0.0)) * 0.6)  # hop again
		elif _damage_numbers < int(bal.perf.max_damage_numbers) and fx.size() < max_fx:  # a refused number must not be registered
			_damage_numbers += 1
			# Numbers hop out sideways and fall back under gravity (instead of
			# a straight rise), so a burst of hits sprays instead of stacking.
			var spread := float(juice.get("num_spread", 0.0))
			var f := {"kind": "num", "pos": ev.pos + Vector2(randf_range(-8, 8), -14), "text": str(roundi(ev.amount)),
				"value": roundi(ev.amount), "frac": float(ev.get("frac", 0.0)), "uid": uid, "life": float(juice.get("num_life_s", 0.55)),
				"vel": Vector2(randf_range(-spread, spread), -float(juice.get("num_rise", 0.0))), "grav": float(juice.get("num_grav", 0.0)), "killed": false,
				"crit": ev.get("crit", false)}
			_add_fx(f, max_fx)
			_num_by_uid[uid] = f
	if ev.get("crit", false):  # Lab: Toxic Burst big hit
		for n in 3:
			var a := randf() * TAU
			_add_fx({"kind": "dot", "pos": ev.pos, "vel": Vector2(cos(a), sin(a)) * randf_range(200, 340), "color": Color("#ff6b8a"), "r": 3.5, "life": 0.2}, max_fx)
	if _sparks_left > 0:
		_sparks_left -= 1
		# Sparks fly on along the shot (a cone around the push), or anywhere.
		var dir: Vector2 = ev.get("dir", Vector2.ZERO)
		for n in 2:
			var a := dir.angle() + randf_range(-0.7, 0.7) if dir != Vector2.ZERO else randf() * TAU
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
