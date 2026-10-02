extends TestCase
## Calibrating the motion sensors (M8.2, bible §23.7): place flat, hold
## still, done — starting over when the device moves — or the angle it is
## held at now.

const G := 9.80665
const STEP := 1.0 / 30.0
const PLACE := Calibration.State.PLACE
const HOLD := Calibration.State.HOLD
const DONE := Calibration.State.DONE

var config: MotionConfig
var calibration: Calibration


func before_each() -> void:
	config = MotionConfig.new()
	calibration = Calibration.new(config)


func _held(degrees: Vector2) -> Vector3:
	return MotionFilter.direction_for(degrees, MotionFilter.FLAT) * G


## So many seconds of readings like that. Returns the state after.
func _readings(gravity: Vector3, seconds: float) -> Calibration.State:
	for i in ceili(seconds / STEP):
		calibration.push(gravity, STEP)
	return calibration.state


func test_place_flat_hold_still_done() -> void:
	assert_eq(config.validate().size(), 0)
	assert_near(config.calibration_hold_seconds, 1.5, 0.001, "the bible's second and a half")
	assert_eq(calibration.state, Calibration.State.IDLE)
	assert_eq(calibration.push(_held(Vector2.ZERO), STEP), Calibration.State.IDLE, "not begun: nothing")
	calibration.begin()
	assert_eq(calibration.state, PLACE)
	assert_true(calibration.wants_flat())
	# In the hand, at an angle: still waiting for it to be laid flat.
	assert_eq(_readings(_held(Vector2(5.0, -35.0)), 2.0), PLACE)
	assert_near(calibration.progress, 0.0, 0.0001)
	# Laid down (a table is never quite level): hold still.
	var table := _held(Vector2(1.5, -2.0))
	assert_eq(calibration.push(table, STEP), HOLD)
	assert_eq(_readings(table, 0.7), HOLD)
	assert_true(calibration.progress > 0.4 and calibration.progress < 0.6, "%.2f" % calibration.progress)
	assert_false(calibration.moved)
	assert_eq(calibration.result, Vector3.ZERO)
	# A second and a half of it: done — and level is how it lay.
	assert_eq(_readings(table, 0.9), DONE)
	assert_near(calibration.progress, 1.0, 0.0001)
	assert_true(calibration.result.distance_to(table.normalized()) < 0.0001)
	assert_near(calibration.result.length(), 1.0, 0.0001)
	assert_eq(calibration.restarts, 0)
	# Done is done.
	assert_eq(calibration.push(_held(Vector2(20.0, 0.0)), STEP), DONE)
	assert_true(calibration.result.distance_to(table.normalized()) < 0.0001)


func test_moving_starts_it_over() -> void:
	calibration.begin()
	var table := _held(Vector2.ZERO)
	_readings(table, 1.0)
	assert_true(calibration.progress > 0.6)
	# Nudged: three degrees is more than holding still.
	assert_eq(calibration.push(_held(Vector2(3.0, 0.0)), STEP), HOLD)
	assert_true(calibration.moved, "said so")
	assert_eq(calibration.restarts, 1)
	assert_near(calibration.progress, 0.0, 0.0001)
	# Still again (where it is now): the full time once more.
	assert_eq(_readings(_held(Vector2(3.0, 0.0)), 1.0), HOLD)
	assert_false(calibration.moved)
	assert_eq(_readings(_held(Vector2(3.0, 0.0)), 0.6), DONE)
	assert_true(calibration.result.distance_to(_held(Vector2(3.0, 0.0)).normalized()) < 0.0001, "level is where it came to rest")
	# The trembling of a sensor is not moving.
	calibration.begin()
	for i in 60:
		calibration.push(_held(Vector2(sin(i * 1.3) * 0.5, cos(i * 0.7) * 0.5)), STEP)
	assert_eq(calibration.state, DONE)
	assert_eq(calibration.restarts, 0)
	assert_true(rad_to_deg(calibration.result.angle_to(MotionFilter.FLAT)) < 0.3, "the middle of it")
	# A hand that never holds still never gets there.
	calibration.begin()
	for i in 300:
		calibration.push(_held(Vector2(sin(i * 0.4) * 6.0, 0.0)), STEP)
	assert_eq(calibration.state, HOLD)
	assert_true(calibration.restarts >= 10)
	# Picked up again: back to "place it flat".
	calibration.begin()
	_readings(table, 0.5)
	assert_eq(calibration.push(_held(Vector2(0.0, -30.0)), STEP), PLACE)
	assert_near(calibration.progress, 0.0, 0.0001)


func test_use_the_current_angle() -> void:
	# No laying flat: as it is held.
	var held := _held(Vector2(-4.0, -38.0))
	calibration.begin(false)
	assert_eq(calibration.state, HOLD)
	assert_false(calibration.wants_flat())
	assert_eq(_readings(held, 1.0), HOLD)
	assert_eq(_readings(held, 0.6), DONE)
	assert_true(calibration.result.distance_to(held.normalized()) < 0.0001)
	# Any angle will do — upright, face down — but it must be held still.
	for direction: Vector3 in [Vector3(0.0, -G, 0.0), Vector3(0.0, 0.0, G), Vector3(G, 0.0, 0.0)]:
		calibration.begin(false)
		assert_eq(_readings(direction, 1.6), DONE, str(direction))
		assert_true(calibration.result.distance_to(direction.normalized()) < 0.0001)
	calibration.begin(false)
	_readings(held, 1.0)
	calibration.push(_held(Vector2(-4.0, -30.0)), STEP)
	assert_eq(calibration.restarts, 1)
	assert_eq(calibration.state, HOLD, "not sent back to 'place it flat'")


func test_readings_that_cannot_be_right_are_passed_over() -> void:
	calibration.begin()
	var table := _held(Vector2.ZERO)
	_readings(table, 0.5)
	var progress := calibration.progress
	for bad: Vector3 in [Vector3(NAN, 0.0, -G), Vector3(0.0, 0.0, -INF), Vector3.ZERO, Vector3(0.0, 0.0, -2.0), Vector3(0.0, 0.0, -40.0)]:
		assert_eq(calibration.push(bad, STEP), HOLD)
	assert_near(calibration.progress, progress, 0.0001, "neither forwards nor back")
	assert_eq(calibration.restarts, 0)
	assert_eq(calibration.push(table, NAN), HOLD, "a time that is no time")
	assert_eq(_readings(table, 1.1), DONE)
	assert_true(MotionFilter.is_usable(calibration.result))
	# Cancelled: nothing more comes of readings.
	calibration.begin()
	_readings(table, 0.5)
	calibration.cancel()
	assert_eq(_readings(table, 2.0), Calibration.State.IDLE)
	assert_eq(calibration.result, Vector3.ZERO)
