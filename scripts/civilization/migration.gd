class_name Migration
extends RefCounted
## Migration and the founding of new settlements (bible §17.1, M12.3).
##
## Once a game day (mid-morning) each settlement weighs what would drive
## people away: crowding under its roofs, hunger, strife between its people,
## floods lived through — and how adventurous its households are. When that
## weighs enough, by the dice, a group sets out: one household or two, with a
## man and a woman grown among them, leaving enough behind. They go to the
## best place **someone has explored** (Places.visited_cells): open, dry,
## even ground above the remembered water, with water and trees near, well
## away from every settlement and not too far. They walk there (nothing else
## takes their attention on the way); there they found a settlement: a fire,
## a first shelter put up from the wood they carried, the food they brought.
## It is a settlement like the first — its own stores, jobs, plans — and its
## founder is remembered (the chronicle: "… has founded Ama's camp").

## People have set out (the journey record: see `journeys`).
signal set_out(journey: Dictionary)
## A new settlement has been founded at the end of a journey.
signal founded(settlement: Settlement, journey: Dictionary)
## A settlement founded since the first has nobody left: it is abandoned (M12.5).
signal abandoned(settlement_id: int, name: String, at: Vector2i)

const ACTIVITY := &"migrate"
## Hut places around a new fire, the nearest first.
const HUT_RING: Array[Vector2i] = [Vector2i(0, -2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0),
	Vector2i(2, -2), Vector2i(2, 2), Vector2i(-2, 2), Vector2i(-2, -2)]

var settlements: Settlements
var people: PersonRegistry
var households: Households
var relationships: RelationshipStore
var props: PropRegistry
var world: WorldData
var pathfinder: Pathfinder
var ids: IdAllocator
var events: EventLog
var behavior: BehaviorSystem
## (info: WorldSetup.StartInfo) -> Settlement: adds a settlement to the world (WorldSession.add_settlement).
var add_settlement: Callable
var rng: RandomNumberGenerator
var config: MigrationConfig

## Journeys under way: {"id", "from", "to": Vector2i, "members": [ids], "households": [ids],
## "leader", "started", "goods": {resource -> units}, "causes": [event ids], "event": event id}.
var journeys: Array[Dictionary] = []
var _rested: Dictionary = {} # settlement id -> the day people last set out from it
var _day := -1_000_000
var _next_id := 1
## For the soak: how many have set out, and settlements founded.
var departures := 0
var foundings := 0
var abandonments := 0


func bind(now: int, cfg: MigrationConfig = null) -> void:
	config = cfg if cfg != null else Config.migration
	journeys.clear()
	_rested.clear()
	_day = Config.time.day_index(now)
	_next_id = 1
	departures = 0
	foundings = 0


## Is the person on their way to new land?
func travelling(person_id: int) -> bool:
	for journey in journeys:
		if (journey["members"] as Array).has(person_id):
			return true
	return false


## Once a day (mid-morning): does anyone set out? And always: have those under
## way arrived?
func advance_to(now: int) -> void:
	if settlements == null or config == null:
		return
	_follow_journeys(now)
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day or Config.time.minute_of_day(now) < 10 * 60:
		return
	_day = today
	_abandon_empty()
	for own in settlements.all().duplicate():
		if settlements.size() + journeys.size() >= config.most_settlements:
			return
		var push := pressure(own, now)
		if float(push["total"]) < config.leave_from:
			continue
		if rng != null and rng.randf() >= config.chance_per_day * float(push["total"]):
			continue
		depart(own, now, push)


## What drives people away from `own` now: {"total", "crowding", "scarcity",
## "conflict", "disaster", "adventure", "causes": [event ids]} (total 0 when
## it is too small, or rests after the last who set out, or has nobody to send).
func pressure(own: Settlement, now: int) -> Dictionary:
	var out := {"total": 0.0, "crowding": 0.0, "scarcity": 0.0, "conflict": 0.0, "disaster": 0.0, "adventure": 0.0, "causes": []}
	var members := own.members()
	if members.size() < config.least_people:
		return out
	var today := Config.time.day_index(now)
	if _rested.has(own.id) and today - int(_rested[own.id]) < config.rest_days:
		return out
	if _going_from(own.id):
		return out
	var causes: Array = []
	# Crowding: few places left under the roofs.
	var places := own.start_info().hut_ids.size() * Config.life.home_room
	var spare := places - members.size()
	if spare <= config.crowded_from_spare:
		out["crowding"] = config.crowding * clampf(float(config.crowded_from_spare - spare + 1) / float(config.crowded_from_spare + 1), 0.0, 1.0)
	# Hunger, days on end.
	if own.shortage != Settlement.Shortage.NONE and own.short_since() >= 0 and now - own.short_since() >= config.scarce_days * TimeConfig.MINUTES_PER_DAY:
		out["scarcity"] = config.scarcity
		_cause(causes, &"food_shortage")
	# Strife: rivals and enemies among them.
	if relationships != null:
		var pairs := 0
		var ids_here := {}
		for person in members:
			ids_here[person.id] = true
		for person in members:
			var known: Dictionary = relationships.of(person.id)
			for other_id: int in known:
				if other_id > person.id and ids_here.has(other_id):
					var record: Relationship = known[other_id]
					if record.has_kind(Relationship.Kind.RIVAL) or record.has_kind(Relationship.Kind.ENEMY):
						pairs += 1
		out["conflict"] = minf(pairs * config.conflict_per_pair, config.conflict_most)
		if pairs > 0:
			_cause(causes, &"became_enemies")
	# Floods lived through lately.
	if events != null:
		var floods := 0
		for event in events.of_type(&"flood"):
			if now - event.tick <= config.disaster_days * TimeConfig.MINUTES_PER_DAY:
				floods += 1
		out["disaster"] = floods * config.disaster_per_flood
		if floods > 0:
			_cause(causes, &"flood")
	# The adventurous.
	var group := choose_group(own, now)
	if group.is_empty():
		return out
	out["adventure"] = config.adventure * float(group["adventure"])
	out["causes"] = causes
	out["total"] = float(out["crowding"]) + float(out["scarcity"]) + float(out["conflict"]) + float(out["disaster"]) + float(out["adventure"])
	return out


## Who would go from `own`: {"households": [ids], "members": [ids], "leader",
## "adventure": 0 … 1} — the most adventurous households, one or two, with a
## man and a woman grown among them, leaving at least `stay_least` behind ({}: nobody).
func choose_group(own: Settlement, now: int) -> Dictionary:
	var by_household: Dictionary = own.households()
	var scored: Array = [] # [score, household id, adventure]
	for household_id: int in by_household:
		if household_id <= 0:
			continue
		var adults := 0
		var adventure := 0.0
		for id: int in by_household[household_id]:
			var person := people.get_person(id)
			if person != null and _grown(person, now):
				adults += 1
				adventure += Traits.value(person.traits, Traits.Axis.ADVENTURE)
		if adults == 0:
			continue
		var mean := clampf(adventure / adults, -1.0, 1.0)
		scored.append([mean, household_id])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var total := own.member_count()
	var chosen: Array[int] = []
	var going: Array[int] = []
	var adventure := 0.0
	for entry: Array in scored:
		if chosen.size() >= config.most_households:
			break
		var household: PackedInt64Array = by_household[entry[1]]
		if total - going.size() - household.size() < config.stay_least:
			continue
		chosen.append(entry[1])
		for id in household:
			going.append(id)
		adventure = maxf(adventure, (float(entry[0]) + 1.0) * 0.5)
		if _has_couple(going, now) and going.size() >= config.group_least:
			break
	if chosen.is_empty() or going.size() < config.group_least or not _has_couple(going, now):
		return {}
	# The leader: the most adventurous grown one.
	var leader := 0
	var most := -INF
	for id in going:
		var person := people.get_person(id)
		if person != null and _grown(person, now) and Traits.value(person.traits, Traits.Axis.ADVENTURE) > most:
			most = Traits.value(person.traits, Traits.Axis.ADVENTURE)
			leader = id
	return {"households": chosen, "members": going, "leader": leader, "adventure": adventure}


## The best place someone of `own` has explored to found a settlement (null: none).
func destination(own: Settlement) -> Variant:
	var places := own.places()
	if places == null or world == null:
		return null
	var origin := own.start_info().settlement_tile
	var fires := settlements.fire_tiles()
	var inner := world.bounds.grow(-3)
	var best: Variant = null
	var best_score := -INF
	var cells := places.visited_cells()
	cells.sort()
	for cell in cells:
		var tile := cell * Places.VISIT_CELL + Vector2i(Places.VISIT_CELL / 2, Places.VISIT_CELL / 2)
		if not inner.has_point(tile):
			continue
		var journey := Vector2(tile - origin).length()
		if journey > config.farthest_journey:
			continue
		var crowded := false
		for fire in fires:
			if Vector2(tile - fire).length() < config.nearest_settlement:
				crowded = true
				break
		if crowded:
			continue
		var score: Variant = site_score(tile, own)
		if score == null:
			continue
		score = float(score) - journey * 0.2
		if score > best_score:
			best_score = score
			best = tile
	return best


## How good `tile` is to settle at (null: not at all): even, dry, open ground
## above the water `own` remembers, water near but not on the bank, trees near.
func site_score(tile: Vector2i, own: Settlement) -> Variant:
	if not WorldSetup._is_flat_dry_square(world, tile, 1):
		return null
	var terrain := world.get_terrain(tile)
	if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
		return null
	if props.prop_at(tile) != null or (pathfinder != null and not pathfinder.can_stand(tile)):
		return null
	if world.get_height(tile) * world.height_step <= own.flood_level + 0.01:
		return null
	if pathfinder != null and not pathfinder.is_reachable(own.start_info().settlement_tile + Vector2i(1, 0), tile):
		return null
	# Water near (not on the bank).
	var water := INF
	var reach := ceili(config.water_within)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var at := tile + Vector2i(dx, dy)
			if world.is_in_bounds(at) and world.get_water(at) > Pathfinder.WET_DEPTH:
				water = minf(water, Vector2(dx, dy).length())
	if water > config.water_within or water < 2.5:
		return null
	var trees := 0
	for dy in range(-config.tree_reach, config.tree_reach + 1):
		for dx in range(-config.tree_reach, config.tree_reach + 1):
			var prop := props.prop_at(tile + Vector2i(dx, dy))
			if prop != null and prop.kind == PropData.Kind.TREE:
				trees += 1
	var fertility := float(world.chunk_at_tile(tile).fertility[world.index_at_tile(tile)])
	return minf(trees, 20) * 2.0 + fertility / 40.0 - absf(water - 5.0) * 2.0


## A group sets out from `own` (now, whatever the dice): returns the journey ({}: nobody can, or nowhere to go).
func depart(own: Settlement, now: int, push: Dictionary = {}) -> Dictionary:
	var group := choose_group(own, now)
	if group.is_empty():
		return {}
	var to: Variant = destination(own)
	if to == null:
		return {}
	# What they take with them.
	var goods := {}
	var going: Array = group["members"]
	var food_units := ceili(own.food_need_per_day() / maxf(own.member_count(), 1) * going.size() * config.food_days)
	var wanted := mini(food_units, floori(own.stockpile.food_units() * config.food_share))
	var food_taken := 0
	while food_taken < wanted:
		var kind := own.stockpile.take_food()
		if kind == &"":
			break
		goods[String(kind)] = int(goods.get(String(kind), 0)) + 1
		food_taken += 1
	var wood := own.stockpile.take(&"wood", mini(config.wood, own.stockpile.available(&"wood")))
	if wood > 0:
		goods["wood"] = wood
	var journey := {"id": _next_id, "from": own.id, "to": to, "members": going.duplicate(), "households": group["households"],
		"leader": group["leader"], "started": now, "goods": goods, "causes": push.get("causes", []), "event": 0}
	_next_id += 1
	journeys.append(journey)
	_rested[own.id] = Config.time.day_index(now)
	departures += 1
	# Off they go (everything else waits until they are there).
	var spots := pathfinder.standable_near(to, going.size(), 3) if pathfinder != null else []
	for i in going.size():
		var person := people.get_person(going[i])
		if person == null:
			continue
		var spot: Vector2i = spots[i % spots.size()] if not spots.is_empty() else to
		if behavior != null:
			behavior.set_plan(person, ACTIVITY, ACTIVITY, [WalkToStep.make(spot, person.sub_tile_offset)])
	set_out.emit(journey)
	return journey


## The journeys under way: the dead are no longer of them; those who are
## there (or have been on the way too long) found their settlement.
func _follow_journeys(now: int) -> void:
	for journey in journeys.duplicate():
		var members: Array = journey["members"]
		for id: int in members.duplicate():
			if people.get_person(id) == null:
				members.erase(id)
		if members.is_empty():
			journeys.erase(journey)
			continue
		var to: Vector2i = journey["to"]
		var there := 0
		var walking := 0
		for id: int in members:
			var person := people.get_person(id)
			if Vector2(person.position - to).length() <= 3.5:
				there += 1
			elif BehaviorSystem.activity_of(person) == ACTIVITY:
				walking += 1
		if there == members.size() or (there > 0 and walking == 0) or now - int(journey["started"]) >= config.longest_journey:
			found(journey, now)


## Founds the settlement at the end of a journey: the fire, a first shelter
## from the wood they carried, the food they brought; they are its people now.
func found(journey: Dictionary, now: int) -> Settlement:
	journeys.erase(journey)
	var members: Array = journey["members"]
	var leader := people.get_person(int(journey["leader"]))
	if leader == null and not members.is_empty():
		leader = people.get_person(members[0])
	var to: Vector2i = journey["to"]
	# Where they stand now, if the place itself has been taken meanwhile.
	if props.prop_at(to) != null and leader != null:
		to = leader.position
	if props.prop_at(to) != null:
		return null
	var info := WorldSetup.StartInfo.new()
	info.ok = true
	info.settlement_tile = to
	info.settlement_id = ids.next_id()
	var fire := PropData.new()
	fire.id = ids.next_id()
	fire.kind = PropData.Kind.CAMPFIRE
	fire.tile = to
	props.add(fire)
	info.campfire_id = fire.id
	var goods: Dictionary = journey["goods"]
	var hut := _first_shelter(to)
	if hut != null:
		info.hut_ids.append(hut.id)
		goods["wood"] = maxi(int(goods.get("wood", 0)) - 12, 0)
	var own: Settlement = add_settlement.call(info)
	own.settlement_name = "%s's camp" % (leader.given_name if leader != null else "Someone")
	own.founded_tick = now
	own.founded_from = int(journey["from"])
	var origin := settlements.get_settlement(int(journey["from"]))
	if origin != null:
		own.knows = origin.knows.duplicate() # (what they knew, they know there too)
	for id: int in members:
		own.founders.append(id)
	for id: int in members:
		var person := people.get_person(id)
		person.settlement_id = own.id
		if behavior != null and BehaviorSystem.activity_of(person) == ACTIVITY:
			person.current_action = {}
	for household_id: int in journey["households"]:
		if households != null:
			households.move_household(household_id, hut.id if hut != null else 0)
	for resource: Variant in goods:
		if int(goods[resource]) > 0:
			own.stockpile.add(StringName(str(resource)), int(goods[resource]))
	foundings += 1
	founded.emit(own, journey)
	return own


## A hut beside the new fire, its door to it (null: no room).
func _first_shelter(fire: Vector2i) -> PropData:
	for offset in HUT_RING:
		var tile := fire + offset
		if not world.is_in_bounds(tile) or props.prop_at(tile) != null or world.get_water(tile) > 0.0:
			continue
		if pathfinder != null and not pathfinder.can_stand(tile):
			continue
		var hut := PropData.new()
		hut.id = ids.next_id()
		hut.kind = PropData.Kind.HUT
		hut.tile = tile
		hut.rotation_step = roundi(Vector2(-offset).angle() / TAU * 256.0) & 0xFF
		if props.add(hut):
			return hut
	return null


## A settlement founded since the first with nobody left (and nobody on the
## way there) is abandoned: its fire goes cold, what it was building is left
## undone, its huts fall into ruin in time. (The first stays, even empty.)
func _abandon_empty() -> void:
	var construction: ConstructionSystem = null
	for own: Settlement in settlements.all().duplicate():
		if own == settlements.primary() or own.member_count() > 0:
			continue
		var waiting := false
		for journey in journeys:
			if Vector2i(journey["to"]) == own.start_info().settlement_tile:
				waiting = true
		if waiting:
			continue
		var fire := own.fire()
		if fire != null and fire.stock != 0:
			fire.stock = 0
			props.touch(fire.id)
		construction = own.construction
		var homes: Array[int] = own.start_info().hut_ids.duplicate()
		var name := own.display_name()
		var at := own.start_info().settlement_tile
		var id := own.id
		if construction != null:
			construction.abandon(id, homes)
		settlements.remove(own)
		abandonments += 1
		abandoned.emit(id, name, at)


## Which way `to` lies from `from`, in words ("north", "south-east" …): -Y is north.
static func direction(from: Vector2i, to: Vector2i) -> String:
	var v := Vector2(to - from)
	if v.length() < 0.5:
		return "nearby"
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var index := posmod(roundi(v.angle() / (TAU / 8.0)), 8)
	return names[index]


func _going_from(settlement_id: int) -> bool:
	for journey in journeys:
		if int(journey["from"]) == settlement_id:
			return true
	return false


func _has_couple(ids_going: Array, now: int) -> bool:
	var man := false
	var woman := false
	for id: int in ids_going:
		var person := people.get_person(id)
		if person == null or not _grown(person, now):
			continue
		if person.sex == PersonData.Sex.MALE:
			man = true
		else:
			woman = true
	return man and woman


func _grown(person: PersonData, now: int) -> bool:
	return person.age_years(now, Config.time.ticks_per_year()) >= Config.people.adult_from_years


## Adds the latest event of `type` as a cause (if there is one).
func _cause(causes: Array, type: StringName) -> void:
	if events == null:
		return
	var found_events := events.of_type(type)
	if not found_events.is_empty():
		causes.append(found_events[-1].id)


func debug_text() -> String:
	return "migration: %d set out, %d founded, %d under way, %d abandoned" % [departures, foundings, journeys.size(), abandonments]


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var rested := {}
	for id: int in _rested:
		rested[str(id)] = _rested[id]
	return {"journeys": journeys.duplicate(true), "rested": rested, "day": _day, "next_id": _next_id,
		"departures": departures, "foundings": foundings, "abandonments": abandonments}


func from_dict(data: Dictionary) -> void:
	journeys.clear()
	_rested.clear()
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	departures = maxi(int(data.get("departures", 0)), 0)
	foundings = maxi(int(data.get("foundings", 0)), 0)
	abandonments = maxi(int(data.get("abandonments", 0)), 0)
	if typeof(data.get("rested")) == TYPE_DICTIONARY:
		for key: Variant in data["rested"]:
			_rested[int(str(key))] = int(data["rested"][key])
	if typeof(data.get("journeys")) == TYPE_ARRAY:
		for entry: Variant in data["journeys"]:
			if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("to")) == TYPE_VECTOR2I \
					and typeof(entry.get("members")) == TYPE_ARRAY and not (entry["members"] as Array).is_empty():
				var journey: Dictionary = (entry as Dictionary).duplicate(true)
				for key: String in ["goods"]:
					if typeof(journey.get(key)) != TYPE_DICTIONARY:
						journey[key] = {}
				for key: String in ["households", "causes"]:
					if typeof(journey.get(key)) != TYPE_ARRAY:
						journey[key] = []
				journeys.append(journey)
