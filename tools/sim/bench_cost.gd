extends SceneTree
## Phase S1 cost report: runs the benchmark fight and prints, per frame,
## where the work goes, in numbers that do not depend on this machine's
## (software) renderer:
##   - our code (sim / view / HUD ms, Prof sections), sounds started per second
##   - draw calls, canvas items, primitives
##   - FILL: screen pixels covered by each layer's quads (what a real GPU pays;
##     transparent quad corners count too), as a multiple of the screen area.
## Run with a fixed frame step so every run plays the identical fight:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --fixed-fps 60 -s res://tools/sim/bench_cost.gd -- --crazygames
## Options after --: --frames N (measured frames, default 1200).

var main: Node
var f := 0
var n := 0
var frames := 1200
var wv: WorldView
var hud: Control
var fill := {}  # layer -> summed pixels
var dc := 0.0
var objs := 0.0
var prims := 0.0
var sim := 0.0
var view := 0.0
var hudms := 0.0
var plays0 := 0
var labels := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--frames")
	if i >= 0 and i + 1 < args.size():
		frames = int(args[i + 1])
	main = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	root.add_child(main)


func _process(_d: float) -> bool:
	f += 1
	if f == 5:
		seed(77)  # the view's own effects use the global RNG
		main.start_benchmark()
		wv = main.view
		hud = main.hud
		for k in ["_splats", "_plague", "_gems", "_shots", "_enemies", "_allies", "_bullets", "_bolt_heads", "_dots", "_pops", "_trails", "_rings"]:
			labels[wv.get(k)] = k.trim_prefix("_")
	# Measure once the warm-up is over (Benchmark.WARMUP_S at a fixed 60 fps).
	if f > 5 + int(Benchmark.WARMUP_S * 60) + 30 and n < frames:
		if n == 0:
			plays0 = root.get_node("Sfx").plays
			Prof.reset()
		n += 1
		_sample()
	if n >= frames:
		_report()
		return true
	return f > 60 * 600


func _sample() -> void:
	var screen := Vector2(root.size)
	var stretch := root.get_final_transform().get_scale().x
	var zs := wv.cam_zoom * stretch  # world units -> window pixels
	for b in labels:
		var sb: SpriteBatch = b
		var px := 0.0
		for i in sb.count():
			var s: float = sb._size[i] * zs
			px += s * s  # aspect keeps the area
		fill[labels[b]] = fill.get(labels[b], 0.0) + px
	fill["floor"] = fill.get("floor", 0.0) + screen.x * screen.y
	var bl: BakedLayer = hud._bars_layer
	fill["hud_panel"] = fill.get("hud_panel", 0.0) + bl.region.get_area() * stretch * stretch
	dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var b: Benchmark = main._bench
	if b != null and b.sim_ms.size() > 0:
		sim += b.sim_ms[-1]
		view += b.view_ms[-1]
		hudms += b.hud_ms[-1]


func _report() -> void:
	var screen := float(root.size.x * root.size.y)
	print("COST frames %d at %dx%d | sim %.2f view %.2f hud %.2f ms | sounds %.1f/s | dc %.0f items %.0f prims %.0f" % [
		n, root.size.x, root.size.y, sim / n, view / n, hudms / n, (root.get_node("Sfx").plays - plays0) / (n / 60.0), dc / n, objs / n, prims / n])
	var keys := fill.keys()
	keys.sort_custom(func(a, c): return fill[a] > fill[c])
	var tot := 0.0
	var parts := []
	for k in keys:
		tot += fill[k] / n
		parts.append("%s %.2f" % [k, fill[k] / n / screen])
	print("FILL x screen (quads; immediate draws not counted) total %.2f | %s" % [tot / screen, " ".join(parts)])
	print(Prof.line(24))
