extends SceneTree
## Headless test runner (bible §31.13, D-03).
##
##   godot --headless --path . -s res://tests/run_tests.gd
##   godot --headless --path . -s res://tests/run_tests.gd -- --filter=save
##
## Options (after `--`):
##   --filter=<text>        run files/tests whose path or name contains <text>
##   --dir=<res://path>     test directory (repeatable; default unit + integration)
##   --test-timeout=<s>     per-test timeout in seconds (default 15)
##   --timeout=<s>          whole-run watchdog in seconds (default 300)
##   --verbose              echo game logs to the console (off by default)
##
## Exit code: 0 all passed · 1 failures · 2 watchdog/abort.
##
## Rules learned the hard way (M0.3/M0.7):
## - This script is compiled before autoloads exist, so test files are load()ed
##   at runtime and autoloads are reached via root.get_node().
## - A runtime script error inside a test does NOT stop the caller, so a Logger
##   records script errors and any error during a test fails that test.

const DEFAULT_DIRS: PackedStringArray = ["res://tests/unit", "res://tests/integration"]
const TEST_SAVE_ROOT := "user://test_run/saves"
const TEST_SETTINGS_PATH := "user://test_run/settings.cfg"
const TEST_RUN_DIR := "user://test_run"


class ErrorCatcher:
	extends Logger
	var _mutex := Mutex.new()
	var script_errors: PackedStringArray = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT and error_type != ERROR_TYPE_SHADER:
			return # push_error()/engine errors are expected in negative tests
		var text := rationale if not rationale.is_empty() else code
		_mutex.lock()
		script_errors.append("%s (%s:%d)" % [text, file.get_file(), line])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var n := script_errors.size()
		_mutex.unlock()
		return n

	func since(index: int) -> PackedStringArray:
		_mutex.lock()
		var out := script_errors.slice(index)
		_mutex.unlock()
		return out


var _catcher := ErrorCatcher.new()
var _filter := ""
var _dirs: PackedStringArray = []
var _test_timeout_s := 15.0
var _verbose := false
var _passed := 0
var _failed := 0
var _failure_lines: PackedStringArray = []


func _initialize() -> void:
	_parse_args()
	OS.add_logger(_catcher)
	await process_frame # autoloads are ready from here on
	await _run()


func _parse_args() -> void:
	var watchdog_s := 300.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.get_slice("=", 1)
		elif arg.begins_with("--dir="):
			_dirs.append(arg.get_slice("=", 1))
		elif arg.begins_with("--test-timeout="):
			_test_timeout_s = float(arg.get_slice("=", 1))
		elif arg == "--verbose":
			_verbose = true
		elif arg.begins_with("--timeout="):
			watchdog_s = float(arg.get_slice("=", 1))
	if _dirs.is_empty():
		_dirs = DEFAULT_DIRS
	create_timer(watchdog_s).timeout.connect(func() -> void:
		print("\nWATCHDOG: test run exceeded %d s — aborting" % watchdog_s)
		quit(2))


func _run() -> void:
	var started := Time.get_ticks_msec()
	_isolate_environment()
	var files := _discover()
	print("Running %d test file(s)%s\n" % [files.size(), "" if _filter.is_empty() else " (filter: %s)" % _filter])
	for file in files:
		await _run_file(file)
	_restore_environment()

	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	if _failed > 0:
		print("FAILURES:")
		for line in _failure_lines:
			print("  " + line)
		print("")
	print("SUMMARY: %d passed, %d failed in %.1f s" % [_passed, _failed, secs])
	quit(0 if _failed == 0 else 1)


func _run_file(file: String) -> void:
	var errors_before := _catcher.count()
	var script := load(file) as GDScript
	if script == null or not script.can_instantiate():
		_record_failure(file, "<load>", ["script failed to load/compile"] + Array(_catcher.since(errors_before)))
		return
	var instance: Variant = script.new()
	var tc := instance as TestCase
	if tc == null:
		_record_failure(file, "<load>", ["does not extend TestCase"])
		return

	var file_matches := _filter.is_empty() or file.contains(_filter)
	var methods: Array[String] = []
	for m: Dictionary in script.get_script_method_list():
		var method_name: String = m["name"]
		if method_name.begins_with("test_") and not methods.has(method_name):
			if file_matches or method_name.contains(_filter):
				methods.append(method_name)
	if methods.is_empty():
		tc.free()
		return

	print(file)
	tc.name = file.get_file().get_basename()
	root.add_child(tc)
	await tc.before_all()
	for method_name in methods:
		await _run_test(file, tc, method_name)
	await tc.after_all()
	tc.queue_free()
	await process_frame


func _run_test(file: String, tc: TestCase, method_name: String) -> void:
	tc._begin_test(method_name)
	var errors_before := _catcher.count()
	var state := {"done": false}
	var started := Time.get_ticks_msec()
	_invoke(tc, method_name, state) # not awaited: we poll so a stuck test can time out
	var deadline := started + int(_test_timeout_s * 1000.0)
	while not state["done"] and Time.get_ticks_msec() < deadline:
		await process_frame

	var problems := Array(tc._take_failures())
	for err in _catcher.since(errors_before):
		problems.append("script error: " + err)
	if not state["done"]:
		problems.append("timed out after %.0f s" % _test_timeout_s)
	var ms := Time.get_ticks_msec() - started
	if problems.is_empty():
		_passed += 1
		print("  PASS %s (%d ms)" % [method_name, ms])
	else:
		print("  FAIL %s (%d ms)" % [method_name, ms])
		for p in problems:
			print("       " + str(p))
		_record_failure(file, method_name, problems)


func _invoke(tc: TestCase, method_name: String, state: Dictionary) -> void:
	await tc.before_each()
	await tc.call(method_name)
	await tc.after_each()
	state["done"] = true


func _record_failure(file: String, test_name: String, problems: Array) -> void:
	if test_name == "<load>":
		print(file)
		print("  FAIL <load>")
		for p in problems:
			print("       " + str(p))
	_failed += 1
	_failure_lines.append("%s :: %s — %s" % [file.get_file(), test_name, str(problems[0]) if not problems.is_empty() else "?"])


func _discover() -> PackedStringArray:
	var found := PackedStringArray()
	for dir in _dirs:
		_collect(dir, found)
	found.sort()
	return found


func _collect(dir: String, out: PackedStringArray) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)


## Keeps tests away from the player's real saves and settings.
func _isolate_environment() -> void:
	root.get_node("Log").console_output = _verbose
	TestCase.remove_dir_recursive(TEST_RUN_DIR)
	DirAccess.make_dir_recursive_absolute(TEST_SAVE_ROOT)
	root.get_node("Config").save.save_root = TEST_SAVE_ROOT
	root.get_node("Settings").use_path(TEST_SETTINGS_PATH)


func _restore_environment() -> void:
	var save_manager := root.get_node("SaveManager")
	save_manager.attach(null)
	if current_scene != null:
		unload_current_scene()
	TestCase.remove_dir_recursive(TEST_RUN_DIR)
