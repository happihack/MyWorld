extends TestCase
## First-time hints: when they appear, when they go away, and that they stay away.

var label: HintLabel
var director: HintDirector


func before_each() -> void:
	Settings.reset_to_defaults()
	label = HintLabel.new()
	add_child(label)
	director = _new_director()


func after_each() -> void:
	director.queue_free()
	label.queue_free()
	Settings.reset_to_defaults()
	await wait_frames(1)


func _new_director() -> HintDirector:
	var d := HintDirector.new(label)
	add_child(d)
	d.set_process(false) # tests advance time themselves
	return d


func _gesture(type: Gesture.Type) -> Gesture:
	return Gesture.new(type)


func _idle() -> float:
	return Config.interaction.hint_idle_seconds


func _follow_up() -> float:
	return Config.interaction.hint_follow_up_seconds


# --- "Drag to explore." -----------------------------------------------------------------------

func test_drag_hint_appears_after_idle_time() -> void:
	director.advance(_idle() - 0.1)
	assert_eq(director.current(), &"")
	assert_false(label.is_showing())
	director.advance(0.2)
	assert_eq(director.current(), HintDirector.DRAG)
	assert_true(label.is_showing())
	assert_true(label.visible)
	assert_eq(label.text(), "Drag to explore.")


func test_touching_the_world_restarts_the_wait() -> void:
	director.advance(_idle() - 1.0)
	director.note_touch()
	director.advance(_idle() - 1.0)
	assert_eq(director.current(), &"", "the player is busy, not idle")
	director.advance(1.1)
	assert_eq(director.current(), HintDirector.DRAG)


func test_first_pan_puts_the_hint_away_for_good() -> void:
	director.advance(_idle() + 0.1)
	director.note_gesture(_gesture(Gesture.Type.DRAG))
	assert_eq(director.current(), &"")
	assert_false(label.is_showing())
	assert_true(director.is_completed(HintDirector.DRAG))
	assert_has(String(Settings.get_value(HintDirector.SETTING)), "drag", "remembered on this device")
	director.advance(_idle() * 4.0)
	assert_ne(director.current(), HintDirector.DRAG, "never again")
	# A new session (new world, relaunch) starts with it already done.
	var later := _new_director()
	later.advance(_idle() * 4.0)
	assert_eq(later.current(), &"")
	later.queue_free()


func test_a_tap_does_not_dismiss_the_drag_hint() -> void:
	director.advance(_idle() + 0.1)
	director.note_touch()
	director.note_gesture(_gesture(Gesture.Type.TAP))
	assert_eq(director.current(), HintDirector.DRAG, "still not explored")
	assert_true(label.is_showing())
	assert_false(director.is_completed(HintDirector.DRAG))
	for type: Gesture.Type in [Gesture.Type.PINCH, Gesture.Type.DOUBLE_TAP, Gesture.Type.DRAG_START]:
		director.note_gesture(_gesture(type))
	assert_eq(director.current(), HintDirector.DRAG, "only moving the view counts")


func test_a_player_who_pans_right_away_never_sees_the_hint() -> void:
	director.advance(1.0)
	director.note_gesture(_gesture(Gesture.Type.TWO_FINGER_DRAG)) # two-finger panning counts too
	assert_true(director.is_completed(HintDirector.DRAG))
	director.advance(_idle() * 3.0)
	assert_false(label.is_showing())


# --- "Hold to learn more." ----------------------------------------------------------------------

func test_hold_hint_follows_the_first_touch() -> void:
	director.note_gesture(_gesture(Gesture.Type.DRAG))
	director.advance(_idle() * 3.0)
	assert_eq(director.current(), &"", "nothing to hold until something was touched")
	director.note_gesture(_gesture(Gesture.Type.TAP))
	director.advance(_follow_up() - 0.1)
	assert_eq(director.current(), &"")
	director.advance(0.2)
	assert_eq(director.current(), HintDirector.HOLD)
	assert_eq(label.text(), "Hold to learn more.")
	director.note_gesture(_gesture(Gesture.Type.LONG_PRESS))
	assert_eq(director.current(), &"")
	assert_true(director.is_completed(HintDirector.HOLD))
	director.advance(60.0)
	assert_false(label.is_showing(), "all hints done: silence")
	assert_eq(String(Settings.get_value(HintDirector.SETTING)), "drag,hold")


func test_hints_come_one_at_a_time_in_order() -> void:
	director.note_gesture(_gesture(Gesture.Type.TAP)) # touched, but has not panned yet
	director.advance(_idle() + 0.1)
	assert_eq(director.current(), HintDirector.DRAG, "exploring comes first")
	director.note_gesture(_gesture(Gesture.Type.DRAG))
	director.advance(_follow_up() + 0.1)
	assert_eq(director.current(), HintDirector.HOLD)


func test_an_early_long_press_skips_the_hold_hint() -> void:
	director.note_gesture(_gesture(Gesture.Type.LONG_PRESS))
	director.note_gesture(_gesture(Gesture.Type.DRAG))
	director.advance(60.0)
	assert_eq(director.current(), &"")
	assert_true(director.is_completed(HintDirector.HOLD))
	# Completing twice does not store it twice.
	director.complete(HintDirector.HOLD)
	assert_eq(director.completed().size(), 2)


# --- panels, reset ----------------------------------------------------------------------------

func test_no_hints_while_a_panel_is_open() -> void:
	director.set_suppressed(true)
	director.advance(_idle() * 3.0)
	assert_eq(director.current(), &"")
	director.set_suppressed(false)
	director.advance(_idle() - 0.1)
	assert_eq(director.current(), &"", "the wait starts when the panel closes")
	director.advance(0.2)
	assert_eq(director.current(), HintDirector.DRAG)
	# Opening a panel hides a hint that is showing; it returns later.
	director.set_suppressed(true)
	assert_eq(director.current(), &"")
	assert_false(label.is_showing())
	assert_false(director.is_completed(HintDirector.DRAG), "hidden, not done")
	director.set_suppressed(false)
	director.advance(_idle() + 0.1)
	assert_eq(director.current(), HintDirector.DRAG)


func test_resetting_settings_brings_the_hints_back() -> void:
	director.note_gesture(_gesture(Gesture.Type.DRAG))
	Settings.reset_to_defaults()
	assert_false(director.is_completed(HintDirector.DRAG))
	director.advance(_idle() + 0.1)
	assert_eq(director.current(), HintDirector.DRAG)


func test_works_without_a_label() -> void:
	var bare := HintDirector.new()
	add_child(bare)
	bare.set_process(false)
	bare.advance(_idle() + 0.1)
	assert_eq(bare.current(), HintDirector.DRAG)
	bare.note_gesture(_gesture(Gesture.Type.DRAG))
	assert_eq(bare.current(), &"")
	bare.queue_free()


# --- the label -------------------------------------------------------------------------------

func test_label_never_takes_a_touch_and_sits_low_and_centred() -> void:
	assert_eq(label.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(label.is_in_group(InputRouter.UI_BLOCKER_GROUP), "the world under it stays touchable")
	assert_false(label.visible, "invisible until needed")
	label.show_text("Drag to explore.")
	var view := get_viewport().get_visible_rect().size
	var rect := label.get_global_rect()
	assert_near(rect.get_center().x, view.x * 0.5, 1.0)
	assert_true(rect.position.y > view.y * 0.5, "in the lower half")
	assert_true(rect.end.y <= view.y - HintLabel.BOTTOM_OFFSET + 1.0, "clear of the bottom row")
	label.hide_hint()
	assert_false(label.is_showing())
	await wait_real_ms(int(HintLabel.FADE_SECONDS * 1000.0) + 250)
	assert_false(label.visible, "gone after the fade")


func test_every_hint_has_text_in_the_quiet_style() -> void:
	for hint in HintDirector.ORDER:
		var text := UIText.hint(hint)
		assert_false(text.is_empty(), String(hint))
		assert_true(text.ends_with("."), "a calm full stop")
		assert_false(text.contains("!"), "never exclamation-heavy (bible §26.3)")
		assert_true(text.length() <= 24, "short")
	assert_eq(UIText.hint(&"unknown"), "")
