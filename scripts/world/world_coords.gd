class_name WorldCoords
extends RefCounted
## Coordinate conversions (bible §8.1). ALL tile/chunk/world math goes through
## here so negative coordinates are floored correctly everywhere.
##
## - Tile:  Vector2i on the XZ plane; may be negative. Tile (x, y) covers world
##          X in [x, x+1) and world Z in [y, y+1).
## - Chunk: chunk_size x chunk_size tiles; chunk coord = floor(tile / chunk_size).
## - Local: tile position inside its chunk, each axis in [0, chunk_size).
## - Index: local.y * chunk_size + local.x into a chunk's packed layer arrays.


## Floor division that is correct for negative numerators (GDScript's `/`
## truncates toward zero: -1 / 16 == 0, but tile -1 lives in chunk -1).
static func floor_div(a: int, b: int) -> int:
	return (a - posmod(a, b)) / b


static func tile_to_chunk(tile: Vector2i, chunk_size: int) -> Vector2i:
	return Vector2i(floor_div(tile.x, chunk_size), floor_div(tile.y, chunk_size))


static func tile_to_local(tile: Vector2i, chunk_size: int) -> Vector2i:
	return Vector2i(posmod(tile.x, chunk_size), posmod(tile.y, chunk_size))


static func local_to_index(local: Vector2i, chunk_size: int) -> int:
	return local.y * chunk_size + local.x


static func index_to_local(index: int, chunk_size: int) -> Vector2i:
	return Vector2i(index % chunk_size, index / chunk_size)


static func tile_to_index(tile: Vector2i, chunk_size: int) -> int:
	return local_to_index(tile_to_local(tile, chunk_size), chunk_size)


## Tile at the chunk's minimum corner.
static func chunk_origin(chunk: Vector2i, chunk_size: int) -> Vector2i:
	return chunk * chunk_size


static func chunk_local_to_tile(chunk: Vector2i, local: Vector2i, chunk_size: int) -> Vector2i:
	return chunk * chunk_size + local


## Tile rectangle covered by a chunk.
static func chunk_rect(chunk: Vector2i, chunk_size: int) -> Rect2i:
	return Rect2i(chunk * chunk_size, Vector2i(chunk_size, chunk_size))


## Chunk coordinates (inclusive rectangle) touched by a tile rectangle.
static func chunks_in_rect(tile_rect: Rect2i, chunk_size: int) -> Rect2i:
	if tile_rect.size.x <= 0 or tile_rect.size.y <= 0:
		return Rect2i()
	var first := tile_to_chunk(tile_rect.position, chunk_size)
	var last := tile_to_chunk(tile_rect.end - Vector2i.ONE, chunk_size)
	return Rect2i(first, last - first + Vector2i.ONE)


## World-space centre of a tile's top surface at the given height level.
static func tile_to_world3d(tile: Vector2i, height_level: int, height_step: float) -> Vector3:
	return Vector3(tile.x + 0.5, height_level * height_step, tile.y + 0.5)


static func world3d_to_tile(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.z))


## Tile containing a 2D world position (x = world X, y = world Z).
static func world2d_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))
