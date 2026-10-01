extends TestCase
## LooseObject and LooseObjectRegistry: movable things as data.

var index: SpatialIndex
var registry: LooseObjectRegistry
var ids: IdAllocator
var events: Array = []


func before_each() -> void:
	index = SpatialIndex.new(16)
	registry = LooseObjectRegistry.new(16, index)
	ids = IdAllocator.new()
	events.clear()
	registry.object_added.connect(func(id: int) -> void: events.append(["added", id]))
	registry.object_removed.connect(func(id: int) -> void: events.append(["removed", id]))
	registry.object_moved.connect(func(id: int) -> void: events.append(["moved", id]))


func _new(kind: LooseObject.Kind, at: Vector2, scale_percent: int = 100) -> LooseObject:
	var o := LooseObject.new()
	o.id = ids.next_id()
	o.kind = kind
	o.position = at
	o.scale_percent = scale_percent
	return o


func _rock_prop(tile: Vector2i, scale_percent: int = 100) -> PropData:
	var p := PropData.new()
	p.kind = PropData.Kind.ROCK
	p.tile = tile
	p.id = PropData.generated_id(tile)
	p.scale_percent = scale_percent
	p.variant = 1
	p.rotation_step = 64
	p.offset_x = 32
	return p


func _generated(tile: Vector2i, scale_percent: int = 100) -> LooseObject:
	return LooseObject.from_generated_rock(_rock_prop(tile, scale_percent))


# --- the object ---------------------------------------------------------------------------

func test_every_kind_has_a_body_and_a_weight() -> void:
	assert_eq(LooseObject.SPECS.size(), LooseObject.Kind.size())
	for kind: int in LooseObject.Kind.values():
		var o := _new(kind as LooseObject.Kind, Vector2.ZERO)
		assert_true(o.radius() > 0.0 and o.height() > 0.0 and o.mass() > 0.0, LooseObject.Kind.keys()[kind])
		assert_eq(o.pick_shape(), Vector2(o.height(), o.radius()))
	var rock := _new(LooseObject.Kind.ROCK, Vector2.ZERO)
	var boulder := _new(LooseObject.Kind.BOULDER, Vector2.ZERO)
	var pebble := _new(LooseObject.Kind.PEBBLE, Vector2.ZERO)
	assert_true(boulder.mass() > rock.mass() * 8.0, "a boulder is far heavier than a rock")
	assert_true(pebble.mass() < rock.mass() / 10.0)
	assert_true(boulder.radius() > rock.radius() and rock.radius() > pebble.radius())
	for o in [rock, boulder, pebble]:
		assert_true(o.is_stone())
		assert_false(o.floats(), "stone sinks")
	for kind: LooseObject.Kind in [LooseObject.Kind.LOG, LooseObject.Kind.FRUIT, LooseObject.Kind.SEED]:
		var o := _new(kind, Vector2.ZERO)
		assert_true(o.floats(), LooseObject.Kind.keys()[kind])
		assert_false(o.is_stone())


func test_heavy_things_give_way_less() -> void:
	var rock := _new(LooseObject.Kind.ROCK, Vector2.ZERO)
	var boulder := _new(LooseObject.Kind.BOULDER, Vector2.ZERO)
	var pebble := _new(LooseObject.Kind.PEBBLE, Vector2.ZERO)
	assert_near(rock.give(), 1.0, 0.0001, "an ordinary rock is the measure")
	assert_true(boulder.give() < 0.35, "a boulder barely stirs (%.2f)" % boulder.give())
	assert_true(pebble.give() > 1.5, "a pebble jumps (%.2f)" % pebble.give())
	assert_true(_new(LooseObject.Kind.BOULDER, Vector2.ZERO, 400).give() >= 0.2, "but everything answers a little")


func test_size_changes_body_and_weight() -> void:
	var small := _new(LooseObject.Kind.ROCK, Vector2.ZERO, 80)
	var big := _new(LooseObject.Kind.ROCK, Vector2.ZERO, 160)
	assert_near(big.radius(), small.radius() * 2.0, 0.0001)
	assert_near(big.mass(), small.mass() * 8.0, 0.001, "weight grows with volume")


func test_generated_rock_becomes_a_rock_or_a_boulder() -> void:
	var prop := _rock_prop(Vector2i(4, -9), 96)
	var rock := LooseObject.from_generated_rock(prop)
	assert_eq(rock.kind, LooseObject.Kind.ROCK)
	assert_eq(rock.id, prop.id, "same stable id as the rock it replaces")
	assert_true(rock.is_generated())
	assert_eq(rock.position, prop.position2d())
	assert_eq(rock.tile(), Vector2i(4, -9))
	assert_near(rock.yaw, prop.rotation_radians(), 0.0001)
	assert_eq(rock.variant, 1)
	assert_eq(rock.scale_percent, 96)
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0)
	assert_false(rock.placed_by_player)
	assert_eq(LooseObject.from_generated_rock(_rock_prop(Vector2i(0, 0), LooseObject.BOULDER_FROM_SCALE - 1)).kind, LooseObject.Kind.ROCK)
	var boulder := LooseObject.from_generated_rock(_rock_prop(Vector2i(0, 0), LooseObject.BOULDER_FROM_SCALE))
	assert_eq(boulder.kind, LooseObject.Kind.BOULDER)
	assert_true(boulder.scale_percent >= 90 and boulder.scale_percent <= 110)


func test_world_position_follows_the_ground() -> void:
	var world := WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.5
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	var o := _new(LooseObject.Kind.ROCK, Vector2(3.25, -4.75))
	assert_eq(o.world_position(world), Vector3(3.25, 1.0, -4.75))
	world.set_height(o.tile(), 6)
	assert_eq(o.world_position(world), Vector3(3.25, 3.0, -4.75), "raised with the ground")
	o.height_offset = 0.8
	assert_near(o.world_position(world).y, 3.8, 0.0001, "held above it")


func test_record_round_trip() -> void:
	var o := _new(LooseObject.Kind.LOG, Vector2(1.5, -2.25), 120)
	o.variant = 3
	o.height_offset = 0.4
	o.yaw = 1.25
	o.placed_by_player = true
	o.moved_count = 7
	o.discovered_by = PackedInt64Array([11, 12])
	var back := LooseObject.from_dict(o.to_dict())
	assert_eq(back.id, o.id)
	assert_eq(back.kind, LooseObject.Kind.LOG)
	assert_eq(back.position, o.position)
	assert_eq(back.variant, 3)
	assert_near(back.height_offset, 0.4, 0.0001)
	assert_near(back.yaw, 1.25, 0.0001)
	assert_eq(back.scale_percent, 120)
	assert_true(back.placed_by_player)
	assert_eq(back.moved_count, 7)
	assert_eq(back.discovered_by, PackedInt64Array([11, 12]))
	# Motion is not saved: an object in the air is saved lying on the ground.
	o.state = LooseObject.State.FALLING
	o.velocity = Vector3(1, 2, 3)
	var landed := LooseObject.from_dict(o.to_dict())
	assert_eq(landed.state, LooseObject.State.RESTING, "loaded objects are at rest")
	assert_eq(landed.velocity, Vector3.ZERO)
	assert_near(landed.height_offset, 0.0, 0.0)
	assert_eq(landed.position, o.position)
	o.state = LooseObject.State.HELD
	assert_near(LooseObject.from_dict(o.to_dict()).height_offset, 0.0, 0.0, "a held object too")


func test_unusable_records_are_rejected() -> void:
	var good := _new(LooseObject.Kind.ROCK, Vector2(1, 1)).to_dict()
	assert_not_null(LooseObject.from_dict(good))
	for change: Array in [["id", "x"], ["kind", 99], ["kind", -1], ["position", Vector3.ZERO], ["position", Vector2(NAN, 0)]]:
		var bad := good.duplicate()
		bad[change[0]] = change[1]
		assert_null(LooseObject.from_dict(bad), "%s = %s" % change)
	var odd := good.duplicate()
	odd["height_offset"] = -3.0
	odd["scale_percent"] = 100000
	odd["moved_count"] = -2
	var fixed := LooseObject.from_dict(odd)
	assert_near(fixed.height_offset, 0.0, 0.0, "never below the ground")
	assert_eq(fixed.scale_percent, 400)
	assert_eq(fixed.moved_count, 0)


# --- the registry -------------------------------------------------------------------------

func test_add_find_move_remove() -> void:
	var o := _new(LooseObject.Kind.ROCK, Vector2(2.5, 3.5))
	assert_true(registry.add(o))
	assert_eq(registry.size(), 1)
	assert_true(registry.get_object(o.id) == o)
	assert_true(registry.has_object(o.id))
	assert_eq(index.get_position(o.id), Vector2(2.5, 3.5))
	assert_eq(index.get_kind(o.id), SpatialIndex.KIND_LOOSE_OBJECT)
	assert_eq(registry.pick_shape(o.id), o.pick_shape())
	assert_null(registry.pick_shape(999))

	assert_true(registry.move(o.id, Vector2(20.5, -7.5), 0.6, 2.0))
	assert_eq(o.position, Vector2(20.5, -7.5))
	assert_near(o.height_offset, 0.6, 0.0001)
	assert_near(o.yaw, 2.0, 0.0001)
	assert_eq(index.get_position(o.id), Vector2(20.5, -7.5), "the index follows, across chunks")
	assert_eq(index.query_radius(Vector2(20, -7), 2.0, SpatialIndex.KIND_LOOSE_OBJECT), [o.id] as Array[int])
	assert_true(registry.move(o.id, Vector2(21, -7)))
	assert_near(o.height_offset, 0.6, 0.0001, "height and turn stay unless given")

	assert_true(registry.remove(o.id))
	assert_eq(registry.size(), 0)
	assert_false(index.has(o.id))
	assert_false(registry.remove(o.id))
	assert_eq(events, [["added", o.id], ["moved", o.id], ["moved", o.id], ["removed", o.id]])


func test_bad_adds_and_moves_are_refused() -> void:
	var o := _new(LooseObject.Kind.ROCK, Vector2(1, 1))
	assert_true(registry.add(o))
	assert_false(registry.add(o), "same id twice")
	assert_false(registry.add(null))
	assert_false(registry.add(_generated(Vector2i(5, 5))), "generated objects only come from populate_chunk")
	var no_id := LooseObject.new()
	assert_false(registry.add(no_id))
	assert_false(registry.move(o.id, Vector2(NAN, 0)), "a broken position never gets in")
	assert_false(registry.move(o.id, Vector2(INF, 0)))
	assert_false(registry.move(12345, Vector2(1, 1)))
	assert_eq(o.position, Vector2(1, 1))
	registry.move(o.id, Vector2(1, 1), -5.0)
	assert_near(o.height_offset, 0.0, 0.0, "never below the ground")


func test_several_objects_can_share_a_tile() -> void:
	var a := _new(LooseObject.Kind.PEBBLE, Vector2(4.2, 4.2))
	var b := _new(LooseObject.Kind.PEBBLE, Vector2(4.8, 4.6))
	var c := _new(LooseObject.Kind.ROCK, Vector2(5.1, 4.5)) # next tile
	for o in [a, b, c]:
		assert_true(registry.add(o))
	var here := registry.objects_at(Vector2i(4, 4))
	assert_eq(here.size(), 2)
	assert_true(a in here and b in here)
	assert_eq(registry.objects_at(Vector2i(5, 4)), [c] as Array[LooseObject])
	assert_eq(registry.objects_at(Vector2i(9, 9)).size(), 0)
	# Without a spatial index the answer is the same.
	var plain := LooseObjectRegistry.new(16)
	plain.add(a)
	plain.add(c)
	assert_eq(plain.objects_at(Vector2i(4, 4)), [a] as Array[LooseObject])


func test_generated_objects_arrive_once_per_chunk() -> void:
	var chunk := Vector2i(0, 0)
	registry.populate_chunk(chunk, [_generated(Vector2i(1, 1)), _generated(Vector2i(2, 2), 118)])
	registry.populate_chunk(chunk, [_generated(Vector2i(3, 3))]) # ignored: already populated
	assert_true(registry.is_chunk_populated(chunk))
	assert_eq(registry.size(), 2)
	assert_eq(registry.get_object(PropData.generated_id(Vector2i(2, 2))).kind, LooseObject.Kind.BOULDER)
	assert_eq(index.size(), 2)


func test_untouched_generated_objects_are_not_saved() -> void:
	registry.populate_chunk(Vector2i(0, 0), [_generated(Vector2i(1, 1)), _generated(Vector2i(2, 2))])
	var data := registry.to_dict()
	assert_eq((data["objects"] as Array).size(), 0)
	assert_eq((data["removed"] as PackedInt64Array).size(), 0)
	assert_eq(registry.saved_count(), 0)


func test_moved_removed_and_added_objects_survive_a_reload() -> void:
	var generated: Array[LooseObject] = [_generated(Vector2i(1, 1)), _generated(Vector2i(2, 2)), _generated(Vector2i(3, 3))]
	registry.populate_chunk(Vector2i(0, 0), generated)
	var moved_id := PropData.generated_id(Vector2i(1, 1))
	var removed_id := PropData.generated_id(Vector2i(2, 2))
	registry.move(moved_id, Vector2(9.5, 9.5), 0.0, 0.5)
	registry.get_object(moved_id).moved_count = 1
	registry.remove(removed_id)
	var pebble := _new(LooseObject.Kind.PEBBLE, Vector2(6.5, 6.5))
	pebble.placed_by_player = true
	registry.add(pebble)
	assert_eq(registry.saved_count(), 2, "the moved rock and the new pebble")
	assert_eq(registry.removed_generated_count(), 1)

	var data: Dictionary = bytes_to_var(var_to_bytes(registry.to_dict())) # as a save would
	var restored := LooseObjectRegistry.new(16, SpatialIndex.new(16))
	assert_eq(restored.from_dict(data), 0)
	var regenerated: Array[LooseObject] = [_generated(Vector2i(1, 1)), _generated(Vector2i(2, 2)), _generated(Vector2i(3, 3))]
	restored.populate_chunk(Vector2i(0, 0), regenerated)
	assert_eq(restored.size(), 3)
	var moved := restored.get_object(moved_id)
	assert_eq(moved.position, Vector2(9.5, 9.5), "where it was left, not where it was generated")
	assert_near(moved.yaw, 0.5, 0.0001)
	assert_eq(moved.moved_count, 1)
	assert_null(restored.get_object(removed_id), "stays gone")
	assert_eq(restored.get_object(PropData.generated_id(Vector2i(3, 3))).position, generated[2].position, "untouched: regenerated")
	var back := restored.get_object(pebble.id)
	assert_eq(back.kind, LooseObject.Kind.PEBBLE)
	assert_true(back.placed_by_player)
	assert_eq(restored.spatial_index.get_position(moved_id), Vector2(9.5, 9.5))
	# Saving again gives the same thing.
	assert_eq(var_to_bytes(restored.to_dict()), var_to_bytes(registry.to_dict()))


func test_touch_marks_a_generated_object_for_saving() -> void:
	registry.populate_chunk(Vector2i(0, 0), [_generated(Vector2i(1, 1))])
	var id := PropData.generated_id(Vector2i(1, 1))
	registry.get_object(id).discovered_by.append(42)
	assert_eq(registry.saved_count(), 0, "not known to have changed yet")
	registry.touch(id)
	assert_eq(registry.saved_count(), 1)
	registry.remove(id)
	assert_eq(registry.saved_count(), 0, "a removed object is only remembered as removed")


func test_unusable_save_data() -> void:
	assert_eq(registry.from_dict({"removed": "x", "objects": []}), -1)
	assert_eq(registry.from_dict({"removed": PackedInt64Array(), "objects": 5}), -1)
	var good := _new(LooseObject.Kind.ROCK, Vector2(1, 1)).to_dict()
	var skipped := registry.from_dict({
		"removed": PackedInt64Array([7, PropData.generated_id(Vector2i(4, 4))]), # 7 is not a generated id
		"objects": [good, good, "junk", {"id": 3}],
	})
	assert_eq(skipped, 4, "bad removed id, duplicate, junk, incomplete")
	assert_eq(registry.size(), 1)
	assert_eq(registry.from_dict({}), 0, "missing lists mean nothing to restore")
	assert_eq(registry.size(), 0)


func test_removed_list_of_an_older_save_is_respected() -> void:
	var gone := PropData.generated_id(Vector2i(2, 2))
	registry.mark_removed(PackedInt64Array([gone, 5]))
	assert_eq(registry.removed_generated_count(), 1, "only generated ids count")
	registry.populate_chunk(Vector2i(0, 0), [_generated(Vector2i(1, 1)), _generated(Vector2i(2, 2))])
	assert_eq(registry.size(), 1)
	assert_null(registry.get_object(gone))


func test_clear_empties_the_index_too() -> void:
	registry.add(_new(LooseObject.Kind.ROCK, Vector2(1, 1)))
	registry.populate_chunk(Vector2i(0, 0), [_generated(Vector2i(3, 3))])
	index.insert(900, Vector2(5, 5), SpatialIndex.KIND_BUILDING) # someone else's entry
	registry.clear()
	assert_eq(registry.size(), 0)
	assert_eq(index.size(), 1, "only its own entries are removed")
	assert_false(registry.is_chunk_populated(Vector2i(0, 0)))
