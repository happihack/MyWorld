extends TestCase

var index: SpatialIndex
var props: PropRegistry
var ids: IdAllocator


func before_each() -> void:
	index = SpatialIndex.new(16)
	props = PropRegistry.new(16, index)
	ids = IdAllocator.new()


func _generated(tile: Vector2i, kind: PropData.Kind = PropData.Kind.TREE) -> PropData:
	var p := PropData.new()
	p.tile = tile
	p.id = PropData.generated_id(tile)
	p.kind = kind
	return p


func _created(tile: Vector2i, kind: PropData.Kind = PropData.Kind.HUT) -> PropData:
	var p := PropData.new()
	p.tile = tile
	p.id = ids.next_id()
	p.kind = kind
	return p


func test_generated_ids_encode_the_tile_and_never_collide() -> void:
	var seen := {}
	for tile in [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(31, -32), Vector2i(-256, 255), Vector2i(100000, -100000)]:
		var id := PropData.generated_id(tile)
		assert_true(PropData.is_generated_id(id))
		assert_true(id > 0, "ids stay positive")
		assert_eq(PropData.tile_of_generated_id(id), tile)
		assert_false(seen.has(id))
		seen[id] = true
	assert_false(PropData.is_generated_id(ids.next_id()), "allocator ids are never 'generated'")
	assert_ne(PropData.generated_id(Vector2i(1, 2)), PropData.generated_id(Vector2i(2, 1)))


func test_prop_data_helpers_and_roundtrip() -> void:
	var p := _generated(Vector2i(-3, 4), PropData.Kind.BUSH)
	p.offset_x = 64
	p.offset_y = -64
	p.rotation_step = 64
	p.scale_percent = 110
	p.variant = 1
	assert_eq(p.position2d(), Vector2(-2.25, 4.25))
	assert_near(p.rotation_radians(), PI / 2.0)
	assert_near(p.scale(), 1.1)
	assert_eq(p.spatial_kind(), SpatialIndex.KIND_RESOURCE_NODE)
	var copy := PropData.from_dict(bytes_to_var(var_to_bytes(p.to_dict())))
	assert_eq(copy.to_dict(), p.to_dict())
	assert_null(PropData.from_dict({}))
	assert_null(PropData.from_dict({"id": 5, "tile": Vector2i.ZERO, "kind": 99}))


func test_populate_adds_generated_props_once() -> void:
	var chunk := Vector2i(0, 0)
	props.populate_chunk(chunk, [_generated(Vector2i(1, 1)), _generated(Vector2i(2, 2), PropData.Kind.ROCK)])
	props.populate_chunk(chunk, [_generated(Vector2i(3, 3))]) # ignored: already populated
	assert_eq(props.size(), 2)
	assert_true(props.is_chunk_populated(chunk))
	assert_eq(props.prop_at(Vector2i(2, 2)).kind, PropData.Kind.ROCK)
	assert_null(props.prop_at(Vector2i(3, 3)))
	assert_eq(props.props_in_chunk(chunk).size(), 2)
	assert_eq(index.size(), 2, "spatial index kept in sync")


func test_one_prop_per_tile() -> void:
	assert_true(props.add(_created(Vector2i(5, 5))))
	assert_false(props.add(_created(Vector2i(5, 5))), "tile occupied")
	props.populate_chunk(Vector2i(0, 0), [_generated(Vector2i(5, 5))])
	assert_eq(props.size(), 1)
	assert_eq(props.prop_at(Vector2i(5, 5)).kind, PropData.Kind.HUT)


func test_add_rejects_bad_props() -> void:
	assert_false(props.add(null))
	assert_false(props.add(_generated(Vector2i(1, 1))), "generated props only come from populate_chunk")
	var zero := PropData.new()
	assert_false(props.add(zero), "id 0 is invalid")
	var a := _created(Vector2i(1, 1))
	assert_true(props.add(a))
	var dup := PropData.new()
	dup.id = a.id
	dup.tile = Vector2i(9, 9)
	assert_false(props.add(dup), "duplicate id")


func test_removed_generated_props_stay_gone() -> void:
	var chunk := Vector2i(-1, -1)
	var tree := _generated(Vector2i(-2, -2))
	var keep := _generated(Vector2i(-3, -3))
	props.populate_chunk(chunk, [tree, keep])
	assert_true(props.remove(tree.id))
	assert_false(props.remove(tree.id), "already removed")
	assert_eq(index.query_radius(tree.position2d(), 0.5), [])
	# The chunk is unloaded and regenerated later: the removed tree stays removed.
	props.depopulate_chunk(chunk)
	assert_eq(props.size(), 0)
	props.populate_chunk(chunk, [_generated(Vector2i(-2, -2)), _generated(Vector2i(-3, -3))])
	assert_eq(props.size(), 1)
	assert_null(props.prop_at(Vector2i(-2, -2)))
	assert_not_null(props.prop_at(Vector2i(-3, -3)))


func test_depopulate_keeps_created_props() -> void:
	var chunk := Vector2i(0, 0)
	props.populate_chunk(chunk, [_generated(Vector2i(1, 1))])
	var hut := _created(Vector2i(4, 4))
	props.add(hut)
	props.depopulate_chunk(chunk)
	assert_eq(props.size(), 1)
	assert_eq(props.get_prop(hut.id).kind, PropData.Kind.HUT)


func test_save_stores_only_differences() -> void:
	var generated: Array[PropData] = []
	for i in 50:
		generated.append(_generated(Vector2i(i % 16, i / 16)))
	props.populate_chunk(Vector2i(0, 0), generated)
	props.remove(PropData.generated_id(Vector2i(3, 0)))
	props.remove(PropData.generated_id(Vector2i(4, 0)))
	var hut := _created(Vector2i(3, 0))
	props.add(hut)
	var data := props.to_dict()
	assert_eq((data["removed"] as PackedInt64Array).size(), 2)
	assert_eq((data["added"] as Array).size(), 1, "the 48 remaining generated props are not saved")

	var restored := PropRegistry.new(16, SpatialIndex.new(16))
	assert_eq(restored.from_dict(bytes_to_var(var_to_bytes(data))), 0)
	var regenerated: Array[PropData] = []
	for i in 50:
		regenerated.append(_generated(Vector2i(i % 16, i / 16)))
	restored.populate_chunk(Vector2i(0, 0), regenerated)
	assert_eq(restored.size(), props.size())
	assert_eq(restored.prop_at(Vector2i(3, 0)).kind, PropData.Kind.HUT)
	assert_null(restored.prop_at(Vector2i(4, 0)))


func test_bad_save_data() -> void:
	assert_eq(props.from_dict({"removed": "x"}), -1)
	assert_eq(props.from_dict({"added": 5}), -1)
	var data := {
		"removed": PackedInt64Array([PropData.generated_id(Vector2i(1, 1)), 7]), # 7 is not a generated id
		"added": [{"garbage": true}, _created(Vector2i(2, 2)).to_dict(), _created(Vector2i(2, 2)).to_dict()],
	}
	assert_eq(props.from_dict(data), 3, "non-generated removed id, garbage record, duplicate tile")
	assert_eq(props.size(), 1)


func test_clear_empties_index_too() -> void:
	props.populate_chunk(Vector2i(0, 0), [_generated(Vector2i(1, 1))])
	props.add(_created(Vector2i(2, 2)))
	props.clear()
	assert_eq(props.size(), 0)
	assert_eq(index.size(), 0)
	assert_false(props.is_chunk_populated(Vector2i(0, 0)))


func test_solid_parts_of_props() -> void:
	var hut := PropData.new()
	hut.kind = PropData.Kind.HUT
	var tree := PropData.new()
	tree.kind = PropData.Kind.TREE
	tree.scale_percent = 200
	var bush := PropData.new()
	bush.kind = PropData.Kind.BUSH
	assert_true(hut.collision_radius() > 0.35 and hut.collision_radius() < hut.pick_shape().y + 0.01, "a hut's walls")
	assert_near(tree.collision_radius(), 0.18, 0.0001, "a trunk, scaled with the tree")
	assert_true(tree.collision_radius() < tree.pick_shape().y, "much thinner than its canopy")
	assert_near(bush.collision_radius(), 0.0, 0.0, "bushes give way")


# --- changed generated props (a tree that lost its fruit) ---------------------------------------

func _tree_at(tile: Vector2i) -> PropData:
	var p := PropData.new()
	p.kind = PropData.Kind.TREE
	p.tile = tile
	p.id = PropData.generated_id(tile)
	return p


func test_what_a_tree_bears() -> void:
	var counts := {}
	for x in 40:
		var tree := _tree_at(Vector2i(x, 3))
		assert_true(tree.bears() >= 2 and tree.bears() <= 4)
		assert_eq(tree.bears(), _tree_at(Vector2i(x, 3)).bears(), "decided by its tile")
		counts[tree.bears()] = true
		var pine := _tree_at(Vector2i(x, 3))
		pine.variant = PropData.TREE_CONIFER_FIRST_VARIANT
		assert_true(pine.bears() >= 1 and pine.bears() <= 2)
	assert_eq(counts.size(), 3, "trees differ")
	var tree := _tree_at(Vector2i(1, 1))
	tree.taken = 1
	assert_eq(tree.bears_left(), tree.bears() - 1)
	tree.taken = 99
	assert_eq(tree.bears_left(), 0)
	assert_eq(PropData.from_dict(tree.to_dict()).taken, 99)
	var rock := PropData.new()
	rock.kind = PropData.Kind.ROCK
	assert_eq(rock.bears(), 0)


func test_a_changed_generated_prop_is_saved_and_restored() -> void:
	var chunk := Vector2i(0, 0)
	props.populate_chunk(chunk, [_tree_at(Vector2i(1, 1)), _tree_at(Vector2i(2, 2))])
	assert_eq((props.to_dict()["changed"] as Array).size(), 0, "untouched: nothing to save")
	var id := PropData.generated_id(Vector2i(1, 1))
	props.get_prop(id).taken = 2
	props.touch(id)
	assert_eq(props.changed_generated_count(), 1)
	var data: Dictionary = bytes_to_var(var_to_bytes(props.to_dict()))
	assert_eq((data["changed"] as Array).size(), 1)

	var restored := PropRegistry.new(16, SpatialIndex.new(16))
	assert_eq(restored.from_dict(data), 0)
	restored.populate_chunk(chunk, [_tree_at(Vector2i(1, 1)), _tree_at(Vector2i(2, 2))])
	assert_eq(restored.size(), 2)
	assert_eq(restored.get_prop(id).taken, 2, "as it was left")
	assert_eq(restored.get_prop(PropData.generated_id(Vector2i(2, 2))).taken, 0, "untouched: regenerated")
	assert_eq(var_to_bytes(restored.to_dict()), var_to_bytes(props.to_dict()), "saving again gives the same")


func test_changes_survive_their_chunk_being_unloaded() -> void:
	var chunk := Vector2i(0, 0)
	props.populate_chunk(chunk, [_tree_at(Vector2i(1, 1))])
	var id := PropData.generated_id(Vector2i(1, 1))
	props.get_prop(id).taken = 1
	props.touch(id)
	props.depopulate_chunk(chunk)
	assert_eq(props.size(), 0)
	assert_eq((props.to_dict()["changed"] as Array).size(), 1, "still in the save while unloaded")
	props.populate_chunk(chunk, [_tree_at(Vector2i(1, 1))])
	assert_eq(props.get_prop(id).taken, 1)


func test_a_removed_prop_is_not_also_saved_as_changed() -> void:
	props.populate_chunk(Vector2i(0, 0), [_tree_at(Vector2i(1, 1))])
	var id := PropData.generated_id(Vector2i(1, 1))
	props.touch(id)
	props.remove(id)
	assert_eq(props.changed_generated_count(), 0)
	assert_eq((props.to_dict()["changed"] as Array).size(), 0)
	# Touching an added (non-generated) prop does nothing: those are saved anyway.
	var hut := PropData.new()
	hut.id = 5
	hut.kind = PropData.Kind.HUT
	hut.tile = Vector2i(3, 3)
	props.add(hut)
	props.touch(5)
	assert_eq(props.changed_generated_count(), 0)


func test_bad_changed_records_are_skipped() -> void:
	var good := _tree_at(Vector2i(1, 1))
	good.taken = 1
	var wrong_id := _tree_at(Vector2i(2, 2)).to_dict()
	wrong_id["id"] = PropData.generated_id(Vector2i(9, 9)) # does not belong to its tile
	var not_generated := good.to_dict()
	not_generated["id"] = 12
	var skipped := props.from_dict({
		"removed": PackedInt64Array([PropData.generated_id(Vector2i(4, 4))]), "added": [],
		"changed": [good.to_dict(), wrong_id, not_generated, "junk", _tree_at(Vector2i(4, 4)).to_dict()],
	})
	assert_eq(skipped, 4, "wrong id, not generated, junk, and one that was removed")
	assert_eq(props.changed_generated_count(), 1)
	assert_eq(props.from_dict({"removed": PackedInt64Array(), "added": []}), 0, "older saves have no changed list")
