extends TestCase
## The timeline (M11.3, bible §21.4): the world's events year by year, the
## latest first, through filters; a tap looks for an event — where it
## happened, or whom it concerned (the living, the graves of the dead, their
## descendants); and a long history scrolls lightly.

var main: Node
var ui: UIRoot
var session: WorldSession
var events: EventLog
var _knobs: Array = []


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
	events = session.events
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"newcomer_chance_per_day", &"marry_out_chance_per_day", &"gathering_romance"]:
		_knobs.append([knob, Config.life.get(knob)])
		Config.life.set(knob, 0.0)


func after_each() -> void:
	for knob: Array in _knobs:
		Config.life.set(knob[0], knob[1])
	_knobs.clear()
	ui.close_all_panels()
	await wait_frames(2)


func test_year_by_year() -> void:
	var year := Config.time.ticks_per_year()
	var people := session.people.all_people()
	var older := events.record(Chronicler.TYPE_FRIENDS, {"participants": [people[0].id, people[1].id], "tick": session.clock.tick + 10})
	var flood := events.record(Chronicler.TYPE_FLOOD, {"tick": session.clock.tick + year + 5, "position": Vector2(3, 3)})
	var touch := events.record(Chronicler.TYPE_PLAYER, {"kind": "touch", "subject": "person", "participants": [people[2].id],
		"tick": session.clock.tick + year + 7, "significance": 0.1})
	var rows := TimelineModel.rows(events)
	# The latest year first, each year's latest first.
	assert_eq(rows[0], {"year": 2})
	assert_eq(rows[1]["event"], touch)
	assert_eq(rows[2]["event"], flood)
	var years: Array = []
	for row: Dictionary in rows:
		if row.has("year"):
			years.append(row["year"])
	assert_eq(years, [2, 1], "each year once")
	var ids: Array = []
	for row: Dictionary in rows:
		if row.has("event"):
			ids.append((row["event"] as WorldEvent).id)
	assert_eq(ids.size(), events.size(), "every event")
	assert_true(ids.find(older.id) > ids.find(flood.id))
	# Filters.
	var only := func(filter: StringName) -> Array:
		var out: Array = []
		for row: Dictionary in TimelineModel.rows(events, filter):
			if row.has("event"):
				out.append((row["event"] as WorldEvent).type)
		return out
	assert_eq(only.call(TimelineModel.FILTER_PLAYER), [Chronicler.TYPE_PLAYER])
	assert_true(only.call(TimelineModel.FILTER_DISASTERS).has(Chronicler.TYPE_FLOOD))
	assert_false(only.call(TimelineModel.FILTER_DISASTERS).has(Chronicler.TYPE_FRIENDS))
	assert_true(only.call(TimelineModel.FILTER_PEOPLE).has(Chronicler.TYPE_FRIENDS))
	assert_false(only.call(TimelineModel.FILTER_PEOPLE).has(Chronicler.TYPE_FLOOD))
	assert_true(only.call(TimelineModel.FILTER_MAJOR).has(Chronicler.TYPE_FLOOD))
	assert_true(only.call(TimelineModel.FILTER_MAJOR).has(Chronicler.TYPE_PLAYER), "the first touch: a first")
	var plain := events.record(Chronicler.TYPE_FRIENDS, {"participants": [people[4].id, people[5].id]})
	plain.tags = PackedStringArray(["people"])
	assert_false(TimelineModel.passes(plain, TimelineModel.FILTER_MAJOR), "what matters little is not major")


func test_timeline_locate_fallbacks() -> void:
	var people := session.people.all_people()
	# Where it happened.
	var placed := events.record(Chronicler.TYPE_STORM, {"position": Vector2(4.5, 6.5)})
	var found := TimelineModel.locate(session, placed)
	assert_eq(found.found, TimelineModel.Found.PLACE)
	assert_eq(found.position, Vector2(4.5, 6.5))
	# Nowhere in particular (or nowhere in the box any more): whom it concerned.
	var nowhere := events.record(Chronicler.TYPE_FRIENDS, {"participants": [people[0].id, people[1].id]})
	nowhere.position = Vector2.INF
	found = TimelineModel.locate(session, nowhere)
	assert_eq([found.found, found.person_id], [TimelineModel.Found.PERSON, people[0].id])
	var outside := events.record(Chronicler.TYPE_FRIENDS, {"participants": [people[2].id], "position": Vector2(99999, 99999)})
	assert_eq(TimelineModel.locate(session, outside).found, TimelineModel.Found.PERSON, "a place outside the box is no place")
	# The dead: their grave.
	var dead := people[3]
	var of_dead := events.record(Chronicler.TYPE_HUNTED, {"participants": [dead.id], "species": "deer"})
	of_dead.position = Vector2.INF
	session.kill_person(dead.id, Lifecycle.CAUSE_ILLNESS)
	found = TimelineModel.locate(session, of_dead)
	assert_eq([found.found, found.person_id], [TimelineModel.Found.GRAVE, dead.id])
	assert_eq(found.position, Vector2(session.archive.get_record(dead.id).grave_tile) + Vector2(0.5, 0.5))
	# The dead without a grave (it is gone): a living descendant.
	var parent: PersonData = null
	for person in session.people.all_people():
		if not person.children.is_empty():
			parent = person
	var of_parent := events.record(Chronicler.TYPE_HUNTED, {"participants": [parent.id], "species": "rabbit"})
	of_parent.position = Vector2.INF
	var children := parent.children.duplicate()
	session.kill_person(parent.id, Lifecycle.CAUSE_ILLNESS)
	var record := session.archive.get_record(parent.id)
	session.props.remove(record.grave_id)
	found = TimelineModel.locate(session, of_parent)
	assert_eq(found.found, TimelineModel.Found.DESCENDANT)
	assert_true(children.has(found.person_id))
	# Nothing at all.
	var lost := events.record(Chronicler.TYPE_DROUGHT, {})
	assert_eq(TimelineModel.locate(session, lost).found, TimelineModel.Found.NOWHERE)


func test_a_long_history_scrolls_lightly() -> void:
	var year := Config.time.ticks_per_year()
	var people := session.people.all_people()
	for n in 3000:
		events.record(Chronicler.TYPE_FIGHT, {"tick": session.clock.tick + n * year / 30, "position": Vector2(5, 5),
			"participants": [people[n % people.size()].id]})
	var started := Time.get_ticks_usec()
	var panel := ui.open_timeline()
	await wait_frames(3)
	var opened_ms := (Time.get_ticks_usec() - started) / 1000.0
	var list := panel.list()
	var pager := panel.pager()
	assert_true(pager.total >= Config.events.max_events, "as much as the log keeps (%d)" % pager.total)
	# A page at a time (the owner's playtest: such lists grow ridiculously long).
	assert_true(pager.visible)
	assert_true(list.item_count() <= TimelinePanel.PAGE_ROWS + 1, "a page of it (%d)" % list.item_count())
	assert_eq(pager.page, 0, "the newest first")
	assert_has(pager.text(), "1/%d" % pager.pages())
	assert_has(pager.text(), "Years ")
	var newest := (list.row_at(1) as Button).text
	pager.go(pager.pages() - 1)
	await wait_frames(2)
	assert_eq(pager.page, pager.pages() - 1, "the oldest")
	assert_true((list.row_at(0) as Label) != null, "a page begins under its year")
	assert_ne((list.row_at(1) as Button).text, newest)
	pager.go(1)
	await wait_frames(2)
	assert_has(pager.text(), " · 2/")
	assert_true(list.shown_count() <= 30, "only the rows on screen are made (%d)" % list.shown_count())
	list.scroll_to(list.item_count() - 1)
	await wait_frames(2)
	assert_not_null(list.row_at(list.item_count() - 1))
	assert_null(list.row_at(0), "and those scrolled away are gone")
	assert_true(list.shown_count() <= 30)
	# A new filter begins at the newest again.
	panel.set_filter(TimelineModel.FILTER_PEOPLE)
	assert_eq(pager.page, 0)
	panel.set_filter(TimelineModel.FILTER_ALL)
	list.scroll_to(list.item_count() - 1)
	await wait_frames(2)
	# A finger dragged over the rows scrolls them: a drag that begins on a row
	# goes on to the list (the owner's playtest: it would not scroll).
	assert_true(list.scroll_deadzone > 0, "a tap that wobbles is still a tap")
	assert_eq(list.row_at(list.item_count() - 1).mouse_filter, Control.MOUSE_FILTER_PASS)
	# Where cards go (centred on a phone, at the left on a wide screen).
	var view := panel.get_viewport_rect()
	var rect := panel.get_global_rect()
	assert_true(view.encloses(rect), "on the screen: %s" % rect)
	assert_near(rect.position.x, UIPanel.across(view.size, TimelinePanel.MAX_WIDTH, TimelinePanel.EDGE_MARGIN).x, 1.0)
	print("    timeline: %d rows, %d made; opened in %.1f ms" % [list.item_count(), list.shown_count(), opened_ms])


func test_the_timeline_in_the_game() -> void:
	# ☰ → HISTORY → Timeline.
	var menu := ui.open_menu()
	await wait_frames(1)
	assert_true(menu.entries().any(func(b: Button) -> bool: return b.text == "Timeline"))
	for entry in menu.entries():
		if entry.text == "Timeline":
			entry.pressed.emit()
	await wait_frames(2)
	var panel := ui.timeline()
	assert_not_null(panel)
	assert_null(ui.main_menu(), "in place of the menu")
	assert_false(ui.toasts().visible)
	# A filter.
	panel.filter_button(TimelineModel.FILTER_PLAYER).pressed.emit()
	assert_eq(panel.filter(), TimelineModel.FILTER_PLAYER)
	assert_true(panel.filter_button(TimelineModel.FILTER_PLAYER).button_pressed)
	assert_false(panel.filter_button(TimelineModel.FILTER_ALL).button_pressed)
	panel.set_filter(TimelineModel.FILTER_ALL)
	# New events appear.
	var storm := events.record(Chronicler.TYPE_STORM, {"position": Vector2(session.start.settlement_tile) + Vector2(6.5, 2.5)})
	panel.refresh()
	await wait_frames(2)
	var first_event_row: Button = panel.list().row_at(1)
	assert_not_null(first_event_row)
	assert_eq(first_event_row.text, EventText.text(storm, session.people, events))
	# A tap: the camera goes there, the timeline closes.
	first_event_row.pressed.emit()
	await wait_frames(2)
	assert_null(ui.timeline())
	assert_true(ui.toasts().visible)
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	for i in 300:
		rig.advance(1.0 / 60.0)
	assert_near(rig.pivot().x, storm.position.x, 0.3, "the camera went to where it happened")
	# The dead: their grave, read.
	var dead := session.people.all_people()[0]
	var of_dead := events.record(Chronicler.TYPE_HUNTED, {"participants": [dead.id], "species": "fox"})
	of_dead.position = Vector2.INF
	session.kill_person(dead.id, Lifecycle.CAUSE_OLD_AGE)
	assert_eq(main.locate_event(of_dead.id), TimelineModel.Found.GRAVE)
	await wait_frames(2)
	assert_not_null(ui.grave_card())
	# The living: selected and looked at.
	var living := session.people.all_people()[0]
	var of_living := events.record(Chronicler.TYPE_HUNTED, {"participants": [living.id], "species": "deer"})
	of_living.position = Vector2.INF
	assert_eq(main.locate_event(of_living.id), TimelineModel.Found.PERSON)
	await wait_frames(2)
	assert_eq(main.selected_person_id(), living.id)
