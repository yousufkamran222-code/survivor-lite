extends SceneTree
## Economy study: what a player can build with a given amount of gold, and
## which Virulence levels the bot clears with it.
##
## For each budget, a buying strategy spends the gold on the shop (no Lab, no
## ability, no Side Effects), then the bot plays `--runs` runs per Virulence
## level, climbing from V1 until the win rate drops below `--stop` (or vmax).
##
##   godot --headless --path . -s res://tools/sim/economy_sim.gd -- --mode classic --strategy value \
##       --budgets 0,1000,2000,5000,10000,20000,40000,full --runs 12 --seed 700 --json out.json
##
## Strategies: cheapest (next cheapest tier anywhere: how the campaign sim and
## many players buy), offense (damage first), defense (survival first), value
## (best power per gold by fixed weights, gold bonus skipped).

const DT := 1.0 / 30.0

## Rough power per tier, for the "value" buyer (gold_gain is economy, not power).
const WEIGHTS := {"meta_hp": 0.8, "meta_might": 1.0, "meta_haste": 1.0, "meta_armor": 1.0, "meta_regen": 0.5,
	"meta_move": 0.6, "meta_magnet": 0.25, "meta_growth": 0.5, "meta_greed": 0.0, "meta_amount": 10.0,
	"meta_dash_cd": 0.3, "meta_dash_charge": 4.0, "meta_dash_dmg": 0.2, "meta_dash_decoy": 0.15, "meta_convert": 0.25,
	"meta_evo_bolt": 0.9, "meta_evo_orbit": 0.9, "meta_evo_nova": 0.9, "meta_evo_chain": 0.9, "meta_outbreak": 6.0}
const OFFENSE := ["meta_might", "meta_haste", "meta_amount", "meta_evo_bolt", "meta_evo_orbit", "meta_evo_nova", "meta_evo_chain", "meta_outbreak", "meta_dash_dmg"]
const DEFENSE := ["meta_hp", "meta_armor", "meta_regen", "meta_move", "meta_dash_cd", "meta_dash_charge"]


func _initialize() -> void:
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i].begins_with("--"):
			args[argv[i].substr(2)] = argv[i + 1] if i + 1 < argv.size() and not argv[i + 1].begins_with("--") else "1"
	var mode := str(args.get("mode", "classic"))
	var strategy := str(args.get("strategy", "value"))
	var runs := int(args.get("runs", 12))
	var seed0 := int(args.get("seed", 700))
	var vmax := int(args.get("vmax", 8))
	var stop := float(args.get("stop", 0.15))
	var data := GameData.load_all()
	var full := 0
	for m in data.meta:
		for c in m.costs:
			full += int(c)
	var budgets := []
	for b in str(args.get("budgets", "0,1000,2000,5000,10000,20000,40000,full")).split(","):
		budgets.append(full if b == "full" else int(b))
	var rows := []
	for budget in budgets:
		var levels := _buy(data.meta, budget, strategy)
		var meta := Progression.meta_bonus(data.meta, levels)
		var spent := _spent(data.meta, levels)
		var by_v := []
		for v in range(1, vmax + 1):
			var d := GameData.apply_virulence(GameData.apply_mode(data, mode), v)
			var wins := 0
			var times := []
			var gold := 0.0
			var lvls := []
			for r in runs:
				var w := World.new(d, seed0 * 1000 + v * 100 + r, meta)
				w.emit_events = false
				var won := _play(w)
				wins += 1 if won else 0
				times.append(w.time)
				gold += w.run_gold_now(won)
				lvls.append(w.level)
			times.sort()
			lvls.sort()
			var wr := float(wins) / runs
			by_v.append({"v": v, "win_rate": snappedf(wr, 0.01), "time_p10": snappedf(times[int(runs * 0.1)], 0.1), "time_p50": snappedf(times[runs / 2], 0.1),
				"level_p50": lvls[runs / 2], "gold_per_run": roundi(gold / runs)})
			printerr("%s %s budget %d V%d: win %.0f%%" % [mode, strategy, budget, v, wr * 100.0])
			if wr < stop:
				break
		rows.append({"budget": budget, "spent": spent, "levels": levels, "by_v": by_v})
	var out := {"mode": mode, "strategy": strategy, "runs": runs, "seed": seed0, "full_shop": full, "rows": rows}
	print(JSON.stringify(out))
	if args.has("json"):
		var f := FileAccess.open(str(args.json), FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
	quit()


func _play(w: World) -> bool:
	var bot := BalanceBot.new(w.rng.seed)
	while w.state in ["playing", "levelup", "chest", "defense_won"] and w.time < 1800.0:
		if w.state == "defense_won":
			w.collect_win()
			break
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
			continue
		if w.state == "chest":
			w.close_chest()
			continue
		w.step(DT, bot.move(w))
	return w.state == "won" or w.state == "defense_won"


func _spent(defs: Array, levels: Dictionary) -> int:
	var s := 0
	for m in defs:
		for k in int(levels.get(m.id, 0)):
			s += int(m.costs[k])
	return s


## Spends up to `budget` gold with a strategy; returns {meta id: level}.
func _buy(defs: Array, budget: int, strategy: String) -> Dictionary:
	var levels := {}
	var left := budget
	while true:
		var pick := _next(defs, levels, left, strategy)
		if pick.is_empty():
			break
		var lv := int(levels.get(pick.id, 0))
		left -= int(pick.costs[lv])
		levels[pick.id] = lv + 1
	return levels


func _affordable(defs: Array, levels: Dictionary, left: int, only: Array = []) -> Array:
	var out := []
	for m in defs:
		var lv := int(levels.get(m.id, 0))
		if lv >= m.costs.size() or int(m.costs[lv]) > left:
			continue
		if not only.is_empty() and not only.has(m.id):
			continue
		out.append(m)
	return out


func _cheapest(list: Array, levels: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bc := 1 << 30
	for m in list:
		var c := int(m.costs[int(levels.get(m.id, 0))])
		if c < bc:
			bc = c
			best = m
	return best


func _next(defs: Array, levels: Dictionary, left: int, strategy: String) -> Dictionary:
	match strategy:
		"cheapest":
			return _cheapest(_affordable(defs, levels, left), levels)
		"offense", "defense":
			var group: Array = OFFENSE if strategy == "offense" else DEFENSE
			var first := _cheapest(_affordable(defs, levels, left, group), levels)
			return first if not first.is_empty() else _cheapest(_affordable(defs, levels, left), levels)
		_:  # value: best weight per gold; gold-gain only once nothing else is affordable
			var best: Dictionary = {}
			var bv := -1.0
			for m in _affordable(defs, levels, left):
				var wgt := float(WEIGHTS.get(m.id, 0.3))
				if wgt <= 0.0:
					continue
				var v := wgt / float(m.costs[int(levels.get(m.id, 0))])
				if v > bv:
					bv = v
					best = m
			return best if not best.is_empty() else _cheapest(_affordable(defs, levels, left), levels)
