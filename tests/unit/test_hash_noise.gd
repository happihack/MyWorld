extends TestCase


func test_hash_is_deterministic_and_32_bit() -> void:
	for p in [[0, 0, 0], [1, 2, 3], [-5, 17, 99], [100000, -100000, 0x7FFFFFFF]]:
		var h := HashNoise.hash2(p[0], p[1], p[2])
		assert_eq(h, HashNoise.hash2(p[0], p[1], p[2]))
		assert_true(h >= 0 and h <= 0xFFFFFFFF, "%s -> %d" % [p, h])


func test_hash_changes_with_every_input() -> void:
	var base := HashNoise.hash2(10, 20, 30)
	assert_ne(HashNoise.hash2(11, 20, 30), base)
	assert_ne(HashNoise.hash2(10, 21, 30), base)
	assert_ne(HashNoise.hash2(10, 20, 31), base)
	assert_ne(HashNoise.hash2(20, 10, 30), base, "not symmetric in x/y")


func test_values_stay_in_range_including_negative_coordinates() -> void:
	for y in range(-40, 40, 3):
		for x in range(-40, 40, 3):
			for v in [HashNoise.tile_value(x, y, 7), HashNoise.value2(x, y, 16, 7), HashNoise.fbm2(x, y, 16, 3, 7)]:
				if v < 0 or v >= HashNoise.ONE:
					fail("out of range at (%d,%d): %d" % [x, y, v])
					return


func test_value_noise_is_smooth_and_continuous_across_cells() -> void:
	# With a 16-tile period, neighbouring tiles differ by a small fraction of the
	# range — including across lattice-cell borders and across zero.
	var biggest := 0
	for y in range(-33, 33):
		for x in range(-33, 33):
			var here := HashNoise.value2(x, y, 16, 1234)
			biggest = maxi(biggest, absi(HashNoise.value2(x + 1, y, 16, 1234) - here))
			biggest = maxi(biggest, absi(HashNoise.value2(x, y + 1, 16, 1234) - here))
	assert_true(biggest < HashNoise.ONE / 8, "largest neighbour step %d" % biggest)


func test_lattice_points_return_their_hash_value() -> void:
	assert_eq(HashNoise.value2(32, -48, 16, 5), HashNoise.hash2(2, -3, 5) & 0xFFFF)


func test_distribution_is_roughly_uniform() -> void:
	var total := 0
	var low := 0
	var n := 0
	for y in range(-50, 50):
		for x in range(-50, 50):
			var v := HashNoise.tile_value(x, y, 99)
			total += v
			if v < HashNoise.ONE / 4:
				low += 1
			n += 1
	assert_near(float(total) / n, HashNoise.ONE / 2.0, HashNoise.ONE * 0.02, "mean")
	assert_near(float(low) / n, 0.25, 0.02, "lowest quarter holds a quarter of the values")


func test_period_one_is_per_tile() -> void:
	assert_eq(HashNoise.value2(3, 4, 1, 8), HashNoise.tile_value(3, 4, 8))


func test_smoothstep_fixed() -> void:
	assert_eq(HashNoise.smoothstep_fixed(100, 200, 50), 0)
	assert_eq(HashNoise.smoothstep_fixed(100, 200, 150), 512)
	assert_eq(HashNoise.smoothstep_fixed(100, 200, 500), 1024)
	assert_eq(HashNoise.smoothstep_fixed(100, 100, 100), 1024, "degenerate edge acts as a step")
	assert_eq(HashNoise.smoothstep_fixed(100, 100, 99), 0)


func test_pinned_reference_values() -> void:
	# Pinned so the noise can never change silently (that would change every world).
	assert_eq(HashNoise.hash2(0, 0, 0), PINNED[0])
	assert_eq(HashNoise.hash2(1, 2, 3), PINNED[1])
	assert_eq(HashNoise.hash2(-7, 13, 0xABCDEF), PINNED[2])
	assert_eq(HashNoise.fbm2(-21, 9, 16, 3, 42), PINNED[3])


const PINNED := [0, 3866995166, 3154547570, 30580]
