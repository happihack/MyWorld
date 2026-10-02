extends TestCase
## Telling a shake from a bump (M8.1, bible §23.6): made-up traces of the
## accelerometer — a single spike, a knock on the table, light shaking,
## long strong shaking — and what the detector makes of them; cooldowns.

const G := Vector3(0.0, 0.0, -9.80665)
const STEP_MS := 33
const LIGHT := ShakeDetector.ShakeClass.LIGHT
const MEDIUM := ShakeDetector.ShakeClass.MEDIUM
const STRONG := ShakeDetector.ShakeClass.STRONG
const EXTREME := ShakeDetector.ShakeClass.EXTREME

var config: MotionConfig
var detector: ShakeDetector
var now := 0


func before_each() -> void:
	config = MotionConfig.new()
	detector = ShakeDetector.new(config)
	now = 1000
	_still(300)


## The device at rest for so long. Returns the shakes reported.
func _still(ms: int, gravity: Vector3 = G, known: bool = true) -> Array:
	var found: Array = []
	for i in ceili(float(ms) / STEP_MS):
		now += STEP_MS
		var shake := detector.push(gravity, gravity if known else Vector3.ZERO, now)
		if shake != null:
			found.append(shake)
	return found


## The device shaken to and fro along `axis`: so strongly (m/s²), so many
## swings a second, for so long. Returns the shakes reported.
func _shaken(peak: float, ms: int, hz: float = 5.0, axis: Vector3 = Vector3.RIGHT, known: bool = true) -> Array:
	var found: Array = []
	var start := now
	while now - start < ms:
		now += STEP_MS
		var swing := axis * peak * sin(TAU * hz * (now - start) / 1000.0)
		var shake := detector.push(G + swing, G if known else Vector3.ZERO, now)
		if shake != null:
			found.append(shake)
	return found


## A shake from beginning to end (the rest after it included).
func _shake(peak: float, ms: int, hz: float = 5.0, axis: Vector3 = Vector3.RIGHT) -> Array:
	return _shaken(peak, ms, hz, axis) + _still(400)


func _classes(shakes: Array) -> Array:
	return shakes.map(func(shake: ShakeDetector.Shake) -> int: return shake.shake_class)


func test_what_makes_a_class() -> void:
	# The bible's four classes and their cooldowns.
	assert_eq(ShakeDetector.CLASS_NAMES, [&"light", &"medium", &"strong", &"extreme"] as Array[StringName])
	assert_eq(Array(config.cooldown_seconds), [1.5, 5.0, 20.0, 60.0])
	assert_eq(config.window_ms, 600)
	# Peak, changes of direction and duration together: the highest class all three allow.
	assert_eq(ShakeDetector.classify(5.0, 3, 300, config), LIGHT)
	assert_eq(ShakeDetector.classify(12.0, 3, 300, config), MEDIUM)
	assert_eq(ShakeDetector.classify(20.0, 4, 500, config), STRONG)
	assert_eq(ShakeDetector.classify(40.0, 6, 800, config), EXTREME)
	assert_eq(ShakeDetector.classify(3.0, 9, 900, config), ShakeDetector.ShakeClass.NONE, "too weak")
	assert_eq(ShakeDetector.classify(40.0, 1, 900, config), ShakeDetector.ShakeClass.NONE, "one change of direction is no shaking")
	assert_eq(ShakeDetector.classify(40.0, 9, 100, config), ShakeDetector.ShakeClass.NONE, "too short")
	assert_eq(ShakeDetector.classify(40.0, 2, 250, config), MEDIUM, "hard but brief: no earthquake")
	assert_eq(ShakeDetector.classify(40.0, 3, 400, config), STRONG)
	assert_eq(ShakeDetector.class_name_of(STRONG), &"strong")
	assert_eq(ShakeDetector.class_name_of(-1), &"none")


func test_a_single_spike_is_no_shake() -> void:
	for size: float in [6.0, 20.0, 45.0]:
		now += STEP_MS
		assert_null(detector.push(G + Vector3(size, 0.0, 0.0), G, now))
		assert_eq(_still(900), [], "a jolt of %s" % size)
		assert_false(detector.is_moving())
	assert_eq(detector.shakes_reported, 0)


func test_a_knock_on_the_table_is_no_shake() -> void:
	# The phone on a table that is bumped: a hard jolt and its ringing —
	# back and forth within a few hundredths of a second, dying away.
	for ringing: Array in [[30.0, -18.0, 8.0, -3.0], [22.0, -20.0, 15.0, -9.0, 5.0], [-35.0, 14.0, -6.0], [12.0, -11.0, 4.0]]:
		for swing: float in ringing:
			now += STEP_MS
			assert_null(detector.push(G + Vector3(0.0, 0.0, swing), G, now))
		assert_eq(_still(900), [], str(ringing))
	# Set down on the table, picked up again: two jolts a second apart.
	now += STEP_MS
	detector.push(G + Vector3(0.0, 0.0, 25.0), G, now)
	assert_eq(_still(1000), [])
	now += STEP_MS
	detector.push(G + Vector3(0.0, 0.0, -25.0), G, now)
	assert_eq(_still(1000), [])
	assert_eq(detector.shakes_reported, 0)


func test_light_shaking_is_a_light_shake() -> void:
	var shakes := _shake(5.5, 500)
	assert_eq(_classes(shakes), [LIGHT])
	var shake: ShakeDetector.Shake = shakes[0]
	assert_true(shake.peak >= 3.5 and shake.peak <= 5.6, "%.2f" % shake.peak)
	assert_true(shake.reversals >= 2)
	assert_true(shake.duration_ms >= 150 and shake.duration_ms <= 520)
	assert_near(shake.intensity, shake.peak / 26.0, 0.001)
	assert_true(absf(shake.direction.x) > 0.95, "along the line it was shaken")
	assert_true(shake.describe().begins_with("light"))
	assert_false(detector.is_moving(), "and it is over")
	# Too gentle to be anything.
	now += 5000
	assert_eq(_shake(2.2, 800), [])
	# Along another line.
	now += 5000
	shakes = _shake(6.0, 500, 5.0, Vector3(0.0, 0.6, 0.8))
	assert_eq(_classes(shakes), [LIGHT])
	assert_true(absf((shakes[0] as ShakeDetector.Shake).direction.dot(Vector3(0.0, 0.6, 0.8))) > 0.95)


func test_each_class_from_its_shaking() -> void:
	assert_eq(_classes(_shake(12.0, 600)), [MEDIUM])
	now += 100_000
	assert_eq(_classes(_shake(20.0, 700)), [STRONG])
	now += 100_000
	var extreme := _shake(34.0, 900)
	assert_eq(_classes(extreme), [EXTREME])
	assert_near((extreme[0] as ShakeDetector.Shake).intensity, 1.0, 0.0001)
	# One report for one shake: no light, medium, strong on the way up.
	assert_eq(detector.shakes_reported, 3)
	# Hard, but too brief to be an earthquake.
	now += 100_000
	assert_eq(_classes(_shake(30.0, 260)), [MEDIUM])
	# Faster and slower hands.
	for hz: float in [3.0, 4.0, 6.0, 8.0]:
		now += 100_000
		assert_eq(_classes(_shake(12.0, 800, hz)), [MEDIUM], "%s swings a second" % hz)


func test_long_strong_shaking_is_a_strong_shake() -> void:
	var start := now
	var shakes := _shaken(20.0, 3000)
	assert_eq(_classes(shakes), [STRONG], "once, however long it goes on")
	var shake: ShakeDetector.Shake = shakes[0]
	assert_true(shake.time_ms - start >= config.window_ms and shake.time_ms - start <= config.window_ms + 2 * STEP_MS,
		"reported when it has gone on for the window (%d ms)" % (shake.time_ms - start))
	assert_true(shake.reversals >= 3 and shake.duration_ms >= 350)
	assert_true(detector.is_moving())
	assert_eq(_still(400), [])
	assert_false(detector.is_moving())


func test_shaking_that_grows_is_reported_again() -> void:
	var first := _shaken(5.5, 800)
	assert_eq(_classes(first), [LIGHT])
	# Without a pause it becomes violent.
	var more := _shaken(20.0, 900) + _still(400)
	assert_true(more.size() >= 1)
	assert_eq((more[-1] as ShakeDetector.Shake).shake_class, STRONG)
	var last := LIGHT
	for shake: ShakeDetector.Shake in more:
		assert_true(shake.shake_class > last, "only ever upwards")
		last = shake.shake_class
	# It dies down: nothing more is said of it.
	now += 100_000
	var fading := _shaken(20.0, 800)
	assert_eq(_classes(fading), [STRONG])
	assert_eq(_shaken(6.0, 800) + _still(400), [])


func test_cooldowns_are_respected() -> void:
	assert_eq(_classes(_shake(5.5, 500)), [LIGHT])
	var reported := now
	assert_true(detector.cooldown_left(LIGHT, now) > 0.5)
	assert_near(detector.cooldown_left(MEDIUM, now), 0.0, 0.0001)
	# Again at once: nothing (and it is counted).
	assert_eq(_shake(5.5, 500), [])
	assert_eq(detector.shakes_held_back, 1)
	# A stronger one is not held back by the cooldown of a weaker.
	assert_eq(_classes(_shake(12.0, 600)), [MEDIUM])
	# After a medium shake: no light and no medium for their cooldowns.
	assert_eq(_shake(5.5, 500), [])
	_still(1600)
	assert_eq(_classes(_shake(5.5, 500)), [LIGHT], "a second and a half later: light again")
	assert_eq(_shake(12.0, 600), [], "but not medium (five seconds)")
	_still(5000)
	assert_eq(_classes(_shake(12.0, 600)), [MEDIUM])
	assert_true(now - reported > 5000)
	# A strong one rests for twenty seconds, an extreme one for sixty.
	_still(6000)
	assert_eq(_classes(_shake(20.0, 700)), [STRONG])
	_still(10_000)
	assert_eq(_shake(20.0, 700), [])
	assert_true(detector.cooldown_left(STRONG, now) > 5.0 and detector.cooldown_left(STRONG, now) < 10.0)
	_still(10_000)
	assert_eq(_classes(_shake(20.0, 700)), [STRONG])
	_still(21_000)
	assert_eq(_classes(_shake(34.0, 900)), [EXTREME])
	_still(30_000)
	assert_eq(_shake(34.0, 900), [], "not even as a strong one: one earthquake at a time")
	assert_true(detector.cooldown_left(EXTREME, now) > 20.0)
	# Shaken without end: again each time the cooldown is over, not in between.
	detector.reset()
	var endless := _shaken(5.5, 6000)
	assert_true(endless.size() >= 2 and endless.size() <= 4, "%d reports in six seconds" % endless.size())
	for i in range(1, endless.size()):
		assert_true((endless[i] as ShakeDetector.Shake).time_ms - (endless[i - 1] as ShakeDetector.Shake).time_ms >= 1500)


func test_turning_the_device_is_no_shake() -> void:
	# Tilted from flat to upright and back within a second: gravity moves, nothing is shaken.
	for step in 60:
		now += STEP_MS
		var angle := deg_to_rad(90.0) * sin(step / 60.0 * PI)
		var gravity := Vector3(0.0, -sin(angle), -cos(angle)) * 9.80665
		assert_null(detector.push(gravity, gravity, now))
	assert_eq(_still(500), [])
	# The same on a device without a gravity sensor (gravity has to be guessed).
	detector.reset()
	_still(1000, G, false)
	for step in 90:
		now += STEP_MS
		var angle := deg_to_rad(60.0) * sin(step / 90.0 * PI)
		assert_null(detector.push(Vector3(0.0, -sin(angle), -cos(angle)) * 9.80665, Vector3.ZERO, now), "step %d" % step)
	assert_eq(_still(500, G, false), [])
	# Such a device still knows a shake when it gets one.
	now += 2000
	_still(500, G, false)
	var shakes := _shaken(12.0, 700, 5.0, Vector3.RIGHT, false) + _still(400, G, false)
	assert_eq(_classes(shakes), [MEDIUM])
	# Carried along in a walking hand: slow swaying, nothing.
	detector.reset()
	_still(300)
	assert_eq(_shaken(2.5, 4000, 1.2), [])


func test_sensitivity_and_bad_readings() -> void:
	# Twice as sensitive: half the movement is enough.
	detector.set_sensitivity(2.0)
	assert_eq(_classes(_shake(2.8, 500)), [LIGHT])
	now += 100_000
	assert_eq(_classes(_shake(6.0, 600)), [MEDIUM])
	# Half as sensitive: it takes twice as much.
	detector.set_sensitivity(0.5)
	now += 100_000
	assert_eq(_shake(5.5, 500), [])
	assert_eq(_classes(_shake(12.0, 600)), [LIGHT])
	detector.set_sensitivity(1.0)
	# Readings that are no numbers are passed over, whatever they are part of.
	now += 100_000
	var start := now
	var shakes: Array = []
	while now - start < 600:
		now += STEP_MS
		var shake := detector.push(G + Vector3.RIGHT * 12.0 * sin(TAU * 5.0 * (now - start) / 1000.0), G, now)
		if shake != null:
			shakes.append(shake)
		assert_null(detector.push(Vector3(NAN, 0.0, 0.0), G, now))
		assert_null(detector.push(G, Vector3(0.0, INF, 0.0), now))
	shakes += _still(400)
	assert_eq(_classes(shakes), [MEDIUM])
	assert_true(detector.rejected >= 30)
	# A clock that stands still or runs backwards does no harm.
	assert_null(detector.push(G + Vector3(50.0, 0.0, 0.0), G, now))
	assert_null(detector.push(G - Vector3(50.0, 0.0, 0.0), G, now - 500))
	assert_eq(_still(900), [])
	# reset() forgets everything, cooldowns too.
	detector.reset()
	assert_near(detector.cooldown_left(MEDIUM, now), 0.0, 0.0001)
	assert_eq([detector.samples, detector.shakes_reported], [0, 0])
	_still(300)
	assert_eq(_classes(_shake(12.0, 600)), [MEDIUM])
