extends TestCase
## The on-device benchmark's numbers and report line (docs/POLISH_PLAN.md Phase 0).


func test_warmup_is_not_recorded_and_run_ends() -> void:
	var b := Benchmark.new()
	check(not b.advance(Benchmark.WARMUP_S * 0.5), "warm-up frames are skipped")
	check(b.advance(Benchmark.WARMUP_S), "then frames are recorded")
	check(not b.is_done())
	b.advance(Benchmark.MEASURE_S)
	check(b.is_done())
	check_eq(b.seconds_left(), 0)


func test_summary_stats() -> void:
	var b := Benchmark.new()
	b.refresh = 90.0
	for i in 95:
		b.add(11.0, 1.0, 2.0, 0.5, 60, 150, 40)
	for i in 5:
		b.add(30.0, 1.0, 2.0, 0.5, 60, 150, 40)  # hitches (> 1.5 x 11.1 ms)
	var s := b.summary()
	check_eq(int(s.frames), 100)
	check_near(float(s.frame_avg), 11.95, 0.01)
	check_near(float(s.slow_pct), 5.0, 0.01)
	check_near(float(s.frame_worst), 30.0, 0.01)
	check_near(float(s.frame_p95), 11.0, 0.01, "p95 sits below the 5 hitches")
	check_eq(int(s.draw_calls), 60)
	check_eq(int(s.refresh), 90)


func test_report_line_is_one_pasteable_line() -> void:
	var b := Benchmark.new()
	b.platform = "android"
	b.build = "abc1234 #9"
	b.add(16.7, 1.0, 1.0, 1.0, 50, 100, 10)
	var line := b.line()
	check(line.begins_with("BENCH v%d android" % Benchmark.VERSION), line)
	check("?Hz" in line, "unknown refresh is shown as ?Hz")
	check(not ("\\n" in line), "single line")
	check(line.ends_with("abc1234 #9"))


func test_empty_benchmark_is_safe() -> void:
	var s := Benchmark.new().summary()
	check_eq(int(s.frames), 0)
	check_eq(float(s.frame_avg), 0.0)
	check_eq(float(s.fps), 0.0, "no frames, no fps (not a huge number)")
