class_name ResourceLibrary
extends RefCounted
## The resources defined in res://data/resources/ (bible §11).

const DIR := "res://data/resources/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> ResourceDef
var _order: Array[StringName] = []


## Loads every definition in `dir`. Unusable files are skipped and reported in
## `problems`; the game runs with whatever is left.
static func load_from(dir: String = DIR) -> ResourceLibrary:
	var library := ResourceLibrary.new()
	# list_directory sees resources as they were authored, also in an exported game.
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as ResourceDef
		if def == null:
			library._problem("%s is not a resource definition" % file)
			continue
		library.add(def)
	if library._defs.is_empty():
		library._problem("no resources found in %s" % dir)
	return library


## Adds a definition. False (with a problem noted) if it is unusable.
func add(def: ResourceDef) -> bool:
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


func has_def(id: StringName) -> bool:
	return _defs.has(id)


func get_def(id: StringName) -> ResourceDef:
	return _defs.get(id)


## All ids, sorted (so that nothing depends on the order of files).
func ids() -> Array[StringName]:
	return _order


## The ids of one category, sorted.
func of_category(category: ResourceDef.Category) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in _order:
		if (_defs[id] as ResourceDef).category == category:
			out.append(id)
	return out


func _problem(message: String) -> void:
	problems.append(message)
	Log.error(Log.Category.SIM, "Resource problem: " + message)
