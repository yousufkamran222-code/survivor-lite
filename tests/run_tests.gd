extends SceneTree
## Headless test runner. Usage:
##   godot --headless --path . -s res://tests/run_tests.gd
## Runs every tests/test_*.gd file (except test_case.gd). Exit code 1 on failure.


func _initialize() -> void:
	var files := []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()
	var total := 0
	var failed: Array = []
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		var inst: Object = script.new()
		for m in inst.get_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			total += 1
			inst._current = "%s::%s" % [f, name]
			var before: int = inst.failures.size()
			inst.call(name)
			if inst.failures.size() > before:
				failed.append_array(inst.failures.slice(before))
	for msg in failed:
		printerr("FAIL ", msg)
	print("%d tests, %d failure(s)" % [total, failed.size()])
	quit(1 if failed.size() > 0 else 0)
