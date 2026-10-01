class_name GestureRecognizer
extends RefCounted
## Turns raw touch points into gestures (bible §23.1). Pure logic: it never reads
## Input or the clock itself, so tests drive it with exact timelines.
##
## Feed it touch_down/touch_move/touch_up and call update(now) every frame (hold
## and long press are time-based). Results arrive through the `recognized` signal.
##
## Policies:
## - TAP fires immediately on release; the second tap of a quick pair fires
##   DOUBLE_TAP instead of TAP (no added latency on single taps).
## - A finger resting still fires HOLD after grab_hold_ms, then LONG_PRESS after
##   long_press_ms. HOLD changes nothing else: releasing after it is still a
##   TAP, moving after it is still a drag (with hold_ms telling how long it rested).
## - A second finger cancels the single-finger gesture (DRAG_END cancelled=true).
## - Two-finger components activate independently once they pass a threshold:
##   PINCH (finger distance, pinch_slop_dp), TWO_FINGER_DRAG (centroid,
##   drag_slop_dp) and TWIST (rotation, twist_start_deg). Finger jitter below the
##   thresholds emits nothing, so zooming does not rotate the view. Pinch and
##   drag include the movement that crossed the threshold; twist starts from
##   zero at activation (no sudden rotation jump).
## - When a two-finger gesture ends with one finger still down, that finger can
##   continue as a drag once it moves past the slop (after_multi=true); it can
##   never become a tap or long press.

signal recognized(gesture: Gesture)

enum State { IDLE, PENDING, DRAGGING, MULTI, AFTER_MULTI_WAIT }

const VELOCITY_WINDOW_MS := 100
const DOUBLE_TAP_SLOP_FACTOR := 3.0 # second tap may land this many slops away
const THREE_FINGER_SLOP_FACTOR := 2.0

var config: InteractionConfig
## Viewport units per dp; thresholds in the config are in dp.
var units_per_dp: float = 1.0

var _state := State.IDLE
var _touches: Dictionary = {} # index -> Vector2 current position
var _order: Array[int] = [] # touch indices in press order

# Single-finger tracking
var _primary := -1
var _down_pos := Vector2.ZERO
var _down_time := 0
var _last_pos := Vector2.ZERO
var _long_pressed := false
var _held := false
var _after_multi := false
var _samples: Array = [] # [time_ms, Vector2] for velocity

# Double tap
var _last_tap_time := -100000
var _last_tap_pos := Vector2.ZERO

# Multi-finger tracking
var _multi_dist := 0.0
var _multi_angle := 0.0
var _multi_centroid := Vector2.ZERO
var _multi_start_time := 0
var _multi_start_positions: Dictionary = {}
var _max_touches := 0
var _multi_moved := false
var _pinch_active := false
var _pan_active := false
var _twist_active := false


func _init(interaction_config: InteractionConfig, dp_scale: float = 1.0) -> void:
	config = interaction_config
	units_per_dp = dp_scale


func is_idle() -> bool:
	return _state == State.IDLE


func touch_down(index: int, pos: Vector2, time_ms: int) -> void:
	if _touches.has(index):
		touch_up(index, pos, time_ms) # missed release: close it first
	_touches[index] = pos
	_order.append(index)
	_max_touches = maxi(_max_touches, _touches.size())

	match _state:
		State.IDLE:
			_begin_single(index, pos, time_ms, false)
			_state = State.PENDING
		State.PENDING, State.DRAGGING, State.AFTER_MULTI_WAIT:
			if _state == State.DRAGGING:
				var end := _make(Gesture.Type.DRAG_END, _last_pos, time_ms)
				end.cancelled = true
				_emit(end)
			_begin_multi(time_ms)
		State.MULTI:
			_multi_start_positions[index] = pos # third+ finger: counted, not tracked


func touch_move(index: int, pos: Vector2, time_ms: int) -> void:
	if not _touches.has(index):
		return
	_touches[index] = pos
	match _state:
		State.PENDING:
			if index != _primary:
				return
			_add_sample(time_ms, pos)
			if pos.distance_to(_down_pos) >= _slop():
				_state = State.DRAGGING
				var start := _make(Gesture.Type.DRAG_START, _down_pos, time_ms)
				start.hold_ms = time_ms - _down_time
				_emit(start)
				_emit_drag(pos, time_ms)
		State.DRAGGING:
			if index == _primary:
				_add_sample(time_ms, pos)
				_emit_drag(pos, time_ms)
		State.MULTI:
			_update_multi(time_ms)


func touch_up(index: int, pos: Vector2, time_ms: int) -> void:
	if not _touches.has(index):
		return
	_touches[index] = pos
	match _state:
		State.PENDING:
			if index == _primary:
				_finish_pending(pos, time_ms)
		State.DRAGGING:
			if index == _primary:
				_finish_drag(pos, time_ms)
		State.MULTI:
			_update_multi(time_ms)
	_touches.erase(index)
	_order.erase(index)

	if _state == State.MULTI:
		if _touches.size() == 1 and _max_touches == 2:
			_end_multi(time_ms)
			var remaining: int = _order[0]
			_begin_single(remaining, _touches[remaining], time_ms, true)
			_state = State.PENDING # becomes a drag only after real movement
		elif _touches.size() <= 1 and _max_touches >= 3:
			_end_multi(time_ms)
			_state = State.AFTER_MULTI_WAIT if _touches.size() == 1 else State.IDLE
		elif _touches.is_empty():
			_end_multi(time_ms)
			_state = State.IDLE
		elif _touches.size() >= 2:
			_rebaseline_multi()
	elif _state == State.AFTER_MULTI_WAIT and _touches.is_empty():
		_state = State.IDLE

	if _touches.is_empty() and _state != State.MULTI:
		_state = State.IDLE
		_max_touches = 0


## Call every frame: fires HOLD, then LONG_PRESS, when a finger is held still
## long enough.
func update(time_ms: int) -> void:
	if _state == State.PENDING and not _held and not _long_pressed and not _after_multi:
		if time_ms - _down_time >= config.grab_hold_ms:
			_held = true
			var hold := _make(Gesture.Type.HOLD, _last_pos, time_ms)
			hold.hold_ms = time_ms - _down_time
			_emit(hold)
	if _state == State.PENDING and not _long_pressed and not _after_multi:
		if time_ms - _down_time >= config.long_press_ms:
			_long_pressed = true
			var g := _make(Gesture.Type.LONG_PRESS, _last_pos, time_ms)
			g.hold_ms = time_ms - _down_time
			g.long_pressed = true
			_emit(g)


## Drops all touches (focus lost, app paused). An active drag ends cancelled.
func cancel_all(time_ms: int) -> void:
	if _state == State.DRAGGING:
		var end := _make(Gesture.Type.DRAG_END, _last_pos, time_ms)
		end.cancelled = true
		_emit(end)
	elif _state == State.MULTI:
		var end := _make(Gesture.Type.MULTI_END, _multi_centroid, time_ms)
		end.cancelled = true
		end.touch_count = _touches.size()
		_emit(end)
	_touches.clear()
	_order.clear()
	_state = State.IDLE
	_max_touches = 0


# --- single finger -----------------------------------------------------------

func _begin_single(index: int, pos: Vector2, time_ms: int, after_multi: bool) -> void:
	_primary = index
	_down_pos = pos
	_last_pos = pos
	_down_time = time_ms
	_long_pressed = false
	_held = false
	_after_multi = after_multi
	_samples = [[time_ms, pos]]


func _finish_pending(pos: Vector2, time_ms: int) -> void:
	if _long_pressed or _after_multi:
		return # long press already handled; after-multi lifts are never taps
	var is_double := time_ms - _last_tap_time <= config.double_tap_ms \
		and pos.distance_to(_last_tap_pos) <= _slop() * DOUBLE_TAP_SLOP_FACTOR
	if is_double:
		_emit(_make(Gesture.Type.DOUBLE_TAP, pos, time_ms))
		_last_tap_time = -100000 # a third tap starts a new pair
	else:
		_emit(_make(Gesture.Type.TAP, pos, time_ms))
		_last_tap_time = time_ms
		_last_tap_pos = pos


func _emit_drag(pos: Vector2, time_ms: int) -> void:
	var g := _make(Gesture.Type.DRAG, pos, time_ms)
	g.delta = pos - _last_pos
	_last_pos = pos
	_emit(g)


func _finish_drag(pos: Vector2, time_ms: int) -> void:
	if pos != _last_pos:
		_add_sample(time_ms, pos)
		_emit_drag(pos, time_ms)
	var end := _make(Gesture.Type.DRAG_END, pos, time_ms)
	end.velocity = _velocity(time_ms)
	_emit(end)
	var swipe_speed := config.swipe_min_velocity_dp_s * units_per_dp
	if not _after_multi and end.velocity.length() >= swipe_speed:
		var swipe := _make(Gesture.Type.SWIPE, pos, time_ms)
		swipe.velocity = end.velocity
		swipe.delta = pos - _down_pos
		_emit(swipe)


func _add_sample(time_ms: int, pos: Vector2) -> void:
	_samples.append([time_ms, pos])
	while _samples.size() > 2 and time_ms - int(_samples[0][0]) > VELOCITY_WINDOW_MS:
		_samples.pop_front()


## Average velocity over the movement samples in the last VELOCITY_WINDOW_MS
## before `time_ms`. A finger that rested before lifting has no recent samples,
## so it produces no fling.
func _velocity(time_ms: int) -> Vector2:
	var recent: Array = []
	for sample: Array in _samples:
		if time_ms - int(sample[0]) <= VELOCITY_WINDOW_MS:
			recent.append(sample)
	if recent.size() < 2:
		return Vector2.ZERO
	var first: Array = recent[0]
	var last: Array = recent[-1]
	var dt := (int(last[0]) - int(first[0])) / 1000.0
	if dt <= 0.0:
		return Vector2.ZERO
	return (Vector2(last[1]) - Vector2(first[1])) / dt


# --- multi finger ------------------------------------------------------------

func _begin_multi(time_ms: int) -> void:
	_state = State.MULTI
	_multi_start_time = time_ms
	_multi_start_positions = _touches.duplicate()
	_multi_moved = false
	_pinch_active = false
	_pan_active = false
	_twist_active = false
	_rebaseline_multi()
	var g := _make(Gesture.Type.MULTI_START, _multi_centroid, time_ms)
	g.touch_count = _touches.size()
	_emit(g)


func _rebaseline_multi() -> void:
	var a: Vector2 = _touches[_order[0]]
	var b: Vector2 = _touches[_order[1]]
	_multi_centroid = (a + b) * 0.5
	_multi_dist = a.distance_to(b)
	_multi_angle = (b - a).angle()


func _update_multi(time_ms: int) -> void:
	if _order.size() < 2:
		return
	for idx in _touches:
		var start: Vector2 = _multi_start_positions.get(idx, _touches[idx])
		if Vector2(_touches[idx]).distance_to(start) >= _slop() * THREE_FINGER_SLOP_FACTOR:
			_multi_moved = true
	var a: Vector2 = _touches[_order[0]]
	var b: Vector2 = _touches[_order[1]]
	var centroid := (a + b) * 0.5
	var dist := a.distance_to(b)
	var ang := (b - a).angle()

	# Each baseline (_multi_dist/_centroid/_angle) only moves once its component
	# is active, so sub-threshold jitter accumulates against the starting pose.
	if not _pinch_active and absf(dist - _multi_dist) >= config.pinch_slop_dp * units_per_dp:
		_pinch_active = true
	if _pinch_active:
		if _multi_dist > 0.0 and dist > 0.0 and not is_equal_approx(dist, _multi_dist):
			var pinch := _make(Gesture.Type.PINCH, centroid, time_ms)
			pinch.scale = dist / _multi_dist
			pinch.touch_count = _touches.size()
			_emit(pinch)
		_multi_dist = dist

	if not _pan_active and centroid.distance_to(_multi_centroid) >= _slop():
		_pan_active = true
	if _pan_active:
		if centroid != _multi_centroid:
			var pan := _make(Gesture.Type.TWO_FINGER_DRAG, centroid, time_ms)
			pan.delta = centroid - _multi_centroid
			pan.touch_count = _touches.size()
			_emit(pan)
		_multi_centroid = centroid

	var d_ang := wrapf(ang - _multi_angle, -PI, PI)
	if not _twist_active:
		if absf(d_ang) >= deg_to_rad(config.twist_start_deg):
			_twist_active = true
			_multi_angle = ang # start from zero: no rotation jump on activation
	else:
		if not is_zero_approx(d_ang):
			var twist := _make(Gesture.Type.TWIST, centroid, time_ms)
			twist.angle = d_ang
			twist.touch_count = _touches.size()
			_emit(twist)
		_multi_angle = ang


func _end_multi(time_ms: int) -> void:
	var g := _make(Gesture.Type.MULTI_END, _multi_centroid, time_ms)
	g.touch_count = _max_touches
	_emit(g)
	if _max_touches == 3 and not _multi_moved and time_ms - _multi_start_time < config.long_press_ms:
		var three := _make(Gesture.Type.THREE_FINGER_TAP, _multi_centroid, time_ms)
		three.touch_count = 3
		_emit(three)


# --- helpers -------------------------------------------------------------------

func _slop() -> float:
	return config.drag_slop_dp * units_per_dp


func _make(type: Gesture.Type, pos: Vector2, time_ms: int) -> Gesture:
	var g := Gesture.new(type)
	g.position = pos
	g.start_position = _down_pos
	g.time_ms = time_ms
	g.long_pressed = _long_pressed
	g.after_multi = _after_multi
	return g


func _emit(g: Gesture) -> void:
	recognized.emit(g)
