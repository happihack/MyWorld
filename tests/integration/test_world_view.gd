extends TestCase
## WorldView showing a generated world: chunk meshes, merged props, ambient life.

const ViewScript := preload("res://scripts/rendering/world_view.gd")

var view: WorldView
var world: WorldData
var generator: WorldGenerator
var props: PropRegistry
var start: WorldSetup.StartInfo


func before_all() -> void:
	var cfg := WorldConfig.new()
	world = WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
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


func test_every_chunk_gets_terrain_and_props() -> void:
	assert_eq(view.chunk_view_count(), 16)
	var with_water := 0
	for coord in world.chunk_coords():
		var chunk_view := view.get_chunk_view(coord)
		assert_not_null(chunk_view.terrain_mesh(), "terrain for %s" % coord)
		assert_not_null(chunk_view.props_mesh(), "props for %s" % coord)
		if chunk_view.water_mesh() != null:
			with_water += 1
	assert_true(with_water >= 4 and with_water < 16, "only river chunks have water (%d)" % with_water)


func test_removing_a_prop_rebuilds_only_that_chunk() -> void:
	var tree: PropData = null
	for p in props.all_props():
		if p.kind == PropData.Kind.TREE:
			tree = p
			break
	assert_not_null(tree)
	var coord := WorldCoords.tile_to_chunk(tree.tile, world.chunk_size)
	var before := view.get_chunk_view(coord).props_mesh()
	var other_coord := Vector2i(-coord.x - 1, -coord.y - 1)
	var other_before := view.get_chunk_view(other_coord).props_mesh()
	props.remove(tree.id)
	assert_eq(view.refresh_dirty_props(), 1)
	assert_true(view.get_chunk_view(coord).props_mesh() != before, "that chunk's mesh was rebuilt")
	assert_true(view.get_chunk_view(other_coord).props_mesh() == other_before, "other chunks untouched")
	assert_eq(view.refresh_dirty_props(), 0, "nothing left to rebuild")


func test_prop_changes_are_picked_up_automatically() -> void:
	var coord := WorldCoords.tile_to_chunk(start.ruin_tile, world.chunk_size)
	var before := view.get_chunk_view(coord).props_mesh()
	props.remove(start.ruin_id)
	await wait_frames(2) # WorldView batches rebuilds once per frame
	assert_true(view.get_chunk_view(coord).props_mesh() != before)


func test_terrain_change_reseats_props() -> void:
	var tile := start.settlement_tile
	var coord := WorldCoords.tile_to_chunk(tile, world.chunk_size)
	var terrain_before := view.get_chunk_view(coord).terrain_mesh()
	var props_before := view.get_chunk_view(coord).props_mesh()
	world.set_height(tile, world.get_height(tile) + 2)
	assert_true(view.refresh_dirty_chunks() >= 1)
	view.refresh_dirty_props()
	assert_true(view.get_chunk_view(coord).terrain_mesh() != terrain_before)
	assert_true(view.get_chunk_view(coord).props_mesh() != props_before, "campfire now stands on the raised tile")
	world.set_height(tile, world.get_height(tile) - 2)
	view.refresh_dirty_chunks()


func test_ambient_life() -> void:
	var ambient := view.ambient()
	assert_eq(ambient.bird_count(), AmbientLife.BIRD_COUNT)
	assert_true(ambient.is_smoking())
	var smoke := ambient.smoke_position()
	assert_near(smoke.x, start.settlement_tile.x + 0.5, 0.001, "smoke rises from the campfire")
	assert_near(smoke.z, start.settlement_tile.y + 0.5, 0.001)
	assert_true(smoke.y > world.get_height(start.settlement_tile) * world.height_step)
	# Birds move.
	var before := ambient.bird_position(0)
	await wait_real_ms(300)
	assert_true(ambient.bird_position(0).distance_to(before) > 0.01, "birds move")
	for i in ambient.bird_count():
		assert_true(ambient.bird_position(i).y > 5.0, "bird %d flies above the terrain" % i)
	assert_true(ambient.bird_position(0).distance_to(ambient.bird_position(6)) > 1.0, "the flock is spread out")


func test_world_without_a_campfire_has_no_smoke() -> void:
	var bare := WorldData.create_centered(32, 16)
	view.show_world(bare)
	assert_false(view.ambient().is_smoking())
	assert_eq(view.chunk_view_count(), 4)
	assert_null(view.get_chunk_view(Vector2i(0, 0)).props_mesh())


func test_clear_disconnects_from_the_registry() -> void:
	view.clear()
	assert_eq(view.chunk_view_count(), 0)
	assert_false(props.chunk_changed.is_connected(view._on_props_changed))
	view.show_world(world, props, start) # showing again must not double-connect
	view.show_world(world, props, start)
	assert_eq(props.chunk_changed.get_connections().size(), 1)


func test_box_frame_matches_the_world() -> void:
	var frame := view.box_frame()
	assert_eq(frame.bounds, world.bounds)
	assert_not_null(frame.wood_mesh())
	var expected_height := Config.world.height_levels * world.height_step + WorldView.BOX_HEADROOM
	assert_near(frame.box_height, expected_height, 0.001, "posts clear the tallest possible terrain")
	# Showing a different world rebuilds the frame around it.
	view.show_world(WorldData.create_centered(32, 16))
	assert_eq(view.box_frame().bounds, Rect2i(-16, -16, 32, 32))


func test_lighting_follows_quality() -> void:
	var lighting := view.lighting()
	lighting.apply_quality(GraphicsQuality.Level.LOW)
	assert_false(lighting.shadows_enabled())
	assert_false(lighting.vignette_visible())
	lighting.apply_quality(GraphicsQuality.Level.MEDIUM)
	assert_true(lighting.shadows_enabled())
	assert_true(lighting.vignette_visible())
	# Changing the setting re-applies it.
	Settings.set_value(GraphicsQuality.SETTING, "low")
	assert_false(lighting.shadows_enabled())
	Settings.set_value(GraphicsQuality.SETTING, "high")
	assert_true(lighting.shadows_enabled())
	assert_eq(lighting.quality, GraphicsQuality.Level.HIGH)
	Settings.set_value(GraphicsQuality.SETTING, "auto")


func test_table_sits_under_the_box() -> void:
	var table := view.lighting().table_position()
	var frame := view.box_frame()
	assert_near(table.y, frame.bottom_y(), 0.001)
	assert_near(table.x, frame.outer_rect().get_center().x, 0.001)
	assert_near(table.z, frame.outer_rect().get_center().y, 0.001)
