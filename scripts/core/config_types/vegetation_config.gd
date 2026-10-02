class_name VegetationConfig
extends ConfigBase
## The soil of all the land and what grows on it (bible §10.4): how the
## ground gets wet and dries, what a flood leaves behind, how grass thins
## and comes back, how trees seed and die — and what would burn.
##
## (What rain gives the soil and what a day dries are the fields' numbers:
## FarmingConfig.rain_moisture, evaporation_per_day, seep_share.)

@export_group("Soil")
## Soil wetter than the land holds by itself loses this share of the
## difference in a day (it drains).
@export_range(0.0, 1.0, 0.01) var drain_share: float = 0.5
## Soil poorer than the land is by itself gains this much fertility a day
## (land left alone recovers).
@export_range(0.0, 20.0, 0.1) var fertility_recover_per_day: float = 1.0
## What a flood leaves when it runs off (silt): this much fertility, up to
## this much above what the land has by itself; it fades by one in this many days.
@export_range(0, 100) var silt_gain: int = 18
@export_range(0, 255) var silt_most: int = 60
@export_range(1, 100) var silt_fade_days: int = 4
## After a long absence no more days than this are made up for.
@export_range(1, 60) var days_made_up: int = 10

@export_group("Grass")
## Grass comes this share of the way to what the soil lets grow in a day,
## and thins this share of the way when the soil lets less grow.
@export_range(0.0, 1.0, 0.01) var grow_per_day: float = 0.04
@export_range(0.0, 1.0, 0.01) var die_per_day: float = 0.08
## How much grows by season (0 = spring): what stands in the middle of each.
@export var by_season: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.92, 0.7])
## Bare ground (less than `bare_below`) greens again as fast as that only
## beside grass of at least `spread_from` (it spreads from its edges);
## alone it comes back at this share of the speed.
@export_range(0, 255) var bare_below: int = 30
@export_range(0, 255) var spread_from: int = 70
@export_range(0.0, 1.0, 0.01) var alone_share: float = 0.15
## Tilled or burnt ground nothing is grown on turns to grass again: the
## chance of that for a tile in a day.
@export_range(0.0, 1.0, 0.005) var reclaim_chance_per_day: float = 0.08
## A chunk is drawn anew when the grass of a tile has changed this much.
@export_range(1, 128) var redraw_step: int = 24

@export_group("Trees")
## The chance that a grown tree seeds a sapling in a day (in the seasons things grow in).
@export_range(0.0, 1.0, 0.0005) var sapling_chance_per_day: float = 0.004
## How far from the tree (tiles), and how many trees may already stand
## around the place (the eight tiles about it).
@export_range(1, 8) var sapling_reach: int = 3
@export_range(0, 8) var sapling_crowd: int = 2
## A sapling needs soil at least this moist, and keeps this far from the settlement's fire.
@export_range(0, 255) var sapling_moisture: int = 70
@export_range(0.0, 32.0, 0.5) var settlement_clearance: float = 5.0
## Trees in soil drier than this die: the chance for one in a day.
@export_range(0, 255) var dry_below: int = 40
@export_range(0.0, 1.0, 0.001) var dry_death_per_day: float = 0.03
## In a cold snap saplings die: the chance for one in a day.
@export_range(0.0, 1.0, 0.001) var cold_death_per_day: float = 0.06
## The forest never grows beyond this many times the trees the world began
## with, and nothing dies below this share of them.
@export_range(1.0, 5.0, 0.05) var forest_most: float = 1.3
@export_range(0.0, 1.0, 0.05) var forest_least: float = 0.5

@export_group("Fire (for the fire system to come)")
## How much of what would burn is grass (full cover) and how much a tree.
@export_range(0.0, 1.0, 0.05) var fuel_grass: float = 0.6
@export_range(0.0, 1.0, 0.05) var fuel_tree: float = 0.4
## Soaked ground burns this little (1 = as well as dry ground).
@export_range(0.0, 1.0, 0.05) var wet_fuel_share: float = 0.15
## A tile can burn from this much fuel.
@export_range(0.0, 1.0, 0.01) var burn_from: float = 0.2
## Ash feeds the soil: this much fertility.
@export_range(0, 100) var ash_gain: int = 10


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, by_season.size() == 4, "by_season needs four entries")
	_check(p, forest_least <= 1.0 and forest_most >= 1.0, "forest_least … forest_most must include 1")
	_check(p, bare_below < spread_from, "bare_below must be less than spread_from")
	_check(p, silt_fade_days >= 1 and days_made_up >= 1, "silt_fade_days and days_made_up must be at least 1")
	return p
