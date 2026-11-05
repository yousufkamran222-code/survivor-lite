class_name BalanceBot
extends RefCounted
## A crude "average player" used by the balance simulator and tests:
## steers away from nearby threats, drifts toward gems, picks upgrades with a
## light preference for weapons. It is not meant to be good, only consistent.

var rng := RandomNumberGenerator.new()
var danger_radius := 230.0
var tangent := 1.0
var gem_greed := 1.3
var loop_time := 3.0  # territory: seconds out before heading home to close the loop
var _order_t := 0.0  # Swarm: next time (run clock) the bot reconsiders its order
var force_order := -1  # sim --order: always keep this order
var bait := true  # Boss Rift: lure the Seeker Phage into the Carrier (sim --nobait turns it off)


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	tangent = 1.0 if rng.randf() < 0.5 else -1.0


func move(w: World) -> Vector2:
	if w.rift_state == World.RIFT_ACTIVE:
		return _rift_move(w)
	var away := Vector2.ZERO
	var dr2 := danger_radius * danger_radius
	var near := 0
	for i in w.e_pos.size():
		if w.e_team[i] == 1:
			continue  # our own allies are not a threat
		var off := w.p_pos - w.e_pos[i]
		var d2 := off.length_squared()
		if d2 < dr2:
			away += off / maxf(d2, 64.0)
			near += 1
	for i in w.s_pos.size():
		var off := w.p_pos - w.s_pos[i]
		var d2 := off.length_squared()
		if d2 < 120.0 * 120.0:
			away += off / maxf(d2, 64.0) * 2.0
	# Telegraphs (like a player reacting): step out of the Mother Cell's slam
	# circle and sideways out of a winding-up Rammer's charge lane.
	if w.boss_slam == 1:
		var off := w.p_pos - w.boss_slam_at
		var sr := float(w.boss_def.get("slam_radius", 120.0)) + 40.0
		if off.length() < sr:
			away += (off.normalized() if off.length_squared() > 1.0 else Vector2.RIGHT) * 0.05
	for i in w.e_pos.size():
		if w.e_affix[i] != World.AFFIX_NONE and w.e_aphase[i] == 1 and w.affix_id(i) == "charge":
			var rel := w.p_pos - w.e_pos[i]
			var side := rel - w.e_adir[i] * rel.dot(w.e_adir[i])
			if rel.dot(w.e_adir[i]) > 0.0 and side.length() < 70.0:
				away += (side.normalized() if side.length_squared() > 1.0 else w.e_adir[i].orthogonal()) * 0.05
	var dir := Vector2.ZERO
	if away.length_squared() > 0.0:
		dir = away.normalized()
		# Circle a little instead of running straight, like players do.
		dir = (dir + dir.orthogonal() * 0.6 * tangent).normalized()
	# Players chase loot: chests and pickups first (they are rare and visible),
	# else the nearest XP gem; harder when it is safe.
	var target := Vector2.INF
	var best_d := 550.0 * 550.0
	for p in w.c_pos:
		if p.distance_squared_to(w.p_pos) < best_d:
			best_d = p.distance_squared_to(w.p_pos)
			target = p
	for p in w.i_pos:
		if p.distance_squared_to(w.p_pos) < best_d:
			best_d = p.distance_squared_to(w.p_pos)
			target = p
	var greed := gem_greed * 1.5
	if target == Vector2.INF:
		greed = gem_greed
		best_d = 450.0 * 450.0
		for i in w.g_pos.size():
			var d2 := w.g_pos[i].distance_squared_to(w.p_pos)
			if d2 < best_d:
				best_d = d2
				target = w.g_pos[i]
	if target != Vector2.INF:
		var to_t := (target - w.p_pos).normalized()
		var safety := clampf(1.0 - away.length() / 0.02, 0.15, 1.0)
		dir = (dir + to_t * safety * greed).normalized()
	# Territory: run a loop out, then head back to close it; stay off the rim.
	if w.terr != null:
		if w.p_on_land:
			loop_time = rng.randf_range(2.0, 4.5)
		elif w.terr.trail_age > loop_time:
			var home := -w.p_pos.normalized() if w.p_pos.length() > 1.0 else Vector2.ZERO
			dir = (dir * 0.6 + home * 1.4).normalized()
		if w.p_pos.length() > w.terr.radius - 250.0:
			dir = (dir - w.p_pos.normalized() * 0.8).normalized()
	# Nucleus: build/upgrade when the biomass allows, otherwise defend close
	# to the nucleus instead of wandering off after gems.
	if w.def_on:
		if w.p_down > 0.0:
			return Vector2.ZERO
		if w.empty_pad_under_player() >= 0:
			w.build_tower(pick_tower(w))
		var pad := _affordable_pad(w)
		if pad >= 0:
			var to_pad := w.pad_pos[pad] - w.p_pos
			var safety := clampf(1.0 - away.length() / 0.03, 0.2, 1.0)
			dir = (dir * (1.0 - safety) + to_pad.normalized() * 1.6 * safety).normalized() if to_pad.length() > 8.0 else Vector2.ZERO
		elif w.p_pos.distance_to(w.core_pos) > 380.0:
			dir = (dir + (w.core_pos - w.p_pos).normalized() * 1.2).normalized()
	var rim := w.dish_r
	if w.terr == null and rim > 0.0 and w.p_pos.length() > rim - 250.0:
		dir = (dir - w.p_pos.normalized() * 0.8).normalized()
	if w.conv_on and force_order < 0 and w.ally_count > 0 and w.time >= _order_t:
		_order_t = w.time + 2.0
		w.set_ally_order(pick_order(w, near))
	# Boss Rift: step in when it's open and we're healthy enough.
	if w.rift_state == World.RIFT_OPEN and w.p_hp > w.p_max_hp * 0.45 and w.rift_grace <= 0.0:
		var to_r := w.rift_pos - w.p_pos
		dir = (dir * 0.4 + to_r.normalized() * 1.6).normalized()
	if w.rift_power_ready() and near >= 6:
		w.use_rift_power()
	# Lab ability: when crowded or hurt.
	if w.ability_ready() and (near >= 6 or w.p_hp < w.p_max_hp * 0.4):
		w.use_ability()
	# Outbreak: trigger the frenzy when a crowd is close.
	if w.outbreak_ready() and away.length() > 0.02:
		w.trigger_outbreak()
	# Dash out when something is about to touch us.
	if w.can_dash() and away.length() > 0.05:
		w.p_move = dir
		w.dash()
	return dir


func pick(w: World) -> String:
	if w.mutated_offer != "" and rng.randf() < 0.7:  # Lab: Mutation Lab (2 levels at once)
		return w.mutated_offer
	var weapons := []
	for id in w.offers:
		if w.upgrade_defs[id].type == "weapon":
			weapons.append(id)
	if not weapons.is_empty() and rng.randf() < 0.6:
		return weapons[rng.randi() % weapons.size()]
	return w.offers[rng.randi() % w.offers.size()]


## In the arena: while the phage tracks us, stand between it and the Carrier
## so its locked shot flies on into the Carrier; on lock, dash sideways.
## Otherwise circle the Carrier at a safe distance.
func _rift_move(w: World) -> Vector2:
	var bi := w.rift_boss_index()
	if bi < 0:
		return Vector2.ZERO
	var bp := w.e_pos[bi]
	var to_b := bp - w.p_pos
	if w.rift_power_ready():
		w.use_rift_power()
	var dir := Vector2.ZERO
	if bait and w.m_state == 1:
		# Get the phage trailing behind us, then run at the Carrier: when it
		# locks, the line from the phage through us points into the Carrier.
		# Run out away from the Carrier (the phage follows), then turn and run
		# back past the (harmless, still tracking) phage at the Carrier: it
		# ends up behind us, so its locked shot flies on into the Carrier.
		var from_b := -to_b.normalized()
		if w.m_t < 1.7:
			dir = from_b
			var to_c := World.RIFT_CENTER - w.p_pos
			if to_c.length() > float(w.bal.rift.arena_radius) - 120.0:
				dir = (from_b.orthogonal() * tangent + to_c.normalized() * 0.5).normalized()
		else:
			dir = to_b.normalized() if to_b.length() > 140.0 else to_b.orthogonal().normalized() * tangent
	elif w.m_state == 2 or w.m_state == 3:
		var side := w.m_dir.orthogonal()
		if side.dot(w.p_pos - w.m_pos) < 0.0:
			side = -side
		dir = side
		if w.m_state == 2 and w.can_dash() and w.m_t > float(w.bal.rift.boss.missile.lock_s) * 0.5:
			w.p_move = side
			w.dash()
	else:
		var r := to_b.length()
		dir = to_b.orthogonal().normalized() * tangent
		if r < 260.0:
			dir = (dir - to_b.normalized()).normalized()
		elif r > 380.0:
			dir = (dir + to_b.normalized()).normalized()
	# Dodge the Carrier's spread shots a little.
	for i in w.s_pos.size():
		var off := w.p_pos - w.s_pos[i]
		if off.length_squared() < 90.0 * 90.0:
			dir = (dir + off.normalized() * 1.5).normalized()
	return dir


## Swarm orders: Guard when hurt, Hunt when crowded, Harvest when it's calm
## and XP is lying around out of reach, else Guard.
func pick_order(w: World, near: int) -> int:
	if w.p_hp < w.p_max_hp * 0.4:
		return World.ORDER_GUARD
	if near >= 6:
		return World.ORDER_HUNT
	var pr := float(w.bal.player.pickup_radius) * (1.0 + float(w.stats.magnet))
	var stray := 0
	for p in w.g_pos:
		if p.distance_to(w.p_pos) > pr:
			stray += 1
	if stray >= 8 and near <= 2:
		return World.ORDER_HARVEST
	return World.ORDER_GUARD if near <= 2 else World.ORDER_HUNT


## Cheapest pad action the biomass covers (new towers before upgrades), or -1.
func _affordable_pad(w: World) -> int:
	var best := -1
	var best_cost := INF
	for k in w.pad_pos.size():
		var c := w.pad_next_cost(k)
		if c < 0 or float(c) > w.biomass:
			continue
		var score := float(c) + (0.0 if w.pad_tower[k] < 0 else 30.0)
		if score < best_cost:
			best_cost = score
			best = k
	return best


## Tower bar: spread the types (a different one per new tower), the
## cheapest affordable if that one is too expensive.
func pick_tower(w: World) -> int:
	var n := w.tower_defs.size()
	var want := w.towers_built % n
	if w.biomass >= float(w.tower_cost(want)):
		return want
	for t in n:
		if w.biomass >= float(w.tower_cost(t)):
			return t
	return -1
