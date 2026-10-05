class_name SaveValidator
extends RefCounted
## Checks what a save holds before a world is built from it, and repairs it
## (bible §31.9: "validate & repair — drop dangling ids, quarantine invalid
## entities"; M22). Each part of the world reads its own records leniently
## (an unusable record is skipped); this looks at how they hang together:
##   people — a place outside the world, numbers that are not numbers, a
##     partner, parent or child nobody knows, a home that is not there;
##   relationships — between people who are not (both) alive;
##   things put in the world (props) — outside it.
## What can be mended is mended; what cannot is taken out and handed back in
## `quarantine` (kept aside by the SaveManager, never simply lost).
##
## Works on the plain data, in place. Never crashes on bad input.

## How many records a repair keeps aside at most (a badly broken save would
## otherwise fill the quarantine with copies of the world).
const MOST_KEPT := 200


## Repairs `world` (a save's "world" dictionary) in place. Returns
## {"repaired": int, "notes": PackedStringArray, "quarantine": Array of
## {"where": String, "why": String, "record": Variant}}.
static func repair(world: Dictionary) -> Dictionary:
	var report := {"repaired": 0, "notes": PackedStringArray(), "quarantine": []}
	var state: Variant = world.get("world_state")
	if typeof(state) != TYPE_DICTIONARY:
		return report
	var bounds := _bounds(state)
	var start := _start_tile(state, bounds)
	var props := _prop_ids(state, bounds, report)
	var living := _people(state, bounds, start, props, report)
	_relationships(state, living, report)
	return report


static func _note(report: Dictionary, note: String) -> void:
	report["repaired"] = int(report["repaired"]) + 1
	var notes: PackedStringArray = report["notes"]
	if not notes.has(note):
		notes.append(note)
		report["notes"] = notes


static func _keep(report: Dictionary, where: String, why: String, record: Variant) -> void:
	_note(report, "%s: %s" % [where, why])
	var kept: Array = report["quarantine"]
	if kept.size() < MOST_KEPT:
		kept.append({"where": where, "why": why, "record": record})


static func _bounds(state: Dictionary) -> Rect2i:
	var world: Variant = state.get("world")
	if typeof(world) == TYPE_DICTIONARY and typeof(world.get("bounds")) == TYPE_RECT2I:
		return world["bounds"]
	return Rect2i() # (unknown: nothing is out of it)


static func _start_tile(state: Dictionary, bounds: Rect2i) -> Vector2i:
	var start: Variant = state.get("start")
	if typeof(start) == TYPE_DICTIONARY and typeof(start.get("settlement_tile")) == TYPE_VECTOR2I:
		return start["settlement_tile"]
	return bounds.get_center() if bounds.has_area() else Vector2i.ZERO


static func _inside(bounds: Rect2i, tile: Vector2i) -> bool:
	return not bounds.has_area() or bounds.has_point(tile)


## The ids of the things put in the world (and those outside it taken out).
static func _prop_ids(state: Dictionary, bounds: Rect2i, report: Dictionary) -> Dictionary:
	var ids := {}
	var props: Variant = state.get("props")
	if typeof(props) != TYPE_DICTIONARY:
		return ids
	for key in ["added", "changed"]:
		var records: Variant = props.get(key)
		if typeof(records) != TYPE_ARRAY:
			continue
		var kept: Array = []
		for record: Variant in records:
			if typeof(record) == TYPE_DICTIONARY and typeof(record.get("tile")) == TYPE_VECTOR2I \
					and not _inside(bounds, record["tile"]):
				_keep(report, "props", "outside the world", record)
				continue
			kept.append(record)
			if typeof(record) == TYPE_DICTIONARY and typeof(record.get("id")) == TYPE_INT:
				ids[int(record["id"])] = true
		props[key] = kept
	return ids


## The living, mended: returns their ids (id -> true).
static func _people(state: Dictionary, bounds: Rect2i, start: Vector2i, props: Dictionary, report: Dictionary) -> Dictionary:
	var living := {}
	var people: Variant = state.get("people")
	if typeof(people) != TYPE_DICTIONARY or typeof(people.get("persons")) != TYPE_ARRAY:
		return living
	var known := {} # everyone: the living and the dead (the archive)
	var archive: Variant = state.get("archive")
	if typeof(archive) == TYPE_DICTIONARY and typeof(archive.get("people")) == TYPE_ARRAY:
		for record: Variant in archive["people"]:
			if typeof(record) == TYPE_DICTIONARY and typeof(record.get("id")) == TYPE_INT:
				known[int(record["id"])] = true
	var kept: Array = []
	for record: Variant in people["persons"]:
		if typeof(record) != TYPE_DICTIONARY or typeof(record.get("id")) != TYPE_INT or int(record["id"]) <= 0:
			_keep(report, "people", "no id", record)
			continue
		var id := int(record["id"])
		if living.has(id):
			_keep(report, "people", "the same person twice", record)
			continue
		living[id] = true
		known[id] = true
		kept.append(record)
	people["persons"] = kept
	for record: Dictionary in kept:
		# Where they are: in the world, or brought back to the fire.
		if typeof(record.get("position")) == TYPE_VECTOR2I and not _inside(bounds, record["position"]):
			record["position"] = start
			_note(report, "people: someone outside the world brought back to the fire")
		for key: String in ["health", "mood", "stress", "facing", "significance", "food_in_hand"]:
			if record.has(key) and typeof(record[key]) == TYPE_FLOAT and not is_finite(float(record[key])):
				record[key] = 1.0 if key == "health" else 0.0
				_note(report, "people: a number that was not one (%s)" % key)
		if typeof(record.get("sub_tile_offset")) == TYPE_VECTOR2:
			var offset: Vector2 = record["sub_tile_offset"]
			if not offset.is_finite():
				record["sub_tile_offset"] = Vector2(0.5, 0.5)
				_note(report, "people: a number that was not one (sub_tile_offset)")
		if typeof(record.get("needs")) == TYPE_PACKED_FLOAT32_ARRAY:
			var needs: PackedFloat32Array = record["needs"]
			for i in needs.size():
				if not is_finite(needs[i]):
					needs[i] = 1.0
					record["needs"] = needs
					_note(report, "people: a number that was not one (needs)")
		# Who they are to others: only people there are (living, or remembered).
		if typeof(record.get("partner_id")) == TYPE_INT and int(record["partner_id"]) != 0 and not known.has(int(record["partner_id"])):
			record["partner_id"] = 0
			_note(report, "people: a partner nobody knows")
		for key: String in ["parents", "children"]:
			if typeof(record.get(key)) == TYPE_PACKED_INT64_ARRAY:
				var ids: PackedInt64Array = record[key]
				var good := PackedInt64Array()
				for other in ids:
					if known.has(int(other)):
						good.append(other)
				if good.size() != ids.size():
					record[key] = good
					_note(report, "people: %s nobody knows" % key)
		# A home that is not there: none (they are housed again).
		if typeof(record.get("home_building_id")) == TYPE_INT and int(record["home_building_id"]) != 0 \
				and not props.has(int(record["home_building_id"])) and not PropData.is_generated_id(int(record["home_building_id"])):
			record["home_building_id"] = 0
			_note(report, "people: a home that is not there")
	return living


static func _relationships(state: Dictionary, living: Dictionary, report: Dictionary) -> void:
	var store: Variant = state.get("relationships")
	if typeof(store) != TYPE_DICTIONARY or typeof(store.get("pairs")) != TYPE_ARRAY or living.is_empty():
		return
	var kept: Array = []
	for pair: Variant in store["pairs"]:
		if typeof(pair) != TYPE_DICTIONARY or not living.has(int(pair.get("a", 0))) or not living.has(int(pair.get("b", 0))):
			_keep(report, "relationships", "between people who are not both living", pair)
			continue
		kept.append(pair)
	store["pairs"] = kept
