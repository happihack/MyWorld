class_name ActivityLibrary
extends RefCounted
## The activities defined in res://data/activities/ (bible §13.4).

const DIR := "res://data/activities/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> ActivityDef
var _order: Array[StringName] = []


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
	_order.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return true


func size() -> int:
	return _defs.size()


func get_def(id: StringName) -> ActivityDef:
	return _defs.get(id)


## All ids, sorted (nothing depends on the order of files).
func ids() -> Array[StringName]:
	return _order


func _problem(message: String) -> void:
	problems.append(message)
	Log.error(Log.Category.AI, "Activity problem: " + message)
