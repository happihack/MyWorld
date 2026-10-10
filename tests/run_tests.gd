extends SceneTree
## Headless test runner (bible §31.13, D-03).
##
##   godot --headless --path . -s res://tests/run_tests.gd
##   godot --headless --path . -s res://tests/run_tests.gd -- --filter=save
##
## Options (after `--`):
##   --filter=<text>        run files/tests whose path or name contains <text>
##   --dir=<res://path>     test directory (repeatable; default unit + integration)
##   --shard=<i>/<n>        run only the i-th of n slices of the test files
##                          (1-based; lets several processes split the suite)
##   --test-timeout=<s>     per-test timeout in seconds (default 30)
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
## Each process gets its own scratch directory, so parallel runs (shards, CI
## jobs, two terminals) can never delete or overwrite each other's files.
const TEST_RUN_DIR_PREFIX := "user://test_run_"


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
var _test_timeout_s := 30.0
var _verbose := false
var _shard_index := 1
var _shard_count := 1
var _run_dir := ""
var _passed := 0
var _failed := 0
var _failure_lines: PackedStringArray = []


func _initialize() -> void:
	_parse_args()
	OS.add_logger(_catcher)
	await process_frame # autoloads are ready from here on
	# With the game's own scripts not compiling, tests would run against
	# half a game (objects that are not what they say, paths that come back
	# empty): nothing is run at all.
	for core: String in ["res://scripts/simulation/world_session.gd", "res://scripts/core/main.gd"]:
		var script := load(core) as GDScript
		if script == null or not script.can_instantiate():
			print("FAILURES:
  the game does not compile (%s) - no tests were run" % core)
			print("SUMMARY: 0 passed, 1 failed in 0.0 s")
			quit(1)
			return
	# ...and neither if a world cannot even be made (a mistake that only
	# shows when the code runs).
	var probe: Node = (load("res://scripts/simulation/world_session.gd") as GDScript).new()
	var whole: bool = probe.get("simulation") != null and probe.get("interactions") != null
	probe.free()
	if not whole:
		print("FAILURES:
  a world cannot be made (WorldSession._init fails) - no tests were run")
		print("SUMMARY: 0 passed, 1 failed in 0.0 s")
		quit(1)
		return
	await _run()


func _parse_args() -> void:
	var watchdog_s := 600.0 # (in the scene's time, which runs behind the clock on the wall while tests work)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.get_slice("=", 1)
		elif arg.begins_with("--dir="):
			_dirs.append(arg.get_slice("=", 1))
		elif arg.begins_with("--test-timeout="):
			_test_timeout_s = float(arg.get_slice("=", 1))
		elif arg.begins_with("--shard="):
			var parts := arg.get_slice("=", 1).split("/")
			if parts.size() == 2 and int(parts[1]) >= 1 and int(parts[0]) >= 1 and int(parts[0]) <= int(parts[1]):
				_shard_index = int(parts[0])
				_shard_count = int(parts[1])
			else:
				print("Ignoring invalid --shard value: %s" % arg)
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
	var notes := PackedStringArray()
	if not _filter.is_empty():
		notes.append("filter: %s" % _filter)
	if _shard_count > 1:
		notes.append("shard %d/%d" % [_shard_index, _shard_count])
	print("Running %d test file(s)%s\n" % [files.size(), "" if notes.is_empty() else " (%s)" % ", ".join(notes)])
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
	if _shard_count <= 1:
		return found
	var slice := PackedStringArray()
	for i in found.size():
		if i % _shard_count == _shard_index - 1:
			slice.append(found[i])
	return slice


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
	_run_dir = "%s%d" % [TEST_RUN_DIR_PREFIX, OS.get_process_id()]
	TestCase.remove_dir_recursive(_run_dir)
	var save_root := _run_dir.path_join("saves")
	DirAccess.make_dir_recursive_absolute(save_root)
	root.get_node("Config").save.save_root = save_root
	root.get_node("Config").interaction.first_opening = false # (test_first_opening turns it on)
	# The tests' worlds begin with the band they were written for (6–8 in 2–3 households);
	# the game's own (people_config) is checked by test_config, test_starting_band and the soaks.
	var people: Resource = root.get_node("Config").people
	people.band_min_people = 6
	people.band_max_people = 8
	people.band_min_households = 2
	people.band_max_households = 3
	# (And a storehouse from 10, as before: these bands of 6–8 would otherwise
	# be off building one in the middle of what each test watches. The game's
	# own — from 6 — is checked by test_progression.)
	root.get_node("Config").construction.first_store_from = 10
	root.get_node("Settings").use_path(_run_dir.path_join("settings.cfg"))


func _restore_environment() -> void:
	var save_manager := root.get_node("SaveManager")
	save_manager.attach(null)
	if current_scene != null:
		unload_current_scene()
	TestCase.remove_dir_recursive(_run_dir)
