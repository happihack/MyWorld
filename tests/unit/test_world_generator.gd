extends TestCase

## SHA-256 of the generated layers of seed 12345 (64x64, River Valley), per
## WorldGenerator.GENERATOR_VERSION. If this fails you changed generator
## output: bump GENERATOR_VERSION, add the new checksum, and read the comment
## on that constant about existing worlds.
const GOLDEN := {
	1: "deec5d8dec3f0331d28560ee18d44d7d9965d28106c0fcd4ca5ded6741be4b95",
	2: "deec5d8dec3f0331d28560ee18d44d7d9965d28106c0fcd4ca5ded6741be4b95", # (the ground as it was: only props were added)
}

const SEEDS := [1, 2, 3, 7, 42, 12345, 987654321, 5636584777608190886]

var template: StartTemplate
var config: WorldConfig


func before_all() -> void:
	template = load("res://data/worldgen/river_valley.tres")
	config = WorldConfig.new()


func _make_world(seed_value: int, size: int = 64) -> WorldData:
	var world := WorldData.create_centered(size, config.chunk_size)
	world.set_generator(WorldGenerator.new(seed_value, template, config))
	return world


func _load_all(world: WorldData, reverse: bool = false) -> void:
	var coords := world.chunk_coords()
	if reverse:
		coords.reverse()
	for c in coords:
		world.get_chunk(c)


func _checksum(world: WorldData, rect: Rect2i) -> String:
	return WorldChecksum.terrain(world, rect)


func test_template_is_valid() -> void:
	assert_not_null(template)
	assert_eq(template.validate().size(), 0, str(template.validate()))
	assert_eq(template.shape, StartTemplate.Shape.RIVER_VALLEY)


func test_same_seed_same_world() -> void:
	var a := _make_world(12345)
	var b := _make_world(12345)
	assert_eq(_checksum(a, a.bounds), _checksum(b, b.bounds))


func test_different_seeds_differ() -> void:
	var seen := {}
	for seed_value: int in SEEDS:
		var w := _make_world(seed_value)
		seen[_checksum(w, w.bounds)] = true
	assert_eq(seen.size(), SEEDS.size())


func test_generation_order_does_not_matter() -> void:
	var forward := _make_world(42)
	_load_all(forward)
	var backward := _make_world(42)
	_load_all(backward, true)
	assert_eq(_checksum(forward, forward.bounds), _checksum(backward, backward.bounds))


func test_unloaded_chunks_regenerate_identically() -> void:
	var w := _make_world(7)
	var before := _checksum(w, w.bounds)
	for c in w.chunk_coords():
		assert_true(w.unload_chunk(c), "generated chunks are pristine, so they can be dropped")
	assert_eq(w.loaded_chunks().size(), 0)
	assert_eq(_checksum(w, w.bounds), before)


func test_terrain_does_not_depend_on_box_size() -> void:
	# Unfolding the box must never change existing terrain.
	var small := _make_world(12345, 64)
	var big := _make_world(12345, 128)
	assert_eq(_checksum(big, small.bounds), _checksum(small, small.bounds))


func test_generated_chunks_are_pristine() -> void:
	var w := _make_world(3)
	_load_all(w)
	assert_eq(w.modified_chunks().size(), 0)
	assert_eq((w.to_dict()["chunks"] as Array).size(), 0, "nothing to save for an untouched world")
	assert_true(w.get_chunk(Vector2i(0, 0)).is_dirty(ChunkData.DIRTY_MESH))


func test_values_are_valid_for_many_seeds() -> void:
	for seed_value: int in SEEDS:
		var w := _make_world(seed_value)
		for y in range(w.bounds.position.y, w.bounds.end.y):
			for x in range(w.bounds.position.x, w.bounds.end.x):
				var tile := Vector2i(x, y)
				var h := w.get_height(tile)
				var water := w.get_water(tile)
				var terrain := w.get_terrain(tile)
				var wet_kind := terrain == ChunkData.Terrain.RIVERBED or terrain == ChunkData.Terrain.SAND
				var problem := ""
				if h < 0 or h >= config.height_levels:
					problem = "height %d" % h
				elif is_nan(water) or water < 0.0:
					problem = "water %s" % water
				elif water > 0.0 and not wet_kind:
					problem = "water on dry terrain %d" % terrain
				elif not wet_kind and h < template.floor_level:
					problem = "dry land below the valley floor (h=%d)" % h
				elif terrain == ChunkData.Terrain.RIVERBED and water <= 0.0:
					problem = "dry river bed"
				if problem != "":
					fail("seed %d tile %s: %s" % [seed_value, tile, problem])
					return


func test_river_runs_unbroken_through_the_box() -> void:
	for seed_value: int in SEEDS:
		var w := _make_world(seed_value)
		var b := w.bounds
		# Flood fill through water from the top row; it must reach the bottom row.
		var frontier: Array[Vector2i] = []
		var seen := {}
		for x in range(b.position.x, b.end.x):
			var t := Vector2i(x, b.position.y)
			if w.get_water(t) > 0.0:
				frontier.append(t)
				seen[t] = true
		assert_true(frontier.size() >= 2, "seed %d: river enters at the top" % seed_value)
		var reached_bottom := false
		while not frontier.is_empty():
			var t: Vector2i = frontier.pop_back()
			if t.y == b.end.y - 1:
				reached_bottom = true
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = t + d
				if b.has_point(n) and not seen.has(n) and w.get_water(n) > 0.0:
					seen[n] = true
					frontier.append(n)
		assert_true(reached_bottom, "seed %d: river is connected top to bottom" % seed_value)


func test_world_has_usable_land() -> void:
	for seed_value: int in SEEDS:
		var w := _make_world(seed_value)
		var grass := 0
		var total := w.bounds.size.x * w.bounds.size.y
		for y in range(w.bounds.position.y, w.bounds.end.y):
			for x in range(w.bounds.position.x, w.bounds.end.x):
				if w.get_terrain(Vector2i(x, y)) == ChunkData.Terrain.GRASS:
					grass += 1
		assert_true(grass * 100 / total >= 35, "seed %d: only %d%% grass" % [seed_value, grass * 100 / total])


func test_sample_tile_matches_chunk_data() -> void:
	var gen := WorldGenerator.new(42, template, config)
	var w := WorldData.create_centered(64, config.chunk_size)
	w.set_generator(gen)
	for tile in [Vector2i(0, 0), Vector2i(-32, -32), Vector2i(31, 31), Vector2i(-7, 19)]:
		var s := gen.sample_tile(tile)
		assert_eq(s["height"], w.get_height(tile))
		assert_eq(s["terrain"], int(w.get_terrain(tile)))
		assert_near(s["water"], w.get_water(tile), 0.00001, "chunk stores 32-bit floats")


func test_golden_checksum_for_current_generator_version() -> void:
	var w := _make_world(12345)
	var actual := _checksum(w, w.bounds)
	assert_true(GOLDEN.has(WorldGenerator.GENERATOR_VERSION), "no golden checksum for GENERATOR_VERSION %d" % WorldGenerator.GENERATOR_VERSION)
	assert_eq(actual, GOLDEN.get(WorldGenerator.GENERATOR_VERSION, ""), "generator output changed")


func test_generation_is_fast_enough() -> void:
	var w := _make_world(99)
	var t0 := Time.get_ticks_msec()
	_load_all(w)
	var ms := Time.get_ticks_msec() - t0
	assert_true(ms < 1500, "64x64 world took %d ms on this machine" % ms)


# --- the terraced lands (2026-10-08) -------------------------------------------------------------

func _land_world(land: StringName, seed_value: int, size: int = 64) -> WorldData:
	var world := WorldData.create_centered(size, config.chunk_size)
	world.set_generator(WorldGenerator.new(seed_value, load("res://data/worldgen/%s.tres" % land), config))
	return world


func test_the_lands_are_sound() -> void:
	# Every land a new world may be: well defined, the river whole, the land
	# mostly usable, little bare rock, no dry hole below the floor.
	for land in WorldSession.LANDS:
		var template_now: StartTemplate = load("res://data/worldgen/%s.tres" % land)
		assert_eq(template_now.validate(), PackedStringArray(), String(land))
		assert_eq(template_now.terrain_style, StartTemplate.Style.TERRACED, String(land))
		for seed_value: int in [1, 7, 42]:
			var w := _land_world(land, seed_value)
			var grass := 0
			var rock := 0
			var total := w.bounds.size.x * w.bounds.size.y
			for y in range(w.bounds.position.y, w.bounds.end.y):
				for x in range(w.bounds.position.x, w.bounds.end.x):
					var tile := Vector2i(x, y)
					var kind := w.get_terrain(tile)
					grass += 1 if kind == ChunkData.Terrain.GRASS else 0
					rock += 1 if kind == ChunkData.Terrain.ROCK or kind == ChunkData.Terrain.SNOW else 0
					var wet := kind == ChunkData.Terrain.RIVERBED or kind == ChunkData.Terrain.SAND
					if not wet and w.get_height(tile) < template_now.floor_level:
						fail("%s seed %d: dry land below the floor at %s" % [land, seed_value, tile])
						return
			assert_true(grass * 100 / total >= 55, "%s seed %d: %d%% grass" % [land, seed_value, grass * 100 / total])
			assert_true(rock * 100 / total <= 15, "%s seed %d: %d%% rock (the mountains not in the way)" % [land, seed_value, rock * 100 / total])


func test_the_lowest_shelves_are_broad() -> void:
	# (The owner: the steps at the foot of the hills were too narrow.) Walking
	# out from the river, the first step up comes after a broad floor, and the
	# next after a broad shelf — not a stair of one-tile steps.
	for land in WorldSession.LANDS:
		var gen := WorldGenerator.new(7, load("res://data/worldgen/%s.tres" % land), config)
		var w := WorldData.create_centered(96, config.chunk_size)
		w.set_generator(gen)
		var widths: Array[int] = []
		for y in range(-40, 41, 8):
			var river := roundi(gen.river_center_x(y))
			for way: int in [-1, 1]:
				var last := w.get_height(Vector2i(river + way * 6, y))
				var since := 0
				for step in range(7, 46):
					var h := w.get_height(Vector2i(river + way * step, y))
					since += 1
					if h != last:
						if since > 0 and last > 0:
							widths.append(since)
						since = 0
						last = h
					if widths.size() > 0 and step > 30:
						break
		var narrow := widths.filter(func(n: int) -> bool: return n <= 1).size()
		assert_true(widths.is_empty() or narrow * 100 / widths.size() <= 25,
			"%s: %d of %d steps one tile wide %s" % [land, narrow, widths.size(), str(widths)])


func test_a_classic_world_stays_classic() -> void:
	# (The worlds made before the lands keep their ground: see GOLDEN.)
	assert_eq(template.terrain_style, StartTemplate.Style.CLASSIC)
