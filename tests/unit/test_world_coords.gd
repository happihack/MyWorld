extends TestCase

const CS := 16


func test_floor_div_negative_numbers() -> void:
	assert_eq(WorldCoords.floor_div(0, 16), 0)
	assert_eq(WorldCoords.floor_div(15, 16), 0)
	assert_eq(WorldCoords.floor_div(16, 16), 1)
	assert_eq(WorldCoords.floor_div(-1, 16), -1, "truncation would give 0")
	assert_eq(WorldCoords.floor_div(-16, 16), -1)
	assert_eq(WorldCoords.floor_div(-17, 16), -2)


func test_tile_to_chunk_and_local() -> void:
	assert_eq(WorldCoords.tile_to_chunk(Vector2i(0, 0), CS), Vector2i(0, 0))
	assert_eq(WorldCoords.tile_to_chunk(Vector2i(31, 16), CS), Vector2i(1, 1))
	assert_eq(WorldCoords.tile_to_chunk(Vector2i(-1, -1), CS), Vector2i(-1, -1))
	assert_eq(WorldCoords.tile_to_chunk(Vector2i(-32, 15), CS), Vector2i(-2, 0))
	assert_eq(WorldCoords.tile_to_local(Vector2i(-1, -1), CS), Vector2i(15, 15))
	assert_eq(WorldCoords.tile_to_local(Vector2i(-16, 17), CS), Vector2i(0, 1))


func test_roundtrip_every_tile_in_a_signed_range() -> void:
	var seen := {}
	for y in range(-40, 40):
		for x in range(-40, 40):
			var tile := Vector2i(x, y)
			var chunk := WorldCoords.tile_to_chunk(tile, CS)
			var local := WorldCoords.tile_to_local(tile, CS)
			var index := WorldCoords.tile_to_index(tile, CS)
			if local.x < 0 or local.x >= CS or local.y < 0 or local.y >= CS:
				fail("local out of range for %s: %s" % [tile, local])
				return
			if WorldCoords.chunk_local_to_tile(chunk, local, CS) != tile:
				fail("roundtrip failed for %s" % tile)
				return
			if WorldCoords.index_to_local(index, CS) != local:
				fail("index roundtrip failed for %s" % tile)
				return
			var key := [chunk, index]
			if seen.has(key):
				fail("two tiles map to the same chunk slot: %s" % tile)
				return
			seen[key] = true
	assert_eq(seen.size(), 80 * 80)


func test_chunk_rect_and_chunks_in_rect() -> void:
	assert_eq(WorldCoords.chunk_rect(Vector2i(-1, 2), CS), Rect2i(-16, 32, 16, 16))
	assert_eq(WorldCoords.chunks_in_rect(Rect2i(-32, -32, 64, 64), CS), Rect2i(-2, -2, 4, 4))
	assert_eq(WorldCoords.chunks_in_rect(Rect2i(-1, -1, 2, 2), CS), Rect2i(-1, -1, 2, 2))
	assert_eq(WorldCoords.chunks_in_rect(Rect2i(0, 0, 16, 16), CS), Rect2i(0, 0, 1, 1))
	assert_eq(WorldCoords.chunks_in_rect(Rect2i(0, 0, 0, 5), CS), Rect2i())


func test_world_space_conversions() -> void:
	assert_eq(WorldCoords.tile_to_world3d(Vector2i(-1, 2), 4, 0.25), Vector3(-0.5, 1.0, 2.5))
	assert_eq(WorldCoords.world3d_to_tile(Vector3(-0.01, 9.0, 2.99)), Vector2i(-1, 2))
	assert_eq(WorldCoords.world3d_to_tile(Vector3(0.0, 0.0, 0.0)), Vector2i(0, 0))
	assert_eq(WorldCoords.world2d_to_tile(Vector2(-16.0, 15.999)), Vector2i(-16, 15))
	# Every tile's own centre maps back to that tile.
	for t in [Vector2i(-33, -1), Vector2i(0, 0), Vector2i(31, -32)]:
		assert_eq(WorldCoords.world3d_to_tile(WorldCoords.tile_to_world3d(t, 0, 0.25)), t)
