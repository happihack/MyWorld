class_name LooseObjectRegistry
extends RefCounted
## All loose objects of the world (bible §8.3): where they are, kept in step
## with the spatial index so they can be found and picked.
##
## Like props, objects that came with the world are not saved while untouched:
## they regenerate with their chunk. The save holds only what differs —
## generated objects that were moved or removed, and objects that were added.

signal object_added(id: int)
signal object_removed(id: int)
## Position, height or rotation changed.
signal object_moved(id: int)

var chunk_size: int
## Optional: kept in sync so objects can be found by position.
var spatial_index: SpatialIndex

var _objects: Dictionary = {} # id -> LooseObject
var _removed_generated: Dictionary = {} # generated id -> true
var _changed_generated: Dictionary = {} # generated id -> true (moved etc.: saved in full)
var _populated: Dictionary = {} # chunk coord -> true


func _init(world_chunk_size: int = 16, index: SpatialIndex = null) -> void:
	chunk_size = world_chunk_size
	spatial_index = index


func size() -> int:
	return _objects.size()


func get_object(id: int) -> LooseObject:
	return _objects.get(id)


func has_object(id: int) -> bool:
	return _objects.has(id)


func all_objects() -> Array[LooseObject]:
	var out: Array[LooseObject] = []
	for object: LooseObject in _objects.values():
		out.append(object)
	return out


## Objects lying on a tile.
func objects_at(tile: Vector2i) -> Array[LooseObject]:
	var out: Array[LooseObject] = []
	if spatial_index != null:
		var center := Vector2(tile) + Vector2(0.5, 0.5)
		for id in spatial_index.query_radius(center, 0.75, SpatialIndex.KIND_LOOSE_OBJECT):
			var object: LooseObject = _objects.get(id)
			if object != null and object.tile() == tile:
				out.append(object)
	else:
		for object: LooseObject in _objects.values():
			if object.tile() == tile:
				out.append(object)
	return out


## Picking body of an object (see Picker), or null if `id` is not one of ours.
func pick_shape(id: int) -> Variant:
	var object: LooseObject = _objects.get(id)
	return object.pick_shape() if object != null else null


func is_chunk_populated(coord: Vector2i) -> bool:
	return _populated.has(coord)


## Adds a chunk's generated objects, skipping those that were removed or that
## were restored from the save in a changed state. Happens once per chunk.
func populate_chunk(coord: Vector2i, generated: Array[LooseObject]) -> void:
	if _populated.has(coord):
		return
	_populated[coord] = true
	for object in generated:
		if _removed_generated.has(object.id) or _objects.has(object.id):
			continue
		_insert(object)


## Adds a new (non-generated) object. False if the id is invalid or taken.
func add(object: LooseObject) -> bool:
	if object == null or object.id <= 0 or object.is_generated() or _objects.has(object.id):
		return false
	_insert(object)
	return true


## Removes an object. Removing a generated one is remembered so it stays gone.
func remove(id: int) -> bool:
	var object: LooseObject = _objects.get(id)
	if object == null:
		return false
	if object.is_generated():
		_removed_generated[id] = true
		_changed_generated.erase(id)
	_objects.erase(id)
	if spatial_index != null:
		spatial_index.remove(id)
	object_removed.emit(id)
	return true


## Moves an object (and optionally lifts or turns it). False for unknown ids
## and positions that are not finite.
func move(id: int, position: Vector2, height_offset: float = NAN, yaw: float = NAN) -> bool:
	var object: LooseObject = _objects.get(id)
	if object == null or not is_finite(position.x) or not is_finite(position.y):
		return false
	object.position = position
	if not is_nan(height_offset):
		object.height_offset = maxf(height_offset, 0.0)
	if not is_nan(yaw):
		object.yaw = yaw
	if spatial_index != null:
		spatial_index.move(id, position)
	touch(id)
	object_moved.emit(id)
	return true


## Marks an object as changed from how it was generated, so it is saved.
## Call after changing any field directly (state flags, counters, ...).
func touch(id: int) -> void:
	var object: LooseObject = _objects.get(id)
	if object != null and object.is_generated():
		_changed_generated[id] = true


## Forgets the generated ids in `ids` (for example the removed list of an older
## save, written when rocks were still props).
func mark_removed(ids: PackedInt64Array) -> void:
	for id in ids:
		if PropData.is_generated_id(id) and not _objects.has(id):
			_removed_generated[id] = true


func removed_generated_count() -> int:
	return _removed_generated.size()


## How many objects the save has to hold (added + changed).
func saved_count() -> int:
	var count := _changed_generated.size()
	for object: LooseObject in _objects.values():
		if not object.is_generated():
			count += 1
	return count


func to_dict() -> Dictionary:
	var removed := PackedInt64Array()
	for id: int in _removed_generated:
		removed.append(id)
	removed.sort()
	var records: Array = []
	var ids: Array = _objects.keys()
	ids.sort()
	for id: int in ids:
		var object: LooseObject = _objects[id]
		if not object.is_generated() or _changed_generated.has(id):
			records.append(object.to_dict())
	return {"removed": removed, "objects": records}


## Restores the saved differences. Call before populating chunks. Returns the
## number of unusable records skipped, or -1 if the data itself is unusable.
func from_dict(data: Dictionary) -> int:
	var removed: Variant = data.get("removed", PackedInt64Array())
	var records: Variant = data.get("objects", [])
	if typeof(removed) != TYPE_PACKED_INT64_ARRAY or typeof(records) != TYPE_ARRAY:
		return -1
	clear()
	var skipped := 0
	for id: int in removed:
		if PropData.is_generated_id(id):
			_removed_generated[id] = true
		else:
			skipped += 1
	for record: Variant in records:
		var object: LooseObject = LooseObject.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
		if object == null or object.id <= 0 or _objects.has(object.id) or _removed_generated.has(object.id):
			skipped += 1
			continue
		if object.is_generated():
			_changed_generated[object.id] = true
		_insert(object)
	return skipped


func clear() -> void:
	if spatial_index != null:
		for id: int in _objects:
			spatial_index.remove(id)
	_objects.clear()
	_removed_generated.clear()
	_changed_generated.clear()
	_populated.clear()


func _insert(object: LooseObject) -> void:
	_objects[object.id] = object
	if spatial_index != null:
		spatial_index.insert(object.id, object.position, SpatialIndex.KIND_LOOSE_OBJECT)
	object_added.emit(object.id)
