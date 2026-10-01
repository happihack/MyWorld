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


# --- 2 -> 3 -----------------------------------------------------------------------------------

func _v2(state: Dictionary) -> Dictionary:
	return {"world": {"seed": 5, "world_state": state}}


func test_v3_gives_the_removed_rocks_to_the_loose_objects() -> void:
	var removed := PackedInt64Array([11, 12, 13])
	var m := SaveMigrations.migrate(_v2({"world": {}, "props": {"removed": removed, "added": []}, "start": {}}), 2, 3)
	assert_true(m.ok, m.error)
	var state: Dictionary = m.data["world"]["world_state"]
	assert_eq(state["loose"]["removed"], removed)
	assert_eq(state["loose"]["objects"], [])
	assert_eq(state["props"]["changed"], [])
	assert_eq(state["history"], {})
	assert_eq(state["water"], {})
	# The lists are separate from now on.
	(state["loose"]["removed"] as PackedInt64Array).append(99)
	assert_eq((state["props"]["removed"] as PackedInt64Array).size(), 3)


func test_v3_keeps_what_later_version_2_builds_already_wrote() -> void:
	# Builds between M3.1 and M3.6 wrote these parts under version 2.
	var loose := {"removed": PackedInt64Array([7]), "objects": [{"id": 3}]}
	var history := {"counts": {"touch": 2}}
	var changed := [{"id": 4}]
	var m := SaveMigrations.migrate(_v2({
		"world": {}, "props": {"removed": PackedInt64Array([7, 8]), "added": [], "changed": changed},
		"start": {}, "loose": loose, "history": history,
	}), 2, 3)
	var state: Dictionary = m.data["world"]["world_state"]
	assert_eq(state["loose"], loose)
	assert_eq(state["history"], history)
	assert_eq(state["props"]["changed"], changed)
	assert_eq(state["water"], {})


func test_v3_leaves_saves_without_a_world_alone() -> void:
	# A migrated version 1 has no world content: it is rebuilt from the seed.
	assert_eq(SaveMigrations.migrate(_v2({}), 2, 3).data, _v2({}))
	assert_eq(SaveMigrations.migrate({"world": "broken"}, 2, 3).data, {"world": "broken"})
	assert_eq(SaveMigrations.migrate({}, 2, 3).data, {})
	var odd := _v2({"world": {}, "props": "broken", "start": {}})
	assert_true(SaveMigrations.migrate(odd, 2, 3).ok, "damaged parts are for the loader to judge")
	# The whole chain from version 1.
	var m := SaveMigrations.migrate({"world": {"seed": 5}}, 1, 3)
	assert_true(m.ok, m.error)


# --- 3 -> 4 -----------------------------------------------------------------------------------

func test_v4_marks_worlds_from_before_people() -> void:
	var m := SaveMigrations.migrate(_v2({"world": {}, "props": {}, "start": {}, "loose": {}}), 3, 4)
	assert_true(m.ok, m.error)
	assert_eq(m.data["world"]["world_state"]["people"], {}, "nobody has arrived yet")
	# People that are already there are left alone.
	var people := {"persons": [{"id": 9}]}
	assert_eq(SaveMigrations.migrate(_v2({"world": {}, "people": people}), 3, 4).data["world"]["world_state"]["people"], people)
	# No world content, nothing to add.
	assert_eq(SaveMigrations.migrate(_v2({}), 3, 4).data, _v2({}))
	assert_eq(SaveMigrations.migrate({"world": 3}, 3, 4).data, {"world": 3})
	# The whole chain.
	var chain := SaveMigrations.migrate(_v2({"world": {}, "props": {"removed": PackedInt64Array()}, "start": {}}), 2, SaveManager.SAVE_VERSION)
	assert_true(chain.ok, chain.error)
	assert_true(chain.data["world"]["world_state"].has("people"))
