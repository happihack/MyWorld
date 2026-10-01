extends TestCase
## Everything the player can do in M3, done in the running game and carried
## across a relaunch (M3.7): a moved rock, shaken fruit, an uprooted tree and
## its log, moved water, water still in hand, something held when the game
## closes — and the history of it all.

var main: Node
var session: WorldSession


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	await _launch()


func after_each() -> void:
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _launch() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	session = main.get_node("WorldSession")
	session.loose_system.set_process(false) # the test steps time itself
	session.water.set_process(false)
	main.get_node("UIRoot").quit_action = func() -> void: pass


## Closes the game in an orderly way (which saves) and starts it again.
func _relaunch() -> void:
	await wait_real_ms(Config.save.min_save_gap_ms + 100)
	get_tree().unload_current_scene()
	await wait_frames(2)
	await _launch()


func _settle() -> void:
	for i in 3600:
		session.loose_system.step(LooseObjectSystem.STEP_SECONDS)
		if i % 6 == 0:
			session.water.step(WaterSim.STEP_SECONDS)
		if session.loose_system.moving_count() == 0 and session.water.is_still():
			return


func _nearest(kind: LooseObject.Kind, to: Vector2) -> LooseObject:
	var best: LooseObject = null
	var best_distance := INF
	for o in session.loose.all_objects():
		var d := o.position.distance_to(to)
		if o.kind == kind and d < best_distance:
			best_distance = d
			best = o
	return best


func _trees_by_distance() -> Array[PropData]:
	var home := Vector2(session.start.settlement_tile)
	var trees: Array[PropData] = []
	for p in session.props.all_props():
		if p.kind == PropData.Kind.TREE:
			trees.append(p)
	trees.sort_custom(func(a: PropData, b: PropData) -> bool:
		var da := Vector2(a.tile).distance_squared_to(home)
		var db := Vector2(b.tile).distance_squared_to(home)
		return da < db or (da == db and a.id < b.id))
	return trees


func _entity(id: int, tile: Vector2i) -> Picker.Result:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = id
	target.tile = tile
	return target


func _river_tile(z: int) -> Vector2i:
	var best := Vector2i(0, z)
	var deepest := 0.0
	for x in range(session.world.bounds.position.x, session.world.bounds.end.x):
		var depth := session.world.get_water(Vector2i(x, z))
		if depth > deepest:
			deepest = depth
			best = Vector2i(x, z)
	return best


## Everything about the loose objects that must survive, in a comparable form.
func _loose_snapshot() -> Dictionary:
	var out := {}
	for o in session.loose.all_objects():
		out[o.id] = [o.kind, o.position, snappedf(o.height_offset, 0.001), o.state, o.moved_count, o.discoverable, o.placed_by_player]
	return out


## The state of the dice the player's touches roll (the people's own dice go
## on rolling while the game runs: they live).
func _touch_dice() -> int:
	return int((session.rng.to_dict()["states"] as Dictionary).get("interaction", 0))


func test_save_loose_objects() -> void:
	var home := Vector2(session.start.settlement_tile) + Vector2(0.5, 0.5)
	var interactions := session.interactions

	# Pick up a rock and drop it by the huts.
	var rock := _nearest(LooseObject.Kind.ROCK, home)
	var rock_from := rock.position
	var by_the_huts := home + Vector2(1.6, 1.2)
	assert_true(interactions.grab(rock.id))
	interactions.carry(rock.id, by_the_huts, 0.55)
	assert_not_null(interactions.release(rock.id))
	_settle()
	assert_true(rock.position.distance_to(by_the_huts) < 1.5, "the rock lies by the huts (%s)" % rock.position)
	assert_true(rock.position.distance_to(rock_from) > 2.0)

	# Shake fruit out of a tree; uproot another.
	var fruit_id := 0
	var shaken: PropData = null
	for tree in _trees_by_distance():
		if tree.bears_left() <= 0:
			continue
		for i in 40:
			var response := interactions.tap(_entity(tree.id, tree.tile))
			if not response.dropped.is_empty():
				fruit_id = response.dropped[0]
				break
		if fruit_id != 0:
			shaken = tree
			break
	assert_true(fruit_id != 0, "a fruit came down")
	var felled: PropData = null
	for tree in _trees_by_distance():
		if tree != shaken:
			felled = tree
			break
	var felled_id := felled.id
	var felled_tile := felled.tile
	var uprooted := interactions.uproot(_entity(felled_id, felled_tile))
	var log_id: int = uprooted.dropped[0]

	# Move water: three scoops out of the river, one poured on dry ground, the
	# rest still in hand.
	var river := _river_tile(session.start.settlement_tile.y)
	var all_water := session.water.total_volume()
	for i in 3:
		assert_true(interactions.scoop(river, 0.3) > 0.0)
		for step in 20:
			session.water.step_once()
	var puddle := session.start.settlement_tile + Vector2i(0, WorldSetup.SITE_RADIUS + 3)
	assert_true(interactions.pour(puddle, 0.3) > 0.0)
	_settle()
	assert_true(session.loose_system.moving_count() == 0 and session.water.is_still(), "a world at rest")

	# And the game closes with a pebble still in the player's hand.
	var pebble := LooseObject.new()
	pebble.id = session.ids.next_id()
	pebble.kind = LooseObject.Kind.PEBBLE
	pebble.position = home + Vector2(-2.0, 2.0)
	session.loose.add(pebble)
	var pebble_id := pebble.id
	assert_true(interactions.grab(pebble_id))
	interactions.carry(pebble_id, pebble.position, 0.55)
	assert_eq(pebble.state, LooseObject.State.HELD)

	var loose_before := _loose_snapshot()
	var terrain := WorldChecksum.terrain(session.world)
	var props := WorldChecksum.props(session.props)
	var prop_count := session.props.size()
	var water_volume := session.water.total_volume()
	var carried := session.water.carried
	var history := session.history.to_dict()
	var stats := session.history.stats()
	var taken := shaken.taken
	var shaken_id := shaken.id
	var rock_id := rock.id
	var rock_at := rock.position
	var next_id := session.ids.peek()
	var dice := _touch_dice()
	var soaked := session.water.soaked_total
	assert_near(water_volume + carried + soaked, all_water, 0.002, "no water made or lost")
	assert_true(soaked > 0.0, "the puddle has soaked into the ground")
	assert_true(carried > 0.5)

	await _relaunch()

	# The rock is still by the huts.
	var rock_again := session.loose.get_object(rock_id)
	assert_eq(rock_again.position, rock_at, "the rock is where it was dropped")
	assert_eq(rock_again.moved_count, 1)
	assert_true(rock_again.discoverable, "and still there to be found")
	# Every loose object is where it was — the pebble on the ground now.
	var loose_after := _loose_snapshot()
	assert_eq(loose_after.size(), loose_before.size())
	for id: int in loose_before:
		if id == pebble_id:
			continue
		assert_eq(loose_after.get(id), loose_before[id], "object %d" % id)
	var pebble_again := session.loose.get_object(pebble_id)
	assert_eq(pebble_again.state, LooseObject.State.RESTING, "nothing is saved in mid-air")
	assert_eq(pebble_again.height_offset, 0.0)
	assert_eq(pebble_again.position, loose_before[pebble_id][1])
	assert_false(session.interactions.is_in_hand(pebble_id))
	assert_eq(session.loose_system.moving_count(), 0, "and nothing starts moving by itself")
	# The trees.
	assert_eq(session.props.get_prop(shaken_id).taken, taken, "the shaken tree is still poorer")
	assert_not_null(session.loose.get_object(fruit_id), "its fruit lies where it fell")
	assert_null(session.props.get_prop(felled_id), "the uprooted tree is gone")
	assert_null(session.props.prop_at(felled_tile))
	assert_eq(session.loose.get_object(log_id).kind, LooseObject.Kind.LOG, "its log remains")
	assert_eq(session.props.size(), prop_count)
	assert_eq(WorldChecksum.props(session.props), props)
	# The water.
	assert_eq(WorldChecksum.terrain(session.world), terrain, "ground and water as they were")
	assert_near(session.water.total_volume(), water_volume, 0.0005)
	assert_near(session.water.carried, carried, 0.0001, "the water in hand")
	assert_near(session.water.soaked_total, soaked, 0.0001)
	# The history, and the books that keep ids and dice from repeating.
	assert_eq(session.history.to_dict(), history)
	assert_eq(session.history.stats(), stats)
	assert_eq(session.history.count(Intervention.MOVE_OBJECT, &"rock"), 1)
	assert_eq(session.history.count(Intervention.UPROOT), 1)
	assert_eq(session.ids.peek(), next_id)
	assert_eq(_touch_dice(), dice)

	# A second relaunch without touching anything changes nothing (a save is
	# stable: loading and saving again does not drift).
	var bytes: int = SaveManager.last_save_info["bytes"]
	var ms: float = SaveManager.last_save_info["ms"]
	await _relaunch()
	assert_eq(_loose_snapshot(), loose_after)
	assert_eq(WorldChecksum.terrain(session.world), terrain)
	assert_eq(session.history.to_dict(), history)
	print("    M3 world: save %d bytes in %.1f ms (%d modified chunks, %d loose records, %d history entries)" % [
		bytes, ms, session.world.modified_chunks().size(),
		(session.to_dict()["world_state"]["loose"]["objects"] as Array).size(), session.history.entry_count()])
	assert_true(bytes < 200_000, "the save stays small (%d bytes)" % bytes)


func test_a_change_made_in_the_game_is_saved_without_closing_it() -> void:
	# What a crash or a killed app would leave behind: the save on disk.
	Config.save.min_save_gap_ms = 0
	Config.save.save_quiet_s = 0.3
	var home := Vector2(session.start.settlement_tile) + Vector2(0.5, 0.5)
	var rock := _nearest(LooseObject.Kind.ROCK, home)
	var target := home + Vector2(1.6, 1.2)
	session.interactions.grab(rock.id)
	session.interactions.carry(rock.id, target, 0.55)
	session.interactions.release(rock.id)
	_settle()
	assert_true(SaveManager.has_unsaved_change())
	await wait_real_ms(500)
	Config.save.min_save_gap_ms = SaveConfig.new().min_save_gap_ms
	Config.save.save_quiet_s = SaveConfig.new().save_quiet_s
	assert_false(SaveManager.has_unsaved_change())
	assert_eq(SaveManager.last_save_info["reason"], &"changed")
	var on_disk := WorldSession.new()
	add_child(on_disk)
	assert_true(on_disk.load_from(SaveManager.load_world(session.world_id).world))
	assert_eq(on_disk.loose.get_object(rock.id).position, rock.position, "already on disk")
	assert_eq(on_disk.history.count(Intervention.MOVE_OBJECT), 1)
	on_disk.queue_free()
