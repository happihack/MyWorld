extends TestCase
## FB3: ways over the water — around the land, never across a corner of it,
## not over ice, not with a mast under a bridge, deep enough for the boat.

var world: WorldData
var paths: WaterPaths


## A pond in a U: water all round a block of land in the middle (x 4…7, y 2…7)
## and open at the top; a shallow arm off to the side.
func before_each() -> void:
	world = WorldData.create_centered(32, 16, 0.4)
	for y in range(0, 10):
		for x in range(0, 12):
			var land := x >= 4 and x <= 7 and y >= 2
			if not land:
				world.set_water(Vector2i(x, y), 0.8)
	for x in range(12, 16):
		world.set_water(Vector2i(x, 0), 0.05) # too shallow for most
	paths = WaterPaths.new()
	paths.bind(world)


func test_round_the_land() -> void:
	var way := paths.find(Vector2i(2, 8), Vector2i(10, 8), 0.1)
	assert_false(way.is_empty(), "a way round")
	assert_eq(way[0], Vector2i(2, 8))
	assert_eq(way[-1], Vector2i(10, 8))
	for i in way.size():
		assert_true(world.get_water(way[i]) >= 0.1, "only water: %s" % way[i])
		if i > 0:
			var step := way[i] - way[i - 1]
			assert_true(absi(step.x) <= 1 and absi(step.y) <= 1, "tile by tile")
			if step.x != 0 and step.y != 0:
				assert_true(world.get_water(way[i - 1] + Vector2i(step.x, 0)) > 0.0 and world.get_water(way[i - 1] + Vector2i(0, step.y)) > 0.0,
					"not across a corner of land")
	assert_true(way.size() > 12, "the long way round (%d)" % way.size())


func test_deep_enough_for_the_boat() -> void:
	assert_true(paths.find(Vector2i(10, 0), Vector2i(15, 0), 0.1).is_empty(), "too shallow")
	assert_false(paths.find(Vector2i(10, 0), Vector2i(15, 0), 0.03).is_empty(), "a raft of little draught gets there")
	assert_true(paths.find(Vector2i(2, 8), Vector2i(5, 5), 0.1).is_empty(), "not onto land")


func test_not_over_ice_nor_a_mast_under_a_bridge() -> void:
	paths.is_ice = func(tile: Vector2i) -> bool: return tile.x == 5
	assert_true(paths.find(Vector2i(2, 8), Vector2i(10, 8), 0.1).is_empty(), "the ice cuts the way")
	paths.is_ice = Callable()
	paths.clear_cache()
	paths.is_bridge = func(tile: Vector2i) -> bool: return tile.x == 9
	assert_false(paths.find(Vector2i(2, 8), Vector2i(10, 8), 0.1).is_empty(), "under the bridge")
	assert_true(paths.find(Vector2i(2, 8), Vector2i(10, 8), 0.1, true).is_empty(), "but not with a mast")


func test_water_near() -> void:
	assert_eq(paths.water_near(Vector2i(2, 2), 0.1), Vector2i(2, 2))
	var near: Variant = paths.water_near(Vector2i(4, 5), 0.1)
	assert_eq(near, Vector2i(3, 5), "beside the land")
	assert_null(paths.water_near(Vector2i(5, 9), 0.1, 1), "none in reach")
