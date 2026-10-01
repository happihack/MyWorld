extends TestCase
## InteractionManager: what a touch of the world means.

var world: WorldData
var props: PropRegistry
var ids: IdAllocator
var manager: InteractionManager
var heard: Array[InteractionResponse] = []


func before_each() -> void:
	# Flat 32x32 world at height level 2 (step 0.5 -> ground at y = 1.0).
	world = WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.5
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	props = PropRegistry.new(16, SpatialIndex.new(16))
	ids = IdAllocator.new()
	manager = InteractionManager.new()
	add_child(manager)
	manager.bind(world, props)
	heard.clear()
	manager.responded.connect(func(r: InteractionResponse) -> void: heard.append(r))


func after_each() -> void:
	manager.queue_free()


func _add(kind: PropData.Kind, tile: Vector2i, scale_percent: int = 100) -> PropData:
	var p := PropData.new()
	p.id = ids.next_id()
	p.kind = kind
	p.tile = tile
	p.scale_percent = scale_percent
	assert_true(props.add(p))
	return p


func _tile_target(tile: Vector2i, at: Vector3 = Vector3.INF) -> Picker.Result:
	var r := Picker.Result.new()
	r.kind = Picker.Kind.TILE
	r.tile = tile
	r.position = at if at != Vector3.INF else Vector3(tile.x + 0.5, 1.0, tile.y + 0.5)
	return r


func _entity_target(prop: PropData) -> Picker.Result:
	var r := _tile_target(prop.tile + Vector2i(0, -2)) # the ray lands behind the prop
	r.kind = Picker.Kind.ENTITY
	r.tile = prop.tile
	r.entity_id = prop.id
	r.direct = true
	return r


func test_tap_on_ground_raises_dust_where_it_was_touched() -> void:
	world.set_terrain(Vector2i(3, 4), ChunkData.Terrain.SAND)
	var response := manager.tap(_tile_target(Vector2i(3, 4), Vector3(3.2, 1.0, 4.7)))
	assert_eq(response.effect, InteractionResponse.DUST)
	assert_eq(response.action, InteractionResponse.Action.TAP)
	assert_eq(response.position, Vector3(3.2, 1.0, 4.7))
	assert_eq(response.tile, Vector2i(3, 4))
	assert_eq(response.terrain, ChunkData.Terrain.SAND)
	assert_false(response.is_entity())
	assert_has(response.description, "SAND")
	assert_eq(heard.size(), 1)
	assert_true(heard[0] == response, "listeners get the same response")


func test_tap_on_water_ripples_on_the_surface() -> void:
	var tile := Vector2i(-5, 2)
	world.set_water(tile, 0.3)
	var target := _tile_target(tile, Vector3(-4.6, 1.1, 2.0)) # caught the side of the water
	target.kind = Picker.Kind.WATER
	var response := manager.tap(target)
	assert_eq(response.effect, InteractionResponse.RIPPLE)
	assert_near(response.position.y, 1.3, 0.0001, "on the surface")
	assert_near(response.position.x, -4.6, 0.0001)
	assert_has(response.description, "WATER")


func test_each_kind_of_prop_answers_in_its_own_way() -> void:
	var expected := {
		PropData.Kind.TREE: InteractionResponse.TREE_SHAKE,
		PropData.Kind.BUSH: InteractionResponse.BUSH_RUSTLE,
		PropData.Kind.ROCK: InteractionResponse.ROCK_WOBBLE,
		PropData.Kind.HUT: InteractionResponse.BUILDING_KNOCK,
		PropData.Kind.CAMPFIRE: InteractionResponse.FIRE_FLARE,
		PropData.Kind.RUIN: InteractionResponse.RUIN_HUM,
	}
	assert_eq(expected.size(), PropData.Kind.size(), "every prop kind has a response")
	var x := -10
	for kind: PropData.Kind in expected:
		var prop := _add(kind, Vector2i(x, 0))
		var response := manager.tap(_entity_target(prop))
		assert_eq(response.effect, expected[kind], PropData.Kind.keys()[kind])
		assert_eq(response.prop_kind, kind)
		assert_eq(response.entity_id, prop.id)
		x += 3
	assert_eq(heard.size(), expected.size())
	assert_eq(manager.interaction_count, expected.size())


func test_entity_response_is_placed_at_the_base_of_the_prop() -> void:
	var tree := _add(PropData.Kind.TREE, Vector2i(6, -3), 150)
	tree.offset_x = 64 # a quarter tile off centre
	world.set_height(tree.tile, 5)
	var response := manager.tap(_entity_target(tree))
	assert_true(response.is_entity())
	assert_eq(response.position, Vector3(6.75, 2.5, -2.5), "the prop's base, not where the ray landed")
	assert_eq(response.tile, tree.tile)
	assert_eq(response.body, tree.pick_shape(), "height and radius follow the prop's scale")
	assert_true(response.body.x > 2.0)
	assert_has(response.description, "TREE")


func test_a_vanished_entity_falls_back_to_the_ground() -> void:
	var rock := _add(PropData.Kind.ROCK, Vector2i(1, 1))
	var target := _entity_target(rock)
	props.remove(rock.id)
	var response := manager.tap(target)
	assert_eq(response.effect, InteractionResponse.DUST)
	assert_false(response.is_entity())


func test_a_miss_is_not_an_interaction() -> void:
	assert_null(manager.tap(Picker.Result.new()))
	assert_null(manager.tap(null))
	assert_null(manager.long_press(Picker.Result.new()))
	assert_eq(heard.size(), 0)
	assert_eq(manager.interaction_count, 0)


func test_long_press_asks_to_inspect() -> void:
	var hut := _add(PropData.Kind.HUT, Vector2i(2, 2))
	var response := manager.long_press(_entity_target(hut))
	assert_eq(response.effect, InteractionResponse.INSPECT)
	assert_eq(response.action, InteractionResponse.Action.LONG_PRESS)
	assert_eq(response.entity_id, hut.id)
	assert_eq(heard.size(), 1, "announced once")
	var ground := manager.long_press(_tile_target(Vector2i(0, 0)))
	assert_eq(ground.effect, InteractionResponse.INSPECT)
	assert_false(ground.is_entity())


func test_describe_tells_without_touching() -> void:
	var ruin := _add(PropData.Kind.RUIN, Vector2i(-2, -2))
	var what := manager.describe(_entity_target(ruin))
	assert_eq(what.entity_id, ruin.id)
	assert_eq(what.prop_kind, PropData.Kind.RUIN)
	assert_eq(heard.size(), 0, "nothing happened to the world")
	assert_eq(manager.interaction_count, 0)


func test_actions_offered_for_a_target() -> void:
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	var expected: Array[StringName] = [
		InteractionManager.ACTION_INSPECT, InteractionManager.ACTION_TOUCH, InteractionManager.ACTION_FOCUS]
	assert_eq(manager.actions_for(_entity_target(tree)), expected)
	assert_eq(manager.actions_for(_tile_target(Vector2i(0, 0))), expected)
	assert_eq(manager.actions_for(Picker.Result.new()).size(), 0, "nothing to do with nothing")
	assert_eq(manager.actions_for(null).size(), 0)
	assert_eq(heard.size(), 0)


func test_long_press_remembers_what_touching_would_do() -> void:
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	tree.variant = 2
	var response := manager.long_press(_entity_target(tree))
	assert_eq(response.effect, InteractionResponse.INSPECT)
	assert_eq(response.touch_effect, InteractionResponse.TREE_SHAKE)
	assert_eq(response.prop_variant, 2)
	assert_eq(manager.tap(_tile_target(Vector2i(0, 0))).touch_effect, InteractionResponse.DUST)


func test_inspect_reports_the_facts_of_a_prop() -> void:
	var rock := _add(PropData.Kind.ROCK, Vector2i(-3, 5), 130)
	rock.variant = 1
	world.set_height(rock.tile, 6)
	world.set_terrain(rock.tile, ChunkData.Terrain.DIRT)
	var chunk := world.chunk_at_tile(rock.tile)
	chunk.set_moisture(world.index_at_tile(rock.tile), 200)
	var report := manager.inspect(_entity_target(rock))
	assert_eq(report.subject, InspectReport.Subject.PROP)
	assert_true(report.is_prop())
	assert_eq(report.entity_id, rock.id)
	assert_eq(report.prop_kind, PropData.Kind.ROCK)
	assert_eq(report.prop_variant, 1)
	assert_eq(report.scale_percent, 130)
	assert_false(report.generated)
	assert_eq(report.tile, rock.tile, "the prop's tile, not where the ray landed")
	assert_eq(report.terrain, ChunkData.Terrain.DIRT)
	assert_eq(report.height_level, 6)
	assert_eq(report.moisture, 200)
	assert_eq(heard.size(), 0, "looking is not touching")
	assert_eq(manager.interaction_count, 0)


func test_inspect_reports_ground_and_water() -> void:
	var tile := Vector2i(7, -7)
	var chunk := world.chunk_at_tile(tile)
	var i := world.index_at_tile(tile)
	chunk.set_fertility(i, 90)
	chunk.set_vegetation(i, 180)
	var ground := manager.inspect(_tile_target(tile))
	assert_eq(ground.subject, InspectReport.Subject.GROUND)
	assert_eq(ground.fertility, 90)
	assert_eq(ground.vegetation, 180)
	assert_eq(ground.height_level, 2)
	assert_near(ground.water_depth, 0.0, 0.0)
	world.set_water(tile, 0.45)
	world.set_terrain(tile, ChunkData.Terrain.RIVERBED)
	var target := _tile_target(tile)
	target.kind = Picker.Kind.WATER
	var water := manager.inspect(target)
	assert_eq(water.subject, InspectReport.Subject.WATER)
	assert_near(water.water_depth, 0.45, 0.0001)
	assert_eq(water.terrain, ChunkData.Terrain.RIVERBED)
	assert_null(manager.inspect(Picker.Result.new()))
	assert_null(manager.inspect(null))


func test_unbound_manager_ignores_touches() -> void:
	var fresh := InteractionManager.new()
	add_child(fresh)
	assert_null(fresh.tap(_tile_target(Vector2i(0, 0))))
	fresh.queue_free()


func test_binding_another_world_starts_the_count_again() -> void:
	manager.tap(_tile_target(Vector2i(0, 0)))
	manager.tap(_tile_target(Vector2i(1, 0)))
	assert_eq(manager.interaction_count, 2)
	manager.bind(world, props)
	assert_eq(manager.interaction_count, 0)
