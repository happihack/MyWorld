class_name PropRegistry
extends RefCounted
## All props of the world, at most one per tile (bible §8.3).
##
## Generated props (trees, rocks, bushes from WorldGenerator) are not saved while
## untouched: they regenerate with their chunk. Only the differences are saved —
## which generated props were removed, which were changed (a tree that has
## lost its fruit), and which props were added.

## Emitted when the props standing on a chunk change (views rebuild that chunk).
signal chunk_changed(coord: Vector2i)

var chunk_size: int
## Goes up whenever a prop is added or removed (for whoever remembers things
## about the props and needs to know when to look again).
var version := 0
## Optional: kept in sync so entities can be found by position.
var spatial_index: SpatialIndex

var _props: Dictionary = {} # id -> PropData
var _by_tile: Dictionary = {} # Vector2i -> id
var _by_chunk: Dictionary = {} # Vector2i -> Array[int]
## Props by kind: kind -> {id: true}, in the order they came (M21: a scan of
## every prop of a 512-tile box for the few wells was dear on every turn).
var _by_kind: Dictionary = {}
var _removed_generated: Dictionary = {} # generated id -> true
var _changed_generated: Dictionary = {} # generated id -> true (saved in full)
var _saved_changes: Dictionary = {} # generated id -> PropData from the save, until its chunk is populated
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


## Picking body of a prop (see Picker), or null if `id` is not a prop here.
func pick_shape(id: int) -> Variant:
	var prop: PropData = _props.get(id)
	return prop.pick_shape() if prop != null else null


func has_prop_at(tile: Vector2i) -> bool:
	return _by_tile.has(tile)


func props_in_chunk(coord: Vector2i) -> Array[PropData]:
	var out: Array[PropData] = []
	var ids: Array = _by_chunk.get(coord, [])
	for id: int in ids:
		out.append(_props[id])
	return out


## Every prop of `kind`, in the order they came.
func of_kind(kind: int) -> Array[PropData]:
	var out: Array[PropData] = []
	for id: int in _by_kind.get(kind, {}):
		out.append(_props[id])
	return out


## How many props of `kind` there are.
func count_of(kind: int) -> int:
	return (_by_kind.get(kind, {}) as Dictionary).size()


## Every building (PropData.BUILDINGS), in the order of the kinds.
func buildings() -> Array[PropData]:
	var out: Array[PropData] = []
	for kind: int in PropData.BUILDINGS:
		for id: int in _by_kind.get(kind, {}):
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
		# A prop that was changed is restored as it was saved, not as generated.
		var saved: PropData = _saved_changes.get(prop.id)
		if saved != null and saved.tile == prop.tile:
			_saved_changes.erase(prop.id)
			_changed_generated[prop.id] = true
			_insert(saved)
		else:
			_insert(prop)
	chunk_changed.emit(coord)


## Forgets a chunk's generated props (when the chunk is unloaded). Added props
## and the removed list are kept.
func depopulate_chunk(coord: Vector2i) -> void:
	if not _populated.has(coord):
		return
	_populated.erase(coord)
	for prop in props_in_chunk(coord):
		if prop.is_generated():
			if _changed_generated.erase(prop.id):
				_saved_changes[prop.id] = prop # its changes wait for the chunk to come back
			_erase(prop)
	chunk_changed.emit(coord)


## Adds a non-generated prop. False if the id is invalid/taken or the tile is occupied.
func add(prop: PropData) -> bool:
	if prop == null or prop.id <= 0 or prop.is_generated() or _props.has(prop.id) or _by_tile.has(prop.tile):
		return false
	_insert(prop)
	chunk_changed.emit(WorldCoords.tile_to_chunk(prop.tile, chunk_size))
	return true


## Removes a prop. Removing a generated prop is remembered so it stays gone.
func remove(id: int) -> bool:
	var prop: PropData = _props.get(id)
	if prop == null:
		return false
	if prop.is_generated():
		_removed_generated[id] = true
		_changed_generated.erase(id)
	_erase(prop)
	chunk_changed.emit(WorldCoords.tile_to_chunk(prop.tile, chunk_size))
	return true


func removed_generated_count() -> int:
	return _removed_generated.size()


## Marks a generated prop as changed from how it was generated, so it is
## saved. Call after changing any of its fields.
func touch(id: int) -> void:
	var prop: PropData = _props.get(id)
	if prop != null and prop.is_generated():
		_changed_generated[id] = true


## A prop looks different from before (a tree felled, a bush picked bare):
## it is saved, and whoever draws its chunk draws it again.
func changed(id: int) -> void:
	var prop: PropData = _props.get(id)
	if prop == null:
		return
	touch(id)
	chunk_changed.emit(WorldCoords.tile_to_chunk(prop.tile, chunk_size))


func changed_generated_count() -> int:
	return _changed_generated.size() + _saved_changes.size()


func to_dict() -> Dictionary:
	var removed := PackedInt64Array()
	for id: int in _removed_generated:
		removed.append(id)
	removed.sort()
	var added: Array = []
	for prop: PropData in _props.values():
		if not prop.is_generated():
			added.append(prop.to_dict())
	var changed: Array = []
	var changed_ids: Array = _changed_generated.keys()
	changed_ids.sort()
	for id: int in changed_ids:
		changed.append((_props[id] as PropData).to_dict())
	# Changes of chunks that are not loaded right now are kept as they came.
	var waiting: Array = _saved_changes.keys()
	waiting.sort()
	for id: int in waiting:
		changed.append((_saved_changes[id] as PropData).to_dict())
	return {"removed": removed, "added": added, "changed": changed}


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
	var changed: Variant = data.get("changed", [])
	if typeof(changed) == TYPE_ARRAY:
		for record: Variant in changed:
			var prop: PropData = PropData.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
			if prop == null or not prop.is_generated() or _removed_generated.has(prop.id) \
					or prop.id != PropData.generated_id(prop.tile):
				skipped += 1
				continue
			_saved_changes[prop.id] = prop
	return skipped


func clear() -> void:
	if spatial_index != null:
		for id: int in _props:
			spatial_index.remove(id)
	_props.clear()
	_by_tile.clear()
	_by_chunk.clear()
	_by_kind.clear()
	_removed_generated.clear()
	_changed_generated.clear()
	_saved_changes.clear()
	_populated.clear()


func _insert(prop: PropData) -> void:
	version += 1
	_props[prop.id] = prop
	_by_tile[prop.tile] = prop.id
	if not _by_kind.has(prop.kind):
		_by_kind[prop.kind] = {}
	(_by_kind[prop.kind] as Dictionary)[prop.id] = true
	var coord := WorldCoords.tile_to_chunk(prop.tile, chunk_size)
	if not _by_chunk.has(coord):
		_by_chunk[coord] = []
	(_by_chunk[coord] as Array).append(prop.id)
	if spatial_index != null:
		spatial_index.insert(prop.id, prop.position2d(), prop.spatial_kind())


func _erase(prop: PropData) -> void:
	version += 1
	_props.erase(prop.id)
	_by_tile.erase(prop.tile)
	(_by_kind.get(prop.kind, {}) as Dictionary).erase(prop.id)
	var coord := WorldCoords.tile_to_chunk(prop.tile, chunk_size)
	var ids: Array = _by_chunk.get(coord, [])
	ids.erase(prop.id)
	if ids.is_empty():
		_by_chunk.erase(coord)
	if spatial_index != null:
		spatial_index.remove(prop.id)
