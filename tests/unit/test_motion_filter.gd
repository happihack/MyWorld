extends TestCase
## From gravity readings to tilt (M8.1, bible §23.5, §31.11): the dead
## zone, the clamp, smoothing, readings that cannot be right (NaN, no
## gravity, spikes), and the way the device is held counting as level.

const G := 9.80665
const STEP := 1.0 / 30.0

var config: MotionConfig
var filter: MotionFilter


func before_each() -> void:
	config = MotionConfig.new()
	filter = MotionFilter.new(config)


## Gravity for a device tilted by `degrees` from lying flat.
func _flat(degrees: Vector2) -> Vector3:
	return MotionFilter.direction_for(degrees, MotionFilter.FLAT) * G


## Holds the device like that for a while (long enough to settle).
func _hold(gravity: Vector3, seconds: float = 1.5) -> void:
	for i in ceili(seconds / STEP):
		filter.push(gravity, STEP)


func test_config_is_sound() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.motion.validate().size(), 0)
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	assert_near(config.dead_zone_degrees, 4.0, 0.001, "the bible's defaults")
	assert_near(config.clamp_degrees, 25.0, 0.001)
	assert_near(config.sample_seconds(), 1.0 / 30.0, 0.0001)


func test_which_way_is_which() -> void:
	# Lying flat, face up: level.
	_hold(Vector3(0.0, 0.0, -G))
	assert_eq(filter.tilt_degrees, Vector2.ZERO)
	assert_eq(filter.tilt_vector, Vector2.ZERO)
	assert_true(filter.has_reading())
	# The right edge lower: gravity pulls to the right of the screen — x is positive.
	_hold(Vector3(G * sin(deg_to_rad(15.0)), 0.0, -G * cos(deg_to_rad(15.0))))
	assert_near(filter.raw_degrees.x, 15.0, 0.05)
	assert_near(filter.raw_degrees.y, 0.0, 0.05)
	assert_true(filter.tilt_degrees.x > 0.0 and absf(filter.tilt_degrees.y) < 0.01)
	# The top edge lower: y is positive.
	_hold(Vector3(0.0, G * sin(deg_to_rad(10.0)), -G * cos(deg_to_rad(10.0))))
	assert_near(filter.raw_degrees.y, 10.0, 0.05)
	assert_true(filter.tilt_degrees.y > 0.0 and absf(filter.tilt_degrees.x) < 0.01)
	# Left and towards the viewer: both negative.
	_hold(_flat(Vector2(-12.0, -9.0)))
	assert_near(filter.raw_degrees.x, -12.0, 0.05)
	assert_near(filter.raw_degrees.y, -9.0, 0.05)
	assert_true(filter.tilt_vector.x < 0.0 and filter.tilt_vector.y < 0.0)
	# The axes can be turned round for a device that reads otherwise.
	config.invert_x = true
	_hold(_flat(Vector2(-12.0, -9.0)), 0.1)
	assert_near(filter.raw_degrees.x, 12.0, 0.05)
	assert_near(filter.raw_degrees.y, -9.0, 0.05)


func test_dead_zone() -> void:
	# Nothing below four degrees — in any direction.
	for degrees: Vector2 in [Vector2(3.9, 0.0), Vector2(0.0, -3.9), Vector2(2.7, 2.7), Vector2(-1.0, 0.5)]:
		filter.reset()
		_hold(_flat(degrees))
		assert_eq(filter.tilt_degrees, Vector2.ZERO, str(degrees))
		assert_eq(filter.tilt_vector, Vector2.ZERO)
		assert_true(filter.raw_degrees.distance_to(degrees) < 0.1, "but it is known how it is held")
	# Just beyond it: a little, not a jump.
	filter.reset()
	_hold(_flat(Vector2(4.5, 0.0)))
	assert_true(filter.tilt_degrees.x > 0.0 and filter.tilt_degrees.x < 1.0, str(filter.tilt_degrees))
	# The rule itself: nothing, then rising without a jump, and at the clamp the clamp.
	assert_eq(MotionFilter.shaped(Vector2(4.0, 0.0), 4.0, 25.0), Vector2.ZERO)
	assert_near(MotionFilter.shaped(Vector2(4.001, 0.0), 4.0, 25.0).x, 0.0, 0.01)
	assert_near(MotionFilter.shaped(Vector2(14.5, 0.0), 4.0, 25.0).x, 12.5, 0.001, "half way between dead zone and clamp")
	assert_near(MotionFilter.shaped(Vector2(25.0, 0.0), 4.0, 25.0).x, 25.0, 0.001)
	var diagonal := MotionFilter.shaped(Vector2(-9.0, 12.0), 4.0, 25.0)
	assert_near(diagonal.angle(), Vector2(-9.0, 12.0).angle(), 0.0001, "the direction is kept")
	assert_near(diagonal.length(), (15.0 - 4.0) / 21.0 * 25.0, 0.001)
	assert_eq(MotionFilter.shaped(Vector2(10.0, 0.0), 30.0, 25.0), Vector2.ZERO, "(a dead zone beyond the clamp: nothing)")


func test_clamp() -> void:
	_hold(_flat(Vector2(25.0, 0.0)))
	assert_near(filter.tilt_degrees.x, 25.0, 0.05)
	assert_near(filter.tilt_vector.x, 1.0, 0.002)
	# Further counts no more.
	for degrees: float in [30.0, 45.0, 70.0]:
		_hold(_flat(Vector2(degrees, 0.0)))
		assert_near(filter.tilt_degrees.x, 25.0, 0.001, "%s degrees" % degrees)
		assert_near(filter.tilt_vector.length(), 1.0, 0.0001)
		assert_true(filter.raw_degrees.x > 29.0, "though it is known to be more")
	# Diagonally too: the length is capped, not each axis.
	_hold(_flat(Vector2(30.0, -30.0)))
	assert_near(filter.tilt_degrees.length(), 25.0, 0.001)
	assert_near(filter.tilt_vector.length(), 1.0, 0.0001)
	assert_near(filter.tilt_degrees.x, -filter.tilt_degrees.y, 0.01)


func test_nan_and_infinity_are_thrown_out() -> void:
	_hold(_flat(Vector2(15.0, 0.0)))
	var before := filter.tilt_degrees
	var accepted := filter.accepted
	for bad: Vector3 in [Vector3(NAN, 0.0, -G), Vector3(0.0, INF, -G), Vector3(0.0, 0.0, -INF), Vector3(NAN, NAN, NAN)]:
		assert_eq(filter.push(bad, STEP), MotionFilter.Reject.NOT_A_NUMBER)
		assert_eq(filter.tilt_degrees, before, "the tilt stays what it was")
		assert_true(MotionFilter.is_usable(filter.gravity_direction()))
	assert_eq(filter.rejected, 4)
	assert_eq(filter.accepted, accepted)
	assert_eq(filter.last_reject, MotionFilter.Reject.NOT_A_NUMBER)
	# A time that is no time does no harm either.
	assert_eq(filter.push(_flat(Vector2(15.0, 0.0)), NAN), MotionFilter.Reject.NONE)
	assert_eq(filter.push(_flat(Vector2(15.0, 0.0)), -1.0), MotionFilter.Reject.NONE)
	assert_true(MotionFilter.is_usable(Vector3(filter.tilt_degrees.x, filter.tilt_degrees.y, 0.0)))
	assert_near(filter.tilt_degrees.x, before.x, 0.01)
	# No gravity at all (no sensor, or free fall), and far too much of it.
	assert_eq(filter.push(Vector3.ZERO, STEP), MotionFilter.Reject.NO_GRAVITY)
	assert_eq(filter.push(Vector3(0.0, 0.0, -2.0), STEP), MotionFilter.Reject.NO_GRAVITY)
	assert_eq(filter.push(Vector3(0.0, 0.0, -40.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.tilt_degrees, before)
	# A filter that has only ever been told nonsense has nothing to say.
	var fresh := MotionFilter.new(config)
	fresh.push(Vector3(NAN, 0.0, 0.0), STEP)
	assert_false(fresh.has_reading())
	assert_eq(fresh.tilt_vector, Vector2.ZERO)
	assert_false(fresh.calibrate_to_current())


func test_spikes_are_thrown_out() -> void:
	_hold(_flat(Vector2(10.0, 0.0)))
	var before := filter.tilt_degrees
	# One reading that has the device on its side: a spike.
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.tilt_degrees, before)
	assert_eq(filter.push(_flat(Vector2(10.0, 0.0)), STEP), MotionFilter.Reject.NONE)
	# Two, and then back: still spikes.
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.push(_flat(Vector2(10.0, 0.0)), STEP), MotionFilter.Reject.NONE)
	assert_near(filter.tilt_degrees.x, before.x, 0.01)
	# Spikes in different directions are not "the same again".
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.push(Vector3(-G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.push(Vector3(0.0, G, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_near(filter.tilt_degrees.x, before.x, 0.01)
	# Three times the same: the device really has been turned.
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.SPIKE)
	assert_eq(filter.push(Vector3(G, 0.0, 0.0), STEP), MotionFilter.Reject.NONE)
	_hold(Vector3(G, 0.0, 0.0))
	assert_true(filter.raw_degrees.x > 80.0)
	assert_near(filter.tilt_degrees.x, 25.0, 0.001)
	# A quick but real turn within what a hand does is no spike.
	filter.reset()
	_hold(_flat(Vector2.ZERO), 0.2)
	assert_eq(filter.push(_flat(Vector2(35.0, 0.0)), STEP), MotionFilter.Reject.NONE)


func test_smoothing_converges() -> void:
	_hold(_flat(Vector2.ZERO), 0.5)
	# Tilted at once to twenty degrees: the tilt follows, it does not jump.
	var target := _flat(Vector2(20.0, 0.0))
	filter.push(target, STEP)
	var first := filter.raw_degrees.x
	assert_true(first > 2.0 and first < 10.0, "a part of the way after one reading (%.2f)" % first)
	var last := first
	for i in 10:
		filter.push(target, STEP)
		assert_true(filter.raw_degrees.x > last, "ever nearer")
		last = filter.raw_degrees.x
	assert_true(last > 15.0 and last < 20.0, "%.2f after a third of a second" % last)
	_hold(target, 1.0)
	assert_near(filter.raw_degrees.x, 20.0, 0.02, "and there after a second")
	assert_near(filter.tilt_degrees.x, MotionFilter.shaped(Vector2(20.0, 0.0), 4.0, 25.0).x, 0.05)
	# The same however the time is cut up.
	var coarse := MotionFilter.new(config)
	var fine := MotionFilter.new(config)
	coarse.push(_flat(Vector2.ZERO), 0.1)
	fine.push(_flat(Vector2.ZERO), 0.1)
	coarse.push(target, 0.2)
	for i in 4:
		fine.push(target, 0.05)
	assert_near(coarse.raw_degrees.x, fine.raw_degrees.x, 0.2)
	# No smoothing: at once.
	config.smoothing_seconds = 0.0
	var direct := MotionFilter.new(config)
	direct.push(_flat(Vector2.ZERO), STEP)
	direct.push(target, STEP)
	assert_near(direct.raw_degrees.x, 20.0, 0.01)
	# Jitter of a degree around level is nothing at all.
	config.smoothing_seconds = 0.12
	filter.reset()
	for i in 90:
		filter.push(_flat(Vector2(sin(i * 1.7) * 1.0, cos(i * 2.3) * 1.0)), STEP)
		assert_eq(filter.tilt_vector, Vector2.ZERO)


func test_level_is_how_the_device_is_held() -> void:
	# Held as people hold a phone: the top edge up by forty degrees.
	var held := _flat(Vector2(0.0, -40.0))
	_hold(held)
	assert_near(filter.tilt_degrees.y, -25.0, 0.001, "against lying flat: tilted as far as it goes")
	assert_true(filter.calibrate_to_current())
	assert_eq(filter.tilt_degrees, Vector2.ZERO)
	assert_true(filter.baseline().distance_to(held.normalized()) < 0.001)
	# From there: ten degrees to the right is ten degrees to the right.
	var level := held.normalized()
	_hold(MotionFilter.direction_for(Vector2(10.0, 0.0), level) * G)
	assert_near(filter.raw_degrees.x, 10.0, 0.05)
	assert_near(filter.raw_degrees.y, 0.0, 0.05)
	# Laid flat now, the top edge is forty degrees lower than "level".
	_hold(Vector3(0.0, 0.0, -G))
	assert_near(filter.raw_degrees.y, 40.0, 0.1)
	assert_near(filter.raw_degrees.x, 0.0, 0.1)
	# Given directly (from the settings), and what cannot be a baseline is refused.
	assert_true(filter.set_baseline(Vector3(0.0, 0.0, -3.0)))
	assert_eq(filter.baseline(), MotionFilter.FLAT)
	assert_near(filter.raw_degrees.y, 0.0, 0.1)
	assert_false(filter.set_baseline(Vector3.ZERO))
	assert_false(filter.set_baseline(Vector3(NAN, 0.0, 0.0)))
	assert_eq(filter.baseline(), MotionFilter.FLAT)
	# However it is held — upright, on its side, face down — tilt is measured from there.
	for level_held: Vector3 in [Vector3(0.0, -1.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0),
			Vector3(0.3, -0.8, -0.5).normalized()]:
		for degrees: Vector2 in [Vector2(10.0, 0.0), Vector2(0.0, -7.0), Vector2(-12.0, 9.0)]:
			var back := MotionFilter.angles(MotionFilter.direction_for(degrees, level_held), level_held)
			assert_true(back.distance_to(degrees) < 0.01, "%s from %s: %s" % [degrees, level_held, back])
		assert_true(MotionFilter.angles(level_held, level_held).length() < 0.001)
	# Raised from flat to upright, "top edge lower" keeps meaning the same thing all the way.
	var previous := MotionFilter.level_axes(MotionFilter.FLAT)[1]
	for raised in range(5, 91, 5):
		var top := MotionFilter.level_axes(MotionFilter.direction_for(Vector2(0.0, -float(mini(raised, 85))), MotionFilter.FLAT)
			if raised < 90 else Vector3(0.0, -1.0, 0.0))[1]
		assert_true(top.dot(previous) > 0.9, "at %d degrees" % raised)
		previous = top


func test_sensitivity() -> void:
	_hold(_flat(Vector2(8.0, 0.0)))
	var normal := filter.tilt_degrees.x
	assert_near(normal, MotionFilter.shaped(Vector2(8.0, 0.0), 4.0, 25.0).x, 0.05)
	filter.set_sensitivity(2.0)
	assert_near(filter.tilt_degrees.x, MotionFilter.shaped(Vector2(16.0, 0.0), 4.0, 25.0).x, 0.05, "twice as much")
	filter.set_sensitivity(0.4)
	assert_eq(filter.tilt_degrees, Vector2.ZERO, "3.2 degrees: within the dead zone")
	filter.set_sensitivity(NAN)
	assert_near(filter.tilt_degrees.x, normal, 0.001, "nonsense: as if nothing had been set")
	filter.set_sensitivity(1000.0)
	assert_near(filter.tilt_degrees.x, 25.0, 0.001, "capped")
	# reset() forgets the readings, not how the device is held or set.
	filter.set_sensitivity(1.0)
	filter.set_baseline(_flat(Vector2(0.0, -30.0)))
	filter.reset()
	assert_false(filter.has_reading())
	assert_eq([filter.tilt_degrees, filter.accepted, filter.rejected], [Vector2.ZERO, 0, 0])
	assert_true(filter.baseline().distance_to(_flat(Vector2(0.0, -30.0)).normalized()) < 0.001)
