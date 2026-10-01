class_name PropRegistry
extends RefCounted
## All props of the world, at most one per tile (bible §8.3).
##
## Generated props (trees, rocks, bushes from WorldGenerator) are never saved:
## they regenerate with their chunk. Only the differences are saved —
## which generated props were removed, and which props were added.

var chunk_size: int
## Optional: kept in sync so entities can be found by position.
var spatial_index: SpatialIndex

var _props: Dictionary = {} # id -> PropData
var _by_tile: Dictionary = {} # Vector2i -> id
var _by_chunk: Dictionary = {} # Vector2i -> Array[int]
var _removed_generated: Dictionary = {} # generated id -> true
var _populated: Dictionary = {} # chunk coord -> true


func _init(world_chunk_size: int = 16, index: SpatialIndex = null) -> void:
	chunk_size = world_chunk_size
	spatial_index = index


func size() -> int:
	return _props.size()


func get_prop(id: int) -> PropData:
	return _props.get(id)


func prop_at(tile: Vector2i) -> PropData:
	return _props.get(_by_tile.get(tile, 0))


func has_prop_at(tile: Vector2i) -> bool:
	return _by_tile.has(tile)


func props_in_chunk(coord: Vector2i) -> Array[PropData]:
	var out: Array[PropData] = []
	var ids: Array = _by_chunk.get(coord, [])
	for id: int in ids:
		out.append(_props[id])
	return out


func all_props() -> Array[PropData]:
	var out: Array[PropData] = []
	for prop: PropData in _props.values():
		out.append(prop)
	return out


func is_chunk_populated(coord: Vector2i) -> bool:
	return _populated.has(coord)


## Adds a chunk's generated props (skipping removed ones and occupied tiles).
## Safe to call again for the same chunk: it only happens once.
func populate_chunk(coord: Vector2i, generated: Array[PropData]) -> void:
	if _populated.has(coord):
		return
	_populated[coord] = true
	for prop in generated:
		if _removed_generated.has(prop.id) or _by_tile.has(prop.tile):
			continue
		_insert(prop)


## Forgets a chunk's generated props (when the chunk is unloaded). Added props
## and the removed list are kept.
func depopulate_chunk(coord: Vector2i) -> void:
	if not _populated.has(coord):
		return
	_populated.erase(coord)
	for prop in props_in_chunk(coord):
		if prop.is_generated():
			_erase(prop)


## Adds a non-generated prop. False if the id is invalid/taken or the tile is occupied.
func add(prop: PropData) -> bool:
	if prop == null or prop.id <= 0 or prop.is_generated() or _props.has(prop.id) or _by_tile.has(prop.tile):
		return false
	_insert(prop)
	return true


## Removes a prop. Removing a generated prop is remembered so it stays gone.
func remove(id: int) -> bool:
	var prop: PropData = _props.get(id)
	if prop == null:
		return false
	if prop.is_generated():
		_removed_generated[id] = true
	_erase(prop)
	return true


func removed_generated_count() -> int:
	return _removed_generated.size()


func to_dict() -> Dictionary:
	var removed := PackedInt64Array()
	for id: int in _removed_generated:
		removed.append(id)
	removed.sort()
	var added: Array = []
	for prop: PropData in _props.values():
		if not prop.is_generated():
			added.append(prop.to_dict())
	return {"removed": removed, "added": added}


## Restores the saved differences. Call before populating chunks. Returns the
## number of unusable records skipped, or -1 if the data itself is unusable.
func from_dict(data: Dictionary) -> int:
	var removed: Variant = data.get("removed", PackedInt64Array())
	var added: Variant = data.get("added", [])
	if typeof(removed) != TYPE_PACKED_INT64_ARRAY or typeof(added) != TYPE_ARRAY:
		return -1
	clear()
	var skipped := 0
	for id: int in removed:
		if PropData.is_generated_id(id):
			_removed_generated[id] = true
		else:
			skipped += 1
	for record: Variant in added:
		var prop: PropData = PropData.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
		if not add(prop):
			skipped += 1
	return skipped


func clear() -> void:
	if spatial_index != null:
		for id: int in _props:
			spatial_index.remove(id)
	_props.clear()
	_by_tile.clear()
	_by_chunk.clear()
	_removed_generated.clear()
	_populated.clear()


func _insert(prop: PropData) -> void:
	_props[prop.id] = prop
	_by_tile[prop.tile] = prop.id
	var coord := WorldCoords.tile_to_chunk(prop.tile, chunk_size)
	if not _by_chunk.has(coord):
		_by_chunk[coord] = []
	(_by_chunk[coord] as Array).append(prop.id)
	if spatial_index != null:
		spatial_index.insert(prop.id, prop.position2d(), prop.spatial_kind())


func _erase(prop: PropData) -> void:
	_props.erase(prop.id)
	_by_tile.erase(prop.tile)
	var coord := WorldCoords.tile_to_chunk(prop.tile, chunk_size)
	var ids: Array = _by_chunk.get(coord, [])
	ids.erase(prop.id)
	if ids.is_empty():
		_by_chunk.erase(coord)
	if spatial_index != null:
		spatial_index.remove(prop.id)
