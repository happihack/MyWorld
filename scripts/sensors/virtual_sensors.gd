class_name VirtualSensors
extends RefCounted
## Sensors made up for a machine that has none (the desktop, an emulator):
## a tilt from the keys (I J K L) or the debug stick, and a shake of each
## class at the press of a key. What it makes up are *readings* — gravity
## and acceleration — so that everything behind the sensors (filter,
## detector, cooldowns) is exercised exactly as on a device.

## After a made-up shake the made-up device lies still for this long
## (milliseconds): a shake is only over when it has been quiet for a while.
const REST_MS := 500

## Where the keys point: -1 … 1 (x: right edge lower, y: top edge lower).
var keys := Vector2.ZERO
## Where the debug stick is held: likewise (zero when let go).
var stick := Vector2.ZERO
## Where two fingers have dragged the box (the touch way of tilting, for
## everyone — not a debug tool): -1 … 1, 1 = as far as it goes.
var touch := Vector2.ZERO
## The tilt that stands for now, in degrees (it comes and goes at a speed).
var tilt_degrees := Vector2.ZERO

var _config: MotionConfig
var _debug_degrees := Vector2.ZERO
var _touch_degrees := Vector2.ZERO
var _shake_class := -1
var _shake_start_ms := 0
var _shake_end_ms := 0
var _shake_peak := 0.0


func _init(config: MotionConfig = null) -> void:
	_config = config


func reset() -> void:
	keys = Vector2.ZERO
	stick = Vector2.ZERO
	touch = Vector2.ZERO
	tilt_degrees = Vector2.ZERO
	_debug_degrees = Vector2.ZERO
	_touch_degrees = Vector2.ZERO
	_shake_class = -1


## Is anything being made up right now by the debug tools (keys, stick, a shake)?
func is_in_use(now_ms: int) -> bool:
	if keys != Vector2.ZERO or stick != Vector2.ZERO or _debug_degrees.length() > 0.01:
		return true
	return _shake_class >= 0 and now_ms <= _shake_end_ms + REST_MS


## Is the box tilted by touch (or still on its way back level)?
func touch_in_use() -> bool:
	return touch != Vector2.ZERO or _touch_degrees.length() > 0.01


## Forgets what the debug tools were doing (they have been locked).
func reset_debug() -> void:
	keys = Vector2.ZERO
	stick = Vector2.ZERO
	_debug_degrees = Vector2.ZERO
	_shake_class = -1


func is_shaking(now_ms: int) -> bool:
	return _shake_class >= 0 and now_ms <= _shake_end_ms


## Lets `delta` seconds pass: the tilt goes towards where keys and stick point.
func advance(delta: float) -> void:
	var config := _settings()
	var target := (keys + stick).limit_length(1.0) * config.virtual_tilt_degrees
	_debug_degrees = _debug_degrees.move_toward(target, config.virtual_tilt_speed * maxf(delta, 0.0))
	# Touch: from the first bit of dragging on (the dead zone is for hands
	# that shake, not for fingers that mean it) to as far as it goes.
	var pulled := touch.limit_length(1.0)
	var touch_target := Vector2.ZERO
	if pulled != Vector2.ZERO:
		touch_target = pulled.normalized() * lerpf(config.dead_zone_degrees, config.clamp_degrees, pulled.length())
	_touch_degrees = _touch_degrees.move_toward(touch_target, config.touch_tilt_speed * maxf(delta, 0.0))
	tilt_degrees = (_debug_degrees + _touch_degrees).limit_length(config.clamp_degrees)


## Begins a shake of a class (ShakeDetector.ShakeClass): strong and long
## enough to be one, not enough to be the next.
func start_shake(shake_class: int, now_ms: int) -> void:
	var config := _settings()
	if shake_class < 0 or shake_class >= config.peak_from.size():
		return
	var from := config.peak_from[shake_class]
	var next := config.peak_from[shake_class + 1] if shake_class + 1 < config.peak_from.size() else from * 1.6
	_shake_class = shake_class
	_shake_peak = lerpf(from, next, 0.45)
	_shake_start_ms = now_ms
	# (Long enough for the swings it takes, and to be judged as a whole.)
	var swings_ms := roundi((config.reversals_from[shake_class] + 2) * 500.0 / config.virtual_shake_hz)
	_shake_end_ms = now_ms + maxi(maxi(config.duration_from_ms[shake_class] + 150, swings_ms), 400)


## What the gravity sensor would say (m/s²), for a device that counts as
## level when gravity points along `level`.
func gravity(level: Vector3) -> Vector3:
	return MotionFilter.direction_for(tilt_degrees, level) * 9.80665


## What the accelerometer would say (m/s²) at `now_ms`, given gravity.
func acceleration(now_ms: int, gravity_now: Vector3) -> Vector3:
	if not is_shaking(now_ms):
		return gravity_now
	var seconds := (now_ms - _shake_start_ms) / 1000.0
	return gravity_now + Vector3.RIGHT * _shake_peak * sin(TAU * _settings().virtual_shake_hz * seconds)


func _settings() -> MotionConfig:
	return _config if _config != null else Config.motion
