extends TestCase
## The single choke point: everything the player does goes through
## InteractionManager.apply_intervention() and ends up in the PlayerHistory.

var world: WorldData
var props: PropRegistry
var loose: LooseObjectRegistry
var motion: LooseObjectSystem
var water: WaterSim
var clock: GameClock
var ids: IdAllocator
var manager: InteractionManager
var history: PlayerHistory
var applied: Array[Intervention] = []
var bus_ids: Array = []
var _on_bus: Callable

const SETTLEMENT := Vector2(0.5, 0.5)


func before_each() -> void:
	Settings.reset_to_defaults()
	# Flat 32x32 world at height level 2 (step 0.5 -> ground at y = 1.0).
	world = WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.5
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	for coord in world.chunk_coords():
		world.get_chunk(coord)
	var index := SpatialIndex.new(SpatialIndex.FINE_CELL_TILES)
	props = PropRegistry.new(16, index)
	loose = LooseObjectRegistry.new(16, index)
	ids = IdAllocator.new()
	clock = GameClock.new(Config.time)
	motion = LooseObjectSystem.new()
	add_child(motion)
	motion.set_process(false)
	motion.bind(world, loose, props)
	water = WaterSim.new()
	add_child(water)
	water.set_process(false)
	water.soak_per_second = 0.0
	water.bind(world)
	history = PlayerHistory.new()
	manager = InteractionManager.new()
	add_child(manager)
	manager.bind(world, props, loose, motion, ids, RngStreams.new(7))
	manager.bind_session(water, clock, history, SETTLEMENT)
	applied.clear()
	bus_ids.clear()
	manager.intervention_applied.connect(func(iv: Intervention) -> void: applied.append(iv))
	_on_bus = func(id: int) -> void: bus_ids.append(id)
	EventBus.intervention_applied.connect(_on_bus)


func after_each() -> void:
	EventBus.intervention_applied.disconnect(_on_bus)
	manager.queue_free()
	motion.queue_free()
	water.queue_free()
	Settings.reset_to_defaults()


func _prop(kind: PropData.Kind, tile: Vector2i) -> PropData:
	var p := PropData.new()
	p.id = ids.next_id()
	p.kind = kind
	p.tile = tile
	assert_true(props.add(p))
	return p


func _object(kind: LooseObject.Kind, at: Vector2) -> LooseObject:
	var o := LooseObject.new()
	o.id = ids.next_id()
	o.kind = kind
	o.position = at
	assert_true(loose.add(o))
	return o


func _ground(tile: Vector2i) -> Picker.Result:
	var r := Picker.Result.new()
	r.kind = Picker.Kind.TILE
	r.tile = tile
	r.position = Vector3(tile.x + 0.5, 1.0, tile.y + 0.5)
	return r


func _entity(id: int, tile: Vector2i) -> Picker.Result:
	var r := _ground(tile)
	r.kind = Picker.Kind.ENTITY
	r.entity_id = id
	return r


func _settle() -> void:
	for i in 1200:
		if motion.moving_count() == 0:
			break
		motion.step(LooseObjectSystem.STEP_SECONDS)


## Picks an object up, carries it by `offset` and lets it go.
func _move(object: LooseObject, offset: Vector2, velocity: Vector3 = Vector3.ZERO) -> Intervention:
	assert_true(manager.grab(object.id))
	assert_true(manager.carry(object.id, object.position + offset, 0.5))
	var iv := manager.release(object.id, velocity)
	_settle()
	return iv


# --- every action goes through the pipeline -----------------------------------------------------

func test_every_player_action_leaves_its_mark_in_the_history() -> void:
	var tree := _prop(PropData.Kind.TREE, Vector2i(4, 4))
	var rock := _object(LooseObject.Kind.ROCK, Vector2(-3.5, 2.5))
	world.set_water(Vector2i(8, 8), 0.6)
	water.wake(Vector2i(8, 8))
	var pool := _ground(Vector2i(8, 8))
	pool.kind = Picker.Kind.WATER
	var expected := 0

	manager.tap(_ground(Vector2i(0, 5)))
	expected += 1
	assert_eq(history.count(Intervention.TOUCH, &"ground"), 1)
	manager.tap(pool)
	expected += 1
	assert_eq(history.count(Intervention.TOUCH, &"water"), 1)
	manager.tap(_entity(tree.id, tree.tile))
	expected += 1
	assert_eq(history.count(Intervention.TOUCH, &"tree"), 1)
	manager.tap(_entity(rock.id, rock.tile()))
	expected += 1
	assert_eq(history.count(Intervention.TOUCH, &"rock"), 1)
	_move(rock, Vector2(2.0, 0.0))
	expected += 1
	assert_eq(history.count(Intervention.MOVE_OBJECT, &"rock"), 1)
	assert_true(manager.scoop(Vector2i(8, 8), 0.2) > 0.0)
	expected += 1
	assert_eq(history.count(Intervention.SCOOP_WATER, &"water"), 1)
	assert_true(manager.pour(Vector2i(-8, -8), 0.2) > 0.0)
	expected += 1
	assert_eq(history.count(Intervention.POUR_WATER, &"water"), 1)
	manager.uproot(_entity(tree.id, tree.tile))
	expected += 1
	assert_eq(history.count(Intervention.UPROOT, &"tree"), 1)

	assert_eq(history.total(), expected, "nothing the player did went unrecorded")
	assert_eq(bus_ids, range(1, expected + 1), "each announced on the bus with its number")
	assert_eq(applied.size(), expected + 1, "the grab went through the pipeline too")
	assert_eq(applied.filter(func(iv: Intervention) -> bool: return not iv.recorded).size(), 1, "but is not history on its own")
	# Looking is not doing.
	manager.long_press(_ground(Vector2i(0, 5)))
	manager.describe(_ground(Vector2i(0, 5)))
	manager.inspect(_ground(Vector2i(0, 5)))
	assert_eq(history.total(), expected)


func test_a_touch_as_an_intervention() -> void:
	clock.tick = 4321
	var tree := _prop(PropData.Kind.TREE, Vector2i(4, 4))
	var iv := manager.apply_intervention(Intervention.create(Intervention.TOUCH, &"hand", _entity(tree.id, tree.tile)))
	assert_true(iv.applied)
	assert_eq(iv.rejected, &"")
	assert_eq(iv.id, 1)
	assert_eq(iv.tick, 4321)
	assert_eq(iv.tool, &"hand")
	assert_eq(iv.subject, &"tree")
	assert_eq(iv.severity, Intervention.Severity.GENTLE)
	assert_eq(iv.target_id, tree.id)
	assert_eq(iv.tile, tree.tile)
	assert_eq(iv.response.effect, InteractionResponse.TREE_SHAKE)
	assert_eq(iv.key(), "touch:tree")
	assert_true(applied[0] == iv)
	assert_eq(manager.apply_intervention(Intervention.create(Intervention.TOUCH, &"hand", _ground(Vector2i(1, 1)))).id, 2)
	assert_eq(history.peek_next_id(), 3)


func test_what_cannot_be_done_is_refused_and_not_recorded() -> void:
	var hut := _prop(PropData.Kind.HUT, Vector2i(2, 2))
	var rock := _object(LooseObject.Kind.ROCK, Vector2(5.5, 5.5))
	var cases := {
		&"nothing_there": Intervention.create(Intervention.TOUCH, &"hand", Picker.Result.new()),
		&"unknown_type": Intervention.create(&"summon_dragon"),
		&"not_a_tree": Intervention.create(Intervention.UPROOT, &"hand", _entity(hut.id, hut.tile)),
		&"cannot_grab": Intervention.create(Intervention.GRAB),
		&"not_in_hand": Intervention.create(Intervention.MOVE_OBJECT),
		&"no_water": Intervention.create(Intervention.POUR_WATER),
	}
	(cases[&"not_in_hand"] as Intervention).target_id = rock.id
	(cases[&"no_water"] as Intervention).magnitude = -1.0
	for reason: StringName in cases:
		var iv := manager.apply_intervention(cases[reason])
		assert_false(iv.applied, String(reason))
		assert_eq(iv.rejected, reason)
		assert_eq(iv.id, 0)
	var dry := Intervention.create(Intervention.SCOOP_WATER)
	dry.tile = Vector2i(3, 3)
	dry.magnitude = 0.3
	assert_eq(manager.apply_intervention(dry).rejected, &"nothing_moved", "no water to scoop there")
	assert_null(manager.apply_intervention(null))
	assert_eq(history.total(), 0)
	assert_eq(applied.size(), 0)
	assert_eq(bus_ids.size(), 0)
	assert_not_null(props.get_prop(hut.id), "and nothing was changed")
	# Without a world nothing can be done at all.
	var unbound := InteractionManager.new()
	add_child(unbound)
	assert_eq(unbound.apply_intervention(Intervention.create(Intervention.TOUCH, &"hand", _ground(Vector2i(0, 0)))).rejected, &"no_world")
	unbound.queue_free()


func test_gentle_hands_only_stops_major_interventions() -> void:
	for severity: Intervention.Severity in [Intervention.Severity.GENTLE, Intervention.Severity.MODERATE]:
		assert_true(InteractionManager.severity_allowed(severity, true))
		assert_true(InteractionManager.severity_allowed(severity, false))
	assert_false(InteractionManager.severity_allowed(Intervention.Severity.MAJOR, true), "kept from happening by accident")
	assert_true(InteractionManager.severity_allowed(Intervention.Severity.MAJOR, false))
	# Uprooting is Moderate: allowed with the default (gentle) setting.
	assert_eq(Settings.get_value(&"gameplay/gentle_hands"), true)
	var tree := _prop(PropData.Kind.TREE, Vector2i(4, 4))
	var iv := manager.apply_intervention(Intervention.create(Intervention.UPROOT, &"hand", _entity(tree.id, tree.tile)))
	assert_true(iv.applied)
	assert_eq(iv.severity, Intervention.Severity.MODERATE)


# --- moving things ----------------------------------------------------------------------------

func test_moving_an_object_is_recorded_when_it_is_put_down() -> void:
	clock.tick = 77
	var rock := _object(LooseObject.Kind.ROCK, Vector2(5.5, 5.5))
	assert_true(manager.grab(rock.id, &"hand"))
	assert_true(manager.is_in_hand(rock.id))
	assert_eq(rock.state, LooseObject.State.HELD)
	assert_false(manager.grab(rock.id), "it is already in hand")
	assert_eq(history.total(), 0, "picking up is not yet history")
	assert_true(manager.carry(rock.id, Vector2(8.5, 9.5), 0.5))
	var iv := manager.release(rock.id)
	assert_not_null(iv)
	assert_true(iv.applied)
	assert_eq(iv.type, Intervention.MOVE_OBJECT)
	assert_eq(iv.subject, &"rock")
	assert_eq(iv.tick, 77)
	assert_near(iv.magnitude, 5.0, 0.0001, "how far it was carried")
	assert_eq(iv.params["from"], Vector2(5.5, 5.5))
	assert_eq(iv.params["to"], Vector2(8.5, 9.5))
	assert_eq(iv.params["thrown"], false)
	assert_eq(iv.severity, Intervention.Severity.MODERATE, "moving rocks is Moderate")
	assert_eq(iv.target_id, rock.id)
	assert_false(manager.is_in_hand(rock.id))
	assert_eq(rock.state, LooseObject.State.FALLING, "let go")
	assert_eq(rock.moved_count, 1)
	assert_true(rock.placed_by_player)
	assert_near(history.total_of(&"distance_moved"), 5.0, 0.0001)
	# A pebble is a small thing: Gentle. Thrown, it is counted as thrown.
	var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(-5.5, -5.5))
	var thrown := _move(pebble, Vector2(1.0, 0.0), Vector3(4.0, 0.0, 0.0))
	assert_eq(thrown.severity, Intervention.Severity.GENTLE)
	assert_eq(thrown.params["thrown"], true)
	assert_eq(history.stats()["objects_thrown"], 1)
	assert_eq(history.stats()["objects_moved"], 2)


func test_putting_something_back_is_no_intervention() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(5.5, 5.5))
	manager.grab(rock.id)
	manager.carry(rock.id, Vector2(5.55, 5.5), 0.5)
	assert_null(manager.release(rock.id), "barely moved: put back")
	assert_eq(rock.state, LooseObject.State.FALLING, "but it is let go")
	assert_eq(rock.moved_count, 0)
	assert_eq(history.total(), 0)
	_settle()
	assert_false(rock.discoverable)
	# Only what is in hand can be carried or released.
	assert_false(manager.carry(rock.id, Vector2(9, 9), 0.5))
	assert_null(manager.release(rock.id))
	assert_false(manager.carry(999, Vector2(1, 1), 0.5))
	assert_eq(rock.position, Vector2(5.55, 5.5))


func test_things_put_down_near_the_settlement_can_be_discovered() -> void:
	var near := _object(LooseObject.Kind.ROCK, Vector2(12.5, 12.5))
	var far := _object(LooseObject.Kind.ROCK, Vector2(3.5, 3.5))
	var untouched := _object(LooseObject.Kind.ROCK, Vector2(1.5, 1.5))
	# Carried to the edge of the glade.
	manager.grab(near.id)
	manager.carry(near.id, Vector2(4.5, 0.5), 0.5)
	manager.release(near.id)
	assert_false(near.discoverable, "not while it is still in the air")
	_settle()
	assert_true(near.discoverable, "at rest, 4 tiles from the fire")
	# Carried far away.
	manager.grab(far.id)
	manager.carry(far.id, Vector2(-14.5, -14.5), 0.5)
	manager.release(far.id)
	_settle()
	assert_false(far.discoverable, "too far for anyone to come upon")
	assert_false(untouched.discoverable, "only what the player moved")
	# Taken away again, it is no longer there to be found.
	manager.grab(near.id)
	manager.carry(near.id, Vector2(-14.5, 12.5), 0.5)
	manager.release(near.id)
	_settle()
	assert_false(near.discoverable)
	assert_true(LooseObject.from_dict(far.to_dict()).discoverable == false)
	near.discoverable = true
	assert_true(LooseObject.from_dict(near.to_dict()).discoverable, "the mark survives a save")


func test_water_interventions_report_what_actually_moved() -> void:
	world.set_water(Vector2i(8, 8), 0.25)
	water.wake(Vector2i(8, 8))
	assert_near(manager.scoop(Vector2i(8, 8), 0.4), 0.25, 0.0001, "only what was there")
	assert_eq(applied[-1].magnitude, 0.25)
	assert_eq(applied[-1].tool, &"water")
	assert_eq(applied[-1].severity, Intervention.Severity.MODERATE)
	assert_near(manager.scoop(Vector2i(8, 8), 0.4), 0.0, 0.0, "now it is dry")
	assert_near(manager.pour(Vector2i(2, 2), 0.25), 0.25, 0.0001)
	assert_near(manager.pour(Vector2i(99, 99), 0.25), 0.0, 0.0, "not outside the box")
	assert_near(history.total_of(&"water_moved"), 0.5, 0.0001)
	assert_eq(history.total(), 2)


# --- the history itself ------------------------------------------------------------------------

func test_ordinary_touches_are_counted_not_logged() -> void:
	for i in 50:
		manager.tap(_ground(Vector2i(i % 8, 3)))
	assert_eq(history.count(Intervention.TOUCH), 50)
	assert_eq(history.entry_count(), 1, "only the first is worth remembering")
	var first: Dictionary = history.entries()[0]
	assert_eq(first["first"], true)
	assert_eq(first["type"], "touch")
	assert_eq(first["subject"], "ground")
	assert_eq(first["id"], 1)
	# A first of another kind is remembered too; Moderate acts always are.
	var rock := _object(LooseObject.Kind.ROCK, Vector2(5.5, 5.5))
	manager.tap(_entity(rock.id, rock.tile()))
	_move(rock, Vector2(1.0, 0.0))
	_move(rock, Vector2(1.0, 0.0))
	assert_eq(history.entry_count(), 4, "first ground touch, first rock touch, two moves")
	assert_eq(history.entries()[3]["first"], false)
	assert_eq(history.entries()[3]["severity"], Intervention.Severity.MODERATE)


func test_the_log_is_bounded_and_keeps_the_firsts() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(5.5, 5.5))
	manager.tap(_ground(Vector2i(0, 0))) # a first, right at the start
	for i in PlayerHistory.MAX_ENTRIES + 40:
		_move(rock, Vector2(0.5 if i % 2 == 0 else -0.5, 0.0))
	assert_eq(history.entry_count(), PlayerHistory.MAX_ENTRIES)
	assert_eq(history.entries()[0]["subject"], "ground", "the first touch is still there")
	assert_eq(history.entries()[1]["first"], true, "and the first move")
	assert_eq(history.count(Intervention.MOVE_OBJECT), PlayerHistory.MAX_ENTRIES + 40, "the counts are complete")
	assert_eq(history.entries()[-1]["id"], PlayerHistory.MAX_ENTRIES + 41, "newest last")


func test_statistics() -> void:
	var tree := _prop(PropData.Kind.TREE, Vector2i(4, 4))
	var bears := tree.bears()
	for i in 80:
		manager.tap(_entity(tree.id, tree.tile))
		if tree.bears_left() == 0:
			break
	manager.uproot(_entity(tree.id, tree.tile))
	var stats := history.stats()
	assert_eq(stats["fruit_shaken"], bears)
	assert_eq(stats["trees_uprooted"], 1)
	assert_eq(stats["resources_manipulated"], bears + 1)
	assert_eq(stats["total_interactions"], history.total())
	assert_eq(stats["touches"], history.count(Intervention.TOUCH))
	assert_eq(stats["objects_moved"], 0)


func test_history_survives_saving() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(5.5, 5.5))
	manager.tap(_ground(Vector2i(0, 0)))
	manager.tap(_ground(Vector2i(0, 0)))
	_move(rock, Vector2(2.0, 1.0))
	var data: Dictionary = bytes_to_var(var_to_bytes(history.to_dict()))
	var restored := PlayerHistory.new()
	assert_true(restored.from_dict(data))
	assert_eq(restored.total(), 3)
	assert_eq(restored.count(Intervention.TOUCH, &"ground"), 2)
	assert_eq(restored.entry_count(), history.entry_count())
	assert_eq(restored.peek_next_id(), 4, "numbering goes on where it stopped")
	assert_near(restored.total_of(&"distance_moved"), history.total_of(&"distance_moved"), 0.0001)
	assert_eq(var_to_bytes(restored.to_dict()), var_to_bytes(history.to_dict()))
	# Broken data gives an empty history, not a crash.
	var broken := PlayerHistory.new()
	assert_false(broken.from_dict({}))
	assert_true(broken.from_dict({"next_id": "x", "counts": 5, "keys": {"a": "b", "touch:ground": 3}, "entries": ["junk", {"id": 9, "type": "touch"}]}))
	assert_eq(broken.total(), 0)
	assert_eq(broken.count(Intervention.TOUCH, &"ground"), 3)
	assert_eq(broken.entry_count(), 1)
	assert_eq(broken.peek_next_id(), 10)


func test_unrecorded_and_unapplied_interventions_are_not_history() -> void:
	var iv := Intervention.create(Intervention.TOUCH)
	assert_false(history.record(iv), "not applied")
	iv.applied = true
	iv.recorded = false
	assert_false(history.record(iv), "not meant to be recorded")
	assert_false(history.record(null))
	assert_eq(history.total(), 0)
	assert_eq(iv.id, 0)
