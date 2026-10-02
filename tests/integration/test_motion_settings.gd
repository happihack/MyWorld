extends TestCase
## The motion settings and the calibration screen in the game, and tilting
## the box with two fingers (M8.2, bible §23.7, §30).

const G := 9.80665
const STEP := 1.0 / 30.0
const STEP_MS := 33

var main: Node
var ui: UIRoot
var manager: Node
var gravity := Vector3.ZERO
var now := 0
var _real: Dictionary = {}
var _real_vibrate: Callable


func before_each() -> void:
	manager = SensorManager
	Config.motion.feature_enabled = true # (on hold in the game; these are the tests of it)
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	Haptics.vibrate_action = func(_ms: int, _amplitude: float) -> void: pass
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	_real = {"gravity": manager.read_gravity, "accelerometer": manager.read_accelerometer, "gyroscope": manager.read_gyroscope,
		"now": manager.now_msec, "virtual": manager.virtual_allowed}
	manager.set_process(false) # (the test says when the sensors are read)
	manager._set_in_front(true)
	manager.set_world_visible(false)
	_fresh()
	gravity = Vector3(0.0, 0.0, -G)
	now = 50_000
	manager.read_gravity = func() -> Vector3: return gravity
	manager.read_accelerometer = func() -> Vector3: return gravity
	manager.read_gyroscope = func() -> Vector3: return Vector3(0.01, 0.0, 0.0)
	manager.now_msec = func() -> int: return now
	manager.virtual_allowed = false
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
	main.get_node("WorldSession").clock.set_speed(0)


func after_each() -> void:
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
		await wait_frames(2)
	manager.set_world_visible(false)
	manager.read_gravity = _real["gravity"]
	manager.read_accelerometer = _real["accelerometer"]
	manager.read_gyroscope = _real["gyroscope"]
	manager.now_msec = _real["now"]
	manager.virtual_allowed = _real["virtual"]
	Haptics.vibrate_action = _real_vibrate
	Settings.reset_to_defaults()
	_fresh()
	manager.set_process(true)
	Config.motion.feature_enabled = MotionConfig.new().feature_enabled


func _fresh() -> void:
	manager.availability = manager.Availability.UNKNOWN
	manager.has_gravity_sensor = false
	manager.has_accelerometer = false
	manager.has_gyroscope = false
	manager._zero_gravity = 0
	manager._zero_acceleration = 0
	manager._zero_gyroscope = 0
	manager.virtual.reset()


func _samples(count: int) -> void:
	for i in count:
		now += STEP_MS
		manager.sample(STEP, now)


func _held(degrees: Vector2) -> Vector3:
	return MotionFilter.direction_for(degrees, MotionFilter.FLAT) * G


func _two_fingers(type: Gesture.Type, delta: Vector2 = Vector2.ZERO) -> void:
	var gesture := Gesture.new(type)
	gesture.touch_count = 2
	gesture.position = Vector2(540.0, 900.0)
	gesture.delta = delta
	main._on_gesture(gesture)


func test_the_motion_settings() -> void:
	_samples(5)
	# The button top left opens them (and closes them again).
	var button := ui.menu_button()
	assert_true(button.is_in_group(InputRouter.UI_BLOCKER_GROUP))
	assert_true(button.get_global_rect().position.x < 60.0 and button.get_global_rect().position.y < 80.0, "top left")
	assert_false(button.get_global_rect().intersects(ui.speed_control().get_global_rect()))
	assert_null(ui.motion_settings())
	button.pressed.emit()
	await wait_frames(2)
	var panel := ui.motion_settings()
	assert_not_null(panel)
	assert_true(panel.is_in_group(InputRouter.UI_BLOCKER_GROUP))
	var view := panel.get_viewport_rect().size
	assert_true(panel.get_global_rect().position.x >= 0.0 and panel.get_global_rect().end.x <= view.x, "on the screen")
	assert_true(panel.get_global_rect().position.y >= 0.0 and panel.get_global_rect().end.y <= view.y, "%s in %s" % [panel.get_global_rect(), view])
	assert_eq(panel.sensors_text(), "This device has motion sensors.")
	# Motion controls: off, and the sensors are let be; on again.
	var enabled := panel.toggle(&"motion/enabled")
	assert_eq(enabled.text, "On")
	enabled.pressed.emit()
	assert_false(bool(Settings.get_value(&"motion/enabled")))
	assert_eq(enabled.text, "Off")
	assert_false(manager.is_sampling())
	assert_eq(panel.sensors_text(), "Motion controls are switched off.")
	assert_true(panel.button(&"calibrate").disabled and panel.button(&"use_current").disabled)
	enabled.pressed.emit()
	assert_true(bool(Settings.get_value(&"motion/enabled")))
	assert_true(manager.is_sampling())
	_samples(3)
	panel.refresh()
	assert_false(panel.button(&"calibrate").disabled)
	# The sensitivities, in steps of a tenth, between a half and two.
	for key: StringName in [&"motion/tilt_sensitivity", &"motion/shake_sensitivity", &"motion/rotation_sensitivity"]:
		assert_eq(panel.value_text(key), "100 %")
		panel.stepper(key, 1).pressed.emit()
		assert_near(float(Settings.get_value(key)), 1.1, 0.0001)
		assert_eq(panel.value_text(key), "110 %")
		for i in 20:
			panel.stepper(key, 1).pressed.emit()
		assert_near(float(Settings.get_value(key)), 2.0, 0.0001, "no further")
		assert_true(panel.stepper(key, 1).disabled)
		for i in 30:
			panel.stepper(key, -1).pressed.emit()
		assert_near(float(Settings.get_value(key)), 0.5, 0.0001)
		assert_eq(panel.value_text(key), "50 %")
		assert_true(panel.stepper(key, -1).disabled and not panel.stepper(key, 1).disabled)
	# They are what the sensors go by.
	assert_near(manager.filter._sensitivity, 0.5, 0.0001)
	assert_near(manager.detector._sensitivity, 0.5, 0.0001)
	# Reduced motion: the setting the views already listen to.
	var reduced := panel.toggle(&"accessibility/reduced_motion")
	assert_eq(reduced.text, "Off")
	reduced.pressed.emit()
	assert_true(bool(Settings.get_value(&"accessibility/reduced_motion")))
	assert_true(main.get_node("WorldView").camera_rig().reduced_motion)
	assert_eq(reduced.text, "On")
	# Changed elsewhere, it shows here.
	Settings.set_value(&"motion/tilt_sensitivity", 1.3)
	assert_eq(panel.value_text(&"motion/tilt_sensitivity"), "130 %")
	# Level: as held, until "use current angle as level" — and forgotten again.
	Settings.set_value(&"motion/tilt_sensitivity", 1.0)
	assert_eq(panel.level_text(), "As held when the game opens")
	assert_false(panel.button(&"forget").visible)
	gravity = _held(Vector2(0.0, -30.0))
	_samples(40)
	panel.button(&"use_current").pressed.emit()
	assert_true(manager.is_calibrated())
	assert_eq(panel.level_text(), "Calibrated")
	assert_true(panel.button(&"forget").visible)
	assert_true((Settings.get_value(&"motion/baseline_gravity") as Vector3).distance_to(gravity.normalized()) < 0.01)
	panel.button(&"forget").pressed.emit()
	assert_false(manager.is_calibrated())
	assert_eq(panel.level_text(), "As held when the game opens")
	# Back closes it.
	EventBus.back_requested.emit()
	await wait_frames(2)
	assert_null(ui.motion_settings())
	assert_eq(ui.panel_count(), 0)


func test_calibration_in_the_game() -> void:
	gravity = _held(Vector2(3.0, -33.0)) # in the hand
	_samples(30)
	var settings := ui.open_motion_settings()
	settings.button(&"calibrate").pressed.emit()
	await wait_frames(2)
	var panel := ui.calibration_panel()
	assert_not_null(panel)
	assert_eq(ui.top_panel(), panel, "over the settings")
	assert_eq(panel.step_text(), "Place your phone flat.")
	assert_true(panel.button(&"use_current").visible)
	assert_eq(panel.button(&"done").text, "Cancel")
	# Still in the hand: it waits.
	_samples(30)
	assert_eq(panel.step_text(), "Place your phone flat.")
	assert_near(panel.progress(), 0.0, 0.001)
	# Laid on the table.
	gravity = _held(Vector2(1.0, 1.5))
	_samples(20)
	assert_eq(panel.step_text(), "Hold still.")
	assert_true(panel.progress() > 0.3 and panel.progress() < 0.6)
	# Bumped.
	gravity = _held(Vector2(5.0, 1.5))
	_samples(1)
	assert_eq(panel.step_text(), "It moved. Hold still.")
	assert_near(panel.progress(), 0.0, 0.001)
	_samples(20)
	assert_eq(panel.step_text(), "Hold still.")
	assert_false(panel.is_done())
	_samples(30)
	assert_true(panel.is_done())
	assert_eq(panel.step_text(), "Calibration complete.")
	assert_eq(panel.button(&"done").text, "Done")
	assert_false(panel.button(&"use_current").visible)
	# What was found is level from now on, and kept.
	assert_true(manager.is_calibrated())
	assert_true((Settings.get_value(&"motion/baseline_gravity") as Vector3).distance_to(gravity.normalized()) < 0.001)
	_samples(30)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	gravity = _held(Vector2(3.0, -33.0))
	_samples(45)
	assert_true(manager.tilt_degrees.y < -20.0, "picked up again: tilted against the table (%s)" % manager.tilt_degrees)
	# Done: back to the settings, which know.
	var finished: Array = []
	panel.finished.connect(func(calibrated: bool) -> void: finished.append(calibrated))
	panel.button(&"done").pressed.emit()
	await wait_frames(2)
	assert_eq(finished, [true])
	assert_null(ui.calibration_panel())
	assert_eq(ui.top_panel(), settings)
	settings.refresh()
	assert_eq(settings.level_text(), "Calibrated")
	# "Use current angle as level": no laying flat.
	var again := ui.open_calibration()
	await wait_frames(2)
	again.button(&"use_current").pressed.emit()
	assert_eq(again.step_text(), "Hold still.")
	assert_false(again.button(&"use_current").visible)
	_samples(50)
	assert_true(again.is_done())
	assert_true((Settings.get_value(&"motion/baseline_gravity") as Vector3).distance_to(gravity.normalized()) < 0.001)
	_samples(30)
	assert_eq(manager.tilt_vector, Vector2.ZERO, "as it is held now: level")
	again.close()
	await wait_frames(2)
	# Cancelled: nothing changes.
	var before: Vector3 = Settings.get_value(&"motion/baseline_gravity")
	var third := ui.open_calibration()
	await wait_frames(2)
	gravity = _held(Vector2.ZERO)
	_samples(20)
	finished.clear()
	third.finished.connect(func(calibrated: bool) -> void: finished.append(calibrated))
	third.button(&"done").pressed.emit()
	await wait_frames(2)
	assert_eq(finished, [false])
	assert_eq(Settings.get_value(&"motion/baseline_gravity"), before)
	_samples(60)
	assert_eq(Settings.get_value(&"motion/baseline_gravity"), before, "a closed screen calibrates nothing")
	# Motion controls off: it says so instead.
	Settings.set_value(&"motion/enabled", false)
	var off := ui.open_calibration()
	await wait_frames(2)
	assert_eq(off.step_text(), "Motion controls are switched off.")
	assert_false(off.button(&"use_current").visible)
	assert_eq(off.button(&"done").text, "Done")
	off.close()


func test_a_device_without_sensors_tilts_by_touch() -> void:
	gravity = Vector3.ZERO
	_samples(Config.motion.unavailable_after_samples + 2)
	assert_eq(manager.availability, manager.Availability.UNAVAILABLE)
	assert_false(bool(Settings.get_value(&"motion/touch_tilt")), "the switch is off...")
	assert_true(manager.touch_tilt_enabled(), "...but without sensors it is how the box is tilted")
	# The settings say so.
	var panel := ui.open_motion_settings()
	await wait_frames(2)
	assert_eq(panel.sensors_text(), "This device has no motion sensors. Drag with two fingers to tilt the box.")
	assert_eq(panel.toggle(&"motion/touch_tilt").text, "On")
	assert_true(panel.toggle(&"motion/touch_tilt").disabled)
	assert_true(panel.button(&"calibrate").disabled)
	# The calibration screen too.
	var calibration := ui.open_calibration()
	await wait_frames(2)
	assert_eq(calibration.step_text(), "This device has no motion sensors.")
	await wait_frames(5)
	for shown: Control in [panel, calibration]:
		assert_true(shown.get_global_rect().size.y < 1500.0 and shown.get_global_rect().position.y >= 0.0, str(shown.get_global_rect()))
	ui.close_all_panels()
	await wait_frames(2)
	# Two fingers dragged to the right: the right edge goes down — and the camera stays.
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	for i in 200:
		rig.advance(1.0 / 60.0)
	_two_fingers(Gesture.Type.MULTI_START)
	var pivot := rig.pivot()
	_two_fingers(Gesture.Type.TWO_FINGER_DRAG, Vector2(Config.motion.touch_tilt_reach * 0.5, 0.0))
	assert_near(main.touch_tilt().x, 0.5, 0.001)
	_samples(30)
	assert_true(manager.is_using_virtual())
	assert_near(manager.tilt_degrees.x, 12.5, 0.4, "half way: half the tilt (no dead zone for fingers)")
	assert_near(manager.tilt_degrees.y, 0.0, 0.05)
	assert_eq(rig.pivot(), pivot, "the view has not moved")
	# Further, and up: as far as it goes, the top edge down as well.
	_two_fingers(Gesture.Type.TWO_FINGER_DRAG, Vector2(Config.motion.touch_tilt_reach, -Config.motion.touch_tilt_reach))
	assert_near(main.touch_tilt().length(), 1.0, 0.001)
	_samples(30)
	assert_near(manager.tilt_degrees.length(), 25.0, 0.2)
	assert_true(manager.tilt_degrees.x > 5.0 and manager.tilt_degrees.y > 5.0)
	assert_near(manager.tilt_vector.length(), 1.0, 0.01)
	# Pinching still zooms.
	var distance := rig.distance()
	var pinch := Gesture.new(Gesture.Type.PINCH)
	pinch.touch_count = 2
	pinch.position = Vector2(540.0, 900.0)
	pinch.scale = 1.3
	main._on_gesture(pinch)
	assert_true(rig.distance() < distance)
	# Lifted: level again, soon.
	_two_fingers(Gesture.Type.MULTI_END)
	assert_eq(main.touch_tilt(), Vector2.ZERO)
	_samples(20)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_false(manager.is_using_virtual())
	# With motion controls off there is no tilting at all.
	Settings.set_value(&"motion/enabled", false)
	_two_fingers(Gesture.Type.MULTI_START)
	_two_fingers(Gesture.Type.TWO_FINGER_DRAG, Vector2(200.0, 0.0))
	_samples(20)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	_two_fingers(Gesture.Type.MULTI_END)


func test_with_sensors_two_fingers_move_the_view_unless_switched() -> void:
	_samples(20)
	assert_eq(manager.availability, manager.Availability.AVAILABLE)
	assert_false(manager.touch_tilt_enabled())
	var rig: CameraRig = main.get_node("WorldView").camera_rig()
	main.go_home() # (closer than the whole box: there is somewhere to move the view to)
	for i in 300:
		rig.advance(1.0 / 60.0)
	var pivot := rig.pivot()
	_two_fingers(Gesture.Type.MULTI_START)
	_two_fingers(Gesture.Type.TWO_FINGER_DRAG, Vector2(200.0, 0.0))
	_two_fingers(Gesture.Type.MULTI_END)
	for i in 60:
		rig.advance(1.0 / 60.0)
	_samples(10)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_eq(main.touch_tilt(), Vector2.ZERO)
	assert_true(rig.pivot().distance_to(pivot) > 0.5, "the view moved, as it always did (%s -> %s, view %s)" % [pivot, rig.pivot(), rig.view_size()])
	# Switched on in the settings: two fingers tilt (while they do, in place of what the sensors say).
	var panel := ui.open_motion_settings()
	await wait_frames(2)
	var toggle := panel.toggle(&"motion/touch_tilt")
	assert_eq(toggle.text, "Off")
	assert_false(toggle.disabled)
	toggle.pressed.emit()
	assert_true(bool(Settings.get_value(&"motion/touch_tilt")))
	assert_true(manager.touch_tilt_enabled())
	panel.close()
	await wait_frames(2)
	_two_fingers(Gesture.Type.MULTI_START)
	pivot = rig.pivot()
	_two_fingers(Gesture.Type.TWO_FINGER_DRAG, Vector2(0.0, -Config.motion.touch_tilt_reach))
	_samples(30)
	assert_near(manager.tilt_degrees.y, 25.0, 0.3)
	assert_true(rig.pivot().distance_to(pivot) < 0.01)
	# It works with the sensors switched off, too: the touch alternative.
	Settings.set_value(&"motion/enabled", false)
	assert_true(manager.is_sampling(), "still listening — to the fingers")
	_samples(30)
	assert_near(manager.tilt_degrees.y, 25.0, 0.3)
	_two_fingers(Gesture.Type.MULTI_END)
	_samples(20)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	# Switched off again while tilted: level.
	Settings.set_value(&"motion/enabled", true)
	_two_fingers(Gesture.Type.MULTI_START)
	_two_fingers(Gesture.Type.TWO_FINGER_DRAG, Vector2(300.0, 0.0))
	Settings.set_value(&"motion/touch_tilt", false)
	_samples(20)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	_two_fingers(Gesture.Type.MULTI_END)
