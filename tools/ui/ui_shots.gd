extends SceneTree
## Screenshots of every menu screen and overlay, to check layouts at a window
## size (the CrazyGames landscape layout in particular). Real GL under xvfb:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 -s res://tools/ui/ui_shots.gd -- --crazygames --out /tmp/shots
## Prints one line per screen with the overlay column's height vs the canvas
## ("OVERFLOW" when it doesn't fit). Uses the local save (onboarding.all is
## set in memory so every tile is open).

var main: Node
var f := 0
var out := "user://ui_shots"
var steps: Array = []
var _i := 0
var _wait := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--out")
	if at >= 0 and at + 1 < args.size():
		out = args[at + 1]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	root.add_child(main)
	steps = [
		["menu", func() -> void: main._show_menu()],
		["shop", func() -> void: main._show_shop()],
		["lab", func() -> void: main._show_lab()],
		["abilities", func() -> void: main._show_abilities()],
		["style", func() -> void: main._show_style()],
		["profile", func() -> void: main._show_profile()],
		["missions", func() -> void: main._show_missions()],
		["settings", func() -> void: main._show_settings()],
		["modes", func() -> void:
			main._show_menu()
			main._open_mode_picker()],
		["run", func() -> void:
			if main._mode_pick != null:
				main._mode_pick[0].visible = false
			main._start_run(false)],
		["levelup", func() -> void:
			main.world.pending_levelups = maxi(main.world.pending_levelups, 1)
			main._open_banked()],
		["pause", func() -> void:
			main._hide_all()
			main._set_screen("playing")
			main._pause_run()],
		["build", func() -> void:
			main._hide_all()
			main._set_screen("playing")
			main._show_build()],
		["results", func() -> void:
			main._hide_all()
			main._show_results(false)],
	]


func _process(_delta: float) -> bool:
	f += 1
	if f == 3:
		var sv := root.get_node("Save")
		sv.profile.onboarding["all"] = true
		sv.profile.onboarding["prologue_done"] = true
	if f < 10:
		return false
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_shot(steps[_i][0])
			_i += 1
		return false
	if _i >= steps.size():
		return true
	steps[_i][1].call()
	_wait = 45
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	var vp: Vector2 = root.get_visible_rect().size
	var worst := 0.0
	for o in [main._menu, main._levelup, main._dead, main._results, main._pause, main._chest, main._victory, main._build]:
		if o[0].visible:
			worst = maxf(worst, o[1].get_combined_minimum_size().y)
			var c: Control = o[1].get_parent()
			print("   col pos %s size %s  center scale %.2f size %s" % [o[1].position, o[1].size, c.scale.x, c.size])
	print("%-10s canvas %dx%d  column %d  %s" % [name, vp.x, vp.y, worst, "OVERFLOW" if worst > vp.y else "ok"])
