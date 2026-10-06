extends TestCase

## SHA-256 of the generated props of seed 12345 (64x64, River Valley), per
## WorldGenerator.GENERATOR_VERSION (see test_world_generator.gd).
const GOLDEN_PROPS := {
	1: "1bcc1ac90813d950f5e48cb90b51aa12febe735193321a9cf8cf270d6e992f39",
	2: "200f451cd12d3ef157d3f7479d4c47f292db708da83391cf0b8beba9a4fb609a", # (mushrooms and roots: 2026-10-06)
}

var template: StartTemplate
var config: WorldConfig


class World:
	extends RefCounted
	var data: WorldData
	var generator: WorldGenerator
	var props: PropRegistry
	var ids: IdAllocator
	var info: WorldSetup.StartInfo


func before_all() -> void:
	template = load("res://data/worldgen/river_valley.tres")
	config = WorldConfig.new()


func _build(seed_value: int, run_setup: bool = true) -> World:
	var w := World.new()
	w.data = WorldData.create_centered(64, config.chunk_size)
	w.generator = WorldGenerator.new(seed_value, template, config)
	w.data.set_generator(w.generator)
	w.props = PropRegistry.new(config.chunk_size, SpatialIndex.new(config.chunk_size))
	w.ids = IdAllocator.new()
	if run_setup:
		w.info = WorldSetup.create_start(w.data, w.generator, w.props, w.ids)
	return w


func _props_checksum(props: PropRegistry, generated_only: bool) -> String:
	return WorldChecksum.props(props, generated_only)


func test_generated_props_are_valid() -> void:
	var w := _build(42, false)
	WorldSetup.populate_all(w.data, w.generator, w.props)
	assert_true(w.props.size() > 100, "world has contents (%d)" % w.props.size())
	var kinds := {}
	for p in w.props.all_props():
		kinds[p.kind] = true
		var terrain := w.data.get_terrain(p.tile)
		var problem := ""
		if not w.data.is_in_bounds(p.tile):
			problem = "outside the box"
		elif w.data.get_water(p.tile) > 0.0:
			problem = "in water"
		elif terrain == ChunkData.Terrain.RIVERBED or terrain == ChunkData.Terrain.SAND:
			problem = "on %d" % terrain
		elif p.kind == PropData.Kind.TREE and terrain != ChunkData.Terrain.GRASS:
			problem = "tree on non-grass"
		elif p.id != PropData.generated_id(p.tile):
			problem = "id does not match tile"
		elif absi(p.offset_x) > 77 or absi(p.offset_y) > 77 or p.scale_percent < 80 or p.scale_percent > 120:
			problem = "offset/scale out of range"
		if problem != "":
			fail("prop at %s: %s" % [p.tile, problem])
			return
	assert_true(kinds.has(PropData.Kind.TREE) and kinds.has(PropData.Kind.ROCK) and kinds.has(PropData.Kind.BUSH))


func test_props_are_deterministic_and_order_independent() -> void:
	var a := _build(7, false)
	WorldSetup.populate_all(a.data, a.generator, a.props)
	var b := _build(7, false)
	var coords := b.data.chunk_coords()
	coords.reverse()
	for c in coords:
		WorldSetup.populate_chunk(b.data, b.generator, b.props, c)
	assert_eq(_props_checksum(a.props, true), _props_checksum(b.props, true))
	var other := _build(8, false)
	WorldSetup.populate_all(other.data, other.generator, other.props)
	assert_ne(_props_checksum(a.props, true), _props_checksum(other.props, true))


func test_start_is_deterministic() -> void:
	var a := _build(12345)
	var b := _build(12345)
	assert_eq(a.info.to_dict(), b.info.to_dict())
	assert_eq(_props_checksum(a.props, false), _props_checksum(b.props, false))


func test_settlement_site_is_a_dry_flat_glade_near_water() -> void:
	for seed_value in [1, 2, 3, 42, 12345]:
		var w := _build(seed_value)
		assert_true(w.info.ok, "seed %d: %s" % [seed_value, w.info.problems])
		var site := w.info.settlement_tile
		var level := w.data.get_height(site)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var tile := site + Vector2i(dx, dy)
				assert_eq(w.data.get_height(tile), level, "seed %d: flat at %s" % [seed_value, tile])
				assert_eq(w.data.get_water(tile), 0.0)
				var p := w.props.prop_at(tile)
				assert_true(p == null or not p.is_generated(), "seed %d: glade cleared at %s" % [seed_value, tile])
		assert_eq(w.props.prop_at(site).kind, PropData.Kind.CAMPFIRE)
		assert_eq(w.info.hut_ids.size(), 3)
		for hut_id in w.info.hut_ids:
			var hut := w.props.get_prop(hut_id)
			assert_eq(hut.kind, PropData.Kind.HUT)
			assert_true(maxi(absi(hut.tile.x - site.x), absi(hut.tile.y - site.y)) <= 2)
		# Near water, but not on the bank.
		var nearest := 999
		for dy in range(-20, 21):
			for dx in range(-20, 21):
				if w.data.get_water(site + Vector2i(dx, dy)) > 0.0:
					nearest = mini(nearest, maxi(absi(dx), absi(dy)))
		assert_true(nearest >= 2 and nearest <= 16, "seed %d: water %d tiles away" % [seed_value, nearest])
		# Away from the walls.
		assert_true(w.data.bounds.grow(-WorldSetup.WALL_MARGIN).has_point(site))


func test_ruin_is_far_from_the_settlement() -> void:
	for seed_value in [1, 2, 3, 42, 12345]:
		var w := _build(seed_value)
		var ruin := w.props.get_prop(w.info.ruin_id)
		assert_not_null(ruin, "seed %d has a ruin" % seed_value)
		assert_eq(ruin.kind, PropData.Kind.RUIN)
		assert_eq(ruin.spatial_kind(), SpatialIndex.KIND_MYSTERY)
		var d := maxi(absi(ruin.tile.x - w.info.settlement_tile.x), absi(ruin.tile.y - w.info.settlement_tile.y))
		assert_true(d >= WorldSetup.RUIN_MIN_DISTANCE, "seed %d: ruin only %d tiles away" % [seed_value, d])
		assert_eq(w.data.get_water(ruin.tile), 0.0)


func test_every_seed_gives_a_livable_world() -> void:
	var invalid := PackedStringArray()
	for seed_value in range(200, 216): # ~0.3 s each; stay well inside the per-test timeout
		var w := _build(seed_value)
		if not w.info.ok:
			invalid.append("seed %d: %s" % [seed_value, ", ".join(w.info.problems)])
	assert_eq(invalid.size(), 0, "\n".join(invalid))


func test_validate_reports_problems() -> void:
	# A flat, empty, waterless world is not livable.
	var barren := WorldData.create_centered(32, 16)
	var empty := PropRegistry.new(16)
	var problems := WorldSetup.validate(barren, empty, Vector2i.ZERO)
	var text := "\n".join(problems)
	for expected in ["no water reachable", "food bushes", "trees", "rocks"]:
		assert_has(text, expected)
	assert_false(text.contains("buildable"), "a flat grass world has plenty of buildable land")
	# A settlement placed in deep water is rejected outright.
	barren.set_water(Vector2i(3, 3), 1.0)
	assert_has("\n".join(WorldSetup.validate(barren, empty, Vector2i(3, 3))), "not walkable")
	assert_has("\n".join(WorldSetup.validate(barren, empty, Vector2i(500, 500))), "not walkable")


func test_walkability_rules() -> void:
	var w := WorldData.create_centered(32, 16)
	w.set_height(Vector2i(1, 0), 1)
	w.set_height(Vector2i(2, 0), 3)
	w.set_water(Vector2i(0, 1), 0.1)
	w.set_water(Vector2i(0, 2), 0.4)
	assert_true(WorldSetup.can_step(w, Vector2i(0, 0), Vector2i(1, 0)), "one level up")
	assert_false(WorldSetup.can_step(w, Vector2i(1, 0), Vector2i(2, 0)), "two levels up is a cliff")
	assert_true(WorldSetup.can_step(w, Vector2i(0, 0), Vector2i(0, 1)), "shallow water can be waded")
	assert_false(WorldSetup.can_step(w, Vector2i(0, 1), Vector2i(0, 2)), "deep water cannot")
	assert_false(WorldSetup.can_step(w, Vector2i(-16, 0), Vector2i(-17, 0)), "outside the box")


func test_no_site_is_reported_not_crashed() -> void:
	# A world too small for the wall margin has no valid site.
	var tiny := World.new()
	tiny.data = WorldData.new(Rect2i(-4, -4, 8, 8), 16)
	tiny.generator = WorldGenerator.new(5, template, config)
	tiny.data.set_generator(tiny.generator)
	tiny.props = PropRegistry.new(16)
	tiny.ids = IdAllocator.new()
	var info := WorldSetup.create_start(tiny.data, tiny.generator, tiny.props, tiny.ids)
	assert_false(info.ok)
	assert_has("\n".join(info.problems), "no suitable settlement site")


func test_start_survives_a_save_roundtrip() -> void:
	var w := _build(12345)
	var saved: Dictionary = bytes_to_var(var_to_bytes(w.props.to_dict()))
	assert_eq((saved["added"] as Array).size(), 5, "campfire + 3 huts + ruin")
	assert_true((saved["removed"] as PackedInt64Array).size() < 40, "only the cleared glade/ruin tile")

	var again := _build(12345, false)
	assert_eq(again.props.from_dict(saved), 0)
	WorldSetup.populate_all(again.data, again.generator, again.props)
	assert_eq(_props_checksum(again.props, false), _props_checksum(w.props, false))
	assert_eq(again.props.prop_at(w.info.settlement_tile).kind, PropData.Kind.CAMPFIRE)


func test_spatial_index_finds_the_settlement() -> void:
	var w := _build(3)
	var site := Vector2(w.info.settlement_tile) + Vector2(0.5, 0.5)
	var buildings := w.props.spatial_index.query_radius(site, 4.0, SpatialIndex.KIND_BUILDING)
	assert_eq(buildings.size(), 4, "campfire + 3 huts")
	assert_eq(buildings[0], w.info.campfire_id, "nearest first")


func test_golden_props_checksum_for_current_generator_version() -> void:
	var w := _build(12345, false)
	WorldSetup.populate_all(w.data, w.generator, w.props)
	assert_eq(_props_checksum(w.props, true), GOLDEN_PROPS.get(WorldGenerator.GENERATOR_VERSION, "<missing>"), "generated props changed")


# --- loose objects ------------------------------------------------------------------------

func _build_with_loose(seed_value: int) -> Array:
	var w := _build(seed_value, false)
	var loose := LooseObjectRegistry.new(config.chunk_size, w.props.spatial_index)
	w.info = WorldSetup.create_start(w.data, w.generator, w.props, w.ids, loose)
	return [w, loose]


func test_generated_rocks_become_loose_objects() -> void:
	var plain := _build(12345) # rocks as props
	var built := _build_with_loose(12345)
	var w: World = built[0]
	var loose: LooseObjectRegistry = built[1]
	var rock_props := 0
	for p in plain.props.all_props():
		if p.kind == PropData.Kind.ROCK:
			rock_props += 1
			var object := loose.get_object(p.id)
			assert_not_null(object, "rock at %s is a loose object" % p.tile)
			if object != null:
				assert_eq(object.position, p.position2d())
				assert_true(object.is_stone())
	assert_true(rock_props > 20, "the world has rocks (%d)" % rock_props)
	assert_eq(loose.size(), rock_props, "every rock, and nothing else")
	for p in w.props.all_props():
		assert_ne(p.kind, PropData.Kind.ROCK, "no rock is left standing as a prop")
	assert_eq(w.props.size() + loose.size(), plain.props.size(), "nothing lost, nothing doubled")
	# Trees, bushes and the settlement are exactly as before.
	assert_eq(w.info.settlement_tile, plain.info.settlement_tile)
	assert_eq(w.info.ruin_tile, plain.info.ruin_tile)
	assert_eq(w.info.ok, plain.info.ok)
	assert_eq(w.info.problems, plain.info.problems)


func test_world_has_rocks_and_boulders() -> void:
	var loose: LooseObjectRegistry = _build_with_loose(12345)[1]
	var kinds := {}
	for object in loose.all_objects():
		kinds[object.kind] = int(kinds.get(object.kind, 0)) + 1
		assert_true(object.is_generated())
		assert_eq(object.state, LooseObject.State.RESTING)
	assert_true(kinds.get(LooseObject.Kind.ROCK, 0) > kinds.get(LooseObject.Kind.BOULDER, 0), "mostly rocks: %s" % kinds)
	assert_true(kinds.get(LooseObject.Kind.BOULDER, 0) >= 3, "and some boulders: %s" % kinds)
	assert_eq(kinds.size(), 2, "only stone comes with the world for now")
	assert_eq(loose.saved_count(), 0, "all of it regenerates: nothing to save")


func test_the_glade_is_clear_of_loose_objects() -> void:
	for seed_value in [3, 42, 12345]:
		var built := _build_with_loose(seed_value)
		var w: World = built[0]
		var loose: LooseObjectRegistry = built[1]
		for object in loose.all_objects():
			var d := object.tile() - w.info.settlement_tile
			assert_false(absi(d.x) <= WorldSetup.SITE_RADIUS and absi(d.y) <= WorldSetup.SITE_RADIUS,
				"seed %d: %s lies in the glade" % [seed_value, object.tile()])
		assert_eq(loose.objects_at(w.info.ruin_tile).size(), 0, "nothing under the ruin")


func test_loose_objects_are_deterministic() -> void:
	var a: LooseObjectRegistry = _build_with_loose(777)[1]
	var b: LooseObjectRegistry = _build_with_loose(777)[1]
	assert_eq(a.size(), b.size())
	for object in a.all_objects():
		var twin := b.get_object(object.id)
		assert_not_null(twin)
		if twin != null:
			assert_eq(var_to_bytes(twin.to_dict()), var_to_bytes(object.to_dict()))
