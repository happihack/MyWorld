extends TestCase
## The Disaster button in the game (the owner's design, 2026-10-05): under
## the journal, as big as the others; its disasters slide out to the left at
## half the size; each asks first, and comes down where the camera looks;
## while the world rests, it says when.

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


func test_the_button_and_its_disasters() -> void:
	var button := ui.disaster_button()
	var journal := ui.journal_button()
	await wait_frames(2)
	assert_true(button.is_visible_in_tree())
	assert_eq(ui.column()[-1], button, "the last of the column")
	assert_true(button.get_global_rect().position.y >= journal.get_global_rect().end.y, "under the journal")
	assert_near(button.get_global_rect().size.x, journal.get_global_rect().size.x, 1.0, "as big as the others")
	assert_near(button.get_global_rect().size.x, SpeedControl.BUTTON_SIZE, 1.0)
	assert_true(router.is_over_ui(button.get_global_rect().get_center()), "a touch on it is not a touch of the world")
	# A tap: the seven slide out to its left, half the size.
	assert_false(ui.disaster_bar().visible)
	button.pressed.emit()
	await wait_frames(30)
	var bar := ui.disaster_bar()
	assert_true(bar.visible)
	var order: Array[StringName] = []
	var last_x := -1.0
	for kind in DisasterSystem.KINDS:
		var one := bar.button(kind)
		var rect := one.get_global_rect()
		assert_near(rect.size.x, SpeedControl.BUTTON_SIZE * 0.5, 1.0, "%s half the size" % kind)
		assert_true(rect.end.x <= button.get_global_rect().position.x, "%s to the left of the button" % kind)
		assert_true(rect.position.x > last_x, "in order, left to right")
		assert_true(rect.position.x >= 0.0, "%s on the screen" % kind)
		assert_true(router.is_over_ui(rect.get_center()))
		last_x = rect.position.x
		order.append(kind)
	assert_eq(order, [&"earthquake", &"eclipse", &"storm", &"flood", &"tornado", &"blood", &"meteors"] as Array[StringName])
	# Another tap: they go away.
	button.pressed.emit()
	assert_false(bar.visible)


func test_a_warning_first_then_where_the_camera_looks() -> void:
	ui.show_disasters()
	await wait_frames(2)
	ui.disaster_bar().button(DisasterSystem.EARTHQUAKE).pressed.emit()
	await wait_frames(1)
	assert_false(ui.disaster_bar().visible, "the row goes away")
	var card := ui.top_panel() as DisasterCard
	assert_not_null(card, "a warning")
	assert_eq(card.heading_text(), "EARTHQUAKE")
	assert_has(card.text(), "shake")
	assert_true(card.yes_button().visible)
	# Cancel: nothing happens.
	card.cancel_button().pressed.emit()
	await wait_frames(1)
	assert_null(ui.top_panel())
	assert_false(session.disasters.is_active())
	assert_eq(session.history.count(Intervention.DISASTER, DisasterSystem.EARTHQUAKE), 0)
	# Yes: it comes down where the camera looks.
	var look := Vector2(session.start.settlement_tile) + Vector2(4.5, 2.5)
	rig.focus_on(Vector3(look.x, 0.0, look.y), Config.camera.home_distance, false)
	card = ui.warn_of_disaster(DisasterSystem.METEORS)
	card.yes_button().pressed.emit()
	await wait_frames(1)
	assert_null(ui.top_panel())
	assert_eq(session.disasters.kind, DisasterSystem.METEORS)
	assert_near(session.disasters.at.distance_to(look), 0.0, 0.6, "where the camera looks")
	assert_eq(session.history.count(Intervention.DISASTER, DisasterSystem.METEORS), 1)
	assert_true(ui.disaster_button().active, "the button glows while it goes on")
	# While it goes on, and the day after, another only says when.
	card = ui.warn_of_disaster(DisasterSystem.STORM)
	assert_false(card.yes_button().visible, "not yet")
	assert_has(card.text(), "recovering")
	card.cancel_button().pressed.emit()
	await wait_frames(1)
	session.clock.tick = session.disasters.until
	session.disasters.advance_to(session.clock.tick)
	await wait_frames(2)
	assert_false(ui.disaster_button().active)
	assert_true(ui.disaster_button().rested < 0.05, "the world begins to rest")
	session.clock.tick += DisasterSystem.REST_MINUTES / 2
	await wait_frames(2)
	assert_near(ui.disaster_button().rested, 0.5, 0.02, "half rested")
	session.clock.tick += DisasterSystem.REST_MINUTES / 2
	await wait_frames(2)
	assert_eq(ui.disaster_button().rested, 1.0, "ready")
	card = ui.warn_of_disaster(DisasterSystem.STORM)
	assert_true(card.yes_button().visible)
	card.close()


func test_what_it_looks_like() -> void:
	var fx := view.disaster_fx()
	assert_not_null(fx)
	var fire := session.settlement.fire().position2d()
	session.interactions.disaster(DisasterSystem.ECLIPSE, fire)
	session.clock.tick += 35
	await wait_frames(2)
	assert_true(view.day_night().eclipse() > 0.9, "the day goes dark")
	session.clock.tick = session.disasters.until
	session.disasters.advance_to(session.clock.tick)
	await wait_frames(2)
	assert_eq(view.day_night().eclipse(), 0.0, "and light again")
	session.disasters.rest_until = 0
	session.interactions.disaster(DisasterSystem.BLOOD, fire)
	session.clock.tick += 120
	await wait_frames(2)
	assert_near(float(view.water_material().get_shader_parameter(&"blood")), 1.0, 0.01, "the water red")
	session.clock.tick = session.disasters.until
	session.disasters.advance_to(session.clock.tick)
	await wait_frames(2)
	assert_eq(float(view.water_material().get_shader_parameter(&"blood")), 0.0)
	session.disasters.rest_until = 0
	session.interactions.disaster(DisasterSystem.TORNADO, fire)
	session.clock.tick += 5
	await wait_frames(2)
	var funnel := fx.get_node("Funnel") as Node3D
	assert_true(funnel.visible, "a whirlwind")
	assert_near(Vector2(funnel.global_position.x, funnel.global_position.z).distance_to(session.disasters.tornado_at(session.clock.tick)), 0.0, 1.0)
	session.clock.tick = session.disasters.until
	session.disasters.advance_to(session.clock.tick)
	await wait_frames(2)
	assert_false(funnel.visible)
