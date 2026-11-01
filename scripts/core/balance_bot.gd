class_name BalanceBot
extends RefCounted
## A crude "average player" used by the balance simulator and tests:
## steers away from nearby threats, drifts toward gems, picks upgrades with a
## light preference for weapons. It is not meant to be good, only consistent.

var rng := RandomNumberGenerator.new()
var danger_radius := 230.0
var tangent := 1.0
var gem_greed := 0.9


func _init(seed_value: int) -> void:
	rng.seed = seed_value
	tangent = 1.0 if rng.randf() < 0.5 else -1.0


func move(w: World) -> Vector2:
	var away := Vector2.ZERO
	var dr2 := danger_radius * danger_radius
	for i in w.e_pos.size():
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
	# Players chase XP: pull toward the nearest gem, harder when it is safe.
	var best := -1
	var best_d := 450.0 * 450.0
	for i in w.g_pos.size():
		var d2 := w.g_pos[i].distance_squared_to(w.p_pos)
		if d2 < best_d:
			best_d = d2
			best = i
	if best >= 0:
		var to_gem := (w.g_pos[best] - w.p_pos).normalized()
		var safety := clampf(1.0 - away.length() / 0.02, 0.15, 1.0)
		dir = (dir + to_gem * safety * gem_greed).normalized()
	return dir


func pick(w: World) -> String:
	var weapons := []
	for id in w.offers:
		if w.upgrade_defs[id].type == "weapon":
			weapons.append(id)
	if not weapons.is_empty() and rng.randf() < 0.6:
		return weapons[rng.randi() % weapons.size()]
	return w.offers[rng.randi() % w.offers.size()]
