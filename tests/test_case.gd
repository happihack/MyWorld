class_name TestCase
extends Node
## Base class for tests run by tests/run_tests.gd (bible §31.13).
##
## Write `func test_something() -> void:` methods (they may `await`). Optional
## hooks: before_all / after_all / before_each / after_each (may also await).
## A test fails on any failed assertion OR any script error raised while it runs
## (the runner catches those through a Logger).
##
## Tests are added to the SceneTree root, so get_tree() and autoloads work.
## Saves and settings are redirected to isolated locations by the runner.

var _current_test := ""
var _failures: PackedStringArray = []


func before_all() -> void:
	pass


func after_all() -> void:
	pass


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- assertions --------------------------------------------------------------

func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		_fail("expected true", message)


func assert_false(condition: bool, message: String = "") -> void:
	if condition:
		_fail("expected false", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if not _equal(actual, expected):
		_fail("expected %s, got %s" % [_repr(expected), _repr(actual)], message)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	if _equal(actual, unexpected):
		_fail("did not expect %s" % _repr(unexpected), message)


func assert_near(actual: float, expected: float, epsilon: float = 0.0001, message: String = "") -> void:
	if absf(actual - expected) > epsilon:
		_fail("expected %s ± %s, got %s" % [expected, epsilon, actual], message)


func assert_null(value: Variant, message: String = "") -> void:
	if value != null:
		_fail("expected null, got %s" % _repr(value), message)


func assert_not_null(value: Variant, message: String = "") -> void:
	if value == null:
		_fail("expected non-null", message)


func assert_has(container: Variant, item: Variant, message: String = "") -> void:
	var found := false
	match typeof(container):
		TYPE_STRING, TYPE_STRING_NAME:
			found = String(container).contains(str(item))
		TYPE_DICTIONARY:
			found = (container as Dictionary).has(item)
		_:
			found = item in container
	if not found:
		_fail("%s does not contain %s" % [_repr(container), _repr(item)], message)


func fail(message: String) -> void:
	_fail("failed", message)


# --- helpers for tests ---------------------------------------------------------

## Waits n rendered frames.
func wait_frames(n: int = 1) -> void:
	for i in n:
		await get_tree().process_frame


func wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits until this much REAL time has passed. Scene timers count frame deltas,
## so after a long frame (e.g. world generation) they can fire early; use this
## when the code under test measures real time (Time.get_ticks_msec()).
func wait_real_ms(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## Recursively deletes a user:// directory (test cleanup only).
## Tests only ever write, change or delete things in the user data directory
## (their own run directory there). A path anywhere else — the project
## itself, if something upstream came back empty — is refused.
static func is_test_path(path: String) -> bool:
	if path.begins_with("user://") and not path.contains(".."):
		return true
	var user_dir := OS.get_user_data_dir().replace("\\", "/")
	var plain := path.replace("\\", "/")
	if user_dir != "" and plain.begins_with(user_dir + "/") and not plain.contains(".."):
		return true
	push_error("Test helper refused a path outside the user data directory: '%s'" % path)
	return false


static func remove_dir_recursive(dir_path: String) -> void:
	if not is_test_path(dir_path):
		return
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for f in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		remove_dir_recursive(dir_path.path_join(d))
	DirAccess.remove_absolute(dir_path)


static func write_bytes(file_path: String, bytes: PackedByteArray) -> void:
	if not is_test_path(file_path):
		return
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


## Flips all bits of the byte `offset_from_end` bytes before the end of a file.
static func corrupt_byte(file_path: String, offset_from_end: int = 2) -> void:
	if not is_test_path(file_path):
		return
	var bytes := FileAccess.get_file_as_bytes(file_path)
	var i := bytes.size() - offset_from_end
	bytes[i] = bytes[i] ^ 0xFF
	write_bytes(file_path, bytes)


# --- runner interface ------------------------------------------------------------

func _begin_test(test_name: String) -> void:
	_current_test = test_name
	_failures = PackedStringArray()


func _take_failures() -> PackedStringArray:
	var f := _failures
	_failures = PackedStringArray()
	return f


func _fail(what: String, message: String) -> void:
	var text := what if message.is_empty() else "%s — %s" % [message, what]
	_failures.append("%s (%s)" % [text, _caller_location()])


func _caller_location() -> String:
	for frame: Dictionary in get_stack():
		var source := String(frame.get("source", ""))
		if not source.ends_with("test_case.gd"):
			return "%s:%d" % [source.get_file(), frame.get("line", 0)]
	return "?"


static func _equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		# Allow int/float comparisons and String/StringName comparisons.
		var numeric := [TYPE_INT, TYPE_FLOAT]
		var stringy := [TYPE_STRING, TYPE_STRING_NAME]
		if typeof(a) in numeric and typeof(b) in numeric:
			return a == b
		if typeof(a) in stringy and typeof(b) in stringy:
			return String(a) == String(b)
		return false
	return a == b


static func _repr(value: Variant) -> String:
	var text := var_to_str(value) if typeof(value) != TYPE_OBJECT else str(value)
	return text if text.length() <= 200 else text.substr(0, 200) + "…"
