class_name SettlementPlanner
extends RefCounted
## What a settlement builds (bible §17.2, M12.1): the player never places a
## building — once a game day the settlement weighs its needs and, if one of
## them calls for a building and nothing is being built yet (a home: no other
## home), it begins one
## on the best ground for it.
##
##   homes full (or someone without a roof,   → a hut
##   or two households crowded under one)
##   the stores overflowing, food going bad   → a storehouse
##   water to drink far from the fire         → a well
##   land near the fire cut off by water      → a bridge across, bank to bank,
##     (a crossing: tile by tile, the near      (Crossing; at the owner's word,
##     bank first)                               2026-10-04 — it was one tile
##                                               over a ford waded often, M12.2)
##   (crafting and the knowing of toolmaking  → a workshop: M12.4, M18)
##
## Where: open, dry ground a few tiles from the fire, above the highest water
## the settlement remembers, clear of other buildings and of the graves, as
## even as can be and as near as can be (unevenness and distance weigh against it).

var _settlement: Settlement
var _construction: ConstructionSystem
var _people: PersonRegistry
var _households: Households
var _traffic: Traffic
## What its people believe together (M17.2: a shrine for a myth many hold).
var faith: MythSystem
## What is further than this from the fire is not this settlement's to build or keep.
const NEAR_REACH := 16.0
var _world: WorldData
var _pathfinder: Pathfinder
var _config: ConstructionConfig
var _day := -1_000_000
var _spoiled: Array = [] # [day, units]
## The crossing worked out today: [day, {tiles, turn}] (it takes a walk over the land).
var _crossing_today: Array = [-1_000_000, {}]


func bind(settlement: Settlement, construction: ConstructionSystem, people: PersonRegistry, world: WorldData,
		pathfinder: Pathfinder, now: int, config: ConstructionConfig = null, households: Households = null,
		traffic: Traffic = null) -> void:
	_settlement = settlement
	_households = households
	_traffic = traffic
	_construction = construction
	_people = people
	_world = world
	_pathfinder = pathfinder
	_config = config if config != null else Config.construction
	_day = Config.time.day_index(now)
	_spoiled.clear()
	if _settlement != null and not _settlement.spoiled.is_connected(_on_spoiled):
		_settlement.spoiled.connect(_on_spoiled)


## Once a game day (by daylight): what is needed, and whether to begin building it.
func advance_to(now: int) -> void:
	if _settlement == null or _construction == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day or Config.time.minute_of_day(now) < 8 * 60:
		return
	_day = today
	if _households != null:
		_households.settle_empty_homes()
	plan(now)


## Weighs the needs now; begins the building the most pressing one calls for.
## Returns the project begun ({}: none).
func plan(now: int) -> Dictionary:
	var going := _construction.builds(_settlement.id)
	for need: StringName in needs(now):
		# One building at a time — but a home does not wait for anything else.
		if not going.is_empty() and (need != &"home" or going.any(func(p: Dictionary) -> bool: return str(p["def"]) == "hut")):
			continue
		var def := _construction.buildings.with_tag(String(need))
		if def.is_empty() or (def[0].tech != &"" and not _settlement.knows_how(def[0].tech)):
			continue
		if need == &"bridge":
			var across := crossing(now)
			for tile: Vector2i in across.get("tiles", []):
				if Crossing.is_bridge(_construction.props(), tile):
					continue # (built, or going up)
				return _construction.start(def[0].id, tile, now, int(across["turn"]), _settlement.id)
			continue
		var site: Variant = shrine_site() if need == &"shrine" else site_for(def[0])
		if site == null:
			continue
		return _construction.start(def[0].id, site, now, 0, _settlement.id)
	return {}


## What calls for a building now, the most pressing first: "home", "storage", "water".
func needs(now: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if homes_short():
		out.append(&"home")
	if storage_short(now):
		out.append(&"storage")
	if water_far():
		out.append(&"water")
	if workshop_wanted():
		out.append(&"workshop")
	if not crossing(now).is_empty():
		out.append(&"bridge")
	for tag: String in LANDMARKS:
		if landmark_wanted(tag):
			out.append(StringName(tag))
	if shrine_wanted():
		out.append(&"shrine")
	return out


## Where to bridge the water (worked out once a day): land near the fire
## that cannot be reached on foot, and the shortest way over to it from
## land that can — straight across, at most `crossing_span_most` tiles of
## water, the near bank first; the bridges of a crossing already begun count
## as built (so it is carried on, and an old one-tile bridge is a start).
## {"tiles": [Vector2i…], "turn": rotation} — {} if there is none to make.
func crossing(now: int) -> Dictionary:
	var today := Config.time.day_index(now)
	if int(_crossing_today[0]) != today:
		_crossing_today = [today, _find_crossing()]
	return _crossing_today[1]


func _find_crossing() -> Dictionary:
	if _pathfinder == null or _settlement == null or _settlement.member_count() < _config.crossing_from_people:
		return {}
	var fire := _settlement.start_info().settlement_tile
	var reach := _config.crossing_reach
	var area := Rect2i(fire - Vector2i(reach, reach), Vector2i(reach * 2 + 1, reach * 2 + 1)).intersection(_world.bounds)
	# What can be walked to from the fire.
	var reached := {}
	var start := fire
	if not _pathfinder.can_stand(start):
		var near := _pathfinder.standable_near(fire, 1, 3)
		if near.is_empty():
			return {}
		start = near[0]
	var queue: Array[Vector2i] = [start]
	reached[start] = true
	while not queue.is_empty():
		var at: Vector2i = queue.pop_back()
		for step: Vector2i in _STEPS:
			var next := at + step
			if not reached.has(next) and area.has_point(next) and _pathfinder.can_step(at, next):
				reached[next] = true
				queue.append(next)
	# A crossing begun is carried on to the far bank (even where the last of
	# it could be waded).
	var begun := _unfinished(fire, reach, reached)
	if not begun.is_empty():
		return begun
	# Land that cannot be walked to: enough of it to want a way over.
	var cut_off := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var tile := Vector2i(x, y)
			if not reached.has(tile) and _dry(tile) and _pathfinder.can_stand(tile):
				cut_off += 1
	if cut_off < _config.cut_off_least:
		return {}
	# The shortest way over, nearest the fire.
	var best := {}
	var best_cost := INF
	var props := _construction.props()
	for from: Vector2i in reached:
		if not _dry(from):
			continue
		for step: Vector2i in _STEPS:
			var tiles: Array[Vector2i] = []
			var built := 0
			var at := from + step
			while tiles.size() < _config.crossing_span_most and _world.is_in_bounds(at) and (Crossing.is_bridge(props, at) or not _dry(at)):
				var there := props.prop_at(at) if props != null else null
				if there != null and there.kind != PropData.Kind.BRIDGE:
					tiles.clear()
					break
				tiles.append(at)
				if Crossing.deck_at(props, at) != null:
					built += 1
				at += step
			if tiles.is_empty() or not _world.is_in_bounds(at) or not _dry(at) or reached.has(at) or not _pathfinder.can_stand(at):
				continue
			var cost := (tiles.size() - built) * 10.0 + Vector2(from - fire).length()
			if cost < best_cost:
				best_cost = cost
				best = {"tiles": tiles, "turn": 64 if step.x != 0 else 0}
	return best


## A bridge begun that does not reach dry land on both sides yet (a crossing
## under way, or an old one-tile bridge): the whole way over it, from the bank
## that can be walked to — the nearest the fire; none within CROSSINGS_APART
## of a crossing that is finished (one way over a stretch of water is enough).
func _unfinished(fire: Vector2i, reach: int, reached: Dictionary) -> Dictionary:
	var props := _construction.props()
	if props == null:
		return {}
	var finished: Array[Vector2i] = []
	var open: Array[Dictionary] = []
	var seen := {}
	for prop in props.all_props():
		if prop.kind != PropData.Kind.BRIDGE or seen.has(prop.tile) or Vector2(prop.tile - fire).length() > reach:
			continue
		var axis := Crossing.axis_of(prop.rotation_step)
		var line := _line_through(prop.tile, axis)
		for tile: Vector2i in line.get("tiles", [prop.tile]):
			seen[tile] = true
		if line.is_empty():
			continue
		if int(line["open"]) == 0:
			finished.append_array(line["tiles"])
		else:
			line["turn"] = prop.rotation_step
			open.append(line)
	var best := {}
	var best_distance := INF
	for line in open:
		var tiles: Array[Vector2i] = line["tiles"]
		var beside := false
		for done in finished:
			for tile in tiles:
				if Vector2(done - tile).length() <= CROSSINGS_APART:
					beside = true
		if beside:
			continue
		if not reached.has(line["from"]):
			if not reached.has(line["to"]):
				continue
			tiles.reverse() # (from the bank they can walk to)
		var distance := Vector2(tiles[0] - fire).length()
		if distance < best_distance:
			best_distance = distance
			best = {"tiles": tiles, "turn": int(line["turn"])}
	return best


## The way over the water through `tile` along `axis`, bank to bank:
## {"tiles": the water tiles in order, "from"/"to": the dry banks, "open": how
## many have no deck yet} — {} if it does not reach dry land on both sides
## within `crossing_span_most` tiles.
func _line_through(tile: Vector2i, axis: Vector2i) -> Dictionary:
	var props := _construction.props()
	var at := tile
	var span := 0
	while span <= _config.crossing_span_most and _world.is_in_bounds(at) and (Crossing.is_bridge(props, at) or not _dry(at)):
		at -= axis
		span += 1
	if not _world.is_in_bounds(at) or span > _config.crossing_span_most:
		return {}
	var from := at
	var tiles: Array[Vector2i] = []
	var open := 0
	at += axis
	while tiles.size() <= _config.crossing_span_most and _world.is_in_bounds(at) and (Crossing.is_bridge(props, at) or not _dry(at)):
		tiles.append(at)
		if Crossing.deck_at(props, at) == null:
			open += 1
		at += axis
	if tiles.is_empty() or tiles.size() > _config.crossing_span_most or not _world.is_in_bounds(at):
		return {}
	return {"tiles": tiles, "from": from, "to": at, "open": open}


## Crossings closer than this (tiles) are one stretch of water's: one is enough.
const CROSSINGS_APART := 6.0
const _STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Dry ground (not water, not a wet patch).
func _dry(tile: Vector2i) -> bool:
	return _world.is_in_bounds(tile) and _world.get_water(tile) <= Pathfinder.WET_DEPTH


## Are the homes full (or is someone without a roof)?
func homes_short() -> bool:
	var places := 0
	for home_id in _settlement.start_info().hut_ids:
		places += Config.life.home_room
	var living := _settlement.member_count()
	for person in _settlement.members():
		if person.home_building_id == 0 or not _settlement.start_info().hut_ids.has(person.home_building_id):
			return true # (without a roof)
	# (Not while a home stands empty: it is there to be lived in.)
	for home_id in _settlement.start_info().hut_ids:
		if _people.living_in(home_id).is_empty():
			return false
	# A home two households share with no room left for a child.
	if _households != null and _households.mover(0, true, _settlement.id) != 0:
		return true
	# (An ambitious leader plans homes with a place more to spare, M12.5.)
	var spare := _config.homes_spare_least
	if _settlement.leader_lean(Traits.Axis.AMBITION) >= Config.governance.ambition_homes_from:
		spare += 1
	return places - living < spare


## Are the stores overflowing, or has food been going bad (and no storehouse
## for it yet — or not enough of them)?
func storage_short(now: int) -> bool:
	var stores := standing_near(PropData.Kind.STOREHOUSE).size()
	var room := _settlement.stockpile.room(&"berries")
	var spoiled := 0
	var today := Config.time.day_index(now)
	for entry: Array in _spoiled:
		if today - int(entry[0]) < _config.spoiled_days:
			spoiled += int(entry[1])
	return (room < _config.storage_room_least or spoiled >= _config.spoiled_from) and stores < 1 + _settlement.member_count() / 12


## Does it know how to make tools, and is big enough for a workshop, and has none (M12.4)?
func workshop_wanted() -> bool:
	return _settlement.knows_how(&"toolmaking") and _settlement.member_count() >= Config.trade.workshop_from \
		and standing_near(PropData.Kind.WORKSHOP).is_empty()


## What knowing something calls for (M16.3): a kiln once they make pots, a
## herb rack once they heal, a record stone once they write, a stone circle
## once they watch the sky — one of each, once there are enough of them.
const LANDMARKS := {"kiln": PropData.Kind.KILN, "herbs": PropData.Kind.HERB_RACK,
	"records": PropData.Kind.RECORD_STONE, "observatory": PropData.Kind.STONE_CIRCLE}
## How many must live here before such a thing is built.
const LANDMARK_FROM := 6


func landmark_wanted(tag: String) -> bool:
	if _settlement.member_count() < LANDMARK_FROM or not standing_near(LANDMARKS[tag]).is_empty():
		return false
	var def := _construction.buildings.with_tag(tag)
	return not def.is_empty() and def[0].tech != &"" and _settlement.knows_how(def[0].tech)


## Does a myth many of its people hold call for a shrine (and none stands)? (M17.2)
func shrine_wanted() -> bool:
	return faith != null and _settlement.member_count() >= LANDMARK_FROM \
		and not faith.shrine_myth(_settlement).is_empty() and standing_near(PropData.Kind.SHRINE).is_empty()


## Where the shrine goes: buildable ground by a sacred place of its myth (the
## nearest of them to the fire, within reach) — or, if there is none, where
## anything else would go.
func shrine_site() -> Variant:
	var fire := _settlement.fire()
	if faith == null or fire == null:
		return null
	var myth := faith.shrine_myth(_settlement)
	var graves: Array[Vector2i] = []
	for id in _construction.standing(PropData.Kind.GRAVE):
		graves.append(_settlement.props().get_prop(id).tile)
	var best: Variant = null
	var best_distance := INF
	for place: Variant in myth.get("places", []):
		if typeof(place) != TYPE_VECTOR2:
			continue
		var sacred := WorldCoords.world2d_to_tile(place)
		if Vector2(sacred - fire.tile).length() > NEAR_REACH:
			continue
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var tile := sacred + Vector2i(dx, dy)
				var distance := Vector2(dx, dy).length() + Vector2(tile - fire.tile).length() * 0.05
				if distance < best_distance and _buildable(tile, graves):
					best = tile
					best_distance = distance
	return best if best != null else site_for(_construction.buildings.get_def(&"shrine"))


## Is water to drink far from the fire (and no well yet)?
func water_far() -> bool:
	if not standing_near(PropData.Kind.WELL).is_empty():
		return false
	var fire := _settlement.fire()
	if fire == null or _settlement.places() == null:
		return false
	var water: Variant = _settlement.places().water_tile(fire.tile)
	return water == null or Vector2(water - fire.tile).length() > _config.well_from


## Is `tile` this settlement's to see to (nearer its fire than any other's,
## and within reach of it)?
func _near(tile: Vector2i) -> bool:
	var fire := _settlement.fire()
	if fire == null or Vector2(tile - fire.tile).length() > NEAR_REACH:
		return false
	var settlements := _construction.settlements
	return settlements == null or settlements.nearest(tile) == _settlement


## The buildings of a kind that are this settlement's (near its fire).
func standing_near(kind: int) -> Array[int]:
	var out: Array[int] = []
	for id in _construction.standing(kind):
		var prop := _settlement.props().get_prop(id)
		if prop != null and _near(prop.tile):
			out.append(id)
	return out


## The best ground for a building (null: none in reach).
func site_for(_def: BuildingDef) -> Variant:
	var fire := _settlement.fire()
	if fire == null or _world == null:
		return null
	var graves := _construction.standing(PropData.Kind.GRAVE)
	var grave_tiles: Array[Vector2i] = []
	for id in graves:
		grave_tiles.append(_settlement.props().get_prop(id).tile)
	var taken := {}
	for person in _people.all_people():
		taken[person.position] = true
	var best: Variant = null
	var best_cost := INF
	var reach := _config.site_farthest
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var distance := Vector2(dx, dy).length()
			if distance < _config.site_nearest or distance > _config.site_farthest:
				continue
			var tile := fire.tile + Vector2i(dx, dy)
			if taken.has(tile) or not _buildable(tile, grave_tiles):
				continue
			var cost := distance * _config.site_distance_cost + _unevenness(tile) * _config.site_unevenness_cost
			if cost < best_cost:
				if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.is_reachable(fire.tile + Vector2i(1, 0), tile):
					continue
				best_cost = cost
				best = tile
	return best


func _buildable(tile: Vector2i, graves: Array[Vector2i]) -> bool:
	if not _world.is_in_bounds(tile) or _world.get_water(tile) > 0.0:
		return false
	if _world.get_height(tile) * _world.height_step <= _settlement.flood_level + 0.01:
		return false # (where the river has been: no)
	var terrain := _world.get_terrain(tile)
	if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
		return false
	if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.can_stand(tile):
		return false
	var props := _settlement.props()
	for y in range(-_config.site_spacing, _config.site_spacing + 1):
		for x in range(-_config.site_spacing, _config.site_spacing + 1):
			var near := props.prop_at(tile + Vector2i(x, y))
			if near == null:
				continue
			if near.kind != PropData.Kind.GRAVE:
				return false # (room around it: no tree or bush grows into its walls)
	for grave in graves:
		if maxi(absi(grave.x - tile.x), absi(grave.y - tile.y)) < _config.site_grave_distance:
			return false
	# Not where the stores are kept.
	var middle := Places.middle_of(tile)
	for resource: StringName in _settlement.stockpile.amounts():
		var place := _settlement.stockpile.place(resource)
		if place != Vector2.INF and middle.distance_to(place) < 2.0:
			return false
	return true


## Height levels between the highest and the lowest of the tile and its neighbours.
func _unevenness(tile: Vector2i) -> int:
	var low := 1 << 20
	var high := -(1 << 20)
	for y in range(-1, 2):
		for x in range(-1, 2):
			var at := tile + Vector2i(x, y)
			if not _world.is_in_bounds(at):
				continue
			var h := _world.get_height(at)
			low = mini(low, h)
			high = maxi(high, h)
	return high - low


func _on_spoiled(_resource: StringName, amount: int) -> void:
	_spoiled.append([_day, amount])
	while _spoiled.size() > 64:
		_spoiled.pop_front()


func to_dict() -> Dictionary:
	return {"day": _day, "spoiled": _spoiled.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	_spoiled.clear()
	if typeof(data.get("spoiled")) == TYPE_ARRAY:
		for entry: Variant in data["spoiled"]:
			if typeof(entry) == TYPE_ARRAY and (entry as Array).size() == 2:
				_spoiled.append([int(entry[0]), int(entry[1])])
