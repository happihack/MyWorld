class_name WorldSession
extends Node
## Owns ALL state of the currently open world (bible §31.3, D-06).
##
## Deliberately not an autoload: New World / Reset / tests create and free
## sessions cleanly. Systems (people, environment, ...) are added as
## children/fields of this node in later milestones.

## Emitted by shutdown() while the world is still active, so listeners (e.g.
## SaveManager) can persist it on every orderly exit path.
signal about_to_close

const FORMAT_KEYS: PackedStringArray = ["world_id", "world_seed", "created_unix", "clock", "ids", "rng"]
const DEFAULT_TEMPLATE_PATH := "res://data/worldgen/river_valley.tres"
## A random seed whose world is not livable is re-rolled up to this many times.
const MAX_SEED_ATTEMPTS := 8

var world_id: String = ""
var world_seed: int = 0
var created_unix: int = 0
var clock: GameClock
var ids: IdAllocator
var rng: RngStreams
var is_active := false

## The tile world and what stands on it (built from the seed).
var world: WorldData
var generator: WorldGenerator
var props: PropRegistry
var spatial: SpatialIndex
var start: WorldSetup.StartInfo


## Starts a brand-new world. seed_value 0 picks a random seed and re-rolls it
## until the world is livable; an explicit seed is always used as given.
func create_new(seed_value: int = 0) -> void:
	if is_active:
		shutdown()
	created_unix = int(Time.get_unix_time_from_system())
	clock = GameClock.new(Config.time)
	var explicit := seed_value != 0
	for attempt in MAX_SEED_ATTEMPTS:
		world_seed = seed_value if explicit else RngStreams.new_world_seed()
		ids = IdAllocator.new()
		_build_world(ids)
		if start.ok or explicit:
			break
		Log.warn(Log.Category.WORLD, "Re-rolling seed: world not livable", {"seed": world_seed, "problems": start.problems})
	if not start.ok:
		Log.warn(Log.Category.WORLD, "World has problems", {"seed": world_seed, "problems": start.problems})
	world_id = _make_world_id(world_seed, created_unix)
	rng = RngStreams.new(world_seed)
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
	# TEMPORARY until M1.8: nothing in the world can be modified yet, so it is
	# rebuilt from the seed (deterministic) instead of being loaded. The setup
	# uses its own id sequence — the same ids as when the world was created —
	# and the session allocator is kept clear of them.
	var setup_ids := IdAllocator.new()
	_build_world(setup_ids)
	ids.reserve_above(setup_ids.peek() - 1)
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
	}


func shutdown() -> void:
	if not is_active:
		return
	about_to_close.emit()
	is_active = false
	clock.speed_changed.disconnect(_on_speed_changed)
	Log.info(Log.Category.WORLD, "World closed", {"world_id": world_id})
	EventBus.world_unloaded.emit()


## Freeing the session always closes the world cleanly.
func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	if is_active:
		clock.advance(delta)


## Generates terrain, props and the starting settlement for `world_seed`.
func _build_world(setup_ids: IdAllocator) -> void:
	var started := Time.get_ticks_msec()
	var template := load(DEFAULT_TEMPLATE_PATH) as StartTemplate
	if template == null:
		Log.error(Log.Category.WORLD, "Start template missing; using defaults", {"path": DEFAULT_TEMPLATE_PATH})
		template = StartTemplate.new()
	world = WorldData.create_centered(Config.world.initial_world_tiles, Config.world.chunk_size, Config.world.height_step)
	generator = WorldGenerator.new(world_seed, template, Config.world)
	world.set_generator(generator)
	spatial = SpatialIndex.new(Config.world.chunk_size)
	props = PropRegistry.new(Config.world.chunk_size, spatial)
	start = WorldSetup.create_start(world, generator, props, setup_ids)
	Log.debug(Log.Category.WORLD, "World built", {
		"ms": Time.get_ticks_msec() - started,
		"tiles": world.bounds.size,
		"props": props.size(),
		"settlement": start.settlement_tile,
	})


func _activate() -> void:
	clock.speed_changed.connect(_on_speed_changed)
	is_active = true
	EventBus.world_loaded.emit(world_id)


func _on_speed_changed(speed_index: int) -> void:
	EventBus.sim_speed_changed.emit(speed_index)


## Unique even when two worlds share a seed.
static func _make_world_id(seed_value: int, unix_time: int) -> String:
	var salt := RngStreams.fnv1a_32("%d:%d:%d" % [seed_value, unix_time, Time.get_ticks_usec()])
	return "w%d_%08x" % [unix_time, salt]
