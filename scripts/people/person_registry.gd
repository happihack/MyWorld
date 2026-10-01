class_name PersonRegistry
extends RefCounted
## Everyone in the world (bible §13.1), kept in step with the spatial index so
## people can be found by where they are.
##
## Unlike props, people are never regenerated: every person is saved in full.
## The lookups by settlement, household and tier walk the whole registry — fine
## for a band; they get their own indices when there are thousands (M21).

signal person_added(id: int)
signal person_removed(id: int)
## Tile, place on the tile or facing changed.
signal person_moved(id: int)

## Optional: kept in sync so people can be found by position.
var spatial_index: SpatialIndex

var _people: Dictionary = {} # id -> PersonData


func _init(index: SpatialIndex = null) -> void:
	spatial_index = index


func size() -> int:
	return _people.size()


func get_person(id: int) -> PersonData:
	return _people.get(id)


func has_person(id: int) -> bool:
	return _people.has(id)


## Adds a person. False if the id is invalid or taken.
func add(person: PersonData) -> bool:
	if person == null or person.id <= 0 or _people.has(person.id):
		return false
	_people[person.id] = person
	if spatial_index != null:
		spatial_index.insert(person.id, person.world2d(), SpatialIndex.KIND_PERSON)
	person_added.emit(person.id)
	return true


## Takes a person out of the world. Their id is never used again; what others
## remember of them (parents, children, partner) is left as it is.
func remove(id: int) -> bool:
	if not _people.erase(id):
		return false
	if spatial_index != null:
		spatial_index.remove(id)
	person_removed.emit(id)
	return true


## Puts a person somewhere else. False for unknown ids and unusable positions.
func move(id: int, tile: Vector2i, sub_tile_offset: Vector2 = Vector2(0.5, 0.5), facing: float = NAN) -> bool:
	var person: PersonData = _people.get(id)
	if person == null or not is_finite(sub_tile_offset.x) or not is_finite(sub_tile_offset.y):
		return false
	person.position = tile
	person.sub_tile_offset = sub_tile_offset.clamp(Vector2.ZERO, Vector2(0.999, 0.999))
	if not is_nan(facing):
		person.facing = facing
	if spatial_index != null:
		spatial_index.move(id, person.world2d())
	person_moved.emit(id)
	return true


## Everyone, in order of id (the order they came into the world).
func all_people() -> Array[PersonData]:
	var ids: Array = _people.keys()
	ids.sort()
	var out: Array[PersonData] = []
	for id: int in ids:
		out.append(_people[id])
	return out


func in_settlement(settlement_id: int) -> Array[PersonData]:
	return _where(func(p: PersonData) -> bool: return p.settlement_id == settlement_id)


func in_household(household_id: int) -> Array[PersonData]:
	return _where(func(p: PersonData) -> bool: return p.household_id == household_id)


## Everyone whose home is the building `building_id`.
func living_in(building_id: int) -> Array[PersonData]:
	return _where(func(p: PersonData) -> bool: return p.home_building_id == building_id)


## Everyone simulated at `tier` right now (see PersonData.sim_tier).
func in_tier(tier: int) -> Array[PersonData]:
	return _where(func(p: PersonData) -> bool: return p.sim_tier == tier)


## The households people belong to (of one settlement, or of all with -1), in
## order of id.
func household_ids(settlement_id: int = -1) -> PackedInt64Array:
	var seen := {}
	for person: PersonData in _people.values():
		if person.household_id > 0 and (settlement_id < 0 or person.settlement_id == settlement_id):
			seen[person.household_id] = true
	var out := PackedInt64Array(seen.keys())
	out.sort()
	return out


## Given names in use, as a set (for the name generator).
func given_names() -> Dictionary:
	var out := {}
	for person: PersonData in _people.values():
		out[person.given_name] = true
	return out


func family_names() -> Dictionary:
	var out := {}
	for person: PersonData in _people.values():
		if person.family_name != "":
			out[person.family_name] = true
	return out


func to_dict() -> Dictionary:
	var records: Array = []
	for person in all_people():
		records.append(person.to_dict())
	return {"persons": records}


## Restores saved people. Returns the number of unusable records skipped, or
## -1 if the data itself is unusable (the registry is then left empty).
func from_dict(data: Dictionary) -> int:
	clear()
	var records: Variant = data.get("persons")
	if typeof(records) != TYPE_ARRAY:
		return -1
	var skipped := 0
	for record: Variant in records:
		var person: PersonData = PersonData.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
		if person == null or not add(person):
			skipped += 1
	return skipped


func clear() -> void:
	if spatial_index != null:
		for id: int in _people:
			spatial_index.remove(id)
	_people.clear()


func _where(test: Callable) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for person in all_people():
		if test.call(person):
			out.append(person)
	return out
