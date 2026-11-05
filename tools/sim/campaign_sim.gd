extends SceneTree
## Account-progression simulator: one fresh profile plays run after run in a
## mode with BalanceBot, like a player would: always the highest unlocked
## Virulence, gold spent on the cheapest next shop tier, Genes on the cheapest
## open Lab node (first side of a fork), the first unlocked ability equipped.
## Prints one JSON report: per-run rows plus milestones (first clear of each
## Virulence level, shop/Lab completion, play time).
##
##   godot --headless --path . -s res://tools/sim/campaign_sim.gd -- --mode classic --runs 250 --seed 1
## Options: --mode ID, --runs N (max runs), --seed S, --json PATH,
## --farm (a stuck player: after 5 losses in a row at the top level, replay
## the highest cleared level once for repeat-win Genes)
## The bot is a rough stand-in for a player (it dodges and picks cards
## randomly; people aim, route and choose builds), so read it as a shape.

const DT := 1.0 / 30.0


func _initialize() -> void:
	var args := {}
	var argv := OS.get_cmdline_user_args()
	for i in argv.size():
		if argv[i].begins_with("--"):
			args[argv[i].substr(2)] = argv[i + 1] if i + 1 < argv.size() and not argv[i + 1].begins_with("--") else "1"
	var mode := str(args.get("mode", "classic"))
	var max_runs := int(args.get("runs", 250))
	var seed0 := int(args.get("seed", 1))
	var data := GameData.load_all()
	var shop_total := 0
	for m in data.meta:
		for c in m.costs:
			shop_total += int(c)
	var lab_total := Lab.full_cost(data.lab)
	var p := Profile.new()
	var rows := []
	var first_clear := {}
	var minutes := 0.0
	var shop_max_run := -1
	var lab_max_run := -1
	var farm := args.has("farm")
	var losses := 0
	for r in max_runs:
		var vl := p.virulence_unlocked(mode)
		if farm and losses >= 5 and p.virulence_cleared(mode) > 0:
			vl = p.virulence_cleared(mode)
			losses = 0
		var d := GameData.apply_virulence(GameData.apply_mode(data, mode), vl)
		var w := World.new(d, seed0 * 100000 + r, Progression.run_bonus(d, p.meta_levels, p.lab))
		w.emit_events = false
		var ab := p.equipped_ability(data.lab)
		w.equip_ability(ab, Lab.ability_level(data.lab, p.lab, ab))
		var won := _play(w)
		minutes += w.time / 60.0
		var gold := w.run_gold_now(won)
		p.add_gold(gold, r)
		var s := Progression.run_summary(w, won, mode, data.online.score)
		var before := p.virulence_cleared(mode)
		if vl == p.virulence_unlocked(mode):
			losses = 0 if won else losses + 1
		p.record_run(s, [], r, data.lab.genes)
		if p.virulence_cleared(mode) > before:
			first_clear[str(p.virulence_cleared(mode))] = r + 1
			p.set_virulence(mode, p.virulence_unlocked(mode))
		var bought := _shop(p, data.meta)
		var nodes := _lab(p, data.lab)
		var shop_spent := _shop_spent(p, data.meta)
		var lab_spent := Lab.spent(data.lab, p.lab)
		if shop_max_run < 0 and shop_spent >= shop_total:
			shop_max_run = r + 1
		if lab_max_run < 0 and lab_spent >= lab_total:
			lab_max_run = r + 1
		rows.append({"run": r + 1, "v": vl, "won": won, "t": snappedf(w.time, 0.1), "level": w.level, "kills": w.kills,
			"gold": gold, "genes": p.last_genes, "shop_pct": snappedf(100.0 * shop_spent / shop_total, 0.1),
			"lab_pct": snappedf(100.0 * lab_spent / lab_total, 0.1), "ability": ab, "bought": bought, "nodes": nodes})
		if p.virulence_cleared(mode) >= Profile.MAX_VIRULENCE:
			break
	var out := {"mode": mode, "seed": seed0, "farm": farm, "runs": rows.size(), "first_clear_run": first_clear,
		"shop_maxed_run": shop_max_run, "lab_maxed_run": lab_max_run, "hours_played": snappedf(minutes / 60.0, 0.01),
		"shop_total_gold": shop_total, "lab_total_genes": lab_total, "gold_earned": p.stats.gold_earned,
		"genes_earned": p.stats.genes_earned, "rows": rows}
	print(JSON.stringify(out))
	if args.has("json"):
		var f := FileAccess.open(str(args.json), FileAccess.WRITE)
		f.store_string(JSON.stringify(out, "  "))
	quit()


func _play(w: World) -> bool:
	var bot := BalanceBot.new(w.rng.seed)
	while w.state in ["playing", "levelup", "chest", "defense_won"]:
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
	return w.state == "won"


## Cheapest next shop tier first, while the gold lasts. Returns tiers bought.
func _shop(p: Profile, defs: Array) -> int:
	var n := 0
	while true:
		var best: Dictionary = {}
		var best_cost := 1 << 30
		for m in defs:
			var lv := p.meta_level(m.id)
			if lv < m.costs.size() and int(m.costs[lv]) < best_cost:
				best = m
				best_cost = int(m.costs[lv])
		if best.is_empty() or p.gold < best_cost:
			return n
		p.buy_meta(best, 0)
		n += 1
	return n


## Cheapest open Lab node first; equips the first ability unlocked.
func _lab(p: Profile, cfg: Dictionary) -> int:
	var n := 0
	while true:
		var best: Dictionary = {}
		var best_cost := 1 << 30
		for node in Lab.nodes(cfg):
			if Lab.can_buy(cfg, node, p.lab, p.genes) and Lab.next_cost(node, p.lab) < best_cost:
				best = node
				best_cost = Lab.next_cost(node, p.lab)
		if best.is_empty():
			return n
		p.buy_lab(cfg, best, 0)
		n += 1
		if best.has("ability") and p.equipped_ability(cfg) == "":
			p.equip_ability(cfg, str(best.ability))
	return n


func _shop_spent(p: Profile, defs: Array) -> int:
	var total := 0
	for m in defs:
		for k in mini(p.meta_level(m.id), m.costs.size()):
			total += int(m.costs[k])
	return total
