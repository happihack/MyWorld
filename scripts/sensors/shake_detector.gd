class_name ShakeDetector
extends RefCounted
## Tells a shake from a bump (bible §23.6). Not raw spikes: the
## acceleration that is not gravity, with what changes slowly taken out
## (the device being turned), is watched for a stretch of movement — its
## peak, how often it changes direction, how long it goes on — and that is
## what makes it a LIGHT, MEDIUM, STRONG or EXTREME shake. One knock is
## nothing; neither is the ringing after it.
##
## A shake is judged once it has gone on for the window (or has ended
## before that); if it goes on and grows, the higher class is reported
## too. After a shake of a class there is none of that class (or a lower
## one) for its cooldown.
##
## Pure: it is given readings and the time, and knows nothing of the
## engine's sensors.

enum ShakeClass { NONE = -1, LIGHT, MEDIUM, STRONG, EXTREME }

const CLASS_NAMES: Array[StringName] = [&"light", &"medium", &"strong", &"extreme"]
## A swing counts (as a change of direction, and towards how long the
## shake goes on) if it is at least this share of the strongest so far:
## what trails after a knock is not shaking.
const SWING_SHARE := 0.4
## Readings further apart than this (seconds) have nothing to do with each
## other: what was going on before is forgotten (not the cooldowns).
const GAP_SECONDS := 0.5

## What push() reports: a shake.
class Shake:
	extends RefCounted
	var shake_class: ShakeClass = ShakeClass.NONE
	## How strong, 0 … 1 (1: as strong as an EXTREME shake has to be, or more).
	var intensity := 0.0
	## Along which line the device was shaken (a unit vector in the device's
	## axes; which way round it points means nothing).
	var direction := Vector3.ZERO
	var peak := 0.0
	var reversals := 0
	var duration_ms := 0
	var time_ms := 0

	func describe() -> String:
		return "%s  peak %.1f  reversals %d  %d ms  intensity %.2f" % [
			ShakeDetector.class_name_of(shake_class), peak, reversals, duration_ms, intensity]


## For the overlay and tests.
var samples := 0
var rejected := 0
var shakes_reported := 0
var shakes_held_back := 0 # (by a cooldown)

var _config: MotionConfig
var _sensitivity := 1.0
## Gravity as it is estimated from the acceleration itself (when no gravity
## sensor says), and the slow part of the movement.
var _gravity_estimate := Vector3.ZERO
var _slow := Vector3.ZERO
var _last_ms := -1
# The stretch of movement being watched (-1: none).
var _start_ms := -1
var _last_loud_ms := -1
var _last_swing_ms := -1
var _peak := 0.0
var _peak_vector := Vector3.ZERO
var _reversals := 0
var _last_reversal_ms := -1_000_000
var _heading := Vector3.ZERO # which way it last moved, strongly enough to count
var _judged := false
var _reported: ShakeClass = ShakeClass.NONE
## When each class may be reported again (ms).
var _ready_ms: Array[int] = [-1_000_000_000, -1_000_000_000, -1_000_000_000, -1_000_000_000]


func _init(config: MotionConfig = null) -> void:
	_config = config


static func class_name_of(shake_class: int) -> StringName:
	return CLASS_NAMES[shake_class] if shake_class >= 0 and shake_class < CLASS_NAMES.size() else &"none"


func reset() -> void:
	_gravity_estimate = Vector3.ZERO
	_slow = Vector3.ZERO
	_last_ms = -1
	_end_stretch()
	for i in _ready_ms.size():
		_ready_ms[i] = -1_000_000_000
	samples = 0
	rejected = 0
	shakes_reported = 0
	shakes_held_back = 0


## How readily a shake counts (the player's setting): at 2, half the
## movement is enough.
func set_sensitivity(value: float) -> void:
	_sensitivity = clampf(value, 0.1, 4.0) if is_finite(value) else 1.0


## Is a stretch of movement being watched?
func is_moving() -> bool:
	return _start_ms >= 0


## Seconds until a shake of this class can be reported again (0: now).
func cooldown_left(shake_class: ShakeClass, now_ms: int) -> float:
	if shake_class < 0 or shake_class >= _ready_ms.size():
		return 0.0
	return maxf((_ready_ms[shake_class] - now_ms) / 1000.0, 0.0)


## A reading of the accelerometer (m/s², gravity included) at `now_ms`,
## with what the gravity sensor says (Vector3.ZERO: there is none — it is
## estimated). Returns the shake this reading completes, or null.
func push(acceleration: Vector3, gravity: Vector3, now_ms: int) -> Shake:
	var config := _settings()
	if not MotionFilter.is_usable(acceleration) or not MotionFilter.is_usable(gravity):
		rejected += 1
		return null
	samples += 1
	var delta := 0.0
	if _last_ms >= 0:
		if now_ms <= _last_ms:
			return null # (the clock stood still, or went back)
		delta = (now_ms - _last_ms) / 1000.0
		if delta > GAP_SECONDS:
			# A gap in the readings: begin afresh.
			delta = 0.0
			_gravity_estimate = Vector3.ZERO
			_end_stretch()
	_last_ms = now_ms
	# Without gravity: what is left when the device is moved.
	if gravity == Vector3.ZERO:
		if _gravity_estimate == Vector3.ZERO:
			_gravity_estimate = acceleration
		else:
			_gravity_estimate = _gravity_estimate.lerp(acceleration, _share(delta, config.gravity_estimate_seconds))
		gravity = _gravity_estimate
	var linear := (acceleration - gravity) * _sensitivity
	# Without what changes slowly (the hand carrying the device somewhere).
	_slow = _slow.lerp(linear, _share(delta, config.high_pass_seconds)) if delta > 0.0 else Vector3.ZERO
	var movement := linear - _slow
	var size := movement.length()
	if size >= config.quiet_below:
		if _start_ms < 0:
			_start_ms = now_ms
			_last_reversal_ms = now_ms
			_heading = movement
		_last_loud_ms = now_ms
		if size > _peak:
			_peak = size
			_peak_vector = movement
		# A swing worth the name (not what trails after a knock).
		if size >= _peak * SWING_SHARE:
			_last_swing_ms = now_ms
			if movement.dot(_heading) < 0.0:
				# It has turned round. (Twice in quick succession is ringing, not shaking.)
				if now_ms - _last_reversal_ms >= config.reversal_min_gap_ms:
					_reversals += 1
					_last_reversal_ms = now_ms
				_heading = movement
			elif size > _heading.length():
				_heading = movement
	if _start_ms < 0:
		return null
	var over := now_ms - _last_loud_ms >= config.quiet_ms
	var shake: Shake = null
	# Judged when it has gone on for the window, or has ended before that;
	# after that, only if it has grown into more.
	if over or _judged or now_ms - _start_ms >= config.window_ms:
		_judged = true
		var found := classify(_peak, _reversals, _last_swing_ms - _start_ms, config)
		if found > _reported:
			_reported = found
			if now_ms >= _ready_ms[found]:
				shake = _report(found, now_ms, config)
			else:
				shakes_held_back += 1
		elif _reported != ShakeClass.NONE and now_ms >= _ready_ms[_reported]:
			# Still being shaken when the cooldown is over: it is judged anew.
			over = true
	if over:
		_end_stretch()
	return shake


## What a stretch of movement amounts to: the highest class it has the
## peak, the changes of direction and the duration for.
static func classify(peak: float, reversals: int, duration_ms: int, config: MotionConfig) -> ShakeClass:
	var found := ShakeClass.NONE
	for i in mini(config.peak_from.size(), ShakeClass.EXTREME + 1):
		if peak >= config.peak_from[i] and reversals >= config.reversals_from[i] and duration_ms >= config.duration_from_ms[i]:
			found = i as ShakeClass
	return found


# --- internals --------------------------------------------------------------------------------------

func _settings() -> MotionConfig:
	return _config if _config != null else Config.motion


static func _share(delta: float, seconds: float) -> float:
	return clampf(1.0 - exp(-delta / seconds), 0.0, 1.0) if seconds > 0.0 and delta > 0.0 else (1.0 if delta > 0.0 else 0.0)


func _report(found: ShakeClass, now_ms: int, config: MotionConfig) -> Shake:
	var shake := Shake.new()
	shake.shake_class = found
	shake.peak = _peak
	shake.reversals = _reversals
	shake.duration_ms = _last_swing_ms - _start_ms
	shake.time_ms = now_ms
	shake.intensity = clampf(_peak / config.peak_from[ShakeClass.EXTREME], 0.0, 1.0)
	shake.direction = _peak_vector.normalized() if _peak_vector.length() > 0.0001 else Vector3.ZERO
	# That class, and every lower one, rests for its cooldown.
	for i in range(0, found + 1):
		_ready_ms[i] = maxi(_ready_ms[i], now_ms + roundi(config.cooldown_seconds[i] * 1000.0))
	shakes_reported += 1
	return shake


func _end_stretch() -> void:
	_start_ms = -1
	_last_loud_ms = -1
	_last_swing_ms = -1
	_peak = 0.0
	_peak_vector = Vector3.ZERO
	_reversals = 0
	_last_reversal_ms = -1_000_000
	_heading = Vector3.ZERO
	_judged = false
	_reported = ShakeClass.NONE
