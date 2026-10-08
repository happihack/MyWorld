class_name BoatSystem
extends RefCounted
## The boats of the box (FB2, bible §18.2a). A settlement with a landing has
## boats built at it — one at a camp or hamlet, two at a village, three at a
## town — of the best kind it knows how to make, each new kind replacing the
## oldest of a lesser one; a builder does the work over a few days, from wood
## in the stores. Boats wear and are mended; a storm or high water may tear
## a moored one loose, and it drifts with the current until it runs aground —
## fetched back if it came to rest near, else lost (and told). Iced in, they
## are laid up. Out on the water (FB3): a crew launches one at its landing,
## paddles it over the water — the current helping or hindering — and brings
## it in again.

signal boat_added(boat: BoatData)
signal boat_removed(boat_id: int)
## A boat moved (drawn anew).
signal boat_moved(boat_id: int)
## A boat is gone: `why` "carried_off" (drifted too far), "fell_apart" or
## "swamped" (told as the swamping).
signal boat_lost(boat: BoatData, why: StringName)
## A settlement's first boat of a kind is built.
signal boat_built(boat: BoatData)
## Swamped out in a storm (FB4): the catch lost, the crew ashore — `drowned`
## those who were not (person ids; only in the worst of it: D1).
signal swamped(boat: BoatData, drowned: Array)

## Days a builder takes over a boat, by kind (PropData.Boat).
const BUILD_DAYS := {PropData.Boat.RAFT: 2, PropData.Boat.CANOE: 3, PropData.Boat.PLANK_BOAT: 5, PropData.Boat.SAIL: 6}
## How much a moored boat wears a day; mended (with MEND_WOOD wood) by
## MEND once below MEND_BELOW.
const WEAR_PER_DAY := 0.004
const MEND_BELOW := 0.6
const MEND := 0.3
const MEND_WOOD := 2
## A storm or high water tears a moored boat loose this often a day.
const TEAR_CHANCE := 0.12
## A boat that ran aground this near its landing (tiles) is fetched back the
## next day; further off, it is lost.
const RECOVER_REACH := 24.0
## Drifting: steps of this long (s), at the current's speed (× DRIFT_SHARE);
## run aground once it has hardly moved for AGROUND_STEPS steps.
const DRIFT_STEP := 0.05
const DRIFT_SHARE := 0.9
const AGROUND_STEPS := 60
const AGROUND_DISTANCE := 0.05
## Where boats lie at a landing: out on the water beside it (MOORING_OUT
## tiles from its middle, towards the water), side by side, pointing out.
## (Not at a set place in the jetty's own frame: landings all face one way,
## and on the phone the boats lay on the dry tile under the planks.)
const MOORING_OUT := 0.85
const MOORING_SPACING := 0.32
const _BERTHS: Array[float] = [0.0, 1.0, -1.0]

var settlements: Settlements
var construction: ConstructionSystem
var weather: WeatherSystem
var hydrology: Hydrology
## Callable() -> bool: is the water iced over?
var is_frozen: Callable
var current: Callable
var rng: RandomNumberGenerator
## Where the fish are (FB4: where a boat goes to fish).
var waters: FishWaters
## Who is aboard (to know a crew is still out there).
var people: PersonRegistry
## The ways over the water (FB3).
var paths := WaterPaths.new()

var _world: WorldData
var _props: PropRegistry
var _ids: IdAllocator
var _boats: Dictionary = {} # id -> BoatData
var _orders: Dictionary = {} # landing id -> {"kind": int, "days": int}
var _built_kinds: Dictionary = {} # settlement id -> {kind: true}
var _day := 0
var _time_bank := 0.0
var _still: Dictionary = {} # boat id -> [position, steps]
## Counted (runtime, for the soak): boats put out that went nowhere — no water
## worth going to, no way there.
var idle_trips := 0
var no_water := 0
var no_way := 0
var _worth: Dictionary = {} # landing id -> [day, worth going out]
var _far: Dictionary = {} # boat id -> furthest from its mooring this trip (tiles)
var _routes: Dictionary = {} # boat id -> {"to": Vector2, "points": PackedVector2Array, "next": int} (not saved)


func bind(world: WorldData, props: PropRegistry, ids: IdAllocator, now: int) -> void:
	_world = world
	_props = props
	_ids = ids
	_boats.clear()
	_orders.clear()
	_built_kinds.clear()
	_still.clear()
	_routes.clear()
	paths.bind(world)
	_day = Config.time.day_index(now)


func all_boats() -> Array[BoatData]:
	var out: Array[BoatData] = []
	var keys: Array = _boats.keys()
	keys.sort()
	for id: int in keys:
		out.append(_boats[id])
	return out


func get_boat(id: int) -> BoatData:
	return _boats.get(id)


func size() -> int:
	return _boats.size()


## The boats of a landing, the oldest first.
func boats_of(landing_id: int) -> Array[BoatData]:
	var out: Array[BoatData] = []
	for boat in all_boats():
		if boat.landing_id == landing_id:
			out.append(boat)
	return out


## Is a boat tied up at this landing (to fish from)?
func has_moored(landing_id: int) -> bool:
	for boat: BoatData in _boats.values():
		if boat.landing_id == landing_id and boat.state == BoatData.State.MOORED:
			return true
	return false


## How many boats a landing of `own` holds.
static func room_at_landing(own: Settlement) -> int:
	if own == null:
		return 1
	if own.tier() >= Settlements.Tier.TOWN:
		return 3
	return 2 if own.tier() >= Settlements.Tier.VILLAGE else 1


# --- where a boat lies --------------------------------------------------------------------------------

## Where the `index`-th boat of a landing lies moored: [position (world XZ), heading].
func mooring(landing: PropData, index: int) -> Array:
	var base: Array = _berth_base(landing)
	var out: Vector2 = base[1]
	var across := Vector2(-out.y, out.x)
	var berth: float = _BERTHS[index % _BERTHS.size()] + floorf(index / float(_BERTHS.size())) * 2.0
	var at: Vector2 = base[0] + across * MOORING_SPACING * berth
	return [at, atan2(out.x, out.y)]


## Where a landing's boats lie, and which way is out: on the water beside it
## — or, if the river has moved off (the phone, 2026-10-07: a landing left
## inland, its boats on the grass by a rain puddle), pulled up at the edge
## of the nearest water deep enough to float a boat within BERTH_REACH; with
## none, beside the landing.
const BERTH_REACH := 3
const BERTH_DEPTH := 0.1


func _berth_base(landing: PropData) -> Array:
	var middle := landing.position2d()
	if _world == null:
		return [middle + Vector2(MOORING_OUT, 0.0), Vector2(1.0, 0.0)]
	var best: Variant = null
	var best_d := INF
	for dy in range(-BERTH_REACH, BERTH_REACH + 1):
		for dx in range(-BERTH_REACH, BERTH_REACH + 1):
			var there := landing.tile + Vector2i(dx, dy)
			if (dx == 0 and dy == 0) or not _world.is_in_bounds(there) or _world.get_water(there) < BERTH_DEPTH:
				continue
			var d := Vector2(dx, dy).length_squared() + (0.01 if dx != 0 and dy != 0 else 0.0)
			if d < best_d:
				best = there
				best_d = d
	if best == null:
		return [middle + Vector2(MOORING_OUT, 0.0), Vector2(1.0, 0.0)]
	var water: Vector2i = best
	var out := Vector2(water - landing.tile).normalized()
	if absi(water.x - landing.tile.x) <= 1 and absi(water.y - landing.tile.y) <= 1:
		return [middle + out * MOORING_OUT, out] # (beside it)
	return [Vector2(water) + Vector2(0.5, 0.5) - out * 0.35, out] # (at the water's edge)


## The height (above the ground of its tile) a boat floats at, there: on the
## water, or on the ground where there is none.
func float_height(at: Vector2) -> float:
	if _world == null:
		return 0.0
	var tile := WorldCoords.world2d_to_tile(at)
	return maxf(_world.get_water(tile), 0.0) if _world.is_in_bounds(tile) else 0.0


# --- the days -----------------------------------------------------------------------------------------

## Brings the boats up to `now`: their days (building, wear, storms, the
## drifted fetched back or lost).
func advance_to(now: int) -> void:
	if _world == null:
		return
	var day := Config.time.day_index(now)
	if day < _day:
		_day = day
		return
	while _day < day:
		_day += 1
		_each_day(now)


func _each_day(now: int) -> void:
	paths.clear_cache() # (the water may have changed)
	_routes.clear()
	_build(now)
	var stormy := (weather != null and weather.state == WeatherSystem.STORM) or (hydrology != null and hydrology.high_water)
	var frozen: bool = is_frozen.is_valid() and bool(is_frozen.call())
	for boat in all_boats():
		# Fish left in the hull spoil (as fish do: within two days) — half of them a day.
		if boat.load_resource == &"fish" and boat.load_amount > 0:
			boat.load_amount /= 2
			if boat.load_amount == 0:
				boat.load_resource = &""
		match boat.state:
			BoatData.State.MOORED:
				boat.condition = maxf(boat.condition - WEAR_PER_DAY, 0.0)
				_mend(boat)
				if frozen:
					boat.state = BoatData.State.LAID_UP
				elif stormy and rng != null and rng.randf() < TEAR_CHANCE:
					boat.state = BoatData.State.DRIFTING
					boat.drift_from = boat.position
			BoatData.State.LAID_UP:
				if not frozen:
					boat.state = BoatData.State.MOORED
			BoatData.State.DRIFTING:
				# (Days lived without frames — away — drift to their end at once.)
				_drift_until_aground(boat)
			BoatData.State.AGROUND:
				_fetch_back_or_lose(boat)
			BoatData.State.OUT:
				# (Nobody out in it any more — a plan dropped, a load: it is brought in.)
				if not _crewed(boat):
					var landing := _props.get_prop(boat.landing_id) if _props != null else null
					if landing != null:
						bring_in(boat)
					else:
						_lose(boat, &"carried_off")
		if boat.condition <= 0.0 and _boats.has(boat.id):
			_lose(boat, &"fell_apart")


## Boats wanted at each landing, built by a builder from the stores' wood.
func _build(now: int) -> void:
	if settlements == null or construction == null:
		return
	for own in settlements.all():
		var best := WorkStep.boat_of(own)
		if best == PropData.Boat.NONE:
			continue
		var builder := _builder_of(own)
		if own.planner == null:
			continue
		for landing_id in own.planner.standing_near(PropData.Kind.LANDING):
			var landing := _props.get_prop(landing_id)
			if landing == null:
				continue
			var there := boats_of(landing_id)
			var order: Variant = _orders.get(landing_id)
			if order == null:
				var worst: BoatData = null
				for boat in there:
					if boat.kind < best and (worst == null or boat.kind < worst.kind):
						worst = boat
				if there.size() >= room_at_landing(own) and worst == null:
					continue
				if builder == null or own.stockpile.amount(&"wood") < int(BoatData.WOOD[best]):
					continue
				own.stockpile.take(&"wood", int(BoatData.WOOD[best]))
				_orders[landing_id] = {"kind": best, "days": 0}
				continue
			if builder == null:
				continue # (waits for someone to do it)
			order["days"] = int(order["days"]) + 1
			if int(order["days"]) < int(BUILD_DAYS.get(int(order["kind"]), 3)):
				continue
			_orders.erase(landing_id)
			# A better boat takes the place of the oldest of a lesser kind (if there is no room).
			if there.size() >= room_at_landing(own):
				var oldest: BoatData = null
				for boat in there:
					if boat.kind < int(order["kind"]) and boat.state != BoatData.State.OUT and (oldest == null or boat.kind < oldest.kind):
						oldest = boat
				if oldest == null:
					continue
				remove(oldest.id)
				there = boats_of(landing_id)
			var boat := add_boat(int(order["kind"]), landing, there.size(), own.id, now)
			if boat != null:
				var kinds: Dictionary = _built_kinds.get(own.id, {})
				if not kinds.has(boat.kind):
					kinds[boat.kind] = true
					_built_kinds[own.id] = kinds
					boat_built.emit(boat)


## Who makes and mends the boats: a builder (D5) — or, with none (builders
## are taken up only while something is being built), a fisher, who makes
## their own (a soak, 2026-10-07: a landing stood boatless for want of a builder).
func _builder_of(own: Settlement) -> PersonData:
	var fisher: PersonData = null
	for person in own.members():
		if person.occupation_id == &"builder":
			return person
		if fisher == null and person.occupation_id == &"fisher":
			fisher = person
	return fisher


func _mend(boat: BoatData) -> void:
	if boat.condition >= MEND_BELOW or settlements == null:
		return
	var own := settlements.get_settlement(boat.settlement_id)
	if own == null or _builder_of(own) == null or own.stockpile.amount(&"wood") < MEND_WOOD:
		return
	own.stockpile.take(&"wood", MEND_WOOD)
	boat.condition = minf(boat.condition + MEND, 1.0)


## A new boat of `kind` at `landing` (its `index`-th place there).
func add_boat(kind: int, landing: PropData, index: int, settlement_id: int, now: int) -> BoatData:
	if _ids == null or landing == null:
		return null
	var boat := BoatData.new()
	boat.id = _ids.next_id()
	boat.kind = kind
	boat.landing_id = landing.id
	boat.settlement_id = settlement_id
	var place := mooring(landing, index)
	boat.position = place[0]
	boat.heading = place[1]
	boat.height = float_height(boat.position)
	boat.built_tick = now
	_boats[boat.id] = boat
	boat_added.emit(boat)
	return boat


func remove(id: int) -> void:
	if _boats.erase(id):
		_still.erase(id)
		boat_removed.emit(id)


func _lose(boat: BoatData, why: StringName) -> void:
	remove(boat.id)
	boat_lost.emit(boat, why)


## Back to its landing if it came to rest near, else lost.
func _fetch_back_or_lose(boat: BoatData) -> void:
	var landing := _props.get_prop(boat.landing_id) if _props != null else null
	if landing == null or boat.position.distance_to(landing.position2d()) > RECOVER_REACH:
		_lose(boat, &"carried_off")
		return
	_moor(boat, landing)


func _moor(boat: BoatData, landing: PropData) -> void:
	boat.state = BoatData.State.MOORED
	var place := mooring(landing, _index_at(boat))
	boat.position = place[0]
	boat.heading = place[1]
	boat.height = float_height(boat.position)
	boat_moved.emit(boat.id)


# --- drifting -------------------------------------------------------------------------------------------

## Advances drifting boats (`delta` real seconds). Cheap when none drifts.
func step(delta: float) -> void:
	var drifting: Array[BoatData] = []
	for boat in _boats.values():
		if boat.state == BoatData.State.DRIFTING:
			drifting.append(boat)
	if drifting.is_empty():
		_time_bank = 0.0
		return
	_time_bank = minf(_time_bank + delta, DRIFT_STEP * 4.0)
	while _time_bank >= DRIFT_STEP:
		_time_bank -= DRIFT_STEP
		for boat in drifting:
			if boat.state == BoatData.State.DRIFTING:
				_drift(boat, DRIFT_STEP)


func _drift(boat: BoatData, dt: float) -> void:
	var tile := boat.tile()
	var flow: Vector2 = current.call(tile) if current.is_valid() else Vector2.ZERO
	var next := boat.position + flow * DRIFT_SHARE * dt
	var inner := Rect2(_world.bounds).grow(-0.4)
	next = Vector2(clampf(next.x, inner.position.x, inner.end.x), clampf(next.y, inner.position.y, inner.end.y))
	var next_tile := WorldCoords.world2d_to_tile(next)
	if _world.get_water(next_tile) < boat.draught():
		boat.state = BoatData.State.AGROUND
		_still.erase(boat.id)
		boat_moved.emit(boat.id)
		return
	if flow.length() > 0.01:
		boat.heading = lerp_angle(boat.heading, atan2(flow.x, flow.y), 0.05)
	boat.position = next
	boat.height = float_height(next)
	var still: Array = _still.get(boat.id, [boat.position, 0])
	still[1] = int(still[1]) + 1
	if int(still[1]) >= AGROUND_STEPS:
		if boat.position.distance_to(still[0]) < AGROUND_DISTANCE:
			boat.state = BoatData.State.AGROUND
			_still.erase(boat.id)
		else:
			_still[boat.id] = [boat.position, 0]
	else:
		_still[boat.id] = still
	boat_moved.emit(boat.id)


func _drift_until_aground(boat: BoatData) -> void:
	for i in 4000:
		if boat.state != BoatData.State.DRIFTING:
			return
		_drift(boat, DRIFT_STEP)
	boat.state = BoatData.State.AGROUND


# --- out on the water (FB3) ----------------------------------------------------------------------------

## Paddling: tiles a game minute at a boat's SPEED 1 (a walker's pace); the
## current adds (or takes) this much of itself, but never more than
## CURRENT_MOST of the boat's own way; a boat is there within ARRIVE tiles.
const CURRENT_SHARE := 0.6
const CURRENT_MOST := 0.7
const ARRIVE := 0.15
## How far out from its landing a boat goes to fish (tiles).
const FISHING_REACH := 18.0
## A tile further out is worth this much less (against a cell's richness × 10):
## the paddling is time not spent fishing (a soak: trips were mostly paddling).
const FISHING_DISTANCE_COST := 0.5
## What a trip takes out of a boat.
const WEAR_PER_TRIP := 0.006


## A moored boat of this landing with room aboard (null: none) — the best kind first.
func boat_to_take(landing_id: int) -> BoatData:
	var best: BoatData = null
	for boat in boats_of(landing_id):
		if boat.state == BoatData.State.MOORED and (best == null or boat.kind > best.kind):
			best = boat
		elif boat.state == BoatData.State.OUT and boat.crew.size() < boat.crew_room() and best == null:
			best = boat
	return best


## `person` goes aboard (the boat put out if it was moored). False if it
## cannot be (iced in, adrift, full).
func board(boat: BoatData, person_id: int) -> bool:
	if boat == null:
		return false
	if boat.crew.has(person_id):
		return true
	if boat.state != BoatData.State.MOORED and boat.state != BoatData.State.OUT:
		return false
	if boat.crew.size() >= boat.crew_room():
		return false
	boat.crew.append(person_id)
	if boat.state == BoatData.State.MOORED:
		boat.state = BoatData.State.OUT
		boat.height = float_height(boat.position)
	return true


## `person` steps off; the last one off at the landing ties it up there.
func step_off(boat: BoatData, person_id: int) -> void:
	if boat == null:
		return
	var at := boat.crew.find(person_id)
	if at >= 0:
		boat.crew.remove_at(at)
	if boat.crew.is_empty() and boat.state == BoatData.State.OUT:
		var landing := _props.get_prop(boat.landing_id) if _props != null else null
		if landing != null and boat.position.distance_to(landing.position2d()) <= 2.0:
			bring_in(boat)


## The boat tied up at its landing again (crew off), a trip done.
func bring_in(boat: BoatData) -> void:
	var landing := _props.get_prop(boat.landing_id) if _props != null else null
	boat.crew = PackedInt64Array()
	_routes.erase(boat.id)
	if landing == null:
		return
	# (A trip is one that went somewhere; one that turned back at the landing is not.)
	if float(_far.get(boat.id, 0.0)) > 1.0:
		boat.trips += 1
		boat.condition = maxf(boat.condition - WEAR_PER_TRIP, 0.0)
	else:
		idle_trips += 1
	_far.erase(boat.id)
	_moor(boat, landing)


## Where the boat lies when tied up.
func mooring_of(boat: BoatData) -> Vector2:
	var landing := _props.get_prop(boat.landing_id) if _props != null else null
	if landing == null:
		return boat.position
	return mooring(landing, _index_at(boat))[0]


## Paddles the boat `minutes` towards `to` (world XZ) over the water. 1: there;
## 0: on the way; -1: there is no way (or the water froze).
func paddle(boat: BoatData, to: Vector2, minutes: float) -> int:
	if boat == null or boat.state != BoatData.State.OUT or _world == null:
		return -1
	var route: Dictionary = _routes.get(boat.id, {})
	if route.is_empty() or (route["to"] as Vector2).distance_to(to) > 0.01:
		route = _route(boat, to)
		if route.is_empty():
			no_way += 1
			return -1
		_routes[boat.id] = route
	var points: PackedVector2Array = route["points"]
	var budget := boat.speed() * Config.people.walk_tiles_per_minute * minutes
	while budget > 0.0 and int(route["next"]) < points.size():
		var aim := points[int(route["next"])]
		var gap := aim - boat.position
		var dir := gap.normalized() if gap.length() > 0.0001 else Vector2.ZERO
		# The current: with it the way is quicker, against it slower.
		var flow: Vector2 = current.call(boat.tile()) if current.is_valid() else Vector2.ZERO
		var along := clampf(flow.dot(dir) * CURRENT_SHARE, -CURRENT_MOST, CURRENT_MOST)
		var reach := budget * (1.0 + along)
		if gap.length() <= reach:
			boat.position = aim
			budget -= gap.length() / maxf(1.0 + along, 0.1)
			route["next"] = int(route["next"]) + 1
		else:
			boat.position += dir * reach
			budget = 0.0
		if dir != Vector2.ZERO:
			boat.heading = lerp_angle(boat.heading, atan2(dir.x, dir.y), 0.5)
	boat.height = float_height(boat.position)
	_far[boat.id] = maxf(float(_far.get(boat.id, 0.0)), boat.position.distance_to(mooring_of(boat)))
	boat_moved.emit(boat.id)
	if int(route["next"]) >= points.size() or boat.position.distance_to(to) <= ARRIVE:
		_routes.erase(boat.id)
		return 1
	return 0


func _route(boat: BoatData, to: Vector2) -> Dictionary:
	var mast := boat.kind == PropData.Boat.SAIL
	var from: Variant = paths.water_near(boat.tile(), boat.draught(), 2, mast)
	var end: Variant = paths.water_near(WorldCoords.world2d_to_tile(to), boat.draught(), 2, mast)
	if from == null or end == null:
		return {}
	var way := paths.find(from, end, boat.draught(), mast)
	if way.is_empty():
		return {}
	return {"to": to, "points": WaterPaths.points_of(way, boat.position, to), "next": 1}


## Nothing worth going out for from this landing today after all (the water
## was fished down since the morning): the fishers fish from the bank.
func not_worth(landing_id: int) -> void:
	_worth[landing_id] = [_day, false]


## Is there a boat at this landing to take, and water worth taking it to?
## (Worked out once a day a landing; with none, the fisher fishes from the bank.)
func worth_going_out(landing_id: int) -> bool:
	var boat := boat_to_take(landing_id)
	if boat == null:
		return false
	var known: Array = _worth.get(landing_id, [])
	if known.is_empty() or int(known[0]) != _day:
		known = [_day, fishing_water(boat) != null]
		_worth[landing_id] = known
	return bool(known[1])


## Where a boat from this landing goes to fish: the richest water within
## FISHING_REACH that it can get to, a tile it floats on there (null: none).
func fishing_water(boat: BoatData) -> Variant:
	if waters == null or boat == null:
		return null
	var mast := boat.kind == PropData.Boat.SAIL
	var from: Variant = paths.water_near(boat.tile(), boat.draught(), 2, mast)
	if from == null:
		return null
	var best: Variant = null
	var best_score := -INF
	for pair: Array in waters.cells_near(boat.tile(), FISHING_REACH):
		var middle := FishWaters.middle_of(pair[0])
		var spot: Variant = paths.water_near(middle, boat.draught(), FishWaters.CELL / 2, mast)
		if spot == null:
			continue
		var distance := Vector2(spot - (from as Vector2i)).length()
		# (Rich water is worth going further for; a little nearer is a little better.)
		var score := waters.richness_at(spot) * 10.0 - distance * FISHING_DISTANCE_COST
		if score > best_score and not paths.find(from, spot, boat.draught(), mast).is_empty():
			best = spot
			best_score = score
	return best


## Swamped (FB4): what was caught is lost; the crew make for the bank — in
## the worst of it (a storm on high water) one may not; the boat drifts off,
## or is lost.
const SWAMP_LOST := 0.4
const SWAMP_DAMAGE := 0.2
const DROWN_SHARE := 0.05


func swamp(boat: BoatData, _now: int) -> void:
	var drowned := []
	var worst := hydrology != null and hydrology.high_water
	for id in boat.crew:
		var person := people.get_person(id) if people != null else null
		if person != null and person.carrying == &"fish":
			person.carrying = &""
			person.carrying_amount = 0
		if worst and rng != null and rng.randf() < DROWN_SHARE:
			drowned.append(id)
	boat.crew = PackedInt64Array()
	boat.load_amount = 0
	_routes.erase(boat.id)
	boat.condition = maxf(boat.condition - SWAMP_DAMAGE, 0.0)
	if rng != null and rng.randf() < SWAMP_LOST:
		swamped.emit(boat, drowned)
		_lose(boat, &"swamped")
		return
	boat.state = BoatData.State.DRIFTING
	boat.drift_from = boat.position
	boat_moved.emit(boat.id)
	swamped.emit(boat, drowned)


## Someone aboard who is still out in it (their step a boat trip).
func _crewed(boat: BoatData) -> bool:
	if people == null:
		return not boat.crew.is_empty()
	for id in boat.crew:
		var person := people.get_person(id)
		if person != null and _step_type(person) == "boat":
			return true
	return false


static func _step_type(person: PersonData) -> String:
	var steps: Variant = person.current_action.get("steps")
	var index := int(person.current_action.get("index", 0))
	if typeof(steps) == TYPE_ARRAY and index >= 0 and index < (steps as Array).size() and typeof(steps[index]) == TYPE_DICTIONARY:
		return str(steps[index].get("type", ""))
	return ""


# --- older worlds, saving ------------------------------------------------------------------------------

## A world from before boats were things (FB2): each landing gets the boat it
## showed.
func adopt_landings(now: int) -> int:
	if _props == null:
		return 0
	var made := 0
	for landing in _props.of_kind(PropData.Kind.LANDING):
		if landing.variant != PropData.Boat.NONE and boats_of(landing.id).is_empty():
			var own := settlements.nearest(landing.tile) if settlements != null else null
			if add_boat(landing.variant, landing, 0, own.id if own != null else 0, now) != null:
				made += 1
	return made


func to_dict() -> Dictionary:
	var list: Array = []
	for boat in all_boats():
		list.append(boat.to_dict())
	var orders := {}
	for landing_id: int in _orders:
		orders[str(landing_id)] = (_orders[landing_id] as Dictionary).duplicate()
	var kinds := {}
	for settlement_id: int in _built_kinds:
		kinds[str(settlement_id)] = (_built_kinds[settlement_id] as Dictionary).keys()
	return {"boats": list, "orders": orders, "built_kinds": kinds, "day": _day}


## Restores the boats (call after bind). Returns how many records were unusable.
func from_dict(data: Dictionary) -> int:
	var skipped := 0
	for item: Variant in data.get("boats", []):
		var boat := BoatData.from_dict(item) if typeof(item) == TYPE_DICTIONARY else null
		if boat == null or _boats.has(boat.id):
			skipped += 1
			continue
		_boats[boat.id] = boat
		if _ids != null:
			_ids.reserve_above(boat.id)
	var orders: Variant = data.get("orders")
	if typeof(orders) == TYPE_DICTIONARY:
		for key: Variant in orders:
			if typeof(orders[key]) == TYPE_DICTIONARY:
				_orders[int(str(key))] = {"kind": int(orders[key].get("kind", PropData.Boat.RAFT)), "days": int(orders[key].get("days", 0))}
	var kinds: Variant = data.get("built_kinds")
	if typeof(kinds) == TYPE_DICTIONARY:
		for key: Variant in kinds:
			var known := {}
			for kind: Variant in kinds[key]:
				known[int(kind)] = true
			_built_kinds[int(str(key))] = known
	_day = int(data.get("day", _day))
	# Moored boats lie where they are moored now (an older save's may lie
	# where boats were once put: under the jetty).
	for boat in all_boats():
		var landing := _props.get_prop(boat.landing_id) if _props != null else null
		if boat.state == BoatData.State.MOORED and landing != null:
			var place := mooring(landing, _index_at(boat))
			boat.position = place[0]
			boat.heading = place[1]
			boat.height = float_height(boat.position)
	return skipped


## A boat's place among those tied up at its landing.
func _index_at(boat: BoatData) -> int:
	var index := 0
	for other in boats_of(boat.landing_id):
		if other.id == boat.id:
			return index
		if other.state != BoatData.State.DRIFTING and other.state != BoatData.State.AGROUND:
			index += 1
	return index
