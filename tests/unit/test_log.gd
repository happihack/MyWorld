extends TestCase


func test_ring_buffer_keeps_latest_line_with_category() -> void:
	Log.info(Log.Category.WORLD, "unit-test info line", {"a": 1})
	var recent := Log.get_recent(3)
	assert_has(recent[-1], "unit-test info line")
	assert_has(recent[-1], "WORLD")
	assert_has(recent[-1], "\"a\": 1")


func test_trace_is_filtered_in_debug_builds() -> void:
	Log.trace(Log.Category.WORLD, "unit-test trace line")
	assert_false("\n".join(Log.get_recent()).contains("unit-test trace line"))


func test_ring_buffer_is_bounded() -> void:
	for i in Log.RING_SIZE + 25:
		Log.debug(Log.Category.CORE, "fill %d" % i)
	assert_eq(Log.get_recent().size(), Log.RING_SIZE)


func test_file_sink_written() -> void:
	Log.info(Log.Category.CORE, "unit-test file line")
	Log.flush()
	var path := Log.current_log_path()
	assert_ne(path, "")
	assert_has(FileAccess.get_file_as_string(path), "unit-test file line")
