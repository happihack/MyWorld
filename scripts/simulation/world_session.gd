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
var start: WorldSetup.StartInfo


## Starts a brand-new world. seed_value 0 picks a random seed and re-rolls it
## until the world is livable; an explicit seed is always used as given.
func create_new(seed_value: int = 0) -> void:
	if is_active:
		shutdown()
	created_unix = int(Time.get_unix_time_from_system())
	clock = GameClock.new(Config.time)
	template_id = DEFAULT_TEMPLATE_ID
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
			"start": start.to_dict(),
		},
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
func _build_new_world(setup_ids: IdAllocator) -> void:
	var started := Time.get_ticks_msec()
	var template := _load_template(template_id)
	world = WorldData.create_centered(Config.world.initial_world_tiles, Config.world.chunk_size, Config.world.height_step)
	generator = WorldGenerator.new(world_seed, template, Config.world)
	world.set_generator(generator)
	spatial = SpatialIndex.new(world.chunk_size)
	props = PropRegistry.new(world.chunk_size, spatial)
	start = WorldSetup.create_start(world, generator, props, setup_ids)
	Log.debug(Log.Category.WORLD, "World built", {
		"ms": Time.get_ticks_msec() - started,
		"tiles": world.bounds.size,
		"props": props.size(),
		"settlement": start.settlement_tile,
	})


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
	var restored_spatial := SpatialIndex.new(restored.chunk_size)
	var restored_props := PropRegistry.new(restored.chunk_size, restored_spatial)
	var skipped_props := restored_props.from_dict(props_data)
	if skipped_props < 0:
		return false
	WorldSetup.populate_all(restored, restored_generator, restored_props)

	template_id = saved_template
	world = restored
	generator = restored_generator
	spatial = restored_spatial
	props = restored_props
	start = restored_start
	if skipped_chunks > 0 or skipped_props > 0:
		Log.warn(Log.Category.LOAD, "Some saved world records were unusable and skipped",
			{"chunks": skipped_chunks, "props": skipped_props})
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
	clock.speed_changed.connect(_on_speed_changed)
	is_active = true
	EventBus.world_loaded.emit(world_id)


func _on_speed_changed(speed_index: int) -> void:
	EventBus.sim_speed_changed.emit(speed_index)


## Unique even when two worlds share a seed.
static func _make_world_id(seed_value: int, unix_time: int) -> String:
	var salt := RngStreams.fnv1a_32("%d:%d:%d" % [seed_value, unix_time, Time.get_ticks_usec()])
	return "w%d_%08x" % [unix_time, salt]
