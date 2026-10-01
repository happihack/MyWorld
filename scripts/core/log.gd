extends Node
## Autoload "Log": structured, categorized logging (bible §31.10).
##
## Usage: Log.info(Log.Category.WORLD, "Chunk generated", {"coord": coord})
## - Debug builds log DEBUG and above; release builds WARN and above.
## - Keeps a ring buffer of recent lines for the debug panel / bug reports.
## - Writes to user://logs/, rotating old files.
## Thread-safe: worker threads (e.g. save writer) may log.

signal line_logged(level: Level, category: Category, text: String)

enum Level { TRACE, DEBUG, INFO, WARN, ERROR }
enum Category { CORE, WORLD, SIM, PLAYER, AI, ENV, HISTORY, SAVE, LOAD, SENSOR, UI, PERFORMANCE, ERROR }

const LOG_DIR := "user://logs"
const MAX_LOG_FILES := 5
const RING_SIZE := 500

var min_level: Level = Level.DEBUG
var file_logging_enabled := true
## Echo to the console/debugger (push_error/push_warning/print). The test runner
## turns this off so expected errors in negative tests don't flood its output;
## the ring buffer and log file still receive everything.
var console_output := true

var _ring: PackedStringArray = []
var _file: FileAccess
var _mutex := Mutex.new()


func _init() -> void:
	min_level = Level.DEBUG if OS.is_debug_build() else Level.WARN
	_open_log_file()


func trace(category: Category, message: String, data: Dictionary = {}) -> void:
	write(Level.TRACE, category, message, data)


func debug(category: Category, message: String, data: Dictionary = {}) -> void:
	write(Level.DEBUG, category, message, data)


func info(category: Category, message: String, data: Dictionary = {}) -> void:
	write(Level.INFO, category, message, data)


func warn(category: Category, message: String, data: Dictionary = {}) -> void:
	write(Level.WARN, category, message, data)


func error(category: Category, message: String, data: Dictionary = {}) -> void:
	write(Level.ERROR, category, message, data)


func write(level: Level, category: Category, message: String, data: Dictionary = {}) -> void:
	if level < min_level:
		return
	var text := _format(level, category, message, data)

	_mutex.lock()
	_ring.append(text)
	if _ring.size() > RING_SIZE:
		_ring = _ring.slice(_ring.size() - RING_SIZE)
	if _file != null:
		_file.store_line(text)
		if level >= Level.WARN:
			_file.flush()
	_mutex.unlock()

	if console_output:
		match level:
			Level.ERROR:
				push_error(text)
			Level.WARN:
				push_warning(text)
			_:
				print(text)

	# Signals must be emitted from the main thread.
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		line_logged.emit(level, category, text)


## Most recent lines, oldest first.
func get_recent(count: int = RING_SIZE) -> PackedStringArray:
	_mutex.lock()
	var start := maxi(0, _ring.size() - count)
	var lines := _ring.slice(start)
	_mutex.unlock()
	return lines


func flush() -> void:
	_mutex.lock()
	if _file != null:
		_file.flush()
	_mutex.unlock()


func current_log_path() -> String:
	return _file.get_path() if _file != null else ""


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			flush()
		NOTIFICATION_PREDELETE:
			if _file != null:
				_file.close()
				_file = null


func _format(level: Level, category: Category, message: String, data: Dictionary) -> String:
	var wall := Time.get_time_string_from_system()
	var uptime := Time.get_ticks_msec() / 1000.0
	var line := "[%s +%.3f] %-5s %-11s %s" % [wall, uptime, Level.keys()[level], Category.keys()[category], message]
	if not data.is_empty():
		line += " " + str(data)
	return line


func _open_log_file() -> void:
	if not file_logging_enabled:
		return
	var err := DirAccess.make_dir_recursive_absolute(LOG_DIR)
	if err != OK:
		push_warning("Log: cannot create %s (%s)" % [LOG_DIR, error_string(err)])
		return
	_rotate_old_files()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/wiab_%s.log" % [LOG_DIR, stamp]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("Log: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	_file.store_line("# My World in a Box %s | Godot %s | %s | debug=%s" % [
		ProjectSettings.get_setting("application/config/version", "?"),
		Engine.get_version_info().string,
		OS.get_name(),
		OS.is_debug_build(),
	])


## Keep at most MAX_LOG_FILES - 1 old logs so the new one makes MAX_LOG_FILES.
func _rotate_old_files() -> void:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(LOG_DIR):
		if f.begins_with("wiab_") and f.ends_with(".log"):
			files.append(f)
	files.sort() # timestamped names sort chronologically
	while files.size() >= MAX_LOG_FILES:
		DirAccess.remove_absolute("%s/%s" % [LOG_DIR, files.pop_front()])
