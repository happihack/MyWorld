extends TestCase
## Save UX v0 (VS.3): straight into the world, saved every 2 minutes and on
## pause, backups that rotate, a corrupt save brought back from a backup —
## and, under Settings → Save, continue another world, a new world, going back
## to a backup and erasing this world (each asked first).


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	SaveManager.open_next = {}
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()


func after_each() -> void:
	var main := get_tree().current_scene
	if main != null and main.has_node("UIRoot"):
		(main.get_node("UIRoot") as UIRoot).close_all_panels()
	SaveManager.open_next = {}
	await wait_frames(2)


## A saved world, `saves` times over (its world.sav and backups).
func _saved_world(saves: int) -> String:
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	for i in saves:
		first.clock.tick += 100 # (each save a little later in the world)
		SaveManager.save_world(first, &"test")
	var id := first.world_id
	first.queue_free()
	await wait_frames(2)
	return id


func _open_main() -> Node:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var main := get_tree().current_scene
	(main.get_node("WorldSession") as WorldSession).clock.set_speed(0)
	return main


## The scene after a world was switched (it reloads).
func _after_switch() -> Node:
	await wait_frames(6)
	var main := get_tree().current_scene
	(main.get_node("WorldSession") as WorldSession).clock.set_speed(0)
	return main


func _save_page(main: Node) -> MainMenu:
	var ui: UIRoot = main.get_node("UIRoot")
	var menu := ui.open_menu()
	menu.open_page(MainMenu.PAGE_SAVE)
	await wait_frames(1)
	return menu


func _press(menu: MainMenu, text: String) -> void:
	for entry in menu.entries():
		if entry.text == text:
			entry.pressed.emit()
			await wait_frames(1)
			return
	fail("no entry %s in %s" % [text, menu.texts()])


func test_first_launch_goes_straight_into_a_world() -> void:
	assert_true(SaveManager.worlds().is_empty())
	var main := await _open_main()
	var session: WorldSession = main.get_node("WorldSession")
	assert_true(session.is_active, "a world, no title screen")
	assert_null((main.get_node("UIRoot") as UIRoot).main_menu())
	assert_eq(SaveManager.worlds().size(), 1, "saved at once")
	assert_eq(main.get("restored_from"), "")


func test_autosave_pause_and_rotating_backups() -> void:
	var id := await _saved_world(4)
	var kept := SaveManager.backups(id)
	assert_eq(kept.size(), Config.save.backup_count, "the oldest dropped off")
	assert_true(int(kept[0]["game_tick"]) > int(kept[1]["game_tick"]), "the newest first")
	var main := await _open_main()
	var session: WorldSession = main.get_node("WorldSession")
	assert_near(Config.save.autosave_interval_s, 120.0, 0.001, "every 2 minutes")
	var timer: Timer = null
	for child in SaveManager.get_children():
		if child is Timer and not (child as Timer).one_shot:
			timer = child
	assert_not_null(timer)
	assert_false(timer.is_stopped(), "autosave running")
	assert_near(timer.wait_time, 120.0, 0.001)
	timer.timeout.emit()
	while SaveManager.is_writing(): # (written on a worker thread, M22)
		await wait_frames(1)
	assert_eq(SaveManager.last_save_info.get("reason"), &"autosave")
	await wait_real_ms(Config.save.min_save_gap_ms + 50)
	EventBus.app_paused.emit()
	assert_eq(SaveManager.last_save_info.get("reason"), &"app_paused", "saved on pause")
	assert_eq(session.world_id, id)


func test_a_corrupt_save_is_brought_back_from_a_backup() -> void:
	var id := await _saved_world(3)
	var path := SaveManager.world_dir(id).path_join(SaveManager.SAVE_FILE)
	var good_tick := int(SaveManager.backups(id)[0]["game_tick"])
	# The main save is spoilt (a torn write, a bad sector).
	var bytes := FileAccess.get_file_as_bytes(path)
	for i in range(bytes.size() / 2, bytes.size()):
		bytes[i] = 0x5A
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	var main := await _open_main()
	var session: WorldSession = main.get_node("WorldSession")
	assert_eq(session.world_id, id, "the same world")
	assert_eq(main.get("restored_from"), "world.sav.bak1")
	assert_eq(session.clock.tick, good_tick, "as at the last good save")
	await wait_frames(4)
	var said := (main.get_node("UIRoot") as UIRoot).toasts().texts()
	assert_true(said.has(MemoryText.translate("SAVE_RESTORED")), "the player is told: %s" % [said])
	# At the next save the spoilt file is set aside, not rotated into the backups.
	SaveManager.save_world(session, &"test")
	assert_true(FileAccess.file_exists(path + SaveManager.CORRUPT_SUFFIX))
	assert_true(SaveContainer.read(path).ok)
	for backup in SaveManager.backups(id):
		assert_true(SaveContainer.read(SaveManager.world_dir(id).path_join(backup["file"])).ok, "good: %s" % backup["file"])


func test_a_new_world_and_back_to_the_first() -> void:
	await _saved_world(1)
	var main := await _open_main()
	var first_id: String = (main.get_node("WorldSession") as WorldSession).world_id
	var menu := await _save_page(main)
	assert_false(menu.texts().has("Continue another world"), "only one world")
	await _press(menu, "New world")
	assert_eq(menu.page(), MainMenu.PAGE_NEW_WORLD, "asked first (and how large a box)")
	await _press(menu, "Cancel")
	assert_eq(menu.page(), MainMenu.PAGE_SAVE)
	await _press(menu, "New world")
	await _press(menu, "A box 64 tiles across (as usual)")
	main = await _after_switch()
	var second_id: String = (main.get_node("WorldSession") as WorldSession).world_id
	assert_ne(second_id, first_id)
	assert_eq(SaveManager.worlds().size(), 2, "the first is kept")
	# Continue another world: the first, as it was.
	menu = await _save_page(main)
	await _press(menu, "Continue another world")
	assert_eq(menu.page(), MainMenu.PAGE_WORLDS)
	assert_eq(menu.entries().size(), 1)
	assert_true(menu.entries()[0].text.begins_with("Seed 12345 · Year 1"), menu.entries()[0].text)
	menu.entries()[0].pressed.emit()
	main = await _after_switch()
	assert_eq((main.get_node("WorldSession") as WorldSession).world_id, first_id)
	assert_eq(SaveManager.worlds().size(), 2)


func test_going_back_to_a_backup() -> void:
	var id := await _saved_world(3)
	var main := await _open_main()
	var session: WorldSession = main.get_node("WorldSession")
	var then := int(SaveManager.backups(id)[0]["game_tick"])
	session.clock.tick += 500
	var later := session.clock.tick
	var menu := await _save_page(main)
	await _press(menu, "Backups")
	assert_eq(menu.page(), MainMenu.PAGE_BACKUPS)
	assert_eq(menu.entries().size(), Config.save.backup_count)
	menu.entries()[0].pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_CONFIRM)
	await _press(menu, "Yes, go back")
	main = await _after_switch()
	session = main.get_node("WorldSession")
	assert_eq(session.world_id, id)
	assert_eq(session.clock.tick, then, "the world as it was then")
	var kept := SaveManager.backups(id)
	assert_eq(int(kept[0]["game_tick"]), later, "what happened since is a backup")


func test_erasing_this_world() -> void:
	await _saved_world(1)
	var main := await _open_main()
	var gone: String = (main.get_node("WorldSession") as WorldSession).world_id
	var menu := await _save_page(main)
	await _press(menu, "Erase this world")
	# Held to (M22): let go early and nothing happens …
	assert_eq(menu.page(), MainMenu.PAGE_HOLD)
	var hold := menu.hold_button()
	assert_not_null(hold)
	hold.press_down()
	hold.advance(hold.hold_seconds * 0.5)
	hold.button_up.emit()
	assert_eq(menu.page(), MainMenu.PAGE_HOLD, "let go early: still here")
	# … held long enough: asked once more.
	hold.press_down()
	hold.advance(hold.hold_seconds + 0.1)
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_CONFIRM)
	await _press(menu, "Yes, erase it")
	main = await _after_switch()
	var now_id: String = (main.get_node("WorldSession") as WorldSession).world_id
	assert_ne(now_id, gone)
	assert_false(DirAccess.dir_exists_absolute(SaveManager.world_dir(gone)), "gone for good")
	assert_eq(SaveManager.worlds().size(), 1)
