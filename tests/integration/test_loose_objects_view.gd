extends TestCase
## Loose objects on screen: batching, picking, moving, and the main scene.

const ViewScript := preload("res://scripts/rendering/world_view.gd")

var view: WorldView
var world: WorldData
var props: PropRegistry
var loose: LooseObjectRegistry
var ids: IdAllocator
var start: WorldSetup.StartInfo


func before_each() -> void:
	var cfg := WorldConfig.new()
	world = WorldData.create_centered(64, cfg.chunk_size, cfg.height_step)
	var generator := WorldGenerator.new(12345, load("res://data/worldgen/river_valley.tres"), cfg)
	world.set_generator(generator)
	var index := SpatialIndex.new(cfg.chunk_size)
	props = PropRegistry.new(cfg.chunk_size, index)
	loose = LooseObjectRegistry.new(cfg.chunk_size, index)
	ids = IdAllocator.new()
	start = WorldSetup.create_start(world, generator, props, ids, loose)
	view = ViewScript.new()
	add_child(view)
	view.show_world(world, props, start, loose)


func after_each() -> void:
	view.queue_free()
	await wait_frames(1)


func _first(kind: LooseObject.Kind) -> LooseObject:
	var found: Array = []
	for o in loose.all_objects():
		if o.kind == kind:
			found.append(o.id)
	found.sort()
	return loose.get_object(found[0])


## The rock lying closest to the settlement.
func _nearest_rock() -> LooseObject:
	var best: LooseObject = null
	var best_distance := INF
	var site := Vector2(start.settlement_tile)
	for o in loose.all_objects():
		var d := o.position.distance_to(site)
		if d < best_distance:
			best_distance = d
			best = o
	return best


func _look_at(xz: Vector2, distance: float = 12.0) -> CameraRig:
	var rig := view.camera_rig()
	rig.set_process(false)
	rig.set_view_size(Vector2(1080, 1920))
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)
	return rig


func test_every_loose_object_is_drawn_in_few_batches() -> void:
	var shown := view.loose_view()
	assert_eq(shown.object_count(), loose.size())
	assert_true(shown.batch_count() >= 2 and shown.batch_count() <= 4, "rocks and boulders, two looks each (%d)" % shown.batch_count())
	var instances := 0
	for child in shown.get_children():
		var batch := child as MultiMeshInstance3D
		if batch == null:
			continue # the drop shadow
		instances += batch.multimesh.instance_count
		assert_true(batch.multimesh.use_colors)
		assert_not_null(batch.multimesh.mesh)
		assert_not_null(batch.material_override, "drawn with the prop material (light, cloud shadows, wobble)")
	assert_eq(instances, loose.size())


func test_objects_lie_on_the_ground_where_the_data_says() -> void:
	var shown := view.loose_view()
	for o in loose.all_objects():
		var at := shown.object_transform(o.id)
		var ground := world.get_height(o.tile()) * world.height_step
		assert_near(at.origin.x, o.position.x, 0.0001)
		assert_near(at.origin.z, o.position.y, 0.0001)
		assert_near(at.origin.y, ground, 0.0001, "%s lies on the ground" % o.tile())
		assert_near(at.basis.get_scale().x, o.scale(), 0.001)


func test_moving_an_object_moves_its_picture() -> void:
	var shown := view.loose_view()
	var rock := _first(LooseObject.Kind.ROCK)
	var target := Vector2(start.settlement_tile) + Vector2(1.5, 1.5)
	loose.move(rock.id, target, 0.5)
	var at := shown.object_transform(rock.id)
	assert_near(at.origin.x, target.x, 0.0001)
	assert_near(at.origin.y, world.get_height(rock.tile()) * world.height_step + 0.5, 0.0001, "lifted")
	assert_false(shown.refresh(), "a move needs no rebuild")


func test_added_and_removed_objects_appear_and_disappear() -> void:
	var shown := view.loose_view()
	var before := shown.object_count()
	var log := LooseObject.new()
	log.id = ids.next_id()
	log.kind = LooseObject.Kind.LOG
	log.position = Vector2(start.settlement_tile) + Vector2(0.5, 1.5)
	loose.add(log)
	var gone := _first(LooseObject.Kind.BOULDER)
	loose.remove(gone.id)
	assert_eq(shown.object_count(), before, "batched: nothing changes until the next frame")
	assert_true(shown.refresh())
	assert_eq(shown.object_count(), before)
	assert_true(shown.is_shown(log.id))
	assert_false(shown.is_shown(gone.id))
	assert_false(shown.refresh(), "nothing left to do")
	await wait_frames(2) # and it happens by itself too
	loose.remove(log.id)
	await wait_frames(2)
	assert_false(shown.is_shown(log.id))


func test_every_kind_has_a_shape() -> void:
	var library := PropMeshLibrary.new()
	for kind: int in LooseObject.Kind.values():
		var template := library.loose_template(kind, 0)
		assert_not_null(template, LooseObject.Kind.keys()[kind])
		assert_true(template.triangle_count() >= 8)
		assert_true(library.loose_template(kind, 7) != null, "unknown variants fall back")
		var top := 0.0
		var low := 0.0
		for v in template.vertices:
			top = maxf(top, v.y)
			low = minf(low, v.y)
		assert_true(low >= -0.01, "%s stands on the ground" % LooseObject.Kind.keys()[kind])
		var spec: Dictionary = LooseObject.SPECS[kind]
		assert_near(top, float(spec["height"]), float(spec["height"]) * 0.45 + 0.03, "body height matches the shape")
	assert_true(library.all_loose_templates().size() >= LooseObject.Kind.size())


func test_objects_follow_the_terrain_when_it_changes() -> void:
	var rock := _first(LooseObject.Kind.ROCK)
	var tile := rock.tile()
	var before := view.loose_view().object_transform(rock.id).origin.y
	world.set_height(tile, world.get_height(tile) + 3)
	view.refresh_dirty_chunks()
	assert_near(view.loose_view().object_transform(rock.id).origin.y, before + 3 * world.height_step, 0.0001)
	world.set_height(tile, world.get_height(tile) - 3)
	view.refresh_dirty_chunks()


func test_a_rock_can_be_picked_and_highlighted() -> void:
	var rock := _nearest_rock()
	var rig := _look_at(rock.position)
	var at := rock.world_position(world)
	var result := view.pick(rig.world_to_screen(at + Vector3(0, rock.height() * 0.5, 0)), 40.0)
	assert_eq(result.kind, Picker.Kind.ENTITY)
	assert_eq(result.entity_id, rock.id)
	assert_eq(result.entity_kind, SpatialIndex.KIND_LOOSE_OBJECT)
	view.show_pick(result)
	assert_true(view.pick_highlight().entity_visible())
	assert_near(view.pick_highlight().entity_position().x, rock.position.x, 0.01)
	# Props are still picked as before.
	var hut := props.get_prop(start.hut_ids[0])
	_look_at(hut.position2d())
	var roof := Vector3(hut.position2d().x, world.get_height(hut.tile) * world.height_step + 0.7, hut.position2d().y)
	assert_eq(view.pick(rig.world_to_screen(roof), 40.0).entity_id, hut.id)


func test_showing_another_world_replaces_the_objects() -> void:
	var shown := view.loose_view()
	view.show_world(WorldData.create_centered(32, 16))
	assert_eq(shown.object_count(), 0)
	assert_eq(shown.batch_count(), 0)
	assert_eq(loose.object_added.get_connections().size(), 0, "disconnected from the old registry")
	view.show_world(world, props, start, loose)
	view.show_world(world, props, start, loose)
	assert_eq(loose.object_moved.get_connections().size(), 1, "never connected twice")
	assert_eq(shown.object_count(), loose.size())
