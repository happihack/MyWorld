extends TestCase

var index: SpatialIndex


func before_each() -> void:
	index = SpatialIndex.new(16)


func test_insert_and_lookup() -> void:
	index.insert(1, Vector2(2.5, 3.5), SpatialIndex.KIND_PERSON)
	assert_true(index.has(1))
	assert_eq(index.size(), 1)
	assert_eq(index.get_position(1), Vector2(2.5, 3.5))
	assert_eq(index.get_tile(1), Vector2i(2, 3))
	assert_eq(index.get_kind(1), SpatialIndex.KIND_PERSON)


func test_unknown_ids_are_safe() -> void:
	assert_false(index.has(99))
	assert_eq(index.get_position(99), Vector2.INF)
	assert_eq(index.get_kind(99), 0)
	index.move(99, Vector2(1, 1))
	index.remove(99)
	assert_eq(index.size(), 0)


func test_query_radius_nearest_first_across_chunk_borders() -> void:
	index.insert(1, Vector2(-0.5, -0.5), SpatialIndex.KIND_PERSON)   # chunk (-1,-1)
	index.insert(2, Vector2(0.5, 0.5), SpatialIndex.KIND_PERSON)     # chunk (0,0)
	index.insert(3, Vector2(1.5, 0.5), SpatialIndex.KIND_ANIMAL)     # chunk (0,0)
	index.insert(4, Vector2(40.0, 40.0), SpatialIndex.KIND_PERSON)   # far away
	assert_eq(index.query_radius(Vector2(0.4, 0.4), 3.0), [2, 3, 1])
	assert_eq(index.query_radius(Vector2(0.4, 0.4), 0.5), [2])
	assert_eq(index.query_radius(Vector2(-100, -100), 5.0), [])


func test_query_filters_by_kind_mask() -> void:
	index.insert(1, Vector2(0.1, 0.1), SpatialIndex.KIND_PERSON)
	index.insert(2, Vector2(0.2, 0.2), SpatialIndex.KIND_ANIMAL)
	index.insert(3, Vector2(0.3, 0.3), SpatialIndex.KIND_BUILDING)
	var center := Vector2.ZERO
	assert_eq(index.query_radius(center, 2.0, SpatialIndex.KIND_ANIMAL), [2])
	assert_eq(index.query_radius(center, 2.0, SpatialIndex.KIND_PERSON | SpatialIndex.KIND_BUILDING), [1, 3])
	assert_eq(index.query_radius(center, 2.0), [1, 2, 3])


func test_move_within_and_between_chunks() -> void:
	index.insert(7, Vector2(1, 1), SpatialIndex.KIND_PERSON)
	index.move(7, Vector2(2, 2))
	assert_eq(index.query_chunk(Vector2i(0, 0)), [7])
	index.move(7, Vector2(-20.5, 33.0))
	assert_eq(index.query_chunk(Vector2i(0, 0)), [])
	assert_eq(index.query_chunk(Vector2i(-2, 2)), [7])
	assert_eq(index.query_radius(Vector2(-20, 33), 1.0), [7])
	assert_eq(index.query_radius(Vector2(2, 2), 1.0), [])


func test_reinsert_updates_position_and_kind() -> void:
	index.insert(5, Vector2(1, 1), SpatialIndex.KIND_LOOSE_OBJECT)
	index.insert(5, Vector2(30, 30), SpatialIndex.KIND_RESOURCE_NODE)
	assert_eq(index.size(), 1)
	assert_eq(index.query_chunk(Vector2i(0, 0)), [])
	assert_eq(index.query_chunk(Vector2i(1, 1), SpatialIndex.KIND_RESOURCE_NODE), [5])


func test_remove_and_clear() -> void:
	for i in range(1, 6):
		index.insert(i, Vector2(i, i), SpatialIndex.KIND_PERSON)
	index.remove(3)
	assert_eq(index.query_radius(Vector2(3, 3), 0.1), [])
	assert_eq(index.size(), 4)
	index.clear()
	assert_eq(index.size(), 0)
	assert_eq(index.query_radius(Vector2(1, 1), 50.0), [])


func test_equal_distance_ties_break_by_id() -> void:
	index.insert(9, Vector2(1, 0), SpatialIndex.KIND_PERSON)
	index.insert(4, Vector2(-1, 0), SpatialIndex.KIND_PERSON)
	index.insert(6, Vector2(0, 1), SpatialIndex.KIND_PERSON)
	assert_eq(index.query_radius(Vector2.ZERO, 2.0), [4, 6, 9], "deterministic order")


func test_many_entities() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var positions := {}
	for id in range(1, 2001):
		var p := Vector2(rng.randf_range(-256, 256), rng.randf_range(-256, 256))
		positions[id] = p
		index.insert(id, p, SpatialIndex.KIND_PERSON)
	var center := Vector2(10, -20)
	var expected := 0
	for id: int in positions:
		if center.distance_to(positions[id]) <= 25.0:
			expected += 1
	assert_eq(index.query_radius(center, 25.0).size(), expected, "matches brute force")
