extends SceneTree
var main: Node
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		main = load("res://scenes/main.tscn").instantiate()
		main.name = "Main"
		root.add_child(main)
	if f == 6:
		main.start_benchmark()
	if f == 700:
		root.get_texture().get_image().save_png("/tmp/claude-0/probe/final_%s.png" % OS.get_environment("TAG"))
	return f > 701
