class_name WorldData
extends RefCounted
## The tile world: bounds + chunks (bible §8). Pure data, runs headless.
##
## Chunks are created on demand by `generator` (set by WorldGenerator), which
## must be deterministic: only chunks that differ from generator output
## (`modified`) are saved, and unmodified chunks may be dropped at any time.
## Out-of-bounds reads return safe defaults; out-of-bounds writes are ignored.

## Fallback generator for tests / missing generator: empty flat chunks.
const DEFAULT_HEIGHT := 0

var chunk_size: int
## Box interior in tiles (grows when the box unfolds).
var bounds: Rect2i
## Callable(coord: Vector2i) -> ChunkData. Must be deterministic.
var generator: Callable

var _chunks: Dictionary = {} # Vector2i -> ChunkData


func _init(tile_bounds: Rect2i = Rect2i(), world_chunk_size: int = 16) -> void:
	bounds = tile_bounds
	chunk_size = world_chunk_size


## A world of size x size tiles centred on the origin (size must be a multiple
## of the chunk size so the walls sit on chunk borders).
static func create_centered(size_tiles: int, world_chunk_size: int) -> WorldData:
	var half := size_tiles / 2
	return WorldData.new(Rect2i(-half, -half, size_tiles, size_tiles), world_chunk_size)


# --- bounds ------------------------------------------------------------------------

func is_in_bounds(tile: Vector2i) -> bool:
	return bounds.has_point(tile)


func is_chunk_in_bounds(coord: Vector2i) -> bool:
	return bounds.intersects(WorldCoords.chunk_rect(coord, chunk_size))


## Every chunk coordinate that overlaps the bounds, row by row.
func chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rect := WorldCoords.chunks_in_rect(bounds, chunk_size)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


# --- chunks ------------------------------------------------------------------------

func has_chunk(coord: Vector2i) -> bool:
	return _chunks.has(coord)


## The chunk at `coord`, generating it if needed. Null when out of bounds, or
## when it is not loaded and generate_if_missing is false.
func get_chunk(coord: Vector2i, generate_if_missing: bool = true) -> ChunkData:
	var chunk: ChunkData = _chunks.get(coord)
	if chunk != null or not generate_if_missing or not is_chunk_in_bounds(coord):
		return chunk
	if generator.is_valid():
		chunk = generator.call(coord) as ChunkData
	if chunk == null:
		chunk = ChunkData.new(coord, chunk_size)
		chunk.height.fill(DEFAULT_HEIGHT)
		chunk.mark_pristine()
	_chunks[coord] = chunk
	return chunk


func loaded_chunks() -> Array[ChunkData]:
	var out: Array[ChunkData] = []
	for chunk: ChunkData in _chunks.values():
		out.append(chunk)
	return out


func modified_chunks() -> Array[ChunkData]:
	var out: Array[ChunkData] = []
	for chunk: ChunkData in _chunks.values():
		if chunk.modified:
			out.append(chunk)
	return out


## Drops an unmodified chunk from memory (it regenerates identically on demand).
## Modified chunks are kept; returns whether the chunk was dropped.
func unload_chunk(coord: Vector2i) -> bool:
	var chunk: ChunkData = _chunks.get(coord)
	if chunk == null or chunk.modified:
		return false
	_chunks.erase(coord)
	return true


# --- tile access ---------------------------------------------------------------------

func get_height(tile: Vector2i) -> int:
	var chunk := _chunk_for(tile)
	return chunk.height[WorldCoords.tile_to_index(tile, chunk_size)] if chunk != null else DEFAULT_HEIGHT


func set_height(tile: Vector2i, level: int) -> void:
	var chunk := _chunk_for(tile)
	if chunk != null:
		chunk.set_height(WorldCoords.tile_to_index(tile, chunk_size), level)


func get_terrain(tile: Vector2i) -> ChunkData.Terrain:
	var chunk := _chunk_for(tile)
	if chunk == null:
		return ChunkData.Terrain.ROCK
	return chunk.terrain[WorldCoords.tile_to_index(tile, chunk_size)] as ChunkData.Terrain


func set_terrain(tile: Vector2i, type: ChunkData.Terrain) -> void:
	var chunk := _chunk_for(tile)
	if chunk != null:
		chunk.set_terrain(WorldCoords.tile_to_index(tile, chunk_size), type)


func get_water(tile: Vector2i) -> float:
	var chunk := _chunk_for(tile)
	return chunk.water[WorldCoords.tile_to_index(tile, chunk_size)] if chunk != null else 0.0


func set_water(tile: Vector2i, depth: float) -> void:
	var chunk := _chunk_for(tile)
	if chunk != null:
		chunk.set_water(WorldCoords.tile_to_index(tile, chunk_size), depth)


func has_flag(tile: Vector2i, flag: int) -> bool:
	var chunk := _chunk_for(tile)
	return chunk != null and chunk.has_flag(WorldCoords.tile_to_index(tile, chunk_size), flag)


func set_flag(tile: Vector2i, flag: int, enabled: bool) -> void:
	var chunk := _chunk_for(tile)
	if chunk != null:
		chunk.set_flag(WorldCoords.tile_to_index(tile, chunk_size), flag, enabled)


## The chunk + index for callers that touch several layers of one tile.
## Returns null when the tile is out of bounds.
func chunk_at_tile(tile: Vector2i) -> ChunkData:
	return _chunk_for(tile)


func index_at_tile(tile: Vector2i) -> int:
	return WorldCoords.tile_to_index(tile, chunk_size)


# --- persistence ---------------------------------------------------------------------

## Only modified chunks are stored; everything else comes from the generator.
func to_dict() -> Dictionary:
	var chunks: Array = []
	for chunk in modified_chunks():
		chunks.append(chunk.to_dict())
	return {"chunk_size": chunk_size, "bounds": bounds, "chunks": chunks}


## Restores bounds and modified chunks. Invalid chunk records are skipped (the
## generator then recreates those chunks); returns how many were skipped, or -1
## if the data itself is unusable.
func from_dict(data: Dictionary) -> int:
	if typeof(data.get("bounds")) != TYPE_RECT2I or typeof(data.get("chunk_size")) != TYPE_INT:
		return -1
	if int(data["chunk_size"]) < 1:
		return -1
	chunk_size = data["chunk_size"]
	bounds = data["bounds"]
	_chunks.clear()
	var skipped := 0
	var records: Variant = data.get("chunks", [])
	if typeof(records) != TYPE_ARRAY:
		return -1
	for record: Variant in records:
		var chunk: ChunkData = null
		if typeof(record) == TYPE_DICTIONARY:
			chunk = ChunkData.from_dict(record)
		if chunk == null or chunk.size != chunk_size or not is_chunk_in_bounds(chunk.coord):
			skipped += 1
			continue
		_chunks[chunk.coord] = chunk
	return skipped


func _chunk_for(tile: Vector2i) -> ChunkData:
	if not bounds.has_point(tile):
		return null
	return get_chunk(WorldCoords.tile_to_chunk(tile, chunk_size))
