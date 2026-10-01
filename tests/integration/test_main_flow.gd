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
	await wait_real_ms(Config.save.min_save_gap_ms + 100) # past the new-world save
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


func test_home_button_returns_to_the_settlement() -> void:
	var main := await _load_main()
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	var session: WorldSession = main.get_node("WorldSession")
	rig.set_process(false)
	assert_true(rig.is_framed())
	var button: Button = main.get_node("UIRoot/HomeButton")
	assert_true(button.is_in_group(InputRouter.UI_BLOCKER_GROUP), "taps on it never reach the world")
	assert_true(button.size.x >= 130.0 and button.size.y >= 130.0, "at least a 48 dp touch target on a phone")
	button.pressed.emit()
	for i in 300:
		rig.advance(1.0 / 60.0)
	assert_near(rig.distance(), Config.camera.home_distance, 0.1)
	assert_near(rig.pivot().x, session.start.settlement_tile.x + 0.5, 0.2)
	assert_near(rig.pivot().z, session.start.settlement_tile.y + 0.5, 0.2)


func test_touching_the_world_stops_a_fling() -> void:
	var main := await _load_main()
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	rig.set_process(false)
	rig.zoom_at(8.0, Vector2(540, 960))
	var start := Gesture.new(Gesture.Type.DRAG_START)
	rig.handle_gesture(start)
	var end := Gesture.new(Gesture.Type.DRAG_END)
	end.position = Vector2(540, 960)
	end.velocity = Vector2(2500, 0)
	rig.handle_gesture(end)
	assert_true(rig.is_flinging())
	_touch(0, Vector2(400, 1000), true) # a finger lands on the world
	assert_false(rig.is_flinging())
	_touch(0, Vector2(400, 1000), false)


func _tap(pos: Vector2) -> void:
	_touch(0, pos, true)
	_touch(0, pos, false)


## Loads Main on a world with a known seed, so touch tests always meet the
## same trees and huts.
func _load_main_on_known_world() -> Node:
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	return await _load_main()


## Parks the camera over the settlement; returns [rig, view, session].
func _look_at_settlement(main: Node, distance: float = 16.0) -> Array:
	var view: WorldView = main.get_node("WorldView")
	var session: WorldSession = main.get_node("WorldSession")
	var rig := view.camera_rig()
	rig.set_process(false)
	var tile := session.start.settlement_tile
	rig.focus_on(Vector3(tile.x + 0.5, 0, tile.y + 0.5), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)
	return [rig, view, session]


## Screen position of open ground near the settlement: a spot where a finger
## touches nothing but the ground (near a prop, the prop would be picked).
func _open_ground_screen(main: Node, rig: CameraRig, session: WorldSession) -> Vector2:
	var center := session.start.settlement_tile
	for radius in range(1, 15):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var tile := center + Vector2i(dx, dy)
				var ground := session.world.get_height(tile) * session.world.height_step
				var screen := rig.world_to_screen(Vector3(tile.x + 0.5, ground, tile.y + 0.5))
				var target: Picker.Result = main.pick_at(screen)
				if target.kind == Picker.Kind.TILE and target.tile == tile:
					return screen
	fail("no open ground near the settlement")
	return Vector2.ZERO


func _prop_screen(rig: CameraRig, session: WorldSession, prop: PropData, up: float) -> Vector2:
	var at := prop.position2d()
	var ground := session.world.get_height(prop.tile) * session.world.height_step
	return rig.world_to_screen(Vector3(at.x, ground + up, at.y))


func test_tapping_the_world_plays_its_response() -> void:
	var main := await _load_main_on_known_world()
	var parts := _look_at_settlement(main)
	var rig: CameraRig = parts[0]
	var view: WorldView = parts[1]
	var session: WorldSession = parts[2]
	var heard: Array[InteractionResponse] = []
	session.interactions.responded.connect(func(r: InteractionResponse) -> void: heard.append(r))
	var fire := session.props.get_prop(session.start.campfire_id)
	_tap(_prop_screen(rig, session, fire, 0.15))
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].effect, InteractionResponse.FIRE_FLARE)
	assert_eq(heard[0].entity_id, fire.id)
	assert_true(view.effects().is_shaking(fire.id))
	assert_eq(view.effects().burst_count(WorldEffects.Burst.SPARKS), 1)
	assert_false(view.pick_highlight().tile_visible(), "no debug highlight while the overlay is hidden")
	# The overlay reports what was touched and how the world answered.
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	overlay.toggle()
	overlay.refresh()
	assert_has((overlay.get_node("%OverlayLabel") as Label).text, "CAMPFIRE")
	assert_has((overlay.get_node("%OverlayLabel") as Label).text, "fire_flare")
	overlay.toggle()
	# Open ground: dust.
	await wait_real_ms(Config.interaction.double_tap_ms + 80) # a separate tap, not a double tap
	_tap(_open_ground_screen(main, rig, session))
	assert_eq(heard.size(), 2)
	assert_eq(heard[1].effect, InteractionResponse.DUST)
	assert_false(heard[1].is_entity())
	assert_eq(view.effects().burst_count(WorldEffects.Burst.DUST), 1)
	assert_eq(session.interactions.interaction_count, 2)


func test_double_tap_on_a_thing_looks_at_it() -> void:
	var main := await _load_main_on_known_world()
	var parts := _look_at_settlement(main)
	var rig: CameraRig = parts[0]
	var session: WorldSession = parts[2]
	var hut := session.props.get_prop(session.start.hut_ids[0])
	var roof := _prop_screen(rig, session, hut, 0.7)
	var before := rig.distance()
	_tap(roof)
	_tap(roof)
	for i in 300:
		rig.advance(1.0 / 60.0)
	assert_near(rig.pivot().x, hut.position2d().x, 0.2, "centred on the hut")
	assert_near(rig.pivot().z, hut.position2d().y, 0.2)
	assert_true(rig.distance() <= before + 0.01, "never zooms out to look at something")
	assert_eq(session.interactions.interaction_count, 1, "only the first tap touched the hut")


func test_double_tap_on_open_ground_zooms_in() -> void:
	var main := await _load_main_on_known_world()
	var parts := _look_at_settlement(main, 40.0)
	var rig: CameraRig = parts[0]
	var session: WorldSession = parts[2]
	assert_eq(session.world_seed, 12345)
	var screen := _open_ground_screen(main, rig, session)
	var before := rig.distance()
	_tap(screen)
	_tap(screen)
	for i in 300:
		rig.advance(1.0 / 60.0)
	assert_near(rig.distance(), before / Config.camera.double_tap_zoom, 0.1)


func test_touches_are_heard_and_felt() -> void:
	AudioManager.ensure_sounds()
	var felt := []
	var real_vibrate := Haptics.vibrate_action
	Haptics.vibrate_action = func(ms: int, _amplitude: float) -> void: felt.append(ms)
	Haptics.reset()
	var main := await _load_main_on_known_world()
	assert_true(AudioManager.is_ambience_wanted(), "the world has a background sound")
	assert_true(AudioManager.ambience_player().playing)
	var parts := _look_at_settlement(main)
	var rig: CameraRig = parts[0]
	var session: WorldSession = parts[2]
	# Tap the campfire: a crackle from where the fire is, and a light tick.
	var fire := session.props.get_prop(session.start.campfire_id)
	_tap(_prop_screen(rig, session, fire, 0.15))
	assert_eq(AudioManager.last_sound, &"crackle")
	var at_the_fire := false
	for i in AudioManager.world_voice_count():
		var voice := AudioManager.world_voice(i)
		if voice.stream == AudioManager.sound(&"crackle") 				and Vector2(voice.position.x, voice.position.z).distance_to(fire.position2d()) < 0.01:
			at_the_fire = true
	assert_true(at_the_fire, "the crackle comes from the fire")
	assert_eq(felt, [Config.feedback.haptic_light_ms])
	# The Home button ticks too.
	await wait_real_ms(Config.feedback.haptic_min_gap_ms + 20)
	(main.get_node("UIRoot/HomeButton") as Button).pressed.emit()
	assert_eq(AudioManager.last_sound, &"ui_tap")
	assert_eq(felt.size(), 2)
	# The overlay reports the feedback services.
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	overlay.toggle()
	overlay.refresh()
	var text := (overlay.get_node("%OverlayLabel") as Label).text
	assert_has(text, "audio ")
	assert_has(text, "haptics 2")
	overlay.toggle()
	await _unload_main()
	assert_false(AudioManager.is_ambience_wanted(), "leaving the world stops its background sound")
	Haptics.vibrate_action = real_vibrate


func test_camera_settings_follow_the_player_settings() -> void:
	var main := await _load_main()
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	assert_false(rig.twist_enabled, "twist-to-rotate is off by default")
	assert_false(rig.reduced_motion)
	Settings.set_value(&"camera/twist_rotate", true)
	Settings.set_value(&"accessibility/reduced_motion", true)
	assert_true(rig.twist_enabled)
	assert_true(rig.reduced_motion)
	assert_true((main.get_node("WorldView") as WorldView).effects().reduced_motion)
