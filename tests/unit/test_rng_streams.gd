extends TestCase


func _sequence(rng: RandomNumberGenerator, n: int) -> Array:
	var out := []
	for i in n:
		out.append(rng.randi())
	return out


func test_same_seed_and_name_same_sequence() -> void:
	assert_eq(_sequence(RngStreams.new(12345).stream(&"terrain"), 8), _sequence(RngStreams.new(12345).stream(&"terrain"), 8))


func test_streams_are_independent() -> void:
	var a := RngStreams.new(7)
	var expected := _sequence(RngStreams.new(7).stream(&"terrain"), 5)
	_sequence(a.stream(&"people"), 100) # heavy use of another stream
	assert_eq(_sequence(a.stream(&"terrain"), 5), expected)


func test_seeds_differ_by_name_and_world_seed() -> void:
	assert_ne(RngStreams.derive_seed(12345, &"terrain"), RngStreams.derive_seed(12345, &"people"))
	assert_ne(RngStreams.derive_seed(12345, &"terrain"), RngStreams.derive_seed(12346, &"terrain"))


func test_fnv1a_reference_values() -> void:
	# Pinned so seeds never change silently (would alter every saved world).
	assert_eq(RngStreams.fnv1a_32(""), 0x811C9DC5)
	assert_eq(RngStreams.fnv1a_32("a"), 0xE40C292C)
	assert_eq(RngStreams.fnv1a_32("foobar"), 0xBF9CF968)


func test_state_roundtrip_continues_sequence() -> void:
	var a := RngStreams.new(99)
	_sequence(a.stream(&"terrain"), 3)
	var saved := a.to_dict()
	var expected := _sequence(a.stream(&"terrain"), 4)
	var b := RngStreams.new()
	b.from_dict(saved)
	assert_eq(_sequence(b.stream(&"terrain"), 4), expected)


func test_new_world_seed_positive() -> void:
	for i in 20:
		assert_true(RngStreams.new_world_seed() > 0)
