extends TestCase
## InputRouter driven by real InputEvents pushed through the root viewport.

const RouterScript := preload("res://scripts/interaction/input_router.gd")

var router: InputRouter
var got: Array = []
var blocker: Control


func before_each() -> void:
	router = RouterScript.new()
	add_child(router)
	got = []
	router.gesture_recognized.connect(func(g: Gesture) -> void: got.append(g.type_name()))
	await wait_frames(1)


func after_each() -> void:
	router.queue_free()
	if is_instance_valid(blocker):
		blocker.queue_free()
	await wait_frames(1)


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = index
	t.position = pos
	t.pressed = pressed
	get_tree().root.push_input(t, true)


func _mouse(button: MouseButton, pos: Vector2, pressed: bool, device: int = 0) -> void:
	var m := InputEventMouseButton.new()
	m.button_index = button
	m.position = pos
	m.pressed = pressed
	m.device = device
	get_tree().root.push_input(m, true)


func test_units_per_dp_is_sane() -> void:
	var u := router.recognizer.units_per_dp
	assert_true(u >= InputRouter.UNITS_PER_DP_MIN and u <= InputRouter.UNITS_PER_DP_MAX, str(u))


func test_touch_becomes_tap() -> void:
	_touch(0, Vector2(500, 500), true)
	_touch(0, Vector2(500, 500), false)
	assert_eq(got, ["TAP"])


func test_ui_blocker_keeps_touch_out_of_world() -> void:
	blocker = Control.new()
	blocker.size = Vector2(200, 200)
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_to_group(InputRouter.UI_BLOCKER_GROUP)
	get_tree().root.add_child(blocker)
	_touch(0, Vector2(100, 100), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(400, 100)
	get_tree().root.push_input(drag, true)
	_touch(0, Vector2(400, 100), false)
	assert_eq(got, [])
	blocker.hide()
	_touch(0, Vector2(100, 100), true)
	_touch(0, Vector2(100, 100), false)
	assert_eq(got, ["TAP"], "hidden blockers don't block")


func test_touch_emulated_mouse_ignored() -> void:
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(600, 600), true, InputEvent.DEVICE_ID_EMULATION)
	_mouse(MOUSE_BUTTON_LEFT, Vector2(600, 600), true, InputEvent.DEVICE_ID_EMULATION)
	assert_eq(got, [])


func test_wheel_is_pinch_at_cursor() -> void:
	var scales := []
	router.gesture_recognized.connect(func(g: Gesture) -> void: scales.append(g.scale))
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(600, 600), true)
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, Vector2(600, 600), true)
	assert_eq(got, ["PINCH", "PINCH"])
	assert_true(scales[0] > 1.0 and scales[1] < 1.0)


func test_right_drag_is_two_finger_drag_until_release() -> void:
	_mouse(MOUSE_BUTTON_RIGHT, Vector2(600, 600), true)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(650, 610)
	get_tree().root.push_input(mm, true)
	_mouse(MOUSE_BUTTON_RIGHT, Vector2(650, 610), false)
	get_tree().root.push_input(mm, true)
	assert_eq(got, ["MULTI_START", "TWO_FINGER_DRAG", "MULTI_END"], "bracketed like a real two-finger gesture")


func test_focus_loss_cancels_drag() -> void:
	_touch(0, Vector2(300, 300), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(400, 300)
	get_tree().root.push_input(drag, true)
	EventBus.app_focus_changed.emit(false)
	assert_eq(got.back(), "DRAG_END")
	assert_true(router.recognizer.is_idle())


func test_touch_ended_is_reported_even_when_no_gesture_is() -> void:
	var ended := []
	router.touch_ended.connect(func(pos: Vector2) -> void: ended.append(pos))
	var at := Vector2(300, 400)
	_touch(0, at, true)
	assert_eq(ended.size(), 0)
	await wait_real_ms(Config.interaction.long_press_ms + 120)
	assert_has(got, "HOLD")
	assert_has(got, "LONG_PRESS")
	var before := got.size()
	_touch(0, at, false)
	assert_eq(got.size(), before, "lifting after a long press is no gesture")
	assert_eq(ended, [at], "but the lift is still reported")
	# A normal tap: the gesture first, then the lift.
	var order := []
	router.gesture_recognized.connect(func(g: Gesture) -> void: order.append(g.type_name()))
	router.touch_ended.connect(func(_pos: Vector2) -> void: order.append("ended"))
	_touch(0, at, true)
	_touch(0, at, false)
	assert_eq(order, ["TAP", "ended"])
	# Losing focus with a finger down ends the touch too.
	_touch(0, at, true)
	EventBus.app_focus_changed.emit(false)
	assert_eq(ended.size(), 3)
	EventBus.app_focus_changed.emit(false)
	assert_eq(ended.size(), 3, "nothing to end when no finger is down")
