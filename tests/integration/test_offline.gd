extends TestCase
## M20: the world goes on while the player is away (bible §9.4, §26.8, §31.8).
## The time away, capped; a clock set back is no time away; the same world
## and the same time away give the same return; a season away is much like a
## season watched; and WHILE YOU WERE GONE tells of what happened.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()


func _world(seed_value: int = 12345) -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	s.create_new(seed_value)
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	return s


func _opened(world_id: String) -> WorldSession:
	var loaded := SaveManager.load_world(world_id)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	return s


func test_offline_caps() -> void:
	var minute := Config.time.real_seconds_per_game_minute
	assert_eq(OfflineSimulator.game_minutes_for(0.0), 0)
	assert_eq(OfflineSimulator.game_minutes_for(3600.0), floori(3600.0 / minute), "an hour away: an hour at Normal speed")
	var day := OfflineSimulator.game_minutes_for(24.0 * 3600.0)
	assert_eq(day, floori(24.0 * 3600.0 / minute), "a day away: in full")
	var two := OfflineSimulator.game_minutes_for(48.0 * 3600.0)
	assert_true(two > day and two < 2 * day, "the second day counts for less")
	var month := OfflineSimulator.game_minutes_for(30.0 * 24.0 * 3600.0)
	var cap := floori(72.0 * 3600.0 / minute)
	assert_true(month <= cap and month > cap * 0.95, "a month away: an older world, not a dead one (at most 72 hours' worth)")
	assert_true(OfflineSimulator.game_minutes_for(365.0 * 24.0 * 3600.0) <= cap)


func test_clock_tamper_ignored() -> void:
	assert_eq(OfflineSimulator.seconds_away(1000, 4600), 3600)
	assert_eq(OfflineSimulator.seconds_away(1000, 500), 0, "a clock set before the save: nothing")
	assert_eq(OfflineSimulator.seconds_away(1000, 4600, 9000), 0, "a clock set back from what the game has seen: nothing")
	assert_eq(OfflineSimulator.seconds_away(0, 4600), 0, "no save time: nothing")


func test_offline_determinism() -> void:
	var first := _world()
	assert_true(SaveManager.save_world(first, &"test"))
	var world_id := first.world_id
	first.queue_free()
	await wait_frames(1)
	var results: Array = []
	for n in 2:
		var s := _opened(world_id)
		var summary := OfflineSimulator.new(s).run(6 * DAY)
		var people := PackedStringArray()
		for person in s.people.all_people():
			people.append("%d:%s:%.3f" % [person.id, person.given_name, person.health])
		results.append([s.clock.tick, people, s.settlement.stockpile.amounts(), s.events.size(), summary["counts"]])
		s.queue_free()
		await wait_frames(1)
	assert_eq(results[0], results[1], "the same world, the same time away: the same return")


func test_offline_vs_realtime_statistical_parity() -> void:
	# A season away, and the same season watched (the full year: tests/soak/offline_parity.gd).
	var days := Config.time.days_per_season
	var away := _world()
	OfflineSimulator.new(away).run(days * DAY)
	var watched := _world()
	for minute in days * DAY:
		var seconds := Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			watched.clock.advance(piece)
			seconds -= piece
		watched.behavior.step(1.0)
		watched.pathfinder.serve(1_000_000)
		watched.movement.step(1.0)
		if minute % 10 == 0:
			watched.advance_systems()
	watched.advance_systems()
	assert_eq(away.clock.tick, watched.clock.tick)
	assert_true(absi(away.people.size() - watched.people.size()) <= 2,
		"people: %d away, %d watched" % [away.people.size(), watched.people.size()])
	assert_eq(away.events.count_of(&"person_hungry_sick"), 0, "nobody weak with hunger away (none watched: %d)" % watched.events.count_of(&"person_hungry_sick"))
	assert_true(float(away.settlement.produced.get("wood", 0.0)) > 0.0, "wood brought in")
	var built := func(s: WorldSession) -> int: return s.construction.standing(PropData.Kind.HUT).size() + s.construction.standing(PropData.Kind.STOREHOUSE).size()
	assert_true(absi(built.call(away) - built.call(watched)) <= 2, "building: %d away, %d watched" % [built.call(away), built.call(watched)])
	assert_true(away.learning.of_settlement(away.settlement, Knowledge.Domain.NATURE) > 0.0, "learning goes on")
	away.queue_free()
	watched.queue_free()
	await wait_frames(1)


func test_years_away_do_not_wear_a_band_down() -> void:
	# (PG.4, 2026-10-07: worlds lived only offline dwindled — no rationing and
	# nobody turning to food when it ran short; a band that ran short did not
	# come back from it.)
	var s := _world()
	var start := s.people.size()
	OfflineSimulator.new(s).run(10 * Config.time.ticks_per_year())
	var starved := 0
	for record in s.archive.all_records():
		if record.cause == Lifecycle.CAUSE_STARVATION:
			starved += 1
	assert_eq(starved, 0, "nobody starved in ten years away")
	assert_true(s.people.size() >= start, "the band has not dwindled: %d at the start, %d after ten years" % [start, s.people.size()])
	s.queue_free()
	await wait_frames(1)


func test_wywg_summary_contents() -> void:
	var s := _world()
	var before := s.events.size()
	var summary := OfflineSimulator.new(s).run(12 * DAY)
	assert_eq(int(summary["days"]), 12)
	assert_eq(int(summary["minutes"]), 12 * DAY)
	assert_eq((summary["events"] as Array).size(), s.events.size() - before, "every event of the time away")
	var counts: Dictionary = summary["counts"]
	assert_eq(int(counts["births"]), _count_since(s, &"person_born", before))
	assert_eq(int(counts["deaths"]), _count_since(s, &"person_died", before))
	assert_eq(int(counts["buildings"]), _count_since(s, &"building_built", before))
	var hook: Dictionary = summary["hook"]
	assert_false(hook.is_empty(), "one thing to go and look at")
	assert_ne(str(hook["text"]), "")
	assert_true(hook["position"] != Vector2.INF)
	# The words.
	assert_eq(WhileYouWereGone.lines({"births": 12, "deaths": 4, "settlements": 1, "discoveries": 2, "storms": 1, "buildings": 3, "observations": 1}),
		PackedStringArray(["12 births · 4 deaths · 1 new settlement · 2 discoveries", "1 storm · 3 buildings completed · 1 unusual observation"]))
	assert_eq(WhileYouWereGone.lines({"births": 1}), PackedStringArray(["1 birth"]))
	assert_false(WhileYouWereGone.worth_telling({"counts": {}, "hook": {}}), "a quiet while: nothing to tell")
	var card := WhileYouWereGone.new()
	add_child(card)
	card.setup(summary)
	await wait_frames(1)
	assert_eq(card.hook_text(), "“%s”" % hook["text"])
	assert_true(card.locate_button().visible)
	var located: Array = []
	card.locate_requested.connect(func(at: Vector2) -> void: located.append(at))
	card.locate_button().pressed.emit()
	assert_eq(located, [hook["position"]])
	s.queue_free()
	await wait_frames(1)


func _count_since(s: WorldSession, type: StringName, before: int) -> int:
	var count := 0
	for event in s.events.of_type(type):
		if event.id > before:
			count += 1
	return count


func test_away_in_the_game_is_lived_and_told() -> void:
	AudioManager.ensure_sounds()
	var first := _world()
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var main := get_tree().current_scene
	var ui: UIRoot = main.get_node("UIRoot")
	var session: WorldSession = main.get_node("WorldSession")
	ui.quit_action = func() -> void: pass
	assert_null(ui.while_you_were_gone(), "just opened: nothing to tell")
	# A while away (two hours): lived behind "the box is settling", then told.
	var tick := session.clock.tick
	var lived: Dictionary = await main.catch_up(2 * 3600)
	assert_eq(session.clock.tick, tick + OfflineSimulator.game_minutes_for(2.0 * 3600.0), "two hours: two hours' worth")
	assert_true(session.is_processing(), "the world goes on again")
	await wait_frames(2)
	if WhileYouWereGone.worth_telling(lived):
		assert_not_null(ui.while_you_were_gone(), "and what happened is told")
		ui.while_you_were_gone().close()
	# The world rests, if the player would have it so.
	Settings.set_value(&"gameplay/world_rests", true)
	tick = session.clock.tick
	assert_true((await main.catch_up(5 * 3600) as Dictionary).is_empty())
	assert_eq(session.clock.tick, tick, "it rested")
	# A minute's look away is not lived.
	Settings.set_value(&"gameplay/world_rests", false)
	assert_true((await main.catch_up(20) as Dictionary).is_empty())
	get_tree().unload_current_scene()
	await wait_frames(2)


func test_lived_in_pieces_is_the_same() -> void:
	# (The time away is lived a piece at a time between frames — each
	# settlement's work, each one's day and planner, each system — so that no
	# frame waits for a whole day: the opening stuttered. The world it comes to
	# is the same as lived in one go.)
	var first := _world()
	assert_true(SaveManager.save_world(first, &"test"))
	var world_id := first.world_id
	first.queue_free()
	await wait_frames(1)
	var results: Array = []
	var calls := 0
	for n in 2:
		var s := _opened(world_id)
		var sim := OfflineSimulator.new(s)
		if n == 0:
			sim.run(4 * DAY)
		else:
			sim.begin(4 * DAY)
			while not sim.step(1): # (a budget of a microsecond: a piece a call)
				calls += 1
			sim.finish()
		var people := PackedStringArray()
		for person in s.people.all_people():
			people.append("%d:%s:%.3f" % [person.id, person.given_name, person.health])
		results.append([s.clock.tick, people, s.settlement.stockpile.amounts(), s.events.size()])
		s.queue_free()
		await wait_frames(1)
	assert_eq(results[0], results[1], "the same world, lived in pieces")
	assert_true(calls >= 4 * 20, "in many pieces (%d)" % calls)


func test_the_opening_waits_for_the_time_away() -> void:
	AudioManager.ensure_sounds()
	var first := _world()
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var main := get_tree().current_scene
	main.get_node("UIRoot").quit_action = func() -> void: pass
	main._opening_started = false
	if main.intro != null:
		main.intro = null
	main.catch_up(6 * 3600) # (not awaited: as the game opens)
	main.open_when_caught_up()
	await wait_frames(2)
	assert_true(main._catching_up, "still living the time away")
	assert_false(main.opening_begun(), "and the opening waits")
	await main.caught_up
	assert_true(main.opening_begun(), "then it opens")
	await wait_frames(3) # (what happened is told: then closed)
	var ui: UIRoot = main.get_node("UIRoot")
	if ui.while_you_were_gone() != null:
		ui.while_you_were_gone().close()
	await wait_frames(2)
	get_tree().unload_current_scene()
	await wait_frames(2)
