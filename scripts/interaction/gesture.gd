class_name Gesture
extends RefCounted
## One recognized gesture (bible §23.1). Positions are in viewport (canvas) units.

enum Type {
	TAP,
	DOUBLE_TAP,
	LONG_PRESS,
	DRAG_START,
	DRAG,
	DRAG_END,
	SWIPE,
	MULTI_START,
	PINCH,
	TWO_FINGER_DRAG,
	TWIST,
	MULTI_END,
	THREE_FINGER_TAP,
	## One finger has rested on the same spot for a moment (shorter than a
	## long press): the hand closes on what is under it.
	HOLD,
}

var type: Type
## Current position (single finger) or centroid (multi-finger).
var position := Vector2.ZERO
var start_position := Vector2.ZERO
## Movement since the previous event of this gesture.
var delta := Vector2.ZERO
## Release velocity in units/second (DRAG_END, SWIPE).
var velocity := Vector2.ZERO
## Incremental zoom factor since the previous PINCH (>1 = fingers spreading).
var scale := 1.0
## Incremental rotation in radians since the previous TWIST.
var angle := 0.0
var touch_count := 1
## Milliseconds the finger was held before the drag started (grab vs pan).
var hold_ms := 0
## Drag continues with the remaining finger after a multi-touch gesture.
var after_multi := false
## A LONG_PRESS already fired for this touch.
var long_pressed := false
## Ended by interruption (second finger, focus loss), not a normal release.
var cancelled := false
var time_ms := 0


func _init(gesture_type: Type = Type.TAP) -> void:
	type = gesture_type


func type_name() -> String:
	return Type.keys()[type]


func _to_string() -> String:
	return "%s @%s" % [type_name(), position.round()]
