class_name SpatialIndex
extends RefCounted
## Finds entities by position (bible §8.3, §23.3). Entities are registered by
## id with an exact 2D world position (x = world X, y = world Z) and a kind;
## lookups are bucketed by chunk so queries only scan nearby entities.
##
## The index stores ids only. It is rebuilt from the registries on load, so it
## is not saved.

## Entity kinds (bit flags so queries can ask for several at once).
const KIND_PERSON := 1 << 0
const KIND_ANIMAL := 1 << 1
const KIND_LOOSE_OBJECT := 1 << 2
const KIND_RESOURCE_NODE := 1 << 3
const KIND_BUILDING := 1 << 4
const KIND_MYSTERY := 1 << 5
const KIND_ALL := 0x7FFFFFFF

var chunk_size: int

var _positions: Dictionary = {} # id -> Vector2
var _kinds: Dictionary = {} # id -> int
var _buckets: Dictionary = {} # Vector2i chunk -> Array[int] ids


func _init(world_chunk_size: int = 16) -> void:
	chunk_size = world_chunk_size


func size() -> int:
	return _positions.size()


func has(id: int) -> bool:
	return _positions.has(id)


## Adds an entity, or moves/re-kinds it if the id is already present.
func insert(id: int, pos: Vector2, kind: int) -> void:
	if _positions.has(id):
		_remove_from_bucket(id, _bucket_of(_positions[id]))
	_positions[id] = pos
	_kinds[id] = kind
	_add_to_bucket(id, _bucket_of(pos))


func remove(id: int) -> void:
	if not _positions.has(id):
		return
	_remove_from_bucket(id, _bucket_of(_positions[id]))
	_positions.erase(id)
	_kinds.erase(id)


## Updates a position. Unknown ids are ignored (the entity may have been removed).
func move(id: int, pos: Vector2) -> void:
	if not _positions.has(id):
		return
	var old_bucket := _bucket_of(_positions[id])
	var new_bucket := _bucket_of(pos)
	_positions[id] = pos
	if old_bucket != new_bucket:
		_remove_from_bucket(id, old_bucket)
		_add_to_bucket(id, new_bucket)


## Position of an entity, or Vector2.INF if unknown.
func get_position(id: int) -> Vector2:
	return _positions.get(id, Vector2.INF)


func get_kind(id: int) -> int:
	return _kinds.get(id, 0)


func get_tile(id: int) -> Vector2i:
	return WorldCoords.world2d_to_tile(get_position(id)) if has(id) else Vector2i.ZERO


## Ids within `radius` of `center` whose kind matches `kind_mask`, nearest first.
func query_radius(center: Vector2, radius: float, kind_mask: int = KIND_ALL) -> Array[int]:
	var found: Array = [] # [distance_squared, id]
	var r2 := radius * radius
	var min_chunk := WorldCoords.tile_to_chunk(WorldCoords.world2d_to_tile(center - Vector2(radius, radius)), chunk_size)
	var max_chunk := WorldCoords.tile_to_chunk(WorldCoords.world2d_to_tile(center + Vector2(radius, radius)), chunk_size)
	for cy in range(min_chunk.y, max_chunk.y + 1):
		for cx in range(min_chunk.x, max_chunk.x + 1):
			var bucket: Array = _buckets.get(Vector2i(cx, cy), [])
			for id: int in bucket:
				if (_kinds[id] & kind_mask) == 0:
					continue
				var d2 := center.distance_squared_to(_positions[id])
				if d2 <= r2:
					found.append([d2, id])
	found.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var ids: Array[int] = []
	for entry: Array in found:
		ids.append(entry[1])
	return ids


## Ids in one chunk (unordered), filtered by kind.
func query_chunk(chunk: Vector2i, kind_mask: int = KIND_ALL) -> Array[int]:
	var ids: Array[int] = []
	var bucket: Array = _buckets.get(chunk, [])
	for id: int in bucket:
		if (_kinds[id] & kind_mask) != 0:
			ids.append(id)
	return ids


func clear() -> void:
	_positions.clear()
	_kinds.clear()
	_buckets.clear()


func _bucket_of(pos: Vector2) -> Vector2i:
	return WorldCoords.tile_to_chunk(WorldCoords.world2d_to_tile(pos), chunk_size)


func _add_to_bucket(id: int, bucket: Vector2i) -> void:
	if not _buckets.has(bucket):
		_buckets[bucket] = []
	(_buckets[bucket] as Array).append(id)


func _remove_from_bucket(id: int, bucket: Vector2i) -> void:
	var ids: Array = _buckets.get(bucket, [])
	ids.erase(id)
	if ids.is_empty():
		_buckets.erase(bucket)
