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
var _saved_water: Dictionary = {} # the water's books from a save, until the water is bound


func _init() -> void:
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


## Starts a brand-new world. seed_value 0 picks a random seed and re-rolls it
## until the world is livable; an explicit seed is always used as given.
func create_new(seed_value: int = 0) -> void:
	if is_active:
		shutdown()
	created_unix = int(Time.get_unix_time_from_system())
	clock = GameClock.new(Config.time)
	template_id = DEFAULT_TEMPLATE_ID
	history = PlayerHistory.new()
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
	if typeof(state) == TYPE_DICTIONARY:
		if typeof((state as Dictionary).get("history")) == TYPE_DICTIONARY:
			history.from_dict(state["history"])
		if typeof((state as Dictionary).get("water")) == TYPE_DICTIONARY:
			_saved_water = state["water"]
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


func to_dict() -> Dictionary:
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
	Log.info(Log.Category.WORLD, "World closed", {"world_id": world_id})
	EventBus.world_unloaded.emit()


## Freeing the session always closes the world cleanly.
func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	if is_active:
		clock.advance(delta)
		behavior.step(clock.last_advance_minutes)
		pathfinder.serve(int(Config.perf.path_budget_ms_per_frame * 1000.0))
		movement.step(clock.last_advance_minutes)


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
	var settlement := Vector2.INF
	if start != null and start.campfire_id != 0:
		settlement = Vector2(start.settlement_tile) + Vector2(0.5, 0.5)
	interactions.bind_session(water, clock, history, settlement)
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
	ai.rng = rng.stream(&"ai")
	behavior.bind(ai)
	clock.speed_changed.connect(_on_speed_changed)
	is_active = true
	EventBus.world_loaded.emit(world_id)


func _on_speed_changed(speed_index: int) -> void:
	EventBus.sim_speed_changed.emit(speed_index)


## Unique even when two worlds share a seed.
static func _make_world_id(seed_value: int, unix_time: int) -> String:
	var salt := RngStreams.fnv1a_32("%d:%d:%d" % [seed_value, unix_time, Time.get_ticks_usec()])
	return "w%d_%08x" % [unix_time, salt]
