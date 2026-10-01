extends TestCase


func test_monotonic_from_one() -> void:
	var ids := IdAllocator.new()
	assert_eq(ids.next_id(), 1)
	assert_eq(ids.next_id(), 2)
	assert_eq(ids.peek(), 3)


func test_reserve_above() -> void:
	var ids := IdAllocator.new()
	ids.reserve_above(100)
	assert_eq(ids.next_id(), 101)
	ids.reserve_above(50) # lower reservation never moves backwards
	assert_eq(ids.next_id(), 102)


func test_roundtrip_and_sanitizing() -> void:
	var ids := IdAllocator.new()
	ids.reserve_above(41)
	var copy := IdAllocator.new()
	copy.from_dict(ids.to_dict())
	assert_eq(copy.next_id(), 42)
	copy.from_dict({"next_id": -7})
	assert_eq(copy.next_id(), 1)
