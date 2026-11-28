extends SceneTree
## Trailer footage: plays one scripted "shot" of the real game (Main, real
## rendering, a bot or a scripted path at the controls, invincible) at a fixed
## 60 fps and saves the frames of its recording window as PNGs.
##
##   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##     --resolution 1920x1080 --fixed-fps 60 -s res://tools/footage/showcase.gd -- \
##     --shot horde --out /tmp/shots/horde [--crazygames] [--seed 11] [--every 1]
##
## Landscape footage (16:9) uses --crazygames (the desktop layout); portrait
## (2:3, e.g. 1080x1620) leaves it out. --every N keeps every Nth frame (quick
## previews). Prints "SHOT <name> frames N" when done. Visual only: nothing
## here changes the game, and the save it touches is the sandbox's.

const FPS := 60.0

var main: Node
var f := 0
var out := ""
var shot := "horde"
var seed_value := 11
var every := 1
var cfg := {}
var t := 0.0  # seconds since the shot started (after setup)
var saved := 0
var started := false
var bot: BalanceBot
var _fired := {}
var _path_i := 0
var _zoom0 := 1.0  # the layout's own camera zoom (landscape), before cfg.zoom


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		match a[i]:
			"--shot": shot = a[i + 1]
			"--out": out = a[i + 1]
			"--seed": seed_value = int(a[i + 1])
			"--every": every = maxi(1, int(a[i + 1]))
	DirAccess.make_dir_recursive_absolute(out)
	cfg = _shot_cfg(shot)
	main = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	root.add_child(main)


func _process(_delta: float) -> bool:
	f += 1
	if f == 4:
		_prepare_profile()
	if f == 12:
		_setup()
		started = true
	if not started:
		return false
	t += 1.0 / FPS
	_direct()
	if cfg.get("hide_hud", false):
		main.hud.visible = false
		main.pause_btn.visible = false
	var rec_from := float(cfg.warm)
	if t >= rec_from:
		var k := int(round((t - rec_from) * FPS))
		if k % every == 0:
			var img := root.get_texture().get_image()
			img.save_png("%s/%05d.png" % [out, saved])
			saved += 1
	if t >= float(cfg.warm) + float(cfg.dur):
		print("SHOT %s frames %d" % [shot, saved])
		return true
	return false


# ------------------------------------------------------------ shot list

func _shot_cfg(name: String) -> Dictionary:
	var strong := {"bolt": 5, "multishot": 2, "orbit": 5, "vitality": 5, "nova": 5, "regen": 3, "chain": 5, "haste": 5, "might": 5, "magnet": 3}
	match name:
		"fever":  # Phase S3/S5 review: Fever Spike on its own in a busy dish (bolt kept low so the pulses read)
			return {"mode": "classic", "time": 230.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 2, "nova": 5, "regen": 5, "might": 3}, "evolve": ["nova"], "warm": 6.0, "dur": 4.0}
		"neural":  # Phase S4/S5 review: Neural Storm on its own
			return {"mode": "classic", "time": 230.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 2, "chain": 5, "haste": 5, "might": 3}, "evolve": ["chain"], "warm": 6.0, "dur": 4.0}
		"storm":  # Phase S5 review: Cytotoxic Storm on its own
			return {"mode": "classic", "time": 230.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 5, "multishot": 5, "might": 3}, "evolve": ["bolt"], "warm": 6.0, "dur": 4.0}
		"wall":  # Phase S5 review: Immune Wall on its own
			return {"mode": "classic", "time": 230.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 2, "orbit": 5, "vitality": 5, "might": 3}, "evolve": ["orbit"], "warm": 6.0, "dur": 4.0}
		"horde":  # final minute, everything evolved, the bot kiting through a full dish
			return {"mode": "classic", "time": 246.0, "vir": 4, "shop": 0.5, "loadout": strong, "evolve": ["bolt", "orbit", "nova", "chain"], "warm": 8.0, "dur": 12.0}
		"outbreak":  # a ring of germs closes in, then OUTBREAK: frenzy + gold blast (+ MEGA KILL)
			return {"mode": "classic", "time": 244.0, "vir": 4, "shop": 0.5, "loadout": {"bolt": 5, "multishot": 2, "nova": 5, "regen": 3, "orbit": 4, "might": 4}, "evolve": ["nova", "bolt"], "warm": 7.0, "dur": 6.5,
				"look": {"pop": "jackpot"}}
		"evolution":  # a chest that evolves Pulse Bolt into Cytotoxic Storm, mid-fight
			return {"mode": "classic", "time": 236.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 5, "multishot": 2, "nova": 4, "orbit": 3, "might": 3}, "evolve": [], "warm": 8.0, "dur": 9.0}
		"dash":  # four quick dashes through the crowd: Perfect Dodge + Overdrive
			return {"mode": "classic", "time": 250.0, "vir": 4, "shop": 0.5, "loadout": {"bolt": 5, "orbit": 4, "nova": 4, "chain": 3, "afterimage": 3, "lunge": 3, "flagella2": 2, "might": 3}, "evolve": [], "warm": 8.0, "dur": 6.0,
				"look": {"trail": "comet", "skin": "galaxy"}}
		"swarm":  # an ally army on Hunt
			return {"mode": "swarm", "time": 230.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 4, "nova": 3, "viral": 5, "hive": 5, "incubate": 3, "might": 3}, "evolve": [], "warm": 25.0, "dur": 8.0}
		"infection":  # leave your land, loop round, claim a big slice of the dish
			return {"mode": "infection", "time": 150.0, "vir": 3, "shop": 0.5, "loadout": {"bolt": 4, "orbit": 3, "nova": 3, "swift": 4}, "evolve": [], "warm": 6.0, "dur": 9.0}
		"boss":  # the Mother Cell: slam telegraphs, phases, the bot dodging
			return {"mode": "classic", "time": 226.0, "vir": 3, "shop": 0.5, "loadout": strong, "evolve": ["bolt", "nova"], "warm": 5.0, "dur": 12.0}
		"cover":  # key art: no HUD, camera pushed in, everything evolved, a ring of germs bursting
			return {"mode": "classic", "time": 200.0, "vir": 4, "shop": 0.5, "loadout": strong, "evolve": ["bolt", "orbit", "nova", "chain"], "warm": 8.0, "dur": 2.0,
				"hide_hud": true, "zoom": 1.45, "no_numbers": true}
		"nucleus":  # towers holding the line on a late wave
			return {"mode": "nucleus", "time": 0.0, "vir": 2, "shop": 0.5, "loadout": {"bolt": 4, "nova": 3, "orbit": 3}, "evolve": [], "warm": 12.0, "dur": 8.0, "wave": 8}
	return {"mode": "classic", "time": 120.0, "loadout": {}, "evolve": [], "warm": 3.0, "dur": 5.0}


# ---------------------------------------------------------------- setup

func _prepare_profile() -> void:
	var sv := root.get_node("Save")
	sv.profile.onboarding["all"] = true
	sv.profile.onboarding["prologue_done"] = true
	var meta := {}
	for m in main.data.meta:  # a part-upgraded shop (cfg.shop: share of every tier)
		meta[m.id] = int(round((m.costs as Array).size() * float(cfg.get("shop", 0.5))))
	sv.meta_levels = meta
	sv.mode = str(cfg.mode)
	sv.profile.settings["dev_all_virulence"] = true
	sv.profile.set_virulence(str(cfg.mode), int(cfg.get("vir", 1)))
	sv.profile.settings["dev_all_cosmetics"] = true
	sv.profile.settings["cosmetics"] = {}
	var look: Dictionary = cfg.get("look", {})
	for cat in look:
		Cosmetics.equip(main.data.cosmetics, sv.profile, str(look[cat]))


func _setup() -> void:
	seed(seed_value)  # Main seeds its World from randi()
	main._start_run(false)
	var w: World = main.world
	w.bal.debug["invincible"] = true
	w.time = float(cfg.time)
	for id in cfg.loadout:
		w.owned[id] = int(cfg.loadout[id])
	for wid in cfg.evolve:
		w.evolved[wid] = w.evolution_defs[wid].id
	w._recompute_stats()
	w.p_hp = w.p_max_hp
	main.hud.show_perf = false  # the playtest FPS readout never goes in footage
	_zoom0 = main.view.base_zoom
	if cfg.get("no_numbers", false):
		main.view.bal.perf["max_damage_numbers"] = 0  # clean key art
	bot = BalanceBot.new(seed_value)
	main.autopilot = _steer
	main._hints = []
	main._hint_queue = []
	match shot:
		"swarm":
			w.set_ally_order(0)  # Guard: a visible bodyguard ring
		"nucleus":
			_build_towers(w)
			w.wave = int(cfg.get("wave", 0))
			w.wave_t = 0.5


func _build_towers(w: World) -> void:
	for k in w.pad_pos.size():
		w.pad_tower[k] = k % w.tower_defs.size()
		w.pad_level[k] = (w.tower_defs[w.pad_tower[k]].levels as Array).size()
		w.towers_built += 1


# ---------------------------------------------------------------- driving

func _steer(w: World) -> Vector2:
	var warm := float(cfg.warm)
	match shot:
		"infection":
			if t >= warm - 0.3:
				return _follow_loop(w)
		"cover":
			return Vector2.ZERO
		"outbreak":
			if t >= warm and t < warm + 3.5:
				return Vector2.ZERO  # hold still while the ring closes in and bursts
	return bot.move(w)


## Infection: out of the start land, round a wide loop, back in to claim.
func _follow_loop(w: World) -> Vector2:
	var pts := [Vector2(0, -80), Vector2(380, -260), Vector2(560, 60), Vector2(420, 420), Vector2(60, 520), Vector2(-260, 360), Vector2(-120, 60), Vector2(0, 0)]
	if _path_i >= pts.size():
		return bot.move(w)
	var target: Vector2 = pts[_path_i]
	if w.p_pos.distance_to(target) < 30.0:
		_path_i += 1
	return (target - w.p_pos).normalized()


func _once(key: String, at: float) -> bool:
	if _fired.has(key) or t < at:
		return false
	_fired[key] = true
	return true


func _direct() -> void:
	var w: World = main.world
	if w == null:
		return
	# Level-ups and chests resolve silently (the evolution shot keeps its chest).
	if w.pending_levelups > 0 and w.state == "playing" and main.screen == "playing":
		w.open_banked()
		while w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
	if main.screen == "chest" and shot != "evolution":
		main._close_chest()
	w.p_hp = w.p_max_hp
	var warm := float(cfg.warm)
	if cfg.has("zoom"):
		main.view.base_zoom = _zoom0 * float(cfg.zoom)
	match shot:
		"outbreak":
			if _once("ring", warm + 0.2):
				for k in 96:
					var a := TAU * k / 96.0
					w._add_enemy("swarm" if k % 4 else "runner", w.p_pos + Vector2(cos(a), sin(a)) * (390.0 + 40.0 * (k % 3)))
			if _once("fill", warm + 0.6):
				w.outbreak = 1.0
			if _once("go", warm + 1.6):
				main._trigger_outbreak()
		"cover":
			if _once("ring", warm - 0.5):
				for k in 84:
					var a := TAU * k / 84.0
					w._add_enemy(["swarm", "runner", "grunt", "spitter"][k % 4], w.p_pos + Vector2(cos(a), sin(a)) * (380.0 + 36.0 * (k % 3)))
		"evolution":
			if _once("chest", warm + 0.8):
				w._open_chest(1)
			if main.screen == "chest" and t > warm + 3.0:
				main._close_chest()
		"dash":
			for k in 4:
				if _once("dash%d" % k, warm + 0.8 + k * 0.5):
					w.dash()
