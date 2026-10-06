class_name HintDirector
extends Node
## Shows the first-time hints (bible §26.2–26.3, track T8): one quiet line at a
## time, only when it is relevant, and only until the player has done the thing
## once — after that it never comes back on this device.
##
##   ("Something lives inside." is no more: the owner, 2026-10-05.)
##   "Drag to explore."              after a few idle seconds, until the first pan
##   "Try touching someone."         once the player has panned and someone is in view,
##                                   until the first touch of a person
##   "Hold to learn more."           after the first touch of the world, until the first long press
##   "Follow them to see their day." while a person's card is open, until the first follow
##   "Something changed when you moved the world."  once, after the first tilt (motion on)
##   "Try tilting the box."          after ~3 minutes of play, until the first tilt (motion on)
##
## Not a line but a glow: the ☰ glows softly once at the first event (Main,
## MENU_GLOW). Nothing waits on the first discovery yet: there are none to
## make (mysteries come later).
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
const INSIDE := &"inside"
const MOVED := &"moved"
const TILT := &"tilt"
## Not hints, but done once and remembered with them: the first opening of
## the box (BoxIntro), and the ☰'s glow at the first event.
const INTRO := &"intro"
const MENU_GLOW := &"menu_glow"
## Hints in the order they are offered.
const ORDER: Array[StringName] = [DRAG, TOUCH, HOLD, FOLLOW, MOVED, TILT]
## "Try tilting the box." after this much play (seconds).
const TILT_AFTER_SECONDS := 180.0
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
## The first opening is on: no hints until it is over.
var _intro_running := false
## The first opening has ended this session: "Something lives inside." is due.
var _inside_due := false
## The world was moved (tilted) and that has not been remarked on yet.
var _moved := false
## Seconds of play (no panel open) this session.
var _played := 0.0
## Are motion controls on? (Their hints only then; tests set it.)
var motion_enabled: Callable = func() -> bool: return SensorManager.feature_enabled()


func _init(label: HintLabel = null) -> void:
	_label = label


func _process(delta: float) -> void:
	advance(delta)


# --- what the player does -----------------------------------------------------------------

## A finger landed on the world: the player is not idle (and has answered
## "Something lives inside.").
func note_touch() -> void:
	_idle = 0.0
	_moved = false
	if _inside_due:
		complete(INSIDE)


## The first opening has ended: its line is due.
func offer_inside() -> void:
	# ("Something lives inside." was taken out at the owner's word, 2026-10-05.)
	_inside_due = false
	_idle = 0.0


func set_intro_running(running: bool) -> void:
	_intro_running = running
	if running:
		_hide()


## The player moved the world (a tilt past the dead zone).
func note_tilt() -> void:
	if not bool(motion_enabled.call()):
		return
	_idle = 0.0
	if not is_completed(TILT):
		complete(TILT)
	if not is_completed(MOVED) and not _suppressed:
		_moved = true


## Hook for InputRouter.gesture_recognized.
func note_gesture(gesture: Gesture) -> void:
	_idle = 0.0
	_moved = false
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
	if _suppressed or _intro_running:
		return
	_idle += delta
	_played += delta
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
		if next == MOVED: # (said once: a remark, not something to do; it stays until they next touch)
			done_now(MOVED)


# --- state --------------------------------------------------------------------------------

## The hint on screen now (&"" if none).
func current() -> StringName:
	return _current


func is_completed(hint: StringName) -> bool:
	return completed().has(String(hint))


func completed() -> PackedStringArray:
	return String(Settings.get_value(SETTING)).split(",", false)


## Remembers a hint as done without taking it off the screen.
func done_now(hint: StringName) -> void:
	if is_completed(hint):
		return
	var done := completed()
	done.append(String(hint))
	Settings.set_value(SETTING, ",".join(done))


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
	var holding_first := false
	for hint in ORDER:
		if is_completed(hint):
			continue
		if hint == FOLLOW and holding_first:
			continue # (a card is opened by holding: that comes first)
		if _relevant(hint):
			return hint
		if hint == HOLD and not _person_card_open:
			holding_first = true # nothing to hold yet
	return &""


## Does a hint make sense as things are?
func _relevant(hint: StringName) -> bool:
	match hint:
		INSIDE:
			return _inside_due and not _person_card_open
		MOVED:
			return _moved and bool(motion_enabled.call())
		TILT:
			return _played >= TILT_AFTER_SECONDS and bool(motion_enabled.call()) and not _person_card_open
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
	match hint:
		INSIDE, MOVED:
			return 0.0
		DRAG:
			return Config.interaction.hint_idle_seconds
	return Config.interaction.hint_follow_up_seconds


func _hide() -> void:
	_current = &""
	_idle = 0.0
	if _label != null:
		_label.hide_hint()
