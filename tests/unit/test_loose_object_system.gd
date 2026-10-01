extends TestCase
## LooseObjectSystem v0: holding, dropping, landing.

var world: WorldData
var registry: LooseObjectRegistry
var system: LooseObjectSystem
var ids: IdAllocator
var landings: Array = [] # [id, impact_speed]


func before_each() -> void:
	# Flat 32x32 world at height level 2 (step 0.5 -> ground at y = 1.0).
	world = WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.5
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	registry = LooseObjectRegistry.new(16, SpatialIndex.new(16))
	ids = IdAllocator.new()
	system = LooseObjectSystem.new()
	add_child(system)
	system.set_process(false) # tests step time themselves
	system.bind(world, registry)
	landings.clear()
	system.landed.connect(func(id: int, speed: float) -> void: landings.append([id, speed]))


func after_each() -> void:
	system.queue_free()


func _object(kind: LooseObject.Kind, at: Vector2, height: float = 0.0) -> LooseObject:
	var o := LooseObject.new()
	o.id = ids.next_id()
	o.kind = kind
	o.position = at
	o.height_offset = height
	registry.add(o)
	return o


## Steps until nothing moves; returns the seconds it took.
func _settle(max_seconds: float = 3.0) -> float:
	var t := 0.0
	while system.moving_count() > 0 and t < max_seconds:
		system.step(1.0 / 60.0)
		t += 1.0 / 60.0
	return t


func test_a_dropped_object_falls_and_comes_to_rest() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 0.55)
	assert_true(system.drop(rock.id))
	assert_eq(rock.state, LooseObject.State.FALLING)
	assert_true(system.is_falling(rock.id))
	system.step(1.0 / 60.0)
	assert_true(rock.height_offset < 0.55 and rock.height_offset > 0.4, "it has started to fall")
	var seconds := _settle()
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0, "exactly on the ground")
	assert_eq(rock.velocity, Vector3.ZERO)
	assert_eq(rock.position, Vector2(2.5, 2.5), "straight down")
	assert_true(seconds > 0.12 and seconds < 0.4, "quick and weighty (%.2f s)" % seconds)
	assert_eq(landings.size(), 1)
	assert_eq(landings[0][0], rock.id)
	var expected := sqrt(2.0 * LooseObjectSystem.GRAVITY * 0.55)
	assert_near(landings[0][1], expected, expected * 0.15, "impact speed from the height it fell")
	assert_eq(system.moving_count(), 0)


func test_a_higher_drop_hits_harder() -> void:
	var low := _object(LooseObject.Kind.ROCK, Vector2(1.5, 1.5), 0.3)
	var high := _object(LooseObject.Kind.ROCK, Vector2(4.5, 1.5), 2.0)
	system.drop(low.id)
	system.drop(high.id)
	_settle()
	assert_eq(landings.size(), 2)
	assert_eq(landings[0][0], low.id, "the lower one lands first")
	assert_true(landings[1][1] > landings[0][1] * 2.0)


func test_a_held_object_stays_put() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 0.5)
	assert_true(system.hold(rock.id))
	assert_eq(rock.state, LooseObject.State.HELD)
	for i in 30:
		system.step(1.0 / 60.0)
	assert_near(rock.height_offset, 0.5, 0.0)
	assert_eq(system.moving_count(), 0)
	# Catching it in mid-air stops the fall.
	system.drop(rock.id)
	system.step(1.0 / 60.0)
	system.step(1.0 / 60.0)
	var caught_at := rock.height_offset
	system.hold(rock.id)
	for i in 30:
		system.step(1.0 / 60.0)
	assert_near(rock.height_offset, caught_at, 0.0)
	assert_eq(landings.size(), 0)


func test_resting_objects_are_left_alone() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5))
	var moves := [0]
	registry.object_moved.connect(func(_id: int) -> void: moves[0] += 1)
	for i in 100:
		system.step(1.0 / 60.0)
	assert_eq(moves[0], 0, "no jitter at rest")
	assert_eq(rock.state, LooseObject.State.RESTING)


func test_unknown_and_removed_objects() -> void:
	assert_false(system.hold(999))
	assert_false(system.drop(999))
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 1.0)
	system.drop(rock.id)
	registry.remove(rock.id)
	system.step(1.0 / 60.0)
	assert_eq(system.moving_count(), 0)
	assert_eq(landings.size(), 0)


func test_stone_sinks_and_wood_floats() -> void:
	var tile := Vector2i(6, 6)
	world.set_water(tile, 0.6)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(6.5, 6.5), 1.2)
	var wood := _object(LooseObject.Kind.LOG, Vector2(6.5, 6.4), 1.2)
	system.drop(rock.id)
	system.drop(wood.id)
	_settle()
	assert_near(rock.height_offset, 0.0, 0.0, "on the river bed")
	assert_near(wood.height_offset, 0.6, 0.0001, "on the surface")
	assert_near(system.rest_height(wood), 0.6, 0.0001)
	# On dry land a log lies on the ground like anything else.
	var dry := _object(LooseObject.Kind.LOG, Vector2(1.5, 1.5), 0.5)
	system.drop(dry.id)
	_settle()
	assert_near(dry.height_offset, 0.0, 0.0)


func test_a_long_frame_does_not_break_the_fall() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 0.55)
	system.drop(rock.id)
	system.step(5.0) # a hitch
	_settle()
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0)
	assert_true(is_finite(landings[0][1]) and landings[0][1] < 20.0)


func test_binding_another_world_forgets_what_was_falling() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 1.0)
	system.drop(rock.id)
	system.bind(world, LooseObjectRegistry.new(16))
	assert_eq(system.moving_count(), 0)
	system.step(0.1) # nothing to do, nothing breaks
