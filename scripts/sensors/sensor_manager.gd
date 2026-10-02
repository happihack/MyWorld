extends Node
## Autoload "SensorManager": the device's motion sensors, read for the game
## (bible §23.5–23.7, §31.12).
##
## It publishes two things: how the box is **tilted** (`tilt_vector`:
## smoothed, measured against how the device is held when level, freed of
## the dead zone, capped) and **shakes** (`shake_event`: a class, how
## strong, along which line). What is done with them is not its business.
##
## The sensors are read at a fixed rate and only while there is a reason
## to: motion controls are switched on, the app is in front, and the world
## is on screen. Otherwise nothing is read at all (the battery).
##
## A device without sensors says nothing but zeros: after a second of that
## it counts as having none. On such a machine — the desktop, an emulator
## — keys and the debug stick stand in (see VirtualSensors), in debug builds.

## The tilt has changed (see `tilt_vector`).
signal tilt_changed(tilt: Vector2)
## The device was shaken: a ShakeDetector.ShakeClass, how strong (0 … 1),
## and along which line (the device's axes).
signal shake_event(shake_class: int, intensity: float, direction: Vector3)
## The device turns out to have motion sensors, or to have none.
signal availability_changed(available: bool)
## The sensors are being read from now on, or no longer.
signal sampling_changed(sampling: bool)

enum Availability { UNKNOWN, AVAILABLE, UNAVAILABLE }

## How the box is tilted, 0 … 1 (1 at the clamp): x positive when the
## right edge of the screen is lower, y when its top edge is — the way
## things slide. Zero while nothing is read.
var tilt_vector := Vector2.ZERO
## The same in degrees.
var tilt_degrees := Vector2.ZERO
## How fast the device turns (rad/s, the gyroscope); zero without one.
var rotation_rate := Vector3.ZERO
var availability: Availability = Availability.UNKNOWN
var has_gravity_sensor := false
var has_accelerometer := false
var has_gyroscope := false
## The last shake reported (null: none yet).
var last_shake: ShakeDetector.Shake
var last_shake_msec := -1

## Where the readings come from (tests put their own here).
var read_gravity: Callable = func() -> Vector3: return Input.get_gravity()
var read_accelerometer: Callable = func() -> Vector3: return Input.get_accelerometer()
var read_gyroscope: Callable = func() -> Vector3: return Input.get_gyroscope()
## The real time in milliseconds.
var now_msec: Callable = func() -> int: return Time.get_ticks_msec()

var filter: MotionFilter
var detector: ShakeDetector
var virtual: VirtualSensors
## May keys and the debug stick stand in for sensors? (Debug builds, or
## debug tools unlocked.)
var virtual_allowed := false
## How often the sensors have been read (for tests and the overlay).
var reads := 0

var _config: MotionConfig
var _enabled := true
var _in_front := true
var _world_visible := false
var _sampling := false
var _since_sample := 0.0
var _since_probe := 0.0
# Readings of nothing but zeros in a row, for each sensor.
var _zero_gravity := 0
var _zero_acceleration := 0
var _zero_gyroscope := 0
## Gravity as the accelerometer alone tells it (no gravity sensor).
var _felt_gravity := Vector3.ZERO
## Calibrated by the player (the baseline is in the settings)? If not, how
## the device is held in the first moments counts as level.
var _calibrated := false
var _baseline_seconds := 0.0
var _baseline_set := false
var _using_virtual := false


func _ready() -> void:
	_config = Config.motion
	filter = MotionFilter.new(_config)
	detector = ShakeDetector.new(_config)
	virtual = VirtualSensors.new(_config)
	_enabled = bool(Settings.get_value(&"motion/enabled"))
	virtual_allowed = OS.is_debug_build() or bool(Settings.get_value(&"debug/enabled"))
	_apply_settings()
	Settings.setting_changed.connect(_on_setting_changed)
	EventBus.app_paused.connect(func() -> void: _set_in_front(false))
	EventBus.app_resumed.connect(func() -> void: _set_in_front(true))
	EventBus.app_focus_changed.connect(_set_in_front)


# --- when the sensors are read ------------------------------------------------------------------------

## Tells the manager whether the world is on screen (the game's main
## scene says so): without it there is nothing to tilt.
func set_world_visible(shown: bool) -> void:
	_world_visible = shown
	_update_sampling()


func is_sampling() -> bool:
	return _sampling


func is_available() -> bool:
	return availability == Availability.AVAILABLE


## Why the sensors are not read ("" if they are).
func idle_reason() -> String:
	if not _enabled:
		return "motion controls off"
	if not _in_front:
		return "app not in front"
	if not _world_visible:
		return "no world on screen"
	return ""


func _process(delta: float) -> void:
	if not _sampling:
		return
	_since_sample += delta
	if _since_sample + 0.0005 < _config.sample_seconds():
		return
	var elapsed := _since_sample
	_since_sample = 0.0
	sample(elapsed, now_msec.call())


## Reads the sensors once and brings tilt and shakes up to date. `delta`:
## seconds since the last reading. (Called at the fixed rate by _process;
## tests call it themselves.)
func sample(delta: float, now_ms: int) -> void:
	if not _sampling:
		return
	if virtual_allowed:
		virtual.keys = Vector2(Input.get_axis(&"debug_tilt_left", &"debug_tilt_right"),
			Input.get_axis(&"debug_tilt_back", &"debug_tilt_forward"))
		virtual.advance(delta)
	_using_virtual = virtual_allowed and virtual.is_in_use(now_ms)
	var gravity := Vector3.ZERO
	var acceleration := Vector3.ZERO
	var felt := Vector3.ZERO # what the tilt is read from
	if _using_virtual:
		gravity = virtual.gravity(filter.baseline())
		acceleration = virtual.acceleration(now_ms, gravity)
		felt = gravity
		rotation_rate = Vector3.ZERO
	else:
		# A device without sensors is asked again only now and then.
		if availability == Availability.UNAVAILABLE:
			_since_probe += delta
			if _since_probe < _config.probe_seconds:
				_publish_tilt(Vector2.ZERO, Vector2.ZERO)
				return
			_since_probe = 0.0
		reads += 1
		gravity = _vector(read_gravity.call())
		acceleration = _vector(read_accelerometer.call())
		var turning := _vector(read_gyroscope.call())
		_note_availability(gravity, acceleration, turning)
		rotation_rate = turning if MotionFilter.is_usable(turning) else Vector3.ZERO
		felt = gravity
		if gravity == Vector3.ZERO and acceleration != Vector3.ZERO and MotionFilter.is_usable(acceleration):
			# No gravity sensor: gravity is what the accelerometer feels, smoothed.
			if _felt_gravity == Vector3.ZERO:
				_felt_gravity = acceleration
			else:
				_felt_gravity = _felt_gravity.lerp(acceleration,
					clampf(1.0 - exp(-delta / _config.gravity_estimate_seconds), 0.0, 1.0))
			felt = _felt_gravity
	# Tilt.
	if felt != Vector3.ZERO or not MotionFilter.is_usable(felt):
		if filter.push(felt, delta) == MotionFilter.Reject.NONE and not _using_virtual:
			_settle_baseline(delta)
	if _using_virtual or _baseline_set:
		_publish_tilt(filter.tilt_vector, filter.tilt_degrees)
	else:
		_publish_tilt(Vector2.ZERO, Vector2.ZERO)
	# Shakes.
	if acceleration != Vector3.ZERO or not MotionFilter.is_usable(acceleration):
		var shake := detector.push(acceleration, gravity, now_ms)
		if shake != null:
			last_shake = shake
			last_shake_msec = now_ms
			Log.debug(Log.Category.SENSOR, "Shake", {"class": ShakeDetector.class_name_of(shake.shake_class),
				"peak": snappedf(shake.peak, 0.1), "reversals": shake.reversals, "ms": shake.duration_ms})
			shake_event.emit(shake.shake_class, shake.intensity, shake.direction)


# --- calibration ------------------------------------------------------------------------------------

## Takes the way the device is held now as level, and (if `keep`) keeps it
## in the settings. False if there is no reading to go by.
func calibrate_to_current(keep: bool = true) -> bool:
	if not filter.calibrate_to_current():
		return false
	_baseline_set = true
	if keep:
		_calibrated = true
		Settings.set_value(&"motion/baseline_gravity", filter.baseline())
		Settings.set_value(&"motion/calibrated", true)
	Log.info(Log.Category.SENSOR, "Motion calibrated", {"baseline": filter.baseline(), "kept": keep})
	_publish_tilt(filter.tilt_vector, filter.tilt_degrees)
	return true


## Forgets the player's calibration: from now on, how the device is held
## when the sensors come on counts as level.
func clear_calibration() -> void:
	Settings.set_value(&"motion/calibrated", false)
	Settings.set_value(&"motion/baseline_gravity", Vector3.ZERO)


func is_calibrated() -> bool:
	return _calibrated


# --- virtual sensors ----------------------------------------------------------------------------------

## Makes up a shake of a class (ShakeDetector.ShakeClass), as a key press
## or the debug stick's buttons do. False if virtual sensors are not allowed.
func virtual_shake(shake_class: int) -> bool:
	if not virtual_allowed or not _sampling:
		return false
	virtual.start_shake(shake_class, now_msec.call())
	return true


## Holds the debug stick at `where` (-1 … 1; zero lets go).
func set_virtual_stick(where: Vector2) -> void:
	virtual.stick = where.limit_length(1.0) if virtual_allowed else Vector2.ZERO


func is_using_virtual() -> bool:
	return _using_virtual


func _unhandled_input(event: InputEvent) -> void:
	if not virtual_allowed or not _sampling or not event.is_action_pressed(&"debug_shake"):
		return
	# Space: light; with Shift: medium; with Ctrl: strong; with both: extreme.
	var key := event as InputEventKey
	var shake_class := ShakeDetector.ShakeClass.LIGHT
	if key != null and key.ctrl_pressed and key.shift_pressed:
		shake_class = ShakeDetector.ShakeClass.EXTREME
	elif key != null and key.ctrl_pressed:
		shake_class = ShakeDetector.ShakeClass.STRONG
	elif key != null and key.shift_pressed:
		shake_class = ShakeDetector.ShakeClass.MEDIUM
	virtual_shake(shake_class)
	get_viewport().set_input_as_handled()


# --- for the overlay --------------------------------------------------------------------------------

func debug_text() -> String:
	var state := "reading at %d Hz" % _config.sample_hz if _sampling else "off (%s)" % idle_reason()
	var have := "%s  gravity %s  accel %s  gyro %s" % [
		["sensors ?", "sensors yes", "NO SENSORS"][availability], _mark(has_gravity_sensor), _mark(has_accelerometer), _mark(has_gyroscope)]
	var level := "calibrated" if _calibrated else ("as first held" if _baseline_set else "not yet")
	var shake := "none yet"
	if last_shake != null:
		shake = "%s  %.1f s ago" % [last_shake.describe(), (int(now_msec.call()) - last_shake_msec) / 1000.0]
	return "motion: %s%s
%s   level: %s   thrown out %d
tilt (%.1f°, %.1f°) -> (%.2f, %.2f)   raw (%.1f°, %.1f°)
shake: %s%s" % [
		state, "  VIRTUAL" if _using_virtual else "", have, level, filter.rejected, tilt_degrees.x, tilt_degrees.y,
		tilt_vector.x, tilt_vector.y, filter.raw_degrees.x, filter.raw_degrees.y, shake, "   (moving)" if detector.is_moving() else ""]


# --- internals --------------------------------------------------------------------------------------

static func _mark(there: bool) -> String:
	return "yes" if there else "no"


static func _vector(value: Variant) -> Vector3:
	return value if typeof(value) == TYPE_VECTOR3 else Vector3.ZERO


func _apply_settings() -> void:
	filter.set_sensitivity(float(Settings.get_value(&"motion/tilt_sensitivity")))
	detector.set_sensitivity(float(Settings.get_value(&"motion/shake_sensitivity")))
	var saved: Vector3 = Settings.get_value(&"motion/baseline_gravity")
	_calibrated = bool(Settings.get_value(&"motion/calibrated")) and saved.length() > 0.0001 and filter.set_baseline(saved)
	if _calibrated:
		_baseline_set = true
	else:
		filter.set_baseline(MotionFilter.FLAT)
		_baseline_set = false
		_baseline_seconds = 0.0


func _on_setting_changed(key: StringName, value: Variant) -> void:
	match key:
		&"motion/enabled":
			_enabled = bool(value)
			_update_sampling()
		&"motion/tilt_sensitivity":
			filter.set_sensitivity(float(value))
		&"motion/shake_sensitivity":
			detector.set_sensitivity(float(value))
		&"motion/calibrated", &"motion/baseline_gravity":
			_apply_settings()
		&"debug/enabled":
			virtual_allowed = OS.is_debug_build() or bool(value)
			if not virtual_allowed:
				virtual.reset()


func _set_in_front(in_front: bool) -> void:
	_in_front = in_front
	_update_sampling()


func _update_sampling() -> void:
	var wanted := _enabled and _in_front and _world_visible
	if wanted == _sampling:
		return
	_sampling = wanted
	_since_sample = 0.0
	_since_probe = 0.0
	if wanted:
		Log.info(Log.Category.SENSOR, "Motion sensors on", {"hz": _config.sample_hz})
	else:
		Log.info(Log.Category.SENSOR, "Motion sensors off", {"why": idle_reason(), "reads": reads})
		# Nothing is read: nothing is tilted, and what was going on is forgotten.
		filter.reset()
		detector.reset()
		virtual.reset()
		_felt_gravity = Vector3.ZERO
		_using_virtual = false
		rotation_rate = Vector3.ZERO
		if not _calibrated:
			_baseline_set = false
			_baseline_seconds = 0.0
		_publish_tilt(Vector2.ZERO, Vector2.ZERO)
	sampling_changed.emit(_sampling)


## Not calibrated by the player: the way the device is held in the first
## moments of reading counts as level.
func _settle_baseline(delta: float) -> void:
	if _baseline_set:
		return
	_baseline_seconds += maxf(delta, 0.0)
	if _baseline_seconds >= _config.auto_baseline_seconds and filter.calibrate_to_current():
		_baseline_set = true
		Log.debug(Log.Category.SENSOR, "Motion level taken from how the device is held", {"baseline": filter.baseline()})


## A sensor that says nothing but zeros for long enough is not there.
func _note_availability(gravity: Vector3, acceleration: Vector3, turning: Vector3) -> void:
	_zero_gravity = 0 if gravity != Vector3.ZERO else _zero_gravity + 1
	_zero_acceleration = 0 if acceleration != Vector3.ZERO else _zero_acceleration + 1
	_zero_gyroscope = 0 if turning != Vector3.ZERO else _zero_gyroscope + 1
	var enough := _config.unavailable_after_samples
	if gravity != Vector3.ZERO:
		has_gravity_sensor = true
	elif _zero_gravity >= enough:
		has_gravity_sensor = false
	if acceleration != Vector3.ZERO:
		has_accelerometer = true
	elif _zero_acceleration >= enough:
		has_accelerometer = false
	if turning != Vector3.ZERO:
		has_gyroscope = true
	elif _zero_gyroscope >= enough:
		has_gyroscope = false
	var now := availability
	if has_gravity_sensor or has_accelerometer:
		now = Availability.AVAILABLE
	elif (_zero_gravity >= enough and _zero_acceleration >= enough) or availability == Availability.UNAVAILABLE:
		now = Availability.UNAVAILABLE
	if now != availability:
		availability = now
		Log.info(Log.Category.SENSOR, "Motion sensors found" if now == Availability.AVAILABLE else "No motion sensors",
			{"gravity": has_gravity_sensor, "accelerometer": has_accelerometer, "gyroscope": has_gyroscope})
		availability_changed.emit(now == Availability.AVAILABLE)


func _publish_tilt(vector: Vector2, degrees: Vector2) -> void:
	if vector.is_equal_approx(tilt_vector) and degrees.is_equal_approx(tilt_degrees):
		return
	tilt_vector = vector
	tilt_degrees = degrees
	tilt_changed.emit(tilt_vector)
