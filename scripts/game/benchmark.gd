class_name Benchmark
extends RefCounted
## On-device benchmark (Phase 0 of docs/POLISH_PLAN.md). Main runs a fixed,
## bot-driven, invincible Classic fight at a high-load moment of the run and
## feeds one sample per rendered frame here; this class only keeps the
## numbers and formats the one-line report Yousuf pastes back.
##
## Bump VERSION whenever the scenario changes, so old and new lines are never
## compared by mistake.

const VERSION := 3  # v3: the bot triggers Outbreak frenzies (v2: "view" counts sprite batches)
const SEED := 4242
const MODE := "classic"
const START_TIME := 170.0  # run clock at start: spawn budget is already high
const WARMUP_S := 5.0  # not measured: lets the crowd build up
const MEASURE_S := 40.0
## Mid/late-run loadout so kills, particles and damage numbers are as busy
## as a real late run while the crowd stays near the cap.
const LOADOUT := {"bolt": 4, "orbit": 3, "nova": 3, "chain": 3, "might": 2, "multishot": 1}

var t := 0.0
var platform := ""
var build := ""
var refresh := 0.0  # screen Hz (0 = unknown)
var frame_ms := PackedFloat32Array()  # time between rendered frames
var sim_ms := PackedFloat32Array()
var view_ms := PackedFloat32Array()  # WorldView fill + draw
var hud_ms := PackedFloat32Array()
var _dc := 0.0
var _enemies := 0.0
var _fx := 0.0


## Advances the clock. Returns true while samples should be recorded.
func advance(dt: float) -> bool:
	t += dt
	return t > WARMUP_S and not is_done()


func is_done() -> bool:
	return t >= WARMUP_S + MEASURE_S


func seconds_left() -> int:
	return maxi(0, ceili(WARMUP_S + MEASURE_S - t))


func add(frame: float, sim: float, view: float, hud: float, draw_calls: int, enemies: int, fx: int) -> void:
	frame_ms.append(frame)
	sim_ms.append(sim)
	view_ms.append(view)
	hud_ms.append(hud)
	_dc += draw_calls
	_enemies += enemies
	_fx += fx


static func mean(a: PackedFloat32Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func percentile(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)]


func summary() -> Dictionary:
	var n := maxi(frame_ms.size(), 1)
	var avg := mean(frame_ms)
	# A frame is "slow" if it took more than 1.5 refresh intervals (a visible
	# hitch). Without a known refresh rate, judge against 60 Hz.
	var budget := 1000.0 / (refresh if refresh > 0.0 else 60.0)
	var slow := 0
	for f in frame_ms:
		if f > budget * 1.5:
			slow += 1
	var worst := 0.0
	for f in frame_ms:
		worst = maxf(worst, f)
	return {
		"version": VERSION, "platform": platform, "build": build, "refresh": roundi(refresh),
		"frames": frame_ms.size(), "fps": snappedf(1000.0 / avg, 0.1) if avg > 0.0 else 0.0,
		"frame_avg": snappedf(avg, 0.01), "frame_p95": snappedf(percentile(frame_ms, 0.95), 0.01),
		"frame_worst": snappedf(worst, 0.01), "slow_pct": snappedf(100.0 * slow / n, 0.1),
		"sim": snappedf(mean(sim_ms), 0.01),
		"view": snappedf(mean(view_ms), 0.01), "hud": snappedf(mean(hud_ms), 0.01),
		"draw_calls": roundi(_dc / n), "enemies": roundi(_enemies / n), "fx": roundi(_fx / n),
	}


## The one line to paste back, e.g.
## BENCH v1 android 90Hz | 88.2 fps avg 11.34 p95 12.9 worst 31.2 ms, slow 1.2% | sim 1.3 view 1.1 hud 0.7 ms | dc 58 enemies 163 fx 41 | abc1234
func line() -> String:
	var s := summary()
	var hz := ("%dHz" % s.refresh) if s.refresh > 0 else "?Hz"
	return "BENCH v%d %s %s | %.1f fps avg %.2f p95 %.2f worst %.1f ms, slow %.1f%% | sim %.2f view %.2f hud %.2f ms | dc %d enemies %d fx %d | %s" % [
		s.version, s.platform, hz, s.fps, s.frame_avg, s.frame_p95, s.frame_worst, s.slow_pct,
		s.sim, s.view, s.hud, s.draw_calls, s.enemies, s.fx, s.build]
