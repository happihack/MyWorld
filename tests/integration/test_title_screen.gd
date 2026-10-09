extends TestCase
## The splash screen, the main menu, and leaving the world (the owner,
## 2026-10-08): boot → splash → main menu → the world chosen; in the world,
## ☰ → Leave → Main menu, or Quit game.


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()


func after_each() -> void:
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	SaveManager.open_next = {}
	await wait_frames(2)


## A saved world (returns its id).
func _saved_world(seed_value: int) -> String:
	var session := WorldSession.new()
	add_child(session)
	session.create_new(seed_value)
	SaveManager.save_world(session, &"test")
	var id := session.world_id
	SaveManager.attach(null)
	session.queue_free()
	await wait_frames(1)
	return id


func _title() -> TitleScreen:
	var title := TitleScreen.new()
	var opened := []
	title.open_action = func(plan: Dictionary) -> void: opened.append(plan)
	title.set_meta(&"opened", opened)
	add_child(title)
	return title


func test_the_splash_goes_on_to_the_menu() -> void:
	var splash := SplashScreen.new()
	var went := [0]
	splash.next_action = func() -> void: went[0] += 1
	add_child(splash)
	await wait_frames(2)
	assert_false(splash.uses_custom_picture(), "no splash.png given")
	assert_true(splash.shows_mascot(), "the mascot in the middle (2026-10-08)")
	assert_eq(went[0], 0, "a moment first")
	await wait_seconds(SplashScreen.FADE_IN + 1.0)
	assert_true(splash.mascot_frame() > 0, "it moves (frame %d)" % splash.mascot_frame())
	await wait_seconds(SplashScreen.length() - SplashScreen.FADE_IN - 1.0 + 0.5)
	assert_eq(splash.mascot_frame(), SplashScreen.MASCOT_FRAMES - 1, "played to its last frame")
	assert_eq(went[0], 1, "then the menu, by itself")
	splash.go_on()
	assert_eq(went[0], 1, "once")
	splash.queue_free()
	# A tap goes on at once.
	var tapped := SplashScreen.new()
	var at_once := [0]
	tapped.next_action = func() -> void: at_once[0] += 1
	add_child(tapped)
	await wait_frames(2)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	tapped._gui_input(touch)
	assert_eq(at_once[0], 1, "a tap skips it")
	tapped.queue_free()


func test_boot_shows_the_splash() -> void:
	get_tree().change_scene_to_file("res://scenes/main/boot.tscn")
	await wait_frames(4)
	assert_eq(get_tree().current_scene.name, "Splash")


func test_the_first_time_there_is_only_the_box_to_open() -> void:
	var title := _title()
	await wait_frames(1)
	assert_eq(title.choices(), PackedStringArray(["Open the box", "Quit"]))
	assert_true(title.choose("Open the box"))
	assert_eq(title.get_meta(&"opened"), [{"kind": "new", "size": MainMenu.NEW_WORLD_SIZES[0]}])
	title.queue_free()


func test_continue_new_and_the_worlds() -> void:
	var older := await _saved_world(11)
	await wait_real_ms(1100) # (saved a second apart: the newest is known)
	var newer := await _saved_world(22)
	var title := _title()
	await wait_frames(1)
	assert_eq(title.choices(), PackedStringArray(["Continue", "New world", "Your worlds", "Quit"]))
	assert_true(title.choose("Continue"))
	assert_eq(title.get_meta(&"opened")[-1], {"kind": "world", "world_id": newer}, "the world played last")
	# A new world: the size of box.
	title.choose("New world")
	assert_eq(title.page(), TitleScreen.NEW)
	assert_eq(title.choices().size(), MainMenu.NEW_WORLD_SIZES.size() + 1, "each size, and back")
	title.choose(title.choices()[1])
	assert_eq(title.get_meta(&"opened")[-1], {"kind": "new", "size": MainMenu.NEW_WORLD_SIZES[1]})
	# Back (the phone's) goes to the first page; there, it quits.
	var quit := [false]
	title.quit_action = func() -> void: quit[0] = true
	EventBus.back_requested.emit()
	assert_eq(title.page(), TitleScreen.ROOT)
	title.choose("Your worlds")
	assert_eq(title.choices().size(), 3, "both worlds, and back")
	title.choose(title.choices()[1])
	assert_eq(title.get_meta(&"opened")[-1], {"kind": "world", "world_id": older})
	title.show_page(TitleScreen.ROOT)
	EventBus.back_requested.emit()
	assert_true(quit[0], "back on the first page: quit")
	title.queue_free()


func test_from_the_world_to_the_menu_and_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var main := get_tree().current_scene
	var ui: UIRoot = main.get_node("UIRoot")
	var world_id: String = main.get_node("WorldSession").world_id
	var menu := ui.open_menu()
	var sections := MenuPages.sections(menu).map(func(section: Array) -> String: return section[0])
	assert_has(sections, "MENU_LEAVE")
	var reasons := []
	var noted := func(_p: String, _ms: float) -> void: reasons.append(SaveManager.last_save_info["reason"])
	await wait_real_ms(Config.save.min_save_gap_ms + 100)
	EventBus.save_completed.connect(noted)
	menu.title_requested.emit()
	EventBus.save_completed.disconnect(noted)
	assert_eq(reasons, [&"to_menu"], "saved on the way out")
	await wait_frames(4)
	var title := get_tree().current_scene
	assert_eq(title.name, "Title")
	assert_true(title is TitleScreen)
	# Continue: the same world again.
	(title as TitleScreen).choose("Continue")
	await wait_frames(4)
	assert_eq(get_tree().current_scene.name, "Main")
	assert_eq(get_tree().current_scene.get_node("WorldSession").world_id, world_id)


func test_quit_from_the_world() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var ui: UIRoot = get_tree().current_scene.get_node("UIRoot")
	var quit := [false]
	ui.quit_action = func() -> void: quit[0] = true
	var menu := ui.open_menu()
	var reasons := []
	var noted := func(_p: String, _ms: float) -> void: reasons.append(SaveManager.last_save_info["reason"])
	await wait_real_ms(Config.save.min_save_gap_ms + 100)
	EventBus.save_completed.connect(noted)
	menu.quit_requested.emit()
	EventBus.save_completed.disconnect(noted)
	assert_true(quit[0], "out of the game")
	assert_eq(reasons, [&"quit"], "the world saved first")


func test_a_new_world_is_one_of_the_lands() -> void:
	SaveManager.open_next = {"kind": "new", "size": MainMenu.NEW_WORLD_SIZES[0]}
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var session: WorldSession = get_tree().current_scene.get_node("WorldSession")
	assert_has(WorldSession.LANDS, session.template_id, "a land of its own")
	# Its land is in its save, and in the list of worlds.
	SaveManager.save_world(session, &"test")
	var listed := SaveManager.worlds()
	assert_eq(listed[0]["land"], String(session.template_id))
	assert_true(MainMenu.world_text(listed[0], int(Time.get_unix_time_from_system())).begins_with(
		MemoryText.translate("LAND_" + String(session.template_id).to_upper())), "named in the list")
