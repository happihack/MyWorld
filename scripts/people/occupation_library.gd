class_name OccupationLibrary
extends RefCounted
## The occupations defined in res://data/occupations/ (bible §13.6).

const DIR := "res://data/occupations/"

var problems: PackedStringArray = []
var _defs: Dictionary = {} # StringName id -> OccupationDef


## Loads every definition in `dir`. Unusable files are skipped and reported in
## `problems`; the game runs with whatever is left.
static func load_from(dir: String = DIR) -> OccupationLibrary:
	var library := OccupationLibrary.new()
	# list_directory sees resources as they were authored, also in an exported game.
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with("/"):
			continue
		var def := ResourceLoader.load(dir.path_join(file)) as OccupationDef
		if def == null:
			library._problem("%s is not an occupation" % file)
			continue
		library.add(def)
	if library._defs.is_empty():
		library._problem("no occupations found in %s" % dir)
	return library


## Adds a definition. False (with a problem noted) if it is unusable.
func add(def: OccupationDef) -> bool:
	var found := def.validate()
	if _defs.has(def.id):
		found.append("%s: defined twice" % def.id)
	for problem in found:
		_problem(problem)
	if not found.is_empty():
		return false
	_defs[def.id] = def
	return true


func size() -> int:
	return _defs.size()


func has_def(id: StringName) -> bool:
	return _defs.has(id)


func get_def(id: StringName) -> OccupationDef:
	return _defs.get(id)


## All ids, sorted (so that nothing depends on the order of files).
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _defs:
		out.append(id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Chooses an occupation for someone at `stage` with `traits`: by what suits
## them and by what the band still lacks (`counts`: id -> how many have it
## already), never by argmax (bible §13.2). &"" if nothing is open to them.
func choose(stage: PersonData.LifeStage, traits: PackedFloat32Array, rng: RandomNumberGenerator,
		counts: Dictionary = {}) -> StringName:
	var open: Array[StringName] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for id in ids():
		var def: OccupationDef = _defs[id]
		if not def.allows(stage) or def.starting_share <= 0.0:
			continue
		var weight := def.starting_share * exp(def.affinity(traits)) / (1.0 + float(counts.get(id, 0)))
		open.append(id)
		weights.append(weight)
		total += weight
	if open.is_empty():
		return &""
	var roll := rng.randf() * total
	for i in open.size():
		roll -= weights[i]
		if roll <= 0.0:
			return open[i]
	return open[-1]


func _problem(message: String) -> void:
	problems.append(message)
	Log.error(Log.Category.SIM, "Occupation problem: " + message)
