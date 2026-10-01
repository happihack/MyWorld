extends TestCase
## End-to-end: Boot -> Main, world continuity, debug overlay, hidden unlock,
## back button. Uses the runner's isolated save root and settings file.


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()


func after_each() -> void:
	await _unload_main()


func _load_main(scene := "res://scenes/main/main.tscn") -> Node:
	get_tree().change_scene_to_file(scene)
	await wait_frames(4)
	return get_tree().current_scene


func _unload_main() -> void:
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	get_tree().root.push_input(t, true)


func test_boot_hands_over_to_main_with_running_world() -> void:
	var main := await _load_main("res://scenes/main/boot.tscn")
	assert_eq(main.name, "Main")
	var session: WorldSession = main.get_node("WorldSession")
	assert_true(session.is_active)
	assert_eq(main.get_node("UIRoot/VersionLabel").text, "v" + str(ProjectSettings.get_setting("application/config/version")))
	var t0 := session.clock.tick
	await wait_seconds(1.2)
	assert_true(session.clock.tick - t0 >= 2)


func test_new_world_saved_immediately_and_continued_on_relaunch() -> void:
	var main := await _load_main()
	var first: WorldSession = main.get_node("WorldSession")
	var world_id := first.world_id
	assert_true(FileAccess.file_exists(SaveManager.world_dir(world_id).path_join("world.sav")))
	await wait_seconds(1.2)
	await _unload_main() # orderly close saves the latest tick
	var saved_tick := SaveManager.load_world(world_id).world["clock"]["tick"] as int
	assert_true(saved_tick >= 2, "saved tick %d" % saved_tick)
	main = await _load_main()
	var second: WorldSession = main.get_node("WorldSession")
	assert_eq(second.world_id, world_id)
	assert_true(second.clock.tick >= saved_tick)


func test_unloadable_world_replaced_and_left_untouched() -> void:
	var main := await _load_main()
	var world_id: String = main.get_node("WorldSession").world_id
	await _unload_main() # no live session may hold the world while we corrupt it
	var dir := SaveManager.world_dir(world_id)
	for f in DirAccess.get_files_at(dir):
		corrupt_byte(dir.path_join(f))
	var snapshot := FileAccess.get_file_as_bytes(dir.path_join("world.sav"))
	main = await _load_main()
	var session: WorldSession = main.get_node("WorldSession")
	assert_true(session.is_active)
	assert_ne(session.world_id, world_id)
	assert_eq(FileAccess.get_file_as_bytes(dir.path_join("world.sav")), snapshot)


func test_corrupt_world_with_newest_header_does_not_block_continuity() -> void:
	var main := await _load_main()
	var good_id: String = main.get_node("WorldSession").world_id
	await _unload_main()
	var bad_dir := SaveManager.world_dir("w_bad_future")
	DirAccess.make_dir_recursive_absolute(bad_dir)
	SaveContainer.write(bad_dir.path_join("world.sav"), {"save_version": 1, "saved_unix": 4000000000}, {"world": {}})
	corrupt_byte(bad_dir.path_join("world.sav"))
	assert_eq(SaveManager.find_latest_world_id(), "w_bad_future")
	main = await _load_main()
	assert_eq(main.get_node("WorldSession").world_id, good_id)


func test_debug_overlay_sections_and_toggles() -> void:
	var main := await _load_main()
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	var label: Label = overlay.get_node("%OverlayLabel")
	assert_false(overlay.is_shown())
	assert_false(overlay.is_processing(), "no cost while hidden")
	overlay.toggle()
	assert_true(overlay.is_shown())
	assert_eq(Settings.get_value(&"debug/overlay_visible"), true)
	overlay.refresh()
	for part in ["FPS", "draw", "mem", "world tick", "save ", "gesture"]:
		assert_has(label.text, part)
	var f3 := InputEventKey.new()
	f3.physical_keycode = KEY_F3
	f3.pressed = true
	get_tree().root.push_input(f3, true)
	assert_false(overlay.is_shown(), "F3 hides")
	for i in 3:
		_touch(i, Vector2(300 + i * 100, 900), true)
	for i in 3:
		_touch(i, Vector2(300 + i * 100, 900), false)
	assert_true(overlay.is_shown(), "three-finger tap shows")
	overlay.toggle()


func test_hidden_unlock_on_version_label() -> void:
	var main := await _load_main()
	var ui: UIRoot = main.get_node("UIRoot")
	for i in 6:
		ui.register_unlock_tap(1000 + i * 100)
	assert_eq(Settings.get_value(&"debug/enabled"), false, "6 taps: nothing")
	ui.register_unlock_tap(1700)
	assert_eq(Settings.get_value(&"debug/enabled"), true, "7 taps within 3 s")
	for i in 7:
		ui.register_unlock_tap(10000 + i * 600)
	assert_eq(Settings.get_value(&"debug/enabled"), true, "slow taps do nothing")
	for i in 7:
		ui.register_unlock_tap(20000 + i * 50)
	assert_eq(Settings.get_value(&"debug/enabled"), false, "toggles back")
	# Real clicks on the label: counted, and never reach the world.
	var world_taps := [0]
	main.get_node("InputRouter").gesture_recognized.connect(func(g: Gesture) -> void:
		if g.type == Gesture.Type.TAP:
			world_taps[0] += 1)
	var center := (ui.get_node("%VersionLabel") as Control).get_global_rect().get_center()
	for i in 7:
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.position = center
			mb.global_position = center
			mb.pressed = pressed
			get_tree().root.push_input(mb, true)
	assert_eq(Settings.get_value(&"debug/enabled"), true)
	assert_eq(world_taps[0], 0)


func test_back_button_with_no_panels_saves_and_quits() -> void:
	var main := await _load_main()
	var ui: UIRoot = main.get_node("UIRoot")
	var quit_called := [false]
	ui.quit_action = func() -> void: quit_called[0] = true
	var reasons := []
	var cb := func(_p: String, _ms: float) -> void: reasons.append(SaveManager.last_save_info["reason"])
	await wait_seconds(Config.save.min_save_gap_ms / 1000.0 + 0.1) # past the new-world save
	EventBus.save_completed.connect(cb)
	EventBus.back_requested.emit()
	EventBus.save_completed.disconnect(cb)
	assert_true(quit_called[0])
	assert_eq(reasons, [&"quit"])


func test_lifecycle_notifications_reach_event_bus() -> void:
	var main := await _load_main()
	var lifecycle: AppLifecycle = main.get_node("AppLifecycle")
	var events := []
	var on_paused := func() -> void: events.append("paused")
	var on_resumed := func() -> void: events.append("resumed")
	var on_back := func() -> void: events.append("back")
	EventBus.app_paused.connect(on_paused)
	EventBus.app_resumed.connect(on_resumed)
	EventBus.back_requested.connect(on_back)
	main.get_node("UIRoot").quit_action = func() -> void: pass
	lifecycle.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	lifecycle.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	lifecycle.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	EventBus.app_paused.disconnect(on_paused)
	EventBus.app_resumed.disconnect(on_resumed)
	EventBus.back_requested.disconnect(on_back)
	assert_eq(events, ["paused", "resumed", "back"])
