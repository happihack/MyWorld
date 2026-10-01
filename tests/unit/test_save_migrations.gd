extends TestCase


func test_same_version_passes_through() -> void:
	var m := SaveMigrations.migrate({"x": 1}, 1, 1)
	assert_true(m.ok)
	assert_eq(m.data, {"x": 1})


func test_newer_and_invalid_versions_refused() -> void:
	assert_has(SaveMigrations.migrate({}, 5, 1).error, "newer")
	assert_false(SaveMigrations.migrate({}, 0, 1).ok)


func test_missing_step_refused() -> void:
	assert_has(SaveMigrations.migrate({}, 1, 2, {}).error, "no migration")


func test_chain_applies_in_order_without_mutating_input() -> void:
	var steps := {
		1: func(d: Dictionary) -> Dictionary:
			d["added"] = true
			return d,
		2: func(d: Dictionary) -> Dictionary:
			d["renamed"] = d["x"]
			d.erase("x")
			return d,
	}
	var original := {"x": 4}
	var m := SaveMigrations.migrate(original, 1, 3, steps)
	assert_true(m.ok, m.error)
	assert_eq(m.data, {"added": true, "renamed": 4})
	assert_eq(original, {"x": 4})


func test_bad_step_result_refused() -> void:
	assert_false(SaveMigrations.migrate({}, 1, 2, {1: func(_d: Dictionary) -> Variant: return null}).ok)


func test_every_version_below_current_has_a_step() -> void:
	# Guards SAVE_VERSION bumps: each older version needs a migration step.
	for v in range(1, SaveManager.SAVE_VERSION):
		assert_true(SaveMigrations.STEPS.has(v), "missing migration step from version %d" % v)
