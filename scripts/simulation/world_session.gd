class_name WorldSession
extends Node
## Owns ALL state of the currently open world (bible §31.3, D-06).
##
## Deliberately not an autoload: New World / Reset / tests create and free
## sessions cleanly. Systems (people, environment, ...) are added as
## children/fields of this node in later milestones.
##
## World persistence is sparse (bible §8.4): the save holds only what differs
## from the generator's output — modified chunks, removed/added props — plus the
## start info, so an untouched world costs almost nothing to save.

## Emitted by shutdown() while the world is still active, so listeners (e.g.
## SaveManager) can persist it on every orderly exit path.
signal about_to_close

const FORMAT_KEYS: PackedStringArray = ["world_id", "world_seed", "created_unix", "clock", "ids", "rng"]
const DEFAULT_TEMPLATE_ID := &"river_valley"
const TEMPLATE_DIR := "res://data/worldgen/"
## A random seed whose world is not livable is re-rolled up to this many times.
const MAX_SEED_ATTEMPTS := 8
## The culture of the starting band (cultures become entities in M17).
const FIRST_CULTURE_ID := 1

var world_id: String = ""
var world_seed: int = 0
var created_unix: int = 0
var clock: GameClock
var ids: IdAllocator
var rng: RngStreams
var is_active := false

## The tile world and what stands on it.
var template_id: StringName = DEFAULT_TEMPLATE_ID
var world: WorldData
var generator: WorldGenerator
var props: PropRegistry
var spatial: SpatialIndex
## Things lying in the world that can be moved (rocks, boulders, ...).
var loose: LooseObjectRegistry
var start: WorldSetup.StartInfo
## Where every player touch of the world is answered.
var interactions: InteractionManager
## Moves the loose objects that are not at rest.
var loose_system: LooseObjectSystem
## Moves the water.
var water: WaterSim
## How the river stands: rain, dry weeks, floods (the coarse side of the water).
var hydrology: Hydrology
## Which of the player's powers have shown themselves (rain, wind, water).
var powers: ToolReveals
## The soil of all the land, and what grows on it.
var soil: SoilSystem
var vegetation: VegetationSystem
## What the player has done to this world.
var history: PlayerHistory
## Everyone who lives here.
var people: PersonRegistry
## Makes names in the sounds of the first culture.
var names: NameGenerator
## What people can do with their days (data/occupations).
var occupations: OccupationLibrary
## Finds ways across the world on foot.
var pathfinder: Pathfinder
## Walks people along those ways.
var movement: MovementSystem
## What people can decide to do (data/activities).
var activities: ActivityLibrary
## People living their days: needs, decisions, plans.
var behavior: BehaviorSystem
## Who notices what the player (and the world) does.
var perception: PerceptionSystem
## What everyone remembers.
var memories: MemoryStore
## What everyone has been doing lately (the card's "Today").
var day_log: DayLog
## What resources there are (data/resources), what the world's nodes still
## hold, and the piles of what has been gathered.
var resources: ResourceLibrary
var nodes: ResourceNodes
var piles: PileStore
## The settlement around the fire: its stores, its job board (null in a
## world without one).
var settlement: Settlement
## The fields and what grows on them.
var farming: Farming
## What the player does frightens the animals at least this near to it (tiles).
const STARTLE_RADIUS := 3.0
## The weather: what the sky does, how warm it is, what has fallen.
var weather: WeatherSystem
## What kinds of animals there are, the animals themselves, and their lives.
var species: SpeciesLibrary
var animals: AnimalRegistry
var fauna: AnimalSystem
## How long the player has stayed with one person (the OBSERVER achievement).
var observer: ObserverWatch
## What has happened in this world, and what led to what (data/events).
var event_defs: EventLibrary
var events: EventLog
## Writes it down as it happens.
var chronicle: Chronicler
## The world's numbers, hour by hour.
var stats: StatsRecorder
## Makes time pass for all of that, in turns and within a budget.
var simulation: SimulationManager
var _saved_water: Dictionary = {} # the water's books from a save, until the water is bound
var _saved_hydrology: Dictionary = {}
var _saved_soil: Dictionary = {}
var _saved_vegetation: Dictionary = {}
var _saved_powers: Dictionary = {}
var _powers_looked := -1_000_000 # the game hour the dry-crop look was last taken in
var _saved_behavior: Dictionary = {} # likewise what the band knows, until behaviour is bound
var _saved_memories: Dictionary = {} # likewise what everyone remembers
var _saved_perception: Dictionary = {}
var _saved_day_log: Dictionary = {}
var _saved_settlement: Dictionary = {}
var _saved_farming: Dictionary = {}
var _saved_animals: Dictionary = {}
var _saved_events: Dictionary = {}
var _saved_weather: Dictionary = {}
var _saved_chronicle: Dictionary = {}
var _saved_stats: Dictionary = {}


func _init() -> void:
	day_log = DayLog.new()
	observer = ObserverWatch.new()
	nodes = ResourceNodes.new()
	piles = PileStore.new()
	farming = Farming.new()
	fauna = AnimalSystem.new()
	weather = WeatherSystem.new()
	events = EventLog.new()
	chronicle = Chronicler.new()
	stats = StatsRecorder.new()
	stats.source = sample_stats
	# What the fields and the stores report is written down (see Chronicler).
	farming.first_field.connect(chronicle.on_first_field)
	farming.failed.connect(chronicle.on_crop_failed)
	farming.sown_thin.connect(chronicle.on_sown_thin)
	farming.harvest_thin.connect(chronicle.on_harvest_thin)
	farming.dry_spell.connect(chronicle.on_dry_spell)
	piles.stored.connect(chronicle.on_stored)
	weather.changed.connect(chronicle.on_weather_changed)
	weather.condition_changed.connect(chronicle.on_condition_changed)
	# The fields' rain is the weather's, and its frost.
	farming.rain_source = weather.rain_on
	farming.frozen_source = weather.is_frozen
	farming.frost_killed.connect(chronicle.on_crop_frozen)
	# The river: its level is the weather's doing; the fields feel it.
	hydrology = Hydrology.new()
	hydrology.settled_source = settled_tiles
	hydrology.occupied_source = func(tile: Vector2i) -> bool:
		return props != null and props.prop_at(tile) != null
	hydrology.high_water_changed.connect(chronicle.on_high_water)
	hydrology.low_water_changed.connect(chronicle.on_low_water)
	hydrology.flood_changed.connect(chronicle.on_flood)
	hydrology.eroded.connect(chronicle.on_bank_eroded)
	farming.groundwater_source = hydrology.groundwater
	farming.drying_source = hydrology.drying
	# The land: its soil, its grass and its trees.
	soil = SoilSystem.new()
	vegetation = VegetationSystem.new()
	nodes.depleted.connect(vegetation.on_depleted)
	nodes.regrown.connect(vegetation.on_regrown)
	vegetation.tree_died.connect(chronicle.on_tree_died)
	# The player's powers show themselves when the world gives the idea of them.
	powers = ToolReveals.new()
	weather.changed.connect(func(_old: StringName, now: StringName) -> void:
		if is_active:
			powers.on_weather(now, clock.tick))
	fauna.migrated.connect(chronicle.on_migrated)
	# Shallow water that is frozen carries.
	weather.frozen_changed.connect(func(frozen: bool) -> void:
		pathfinder.set_frozen(frozen, Config.seasons.ice_depth))
	# A field is sown with grain from the stores.
	farming.seed_source = func(units: int) -> bool:
		return settlement != null and settlement.stockpile.take(&"grain", units) == units
	nodes.reaped.connect(func(prop_id: int) -> void:
		var crop := props.get_prop(prop_id) if props != null else null
		if crop != null:
			farming.reaped(crop, clock.tick))
	interactions = InteractionManager.new()
	interactions.name = "InteractionManager"
	add_child(interactions)
	loose_system = LooseObjectSystem.new()
	loose_system.name = "LooseObjectSystem"
	add_child(loose_system)
	water = WaterSim.new()
	water.name = "WaterSim"
	add_child(water)
	water.tiles_changed.connect(loose_system.on_water_changed)
	pathfinder = Pathfinder.new()
	movement = MovementSystem.new()
	behavior = BehaviorSystem.new()
	perception = PerceptionSystem.new()
	memories = MemoryStore.new()
	interactions.stimulus_emitted.connect(perception.emit)
	# What the player does startles the animals near it.
	interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void:
		if stimulus != null and clock != null:
			fauna.startle(stimulus.position, maxf(stimulus.radius, STARTLE_RADIUS), clock.tick))
	perception.noticed.connect(behavior.notice)
	interactions.intervention_applied.connect(chronicle.on_intervention)
	interactions.intervention_applied.connect(func(iv: Intervention) -> void:
		if iv != null and iv.applied and iv.type == Intervention.TOUCH and iv.subject == &"water":
			powers.on_water_touched(history.count(Intervention.TOUCH, &"water"), clock.tick))
	behavior.hunted.connect(chronicle.on_hunted)
	behavior.fell_ill.connect(chronicle.on_fell_ill)
	behavior.recovered.connect(chronicle.on_recovered)
	simulation = SimulationManager.new()
	simulation.name = "SimulationManager"
	add_child(simulation)


## Starts a brand-new world. seed_value 0 picks a random seed and re-rolls it
## until the world is livable; an explicit seed is always used as given.
func create_new(seed_value: int = 0) -> void:
	if is_active:
		shutdown()
	created_unix = int(Time.get_unix_time_from_system())
	clock = GameClock.new(Config.time)
	template_id = DEFAULT_TEMPLATE_ID
	history = PlayerHistory.new()
	observer.reset()
	_saved_behavior = {}
	_saved_memories = {}
	_saved_perception = {}
	_saved_day_log = {}
	_saved_events = {}
	_saved_chronicle = {}
	_saved_stats = {}
	_saved_weather = {}
	_saved_hydrology = {}
	_saved_soil = {}
	_saved_vegetation = {}
	_saved_powers = {}
	var explicit := seed_value != 0
	for attempt in MAX_SEED_ATTEMPTS:
		world_seed = seed_value if explicit else RngStreams.new_world_seed()
		ids = IdAllocator.new()
		_build_new_world(ids)
		if start.ok or explicit:
			break
		Log.warn(Log.Category.WORLD, "Re-rolling seed: world not livable", {"seed": world_seed, "problems": start.problems})
	if not start.ok:
		Log.warn(Log.Category.WORLD, "World has problems", {"seed": world_seed, "problems": start.problems})
	world_id = _make_world_id(world_seed, created_unix)
	rng = RngStreams.new(world_seed)
	_restore_people({})
	_activate()
	if settlement != null:
		# (What it is given to begin with is no event; that it began is the first.)
		chronicle.listening = false
		settlement.stock_up(clock.tick)
		chronicle.listening = true
		chronicle.founded()
		settlement.ensure_farmer(clock.tick)
		settlement.ensure_hunter(clock.tick)
	Log.info(Log.Category.WORLD, "New world created", {"world_id": world_id, "seed": world_seed})


## Restores a world from to_dict() output. Returns false (and stays inactive)
## if the data is unusable; the caller decides how to recover.
func load_from(data: Dictionary) -> bool:
	for key in FORMAT_KEYS:
		if not data.has(key):
			Log.error(Log.Category.LOAD, "World data missing key", {"key": key})
			return false
	if is_active:
		shutdown()
	world_id = String(data["world_id"])
	world_seed = int(data["world_seed"])
	created_unix = int(data["created_unix"])
	clock = GameClock.new(Config.time)
	clock.from_dict(data["clock"])
	ids = IdAllocator.new()
	ids.from_dict(data["ids"])
	rng = RngStreams.new(world_seed)
	rng.from_dict(data["rng"])

	var state: Variant = data.get("world_state", {})
	history = PlayerHistory.new()
	_saved_water = {}
	_saved_behavior = {}
	_saved_memories = {}
	_saved_perception = {}
	_saved_day_log = {}
	_saved_settlement = {}
	_saved_farming = {}
	_saved_animals = {}
	_saved_events = {}
	_saved_chronicle = {}
	_saved_stats = {}
	_saved_weather = {}
	_saved_hydrology = {}
	_saved_soil = {}
	_saved_vegetation = {}
	_saved_powers = {}
	observer.reset()
	if typeof(state) == TYPE_DICTIONARY:
		if typeof((state as Dictionary).get("powers")) == TYPE_DICTIONARY:
			_saved_powers = state["powers"]
		if typeof((state as Dictionary).get("soil")) == TYPE_DICTIONARY:
			_saved_soil = state["soil"]
		if typeof((state as Dictionary).get("vegetation")) == TYPE_DICTIONARY:
			_saved_vegetation = state["vegetation"]
		if typeof((state as Dictionary).get("hydrology")) == TYPE_DICTIONARY:
			_saved_hydrology = state["hydrology"]
		if typeof((state as Dictionary).get("weather")) == TYPE_DICTIONARY:
			_saved_weather = state["weather"]
		if typeof((state as Dictionary).get("events")) == TYPE_DICTIONARY:
			_saved_events = state["events"]
		if typeof((state as Dictionary).get("chronicle")) == TYPE_DICTIONARY:
			_saved_chronicle = state["chronicle"]
		if typeof((state as Dictionary).get("stats")) == TYPE_DICTIONARY:
			_saved_stats = state["stats"]
		if typeof((state as Dictionary).get("animals")) == TYPE_DICTIONARY:
			_saved_animals = state["animals"]
		if typeof((state as Dictionary).get("farming")) == TYPE_DICTIONARY:
			_saved_farming = state["farming"]
		if typeof((state as Dictionary).get("settlement")) == TYPE_DICTIONARY:
			_saved_settlement = state["settlement"]
		if typeof((state as Dictionary).get("day_log")) == TYPE_DICTIONARY:
			_saved_day_log = state["day_log"]
		if typeof((state as Dictionary).get("observer")) == TYPE_DICTIONARY:
			observer.from_dict(state["observer"])
		if typeof((state as Dictionary).get("history")) == TYPE_DICTIONARY:
			history.from_dict(state["history"])
		if typeof((state as Dictionary).get("water")) == TYPE_DICTIONARY:
			_saved_water = state["water"]
		if typeof((state as Dictionary).get("behavior")) == TYPE_DICTIONARY:
			_saved_behavior = state["behavior"]
		if typeof((state as Dictionary).get("memories")) == TYPE_DICTIONARY:
			_saved_memories = state["memories"]
		if typeof((state as Dictionary).get("perception")) == TYPE_DICTIONARY:
			_saved_perception = state["perception"]
	if typeof(state) != TYPE_DICTIONARY or not _restore_world(state):
		# No usable world state (a migrated version-1 save, or damaged data):
		# rebuild from the seed. The setup's props take the same low ids they
		# had when the world was created; keep the allocator clear of them.
		if typeof(state) == TYPE_DICTIONARY and not (state as Dictionary).is_empty():
			Log.error(Log.Category.LOAD, "World state unusable; rebuilding the world from its seed")
		template_id = DEFAULT_TEMPLATE_ID
		var setup_ids := IdAllocator.new()
		_build_new_world(setup_ids)
		ids.reserve_above(setup_ids.peek() - 1)
	var saved_people: Variant = (state as Dictionary).get("people") if typeof(state) == TYPE_DICTIONARY else null
	_restore_people(saved_people if typeof(saved_people) == TYPE_DICTIONARY else {})
	_activate()
	Log.info(Log.Category.LOAD, "World loaded", {"world_id": world_id, "tick": clock.tick})
	return true


## Tells the world whom the camera is with right now (0 = nobody): staying
## with one person for a whole day is the OBSERVER achievement. Returns true
## at the moment it is unlocked.
func watch_followed(person_id: int) -> bool:
	if not is_active or history.has_achievement(PlayerHistory.OBSERVER):
		return false
	if person_id != 0 and people.get_person(person_id) == null:
		person_id = 0
	if not observer.update(clock.tick, person_id):
		return false
	history.unlock(PlayerHistory.OBSERVER, clock.tick)
	for achievement in history.take_unlocked():
		Log.info(Log.Category.WORLD, "Achievement unlocked", {"achievement": achievement, "tick": clock.tick})
		EventBus.achievement_unlocked.emit(achievement)
	SaveManager.note_world_changed()
	return true


## Everything about the world that is saved. (Before it is written, everyone
## lives the time that has built up for them: nobody is saved "behind".)
func to_dict() -> Dictionary:
	if is_active:
		simulation.settle()
	return {
		"world_id": world_id,
		"world_seed": world_seed,
		"created_unix": created_unix,
		"clock": clock.to_dict(),
		"ids": ids.to_dict(),
		"rng": rng.to_dict(),
		"world_state": {
			"template_id": String(template_id),
			"generator_version": WorldGenerator.GENERATOR_VERSION,
			"world": world.to_dict(),
			"props": props.to_dict(),
			"loose": loose.to_dict(),
			"history": history.to_dict(),
			"water": water.to_dict(),
			"people": people.to_dict(),
			"behavior": behavior.to_dict(),
			"memories": memories.to_dict(),
			"day_log": day_log.to_dict(),
			"observer": observer.to_dict(),
			"settlement": settlement.to_dict() if settlement != null else {},
			"farming": farming.to_dict(),
			"animals": fauna.to_dict(),
			"events": events.to_dict(),
			"chronicle": chronicle.to_dict(),
			"stats": stats.to_dict(),
			"weather": weather.to_dict(),
			"hydrology": hydrology.to_dict(),
			"powers": powers.to_dict(),
			"soil": soil.to_dict(),
			"vegetation": vegetation.to_dict(),
			"perception": {"next_stimulus_id": behavior.ctx.next_stimulus_id if behavior.ctx != null else 1},
			"start": start.to_dict(),
		},
	}


func shutdown() -> void:
	if not is_active:
		return
	about_to_close.emit()
	is_active = false
	movement.stop_all()
	clock.speed_changed.disconnect(_on_speed_changed)
	clock.day_started.disconnect(_on_day_started)
	clock.season_changed.disconnect(_on_season_changed)
	clock.year_started.disconnect(_on_year_started)
	Log.info(Log.Category.WORLD, "World closed", {"world_id": world_id})
	EventBus.world_unloaded.emit()


## Freeing the session always closes the world cleanly.
func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	if is_active:
		simulation.advance(delta)
		weather.advance_to(clock.tick)
		soil.advance_to(clock.tick)
		_look_for_powers()
		if nodes.due(clock.tick):
			nodes.settle(clock.tick)
		if settlement != null:
			settlement.step(clock.tick)
		fauna.advance_to(clock.tick)
		stats.advance_to(clock.tick)


## Once a game hour: does a crop stand dry in the field (the idea of rain)?
func _look_for_powers() -> void:
	@warning_ignore("integer_division")
	var hour := clock.tick / 60
	if hour == _powers_looked or powers.is_known(ToolReveals.RAIN):
		return
	_powers_looked = hour
	for crop in farming.crops():
		if Farming.looks_dry(crop):
			powers.on_dry_crop(clock.tick)
			return


## The tiles where people live and work: their huts, the fire, the fields.
func settled_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if props == null:
		return tiles
	for prop in props.all_props():
		if prop.kind == PropData.Kind.HUT or prop.kind == PropData.Kind.CAMPFIRE or prop.kind == PropData.Kind.CROP:
			tiles.append(prop.tile)
	return tiles


## Where the settlement keeps `resource` (the middle of its storage tile),
## or Vector2.INF if it has no such place.
func storage_place(resource: StringName) -> Vector2:
	var places := behavior.ctx.places if behavior.ctx != null else null
	var tile: Variant = places.storage_tile(resource) if places != null else null
	return Places.middle_of(tile) if tile != null else Vector2.INF


## How much of `resource` the settlement has in store: what lies in piles at
## its storage place (a pile carried off is no longer its own).
func stored(resource: StringName) -> int:
	var at := storage_place(resource)
	return piles.total(resource, at, Config.resources.storage_radius) if at != Vector2.INF else 0


## The world's numbers as they are now (what the StatsRecorder writes down
## every game hour).
func sample_stats() -> Dictionary:
	var count := 0
	var health := 0.0
	var mood := 0.0
	for person in people.all_people():
		count += 1
		health += person.health
		mood += Needs.mood(person.needs)
	var stores := settlement.stockpile if settlement != null else null
	return {
		&"population": float(count),
		&"food": stores.food() if stores != null else 0.0,
		&"water": water.total_volume(),
		&"trees": float(vegetation.tree_count()),
		&"grass": vegetation.grass_cover(),
		&"wood": float(stores.amount(&"wood")) if stores != null else 0.0,
		&"stone": float(stores.amount(&"stone")) if stores != null else 0.0,
		&"health": health / count if count > 0 else 0.0,
		&"temperature": weather.temperature(clock.tick),
		&"mood": mood / count if count > 0 else 0.0,
	}


## Generates terrain, props and the starting settlement for `world_seed`.
func _build_new_world(setup_ids: IdAllocator) -> void:
	var started := Time.get_ticks_msec()
	var template := _load_template(template_id)
	world = WorldData.create_centered(Config.world.initial_world_tiles, Config.world.chunk_size, Config.world.height_step)
	generator = WorldGenerator.new(world_seed, template, Config.world)
	world.set_generator(generator)
	spatial = SpatialIndex.new(SpatialIndex.FINE_CELL_TILES)
	props = PropRegistry.new(world.chunk_size, spatial)
	loose = LooseObjectRegistry.new(world.chunk_size, spatial)
	start = WorldSetup.create_start(world, generator, props, setup_ids, loose)
	Log.debug(Log.Category.WORLD, "World built", {
		"ms": Time.get_ticks_msec() - started,
		"tiles": world.bounds.size,
		"props": props.size(),
		"loose": loose.size(),
		"settlement": start.settlement_tile,
	})


## The inhabitants: restored from `saved` (PersonRegistry.to_dict()), or — for
## a new world, a world saved before it had people, or unusable data — the
## starting band, made from the world's "people" dice. A world whose people
## are all gone stays empty: only a missing record brings a new band.
func _restore_people(saved: Dictionary) -> void:
	people = PersonRegistry.new(spatial)
	names = NameGenerator.new(Phonology.from_seed(RngStreams.derive_seed(world_seed, &"culture:%d" % FIRST_CULTURE_ID)))
	if occupations == null:
		occupations = OccupationLibrary.load_from()
	if saved.has("persons"):
		var skipped := people.from_dict(saved)
		if skipped >= 0:
			if skipped > 0:
				Log.warn(Log.Category.LOAD, "Some saved people were unusable and skipped", {"people": skipped})
			for person in people.all_people():
				ids.reserve_above(person.id)
			return
		Log.error(Log.Category.LOAD, "Saved people unusable; a new band arrives")
	if start == null or start.campfire_id == 0:
		return # nowhere to live (the world has no settlement)
	var band := StartingBand.spawn(people, ids, rng.stream(&"people"), names, occupations, world, props, start,
		clock.tick, Config.people, Config.time.ticks_per_year(), loose)
	Log.info(Log.Category.SIM, "The first band arrives", {
		"people": band.size(), "households": people.household_ids().size(), "settlement": start.settlement_id})
	for person in band:
		Log.debug(Log.Category.SIM, "  %s" % person.full_name(), {
			"age": person.age_years(clock.tick, Config.time.ticks_per_year()),
			"occupation": person.occupation_id, "household": person.household_id, "at": person.position})


# --- debug commands -----------------------------------------------------------------------------

## Debug: brings someone new into the world, at (or beside) `near`. They join
## the settlement as a household of their own. Null if there is no settlement.
func spawn_person(near: Vector2i, stage: PersonData.LifeStage = PersonData.LifeStage.ADULT) -> PersonData:
	if not is_active or start == null or start.campfire_id == 0:
		return null
	var person := PersonFactory.newcomer(ids, rng.stream(&"people"), names, occupations, people, start, pathfinder,
		clock.tick, near, stage)
	people.add(person)
	Log.info(Log.Category.SIM, "Someone arrives", {"person": person.full_name(), "id": person.id, "at": person.position,
		"occupation": person.occupation_id})
	EventBus.person_born.emit(person.id)
	return person


## Debug: takes someone out of the world. Those who knew them keep their ids
## (lineage outlives people).
func kill_person(person_id: int, cause: StringName = &"debug") -> bool:
	var person := people.get_person(person_id) if is_active else null
	if person == null:
		return false
	Log.info(Log.Category.SIM, "Someone is gone", {"person": person.full_name(), "id": person_id, "cause": cause})
	people.remove(person_id)
	EventBus.person_died.emit(person_id, cause)
	return true


## Rebuilds the world from saved state: generator output + saved differences.
## Returns false if the state cannot be used (the caller then regenerates).
func _restore_world(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var world_data: Variant = state.get("world")
	var props_data: Variant = state.get("props")
	var start_data: Variant = state.get("start")
	if typeof(world_data) != TYPE_DICTIONARY or typeof(props_data) != TYPE_DICTIONARY \
			or typeof(start_data) != TYPE_DICTIONARY:
		return false
	var started := Time.get_ticks_msec()
	var restored := WorldData.new()
	var skipped_chunks := restored.from_dict(world_data)
	if skipped_chunks < 0 or restored.bounds.size.x <= 0 or restored.bounds.size.y <= 0:
		return false
	var restored_start := WorldSetup.StartInfo.from_dict(start_data)
	if restored_start == null:
		return false

	var saved_template := StringName(str(state.get("template_id", DEFAULT_TEMPLATE_ID)))
	var saved_generator := int(state.get("generator_version", WorldGenerator.GENERATOR_VERSION))
	if saved_generator != WorldGenerator.GENERATOR_VERSION:
		# Unmodified chunks are regenerated, so a different generator changes them.
		Log.warn(Log.Category.LOAD, "World was created by a different generator version",
			{"saved": saved_generator, "current": WorldGenerator.GENERATOR_VERSION})

	# The generator must use the world's own geometry, not today's config.
	var world_config := Config.world.duplicate() as WorldConfig
	world_config.chunk_size = restored.chunk_size
	world_config.height_step = restored.height_step
	var restored_generator := WorldGenerator.new(world_seed, _load_template(saved_template), world_config)
	restored.set_generator(restored_generator)
	var restored_spatial := SpatialIndex.new(SpatialIndex.FINE_CELL_TILES)
	var restored_props := PropRegistry.new(restored.chunk_size, restored_spatial)
	var skipped_props := restored_props.from_dict(props_data)
	if skipped_props < 0:
		return false
	var restored_loose := LooseObjectRegistry.new(restored.chunk_size, restored_spatial)
	var loose_data: Variant = state.get("loose")
	var skipped_loose := 0
	if typeof(loose_data) == TYPE_DICTIONARY: # (always there since save version 3)
		skipped_loose = restored_loose.from_dict(loose_data)
		if skipped_loose < 0:
			return false
	WorldSetup.populate_all(restored, restored_generator, restored_props, restored_loose)

	template_id = saved_template
	world = restored
	generator = restored_generator
	spatial = restored_spatial
	props = restored_props
	loose = restored_loose
	start = restored_start
	if skipped_chunks > 0 or skipped_props > 0 or skipped_loose > 0:
		Log.warn(Log.Category.LOAD, "Some saved world records were unusable and skipped",
			{"chunks": skipped_chunks, "props": skipped_props, "loose": skipped_loose})
	Log.debug(Log.Category.WORLD, "World restored", {
		"ms": Time.get_ticks_msec() - started,
		"modified_chunks": world.modified_chunks().size(),
		"props": props.size(),
	})
	return true


func _load_template(id: StringName) -> StartTemplate:
	var path := "%s%s.tres" % [TEMPLATE_DIR, id]
	var template: StartTemplate = null
	if ResourceLoader.exists(path):
		template = load(path) as StartTemplate
	if template == null:
		Log.error(Log.Category.WORLD, "Start template missing; using defaults", {"path": path})
		template = StartTemplate.new()
	return template


func _activate() -> void:
	water.bind(world, generator)
	water.from_dict(_saved_water)
	_saved_water = {}
	loose_system.bind(world, loose, props, water.current_at)
	interactions.bind(world, props, loose, loose_system, ids, rng)
	var fire_at := Vector2.INF
	if start != null and start.campfire_id != 0:
		fire_at = Vector2(start.settlement_tile) + Vector2(0.5, 0.5)
	interactions.bind_session(water, clock, history, fire_at)
	interactions.bind_people(people)
	interactions.bind_animals(fauna)
	interactions.bind_environment(weather, hydrology, func(tile: Vector2i) -> int:
		return int(generator.sample_tile(tile)["height"]) if generator != null else world.get_height(tile))
	pathfinder.bind(world, props, loose, water)
	movement.bind(people, pathfinder, clock)
	if activities == null:
		activities = ActivityLibrary.load_from()
	var ai := AiContext.new()
	ai.world = world
	ai.props = props
	ai.people = people
	ai.pathfinder = pathfinder
	ai.movement = movement
	ai.clock = clock
	ai.start = start
	ai.occupations = occupations
	ai.activities = activities
	ai.places = Places.new(world, props, people, pathfinder, start)
	if resources == null:
		resources = ResourceLibrary.load_from()
	nodes.bind(props, Config.resources)
	piles.bind(loose, ids, resources, Config.resources)
	ai.nodes = nodes
	ai.piles = piles
	ai.resources = resources
	ai.places.resources = resources
	ai.places.nodes = nodes
	# The weather: where the save left it (a world from before there was any
	# begins under a clear sky, now).
	var level := world.get_height(start.settlement_tile) if start != null and start.campfire_id != 0 else 0
	weather.bind(clock, Config.climate, world_seed, world, level)
	weather.from_dict(_saved_weather)
	_saved_weather = {}
	# The river stands where the save left it (and goes on with the weather).
	hydrology.bind(world, water, weather, Config.hydrology, world_seed, generator.water_surface_height())
	hydrology.from_dict(_saved_hydrology)
	_saved_hydrology = {}
	water.river_flow = hydrology.flow()
	weather.advance_to(clock.tick)
	pathfinder.set_frozen(weather.frozen, Config.seasons.ice_depth)
	ai.weather = weather
	farming.bind(world, props, ids, pathfinder, start, people, occupations, generator, world_seed, Config.farming)
	farming.from_dict(_saved_farming)
	_saved_farming = {}
	ai.farming = farming
	# The land's soil and plants go on from where the save left them.
	soil.bind(world, generator, props, weather, hydrology, Config.vegetation, Config.farming)
	soil.from_dict(_saved_soil)
	_saved_soil = {}
	vegetation.bind(world, props, nodes, soil, weather, ids, rng.stream(&"vegetation"), clock, Config.vegetation, fire_at)
	vegetation.from_dict(_saved_vegetation)
	_saved_vegetation = {}
	# The powers that have shown themselves — and, for a world from before
	# they were kept, those it has already earned.
	powers.from_dict(_saved_powers)
	_saved_powers = {}
	_powers_looked = -1_000_000
	powers.on_water_touched(history.count(Intervention.TOUCH, &"water"), clock.tick, true)
	powers.on_weather(weather.state, clock.tick, true)
	if events != null and events.count_of(Chronicler.TYPE_STORM) > 0:
		powers.on_weather(WeatherSystem.STORM, clock.tick, true)
	# The animals: those the save has — or, for a world that never had any, its first.
	if species == null:
		species = SpeciesLibrary.load_from()
	animals = AnimalRegistry.new(spatial)
	fauna.bind(world, props, people, animals, species, ids, start, rng.stream(&"animals"), pathfinder)
	var lost := fauna.from_dict(_saved_animals)
	if lost > 0:
		Log.warn(Log.Category.LOAD, "Some saved animals were unusable and skipped", {"animals": lost})
	_saved_animals = {}
	for animal in animals.all_animals():
		ids.reserve_above(animal.id)
	fauna.seed_world(clock.tick)
	ai.fauna = fauna
	if settlement != null:
		settlement.unbind()
	settlement = null
	if start != null and start.campfire_id != 0:
		settlement = Settlement.new()
		settlement.bind(start, people, props, piles, ai.places, resources, loose, Config.settlement)
		settlement.farming = farming
		settlement.occupations = occupations
		settlement.fauna = fauna
		settlement.nodes = nodes
		settlement.from_dict(_saved_settlement)
		settlement.jobs.refresh(settlement, clock.tick)
		settlement.shortage_changed.connect(chronicle.on_shortage_changed)
		settlement.seed_released.connect(chronicle.on_seed_released)
		settlement.forage_changed.connect(chronicle.on_forage_changed)
		settlement.fire_changed.connect(chronicle.on_fire_changed)
		settlement.spoiled.connect(chronicle.on_spoiled)
		settlement.took_up.connect(chronicle.on_took_up)
	_saved_settlement = {}
	# The world's history: what the save has of it. (A world from before
	# there was one begins it now: what it has in store is no discovery.)
	if event_defs == null:
		event_defs = EventLibrary.load_from()
	events.bind(clock, event_defs, Config.events)
	var lost_events := events.from_dict(_saved_events)
	if lost_events > 0:
		Log.warn(Log.Category.LOAD, "Some saved events were unusable and skipped", {"events": lost_events})
	chronicle.listening = true
	chronicle.bind(events, people, props, loose, resources, settlement, farming, Config.events)
	chronicle.from_dict(_saved_chronicle)
	if bool(_saved_chronicle.get("adopt", false)):
		chronicle.adopt()
	if not stats.from_dict(_saved_stats):
		Log.warn(Log.Category.LOAD, "The saved statistics were unusable; they begin anew")
	_saved_events = {}
	_saved_chronicle = {}
	_saved_stats = {}
	ai.settlement = settlement
	ai.rng = rng.stream(&"ai")
	ai.world_seed = world_seed
	memories.bind(people)
	var unusable := memories.from_dict(_saved_memories)
	if unusable > 0:
		Log.warn(Log.Category.LOAD, "Some saved memories were unusable and skipped", {"memories": unusable})
	_saved_memories = {}
	ai.memories = memories
	ai.loose = loose
	ai.places.memories = memories
	var unreadable := day_log.from_dict(_saved_day_log)
	if unreadable > 0:
		Log.warn(Log.Category.LOAD, "Some saved day-log entries were unusable and skipped", {"entries": unreadable})
	_saved_day_log = {}
	ai.day_log = day_log
	ai.next_stimulus_id = maxi(int(_saved_perception.get("next_stimulus_id", 1)), 1)
	_saved_perception = {}
	behavior.bind(ai)
	perception.bind(ai)
	behavior.from_dict(_saved_behavior)
	_saved_behavior = {}
	simulation.tiers.low_end = GraphicsQuality.current() == GraphicsQuality.Level.LOW
	simulation.bind(clock, people, behavior, pathfinder, movement)
	clock.speed_changed.connect(_on_speed_changed)
	clock.day_started.connect(_on_day_started)
	clock.season_changed.connect(_on_season_changed)
	clock.year_started.connect(_on_year_started)
	_apply_pause()
	is_active = true
	EventBus.world_loaded.emit(world_id)


func _on_speed_changed(speed_index: int) -> void:
	_apply_pause()
	EventBus.sim_speed_changed.emit(speed_index)


## Paused, the whole world stands still — also what falls and what flows
## (bible §9.2). The UI, the camera and looking at things go on.
func _apply_pause() -> void:
	loose_system.frozen = clock.is_paused()
	water.frozen = clock.is_paused()


func _on_day_started(day: int) -> void:
	EventBus.day_started.emit(day)


func _on_season_changed(season: int, year: int) -> void:
	Log.info(Log.Category.WORLD, "A new season", {"season": GameClock.season_name(season), "year": year})
	EventBus.season_changed.emit(season, year)


func _on_year_started(year: int) -> void:
	EventBus.year_started.emit(year)


## Unique even when two worlds share a seed.
static func _make_world_id(seed_value: int, unix_time: int) -> String:
	var salt := RngStreams.fnv1a_32("%d:%d:%d" % [seed_value, unix_time, Time.get_ticks_usec()])
	return "w%d_%08x" % [unix_time, salt]
