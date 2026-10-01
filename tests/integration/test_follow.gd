extends TestCase
## Following people with the camera, and finding them (M5.2), in the running
## game: the Follow button, the banner, pausing and resuming, the Find chip.

const FRAME := 1.0 / 60.0

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var banner: FollowBanner
var followed: Array[int] = []
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
	followed.clear()
	EventBus.person_followed.connect(_on_followed)
	await _open_main()


func _open_main() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	router = main.get_node("InputRouter")
	banner = ui.follow_banner()
	rig = view.camera_rig()
	rig.set_process(false) # the tests step it by hand
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false # people stand where the tests put them


func after_each() -> void:
	EventBus.person_followed.disconnect(_on_followed)
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _on_followed(person_id: int) -> void:
	followed.append(person_id)


## Lets the game run, with the camera stepped by hand.
func _run(frames: int) -> void:
	for i in frames:
		await wait_frames(1)
		rig.advance(FRAME)


func _look_at(xz: Vector2, distance: float = 14.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	await _run(4)


func _gesture(type: Gesture.Type, pos: Vector2) -> void:
	var g := Gesture.new(type)
	g.position = pos
	g.start_position = pos
	router.gesture_recognized.emit(g)


## Someone who is up, with nobody else near them.
func _someone(but_not: int = 0) -> PersonData:
	var best: PersonData = null
	var most_room := -1.0
	for p in session.people.all_people():
		if p.has_flag(PersonData.FLAG_INDOORS) or p.id == but_not:
			continue
		var room := INF
		for other in session.people.all_people():
			if other.id != p.id:
				room = minf(room, other.world2d().distance_to(p.world2d()))
		if room > most_room:
			most_room = room
			best = p
	return best


## Where the person is seen on the screen (the middle of their body).
func _screen_of(person: PersonData) -> Vector2:
	return rig.world_to_screen(view.people_view().shown_position(person) + Vector3(0, PersonMeshLibrary.ADULT_HEIGHT * 0.5, 0))


## Where they should be kept, given what is on the screen.
func _anchor() -> Vector2:
	var card := ui.person_card()
	var bottom := card.get_global_rect().position.y if card != null else ui.tool_bar().get_global_rect().position.y
	return CameraFollow.anchor(rig.view_size(), banner.bottom(), bottom)


## Moves a person over the ground as if walking (no checks: the tests vouch).
func _walk(person: PersonData, step: Vector2, frames: int) -> void:
	for i in frames:
		var at := person.world2d() + step
		var tile := Vector2i(floori(at.x), floori(at.y))
		session.people.place(person, tile, at - Vector2(tile), person.facing)
		await _run(1)


# --- the state ------------------------------------------------------------------------------------

func test_following_is_off_on_or_paused() -> void:
	var f := CameraFollow.new()
	var changes: Array = []
	f.changed.connect(func() -> void: changes.append(1))
	assert_false(f.is_active())
	f.pause()
	f.resume()
	f.stop()
	assert_eq(changes.size(), 0, "nothing to pause, resume or stop")
	f.start(7)
	assert_true(f.is_following() and f.is_active())
	assert_eq(f.person_id, 7)
	f.start(7)
	assert_eq(changes.size(), 1, "already following them")
	f.pause()
	assert_eq(f.state, CameraFollow.State.PAUSED)
	assert_true(f.is_active() and not f.is_following())
	assert_eq(f.person_id, 7, "still the one followed")
	f.pause()
	assert_eq(changes.size(), 2)
	f.resume()
	assert_true(f.is_following())
	f.pause()
	f.start(7)
	assert_true(f.is_following(), "starting again resumes")
	f.start(9)
	assert_eq(f.person_id, 9, "someone else: the first is let go")
	f.stop()
	assert_eq(f.person_id, 0)
	assert_eq(f.state, CameraFollow.State.OFF)
	f.start(3)
	f.start(0)
	assert_false(f.is_active(), "following nobody is not following")


func test_the_followed_person_is_kept_in_what_is_free_of_the_screen() -> void:
	var screen := Vector2(1080, 1920)
	assert_eq(CameraFollow.anchor(screen, 56.0, 1500.0), Vector2(540, 778), "in the middle of what is free")
	assert_near(CameraFollow.anchor(screen, 56.0, 1900.0).y, 1920 * CameraFollow.LOWEST, 0.001, "never below the middle")
	assert_near(CameraFollow.anchor(screen, 56.0, 400.0).y, 1920 * CameraFollow.HIGHEST, 0.001, "never squeezed against the top")


func test_the_camera_can_keep_a_point_under_a_place_on_the_screen() -> void:
	await _look_at(Vector2(2.5, 3.5), 14.0)
	var point := Vector3(6.2, session.world.get_height(Vector2i(6, -1)) * session.world.height_step, -0.7)
	var screen := Vector2(540, 700)
	for i in 240:
		rig.track(point, screen)
		rig.advance(FRAME)
	assert_true(rig.world_to_screen(point).distance_to(screen) < 3.0, "%s" % rig.world_to_screen(point))
	assert_near(rig.distance(), 14.0, 0.01, "from as far as before")
	# Not against a finger on the view.
	_gesture(Gesture.Type.DRAG_START, Vector2(500, 900))
	var held := rig.pivot()
	rig.track(point + Vector3(5, 0, 5), screen)
	rig.advance(FRAME)
	assert_eq(rig.pivot(), held)
	_gesture(Gesture.Type.DRAG_END, Vector2(500, 900))
	# Never out of the world.
	for i in 240:
		rig.track(Vector3(5000, 0, 5000), screen)
		rig.advance(FRAME)
	assert_true(rig.pivot().is_equal_approx(rig.clamped_pivot()))


func test_the_banner_says_what_is_going_on() -> void:
	var b := FollowBanner.new()
	add_child(b)
	await wait_frames(1)
	assert_eq(b.follow_text(), "")
	assert_eq(b.locate_text(), "")
	assert_false(b.button(&"follow").is_visible_in_tree())
	assert_eq(b.bottom(), FollowBanner.TOP)
	b.set_following("Mara")
	await wait_frames(1)
	assert_eq(b.follow_text(), "Following Mara")
	assert_false(b.is_paused())
	assert_true(b.button(&"stop").is_visible_in_tree())
	assert_true(b.bottom() > FollowBanner.TOP + 50.0)
	var rect := b.button(&"follow").get_global_rect().merge(b.button(&"stop").get_global_rect())
	assert_near(rect.get_center().x, get_viewport().get_visible_rect().size.x * 0.5, 2.0, "in the middle of the top")
	b.set_following("Mara", true)
	assert_eq(b.follow_text(), "Resume following Mara")
	assert_true(b.is_paused())
	b.set_locate("Joren")
	await wait_frames(1)
	assert_eq(b.locate_text(), "Find Joren")
	assert_true(b.button(&"locate").get_global_rect().position.y >= b.button(&"follow").get_global_rect().end.y, "one under the other")
	assert_eq(b.bottom(), b.button(&"locate").get_global_rect().end.y)
	var pressed: Array = []
	b.follow_pressed.connect(func() -> void: pressed.append(&"follow"))
	b.stop_pressed.connect(func() -> void: pressed.append(&"stop"))
	b.locate_pressed.connect(func() -> void: pressed.append(&"locate"))
	for which: StringName in [&"follow", &"stop", &"locate"]:
		b.button(which).pressed.emit()
		assert_true(b.button(which).is_in_group(InputRouter.UI_BLOCKER_GROUP), "touches on it never reach the world")
		assert_true(b.button(which).get_global_rect().size.y >= UITheme.TOUCH_TARGET * 0.7, "big enough for a finger")
	assert_eq(pressed, [&"follow", &"stop", &"locate"])
	b.set_following("")
	b.set_locate("")
	assert_eq(b.follow_text(), "")
	assert_eq(b.locate_text(), "")
	b.queue_free()


# --- in the game ----------------------------------------------------------------------------------

func test_follow_from_the_card() -> void:
	var person := _someone()
	await _look_at(person.world2d() + Vector2(5.0, 4.0), 30.0)
	main.select_person(person.id, PersonCard.State.HALF)
	await _run(2)
	var card := ui.person_card()
	assert_not_null(card.button(&"follow"))
	assert_true(card.button(&"follow").is_visible_in_tree())
	assert_false(card.button(&"follow").button_pressed)
	assert_eq(banner.follow_text(), "")
	# Five words in a row, none cut off or off the card.
	for which: StringName in [&"observe", &"touch", &"follow", &"focus", &"more"]:
		var b := card.button(which)
		assert_true(card.get_global_rect().encloses(b.get_global_rect()), "%s is on the card" % which)
		assert_true(b.get_global_rect().size.x >= b.get_theme_font(&"font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size(&"font_size")).x, "%s is not cut off" % which)
	card.button(&"follow").pressed.emit()
	assert_true(main.follow.is_following())
	assert_eq(main.follow.person_id, person.id)
	assert_eq(followed, [person.id])
	assert_true(person.has_flag(PersonData.FLAG_FOLLOWED))
	assert_eq(person.sim_tier, TierManager.FOCUS)
	assert_eq(banner.follow_text(), "Following %s" % person.given_name)
	assert_true(card.button(&"follow").button_pressed, "the button shows it")
	assert_true(card.is_following())
	# The camera comes to them — closer, and with them in what is free above the card.
	await _run(300)
	assert_true(rig.distance() <= Config.camera.home_distance + 0.01, "it came closer")
	var at := _screen_of(person)
	assert_true(at.distance_to(_anchor()) < 6.0, "%s is not at %s" % [at, _anchor()])
	assert_true(at.y < card.get_global_rect().position.y, "above the card")
	assert_true(at.y >= rig.view_size().y * CameraFollow.HIGHEST - 6.0)
	# The card taller: they move up out of its way.
	card.set_state(PersonCard.State.FULL)
	await _run(300)
	at = _screen_of(person)
	assert_true(at.distance_to(_anchor()) < 6.0, "%s is not at %s" % [at, _anchor()])
	assert_true(at.y < card.get_global_rect().position.y or is_equal_approx(_anchor().y, rig.view_size().y * CameraFollow.HIGHEST),
		"above the card, as long as there is room")
	# The card away: back toward the middle.
	card.close()
	await _run(300)
	assert_true(main.follow.is_following(), "closing the card is not letting go")
	assert_eq(main.selected_person_id(), 0)
	assert_eq(person.sim_tier, TierManager.FOCUS, "still followed, still in focus")
	assert_true(_screen_of(person).distance_to(_anchor()) < 6.0)
	# Pressing Follow again on their card stops it.
	main.select_person(person.id, PersonCard.State.HALF)
	await _run(2)
	assert_true(ui.person_card().button(&"follow").button_pressed)
	ui.person_card().button(&"follow").pressed.emit()
	assert_false(main.follow.is_active())
	assert_false(ui.person_card().button(&"follow").button_pressed)
	assert_false(person.has_flag(PersonData.FLAG_FOLLOWED))
	assert_eq(banner.follow_text(), "")
	assert_eq(followed, [person.id, -1])
	assert_eq(person.sim_tier, TierManager.FOCUS, "still selected")
	main.clear_selection()
	assert_eq(person.sim_tier, TierManager.ACTIVE)


func test_the_camera_keeps_up_with_someone_walking() -> void:
	var person := _someone()
	await _look_at(person.world2d(), 14.0)
	assert_true(main.follow_person(person.id))
	await _run(200)
	var start := rig.pivot()
	var worst := 0.0
	for i in 12:
		await _walk(person, Vector2(0.02, 0.012), 20) # (about 1.4 tiles a second: a brisk walk)
		worst = maxf(worst, _screen_of(person).distance_to(_anchor()))
	assert_true(Vector2(rig.pivot().x - start.x, rig.pivot().z - start.z).length() > 4.0, "the camera went with them")
	print("    follow: a walker strays at most %.0f units from where they are kept" % worst)
	assert_true(worst < rig.view_size().y * 0.04, "never far from where they are kept (%.0f)" % worst)
	await _run(240)
	assert_true(_screen_of(person).distance_to(_anchor()) < 6.0, "and on them again when they stop")
	# Zooming with two fingers does not let go.
	_gesture(Gesture.Type.MULTI_START, Vector2(540, 900))
	var pinch := Gesture.new(Gesture.Type.PINCH)
	pinch.position = Vector2(300, 500)
	pinch.scale = 1.4
	router.gesture_recognized.emit(pinch)
	_gesture(Gesture.Type.MULTI_END, Vector2(540, 900))
	assert_true(main.follow.is_following())
	await _run(240)
	assert_true(rig.distance() < 14.0 - 1.0, "closer now")
	assert_true(_screen_of(person).distance_to(_anchor()) < 6.0, "and still on them")
	# Carrying something: the view is the hand's for the while.
	assert_false(main.follow_person(999_999), "nobody there to follow")
	assert_eq(main.follow.person_id, person.id)


func test_dragging_the_view_away_pauses_and_the_banner_resumes() -> void:
	var person := _someone()
	await _look_at(person.world2d(), 14.0)
	main.follow_person(person.id)
	await _run(120)
	_gesture(Gesture.Type.DRAG_START, Vector2(540, 900))
	var drag := Gesture.new(Gesture.Type.DRAG)
	drag.position = Vector2(540, 600)
	drag.delta = Vector2(0, -300)
	router.gesture_recognized.emit(drag)
	_gesture(Gesture.Type.DRAG_END, Vector2(540, 600))
	assert_eq(main.follow.state, CameraFollow.State.PAUSED)
	assert_eq(main.follow.person_id, person.id)
	assert_eq(banner.follow_text(), "Resume following %s" % person.given_name)
	assert_true(person.has_flag(PersonData.FLAG_FOLLOWED), "still the one followed")
	assert_eq(person.sim_tier, TierManager.FOCUS)
	assert_eq(followed, [person.id], "nothing new to tell the world")
	await _run(120)
	var left_at := rig.pivot()
	await _walk(person, Vector2(0.03, 0.0), 40)
	assert_true(rig.pivot().is_equal_approx(left_at), "the view stays where it was put")
	assert_true(_screen_of(person).distance_to(_anchor()) > 100.0)
	# Their card, opened meanwhile, shows that the camera is not with them.
	main.select_person(person.id, PersonCard.State.HALF)
	await _run(2)
	assert_false(ui.person_card().button(&"follow").button_pressed)
	ui.person_card().close()
	await _run(2)
	# The banner takes it up again.
	banner.button(&"follow").pressed.emit()
	assert_true(main.follow.is_following())
	assert_eq(banner.follow_text(), "Following %s" % person.given_name)
	await _run(300)
	assert_true(_screen_of(person).distance_to(_anchor()) < 6.0)
	# While following, the banner's name opens their card.
	assert_eq(main.selected_person_id(), 0)
	banner.button(&"follow").pressed.emit()
	assert_eq(main.selected_person_id(), person.id)
	assert_true(main.follow.is_following())
	# Its ✕ lets go.
	banner.button(&"stop").pressed.emit()
	assert_false(main.follow.is_active())
	assert_eq(banner.follow_text(), "")
	assert_eq(followed, [person.id, -1])
	assert_false(person.has_flag(PersonData.FLAG_FOLLOWED))
	await _run(2)
	assert_false(ui.person_card().button(&"follow").button_pressed)


func test_looking_elsewhere_pauses_and_looking_at_them_resumes() -> void:
	var person := _someone()
	var other := _someone(person.id)
	await _look_at(person.world2d(), 14.0)
	main.follow_person(person.id)
	await _run(60)
	# Home.
	ui.home_pressed.emit()
	assert_eq(main.follow.state, CameraFollow.State.PAUSED)
	main.follow_person(person.id)
	assert_true(main.follow.is_following())
	# Someone else chosen from a list (a marked name, family): the camera goes to them.
	main._on_person_chosen(other.id)
	assert_eq(main.follow.state, CameraFollow.State.PAUSED)
	assert_eq(main.selected_person_id(), other.id)
	await _run(300)
	assert_near(rig.pivot().x, other.world2d().x, 0.2)
	# Tapping someone else selects them without taking the camera off the followed one.
	main.follow_person(person.id)
	main.select_person(other.id, PersonCard.State.HALF)
	await _run(2)
	assert_true(main.follow.is_following())
	assert_false(ui.person_card().button(&"follow").button_pressed, "this is not the one followed")
	assert_eq(person.sim_tier, TierManager.FOCUS)
	assert_eq(other.sim_tier, TierManager.FOCUS, "both in focus")
	# Focus on the other: paused. Focus on the followed one: resumed.
	ui.person_card().button(&"focus").pressed.emit()
	assert_eq(main.follow.state, CameraFollow.State.PAUSED)
	main.focus_on_person(person.id)
	assert_true(main.follow.is_following())
	# Follow pressed on the other's card: the camera changes people.
	ui.person_card().button(&"follow").pressed.emit()
	assert_eq(main.follow.person_id, other.id)
	assert_true(main.follow.is_following())
	assert_eq(followed, [person.id, other.id])
	assert_false(person.has_flag(PersonData.FLAG_FOLLOWED))
	assert_true(other.has_flag(PersonData.FLAG_FOLLOWED))
	assert_eq(person.sim_tier, TierManager.ACTIVE, "the first is let go")
	assert_eq(banner.follow_text(), "Following %s" % other.given_name)
	assert_true(ui.person_card().button(&"follow").button_pressed)
	# A double tap on something else looks at that.
	var hut := session.props.get_prop(session.start.hut_ids[0])
	main.follow.resume()
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = hut.id
	target.tile = hut.tile
	main._on_context_action(InteractionManager.ACTION_FOCUS, target)
	assert_eq(main.follow.state, CameraFollow.State.PAUSED)


func test_someone_followed_who_dies_is_let_go() -> void:
	var person := _someone()
	main.follow_person(person.id)
	main.select_person(person.id)
	await _run(4)
	session.kill_person(person.id)
	await _run(4)
	assert_false(main.follow.is_active())
	assert_eq(banner.follow_text(), "")
	assert_eq(followed, [person.id, -1])
	assert_null(ui.person_card())
	assert_eq(session.simulation.tiers.focused().size(), 0)


func test_who_was_followed_is_offered_again_after_a_relaunch() -> void:
	var person := _someone()
	main.follow_person(person.id)
	await _run(4)
	SaveManager.save_world(session, &"test")
	get_tree().unload_current_scene()
	await wait_frames(2)
	followed.clear()
	await _open_main()
	var back := session.people.get_person(person.id)
	assert_true(back.has_flag(PersonData.FLAG_FOLLOWED))
	assert_eq(main.follow.state, CameraFollow.State.PAUSED, "offered, not imposed: the game opens on the settlement")
	assert_eq(main.follow.person_id, person.id)
	assert_eq(banner.follow_text(), "Resume following %s" % person.given_name)
	assert_eq(followed, [person.id])
	assert_eq(back.sim_tier, TierManager.FOCUS)
	banner.button(&"follow").pressed.emit()
	assert_true(main.follow.is_following())
	await _run(300)
	assert_true(_screen_of(back).distance_to(_anchor()) < 6.0)
	# Let go, saved, reopened: nobody is followed.
	main.stop_following()
	SaveManager.save_world(session, &"test")
	get_tree().unload_current_scene()
	await wait_frames(2)
	await _open_main()
	assert_false(main.follow.is_active())
	assert_eq(banner.follow_text(), "")


func test_someone_selected_and_out_of_sight_can_be_found() -> void:
	var person := _someone()
	await _look_at(person.world2d(), 14.0)
	main.select_person(person.id)
	await _run(3)
	assert_eq(banner.locate_text(), "", "in sight: nothing to find")
	# The view goes elsewhere.
	await _look_at(person.world2d() + Vector2(25.0, 20.0), 14.0)
	await _run(2)
	assert_eq(banner.locate_text(), "Find %s" % person.given_name)
	assert_true(banner.button(&"locate").is_visible_in_tree())
	assert_true(router.is_over_ui(banner.button(&"locate").get_global_rect().get_center()))
	banner.button(&"locate").pressed.emit()
	await _run(300)
	assert_near(rig.pivot().x, person.world2d().x, 0.2, "the camera went to them")
	assert_near(rig.pivot().z, person.world2d().y, 0.2)
	assert_eq(banner.locate_text(), "")
	# Hidden behind their own card counts as out of sight.
	ui.person_card().set_state(PersonCard.State.FULL)
	await _run(3)
	var under := rig.world_to_screen(view.people_view().ground_position(person)).y >= ui.person_card().get_global_rect().position.y
	assert_eq(banner.locate_text() != "", under)
	# Nobody selected: nothing to find. Followed: never out of sight.
	await _look_at(person.world2d() + Vector2(25.0, 20.0), 14.0)
	await _run(2)
	assert_ne(banner.locate_text(), "")
	main.follow_person(person.id)
	await _run(2)
	assert_eq(banner.locate_text(), "", "the camera is on its way to them")
	main.stop_following()
	await _look_at(person.world2d() + Vector2(25.0, 20.0), 14.0)
	main.clear_selection()
	await _run(2)
	assert_eq(banner.locate_text(), "")
