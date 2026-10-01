class_name WorldChecksum
extends RefCounted
## Fingerprints of world content (bible §8.4). Used to pin generator output in
## tests (golden checksums) and to compare devices: the same seed must give
## the same fingerprint on every platform.


## SHA-256 (hex) of every tile layer inside `rect` (default: the whole box).
static func terrain(world: WorldData, rect: Rect2i = Rect2i()) -> String:
	if rect.size == Vector2i.ZERO:
		rect = world.bounds
	var bytes := PackedByteArray()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var tile := Vector2i(x, y)
			var chunk := world.chunk_at_tile(tile)
			if chunk == null:
				continue
			var i := world.index_at_tile(tile)
			bytes.append(chunk.height[i])
			bytes.append(chunk.terrain[i])
			bytes.append(chunk.moisture[i])
			bytes.append(chunk.fertility[i])
			bytes.append(chunk.vegetation[i])
			bytes.append(chunk.temperature[i])
			bytes.append(roundi(chunk.water[i] * 1000.0) & 0xFF)
	return SaveContainer.sha256(bytes).hex_encode()


## SHA-256 (hex) of the props in a registry, independent of insertion order.
static func props(registry: PropRegistry, generated_only: bool = false) -> String:
	var rows: Array = []
	for p in registry.all_props():
		if generated_only and not p.is_generated():
			continue
		rows.append([p.tile.y, p.tile.x, p.id, p.kind, p.variant, p.rotation_step, p.scale_percent, p.offset_x, p.offset_y])
	rows.sort()
	return SaveContainer.sha256(var_to_bytes(rows)).hex_encode()
