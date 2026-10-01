extends TestCase
## Exact touch timelines through the pure GestureRecognizer (units_per_dp = 1,
## so slop = 10 units, long press = 450 ms, double tap = 300 ms).

const P := Vector2(100, 100)

var r: GestureRecognizer
var got: Array = []


func before_each() -> void:
	r = GestureRecognizer.new(Config.interaction, 1.0)
	got = []
	r.recognized.connect(func(g: Gesture) -> void: got.append(g))


func _names() -> Array:
	return got.map(func(g: Gesture) -> String: return g.type_name())


func _of(type: Gesture.Type) -> Array:
	return got.filter(func(g: Gesture) -> bool: return g.type == type)


func test_tap() -> void:
	r.touch_down(0, P, 0)
	r.update(50)
	r.touch_up(0, P, 100)
	assert_eq(_names(), ["TAP"])
	assert_true(r.is_idle())


func test_double_tap_then_new_pair() -> void:
	r.touch_down(0, P, 1000); r.touch_up(0, P, 1050)
	r.touch_down(0, P + Vector2(8, 0), 1150); r.touch_up(0, P + Vector2(8, 0), 1200)
	r.touch_down(0, P, 1300); r.touch_up(0, P, 1340)
	assert_eq(_names(), ["TAP", "DOUBLE_TAP", "TAP"])


func test_far_or_slow_taps_are_not_double() -> void:
	r.touch_down(0, P, 0); r.touch_up(0, P, 50)
	r.touch_down(0, P + Vector2(200, 0), 150); r.touch_up(0, P + Vector2(200, 0), 200)
	r.touch_down(0, P, 700); r.touch_up(0, P, 750)
	assert_eq(_names(), ["TAP", "TAP", "TAP"])


func test_long_press_fires_once_and_suppresses_tap() -> void:
	r.touch_down(0, P, 5000)
	r.update(5400)
	assert_true(got.is_empty())
	r.update(5460)
	r.update(5600)
	r.touch_up(0, P, 5700)
	assert_eq(_names(), ["LONG_PRESS"])
	assert_eq(got[0].hold_ms, 460)


func test_drag_respects_slop_and_reports_deltas() -> void:
	r.touch_down(0, Vector2.ZERO, 0)
	r.touch_move(0, Vector2(5, 0), 10)
	assert_true(got.is_empty(), "within slop")
	r.touch_move(0, Vector2(20, 0), 20)
	r.touch_move(0, Vector2(40, 0), 40)
	r.touch_up(0, Vector2(40, 0), 300)
	assert_eq(_names(), ["DRAG_START", "DRAG", "DRAG", "DRAG_END"])
	assert_eq(got[0].start_position, Vector2.ZERO)
	assert_eq(got[1].delta, Vector2(20, 0))
	assert_eq(got[2].delta, Vector2(20, 0))
	assert_eq(got[3].velocity, Vector2.ZERO, "rested before lifting: no fling")


func test_fast_release_swipes() -> void:
	r.touch_down(0, Vector2.ZERO, 0)
	r.touch_move(0, Vector2(20, 0), 10)
	r.touch_move(0, Vector2(60, 0), 20)
	r.touch_move(0, Vector2(100, 0), 30)
	r.touch_up(0, Vector2(120, 0), 40)
	assert_eq(_names().back(), "SWIPE")
	assert_true(got.back().velocity.x > 2000.0)


func test_hold_then_drag_reports_hold_time() -> void:
	r.touch_down(0, P, 0)
	r.update(300)
	r.touch_move(0, P + Vector2(30, 0), 350)
	assert_eq(_names(), ["DRAG_START", "DRAG"])
	assert_eq(got[0].hold_ms, 350)


func test_pinch() -> void:
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, Vector2(100, 0), 10)
	r.touch_move(1, Vector2(200, 0), 20)
	r.touch_up(0, Vector2(0, 0), 30)
	r.touch_up(1, Vector2(200, 0), 40)
	assert_eq(_names(), ["MULTI_START", "PINCH", "TWO_FINGER_DRAG", "MULTI_END"])
	assert_near(got[1].scale, 2.0)
	assert_eq(got[2].delta, Vector2(50, 0))


func test_second_finger_cancels_drag() -> void:
	r.touch_down(0, Vector2.ZERO, 0)
	r.touch_move(0, Vector2(30, 0), 10)
	r.touch_down(1, Vector2(100, 100), 20)
	assert_eq(_names(), ["DRAG_START", "DRAG", "DRAG_END", "MULTI_START"])
	assert_true(got[2].cancelled)


func test_remaining_finger_continues_as_after_multi_drag() -> void:
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, Vector2(100, 0), 10)
	r.touch_up(0, Vector2(0, 0), 20)
	r.touch_move(1, Vector2(150, 0), 30)
	r.touch_move(1, Vector2(250, 0), 40)
	r.touch_up(1, Vector2(350, 0), 50)
	assert_eq(_names(), ["MULTI_START", "MULTI_END", "DRAG_START", "DRAG", "DRAG", "DRAG", "DRAG_END"])
	assert_true(got[2].after_multi)
	assert_false(_names().has("SWIPE"), "after-multi drags never swipe")


func test_leftover_finger_never_taps_or_long_presses() -> void:
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, Vector2(100, 0), 10)
	r.touch_up(0, Vector2(0, 0), 20)
	r.update(2000)
	r.touch_up(1, Vector2(100, 0), 2100)
	assert_eq(_names(), ["MULTI_START", "MULTI_END"])


func _rotated(deg: float, radius: float = 100.0) -> Vector2:
	return Vector2(radius, 0).rotated(deg_to_rad(deg))


func test_twist_starts_after_threshold_without_a_jump() -> void:
	# Finger 0 is the pivot; finger 1 circles it at constant distance.
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, _rotated(0), 10)
	r.touch_move(1, _rotated(8), 20)
	assert_true(_of(Gesture.Type.TWIST).is_empty(), "8 deg is below twist_start_deg")
	r.touch_move(1, _rotated(15), 30) # crosses 12 deg: activates, emits nothing yet
	assert_true(_of(Gesture.Type.TWIST).is_empty(), "activation itself does not rotate")
	r.touch_move(1, _rotated(45), 40)
	r.touch_move(1, _rotated(90), 50)
	var twists := _of(Gesture.Type.TWIST)
	assert_eq(twists.size(), 2)
	assert_near(rad_to_deg(twists[0].angle), 30.0, 0.01)
	assert_near(rad_to_deg(twists[1].angle), 45.0, 0.01)
	assert_true(_of(Gesture.Type.PINCH).is_empty(), "constant distance: no pinch")


func test_finger_jitter_emits_nothing() -> void:
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, Vector2(300, 0), 10)
	# A resting two-finger hold: a few units of wobble in every direction.
	for i in 20:
		r.touch_move(0, Vector2(sin(i) * 2.0, cos(i * 1.3) * 2.0), 20 + i * 10)
		r.touch_move(1, Vector2(300 + cos(i) * 3.0, sin(i * 0.7) * 3.0), 25 + i * 10)
	assert_eq(_names(), ["MULTI_START"])


func test_real_pinch_does_not_twist() -> void:
	# Fingers spread from 200 to 600 apart while the angle wobbles by a few degrees.
	r.touch_down(0, Vector2(400, 500), 0)
	r.touch_down(1, Vector2(600, 500), 10)
	for i in range(1, 11):
		var half := 100.0 + i * 20.0
		var wobble := deg_to_rad(sin(i * 1.7) * 4.0)
		var offset := Vector2(half, 0).rotated(wobble)
		r.touch_move(0, Vector2(500, 500) - offset, 20 + i * 10)
		r.touch_move(1, Vector2(500, 500) + offset, 25 + i * 10)
	assert_true(_of(Gesture.Type.TWIST).is_empty(), "4 deg wobble never twists")
	var total := 1.0
	for g: Gesture in _of(Gesture.Type.PINCH):
		total *= g.scale
	assert_near(total, 3.0, 0.01, "pinch scales multiply to 600/200")


func test_two_finger_drag_needs_slop_then_includes_it() -> void:
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, Vector2(100, 0), 10)
	r.touch_move(0, Vector2(0, 6), 20)
	r.touch_move(1, Vector2(100, 6), 30)
	assert_true(_of(Gesture.Type.TWO_FINGER_DRAG).is_empty(), "6 units is inside the slop")
	# Fingers report one at a time, in small steps (as on a real touchscreen).
	var t := 40
	for y in [14, 22, 30, 40]:
		r.touch_move(0, Vector2(0, y), t)
		r.touch_move(1, Vector2(100, y), t + 5)
		t += 10
	var total := Vector2.ZERO
	for g: Gesture in _of(Gesture.Type.TWO_FINGER_DRAG):
		total += g.delta
	assert_eq(total, Vector2(0, 40), "no movement is lost once the drag starts")
	assert_true(_of(Gesture.Type.PINCH).is_empty() and _of(Gesture.Type.TWIST).is_empty())


func test_three_finger_tap() -> void:
	r.touch_down(0, Vector2(0, 0), 0); r.touch_down(1, Vector2(50, 0), 5); r.touch_down(2, Vector2(100, 0), 10)
	r.touch_up(0, Vector2(0, 0), 100); r.touch_up(1, Vector2(50, 0), 105); r.touch_up(2, Vector2(100, 0), 110)
	assert_has(_names(), "THREE_FINGER_TAP")
	assert_false(_names().has("TAP"))
	assert_true(r.is_idle())


func test_moved_three_fingers_is_not_a_tap() -> void:
	r.touch_down(0, Vector2(0, 0), 0); r.touch_down(1, Vector2(50, 0), 5); r.touch_down(2, Vector2(100, 0), 10)
	r.touch_move(2, Vector2(100, 200), 50)
	r.touch_up(0, Vector2(0, 0), 100); r.touch_up(1, Vector2(50, 0), 105); r.touch_up(2, Vector2(100, 200), 110)
	assert_false(_names().has("THREE_FINGER_TAP"))


func test_cancel_all_ends_drag_cancelled() -> void:
	r.touch_down(0, Vector2.ZERO, 0)
	r.touch_move(0, Vector2(50, 0), 10)
	r.cancel_all(20)
	assert_eq(_names().back(), "DRAG_END")
	assert_true(got.back().cancelled)
	assert_true(r.is_idle())


func test_missed_release_is_closed_safely() -> void:
	r.touch_down(0, P, 0)
	r.touch_down(0, P, 100) # same index pressed again without a release
	r.touch_up(0, P, 150)
	assert_eq(_names(), ["TAP", "DOUBLE_TAP"])
	assert_true(r.is_idle())


func test_thresholds_scale_with_units_per_dp() -> void:
	r.units_per_dp = 3.0 # slop becomes 30 units
	r.touch_down(0, Vector2.ZERO, 0)
	r.touch_move(0, Vector2(25, 0), 10)
	assert_true(got.is_empty())
	r.touch_move(0, Vector2(31, 0), 20)
	assert_eq(_names()[0], "DRAG_START")
