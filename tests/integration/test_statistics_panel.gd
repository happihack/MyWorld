extends TestCase
## The statistics panel (VS.2): the world's numbers now, and a line of each
## over the days kept (StatsRecorder).

var main: Node
var ui: UIRoot
var session: WorldSession


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	session = main.get_node("WorldSession")
	session.clock.set_speed(0)


func after_each() -> void:
	ui.close_all_panels()
	await wait_frames(2)


func test_from_the_menu() -> void:
	var menu := ui.open_menu()
	for entry in menu.entries():
		if entry.text == "Statistics":
			entry.pressed.emit()
	await wait_frames(2)
	assert_null(ui.main_menu(), "in place of the menu")
	var panel := ui.statistics()
	assert_not_null(panel)
	var now := session.sample_stats()
	assert_eq(panel.value_label(&"population").text, str(int(now[&"population"])))
	assert_true(panel.value_label(&"food_days").text.ends_with(" days"))
	assert_true(panel.value_label(&"health").text.ends_with("%"))
	assert_eq(panel.value_label(&"temperature").text,
		UIText.weather_line(session.weather.state, session.stats.latest().get(&"temperature", now[&"temperature"])))
	for key in [&"population", &"food_days", &"water", &"wood", &"stone", &"health", &"mood", &"temperature"]:
		assert_not_null(panel.sparkline(key), String(key))


func test_lines_over_time() -> void:
	var stats := session.stats
	# (Only the samples written here: the session's own hourly ones wait.)
	var source := stats.source
	stats.source = Callable()
	stats.clear()
	var panel := ui.open_statistics()
	await wait_frames(1)
	assert_eq(panel.span_label().text, "The lines begin within the hour")
	# Three days of samples: the people grow from 8 to 11, the food runs down.
	var start := session.clock.tick
	for hour in 72:
		var values := session.sample_stats()
		values[&"population"] = 8.0 + hour / 24
		values[&"food_days"] = 6.0 - hour / 18.0
		stats.add_sample(start + hour * 60, values)
	panel.refresh()
	await wait_frames(2)
	assert_eq(panel.value_label(&"population").text, "10")
	assert_eq(panel.value_label(&"food_days").text, "2.1 days")
	assert_eq(panel.span_label().text, "Over the last 2 days")
	var line := panel.sparkline(&"population")
	assert_eq(line.values(), stats.series(&"population"))
	var at := line.points()
	assert_eq(at.size(), 72)
	assert_true(at[-1].y < at[0].y, "more people: the line rises")
	assert_true(at[-1].x > at[0].x, "now on the right")
	var food := panel.sparkline(&"food_days").points()
	assert_true(food[-1].y > food[0].y, "less food: the line falls")
	# A new sample shows within a second.
	var values := session.sample_stats()
	values[&"population"] = 12.0
	stats.add_sample(start + 72 * 60, values)
	await wait_seconds(1.2)
	assert_eq(panel.value_label(&"population").text, "12")
	stats.source = source


func test_days_of_food_and_the_stores_of_every_settlement() -> void:
	var own := session.settlement
	var now := session.sample_stats()
	assert_near(now[&"food_days"], own.days_of_food(), 0.001)
	assert_near(now[&"food"], own.stockpile.food(), 0.001)
	assert_true(StatsRecorder.SERIES.has(&"food_days"))
	# A saved world without the series reads it as unknown (zeros), not as broken.
	var saved := session.stats.to_dict()
	(saved["series"] as Dictionary).erase("food_days")
	var again := StatsRecorder.new()
	assert_true(again.from_dict(saved))
	assert_eq(again.series(&"food_days").size(), again.sample_count())
	assert_eq(StatsPanel.value_text(&"food_days", 12.4), "12 days")
	assert_eq(StatsPanel.value_text(&"mood", 0.637), "64%")
	assert_eq(StatsPanel.value_text(&"wood", 23.0), "23")


func test_a_sparkline() -> void:
	var line := Sparkline.new()
	line.custom_minimum_size = Vector2.ZERO
	add_child(line)
	line.size = Vector2(200.0, 60.0)
	assert_true(line.points().is_empty(), "nothing to draw")
	line.set_values(PackedFloat32Array([5.0, 5.0, 5.0]))
	var flat := line.points()
	assert_eq(flat.size(), 3)
	assert_near(flat[0].y, 30.0, 0.01, "unchanged: level through the middle")
	assert_near(flat[2].y, 30.0, 0.01)
	line.set_values(PackedFloat32Array([0.0, 10.0]))
	var rising := line.points()
	assert_near(rising[0].y, 60.0 - Sparkline.PAD, 0.01, "the least at the bottom")
	assert_near(rising[1].y, Sparkline.PAD, 0.01, "the most at the top")
	assert_near(rising[1].x, 200.0 - Sparkline.PAD, 0.01)
	# From nothing: 36 to 35 is a small step down, not the whole height.
	line.from_zero = true
	line.set_values(PackedFloat32Array([36.0, 35.0]))
	var counted := line.points()
	assert_true(counted[1].y - counted[0].y < 3.0, "a small change looks small")
	assert_near(counted[0].y, Sparkline.PAD, 0.01, "the most at the top")
	line.queue_free()
