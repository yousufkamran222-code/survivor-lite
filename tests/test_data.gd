extends TestCase


func test_data_validates() -> void:
	var errors := GameData.validate(data())
	check(errors.is_empty(), "data errors: %s" % str(errors))


func test_scope_caps() -> void:
	var d := data()
	check(d.enemies.size() <= 8, "v1 scope: at most 8 enemy types")
	var general := 0
	for u in d.upgrades:
		if not u.has("modes"):
			general += 1
	check(general <= 16, "scope: about 16 upgrades shared by all modes (incl. 5 dash cards)")


func test_budget_curve_increases() -> void:
	var curve: Array = data().waves.budget_curve
	for i in range(1, curve.size()):
		check(float(curve[i][1]) >= float(curve[i - 1][1]), "budget curve should not drop at t=%s" % curve[i][0])


func test_modes_apply_overrides() -> void:
	var d := data()
	check(d.modes.size() >= 2, "at least two game modes")
	var classic := GameData.apply_mode(d, "classic")
	var infection := GameData.apply_mode(d, "infection")
	check(not classic.balance.territory.enabled, "classic: no territory")
	check(infection.balance.territory.enabled, "infection: territory on")
	check_eq(classic.balance.territory.dish_radius, d.balance.territory.dish_radius, "deep merge keeps other keys")
	check(World.new(classic, 1).terr == null)
	check(World.new(infection, 1).terr != null)
	# apply_mode must not mutate the shared data.
	d.balance.territory.enabled = true
	GameData.apply_mode(d, "classic")
	check(d.balance.territory.enabled, "original data untouched")


func test_hint_events_exist_in_the_world() -> void:
	# An event-triggered hint with a typo would silently never show.
	var src := FileAccess.get_file_as_string("res://scripts/core/world.gd")
	var h: Dictionary = data().hints
	var n := 0
	for key in h:
		for hint in h[key]:
			if hint.has("event"):
				n += 1
				check(('"type": "%s"' % hint.event) in src, "hint '%s' waits for unknown event '%s'" % [hint.id, hint.event])
	check(n > 0, "some hints are event-triggered")


func test_store_builds_force_debug_off() -> void:
	var d := data()
	d.balance.debug.dev_tools = true
	d.balance.debug.show_perf = true
	d.balance.debug.invincible = true
	GameData.apply_store_build(d, false)
	check(d.balance.debug.dev_tools, "playtest builds keep the dev tools")
	GameData.apply_store_build(d, true)
	check(not d.balance.debug.dev_tools and not d.balance.debug.show_perf and not d.balance.debug.invincible)


## The CrazyGames build (feature "crazygames") forces the debug flags off;
## every other build is untouched by it.
func test_crazygames_build_forces_debug_off() -> void:
	var d := data().duplicate(true)
	d.balance.debug.dev_tools = true
	d.balance.debug.show_perf = true
	d.balance.debug.invincible = true
	GameData.apply_crazygames_build(d, false)
	check(d.balance.debug.dev_tools and d.balance.debug.show_perf, "other builds keep their debug flags")
	GameData.apply_crazygames_build(d, true)
	check(not d.balance.debug.dev_tools and not d.balance.debug.show_perf and not d.balance.debug.invincible)
	check(float(d.balance.crazygames.prologue_skip_after_s) >= 0.0, "balance.crazygames.prologue_skip_after_s")


## Basic Launch on CrazyGames: no ads, so nothing is ever ready (every ad
## button hides) and a stray call never rewards.
func test_no_ad_backend_never_rewards() -> void:
	var b := NoAdBackend.new()
	check(not b.is_rewarded_ready() and not b.is_interstitial_ready())
	var got := [true, false]
	b.show_rewarded("revive", func(ok: bool) -> void: got[0] = ok)
	b.show_interstitial("between_runs", func() -> void: got[1] = true)
	check(not got[0], "no reward")
	check(got[1], "interstitial finishes at once")
	b.free()


## Only the CrazyGames preset carries the "crazygames" feature, so the itch
## web build, the APK and the store AAB never take that path.
func test_crazygames_preset_is_separate() -> void:
	var cfg := ConfigFile.new()
	check(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg loads")
	var found := false
	for sec in cfg.get_sections():
		if not sec.begins_with("preset.") or sec.ends_with(".options"):
			continue
		var feats := str(cfg.get_value(sec, "custom_features", ""))
		if str(cfg.get_value(sec, "name", "")) == "CrazyGames":
			found = true
			check(feats == "crazygames", "CrazyGames preset feature")
			check(str(cfg.get_value(sec, "platform", "")) == "Web", "CrazyGames is a web export")
			check(not bool(cfg.get_value(sec + ".options", "variant/thread_support", true)), "no threads (no COOP/COEP headers on portals)")
		else:
			check(not feats.contains("crazygames"), "preset %s must not carry crazygames" % cfg.get_value(sec, "name", sec))
	check(found, "a CrazyGames preset exists")


## The web build's overrides (balance.web) may only lower visual caps:
## never a gameplay number (perf 2026-11-14).
func test_web_overrides_are_visual_only() -> void:
	var d := data().duplicate(true)
	var allowed := {"perf": ["max_effects", "max_damage_numbers"], "juice": ["hit_sparks_per_frame", "splat_max"]}
	for sec in d.balance.web:
		if str(sec).begins_with("_"):
			continue
		check(allowed.has(sec), "web overrides section %s" % sec)
		for k in d.balance.web[sec]:
			check(allowed.get(sec, []).has(k), "web override %s.%s must be visual" % [sec, k])
	var before: Dictionary = d.balance.perf.duplicate()
	GameData.apply_web_build(d, true)
	check(int(d.balance.perf.max_effects) < int(before.max_effects), "fewer effects on web")
	check_eq(int(d.balance.perf.max_projectiles), int(before.max_projectiles), "gameplay caps untouched")
	var d2 := data().duplicate(true)
	GameData.apply_web_build(d2, false)
	check_eq(int(d2.balance.perf.max_effects), int(before.max_effects), "native builds unchanged")
