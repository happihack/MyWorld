class_name SpeciesLibrary
extends RefCounted
## The species defined in res://data/species/ (bible §12).

const DIR := "res://data/species/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> SpeciesDef
var _order: Array[StringName] = []


static func load_from(dir: String = DIR) -> SpeciesLibrary:
	var library := SpeciesLibrary.new()
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as SpeciesDef
		if def == null:
			library._problem("%s is not a species" % file)
			continue
		library.add(def)
	if library._defs.is_empty():
		library._problem("no species found in %s" % dir)
	# What a predator eats must exist.
	for id in library._order:
		for prey in (library._defs[id] as SpeciesDef).prey:
			if not library._defs.has(StringName(prey)):
				library._problem("%s preys on '%s', which is not a species" % [id, prey])
	return library


func add(def: SpeciesDef) -> bool:
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


func get_def(id: StringName) -> SpeciesDef:
	return _defs.get(id)


## All ids, sorted.
func ids() -> Array[StringName]:
	return _order


func _problem(message: String) -> void:
	problems.append(message)
	Log.error(Log.Category.SIM, "Species problem: " + message)
