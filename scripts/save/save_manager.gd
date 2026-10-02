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
## Saves are synchronous for now; threaded writes arrive in M22.

## 1: clock, ids, rng. 2: + world_state (modified chunks, prop differences, start info).
## 3: + loose objects, changed props, player history, water books (M3).
## 4: + people (M4.1). 5: + what the band knows of the world (M4.6).
const SAVE_VERSION := 14
const SAVE_FILE := "world.sav"

## Last save outcome, for the debug overlay.
var last_save_info: Dictionary = {}

var _session: WorldSession
var _autosave_timer: Timer
## Saves soon after the player changed the world (see note_world_changed).
var _change_timer: Timer
var _first_unsaved_msec := 0
var _last_saved_world_id := ""
var _last_saved_msec := 0


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
	_autosave_timer.timeout.connect(func() -> void: save_current(&"autosave"))
	add_child(_autosave_timer)
	_change_timer = Timer.new()
	_change_timer.one_shot = true
	_change_timer.timeout.connect(func() -> void: save_current(&"changed"))
	add_child(_change_timer)
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


func save_world(session: WorldSession, reason: StringName = &"manual") -> bool:
	var started := Time.get_ticks_usec()
	EventBus.save_started.emit(reason)
	var dir := world_dir(session.world_id)
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return _save_failed("cannot create %s (%s)" % [dir, error_string(err)])

	var path := dir.path_join(SAVE_FILE)
	var tmp := path + ".tmp"
	var header := {
		"save_version": SAVE_VERSION,
		"world_id": session.world_id,
		"world_seed": session.world_seed,
		"created_unix": session.created_unix,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"game_tick": session.clock.tick,
		"game_version": ProjectSettings.get_setting("application/config/version", "?"),
	}
	err = SaveContainer.write(tmp, header, {"world": session.to_dict()})
	if err != OK:
		return _save_failed("write failed (%s)" % error_string(err))
	var verify := SaveContainer.read(tmp)
	if not verify.ok:
		return _save_failed("verification failed: " + verify.error)

	_rotate_backups(path)
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return _save_failed("final rename failed (%s)" % error_string(err))

	_last_saved_world_id = session.world_id
	_last_saved_msec = Time.get_ticks_msec()
	if session == _session:
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


func _save_failed(message: String) -> bool:
	last_save_info = {"error": message}
	Log.error(Log.Category.SAVE, "Save failed", {"error": message})
	EventBus.save_failed.emit(message)
	return false
