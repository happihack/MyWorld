class_name PlayerHistory
extends RefCounted
## What the player has done to this world (bible §14.6, §27.3). Saved with the
## world. Two things are kept:
##
##  - **Counts** of everything, by kind and by what it was done to — the raw
##    material for the player's statistics ("for reflection, not score").
##  - **A log of the acts worth remembering**: the first of each kind (the
##    first tree shaken, the first boulder moved) and everything Moderate or
##    Major. Thousands of ordinary touches are counted, not logged.
##
## The log is append-only and bounded: when it is full, the oldest entry that
## is not a "first" makes room.

const MAX_ENTRIES := 400

## Achievements the history can unlock so far (bible §27.4; they are shown
## from M25 on — until then they are only kept).
const FIRST_CONTACT := &"first_contact"
## Stayed with one person for a whole day (see ObserverWatch).
const OBSERVER := &"observer"

var _next_id := 1
var _counts: Dictionary = {} # type -> int
var _keys: Dictionary = {} # "type:subject" -> int
var _totals: Dictionary = {} # stat name -> float (sums: distance, water, ...)
var _entries: Array[Dictionary] = []
var _people: Dictionary = {} # person id -> how often they were touched
var _achievements: Dictionary = {} # id (String) -> {"tick": int, "intervention": int}
## Achievements unlocked and not yet announced (see take_unlocked()).
var _unlocked: Array[StringName] = []


## The number the next recorded intervention gets.
func peek_next_id() -> int:
	return _next_id


## Writes an applied intervention into the history and gives it its number.
## Returns true if it also went into the log.
func record(iv: Intervention) -> bool:
	if iv == null or not iv.applied or not iv.recorded:
		return false
	iv.id = _next_id
	_next_id += 1
	var type := String(iv.type)
	var key := iv.key()
	var first := not _keys.has(key)
	_counts[type] = int(_counts.get(type, 0)) + 1
	_keys[key] = int(_keys.get(key, 0)) + 1
	match iv.type:
		Intervention.MOVE_OBJECT:
			_add(&"distance_moved", iv.magnitude)
			if bool(iv.params.get("thrown", false)):
				_add(&"objects_thrown", 1.0)
		Intervention.SCOOP_WATER, Intervention.POUR_WATER:
			_add(&"water_moved", iv.magnitude)
		Intervention.MAKE_RAIN:
			_add(&"rain_made", iv.magnitude)
		Intervention.CARVE:
			_add(&"tiles_carved", iv.magnitude)
		Intervention.TOUCH:
			if iv.response != null and not iv.response.dropped.is_empty():
				_add(&"fruit_shaken", iv.response.dropped.size())
			if iv.subject == &"person" and iv.target_id != 0:
				_people[iv.target_id] = int(_people.get(iv.target_id, 0)) + 1
				unlock(FIRST_CONTACT, iv.tick, iv.id)
	if not first and iv.severity == Intervention.Severity.GENTLE:
		return false
	var entry := iv.to_record()
	entry["first"] = first
	_entries.append(entry)
	if _entries.size() > MAX_ENTRIES:
		_drop_oldest_ordinary()
	return true


# --- reading ----------------------------------------------------------------------------

## Everything the player has done, counted.
func total() -> int:
	var sum := 0
	for n: int in _counts.values():
		sum += n
	return sum


## How often a kind of intervention happened (to `subject`, if given).
func count(type: StringName, subject: StringName = &"") -> int:
	if subject == &"":
		return int(_counts.get(String(type), 0))
	return int(_keys.get("%s:%s" % [type, subject], 0))


func total_of(stat: StringName) -> float:
	return float(_totals.get(String(stat), 0.0))


## How many different people the player has touched (they count for ever,
## whatever becomes of them).
func people_touched() -> int:
	return _people.size()


## How often this person was touched.
func touches_of(person_id: int) -> int:
	return int(_people.get(person_id, 0))


# --- achievements -------------------------------------------------------------------------------

## Unlocks an achievement (once). Returns true if it was not unlocked before.
func unlock(id: StringName, tick: int, intervention_id: int = 0) -> bool:
	if _achievements.has(String(id)):
		return false
	_achievements[String(id)] = {"tick": tick, "intervention": intervention_id}
	_unlocked.append(id)
	return true


func has_achievement(id: StringName) -> bool:
	return _achievements.has(String(id))


## Everything unlocked: id (String) -> {"tick", "intervention"}.
func achievements() -> Dictionary:
	return _achievements.duplicate(true)


## The achievements unlocked since this was last asked (for whoever announces them).
func take_unlocked() -> Array[StringName]:
	var out := _unlocked.duplicate()
	_unlocked.clear()
	return out


## The log, oldest first. Each entry: id, type, subject, tool, tick, tile,
## target_id, magnitude, severity, first.
func entries() -> Array[Dictionary]:
	return _entries


func entry_count() -> int:
	return _entries.size()


## The player's statistics (bible §27.3) as far as the world can produce them yet.
func stats() -> Dictionary:
	return {
		"total_interactions": total(),
		"touches": count(Intervention.TOUCH),
		"people_touched": people_touched(),
		"objects_moved": count(Intervention.MOVE_OBJECT),
		"objects_thrown": int(total_of(&"objects_thrown")),
		"distance_moved": total_of(&"distance_moved"),
		"trees_uprooted": count(Intervention.UPROOT),
		"fruit_shaken": int(total_of(&"fruit_shaken")),
		"water_moved": total_of(&"water_moved"),
		# Trees felled, fruit brought down, piles carried off: the world's resources, handled.
		"resources_manipulated": count(Intervention.UPROOT) + int(total_of(&"fruit_shaken"))
			+ count(Intervention.MOVE_OBJECT, &"pile"),
		"rain_made": count(Intervention.MAKE_RAIN),
		"gusts": count(Intervention.MAKE_WIND),
		"ground_carved": count(Intervention.CARVE),
	}


# --- saving -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"next_id": _next_id,
		"counts": _counts.duplicate(),
		"keys": _keys.duplicate(),
		"totals": _totals.duplicate(),
		"entries": _entries.duplicate(true),
		"people": _people.duplicate(),
		"achievements": _achievements.duplicate(true),
	}


## Restores a saved history. Unusable parts are left empty; returns false if
## nothing could be used.
func from_dict(data: Dictionary) -> bool:
	_next_id = 1
	_counts = {}
	_keys = {}
	_totals = {}
	_entries = []
	_people = {}
	_achievements = {}
	_unlocked = []
	if data.is_empty():
		return false
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	_counts = _numbers(data.get("counts"), true)
	_keys = _numbers(data.get("keys"), true)
	_totals = _numbers(data.get("totals"), false)
	var saved: Variant = data.get("entries", [])
	if typeof(saved) == TYPE_ARRAY:
		for entry: Variant in saved:
			if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("type") and (entry as Dictionary).has("id"):
				_entries.append((entry as Dictionary).duplicate())
				_next_id = maxi(_next_id, int(entry["id"]) + 1)
	if _entries.size() > MAX_ENTRIES:
		_entries = _entries.slice(_entries.size() - MAX_ENTRIES)
	var people: Variant = data.get("people")
	if typeof(people) == TYPE_DICTIONARY:
		for id: Variant in people:
			if typeof(id) == TYPE_INT and typeof((people as Dictionary)[id]) == TYPE_INT and int(people[id]) > 0:
				_people[id] = int(people[id])
	var unlocked: Variant = data.get("achievements")
	if typeof(unlocked) == TYPE_DICTIONARY:
		for id: Variant in unlocked:
			var record: Variant = (unlocked as Dictionary)[id]
			if typeof(record) == TYPE_DICTIONARY:
				_achievements[str(id)] = {"tick": int((record as Dictionary).get("tick", 0)),
					"intervention": int((record as Dictionary).get("intervention", 0))}
	return true


# --- internals --------------------------------------------------------------------------

func _add(stat: StringName, amount: float) -> void:
	_totals[String(stat)] = float(_totals.get(String(stat), 0.0)) + amount


func _drop_oldest_ordinary() -> void:
	for i in _entries.size():
		if not bool(_entries[i].get("first", false)):
			_entries.remove_at(i)
			return
	_entries.remove_at(0) # only firsts left (cannot happen with a sane limit)


## A dictionary of String -> number from saved data; anything else is dropped.
static func _numbers(value: Variant, whole: bool) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	for key: Variant in value:
		var v: Variant = (value as Dictionary)[key]
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			out[str(key)] = int(v) if whole else float(v)
	return out
