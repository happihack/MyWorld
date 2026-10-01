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


func test_twist() -> void:
	r.touch_down(0, Vector2(0, 0), 0)
	r.touch_down(1, Vector2(100, 0), 10)
	r.touch_move(1, Vector2(0, 100), 20)
	var twists := _of(Gesture.Type.TWIST)
	assert_eq(twists.size(), 1)
	assert_near(rad_to_deg(twists[0].angle), 90.0, 0.01)
	assert_true(_of(Gesture.Type.PINCH).is_empty(), "equal distance: no pinch")


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
