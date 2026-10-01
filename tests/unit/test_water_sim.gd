extends TestCase
## WaterSim: water that runs downhill, stays in the box and is never lost.

var world: WorldData
var sim: WaterSim
var changes: Array = [] # arrays of changed tiles, one per step


func before_each() -> void:
	# Flat 32x32 world at height level 4 (step 0.4 -> ground at y = 1.6).
	world = WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.4
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(4)
		c.mark_pristine()
		return c
	for coord in world.chunk_coords():
		world.get_chunk(coord)
	sim = WaterSim.new()
	add_child(sim)
	sim.set_process(false) # tests step time themselves
	sim.soak_per_second = 0.0 # most tests want every drop accounted for in the water itself
	sim.bind(world)
	changes.clear()
	sim.tiles_changed.connect(func(tiles: Array[Vector2i]) -> void: changes.append(tiles))


func after_each() -> void:
	sim.queue_free()


func _run(steps: int) -> int:
	var done := 0
	for i in steps:
		if sim.is_still():
			break
		sim.step_once()
		done += 1
	return done


func _surface(tile: Vector2i) -> float:
	return world.get_height(tile) * world.height_step + world.get_water(tile)


func _lowest_water() -> float:
	var lowest := INF
	for chunk in world.loaded_chunks():
		for depth in chunk.water:
			lowest = minf(lowest, depth)
	return lowest


## A square basin `size` tiles wide, `depth` levels deep, with its corner at `corner`.
func _basin(corner: Vector2i, size: int, depth: int) -> void:
	for y in size:
		for x in size:
			world.set_height(corner + Vector2i(x, y), 4 - depth)


func test_still_water_is_left_alone() -> void:
	_basin(Vector2i(0, 0), 4, 2)
	for y in 4:
		for x in 4:
			world.set_water(Vector2i(x, y), 0.5)
	sim.bind(world) # as when a world is opened
	for chunk in world.loaded_chunks():
		chunk.modified = false # as if generated that way
	sim.bind(world)
	assert_true(sim.is_still(), "nothing to do in a level pool")
	sim.step(1.0)
	assert_eq(changes.size(), 0)
	assert_eq(sim.last_step_usec, 0, "and it costs nothing")
	assert_eq(world.modified_chunks().size(), 0, "nothing was touched")


func test_poured_water_spreads_and_is_conserved() -> void:
	var tile := Vector2i(3, 3)
	assert_near(sim.add_water(tile, 1.0), 1.0, 0.0)
	assert_false(sim.is_still())
	var before := sim.total_volume()
	sim.step_once()
	assert_true(world.get_water(tile) < 1.0, "it runs off")
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		assert_true(world.get_water(tile + dir) > 0.0, "to every side")
	assert_near(world.get_water(tile + Vector2i(1, 0)), world.get_water(tile + Vector2i(-1, 0)), 0.00001, "evenly")
	assert_near(sim.total_volume(), before, 0.00001)
	assert_eq(changes.size(), 1)
	assert_true(changes[0].has(tile) and changes[0].has(tile + Vector2i(1, 0)))
	_run(400)
	assert_near(sim.total_volume(), before, 0.0005, "none lost while spreading")
	assert_true(_lowest_water() >= 0.0, "never negative")


func test_a_spill_ends_as_puddles_not_an_endless_film() -> void:
	sim.add_water(Vector2i(0, 0), 2.0)
	var steps := _run(2000)
	assert_true(sim.is_still(), "it comes to rest (after %d steps)" % steps)
	var wet := 0
	var thinnest := INF
	for chunk in world.loaded_chunks():
		for depth in chunk.water:
			if depth > 0.0:
				wet += 1
				thinnest = minf(thinnest, depth)
	assert_true(wet > 20 and wet < 200, "a patch of puddles, not the whole world (%d tiles)" % wet)
	assert_near(sim.total_volume(), 2.0, 0.001)
	# A thin film on its own does not move at all.
	sim.add_water(Vector2i(-10, -10), WaterSim.FILM * 0.9)
	_run(50)
	assert_near(world.get_water(Vector2i(-10, -10)), WaterSim.FILM * 0.9, 0.00001)
	assert_near(world.get_water(Vector2i(-9, -10)), 0.0, 0.0)


func test_water_runs_downhill_and_fills_the_low_ground() -> void:
	# A hillside falling toward +X into a basin.
	for x in range(-16, 16):
		for y in range(-16, 16):
			world.set_height(Vector2i(x, y), clampi(8 - x, 2, 12))
	sim.bind(world)
	sim.add_water(Vector2i(-2, 0), 14.0)
	var before := sim.total_volume()
	var steps := _run(6000)
	assert_true(sim.is_still(), "it settles (after %d steps)" % steps)
	assert_near(sim.total_volume(), before, 0.002)
	var high := 0.0
	var low := 0.0
	var deepest_on_slope := 0.0
	for chunk in world.loaded_chunks():
		var origin := WorldCoords.chunk_origin(chunk.coord, 16)
		for i in chunk.water.size():
			if origin.x + i % 16 < 6:
				high += chunk.water[i]
				deepest_on_slope = maxf(deepest_on_slope, chunk.water[i])
			else:
				low += chunk.water[i]
	assert_true(low > high * 3.0, "most of it ended up on the low ground (%.2f low, %.2f left on the slope)" % [low, high])
	assert_true(deepest_on_slope <= WaterSim.FILM + WaterSim.MIN_DIFF * 2.0, "only wet ground is left on the slope (%.3f)" % deepest_on_slope)
	assert_true(_lowest_water() >= 0.0)


func test_a_basin_fills_to_a_level_surface() -> void:
	_basin(Vector2i(2, 2), 5, 3)
	sim.bind(world)
	sim.add_water(Vector2i(4, 4), 12.0)
	_run(3000)
	assert_true(sim.is_still())
	var levels: Array[float] = []
	for y in 5:
		for x in 5:
			levels.append(_surface(Vector2i(2 + x, 2 + y)))
	levels.sort()
	assert_true(levels[-1] - levels[0] < 0.03, "level across the basin (%.3f .. %.3f)" % [levels[0], levels[-1]])
	assert_near(world.get_water(Vector2i(0, 0)), 0.0, 0.0, "and none outside it")
	assert_near(sim.total_volume(), 12.0, 0.002)


func test_volume_is_conserved_over_a_thousand_steps() -> void:
	# Uneven ground and several spills keep the water moving for a long time.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for x in range(-16, 16):
		for y in range(-16, 16):
			world.set_height(Vector2i(x, y), 3 + rng.randi_range(0, 3))
	sim.bind(world)
	for i in 12:
		sim.add_water(Vector2i(rng.randi_range(-14, 14), rng.randi_range(-14, 14)), rng.randf_range(1.0, 4.0))
	var before := sim.total_volume()
	var worst := 0.0
	for i in 1000:
		sim.step_once()
		if i % 50 == 0:
			worst = maxf(worst, absf(sim.total_volume() - before))
	worst = maxf(worst, absf(sim.total_volume() - before))
	assert_true(worst < 0.005, "volume %.3f never off by more than %.5f" % [before, worst])
	assert_true(_lowest_water() >= 0.0, "no negative depth")
	assert_near(sim.soaked_total, 0.0, 0.0)


func test_water_stays_in_the_box() -> void:
	# Pour against the wall, with the ground falling toward it.
	for y in range(-16, 16):
		for x in range(10, 16):
			world.set_height(Vector2i(x, y), 4 - (x - 9))
	sim.bind(world)
	sim.add_water(Vector2i(15, 0), 5.0)
	sim.add_water(Vector2i(15, 15), 5.0)
	_run(3000)
	assert_near(sim.total_volume(), 10.0, 0.002, "nothing drains through the walls")
	assert_true(world.get_water(Vector2i(15, 5)) > 0.0, "it pools along the wall")


func test_soil_soaks_up_thin_water_and_everything_is_accounted_for() -> void:
	sim.soak_per_second = 0.05
	var tile := Vector2i(2, 2)
	var moisture := world.chunk_at_tile(tile).moisture[world.index_at_tile(tile)]
	sim.add_water(tile, 0.6)
	_run(4000)
	assert_true(sim.is_still())
	assert_near(sim.total_volume(), 0.0, 0.0001, "the puddles are gone")
	assert_near(sim.soaked_total, 0.6, 0.001, "into the soil, all of it")
	assert_true(world.chunk_at_tile(tile).moisture[world.index_at_tile(tile)] > moisture, "which is wetter for it")
	# Rock and river bed do not soak.
	world.set_terrain(Vector2i(-8, -8), ChunkData.Terrain.ROCK)
	sim.add_water(Vector2i(-8, -8), WaterSim.FILM * 0.9)
	_run(200)
	assert_near(world.get_water(Vector2i(-8, -8)), WaterSim.FILM * 0.9, 0.00001)


func test_taking_and_adding_water() -> void:
	var tile := Vector2i(1, 1)
	sim.add_water(tile, 0.5)
	assert_near(sim.take_water(tile, 0.2), 0.2, 0.00001)
	assert_near(world.get_water(tile), 0.3, 0.00001)
	assert_near(sim.take_water(tile, 5.0), 0.3, 0.00001, "only what is there")
	assert_near(sim.take_water(tile, 1.0), 0.0, 0.0, "a dry tile gives nothing")
	assert_near(sim.add_water(Vector2i(99, 99), 1.0), 0.0, 0.0, "outside the box")
	assert_near(sim.add_water(tile, -1.0), 0.0, 0.0)
	assert_near(sim.add_water(tile, NAN), 0.0, 0.0)
	assert_near(sim.take_water(tile, INF), 0.0, 0.0)
	assert_near(sim.total_volume(), 0.0, 0.00001)


func test_digging_beside_a_pool_lets_the_water_in() -> void:
	_basin(Vector2i(0, 0), 3, 2)
	for y in 3:
		for x in 3:
			world.set_water(Vector2i(x, y), 0.7)
	sim.bind(world)
	for chunk in world.loaded_chunks():
		chunk.modified = false
	sim.bind(world)
	assert_true(sim.is_still())
	var hole := Vector2i(3, 1)
	world.set_height(hole, 2) # the ground beside the pool is dug away
	sim.wake(hole)
	_run(2000)
	assert_true(world.get_water(hole) > 0.3, "the pool spread into the hole (%.2f)" % world.get_water(hole))
	assert_near(sim.total_volume(), 9 * 0.7, 0.002)


func test_a_world_saved_in_mid_flow_goes_on_flowing() -> void:
	sim.add_water(Vector2i(0, 0), 3.0)
	sim.step_once()
	var later := WaterSim.new()
	add_child(later)
	later.set_process(false)
	later.soak_per_second = 0.0
	later.bind(world) # as after loading: nothing remembered but the world itself
	assert_false(later.is_still(), "the unsettled water is found again")
	assert_near(world.get_water(Vector2i(2, 0)), 0.0, 0.0)
	later.step_once()
	assert_true(world.get_water(Vector2i(2, 0)) > 0.0, "and spreads on")
	later.queue_free()


func test_the_work_per_step_is_bounded() -> void:
	# A flood over the whole world: more tiles than one step may handle.
	for chunk in world.loaded_chunks():
		for i in chunk.water.size():
			chunk.set_water(i, 0.05 + (i % 7) * 0.05)
	sim.bind(world)
	assert_eq(sim.active_count(), 32 * 32, "every tile is unsettled")
	assert_true(sim.active_count() > WaterSim.MAX_TILES_PER_STEP)
	var before := sim.total_volume()
	var worst := 0
	var total := 0
	for i in 60:
		var started := Time.get_ticks_usec()
		sim.step_once()
		var took := Time.get_ticks_usec() - started
		worst = maxi(worst, took)
		total += took
	print("    water: a whole flooded world unsettled: %.2f ms per step on average, worst %.2f ms (at most %d tiles per step)" % [
		total / 60.0 / 1000.0, worst / 1000.0, WaterSim.MAX_TILES_PER_STEP])
	assert_true(total / 60.0 / 1000.0 < 4.0, "a step stays cheap even then")
	assert_near(sim.total_volume(), before, 0.01, "still conserved when the work is spread over steps")
	_run(8000)
	assert_true(sim.is_still(), "and it still settles")


func test_current_follows_the_flow() -> void:
	assert_eq(sim.current_at(Vector2i(0, 0)), Vector2.ZERO, "no water, no current")
	for x in range(-16, 16):
		for y in range(-16, 16):
			world.set_height(Vector2i(x, y), clampi(8 - x, 2, 12))
	sim.bind(world)
	sim.add_water(Vector2i(0, 0), 2.0)
	sim.step_once()
	sim.step_once()
	var current := sim.current_at(Vector2i(1, 0))
	assert_true(current.x > 0.1, "downhill, toward +X (%s)" % current)
	assert_true(absf(current.y) < current.x * 0.5)
	assert_true(current.length() <= 3.0, "never absurdly fast")
	_run(4000)
	assert_eq(sim.current_at(Vector2i(1, 0)), Vector2.ZERO, "still water has no current")


func test_the_generated_river_is_at_rest_and_has_its_own_current() -> void:
	var cfg := WorldConfig.new()
	var river := WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
	var generator := WorldGenerator.new(12345, load("res://data/worldgen/river_valley.tres"), cfg)
	river.set_generator(generator)
	for coord in river.chunk_coords():
		river.get_chunk(coord)
	sim.soak_per_second = 0.02
	sim.bind(river, generator)
	assert_true(sim.is_still())
	var before := sim.total_volume()
	assert_true(before > 50.0, "there is a river (%.1f)" % before)
	# Wake all of it: nothing should move, because it lies level.
	for coord in river.chunk_coords():
		var origin := WorldCoords.chunk_origin(coord, cfg.chunk_size)
		for i in cfg.chunk_size * cfg.chunk_size:
			var tile := origin + Vector2i(i % cfg.chunk_size, i / cfg.chunk_size)
			if river.get_water(tile) > 0.0:
				sim.wake(tile)
	for i in 30:
		sim.step_once()
	assert_true(sim.is_still(), "the river as generated is already in balance")
	assert_eq(river.modified_chunks().size(), 0, "so nothing changes and nothing needs saving")
	assert_near(sim.total_volume(), before, 0.0)
	# Deep river water carries things downstream (+Z); banks and dry land do not.
	var deep := Vector2i.ZERO
	var deepest := 0.0
	for x in range(-32, 32):
		var depth := river.get_water(Vector2i(x, 0))
		if depth > deepest:
			deepest = depth
			deep = Vector2i(x, 0)
	var current := sim.current_at(deep)
	assert_true(current.y > 0.3, "downstream (%s)" % current)
	assert_true(current.length() <= WaterSim.RIVER_CURRENT * 1.3, "gentle (%.2f)" % current.length())
	assert_near(generator.river_direction(deep).length(), 1.0, 0.0001)
	assert_eq(sim.current_at(Vector2i(-30, 0)), Vector2.ZERO)
