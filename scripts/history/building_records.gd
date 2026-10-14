class_name BuildingRecords
extends RefCounted
## Building records (buildings & villagers F5, bible §17.2): what a building
## has been — when it went up and who built it, who worked there over the
## years, what it weathered, when it fell — and the name it comes to have.
## Kept for every building but the homes (there are many of those, and the
## dead's own records tell of them), saved with the world; a ruin keeps the
## record of what stood there.
##
## Names come of what it is and what happened: the first of its kind in the
## world is "the First Kiln", a bridge is called after whoever built most of
## it, and one that has stood OLD_YEARS is "the Old Workshop".

## A building this many years old is called old.
const OLD_YEARS := 50
## What is not recorded: the homes.
const UNRECORDED: Array[int] = [PropData.Kind.HUT]
## What it weathered (kept: the most recent this many).
const MOST_EVENTS := 12

## A building has come to be called by a name it did not have when built (F6).
signal named(building_id: int, name: String, tile: Vector2i)

var buildings: BuildingLibrary
var people: PersonRegistry
var archive: HistoryArchive
var _records: Dictionary = {} # building (or ruin) prop id -> record (Dictionary)
var _firsts: Dictionary = {} # def id -> true: the first of it has gone up


func clear() -> void:
	_records.clear()
	_firsts.clear()


## A building is finished (ConstructionSystem.finished).
func on_built(project: Dictionary, building_id: int, kind: int, now: int) -> void:
	if UNRECORDED.has(kind) or _records.has(building_id):
		return
	var def := StringName(str(project.get("def", "")))
	var builders: Array[int] = ConstructionSystem.builders_of(project)
	var first := not _firsts.has(def)
	_firsts[def] = true
	_records[building_id] = {"def": String(def), "tile": project.get("tile", Vector2i.ZERO),
		"settlement": int(project.get("settlement", 0)), "built": now, "builders": builders,
		"first": first, "workers": {}, "events": [], "ruined": -1}


## Something happened to it: "flood", "storm", "blizzard" (damaged), "repaired".
func on_event(building_id: int, what: StringName, now: int) -> void:
	var record: Dictionary = _records.get(building_id, {})
	if record.is_empty():
		return
	var events: Array = record["events"]
	events.append([now, String(what)])
	while events.size() > MOST_EVENTS:
		events.pop_front()


## It was built anew as another (an upgrade, F4): the same record, the new kind.
func on_upgraded(building_id: int, def: StringName, now: int) -> void:
	var record: Dictionary = _records.get(building_id, {})
	if record.is_empty():
		return
	on_event(building_id, &"rebuilt", now)
	record["def"] = String(def)


## It fell (ConstructionSystem.ruined): the ruin left at its tile keeps its record
## (a bridge leaves none: its own id).
func on_ruined(ruin_id: int, tile: Vector2i, now: int) -> void:
	if _records.has(ruin_id):
		(_records[ruin_id] as Dictionary)["ruined"] = now
		return
	for id: int in _records.keys():
		var record: Dictionary = _records[id]
		if int(record["ruined"]) < 0 and record["tile"] == tile:
			record["ruined"] = now
			if ruin_id != id:
				_records.erase(id)
				_records[ruin_id] = record
			return


var _day := -1_000_000


## Once a game day (see each_day).
func advance_to(now: int, settlements: Settlements) -> void:
	var today := Config.time.day_index(now)
	if today == _day:
		return
	var first := _day == -1_000_000
	_day = today
	if not first:
		each_day(settlements)
		_names_now(now)


## A day: those of its workers' trades in its settlement worked there.
func each_day(settlements: Settlements) -> void:
	if buildings == null or settlements == null:
		return
	for id: int in _records:
		var record: Dictionary = _records[id]
		if int(record["ruined"]) >= 0:
			continue
		var def := buildings.get_def(StringName(str(record["def"])))
		var own := settlements.get_settlement(int(record["settlement"]))
		if def == null or def.workers.is_empty() or own == null:
			continue
		var workers: Dictionary = record["workers"]
		for person in own.members():
			if def.workers.has(String(person.occupation_id)):
				workers[str(person.id)] = int(workers.get(str(person.id), 0)) + 1


## Those that have come to a name since they were built: told once.
func _names_now(now: int) -> void:
	for id: int in _records:
		var record: Dictionary = _records[id]
		if int(record["ruined"]) >= 0 or bool(record.get("named", false)) or bool(record["first"]):
			continue
		var name := name_of(id, now)
		if name != "" and str(record["def"]) != "bridge":
			record["named"] = true
			named.emit(id, name, record["tile"])


func has_record(id: int) -> bool:
	return _records.has(id)


func record_of(id: int) -> Dictionary:
	return _records.get(id, {})


func size() -> int:
	return _records.size()


## What it is called (now): "the First Kiln", "Asha's Bridge", "the Old
## Workshop" — or "" (just a kiln).
func name_of(id: int, now: int) -> String:
	var record := record_of(id)
	if record.is_empty():
		return ""
	var what := UIText.building_name(StringName(str(record["def"])))
	if str(record["def"]) == "bridge":
		var builder := _most_of(record)
		if builder != "":
			return "%s's %s" % [builder, what]
	if bool(record["first"]):
		return "the First %s" % what
	if _years(now - int(record["built"])) >= OLD_YEARS:
		return "the Old %s" % what
	return ""


## What its card tells of it: [label, text] pairs.
func lines_of(id: int, now: int) -> Array:
	var record := record_of(id)
	var out: Array = []
	if record.is_empty():
		return out
	var name := name_of(id, now)
	if name != "":
		out.append(["Called", name.left(1).to_upper() + name.substr(1)])
	var years := _years(now - int(record["built"]))
	var when := "this year" if years == 0 else ("a year ago" if years == 1 else "%d years ago" % years)
	var names := _names(record["builders"], 2)
	out.append(["Built", when + (" by %s" % names if names != "" else "")])
	var workers: Dictionary = record["workers"]
	if not workers.is_empty():
		var family := _biggest_family(workers)
		var text := "one person" if workers.size() == 1 else "%d people over the years" % workers.size()
		if family[1] >= 3:
			text += " — %d of the %s family" % [family[1], family[0]]
		out.append(["Worked by", text])
	var weathered := {}
	var repairs := 0
	for event: Array in record["events"]:
		if str(event[1]) == "repaired":
			repairs += 1
		else:
			weathered[str(event[1])] = int(weathered.get(str(event[1]), 0)) + 1
	if not weathered.is_empty():
		var parts := PackedStringArray()
		for what: String in weathered:
			var count := int(weathered[what])
			parts.append("%s %s" % ["a" if count == 1 else str(count), what if count == 1 else what + "s"])
		out.append(["Weathered", ", ".join(parts)])
	if repairs > 0:
		out.append(["Mended", "once" if repairs == 1 else "%d times" % repairs])
	if int(record["ruined"]) >= 0:
		var fell := _years(now - int(record["ruined"]))
		out.append(["Fell", "this year" if fell == 0 else ("a year ago" if fell == 1 else "%d years ago" % fell)])
	return out


func _years(ticks: int) -> int:
	return maxi(ticks, 0) / maxi(Config.time.ticks_per_year(), 1)


## Given names of `ids` (living, or in the archive of the dead), at most `most`.
func _names(ids: Array, most: int) -> String:
	var names := PackedStringArray()
	for id: Variant in ids:
		var name := _given_name(int(id))
		if name != "":
			names.append(name)
		if names.size() >= most:
			break
	if names.size() < ids.size() and names.size() >= most:
		return "%s and others" % ", ".join(names)
	return " and ".join(names)


func _given_name(id: int) -> String:
	var person := people.get_person(id) if people != null else null
	if person != null:
		return person.given_name
	var dead := archive.get_record(id) if archive != null else null
	return dead.given_name if dead != null else ""


func _family_name(id: int) -> String:
	var person := people.get_person(id) if people != null else null
	if person != null:
		return person.family_name
	var dead := archive.get_record(id) if archive != null else null
	return dead.family_name if dead != null else ""


## Whoever built most of it (by name).
func _most_of(record: Dictionary) -> String:
	var builders: Array = record["builders"]
	return _given_name(int(builders[0])) if not builders.is_empty() else ""


## [family name, how many of it] among its workers — the biggest.
func _biggest_family(workers: Dictionary) -> Array:
	var by := {}
	for key: String in workers:
		var family := _family_name(int(key))
		if family != "":
			by[family] = int(by.get(family, 0)) + 1
	var best := ["", 0]
	var names := by.keys()
	names.sort()
	for family: String in names:
		if int(by[family]) > int(best[1]):
			best = [family, int(by[family])]
	return best


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for id: int in _records:
		out[str(id)] = (_records[id] as Dictionary).duplicate(true)
	return {"records": out, "firsts": _firsts.keys().map(func(k: StringName) -> String: return String(k))}


## Returns how many saved records were unusable (and dropped).
func from_dict(data: Dictionary) -> int:
	clear()
	var bad := 0
	var saved: Variant = data.get("records", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for key: Variant in saved:
			var record: Variant = saved[key]
			if typeof(record) != TYPE_DICTIONARY or not str(key).is_valid_int() or not (record as Dictionary).has("def"):
				bad += 1
				continue
			var r: Dictionary = record
			for field: String in ["workers", "events", "builders"]:
				if not r.has(field):
					r[field] = {} if field == "workers" else []
			r["ruined"] = int(r.get("ruined", -1))
			r["first"] = bool(r.get("first", false))
			r["settlement"] = int(r.get("settlement", 0))
			r["built"] = int(r.get("built", 0))
			_records[int(str(key))] = r
	for def: Variant in data.get("firsts", []):
		_firsts[StringName(str(def))] = true
	return bad
