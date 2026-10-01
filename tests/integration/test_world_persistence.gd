extends TestCase
## The world itself surviving save/load (M1.8): sparse storage of modified
## chunks and prop differences, start info, and migration of version-1 saves.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V1_FIXTURE := "res://tests/fixtures/saves/v1_world.sav"

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
	s.world.set_height(s.start.settlement_tile + Vector2i(5, 5), 2)
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


func test_save_from_before_loose_objects_keeps_its_glade_clear() -> void:
	var s := _session()
	s.create_new(12345)
	var data := s.to_dict()
	# As such a save looked: no "loose" entry, and the glade's rocks listed with
	# the removed props (rocks were props then).
	var removed: PackedInt64Array = data["world_state"]["props"]["removed"]
	removed.append_array(data["world_state"]["loose"]["removed"])
	removed.sort()
	data["world_state"]["props"]["removed"] = removed
	(data["world_state"] as Dictionary).erase("loose")
	var old := _session()
	assert_true(old.load_from(data))
	assert_eq(old.loose.size(), s.loose.size(), "the same rocks, now loose")
	assert_eq(old.props.size(), s.props.size())
	for o in old.loose.all_objects():
		var d := o.tile() - old.start.settlement_tile
		assert_false(absi(d.x) <= WorldSetup.SITE_RADIUS and absi(d.y) <= WorldSetup.SITE_RADIUS, "glade stays clear")


func test_damaged_loose_data_falls_back_to_the_seed() -> void:
	var s := _session()
	s.create_new(12345)
	var data := s.to_dict()
	data["world_state"]["loose"] = {"removed": "broken", "objects": []}
	Log.console_output = false
	var again := _session()
	assert_true(again.load_from(data), "still loads")
	assert_eq(again.loose.size(), s.loose.size(), "rebuilt from the seed")
