extends Node
## Autoload "SaveManager": world persistence (bible §31.9).
##
## Layout: <save_root>/<world_id>/world.sav (+ .bak1..bakN, transient .tmp)
## Saving is atomic: write .tmp -> read back and verify -> rotate backups ->
## rename .tmp to world.sav. A verified copy exists at every moment, so a crash
## or kill mid-save never loses the world.
## Loading tries world.sav, then a leftover .tmp (it is the newest copy if the
## app died between rotating backups and the final rename, and it only loads if
## it fully verifies), then each backup.
## Autosaves and saves after a change are written on a worker thread (M22):
## the world is read into a snapshot on the main thread (it must not change
## underneath), then compressed, hashed, written and verified off it; the
## backups rotate and the file is renamed when it is done. Saves when the
## game is paused or closed, and the player's own, are written at once (and
## wait for one under way first). A save that fails (no room left, say)
## leaves the last good one as it is, says so, and is tried again later.
## Loading checks and repairs what it reads (SaveValidator); what it takes
## out is kept aside in the world's quarantine file.
## A world loaded from a fallback because its world.sav was unusable gets that
## file set aside (world.sav.corrupt) at its next save, not rotated into the
## backups in place of a good one (VS.3).
##
## The player's own choices (VS.3, Settings → Save): continue another world,
## start a new one, go back to a backup, erase this one — `open_next` tells
## Main what to open when it next opens a world.

## 1: clock, ids, rng. 2: + world_state (modified chunks, prop differences, start info).
## 3: + loose objects, changed props, player history, water books (M3).
## 4: + people (M4.1). 5: + what the band knows of the world (M4.6).
const SAVE_VERSION := 28
const SAVE_FILE := "world.sav"
const CORRUPT_SUFFIX := ".corrupt"

## What Main opens next instead of the newest world (taken once):
## {"kind": "world", "world_id": …} · {"kind": "new"} ·
## {"kind": "loaded", "loaded": LoadResult} (a backup gone back to).
var open_next: Dictionary = {}

## Last save outcome, for the debug overlay.
var last_save_info: Dictionary = {}

var _session: WorldSession
var _autosave_timer: Timer
## Saves soon after the player changed the world (see note_world_changed).
var _change_timer: Timer
var _first_unsaved_msec := 0
var _last_saved_world_id := ""
var _last_saved_msec := 0
## world_id -> true: its world.sav was unusable when it was loaded.
var _bad_main: Dictionary = {}
## A save being written on a worker thread: its task (-1: none), and what it
## needs and found ({session, world_id, path, tmp, header, raw, reason, started, err, verified}).
var _task := -1
var _writing: Dictionary = {}
## Another save asked for while one is being written: done after it.
var _again: Array = []
## A failed save is tried again after this long.
var _retry_timer: Timer
## Room on the disk wanted beyond the save itself (bytes).
const SPARE_ROOM := 2 * 1024 * 1024
## What loading took out of a world is kept here, beside its saves.
const QUARANTINE_FILE := "quarantine.txt"


class LoadResult:
	extends RefCounted
	var ok := false
	var error := ""
	var world: Dictionary = {}
	var header: Dictionary = {}
	## Which file the world came from ("world.sav", "world.sav.bak1", ...).
	var source := ""


func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = false
	_autosave_timer.timeout.connect(func() -> void: save_current_async(&"autosave"))
	add_child(_autosave_timer)
	_change_timer = Timer.new()
	_change_timer.one_shot = true
	_change_timer.timeout.connect(func() -> void: save_current_async(&"changed"))
	add_child(_change_timer)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	# (A retry saves whatever the last good save was: it is the one that failed.)
	_retry_timer.timeout.connect(func() -> void:
		if _session != null and is_instance_valid(_session) and _session.is_active:
			save_world_async(_session, &"retry"))
	add_child(_retry_timer)
	EventBus.app_paused.connect(func() -> void: save_current(&"app_paused"))
	EventBus.app_quit_requested.connect(func() -> void: save_current(&"quit"))
	EventBus.app_focus_changed.connect(func(has_focus: bool) -> void:
		if not has_focus:
			save_current(&"focus_lost"))


## The session that lifecycle/autosaves write. Pass null to detach.
func attach(session: WorldSession) -> void:
	if _session != null and is_instance_valid(_session):
		if _session.about_to_close.is_connected(_on_session_closing):
			_session.about_to_close.disconnect(_on_session_closing)
		if _session.interactions.intervention_applied.is_connected(_on_intervention):
			_session.interactions.intervention_applied.disconnect(_on_intervention)
	_session = session
	_change_timer.stop()
	_first_unsaved_msec = 0
	if session != null:
		session.about_to_close.connect(_on_session_closing)
		session.interactions.intervention_applied.connect(_on_intervention)
		_autosave_timer.start(Config.save.autosave_interval_s)
	else:
		_autosave_timer.stop()


## The player changed the world. It is saved once they have left it alone for
## Config.save.save_quiet_s — or, if they never do, save_max_wait_s after the
## first unsaved change — so that even a crash loses very little, without a
## save interrupting every touch.
func note_world_changed() -> void:
	if _session == null or not is_instance_valid(_session) or not _session.is_active:
		return
	var now := Time.get_ticks_msec()
	if _first_unsaved_msec == 0:
		_first_unsaved_msec = now
	var waited := (now - _first_unsaved_msec) / 1000.0
	var wait := minf(Config.save.save_quiet_s, Config.save.save_max_wait_s - waited)
	_change_timer.start(maxf(wait, 0.05))


## True while a change is waiting to be saved.
func has_unsaved_change() -> bool:
	return _first_unsaved_msec != 0


## Saves the attached session if there is an active one. Used by lifecycle
## events and autosave; a save that would land within Config.save.min_save_gap_ms
## of the previous successful save of the same world is skipped (returns true:
## the world on disk is already current). save_world() itself always saves.
func save_current(reason: StringName = &"manual") -> bool:
	if _session == null or not is_instance_valid(_session) or not _session.is_active:
		return false
	if _session.world_id == _last_saved_world_id \
			and Time.get_ticks_msec() - _last_saved_msec < Config.save.min_save_gap_ms:
		Log.debug(Log.Category.SAVE, "Save skipped (just saved)", {"reason": reason})
		return true
	return save_world(_session, reason)


## Like save_current, written on a worker thread (autosave, a change settled).
func save_current_async(reason: StringName = &"autosave") -> bool:
	if _session == null or not is_instance_valid(_session) or not _session.is_active:
		return false
	if _session.world_id == _last_saved_world_id \
			and Time.get_ticks_msec() - _last_saved_msec < Config.save.min_save_gap_ms:
		return true
	return save_world_async(_session, reason)


## Saves on a worker thread: the snapshot now, the writing off the main thread
## (see the top). One at a time — asked again meanwhile, it is done after.
func save_world_async(session: WorldSession, reason: StringName = &"autosave") -> bool:
	if _task >= 0:
		_again = [session, reason]
		return true
	var job := _prepare(session, reason)
	if job.is_empty():
		return false
	_writing = job
	_task = WorkerThreadPool.add_task(_write_job.bind(_writing), false, "Save")
	set_process(true)
	return true


## Is a save being written on a worker thread?
func is_writing() -> bool:
	return _task >= 0


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish_writing()
	if _task < 0:
		set_process(false)


## The save being written is done: its file put in place (or its failure told).
func _finish_writing() -> bool:
	if _task < 0:
		return true
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var job := _writing
	_writing = {}
	var ok := _commit(job)
	if not _again.is_empty():
		var next: Array = _again
		_again = []
		if is_instance_valid(next[0]) and (next[0] as WorldSession).is_active:
			save_world_async(next[0], next[1])
	return ok


## (On the worker thread: compress, hash, write, read back — nothing else is touched.)
static func _write_job(job: Dictionary) -> void:
	job["err"] = SaveContainer.write_raw(job["tmp"], job["header"], job["raw"])
	job["verified"] = job["err"] == OK and SaveContainer.read(job["tmp"]).ok


func save_world(session: WorldSession, reason: StringName = &"manual") -> bool:
	# (One under way on the worker thread is finished first: one save at a time.)
	if _task >= 0:
		_finish_writing()
	var job := _prepare(session, reason)
	if job.is_empty():
		return false
	_write_job(job)
	return _commit(job)


## What a save needs, read from the world now: {} if it cannot be made (told).
func _prepare(session: WorldSession, reason: StringName) -> Dictionary:
	var started := Time.get_ticks_usec()
	EventBus.save_started.emit(reason)
	var dir := world_dir(session.world_id)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		_save_failed("cannot create %s (%s)" % [dir, error_string(err)])
		return {}
	var path := dir.path_join(SAVE_FILE)
	var header := {
		"save_version": SAVE_VERSION,
		"world_id": session.world_id,
		"world_seed": session.world_seed,
		"created_unix": session.created_unix,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"game_tick": session.clock.tick,
		"population": session.people.size() if session.people != null else 0,
		"game_version": ProjectSettings.get_setting("application/config/version", "?"),
	}
	var raw := var_to_bytes({"world": session.to_dict()})
	# Room for it (compressed it is smaller — this errs on the safe side).
	var space := room_left(dir)
	if space >= 0 and space < raw.size() + SPARE_ROOM:
		_save_failed("not enough room left (%d bytes free)" % space, true)
		return {}
	return {"session": session, "world_id": session.world_id, "path": path, "tmp": path + ".tmp", "header": header,
		"raw": raw, "reason": reason, "started": started, "err": OK, "verified": false}


## Bytes free where `dir` is (-1: not known). (Tests may pretend.)
var room_left_override := -1
func room_left(dir: String) -> int:
	if room_left_override >= 0:
		return room_left_override
	var access := DirAccess.open(dir)
	return int(access.get_space_left()) if access != null else -1


## The written file put in place: the backups rotated, the .tmp renamed.
func _commit(job: Dictionary) -> bool:
	var err: Error = job["err"]
	if err != OK:
		return _save_failed("write failed (%s)" % error_string(err), true)
	if not bool(job["verified"]):
		return _save_failed("verification failed", true)
	var session: WorldSession = job["session"] if is_instance_valid(job["session"]) else null
	var world_id: String = job["world_id"]
	var path: String = job["path"]
	var tmp: String = job["tmp"]
	var header: Dictionary = job["header"]
	var reason: StringName = job["reason"]
	var started: int = job["started"]

	if _bad_main.has(world_id):
		# (The unusable file is kept aside, and the good backups stay as they are.)
		if FileAccess.file_exists(path):
			DirAccess.rename_absolute(path, path + CORRUPT_SUFFIX)
		_bad_main.erase(world_id)
	else:
		_rotate_backups(path)
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return _save_failed("final rename failed (%s)" % error_string(err), true)

	_last_saved_world_id = world_id
	_last_saved_msec = Time.get_ticks_msec()
	_retry_timer.stop()
	if session != null and session == _session:
		_first_unsaved_msec = 0
		_change_timer.stop()
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	last_save_info = {
		"reason": reason,
		"ms": ms,
		"bytes": FileAccess.get_file_as_bytes(path).size(),
		"unix": header["saved_unix"],
	}
	Log.info(Log.Category.SAVE, "World saved", {"reason": reason, "ms": snappedf(ms, 0.01), "tick": header["game_tick"]})
	EventBus.save_completed.emit(path, ms)
	return true


## world_id of the most recently saved world with a readable header, or "".
func find_latest_world_id() -> String:
	var ids := world_ids_by_recency()
	return ids[0] if not ids.is_empty() else ""


## All worlds with at least one readable header, newest save first. Callers
## should try them in order: a header can be readable while the payload is not.
func world_ids_by_recency() -> PackedStringArray:
	var root := Config.save.save_root
	if not DirAccess.dir_exists_absolute(root):
		return PackedStringArray()
	var entries: Array = [] # [saved_unix, world_id]
	for world_id in DirAccess.get_directories_at(root):
		for file_name in _candidate_files():
			var header := SaveContainer.read_header(world_dir(world_id).path_join(file_name))
			if header.ok:
				entries.append([int(header.header.get("saved_unix", 0)), world_id])
				break
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var ids := PackedStringArray()
	for entry: Array in entries:
		ids.append(entry[1])
	return ids


## Loads a world's data, falling back through backups. Never modifies files.
func load_world(world_id: String) -> LoadResult:
	var result := LoadResult.new()
	var errors := PackedStringArray()
	for file_name in _candidate_files():
		var path := world_dir(world_id).path_join(file_name)
		if not FileAccess.file_exists(path):
			continue
		var read := SaveContainer.read(path)
		if not read.ok:
			if file_name == SAVE_FILE:
				_bad_main[world_id] = true
			errors.append("%s: %s" % [file_name, read.error])
			Log.warn(Log.Category.LOAD, "Save file unusable", {"file": file_name, "error": read.error})
			continue
		var version := int(read.header.get("save_version", 0))
		var migrated := SaveMigrations.migrate(read.data, version, SAVE_VERSION)
		if not migrated.ok:
			errors.append("%s: %s" % [file_name, migrated.error])
			Log.error(Log.Category.LOAD, "Save cannot be migrated", {"file": file_name, "error": migrated.error})
			continue
		var world: Variant = migrated.data.get("world")
		if typeof(world) != TYPE_DICTIONARY:
			errors.append("%s: no world data" % file_name)
			continue
		_check(world_id, world)
		result.ok = true
		result.world = world
		result.header = read.header
		result.source = file_name
		if file_name != SAVE_FILE:
			Log.warn(Log.Category.LOAD, "Loaded world from fallback file", {"file": file_name})
		return result
	result.error = "no usable save for %s" % world_id if errors.is_empty() else "; ".join(errors)
	Log.error(Log.Category.LOAD, "World load failed", {"world_id": world_id, "error": result.error})
	EventBus.load_failed.emit(result.error)
	return result


## One saved file of a world, as it is: that file only, no fallback (a
## backup to go back to). Never modifies files.
func load_file(world_id: String, file_name: String) -> LoadResult:
	var result := LoadResult.new()
	var path := world_dir(world_id).path_join(file_name)
	var read := SaveContainer.read(path)
	if not read.ok:
		result.error = read.error
		return result
	var migrated := SaveMigrations.migrate(read.data, int(read.header.get("save_version", 0)), SAVE_VERSION)
	if not migrated.ok or typeof(migrated.data.get("world")) != TYPE_DICTIONARY:
		result.error = migrated.error if not migrated.ok else "no world data"
		return result
	_check(world_id, migrated.data["world"])
	result.ok = true
	result.world = migrated.data["world"]
	result.header = read.header
	result.source = file_name
	return result


## What is read is checked and repaired (SaveValidator); what had to be taken
## out is kept aside in the world's quarantine file, never simply lost.
func _check(world_id: String, world: Dictionary) -> void:
	var report := SaveValidator.repair(world)
	if int(report["repaired"]) == 0:
		return
	Log.warn(Log.Category.LOAD, "Save repaired", {"world_id": world_id, "repaired": report["repaired"],
		"quarantined": (report["quarantine"] as Array).size()})
	if (report["quarantine"] as Array).is_empty():
		return
	var path := world_dir(world_id).path_join(QUARANTINE_FILE)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("# %s — loaded and repaired: %s" % [Time.get_datetime_string_from_system(), "; ".join(report["notes"])])
	for entry: Dictionary in report["quarantine"]:
		file.store_line(var_to_str(entry).replace("\n", " "))
	file.close()


## Every saved world, the newest save first: [{world_id, seed, saved_unix, game_tick}, …].
func worlds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for world_id in world_ids_by_recency():
		for file_name in _candidate_files():
			var header := SaveContainer.read_header(world_dir(world_id).path_join(file_name))
			if header.ok:
				out.append({"world_id": world_id, "seed": int(header.header.get("world_seed", 0)),
					"saved_unix": int(header.header.get("saved_unix", 0)), "game_tick": int(header.header.get("game_tick", 0))})
				break
	return out


## A world's backups that can be read, the newest first: [{file, saved_unix, game_tick}, …].
func backups(world_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(1, Config.save.backup_count + 1):
		var file_name := "%s.bak%d" % [SAVE_FILE, i]
		var header := SaveContainer.read_header(world_dir(world_id).path_join(file_name))
		if header.ok:
			out.append({"file": file_name, "saved_unix": int(header.header.get("saved_unix", 0)),
				"game_tick": int(header.header.get("game_tick", 0)), "population": int(header.header.get("population", -1))})
	return out


## Erases a world and all its files for good. Returns whether it is gone.
func delete_world(world_id: String) -> bool:
	if world_id == "" or world_id.contains("/") or world_id.contains(".."):
		return false
	var dir := world_dir(world_id)
	if not DirAccess.dir_exists_absolute(dir):
		return true
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	_bad_main.erase(world_id)
	if _last_saved_world_id == world_id:
		_last_saved_world_id = ""
	return DirAccess.remove_absolute(dir) == OK


## What Main is to open next (see open_next), once; {} for the newest world.
func take_open_next() -> Dictionary:
	var plan := open_next
	open_next = {}
	return plan


func world_dir(world_id: String) -> String:
	return Config.save.save_root.path_join(world_id)


## Load preference order (see class comment).
func _candidate_files() -> PackedStringArray:
	var files := PackedStringArray([SAVE_FILE, SAVE_FILE + ".tmp"])
	for i in range(1, Config.save.backup_count + 1):
		files.append("%s.bak%d" % [SAVE_FILE, i])
	return files


## bakN-1 -> bakN ... bak1 -> bak2, world.sav -> bak1. The oldest backup drops off.
func _rotate_backups(path: String) -> void:
	var count := Config.save.backup_count
	for i in range(count, 1, -1):
		var older := "%s.bak%d" % [path, i - 1]
		if FileAccess.file_exists(older):
			DirAccess.rename_absolute(older, "%s.bak%d" % [path, i])
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, path + ".bak1")


func _on_session_closing() -> void:
	save_current(&"world_closed")


func _on_intervention(intervention: Intervention) -> void:
	if intervention.recorded:
		note_world_changed()


## A save that did not happen: the last good one stays as it is; it is said
## (gently: EventBus.save_failed), and — `retry` — tried again later.
func _save_failed(message: String, retry: bool = false) -> bool:
	last_save_info = {"error": message}
	Log.error(Log.Category.SAVE, "Save failed", {"error": message})
	EventBus.save_failed.emit(message)
	if retry and _retry_timer != null and _session != null and is_instance_valid(_session):
		_retry_timer.start(Config.save.retry_after_s)
	return false
