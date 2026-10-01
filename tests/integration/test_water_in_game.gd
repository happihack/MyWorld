extends TestCase
## Water in the game: things that float and drift, the debug water tool, what
## is drawn and what is saved.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const ViewScript := preload("res://scripts/rendering/world_view.gd")

var session: WorldSession
var view: WorldView


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.loose_system.set_process(false) # tests step time themselves
	session.water.set_process(false)
	view = null


func after_each() -> void:
	if view != null:
		view.queue_free()
	session.queue_free()
	await wait_frames(1)


## The deepest river tile in row `z`.
func _river_tile(z: int) -> Vector2i:
	var best := Vector2i(0, z)
	var deepest := 0.0
	for x in range(session.world.bounds.position.x, session.world.bounds.end.x):
		var depth := session.world.get_water(Vector2i(x, z))
		if depth > deepest:
			deepest = depth
			best = Vector2i(x, z)
	return best


func _spawn(kind: LooseObject.Kind, at: Vector2, height: float = 1.0) -> LooseObject:
	var o := LooseObject.new()
	o.id = session.ids.next_id()
	o.kind = kind
	o.position = at
	o.height_offset = height
	session.loose.add(o)
	return o


func _run(seconds: float) -> void:
	for i in int(seconds * 60.0):
		session.loose_system.step(LooseObjectSystem.STEP_SECONDS)
		if i % 6 == 0:
			session.water.step(WaterSim.STEP_SECONDS)


func _dry_tile_near(tile: Vector2i) -> Vector2i:
	for radius in range(1, 12):
		for dx in range(-radius, radius + 1):
			var t := tile + Vector2i(dx, 0)
			if session.world.is_in_bounds(t) and session.world.get_water(t) <= 0.0 \
					and session.world.get_terrain(t) == ChunkData.Terrain.GRASS:
				return t
	return tile


func test_a_log_dropped_in_the_river_drifts_downstream_and_runs_aground() -> void:
	var tile := _river_tile(-10)
	var log := _spawn(LooseObject.Kind.LOG, Vector2(tile) + Vector2(0.5, 0.5))
	session.loose_system.drop(log.id)
	_run(1.5)
	assert_near(log.height_offset, session.world.get_water(log.tile()), 0.01, "it floats on the surface")
	var after_landing := log.position
	_run(6.0)
	assert_true(log.position.y > after_landing.y + 1.5, "it drifts downstream (%.2f -> %.2f)" % [after_landing.y, log.position.y])
	assert_true(session.world.get_water(log.tile()) > 0.0, "staying in the water")
	_run(240.0)
	assert_eq(log.state, LooseObject.State.RESTING, "until it runs aground")
	assert_true(Rect2(session.world.bounds).has_point(log.position))
	assert_true(log.position.y > after_landing.y + 5.0, "well downstream (%.1f tiles)" % (log.position.y - after_landing.y))
	assert_eq(session.loose_system.moving_count(), 0, "and then costs nothing")


func test_a_stone_sinks_and_stays() -> void:
	var tile := _river_tile(-10)
	var rock := _spawn(LooseObject.Kind.ROCK, Vector2(tile) + Vector2(0.5, 0.5))
	session.loose_system.drop(rock.id)
	_run(4.0)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0, "on the river bed")
	assert_eq(rock.tile(), tile, "the current does not move stone")


func test_a_tap_on_the_water_pushes_floating_things_away() -> void:
	var tile := _river_tile(0)
	var fruit := _spawn(LooseObject.Kind.FRUIT, Vector2(tile) + Vector2(0.8, 0.5), 0.0)
	fruit.height_offset = session.world.get_water(tile) # already afloat, at rest
	var stone := _spawn(LooseObject.Kind.ROCK, Vector2(tile) + Vector2(0.2, 0.5), 0.0)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.WATER
	target.tile = tile
	target.position = Vector3(tile.x + 0.3, 0.0, tile.y + 0.5)
	var response := session.interactions.tap(target)
	assert_eq(response.effect, InteractionResponse.RIPPLE)
	assert_true(session.loose_system.is_moving(fruit.id), "the fruit is set moving")
	assert_true(fruit.velocity.x > 0.3, "away from the finger (%s)" % fruit.velocity)
	assert_false(session.loose_system.is_moving(stone.id), "a sunken stone is not")


func test_floating_things_rise_and_fall_with_the_water() -> void:
	var tile := _river_tile(0)
	var log := _spawn(LooseObject.Kind.LOG, Vector2(tile) + Vector2(0.5, 0.5))
	# No current for this test: only the level matters.
	session.loose_system.bind(session.world, session.loose, session.props)
	session.loose_system.drop(log.id)
	_run(3.0)
	assert_eq(log.state, LooseObject.State.RESTING)
	var before := log.height_offset
	assert_near(before, session.world.get_water(log.tile()), 0.001)
	# Pour a lot onto the whole stretch so the level rises and stays.
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var t := log.tile() + Vector2i(dx, dz)
			if session.world.get_water(t) > 0.1:
				session.water.add_water(t, 0.3)
	_run(1.0)
	assert_true(log.height_offset > before + 0.1, "it rides up with the water (%.2f -> %.2f)" % [before, log.height_offset])


func test_the_water_tool_moves_water_without_making_or_losing_any() -> void:
	view = ViewScript.new()
	add_child(view)
	view.show_world(session.world, session.props, session.start, session.loose)
	var context := ToolBase.Context.new()
	context.session = session
	context.view = view
	var tool := WaterTool.new()
	tool.setup(context)
	session.water.soak_per_second = 0.0
	var river := _river_tile(0)
	var dry := _dry_tile_near(river)
	var before := session.water.total_volume()
	var target := Picker.Result.new()
	target.kind = Picker.Kind.TILE
	target.tile = dry
	assert_null(tool.tap(target))
	assert_near(session.water.total_volume(), before, 0.0, "an empty bucket pours nothing")
	target.tile = river
	target.kind = Picker.Kind.WATER
	tool.tap(target)
	assert_near(tool.bucket, WaterTool.SCOOP, 0.0001, "one scoop")
	assert_near(session.world.get_water(river) + WaterTool.SCOOP, before - (session.water.total_volume() - session.world.get_water(river)), 0.001)
	_run(5.0) # the river closes over the hole
	tool.tap(target)
	var scooped := tool.bucket
	assert_true(scooped > WaterTool.SCOOP * 1.5, "a second scoop (%.2f in the bucket)" % scooped)
	assert_near(session.water.total_volume() + tool.bucket, before, 0.001)
	assert_eq(AudioManager.last_sound, &"plip")
	target.tile = dry
	target.kind = Picker.Kind.TILE
	tool.tap(target)
	assert_near(tool.bucket, scooped - WaterTool.SCOOP, 0.0001)
	assert_true(session.world.get_water(dry) > 0.0, "poured onto the ground")
	_run(30.0)
	assert_near(session.water.total_volume() + tool.bucket, before, 0.005, "nothing made, nothing lost")
	# The bucket has a brim.
	target.tile = river
	target.kind = Picker.Kind.WATER
	for i in 40:
		tool.tap(target)
	assert_true(tool.bucket <= WaterTool.BUCKET + 0.0001)
	assert_null(tool.tap(Picker.Result.new()))


func test_changed_water_is_redrawn_a_few_chunks_at_a_time() -> void:
	view = ViewScript.new()
	add_child(view)
	view.set_process(false)
	view.show_world(session.world, session.props, session.start, session.loose)
	assert_eq(view.refresh_dirty_water(), 0, "nothing to redraw in a still world")
	var river := _river_tile(0)
	var coord := WorldCoords.tile_to_chunk(river, session.world.chunk_size)
	var before := view.get_chunk_view(coord).water_mesh()
	session.world.set_water(river, session.world.get_water(river) + 0.5)
	assert_eq(view.refresh_dirty_water(), 1)
	assert_true(view.get_chunk_view(coord).water_mesh() != before, "the water of that chunk was rebuilt")
	assert_eq(view.refresh_dirty_water(), 0)
	# A change in every chunk is spread over calls.
	for c in session.world.chunk_coords():
		session.world.get_chunk(c).dirty |= ChunkData.DIRTY_WATER
	assert_eq(view.refresh_dirty_water(3), 3)
	assert_eq(view.refresh_dirty_water(3), 3)
	var rest := view.refresh_dirty_water()
	assert_eq(rest, session.world.chunk_coords().size() - 6, "every chunk gets its turn exactly once")
	# Water poured on dry ground appears where there was none.
	var dry := _dry_tile_near(river)
	session.water.add_water(dry, 0.4)
	view.refresh_dirty_water()
	assert_not_null(view.get_chunk_view(WorldCoords.tile_to_chunk(dry, session.world.chunk_size)).water_mesh())


func test_poured_water_survives_a_reload_and_goes_on_flowing() -> void:
	var dry := _dry_tile_near(_river_tile(0))
	session.water.soak_per_second = 0.0
	session.water.add_water(dry, 2.0)
	session.water.step_once()
	var volume := session.water.total_volume()
	assert_true(session.world.modified_chunks().size() >= 1)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.water.set_process(false)
	again.water.soak_per_second = 0.0
	assert_near(again.water.total_volume(), volume, 0.001, "the same water")
	assert_near(again.world.get_water(dry), session.world.get_water(dry), 0.0001)
	assert_false(again.water.is_still(), "still on its way")
	var moved := [0]
	again.water.tiles_changed.connect(func(tiles: Array[Vector2i]) -> void: moved[0] += tiles.size())
	again.water.step_once()
	assert_true(moved[0] > 0, "and it goes on spreading")
	again.queue_free()


func test_an_untouched_world_keeps_its_water_asleep() -> void:
	for i in 100:
		session.water.step(0.1)
	assert_true(session.water.is_still())
	assert_eq(session.world.modified_chunks().size(), 0, "nothing changed, nothing to save")
	assert_eq(session.water.last_step_usec, 0)
