extends TestCase
## The Blessing button in the game (the owner and Josh, 2026-10-16): under
## the Disaster button, as big as the others, green; its blessings slide out
## to the left at two thirds the size; each offers first, and is given
## where the camera looks; while the world rests, it says when; the lights
## light the sky.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
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
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	router = main.get_node("InputRouter")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func test_the_button_and_its_blessings() -> void:
	var button := ui.blessing_button()
	var disaster := ui.disaster_button()
	await wait_frames(2)
	assert_true(button.is_visible_in_tree())
	assert_eq(ui.column()[-1], button, "the last of the column")
	assert_true(button.get_global_rect().position.y >= disaster.get_global_rect().end.y, "under the disasters")
	assert_near(button.get_global_rect().size.x, disaster.get_global_rect().size.x, 1.0, "as big as the others")
	assert_true(router.is_over_ui(button.get_global_rect().get_center()), "a touch on it is not a touch of the world")
	assert_false(ui.blessing_bar().visible)
	button.pressed.emit()
	await wait_frames(30)
	var bar := ui.blessing_bar()
	assert_true(bar.visible)
	for kind in BlessingSystem.KINDS:
		var one := bar.button(kind)
		var rect := one.get_global_rect()
		assert_near(rect.size.x, DisasterBar.size_of_one(), 1.0, "%s two thirds the size" % kind)
		assert_true(rect.end.x <= button.get_global_rect().position.x, "%s to the left of the button" % kind)
		assert_true(rect.position.x >= 0.0, "%s on the screen" % kind)
		assert_true(router.is_over_ui(rect.get_center()))
	# One hand's bar at a time.
	ui.show_disasters()
	await wait_frames(2)
	assert_false(bar.visible, "the blessings go in as the disasters come out")
	assert_true(ui.disaster_bar().visible)
	ui.show_blessings()
	await wait_frames(2)
	assert_false(ui.disaster_bar().visible)
	assert_true(bar.visible)


func test_an_offer_first_then_where_the_camera_looks() -> void:
	ui.show_blessings()
	await wait_frames(2)
	ui.blessing_bar().button(BlessingSystem.LIGHTS).pressed.emit()
	await wait_frames(1)
	assert_false(ui.blessing_bar().visible, "the row goes away")
	var card := ui.top_panel() as DisasterCard
	assert_not_null(card, "an offer")
	assert_eq(card.act, &"blessing")
	assert_eq(card.heading_text(), "LIGHTS IN THE SKY")
	assert_has(card.text(), "Lights")
	assert_eq(card.yes_button().text, "Give it")
	assert_true(card.yes_button().visible)
	card.cancel_button().pressed.emit()
	await wait_frames(1)
	assert_null(ui.top_panel())
	assert_false(session.blessings.is_active())
	assert_eq(session.history.count(Intervention.BLESSING, BlessingSystem.LIGHTS), 0)
	# Yes: given where the camera looks.
	var look := Vector2(session.start.settlement_tile) + Vector2(4.5, 2.5)
	rig.focus_on(Vector3(look.x, 0.0, look.y), Config.camera.home_distance, false)
	card = ui.offer_blessing(BlessingSystem.LIGHTS)
	card.yes_button().pressed.emit()
	await wait_frames(1)
	assert_null(ui.top_panel())
	assert_eq(session.blessings.kind, BlessingSystem.LIGHTS)
	assert_near(session.blessings.at.distance_to(look), 0.0, 0.6, "where the camera looks")
	assert_eq(session.history.count(Intervention.BLESSING, BlessingSystem.LIGHTS), 1)
	assert_true(ui.blessing_button().active, "the button glows while it goes on")
	assert_false(ui.disaster_button().active)
	assert_false(ui.disaster_bar().can_strike, "the disasters wait")
	# While it goes on, and the day after, another of either hand only says when.
	card = ui.offer_blessing(BlessingSystem.LIGHTS)
	assert_false(card.yes_button().visible, "not yet")
	assert_has(card.text(), "taking in")
	card.cancel_button().pressed.emit()
	await wait_frames(1)
	card = ui.warn_of_disaster(DisasterSystem.STORM)
	assert_false(card.yes_button().visible, "nor a disaster")
	card.cancel_button().pressed.emit()
	await wait_frames(1)
	session.clock.tick = session.blessings.until
	session.blessings.advance_to(session.clock.tick)
	await wait_frames(2)
	assert_false(ui.blessing_button().active)
	assert_true(ui.blessing_button().rested < 0.05, "the world begins to rest")
	assert_true(ui.disaster_button().rested < 0.05, "on both buttons")
	session.clock.tick += BlessingSystem.REST_MINUTES / 2
	await wait_frames(2)
	assert_near(ui.blessing_button().rested, 0.5, 0.02, "half rested")
	assert_near(ui.disaster_button().rested, 0.5, 0.02)
	session.clock.tick += BlessingSystem.REST_MINUTES / 2
	await wait_frames(2)
	assert_eq(ui.blessing_button().rested, 1.0, "ready")
	card = ui.offer_blessing(BlessingSystem.LIGHTS)
	assert_true(card.yes_button().visible)
	card.close()


func test_slowed_to_be_watched_and_the_sky_lit() -> void:
	var clock := session.clock
	ui.set_speed(GameClock.SPEED_VERY_FAST)
	main.give(BlessingSystem.LIGHTS)
	await wait_frames(2)
	assert_eq(clock.speed_index, GameClock.SPEED_NORMAL, "at its usual speed, to be watched")
	clock.tick += 35
	await wait_frames(2)
	assert_true(view.day_night().lights() > 0.9, "the sky lit")
	var lit := DayNight.lit_by_lights(DayNight.state_at(23.0, Config.day_night), 1.0)
	var dark := DayNight.state_at(23.0, Config.day_night)
	assert_true(lit.ambient_energy > dark.ambient_energy, "the night lit by it")
	assert_true(lit.background.g > dark.background.g, "green in the sky")
	clock.tick = session.blessings.until
	session.blessings.advance_to(clock.tick)
	await wait_frames(2)
	assert_eq(view.day_night().lights(), 0.0, "and gone")
	assert_eq(clock.speed_index, GameClock.SPEED_VERY_FAST, "and as fast as before, after")
