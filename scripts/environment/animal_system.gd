class_name AnimalSystem
extends RefCounted
## The animals' lives (bible §12): each one grazes, wanders about where its
## group lives, drinks, sleeps, runs from people and predators and from
## whatever the player does near it; predators hunt; and day by day each
## species has young and loses its old, levelling off at what the box holds.
## Fish are one number for all the water.
##
## Time is given in whole game minutes (`advance_to`), in pieces of at most
## STEP_MINUTES — so it does the same at any game speed, and a long stretch
## (a test, a world opened after a while) costs little.

## An animal died: of old age or hunger (&"age", &"hunger"), was taken by a
## predator (&"prey") or by a hunter (&"hunted").
signal died(animal_id: int, species: StringName, cause: StringName, position: Vector2)
signal born(animal_id: int, species: StringName)
## An animal took fright and ran.
signal fled(animal_id: int)
## A group has set out for other ground (in autumn, in spring).
signal migrated(species: StringName, group: int, to: Vector2)

const STEP_MINUTES := 30
## When time comes a minute at a time (the running game), animals that are
## neither running nor hunting are looked at only every so many minutes (and
## then live all of them at once): most of what animals do is stand and
## chew. With nobody running or hunting, the minutes between cost nothing.
const CALM_EVERY := 3
## More than this many steps at once are not lived through one by one: the
## days in between only count for who is born and who dies.
const MAX_STEPS_AT_ONCE := 96
## Tiles an animal moves between looks at where it is going.
const STRIDE := 0.5
## Levels of height an animal climbs in a step (as people do).
const MAX_STEP_LEVELS := 1
## How long a fright lasts, in game minutes, and how far it carries them.
const FLEE_MINUTES := 25
const FLEE_DISTANCE := 7.0
## A predator is on its quarry at this distance, and gives up after so long.
const POUNCE_REACH := 0.7
const HUNT_MINUTES := 90
## How long a kill keeps a predator from the next, as a share of its
## species' `hunts_every_days`, when it failed (it tries again sooner).
const RETRY_SHARE := 0.25
## Someone stalking an animal is noticed from this share of its fear radius.
const STALKED_SHARE := 0.4
## After a kill a predator's home moves this much of the way to where it
## made it (they live where their prey is).
const HOME_DRIFT := 0.3
## A group that moves on goes at least this far (tiles).
const MIGRATION_MIN_TILES := 12.0
## Animals on their way to other ground go at this share of their amble.
const JOURNEY_PACE := 0.6
## One on its way has arrived this near where the group will live (tiles).
const JOURNEY_ARRIVED := 2.5
## Whoever has not arrived by this day of the season lives there all the
## same (and gets there as it can).
const JOURNEY_OVER_DAY := 4
## How many places a group looks at for a way that keeps clear of people.
const JOURNEY_TRIES := 6
## The last few of a kind keep hidden: a predator catches nothing when there
## are no more than this many of its prey — and when the last pair grows
## old, a young one takes the old one's place. (No kind dies out by itself;
## what the player does to the box is another matter.)
const REFUGE := 3
const LAST_PAIR := 2
## A new world's herds keep at least this far from the settlement.
const SETTLEMENT_CLEARANCE := 12.0
## One fish per so many tiles of water is what a water holds, and the share
## of what is missing that comes back in a day.
const WATER_TILES_PER_FISH := 5.0
const FISH_REGROWTH := 0.2

var registry: AnimalRegistry
var species: SpeciesLibrary
## Fish in the water (see SpeciesDef.aggregate), and how many it holds.
var fish := 0.0
var fish_capacity := 0.0
## True once the world has been given its animals (an older world is given
## them when it is opened).
var seeded := false
var last_tick := -1_000_000
## Time spent on the animals since the world was opened, in microseconds
## (for the debug overlay and for tests of what they cost).
var total_usec := 0

var _world: WorldData
var _props: PropRegistry
var _people: PersonRegistry
var _ids: IdAllocator
var _start: WorldSetup.StartInfo
## Where every settlement's fire is (M12.3; empty: only the first's).
var settlement_tiles: Array[Vector2i] = []
var _rng: RandomNumberGenerator
var _pathfinder: Pathfinder
var _day := -1_000_000
var _births: Dictionary = {} # species -> young not yet whole (0 … 1)
var _next_group := 1
## Herds on their way to other ground: group -> where to (Vector2). Each
## of the group walks there by a way of its own, and lives there once it
## has arrived (`home`); the journey is over when they all do.
var _journeys: Dictionary = {}
## The way each one on a journey is following (animal id -> the middles of
## its tiles) and how far along it is. Not saved: found again when wanted.
var _ways: Dictionary = {}
var _way_at: Dictionary = {}
var _wade := 0.24
var _shores: Dictionary = {} # group -> Vector2 (where they drink) or Vector2.INF
var _unreached: Dictionary = {} # group -> the tick a hunter found no way to it
var _hurried := 0 # how many are running or hunting (as of the last step)


## `pathfinder` (optional): so that a new world's herds live where people
## can get to them.
func bind(world: WorldData, props: PropRegistry, people: PersonRegistry, animals: AnimalRegistry, library: SpeciesLibrary,
		ids: IdAllocator, start: WorldSetup.StartInfo, rng: RandomNumberGenerator, pathfinder: Pathfinder = null) -> void:
	_pathfinder = pathfinder
	_world = world
	_props = props
	_people = people
	registry = animals
	species = library
	_ids = ids
	_start = start
	_rng = rng
	_wade = Pathfinder.WADE_DEPTH * world.height_step if world != null else 0.24
	_shores.clear()
	last_tick = -1_000_000
	_day = -1_000_000
	_count_water()
	for animal in registry.all_animals():
		_next_group = maxi(_next_group, animal.group + 1)


# --- a new world's animals ------------------------------------------------------------------------

## Gives the world its animals: each species' groups, somewhere they can
## live, away from the settlement. Once per world.
func seed_world(now: int) -> void:
	if seeded or registry == null or species == null:
		return
	seeded = true
	for id in species.ids():
		var def := species.get_def(id)
		if def.aggregate:
			fish = fish_capacity * 0.8
			continue
		for group in def.starting_groups:
			var home: Variant = _find_home(def)
			if home == null:
				continue
			var size := _rng.randi_range(def.group_min, def.group_max)
			var herd := _next_group
			_next_group += 1
			for i in size:
				if registry.count(id) >= def.capacity:
					break
				# (Of every age: a group that has been living there.)
				var age := _rng.randi_range(0, maxi(def.lifespan_days * 2 / 3, 1))
				spawn(id, _scatter(home, 2.0), home, herd, now - age * TimeConfig.MINUTES_PER_DAY)


## Brings an animal into the world. Null if the species is unknown.
func spawn(species_id: StringName, at: Vector2, home: Vector2, group: int, born_tick: int) -> AnimalData:
	var def := species.get_def(species_id) if species != null else null
	if def == null or def.aggregate or registry == null:
		return null
	var animal := AnimalData.new()
	animal.id = _ids.next_id()
	animal.species = species_id
	animal.position = at
	animal.home = home
	animal.group = group
	animal.born_tick = born_tick
	animal.fed_tick = born_tick
	animal.facing = _rng.randf() * TAU if _rng != null else 0.0
	registry.add(animal)
	return animal


# --- time -----------------------------------------------------------------------------------------

## Lets the animals live up to game minute `now`. Cheap to call often (and
## from more than one place: what has been lived is not lived again).
func advance_to(now: int) -> void:
	if registry == null or species == null:
		return
	if last_tick == -1_000_000 or now < last_tick:
		last_tick = now
		_day = Config.time.day_index(now)
		return
	var steps := 0
	var started := Time.get_ticks_usec()
	while now - last_tick >= 1 and steps < MAX_STEPS_AT_ONCE:
		var minutes := mini(now - last_tick, STEP_MINUTES)
		last_tick += minutes
		steps += 1
		_step(minutes, last_tick)
		_days(last_tick)
	total_usec += Time.get_ticks_usec() - started
	if now > last_tick:
		# Too long to live through: only the days count (and whoever was on
		# the way somewhere has got there).
		last_tick = now
		_days(now)
		_end_journeys(now, true)


## Something startling happened at `at` (the player's hand, a falling tree):
## animals within `radius` run from it.
func startle(at: Vector2, radius: float, now: int) -> int:
	var ran := 0
	if registry == null or radius <= 0.0:
		return 0
	for animal in registry.all_animals():
		if animal.position.distance_to(at) <= radius:
			_flee(animal, at, now)
			ran += 1
	return ran


## One animal takes fright (touched by the player).
func startle_one(animal_id: int, from: Vector2, now: int) -> bool:
	var animal := registry.get_animal(animal_id) if registry != null else null
	if animal == null:
		return false
	_flee(animal, from, now)
	return true


# --- for hunters ----------------------------------------------------------------------------------

## May people hunt this species now (there are enough of them)?
func may_hunt(species_id: StringName) -> bool:
	var def := species.get_def(species_id) if species != null else null
	return def != null and def.is_hunted() and registry.count(species_id) > def.capacity * def.hunt_above


## Is there anything to hunt at all?
func has_game() -> bool:
	if species == null:
		return false
	for id in species.ids():
		if may_hunt(id):
			return true
	return false


## The nearest animal to `from` that may be hunted, within `radius` of
## `center` (where the hunter lives). Null if there is none.
func quarry_for(from: Vector2, center: Vector2, radius: float) -> AnimalData:
	var best: AnimalData = null
	if registry == null:
		return null
	for animal in registry.all_animals():
		if not may_hunt(animal.species) or animal.position.distance_to(center) > radius:
			continue
		if _unreached.has(animal.group) and last_tick >= int(_unreached[animal.group]) \
				and last_tick - int(_unreached[animal.group]) < TimeConfig.MINUTES_PER_DAY:
			continue # (no way to them was found today)
		if best == null or animal.position.distance_squared_to(from) < best.position.distance_squared_to(from):
			best = animal
	return best


## A hunter found no way to where a group is: it is not gone after again
## for a day.
func out_of_reach(group: int, now: int) -> void:
	_unreached[group] = now


## A hunter's throw hit: the animal is dead. Returns the meat it gives.
func hunted(animal_id: int) -> int:
	var animal := registry.get_animal(animal_id) if registry != null else null
	if animal == null:
		return 0
	var def := species.get_def(animal.species)
	_die(animal, &"hunted")
	return def.meat if def != null else 0


## A hunter's throw missed: it runs.
func missed(animal_id: int, from: Vector2, now: int) -> void:
	startle_one(animal_id, from, now)


## Takes up to `amount` fish out of the water. Returns how many.
func take_fish(amount: int) -> int:
	var got := mini(amount, floori(fish))
	fish -= got
	return got


# --- telling ---------------------------------------------------------------------------------------

func count(species_id: StringName) -> int:
	return registry.count(species_id) if registry != null else 0


func debug_text() -> String:
	var parts := PackedStringArray()
	if species != null:
		for id in species.ids():
			var def := species.get_def(id)
			if def.aggregate:
				parts.append("%s %d/%d" % [id, floori(fish), floori(fish_capacity)])
			else:
				parts.append("%s %d/%d" % [id, count(id), _capacity(def)])
	return "animals: %s" % ("  ".join(parts) if not parts.is_empty() else "none")


func to_dict() -> Dictionary:
	return {"seeded": seeded, "fish": fish, "last_tick": last_tick, "day": _day, "births": _births.duplicate(),
		"next_group": _next_group, "journeys": _journeys.duplicate(),
		"animals": registry.to_dict() if registry != null else {}}


## Restores the saved state (call after bind). Returns how many animal
## records were unusable.
func from_dict(data: Dictionary) -> int:
	seeded = bool(data.get("seeded", false))
	var water := float(data.get("fish", 0.0))
	fish = clampf(water, 0.0, maxf(fish_capacity, 0.0)) if is_finite(water) else 0.0
	last_tick = int(data["last_tick"]) if typeof(data.get("last_tick")) == TYPE_INT else -1_000_000
	_day = int(data["day"]) if typeof(data.get("day")) == TYPE_INT else -1_000_000
	_births = {}
	var carried: Variant = data.get("births")
	if typeof(carried) == TYPE_DICTIONARY:
		for key: Variant in carried:
			_births[StringName(str(key))] = clampf(float(carried[key]), 0.0, 1.0)
	var saved: Variant = data.get("animals")
	var skipped := registry.from_dict(saved if typeof(saved) == TYPE_DICTIONARY else {}) if registry != null else 0
	_next_group = maxi(int(data.get("next_group", 1)), 1)
	_journeys = {}
	_ways = {}
	_way_at = {}
	var under_way: Variant = data.get("journeys")
	if typeof(under_way) == TYPE_DICTIONARY:
		for group: Variant in under_way:
			var to: Variant = (under_way as Dictionary)[group]
			if typeof(group) == TYPE_INT and typeof(to) == TYPE_VECTOR2 and (to as Vector2).is_finite():
				_journeys[group] = to
	if registry != null:
		for animal in registry.all_animals():
			_next_group = maxi(_next_group, animal.group + 1)
			if species != null and not species.has_def(animal.species):
				skipped += 1
		for animal in registry.all_animals():
			if species != null and not species.has_def(animal.species):
				registry.remove(animal.id)
	return skipped


# --- one step ---------------------------------------------------------------------------------------

func _step(minutes: int, now: int) -> void:
	if not _journeys.is_empty():
		_advance_journeys(minutes, now)
	var fine := minutes < CALM_EVERY
	var calm_turn := not fine or posmod(now, CALM_EVERY) < minutes
	if fine and not calm_turn and _hurried == 0:
		return # nobody in a hurry, and not the minute for the others
	var hour := Config.time.minute_of_day(now) / 60.0
	# Who is about (people out of doors), for the animals to be afraid of.
	var about: Array = [] # [position, stalking]
	if _people != null:
		for person in _people.all_people():
			if person.has_flag(PersonData.FLAG_INDOORS):
				continue
			about.append([person.world2d(), str(BehaviorSystem.current_step(person).get("type", "")) == "hunt"])
	var all := registry.all_animals()
	# Those that hunt (for the others to be afraid of).
	var hunters: Array[AnimalData] = []
	for animal in all:
		var kind := species.get_def(animal.species)
		if kind != null and kind.diet == SpeciesDef.Diet.PREDATOR:
			hunters.append(animal)
	var hurried := 0
	for animal in all:
		if not registry.has_animal(animal.id):
			continue # (taken by a predator earlier in this step)
		var def := species.get_def(animal.species)
		if def == null:
			continue
		var lived := minutes
		if fine and animal.state != AnimalData.State.FLEE and animal.state != AnimalData.State.HUNT:
			if not calm_turn:
				continue
			lived = CALM_EVERY
		_live(animal, def, lived, now, hour, about, hunters)
		if animal.state == AnimalData.State.FLEE or animal.state == AnimalData.State.HUNT:
			hurried += 1
	_hurried = hurried


func _live(animal: AnimalData, def: SpeciesDef, minutes: int, now: int, hour: float, about: Array,
		hunters: Array[AnimalData]) -> void:
	# What frightens them comes before everything.
	if animal.state != AnimalData.State.FLEE:
		var threat := _threat(animal, def, about, hunters)
		if threat != Vector2.INF:
			_flee(animal, threat, now)
	if _on_journey(animal) and animal.state != AnimalData.State.FLEE and animal.state != AnimalData.State.HUNT:
		return # (on its way to other ground: `_advance_journeys` walks it)
	match animal.state:
		AnimalData.State.FLEE:
			if now >= animal.state_until:
				_rest(animal, now, 10, 30)
			elif _move(animal, animal.target, def.run_speed * minutes):
				if animal.position.distance_to(animal.target) <= 0.3:
					_rest(animal, now, 10, 30)
				else:
					# Something in the way (water, a cliff): on, another way.
					var heading := (animal.target - animal.position).normalized()
					animal.target = _way_out(animal, heading.rotated(1.0 if _rng.randf() < 0.5 else -1.0))
		AnimalData.State.SLEEP:
			if not def.sleeps_at(hour):
				_rest(animal, now, 5, 40)
		AnimalData.State.WANDER, AnimalData.State.DRINK:
			if _move(animal, animal.target, def.walk_speed * minutes) or now >= animal.state_until:
				if animal.state == AnimalData.State.DRINK:
					animal.drank_day = Config.time.day_index(now)
				_rest(animal, now, 20, 90)
		AnimalData.State.HUNT:
			_chase(animal, def, minutes, now)
		_:
			# (Sleep does not wait for whatever they were resting from.)
			if now >= animal.state_until or def.sleeps_at(hour):
				_decide(animal, def, now, hour)


## What the animal turns to after standing a while.
func _decide(animal: AnimalData, def: SpeciesDef, now: int, hour: float) -> void:
	if def.sleeps_at(hour):
		# Home first, if they are far from it (they sleep where they live).
		if animal.position.distance_to(animal.home) > def.home_range and animal.state != AnimalData.State.WANDER:
			animal.state = AnimalData.State.WANDER
			animal.target = _scatter(animal.home, minf(def.home_range * 0.4, 3.0))
			animal.state_until = now + 240
			return
		animal.state = AnimalData.State.SLEEP
		animal.state_until = now + 60
		return
	if def.diet == SpeciesDef.Diet.PREDATOR and now - animal.fed_tick >= roundi(def.hunts_every_days * TimeConfig.MINUTES_PER_DAY):
		var quarry := _prey_for(animal, def)
		if quarry != null:
			animal.state = AnimalData.State.HUNT
			animal.quarry_id = quarry.id
			animal.state_until = now + HUNT_MINUTES
			return
		animal.fed_tick = now - roundi(def.hunts_every_days * TimeConfig.MINUTES_PER_DAY * (1.0 - RETRY_SHARE))
	if animal.drank_day != Config.time.day_index(now) and hour >= 9.0 and _rng.randf() < 0.5:
		var shore := _shore_of(animal)
		if shore != Vector2.INF:
			animal.state = AnimalData.State.DRINK
			animal.target = _scatter(shore, 1.0)
			animal.state_until = now + 240
			return
		animal.drank_day = Config.time.day_index(now) # (no water in reach: they make do)
	# Somewhere else within where the group lives.
	for attempt in 6:
		var to := _scatter(animal.home, def.home_range)
		if _can_stand(WorldCoords.world2d_to_tile(to)):
			animal.state = AnimalData.State.WANDER
			animal.target = to
			animal.state_until = now + 180
			return
	_rest(animal, now, 20, 60)


func _rest(animal: AnimalData, now: int, least: int, most: int) -> void:
	animal.state = AnimalData.State.GRAZE
	animal.quarry_id = 0
	animal.state_until = now + _rng.randi_range(least, most)


func _flee(animal: AnimalData, from: Vector2, now: int) -> void:
	var away := animal.position - from
	if away.length() < 0.05:
		away = Vector2.RIGHT.rotated(_rng.randf() * TAU)
	if animal.state != AnimalData.State.FLEE and animal.state != AnimalData.State.HUNT:
		_hurried += 1
	animal.state = AnimalData.State.FLEE
	animal.target = _way_out(animal, away.normalized())
	animal.quarry_id = 0
	animal.state_until = now + FLEE_MINUTES
	fled.emit(animal.id)


## Where to run to: FLEE_DISTANCE along `heading` — or, if the first steps
## that way are shut (water, a cliff, the wall of the box), the nearest
## other way that is open. Where it stands if there is none.
func _way_out(animal: AnimalData, heading: Vector2) -> Vector2:
	var here := WorldCoords.world2d_to_tile(animal.position)
	var inside := Rect2(_world.bounds).grow(-0.6)
	for turn: float in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, PI]:
		var way := heading.rotated(turn)
		var first := animal.position + way * 1.0
		var second := animal.position + way * 2.0
		if not inside.has_point(first) or not _can_step(here, WorldCoords.world2d_to_tile(first)):
			continue
		if not inside.has_point(second) or not _can_step(WorldCoords.world2d_to_tile(first), WorldCoords.world2d_to_tile(second)):
			continue
		var to := animal.position + way * FLEE_DISTANCE
		return Vector2(clampf(to.x, inside.position.x, inside.end.x), clampf(to.y, inside.position.y, inside.end.y))
	return animal.position


## The nearest thing to run from within the animal's fear, or Vector2.INF.
func _threat(animal: AnimalData, def: SpeciesDef, about: Array, hunters: Array[AnimalData]) -> Vector2:
	if def.fear_radius <= 0.0:
		return Vector2.INF
	var nearest := Vector2.INF
	var nearest_distance := INF
	for entry: Array in about:
		var reach := def.fear_radius * (STALKED_SHARE if bool(entry[1]) else 1.0)
		var distance := animal.position.distance_to(entry[0])
		if distance <= reach and distance < nearest_distance:
			nearest = entry[0]
			nearest_distance = distance
	if def.diet == SpeciesDef.Diet.GRAZER:
		for other in hunters:
			var hunter := species.get_def(other.species)
			if hunter == null or not hunter.preys_on(animal.species):
				continue
			var distance := animal.position.distance_to(other.position)
			# (One that is after them is seen later than one that ambles past.)
			var reach := def.fear_radius * (0.35 if other.state == AnimalData.State.HUNT else 0.8)
			if distance <= reach and distance < nearest_distance:
				nearest = other.position
				nearest_distance = distance
	return nearest


func _prey_for(animal: AnimalData, def: SpeciesDef) -> AnimalData:
	# (The nearest there is, however far: a hungry fox goes where the rabbits are.)
	var best: AnimalData = null
	for other in registry.all_animals():
		if not def.preys_on(other.species):
			continue
		if best == null or other.position.distance_squared_to(animal.position) < best.position.distance_squared_to(animal.position):
			best = other
	return best


## A predator after its quarry.
func _chase(animal: AnimalData, def: SpeciesDef, minutes: int, now: int) -> void:
	var quarry := registry.get_animal(animal.quarry_id)
	if quarry == null or now >= animal.state_until:
		animal.fed_tick = now - roundi(def.hunts_every_days * TimeConfig.MINUTES_PER_DAY * (1.0 - RETRY_SHARE))
		_rest(animal, now, 30, 90)
		return
	var arrived := _move(animal, quarry.position, def.run_speed * minutes)
	if animal.position.distance_to(quarry.position) > POUNCE_REACH:
		if arrived:
			_rest(animal, now, 30, 90) # (it could not get to it)
		return
	# The pounce: likelier where prey is plentiful (the weak and unwary are
	# caught; the last few are hard to come by).
	var prey_def := species.get_def(quarry.species)
	var plenty := 1.0
	if prey_def != null:
		plenty = clampf(float(registry.count(quarry.species) - REFUGE) / maxf(prey_def.capacity - REFUGE, 1.0), 0.0, 1.0)
	if _rng.randf() < def.pounce_success * plenty:
		animal.home = animal.home.lerp(quarry.position, HOME_DRIFT)
		_die(quarry, &"prey")
		animal.fed_tick = now
		_rest(animal, now, 120, 240)
	else:
		_flee(quarry, animal.position, now)
		animal.fed_tick = now - roundi(def.hunts_every_days * TimeConfig.MINUTES_PER_DAY * (1.0 - RETRY_SHARE))
		_rest(animal, now, 60, 120)


## Moves `animal` up to `distance` tiles towards `to`. True if it is there
## (or can get no further).
func _move(animal: AnimalData, to: Vector2, distance: float) -> bool:
	var at := animal.position
	var left := distance
	var facing := animal.facing
	var there := false
	while left > 0.0001:
		var gap := at.distance_to(to)
		if gap <= 0.05:
			there = true
			break
		var stride := minf(minf(STRIDE, left), gap)
		var next := at + (to - at) / gap * stride
		if not _can_step(WorldCoords.world2d_to_tile(at), WorldCoords.world2d_to_tile(next)):
			there = true # (in the way: this is as far as it goes)
			break
		facing = (next - at).angle()
		at = next
		left -= stride
	if at != animal.position or facing != animal.facing:
		registry.move(animal.id, at, facing)
	return there


func _can_stand(tile: Vector2i) -> bool:
	if _world == null or not _world.bounds.has_point(tile) or _world.get_water(tile) > _wade:
		return false
	var prop := _props.prop_at(tile) if _props != null else null
	return prop == null or (prop.kind != PropData.Kind.HUT and prop.kind != PropData.Kind.CAMPFIRE and prop.kind != PropData.Kind.RUIN)


func _can_step(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
	return _can_stand(to) and absi(_world.get_height(to) - _world.get_height(from)) <= MAX_STEP_LEVELS


func _scatter(around: Vector2, spread: float) -> Vector2:
	var to := around + Vector2.RIGHT.rotated(_rng.randf() * TAU) * (sqrt(_rng.randf()) * spread)
	var inside := Rect2(_world.bounds).grow(-0.6)
	return Vector2(clampf(to.x, inside.position.x, inside.end.x), clampf(to.y, inside.position.y, inside.end.y))


## Where a group drinks: the water's edge nearest to where it lives.
func _shore_of(animal: AnimalData) -> Vector2:
	if _shores.has(animal.group):
		return _shores[animal.group]
	var best := Vector2.INF
	var best_distance := INF
	var home := WorldCoords.world2d_to_tile(animal.home)
	var reach := 22
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := home + Vector2i(dx, dy)
			if not _world.bounds.has_point(tile) or _world.get_water(tile) <= 0.0:
				continue
			var distance := Vector2(dx, dy).length()
			if distance >= best_distance:
				continue
			# The dry tile beside it that is nearest to home.
			for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var beside := tile + side
				if _world.bounds.has_point(beside) and _world.get_water(beside) <= 0.0 and _can_stand(beside):
					best = Vector2(beside) + Vector2(0.5, 0.5)
					best_distance = distance
					break
	_shores[animal.group] = best
	return best


# --- the days: who is born, who dies ------------------------------------------------------------------

func _days(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
	var made_up := 0
	while _day < today and made_up < 400:
		_day += 1
		made_up += 1
		_one_day(_day * TimeConfig.MINUTES_PER_DAY - roundi(Config.time.start_hour * 60.0))
	_day = today


func _one_day(now: int) -> void:
	var season := Config.time.season_of(now)
	# The first day of autumn and of spring: those who do move on.
	if Config.time.day_of_season(now) == 1 and (season == Seasons.AUTUMN or season == Seasons.SPRING):
		_migrate(now)
	elif Config.time.day_of_season(now) == JOURNEY_OVER_DAY and not _journeys.is_empty():
		_end_journeys(now, false)
	for id in species.ids():
		var def := species.get_def(id)
		if def.aggregate:
			# Fish come back towards what the water holds.
			fish = minf(fish + (fish_capacity - fish) * FISH_REGROWTH, fish_capacity)
			continue
		var all := registry.of_species(id)
		# The old die.
		var grown: Array[AnimalData] = []
		for animal in all:
			if animal.age_days(now) >= def.lifespan_days:
				# (The last pair is never without a successor.)
				if registry.count(id) <= LAST_PAIR:
					var heir := spawn(id, _scatter(animal.position, 0.6), animal.home, animal.group, now)
					if heir != null:
						born.emit(heir.id, id)
				_die(animal, &"age")
			elif animal.age_days(now) >= def.adult_days:
				grown.append(animal)
		var holds := _capacity(def)
		var here := registry.count(id)
		# More than the land (or their prey) can keep: the weakest go hungry.
		if here > holds and here > LAST_PAIR and _rng.randf() < 0.35:
			var hungry := registry.of_species(id)
			if not hungry.is_empty():
				_die(hungry[_rng.randi_range(0, hungry.size() - 1)], &"hunger")
				here -= 1
		# Young: the more, the more room there is; none without two grown ones.
		if grown.size() < 2 or here >= holds or not def.mates_in(season):
			continue
		var expected := def.birth_rate * def.mating_boost() * grown.size() * maxf(1.0 - float(here) / float(holds), 0.0)
		var due := expected + float(_births.get(id, 0.0))
		while due >= 1.0 and registry.count(id) < holds:
			due -= 1.0
			var parent: AnimalData = grown[_rng.randi_range(0, grown.size() - 1)]
			var young := spawn(id, _scatter(parent.position, 0.6), parent.home, parent.group, now)
			if young != null:
				born.emit(young.id, id)
		_births[id] = clampf(due, 0.0, 1.0)


## Every group of a species that migrates looks for other ground to live
## on, well away from where it lives now, and sets out for it.
func _migrate(_now: int) -> void:
	for id in species.ids():
		var def := species.get_def(id)
		if def.aggregate or not def.migrates:
			continue
		var homes := {} # group -> where it lives
		for animal in registry.of_species(id):
			homes[animal.group] = animal.home
		for group: int in homes:
			if _journeys.has(group):
				continue # (still on its way from last time)
			var from: Vector2 = homes[group]
			# Somewhere they can walk to without passing the people's huts.
			for found: Vector2 in _other_ground(from):
				if _pathfinder != null and not _clear_way(WorldCoords.world2d_to_tile(from), WorldCoords.world2d_to_tile(found),
						def.fear_radius + 2.0):
					continue
				_journeys[group] = found
				migrated.emit(id, group, found)
				break


## Open ground well away from `from` (and from the settlement) where a
## group might live: a few places, the best first.
func _other_ground(from: Vector2) -> Array[Vector2]:
	var b := _world.bounds.grow(-3)
	var scored: Array = [] # [how good, where]
	for attempt in 80:
		var tile := Vector2i(_rng.randi_range(b.position.x, b.end.x - 1), _rng.randi_range(b.position.y, b.end.y - 1))
		var at := Vector2(tile) + Vector2(0.5, 0.5)
		if at.distance_to(from) < MIGRATION_MIN_TILES or not _can_stand(tile) or _world.get_water(tile) > 0.0:
			continue
		var terrain := _world.get_terrain(tile)
		if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
			continue
		if _from_people(at) < SETTLEMENT_CLEARANCE:
			continue
		# (Green ground, and not further than need be: the further, the likelier the way leads past people.)
		var green := float(_world.chunk_at_tile(tile).vegetation[_world.index_at_tile(tile)]) / 255.0
		scored.append([green * 10.0 - at.distance_to(from) * 0.3, at])
	scored.sort_custom(func(a: Array, c: Array) -> bool: return a[0] > c[0])
	var places: Array[Vector2] = []
	for entry: Array in scored.slice(0, JOURNEY_TRIES):
		places.append(entry[1])
	return places


## Whether there is a way from one tile to another that keeps `clearance`
## tiles away from the settlement (animals do not walk past people).
func _clear_way(from: Vector2i, to: Vector2i, clearance: float) -> bool:
	var way := _pathfinder.find_path(from, to)
	if way.size() < 2:
		return false
	if _start == null:
		return true
	for tile in way:
		if _from_people(Vector2(tile)) < clearance:
			return false
	return true


## How far `at` is from the nearest settlement's fire (INF: there is none).
func _from_people(at: Vector2) -> float:
	var nearest := INF
	if not settlement_tiles.is_empty():
		for tile in settlement_tiles:
			nearest = minf(nearest, at.distance_to(Vector2(tile)))
	elif _start != null:
		nearest = at.distance_to(Vector2(_start.settlement_tile))
	return nearest


## Whether an animal is on its way to where its group is moving to.
func _on_journey(animal: AnimalData) -> bool:
	return not _journeys.is_empty() and _journeys.has(animal.group) and animal.home != _journeys[animal.group]


## Herds on their way: each one walks the way there, in the hours it is
## awake (a fright or a hunt comes first), and lives there once it arrives.
func _advance_journeys(minutes: int, now: int) -> void:
	var hour := Config.time.minute_of_day(now) / 60.0
	var arrived := {} # group -> whether nobody of it is still on the way
	for group: int in _journeys:
		arrived[group] = true
	for animal in registry.all_animals():
		if not _on_journey(animal):
			continue
		var to: Vector2 = _journeys[animal.group]
		arrived[animal.group] = false
		var def := species.get_def(animal.species)
		if def == null or animal.state == AnimalData.State.FLEE or animal.state == AnimalData.State.HUNT:
			_forget_way(animal.id)
			continue
		if def.sleeps_at(hour):
			animal.state = AnimalData.State.SLEEP # (where they are: there is no going home)
			continue
		animal.state = AnimalData.State.WANDER
		animal.target = to
		if animal.position.distance_to(to) <= JOURNEY_ARRIVED or _follow(animal, to, def.walk_speed * JOURNEY_PACE * minutes):
			animal.home = to
			_forget_way(animal.id)
			_rest(animal, now, 20, 60)
	for group: int in arrived:
		if arrived[group]:
			_journeys.erase(group)


## Moves an animal up to `distance` tiles along its way to `to`. True if
## it is there — or there is no way for it (then it tries as it always
## does: straight for where it lives).
func _follow(animal: AnimalData, to: Vector2, distance: float) -> bool:
	var way: PackedVector2Array = _ways.get(animal.id, PackedVector2Array())
	var index: int = _way_at.get(animal.id, 0)
	if way.is_empty() or index >= way.size() or animal.position.distance_to(way[index]) > 1.6:
		# No way yet, or it was driven off it: from where it stands.
		way = PackedVector2Array()
		if _pathfinder != null:
			for tile in _pathfinder.find_path(WorldCoords.world2d_to_tile(animal.position), WorldCoords.world2d_to_tile(to)):
				way.append(Vector2(tile) + Vector2(0.5, 0.5))
		if way.size() < 2:
			return true
		index = 0
		_ways[animal.id] = way
	var at := animal.position
	var facing := animal.facing
	var left := distance
	while left > 0.0001 and index < way.size():
		var gap := at.distance_to(way[index])
		if gap <= 0.05:
			index += 1
			continue
		var stride := minf(left, gap)
		var next := at + (way[index] - at) / gap * stride
		facing = (next - at).angle()
		at = next
		left -= stride
	_way_at[animal.id] = index
	if at != animal.position or facing != animal.facing:
		registry.move(animal.id, at, facing)
	return index >= way.size()


func _forget_way(id: int) -> void:
	_ways.erase(id)
	_way_at.erase(id)


## The journeys are over. `there`: time went by that nobody lived through,
## and those on the way have arrived; otherwise they have been long enough
## about it, and whoever is still on the way gets there as it can.
func _end_journeys(now: int, there: bool) -> void:
	for animal in registry.all_animals():
		if not _on_journey(animal):
			continue
		var to: Vector2 = _journeys[animal.group]
		if there:
			var at := to
			for attempt in 6:
				var near := _scatter(to, 2.0)
				if _can_stand(WorldCoords.world2d_to_tile(near)):
					at = near
					break
			registry.move(animal.id, at, animal.facing)
		animal.home = to
		_rest(animal, now, 20, 60)
	_journeys.clear()
	_ways.clear()
	_way_at.clear()


## How many herds are on their way to other ground.
func journey_count() -> int:
	return _journeys.size()


## How many of a species the box keeps: its capacity — and for a predator,
## no more than its prey supports.
func _capacity(def: SpeciesDef) -> int:
	if def.diet != SpeciesDef.Diet.PREDATOR:
		return def.capacity
	var prey := 0
	for id in def.prey:
		prey += registry.count(StringName(id))
	return clampi(floori(prey * def.per_prey), 1, def.capacity)


func _die(animal: AnimalData, cause: StringName) -> void:
	var at := animal.position
	var kind := animal.species
	var id := animal.id
	registry.remove(id)
	died.emit(id, kind, cause, at)


# --- setting up -------------------------------------------------------------------------------------

func _count_water() -> void:
	var tiles := 0
	if _world != null:
		for coord in _world.chunk_coords():
			var chunk := _world.get_chunk(coord, false)
			if chunk == null:
				continue
			for depth in chunk.water:
				if depth > 0.0:
					tiles += 1
	fish_capacity = tiles / WATER_TILES_PER_FISH
	fish = minf(fish, fish_capacity)


## Somewhere for a group to live: open ground they can stand on, away from
## the settlement and (for those who fear them) from where predators live.
func _find_home(def: SpeciesDef) -> Variant:
	var b := _world.bounds.grow(-3)
	var best: Variant = null
	var best_score := -INF
	for attempt in 60:
		var tile := Vector2i(_rng.randi_range(b.position.x, b.end.x - 1), _rng.randi_range(b.position.y, b.end.y - 1))
		if not _can_stand(tile) or _world.get_water(tile) > 0.0:
			continue
		var terrain := _world.get_terrain(tile)
		if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
			continue
		var from_people := minf(_from_people(Vector2(tile)), 100.0)
		if from_people < SETTLEMENT_CLEARANCE:
			continue
		# Green ground, not on top of another group.
		var chunk := _world.chunk_at_tile(tile)
		var score := float(chunk.vegetation[_world.index_at_tile(tile)]) / 255.0 * 10.0 + minf(from_people, 30.0) * 0.1
		# Where people can walk to, rather than across water they cannot cross.
		if _pathfinder != null and _start != null and _pathfinder.is_reachable(_start.settlement_tile + Vector2i(1, 0), tile):
			score += 12.0
		for other in registry.all_animals():
			if other.home.distance_to(Vector2(tile)) < 8.0:
				score -= 6.0
				break
		if score > best_score:
			best_score = score
			best = Vector2(tile) + Vector2(0.5, 0.5)
	return best
