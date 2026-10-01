class_name TerrainPalette
extends ConfigBase
## Colours of the terrain blocks (bible §28). Indexed by ChunkData.Terrain.
## Top = the walkable surface; side = the exposed face of a step.

@export var top_colors: Array[Color] = [
	Color(0.46, 0.70, 0.33), # GRASS
	Color(0.60, 0.47, 0.32), # DIRT
	Color(0.86, 0.80, 0.58), # SAND
	Color(0.61, 0.60, 0.62), # ROCK
	Color(0.95, 0.96, 0.98), # SNOW
	Color(0.55, 0.42, 0.24), # FARMLAND
	Color(0.68, 0.62, 0.50), # ROAD
	Color(0.52, 0.47, 0.38), # RIVERBED
	Color(0.40, 0.32, 0.24), # MUD
	Color(0.30, 0.30, 0.30), # ASH
]
@export var side_colors: Array[Color] = [
	Color(0.50, 0.38, 0.26), # GRASS (soil under the turf)
	Color(0.50, 0.38, 0.26), # DIRT
	Color(0.74, 0.67, 0.47), # SAND
	Color(0.49, 0.48, 0.51), # ROCK
	Color(0.62, 0.62, 0.67), # SNOW
	Color(0.46, 0.35, 0.21), # FARMLAND
	Color(0.55, 0.50, 0.41), # ROAD
	Color(0.43, 0.39, 0.32), # RIVERBED
	Color(0.33, 0.26, 0.20), # MUD
	Color(0.24, 0.24, 0.24), # ASH
]
## Each tile's brightness varies by up to this fraction (hides the grid a little).
@export_range(0.0, 0.2, 0.005) var tile_variation: float = 0.035
## How much one taller neighbour darkens a top-face corner (ambient occlusion).
@export_range(0.0, 0.4, 0.01) var corner_occlusion: float = 0.13
## Brightness of the bottom edge of a side face (1 = no gradient).
@export_range(0.3, 1.0, 0.01) var side_base_shade: float = 0.72

@export_group("Water")
@export var water_shallow: Color = Color(0.40, 0.74, 0.86)
@export var water_deep: Color = Color(0.13, 0.40, 0.68)
@export var water_foam: Color = Color(0.95, 0.98, 1.0)
@export_range(0.0, 1.0, 0.01) var water_opacity_shallow: float = 0.62
@export_range(0.0, 1.0, 0.01) var water_opacity_deep: float = 0.90
## Water this many height levels deep is drawn fully "deep".
@export_range(0.1, 8.0, 0.1) var water_deep_levels: float = 1.4
@export_range(0.0, 0.2, 0.005) var water_wave_height: float = 0.02
@export_range(0.0, 1.0, 0.01) var water_foam_amount: float = 0.75


func top(terrain: int) -> Color:
	return top_colors[terrain] if terrain >= 0 and terrain < top_colors.size() else Color.MAGENTA


func side(terrain: int) -> Color:
	return side_colors[terrain] if terrain >= 0 and terrain < side_colors.size() else Color.MAGENTA


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	var count := ChunkData.Terrain.size()
	_check(p, top_colors.size() == count, "top_colors needs %d entries (one per terrain type)" % count)
	_check(p, side_colors.size() == count, "side_colors needs %d entries (one per terrain type)" % count)
	return p
