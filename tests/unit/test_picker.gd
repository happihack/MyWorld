extends TestCase

const VIEW := Vector2(1080, 1920)
const TOUCH := 60.0 # touch radius in viewport units for these tests

var world: WorldData
var spatial: SpatialIndex
var props: PropRegistry
var rig: CameraRig
var ids: IdAllocator


func before_each() -> void:
	# Flat 32x32 world at height level 2 (step 0.5 -> ground at y = 1.0).
	world = WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.5
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	spatial = SpatialIndex.new(16)
	props = PropRegistry.new(16, spatial)
	ids = IdAllocator.new()
	rig = CameraRig.new(CameraConfig.new())
	add_child(rig)
	rig.set_process(false)
	rig.set_view_size(VIEW)
	rig.setup(Rect2(world.bounds), Rect2(world.bounds).grow(1.5), -1.8, 9.0)
	rig.zoom_at(rig.distance() / 30.0, VIEW * 0.5) # a working zoom level


func after_each() -> void:
	rig.queue_free()


func _add(kind: PropData.Kind, tile: Vector2i) -> PropData:
	var p := PropData.new()
	p.id = ids.next_id()
	p.kind = kind
	p.tile = tile
	assert_true(props.add(p))
	return p


func _pick(screen: Vector2, touch: float = TOUCH) -> Picker.Result:
	return Picker.pick(screen, rig, world, spatial, props.pick_shape, touch)


## Screen position of the centre of a tile's top surface.
func _tile_screen(tile: Vector2i) -> Vector2:
	var y := world.get_height(tile) * world.height_step + world.get_water(tile)
	return rig.world_to_screen(Vector3(tile.x + 0.5, y, tile.y + 0.5))


# --- terrain ray march -----------------------------------------------------------

func test_straight_down_hits_the_tile_below() -> void:
	var hit := Picker.raycast_terrain(world, Vector3(3.5, 20, -7.5), Vector3.DOWN)
	assert_not_null(hit)
	assert_eq(hit.tile, Vector2i(3, -8))
	assert_near(hit.position.y, 1.0, 0.0001)
	assert_near(hit.distance, 19.0, 0.0001)
	assert_false(hit.is_side)
	assert_false(hit.is_water)


func test_angled_ray_matches_plane_intersection_on_flat_ground() -> void:
	var origin := Vector3(-3.2, 12.0, 9.7)
	var dir := Vector3(0.35, -1.0, -0.6).normalized()
	var hit := Picker.raycast_terrain(world, origin, dir)
	var t := (1.0 - origin.y) / dir.y
	var expected := origin + dir * t
	assert_near(hit.position.x, expected.x, 0.0001)
	assert_near(hit.position.z, expected.z, 0.0001)
	assert_eq(hit.tile, Vector2i(floori(expected.x), floori(expected.z)))


func test_raised_block_is_hit_on_its_side_and_hides_what_is_behind() -> void:
	world.set_height(Vector2i(4, 0), 8) # a tower 4 units tall at x 4..5
	# A low ray travelling +X along z = 0.5 at y = 2.5 runs into the tower's side.
	var hit := Picker.raycast_terrain(world, Vector3(-10, 2.5, 0.5), Vector3(1, -0.02, 0).normalized())
	assert_eq(hit.tile, Vector2i(4, 0))
	assert_true(hit.is_side)
	assert_near(hit.position.x, 4.0, 0.001, "hit on the face at x = 4")
	# The same ray one tile over (z = 1.5) passes the tower and lands far beyond.
	var miss := Picker.raycast_terrain(world, Vector3(-10, 2.5, 1.5), Vector3(1, -0.02, 0).normalized())
	assert_true(miss == null or miss.tile != Vector2i(4, 0))


func test_top_of_a_raised_block() -> void:
	world.set_height(Vector2i(4, 0), 8)
	var hit := Picker.raycast_terrain(world, Vector3(4.5, 30, 0.5), Vector3.DOWN)
	assert_eq(hit.tile, Vector2i(4, 0))
	assert_near(hit.position.y, 4.0, 0.0001)


func test_ray_from_outside_enters_through_the_rim() -> void:
	# Starting outside the box, heading in and down.
	var hit := Picker.raycast_terrain(world, Vector3(-40, 6, 0.5), Vector3(1, -0.2, 0).normalized())
	assert_not_null(hit)
	assert_true(world.is_in_bounds(hit.tile))
	# A low horizontal ray from outside strikes the rim (the terrain's cut edge).
	var rim := Picker.raycast_terrain(world, Vector3(-40, 0.5, 0.5), Vector3(1, 0, 0))
	assert_eq(rim.tile, Vector2i(-16, 0))
	assert_true(rim.is_side)


func test_rays_that_miss_return_null() -> void:
	assert_null(Picker.raycast_terrain(world, Vector3(100, 5, 100), Vector3.DOWN), "outside the box")
	assert_null(Picker.raycast_terrain(world, Vector3(0, 5, 0), Vector3.UP), "pointing at the sky")
	assert_null(Picker.raycast_terrain(world, Vector3(-40, 20, 0.5), Vector3(-1, -0.2, 0).normalized()), "heading away")
	assert_null(Picker.raycast_terrain(world, Vector3(0, 5, 100), Vector3(1, 0, 0)), "parallel, beside the box")
	assert_null(Picker.raycast_terrain(WorldData.new(), Vector3.ZERO, Vector3.DOWN), "empty world")


func test_water_surface_is_the_hit() -> void:
	world.set_height(Vector2i(2, 2), 0)
	world.set_water(Vector2i(2, 2), 0.7)
	var hit := Picker.raycast_terrain(world, Vector3(2.5, 20, 2.5), Vector3.DOWN)
	assert_true(hit.is_water)
	assert_near(hit.position.y, 0.7, 0.0001, "the surface, not the bed")


# --- picking through the camera ----------------------------------------------------

func test_every_visible_tile_picks_itself() -> void:
	var checked := 0
	for y in range(-14, 14, 3):
		for x in range(-14, 14, 3):
			var tile := Vector2i(x, y)
			var screen := _tile_screen(tile)
			if screen == Vector2.INF or screen.x < 0 or screen.x > VIEW.x or screen.y < 0 or screen.y > VIEW.y:
				continue
			var result := _pick(screen)
			if result.kind != Picker.Kind.TILE or result.tile != tile:
				fail("tile %s picked as %s (kind %d)" % [tile, result.tile, result.kind])
				return
			checked += 1
	assert_true(checked >= 6, "enough tiles were on screen (%d)" % checked)


func test_pick_outside_the_world_is_nothing() -> void:
	rig.frame_box(false)
	var result := _pick(Vector2(5, 5)) # a corner of the screen: the tabletop
	assert_eq(result.kind, Picker.Kind.NONE)
	assert_false(result.is_hit())


func test_water_is_reported() -> void:
	var tile := Vector2i(0, 0)
	world.set_water(tile, 0.3)
	var result := _pick(_tile_screen(tile))
	assert_eq(result.kind, Picker.Kind.WATER)
	assert_eq(result.tile, tile)


func test_tapping_a_props_base_selects_it() -> void:
	var rock := _add(PropData.Kind.ROCK, Vector2i(1, 1))
	var result := _pick(_tile_screen(Vector2i(1, 1)))
	assert_eq(result.kind, Picker.Kind.ENTITY)
	assert_eq(result.entity_id, rock.id)
	assert_eq(result.entity_kind, SpatialIndex.KIND_RESOURCE_NODE)
	assert_true(result.direct)
	assert_eq(result.tile, Vector2i(1, 1))


func test_tapping_a_trees_canopy_selects_the_tree() -> void:
	var tree := _add(PropData.Kind.TREE, Vector2i(2, 2))
	# Screen position of a point near the top of the tree: the ray through it
	# lands on the ground well behind the tree.
	var canopy := rig.world_to_screen(Vector3(2.5, 1.0 + 1.3, 2.5))
	var ground: Picker.TerrainHit = Picker.raycast_terrain(world, rig.screen_ray(canopy)[0], rig.screen_ray(canopy)[1])
	assert_ne(ground.tile, Vector2i(2, 2), "the ray itself lands on another tile")
	var result := _pick(canopy)
	assert_eq(result.kind, Picker.Kind.ENTITY)
	assert_eq(result.entity_id, tree.id)
	assert_eq(result.tile, Vector2i(2, 2), "the result reports the tree's tile")


func test_near_miss_within_the_touch_radius_still_selects() -> void:
	var rock := _add(PropData.Kind.ROCK, Vector2i(1, 1))
	var base := _tile_screen(Vector2i(1, 1))
	var body_px := rock.pick_shape().y / rig.world_units_per_screen_unit(Vector3(1.5, 1.0, 1.5))
	var near := base + Vector2(body_px + TOUCH * 0.6, 0)
	var result := _pick(near)
	assert_eq(result.entity_id, rock.id)
	assert_false(result.direct, "a near miss, not a direct hit")
	var far := base + Vector2(body_px + TOUCH * 1.6, 0)
	assert_eq(_pick(far).kind, Picker.Kind.TILE, "outside the radius it is just ground")
	assert_eq(_pick(near, 0.0).kind, Picker.Kind.TILE, "no forgiveness with a zero touch radius")


func test_direct_hit_beats_a_higher_priority_near_miss() -> void:
	var hut := _add(PropData.Kind.HUT, Vector2i(0, 0))
	var tree := _add(PropData.Kind.TREE, Vector2i(1, 0)) # trees outrank buildings
	# Tap squarely on the hut's wall: the tree is within the touch radius, but
	# the finger is ON the hut.
	var on_hut := rig.world_to_screen(Vector3(0.5, 1.0 + 0.3, 0.5))
	var result := _pick(on_hut, 400.0)
	assert_eq(result.entity_id, hut.id)
	assert_true(result.direct)
	assert_ne(result.entity_id, tree.id)


func test_priority_decides_between_two_near_misses() -> void:
	var hut := _add(PropData.Kind.HUT, Vector2i(-1, 0))
	var bush := _add(PropData.Kind.BUSH, Vector2i(2, 0))
	# A point on the ground between them, outside both bodies, with a huge radius.
	var between := rig.world_to_screen(Vector3(0.9, 1.0, 0.5))
	var result := _pick(between, 2000.0)
	assert_eq(result.entity_id, bush.id, "resource nodes outrank buildings among near misses")
	assert_false(result.direct)
	assert_ne(result.entity_id, hut.id)
	assert_true(Picker.priority_of(SpatialIndex.KIND_PERSON) < Picker.priority_of(SpatialIndex.KIND_ANIMAL))
	assert_true(Picker.priority_of(SpatialIndex.KIND_RESOURCE_NODE) < Picker.priority_of(SpatialIndex.KIND_BUILDING))
	assert_true(Picker.priority_of(0) > Picker.priority_of(SpatialIndex.KIND_BUILDING), "unknown kinds come last")


func test_nearest_wins_among_equals() -> void:
	var a := _add(PropData.Kind.ROCK, Vector2i(0, 0))
	var b := _add(PropData.Kind.ROCK, Vector2i(2, 0))
	var near_b := rig.world_to_screen(Vector3(1.75, 1.0, 0.5))
	assert_eq(_pick(near_b, 2000.0).entity_id, b.id)
	var near_a := rig.world_to_screen(Vector3(1.25, 1.0, 0.5))
	assert_eq(_pick(near_a, 2000.0).entity_id, a.id)


func test_kind_mask_filters_entities() -> void:
	_add(PropData.Kind.ROCK, Vector2i(1, 1))
	var screen := _tile_screen(Vector2i(1, 1))
	var only_buildings := Picker.pick(screen, rig, world, spatial, props.pick_shape, TOUCH, SpatialIndex.KIND_BUILDING)
	assert_eq(only_buildings.kind, Picker.Kind.TILE)


func test_removed_props_cannot_be_picked() -> void:
	var rock := _add(PropData.Kind.ROCK, Vector2i(1, 1))
	props.remove(rock.id)
	assert_eq(_pick(_tile_screen(Vector2i(1, 1))).kind, Picker.Kind.TILE)


func test_prop_hidden_behind_a_hill_is_not_picked() -> void:
	# The camera looks toward -Z from +Z. A wall of tall blocks stands at z = 2,
	# a tree behind it at z = -1.
	for x in range(-6, 7):
		world.set_height(Vector2i(x, 2), 12)
	var tree := _add(PropData.Kind.TREE, Vector2i(0, -1))
	# Aim at the wall face in front of where the tree's base would appear.
	var wall_face := rig.world_to_screen(Vector3(0.5, 3.0, 3.0))
	var result := _pick(wall_face)
	assert_ne(result.entity_id, tree.id, "the wall is in the way")
	assert_eq(result.tile.y, 2, "the wall itself is what was touched")


func test_pick_without_entities_or_provider() -> void:
	var screen := _tile_screen(Vector2i(0, 0))
	assert_eq(Picker.pick(screen, rig, world, null, Callable(), TOUCH).kind, Picker.Kind.TILE)
	_add(PropData.Kind.ROCK, Vector2i(0, 0))
	assert_eq(Picker.pick(screen, rig, world, spatial, Callable(), TOUCH).kind, Picker.Kind.TILE, "no shape provider: terrain only")
