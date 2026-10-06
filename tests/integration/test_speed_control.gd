extends TestCase
## The clock and the speed of the world in the running game (M6.1): the
## readout, pausing, the selector, and what a pause freezes.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var control: SpeedControl
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	Haptics.vibrate_action = func(_ms: int, _amplitude: float) -> void: pass
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
	await _open_main()


func _open_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	router = main.get_node("InputRouter")
	control = ui.speed_control()
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _tap(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		get_tree().root.push_input(t, true)


func test_the_clock_is_in_the_top_right_corner() -> void:
	var view_size := get_viewport().get_visible_rect().size
	var button := control.speed_button()
	assert_true(button.is_visible_in_tree())
	var rect := button.get_global_rect()
	assert_true(rect.end.x <= view_size.x - SpeedControl.EDGE_MARGIN + 1.0 and rect.end.x > view_size.x - 80.0, "at the right edge")
	assert_true(rect.position.y < view_size.y * 0.2, "at the top")
	assert_true(rect.size.x >= UITheme.TOUCH_TARGET * 0.9 and rect.size.y >= UITheme.TOUCH_TARGET * 0.9, "big enough for a finger")
	assert_true(router.is_over_ui(rect.get_center()), "a touch on it is not a touch of the world")
	# The time of day, the date and the weather, above it, at the very top
	# (the owner's playtest, 2026-10-05); touches pass through the words.
	control.refresh()
	assert_eq(control.time_text(), session.clock.format_time())
	assert_eq(control.date_text(), "Year 1 · Spring · Day 1")
	var time_label := control.get_node("Time") as Label
	assert_true(time_label.get_global_rect().end.y <= rect.position.y + 1.0, "above the button")
	assert_near(time_label.get_global_rect().position.y, SpeedControl.TOP, 1.0, "at the top")
	var home := ui.get_node("%HomeButton") as Control
	assert_true(home.get_global_rect().position.y >= rect.end.y, "Home under the button")
	assert_true(time_label.get_global_rect().end.x <= view_size.x)
	assert_false(router.is_over_ui(time_label.get_global_rect().get_center()), "the world under the words stays touchable")
	# Clear of what else is up there.
	assert_false(control.get_global_rect().intersects(ui.pins().get_global_rect()))
	ui.follow_banner().set_following("Mara", true)
	ui.follow_banner().set_locate("Mara")
	await wait_frames(2)
	for which: StringName in [&"follow", &"stop", &"locate"]:
		assert_false(ui.follow_banner().button(which).get_global_rect().intersects(control.get_global_rect()), "clear of the banner's %s" % which)
	# It follows the clock.
	session.clock.tick = 3 * TimeConfig.MINUTES_PER_DAY + 95
	control.refresh()
	assert_eq(control.time_text(), session.clock.format_time())
	assert_eq(control.date_text(), "Year 1 · Spring · Day 4")
	await wait_real_ms(500)
	assert_eq(control.time_text(), session.clock.format_time(), "by itself, as time passes")


func test_a_tap_pauses_and_carries_on() -> void:
	var speeds: Array = []
	var seen := func(index: int) -> void: speeds.append(index)
	EventBus.sim_speed_changed.connect(seen)
	assert_eq(session.clock.speed_index, GameClock.SPEED_NORMAL)
	# A real tap on the button.
	_tap(control.speed_button().get_global_rect().get_center())
	await wait_frames(2)
	assert_true(session.clock.is_paused())
	assert_eq(speeds, [GameClock.SPEED_PAUSE], "the world is told")
	assert_has(control.time_text(), "Paused")
	assert_eq(session.history.total(), 0, "and the world was not touched")
	# Paused: nobody lives, nothing falls or flows, the clock stands — the camera and the UI go on.
	assert_true(session.loose_system.frozen and session.water.frozen)
	var tick := session.clock.tick
	var people := session.people.to_dict()
	await wait_real_ms(600)
	assert_eq(session.clock.tick, tick)
	assert_eq(session.people.to_dict(), people, "nobody moved, nobody grew hungrier")
	var home := session.start.settlement_tile
	rig.focus_on(Vector3(home.x, 0, home.y), 14.0, false)
	var before := rig.pivot()
	rig.pan_world(Vector2(2.0, 0.0))
	assert_true(rig.pivot().distance_to(before) > 1.0, "the view moves")
	var person := session.people.all_people()[0]
	assert_true(main.select_person(person.id), "someone can be looked at")
	await wait_frames(2)
	assert_not_null(ui.person_card())
	ui.close_all_panels()
	# Something dropped while paused hangs where it was let go, and falls when the world goes on.
	var stone: LooseObject = null
	for object in session.loose.all_objects():
		if object.kind == LooseObject.Kind.ROCK:
			stone = object
			break
	assert_true(session.interactions.grab(stone.id))
	session.interactions.carry(stone.id, stone.position + Vector2(0.5, 0.0), 1.5)
	session.interactions.release(stone.id)
	await wait_real_ms(400)
	assert_true(stone.height_offset > 1.0, "still in the air")
	# A second tap: on at the speed it had.
	control.speed_button().button_down.emit()
	control.speed_button().button_up.emit()
	assert_eq(session.clock.speed_index, GameClock.SPEED_NORMAL)
	assert_false(session.loose_system.frozen or session.water.frozen)
	assert_false(control.time_text().contains("Paused"))
	await wait_real_ms(900)
	assert_true(session.clock.tick > tick, "time passes again")
	assert_true(stone.height_offset < 0.5, "and the stone has come down")
	# From Fast, a pause goes back to Fast.
	ui.set_speed(GameClock.SPEED_FAST)
	assert_eq(control.resume_speed(), GameClock.SPEED_FAST)
	control.toggle_pause()
	assert_true(session.clock.is_paused())
	control.toggle_pause()
	assert_eq(session.clock.speed_index, GameClock.SPEED_FAST)
	assert_eq(speeds, [0, 1, 2, 0, 2])
	EventBus.sim_speed_changed.disconnect(seen)


func test_a_long_press_opens_the_selector() -> void:
	assert_null(ui.speed_selector())
	# A finger resting on the button.
	control.speed_button().button_down.emit()
	await wait_real_ms(Config.interaction.long_press_ms + 150)
	var selector := ui.speed_selector()
	assert_not_null(selector, "the selector")
	control.speed_button().button_up.emit()
	assert_eq(session.clock.speed_index, GameClock.SPEED_NORMAL, "letting go is not a tap: nothing paused")
	assert_true(ui.open_speed_selector() == selector, "open already: the same one")
	# Four speeds, the current one marked, under the button and on the screen.
	assert_eq(selector.current(), GameClock.SPEED_NORMAL)
	var names := PackedStringArray()
	for index in 4:
		names.append(selector.row(index).text.strip_edges())
		assert_true(selector.row(index).get_global_rect().size.y >= UITheme.TOUCH_TARGET * 0.8)
	assert_eq(names, PackedStringArray(["Paused", "Normal", "Fast", "Very fast"]))
	assert_null(selector.row(4))
	var view_size := get_viewport().get_visible_rect().size
	assert_true(selector.get_global_rect().position.y >= control.speed_button().get_global_rect().end.y, "under the button")
	assert_true(Rect2(Vector2.ZERO, view_size).encloses(selector.get_global_rect()), "on the screen")
	assert_true(router.is_over_ui(selector.get_global_rect().get_center()))
	# Choosing sets the speed and puts the selector away.
	selector.row(GameClock.SPEED_VERY_FAST).pressed.emit()
	await wait_frames(2)
	assert_eq(session.clock.speed_index, GameClock.SPEED_VERY_FAST)
	assert_null(ui.speed_selector())
	var tick := session.clock.tick
	await wait_real_ms(500)
	assert_true(session.clock.tick - tick >= 10, "the world races (%d minutes in half a second)" % (session.clock.tick - tick))
	# Opened again it marks the new speed; touching the world puts it away and does nothing else.
	control.hold()
	await wait_frames(2)
	assert_eq(ui.speed_selector().current(), GameClock.SPEED_VERY_FAST)
	var touches := session.history.total()
	_tap(view_size * 0.5)
	await wait_frames(2)
	assert_null(ui.speed_selector(), "a touch of the world closes it")
	assert_eq(session.history.total(), touches, "and that touch did nothing else")
	# Pause from the selector; back with a tap, to what it was before.
	control.hold()
	await wait_frames(2)
	ui.speed_selector().row(GameClock.SPEED_PAUSE).pressed.emit()
	assert_true(session.clock.is_paused())
	control.toggle_pause()
	assert_eq(session.clock.speed_index, GameClock.SPEED_VERY_FAST)
	# The back button closes it too.
	control.hold()
	await wait_frames(2)
	EventBus.back_requested.emit()
	await wait_frames(2)
	assert_null(ui.speed_selector())


func test_a_paused_world_is_saved_paused_and_says_so() -> void:
	ui.set_speed(GameClock.SPEED_FAST)
	control.toggle_pause()
	assert_true(SaveManager.save_world(session, &"test"))
	get_tree().unload_current_scene()
	await wait_frames(2)
	await _open_main()
	assert_true(session.clock.is_paused(), "as it was left")
	assert_true(session.loose_system.frozen and session.water.frozen)
	control.refresh()
	assert_has(control.time_text(), "Paused", "and the HUD says so")
	# A tap carries on (at the usual speed: what it ran at before is not kept).
	control.toggle_pause()
	assert_false(session.clock.is_paused())
	assert_eq(session.clock.speed_index, GameClock.SPEED_NORMAL)


func test_the_world_is_told_when_days_begin() -> void:
	var days: Array = []
	var seasons: Array = []
	var years: Array = []
	var on_day := func(day: int) -> void: days.append(day)
	var on_season := func(season: int, year: int) -> void: seasons.append([season, year])
	var on_year := func(year: int) -> void: years.append(year)
	EventBus.day_started.connect(on_day)
	EventBus.season_changed.connect(on_season)
	EventBus.year_started.connect(on_year)
	var start := roundi(Config.time.start_hour * 60.0)
	session.clock.tick = Config.time.ticks_per_year() - start - 2
	ui.set_speed(GameClock.SPEED_VERY_FAST)
	await wait_real_ms(500)
	assert_eq(days, [Config.time.days_per_year() + 1])
	assert_eq(seasons, [[0, 2]])
	assert_eq(years, [2])
	control.refresh()
	assert_eq(control.date_text(), "Year 2 · Spring · Day 1")
	assert_has(main._doing_debug_section(), "Year 2 · Spring · Day 1 · 00:")
	EventBus.day_started.disconnect(on_day)
	EventBus.season_changed.disconnect(on_season)
	EventBus.year_started.disconnect(on_year)
