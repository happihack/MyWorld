class_name TechnologyLibrary
extends RefCounted
## The technologies defined in res://data/technologies/ (bible §18.2, M16.2).

const DIR := "res://data/technologies/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> TechnologyDef


## Loads every definition in `dir`. Unusable files are skipped and reported in
## `problems`; the game runs with whatever is left.
static func load_from(dir: String = DIR) -> TechnologyLibrary:
	var library := TechnologyLibrary.new()
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as TechnologyDef
		if def == null:
			library.problems.append("%s is not a technology" % file)
			continue
		library.add(def)
	if library._defs.is_empty():
		library.problems.append("no technologies found in %s" % dir)
	library.problems.append_array(library.check_chain())
	return library


func add(def: TechnologyDef) -> bool:
	var found := def.validate()
	if _defs.has(def.id):
		found.append("%s: defined twice" % def.id)
	problems.append_array(found)
	if not found.is_empty():
		return false
	_defs[def.id] = def
	return true


## Every prerequisite defined, and no technology its own ancestor.
func check_chain() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids():
		for before in get_def(id).prerequisites:
			if not _defs.has(StringName(before)):
				out.append("%s: requires %s, which is not defined" % [id, before])
		if _ancestors(id, {}).has(id):
			out.append("%s: requires itself, by way of others" % id)
	return out


func _ancestors(id: StringName, seen: Dictionary) -> Dictionary:
	var def := get_def(id)
	if def == null:
		return seen
	for before in def.prerequisites:
		var key := StringName(before)
		if seen.has(key):
			continue
		seen[key] = true
		_ancestors(key, seen)
	return seen


func get_def(id: StringName) -> TechnologyDef:
	return _defs.get(id)


func has_def(id: StringName) -> bool:
	return _defs.has(id)


## Every id, in the order of the chain.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _defs:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		var da: TechnologyDef = _defs[a]
		var db: TechnologyDef = _defs[b]
		return da.order < db.order or (da.order == db.order and String(a) < String(b)))
	return out


## The technologies that bring `what` of `kind` ("buildings", "visuals" …).
func unlocking(kind: String, what: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ids():
		if get_def(id).unlocked(kind).has(what):
			out.append(id)
	return out
