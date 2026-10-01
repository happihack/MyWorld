class_name SaveMigrations
extends RefCounted
## Upgrades save data written by older game versions (bible §31.9).
##
## Every change to an already-saved structure must:
##   1. bump SaveManager.SAVE_VERSION,
##   2. add a step here: STEPS[old_version] = Callable(data) -> Dictionary
##      returning the data in old_version + 1 format,
##   3. add a fixture save of the old version under tests/fixtures/ plus a test.
## No steps exist yet: version 1 is the first format.

static var STEPS: Dictionary = {} # int from_version -> Callable


class Result:
	extends RefCounted
	var ok := false
	var error := ""
	var data: Dictionary = {}


static func migrate(data: Dictionary, from_version: int, to_version: int, steps: Dictionary = STEPS) -> Result:
	var result := Result.new()
	if from_version > to_version:
		result.error = "save version %d is newer than this game supports (%d)" % [from_version, to_version]
		return result
	if from_version < 1:
		result.error = "invalid save version %d" % from_version
		return result
	var current := data
	for version in range(from_version, to_version):
		if not steps.has(version):
			result.error = "no migration from save version %d" % version
			return result
		var step: Callable = steps[version]
		var next: Variant = step.call(current.duplicate(true))
		if typeof(next) != TYPE_DICTIONARY:
			result.error = "migration from version %d failed" % version
			return result
		current = next
	result.ok = true
	result.data = current
	return result
