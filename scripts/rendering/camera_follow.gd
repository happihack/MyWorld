class_name CameraFollow
extends RefCounted
## Following a person with the camera (bible §26.6 "Follow"): who is
## followed, and whether the camera is with them right now. Moving the view by
## hand does not end it — it pauses, and can be taken up again.
##
## This is only the state; whoever owns the camera (Main) moves it.

enum State { OFF, FOLLOWING, PAUSED }

## The state or the person changed.
signal changed

## The followed person is kept no higher on the screen than this fraction of
## its height, and no lower than the middle (below it the card takes over).
const HIGHEST := 0.28
const LOWEST := 0.5

var person_id := 0
var state: State = State.OFF


## Starts following a person (whoever was followed before is let go).
func start(id: int) -> void:
	if id <= 0:
		stop()
		return
	if person_id == id and state == State.FOLLOWING:
		return
	person_id = id
	state = State.FOLLOWING
	changed.emit()


## The view was taken elsewhere: the person is still the one followed, but
## the camera stays where it is put.
func pause() -> void:
	if state == State.FOLLOWING:
		state = State.PAUSED
		changed.emit()


func resume() -> void:
	if state == State.PAUSED:
		state = State.FOLLOWING
		changed.emit()


func stop() -> void:
	if state == State.OFF:
		return
	person_id = 0
	state = State.OFF
	changed.emit()


## The camera is with the person now.
func is_following() -> bool:
	return state == State.FOLLOWING


## Someone is followed (with the camera on them or not).
func is_active() -> bool:
	return state != State.OFF


## Where on the screen the followed person is kept: in the middle of what is
## free between `free_top` and `free_bottom` (the banner above, the card or
## the tools below), within the limits above.
static func anchor(view: Vector2, free_top: float, free_bottom: float) -> Vector2:
	var y := clampf((free_top + free_bottom) * 0.5, view.y * HIGHEST, view.y * LOWEST)
	return Vector2(view.x * 0.5, y)
