class_name Lab
extends RefCounted
## The Lab (data/lab.json): a second, Genes-paid progression layer. Four
## branches; each node has a tier, per-level `effects` (stats, the same keys
## as Upgrades.GLOBAL_STATS) and `costs`. A node opens once every lower tier
## of its branch has something owned. Nodes sharing a `fork` key exclude each
## other. Pure logic: Profile stores the owned levels ({node id: level}).


static func nodes(cfg: Dictionary) -> Array:
	var out := []
	for b in cfg.get("branches", []):
		out.append_array(b.nodes)
	return out


static func find(cfg: Dictionary, id: String) -> Dictionary:
	for n in nodes(cfg):
		if n.id == id:
			return n
	return {}


static func branch_of(cfg: Dictionary, id: String) -> Dictionary:
	for b in cfg.get("branches", []):
		for n in b.nodes:
			if n.id == id:
				return b
	return {}


static func level(owned: Dictionary, id: String) -> int:
	return int(owned.get(id, 0))


static func max_level(node: Dictionary) -> int:
	return node.costs.size()


## Cost of the next level, or -1 when maxed.
static func next_cost(node: Dictionary, owned: Dictionary) -> int:
	var lv := level(owned, node.id)
	return int(node.costs[lv]) if lv < max_level(node) else -1


## The other side of a fork is owned (this node can never be bought).
static func fork_blocked(cfg: Dictionary, node: Dictionary, owned: Dictionary) -> bool:
	if not node.has("fork"):
		return false
	for n in branch_of(cfg, node.id).nodes:
		if n.id != node.id and n.get("fork", "") == node.fork and level(owned, n.id) > 0:
			return true
	return false


## Every lower tier of the branch has at least one owned node.
static func tier_open(cfg: Dictionary, node: Dictionary, owned: Dictionary) -> bool:
	var have := {}
	for n in branch_of(cfg, node.id).nodes:
		if int(n.tier) < int(node.tier):
			have[int(n.tier)] = bool(have.get(int(n.tier), false)) or level(owned, n.id) > 0
	for t in have:
		if not have[t]:
			return false
	return true


static func can_buy(cfg: Dictionary, node: Dictionary, owned: Dictionary, genes: int) -> bool:
	var cost := next_cost(node, owned)
	return cost >= 0 and genes >= cost and tier_open(cfg, node, owned) and not fork_blocked(cfg, node, owned)


## Summed stat bonus of everything owned (added to the shop's meta bonus).
static func bonus(cfg: Dictionary, owned: Dictionary) -> Dictionary:
	var out := {}
	for n in nodes(cfg):
		var lv := mini(level(owned, n.id), max_level(n))
		for k in n.effects:
			if lv > 0:
				out[k] = float(out.get(k, 0.0)) + float(n.effects[k]) * lv
	return out


## Genes spent so far (what a respec refunds).
static func spent(cfg: Dictionary, owned: Dictionary) -> int:
	var total := 0
	for n in nodes(cfg):
		for k in mini(level(owned, n.id), max_level(n)):
			total += int(n.costs[k])
	return total


## Total Genes to buy the whole Lab (one side of each fork).
static func full_cost(cfg: Dictionary) -> int:
	return spent(cfg, full_owned(cfg))


## A maxed Lab (first side of each fork): the sim's --lab all.
static func full_owned(cfg: Dictionary) -> Dictionary:
	var out := {}
	var forks := {}
	for n in nodes(cfg):
		if n.has("fork"):
			if forks.has(n.fork):
				continue
			forks[n.fork] = true
		out[n.id] = max_level(n)
	return out


# ---------------------------------------------------------------- abilities

## The Lab node that unlocks (and levels) an ability ({} if none).
static func ability_node(cfg: Dictionary, ability_id: String) -> Dictionary:
	for n in nodes(cfg):
		if str(n.get("ability", "")) == ability_id:
			return n
	return {}


## An ability's level = the level of its Lab node (0 = locked).
static func ability_level(cfg: Dictionary, owned: Dictionary, ability_id: String) -> int:
	var n := ability_node(cfg, ability_id)
	return 0 if n.is_empty() else mini(level(owned, n.id), max_level(n))


## Ability ids in data order.
static func ability_ids(cfg: Dictionary) -> Array:
	return cfg.get("abilities", {}).keys()


## Stats of an ability at a level (1-based): its top-level numbers plus the
## level row (duration_s, kills).
static func ability_stats(cfg: Dictionary, ability_id: String, lv: int) -> Dictionary:
	var a: Dictionary = cfg.abilities[ability_id]
	var out := a.duplicate()
	out.erase("levels")
	var rows: Array = a.levels
	var row: Dictionary = rows[clampi(lv, 1, rows.size()) - 1]
	for k in row:
		out[k] = row[k]
	return out


## An ability level in words: "Lasts 3.5 s, recharges in 215 kills".
static func ability_text(cfg: Dictionary, ability_id: String, lv: int) -> String:
	if lv <= 0:
		return "Locked"
	var a := ability_stats(cfg, ability_id, lv)
	return "Lasts %s s, recharges in %d kills" % [str(snappedf(float(a.duration_s), 0.1)), int(a.kills)]


## What a stat node gives at a level, in words: "+12% damage" ("None yet" at 0).
## Fork and keystone nodes use their `desc`.
static func effect_text(node: Dictionary, lv: int) -> String:
	if node.has("desc"):
		return str(node.desc)
	if lv <= 0:
		return "None yet"
	var k: String = node.effects.keys()[0]
	var v := float(node.effects[k]) * lv
	if node.get("fmt", "flat") == "pct":
		return "+%d%% %s" % [roundi(v * 100.0), node.label]
	return "+%s %s" % [str(roundi(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.01)), node.label]
