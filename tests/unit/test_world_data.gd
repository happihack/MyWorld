extends TestCase

var world: WorldData
var generated: Array = []


func before_each() -> void:
	world = WorldData.create_centered(64, 16)
	generated = []
	# Deterministic toy generator: height encodes the chunk coordinate.
	world.generator = func(coord: Vector2i) -> ChunkData:
		generated.append(coord)
		var c := ChunkData.new(coord, 16)
		c.height.fill(posmod(coord.x + coord.y * 4, 16))
		c.mark_pristine()
		return c


func test_centered_bounds() -> void:
	assert_eq(world.bounds, Rect2i(-32, -32, 64, 64))
	assert_true(world.is_in_bounds(Vector2i(-32, -32)))
	assert_true(world.is_in_bounds(Vector2i(31, 31)))
	assert_false(world.is_in_bounds(Vector2i(32, 0)))
	assert_false(world.is_in_bounds(Vector2i(0, -33)))


func test_chunk_coords_cover_bounds() -> void:
	var coords := world.chunk_coords()
	assert_eq(coords.size(), 16)
	assert_eq(coords[0], Vector2i(-2, -2))
	assert_eq(coords[-1], Vector2i(1, 1))


func test_chunks_generate_once_on_demand() -> void:
	assert_true(generated.is_empty(), "nothing generated up front")
	var a := world.get_chunk(Vector2i(-2, -2))
	var b := world.get_chunk(Vector2i(-2, -2))
	assert_true(a == b)
	assert_eq(generated, [Vector2i(-2, -2)])
	assert_null(world.get_chunk(Vector2i(5, 5)), "out of bounds")
	assert_null(world.get_chunk(Vector2i(0, 0), false), "not loaded and not generated")
	assert_false(world.has_chunk(Vector2i(0, 0)))


func test_tile_access_routes_to_the_right_chunk() -> void:
	world.set_height(Vector2i(-1, -1), 9)   # chunk (-1,-1), local (15,15)
	world.set_height(Vector2i(0, 0), 3)     # chunk (0,0), local (0,0)
	world.set_water(Vector2i(-17, 16), 0.5) # chunk (-2,1), local (15,0)
	assert_eq(world.get_height(Vector2i(-1, -1)), 9)
	assert_eq(world.get_chunk(Vector2i(-1, -1)).height[255], 9)
	assert_eq(world.get_chunk(Vector2i(0, 0)).height[0], 3)
	assert_eq(world.get_chunk(Vector2i(-2, 1)).water[15], 0.5)
	assert_eq(world.get_water(Vector2i(-17, 16)), 0.5)
	# Neighbouring tiles across the chunk border are untouched.
	assert_eq(world.get_height(Vector2i(-2, -1)), posmod(-1 + -1 * 4, 16))


func test_out_of_bounds_is_safe() -> void:
	var before := world.loaded_chunks().size()
	world.set_height(Vector2i(500, 500), 7)
	world.set_water(Vector2i(-500, 0), 2.0)
	world.set_flag(Vector2i(99, 99), ChunkData.FLAG_SACRED, true)
	assert_eq(world.get_height(Vector2i(500, 500)), WorldData.DEFAULT_HEIGHT)
	assert_eq(world.get_water(Vector2i(-500, 0)), 0.0)
	assert_false(world.has_flag(Vector2i(99, 99), ChunkData.FLAG_SACRED))
	assert_null(world.chunk_at_tile(Vector2i(500, 500)))
	assert_eq(world.loaded_chunks().size(), before, "no chunks created outside the box")


func test_only_modified_chunks_are_saved() -> void:
	for coord in world.chunk_coords():
		world.get_chunk(coord)
	assert_eq(world.loaded_chunks().size(), 16)
	assert_eq(world.modified_chunks().size(), 0)
	world.set_terrain(Vector2i(5, 5), ChunkData.Terrain.ROAD)
	world.set_flag(Vector2i(-20, 3), ChunkData.FLAG_RUIN, true)
	var data := world.to_dict()
	assert_eq((data["chunks"] as Array).size(), 2)


func test_roundtrip_restores_modifications_and_regenerates_the_rest() -> void:
	world.set_height(Vector2i(-1, -1), 12)
	world.set_water(Vector2i(10, -30), 1.25)
	var data: Dictionary = bytes_to_var(var_to_bytes(world.to_dict()))
	var copy := WorldData.new()
	copy.generator = world.generator
	assert_eq(copy.from_dict(data), 0)
	assert_eq(copy.bounds, world.bounds)
	assert_eq(copy.chunk_size, 16)
	assert_eq(copy.get_height(Vector2i(-1, -1)), 12)
	assert_eq(copy.get_water(Vector2i(10, -30)), 1.25)
	# An untouched chunk comes back from the generator, identical to the original.
	assert_eq(copy.get_height(Vector2i(20, 20)), world.get_height(Vector2i(20, 20)))
	assert_eq(copy.modified_chunks().size(), 2)


func test_unload_drops_only_unmodified_chunks() -> void:
	world.get_chunk(Vector2i(0, 0))
	world.set_height(Vector2i(-20, -20), 5)
	assert_true(world.unload_chunk(Vector2i(0, 0)))
	assert_false(world.has_chunk(Vector2i(0, 0)))
	assert_false(world.unload_chunk(Vector2i(-2, -2)), "modified chunks are kept")
	assert_false(world.unload_chunk(Vector2i(1, 1)), "not loaded")
	# Regenerated chunk is identical to the first generation.
	assert_eq(world.get_height(Vector2i(3, 3)), posmod(0 + 0 * 4, 16))


func test_bad_save_data_is_handled() -> void:
	var copy := WorldData.new()
	assert_eq(copy.from_dict({}), -1)
	assert_eq(copy.from_dict({"bounds": Rect2i(0, 0, 16, 16), "chunk_size": 0}), -1)
	assert_eq(copy.from_dict({"bounds": Rect2i(0, 0, 16, 16), "chunk_size": 16, "chunks": "x"}), -1)
	world.set_height(Vector2i(0, 0), 4)
	var data := world.to_dict()
	(data["chunks"] as Array).append({"garbage": true})
	(data["chunks"] as Array).append(ChunkData.new(Vector2i(50, 50), 16).to_dict()) # outside the box
	(data["chunks"] as Array).append(ChunkData.new(Vector2i(0, 1), 8).to_dict())   # wrong chunk size
	assert_eq(copy.from_dict(data), 3, "three bad records skipped, the good one kept")
	assert_eq(copy.get_height(Vector2i(0, 0)), 4)


class CountingGenerator:
	extends RefCounted
	var calls := 0

	func generate_chunk(coord: Vector2i) -> ChunkData:
		calls += 1
		var c := ChunkData.new(coord, 16)
		c.height.fill(7)
		c.mark_pristine()
		return c


func test_set_generator_keeps_the_generator_alive() -> void:
	# A bare Callable does not keep its object alive; set_generator() must, or
	# the world would silently fall back to flat chunks.
	var w := WorldData.create_centered(32, 16)
	w.set_generator(CountingGenerator.new()) # no other reference to the object
	assert_eq(w.get_height(Vector2i(0, 0)), 7)
	assert_eq(w.get_height(Vector2i(-16, -16)), 7)


func test_missing_generator_gives_flat_chunks() -> void:
	var bare := WorldData.create_centered(32, 16)
	assert_eq(bare.get_height(Vector2i(3, 3)), WorldData.DEFAULT_HEIGHT)
	assert_false(bare.get_chunk(Vector2i(0, 0)).modified)
