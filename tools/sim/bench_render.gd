extends SceneTree
## Desktop render benchmark: runs the same scenario as the on-device
## benchmark (Benchmark / Main.start_benchmark) with vsync off and prints the
## result line. CPU-rendered under xvfb, so compare runs with each other, not
## with phones:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/sim/bench_render.gd

var main: Node
var f := 0


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main = load("res://scenes/main.tscn").instantiate()
	main.name = "Main"
	root.add_child(main)


func _process(_delta: float) -> bool:
	f += 1
	if f == 5:
		main.start_benchmark()
	if f > 5 and main.bench_result != "":
		print(main.bench_result)
		return true
	return false
