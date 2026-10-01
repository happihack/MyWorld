class_name ActivityLibrary
extends RefCounted
## The activities defined in res://data/activities/ (bible §13.4).

const DIR := "res://data/activities/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> ActivityDef
var _order: Array[StringName] = []
# For ceiling(): the most that can speak for any activity.
var _most_without_needs := 0.0
var _most_need_weight := 0.0
var _most_hour := 1.0


static func load_from(dir: String = DIR) -> ActivityLibrary:
	var library := ActivityLibrary.new()
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as ActivityDef
		if def == null:
			library._problem("%s is not an activity" % file)
			continue
		library.add(def)
	if library._defs.is_empty():
		library._problem("no activities found in %s" % dir)
	return library


func add(def: ActivityDef) -> bool:
	var found := def.validate()
	if _defs.has(def.id):
		found.append("%s: defined twice" % def.id)
	for problem in found:
		_problem(problem)
	if not found.is_empty():
		return false
	_defs[def.id] = def
	_order.append(def.id)
	var nature := def.base
	for axis_name: Variant in def.trait_weights:
		nature += absf(float(def.trait_weights[axis_name])) * ActivityDef.TRAIT_SCALE
	_most_without_needs = maxf(_most_without_needs, nature)
	var weights := 0.0
	for need_name: Variant in def.need_weights:
		weights += maxf(float(def.need_weights[need_name]), 0.0)
	_most_need_weight = maxf(_most_need_weight, weights)
	for factor in def.hours:
		_most_hour = maxf(_most_hour, factor)
	_order.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return true


func size() -> int:
	return _defs.size()


func get_def(id: StringName) -> ActivityDef:
	return _defs.get(id)


## The highest score any activity could have for someone whose loudest need
## speaks with `loudest` (0 … 1; see ActivityDef.voice) — whatever their
## nature and whatever the hour. If that is not enough to make them drop
## what they are doing, there is no need to work out the scores at all.
func ceiling(loudest: float) -> float:
	return (_most_without_needs + _most_need_weight * loudest) * _most_hour


## All ids, sorted (nothing depends on the order of files).
func ids() -> Array[StringName]:
	return _order


func _problem(message: String) -> void:
	problems.append(message)
	Log.error(Log.Category.AI, "Activity problem: " + message)
