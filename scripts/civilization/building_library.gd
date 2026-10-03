class_name BuildingLibrary
extends RefCounted
## The kinds of building defined in res://data/buildings/ (bible §17.2, M12.1).

const DIR := "res://data/buildings/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> BuildingDef


## Loads every definition in `dir`. Unusable files are skipped and reported in
## `problems`; the game runs with whatever is left.
static func load_from(dir: String = DIR) -> BuildingLibrary:
	var library := BuildingLibrary.new()
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as BuildingDef
		if def == null:
			library.problems.append("%s is not a building" % file)
			continue
		library.add(def)
	if library._defs.is_empty():
		library.problems.append("no buildings found in %s" % dir)
	return library


func add(def: BuildingDef) -> bool:
	var found := def.validate()
	if _defs.has(def.id):
		found.append("%s: defined twice" % def.id)
	problems.append_array(found)
	if not found.is_empty():
		return false
	_defs[def.id] = def
	return true


func get_def(id: StringName) -> BuildingDef:
	return _defs.get(id)


func has_def(id: StringName) -> bool:
	return _defs.has(id)


## The kind of building that stands as this prop kind (null: none).
func of_kind(prop_kind: int) -> BuildingDef:
	for id in ids():
		if (_defs[id] as BuildingDef).prop_kind == prop_kind:
			return _defs[id]
	return null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _defs:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The kinds of building with `tag` ("home", "storage" …).
func with_tag(tag: String) -> Array[BuildingDef]:
	var out: Array[BuildingDef] = []
	for id in ids():
		if (_defs[id] as BuildingDef).has_tag(tag):
			out.append(_defs[id])
	return out
