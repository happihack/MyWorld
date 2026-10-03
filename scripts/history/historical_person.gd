class_name HistoricalPerson
extends RefCounted
## Someone who has died, as the world remembers them (bible §16.3): a compact
## record kept in the HistoryArchive in place of the person: who they were,
## whose family they are, what they did that the world remembers, what they
## remembered most, how much they mattered, and where they lie.

var id := 0
var given_name := ""
var family_name := ""
var sex: PersonData.Sex = PersonData.Sex.FEMALE
var birth_tick := 0
var death_tick := 0
## What they died of (Lifecycle.CAUSE_*).
var cause: StringName = &""
var parents: PackedInt64Array = PackedInt64Array()
var children: PackedInt64Array = PackedInt64Array()
## Their partner when they died (0: none).
var partner_id := 0
var occupation_id: StringName = &""
var household_id := 0
var settlement_id := 0
## Where they died.
var place := Vector2.ZERO
## Their grave (a prop; 0: none) — and where it is.
var grave_id := 0
var grave_tile := Vector2i.ZERO
## Events they took part in (not what merely happened to them), the most notable first (ids).
var accomplishments: PackedInt64Array = PackedInt64Array()
## What they remembered most (Memory.to_dict() records, at most a few).
var memories: Array = []
## How much they mattered, in points (Significance, M11.2): what they took
## part in, a long life, children, the Presence.
var significance := 0.0
## The event that told of their death (0: none).
var obituary_event := 0


static func of(person: PersonData, now: int, why: StringName) -> HistoricalPerson:
	var record := HistoricalPerson.new()
	record.id = person.id
	record.given_name = person.given_name
	record.family_name = person.family_name
	record.sex = person.sex
	record.birth_tick = person.birth_tick
	record.death_tick = now
	record.cause = why
	record.parents = person.parents.duplicate()
	record.children = person.children.duplicate()
	record.partner_id = person.partner_id
	record.occupation_id = person.occupation_id
	record.household_id = person.household_id
	record.settlement_id = person.settlement_id
	record.place = person.world2d()
	return record


func full_name() -> String:
	return given_name if family_name == "" else "%s %s" % [given_name, family_name]


## Whole years they lived.
func age_years(ticks_per_year: int) -> int:
	return maxi(death_tick - birth_tick, 0) / maxi(ticks_per_year, 1)


func to_dict() -> Dictionary:
	return {"id": id, "given_name": given_name, "family_name": family_name, "sex": sex,
		"birth_tick": birth_tick, "death_tick": death_tick, "cause": String(cause),
		"parents": parents.duplicate(), "children": children.duplicate(), "partner_id": partner_id,
		"occupation_id": String(occupation_id), "household_id": household_id, "settlement_id": settlement_id,
		"place": place, "grave_id": grave_id, "grave_tile": grave_tile, "accomplishments": accomplishments.duplicate(),
		"memories": memories.duplicate(true), "significance": significance, "obituary_event": obituary_event}


## Null if the record is unusable (no id).
static func from_dict(data: Dictionary) -> HistoricalPerson:
	if typeof(data.get("id")) != TYPE_INT or int(data["id"]) <= 0:
		return null
	var record := HistoricalPerson.new()
	record.id = data["id"]
	record.given_name = str(data.get("given_name", ""))
	record.family_name = str(data.get("family_name", ""))
	record.sex = PersonData.Sex.MALE if int(data.get("sex", 0)) == PersonData.Sex.MALE else PersonData.Sex.FEMALE
	record.birth_tick = int(data.get("birth_tick", 0))
	record.death_tick = maxi(int(data.get("death_tick", 0)), record.birth_tick)
	record.cause = StringName(str(data.get("cause", "")))
	record.parents = _ids(data.get("parents"))
	record.children = _ids(data.get("children"))
	record.partner_id = maxi(int(data.get("partner_id", 0)), 0)
	record.occupation_id = StringName(str(data.get("occupation_id", "")))
	record.household_id = maxi(int(data.get("household_id", 0)), 0)
	record.settlement_id = maxi(int(data.get("settlement_id", 0)), 0)
	var where: Variant = data.get("place")
	if typeof(where) == TYPE_VECTOR2 and is_finite((where as Vector2).x) and is_finite((where as Vector2).y):
		record.place = where
	record.grave_id = maxi(int(data.get("grave_id", 0)), 0)
	if typeof(data.get("grave_tile")) == TYPE_VECTOR2I:
		record.grave_tile = data["grave_tile"]
	record.accomplishments = _ids(data.get("accomplishments"))
	if typeof(data.get("memories")) == TYPE_ARRAY:
		for entry: Variant in data["memories"]:
			if typeof(entry) == TYPE_DICTIONARY and Memory.from_dict(entry) != null:
				record.memories.append((entry as Dictionary).duplicate(true))
	var weight := float(data.get("significance", 0.0)) if typeof(data.get("significance")) in [TYPE_FLOAT, TYPE_INT] else 0.0
	record.significance = clampf(weight, 0.0, 1000.0) if is_finite(weight) else 0.0
	record.obituary_event = maxi(int(data.get("obituary_event", 0)), 0)
	return record


## What they remembered most, as memories (owned by nobody living).
func remembered() -> Array[Memory]:
	var out: Array[Memory] = []
	for entry: Dictionary in memories:
		var memory := Memory.from_dict(entry)
		if memory != null:
			out.append(memory)
	return out


static func _ids(value: Variant) -> PackedInt64Array:
	var out := PackedInt64Array()
	if typeof(value) == TYPE_PACKED_INT64_ARRAY:
		for id_value: int in value:
			if id_value > 0:
				out.append(id_value)
	return out
