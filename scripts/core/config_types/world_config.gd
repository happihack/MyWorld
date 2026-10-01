class_name WorldConfig
extends ConfigBase
## World space: tiles, chunks, heights, sizes (bible §8).

@export_range(4, 64) var chunk_size: int = 16
@export_range(16, 4096) var initial_world_tiles: int = 64
@export_range(16, 4096) var slice_world_tiles: int = 32
@export_range(16, 4096) var max_world_tiles: int = 512
@export_range(2, 255) var height_levels: int = 16
## World units of vertical rise per height level.
@export_range(0.05, 2.0, 0.05) var height_step: float = 0.4


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	for size in [initial_world_tiles, slice_world_tiles, max_world_tiles]:
		_check(p, size % chunk_size == 0, "world size %d must be a multiple of chunk_size %d" % [size, chunk_size])
	_check(p, max_world_tiles >= initial_world_tiles, "max_world_tiles must be >= initial_world_tiles")
	return p
