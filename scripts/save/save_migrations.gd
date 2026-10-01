class_name SaveMigrations
extends RefCounted
## Upgrades save data written by older game versions (bible §31.9).
##
## Every change to an already-saved structure must:
##   1. bump SaveManager.SAVE_VERSION,
##   2. add a step here: STEPS[old_version] = Callable(data) -> Dictionary
##      returning the data in old_version + 1 format,
##   3. add a fixture save of the old version under tests/fixtures/ plus a test.

static var STEPS: Dictionary = { # int from_version -> Callable
	1: _v1_to_v2,
	2: _v2_to_v3,
	3: _v3_to_v4,
	4: _v4_to_v5,
}


class Result:
	extends RefCounted
	var ok := false
	var error := ""
	var data: Dictionary = {}


## Version 1 saved no world content: the world was rebuilt from its seed on
## every load. An empty world_state tells WorldSession to do exactly that once
## more; from then on the world is saved properly.
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) == TYPE_DICTIONARY and not (world as Dictionary).has("world_state"):
		(world as Dictionary)["world_state"] = {}
	return data


## Version 3 (M3) adds to the world state: loose objects, props changed since
## they were generated, the player's history and the water's books.
##
## In version 2 rocks were props. They are loose objects now, with the same
## ids — so the rocks that had been removed (the glade cleared for the
## settlement) are carried over as removed loose objects, or they would lie
## in the glade again. (Builds between M3.1 and M3.6 already wrote some of
## these parts under version 2; what is there is kept.)
static func _v2_to_v3(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data # no world content saved (a migrated version 1): rebuilt from the seed
	var s: Dictionary = state
	var props: Variant = s.get("props")
	if typeof(props) == TYPE_DICTIONARY:
		if not (props as Dictionary).has("changed"):
			(props as Dictionary)["changed"] = []
		if typeof(s.get("loose")) != TYPE_DICTIONARY:
			var removed: Variant = (props as Dictionary).get("removed")
			s["loose"] = {
				"removed": (removed as PackedInt64Array).duplicate() if typeof(removed) == TYPE_PACKED_INT64_ARRAY else PackedInt64Array(),
				"objects": [],
			}
	if typeof(s.get("history")) != TYPE_DICTIONARY:
		s["history"] = {}
	if typeof(s.get("water")) != TYPE_DICTIONARY:
		s["water"] = {}
	return data


## Version 4 (M4) adds the people. A world saved before it had any gets an
## empty record — which the loader reads as "nobody has arrived yet" and
## answers with the starting band (a record with a "persons" list, even an
## empty one, is a world whose people are known).
static func _v3_to_v4(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if typeof((state as Dictionary).get("people")) != TYPE_DICTIONARY:
		(state as Dictionary)["people"] = {}
	return data


## Version 5 (M4.6) adds what people's behaviour keeps about the world (the
## places the band has been). People themselves need no migrating: what a
## person saved before M4.4 lacks — needs, a plan — is filled in when they
## start living (their record always had the fields, empty).
static func _v4_to_v5(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if typeof((state as Dictionary).get("behavior")) != TYPE_DICTIONARY:
		(state as Dictionary)["behavior"] = {}
	return data


static func migrate(data: Dictionary, from_version: int, to_version: int, steps: Dictionary = STEPS) -> Result:
	var result := Result.new()
	if from_version > to_version:
		result.error = "save version %d is newer than this game supports (%d)" % [from_version, to_version]
		return result
	if from_version < 1:
		result.error = "invalid save version %d" % from_version
		return result
	var current := data
	for version in range(from_version, to_version):
		if not steps.has(version):
			result.error = "no migration from save version %d" % version
			return result
		var step: Callable = steps[version]
		var next: Variant = step.call(current.duplicate(true))
		if typeof(next) != TYPE_DICTIONARY:
			result.error = "migration from version %d failed" % version
			return result
		current = next
	result.ok = true
	result.data = current
	return result
