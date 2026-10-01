extends TestCase
## Runner self-test. Run with:
##   godot --headless --path . -s res://tests/run_tests.gd -- --dir=res://tests/fixtures/runner_selftest --test-timeout=2
## Expected: 3 passed, 4 failed (exactly the tests named *_should_fail).

var hooks: Array[String] = []


func before_each() -> void:
	hooks.append("before")


func test_sync_pass() -> void:
	assert_eq(1 + 1, 2)
	assert_eq(2, 2.0, "int/float compare equal")
	assert_eq(&"a", "a", "StringName/String compare equal")


func test_async_pass() -> void:
	await wait_frames(2)
	assert_true(hooks.size() >= 1, "before_each ran")


func test_hooks_ran_each_time() -> void:
	assert_eq(hooks.size(), 3, "before_each ran once per test so far")


func test_assertion_should_fail() -> void:
	assert_eq([1, 2], [1, 3])


func test_script_error_should_fail() -> void:
	var d := {}
	var _x: int = d["missing"] # runtime error: the runner must catch it


func test_async_script_error_should_fail() -> void:
	await wait_frames(1)
	var arr: Array = []
	var _y: int = arr[5]


func test_timeout_should_fail() -> void:
	await wait_seconds(30.0)
