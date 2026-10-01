class_name Places
extends RefCounted
## Where things are, as far as people's plans are concerned: food, water,
## home, work, company, somewhere new. Every question is answered from the
## world as it is at that moment (a band asks a few times a minute; nothing
## here is worth caching and then keeping right).

## How far (tiles) water and work are looked for.
const WATER_RADIUS := 26
const WORK_RADIUS := 16.0
## Work is done at one of the nearest few places, not always the very nearest.
const WORK_CHOICES := 5
## Exploring goes this far from home (grown people / children).
const EXPLORE_MIN := 6.0
const EXPLORE_MAX := 20.0
const EXPLORE_CHILD_MAX := 8.0
const EXPLORE_TRIES := 10
## The world is remembered as visited in squares of this many tiles.
const VISIT_CELL := 4

var _world: WorldData
var _props: PropRegistry
var _people: PersonRegistry
var _pathfinder: Pathfinder
var _start: WorldSetup.StartInfo
var _visited: Dictionary = {} # cell -> true


func _init(world: WorldData, props: PropRegistry, people: PersonRegistry, pathfinder: Pathfinder,
		start: WorldSetup.StartInfo) -> void:
	_world = world
	_props = props
	_people = people
	_pathfinder = pathfinder
	_start = start


## The tile of the person's home, or null if they have none.
func home_tile(person: PersonData) -> Variant:
	var home := _props.get_prop(person.home_building_id) if _props != null else null
	return home.tile if home != null else null


## Where there is something to eat: the settlement's fire (the band's shared
## food, until there are stores — M9), or null.
func food_tile(_person: PersonData) -> Variant:
	var fire := _props.get_prop(_start.campfire_id) if _props != null and _start != null else null
	return fire.tile if fire != null else null


## The nearest water to drink from (a tile of water with dry land beside it),
## or null.
func water_tile(from: Vector2i) -> Variant:
	var best: Variant = null
	var best_distance := INF
	var bounds := _world.bounds
	for y in range(maxi(from.y - WATER_RADIUS, bounds.position.y), mini(from.y + WATER_RADIUS + 1, bounds.end.y)):
		for x in range(maxi(from.x - WATER_RADIUS, bounds.position.x), mini(from.x + WATER_RADIUS + 1, bounds.end.x)):
			var tile := Vector2i(x, y)
			var distance := float((tile - from).length_squared())
			if distance >= best_distance or _world.get_water(tile) < Pathfinder.WET_DEPTH * 3.0:
				continue
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if _pathfinder.can_stand(tile + offset) and _world.get_water(tile + offset) <= Pathfinder.WET_DEPTH:
					best = tile
					best_distance = distance
					break
	return best


## Where the person's work is: {"tile": Vector2i, "id": int} or {} if there is
## none. `target` is OccupationDef.work_target.
func work_place(person: PersonData, target: StringName, rng: RandomNumberGenerator) -> Dictionary:
	if _start == null:
		return {}
	match target:
		&"fire":
			var fire := _props.get_prop(_start.campfire_id)
			return {"tile": fire.tile, "id": fire.id} if fire != null else {}
		&"tree":
			return _nearest_prop(person, PropData.Kind.TREE, rng)
		&"bush":
			return _nearest_prop(person, PropData.Kind.BUSH, rng)
	return {}


## Someone to talk to: a person of the same settlement who is up and about,
## one of the nearest few. Null if there is nobody.
func company(person: PersonData, rng: RandomNumberGenerator) -> PersonData:
	var others: Array[PersonData] = []
	for other in _people.in_settlement(person.settlement_id):
		if other.id != person.id and not other.has_flag(PersonData.FLAG_INDOORS) and other.pose != PersonData.Pose.SLEEP:
			others.append(other)
	if others.is_empty():
		return null
	var from := person.world2d()
	others.sort_custom(func(a: PersonData, b: PersonData) -> bool:
		var da := a.world2d().distance_squared_to(from)
		var db := b.world2d().distance_squared_to(from)
		return da < db or (da == db and a.id < b.id))
	return others[rng.randi_range(0, mini(others.size(), 3) - 1)]


func has_company(person: PersonData) -> bool:
	for other in _people.in_settlement(person.settlement_id):
		if other.id != person.id and not other.has_flag(PersonData.FLAG_INDOORS) and other.pose != PersonData.Pose.SLEEP:
			return true
	return false


## Somewhere to go and look: a tile away from home that can be stood on,
## preferably where nobody of the band has been. Null if none was found.
func explore_tile(person: PersonData, stage: PersonData.LifeStage, rng: RandomNumberGenerator) -> Variant:
	var home: Variant = home_tile(person)
	var center: Vector2i = home if home != null else person.position
	var farthest := EXPLORE_CHILD_MAX if stage == PersonData.LifeStage.CHILD else EXPLORE_MAX
	var nearest := minf(EXPLORE_MIN, farthest * 0.5)
	var fallback: Variant = null
	for attempt in EXPLORE_TRIES:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(nearest, farthest)
		var tile := center + Vector2i(roundi(cos(angle) * distance), roundi(sin(angle) * distance))
		if not _pathfinder.can_stand(tile) or _world.get_water(tile) > Pathfinder.WET_DEPTH \
				or _pathfinder.weight_at(tile) >= Pathfinder.WEIGHT_OBSTACLE \
				or not _pathfinder.is_reachable(person.position, tile):
			continue
		if not was_visited(tile):
			return tile
		if fallback == null:
			fallback = tile
	return fallback


## Somewhere near home to play: a tile that can be stood on, a few steps
## from the door. Null if there is none.
func play_tile(person: PersonData, rng: RandomNumberGenerator) -> Variant:
	var home: Variant = home_tile(person)
	var center: Vector2i = home if home != null else person.position
	var spots := _pathfinder.standable_near(center + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4)), 1, 3)
	return spots[0] if not spots.is_empty() else null


## Remembers that someone of the band has been around `tile`.
func mark_visited(tile: Vector2i) -> void:
	_visited[_cell(tile)] = true


func was_visited(tile: Vector2i) -> bool:
	return _visited.has(_cell(tile))


func visited_count() -> int:
	return _visited.size()


func _cell(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / VISIT_CELL), floori(float(tile.y) / VISIT_CELL))


## One of the props of `kind` nearest to the person's home (and so to the
## settlement: work is done near home), chosen by the dice among the nearest few.
func _nearest_prop(person: PersonData, kind: PropData.Kind, rng: RandomNumberGenerator) -> Dictionary:
	var home: Variant = home_tile(person)
	var center: Vector2i = home if home != null else person.position
	var found: Array[PropData] = []
	for prop in _props.all_props():
		if prop.kind == kind and Vector2(prop.tile - center).length() <= WORK_RADIUS \
				and _world.get_water(prop.tile) <= Pathfinder.WET_DEPTH:
			found.append(prop)
	if found.is_empty():
		return {}
	found.sort_custom(func(a: PropData, b: PropData) -> bool:
		var da := (a.tile - center).length_squared()
		var db := (b.tile - center).length_squared()
		return da < db or (da == db and a.id < b.id))
	var chosen := found[rng.randi_range(0, mini(found.size(), WORK_CHOICES) - 1)]
	return {"tile": chosen.tile, "id": chosen.id}
