extends TestCase
## Motion controls are on hold (the owner's decision after M8.2): the code
## is there, switched off by MotionConfig.feature_enabled. As shipped,
## nothing of it is on screen and nothing of it runs.

var main: Node
var ui: UIRoot
var _reads := [0]
var _real: Dictionary = {}


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	AudioManager.ensure_sounds()
	_real = {"gravity": SensorManager.read_gravity, "accelerometer": SensorManager.read_accelerometer,
		"gyroscope": SensorManager.read_gyroscope}
	_reads[0] = 0
	SensorManager.read_gravity = func() -> Vector3:
		_reads[0] += 1
		return Vector3(3.0, 0.0, -9.3)
	SensorManager.read_accelerometer = func() -> Vector3:
		_reads[0] += 1
		return Vector3(3.0, 0.0, -9.3)
	SensorManager.read_gyroscope = func() -> Vector3:
		_reads[0] += 1
		return Vector3.ZERO
	SensorManager._set_in_front(true)
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
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)


func after_each() -> void:
	Input.action_release(&"debug_tilt_right")
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
		await wait_frames(2)
	SensorManager.read_gravity = _real["gravity"]
	SensorManager.read_accelerometer = _real["accelerometer"]
	SensorManager.read_gyroscope = _real["gyroscope"]
	Settings.reset_to_defaults()


func test_as_shipped_motion_controls_are_switched_off() -> void:
	assert_false(Config.motion.feature_enabled, "on hold")
	assert_false(MotionConfig.new().feature_enabled, "also if the file were missing")
	assert_false(SensorManager.feature_enabled())
	# The sensors are not read, whatever the settings say.
	assert_true(bool(Settings.get_value(&"motion/enabled")))
	assert_false(SensorManager.is_sampling())
	assert_eq(SensorManager.idle_reason(), "on hold")
	await wait_seconds(0.3)
	for i in 30:
		SensorManager.sample(1.0 / 30.0, 100_000 + i * 33)
	assert_eq(_reads[0], 0, "not once")
	assert_eq(SensorManager.tilt_vector, Vector2.ZERO)
	Settings.set_value(&"motion/touch_tilt", true)
	assert_false(SensorManager.is_sampling())
	assert_false(SensorManager.touch_tilt_enabled())
	# Nothing of it is on screen: no menu button, no settings, no calibration.
	assert_false(ui.menu_button().visible)
	assert_null(ui.open_motion_settings())
	assert_null(ui.open_calibration())
	assert_eq(ui.panel_count(), 0)
	# Two fingers move the view, as they always did; nothing tilts.
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	main.go_home()
	for i in 300:
		rig.advance(1.0 / 60.0)
	var pivot := rig.pivot()
	for type: Gesture.Type in [Gesture.Type.MULTI_START, Gesture.Type.TWO_FINGER_DRAG, Gesture.Type.MULTI_END]:
		var gesture := Gesture.new(type)
		gesture.touch_count = 2
		gesture.position = Vector2(540.0, 900.0)
		gesture.delta = Vector2(200.0, 0.0) if type == Gesture.Type.TWO_FINGER_DRAG else Vector2.ZERO
		main._on_gesture(gesture)
	for i in 60:
		rig.advance(1.0 / 60.0)
	assert_true(rig.pivot().distance_to(pivot) > 0.5)
	assert_eq(main.touch_tilt(), Vector2.ZERO)
	# The debug tools of it are gone too: no stick, no section, keys do nothing.
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	if not overlay.is_shown():
		overlay.toggle()
	await wait_frames(3)
	overlay.refresh()
	assert_false(main.tilt_stick.visible)
	assert_false((overlay.get_node("%OverlayLabel") as Label).text.contains("motion:"))
	Input.action_press(&"debug_tilt_right")
	assert_false(SensorManager.virtual_shake(ShakeDetector.ShakeClass.STRONG))
	await wait_seconds(0.3)
	assert_eq(SensorManager.tilt_vector, Vector2.ZERO)
	assert_eq(_reads[0], 0)
