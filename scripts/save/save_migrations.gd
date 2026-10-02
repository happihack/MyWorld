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
	5: _v5_to_v6,
	6: _v6_to_v7,
	7: _v7_to_v8,
	8: _v8_to_v9,
	9: _v9_to_v10,
	10: _v10_to_v11,
	11: _v11_to_v12,
	12: _v12_to_v13,
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


## Version 6 (M5.4) adds what everyone remembers (`memories`) and the
## numbering of stimuli (`perception`).
##
## Version 5 worlds (M5.3) already had people who had been touched, seen
## things and been told of them — with convictions and a count of each kind
## of experience, but no memories. They are given one memory per kind of
## experience: vaguer than a lived one (nobody knows any more where it was or
## how it felt), taken the way they are most convinced things are.
static func _v5_to_v6(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	var s: Dictionary = state
	if typeof(s.get("perception")) != TYPE_DICTIONARY:
		s["perception"] = {"next_stimulus_id": 1}
	if typeof(s.get("memories")) == TYPE_DICTIONARY:
		return data
	var clock: Variant = (world as Dictionary).get("clock")
	var now := int((clock as Dictionary).get("tick", 0)) if typeof(clock) == TYPE_DICTIONARY else 0
	var list: Array = []
	var next_id := 1
	var people: Variant = s.get("people")
	var persons: Variant = (people as Dictionary).get("persons") if typeof(people) == TYPE_DICTIONARY else null
	if typeof(persons) == TYPE_ARRAY:
		for record: Variant in persons:
			if typeof(record) != TYPE_DICTIONARY or typeof((record as Dictionary).get("id")) != TYPE_INT:
				continue
			var person: Dictionary = record
			var knowledge: Variant = person.get("knowledge")
			var experienced: Variant = (knowledge as Dictionary).get("experienced") if typeof(knowledge) == TYPE_DICTIONARY else null
			if typeof(experienced) != TYPE_DICTIONARY:
				continue
			# What they are most convinced of (the order of ReactionTable.INTERPRETATIONS in version 5).
			var order := ["natural", "spirit", "deity", "ancestor", "experiment", "unknown_intelligence",
				"multiple_entities", "hallucination", "physics"]
			var beliefs: Variant = person.get("beliefs")
			var conviction := "natural"
			if typeof(beliefs) == TYPE_PACKED_FLOAT32_ARRAY:
				var most := 0.0
				for i in mini((beliefs as PackedFloat32Array).size(), order.size()):
					if beliefs[i] > most:
						most = beliefs[i]
						conviction = order[i]
			var ids := PackedInt64Array()
			var kinds: Array = (experienced as Dictionary).keys()
			kinds.sort()
			for kind: Variant in kinds:
				var times := int((experienced as Dictionary)[kind])
				if times <= 0:
					continue
				var at := Vector2.ZERO
				if typeof(person.get("position")) == TYPE_VECTOR2I:
					at = Vector2(person["position"]) + Vector2(0.5, 0.5)
				var touched := str(kind) == "touch"
				list.append({
					"id": next_id, "owner_kind": 0, "owner_id": person["id"], "kind": "experience", "subject": str(kind),
					"stimulus_id": 0, "event_id": 0, "tick": now, "first_tick": now, "location": at,
					"interpretation": conviction, "emotions": PackedFloat32Array([0, 0, 0, 0, 0]),
					"intensity": 0.5, "importance": 0.5 if touched else 0.25, "source": 0 if touched else 1, "told_by": 0,
					"fidelity": 0.8, "count": times, "stage": 2, "told_tick": -1, "text_key": "", "text_params": {},
				})
				ids.append(next_id)
				next_id += 1
			person["memory_ids"] = ids
	s["memories"] = {"next_id": next_id, "faded_day": -1, "memories": list}
	return data


## Version 7 (M5.5) adds to the player's history: who was touched (and how
## often) and the achievements unlocked. Both can be told from what a
## version-6 world holds: people carry the mark of having been touched (and
## a count of it), and the history's log has the first touch of a person.
static func _v6_to_v7(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	var history: Variant = (state as Dictionary).get("history")
	if typeof(history) != TYPE_DICTIONARY or (history as Dictionary).is_empty():
		return data
	var h: Dictionary = history
	if typeof(h.get("people")) != TYPE_DICTIONARY:
		var touched := {}
		var people: Variant = (state as Dictionary).get("people")
		var persons: Variant = (people as Dictionary).get("persons") if typeof(people) == TYPE_DICTIONARY else null
		if typeof(persons) == TYPE_ARRAY:
			for record: Variant in persons:
				if typeof(record) != TYPE_DICTIONARY or typeof((record as Dictionary).get("id")) != TYPE_INT:
					continue
				if (int((record as Dictionary).get("flags", 0)) & 4) == 0: # PersonData.FLAG_TOUCHED_BY_PLAYER
					continue
				var times := 1
				var knowledge: Variant = (record as Dictionary).get("knowledge")
				var experienced: Variant = (knowledge as Dictionary).get("experienced") if typeof(knowledge) == TYPE_DICTIONARY else null
				if typeof(experienced) == TYPE_DICTIONARY:
					times = maxi(int((experienced as Dictionary).get("touch", 1)), 1)
				touched[int(record["id"])] = times
		h["people"] = touched
	if typeof(h.get("achievements")) != TYPE_DICTIONARY:
		var unlocked := {}
		var keys: Variant = h.get("keys")
		if typeof(keys) == TYPE_DICTIONARY and int((keys as Dictionary).get("touch:person", 0)) > 0:
			var first := {"tick": 0, "intervention": 0}
			var entries: Variant = h.get("entries")
			if typeof(entries) == TYPE_ARRAY:
				for entry: Variant in entries:
					if typeof(entry) == TYPE_DICTIONARY and str((entry as Dictionary).get("type", "")) == "touch" \
							and str((entry as Dictionary).get("subject", "")) == "person":
						first = {"tick": int((entry as Dictionary).get("tick", 0)), "intervention": int((entry as Dictionary).get("id", 0))}
						break
			unlocked["first_contact"] = first
		h["achievements"] = unlocked
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


## Version 8 (M6.4) adds what everyone has been doing lately (the day log)
## and how long the player has stayed with one person. Neither can be told
## from an older save: both start empty.
static func _v7_to_v8(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if not (state as Dictionary).has("day_log"):
		(state as Dictionary)["day_log"] = {"logs": {}}
	if not (state as Dictionary).has("observer"):
		(state as Dictionary)["observer"] = {}
	return data


## Version 9 (M7.1) adds resources: what a tree, bush or rock still holds
## (props: "stock", "stock_tick", "felled"), piles of what was gathered (loose
## objects of a new kind, with "resource" and "amount") and what people carry
## ("carrying", "carrying_amount"). An older world has none of it: every node
## is whole, nothing lies in piles, nobody carries anything — which is what
## records without those fields mean, so there is nothing to rewrite.
static func _v8_to_v9(data: Dictionary) -> Dictionary:
	return data


## Version 10 (M7.2) adds the settlement's own state (when its fire wants
## wood next, its job board), how far a pile has gone bad ("spoil") and what
## is left of the food someone last took ("food_in_hand"). An older world's
## settlement begins its housekeeping when it is opened.
static func _v9_to_v10(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if not (state as Dictionary).has("settlement"):
		(state as Dictionary)["settlement"] = {}
	return data


## Version 11 (M7.3) adds farming: crops (props of a new kind with "growth",
## "vigor" and "tended_tick"), tilled ground, and the day up to which the
## fields' soil has been looked after. An older world has no fields; its
## people begin one when the season comes.
static func _v10_to_v11(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if not (state as Dictionary).has("farming"):
		(state as Dictionary)["farming"] = {}
	return data


## Version 12 (M7.4) adds animals. An older world has none in its save: it
## is given its first when it is opened (they were always there — the
## player just had not seen them).
static func _v11_to_v12(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if not (state as Dictionary).has("animals"):
		(state as Dictionary)["animals"] = {}
	return data


## Version 13 (M7.5) adds the world's event log, what the chronicler keeps
## between events, and the statistics. An older world has no history
## written down: it begins now ("adopt": what the settlement already has in
## store is not discovered a second time).
static func _v12_to_v13(data: Dictionary) -> Dictionary:
	var world: Variant = data.get("world")
	if typeof(world) != TYPE_DICTIONARY:
		return data
	var state: Variant = (world as Dictionary).get("world_state")
	if typeof(state) != TYPE_DICTIONARY or (state as Dictionary).is_empty():
		return data
	if not (state as Dictionary).has("events"):
		(state as Dictionary)["events"] = {}
	if not (state as Dictionary).has("chronicle"):
		(state as Dictionary)["chronicle"] = {"adopt": true}
	if not (state as Dictionary).has("stats"):
		(state as Dictionary)["stats"] = {}
	return data
