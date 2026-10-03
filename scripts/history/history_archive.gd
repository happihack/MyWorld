class_name HistoryArchive
extends RefCounted
## Everyone who has died (bible §16.3): the dead leave the live registry and
## are kept here as HistoricalPerson records, so that whatever names them —
## an event, a memory, a family tree — still knows who they were. Lineage
## outlives people.

var _records: Dictionary = {} # id -> HistoricalPerson
var _graves: Dictionary = {} # grave (prop) id -> person id


func clear() -> void:
	_records.clear()
	_graves.clear()


func add(record: HistoricalPerson) -> void:
	if record != null and record.id > 0:
		_records[record.id] = record
		if record.grave_id > 0:
			_graves[record.grave_id] = record.id


## Whoever lies in this grave (null: nobody known).
func buried_in(grave_id: int) -> HistoricalPerson:
	return _records.get(int(_graves.get(grave_id, 0)))


## Their grave is (now) this prop at this tile.
func set_grave(person_id: int, grave_id: int, tile: Vector2i) -> void:
	var record: HistoricalPerson = _records.get(person_id)
	if record == null:
		return
	_graves.erase(record.grave_id)
	record.grave_id = grave_id
	record.grave_tile = tile
	if grave_id > 0:
		_graves[grave_id] = person_id


func get_record(id: int) -> HistoricalPerson:
	return _records.get(id)


func has_record(id: int) -> bool:
	return _records.has(id)


func size() -> int:
	return _records.size()


## Everyone in the archive, in order of id.
func all_records() -> Array[HistoricalPerson]:
	var ids: Array = _records.keys()
	ids.sort()
	var out: Array[HistoricalPerson] = []
	for id: int in ids:
		out.append(_records[id])
	return out


## A record of someone who died: a child of theirs is born after (a father who
## died before the birth) — the link is kept on both sides.
func add_child(parent_id: int, child_id: int) -> void:
	var record: HistoricalPerson = _records.get(parent_id)
	if record != null and not record.children.has(child_id):
		record.children.append(child_id)


func to_dict() -> Dictionary:
	var out: Array = []
	for record in all_records():
		out.append(record.to_dict())
	return {"people": out}


## Returns how many saved records were unusable.
func from_dict(data: Dictionary) -> int:
	clear()
	var saved: Variant = data.get("people")
	if typeof(saved) != TYPE_ARRAY:
		return 0
	var skipped := 0
	for entry: Variant in saved:
		var record := HistoricalPerson.from_dict(entry) if typeof(entry) == TYPE_DICTIONARY else null
		if record == null or _records.has(record.id):
			skipped += 1
			continue
		add(record)
	return skipped
