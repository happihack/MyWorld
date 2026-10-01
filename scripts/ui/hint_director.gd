class_name HintDirector
extends Node
## Shows the first-time hints (bible §26.2–26.3, track T8): one quiet line at a
## time, only when it is relevant, and only until the player has done the thing
## once — after that it never comes back on this device.
##
##   "Drag to explore."              after a few idle seconds, until the first pan
##   "Try touching someone."         once the player has panned and someone is in view,
##                                   until the first touch of a person
##   "Hold to learn more."           after the first touch of the world, until the first long press
##   "Follow them to see their day." while a person's card is open, until the first follow
##
## One at a time, in that order — but a hint that makes no sense right now
## (nobody in view to touch) does not hold up the next. A player who does
## the thing before its hint appears never sees the hint.
## What has been done is remembered in Settings ("ftue/completed"), so it
## survives new worlds and reinstalls of a world, but not of the app.

const DRAG := &"drag"
const TOUCH := &"touch_person"
const HOLD := &"hold"
const FOLLOW := &"follow"
## Hints in the order they are offered.
const ORDER: Array[StringName] = [DRAG, TOUCH, HOLD, FOLLOW]
const SETTING := &"ftue/completed"

var _label: HintLabel
var _idle := 0.0
var _suppressed := false
## The world was touched (tapped) during this session.
var _touched_world := false
## Someone can be seen (as a figure, not a far-off dot).
var _person_in_view := false
## A person's card is open (and nothing else is).
var _person_card_open := false
var _current: StringName = &""


func _init(label: HintLabel = null) -> void:
	_label = label


func _process(delta: float) -> void:
	advance(delta)


# --- what the player does -----------------------------------------------------------------

## A finger landed on the world: the player is not idle.
func note_touch() -> void:
	_idle = 0.0


## Hook for InputRouter.gesture_recognized.
func note_gesture(gesture: Gesture) -> void:
	_idle = 0.0
	match gesture.type:
		Gesture.Type.DRAG, Gesture.Type.TWO_FINGER_DRAG:
			complete(DRAG)
		Gesture.Type.TAP:
			_touched_world = true
		Gesture.Type.LONG_PRESS:
			_touched_world = true
			complete(HOLD)


## Tells the director whether anyone is on screen to be touched.
func set_person_in_view(in_view: bool) -> void:
	_person_in_view = in_view


## Tells the director that a person's card is open: the only hint that makes
## sense then is the one about what the card offers.
func set_person_card_open(open: bool) -> void:
	if _person_card_open == open:
		return
	_person_card_open = open
	_idle = 0.0


## While suppressed (a panel is open) no hint shows and idle time does not count.
func set_suppressed(suppressed: bool) -> void:
	if _suppressed == suppressed:
		return
	_suppressed = suppressed
	_idle = 0.0
	if suppressed:
		_hide()


## Advances idle time. Called every frame; tests call it directly.
func advance(delta: float) -> void:
	if _suppressed:
		return
	_idle += delta
	if _current != &"":
		# Shown, and no longer to the point (the person walked off, a card opened)?
		if not _relevant(_current):
			_hide()
		return
	var next := _next_hint()
	if next != &"" and _idle >= _delay_for(next):
		_current = next
		if _label != null:
			_label.show_text(UIText.hint(next))
		Log.debug(Log.Category.UI, "Hint shown", {"hint": next})


# --- state --------------------------------------------------------------------------------

## The hint on screen now (&"" if none).
func current() -> StringName:
	return _current


func is_completed(hint: StringName) -> bool:
	return completed().has(String(hint))


func completed() -> PackedStringArray:
	return String(Settings.get_value(SETTING)).split(",", false)


## Marks a hint's action as done: the hint goes away and never returns.
func complete(hint: StringName) -> void:
	if _current == hint:
		_hide()
	if is_completed(hint):
		return
	var done := completed()
	done.append(String(hint))
	Settings.set_value(SETTING, ",".join(done))


# --- internals ----------------------------------------------------------------------------

## The first hint that is still needed and makes sense right now.
func _next_hint() -> StringName:
	for hint in ORDER:
		if is_completed(hint):
			continue
		if _relevant(hint):
			return hint
		if hint == HOLD and not _person_card_open:
			return &"" # nothing to hold yet, and nothing later makes sense before it
	return &""


## Does a hint make sense as things are?
func _relevant(hint: StringName) -> bool:
	match hint:
		DRAG:
			return not _person_card_open
		TOUCH:
			# After the first pan (the view is theirs), with someone to touch.
			return is_completed(DRAG) and _person_in_view and not _person_card_open
		HOLD:
			return _touched_world and not _person_card_open
		FOLLOW:
			return _person_card_open
	return false


func _delay_for(hint: StringName) -> float:
	return Config.interaction.hint_idle_seconds if hint == DRAG else Config.interaction.hint_follow_up_seconds


func _hide() -> void:
	_current = &""
	_idle = 0.0
	if _label != null:
		_label.hide_hint()
