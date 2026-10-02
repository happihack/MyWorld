class_name MotionFilter
extends RefCounted
## From what the gravity sensor says to how the box is tilted (bible §23.5,
## §31.11): readings that cannot be right are thrown out (NaN, infinity, no
## gravity at all, a spike), the rest is smoothed, measured against the
## way the device is held when it counts as level (the baseline), freed of
## the small tilt nobody means (dead zone) and capped (clamp).
##
## Pure: it is given readings and the time between them, and knows nothing
## of the engine's sensors.
##
## Axes: X to the right of the screen, Y to its top, Z out of it towards
## the viewer. Gravity points where things fall: a device lying flat, face
## up, reads (0, 0, -9.8). The tilt's x is positive when the right edge is
## lower, its y when the top edge is lower — the way things would slide.

## A device lying flat, face up.
const FLAT := Vector3(0.0, 0.0, -1.0)

## Why a reading was not used.
enum Reject { NONE, NOT_A_NUMBER, NO_GRAVITY, SPIKE }

## How the tilt is now, in degrees (dead zone and clamp applied).
var tilt_degrees := Vector2.ZERO
## The same from 0 to 1: its length is 1 at the clamp.
var tilt_vector := Vector2.ZERO
## Before the dead zone and the clamp (for calibration and the overlay).
var raw_degrees := Vector2.ZERO
## For the overlay and tests.
var accepted := 0
var rejected := 0
var last_reject: Reject = Reject.NONE

var _config: MotionConfig
var _baseline := FLAT
## The smoothed direction of gravity (a unit vector); zero until the first reading.
var _smoothed := Vector3.ZERO
## A direction far from the smoothed one, seen in the last readings (a
## spike — or the beginning of a real, quick turn), and how often in a row.
var _odd := Vector3.ZERO
var _odd_count := 0
var _sensitivity := 1.0


func _init(config: MotionConfig = null) -> void:
	_config = config


func reset() -> void:
	tilt_degrees = Vector2.ZERO
	tilt_vector = Vector2.ZERO
	raw_degrees = Vector2.ZERO
	_smoothed = Vector3.ZERO
	_odd = Vector3.ZERO
	_odd_count = 0
	accepted = 0
	rejected = 0
	last_reject = Reject.NONE


## How the device is held when the world is level: the direction of
## gravity then (any length; an unusable one leaves the baseline as it is).
func set_baseline(gravity: Vector3) -> bool:
	if not is_usable(gravity) or gravity.length() < 0.0001:
		return false
	_baseline = gravity.normalized()
	_update_tilt()
	return true


func baseline() -> Vector3:
	return _baseline


## How much a degree of the device counts (the player's setting).
func set_sensitivity(value: float) -> void:
	_sensitivity = clampf(value, 0.1, 4.0) if is_finite(value) else 1.0
	_update_tilt()


## Has there been a reading to go by?
func has_reading() -> bool:
	return _smoothed != Vector3.ZERO


## The direction of gravity as it is taken to be now (a unit vector; zero
## before the first reading).
func gravity_direction() -> Vector3:
	return _smoothed


## A reading of the gravity sensor (m/s²), `delta` seconds after the last.
## Returns why it was not used (Reject.NONE: it was).
func push(gravity: Vector3, delta: float) -> Reject:
	var config := _settings()
	last_reject = _judge(gravity, config)
	if last_reject != Reject.NONE:
		rejected += 1
		return last_reject
	var direction := gravity.normalized()
	if _smoothed == Vector3.ZERO:
		_smoothed = direction
	else:
		# A reading far from where the device was: once is a spike; several
		# times the same is the device having been turned.
		if rad_to_deg(_smoothed.angle_to(direction)) > config.spike_degrees:
			if _odd_count > 0 and rad_to_deg(_odd.angle_to(direction)) <= config.spike_degrees:
				_odd_count += 1
			else:
				_odd_count = 1
			_odd = direction
			if _odd_count < config.spike_samples:
				rejected += 1
				last_reject = Reject.SPIKE
				return last_reject
		else:
			_odd_count = 0
		var share := 1.0
		if config.smoothing_seconds > 0.0 and is_finite(delta) and delta >= 0.0:
			share = 1.0 - exp(-delta / config.smoothing_seconds)
		var blended := _smoothed.lerp(direction, clampf(share, 0.0, 1.0))
		_smoothed = blended.normalized() if blended.length() > 0.0001 else direction
	accepted += 1
	_update_tilt()
	return Reject.NONE


## Takes the way the device is held now as level. False before any reading.
func calibrate_to_current() -> bool:
	return has_reading() and set_baseline(_smoothed)


# --- the rules (static) -----------------------------------------------------------------------------

static func is_usable(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


## The screen's right and top as far as they lie in the plane that is
## level when gravity points along `level` (a unit vector): [right, top].
static func level_axes(level: Vector3) -> Array[Vector3]:
	var top := Vector3.UP - level * Vector3.UP.dot(level)
	if top.length() < 0.05:
		# (Held upright, the screen's top points straight up: then "top" is
		# what faces away from the viewer — as it comes to be when the device
		# is raised from lying flat.)
		top = Vector3.FORWARD - level * Vector3.FORWARD.dot(level)
	top = top.normalized()
	# (At right angles to it — the screen's right, as near as level allows.)
	return [level.cross(top).normalized(), top]


## How far gravity `direction` is from `level` (both unit vectors), in
## degrees: x to the right, y to the top of the screen.
static func angles(direction: Vector3, level: Vector3) -> Vector2:
	var axes := level_axes(level)
	var down := direction.dot(level)
	return Vector2(rad_to_deg(atan2(direction.dot(axes[0]), down)), rad_to_deg(atan2(direction.dot(axes[1]), down)))


## The other way round: where gravity points (a unit vector) when the
## device is tilted by `degrees` from `level`.
static func direction_for(degrees: Vector2, level: Vector3) -> Vector3:
	var axes := level_axes(level)
	return (level + axes[0] * tan(deg_to_rad(clampf(degrees.x, -85.0, 85.0)))
		+ axes[1] * tan(deg_to_rad(clampf(degrees.y, -85.0, 85.0)))).normalized()


## A tilt of `degrees` with the dead zone taken out and the clamp put on:
## nothing below the dead zone, rising from there without a jump, and at
## the clamp exactly the clamp.
static func shaped(degrees: Vector2, dead_zone: float, clamp_at: float) -> Vector2:
	var size := degrees.length()
	if size <= dead_zone or size <= 0.0 or clamp_at <= dead_zone:
		return Vector2.ZERO
	var capped := minf(size, clamp_at)
	return degrees / size * ((capped - dead_zone) / (clamp_at - dead_zone) * clamp_at)


# --- internals --------------------------------------------------------------------------------------

func _settings() -> MotionConfig:
	return _config if _config != null else Config.motion


func _judge(gravity: Vector3, config: MotionConfig) -> Reject:
	if not is_usable(gravity):
		return Reject.NOT_A_NUMBER
	var size := gravity.length()
	if size < config.gravity_min or size > config.gravity_max:
		return Reject.NO_GRAVITY if size < config.gravity_min else Reject.SPIKE
	return Reject.NONE


func _update_tilt() -> void:
	if _smoothed == Vector3.ZERO:
		return
	var config := _settings()
	raw_degrees = angles(_smoothed, _baseline)
	if config.invert_x:
		raw_degrees.x = -raw_degrees.x
	if config.invert_y:
		raw_degrees.y = -raw_degrees.y
	tilt_degrees = shaped(raw_degrees * _sensitivity, config.dead_zone_degrees, config.clamp_degrees)
	tilt_vector = tilt_degrees / config.clamp_degrees
