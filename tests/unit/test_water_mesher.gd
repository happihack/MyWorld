extends TestCase

const DEEP := 0.5


## A 16x16 single-chunk world: flat at height level 2, height step 0.25.
func _world(bounds: Rect2i = Rect2i(0, 0, 16, 16)) -> WorldData:
	var w := WorldData.new(bounds, 16)
	w.height_step = 0.25
	w.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	return w


func _buffers(w: WorldData, coord: Vector2i = Vector2i.ZERO) -> WaterMesher.Buffers:
	return WaterMesher.build_buffers(w, coord, DEEP)


func _top_quads(b: WaterMesher.Buffers) -> Array:
	var quads: Array = []
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] == Vector3.UP:
			quads.append(i)
	return quads


func test_dry_chunk_has_no_water_mesh() -> void:
	var w := _world()
	assert_true(_buffers(w).is_empty())
	assert_null(WaterMesher.build_mesh(w, Vector2i.ZERO, DEEP))
	w.set_water(Vector2i(3, 3), 0.0005)
	assert_true(_buffers(w).is_empty(), "a film thinner than MIN_DEPTH is dry")


func test_one_quad_per_wet_tile_at_bed_plus_depth() -> void:
	var w := _world()
	for tile in [Vector2i(5, 5), Vector2i(6, 5), Vector2i(5, 6)]:
		w.set_water(tile, 0.2)
	var b := _buffers(w)
	assert_eq(_top_quads(b).size(), 3)
	assert_eq(b.triangle_count(), 6)
	for v in b.vertices:
		assert_near(v.y, 2 * 0.25 + 0.2, 0.0001)
	assert_eq(b.uvs.size(), b.vertices.size())
	assert_eq(b.colors.size(), b.vertices.size())


func test_surface_sits_on_lowered_beds_at_the_same_level() -> void:
	# A deep channel beside a shallow bank share one flat surface.
	var w := _world()
	w.set_height(Vector2i(5, 5), 0)
	w.set_water(Vector2i(5, 5), 0.6)  # bed 0.0 + 0.6
	w.set_height(Vector2i(6, 5), 1)
	w.set_water(Vector2i(6, 5), 0.35) # bed 0.25 + 0.35
	var b := _buffers(w)
	for v in b.vertices:
		assert_near(v.y, 0.6, 0.0001)


func test_corner_heights_average_between_different_levels() -> void:
	var w := _world()
	w.set_water(Vector2i(5, 5), 0.1) # surface 0.6
	w.set_water(Vector2i(6, 5), 0.3) # surface 0.8
	var b := _buffers(w)
	var shared := 0
	for i in b.vertices.size():
		var v := b.vertices[i]
		if v.x == 6: # the edge shared by both tiles
			assert_near(v.y, 0.7, 0.0001, "shared corners sit halfway")
			shared += 1
		elif v.x == 5:
			assert_near(v.y, 0.6, 0.0001)
		elif v.x == 7:
			assert_near(v.y, 0.8, 0.0001)
	assert_eq(shared, 4, "both quads use the shared corners: no crack")


func test_shore_flag_marks_corners_touching_land() -> void:
	var w := _world()
	for y in range(4, 9):
		for x in range(4, 9):
			w.set_water(Vector2i(x, y), 0.2) # a 5x5 pond
	var b := _buffers(w)
	for i in b.vertices.size():
		var v := b.vertices[i]
		var on_rim := v.x == 4 or v.x == 9 or v.z == 4 or v.z == 9
		if not is_equal_approx(b.colors[i].g, 1.0 if on_rim else 0.0):
			fail("corner %s shore flag %f (rim=%s)" % [v, b.colors[i].g, on_rim])
			return


func test_depth_attribute_scales_to_deep() -> void:
	var w := _world()
	w.set_water(Vector2i(2, 2), DEEP * 0.5)
	w.set_water(Vector2i(10, 10), DEEP * 3.0)
	var b := _buffers(w)
	for i in b.vertices.size():
		var expected := 0.5 if b.vertices[i].x < 5 else 1.0
		assert_near(b.colors[i].r, expected, 0.0001)


func test_uv_is_world_position() -> void:
	var w := _world(Rect2i(-16, -16, 16, 16))
	w.set_water(Vector2i(-3, -7), 0.2)
	var b := _buffers(w, Vector2i(-1, -1))
	assert_eq(b.vertices[0], Vector3(13, 0.7, 9), "chunk-local vertex")
	assert_eq(b.uvs[0], Vector2(-3, -7), "world-space UV")


func test_wall_face_only_where_water_meets_the_box_wall() -> void:
	var w := _world()
	w.set_water(Vector2i(0, 5), 0.2)   # touches the -X wall
	w.set_water(Vector2i(8, 8), 0.2)   # interior
	var b := _buffers(w)
	var walls := 0
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] == Vector3.UP:
			continue
		walls += 1
		assert_eq(b.normals[i], Vector3.LEFT)
		var ys := [b.vertices[i].y, b.vertices[i + 1].y, b.vertices[i + 2].y, b.vertices[i + 3].y]
		assert_near(ys.max(), 0.7, 0.0001)
		assert_near(ys.min(), 0.5, 0.0001, "down to the bed")
		assert_eq(b.colors[i].g, 0.0, "the wall is not a shore")
	assert_eq(walls, 1)
	# The corner on the wall is not flagged as shore just because of the wall.
	for i in b.vertices.size():
		if b.normals[i] == Vector3.UP and b.vertices[i] == Vector3(0, 0.7, 5):
			assert_eq(b.colors[i].g, 1.0, "this corner also touches dry tile (0,4)")


func test_every_triangle_faces_its_normal() -> void:
	var w := _world()
	w.set_water(Vector2i(0, 0), 0.2)
	w.set_water(Vector2i(15, 15), 0.3)
	w.set_water(Vector2i(7, 7), 0.1)
	var b := _buffers(w)
	for t in range(0, b.indices.size(), 3):
		var p0 := b.vertices[b.indices[t]]
		var p1 := b.vertices[b.indices[t + 1]]
		var p2 := b.vertices[b.indices[t + 2]]
		var facing := (p2 - p0).cross(p1 - p0)
		if facing.length() < 0.000001 or facing.normalized().dot(b.normals[b.indices[t]]) < 0.99:
			fail("triangle %d does not face its normal" % (t / 3))
			return


func test_seamless_across_chunk_borders() -> void:
	var w := _world(Rect2i(0, 0, 32, 16))
	w.set_water(Vector2i(15, 5), 0.1)
	w.set_water(Vector2i(16, 5), 0.3)
	var left := _buffers(w, Vector2i(0, 0))
	var right := _buffers(w, Vector2i(1, 0))
	# The corners on the shared edge x = 16 match in both chunk meshes.
	var left_ys := []
	var right_ys := []
	for v in left.vertices:
		if v.x == 16:
			left_ys.append(roundi(v.y * 1000.0))
	for v in right.vertices:
		if v.x == 0:
			right_ys.append(roundi(v.y * 1000.0))
	assert_eq(left_ys, [700, 700], "left chunk's edge corners (millimetres)")
	assert_eq(right_ys, [700, 700], "right chunk's edge corners match: no crack")


func test_generated_river_meshes() -> void:
	var cfg := WorldConfig.new()
	var w := WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
	w.set_generator(WorldGenerator.new(12345, load("res://data/worldgen/river_valley.tres"), cfg))
	var wet_tiles := 0
	for y in range(-32, 32):
		for x in range(-32, 32):
			if w.get_water(Vector2i(x, y)) > WaterMesher.MIN_DEPTH:
				wet_tiles += 1
	var quads := 0
	var levels := {}
	for c in w.chunk_coords():
		var b := WaterMesher.build_buffers(w, c, 1.4 * cfg.height_step)
		quads += _top_quads(b).size()
		for i in b.vertices.size():
			if b.normals[i] == Vector3.UP:
				levels[snappedf(b.vertices[i].y, 0.001)] = true
	assert_eq(quads, wet_tiles)
	assert_eq(levels.size(), 1, "the generated river is one flat surface: %s" % str(levels.keys()))


func test_view_rebuilds_water_when_dirty() -> void:
	var w := _world()
	var view := ChunkView.new()
	add_child(view)
	view.setup(w, Vector2i.ZERO, null, null)
	assert_null(view.water_mesh())
	w.set_water(Vector2i(4, 4), 0.2)
	assert_true(w.get_chunk(Vector2i.ZERO).is_dirty(ChunkData.DIRTY_WATER))
	view.rebuild_water(w)
	assert_not_null(view.water_mesh())
	assert_false(w.get_chunk(Vector2i.ZERO).is_dirty(ChunkData.DIRTY_WATER))
	view.queue_free()
