class_name StartTemplate
extends ConfigBase
## Parameters for one kind of starting world (bible §8.5). Each world is
## created from a template; the generator turns these numbers into terrain.
##
## Only RIVER_VALLEY is implemented so far; the other shapes arrive with the
## content milestone (M32) and currently fall back to the river valley.

enum Shape { RIVER_VALLEY, ISLAND, MOUNTAIN_BASIN, FOREST_CLEARING, COASTAL_PLAIN, DESERT_OASIS }

@export var id: StringName = &"river_valley"
@export var display_name: String = "River Valley"
@export var shape: Shape = Shape.RIVER_VALLEY

@export_group("Valley")
## Height level of the flat valley floor.
@export_range(1, 12) var floor_level: int = 3
## How many levels the tallest hills rise above the floor.
@export_range(0, 14) var hill_height_levels: int = 8
## Distance from the river (tiles) where the hills begin.
@export_range(1.0, 64.0, 0.5) var valley_half_width_tiles: float = 10.0
## Distance over which the hills reach full height.
@export_range(1.0, 64.0, 0.5) var hill_run_tiles: float = 19.0
## How far (tiles) noise pushes the valley edge in and out, so the foot of the
## hills is irregular instead of a straight line.
@export_range(0.0, 16.0, 0.5) var valley_edge_warp_tiles: float = 6.0
@export_range(4, 128) var valley_edge_warp_period: int = 20
## 0 = every hill reaches full height; 0.5 = some hills are only half as tall
## (lower hills stay grassy, taller ones turn to rock).
@export_range(0.0, 0.9, 0.05) var hill_height_variation: float = 0.5
@export_range(4, 128) var hill_variation_period: int = 26
@export_range(2, 64) var terrain_noise_period: int = 14
@export_range(0.0, 4.0, 0.1) var valley_roughness_levels: float = 0.5
@export_range(0.0, 6.0, 0.1) var hill_roughness_levels: float = 2.4

@export_group("Terraces")
## How the land rises from the valley floor (the owner, 2026-10-08: the old
## hills were too much mountain, and their steps too thin at the foot).
## CLASSIC: the first worlds' rough hills — kept exactly for the worlds made
## with it. TERRACED: broad flat shelves, widest at the foot, and mountains
## only here and there, far from the river.
enum Style { CLASSIC, TERRACED }
@export var terrain_style: Style = Style.CLASSIC
## Levels from one shelf to the next.
@export_range(1, 4) var terrace_levels: int = 2
## 0..1: how much the rise holds back at the foot (wider bottom shelves).
@export_range(0.0, 1.0, 0.05) var terrace_ease: float = 0.6
## -1..1: one side of the river higher than the other (0: both alike).
@export_range(-1.0, 1.0, 0.05) var side_balance: float = 0.0
## 0..1: how much of the far land rises into mountains.
@export_range(0.0, 1.0, 0.05) var mountain_amount: float = 0.25
## How many levels mountains rise above the hills.
@export_range(0, 10) var mountain_height_levels: int = 5
@export_range(8, 128) var mountain_period: int = 30
## 0..1: where mountains begin, from the foot of the land (0) to its far edge
## (1) — and beyond (the higher, the further out).
@export_range(0.0, 2.0, 0.05) var mountain_from: float = 0.5
## 0..1: knolls — flat-topped mounds and low mesas out on the land, in patches.
@export_range(0.0, 1.0, 0.05) var knoll_amount: float = 0.0
@export_range(1, 6) var knoll_height_levels: int = 2
@export_range(6, 64) var knoll_period: int = 16

@export_group("River")
@export_range(0.5, 8.0, 0.1) var river_half_width_tiles: float = 1.6
## Width of the lowered, shallow-water bank on each side of the river.
@export_range(0.0, 4.0, 0.1) var bank_width_tiles: float = 1.2
@export_range(0.0, 32.0, 0.5) var meander_amplitude_tiles: float = 11.0
@export_range(8, 256) var meander_period_tiles: int = 30
## Extra river half-width where it swells into ponds.
@export_range(0.0, 12.0, 0.5) var pond_extra_width_tiles: float = 4.5
@export_range(8, 256) var pond_period_tiles: int = 22
## 0..1: how much of the river's length swells into ponds (higher = more).
@export_range(0.0, 1.0, 0.05) var pond_amount: float = 0.45
## How far the water surface sits below the valley floor, in height levels.
@export_range(0.1, 2.0, 0.1) var water_below_floor_levels: float = 0.6

@export_group("Surface")
## Height level at and above which the ground is bare rock / snow.
@export_range(1, 16) var rock_level: int = 9
@export_range(1, 16) var snow_level: int = 14

@export_group("Contents")
@export_range(4, 128) var forest_period_tiles: int = 18
## Chance of a tree per tile in the densest forest.
@export_range(0.0, 1.0, 0.01) var tree_density: float = 0.6
@export_range(0.0, 1.0, 0.005) var rock_density: float = 0.03
## Berry bushes: base chance per tile; up to 7x that along forest edges.
@export_range(0.0, 1.0, 0.001) var bush_density: float = 0.01


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, floor_level >= 2, "floor_level must be >= 2 (room for the river bed below it)")
	_check(p, floor_level + hill_height_levels <= 15, "floor_level + hill_height_levels must be <= 15")
	_check(p, terrain_style != Style.TERRACED or floor_level + hill_height_levels + mountain_height_levels <= 15,
		"floor_level + hill_height_levels + mountain_height_levels must be <= 15")
	_check(p, rock_level <= snow_level, "rock_level must be <= snow_level")
	_check(p, id != &"", "id must not be empty")
	# Keeps consecutive river rows connected (centre shifts well under the river
	# width per row).
	_check(p, meander_amplitude_tiles * 3.0 <= float(meander_period_tiles) * 1.2,
		"meander too steep for its period: the river could break apart")
	return p
