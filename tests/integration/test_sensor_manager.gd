extends TestCase
## The SensorManager (M8.1): the sensors are read only while there is a
## reason to, at a fixed rate; a device without sensors is found out; tilt
## and shakes are published; keys and the debug stick stand in on a
## machine without sensors.

const G := 9.80665
const STEP := 1.0 / 30.0
const STEP_MS := 33

var manager: Node
var gravity := Vector3.ZERO
var acceleration := Vector3.ZERO
var turning := Vector3.ZERO
var now := 0
var _reads := [0]
var _tilts: Array = []
var _shakes: Array = []
var _availability: Array = []
var _sampling: Array = []
var _real: Dictionary = {}
var main: Node


func before_each() -> void:
	manager = SensorManager
	Config.motion.feature_enabled = true # (on hold in the game; these are the tests of it)
	Settings.reset_to_defaults()
	_real = {"gravity": manager.read_gravity, "accelerometer": manager.read_accelerometer, "gyroscope": manager.read_gyroscope,
		"now": manager.now_msec, "virtual": manager.virtual_allowed}
	manager.set_process(false) # (the test says when the sensors are read)
	manager._set_in_front(true) # (whatever an earlier test told the app)
	manager.set_world_visible(false)
	_fresh()
	gravity = Vector3(0.0, 0.0, -G)
	acceleration = gravity
	turning = Vector3(0.01, 0.0, 0.0)
	now = 10_000
	_reads[0] = 0
	manager.read_gravity = func() -> Vector3:
		_reads[0] += 1
		return gravity
	manager.read_accelerometer = func() -> Vector3: return acceleration
	manager.read_gyroscope = func() -> Vector3: return turning
	manager.now_msec = func() -> int: return now
	manager.virtual_allowed = false
	_tilts.clear()
	_shakes.clear()
	_availability.clear()
	_sampling.clear()
	manager.tilt_changed.connect(_on_tilt)
	manager.shake_event.connect(_on_shake)
	manager.availability_changed.connect(_on_availability)
	manager.sampling_changed.connect(_on_sampling)
	main = null


func after_each() -> void:
	for action: StringName in [&"debug_tilt_left", &"debug_tilt_right", &"debug_tilt_forward", &"debug_tilt_back"]:
		Input.action_release(action)
	manager.tilt_changed.disconnect(_on_tilt)
	manager.shake_event.disconnect(_on_shake)
	manager.availability_changed.disconnect(_on_availability)
	manager.sampling_changed.disconnect(_on_sampling)
	if main != null and get_tree().current_scene != null:
		get_tree().unload_current_scene()
		await wait_frames(2)
	manager.set_world_visible(false)
	manager.read_gravity = _real["gravity"]
	manager.read_accelerometer = _real["accelerometer"]
	manager.read_gyroscope = _real["gyroscope"]
	manager.now_msec = _real["now"]
	manager.virtual_allowed = _real["virtual"]
	Settings.reset_to_defaults()
	_fresh()
	manager.set_process(true)
	Config.motion.feature_enabled = MotionConfig.new().feature_enabled


## The manager as it is when the game starts: nothing known about the sensors.
func _fresh() -> void:
	manager.availability = manager.Availability.UNKNOWN
	manager.has_gravity_sensor = false
	manager.has_accelerometer = false
	manager.has_gyroscope = false
	manager._zero_gravity = 0
	manager._zero_acceleration = 0
	manager._zero_gyroscope = 0
	manager.reads = 0
	manager.last_shake = null
	manager.virtual.reset()


func _on_tilt(tilt: Vector2) -> void:
	_tilts.append(tilt)


func _on_shake(shake_class: int, intensity: float, direction: Vector3) -> void:
	_shakes.append([shake_class, intensity, direction])


func _on_availability(available: bool) -> void:
	_availability.append(available)


func _on_sampling(sampling: bool) -> void:
	_sampling.append(sampling)


## Lets the sensors be read so many times, a thirtieth of a second apart.
func _samples(count: int) -> void:
	for i in count:
		now += STEP_MS
		manager.sample(STEP, now)


func _tilted(degrees: Vector2, level: Vector3 = MotionFilter.FLAT) -> Vector3:
	return MotionFilter.direction_for(degrees, level) * G


func test_the_sensors_are_read_only_while_there_is_reason_to() -> void:
	# No world on screen: nothing is read.
	assert_false(manager.is_sampling())
	assert_eq(manager.idle_reason(), "no world on screen")
	_samples(10)
	assert_eq(_reads[0], 0)
	# The world is shown: they are.
	manager.set_world_visible(true)
	assert_true(manager.is_sampling())
	assert_eq(_sampling, [true])
	assert_eq(manager.idle_reason(), "")
	_samples(10)
	assert_eq([_reads[0], manager.reads], [10, 10])
	_samples(20)
	# Motion controls switched off in the settings: not read, and no tilt left standing.
	gravity = _tilted(Vector2(15.0, 0.0))
	_samples(40)
	assert_true(manager.tilt_vector.x > 0.2)
	var before: int = _reads[0]
	Settings.set_value(&"motion/enabled", false)
	assert_false(manager.is_sampling())
	assert_eq(manager.idle_reason(), "motion controls off")
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_eq(_tilts[-1], Vector2.ZERO, "and whoever listens is told")
	_samples(10)
	assert_eq(_reads[0], before)
	Settings.set_value(&"motion/enabled", true)
	assert_true(manager.is_sampling())
	# The app in the background, or without focus: not read.
	EventBus.app_paused.emit()
	assert_false(manager.is_sampling())
	assert_eq(manager.idle_reason(), "app not in front")
	_samples(10)
	assert_eq(_reads[0], before)
	EventBus.app_resumed.emit()
	assert_true(manager.is_sampling())
	EventBus.app_focus_changed.emit(false)
	assert_false(manager.is_sampling())
	EventBus.app_focus_changed.emit(true)
	assert_true(manager.is_sampling())
	_samples(3)
	assert_eq(_reads[0], before + 3)
	# The world closed.
	manager.set_world_visible(false)
	assert_false(manager.is_sampling())
	assert_eq(_sampling, [true, false, true, false, true, false, true, false])
	assert_true(manager.debug_text().contains("off (no world on screen)"))


func test_the_sensors_are_read_at_a_fixed_rate() -> void:
	manager.set_world_visible(true)
	# Thirty times a second, however many frames there are: at 120 frames a second...
	for frame in 120:
		now += 8
		manager._process(1.0 / 120.0)
	assert_true(_reads[0] >= 28 and _reads[0] <= 31, "%d readings in a second of 120 frames" % _reads[0])
	# ...at 60...
	_reads[0] = 0
	for frame in 60:
		now += 17
		manager._process(1.0 / 60.0)
	assert_true(_reads[0] >= 28 and _reads[0] <= 31, "%d readings in a second of 60 frames" % _reads[0])
	# ...and when frames are slow, once a frame — never several at once to catch up.
	_reads[0] = 0
	for frame in 5:
		now += 200
		manager._process(0.2)
	assert_eq(_reads[0], 5)
	# Not read at all while there is no reason to.
	manager.set_world_visible(false)
	for frame in 60:
		manager._process(1.0 / 60.0)
	assert_eq(_reads[0], 5)


func test_a_device_without_sensors_is_found_out() -> void:
	gravity = Vector3.ZERO
	acceleration = Vector3.ZERO
	turning = Vector3.ZERO
	manager.set_world_visible(true)
	assert_eq(manager.availability, manager.Availability.UNKNOWN)
	_samples(Config.motion.unavailable_after_samples - 1)
	assert_eq(manager.availability, manager.Availability.UNKNOWN, "not yet: a sensor may take a moment")
	_samples(1)
	assert_eq(manager.availability, manager.Availability.UNAVAILABLE)
	assert_eq(_availability, [false])
	assert_false(manager.is_available())
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_true(manager.debug_text().contains("NO SENSORS"))
	# From now on it is asked only now and then.
	var before: int = _reads[0]
	_samples(roundi(Config.motion.probe_seconds * 30.0 * 3.0))
	assert_true(_reads[0] - before >= 2 and _reads[0] - before <= 4, "%d readings in nine seconds" % (_reads[0] - before))
	# A sensor turns up after all.
	gravity = Vector3(0.0, 0.0, -G)
	acceleration = gravity
	_samples(roundi(Config.motion.probe_seconds * 30.0) + 2)
	assert_eq(manager.availability, manager.Availability.AVAILABLE)
	assert_eq(_availability, [false, true])
	assert_true(manager.has_gravity_sensor and manager.has_accelerometer)
	assert_false(manager.has_gyroscope, "no gyroscope: that is known too")
	turning = Vector3(0.0, 0.2, 0.0)
	_samples(2)
	assert_true(manager.has_gyroscope)
	assert_eq(manager.rotation_rate, Vector3(0.0, 0.2, 0.0))
	# One reading of zeros is not "gone".
	gravity = Vector3.ZERO
	acceleration = Vector3.ZERO
	_samples(5)
	assert_eq(manager.availability, manager.Availability.AVAILABLE)


func test_tilt_is_published() -> void:
	# Held as a phone is held; not calibrated: that is level.
	var held := _tilted(Vector2(0.0, -35.0))
	gravity = held
	acceleration = held
	manager.set_world_visible(true)
	_samples(30)
	assert_eq(manager.availability, manager.Availability.AVAILABLE)
	assert_eq(_availability, [true])
	assert_false(manager.is_calibrated())
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_eq(_tilts, [], "level: nothing to tell")
	# Tilted from there, twelve degrees to the right.
	gravity = _tilted(Vector2(12.0, 0.0), held.normalized())
	_samples(45)
	var expected := MotionFilter.shaped(Vector2(12.0, 0.0), 4.0, 25.0)
	assert_near(manager.tilt_degrees.x, expected.x, 0.1)
	assert_near(manager.tilt_degrees.y, 0.0, 0.1)
	assert_near(manager.tilt_vector.x, expected.x / 25.0, 0.005)
	assert_true(_tilts.size() >= 5, "told as it changes")
	assert_eq(_tilts[-1], manager.tilt_vector)
	for i in range(1, _tilts.size()):
		assert_true((_tilts[i] as Vector2).x >= (_tilts[i - 1] as Vector2).x - 0.0001, "smoothly")
	# Held still: nothing more is said.
	var told := _tilts.size()
	_samples(60)
	assert_true(_tilts.size() <= told + 2)
	# The player's sensitivity setting.
	Settings.set_value(&"motion/tilt_sensitivity", 2.0)
	assert_near(manager.filter.tilt_degrees.x, MotionFilter.shaped(Vector2(24.0, 0.0), 4.0, 25.0).x, 0.2, "twice as much")
	Settings.set_value(&"motion/tilt_sensitivity", 1.0)
	# Readings that are no numbers: passed over.
	var rejected: int = manager.filter.rejected
	gravity = Vector3(NAN, 1.0, INF)
	acceleration = Vector3(NAN, NAN, NAN)
	_samples(5)
	assert_eq(manager.filter.rejected, rejected + 5)
	assert_near(manager.tilt_degrees.x, expected.x, 0.1)
	assert_eq(_shakes, [])
	# Calibrated: how it is held now is level from now on — also after the app was away.
	gravity = _tilted(Vector2(12.0, 0.0), held.normalized())
	acceleration = gravity
	_samples(10)
	assert_true(manager.calibrate_to_current())
	assert_true(manager.is_calibrated())
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_true(bool(Settings.get_value(&"motion/calibrated")))
	assert_true((Settings.get_value(&"motion/baseline_gravity") as Vector3).distance_to(gravity.normalized()) < 0.01)
	EventBus.app_paused.emit()
	EventBus.app_resumed.emit()
	gravity = held
	acceleration = held
	_samples(45)
	assert_true(manager.tilt_degrees.x < -5.0, "back to how it was held before: tilted, by the calibrated level (%s)" % manager.tilt_degrees)
	# Calibration forgotten: how it is held when the sensors come on counts again.
	manager.clear_calibration()
	assert_false(manager.is_calibrated())
	_samples(30)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	EventBus.app_paused.emit()
	EventBus.app_resumed.emit()
	gravity = Vector3(0.0, 0.0, -G)
	acceleration = gravity
	_samples(30)
	assert_eq(manager.tilt_vector, Vector2.ZERO, "laid flat while away: that is level now")
	# Before there is a reading there is nothing to calibrate to.
	EventBus.app_paused.emit()
	EventBus.app_resumed.emit()
	assert_false(manager.calibrate_to_current())


func test_without_a_gravity_sensor_the_accelerometer_tells_tilt() -> void:
	gravity = Vector3.ZERO
	acceleration = Vector3(0.0, 0.0, -G)
	manager.set_world_visible(true)
	_samples(40)
	assert_eq(manager.availability, manager.Availability.AVAILABLE)
	assert_false(manager.has_gravity_sensor)
	assert_true(manager.has_accelerometer)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	acceleration = _tilted(Vector2(0.0, 15.0))
	_samples(120)
	assert_near(manager.tilt_degrees.y, MotionFilter.shaped(Vector2(0.0, 15.0), 4.0, 25.0).y, 0.3)
	assert_true(manager.debug_text().contains("gravity no"))


func test_shakes_are_published() -> void:
	manager.set_world_visible(true)
	_samples(30)
	# The device is shaken to and fro for a good half second.
	var start := now
	for i in 20:
		now += STEP_MS
		acceleration = gravity + Vector3.RIGHT * 12.0 * sin(TAU * 5.0 * (now - start) / 1000.0)
		manager.sample(STEP, now)
	acceleration = gravity
	_samples(12)
	assert_eq(_shakes.size(), 1)
	assert_eq(_shakes[0][0], ShakeDetector.ShakeClass.MEDIUM)
	assert_true(_shakes[0][1] > 0.3 and _shakes[0][1] < 0.6, "intensity %s" % _shakes[0][1])
	assert_true(absf((_shakes[0][2] as Vector3).x) > 0.95)
	assert_eq(manager.last_shake.shake_class, ShakeDetector.ShakeClass.MEDIUM)
	assert_true(manager.debug_text().contains("shake: medium"))
	# The shaking did not tilt anything.
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	# The player's sensitivity setting: half as sensitive, the same shaking is a light one.
	Settings.set_value(&"motion/shake_sensitivity", 0.5)
	_samples(200)
	start = now
	for i in 20:
		now += STEP_MS
		acceleration = gravity + Vector3.RIGHT * 12.0 * sin(TAU * 5.0 * (now - start) / 1000.0)
		manager.sample(STEP, now)
	acceleration = gravity
	_samples(12)
	assert_eq(_shakes.size(), 2)
	assert_eq(_shakes[1][0], ShakeDetector.ShakeClass.LIGHT)


func test_keys_and_the_stick_stand_in_for_sensors() -> void:
	gravity = Vector3.ZERO
	acceleration = Vector3.ZERO
	turning = Vector3.ZERO
	manager.virtual_allowed = true
	manager.set_world_visible(true)
	_samples(40)
	assert_eq(manager.availability, manager.Availability.UNAVAILABLE)
	assert_false(manager.is_using_virtual())
	# L: the right edge goes down.
	Input.action_press(&"debug_tilt_right")
	_samples(30)
	assert_true(manager.is_using_virtual())
	assert_near(manager.tilt_degrees.x, MotionFilter.shaped(Vector2(Config.motion.virtual_tilt_degrees, 0.0), 4.0, 25.0).x, 0.3)
	assert_near(manager.tilt_degrees.y, 0.0, 0.05)
	assert_true(_tilts.size() > 3, "it comes on gradually")
	assert_true(manager.debug_text().contains("VIRTUAL"))
	# I as well: and the top edge.
	Input.action_press(&"debug_tilt_forward")
	_samples(30)
	assert_true(manager.tilt_degrees.x > 3.0 and manager.tilt_degrees.y > 3.0)
	assert_near(manager.filter.raw_degrees.length(), Config.motion.virtual_tilt_degrees, 0.5, "no further diagonally")
	# Let go: level again.
	Input.action_release(&"debug_tilt_right")
	Input.action_release(&"debug_tilt_forward")
	_samples(40)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_false(manager.is_using_virtual())
	# J and K: the other ways.
	Input.action_press(&"debug_tilt_left")
	Input.action_press(&"debug_tilt_back")
	_samples(30)
	assert_true(manager.tilt_degrees.x < -3.0 and manager.tilt_degrees.y < -3.0)
	Input.action_release(&"debug_tilt_left")
	Input.action_release(&"debug_tilt_back")
	_samples(40)
	# The debug stick.
	manager.set_virtual_stick(Vector2(0.0, 1.0))
	_samples(30)
	assert_true(manager.tilt_degrees.y > 10.0 and absf(manager.tilt_degrees.x) < 0.05)
	manager.set_virtual_stick(Vector2.ZERO)
	_samples(40)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	# Space, Shift+Space, Ctrl+Space, Ctrl+Shift+Space: a shake of each class, through the whole detector.
	var wanted := [ShakeDetector.ShakeClass.LIGHT, ShakeDetector.ShakeClass.MEDIUM, ShakeDetector.ShakeClass.STRONG,
		ShakeDetector.ShakeClass.EXTREME]
	for shake_class: int in wanted:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		key.pressed = true
		key.shift_pressed = shake_class == ShakeDetector.ShakeClass.MEDIUM or shake_class == ShakeDetector.ShakeClass.EXTREME
		key.ctrl_pressed = shake_class >= ShakeDetector.ShakeClass.STRONG
		manager._unhandled_input(key)
		assert_true(manager.virtual.is_shaking(now))
		_samples(60)
		assert_eq(_shakes.size(), shake_class + 1, "one shake for the key (%s)" % ShakeDetector.class_name_of(shake_class))
		assert_eq(_shakes[-1][0], shake_class)
		assert_eq(manager.tilt_vector, Vector2.ZERO)
	# Asked for directly (the stick's buttons); during its cooldown nothing comes of it.
	assert_true(manager.virtual_shake(ShakeDetector.ShakeClass.EXTREME))
	_samples(60)
	assert_eq(_shakes.size(), 4)
	# Not allowed (a release build with debug tools locked): keys and stick do nothing.
	manager.virtual_allowed = false
	Input.action_press(&"debug_tilt_right")
	manager.set_virtual_stick(Vector2(1.0, 0.0))
	assert_false(manager.virtual_shake(ShakeDetector.ShakeClass.LIGHT))
	_samples(30)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	assert_false(manager.is_using_virtual())
	Input.action_release(&"debug_tilt_right")
	# Unlocking the debug tools allows them.
	manager.virtual_allowed = false
	Settings.set_value(&"debug/enabled", true)
	assert_true(manager.virtual_allowed)


func test_in_the_game() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	AudioManager.ensure_sounds()
	manager.virtual_allowed = true
	gravity = Vector3.ZERO
	acceleration = Vector3.ZERO
	assert_false(manager.is_sampling())
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	main.get_node("UIRoot").quit_action = func() -> void: pass
	# The world is on screen: the sensors are read.
	assert_true(manager.is_sampling())
	_samples(5)
	assert_eq(_reads[0], 5)
	# The overlay says how things stand, and has the stick.
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	if not overlay.is_shown():
		overlay.toggle()
	await wait_frames(2)
	overlay.refresh()
	assert_true((overlay.get_node("%OverlayLabel") as Label).text.contains("motion: reading at 30 Hz"))
	var stick: TiltStick = main.tilt_stick
	assert_true(stick.visible)
	assert_true(stick.get_node("Pad").is_in_group(InputRouter.UI_BLOCKER_GROUP), "a touch on it is not a touch on the world")
	# Pushed up: the top edge of the box goes down.
	stick.hold_at(Vector2(TiltStick.PAD_SIZE * 0.5, 0.0))
	assert_true(stick.is_held())
	assert_eq(stick.stick(), Vector2(0.0, 1.0))
	_samples(30)
	assert_true(manager.tilt_degrees.y > 10.0)
	stick.release()
	_samples(40)
	assert_eq(manager.tilt_vector, Vector2.ZERO)
	# To the right, only half way.
	stick.hold_at(Vector2(TiltStick.PAD_SIZE * 0.5 + (TiltStick.PAD_SIZE * 0.5 - TiltStick.KNOB_RADIUS) * 0.5, TiltStick.PAD_SIZE * 0.5))
	assert_near(stick.stick().x, 0.5, 0.001)
	_samples(30)
	assert_near(manager.filter.raw_degrees.x, Config.motion.virtual_tilt_degrees * 0.5, 0.3)
	stick.release()
	_samples(40)
	# Its buttons shake the box.
	stick.shake_button(ShakeDetector.ShakeClass.MEDIUM).pressed.emit()
	_samples(60)
	assert_eq(_shakes.size(), 1)
	assert_eq(_shakes[0][0], ShakeDetector.ShakeClass.MEDIUM)
	# Hidden with the overlay — and it lets go.
	stick.hold_at(Vector2(0.0, TiltStick.PAD_SIZE * 0.5))
	overlay.toggle()
	await wait_frames(2)
	assert_false(stick.visible)
	assert_false(stick.is_held())
	assert_eq(manager.virtual.stick, Vector2.ZERO)
	# The world closed: nothing is read any more.
	get_tree().unload_current_scene()
	await wait_frames(2)
	main = null
	assert_false(manager.is_sampling())
	assert_eq(manager.idle_reason(), "no world on screen")
