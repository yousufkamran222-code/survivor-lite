extends TestCase
## The in-run BUILD overlay lists every owned weapon and upgrade.


func _evos(d: Dictionary) -> Array:
	var by_w := {}
	var by_p := {}
	for ev in d.evolutions:
		by_w[ev.weapon] = ev
		by_p[ev.requires] = ev
	return [by_w, by_p]


func test_lists_every_owned_item() -> void:
	var d := GameData.apply_mode(data(), "classic")
	var w := World.new(d, 1)
	w.owned["orbit"] = 2
	w.owned["might"] = 3
	w.owned["multishot"] = 1
	w.owned["chain"] = 5
	w.evolved["chain"] = "neural"
	w._recompute_stats()
	var e := _evos(d)
	var bs := BuildScreen.new()
	bs.setup(d.balance.palette, w, e[0], e[1], func() -> void: pass)
	var text := _all_text(bs)
	for id in w.owned:
		var name: String = w.upgrade_defs[id].name
		if w.evolved.has(id):
			name = e[0][id].name
		check(text.contains(name), "%s is listed" % name)
	check(text.contains("EVOLVED"), "evolved weapon marked")
	check(text.contains("LV 3 / 5"), "levels shown")
	bs.free()


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += (n as Label).text + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out
