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

@export_group("The box unfolds")
## A ring of chunks is added (BoxUnfolder) when at least this share of the
## band along the walls has been explored, and either this many people live
## in each 1000 tiles of the box or a fire stands within `unfold_near_wall_tiles`
## of a wall; not again for `unfold_rest_days`.
@export_range(0.0, 1.0, 0.01) var unfold_edge_share: float = 0.25
@export_range(0.1, 100.0, 0.1) var unfold_people_per_1000_tiles: float = 6.0
@export_range(1, 64) var unfold_near_wall_tiles: int = 12
@export_range(0, 10000) var unfold_rest_days: int = 48
## How long the walls take to move outward (real seconds).
@export_range(0.1, 10.0, 0.1) var unfold_seconds: float = 3.0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	for size in [initial_world_tiles, slice_world_tiles, max_world_tiles]:
		_check(p, size % chunk_size == 0, "world size %d must be a multiple of chunk_size %d" % [size, chunk_size])
	_check(p, max_world_tiles >= initial_world_tiles, "max_world_tiles must be >= initial_world_tiles")
	return p
