extends TestCase
## Selecting people and their card (M5.1) in the running game: a tap selects
## (and, with the hand, touches), the card says who they are and what they
## are about, and offers what can be done.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var heard: Array[InteractionResponse] = []
var selected: Array[int] = []
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
	heard.clear()
	selected.clear()
	session.interactions.responded.connect(func(r: InteractionResponse) -> void: heard.append(r))
	EventBus.person_selected.connect(_on_selected)


func after_each() -> void:
	EventBus.person_selected.disconnect(_on_selected)
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _on_selected(person_id: int) -> void:
	selected.append(person_id)


func _look_at(xz: Vector2, distance: float = 14.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)
	await wait_frames(2)


func _tap(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = pos
		t.pressed = pressed
		get_tree().root.push_input(t, true)


func _gesture(type: Gesture.Type, pos: Vector2) -> void:
	var g := Gesture.new(type)
	g.position = pos
	g.start_position = pos
	router.gesture_recognized.emit(g)


## Someone who is up and standing still, with nobody else near them.
func _someone(but_not: int = 0) -> PersonData:
	session.behavior.enabled = false # (everyone holds still to be tapped)
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


func _screen_of(person: PersonData) -> Vector2:
	return rig.world_to_screen(view.people_view().ground_position(person) + Vector3(0, PersonMeshLibrary.ADULT_HEIGHT * 0.5, 0))


## Open ground near a person with nobody on it.
func _open_ground_near(person: PersonData) -> Vector2:
	var open := Vector3.ZERO
	for offset: Vector3 in [Vector3(3, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3), Vector3(3, 0, 3), Vector3(-3, 0, -3)]:
		open = view.people_view().ground_position(person) + offset
		var crowded := false
		for other in session.people.all_people():
			if other.world2d().distance_to(Vector2(open.x, open.z)) < 2.0:
				crowded = true
		if not crowded:
			break
	return rig.world_to_screen(open)


# --- words ----------------------------------------------------------------------------------------

func test_the_words_of_the_card() -> void:
	for need_name in Needs.NAMES:
		assert_true(UIText.NEED_LABELS.has(need_name), "a word for %s" % need_name)
	assert_eq(UIText.need_label(&"hunger"), "Food")
	assert_eq(UIText.need_label(&"thirst"), "Water")
	assert_eq(UIText.need_label(&"something_new"), "Something New", "a need without a word still reads")
	assert_eq(UIText.age_text(0), "A baby")
	assert_eq(UIText.age_text(1), "1 year")
	assert_eq(UIText.age_text(34), "34 years")
	assert_eq(UIText.mood_word(0.9), "Content")
	assert_eq(UIText.mood_word(0.7), "At ease")
	assert_eq(UIText.mood_word(0.5), "Restless")
	assert_eq(UIText.mood_word(0.2), "Troubled")
	assert_eq(UIText.mood_word(0.9, 0.5), "Strained", "stress speaks louder than mood")
	assert_eq(UIText.mood_word(0.9, 0.9), "Desperate")
	assert_eq(UIText.relation_word(&"parent", PersonData.Sex.FEMALE), "Mother")
	assert_eq(UIText.relation_word(&"parent", PersonData.Sex.MALE), "Father")
	assert_eq(UIText.relation_word(&"child", PersonData.Sex.FEMALE), "Daughter")
	assert_eq(UIText.relation_word(&"child", PersonData.Sex.MALE), "Son")
	assert_eq(UIText.relation_word(&"partner", PersonData.Sex.MALE), "Partner")


func test_the_facts_about_a_person() -> void:
	var parent: PersonData = null
	for p in session.people.all_people():
		if not p.children.is_empty() and p.partner_id != 0:
			parent = p
			break
	assert_not_null(parent, "the band has a family")
	parent.needs = PackedFloat32Array([0.1, 0.9, 0.8, 0.7, 0.6, 1.0])
	parent.mood = 0.9
	parent.stress = 0.0
	session.clock.tick = 4 * 60
	session.behavior.think(parent)
	parent.mood = 0.9 # (thinking brings mood and stress up to date)
	parent.stress = 0.0
	var facts := PersonCard.facts(session, parent)
	assert_eq(facts["name"], parent.full_name())
	assert_eq(facts["age"], "%d years" % parent.age_years(session.clock.tick, Config.time.ticks_per_year()))
	assert_eq(facts["occupation"], UIText.occupation_name(parent.occupation_id))
	assert_eq(facts["activity"], "Eating — hungry")
	assert_eq(facts["mood"], "Content")
	assert_eq((facts["needs"] as PackedFloat32Array).size(), Needs.COUNT)
	assert_near((facts["needs"] as PackedFloat32Array)[Needs.Need.HUNGER], 0.1, 0.001)
	assert_eq(facts["traits"], UIText.trait_words(parent.traits))
	assert_false(facts["marked"])
	var family: Array = facts["family"]
	assert_eq(family.size(), 1 + parent.children.size(), "partner and children")
	assert_eq(family[0][0], parent.partner_id)
	assert_eq(family[0][1], "Partner")
	var child := session.people.get_person(parent.children[0])
	assert_eq(family[1], [child.id, "Daughter" if child.sex == PersonData.Sex.FEMALE else "Son", child.given_name])
	# The child's card names its parents.
	var of_child: Array = PersonCard.facts(session, child)["family"]
	assert_eq(of_child.size(), child.parents.size())
	for entry: Array in of_child:
		assert_true(entry[1] == "Mother" or entry[1] == "Father", str(entry))
	assert_eq(PersonCard.facts(session, child)["occupation"], "Child")
	# Family who are gone are not offered.
	session.kill_person(child.id)
	assert_eq((PersonCard.facts(session, parent)["family"] as Array).size(), family.size() - 1)
	# Someone with nothing to do, and broken needs.
	parent.current_action = {}
	parent.needs = PackedFloat32Array([NAN, 7.0])
	facts = PersonCard.facts(session, parent)
	assert_eq(facts["activity"], UIText.ACTIVITY_NAMES[&"idle"])
	for value: float in facts["needs"]:
		assert_true(value >= 0.0 and value <= 1.0, "never a broken bar")
	parent.set_flag(PersonData.FLAG_MARKED_IMPORTANT, true)
	assert_true(PersonCard.facts(session, parent)["marked"])


func test_need_bars_warm_as_they_empty() -> void:
	assert_eq(NeedBar.color_for(1.0), NeedBar.FULL)
	assert_eq(NeedBar.color_for(0.5), NeedBar.LOW)
	assert_eq(NeedBar.color_for(0.0), NeedBar.EMPTY)
	var bar := NeedBar.new()
	bar.value = 7.0
	assert_eq(bar.value, 1.0)
	bar.value = -1.0
	assert_eq(bar.value, 0.0)
	bar.free()


# --- selecting ------------------------------------------------------------------------------------

func test_a_tap_with_the_hand_touches_and_selects() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	assert_eq(main.selected_person_id(), 0)
	assert_null(ui.person_card())
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(main.selected_person_id(), person.id)
	assert_eq(selected, [person.id], "said once")
	assert_eq(person.sim_tier, TierManager.FOCUS, "whoever is selected is simulated most closely")
	# The touch: an intervention on a person, gentle, remembered.
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].effect, InteractionResponse.PERSON_TOUCH)
	assert_eq(heard[0].person_id, person.id)
	assert_eq(InteractionManager.subject_of(heard[0]), &"person")
	assert_true(person.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	assert_eq(session.history.total(), 1)
	assert_eq(UIText.subject_name(heard[0]), "Someone")
	# The card: short, with who and what.
	var card := ui.person_card()
	assert_not_null(card)
	assert_eq(card.person_id(), person.id)
	assert_eq(card.state(), PersonCard.State.PEEK)
	assert_eq(card.name_text(), person.full_name())
	assert_ne(card.activity_text(), "")
	assert_false((card.get_node("%Body") as Control).visible, "only a peek")
	assert_true(card.get_global_rect().end.y < ui.tool_bar().get_global_rect().position.y, "above the tools")
	assert_true(card.get_global_rect().position.x >= 0.0 and card.get_global_rect().end.x <= get_viewport().get_visible_rect().size.x)
	assert_true(router.is_over_ui(card.get_global_rect().get_center()), "touches on it never reach the world")
	# In the world: ringed and outlined.
	assert_true(view.people_view().ring_shown())
	assert_true(view.people_view().view_of(person.id).is_outlined(view.people_view().selected_material()))
	# A second tap touches again, selects no more than before.
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(heard.size(), 2)
	assert_eq(selected, [person.id])
	assert_true(ui.person_card() == card, "the same card")
	# A tap on the ground touches the ground; they stay selected.
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_tap(_open_ground_near(person))
	await wait_frames(2)
	assert_eq(heard.size(), 3)
	assert_eq(heard[2].person_id, 0)
	assert_eq(main.selected_person_id(), person.id)
	# Someone else: the card changes hands, the first is let go.
	var other := _someone(person.id)
	await _look_at(other.world2d())
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_tap(_screen_of(other))
	await wait_frames(2)
	assert_eq(main.selected_person_id(), other.id)
	assert_eq(selected, [person.id, other.id], "never 'nobody' in between")
	assert_eq(ui.person_card().person_id(), other.id)
	assert_eq(ui.panel_count(), 1, "one card")
	assert_eq(person.sim_tier, TierManager.ACTIVE)
	assert_eq(other.sim_tier, TierManager.FOCUS)


func test_looking_selects_without_touching() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	main.tools.select(ObserveTool.ID)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(main.selected_person_id(), person.id)
	assert_not_null(ui.person_card())
	assert_eq(heard.size(), 0, "nothing was touched")
	assert_false(person.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	assert_eq(session.history.total(), 0)
	# Looking at the ground instead: the inspect card takes the person card's place.
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_tap(_open_ground_near(person))
	await wait_frames(2)
	assert_true(ui.top_panel() is InspectCard)
	assert_eq(ui.panel_count(), 1)
	assert_eq(main.selected_person_id(), 0, "and the person is let go")
	assert_eq(selected, [person.id, -1])
	assert_false(view.people_view().ring_shown())
	# ...and the other way round.
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_true(ui.top_panel() is PersonCard)
	assert_eq(ui.panel_count(), 1)


func test_a_long_press_opens_the_card_with_what_can_be_done() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	_gesture(Gesture.Type.LONG_PRESS, _screen_of(person))
	await wait_frames(2)
	assert_eq(main.selected_person_id(), person.id)
	var card := ui.person_card()
	assert_not_null(card)
	assert_eq(card.state(), PersonCard.State.HALF)
	assert_eq(ui.panel_count(), 1, "the card, not the menu")
	assert_eq(heard.size(), 0, "a press is not a touch")
	assert_true((card.get_node("%Body") as Control).visible)
	assert_false((card.get_node("%More") as Control).visible)
	for which: StringName in [&"observe", &"touch", &"focus", &"more", &"mark", &"close"]:
		assert_not_null(card.button(which), String(which))
		assert_true(card.button(which).is_visible_in_tree(), String(which))
		assert_true(card.button(which).get_global_rect().size.y >= UITheme.TOUCH_TARGET * 0.7, "%s is big enough for a finger" % which)
	assert_has(card.about_text(), UIText.mood_word(person.mood, person.stress))
	assert_has(card.about_text(), "years")
	assert_eq(card.need_values().size(), Needs.COUNT)
	for need in Needs.COUNT:
		assert_near(card.need_values()[need], person.needs[need], 0.001)
	assert_ne(card.traits_text(), "")
	# A tap on them afterwards does not make the card smaller.
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(ui.person_card().state(), PersonCard.State.HALF)


func test_a_double_tap_looks_at_them() -> void:
	var person := _someone()
	var beside := person.world2d() + Vector2(2.0, 1.5)
	await _look_at(beside, 12.0)
	var before := rig.distance()
	_tap(_screen_of(person))
	_tap(_screen_of(person))
	for i in 300:
		rig.advance(1.0 / 60.0)
	await wait_frames(2)
	assert_near(rig.pivot().x, person.world2d().x, 0.2, "centred on them")
	assert_near(rig.pivot().z, person.world2d().y, 0.2)
	assert_true(rig.distance() <= before + 0.01)
	assert_eq(main.selected_person_id(), person.id)
	assert_eq(heard.size(), 1, "touched once: the second tap was the look")


func test_other_tools_keep_their_own_tap() -> void:
	var person := _someone()
	await _look_at(person.world2d())
	main.tools.select(CallTool.ID)
	_tap(_screen_of(person))
	await wait_frames(2)
	assert_eq(main.selected_person_id(), 0, "calling is not selecting")
	assert_null(ui.person_card())


# --- the card -------------------------------------------------------------------------------------

func test_the_card_grows_and_shrinks() -> void:
	var person := _someone()
	main.select_person(person.id)
	await wait_frames(2)
	var card := ui.person_card()
	var states: Array = []
	card.state_changed.connect(func(s: PersonCard.State) -> void: states.append(s))
	var peek := card.size.y
	var bottom := card.get_global_rect().end.y
	card.set_state(PersonCard.State.HALF)
	await wait_frames(2)
	var half := card.size.y
	assert_true(half > peek + 100.0, "more to see")
	assert_near(card.get_global_rect().end.y, bottom, 1.0, "it grows upward")
	card.button(&"more").pressed.emit()
	await wait_frames(2)
	assert_eq(card.state(), PersonCard.State.FULL)
	assert_eq(card.button(&"more").text, "Less")
	assert_true(card.size.y > half, "and more")
	assert_true(card.get_global_rect().position.y > 0.0, "still on the screen")
	assert_true((card.get_node("%More") as Control).visible)
	card.button(&"more").pressed.emit()
	await wait_frames(2)
	assert_eq(card.state(), PersonCard.State.HALF)
	assert_near(card.size.y, half, 1.0, "back to what it was")
	card.set_state(PersonCard.State.HALF)
	assert_eq(states, [PersonCard.State.HALF, PersonCard.State.FULL, PersonCard.State.HALF], "said when it changes, only then")
	# The header is a handle: a tap toggles, drags step, down from the shortest closes.
	var header := card.get_node("%Header") as Control
	var at := header.get_global_rect().get_center()
	_header_touch(header, at, true)
	_header_touch(header, at, false)
	assert_eq(card.state(), PersonCard.State.PEEK, "a tap on the header folds it")
	_header_touch(header, at, true)
	_header_touch(header, at, false)
	assert_eq(card.state(), PersonCard.State.HALF, "and unfolds it")
	_header_touch(header, at, true)
	_header_drag(header, at + Vector2(0, -PersonCard.DRAG_STEP - 5.0))
	assert_eq(card.state(), PersonCard.State.FULL, "dragged up")
	_header_drag(header, at + Vector2(0, -PersonCard.DRAG_STEP * 2.0 - 10.0))
	assert_eq(card.state(), PersonCard.State.FULL, "no higher than full")
	_header_touch(header, at + Vector2(0, -PersonCard.DRAG_STEP * 2.0 - 10.0), false)
	assert_eq(card.state(), PersonCard.State.FULL, "letting go after a drag is not a tap")
	_header_touch(header, at, true)
	_header_drag(header, at + Vector2(0, PersonCard.DRAG_STEP + 5.0))
	_header_drag(header, at + Vector2(0, PersonCard.DRAG_STEP * 2.0 + 10.0))
	assert_eq(card.state(), PersonCard.State.PEEK, "dragged down twice")
	_header_drag(header, at + Vector2(0, PersonCard.DRAG_STEP * 3.0 + 15.0))
	assert_true(card.is_closing(), "and once more: away")
	await wait_frames(2)
	assert_eq(main.selected_person_id(), 0)
	assert_eq(selected, [person.id, -1])


func _header_touch(header: Control, at: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = at
	t.pressed = pressed
	header.gui_input.emit(t)


func _header_drag(header: Control, to: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = to
	header.gui_input.emit(d)


func test_the_card_follows_the_person() -> void:
	var person := _someone()
	main.select_person(person.id, PersonCard.State.HALF)
	await wait_frames(2)
	var card := ui.person_card()
	person.needs[Needs.Need.HUNGER] = 0.05
	session.behavior.set_plan(person, &"sleep", &"sleep", [RestStep.make(600.0)], 1.0)
	await wait_real_ms(400) # (the card refreshes four times a second)
	assert_near(card.need_values()[Needs.Need.HUNGER], 0.05, 0.001)
	assert_eq(card.activity_text(), "Sleeping — tired")
	# They die: the card goes, and the selection.
	session.kill_person(person.id)
	await wait_frames(2)
	assert_null(ui.person_card())
	assert_eq(main.selected_person_id(), 0)
	assert_eq(selected, [person.id, -1])
	assert_false(view.people_view().ring_shown())
	assert_false(main.select_person(person.id), "nobody there to select")


func test_closing_the_card_lets_go() -> void:
	var person := _someone()
	main.select_person(person.id)
	await wait_frames(2)
	ui.person_card().button(&"close").pressed.emit()
	await wait_frames(2)
	assert_eq(main.selected_person_id(), 0)
	assert_null(ui.person_card())
	assert_eq(ui.panel_count(), 0)
	assert_eq(person.sim_tier, TierManager.ACTIVE)
	# The back button does the same.
	main.select_person(person.id)
	await wait_frames(2)
	EventBus.back_requested.emit()
	await wait_frames(2)
	assert_eq(main.selected_person_id(), 0)
	assert_eq(selected, [person.id, -1, person.id, -1])


# --- what can be done -----------------------------------------------------------------------------

func test_touch_and_focus_from_the_card() -> void:
	var person := _someone()
	await _look_at(person.world2d() + Vector2(4.0, 3.0), 16.0)
	main.select_person(person.id, PersonCard.State.HALF)
	await wait_frames(2)
	var card := ui.person_card()
	card.button(&"touch").pressed.emit()
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].person_id, person.id)
	assert_true(person.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	assert_true(Vector2(heard[0].position.x, heard[0].position.z).distance_to(person.world2d()) < 0.01, "where they stand")
	card.button(&"focus").pressed.emit()
	for i in 300:
		rig.advance(1.0 / 60.0)
	assert_near(rig.pivot().x, person.world2d().x, 0.2)
	assert_near(rig.pivot().z, person.world2d().y, 0.2)
	assert_true(rig.distance() <= 16.01, "never zooms out to look at someone")


func test_observing_shows_the_way_they_are_going() -> void:
	var person := _someone()
	main.select_person(person.id, PersonCard.State.HALF)
	await wait_frames(2)
	var card := ui.person_card()
	var people_view := view.people_view()
	assert_false(main.is_observing())
	assert_eq(card.button(&"observe").text, "Observe")
	card.button(&"observe").pressed.emit()
	assert_true(main.is_observing())
	assert_eq(card.button(&"observe").text, "Observing")
	await wait_frames(2)
	assert_eq(people_view.trail_size(), 0, "standing still: no way to show")
	# They set off.
	var goal: Vector2i = session.pathfinder.standable_near(person.position + Vector2i(6, 0), 1)[0]
	assert_true(session.movement.walk_to(person.id, goal))
	await wait_frames(3)
	var way := session.movement.remaining_path(person.id)
	assert_true(way.size() > 2, "a way to go")
	assert_eq(people_view.trail_size(), way.size(), "a dot for every tile of it")
	assert_eq(heard.size(), 0, "watching touches nothing")
	# Someone else selected: the watching ends.
	var other := _someone(person.id)
	main.select_person(other.id)
	await wait_frames(2)
	assert_false(main.is_observing())
	assert_eq(people_view.trail_size(), 0)
	assert_eq(ui.person_card().button(&"observe").text, "Observe")
	# On and off again.
	main.select_person(person.id, PersonCard.State.HALF)
	await wait_frames(2)
	ui.person_card().button(&"observe").pressed.emit()
	await wait_frames(2)
	assert_true(people_view.trail_size() > 0)
	ui.person_card().button(&"observe").pressed.emit()
	await wait_frames(2)
	assert_false(main.is_observing())
	assert_eq(people_view.trail_size(), 0)


func test_marking_someone_pins_their_name() -> void:
	var pins := ui.pins()
	assert_false(pins.visible, "nobody marked: no list")
	var person := _someone()
	var other := _someone(person.id)
	main.select_person(person.id)
	await wait_frames(2)
	var card := ui.person_card()
	assert_false((card.button(&"mark") as StarButton).marked)
	card.button(&"mark").pressed.emit()
	await wait_frames(2)
	assert_true(person.has_flag(PersonData.FLAG_MARKED_IMPORTANT))
	assert_true((card.button(&"mark") as StarButton).marked, "the star is lit")
	assert_true(pins.visible)
	assert_eq(pins.ids(), [person.id] as Array[int])
	assert_eq(pins.chips()[0].text, person.given_name)
	assert_true(router.is_over_ui(pins.chips()[0].get_global_rect().get_center()), "a touch on a name is not a touch of the world")
	assert_false(pins.get_global_rect().intersects(card.get_global_rect()), "clear of the card")
	main.select_person(other.id)
	await wait_frames(2)
	ui.person_card().button(&"mark").pressed.emit()
	await wait_frames(2)
	var both: Array[int] = [person.id, other.id]
	both.sort()
	assert_eq(pins.ids(), both, "in the order they came into the world")
	# A tap on a name goes to them.
	await _look_at(person.world2d() + Vector2(8.0, 8.0), 14.0)
	var chip := pins.chips()[pins.ids().find(person.id)]
	chip.pressed.emit()
	for i in 300:
		rig.advance(1.0 / 60.0)
	await wait_frames(2)
	assert_eq(main.selected_person_id(), person.id)
	assert_near(rig.pivot().x, person.world2d().x, 0.2)
	assert_near(rig.pivot().z, person.world2d().y, 0.2)
	# Unmarked: off the list.
	ui.person_card().button(&"mark").pressed.emit()
	await wait_frames(2)
	assert_false(person.has_flag(PersonData.FLAG_MARKED_IMPORTANT))
	assert_eq(pins.ids(), [other.id] as Array[int])
	# Someone marked who dies leaves the list.
	session.kill_person(other.id)
	await wait_frames(2)
	assert_false(pins.visible)
	assert_eq(pins.ids().size(), 0)


func test_marks_and_touches_are_kept_across_saves() -> void:
	var person := _someone()
	main.select_person(person.id)
	await wait_frames(2)
	ui.person_card().button(&"mark").pressed.emit()
	ui.person_card().button(&"touch").pressed.emit()
	var saved := session.to_dict()
	var again := WorldSession.new()
	add_child(again)
	assert_true(again.load_from(saved.duplicate(true)))
	var back := again.people.get_person(person.id)
	assert_true(back.has_flag(PersonData.FLAG_MARKED_IMPORTANT))
	assert_true(back.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	again.queue_free()
	# The running game shows the marks of the world it opens.
	SaveManager.save_world(session, &"test")
	get_tree().unload_current_scene()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var reopened := get_tree().current_scene
	var pins: PinList = (reopened.get_node("UIRoot") as UIRoot).pins()
	assert_eq(pins.ids(), [person.id] as Array[int])
	assert_eq(reopened.selected_person_id(), 0, "who was selected is not part of the world")


func test_family_on_the_card_leads_to_them() -> void:
	var parent: PersonData = null
	for p in session.people.all_people():
		if not p.children.is_empty():
			parent = p
			break
	session.behavior.enabled = false
	main.select_person(parent.id, PersonCard.State.FULL)
	await wait_frames(3)
	var card := ui.person_card()
	var buttons := card.family_buttons()
	var facts: Array = PersonCard.facts(session, parent)["family"]
	assert_eq(buttons.size(), facts.size())
	assert_has(buttons[0].text, facts[0][2])
	var child := session.people.get_person(parent.children[0])
	var index := -1
	for i in facts.size():
		if facts[i][0] == child.id:
			index = i
	buttons[index].pressed.emit()
	for i in 300:
		rig.advance(1.0 / 60.0)
	await wait_frames(3)
	assert_eq(main.selected_person_id(), child.id)
	assert_eq(ui.person_card().person_id(), child.id)
	assert_eq(ui.person_card().state(), PersonCard.State.FULL, "at the same height")
	assert_eq(ui.panel_count(), 1)
	if not child.has_flag(PersonData.FLAG_INDOORS):
		assert_near(rig.pivot().x, child.world2d().x, 0.2, "and the camera goes to them")
	var names := PackedStringArray()
	for b in ui.person_card().family_buttons():
		names.append(b.text)
	assert_has(" ".join(names), parent.given_name, "their card names the parent")


func test_the_pin_list_shows_no_more_than_fits() -> void:
	var list := PinList.new()
	add_child(list)
	var chosen: Array = []
	list.chosen.connect(func(id: int) -> void: chosen.append(id))
	var many: Array = []
	for i in 10:
		many.append([i + 1, "Name%d" % i])
	list.set_people(many)
	await wait_frames(1)
	assert_eq(list.chips().size(), PinList.MAX_SHOWN)
	assert_eq(list.ids().size(), PinList.MAX_SHOWN)
	list.chips()[2].pressed.emit()
	assert_eq(chosen, [3])
	list.set_people([])
	await wait_frames(1)
	assert_false(list.visible)
	assert_eq(list.chips().size(), 0)
	list.queue_free()
