extends TestCase
## New-player start (data/onboarding.json): the Patient Zero prologue (a
## scripted run the bot can finish), mode coaches, staged unlocks, Profile v8.

const DT := 1.0 / 60.0


func _prologue(seed_value: int, p: Profile = null) -> World:
	var d := data()
	var w := World.new(GameData.apply_prologue(d), seed_value)
	w.emit_events = false
	w.start_tutorial(d.onboarding.prologue.beats, Onboarding.prologue_opts(d, p if p != null else Profile.new()))
	return w


## Plays a run the way a player would answer the prompts: open banked
## level-ups, dash / Outbreak when asked, close chests. Returns seconds.
func _play(w: World, max_s: float, seed_value: int) -> float:
	var bot := BalanceBot.new(seed_value)
	var t := 0.0
	while t < max_s:
		if w.pending_levelups > 0 and w.state == "playing":
			w.open_banked()
		if w.state == "levelup":
			w.choose_upgrade(bot.pick(w))
		elif w.state == "chest":
			w.close_chest()
		elif w.state != "playing":
			break
		var c := w.coach()
		if c.get("target", "") == "dash":
			w.dash()
		elif c.get("target", "") == "outbreak":
			w.trigger_outbreak()
		w.step(DT, bot.move(w))
		t += DT
	return t


func test_data_is_valid() -> void:
	var errors := GameData.validate(data())
	check(errors.is_empty(), str(errors))


func test_validation_catches_bad_beats() -> void:
	var d := data().duplicate(true)
	d.onboarding.prologue.beats.append({"id": "bad", "until": {"vibes": 1}, "target": "moon", "start": {"spawn": [{"id": "dragon"}], "offers": [["laser"]]}})
	var text := str(GameData.validate(d))
	for want in ["unknown condition", "unknown target", "unknown enemy", "unknown upgrade"]:
		check(text.contains(want), want + " in " + text)


func test_prologue_mode_is_scripted() -> void:
	var pd := GameData.apply_prologue(data())
	check_eq(str(pd.balance.mode_id), "prologue")
	check(pd.waves.events.is_empty(), "no timed events: the beats spawn things")
	check(float(pd.waves.elites.first_s) > 9000.0, "no timed elites")
	check(float(pd.balance.run_length_s) > 9000.0, "the finale ends it, not the clock")
	check(float(data().waves.elites.first_s) < 100.0, "normal waves untouched")


func test_bot_finishes_the_prologue_with_an_evolution() -> void:
	var w := _prologue(5)
	var t := _play(w, 360.0, 5)
	check_eq(w.state, "won", "finished in %.0f s at beat %s" % [t, w.tut.beat().get("id", "end")])
	check(w.evolved.has("bolt"), "first prologue evolves Pulse Bolt")
	check(w.boss_killed, "the Mother Cell died")
	check(w.picks >= 3, "picked upgrades")
	check(w.dashes >= 1 and w.outbreaks >= 1, "dashed and used Outbreak")
	check(t > 90.0 and t < 330.0, "about 4 minutes, took %.0f s" % t)
	check(w.tut.boss_s > 0.0)


func test_prologue_cannot_kill_you() -> void:
	var w := _prologue(9)
	w.p_iframes = 0.0
	for k in 50:
		w.p_iframes = 0.0
		w._hurt(500.0, "test")
	check(w.state == "playing" and w.p_hp > 0.0, "HP floor holds")


func test_replays_rotate_the_showcase() -> void:
	var d := data()
	var p := Profile.new()
	var seen := []
	for k in 4:
		var o := Onboarding.prologue_opts(d, p)
		seen.append(o.showcase)
		Onboarding.record_prologue(p, 100, 50, k)
	check_eq(seen, ["bolt", "orbit", "nova", "chain"])
	check_eq(str(Onboarding.prologue_opts(d, Profile.new()).partner), "multishot")
	var w := _prologue(21, p)  # 5th run: bolt again; a 2nd-run profile would be orbit
	check_eq(w.showcase, "bolt")


func test_orbit_showcase_also_evolves() -> void:
	var d := data()
	var p := Profile.new()
	Onboarding.record_prologue(p, 1, 1, 1)
	var w := _prologue(8, p)
	check_eq(w.showcase, "orbit")
	_play(w, 360.0, 8)
	check(w.evolved.has("orbit"), "Immune Wall shown on the 2nd prologue")


func test_forced_offers_and_granted_levels() -> void:
	var w := World.new(GameData.apply_prologue(data()), 3)
	w.forced_offers = [["orbit", "nova", "might"]]
	w.grant_level()
	check(w.open_banked())
	check_eq(w.offers, ["orbit", "nova", "might"])
	w.choose_upgrade("nova")
	check_eq(w.picks, 1)
	w.grant_level()
	w.open_banked()
	check_eq(w.offers.size(), 3, "back to normal rolls")


func test_score_and_medals() -> void:
	var pc: Dictionary = data().onboarding.prologue
	var slow := Onboarding.prologue_score(pc, 300, 50, 60.0)
	var fast := Onboarding.prologue_score(pc, 300, 50, 10.0)
	check(fast > slow, "a quick boss kill scores more")
	check(Onboarding.medal(pc, 0).is_empty())
	check_eq(str(Onboarding.medal(pc, 999999).id), "gold")


func test_prologue_never_counts_as_a_run_or_a_mode() -> void:
	var p := Profile.new()
	check(not Onboarding.prologue_done(p))
	check(Onboarding.record_prologue(p, 500, 200, 7), "first score is a best")
	check(Onboarding.prologue_done(p))
	check_eq(int(p.stats.runs), 0)
	check_eq(int(p.flat().modes_won), 0)
	check_eq(int(p.flat().best_virulence), 0)
	check_eq(int(p.flat().best_score_prologue), 500)
	check(not Onboarding.record_prologue(p, 100, 10, 8))
	check_eq(Onboarding.prologue_runs(p), 2)


func test_unlocks_follow_runs_and_wins() -> void:
	var d := data()
	var p := Profile.new()
	check(not Onboarding.unlocked(d, p, "classic"), "nothing before the prologue")
	Onboarding.record_prologue(p, 1, 1, 1)
	check(Onboarding.unlocked(d, p, "classic") and Onboarding.unlocked(d, p, "shop"))
	for id in ["style", "infection", "swarm", "nucleus", "virulence", "lab"]:
		check(not Onboarding.unlocked(d, p, id), id + " locked at first")
	p.stats.runs = 2
	check(Onboarding.unlocked(d, p, "style"))
	check(not Onboarding.unlocked(d, p, "infection"))
	p.stats.wins = 1
	check(Onboarding.unlocked(d, p, "infection"), "a win opens Infection early")
	check(Onboarding.unlocked(d, p, "virulence"))
	check(not Onboarding.unlocked(d, p, "lab"), "the Lab needs Genes")
	p.stats.genes_earned = 4
	check(Onboarding.unlocked(d, p, "lab"))
	p.stats.runs = 7
	check(Onboarding.unlocked(d, p, "nucleus"))
	check_eq(Onboarding.unlock_text(d, Profile.new(), "swarm"), "Play 5 more runs to unlock")
	check_eq(Onboarding.unlock_text(d, Profile.new(), "infection"), "Play 3 more runs or win a run to unlock")
	check_eq(Onboarding.unlock_text(d, Profile.new(), "lab"), "Win a run (it earns Genes) to unlock")
	check_eq(Onboarding.unlock_text(d, Profile.new(), "infection", true), "3 more runs or a win")
	check_eq(Onboarding.unlock_text(d, Profile.new(), "virulence", true), "Win a run")


func test_announcements_once_and_free_style_pick() -> void:
	var d := data()
	var p := Profile.new()
	check(Onboarding.pending_announcements(d, p).is_empty(), "nothing before the prologue")
	Onboarding.record_prologue(p, 1, 1, 1)
	var ids := []
	for u in Onboarding.pending_announcements(d, p):
		ids.append(u.id)
		Onboarding.mark_announced(p, u.id)
	check_eq(ids, ["classic", "shop"])
	check(Onboarding.pending_announcements(d, p).is_empty())
	check(Onboarding.is_new(p, "shop"))
	Onboarding.mark_opened(p, "shop")
	check(not Onboarding.is_new(p, "shop"))
	p.stats.runs = 2
	check(not Onboarding.free_pick(p))
	Onboarding.mark_announced(p, "style")
	check(Onboarding.free_pick(p), "Style comes with one free item")


func test_coaches_and_ads() -> void:
	var d := data()
	var p := Profile.new()
	check(Onboarding.coach_due(d, p, "infection"))
	check(not Onboarding.coach_due(d, p, "classic"), "Classic has no coach (the prologue taught it)")
	Onboarding.mark_coached(p, "infection")
	check(not Onboarding.coach_due(d, p, "infection"))
	check(not Onboarding.ads_allowed(d, p))
	p.stats.runs = 3
	check(Onboarding.ads_allowed(d, p))


func test_veteran_saves_keep_everything() -> void:
	var d := data()
	var old := Profile.from_dict({"version": 7, "gold": 900, "stats": {"runs": 40, "wins": 0}})
	check(Onboarding.prologue_done(old), "no forced prologue for existing players")
	for u in d.onboarding.unlocks:
		check(Onboarding.unlocked(d, old, u.id), u.id + " stays open")
	check(Onboarding.pending_announcements(d, old).size() >= 0)
	check(not Onboarding.coach_due(d, old, "swarm"))
	check(Onboarding.ads_allowed(d, old))
	var fresh := Profile.from_dict({"version": 7, "gold": 0})
	check(not Onboarding.prologue_done(fresh), "a save that never played gets the new start")
	var q := Profile.from_dict(JSON.parse_string(JSON.stringify(old.to_dict())))
	check(bool(q.onboarding.all), "survives a round trip")
	check_eq(Profile.new().settings.mode, "classic", "new players start in Classic")


func test_merge_keeps_onboarding_progress() -> void:
	var a := Profile.new()
	a.onboarding = {"prologue_done": true, "coached": {"swarm": true}}
	a.updated_at = 1
	var b := Profile.new()
	b.onboarding = {"announced": {"shop": true}}
	b.updated_at = 2
	var m := Profile.merge(a, b)
	check(bool(m.onboarding.get("prologue_done", false)))
	check(m.onboarding.coached.has("swarm") and m.onboarding.announced.has("shop"))


func test_coach_beats_finish_in_their_modes() -> void:
	var d := data()
	for mode in ["infection", "swarm", "nucleus"]:
		var w := World.new(GameData.apply_mode(d, mode), 4)
		w.emit_events = false
		w.start_tutorial(d.onboarding.coaches[mode])
		_play(w, 150.0, 4)
		check(w.tut.done or w.state != "playing", "%s coach reached the end (at %s)" % [mode, w.tut.beat().get("id", "end")])


func test_free_style_pick() -> void:
	var cfg: Dictionary = data().cosmetics
	var p := Profile.new()
	check(not Cosmetics.take_free(cfg, p, "mint", 2500, 1), "no pick before the Style unlock")
	Onboarding.mark_announced(p, "style")
	check(not Cosmetics.take_free(cfg, p, "royal", 2500, 1), "too pricey for the free pick")
	check(not Cosmetics.take_free(cfg, p, "golden", 2500, 1), "prestige items aren't free")
	check(Cosmetics.take_free(cfg, p, "ember", 2500, 1))
	check(p.cosmetics.has("ember") and p.gold == 0)
	check(not Onboarding.free_pick(p), "only one")
	check(not Cosmetics.take_free(cfg, p, "mint", 2500, 2))


func test_gold_medal_skin_matches_the_gold_medal() -> void:
	var d := data()
	var gold := 0
	for m in d.onboarding.prologue.medals:
		if m.id == "gold":
			gold = int(m.score)
	var it := Cosmetics.find(d.cosmetics, "prototype")
	check_eq(int(it.unlock.goal), gold)
	check_eq(str(it.unlock.stat), "best_score_prologue")
	var p := Profile.new()
	Onboarding.record_prologue(p, gold, 300, 1)
	check(Cosmetics.earned(it, p))
