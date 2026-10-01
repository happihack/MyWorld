extends TestCase
## The world itself surviving save/load (M1.8): sparse storage of modified
## chunks and prop differences, start info, and migration of version-1 saves.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V1_FIXTURE := "res://tests/fixtures/saves/v1_world.sav"
const V2_FIXTURE := "res://tests/fixtures/saves/v2_world.sav"

var sessions: Array[WorldSession] = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)


func after_each() -> void:
	SaveManager.attach(null)
	for s in sessions:
		if is_instance_valid(s):
			s.queue_free()
	sessions.clear()
	await wait_frames(1)


func _session() -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	sessions.append(s)
	return s


## Saves `s` through SaveManager and loads it into a fresh session.
func _save_and_reload(s: WorldSession) -> WorldSession:
	assert_true(SaveManager.save_world(s, &"test"))
	var loaded := SaveManager.load_world(s.world_id)
	assert_true(loaded.ok, loaded.error)
	var again := _session()
	assert_true(again.load_from(loaded.world))
	return again


func _first_tree(s: WorldSession) -> PropData:
	for p in s.props.all_props():
		if p.kind == PropData.Kind.TREE:
			return p
	return null


func test_untouched_world_saves_only_the_start() -> void:
	var s := _session()
	s.create_new(12345)
	var state: Dictionary = s.to_dict()["world_state"]
	assert_eq(state["template_id"], "river_valley")
	assert_eq(state["generator_version"], WorldGenerator.GENERATOR_VERSION)
	assert_eq((state["world"]["chunks"] as Array).size(), 0, "no chunk differs from the generator")
	assert_eq((state["props"]["added"] as Array).size(), 5, "campfire + 3 huts + ruin")
	assert_eq(state["start"]["settlement_tile"], s.start.settlement_tile)
	SaveManager.save_world(s, &"test")
	assert_true(SaveManager.last_save_info["bytes"] < 4000, "a pristine world is tiny (%d B)" % SaveManager.last_save_info["bytes"])


func test_reload_reproduces_the_world_exactly() -> void:
	var s := _session()
	s.create_new(12345)
	var again := _save_and_reload(s)
	assert_eq(WorldChecksum.terrain(again.world), WorldChecksum.terrain(s.world))
	assert_eq(WorldChecksum.props(again.props), WorldChecksum.props(s.props))
	assert_eq(again.start.to_dict(), s.start.to_dict())
	assert_eq(again.world.bounds, s.world.bounds)
	assert_eq(again.ids.peek(), s.ids.peek(), "ids continue exactly where they left off")
	assert_eq(again.template_id, s.template_id)


func test_changes_survive_and_only_changes_are_stored() -> void:
	var s := _session()
	s.create_new(777)
	var dug := s.start.settlement_tile + Vector2i(6, 0)
	var flooded := s.start.settlement_tile + Vector2i(-20, 3)
	s.world.set_height(dug, 1)
	s.world.set_water(flooded, 0.3)
	var tree := _first_tree(s)
	var tree_tile := tree.tile
	s.props.remove(tree.id)

	var state: Dictionary = s.to_dict()["world_state"]
	var saved_chunks := (state["world"]["chunks"] as Array).size()
	assert_true(saved_chunks >= 1 and saved_chunks <= 2, "only the touched chunks (%d of 16)" % saved_chunks)

	var again := _save_and_reload(s)
	assert_eq(again.world.get_height(dug), 1)
	assert_near(again.world.get_water(flooded), 0.3, 0.0001)
	assert_null(again.props.prop_at(tree_tile), "the removed tree stays removed")
	assert_eq(again.world.modified_chunks().size(), saved_chunks)
	assert_eq(WorldChecksum.terrain(again.world), WorldChecksum.terrain(s.world))
	assert_eq(WorldChecksum.props(again.props), WorldChecksum.props(s.props))
	# And it stays that way through a second save/load.
	var third := _save_and_reload(again)
	assert_eq(WorldChecksum.terrain(third.world), WorldChecksum.terrain(s.world))
	assert_null(third.props.prop_at(tree_tile))


func test_saved_start_is_restored_not_recomputed() -> void:
	var s := _session()
	s.create_new(42)
	var data := s.to_dict()
	var moved: Vector2i = s.start.settlement_tile + Vector2i(1, 1)
	data["world_state"]["start"]["settlement_tile"] = moved
	var again := _session()
	assert_true(again.load_from(data))
	assert_eq(again.start.settlement_tile, moved, "the saved site wins over what scoring would choose today")
	assert_eq(again.start.hut_ids, s.start.hut_ids)
	assert_eq(again.start.campfire_id, s.start.campfire_id)


func test_world_keeps_its_own_geometry_when_config_changes() -> void:
	var s := _session()
	s.create_new(99)
	var data := s.to_dict()
	var original_step := Config.world.height_step
	Config.world.height_step = original_step * 2.0 # the designer retunes later
	var again := _session()
	var ok := again.load_from(data)
	Config.world.height_step = original_step
	assert_true(ok)
	assert_near(again.world.height_step, original_step, 0.0001, "an existing world keeps the step it was made with")
	assert_eq(WorldChecksum.terrain(again.world), WorldChecksum.terrain(s.world))


func test_damaged_world_state_falls_back_to_the_seed() -> void:
	var s := _session()
	s.create_new(12345)
	var expected := WorldChecksum.terrain(s.world)
	for damage in ["not a dictionary", {"world": 5, "props": {}, "start": {}},
			{"world": {"bounds": "x"}, "props": {}, "start": {}},
			{"world": s.world.to_dict(), "props": {"removed": "x"}, "start": s.start.to_dict()},
			{"world": s.world.to_dict(), "props": s.props.to_dict(), "start": {}}]:
		var data := s.to_dict()
		data["world_state"] = damage
		var again := _session()
		assert_true(again.load_from(data), "still loads with world_state = %s" % str(damage).substr(0, 40))
		assert_true(again.is_active)
		assert_eq(WorldChecksum.terrain(again.world), expected, "rebuilt from the seed")
		assert_true(again.start.ok)
		assert_true(again.ids.peek() >= 6, "ids kept clear of the rebuilt props")


func test_bad_chunk_records_are_skipped_not_fatal() -> void:
	var s := _session()
	s.create_new(5)
	s.world.set_height(s.start.settlement_tile, 9)
	var data := s.to_dict()
	(data["world_state"]["world"]["chunks"] as Array).append({"garbage": true})
	var again := _session()
	assert_true(again.load_from(data))
	assert_eq(again.world.get_height(s.start.settlement_tile), 9, "the good chunk record still applies")


func test_version_1_save_migrates_and_loads() -> void:
	assert_true(FileAccess.file_exists(V1_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir("w1790000000_fixture1")
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V1_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 1)

	var loaded := SaveManager.load_world("w1790000000_fixture1")
	assert_true(loaded.ok, loaded.error)
	assert_true(loaded.world.has("world_state"), "migration added world_state")
	var s := _session()
	assert_true(s.load_from(loaded.world))
	assert_eq(s.world_seed, 12345)
	assert_eq(s.clock.tick, 4321)
	assert_true(s.start.ok)
	assert_true(s.props.size() > 100)
	assert_true(s.ids.peek() >= 6)
	# Saving again writes the current version with the world inside.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 1, "the version-1 file is kept as a backup")
	var reloaded := SaveManager.load_world("w1790000000_fixture1")
	assert_eq(reloaded.world["world_state"]["start"]["settlement_tile"], s.start.settlement_tile)


func test_main_scene_keeps_world_changes_across_launches() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var main := get_tree().current_scene
	var s: WorldSession = main.get_node("WorldSession")
	var tree := _first_tree(s)
	var tile := tree.tile
	s.props.remove(tree.id)
	var dug := s.start.settlement_tile + Vector2i(5, 5)
	s.world.set_height(dug, 2)
	# Digging may let water in (if the river is near): let it settle first, so
	# the world that is saved is a world at rest.
	s.water.wake(dug)
	for i in 5000:
		if s.water.is_still():
			break
		s.water.step_once()
	assert_true(s.water.is_still())
	var fingerprint := WorldChecksum.terrain(s.world)
	await wait_real_ms(Config.save.min_save_gap_ms + 100)
	get_tree().unload_current_scene() # orderly close saves
	await wait_frames(2)

	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var s2: WorldSession = get_tree().current_scene.get_node("WorldSession")
	assert_null(s2.props.prop_at(tile), "the felled tree is still gone after relaunch")
	assert_eq(WorldChecksum.terrain(s2.world), fingerprint)
	get_tree().unload_current_scene()
	await wait_frames(2)


# --- loose objects ------------------------------------------------------------------------

func _first_loose(s: WorldSession, kind: LooseObject.Kind) -> LooseObject:
	var ids: Array = []
	for o in s.loose.all_objects():
		if o.kind == kind:
			ids.append(o.id)
	ids.sort()
	return s.loose.get_object(ids[0]) if not ids.is_empty() else null


func test_untouched_loose_objects_cost_nothing_to_save() -> void:
	var s := _session()
	s.create_new(12345)
	assert_true(s.loose.size() > 20, "rocks lie about (%d)" % s.loose.size())
	var state: Dictionary = s.to_dict()["world_state"]
	assert_eq((state["loose"]["objects"] as Array).size(), 0)
	assert_true((state["loose"]["removed"] as PackedInt64Array).size() <= 25, "only the cleared glade")
	var again := _save_and_reload(s)
	assert_eq(again.loose.size(), s.loose.size())
	for o in s.loose.all_objects():
		var twin := again.loose.get_object(o.id)
		assert_not_null(twin)
		if twin != null:
			assert_eq(twin.position, o.position)
			assert_eq(twin.kind, o.kind)


func test_moved_added_and_removed_loose_objects_survive() -> void:
	var s := _session()
	s.create_new(12345)
	var rock := _first_loose(s, LooseObject.Kind.ROCK)
	var boulder := _first_loose(s, LooseObject.Kind.BOULDER)
	var site := Vector2(s.start.settlement_tile) + Vector2(1.5, 0.5)
	s.loose.move(rock.id, site, 0.0, 1.0)
	rock.moved_count = 2
	s.loose.remove(boulder.id)
	var pebble := LooseObject.new()
	pebble.id = s.ids.next_id()
	pebble.kind = LooseObject.Kind.PEBBLE
	pebble.position = site + Vector2(0.3, 0.2)
	pebble.placed_by_player = true
	assert_true(s.loose.add(pebble))
	var count := s.loose.size()

	var again := _save_and_reload(s)
	assert_eq(again.loose.size(), count)
	var moved := again.loose.get_object(rock.id)
	assert_eq(moved.position, site, "the rock stays by the fire")
	assert_eq(moved.moved_count, 2)
	assert_null(again.loose.get_object(boulder.id), "the boulder stays gone")
	var back := again.loose.get_object(pebble.id)
	assert_not_null(back)
	assert_true(back.placed_by_player)
	assert_eq(again.spatial.get_kind(rock.id), SpatialIndex.KIND_LOOSE_OBJECT)
	assert_eq(again.spatial.get_position(rock.id), site)
	assert_true(again.ids.next_id() > pebble.id, "new ids never reuse a saved object's id")
	# The touch system of the reloaded world knows the objects.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = rock.id
	target.tile = moved.tile()
	assert_eq(again.interactions.tap(target).loose_kind, LooseObject.Kind.ROCK)


func test_version_2_save_migrates_and_loads() -> void:
	# The fixture was written by the last build from before loose objects
	# (rocks were props): seed 12345, one tree felled, one tile dug.
	assert_true(FileAccess.file_exists(V2_FIXTURE), "fixture present")
	var id := "w1790835263_88a7bf97"
	var dir := SaveManager.world_dir(id)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V2_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 2)

	var loaded := SaveManager.load_world(id)
	assert_true(loaded.ok, loaded.error)
	var state: Dictionary = loaded.world["world_state"]
	for part: String in ["loose", "history", "water"]:
		assert_true(typeof(state.get(part)) == TYPE_DICTIONARY, "migration added %s" % part)
	assert_true((state["props"] as Dictionary).has("changed"))
	assert_true((state["loose"]["removed"] as PackedInt64Array).size() > 0, "the rocks cleared from the glade")

	var s := _session()
	assert_true(s.load_from(loaded.world))
	var fresh := _session()
	fresh.create_new(12345)
	assert_eq(s.world_seed, 12345)
	assert_eq(s.clock.tick, 617)
	assert_eq(s.start.settlement_tile, Vector2i(11, 9))
	# What the player of that save had changed is still changed.
	assert_null(s.props.prop_at(Vector2i(-8, -32)), "the felled tree stays felled")
	assert_not_null(fresh.props.prop_at(Vector2i(-8, -32)))
	assert_eq(s.world.get_height(Vector2i(16, 14)), 2, "the dug tile stays dug")
	assert_eq(s.props.size(), fresh.props.size() - 1)
	# Its rocks are loose objects now, and none lie in the glade again.
	assert_eq(s.loose.size(), fresh.loose.size(), "the same rocks, now loose")
	for o in s.loose.all_objects():
		var d := o.tile() - s.start.settlement_tile
		assert_false(absi(d.x) <= WorldSetup.SITE_RADIUS and absi(d.y) <= WorldSetup.SITE_RADIUS, "glade stays clear")
		var twin := fresh.loose.get_object(o.id)
		assert_not_null(twin, "the same ids as in a new world")
		if twin != null:
			assert_eq(o.position, twin.position)
	assert_eq(s.history.total(), 0, "an empty history to start from")
	assert_eq(s.water.carried, 0.0)
	# Saving again writes the current version; the old file is kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 2)
	var again := _session()
	assert_true(again.load_from(SaveManager.load_world(id).world))
	assert_eq(again.loose.size(), s.loose.size())
	assert_eq(WorldChecksum.terrain(again.world), WorldChecksum.terrain(s.world))


func test_damaged_loose_data_falls_back_to_the_seed() -> void:
	var s := _session()
	s.create_new(12345)
	var data := s.to_dict()
	data["world_state"]["loose"] = {"removed": "broken", "objects": []}
	Log.console_output = false
	var again := _session()
	assert_true(again.load_from(data), "still loads")
	assert_eq(again.loose.size(), s.loose.size(), "rebuilt from the seed")


# --- trees ----------------------------------------------------------------------------------

func _shake_until_drop(s: WorldSession, tree: PropData) -> int:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	for i in 60:
		var response := s.interactions.tap(target)
		if not response.dropped.is_empty():
			return response.dropped[0]
	return 0


func test_shaken_fruit_and_the_trees_loss_survive() -> void:
	var s := _session()
	s.create_new(12345)
	s.loose_system.set_process(false)
	var tree := _first_tree(s)
	var fruit_id := _shake_until_drop(s, tree)
	assert_true(fruit_id != 0, "a fruit came down")
	for i in 600:
		s.loose_system.step(LooseObjectSystem.STEP_SECONDS)
	var fruit := s.loose.get_object(fruit_id)
	assert_eq(fruit.state, LooseObject.State.RESTING)
	var state: Dictionary = s.to_dict()["world_state"]
	assert_eq((state["props"]["changed"] as Array).size(), 1, "only the shaken tree")

	var again := _save_and_reload(s)
	assert_eq(again.props.get_prop(tree.id).taken, 1, "the tree is one fruit poorer")
	var back := again.loose.get_object(fruit_id)
	assert_not_null(back, "and the fruit lies where it fell")
	assert_eq(back.kind, fruit.kind)
	assert_eq(back.position, fruit.position)
	assert_true(again.rng.to_dict() == s.rng.to_dict(), "the dice continue where they stopped")


func test_an_uprooted_tree_stays_gone_and_its_log_stays() -> void:
	var s := _session()
	s.create_new(12345)
	s.loose_system.set_process(false)
	var tree := _first_tree(s)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	var response := s.interactions.uproot(target)
	for i in 600:
		s.loose_system.step(LooseObjectSystem.STEP_SECONDS)
	var log := s.loose.get_object(response.dropped[0])
	var again := _save_and_reload(s)
	assert_null(again.props.get_prop(tree.id))
	assert_eq(again.props.size(), s.props.size())
	var back := again.loose.get_object(log.id)
	assert_eq(back.kind, LooseObject.Kind.LOG)
	assert_eq(back.position, log.position)


# --- player history -------------------------------------------------------------------------

func test_the_players_history_is_saved_with_the_world() -> void:
	var s := _session()
	s.create_new(12345)
	s.loose_system.set_process(false)
	assert_eq(s.history.total(), 0, "a new world has no history")
	var tree := _first_tree(s)
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	s.interactions.tap(target)
	s.interactions.tap(target)
	s.interactions.uproot(target)
	assert_eq(s.history.total(), 3)

	var again := _save_and_reload(s)
	assert_eq(again.history.total(), 3)
	assert_eq(again.history.count(Intervention.TOUCH, &"tree"), 2)
	assert_eq(again.history.count(Intervention.UPROOT), 1)
	assert_eq(again.history.entry_count(), s.history.entry_count())
	assert_true(again.interactions.history == again.history, "the manager writes into the saved history")
	# What is done next continues the numbering.
	var ground := Picker.Result.new()
	ground.kind = Picker.Kind.TILE
	ground.tile = again.start.settlement_tile
	again.interactions.tap(ground)
	assert_eq(again.history.entries()[-1]["id"], 4)
	# Another new world starts with a clean slate.
	again.create_new(777)
	assert_eq(again.history.total(), 0)


func test_a_save_without_history_loads_with_an_empty_one() -> void:
	var s := _session()
	s.create_new(12345)
	var data := s.to_dict()
	(data["world_state"] as Dictionary).erase("history")
	var old := _session()
	assert_true(old.load_from(data))
	assert_eq(old.history.total(), 0)
	assert_eq(old.history.peek_next_id(), 1)


# --- water ------------------------------------------------------------------------------------

func _river_tile(s: WorldSession, z: int) -> Vector2i:
	var best := Vector2i(0, z)
	var deepest := 0.0
	for x in range(s.world.bounds.position.x, s.world.bounds.end.x):
		var depth := s.world.get_water(Vector2i(x, z))
		if depth > deepest:
			deepest = depth
			best = Vector2i(x, z)
	return best


func test_water_in_the_players_hands_is_saved_with_the_world() -> void:
	var s := _session()
	s.create_new(12345)
	s.water.set_process(false)
	s.water.soak_per_second = 0.0
	var before := s.water.total_volume()
	var river := _river_tile(s, 0)
	assert_near(s.interactions.pour(river, 0.3), 0.0, 0.0, "empty hands pour nothing")
	var scooped := s.interactions.scoop(river, 0.3)
	assert_true(scooped > 0.0)
	assert_near(s.water.carried, scooped, 0.0001)
	assert_near(s.interactions.pour(river + Vector2i(0, 3), 5.0), scooped, 0.0001, "no more than is carried")
	assert_near(s.water.carried, 0.0, 0.0001)
	scooped = s.interactions.scoop(river, 0.3)
	assert_near(s.water.total_volume() + s.water.carried, before, 0.0001, "none made, none lost")

	var again := _save_and_reload(s)
	again.water.set_process(false)
	assert_near(again.water.carried, scooped, 0.0001, "still carried after loading")
	assert_near(again.water.total_volume() + again.water.carried, before, 0.001)
	assert_near(again.interactions.pour(river, 1.0), scooped, 0.0001, "and it can be poured out")
	# Another world does not inherit it.
	again.water.carried = 1.0
	again.create_new(777)
	assert_eq(again.water.carried, 0.0)


func test_what_the_soil_drank_is_remembered() -> void:
	var s := _session()
	s.create_new(12345)
	s.water.set_process(false)
	var dry := s.start.settlement_tile + Vector2i(6, 0)
	s.water.add_water(dry, 0.5)
	for i in 3000:
		if s.water.is_still():
			break
		s.water.step_once()
	assert_true(s.water.soaked_total > 0.0)
	var again := _save_and_reload(s)
	assert_near(again.water.soaked_total, s.water.soaked_total, 0.00001)


func test_broken_water_books_load_as_empty() -> void:
	var s := _session()
	s.create_new(12345)
	var data := s.to_dict()
	data["world_state"]["water"] = {"carried": NAN, "soaked_total": -4.0}
	var again := _session()
	assert_true(again.load_from(data))
	assert_eq(again.water.carried, 0.0)
	assert_eq(again.water.soaked_total, 0.0)
	data["world_state"]["water"] = "broken"
	var third := _session()
	assert_true(third.load_from(data))
	assert_eq(third.water.carried, 0.0)


func test_a_floating_log_saved_adrift_is_afloat_after_loading() -> void:
	var s := _session()
	s.create_new(12345)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	var tile := _river_tile(s, -10)
	var log := LooseObject.new()
	log.id = s.ids.next_id()
	log.kind = LooseObject.Kind.LOG
	log.position = Vector2(tile) + Vector2(0.5, 0.5)
	log.height_offset = 1.0
	s.loose.add(log)
	s.loose_system.drop(log.id)
	for i in 150:
		s.loose_system.step(LooseObjectSystem.STEP_SECONDS)
	assert_true(s.loose_system.is_moving(log.id), "adrift")
	assert_true(log.height_offset > 0.05, "on the surface")

	var again := _save_and_reload(s)
	again.loose_system.set_process(false)
	again.water.set_process(false)
	var back := again.loose.get_object(log.id)
	assert_eq(back.position, log.position, "where it was")
	assert_true(again.loose_system.is_moving(back.id), "it does not lie on the river bed")
	for i in 120:
		again.loose_system.step(LooseObjectSystem.STEP_SECONDS)
	assert_near(back.height_offset, again.world.get_water(back.tile()), 0.02, "afloat again")
	assert_true(back.position.y > log.position.y, "and drifting on")


func test_flooding_or_digging_under_things_does_not_unmake_them() -> void:
	# What stands and lies in a chunk comes from the land as it was made. The
	# generator grows nothing on water — so a flooded tree must not be missing
	# after loading, nor a tree on dug ground change its kind.
	var s := _session()
	s.create_new(12345)
	s.water.set_process(false)
	s.loose_system.set_process(false)
	var tree := _first_tree(s)
	var rock := _first_loose(s, LooseObject.Kind.ROCK)
	s.world.set_water(tree.tile, 0.3)
	s.world.set_water(rock.tile(), 0.3)
	var conifer: PropData = null
	for p in s.props.all_props():
		if p.kind == PropData.Kind.TREE and p.is_conifer():
			conifer = p
			break
	assert_not_null(conifer)
	s.world.set_height(conifer.tile, 0)
	var props := WorldChecksum.props(s.props)
	var count := s.loose.size()

	var again := _save_and_reload(s)
	assert_true(again.world.get_water(tree.tile) > 0.0, "the flood was saved")
	assert_not_null(again.props.get_prop(tree.id), "the flooded tree still stands")
	assert_not_null(again.loose.get_object(rock.id), "the flooded rock still lies there")
	assert_true(again.props.get_prop(conifer.id).is_conifer(), "the tree on dug ground is the tree it was")
	assert_eq(WorldChecksum.props(again.props), props)
	assert_eq(again.loose.size(), count)
	# And nothing new grows where the player drained the river.
	var bed := _river_tile(s, 0)
	s.world.set_water(bed, 0.0)
	s.world.set_terrain(bed, ChunkData.Terrain.GRASS)
	var drained := _save_and_reload(s)
	assert_null(drained.props.prop_at(bed))
	assert_eq(drained.props.size(), s.props.size())
