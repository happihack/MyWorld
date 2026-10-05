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
## How many of the nearest are kept in mind, to choose those among them that
## still have something to give.
const WORK_CANDIDATES := 14
## Exploring goes this far from home (grown people / children).
const EXPLORE_MIN := 6.0
const EXPLORE_MAX := 20.0
const EXPLORE_CHILD_MAX := 8.0
const EXPLORE_TRIES := 10
## The world is remembered as visited in squares of this many tiles.
const VISIT_CELL := 4
## How much further than EXPLORE_MAX the most adventurous explore (tiles).
const ADVENTURE_REACH := 12.0

var _world: WorldData
var _props: PropRegistry
var _people: PersonRegistry
var _pathfinder: Pathfinder
var _start: WorldSetup.StartInfo
var _visited: Dictionary = {} # cell -> true
var _company_tick := -1
# The nearest places of work, remembered until the props change:
# [kind, center] -> Array of [tile, id].
var _work_places: Dictionary = {}
var _work_version := -1
## Places a walk to which was given up (no way there — across the river, before
## a crossing): tile -> the tick until which nobody is sent there again. (Owner
## saw someone set out, turn back and set out again, over and over.)
var _out_of_reach: Dictionary = {}
## A place out of reach is tried again after this long (a crossing may have
## been made) — or at once, when a building (a bridge) is finished.
const OUT_OF_REACH_MINUTES := 1440
## Nobody sets out to explore this near (tiles) to where there was no way to.
const OUT_OF_REACH_NEAR := 3
# Where water can be drunk, remembered for a while (shores move slowly).
var _shore: Array[Vector2i] = []
var _shore_tick := -1_000_000
var _shore_version := -1
## While water is moving, the shore is looked for again at most this often
## (game minutes); while it is still, never.
const SHORE_MINUTES := 120
var _up_and_about: Dictionary = {} # settlement id -> people up and about


## What everyone remembers (may be null); see feared().
var memories: MemoryStore
## What resources there are and what the nodes still hold (set by whoever
## owns the world; without them every node is as good as another).
var resources: ResourceLibrary
var nodes: ResourceNodes
## How many times as far as usual people go for berries (more than 1 when
## the settlement is short of food; see Settlement).
var forage_reach := 1.0


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
	if home == null:
		return null
	# Flooded out: where the settlement has taken refuge is home for now.
	if refuge != null and _world != null and _world.get_water(home.tile) >= Config.hydrology.flood_depth:
		return refuge
	return home.tile


## Is the person at their hut (at its door: on its tile or one beside it)
## — and is it a hut to be in (not under water)?
func is_at_home(person: PersonData) -> bool:
	var home := _props.get_prop(person.home_building_id) if _props != null else null
	if home == null or is_flooded_out(person):
		return false
	return maxi(absi(person.position.x - home.tile.x), absi(person.position.y - home.tile.y)) <= 1


## Is the person's hut under water (so that they live at the refuge for now)?
func is_flooded_out(person: PersonData) -> bool:
	var home := _props.get_prop(person.home_building_id) if _props != null else null
	return home != null and _world != null and _world.get_water(home.tile) >= Config.hydrology.flood_depth


## Where everyone whose hut is under water goes instead (dry ground near
## the settlement; the settlement says, while a flood lasts). Null: nowhere.
var refuge: Variant = null


## The middle of a tile, on the ground plane.
static func middle_of(tile: Vector2i) -> Vector2:
	return Vector2(tile) + Vector2(0.5, 0.5)


## Where the settlement keeps `resource`: a tile near the fire, one for each
## kind of thing (see ResourcesConfig.storage_offsets). Null if there is no
## settlement or nowhere to stand there.
func storage_tile(resource: StringName) -> Variant:
	var fire := _props.get_prop(_start.campfire_id) if _props != null and _start != null else null
	if fire == null:
		return null
	var def := resources.get_def(resource) if resources != null else null
	var category := def.category if def != null else ResourceDef.Category.MATERIAL
	var tile := fire.tile + Config.resources.storage_offset(category)
	if _pathfinder == null or _pathfinder.can_stand(tile):
		return tile
	var near := _pathfinder.standable_near(tile, 1)
	return near[0] if not near.is_empty() else null


## Where there is something to eat: the settlement's fire (the band's shared
## food, until there are stores — M9), or null.
func food_tile(_person: PersonData) -> Variant:
	var fire := _props.get_prop(_start.campfire_id) if _props != null and _start != null else null
	return fire.tile if fire != null else null


## The person's place at a meal: one of the tiles around the fire, always
## the same one for them (so the band sits in a ring, not on one spot). The
## fire's own tile if nobody can stand around it.
func meal_spot(person: PersonData) -> Vector2i:
	var fire: Variant = food_tile(person)
	if fire == null:
		return person.position
	var around: Array[Vector2i] = []
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
			Vector2i(0, -1), Vector2i(1, -1)]:
		var tile: Vector2i = (fire as Vector2i) + offset
		if _pathfinder.can_stand(tile) and _pathfinder.weight_at(tile) < Pathfinder.WEIGHT_OBSTACLE:
			around.append(tile)
	if around.is_empty():
		return fire
	return around[posmod(person.id, around.size())]


## A parent of the person who is up and about (the nearer one), or null.
## The grave of someone this person has lost, to go to: whoever they grieve
## for, else a parent, a partner, a child of theirs who has died.
## {"tile": Vector2i, "of": person id} — {} if there is none.
func grave_to_visit(person: PersonData) -> Dictionary:
	var archive := _people.archive
	if archive == null or archive.size() == 0:
		return {}
	var close: Array[int] = []
	var grieved := Lifecycle.grieving_for(person)
	if grieved != 0:
		close.append(grieved)
	for id in person.parents:
		close.append(id)
	for id in person.children:
		close.append(id)
	for id in close:
		var record := archive.get_record(id)
		if record != null and record.grave_id != 0 and _props.get_prop(record.grave_id) != null:
			return {"tile": record.grave_tile, "of": record.id}
	# A partner who has died (their record knows whose partner they were).
	for record in archive.all_records():
		if record.partner_id == person.id and record.grave_id != 0 and _props.get_prop(record.grave_id) != null:
			return {"tile": record.grave_tile, "of": record.id}
	return {}


func parent_about(person: PersonData) -> PersonData:
	var best: PersonData = null
	var best_distance := INF
	for id in person.parents:
		var parent := _people.get_person(id)
		if parent == null or parent.has_flag(PersonData.FLAG_INDOORS) or parent.pose == PersonData.Pose.SLEEP:
			continue
		var distance := parent.world2d().distance_squared_to(person.world2d())
		if distance < best_distance:
			best_distance = distance
			best = parent
	return best


## The nearest water to drink from (a tile of water with dry land beside it),
## or null.
func water_tile(from: Vector2i, now: int = -1) -> Variant:
	if _shore_version != _pathfinder.version and (now < 0 or now - _shore_tick >= SHORE_MINUTES or _shore_version < 0):
		_shore = _pathfinder.shore_tiles()
		_shore_tick = now
		_shore_version = _pathfinder.version
	var best: Variant = null
	var best_distance := float(WATER_RADIUS * WATER_RADIUS)
	for tile in _shore:
		var distance := float((tile - from).length_squared())
		if distance < best_distance:
			best = tile
			best_distance = distance
	# A well is water too (M12.1).
	if _props != null:
		for prop in _props.all_props():
			if prop.kind == PropData.Kind.WELL:
				var distance := float((prop.tile - from).length_squared())
				if distance < best_distance:
					best = prop.tile
					best_distance = distance
	return best


## The nearest bank to `from` where one can stand and fish: a dry tile beside
## water (not a well). Null: none within reach of the water.
func fishing_bank(from: Vector2i) -> Variant:
	if _pathfinder == null or not _pathfinder.is_bound():
		return null
	var best: Variant = null
	var best_distance := float(WATER_RADIUS * WATER_RADIUS)
	for water in _pathfinder.shore_tiles():
		var distance := float((water - from).length_squared())
		if distance >= best_distance:
			continue
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var bank := water + step
			if _pathfinder.can_stand(bank) and _world.get_water(bank) <= 0.0 and not near_out_of_reach(bank, 1):
				best = bank
				best_distance = distance
				break
	return best


## Where a fisher fishes (M19.5): from the end of the settlement's landing, if
## one stands near (from its boat), else from the bank nearest home.
## {"stand": Vector2i, "at": Vector2i (the water), "landing": prop id (0: the bank)} — {} if nowhere.
func fishing_spot(person: PersonData) -> Dictionary:
	var home: Variant = home_tile(person)
	var center: Vector2i = home if home != null else person.position
	if _props != null:
		var nearest: PropData = null
		for prop in _props.all_props():
			if prop.kind == PropData.Kind.LANDING and Vector2(prop.tile - center).length() <= WORK_RADIUS * 1.5 \
					and (nearest == null or (prop.tile - center).length_squared() < (nearest.tile - center).length_squared()):
				nearest = prop
		if nearest != null and not near_out_of_reach(nearest.tile, 0):
			return {"stand": nearest.tile, "at": water_beside(nearest.tile, nearest.tile), "landing": nearest.id}
	var bank: Variant = fishing_bank(center)
	if bank == null:
		return {}
	return {"stand": bank, "at": water_beside(bank, bank), "landing": 0}


## A water tile beside `tile` (`tile` itself if none).
func water_beside(tile: Vector2i, fallback: Vector2i) -> Vector2i:
	for step: Vector2i in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		if _world.get_water(tile + step) > 0.0:
			return tile + step
	return fallback


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
		&"rock":
			return _nearest_prop(person, PropData.Kind.ROCK, rng)
	return {}


## A bush with berries on it, near home: where someone goes to eat when the
## stores are empty. {} if there is none.
func forage_place(person: PersonData, rng: RandomNumberGenerator) -> Dictionary:
	return _nearest_prop(person, PropData.Kind.BUSH, rng, true) if _start != null and nodes != null else {}


## Is there anything to eat for this person: food in the settlement's
## stores, or failing that berries on a bush?
func has_food(person: PersonData, settlement: Settlement) -> bool:
	if settlement == null:
		return food_tile(person) != null
	return person.food_in_hand > 0.0 or (settlement.stockpile.food_units() > 0 and settlement.serves(person.id)) \
		or not forage_place(person, null).is_empty()


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
	if relationships == null:
		return others[rng.randi_range(0, mini(others.size(), 3) - 1)]
	# Of the nearest few, the ones they like: friends and family more, rivals not
	# at all (unless there is nobody else).
	var near := others.slice(0, mini(others.size(), COMPANY_CHOICES))
	# Someone free to court is sought out wherever they are (M10.2).
	for other in others.slice(COMPANY_CHOICES):
		if _courting(person, other):
			near.append(other)
	var weights := PackedFloat32Array()
	var total := 0.0
	for other: PersonData in near:
		var kinds := relationships.kinds(person.id, other.id)
		var weight := 0.0
		if kinds & (Relationship.Kind.RIVAL | Relationship.Kind.ENEMY) == 0:
			weight = exp(2.0 * relationships.affinity(person.id, other.id)) * (1.5 if relationships.is_family(person.id, other.id) else 1.0)
			if _courting(person, other):
				weight *= 1.0 + COURTING * SocialActs.chemistry(person, other)
		weights.append(weight)
		total += weight
	if total <= 0.0:
		return near[0]
	var roll := rng.randf() * total
	for i in near.size():
		roll -= weights[i]
		if roll <= 0.0:
			return near[i]
	return near[-1]


## How many of the nearest are thought of when looking for company.
const COMPANY_CHOICES := 5
## How much more someone free to court is sought out (× how drawn to them).
const COURTING := 3.0
## The clock (may be null: then nobody courts).
var clock: GameClock


## Two grown-ups, both free, of either sex to the other, not kin: they may
## become partners (see Lifecycle), so they seek each other out.
func _courting(person: PersonData, other: PersonData) -> bool:
	if clock == null or relationships == null or person.partner_id != 0 or other.partner_id != 0 or person.sex == other.sex:
		return false
	var year := Config.time.ticks_per_year()
	if person.life_stage(clock.tick, year, Config.people) != PersonData.LifeStage.ADULT \
			or other.life_stage(clock.tick, year, Config.people) != PersonData.LifeStage.ADULT:
		return false
	return not relationships.is_family(person.id, other.id) and not relationships.close_kin(person.id, other.id)
## What people are to each other (may be null: then the nearest few, at random).
var relationships: RelationshipStore


## Is anyone of the person's settlement (other than themselves) up and
## about? Counted once per tick and settlement (`now`: the tick), since
## everyone who decides anything asks.
func has_company(person: PersonData, now: int = -1) -> bool:
	if now < 0 or now != _company_tick:
		_company_tick = now
		_up_and_about.clear()
		for other in _people.everyone():
			if not other.has_flag(PersonData.FLAG_INDOORS) and other.pose != PersonData.Pose.SLEEP:
				_up_and_about[other.settlement_id] = int(_up_and_about.get(other.settlement_id, 0)) + 1
	var up := int(_up_and_about.get(person.settlement_id, 0))
	var me := 0 if person.has_flag(PersonData.FLAG_INDOORS) or person.pose == PersonData.Pose.SLEEP else 1
	return up - me > 0


## Somewhere to go and look: a tile away from home that can be stood on,
## preferably where nobody of the band has been. Null if none was found.
## (Whether there is a way there is found out by setting off: asking the
## pathfinder for every candidate would cost more than a frame can spare.)
func explore_tile(person: PersonData, stage: PersonData.LifeStage, rng: RandomNumberGenerator) -> Variant:
	var home: Variant = home_tile(person)
	var center: Vector2i = home if home != null else person.position
	var farthest := EXPLORE_CHILD_MAX if stage == PersonData.LifeStage.CHILD else EXPLORE_MAX + scouting
	# The adventurous go further (M13.4: to the frontier, and some to the Edge) —
	# setting out in the morning, to be back by dark (with any child who keeps them company).
	var morning := clock == null or Config.time.minute_of_day(clock.tick) < 12 * 60
	if stage != PersonData.LifeStage.CHILD and morning:
		farthest += ADVENTURE_REACH * clampf(Traits.value(person.traits, Traits.Axis.ADVENTURE), 0.0, 1.0)
	var nearest := minf(EXPLORE_MIN, farthest * 0.5)
	var fallback: Variant = null
	for attempt in EXPLORE_TRIES:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(nearest, farthest)
		var tile := center + Vector2i(roundi(cos(angle) * distance), roundi(sin(angle) * distance))
		if not _pathfinder.can_stand(tile) or _world.get_water(tile) > Pathfinder.WET_DEPTH \
				or _pathfinder.weight_at(tile) >= Pathfinder.WEIGHT_OBSTACLE:
			continue
		if feared(person, tile):
			continue # not there again
		if near_out_of_reach(tile, OUT_OF_REACH_NEAR):
			continue # (no way over there just now: across the river, before a crossing)
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


## What has been explored is known to every settlement alike (M12.3: those
## who set out knew the land): this one shares `other`'s record of it.
func share_visited(other: Places) -> void:
	_visited = other._visited


## How much further than usual the grown explore (M12: a settlement that
## wants to send people out, and knows of nowhere for them, scouts).
var scouting := 0.0


## Remembers that someone of the band has been around `tile`.
func mark_visited(tile: Vector2i) -> void:
	_visited[_cell(tile)] = true


func was_visited(tile: Vector2i) -> bool:
	return _visited.has(_cell(tile))


func visited_count() -> int:
	return _visited.size()


## The squares the band has been to, sorted (for saving).
func visited_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in _visited:
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


## Restores visited_cells() output (anything else in the list is ignored).
func set_visited_cells(cells: Array) -> void:
	_visited.clear()
	for cell: Variant in cells:
		if typeof(cell) == TYPE_VECTOR2I:
			_visited[cell] = true


func _cell(tile: Vector2i) -> Vector2i:
	return cell_of(tile)


## The square (of VISIT_CELL tiles) `tile` is in.
static func cell_of(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / VISIT_CELL), floori(float(tile.y) / VISIT_CELL))


## One of the props of `kind` nearest to the person's home (and so to the
## settlement: work is done near home), chosen by the dice among the nearest few.
## `only_giving`: nothing rather than one that has nothing to take.
func _nearest_prop(person: PersonData, kind: PropData.Kind, rng: RandomNumberGenerator, only_giving: bool = false) -> Dictionary:
	var home: Variant = home_tile(person)
	var center: Vector2i = home if home != null else person.position
	if _work_version != _props.version:
		_work_version = _props.version
		_work_places.clear()
	# Short of food, people go further for berries (and have more bushes to choose from).
	var further := forage_reach if kind == PropData.Kind.BUSH else 1.0
	var radius := WORK_RADIUS * further
	var key := [kind, center, further]
	if not _work_places.has(key):
		var found: Array[PropData] = []
		for prop in _props.all_props():
			if prop.kind == kind and Vector2(prop.tile - center).length() <= radius \
					and _world.get_water(prop.tile) <= Pathfinder.WET_DEPTH:
				found.append(prop)
		found.sort_custom(func(a: PropData, b: PropData) -> bool:
			var da := (a.tile - center).length_squared()
			var db := (b.tile - center).length_squared()
			return da < db or (da == db and a.id < b.id))
		var nearest: Array = []
		for prop in found:
			nearest.append([prop.tile, prop.id])
		_work_places[key] = nearest
	var places: Array = _work_places[key]
	# Not where there turned out to be no way to (while that holds): the nearest
	# that can be got to instead.
	if not _out_of_reach.is_empty() and clock != null:
		var reachable: Array = []
		for place: Array in places:
			if int(_out_of_reach.get(place[0], -1)) <= clock.tick:
				reachable.append(place)
		places = reachable
	# (Going further, every bush within reach is one to go to.)
	if further <= 1.0:
		places = places.slice(0, WORK_CANDIDATES)
	if places.is_empty():
		return {}
	# Where there is still something to take, if there is such a place among
	# them; the nearest few of those.
	if nodes != null:
		var giving: Array = []
		var begun: Array = []
		var laden: Array = []
		for place: Array in places:
			var prop := _props.get_prop(place[1])
			var there := nodes.available(prop)
			if there > 0:
				giving.append(place)
				# A tree somebody has begun to cut is cut down before the next
				# one is begun; a bush is worth the walk when it has berries
				# enough on it (a nearly bare one only if there are no others).
				if kind == PropData.Kind.TREE and prop.stock >= 0:
					begun.append(place)
				elif kind == PropData.Kind.BUSH and there >= nodes.capacity(prop) * Config.resources.worth_picking_from:
					laden.append(place)
					if laden.size() >= WORK_CHOICES:
						break # (the nearest few are found: no need to look at the rest)
		if not begun.is_empty():
			places = begun
		elif not laden.is_empty():
			places = laden
		elif not giving.is_empty():
			places = giving
		elif only_giving:
			return {}
	places = places.slice(0, WORK_CHOICES)
	# Not where something frightening happened, if there is anywhere else.
	if memories != null and not person.memory_ids.is_empty():
		var calm: Array = []
		for place: Array in places:
			if not feared(person, place[0]):
				calm.append(place)
		if not calm.is_empty():
			places = calm
	var chosen: Array = places[rng.randi_range(0, places.size() - 1) if rng != null else 0]
	return {"tile": chosen[0], "id": chosen[1]}


## There was no way to `tile`: nobody is sent there again for a while.
func note_out_of_reach(tile: Vector2i) -> void:
	if clock == null:
		return
	_out_of_reach[tile] = clock.tick + OUT_OF_REACH_MINUTES
	# (Old notes are let go of as they run out.)
	for old: Vector2i in _out_of_reach.keys():
		if int(_out_of_reach[old]) <= clock.tick:
			_out_of_reach.erase(old)


func is_out_of_reach(tile: Vector2i) -> bool:
	return clock != null and int(_out_of_reach.get(tile, -1)) > clock.tick


## Is `tile` within `reach` tiles of somewhere there was no way to (and still is not)?
func near_out_of_reach(tile: Vector2i, reach: int) -> bool:
	if clock == null or _out_of_reach.is_empty():
		return false
	for other: Vector2i in _out_of_reach:
		if maxi(absi(other.x - tile.x), absi(other.y - tile.y)) <= reach and int(_out_of_reach[other]) > clock.tick:
			return true
	return false


## Something was built (a bridge): every way is worth trying again.
func forget_out_of_reach() -> void:
	_out_of_reach.clear()


## Does the person keep away from this place, for what they remember of it?
func feared(person: PersonData, tile: Vector2i) -> bool:
	return memories != null and memories.fear_at(person, Vector2(tile) + Vector2(0.5, 0.5)) > Config.memory.avoid_from
