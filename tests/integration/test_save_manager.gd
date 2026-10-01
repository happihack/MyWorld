extends TestCase
## SaveManager against the runner's isolated save root.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession


func before_each() -> void:
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	session = SessionScript.new()
	add_child(session)
	session.create_new(4242)


func after_each() -> void:
	Config.save.min_save_gap_ms = SaveConfig.new().min_save_gap_ms
	SaveManager.attach(null)
	if is_instance_valid(session):
		session.queue_free()
	await wait_frames(1)


func _tick(n: int) -> void:
	for i in n * 2:
		session.clock.advance(0.25)


func _dir() -> String:
	return SaveManager.world_dir(session.world_id)


func _header_tick(file_name: String) -> int:
	return int(SaveContainer.read_header(_dir().path_join(file_name)).header["game_tick"])


func test_runner_isolated_the_save_root() -> void:
	assert_has(Config.save.save_root, "test_run")


func test_save_and_load_roundtrip() -> void:
	assert_true(SaveManager.save_world(session, &"test"))
	var lr := SaveManager.load_world(session.world_id)
	assert_true(lr.ok, lr.error)
	assert_eq(lr.source, "world.sav")
	assert_eq(lr.world, session.to_dict())
	assert_eq(lr.header["save_version"], SaveManager.SAVE_VERSION)


func test_rotation_keeps_progressively_older_backups() -> void:
	for i in 4:
		SaveManager.save_world(session, &"test")
		_tick(1)
	var files := Array(DirAccess.get_files_at(_dir()))
	files.sort()
	assert_eq(files, ["world.sav", "world.sav.bak1", "world.sav.bak2"])
	assert_eq([_header_tick("world.sav"), _header_tick("world.sav.bak1"), _header_tick("world.sav.bak2")], [3, 2, 1])


func test_corrupt_main_falls_back_to_bak1() -> void:
	SaveManager.save_world(session, &"test")
	_tick(1)
	SaveManager.save_world(session, &"test")
	corrupt_byte(_dir().path_join("world.sav"))
	var lr := SaveManager.load_world(session.world_id)
	assert_true(lr.ok)
	assert_eq(lr.source, "world.sav.bak1")
	assert_eq(lr.world["clock"]["tick"], 0)


func test_crash_between_rotation_and_rename_prefers_tmp() -> void:
	SaveManager.save_world(session, &"test")
	SaveManager.save_world(session, &"test")
	DirAccess.remove_absolute(_dir().path_join("world.sav")) # rotated away, rename never happened
	_tick(2)
	SaveContainer.write(_dir().path_join("world.sav.tmp"), {"save_version": 1, "saved_unix": 1}, {"world": session.to_dict()})
	var lr := SaveManager.load_world(session.world_id)
	assert_eq(lr.source, "world.sav.tmp")
	assert_eq(lr.world["clock"]["tick"], 2)


func test_everything_corrupt_fails_cleanly() -> void:
	for i in 3:
		SaveManager.save_world(session, &"test")
	for f in DirAccess.get_files_at(_dir()):
		corrupt_byte(_dir().path_join(f))
	var failed := [false]
	var cb := func(_e: String) -> void: failed[0] = true
	EventBus.load_failed.connect(cb)
	var lr := SaveManager.load_world(session.world_id)
	EventBus.load_failed.disconnect(cb)
	assert_false(lr.ok)
	assert_true(failed[0])


func test_newer_save_version_refused_and_untouched() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	var path := _dir().path_join("world.sav")
	SaveContainer.write(path, {"save_version": 99, "saved_unix": 1}, {"world": session.to_dict()})
	var before := FileAccess.get_file_as_bytes(path)
	var lr := SaveManager.load_world(session.world_id)
	assert_false(lr.ok)
	assert_has(lr.error, "newer")
	assert_eq(FileAccess.get_file_as_bytes(path), before)


func test_recency_order_and_unreadable_headers() -> void:
	var root := Config.save.save_root
	for spec in [["wA", 100], ["wB", 300], ["wC", 200]]:
		DirAccess.make_dir_recursive_absolute(root.path_join(spec[0]))
		SaveContainer.write(root.path_join(spec[0]).path_join("world.sav"), {"save_version": 1, "saved_unix": spec[1]}, {"world": {}})
	assert_eq(SaveManager.world_ids_by_recency(), PackedStringArray(["wB", "wC", "wA"]))
	var bytes := FileAccess.get_file_as_bytes(root.path_join("wB/world.sav"))
	bytes[0] = 0
	write_bytes(root.path_join("wB/world.sav"), bytes)
	assert_eq(SaveManager.find_latest_world_id(), "wC")


func test_back_to_back_lifecycle_saves_are_deduplicated() -> void:
	var reasons := []
	var cb := func(_p: String, _ms: float) -> void: reasons.append(SaveManager.last_save_info["reason"])
	EventBus.save_completed.connect(cb)
	SaveManager.attach(session)
	EventBus.app_focus_changed.emit(false) # Android: focus loss, then pause
	EventBus.app_paused.emit()
	EventBus.save_completed.disconnect(cb)
	assert_eq(reasons, [&"focus_lost"], "second save within the gap is skipped")
	var files := Array(DirAccess.get_files_at(_dir()))
	assert_false(files.has("world.sav.bak1"), "no duplicate rotated into the backups")
	assert_true(SaveManager.save_world(session, &"manual"), "explicit save_world always saves")
	await wait_seconds(Config.save.min_save_gap_ms / 1000.0 + 0.1)
	EventBus.save_completed.connect(cb)
	EventBus.app_paused.emit()
	EventBus.save_completed.disconnect(cb)
	assert_eq(reasons, [&"focus_lost", &"app_paused"], "saves again once the gap has passed")


func test_lifecycle_and_close_saves() -> void:
	Config.save.min_save_gap_ms = 0 # isolate the triggers from the dedupe rule
	var reasons := []
	var cb := func(_p: String, _ms: float) -> void: reasons.append(SaveManager.last_save_info["reason"])
	EventBus.save_completed.connect(cb)
	assert_false(SaveManager.save_current(), "nothing attached")
	SaveManager.attach(session)
	EventBus.app_paused.emit()
	EventBus.app_quit_requested.emit()
	EventBus.app_focus_changed.emit(false)
	EventBus.app_focus_changed.emit(true)
	_tick(1)
	session.shutdown()
	EventBus.save_completed.disconnect(cb)
	assert_eq(reasons, [&"app_paused", &"quit", &"focus_lost", &"world_closed"])
	assert_eq(SaveManager.load_world(session.world_id).world["clock"]["tick"], 1, "close save has latest tick")


func test_reattach_and_detach_stop_saving_old_session() -> void:
	Config.save.min_save_gap_ms = 0
	var other: WorldSession = SessionScript.new()
	add_child(other)
	other.create_new(5)
	SaveManager.attach(session)
	SaveManager.attach(other)
	var saves := [0]
	var cb := func(_p: String, _ms: float) -> void: saves[0] += 1
	EventBus.save_completed.connect(cb)
	session.shutdown() # no longer attached
	SaveManager.attach(null)
	other.shutdown() # detached
	EventBus.save_completed.disconnect(cb)
	other.queue_free()
	assert_eq(saves[0], 0)
