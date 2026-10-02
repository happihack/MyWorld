class_name Calibration
extends RefCounted
## Finding out how the device is held when the world is level (bible
## §23.7): "Place your phone flat." → "Hold still." (a second and a half
## of readings; if it moves, it starts over) → "Calibration complete."
## Or, without laying it flat: the angle it is held at now.
##
## Pure: it is given gravity readings and the time between them.

enum State {
	IDLE,
	## Waiting for the device to lie flat.
	PLACE,
	## Lying as wanted: readings are being taken.
	HOLD,
	DONE,
}

var state: State = State.IDLE
## How far the holding still has got, 0 … 1.
var progress := 0.0
## The level found (a unit vector: where gravity points); zero until DONE.
var result := Vector3.ZERO
## How often it had to start over because the device moved.
var restarts := 0
## It has just started over (until the next reading that does not).
var moved := false

var _config: MotionConfig
var _flat := true
var _sum := Vector3.ZERO
var _count := 0
var _seconds := 0.0


func _init(config: MotionConfig = null) -> void:
	_config = config


## Begins. `flat`: the device is to be laid flat first; otherwise the
## angle it is held at now is taken.
func begin(flat: bool = true) -> void:
	_flat = flat
	state = State.PLACE if flat else State.HOLD
	result = Vector3.ZERO
	restarts = 0
	moved = false
	_start_over()


func cancel() -> void:
	state = State.IDLE
	_start_over()


func wants_flat() -> bool:
	return _flat


## A gravity reading (m/s²), `delta` seconds after the last. Returns the
## state it leaves the calibration in.
func push(gravity: Vector3, delta: float) -> State:
	if state == State.IDLE or state == State.DONE:
		return state
	var config := _settings()
	if not MotionFilter.is_usable(gravity):
		return state
	var size := gravity.length()
	if size < config.gravity_min or size > config.gravity_max:
		return state
	var direction := gravity / size
	var off_flat := rad_to_deg(direction.angle_to(MotionFilter.FLAT))
	if state == State.PLACE:
		if off_flat > config.calibration_flat_degrees:
			return state
		state = State.HOLD
		_start_over()
	elif _flat and off_flat > config.calibration_flat_degrees * 1.5:
		# Picked up again.
		state = State.PLACE
		_start_over()
		return state
	# Holding still: every reading close to what the others say.
	if _count > 0 and rad_to_deg(direction.angle_to(_sum.normalized())) > config.calibration_spread_degrees:
		restarts += 1
		_start_over()
		moved = true
	elif _count > 0:
		moved = false
	_sum += direction
	_count += 1
	if _count > 1:
		_seconds += maxf(delta, 0.0) if is_finite(delta) else 0.0
	progress = clampf(_seconds / config.calibration_hold_seconds, 0.0, 1.0)
	if _seconds >= config.calibration_hold_seconds:
		result = _sum.normalized()
		state = State.DONE
		progress = 1.0
	return state


func _start_over() -> void:
	_sum = Vector3.ZERO
	_count = 0
	_seconds = 0.0
	progress = 0.0
	moved = false


func _settings() -> MotionConfig:
	return _config if _config != null else Config.motion
