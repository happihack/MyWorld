extends TestCase
## The statistics of M15: the numbers worked out from the world, kept by the
## hour, the day and the year, saved, said in words (Insights), shown only once
## there is anything to show, and drawn (Chart; the panel's tabs and detail).

var session: WorldSession


func before_each() -> void:
	session = WorldSession.new()
	add_child(session)
	session.create_new(12345)
	session.clock.set_speed(0)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## Hours from tick `start` on, one sample each, of `values` (Callable hour -> Dictionary).
func _hours(stats: StatsRecorder, start: int, hours: int, values: Callable) -> void:
	for hour in hours:
		stats.add_sample(start + hour * 60, values.call(hour))


func test_stats_derived_not_static() -> void:
	var before := session.sample_stats()
	for name in StatsRecorder.SERIES:
		assert_true(before.has(name), "a value for " + String(name))
	assert_eq(int(before[&"population"]), session.people.size())
	assert_eq(int(before[&"settlements"]), session.settlements.size())
	# The world changes: the numbers do too (nothing is kept by hand).
	var own := session.settlement
	own.stockpile.add(&"wood", 5)
	var someone: PersonData = session.people.all_people()[0]
	assert_true(session.kill_person(someone.id))
	var after := session.sample_stats()
	assert_eq(int(after[&"population"]), int(before[&"population"]) - 1)
	assert_eq(int(after[&"deaths"]), int(before[&"deaths"]) + 1)
	assert_eq(int(after[&"wood"]), own.stockpile.amount(&"wood"))
	assert_eq(int(after[&"children"] + after[&"adults"] + after[&"elders"]), int(after[&"population"]), "every one of an age")
	assert_true(after[&"soil"] > 0.0 and after[&"soil"] <= 1.0, "the soil, on average")
	assert_true(after[&"forest"] >= 0.0 and after[&"forest"] <= 1.0)


func test_series_downsampling() -> void:
	var stats := StatsRecorder.new()
	var day := TimeConfig.MINUTES_PER_DAY
	# Ten days of hours: the people are the day's number (0, 1, 2 …).
	var first_day := Config.time.day_index(0)
	var start := (first_day + 1) * day - roundi(Config.time.start_hour * 60.0) # (midnight)
	_hours(stats, start, 24 * 10, func(hour: int) -> Dictionary:
		return {&"population": float(hour / 24), &"food": float(hour % 24)})
	assert_eq(stats.sample_count(), 240)
	assert_eq(stats.sample_count(StatsRecorder.Resolution.DAILY), 9, "the tenth day is not over yet")
	var daily := stats.series(&"population", StatsRecorder.Resolution.DAILY)
	assert_near(daily[0], 0.0, 0.001)
	assert_near(daily[8], 8.0, 0.001)
	assert_near(stats.series(&"food", StatsRecorder.Resolution.DAILY)[3], 11.5, 0.001, "the day's average")
	assert_eq(stats.ticks(StatsRecorder.Resolution.DAILY)[1], start + day, "dated by its first hour")
	# Years: one sample a day for three years and a bit.
	var years := StatsRecorder.new()
	var per_year := Config.time.days_per_year()
	for d in per_year * 3 + 2:
		years.add_sample(start + d * day, {&"population": float(Config.time.year_of(start + d * day))})
	assert_eq(years.sample_count(StatsRecorder.Resolution.YEARLY), 3, "the first (begun late) and two whole years written down; the fourth is open")
	var yearly := years.series(&"population", StatsRecorder.Resolution.YEARLY)
	assert_near(yearly[1] - yearly[0], 1.0, 0.001)
	# Bounded however long it runs.
	var most := Config.events.max_samples
	var long := StatsRecorder.new()
	_hours(long, start, most + 50, func(hour: int) -> Dictionary: return {&"food": float(hour)})
	assert_eq(long.sample_count(), most)
	assert_near(long.series(&"food")[-1], float(most + 49), 0.001)
	assert_eq(long.ticks()[0], start + 50 * 60, "the oldest let go of")


func test_stats_persistence() -> void:
	var day := TimeConfig.MINUTES_PER_DAY
	var whole := StatsRecorder.new()
	var halves := StatsRecorder.new()
	var values := func(hour: int) -> Dictionary: return {&"population": float(hour % 7), &"mood": 0.5}
	_hours(whole, 0, 24 * 30, values)
	_hours(halves, 0, 24 * 15 + 5, values)
	# Saved part way through a day, and read back as the save does (through var_to_bytes).
	var saved: Dictionary = bytes_to_var(var_to_bytes(halves.to_dict()))
	var again := StatsRecorder.new()
	assert_true(again.from_dict(saved))
	for hour in range(24 * 15 + 5, 24 * 30):
		again.add_sample(hour * 60, values.call(hour))
	for resolution in [StatsRecorder.Resolution.HOURLY, StatsRecorder.Resolution.DAILY]:
		assert_eq(again.ticks(resolution), whole.ticks(resolution))
		assert_eq(again.series(&"population", resolution), whole.series(&"population", resolution), "as if never saved")
	assert_true(again.sample_count(StatsRecorder.Resolution.DAILY) >= 29)
	# A world saved before M15: its hours read, the rest begins empty.
	var old := {"ticks": PackedInt64Array([0, 60, 120]), "series": {"population": PackedFloat32Array([5, 6, 7]),
		"food": PackedFloat32Array([1, 2, 3])}, "last": 120}
	var read := StatsRecorder.new()
	assert_true(read.from_dict(old))
	assert_eq(read.sample_count(), 3)
	assert_eq(read.series(&"population"), PackedFloat32Array([5, 6, 7]))
	assert_eq(read.series(&"births").size(), 3, "a number not kept then: nothing known of it")
	assert_eq(read.sample_count(StatsRecorder.Resolution.DAILY), 0)
	read.add_sample(day * 2, {&"population": 8.0})
	assert_eq(read.sample_count(), 4)
	# And with the world.
	_hours(session.stats, session.clock.tick, 24 * 3, values)
	var dict := session.to_dict()
	var loaded := WorldSession.new()
	add_child(loaded)
	assert_true(loaded.load_from(bytes_to_var(var_to_bytes(dict))))
	assert_eq(loaded.stats.series(&"population", StatsRecorder.Resolution.DAILY), session.stats.series(&"population", StatsRecorder.Resolution.DAILY))
	assert_true(loaded.stats.sample_count(StatsRecorder.Resolution.DAILY) >= 2)
	loaded.queue_free()


func test_insights() -> void:
	var stats := StatsRecorder.new()
	var events := EventLog.new()
	var day := TimeConfig.MINUTES_PER_DAY
	# Twenty days: the food halves after a drought on the tenth; the mood stays.
	_hours(stats, 0, 24 * 20, func(hour: int) -> Dictionary:
		return {&"food": 40.0 if hour < 24 * 10 else 20.0, &"water": 100.0, &"mood": 0.6})
	var drought_at := 10 * day - roundi(Config.time.start_hour * 60.0) + 60
	assert_eq(Config.time.day_index(drought_at), 10)
	events.record(&"drought", {EventLog.PARAM_TICK: drought_at})
	assert_near(Insights.change_after(stats, &"food", drought_at), -0.5, 0.05)
	assert_near(Insights.change_after(stats, &"water", drought_at), 0.0, 0.001)
	var said := Insights.lines(stats, events)
	assert_eq(said.size(), 1, "only what changed enough")
	assert_eq(said[0], "Food in store fell 50% after the drought in year 1.")
	assert_true(Insights.lines(stats, events, [&"water"]).is_empty(), "only about what is asked")
	# Too few days after it: nothing to say.
	events.record(&"storm", {EventLog.PARAM_TICK: 19 * day})
	assert_true(is_nan(Insights.change_after(stats, &"wood", 19 * day)))
	# Too few days in all: nothing.
	var short := StatsRecorder.new()
	_hours(short, 0, 24 * 3, func(_hour: int) -> Dictionary: return {&"food": 1.0})
	assert_true(Insights.lines(short, events).is_empty())


func test_reveal() -> void:
	var stats := StatsRecorder.new()
	_hours(stats, 0, 3, func(_hour: int) -> Dictionary: return {&"population": 8.0})
	var shown := StatsCatalog.shown(stats, StatsCatalog.POPULATION)
	assert_true(shown.has(&"population"))
	assert_false(shown.has(&"births"), "nobody born yet: not shown")
	stats.add_sample(4 * 60, {&"population": 9.0, &"births": 1.0})
	assert_true(StatsCatalog.shown(stats, StatsCatalog.POPULATION).has(&"births"), "once there is any")
	assert_true(StatsCatalog.tabs(stats).has(StatsCatalog.PLAYER), "the player's always")
	# Every number has a tab, a name and a way to be written.
	for name in StatsRecorder.SERIES:
		var entry := StatsCatalog.entry(name)
		assert_false(entry.is_empty(), String(name))
		assert_true(StatsCatalog.TABS.has(entry[1]))
		assert_false(StatsCatalog.label(name).begins_with("STAT_"), "a name for " + String(name))
	assert_eq(StatsCatalog.text(&"food_days", 3.42), "3.4 days")
	assert_eq(StatsCatalog.text(&"average_age", 23.46), "23.5 years")
	assert_eq(StatsCatalog.text(&"trust", 0.4), "40%")
	assert_eq(StatsCatalog.text(&"rainfall", 1.25), "1.3 mm")


func test_chart() -> void:
	var chart := Chart.new()
	add_child(chart)
	chart.size = Vector2(400.0, 300.0)
	var ticks := PackedInt64Array()
	var values := PackedFloat32Array()
	for i in 100:
		ticks.append(i * 60)
		values.append(float(i))
	chart.set_lines(ticks, [{"name": &"food", "values": values}])
	assert_eq(chart.window(), Vector2i(0, 99), "all of it in view")
	var at := chart.points(0)
	assert_eq(at.size(), 100)
	assert_true(at[-1].y < at[0].y, "more: higher")
	assert_true(at[-1].x > at[0].x, "later: to the right")
	chart.zoom_by(0.5)
	var window := chart.window()
	assert_true(window.y - window.x <= 50 and window.y - window.x >= 48, "closer: half as much")
	chart.pan_by(-1000)
	assert_eq(chart.window().x, 0, "no further back than the first")
	chart.pan_by(1000)
	assert_eq(chart.window().y, 99, "no further on than now")
	assert_near(chart.value_range().y, 99.0, 0.001, "the scale fits what is in view")
	# A new sample: the window showing now follows it.
	ticks.append(100 * 60)
	values.append(100.0)
	chart.update_lines(ticks, [{"name": &"food", "values": values}])
	assert_eq(chart.window().y, 100)
	chart.zoom_by(100.0)
	assert_eq(chart.window(), Vector2i(0, 100), "no further out than all of it")
	# Bars, stacked.
	chart.set_bars(PackedStringArray(["0", "10"]), [PackedFloat32Array([2, 3]), PackedFloat32Array([1, 0])],
		PackedStringArray(["Women", "Men"]))
	assert_eq(chart.mode, Chart.Mode.BARS)
	await wait_frames(1)
	chart.queue_free()


func test_panel_tabs_and_detail() -> void:
	var panel := StatsPanel.new()
	add_child(panel)
	_hours(session.stats, session.clock.tick, 24 * 3, func(_hour: int) -> Dictionary: return session.sample_stats())
	panel.setup(session)
	await wait_frames(2)
	assert_eq(panel.tab(), StatsCatalog.POPULATION)
	var tabs := panel.tab_keys()
	assert_true(tabs.has(StatsCatalog.ECONOMY) and tabs.has(StatsCatalog.ENVIRONMENT) and tabs.has(StatsCatalog.PLAYER))
	assert_eq(panel.value_label(&"population").text, str(session.people.size()))
	# The ages: every one of the living, women and men.
	var ages := panel.ages_chart()
	assert_not_null(ages)
	var counted := 0.0
	for stack: PackedFloat32Array in StatsPanel.ages_by_sex(session)[1]:
		counted += stack[0] + stack[1]
	assert_eq(int(counted), session.people.size())
	# Another tab.
	panel.set_tab(StatsCatalog.ENVIRONMENT)
	await wait_frames(1)
	assert_not_null(panel.value_label(&"trees"))
	assert_null(panel.value_label(&"population"))
	# A tap opens a number: its chart, by the hour; the days once there are two.
	var buttons := panel.stat_buttons()
	assert_true(buttons.has(&"trees"))
	(buttons[&"trees"] as Button).pressed.emit()
	await wait_frames(1)
	assert_eq(panel.detail(), &"trees")
	assert_not_null(panel.chart())
	assert_eq(panel.chart().window().y, session.stats.sample_count() - 1)
	assert_true(panel.texts().has("What the numbers say"))
	panel.set_resolution(StatsRecorder.Resolution.DAILY)
	await wait_frames(1)
	assert_eq(panel.chart().points(0).size(), session.stats.sample_count(StatsRecorder.Resolution.DAILY))
	# A new sample: the same page, newer numbers (the zoom stays).
	panel.set_resolution(StatsRecorder.Resolution.HOURLY)
	panel.chart().zoom_by(0.5)
	var window := panel.chart().window()
	var chart := panel.chart()
	session.stats.add_sample(session.clock.tick + 24 * 3 * 60, session.sample_stats())
	panel.refresh()
	assert_eq(panel.chart(), chart, "not built again")
	assert_eq(chart.window().y - chart.window().x, window.y - window.x)
	panel.close_detail()
	await wait_frames(1)
	assert_null(panel.chart())
	assert_eq(panel.tab(), StatsCatalog.ENVIRONMENT)
	# The player's tab: what was done.
	panel.set_tab(StatsCatalog.PLAYER)
	await wait_frames(1)
	assert_true(panel.texts()[0].begins_with("Interactions: "), "what was done")
	panel.queue_free()
