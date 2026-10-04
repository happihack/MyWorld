extends TestCase
## Chunk streaming (M13.1): views only for what the camera sees, built on
## worker threads; chunk data dropped and generated again, identical.

const ViewScript := preload("res://scripts/rendering/world_view.gd")

var view: WorldView
var world: WorldData
var generator: WorldGenerator
var props: PropRegistry
var start: WorldSetup.StartInfo


func before_all() -> void:
	var cfg := WorldConfig.new()
	world = WorldData.create_centered(128, cfg.chunk_size, cfg.height_step)
	generator = WorldGenerator.new(12345, load("res://data/worldgen/river_valley.tres"), cfg)
	world.set_generator(generator)
	props = PropRegistry.new(cfg.chunk_size, SpatialIndex.new(cfg.chunk_size))
	start = WorldSetup.create_start(world, generator, props, IdAllocator.new())


func before_each() -> void:
	view = ViewScript.new()
	add_child(view)
	view.show_world(world, props, start)


func after_each() -> void:
	view.queue_free()
	await wait_frames(1)


func test_chunk_evict_regenerate_identical() -> void:
	var cfg := WorldConfig.new()
	var fresh := WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
	fresh.set_generator(WorldGenerator.new(777, load("res://data/worldgen/river_valley.tres"), cfg))
	var coord := Vector2i(-1, 0)
	var before := fresh.get_chunk(coord).to_dict()
	assert_true(fresh.unload_chunk(coord), "a pristine chunk is dropped")
	assert_false(fresh.has_chunk(coord))
	# Others made in between, in another order, change nothing.
	for other in [Vector2i(1, 1), Vector2i(-2, -2), Vector2i(0, 0)]:
		fresh.get_chunk(other)
	var after := fresh.get_chunk(coord).to_dict()
	for layer: String in before:
		assert_eq(after[layer], before[layer], "layer %s comes back the same" % layer)
	# A changed chunk is kept, with its change.
	var tile := WorldCoords.chunk_origin(coord, fresh.chunk_size) + Vector2i(3, 4)
	fresh.set_terrain(tile, ChunkData.Terrain.ROAD)
	assert_false(fresh.unload_chunk(coord), "a modified chunk stays")
	assert_eq(fresh.get_terrain(tile), ChunkData.Terrain.ROAD)


func test_the_framed_box_shows_every_chunk() -> void:
	assert_eq(view.chunk_view_count(), 64, "framed, the whole box is seen")
	for coord in world.chunk_coords():
		assert_not_null(view.get_chunk_view(coord).terrain_mesh(), "terrain for %s" % coord)


func test_streaming_loads_visible() -> void:
	var rig := view.camera_rig()
	var streamer := view.chunk_streamer()
	var at := Vector3(40.5, 0.0, 40.5) # off in a corner of the box
	rig.focus_on(at, rig.config.min_distance, false)
	streamer.update(rig)
	streamer.finish_all()
	var shown := view.chunk_view_count()
	assert_true(shown < 64 and shown >= 4, "close up, only what is seen has views (%d)" % shown)
	assert_true(streamer.released > 0)
	# Everything under the screen has a view, with its ground.
	var size := rig.view_size()
	for screen in [size * 0.5, Vector2.ZERO, size, Vector2(size.x, 0.0), Vector2(0.0, size.y)]:
		var ground: Variant = rig.screen_to_ground(screen, 0.0)
		assert_not_null(ground)
		var tile := WorldCoords.world2d_to_tile(Vector2((ground as Vector3).x, (ground as Vector3).z))
		if not world.is_in_bounds(tile):
			continue
		var coord := WorldCoords.tile_to_chunk(tile, world.chunk_size)
		assert_not_null(view.get_chunk_view(coord), "a view under %s" % screen)
		assert_not_null(view.get_chunk_view(coord).terrain_mesh(), "with its ground (%s)" % coord)
	assert_null(view.get_chunk_view(Vector2i(-4, -4)), "the far corner has none")
	# Across the box: views come with the camera, from the workers.
	var streamed_before := streamer.streamed
	rig.focus_on(Vector3(-40.5, 0.0, -40.5), rig.config.min_distance, false)
	streamer.update(rig)
	assert_true(streamer.pending() > 0, "built on workers, not at once")
	streamer.finish_all()
	assert_true(streamer.streamed > streamed_before)
	assert_not_null(view.get_chunk_view(Vector2i(-3, -3)).terrain_mesh())
	assert_null(view.get_chunk_view(Vector2i(2, 2)), "what was left behind is released")
	# And back to the whole box.
	rig.frame_box(false)
	streamer.update(rig)
	streamer.finish_all()
	assert_eq(view.chunk_view_count(), 64)


func test_a_streamed_chunk_looks_as_one_built_at_once() -> void:
	var rig := view.camera_rig()
	var streamer := view.chunk_streamer()
	rig.focus_on(Vector3(-40.5, 0.0, -40.5), rig.config.min_distance, false)
	streamer.update(rig)
	streamer.finish_all()
	rig.frame_box(false)
	streamer.update(rig)
	streamer.finish_all()
	var checked := 0
	for coord in world.chunk_coords():
		var shown := view.get_chunk_view(coord)
		var made := TerrainMesher.build_mesh(world, coord, Config.terrain_palette, world.height_step)
		assert_eq(_vertices(shown.terrain_mesh()), _vertices(made), "terrain of %s" % coord)
		var deep := Config.terrain_palette.water_deep_levels * world.height_step
		assert_eq(_vertices(shown.water_mesh()), _vertices(WaterMesher.build_mesh(world, coord, deep)), "water of %s" % coord)
		assert_eq(_vertices(shown.props_mesh()), _vertices(PropMesher.build_mesh(world, props, coord, PropMeshLibrary.new())),
			"props of %s" % coord)
		checked += 1
	assert_eq(checked, 64)
	assert_true(streamer.streamed > 0, "some of them came from the workers")


func test_a_change_while_building_is_not_lost() -> void:
	var rig := view.camera_rig()
	var streamer := view.chunk_streamer()
	rig.focus_on(Vector3(40.5, 0.0, 40.5), rig.config.min_distance, false)
	streamer.update(rig)
	streamer.finish_all()
	rig.frame_box(false)
	streamer.update(rig) # builds started from copies of the chunks as they are now
	var building: Vector2i = Vector2i(-4, -4)
	for coord: Vector2i in view.chunk_streamer().views:
		var job: RefCounted = view.get_chunk_view(coord).job
		if job != null:
			building = coord
			break
	assert_not_null(view.get_chunk_view(building).job, "a build under way")
	# The ground changes under it, and is drawn anew at once.
	var tile := WorldCoords.chunk_origin(building, world.chunk_size) + Vector2i(5, 5)
	var level := world.get_height(tile)
	world.set_height(tile, level + 3)
	view.refresh_dirty_chunks()
	streamer.finish_all()
	var made := TerrainMesher.build_mesh(world, building, Config.terrain_palette, world.height_step)
	assert_eq(_vertices(view.get_chunk_view(building).terrain_mesh()), _vertices(made), "the change stands")
	world.set_height(tile, level)
	view.refresh_dirty_chunks()


static func _vertices(mesh: Mesh) -> PackedVector3Array:
	if mesh == null:
		return PackedVector3Array()
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
