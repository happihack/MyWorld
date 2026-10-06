class_name DayLog
extends RefCounted
## What everyone has been doing, lately: for each person a short list of what
## they turned to and when ("06:30 wakes · 07:00 has breakfast · 08:00 chops
## wood"). The card shows today's (see DayLogText). Saved with the world.
##
## An entry is [tick: int, kind: String, detail: String, other: int]:
##   kind    an activity id ("eat", "work", "sleep", "socialize", ...), or
##           WAKE, STIR, or REACT (something they noticed and did about it);
##   detail  what kind of it ("meal", "nap", the kind of work; for REACT
##           "<reaction>:<stimulus>");
##   other   who it was with (0 = nobody in particular).
##
## The list is a ring: the oldest entries make room, and nothing older than
## KEEP_MINUTES is kept.

const MAX_ENTRIES := 40 # (evenings by the fire fill a day more: 2026-10-06)
const KEEP_MINUTES := 2880
## What is given up again within this many minutes never really happened:
## its entry makes way for what came instead.
const BRIEF_MINUTES := 3

const WAKE := "wake"
const STIR := "stir"
const REACT := "react"
## What life brings (born, partners, a death in the family: M10.2): it
## happens beside whatever they were doing, and takes nothing's place.
const LIFE := "life"
## Entries that stand, however brief.
const MOMENTS: Array[String] = [WAKE, STIR, REACT, LIFE]
## Things done with someone, where going from one person to the next is
## still the same thing: the entry names the first and says there were more.
const ROUNDS: Array[String] = ["socialize"]
const MORE := "more"
## Waking again within this many minutes of waking is the same waking
## (someone who turned over once more).
const WAKING_MINUTES := 60

const TICK := 0
const KIND := 1
const DETAIL := 2
const OTHER := 3

var _logs: Dictionary = {} # person id -> Array of entries, oldest first


## Writes down what a person turns to. Returns true if it made an entry (not
## if it is what they were at already).
func note(person_id: int, tick: int, kind: String, detail: String = "", other: int = 0) -> bool:
	if person_id <= 0 or kind == "":
		return false
	if not _logs.has(person_id):
		_logs[person_id] = []
	var log: Array = _logs[person_id]
	# What they had only just turned to did not come to anything.
	if not log.is_empty():
		var last: Array = log[-1]
		# (A moment between two people — a word, a lesson — does not undo it.)
		if tick - int(last[TICK]) < BRIEF_MINUTES and not MOMENTS.has(str(last[KIND])) and kind != LIFE and kind != "social" and not _same(last, kind, detail, other):
			log.pop_back()
	if kind == WAKE and not log.is_empty() and str((log[-1] as Array)[KIND]) == WAKE 			and tick - int((log[-1] as Array)[TICK]) < WAKING_MINUTES:
		return false
	# Going on with the same thing is not news.
	if not log.is_empty() and not MOMENTS.has(kind) and _same(log[-1], kind, detail, other):
		return false
	# From one person to the next: the same talk, with more people in it.
	if not log.is_empty() and ROUNDS.has(kind) and str((log[-1] as Array)[KIND]) == kind:
		if int((log[-1] as Array)[OTHER]) != other:
			(log[-1] as Array)[DETAIL] = MORE
		return false
	log.append([tick, kind, detail, other])
	while log.size() > MAX_ENTRIES or (log.size() > 1 and tick - int((log[0] as Array)[TICK]) > KEEP_MINUTES):
		log.pop_front()
	return true


## Everything kept about a person, oldest first.
func of(person_id: int) -> Array:
	return _logs.get(person_id, [])


## The entries of one game day (TimeConfig.day_index).
func of_day(person_id: int, day: int, config: TimeConfig) -> Array:
	var out: Array = []
	for entry: Array in of(person_id):
		if config.day_index(int(entry[TICK])) == day:
			out.append(entry)
	return out


## What there is to show now: today's entries — or, while today has none
## yet (the small hours), the day before's. [day index, entries].
func latest_day(person_id: int, now_tick: int, config: TimeConfig) -> Array:
	var today := config.day_index(now_tick)
	var entries := of_day(person_id, today, config)
	if not entries.is_empty():
		return [today, entries]
	var log := of(person_id)
	if log.is_empty():
		return [today, []]
	var day := config.day_index(int((log[-1] as Array)[TICK]))
	return [day, of_day(person_id, day, config)]


func forget(person_id: int) -> void:
	_logs.erase(person_id)


func clear() -> void:
	_logs.clear()


func people_count() -> int:
	return _logs.size()


func entry_count() -> int:
	var total := 0
	for log: Array in _logs.values():
		total += log.size()
	return total


# --- saving -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for id: int in _logs:
		if not (_logs[id] as Array).is_empty():
			out[id] = (_logs[id] as Array).duplicate(true)
	return {"logs": out}


## Restores saved logs; whatever is unusable is left out. Returns how many
## entries were dropped.
func from_dict(data: Dictionary) -> int:
	_logs = {}
	var dropped := 0
	var saved: Variant = data.get("logs")
	if typeof(saved) != TYPE_DICTIONARY:
		return 0
	for id: Variant in saved:
		var entries: Variant = (saved as Dictionary)[id]
		if typeof(id) != TYPE_INT or int(id) <= 0 or typeof(entries) != TYPE_ARRAY:
			dropped += (entries as Array).size() if typeof(entries) == TYPE_ARRAY else 1
			continue
		var log: Array = []
		var before := -1000000000000
		for entry: Variant in entries:
			if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 4 or typeof(entry[TICK]) != TYPE_INT \
					or typeof(entry[KIND]) != TYPE_STRING or str(entry[KIND]) == "" or typeof(entry[DETAIL]) != TYPE_STRING \
					or typeof(entry[OTHER]) != TYPE_INT or int(entry[TICK]) < before:
				dropped += 1
				continue
			before = int(entry[TICK])
			log.append([int(entry[TICK]), str(entry[KIND]), str(entry[DETAIL]), int(entry[OTHER])])
		if log.size() > MAX_ENTRIES:
			log = log.slice(log.size() - MAX_ENTRIES)
		if not log.is_empty():
			_logs[int(id)] = log
	return dropped


static func _same(entry: Array, kind: String, detail: String, other: int) -> bool:
	return str(entry[KIND]) == kind and str(entry[DETAIL]) == detail and int(entry[OTHER]) == other
