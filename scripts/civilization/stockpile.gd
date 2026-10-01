class_name Stockpile
extends RefCounted
## What a settlement has in store (bible §11, §17.3): the piles that lie at
## its storage places, counted. Storage is physical — the count is whatever
## is really there: carry a pile off and the settlement has less.
##
## Counting looks at every pile, so the counts are kept until something that
## lies about is added, removed, moved or changed.

var _piles: PileStore
var _places: Places
var _library: ResourceLibrary
var _loose: LooseObjectRegistry
var _radius := 1.6
var _counts: Dictionary = {} # resource id -> units
var _stale := true


func bind(piles: PileStore, places: Places, library: ResourceLibrary, loose: LooseObjectRegistry,
		config: ResourcesConfig = null) -> void:
	unbind()
	_piles = piles
	_places = places
	_library = library
	_loose = loose
	_radius = (config if config != null else Config.resources).storage_radius
	_stale = true
	if _loose != null:
		_loose.object_added.connect(_on_loose_changed)
		_loose.object_removed.connect(_on_loose_changed)
		_loose.object_moved.connect(_on_loose_changed)


func unbind() -> void:
	if _loose != null and _loose.object_added.is_connected(_on_loose_changed):
		_loose.object_added.disconnect(_on_loose_changed)
		_loose.object_removed.disconnect(_on_loose_changed)
		_loose.object_moved.disconnect(_on_loose_changed)
	_loose = null
	_counts.clear()
	_stale = true


## Where `resource` is kept (the middle of its storage tile), or Vector2.INF.
func place(resource: StringName) -> Vector2:
	var tile: Variant = _places.storage_tile(resource) if _places != null else null
	return Places.middle_of(tile) if tile != null else Vector2.INF


## Units of `resource` in store.
func amount(resource: StringName) -> int:
	_recount()
	return int(_counts.get(resource, 0))


## Everything in store: resource id -> units (only what there is some of).
func amounts() -> Dictionary:
	_recount()
	return _counts.duplicate()


## How many units of food there are, of whatever kind.
func food_units() -> int:
	_recount()
	var units := 0
	for resource: StringName in _counts:
		var def := _library.get_def(resource) if _library != null else null
		if def != null and def.is_food():
			units += int(_counts[resource])
	return units


## The food in store in bellies: what it feeds (see ResourceDef.nutrition).
func food() -> float:
	_recount()
	var bellies := 0.0
	for resource: StringName in _counts:
		var def := _library.get_def(resource) if _library != null else null
		if def != null and def.is_food():
			bellies += int(_counts[resource]) * def.nutrition
	return bellies


## How much more of `resource` the stores take.
func room(resource: StringName) -> int:
	var at := place(resource)
	return _piles.room(resource, at) if _piles != null and at != Vector2.INF else 0


## Puts `units` of `resource` into the stores.
func add(resource: StringName, units: int) -> void:
	var at := place(resource)
	if _piles != null and at != Vector2.INF:
		_piles.add(resource, units, at)


## Takes up to `units` of `resource` out of the stores. Returns how many.
func take(resource: StringName, units: int) -> int:
	var at := place(resource)
	if _piles == null or at == Vector2.INF or units <= 0 or amount(resource) <= 0:
		return 0
	return _piles.take(resource, units, at, _radius)


## Takes one unit of food — of what goes bad soonest, so that nothing is
## left to rot while fresher food is eaten. Returns what it was (&"" if
## there is none).
func take_food() -> StringName:
	_recount()
	var best: ResourceDef = null
	for resource: StringName in _counts:
		var def := _library.get_def(resource) if _library != null else null
		if def == null or not def.is_food() or int(_counts[resource]) <= 0:
			continue
		if best == null or _keeps(def) < _keeps(best) or (_keeps(def) == _keeps(best) and String(def.id) < String(best.id)):
			best = def
	if best == null or take(best.id, 1) <= 0:
		return &""
	return best.id


func debug_text() -> String:
	var counts := amounts()
	var names: Array = counts.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var parts := PackedStringArray()
	for resource: StringName in names:
		parts.append("%s %d" % [resource, counts[resource]])
	return " ".join(parts) if not parts.is_empty() else "nothing"


static func _keeps(def: ResourceDef) -> float:
	return def.spoil_days if def.spoils() else INF


func _recount() -> void:
	if not _stale:
		return
	_stale = false
	_counts.clear()
	if _piles == null or _library == null:
		return
	for resource in _library.ids():
		var at := place(resource)
		if at == Vector2.INF:
			continue
		var units := _piles.total(resource, at, _radius)
		if units > 0:
			_counts[resource] = units


func _on_loose_changed(_id: int) -> void:
	_stale = true
