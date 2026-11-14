class_name Prof
extends RefCounted
## Section timers for the on-device benchmark (Benchmark v4). Off by default:
## a disabled section costs one bool check. The benchmark switches it on,
## and its result screen shows a second line ("PROF ...") with the costliest
## sections in ms per frame, so the phone tells us where its time goes.
##
##   var t0 := Prof.t()
##   ... work ...
##   Prof.add("sim.enemies", t0)

static var on := false
static var _acc := {}  # section -> total microseconds
static var _frames := 0


static func reset() -> void:
	_acc.clear()
	_frames = 0


static func t() -> int:
	return Time.get_ticks_usec() if on else 0


static func add(key: String, t0: int) -> void:
	if on:
		_acc[key] = float(_acc.get(key, 0.0)) + float(Time.get_ticks_usec() - t0)


## Adds an already measured duration (milliseconds).
static func add_ms(key: String, ms: float) -> void:
	if on:
		_acc[key] = float(_acc.get(key, 0.0)) + ms * 1000.0


## Call once per measured frame.
static func frame() -> void:
	if on:
		_frames += 1


## Section -> ms per frame.
static func per_frame() -> Dictionary:
	var out := {}
	for k in _acc:
		out[k] = float(_acc[k]) / 1000.0 / maxf(float(_frames), 1.0)
	return out


## The costliest `top` sections, e.g. "PROF sim.enemies 0.62 | view.top 0.41 | ...".
static func line(top: int = 16) -> String:
	var pf := per_frame()
	var keys := pf.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return pf[a] > pf[b])
	var parts := []
	for i in mini(top, keys.size()):
		parts.append("%s %.2f" % [keys[i], pf[keys[i]]])
	return "PROF " + " | ".join(parts)
