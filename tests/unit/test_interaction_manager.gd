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
		PropData.Kind.CROP: InteractionResponse.BUSH_RUSTLE,
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
	var for_a_tree: Array[StringName] = [InteractionManager.ACTION_INSPECT, InteractionManager.ACTION_TOUCH,
		InteractionManager.ACTION_REMOVE, InteractionManager.ACTION_FOCUS]
	assert_eq(manager.actions_for(_entity_target(tree)), for_a_tree, "a tree can also be uprooted")
	assert_eq(manager.actions_for(_entity_target(_add(PropData.Kind.HUT, Vector2i(8, 8)))), expected)
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


# --- loose objects ------------------------------------------------------------------------

func _loose_setup() -> LooseObjectRegistry:
	var loose := LooseObjectRegistry.new(16, props.spatial_index)
	manager.bind(world, props, loose)
	return loose


func _loose_object(loose: LooseObjectRegistry, kind: LooseObject.Kind, at: Vector2) -> LooseObject:
	var o := LooseObject.new()
	o.id = ids.next_id()
	o.kind = kind
	o.position = at
	assert_true(loose.add(o))
	return o


func _loose_target(o: LooseObject) -> Picker.Result:
	var r := _tile_target(o.tile() + Vector2i(0, -1))
	r.kind = Picker.Kind.ENTITY
	r.tile = o.tile()
	r.entity_id = o.id
	r.direct = true
	return r


func test_tapping_a_loose_object() -> void:
	var loose := _loose_setup()
	var boulder := _loose_object(loose, LooseObject.Kind.BOULDER, Vector2(3.25, 4.75))
	world.set_height(boulder.tile(), 4)
	world.set_terrain(boulder.tile(), ChunkData.Terrain.DIRT)
	var response := manager.tap(_loose_target(boulder))
	assert_eq(response.effect, InteractionResponse.ROCK_WOBBLE)
	assert_eq(response.loose_kind, LooseObject.Kind.BOULDER)
	assert_eq(response.prop_kind, -1)
	assert_true(response.is_entity())
	assert_eq(response.entity_id, boulder.id)
	assert_eq(response.position, Vector3(3.25, 2.0, 4.75), "where the boulder lies")
	assert_eq(response.tile, Vector2i(3, 4))
	assert_eq(response.body, boulder.pick_shape())
	assert_eq(response.terrain, ChunkData.Terrain.DIRT)
	assert_has(response.description, "BOULDER")
	assert_eq(UIText.subject_name(response), "Boulder")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH, response.touch_effect), "Touch")
	assert_eq(manager.actions_for(_loose_target(boulder)).size(), 3)


func test_inspecting_a_loose_object() -> void:
	var loose := _loose_setup()
	var rock := _loose_object(loose, LooseObject.Kind.ROCK, Vector2(-2.5, 6.5))
	rock.scale_percent = 110
	rock.moved_count = 3
	world.set_height(rock.tile(), 5)
	var report := manager.inspect(_loose_target(rock))
	assert_true(report.is_loose())
	assert_eq(report.subject, InspectReport.Subject.LOOSE)
	assert_eq(report.loose_kind, LooseObject.Kind.ROCK)
	assert_eq(report.entity_id, rock.id)
	assert_eq(report.tile, rock.tile())
	assert_eq(report.height_level, 5)
	assert_near(report.mass, rock.mass(), 0.0001)
	assert_eq(report.moved_count, 3)
	assert_false(report.generated)
	assert_eq(heard.size(), 0)


func test_a_removed_loose_object_falls_back_to_the_ground() -> void:
	var loose := _loose_setup()
	var pebble := _loose_object(loose, LooseObject.Kind.PEBBLE, Vector2(1.5, 1.5))
	var target := _loose_target(pebble)
	loose.remove(pebble.id)
	var response := manager.tap(target)
	assert_eq(response.effect, InteractionResponse.DUST)
	assert_eq(response.loose_kind, -1)
	assert_eq(manager.inspect(target).subject, InspectReport.Subject.GROUND)


# --- trees: shaking and uprooting -----------------------------------------------------------

var _motion: LooseObjectSystem


## Binds the manager with everything it needs to bring new objects into the world.
func _spawning_setup(seed_value: int = 42) -> LooseObjectRegistry:
	var loose := LooseObjectRegistry.new(16, props.spatial_index)
	if _motion == null or not is_instance_valid(_motion):
		_motion = LooseObjectSystem.new()
		add_child(_motion)
		_motion.set_process(false)
	_motion.bind(world, loose, props)
	manager.bind(world, props, loose, _motion, ids, RngStreams.new(seed_value))
	return loose


## Shakes `tree` until nothing more can fall (at most `limit` times); returns
## every response.
func _shake_bare(tree: PropData, limit: int = 80) -> Array[InteractionResponse]:
	var out: Array[InteractionResponse] = []
	for i in limit:
		out.append(manager.tap(_entity_target(tree)))
		if tree.bears_left() == 0:
			break
	return out


func test_repeated_shakes_bring_the_fruit_down() -> void:
	var loose := _spawning_setup()
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	var bears := tree.bears()
	assert_true(bears >= 2 and bears <= 4, "a broadleaf bears a few fruit (%d)" % bears)
	var first := manager.tap(_entity_target(tree))
	assert_eq(first.effect, InteractionResponse.TREE_SHAKE)
	assert_eq(first.dropped.size(), 0, "the first shake only rustles it")
	assert_eq(loose.size(), 0)
	var responses := _shake_bare(tree)
	assert_eq(tree.bears_left(), 0, "shaken bare after %d more shakes" % responses.size())
	assert_eq(loose.size(), bears, "every fruit came down, and no more")
	assert_true(responses.size() > bears - 1, "not one per shake: it takes some shaking")
	var dropped := 0
	for r in responses:
		assert_true(r.dropped.size() <= 1, "one at a time")
		dropped += r.dropped.size()
	assert_eq(dropped, bears)
	# Bare now: more shaking only shakes.
	for i in 10:
		assert_eq(manager.tap(_entity_target(tree)).dropped.size(), 0)
	assert_eq(loose.size(), bears)
	assert_eq(manager.shakes_of(tree.id), responses.size() + 11)


func test_fruit_falls_from_the_crown_and_comes_to_rest() -> void:
	var loose := _spawning_setup()
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	_shake_bare(tree)
	var body := tree.pick_shape()
	for fruit in loose.all_objects():
		assert_eq(fruit.kind, LooseObject.Kind.FRUIT)
		assert_true(fruit.id > 0 and not fruit.is_generated())
		assert_true(fruit.height_offset > body.x * 0.3 or fruit.state != LooseObject.State.FALLING, "it starts up in the crown")
		assert_true(_motion.is_moving(fruit.id), "and is falling")
	for i in 600:
		_motion.step(LooseObjectSystem.STEP_SECONDS)
	for fruit in loose.all_objects():
		assert_eq(fruit.state, LooseObject.State.RESTING)
		assert_near(fruit.height_offset, 0.0, 0.0001)
		var away := fruit.position.distance_to(tree.position2d())
		assert_true(away > tree.collision_radius() and away < 2.5, "on the ground around the tree (%.2f)" % away)


func test_conifers_drop_cones() -> void:
	var loose := _spawning_setup()
	var pine := _add(PropData.Kind.TREE, Vector2i(-6, 3))
	pine.variant = PropData.TREE_CONIFER_FIRST_VARIANT
	assert_true(pine.is_conifer())
	assert_true(pine.bears() >= 1 and pine.bears() <= 2)
	_shake_bare(pine)
	assert_eq(loose.size(), pine.bears())
	for cone in loose.all_objects():
		assert_eq(cone.kind, LooseObject.Kind.SEED)


func test_the_same_world_drops_fruit_on_the_same_shakes() -> void:
	var runs: Array = []
	for run in 2:
		_spawning_setup(777)
		var tree := _add(PropData.Kind.TREE, Vector2i(2 + run * 6, -5))
		tree.taken = 0
		var pattern := []
		for r in _shake_bare(tree):
			pattern.append(r.dropped.size())
		runs.append(pattern)
	# Different trees bear different amounts; compare what both runs share.
	var n := mini(runs[0].size(), runs[1].size())
	assert_true(n >= 1)
	assert_eq(runs[0].slice(0, n - 1), runs[1].slice(0, n - 1), "same seed, same luck")


func test_shaking_without_a_way_to_spawn_only_shakes() -> void:
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	assert_false(manager.can_spawn())
	for i in 20:
		assert_eq(manager.tap(_entity_target(tree)).dropped.size(), 0)
	assert_eq(tree.taken, 0)
	assert_eq(heard.size(), 20)


func test_uprooting_a_tree_leaves_a_log() -> void:
	var loose := _spawning_setup()
	var tree := _add(PropData.Kind.TREE, Vector2i(5, -2), 120)
	world.set_height(tree.tile, 4)
	var at := tree.position2d()
	var response := manager.uproot(_entity_target(tree))
	assert_eq(response.effect, InteractionResponse.TREE_UPROOT)
	assert_eq(response.position, Vector3(at.x, 2.0, at.y), "where the tree stood")
	assert_true(response.body.x > 1.0, "the size of the tree that fell")
	assert_null(props.get_prop(tree.id), "the tree is gone")
	assert_false(props.has_prop_at(Vector2i(5, -2)))
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].effect, InteractionResponse.TREE_UPROOT)
	assert_eq(loose.size(), 1)
	var log := loose.get_object(response.dropped[0])
	assert_eq(log.kind, LooseObject.Kind.LOG)
	assert_eq(log.scale_percent, 120, "a big tree leaves a big log")
	assert_true(log.position.distance_to(at) < 0.01)
	assert_true(_motion.is_moving(log.id), "it topples")
	for i in 600:
		_motion.step(LooseObjectSystem.STEP_SECONDS)
	assert_eq(log.state, LooseObject.State.RESTING)
	assert_near(log.height_offset, 0.0, 0.0001)
	# Tapping the log knocks on wood.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = log.id
	target.tile = log.tile()
	assert_eq(manager.tap(target).effect, InteractionResponse.LOG_KNOCK)


func test_only_trees_can_be_uprooted() -> void:
	_spawning_setup()
	var hut := _add(PropData.Kind.HUT, Vector2i(2, 2))
	assert_null(manager.uproot(_entity_target(hut)))
	assert_null(manager.uproot(_tile_target(Vector2i(0, 0))))
	assert_null(manager.uproot(Picker.Result.new()))
	assert_not_null(props.get_prop(hut.id))
	assert_eq(heard.size(), 0)


func test_uprooting_without_a_way_to_spawn_still_removes_the_tree() -> void:
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	var response := manager.uproot(_entity_target(tree))
	assert_not_null(response)
	assert_eq(response.dropped.size(), 0)
	assert_null(props.get_prop(tree.id))


func test_inspecting_a_tree_tells_what_it_bears() -> void:
	_spawning_setup()
	var tree := _add(PropData.Kind.TREE, Vector2i(4, 4))
	var report := manager.inspect(_entity_target(tree))
	assert_eq(report.bears, tree.bears())
	assert_eq(report.bears_left, tree.bears())
	_shake_bare(tree)
	assert_eq(manager.inspect(_entity_target(tree)).bears_left, 0)
	var hut := _add(PropData.Kind.HUT, Vector2i(9, 9))
	assert_eq(manager.inspect(_entity_target(hut)).bears, -1, "huts bear nothing")


func test_small_loose_things_are_nudged() -> void:
	var loose := _spawning_setup()
	var fruit := _loose_object(loose, LooseObject.Kind.FRUIT, Vector2(1.5, 1.5))
	var response := manager.tap(_loose_target(fruit))
	assert_eq(response.effect, InteractionResponse.NUDGE)
	assert_true(response.strength > 1.5, "light: it jumps")
