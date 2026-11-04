extends SceneTree
## Boss Rift tuning harness: 24 arena fights with a mid-run build (bolt 4,
## nova 2, might 2 at 2:30), with and without the bot baiting the Seeker
## Phage. Usage: godot --headless --path . -s res://tools/sim/rift_bench.gd [-- --nobait]
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var bait := not args.has("--nobait")
	var res := {"won": 0, "timeout": 0, "eject": 0, "hits": 0, "t_won": 0.0}
	for s in 24:
		var d := GameData.apply_mode(GameData.load_all(), "classic")
		var w := World.new(d, 900 + s)
		w.emit_events = false
		w.time = 150.0
		w.owned["bolt"] = 4
		w.owned["nova"] = 2
		w.owned["might"] = 2
		w._recompute_stats()
		var bot := BalanceBot.new(900 + s)
		bot.bait = bait
		w._rift_enter()
		var hp0 := w.e_maxhp[w.rift_boss_index()]
		while w.rift_state == World.RIFT_ACTIVE and w.state == "playing":
			w.step(1.0 / 30.0, bot.move(w))
			if w.state == "levelup":
				w.close_levelup()
		res.hits += w.missile_hits_boss
		if w.rifts_won > 0:
			res.won += 1
			res.t_won += w.rift_t
		elif w.rifts_ejected > 0:
			res.eject += 1
		else:
			res.timeout += 1
	print("PROBE bait=", bait, " ", res, " mean win t=", res.t_won / maxf(res.won, 1))
	quit(0)
