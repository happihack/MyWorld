extends TestCase

var library: PropMeshLibrary


func before_all() -> void:
	library = PropMeshLibrary.new()


## Flat 16x16 world at height level 2 (step 0.5 -> ground at y = 1.0).
func _world() -> WorldData:
	var w := WorldData.new(Rect2i(0, 0, 16, 16), 16)
	w.height_step = 0.5
	w.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	return w


func _prop(id: int, kind: PropData.Kind, tile: Vector2i, variant: int = 0) -> PropData:
	var p := PropData.new()
	p.id = id
	p.kind = kind
	p.tile = tile
	p.variant = variant
	return p


func _buffers(w: WorldData, props: PropRegistry, tufts: bool = false) -> PropMesher.Buffers:
	return PropMesher.build_buffers(w, props, Vector2i.ZERO, library, tufts)


# --- library -------------------------------------------------------------------

func test_library_has_a_shape_for_every_kind() -> void:
	for kind in PropData.Kind.values():
		var t := library.template_for(kind, 0)
		assert_not_null(t, "kind %d" % kind)
		assert_true(t.triangle_count() >= 4, "kind %d has geometry" % kind)
	assert_true(library.template_for(PropData.Kind.TREE, 2) != library.template_for(PropData.Kind.TREE, 0), "conifers differ from broadleaf trees")
	assert_true(library.template_for(PropData.Kind.HUT, 9) == library.template_for(PropData.Kind.HUT, 0), "unknown variant falls back to variant 0")
	assert_true(library.grass_tuft().triangle_count() > 0)


func test_templates_are_well_formed() -> void:
	for t in library.all_templates():
		assert_eq(t.vertices.size() % 3, 0)
		assert_eq(t.normals.size(), t.vertices.size())
		assert_eq(t.colors.size(), t.vertices.size())
		for i in range(0, t.vertices.size(), 3):
			var a := t.vertices[i]
			var b := t.vertices[i + 1]
			var c := t.vertices[i + 2]
			var facing := (c - a).cross(b - a)
			if facing.length() < 0.0000001:
				fail("degenerate triangle")
				return
			# Flat shading: the stored normal is the face normal, unit length.
			if facing.normalized().dot(t.normals[i]) < 0.999 or absf(t.normals[i].length() - 1.0) > 0.001:
				fail("normal does not match the triangle's facing")
				return


func test_templates_fit_their_tile_and_stand_on_the_ground() -> void:
	for kind in PropData.Kind.values():
		for variant in 4:
			var t := library.template_for(kind, variant)
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for v in t.vertices:
				lo = lo.min(v)
				hi = hi.max(v)
			assert_true(lo.y >= -0.001 and lo.y < 0.1, "kind %d/%d base at the ground (%f)" % [kind, variant, lo.y])
			# (A crop's first stages are low: bare furrows, then sprouts.)
			var least := 0.02 if kind == PropData.Kind.CROP else 0.1
			assert_true(hi.y > least and hi.y < 2.2, "kind %d/%d sensible height (%f)" % [kind, variant, hi.y])
			# (A cemetery fills its plot: three tiles across.)
			var widest := Graves.PLOT * 2.0 + 1.0 if kind == PropData.Kind.CEMETERY else 1.2
			assert_true(maxf(hi.x - lo.x, hi.z - lo.z) < widest, "kind %d/%d footprint about a tile" % [kind, variant])


func test_sway_weights() -> void:
	# Trees: rigid at the base, moving at the top. Built things never move.
	for variant in 4:
		var tree := library.template_for(PropData.Kind.TREE, variant)
		var base_weight := INF
		var top_weight := 0.0
		var top_y := -INF
		for i in tree.vertices.size():
			if tree.vertices[i].y < 0.01:
				base_weight = minf(base_weight, tree.colors[i].a)
			if tree.vertices[i].y > top_y:
				top_y = tree.vertices[i].y
				top_weight = tree.colors[i].a
		assert_eq(base_weight, 0.0, "tree %d base is rigid" % variant)
		assert_true(top_weight >= 0.9, "tree %d top sways (%f)" % [variant, top_weight])
	for kind in [PropData.Kind.ROCK, PropData.Kind.HUT, PropData.Kind.RUIN]:
		for c in library.template_for(kind, 0).colors:
			if c.a != 0.0:
				fail("kind %d should be rigid" % kind)
				return


# --- mesher --------------------------------------------------------------------

func test_empty_chunk_has_no_mesh() -> void:
	var w := _world()
	var props := PropRegistry.new(16)
	assert_true(_buffers(w, props).is_empty())
	assert_null(PropMesher.build_mesh(w, props, Vector2i.ZERO, library, false))
	assert_true(PropMesher.build_buffers(w, props, Vector2i(9, 9), library).is_empty(), "out of bounds")


func test_merged_mesh_contains_every_prop() -> void:
	var w := _world()
	var props := PropRegistry.new(16)
	props.add(_prop(1, PropData.Kind.TREE, Vector2i(2, 2)))
	props.add(_prop(2, PropData.Kind.ROCK, Vector2i(5, 5), 1))
	props.add(_prop(3, PropData.Kind.HUT, Vector2i(9, 9)))
	var expected := library.template_for(PropData.Kind.TREE, 0).vertices.size() \
		+ library.template_for(PropData.Kind.ROCK, 1).vertices.size() \
		+ library.template_for(PropData.Kind.HUT, 0).vertices.size()
	var b := _buffers(w, props)
	assert_eq(b.vertices.size(), expected)
	assert_eq(b.normals.size(), expected)
	assert_eq(b.colors.size(), expected)
	var mesh := PropMesher.build_mesh(w, props, Vector2i.ZERO, library, false)
	assert_eq(mesh.get_surface_count(), 1, "one draw call for the whole chunk")


func test_props_stand_on_the_terrain_at_their_position() -> void:
	var w := _world()
	w.set_height(Vector2i(6, 3), 5) # ground at 2.5
	var props := PropRegistry.new(16)
	var rock := _prop(1, PropData.Kind.ROCK, Vector2i(6, 3))
	rock.offset_x = 64  # +0.25 tile
	rock.offset_y = -64 # -0.25 tile
	props.add(rock)
	var b := _buffers(w, props)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in b.vertices:
		lo = lo.min(v)
		hi = hi.max(v)
	assert_near(lo.y, 2.5, 0.001, "base sits on the raised tile")
	var mid := (lo + hi) * 0.5
	assert_near(mid.x, 6.75, 0.08, "tile centre + offset")
	assert_near(mid.z, 3.25, 0.08)


func test_scale_and_rotation_are_applied() -> void:
	var w := _world()
	var small := PropRegistry.new(16)
	var big := PropRegistry.new(16)
	var a := _prop(1, PropData.Kind.TREE, Vector2i(4, 4))
	a.scale_percent = 80
	var c := _prop(1, PropData.Kind.TREE, Vector2i(4, 4))
	c.scale_percent = 120
	small.add(a)
	big.add(c)
	var top_small := -INF
	var top_big := -INF
	for v in _buffers(w, small).vertices:
		top_small = maxf(top_small, v.y)
	for v in _buffers(w, big).vertices:
		top_big = maxf(top_big, v.y)
	assert_near((top_big - 1.0) / (top_small - 1.0), 1.5, 0.001, "height above ground scales 120% vs 80%")

	# The hut's doorway faces +X unrotated; a quarter turn (64 steps) moves it
	# to face +/-Z. The door is the only part with the DOOR colour.
	var plain := PropRegistry.new(16)
	plain.add(_prop(1, PropData.Kind.HUT, Vector2i(8, 8)))
	var turned := PropRegistry.new(16)
	var hut := _prop(1, PropData.Kind.HUT, Vector2i(8, 8))
	hut.rotation_step = 64
	turned.add(hut)
	var door_plain := _door_offset(_buffers(w, plain))
	var door_turned := _door_offset(_buffers(w, turned))
	assert_true(door_plain.x > 0.3 and absf(door_plain.y) < 0.01, "door on +X: %s" % door_plain)
	assert_true(absf(door_turned.x) < 0.01 and absf(door_turned.y) > 0.3, "door on the Z side after a quarter turn: %s" % door_turned)


## Average XZ offset of the hut's door vertices from the hut's tile centre (8.5, 8.5).
func _door_offset(b: PropMesher.Buffers) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for i in b.vertices.size():
		var c := b.colors[i]
		if is_equal_approx(c.r, PropMeshLibrary.DOOR.r) and is_equal_approx(c.g, PropMeshLibrary.DOOR.g):
			sum += Vector2(b.vertices[i].x - 8.5, b.vertices[i].z - 8.5)
			n += 1
	return sum / n if n > 0 else Vector2.INF


func test_transformed_triangles_still_face_their_normals() -> void:
	var w := _world()
	var props := PropRegistry.new(16)
	var tree := _prop(1, PropData.Kind.TREE, Vector2i(3, 3), 2)
	tree.rotation_step = 37
	tree.scale_percent = 115
	props.add(tree)
	var b := _buffers(w, props)
	for i in range(0, b.vertices.size(), 3):
		var facing := (b.vertices[i + 2] - b.vertices[i]).cross(b.vertices[i + 1] - b.vertices[i])
		if facing.normalized().dot(b.normals[i]) < 0.999:
			fail("triangle %d lost its facing after the transform" % (i / 3))
			return


func test_sway_weight_survives_the_tint() -> void:
	var w := _world()
	var props := PropRegistry.new(16)
	props.add(_prop(1, PropData.Kind.TREE, Vector2i(3, 3)))
	var template := library.template_for(PropData.Kind.TREE, 0)
	var b := _buffers(w, props)
	for i in template.colors.size():
		if b.colors[i].a != template.colors[i].a:
			fail("alpha (sway weight) changed at vertex %d" % i)
			return


func test_grass_tufts_only_on_lush_free_grass() -> void:
	var w := _world()
	var props := PropRegistry.new(16)
	assert_true(PropMesher.build_buffers(w, props, Vector2i.ZERO, library, true).is_empty(), "bare ground: no tufts")
	var chunk := w.get_chunk(Vector2i.ZERO)
	chunk.vegetation.fill(255)
	var lush := PropMesher.build_buffers(w, props, Vector2i.ZERO, library, true)
	var tuft_size := library.grass_tuft().vertices.size()
	var tufts := lush.vertices.size() / tuft_size
	assert_true(tufts > 256 * 20 / 100 and tufts < 256 * 60 / 100, "about 40%% of lush tiles (%d tufts)" % tufts)
	# Deterministic, and never on water or non-grass.
	assert_eq(PropMesher.build_buffers(w, props, Vector2i.ZERO, library, true).vertices.size(), lush.vertices.size())
	chunk.terrain.fill(ChunkData.Terrain.ROCK)
	assert_true(PropMesher.build_buffers(w, props, Vector2i.ZERO, library, true).is_empty())
	chunk.terrain.fill(ChunkData.Terrain.GRASS)
	chunk.water.fill(0.2)
	assert_true(PropMesher.build_buffers(w, props, Vector2i.ZERO, library, true).is_empty())


func test_generated_world_prop_meshes_are_reasonable() -> void:
	var cfg := WorldConfig.new()
	var w := WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
	var gen := WorldGenerator.new(12345, load("res://data/worldgen/river_valley.tres"), cfg)
	w.set_generator(gen)
	var props := PropRegistry.new(cfg.chunk_size)
	WorldSetup.create_start(w, gen, props, IdAllocator.new())
	var t0 := Time.get_ticks_msec()
	var triangles := 0
	for c in w.chunk_coords():
		triangles += PropMesher.build_buffers(w, props, c, library).triangle_count()
	var ms := Time.get_ticks_msec() - t0
	assert_true(triangles > 2000, "props present (%d triangles)" % triangles)
	assert_true(triangles < 80000, "within the mobile budget (%d triangles)" % triangles)
	assert_true(ms < 2500, "merging 16 chunks took %d ms" % ms)
