class_name AnimalRegistry
extends RefCounted
## All the animals of the world (those kept one by one; fish are a number).

signal animal_added(id: int)
signal animal_removed(id: int)

## Optional: kept in sync so animals can be found by position.
var spatial_index: SpatialIndex

var _animals: Dictionary = {} # id -> AnimalData
var _order: Array[int] = [] # ids in the order they came (stable to walk through)
var _counts: Dictionary = {} # species -> how many


func _init(index: SpatialIndex = null) -> void:
	spatial_index = index


func size() -> int:
	return _animals.size()


func get_animal(id: int) -> AnimalData:
	return _animals.get(id)


func has_animal(id: int) -> bool:
	return _animals.has(id)


## Everyone, in the order they came into the world.
func all_animals() -> Array[AnimalData]:
	var out: Array[AnimalData] = []
	for id in _order:
		out.append(_animals[id])
	return out


func of_species(species: StringName) -> Array[AnimalData]:
	var out: Array[AnimalData] = []
	for id in _order:
		if (_animals[id] as AnimalData).species == species:
			out.append(_animals[id])
	return out


func count(species: StringName) -> int:
	return int(_counts.get(species, 0))


func add(animal: AnimalData) -> bool:
	if animal == null or animal.id <= 0 or _animals.has(animal.id) or animal.species == &"":
		return false
	_animals[animal.id] = animal
	_order.append(animal.id)
	_counts[animal.species] = count(animal.species) + 1
	if spatial_index != null:
		spatial_index.insert(animal.id, animal.position, SpatialIndex.KIND_ANIMAL)
	animal_added.emit(animal.id)
	return true


func remove(id: int) -> bool:
	var animal: AnimalData = _animals.get(id)
	if animal == null:
		return false
	_animals.erase(id)
	_order.erase(id)
	_counts[animal.species] = maxi(count(animal.species) - 1, 0)
	if spatial_index != null:
		spatial_index.remove(id)
	animal_removed.emit(id)
	return true


## Puts an animal somewhere else (and keeps the index in step).
func move(id: int, position: Vector2, facing: float = NAN) -> void:
	var animal: AnimalData = _animals.get(id)
	if animal == null or not is_finite(position.x) or not is_finite(position.y):
		return
	animal.position = position
	if not is_nan(facing):
		animal.facing = facing
	if spatial_index != null:
		spatial_index.move(id, position)


func clear() -> void:
	if spatial_index != null:
		for id: int in _animals:
			spatial_index.remove(id)
	_animals.clear()
	_order.clear()
	_counts.clear()


func to_dict() -> Dictionary:
	var records: Array = []
	for id in _order:
		records.append((_animals[id] as AnimalData).to_dict())
	return {"animals": records}


## Restores saved animals. Returns how many records were unusable.
func from_dict(data: Dictionary) -> int:
	clear()
	var skipped := 0
	var records: Variant = data.get("animals")
	if typeof(records) != TYPE_ARRAY:
		return 0
	for record: Variant in records:
		var animal := AnimalData.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
		if not add(animal):
			skipped += 1
	return skipped
