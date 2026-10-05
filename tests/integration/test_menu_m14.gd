extends TestCase
## The menu and the information system (M14, bible §26.5): every section and
## page, shown once what it tells of exists; Individuals searched, ordered and
## filtered; the five questions a tester is asked answered; every page opens
## quickly on a large world.

var main: Node
var ui: UIRoot
var session: WorldSession


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	SaveManager.open_next = {}
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
	Settings.reset_to_defaults()
	get_tree().unload_current_scene()
	await wait_frames(2)


## Every entry the menu shows now (its text keys).
func _shown(menu: MainMenu) -> Array:
	var out: Array = []
	for section: Array in MenuPages.sections(menu):
		out.append(section[0])
		for item: Array in section[1]:
			out.append(item[0])
	return out


func test_menu_visibility_rules() -> void:
	var menu := ui.open_menu()
	var shown := _shown(menu)
	for always in ["MENU_WORLD", "MENU_LOCATE", "MENU_MAP", "MENU_OVERVIEW", "MENU_WEATHER", "MENU_ENVIRONMENT", "MENU_RESOURCES",
			"MENU_POPULATION", "MENU_INDIVIDUALS", "MENU_CIVILIZATION", "MENU_SETTLEMENTS", "MENU_BUILDINGS", "MENU_TIMELINE",
			"MENU_INTERACTIONS", "MENU_STATISTICS", "MENU_AUDIO", "MENU_GRAPHICS", "MENU_SPEED", "MENU_ACCESSIBILITY",
			"MENU_NOTIFICATIONS", "MENU_SAVE", "MENU_ADVANCED"]:
		assert_has(shown, always)
	# Not yet: nothing traded, no field, nobody leads, nothing believed, no
	# disaster, nothing found; motion on hold; no debug.
	for hidden in ["MENU_ECONOMY", "MENU_AGRICULTURE", "MENU_GOVERNMENT", "MENU_BELIEFS", "MENU_DISASTERS", "MENU_DISCOVERIES",
			"MENU_MOTION", "MENU_DEBUG"]:
		assert_false(shown.has(hidden), "%s hidden until there is something" % hidden)
	# Each comes when there is something to tell of.
	session.trade.trips = 1
	var tile := session.start.settlement_tile + Vector2i(4, 4)
	for y in range(-8, 9):
		for x in range(-8, 9):
			if session.farming.crops().is_empty() and session.farming.suitable(tile + Vector2i(x, y)):
				session.farming.sow(tile + Vector2i(x, y), session.clock.tick)
	session.governance.weigh_all(session.clock.tick)
	session.events.record(&"cultural_memory", {"subject": "flood", "interpretation": "punishment"})
	session.events.record(&"flood", {"significance": 0.6})
	session.events.record(&"region_found", {"participants": [session.people.all_people()[0].id], "place": "the eastern hills"})
	Settings.set_value(&"debug/enabled", true)
	shown = _shown(menu)
	for now in ["MENU_ECONOMY", "MENU_AGRICULTURE", "MENU_GOVERNMENT", "MENU_BELIEFS", "MENU_DISASTERS", "MENU_DISCOVERIES", "MENU_DEBUG"]:
		assert_has(shown, now)
	assert_false(shown.has("MENU_MOTION"), "motion stays on hold")
	# An accordion: the headings, closed; a tap opens one (and closes the other).
	menu.open_section("")
	menu.open_page(MainMenu.PAGE_ROOT)
	await wait_frames(1)
	assert_true(menu.texts().has("PEOPLE") and not menu.texts().has("Population"), "closed at first")
	_heading(menu, "MENU_PEOPLE").pressed.emit()
	await wait_frames(1)
	assert_true(menu.texts().has("Population"), "opened")
	assert_eq((_heading(menu, "MENU_PEOPLE").get_node("Chevron") as Label).text, "−")
	_heading(menu, "MENU_WORLD").pressed.emit()
	await wait_frames(1)
	assert_true(menu.texts().has("Map") and not menu.texts().has("Population"), "one open at a time")
	_heading(menu, "MENU_WORLD").pressed.emit()
	await wait_frames(1)
	assert_false(menu.texts().has("Map"), "closed again")
	assert_eq(menu.open_section_key(), "")
	# A drag over the entries scrolls the list.
	for button in menu.entries():
		assert_eq(button.mouse_filter, Control.MOUSE_FILTER_PASS)


func _heading(menu: MainMenu, key: String) -> Button:
	for child in menu.find_children("Section_" + key, "Button", true, false):
		if not child.is_queued_for_deletion():
			return child
	return null


func test_every_page_opens_on_a_large_world() -> void:
	# A larger world: a box of 128, and more people in it.
	session.queue_free()
	var big := WorldSession.new()
	add_child(big)
	big.create_new(4242, 128)
	big.set_process(false)
	var fire := big.start.settlement_tile
	for i in 50:
		big.spawn_person(fire + Vector2i(i % 5, i / 5 % 5))
	for i in 40:
		big.events.record(&"flood", {"significance": 0.6, "position": Vector2(fire)})
	big.governance.weigh_all(big.clock.tick)
	var menu := MainMenu.new()
	ui.open_panel(menu)
	menu.setup(big)
	await wait_frames(1)
	var pages: Array = [MainMenu.PAGE_ROOT, MainMenu.PAGE_INDIVIDUALS, MainMenu.PAGE_FAMILIES, MainMenu.PAGE_RELATIONSHIPS,
		MainMenu.PAGE_IMPORTANT, MainMenu.PAGE_FIRSTS, MainMenu.PAGE_WEATHER, MainMenu.PAGE_AUDIO, MainMenu.PAGE_HAPTICS,
		MainMenu.PAGE_SAVE, MainMenu.PAGE_REGIONS, MainMenu.PAGE_LOCATE, MainMenu.PAGE_NEW_WORLD,
		MenuPages.OVERVIEW, MenuPages.ENVIRONMENT, MenuPages.RESOURCES, MenuPages.POPULATION, MenuPages.OCCUPATIONS,
		MenuPages.SETTLEMENTS, MenuPages.BUILDINGS, MenuPages.ECONOMY, MenuPages.AGRICULTURE, MenuPages.GOVERNMENT,
		MenuPages.BELIEFS, MenuPages.DISCOVERIES, MenuPages.SEEN, MenuPages.GRAPHICS, MenuPages.SPEED,
		MenuPages.ACCESSIBILITY, MenuPages.NOTIFICATIONS, MenuPages.ADVANCED, MenuPages.DEBUG]
	var slowest := 0.0
	var slowest_page := ""
	for page: StringName in pages:
		var started := Time.get_ticks_usec()
		menu.open_page(page)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		assert_true(menu.find_children("*", "Label", true, false).size() + menu.entries().size() > 1, "%s shows something" % page)
		assert_true(ms < 100.0, "%s opened in %.1f ms" % [page, ms])
		if ms > slowest:
			slowest = ms
			slowest_page = page
		menu.back()
	print("    every page of the menu opened; the slowest: %s, %.1f ms (%d people, a box of 128)" % [slowest_page, slowest, big.people.size()])
	menu.close()
	big.queue_free()


func test_the_five_questions() -> void:
	# The plan's exit criterion: how many people? who is the oldest? what
	# happened last year? which settlement has the most food? what is the weather?
	var overview := MenuPages.overview_lines(session)
	assert_has(overview[1], "%d people" % session.people.size())
	var oldest: PersonData = null
	for p in session.people.all_people():
		if oldest == null or p.birth_tick < oldest.birth_tick:
			oldest = p
	assert_true(String(MenuPages.oldest_and_youngest(session)[0][1]).contains(oldest.full_name()), "the oldest")
	assert_eq(MainMenu.individuals(session, "", &"age")[0][0], oldest.id, "and first by age")
	assert_true(overview[3].begins_with("Now: "), "the weather")
	var places := MenuPages.settlements(session)
	var food_line := false
	for line in (places[0][1] as PackedStringArray):
		if line.begins_with("Food for"):
			food_line = true
	assert_true(food_line, "each settlement's food")
	assert_false(TimelineModel.rows(session.events, TimelineModel.FILTER_ALL).is_empty(), "what happened, year by year")


func test_individuals_searched_ordered_filtered() -> void:
	var everyone := MainMenu.individuals(session)
	assert_eq(everyone.size(), session.people.size())
	var someone := session.people.all_people()[0]
	var found := MainMenu.individuals(session, someone.given_name.to_lower())
	assert_true(found.size() >= 1 and int(found[0][0]) == someone.id or found.any(func(r: Array) -> bool: return int(r[0]) == someone.id))
	var year := Config.time.ticks_per_year()
	for row: Array in MainMenu.individuals(session, "", &"name", &"children"):
		var stage := session.people.get_person(int(row[0])).life_stage(session.clock.tick, year, Config.people)
		assert_true(stage == PersonData.LifeStage.CHILD or stage == PersonData.LifeStage.ADOLESCENT)
	var by_age := MainMenu.individuals(session, "", &"age")
	for i in range(1, by_age.size()):
		assert_true(session.people.get_person(int(by_age[i - 1][0])).birth_tick <= session.people.get_person(int(by_age[i][0])).birth_tick, "the oldest first")
	# On the page.
	var menu := ui.open_menu()
	menu.open_page(MainMenu.PAGE_INDIVIDUALS)
	await wait_frames(1)
	assert_eq(menu.entries().size(), session.people.size())
	for child in menu.find_children("*", "LineEdit", true, false):
		(child as LineEdit).text = someone.given_name
		(child as LineEdit).text_changed.emit(someone.given_name)
	await wait_frames(1)
	assert_true(menu.entries().size() >= 1 and menu.entries().size() < session.people.size(), "searched")


func test_settings_that_act() -> void:
	Settings.set_value(&"notifications/toasts", false)
	assert_false(NotificationManager.enabled, "no notices")
	Settings.set_value(&"notifications/toasts", true)
	assert_true(NotificationManager.enabled)
	Settings.set_value(&"graphics/fps_cap", 30)
	assert_eq(Engine.max_fps, 30)
	Settings.set_value(&"graphics/fps_cap", 60)
	# Simulation speed from the menu.
	var menu := ui.open_menu()
	menu.open_page(MenuPages.SPEED)
	await wait_frames(1)
	for child in menu.find_children("*", "Button", true, false):
		if (child as Button).text == "Fast":
			(child as Button).pressed.emit()
	assert_eq(session.clock.speed_index, 2)
	session.clock.set_speed(0)
	# The seed, for copying.
	assert_true(MenuPages.overview_lines(session)[-1].contains(str(session.world_seed)))
	# On its side, the panel covers no more than half the world.
	assert_true(MainMenu.panel_width(Vector2(2400, 1080)) <= 1200.0 * 0.9 + 0.1)
	assert_near(MainMenu.panel_width(Vector2(1080, 1920)), minf(1080 * 0.82, MainMenu.MAX_WIDTH), 0.5)
