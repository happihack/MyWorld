class_name MysterySystem
extends RefCounted
## The world's seeded mysteries (M18, bible §25.2): placed deterministically
## from the world's seed when it is first opened, dormant until what each
## clue needs has come about. Once a game day, each mystery's next clue is
## looked at; when its conditions hold it is found — history tells of it (an
## event, whoever found it named), and it stays found. One clue a day at most
## for each: **never everything at once**.

## A clue has been found: the mystery, the clue's index, who found it (0: nobody in particular).
signal clue_found(mystery_id: StringName, step: int, person_id: int)

const DIR := "res://data/mysteries/"
## Within this many tiles of a mystery's place, someone has "stood near it".
const NEAR := 2.5
## A mystery placed is at least this far from where the band begins (tiles).
const FROM_START := 10.0

var defs: Array[MysteryDef] = []
var problems: PackedStringArray = []
var world: WorldData
var props: PropRegistry
var people: PersonRegistry
var settlements: Settlements
var events: EventLog
var ids: IdAllocator
var world_seed := 0
## Is there someone looking into the unexplained? Callable(settlement) -> bool.
var has_scholar := Callable()
## Has the Edge been found? Callable() -> bool.
var edge_known := Callable()
## mystery id -> {"tile": Vector2i, "prop": int (0: none), "found": int (clues found), "seen": PackedInt32Array (days)}.
var placed: Dictionary = {}
var _day := -1_000_000


func load_defs(dir: String = DIR) -> void:
	defs.clear()
	problems.clear()
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as MysteryDef
		if def == null:
			problems.append("%s is not a mystery" % file)
			continue
		var found := def.validate()
		problems.append_array(found)
		if found.is_empty():
			defs.append(def)


func bind(land: WorldData, registry: PropRegistry, persons: PersonRegistry, all: Settlements, log: EventLog,
		id_source: IdAllocator, seed_value: int, now: int) -> void:
	world = land
	props = registry
	people = persons
	settlements = all
	events = log
	ids = id_source
	world_seed = seed_value
	_day = Config.time.day_index(now)


func get_def(id: StringName) -> MysteryDef:
	for def in defs:
		if def.id == id:
			return def
	return null


# --- placing ------------------------------------------------------------------------------------------

## Puts every mystery not yet placed somewhere (deterministic for the world's seed).
func place_all(start_tile: Vector2i) -> void:
	for def in defs:
		if placed.has(def.id):
			continue
		var tile: Variant = _where(def, start_tile)
		if tile == null:
			continue
		var entry := {"tile": tile, "prop": 0, "found": 0, "seen": PackedInt32Array()}
		if def.placement == "stones" or (def.placement == "ruin" and props.prop_at(tile) == null):
			var stones := PropData.new()
			stones.id = ids.next_id()
			stones.kind = PropData.Kind.RUIN
			stones.tile = tile
			if props.add(stones):
				entry["prop"] = stones.id
		elif def.placement == "ruin":
			entry["prop"] = props.prop_at(tile).id
		placed[def.id] = entry


func _where(def: MysteryDef, start: Vector2i) -> Variant:
	var b := world.bounds
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, String(def.id), "mystery"])
	if def.placement == "ruin":
		# Old stones the world already has, if any are free.
		var ruins: Array[PropData] = []
		for prop in props.all_props():
			if prop.kind == PropData.Kind.RUIN and not _taken(prop.tile):
				ruins.append(prop)
		ruins.sort_custom(func(x: PropData, y: PropData) -> bool: return x.id < y.id)
		if not ruins.is_empty():
			return ruins[rng.randi_range(0, ruins.size() - 1)].tile
	if def.placement == "edge":
		var side := rng.randi_range(0, 3)
		var along := rng.randi_range(b.position.x + 2, b.end.x - 3)
		match side:
			0: return Vector2i(along, b.position.y)
			1: return Vector2i(along, b.end.y - 1)
			2: return Vector2i(b.position.x, clampi(along, b.position.y, b.end.y - 1))
			_: return Vector2i(b.end.x - 1, clampi(along, b.position.y, b.end.y - 1))
	if def.placement == "none":
		return start
	for attempt in 200:
		var tile := Vector2i(rng.randi_range(b.position.x + 2, b.end.x - 3), rng.randi_range(b.position.y + 2, b.end.y - 3))
		if Vector2(tile - start).length() < FROM_START or world.get_water(tile) > 0.0 or props.prop_at(tile) != null or _taken(tile):
			continue
		return tile
	return null


func _taken(tile: Vector2i) -> bool:
	for entry: Dictionary in placed.values():
		if entry["tile"] == tile:
			return true
	return false


# --- unfolding ----------------------------------------------------------------------------------------

func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	each_day(now)


func each_day(now: int) -> void:
	_day = Config.time.day_index(now)
	for def in defs:
		var entry: Variant = placed.get(def.id)
		if entry == null:
			continue
		var near := _near(entry["tile"])
		if near != null:
			var seen: PackedInt32Array = entry["seen"]
			if seen.is_empty() or seen[-1] != _day:
				seen.append(_day)
				entry["seen"] = seen
		var step := int(entry["found"])
		if step >= def.steps.size():
			continue
		if holds(def.steps[step], entry, near):
			entry["found"] = step + 1
			clue_found.emit(def.id, step, near.id if near != null else 0)


## Does every condition of a clue hold?
func holds(conditions: PackedStringArray, entry: Dictionary, near: PersonData) -> bool:
	for condition in conditions:
		var parts := condition.split(":")
		match parts[0]:
			"dormant":
				return false
			"visited":
				if (entry["seen"] as PackedInt32Array).is_empty():
					return false
			"seen":
				if (entry["seen"] as PackedInt32Array).size() < int(parts[1]):
					return false
			"known":
				if settlements == null or not settlements.all().any(func(own: Settlement) -> bool: return own.knows_how(StringName(parts[1]))):
					return false
			"scholar":
				if settlements == null or not has_scholar.is_valid() \
						or not settlements.all().any(func(own: Settlement) -> bool: return bool(has_scholar.call(own))):
					return false
			"edge":
				if not edge_known.is_valid() or not bool(edge_known.call()):
					return false
			"exposed":
				if not _exposed(entry["tile"]):
					return false
			"building":
				if not _standing(parts[1]):
					return false
	return true


## Someone standing near a place (null: nobody).
func _near(tile: Vector2i) -> PersonData:
	if people == null or people.spatial_index == null:
		return null
	var at := Vector2(tile) + Vector2(0.5, 0.5)
	var best: PersonData = null
	for id in people.spatial_index.query_radius(at, NEAR, SpatialIndex.KIND_PERSON):
		var person := people.get_person(id)
		if person != null and (best == null or person.id < best.id):
			best = person
	return best


## Has the ground over it been turned: tilled, flooded to mud, washed away, or worked into a path?
func _exposed(tile: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var t := tile + Vector2i(dx, dy)
			if not world.is_in_bounds(t):
				continue
			var terrain := world.get_terrain(t)
			if terrain == ChunkData.Terrain.FARMLAND or terrain == ChunkData.Terrain.MUD or terrain == ChunkData.Terrain.RIVERBED \
					or terrain == ChunkData.Terrain.ROAD or terrain == ChunkData.Terrain.PAVED:
				return true
			var prop := props.prop_at(t)
			if prop != null and prop.kind == PropData.Kind.CROP:
				return true
	return false


func _standing(building: String) -> bool:
	var kinds := {"stone_circle": PropData.Kind.STONE_CIRCLE, "record_stone": PropData.Kind.RECORD_STONE, "kiln": PropData.Kind.KILN}
	if not kinds.has(building):
		return false
	for prop in props.all_props():
		if prop.kind == kinds[building]:
			return true
	return false


## The clues found so far, in order: [[mystery id, step], …].
func found() -> Array:
	var out: Array = []
	for def in defs:
		var entry: Variant = placed.get(def.id)
		if entry == null:
			continue
		for step in int(entry["found"]):
			out.append([def.id, step])
	return out


func to_dict() -> Dictionary:
	var kept := {}
	for id: StringName in placed:
		var entry: Dictionary = placed[id]
		kept[String(id)] = {"tile": entry["tile"], "prop": entry["prop"], "found": entry["found"], "seen": (entry["seen"] as PackedInt32Array).duplicate()}
	return {"placed": kept, "day": _day}


func from_dict(data: Dictionary) -> void:
	placed.clear()
	if typeof(data.get("placed")) == TYPE_DICTIONARY:
		for key: Variant in data["placed"]:
			var e: Variant = data["placed"][key]
			if typeof(e) == TYPE_DICTIONARY and typeof((e as Dictionary).get("tile")) == TYPE_VECTOR2I:
				placed[StringName(str(key))] = {"tile": e["tile"], "prop": int(e.get("prop", 0)), "found": int(e.get("found", 0)),
					"seen": (e["seen"] as PackedInt32Array).duplicate() if typeof(e.get("seen")) == TYPE_PACKED_INT32_ARRAY else PackedInt32Array()}
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var parts := PackedStringArray()
	for def in defs:
		var entry: Variant = placed.get(def.id)
		if entry != null:
			parts.append("%s %d/%d" % [def.id, int(entry["found"]), def.steps.size()])
	return "mysteries: %s" % ", ".join(parts)
