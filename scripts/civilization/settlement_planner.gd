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
##   a ford waded often                       → a bridge (M12.2)
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
## What is further than this from the fire is not this settlement's to build or keep.
const NEAR_REACH := 16.0
var _world: WorldData
var _pathfinder: Pathfinder
var _config: ConstructionConfig
var _day := -1_000_000
var _spoiled: Array = [] # [day, units]


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
			var ford: Variant = _traffic.ford_for_bridge()
			if ford != null and _near(ford):
				return _construction.start(def[0].id, ford, now, bridge_turn(ford), _settlement.id)
			continue
		var site: Variant = site_for(def[0])
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
	if _traffic != null and _traffic.ford_for_bridge() != null and _near(_traffic.ford_for_bridge()):
		out.append(&"bridge")
	return out


## Which way a bridge on `ford` runs: across the water, the shorter way to
## dry land on both sides (0: north–south; 64: east–west).
func bridge_turn(ford: Vector2i) -> int:
	var across_x := _water_run(ford, Vector2i(1, 0)) + _water_run(ford, Vector2i(-1, 0))
	var across_y := _water_run(ford, Vector2i(0, 1)) + _water_run(ford, Vector2i(0, -1))
	return 64 if across_x < across_y else 0


## Tiles of water from `tile` (not counted) in direction `step` before dry land (at most 16).
func _water_run(tile: Vector2i, step: Vector2i) -> int:
	var run := 0
	var at := tile + step
	while run < 16 and _world.is_in_bounds(at) and _world.get_water(at) > 0.0:
		run += 1
		at += step
	return run


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
	return places - living < _config.homes_spare_least


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
