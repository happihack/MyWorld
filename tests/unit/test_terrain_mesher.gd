extends TestCase

const STEP := 0.5

var palette: TerrainPalette


func before_all() -> void:
	palette = TerrainPalette.new()


## A single 16x16 chunk world at height 2, optionally edited by `shape`.
func _world(shape: Callable = Callable()) -> WorldData:
	var w := WorldData.new(Rect2i(0, 0, 16, 16), 16)
	w.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	if shape.is_valid():
		shape.call(w)
	return w


func _buffers(w: WorldData, coord: Vector2i = Vector2i.ZERO) -> TerrainMesher.Buffers:
	return TerrainMesher.build_buffers(w, coord, palette, STEP)


func _count_faces(b: TerrainMesher.Buffers, normal: Vector3) -> int:
	var n := 0
	for i in range(0, b.normals.size(), 4):
		if b.normals[i].is_equal_approx(normal):
			n += 1
	return n


func test_flat_chunk_has_tops_and_rim() -> void:
	var b := _buffers(_world())
	assert_eq(_count_faces(b, Vector3.UP), 256, "one top face per tile")
	for normal in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		assert_eq(_count_faces(b, normal), 16, "rim faces toward %s" % normal)
	assert_eq(b.vertices.size(), (256 + 64) * 4)
	assert_eq(b.triangle_count(), (256 + 64) * 2)
	assert_eq(b.normals.size(), b.vertices.size())
	assert_eq(b.colors.size(), b.vertices.size())


func test_geometry_extents() -> void:
	var b := _buffers(_world())
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in b.vertices:
		lo = lo.min(v)
		hi = hi.max(v)
	assert_eq(lo, Vector3(0, 0, 0), "rim reaches the base at y = 0")
	assert_eq(hi, Vector3(16, 2 * STEP, 16), "tops at height * step, chunk-local coordinates")


func test_every_triangle_faces_its_normal() -> void:
	# Godot front faces wind clockwise: front normal = (p2 - p0) x (p1 - p0).
	var w := _world(func(world: WorldData) -> void:
		world.set_height(Vector2i(5, 5), 6)
		world.set_height(Vector2i(6, 5), 4)
		world.set_height(Vector2i(10, 3), 0))
	var b := _buffers(w)
	for t in range(0, b.indices.size(), 3):
		var p0 := b.vertices[b.indices[t]]
		var p1 := b.vertices[b.indices[t + 1]]
		var p2 := b.vertices[b.indices[t + 2]]
		var facing := (p2 - p0).cross(p1 - p0)
		if facing.length() < 0.000001:
			fail("degenerate triangle at index %d" % t)
			return
		if facing.normalized().dot(b.normals[b.indices[t]]) < 0.99:
			fail("triangle %d faces away from its normal %s" % [t / 3, b.normals[b.indices[t]]])
			return


func test_step_creates_side_faces_of_the_right_height() -> void:
	var w := _world(func(world: WorldData) -> void: world.set_height(Vector2i(8, 8), 5))
	var b := _buffers(w)
	# The raised tile exposes four sides, each from level 2 up to level 5.
	var raised_sides := 0
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] == Vector3.UP:
			continue
		var ys := [b.vertices[i].y, b.vertices[i + 1].y, b.vertices[i + 2].y, b.vertices[i + 3].y]
		if ys.max() == 5 * STEP:
			raised_sides += 1
			assert_eq(ys.min(), 2 * STEP, "side stops at the neighbour's height")
	assert_eq(raised_sides, 4)
	assert_eq(_count_faces(b, Vector3.UP), 256)


func test_lower_neighbour_is_not_given_a_wall() -> void:
	# A pit: its four neighbours get sides facing the pit; the pit itself gets none.
	var w := _world(func(world: WorldData) -> void: world.set_height(Vector2i(8, 8), 0))
	var b := _buffers(w)
	var inner_sides := 0
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] == Vector3.UP:
			continue
		var c := (b.vertices[i] + b.vertices[i + 1] + b.vertices[i + 2] + b.vertices[i + 3]) / 4.0
		if c.x > 1 and c.x < 15 and c.z > 1 and c.z < 15:
			inner_sides += 1
	assert_eq(inner_sides, 4)


func test_neighbouring_chunks_share_a_seamless_border() -> void:
	# Two chunks side by side: no walls between equal heights, one wall at a step.
	var w := WorldData.new(Rect2i(0, 0, 32, 16), 16)
	w.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2 if coord.x == 0 else 4)
		c.mark_pristine()
		return c
	var left := _buffers(w, Vector2i(0, 0))
	var right := _buffers(w, Vector2i(1, 0))
	assert_eq(_count_faces(left, Vector3.RIGHT), 0, "lower chunk has no wall toward the higher one")
	assert_eq(_count_faces(right, Vector3.LEFT), 16, "higher chunk owns the step")
	assert_eq(_count_faces(left, Vector3.LEFT), 16, "box rim on the outer edge")
	assert_eq(_count_faces(right, Vector3.RIGHT), 16)


func test_colours_come_from_the_palette() -> void:
	var w := _world(func(world: WorldData) -> void: world.set_terrain(Vector2i(3, 3), ChunkData.Terrain.SNOW))
	var b := _buffers(w)
	var grass := palette.top(ChunkData.Terrain.GRASS)
	var snow := palette.top(ChunkData.Terrain.SNOW)
	var found_snow := false
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] != Vector3.UP:
			continue
		var c := b.colors[i]
		var is_snow_tile := b.vertices[i].x == 3 and b.vertices[i].z == 3
		var expected := snow if is_snow_tile else grass
		# Per-tile variation only scales brightness by a few percent.
		if absf(c.r - expected.r) > 0.06 or absf(c.g - expected.g) > 0.06 or absf(c.b - expected.b) > 0.06:
			fail("unexpected colour %s at %s (wanted about %s)" % [c, b.vertices[i], expected])
			return
		found_snow = found_snow or is_snow_tile
	assert_true(found_snow)


func test_corner_occlusion_darkens_next_to_taller_tiles() -> void:
	var w := _world(func(world: WorldData) -> void: world.set_height(Vector2i(8, 8), 6))
	var b := _buffers(w)
	# Tile (7, 8) sits left of the tower: its two right-hand corners are darker.
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] == Vector3.UP and b.vertices[i] == Vector3(7, 2 * STEP, 8):
			var near := b.colors[i + 1].g # corner (8, 8), touching the tower
			var far := b.colors[i].g      # corner (7, 8)
			assert_true(near < far, "corner beside the tower is darker (%f vs %f)" % [near, far])
			return
	fail("tile (7, 8) not found")


func test_side_faces_darken_toward_the_base() -> void:
	var b := _buffers(_world())
	for i in range(0, b.vertices.size(), 4):
		if b.normals[i] == Vector3.RIGHT:
			assert_true(b.colors[i + 2].g < b.colors[i].g, "bottom of a side face is darker than its top")
			return
	fail("no side face found")


func test_out_of_bounds_chunk_gives_no_mesh() -> void:
	var w := _world()
	assert_true(_buffers(w, Vector2i(5, 5)).is_empty())
	assert_null(TerrainMesher.build_mesh(w, Vector2i(5, 5), palette, STEP))


func test_build_mesh_produces_one_surface() -> void:
	var mesh := TerrainMesher.build_mesh(_world(), Vector2i.ZERO, palette, STEP)
	assert_not_null(mesh)
	assert_eq(mesh.get_surface_count(), 1)
	var aabb := mesh.get_aabb()
	assert_eq(aabb.size, Vector3(16, 2 * STEP, 16))


func test_palette_is_complete() -> void:
	assert_eq(palette.validate().size(), 0, str(palette.validate()))
	assert_eq(Config.terrain_palette.validate().size(), 0)


func test_generated_world_meshes_quickly() -> void:
	var cfg := WorldConfig.new()
	var w := WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
	w.set_generator(WorldGenerator.new(12345, load("res://data/worldgen/river_valley.tres"), cfg))
	for c in w.chunk_coords():
		w.get_chunk(c)
	var t0 := Time.get_ticks_msec()
	var triangles := 0
	for c in w.chunk_coords():
		triangles += _buffers(w, c).triangle_count()
	var ms := Time.get_ticks_msec() - t0
	assert_true(triangles > 64 * 64 * 2, "at least the top faces (%d triangles)" % triangles)
	assert_true(triangles < 64 * 64 * 2 * 4, "no runaway geometry (%d triangles)" % triangles)
	assert_true(ms < 1500, "meshing 16 chunks took %d ms" % ms)
