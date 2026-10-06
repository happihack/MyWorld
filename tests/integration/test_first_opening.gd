extends TestCase
## The first launch (VS.4, bible §26.1, §26.3): the box opens and the camera
## comes down to someone walking, "Something lives inside." — once, at most
## six seconds, a touch skips it — and the rest of the hint chain: the ☰
## glows at the first event, the motion hints (only while motion is on).


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	SaveManager.open_next = {}
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	Config.interaction.first_opening = true


func after_each() -> void:
	Config.interaction.first_opening = false
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _open_main() -> Node:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	return get_tree().current_scene


func _touch(pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = Vector2(540, 900)
	event.pressed = pressed
	Input.parse_input_event(event)


func test_the_first_opening() -> void:
	var main := await _open_main()
	var intro: BoxIntro = main.get("intro")
	assert_not_null(intro, "the first launch opens the box")
	assert_true(intro.is_running())
	var view: WorldView = main.get_node("WorldView")
	var rig := view.camera_rig()
	var ui: UIRoot = main.get_node("UIRoot")
	assert_true(rig.is_framed(), "the closed box on its table")
	assert_true(view.box_frame().lid().visible, "with its lid")
	assert_eq(ui.hints().current(), &"", "no hints while it opens")
	assert_false(ui.visible, "no menus, no buttons: only the box")
	assert_false(view.people_view().visible, "nothing seen through the lid")
	await wait_real_ms(1800)
	assert_true(view.box_frame().lid().rotation.x < -0.3, "the lid swings open")
	await wait_real_ms(4400) # (6.2 s in all: never longer than six)
	assert_null(main.get("intro"), "over")
	assert_false(view.box_frame().lid().visible)
	assert_true(ui.visible, "the HUD back")
	assert_true(view.people_view().visible)
	assert_true(ui.hints().is_completed(HintDirector.INTRO))
	# At rest above the one it came down to.
	var session: WorldSession = main.get_node("WorldSession")
	var person := session.people.get_person(main.get("_intro_person"))
	assert_not_null(person)
	var at := view.people_view().ground_position(person)
	assert_near(rig.distance(), BoxIntro.REST_DISTANCE, 0.5)
	assert_true(Vector2(rig.pivot().x, rig.pivot().z).distance_to(Vector2(at.x, at.z)) < 2.0, "on them")
	# No "Something lives inside." (the owner, 2026-10-05): nothing is said.
	ui.hints().advance(0.1)
	assert_ne(ui.hints().current(), HintDirector.INSIDE)


func test_a_touch_skips_it() -> void:
	var main := await _open_main()
	var view: WorldView = main.get_node("WorldView")
	assert_not_null(main.get("intro"))
	var answered := [0]
	(main.get_node("WorldSession") as WorldSession).interactions.responded.connect(func(_r: InteractionResponse) -> void: answered[0] += 1)
	_touch(true)
	_touch(false)
	await wait_frames(2)
	assert_null(main.get("intro"), "skipped")
	assert_eq(answered[0], 0, "that touch only ended the opening (what was under it has moved)")
	assert_false(view.box_frame().lid().visible)
	assert_near(view.camera_rig().distance(), BoxIntro.REST_DISTANCE, 0.5, "at rest above someone")


func test_every_time() -> void:
	var main := await _open_main()
	(main.get("intro") as BoxIntro).skip()
	await wait_frames(2)
	get_tree().unload_current_scene()
	await wait_frames(2)
	main = await _open_main()
	# (The owner, 2026-10-05: the box opens every time, as it did the first.)
	assert_not_null(main.get("intro"), "a later launch: the box opens again")
	(main.get("intro") as BoxIntro).skip()
	await wait_frames(2)
	assert_null(main.get("intro"))


func test_with_reduced_motion_it_is_simply_the_end() -> void:
	Settings.set_value(&"accessibility/reduced_motion", true)
	var main := await _open_main()
	assert_null(main.get("intro"), "no opening to watch")
	assert_true((main.get_node("UIRoot") as UIRoot).hints().is_completed(HintDirector.INTRO))
	assert_near((main.get_node("WorldView") as WorldView).camera_rig().distance(), BoxIntro.REST_DISTANCE, 0.5)


func test_the_menu_glows_at_the_first_event() -> void:
	var main := await _open_main()
	(main.get("intro") as BoxIntro).skip()
	var ui: UIRoot = main.get_node("UIRoot")
	var session: WorldSession = main.get_node("WorldSession")
	# (The world runs while it opens: something may already have happened
	# then — the first event all the same; else one is made to happen now.)
	if not ui.hints().is_completed(HintDirector.MENU_GLOW):
		assert_false(ui.menu_button().is_glowing())
		session.events.record(&"dry_spell", {"days": 6, "significance": 0.6})
	assert_true(ui.menu_button().is_glowing(), "the ☰, softly")
	assert_true(ui.hints().is_completed(HintDirector.MENU_GLOW), "once")
	# Once only: on the next launch it does not glow again.
	get_tree().unload_current_scene()
	await wait_frames(2)
	main = await _open_main()
	ui = main.get_node("UIRoot")
	(main.get_node("WorldSession") as WorldSession).events.record(&"dry_spell", {"days": 7, "significance": 0.6})
	assert_false(ui.menu_button().is_glowing())


func test_the_motion_hints() -> void:
	var label := HintLabel.new()
	add_child(label)
	var director := HintDirector.new(label)
	add_child(director)
	director.set_process(false)
	var motion := [false]
	director.motion_enabled = func() -> bool: return motion[0]
	for hint in [HintDirector.DRAG, HintDirector.TOUCH, HintDirector.HOLD, HintDirector.FOLLOW]:
		director.complete(hint)
	# Motion off (on hold): never.
	director.advance(200.0)
	director.note_tilt()
	director.advance(1.0)
	assert_eq(director.current(), &"")
	# Motion on: after three minutes of play, "Try tilting the box."
	motion[0] = true
	director.advance(1.0)
	assert_eq(director.current(), HintDirector.TILT)
	assert_eq(label.text(), "Try tilting the box.")
	# They tilt: done; and it is remarked on, once.
	director.note_tilt()
	assert_true(director.is_completed(HintDirector.TILT))
	director.advance(0.1)
	assert_eq(director.current(), HintDirector.MOVED)
	assert_eq(label.text(), "Something changed when you moved the world.")
	director.advance(5.0)
	assert_eq(director.current(), HintDirector.MOVED, "it stays a while")
	director.note_touch()
	director.advance(0.1)
	assert_eq(director.current(), &"")
	director.note_tilt()
	director.advance(10.0)
	assert_eq(director.current(), &"", "said once")
	director.queue_free()
	label.queue_free()
