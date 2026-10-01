extends TestCase
## Ways on foot (M4.3), on small hand-made worlds: flat ground unless a test
## shapes it.

var world: WorldData
var props: PropRegistry
var loose: LooseObjectRegistry
var index: SpatialIndex
var ids: IdAllocator
var finder: Pathfinder


func before_each() -> void:
	world = WorldData.new(Rect2i(0, 0, 16, 16), 16)
	index = SpatialIndex.new(4)
	props = PropRegistry.new(16, index)
	loose = LooseObjectRegistry.new(16, index)
	ids = IdAllocator.new()
	finder = Pathfinder.new()
	finder.bind(world, props, loose)


func after_each() -> void:
	finder.unbind()


func _prop(kind: PropData.Kind, tile: Vector2i) -> PropData:
	var prop := PropData.new()
	prop.id = ids.next_id()
	prop.kind = kind
	prop.tile = tile
	props.add(prop)
	return prop


func _object(kind: LooseObject.Kind, tile: Vector2i) -> LooseObject:
	var object := LooseObject.new()
	object.id = ids.next_id()
	object.kind = kind
	object.position = Vector2(tile) + Vector2(0.5, 0.5)
	loose.add(object)
	return object


## A wall of something across the map at x = `x`, with a gap at `gap_y` (-1: none).
func _wall(x: int, gap_y: int, build: Callable) -> void:
	for y in 16:
		if y != gap_y:
			build.call(Vector2i(x, y))


func _deep(tile: Vector2i) -> void:
	world.set_water(tile, 1.0)
	finder.mark_dirty(tile)


func _is_connected(path: Array[Vector2i]) -> bool:
	for i in range(1, path.size()):
		var step := path[i] - path[i - 1]
		if maxi(absi(step.x), absi(step.y)) != 1:
			return false
	return true


# --- open ground --------------------------------------------------------------------------------

func test_a_straight_way_on_open_ground() -> void:
	var path := finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	assert_eq(path.size(), 8, "both ends included")
	assert_eq(path[0], Vector2i(2, 5))
	assert_eq(path[-1], Vector2i(9, 5))
	assert_true(_is_connected(path))
	for tile in path:
		assert_eq(tile.y, 5, "straight")
	assert_near(finder.path_cost(path), 7.0, 0.0001)


func test_diagonals_are_used() -> void:
	var path := finder.find_path(Vector2i(1, 1), Vector2i(6, 6))
	assert_eq(path.size(), 6, "five diagonal steps")
	assert_near(finder.path_cost(path), 5.0 * sqrt(2.0), 0.001)


func test_already_there_and_off_the_map() -> void:
	assert_eq(finder.find_path(Vector2i(3, 3), Vector2i(3, 3)), [Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(finder.find_path(Vector2i(3, 3), Vector2i(40, 3)).size(), 0)
	assert_eq(finder.find_path(Vector2i(-1, 3), Vector2i(3, 3)).size(), 0)
	assert_false(finder.can_stand(Vector2i(16, 0)))
	assert_false(finder.has_tile(Vector2i(0, -1)))
	assert_true(finder.has_tile(Vector2i(15, 15)))
	assert_eq(finder.weight_at(Vector2i(99, 99)), INF)


func test_an_unbound_pathfinder_finds_nothing() -> void:
	var idle := Pathfinder.new()
	assert_false(idle.is_bound())
	assert_eq(idle.find_path(Vector2i.ZERO, Vector2i(1, 1)).size(), 0)
	assert_eq(idle.serve(), 0)
	assert_false(idle.has_tile(Vector2i.ZERO))


# --- water --------------------------------------------------------------------------------------

func test_deep_water_is_gone_around() -> void:
	_wall(8, 12, _deep)
	var path := finder.find_path(Vector2i(2, 5), Vector2i(13, 5))
	assert_true(path.size() > 12, "the long way (%d tiles)" % path.size())
	assert_true(_is_connected(path))
	assert_true(path.has(Vector2i(8, 12)), "through the gap")
	for tile in path:
		assert_true(world.get_water(tile) == 0.0, "dry all the way")


func test_no_way_across_deep_water_means_no_path() -> void:
	_wall(8, -1, _deep)
	assert_eq(finder.find_path(Vector2i(2, 5), Vector2i(13, 5)).size(), 0, "unreachable")
	assert_false(finder.is_reachable(Vector2i(2, 5), Vector2i(13, 5)))
	assert_true(finder.is_reachable(Vector2i(2, 5), Vector2i(7, 14)), "this side is fine")
	assert_false(finder.can_stand(Vector2i(8, 3)))


func test_shallow_water_is_waded_only_when_it_saves_a_long_walk() -> void:
	# A shallow stream with a dry crossing nearby: use the crossing.
	for y in 16:
		if y != 7:
			world.set_water(Vector2i(8, y), 0.08)
			finder.mark_dirty(Vector2i(8, y))
	var near := finder.find_path(Vector2i(6, 5), Vector2i(10, 5))
	assert_true(near.has(Vector2i(8, 7)), "two tiles out of the way beats wet feet")
	# Far from the crossing: wade.
	var far := finder.find_path(Vector2i(6, 15), Vector2i(10, 15))
	assert_false(far.has(Vector2i(8, 7)))
	assert_eq(far.size(), 5, "straight through the stream")
	assert_true(finder.can_stand(Vector2i(8, 15)))
	assert_true(finder.weight_at(Vector2i(8, 15)) > 3.0)
	assert_true(finder.speed_factor(Vector2i(8, 15)) < 0.5, "wading is slow")
	assert_near(finder.speed_factor(Vector2i(3, 3)), 1.0)
	# A wet patch is not a stream.
	world.set_water(Vector2i(3, 3), 0.01)
	finder.mark_dirty(Vector2i(3, 3))
	finder.refresh_dirty()
	assert_near(finder.weight_at(Vector2i(3, 3)), 1.0)


func test_a_way_to_something_in_the_water_ends_on_the_bank() -> void:
	_wall(8, -1, _deep)
	var path := finder.find_path(Vector2i(2, 5), Vector2i(8, 5))
	assert_true(path.size() > 0, "to the water's edge")
	assert_eq(path[-1], Vector2i(7, 5))
	# From the far side, the far bank.
	assert_eq(finder.find_path(Vector2i(13, 5), Vector2i(8, 5))[-1], Vector2i(9, 5))


# --- buildings and what stands in the way ---------------------------------------------------------

func test_buildings_are_gone_around_and_never_entered() -> void:
	for kind: PropData.Kind in [PropData.Kind.HUT, PropData.Kind.CAMPFIRE, PropData.Kind.RUIN]:
		var tile := Vector2i(5, 5)
		var prop := _prop(kind, tile)
		assert_false(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)).has(tile), "around the %s" % PropData.Kind.keys()[kind])
		assert_false(finder.can_stand(tile))
		assert_false(finder.can_step(Vector2i(4, 5), tile))
		props.remove(prop.id)
		assert_true(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)).has(tile), "gone: straight through again")


func test_nobody_cuts_the_corner_of_a_building() -> void:
	_prop(PropData.Kind.HUT, Vector2i(5, 5))
	var path := finder.find_path(Vector2i(4, 5), Vector2i(5, 4))
	assert_eq(path.size(), 3, "around the corner, not across it")
	assert_false(finder.can_step(Vector2i(4, 5), Vector2i(5, 4)))
	assert_false(finder.can_step(Vector2i(5, 6), Vector2i(6, 5)))
	assert_true(finder.can_step(Vector2i(4, 4), Vector2i(5, 4)), "walking past is fine")
	assert_true(finder.can_step(Vector2i(3, 3), Vector2i(4, 4)))


func test_walking_to_a_building_ends_at_its_side() -> void:
	_prop(PropData.Kind.HUT, Vector2i(9, 5))
	var path := finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	assert_eq(path[-1], Vector2i(8, 5), "the nearest side")
	assert_eq(finder.find_path(Vector2i(14, 5), Vector2i(9, 5))[-1], Vector2i(10, 5))
	# In the middle of a pond: as near as one can stand, the bank.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if dx != 0 or dy != 0:
				_deep(Vector2i(4, 11) + Vector2i(dx, dy))
	_prop(PropData.Kind.RUIN, Vector2i(4, 11))
	var to_pond := finder.find_path(Vector2i(8, 8), Vector2i(4, 11))

	assert_eq(maxi(absi(to_pond[-1].x - 4), absi(to_pond[-1].y - 11)), 3, "the water's edge")
	# In the middle of a lake: too far from any bank to count as getting there.
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			_deep(Vector2i(4, 11) + Vector2i(dx, dy))
	assert_eq(finder.find_path(Vector2i(12, 2), Vector2i(4, 11)).size(), 0)


func test_trees_and_bushes_slow_the_way_but_do_not_close_it() -> void:
	_wall(8, 12, func(tile: Vector2i) -> void: _prop(PropData.Kind.TREE, tile))
	assert_true(finder.can_stand(Vector2i(8, 5)), "a tree can be walked past")
	var across := finder.find_path(Vector2i(6, 5), Vector2i(10, 5))
	assert_eq(across.size(), 5, "the gap is far: push through")
	var near_gap := finder.find_path(Vector2i(6, 11), Vector2i(10, 11))
	assert_true(near_gap.has(Vector2i(8, 12)), "the gap is near: use it")
	_prop(PropData.Kind.BUSH, Vector2i(2, 2))
	assert_true(finder.weight_at(Vector2i(2, 2)) > 1.0)
	assert_true(finder.weight_at(Vector2i(2, 2)) < finder.weight_at(Vector2i(8, 5)), "a bush is less in the way than a tree")


func test_boulders_and_logs_are_walked_around() -> void:
	var boulder := _object(LooseObject.Kind.BOULDER, Vector2i(5, 5))
	assert_false(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)).has(Vector2i(5, 5)))
	assert_true(finder.can_stand(Vector2i(5, 5)), "in the way, but not a wall")
	# The player carries it elsewhere: the old place opens, the new one fills.
	loose.move(boulder.id, Vector2(7.5, 5.5))
	var path := finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	assert_true(path.has(Vector2i(5, 5)))
	assert_false(path.has(Vector2i(7, 5)))
	loose.move(boulder.id, Vector2(7.8, 5.2))
	assert_eq(finder.dirty_count(), 0, "moving within a tile changes nothing")
	# Two on one tile; one taken away; then the other.
	var log := _object(LooseObject.Kind.LOG, Vector2i(7, 5))
	loose.remove(boulder.id)
	assert_false(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)).has(Vector2i(7, 5)), "the log still lies there")
	loose.remove(log.id)
	assert_true(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)).has(Vector2i(7, 5)))
	# Small things are stepped over.
	_object(LooseObject.Kind.ROCK, Vector2i(6, 5))
	_object(LooseObject.Kind.PEBBLE, Vector2i(4, 5))
	assert_eq(finder.dirty_count(), 0)
	assert_near(finder.weight_at(Vector2i(6, 5)), 1.0)


# --- the shape of the land ------------------------------------------------------------------------

func test_a_step_of_one_level_is_climbed_and_a_cliff_is_not() -> void:
	# A terrace: x >= 8 is one level up. Then a cliff: x >= 12 is three more.
	for y in 16:
		for x in range(8, 16):
			world.set_height(Vector2i(x, y), 1 if x < 12 else 4)
	var up := finder.find_path(Vector2i(4, 5), Vector2i(10, 5))
	assert_eq(up.size(), 7, "straight up the terrace")
	assert_true(finder.can_step(Vector2i(7, 5), Vector2i(8, 5)))
	assert_false(finder.can_step(Vector2i(11, 5), Vector2i(12, 5)), "a cliff")
	assert_eq(finder.find_path(Vector2i(4, 5), Vector2i(14, 5)).size(), 0, "no way up")
	assert_true(finder.is_reachable(Vector2i(13, 2), Vector2i(14, 12)), "the top is walkable in itself")
	assert_true(finder.weight_at(Vector2i(8, 5)) > finder.weight_at(Vector2i(4, 5)), "a slope is a little slower")
	# A ramp makes the top reachable.
	world.set_height(Vector2i(12, 9), 2)
	world.set_height(Vector2i(13, 9), 3)
	var ramp := finder.find_path(Vector2i(4, 5), Vector2i(14, 5))
	assert_true(ramp.has(Vector2i(12, 9)) and ramp.has(Vector2i(13, 9)), "up the ramp")
	assert_true(_is_connected(ramp))
	for i in range(1, ramp.size()):
		assert_true(absi(world.get_height(ramp[i]) - world.get_height(ramp[i - 1])) <= 1, "never more than one level at a time")


func test_no_diagonal_across_the_lip_of_a_cliff() -> void:
	world.set_height(Vector2i(6, 5), 4) # a pillar
	assert_false(finder.can_step(Vector2i(5, 5), Vector2i(6, 4)), "its corner cannot be cut")
	assert_true(finder.can_step(Vector2i(5, 5), Vector2i(5, 4)))
	assert_false(finder.can_step(Vector2i(5, 5), Vector2i(6, 5)))
	assert_true(finder.can_stand(Vector2i(6, 5)), "one could stand on top")


func test_rough_ground_costs_more() -> void:
	world.set_terrain(Vector2i(3, 3), ChunkData.Terrain.MUD)
	world.set_terrain(Vector2i(4, 3), ChunkData.Terrain.ROAD)
	finder.refresh_dirty()
	assert_true(finder.weight_at(Vector2i(3, 3)) > 1.4)
	assert_true(finder.weight_at(Vector2i(4, 3)) < 1.0, "a path is easier than grass")
	assert_true(finder.speed_factor(Vector2i(4, 3)) > 1.0)
	# A muddy strip is avoided when the detour is short.
	for y in range(2, 9):
		world.set_terrain(Vector2i(8, y), ChunkData.Terrain.MUD)
	var path := finder.find_path(Vector2i(6, 8), Vector2i(10, 9))
	for tile in path:
		assert_ne(world.get_terrain(tile), ChunkData.Terrain.MUD, "around the end of the mud")


# --- keeping up with the world --------------------------------------------------------------------

func test_the_graph_follows_the_world_tile_by_tile() -> void:
	var before := finder.version
	assert_eq(finder.refresh_dirty(), 0)
	assert_eq(finder.version, before, "nothing changed, nothing new")
	_deep(Vector2i(5, 5))
	assert_eq(finder.dirty_count(), 1)
	assert_eq(finder.refresh_dirty(), 1)
	assert_true(finder.version > before)
	assert_false(finder.can_stand(Vector2i(5, 5)))
	assert_false(finder.can_step(Vector2i(4, 4), Vector2i(5, 5)))
	assert_false(finder.can_step(Vector2i(4, 5), Vector2i(5, 4)), "nor past its corner")
	# Marked but unchanged: the graph stays as it is.
	var version := finder.version
	finder.mark_dirty(Vector2i(10, 10))
	assert_eq(finder.refresh_dirty(), 0)
	assert_eq(finder.version, version)
	# The water goes: the tile is open again, exactly as before.
	world.set_water(Vector2i(5, 5), 0.0)
	finder.mark_dirty(Vector2i(5, 5))
	finder.refresh_dirty()
	assert_true(finder.can_step(Vector2i(4, 4), Vector2i(5, 5)))
	assert_true(finder.can_step(Vector2i(4, 5), Vector2i(5, 4)))
	assert_eq(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)).size(), 8)


func test_incremental_updates_match_a_fresh_build() -> void:
	# Change the world in many ways, then compare with a graph built from scratch.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var placed: Array[PropData] = []
	for i in 120:
		var tile := Vector2i(rng.randi_range(0, 15), rng.randi_range(0, 15))
		match rng.randi_range(0, 4):
			0:
				world.set_height(tile, rng.randi_range(0, 3))
			1:
				world.set_water(tile, [0.0, 0.08, 1.0][rng.randi_range(0, 2)])
				finder.mark_dirty(tile)
			2:
				if props.prop_at(tile) == null:
					placed.append(_prop([PropData.Kind.HUT, PropData.Kind.TREE, PropData.Kind.BUSH][rng.randi_range(0, 2)], tile))
			3:
				if not placed.is_empty():
					props.remove(placed.pop_back().id)
			4:
				_object(LooseObject.Kind.BOULDER, tile)
		if i % 7 == 0:
			finder.refresh_dirty()
	finder.refresh_dirty()
	var fresh := Pathfinder.new()
	fresh.bind(world, props, loose)
	var differences := 0
	for y in 16:
		for x in 16:
			var tile := Vector2i(x, y)
			if finder.can_stand(tile) != fresh.can_stand(tile) or not is_equal_approx(finder.weight_at(tile), fresh.weight_at(tile)):
				differences += 1
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]:
				if finder.can_step(tile, tile + offset) != fresh.can_step(tile, tile + offset) \
						or finder.can_step(tile + offset, tile) != fresh.can_step(tile + offset, tile):
					differences += 1
	assert_eq(differences, 0, "the same graph either way")
	fresh.unbind()


func test_someone_standing_where_nobody_can_may_still_walk_away() -> void:
	_prop(PropData.Kind.HUT, Vector2i(5, 5)) # a hut built on top of them
	var path := finder.find_path(Vector2i(5, 5), Vector2i(9, 5))
	assert_true(path.size() > 0)
	assert_eq(path[0], Vector2i(5, 5))
	assert_false(finder.can_stand(Vector2i(5, 5)), "and the hut is still a hut")


# --- cache and queue ------------------------------------------------------------------------------

func test_answers_are_remembered_until_the_world_changes() -> void:
	var first := finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	var searches := finder.paths_found
	var again := finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	assert_eq(again, first)
	assert_eq(finder.paths_found, searches, "not searched twice")
	assert_eq(finder.cache_hits, 1)
	# The answer handed out is the caller's own.
	again.clear()
	assert_eq(finder.find_path(Vector2i(2, 5), Vector2i(9, 5)), first)
	# The world changes: the old answer is not trusted.
	_prop(PropData.Kind.HUT, Vector2i(5, 5))
	var around := finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	assert_false(around.has(Vector2i(5, 5)))
	assert_true(finder.paths_found > searches)
	# "No way" is remembered too.
	_wall(12, -1, _deep)
	finder.find_path(Vector2i(2, 5), Vector2i(14, 5))
	searches = finder.paths_found
	assert_eq(finder.find_path(Vector2i(2, 5), Vector2i(14, 5)).size(), 0)
	assert_eq(finder.paths_found, searches)


func test_the_cache_does_not_grow_without_end() -> void:
	for i in Pathfinder.CACHE_SIZE + 50:
		@warning_ignore("integer_division")
		finder.find_path(Vector2i(i % 16, (i / 16) % 16), Vector2i(15 - i % 16, 15))
	assert_true(finder._cache.size() <= Pathfinder.CACHE_SIZE)


func test_queued_requests_are_answered_in_order_within_a_budget() -> void:
	var answers := []
	for i in 6:
		finder.request(Vector2i(1, i), Vector2i(14, 15 - i), func(path: Array[Vector2i]) -> void: answers.append([i, path.size()]))
	assert_eq(finder.queue_size(), 6)
	assert_eq(answers.size(), 0, "nothing is answered before there is time")
	# A budget of nothing still answers one: the queue cannot stall.
	assert_eq(finder.serve(0), 1)
	assert_eq(answers.size(), 1)
	assert_eq(answers[0][0], 0, "the oldest first")
	assert_eq(finder.serve(1_000_000), 5)
	assert_eq(finder.queue_size(), 0)
	for i in 6:
		assert_eq(answers[i][0], i)
		assert_true(answers[i][1] > 0)
	assert_eq(finder.serve(1000), 0)


func test_a_request_can_be_withdrawn() -> void:
	var answered := [0]
	var first := finder.request(Vector2i(1, 1), Vector2i(9, 9), func(_path: Array[Vector2i]) -> void: answered[0] += 1)
	var second := finder.request(Vector2i(1, 1), Vector2i(9, 9), func(_path: Array[Vector2i]) -> void: answered[0] += 10)
	assert_true(second > first)
	assert_true(finder.cancel(first))
	assert_false(finder.cancel(first))
	assert_false(finder.cancel(999))
	finder.serve(1_000_000)
	assert_eq(answered[0], 10)


func test_standing_places_around_a_spot() -> void:
	_prop(PropData.Kind.CAMPFIRE, Vector2i(8, 8))
	_object(LooseObject.Kind.BOULDER, Vector2i(9, 8))
	var places := finder.standable_near(Vector2i(8, 8), 6)
	assert_eq(places.size(), 6)
	var seen := {}
	for tile in places:
		assert_true(finder.can_stand(tile))
		assert_ne(tile, Vector2i(8, 8), "not in the fire")
		assert_ne(tile, Vector2i(9, 8), "not on the boulder")
		assert_false(seen.has(tile), "each their own")
		seen[tile] = true
		assert_true(maxi(absi(tile.x - 8), absi(tile.y - 8)) <= 2, "close by")
	assert_eq(finder.standable_near(Vector2i(8, 8), 6), places, "the same every time")
	assert_eq(finder.standable_near(Vector2i(3, 3), 1), [Vector2i(3, 3)] as Array[Vector2i])
	assert_eq(finder.standable_near(Vector2i(0, 0), 500, 2).size(), 9, "only what is there")


func test_binding_another_world_forgets_the_first() -> void:
	_prop(PropData.Kind.HUT, Vector2i(5, 5))
	finder.find_path(Vector2i(2, 5), Vector2i(9, 5))
	var other := WorldData.new(Rect2i(-4, -4, 8, 8), 16)
	finder.bind(other)
	assert_true(finder.has_tile(Vector2i(-4, -4)))
	assert_false(finder.has_tile(Vector2i(5, 5)))
	assert_eq(finder.find_path(Vector2i(-4, -4), Vector2i(3, 3)).size(), 8)
	# The first world's changes no longer reach it.
	world.set_height(Vector2i(2, 2), 3)
	props.remove(props.prop_at(Vector2i(5, 5)).id)
	assert_eq(finder.dirty_count(), 0)
