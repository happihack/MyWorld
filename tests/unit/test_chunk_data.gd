extends TestCase


func test_new_chunk_is_sized_and_neutral() -> void:
	var c := ChunkData.new(Vector2i(-1, 2), 16)
	assert_eq(c.tile_count(), 256)
	for layer in [c.height, c.terrain, c.moisture, c.fertility, c.vegetation, c.traffic, c.temperature]:
		assert_eq(layer.size(), 256)
	assert_eq(c.water.size(), 256)
	assert_eq(c.flags.size(), 256)
	assert_false(c.modified)
	assert_eq(c.get_temperature_offset(0), 0, "temperature defaults to no offset")
	assert_eq(c.index_of(Vector2i(3, 2)), 35)


func test_setters_mark_modified_and_dirty() -> void:
	var c := ChunkData.new(Vector2i.ZERO, 16)
	c.mark_pristine()
	c.clear_dirty(ChunkData.DIRTY_MESH | ChunkData.DIRTY_WATER)
	c.set_moisture(5, 200)
	assert_true(c.modified)
	assert_true(c.is_dirty(ChunkData.DIRTY_SAVE))
	assert_false(c.is_dirty(ChunkData.DIRTY_MESH), "moisture does not change the mesh")
	assert_true(c.has_flag(5, ChunkData.FLAG_MODIFIED))
	assert_false(c.has_flag(6, ChunkData.FLAG_MODIFIED))
	c.set_height(7, 9)
	assert_true(c.is_dirty(ChunkData.DIRTY_MESH) and c.is_dirty(ChunkData.DIRTY_WATER))
	c.clear_dirty(ChunkData.DIRTY_MESH)
	assert_false(c.is_dirty(ChunkData.DIRTY_MESH))
	assert_true(c.is_dirty(ChunkData.DIRTY_WATER))


func test_generator_path_stays_pristine() -> void:
	var c := ChunkData.new(Vector2i.ZERO, 16)
	c.height.fill(4) # generators write arrays directly
	c.mark_pristine()
	assert_false(c.modified)
	assert_true(c.is_dirty(ChunkData.DIRTY_MESH), "fresh chunks still need a mesh")
	assert_false(c.is_dirty(ChunkData.DIRTY_SAVE))


func test_values_are_clamped() -> void:
	var c := ChunkData.new(Vector2i.ZERO, 16)
	c.set_height(0, 999)
	c.set_moisture(0, -5)
	c.set_water(0, -1.5)
	c.set_temperature_offset(0, -500)
	c.set_temperature_offset(1, 500)
	c.set_temperature_offset(2, -7)
	assert_eq(c.height[0], 255)
	assert_eq(c.moisture[0], 0)
	assert_eq(c.water[0], 0.0)
	assert_eq(c.get_temperature_offset(0), -128)
	assert_eq(c.get_temperature_offset(1), 127)
	assert_eq(c.get_temperature_offset(2), -7)


func test_flags() -> void:
	var c := ChunkData.new(Vector2i.ZERO, 16)
	c.set_flag(3, ChunkData.FLAG_SACRED, true)
	c.set_flag(3, ChunkData.FLAG_RUIN, true)
	assert_true(c.has_flag(3, ChunkData.FLAG_SACRED) and c.has_flag(3, ChunkData.FLAG_RUIN))
	c.set_flag(3, ChunkData.FLAG_SACRED, false)
	assert_false(c.has_flag(3, ChunkData.FLAG_SACRED))
	assert_true(c.has_flag(3, ChunkData.FLAG_RUIN))
	var c2 := ChunkData.new(Vector2i.ZERO, 16)
	c2.set_flag(0, ChunkData.FLAG_EDGE, false) # no change
	assert_false(c2.modified, "setting a flag to its current value changes nothing")


func test_roundtrip_through_bytes() -> void:
	var c := ChunkData.new(Vector2i(-3, 5), 16)
	c.set_height(10, 7)
	c.set_terrain(10, ChunkData.Terrain.SAND)
	c.set_water(11, 0.75)
	c.set_vegetation(12, 90)
	c.set_temperature_offset(13, -20)
	c.set_flag(14, ChunkData.FLAG_RUIN, true)
	var restored := ChunkData.from_dict(bytes_to_var(var_to_bytes(c.to_dict())))
	assert_not_null(restored)
	assert_eq(restored.coord, Vector2i(-3, 5))
	assert_eq(restored.height, c.height)
	assert_eq(restored.terrain, c.terrain)
	assert_eq(restored.water, c.water)
	assert_eq(restored.vegetation, c.vegetation)
	assert_eq(restored.get_temperature_offset(13), -20)
	assert_true(restored.has_flag(14, ChunkData.FLAG_RUIN))
	assert_true(restored.modified, "saved chunks are modified by definition")


func test_snapshot_is_independent_of_live_chunk() -> void:
	var c := ChunkData.new(Vector2i.ZERO, 16)
	c.set_height(0, 3)
	var snapshot := c.to_dict()
	c.set_height(0, 9)
	assert_eq((snapshot["height"] as PackedByteArray)[0], 3)
	var restored := ChunkData.from_dict(snapshot)
	restored.set_height(1, 5)
	assert_eq((snapshot["height"] as PackedByteArray)[1], 0)


func test_invalid_data_rejected() -> void:
	var good := ChunkData.new(Vector2i.ZERO, 16).to_dict()
	assert_not_null(ChunkData.from_dict(good))
	var missing := good.duplicate()
	missing.erase("water")
	assert_null(ChunkData.from_dict(missing))
	var short := good.duplicate()
	short["height"] = PackedByteArray([1, 2, 3])
	assert_null(ChunkData.from_dict(short))
	var wrong_type := good.duplicate()
	wrong_type["flags"] = "nope"
	assert_null(ChunkData.from_dict(wrong_type))
	var bad_size := good.duplicate()
	bad_size["size"] = 0
	assert_null(ChunkData.from_dict(bad_size))
	assert_null(ChunkData.from_dict({}))
