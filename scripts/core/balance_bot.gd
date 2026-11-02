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


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	tangent = 1.0 if rng.randf() < 0.5 else -1.0


func move(w: World) -> Vector2:
	var away := Vector2.ZERO
	var dr2 := danger_radius * danger_radius
	for i in w.e_pos.size():
		if w.e_team[i] == 1:
			continue  # our own allies are not a threat
		var off := w.p_pos - w.e_pos[i]
		var d2 := off.length_squared()
		if d2 < dr2:
			away += off / maxf(d2, 64.0)
	for i in w.s_pos.size():
		var off := w.p_pos - w.s_pos[i]
		var d2 := off.length_squared()
		if d2 < 120.0 * 120.0:
			away += off / maxf(d2, 64.0) * 2.0
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
	# Dash out when something is about to touch us.
	if w.can_dash() and away.length() > 0.05:
		w.p_move = dir
		w.dash()
	return dir


func pick(w: World) -> String:
	var weapons := []
	for id in w.offers:
		if w.upgrade_defs[id].type == "weapon":
			weapons.append(id)
	if not weapons.is_empty() and rng.randf() < 0.6:
		return weapons[rng.randi() % weapons.size()]
	return w.offers[rng.randi() % w.offers.size()]
