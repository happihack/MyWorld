extends TestCase
## M22: the player trusts their world will never disappear (bible §31.9).
## Saves rotate atomically — whenever the writing is cut off, a whole world
## is there to load; every kind of damage is found and a backup taken
## instead; every save the game has ever written still opens; what is read is
## repaired, and what had to be taken out is kept aside; a save that cannot be
## written (no room) leaves the last good one and is tried again; saves are
## written off the main thread, one at a time.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const FIXTURES := "res://tests/fixtures/saves/"


func before_each() -> void:
	SaveManager.attach(null)
	SaveManager.room_left_override = -1
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()


func after_each() -> void:
	SaveManager.room_left_override = -1


func _world(seed_value: int = 4242) -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	s.create_new(seed_value)
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	return s


func _path(world_id: String, file_name: String = SaveManager.SAVE_FILE) -> String:
	return SaveManager.world_dir(world_id).path_join(file_name)


func _corrupt(path: String, at: int, by: int = 0x5A) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	bytes[at] = bytes[at] ^ by
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _truncate(path: String, length: int) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes.slice(0, length))
	file.close()


func test_atomic_rotation() -> void:
	var s := _world()
	var ticks: Array[int] = []
	for n in 3:
		s.clock.tick += 100
		ticks.append(s.clock.tick)
		assert_true(SaveManager.save_world(s, &"test"))
	var id := s.world_id
	assert_eq(int(SaveContainer.read_header(_path(id)).header["game_tick"]), ticks[2], "the newest in world.sav")
	assert_eq(int(SaveContainer.read_header(_path(id, "world.sav.bak1")).header["game_tick"]), ticks[1])
	assert_eq(int(SaveContainer.read_header(_path(id, "world.sav.bak2")).header["game_tick"]), ticks[0])
	assert_false(FileAccess.file_exists(_path(id, "world.sav.tmp")), "nothing half-done left behind")
	# Cut off while writing (a .tmp half there): the world is as it was.
	var whole := FileAccess.get_file_as_bytes(_path(id))
	var tmp := FileAccess.open(_path(id, "world.sav.tmp"), FileAccess.WRITE)
	tmp.store_buffer(whole.slice(0, whole.size() / 3))
	tmp.close()
	var loaded := SaveManager.load_world(id)
	assert_true(loaded.ok)
	assert_eq(loaded.source, SaveManager.SAVE_FILE, "the half-written copy is not taken")
	# Cut off after the backups turned and before the rename: the .tmp is the world.
	DirAccess.rename_absolute(_path(id), _path(id, "world.sav.tmp"))
	loaded = SaveManager.load_world(id)
	assert_true(loaded.ok)
	assert_eq(int(loaded.header["game_tick"]), ticks[2], "nothing lost")
	# And the next save goes on from there.
	s.clock.tick += 100
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.load_world(id).ok)
	s.queue_free()
	await wait_frames(1)


func test_corruption_detection_matrix() -> void:
	var s := _world()
	assert_true(SaveManager.save_world(s, &"test"))
	s.clock.tick += 60
	assert_true(SaveManager.save_world(s, &"test"))
	var id := s.world_id
	var path := _path(id)
	var good := FileAccess.get_file_as_bytes(path)
	var size := good.size()
	var tried := 0
	# A byte flipped anywhere (the magic, the header, its hash, the payload): found.
	for n in 40:
		var at := (n * 7919 + 13) % size
		_corrupt(path, at)
		var read := SaveContainer.read(path)
		assert_false(read.ok, "byte %d flipped and not noticed" % at)
		var loaded := SaveManager.load_world(id)
		assert_true(loaded.ok and loaded.source == "world.sav.bak1", "byte %d: the backup instead (%s)" % [at, loaded.source])
		_corrupt(path, at) # (flipped back)
		tried += 1
	# Cut short anywhere: found.
	for length in [0, 3, 11, 12, 40, size / 2, size - 33, size - 1]:
		_truncate(path, length)
		assert_false(SaveContainer.read(path).ok, "cut at %d and not noticed" % length)
		assert_eq(SaveManager.load_world(id).source, "world.sav.bak1")
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(good)
		file.close()
		tried += 1
	# Garbage after it: found.
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(good + PackedByteArray([1, 2, 3]))
	file.close()
	assert_false(SaveContainer.read(path).ok)
	assert_true(tried >= 48)
	s.queue_free()
	await wait_frames(1)


func test_migration_chain_all_fixtures() -> void:
	var versions := 0
	for file_name in DirAccess.get_files_at(FIXTURES):
		if not file_name.ends_with("_world.sav"):
			continue
		var source := FIXTURES.path_join(file_name)
		var header := SaveContainer.read_header(source)
		assert_true(header.ok, "%s: readable" % file_name)
		var world_id := str(header.header.get("world_id", ""))
		DirAccess.make_dir_recursive_absolute(SaveManager.world_dir(world_id))
		var copy := FileAccess.open(_path(world_id), FileAccess.WRITE)
		copy.store_buffer(FileAccess.get_file_as_bytes(source))
		copy.close()
		var loaded := SaveManager.load_world(world_id)
		assert_true(loaded.ok, "%s: %s" % [file_name, loaded.error])
		var s: WorldSession = SessionScript.new()
		add_child(s)
		assert_true(s.load_from(loaded.world), "%s: opens" % file_name)
		s.set_process(false)
		assert_true(s.is_active and s.clock.tick >= 0, file_name)
		# … and is saved again in today's format.
		assert_true(SaveManager.save_world(s, &"test"), file_name)
		assert_eq(int(SaveContainer.read_header(_path(world_id)).header["save_version"]), SaveManager.SAVE_VERSION)
		s.queue_free()
		await wait_frames(1)
		versions += 1
	assert_eq(versions, SaveManager.SAVE_VERSION, "a fixture from every version, up to today's")


## A world, saved and spoilt in ways no part of it would read wrong by itself.
func _spoilt() -> Dictionary:
	var s := _world()
	var world := s.to_dict()
	var state: Dictionary = world["world_state"]
	var persons: Array = state["people"]["persons"]
	persons[0]["position"] = Vector2i(99999, -99999)
	persons[0]["health"] = NAN
	persons[1]["partner_id"] = 987654321
	persons[1]["parents"] = PackedInt64Array([876543210])
	persons[2]["home_building_id"] = 765432109
	persons.append(persons[3].duplicate(true)) # (the same person twice)
	state["relationships"]["pairs"].append({"a": persons[0]["id"], "b": 123123123, "affinity": 0.5})
	state["props"]["added"].append({"id": 4040404, "kind": PropData.Kind.HUT, "tile": Vector2i(-77777, 5)})
	s.queue_free()
	return world


func test_validator_repairs() -> void:
	var world := _spoilt()
	var report := SaveValidator.repair(world)
	assert_true(int(report["repaired"]) >= 7, str(report["notes"]))
	var state: Dictionary = world["world_state"]
	var persons: Array = state["people"]["persons"]
	var start: Vector2i = state["start"]["settlement_tile"]
	assert_eq(persons[0]["position"], start, "brought back to the fire")
	assert_eq(persons[0]["health"], 1.0)
	assert_eq(persons[1]["partner_id"], 0, "a partner nobody knows: none")
	assert_eq((persons[1]["parents"] as PackedInt64Array).size(), 0)
	assert_eq(persons[2]["home_building_id"], 0, "a home that is not there: none")
	var ids := {}
	for record: Dictionary in persons:
		assert_false(ids.has(record["id"]), "nobody twice")
		ids[record["id"]] = true
	for pair: Dictionary in state["relationships"]["pairs"]:
		assert_ne(int(pair["b"]), 123123123)
	for prop: Dictionary in state["props"]["added"]:
		assert_ne(int(prop["id"]), 4040404)
	# The world opens from it.
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(world))
	s.set_process(false)
	assert_eq(s.people.size(), persons.size())
	# A sound world needs nothing.
	var sound := s.to_dict()
	assert_eq(int(SaveValidator.repair(sound)["repaired"]), 0, str(SaveValidator.repair(sound)["notes"]))
	s.queue_free()
	await wait_frames(1)


func test_quarantine() -> void:
	var world := _spoilt()
	var id := str(world["world_id"])
	DirAccess.make_dir_recursive_absolute(SaveManager.world_dir(id))
	var header := {"save_version": SaveManager.SAVE_VERSION, "world_id": id, "saved_unix": 1, "game_tick": 0}
	assert_eq(SaveContainer.write(_path(id), header, {"world": world}), OK)
	var loaded := SaveManager.load_world(id)
	assert_true(loaded.ok)
	var kept := FileAccess.get_file_as_string(_path(id, SaveManager.QUARANTINE_FILE))
	assert_has(kept, "loaded and repaired")
	assert_has(kept, "the same person twice", "what was taken out is kept aside")
	assert_has(kept, "between people who are not both living")
	assert_has(kept, "outside the world")
	assert_has(kept, "123123123", "the record itself")


func test_low_storage_keeps_the_last_save_and_tries_again() -> void:
	var s := _world()
	SaveManager.attach(s)
	assert_true(SaveManager.save_world(s, &"test"))
	var id := s.world_id
	var before := FileAccess.get_file_as_bytes(_path(id))
	var failed: Array = []
	var told := func(message: String) -> void: failed.append(message)
	EventBus.save_failed.connect(told)
	SaveManager.room_left_override = 1024 # (all but full)
	s.clock.tick += 500
	assert_false(SaveManager.save_world(s, &"test"))
	assert_eq(FileAccess.get_file_as_bytes(_path(id)), before, "the last good save, untouched")
	assert_false(FileAccess.file_exists(_path(id, "world.sav.tmp")))
	assert_eq(failed.size(), 1, "said")
	assert_has(str(failed[0]), "room")
	var retry: Timer = null
	for child in SaveManager.get_children():
		if child is Timer and (child as Timer).one_shot and not (child as Timer).is_stopped():
			retry = child
	assert_not_null(retry, "tried again later")
	# Room again: the retry saves.
	SaveManager.room_left_override = -1
	retry.timeout.emit()
	while SaveManager.is_writing():
		await wait_frames(1)
	assert_eq(int(SaveContainer.read_header(_path(id)).header["game_tick"]), s.clock.tick, "saved once there was room")
	EventBus.save_failed.disconnect(told)
	SaveManager.attach(null)
	s.queue_free()
	await wait_frames(1)


func test_saves_are_written_off_the_main_thread_one_at_a_time() -> void:
	var s := _world()
	var id := s.world_id
	assert_true(SaveManager.save_world_async(s, &"autosave"))
	assert_true(SaveManager.is_writing(), "written on a worker thread")
	# A save at once (the game paused) waits for it, and comes after it.
	s.clock.tick += 77
	assert_true(SaveManager.save_world(s, &"app_paused"))
	assert_false(SaveManager.is_writing())
	assert_eq(int(SaveContainer.read_header(_path(id)).header["game_tick"]), s.clock.tick, "the later one is the world")
	assert_true(FileAccess.file_exists(_path(id, "world.sav.bak1")), "the earlier one, its backup")
	# Asked again while one is being written: done after it.
	assert_true(SaveManager.save_world_async(s, &"autosave"))
	s.clock.tick += 11
	assert_true(SaveManager.save_world_async(s, &"changed"))
	var waited := 0
	while SaveManager.is_writing() and waited < 600:
		await wait_frames(1)
		waited += 1
	assert_eq(int(SaveContainer.read_header(_path(id)).header["game_tick"]), s.clock.tick)
	assert_eq(SaveManager.last_save_info.get("reason"), &"changed")
	assert_eq(int(SaveContainer.read_header(_path(id)).header["population"]), s.people.size(), "the people counted, for the backups' list")
	s.queue_free()
	await wait_frames(1)
