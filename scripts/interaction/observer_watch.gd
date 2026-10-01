class_name ObserverWatch
extends RefCounted
## Keeps count of how long the player has stayed with one person (bible
## §27.4, the OBSERVER achievement): followed for a whole game day, with the
## camera on them for at least nine tenths of it.
##
## It looks at the last WINDOW game minutes: the person must have been the
## one followed for all of that time, and the view may have been elsewhere
## (following paused, or stopped and taken up again) for no more than a tenth
## of it. Following someone else starts over. Saved with the world.

## Game minutes: a day.
const WINDOW := 1440
const SHARE := 0.9

## Who is being watched (0 = nobody), and since when.
var person_id := 0
var since_tick := 0
var _gaps: Array = [] # [from tick, to tick]: the view was elsewhere
var _gap_from := -1 # an open gap (the view is elsewhere now), or -1


## Call as time passes: `followed_id` is the person the camera is with now
## (0 = with nobody). Returns true once the day is complete.
func update(now: int, followed_id: int) -> bool:
	if followed_id > 0 and followed_id != person_id:
		_start(followed_id, now)
	if person_id == 0:
		return false
	if now < since_tick:
		# (The clock was set back: a test, or a save from before.)
		_start(person_id if followed_id > 0 else 0, now)
		return false
	if followed_id == 0:
		if _gap_from < 0:
			_gap_from = now
		elif now - _gap_from >= WINDOW:
			# A whole day elsewhere: they are not being watched any more.
			_start(0, now)
			return false
	elif _gap_from >= 0:
		if now > _gap_from:
			_gaps.append([_gap_from, now])
		_gap_from = -1
	while not _gaps.is_empty() and int((_gaps[0] as Array)[1]) <= now - WINDOW:
		_gaps.pop_front()
	return watched(now) >= WINDOW and away(now) <= allowed_away()


## How long the person has been the one followed, in game minutes.
func watched(now: int) -> int:
	return maxi(now - since_tick, 0) if person_id != 0 else 0


## How much of the last WINDOW minutes the view was elsewhere.
func away(now: int) -> int:
	var from := maxi(now - WINDOW, since_tick)
	var total := 0
	for gap: Array in _gaps:
		total += maxi(mini(int(gap[1]), now) - maxi(int(gap[0]), from), 0)
	if _gap_from >= 0:
		total += maxi(now - maxi(_gap_from, from), 0)
	return total


static func allowed_away() -> int:
	return roundi(WINDOW * (1.0 - SHARE))


## How far along it is, 0 … 1 (for whoever wants to show it).
func progress(now: int) -> float:
	if person_id == 0:
		return 0.0
	if away(now) > allowed_away():
		# Too long elsewhere: it can only be complete once that has left the window.
		return clampf(float(watched(now)) / float(WINDOW), 0.0, 0.99) * 0.9
	return clampf(float(watched(now)) / float(WINDOW), 0.0, 1.0)


func reset() -> void:
	_start(0, 0)


func to_dict() -> Dictionary:
	if person_id == 0:
		return {}
	return {"person": person_id, "since": since_tick, "gaps": _gaps.duplicate(true), "gap_from": _gap_from}


func from_dict(data: Dictionary) -> void:
	reset()
	if typeof(data.get("person")) != TYPE_INT or int(data["person"]) <= 0 or typeof(data.get("since")) != TYPE_INT:
		return
	person_id = int(data["person"])
	since_tick = int(data["since"])
	_gap_from = int(data["gap_from"]) if typeof(data.get("gap_from")) == TYPE_INT else -1
	var gaps: Variant = data.get("gaps")
	if typeof(gaps) == TYPE_ARRAY:
		for gap: Variant in gaps:
			if typeof(gap) == TYPE_ARRAY and (gap as Array).size() == 2 and typeof(gap[0]) == TYPE_INT \
					and typeof(gap[1]) == TYPE_INT and int(gap[1]) > int(gap[0]):
				_gaps.append([int(gap[0]), int(gap[1])])


func _start(id: int, now: int) -> void:
	person_id = id
	since_tick = now
	_gaps = []
	_gap_from = -1
