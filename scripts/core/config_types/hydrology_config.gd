class_name HydrologyConfig
extends ConfigBase
## How the river stands (bible §10.3): what rain, melting snow, dry weeks
## and heat do to its level, when it is over its banks and when its banks
## lie dry, and what that means for the ground beside it.
##
## Levels are in world units above (+) or below (−) where the river was
## made. (In the river valley the banks lie 0.16 under the water, the valley
## floor 0.24 above it, and the bed 0.56 under it.)

@export_group("Where the river settles")
## The rain of this many days decides where the river settles …
@export_range(1, 30) var rain_days: int = 10
## … compared with what falls in a day on average (units of rain: see
## ClimateConfig.precipitation). Days nobody watched count as average.
@export_range(0.1, 50.0, 0.1) var normal_rain_per_day: float = 4.8
## With no rain at all in those days it settles `dry_span` below; with
## twice the average `wet_span` above (and so on, up to `wet_most` times).
@export_range(0.0, 1.0, 0.005) var dry_span: float = 0.18
@export_range(0.0, 1.0, 0.005) var wet_span: float = 0.15
@export_range(1.0, 5.0, 0.1) var wet_most: float = 2.5
## Heat takes water: this much lower for every ten degrees above `heat_from`
## (more in wind: × (1 + wind × `wind_factor`)). Nothing under ice.
@export_range(0.0, 0.5, 0.005) var heat_fall: float = 0.05
@export_range(-10.0, 40.0, 0.5) var heat_from: float = 18.0
@export_range(0.0, 3.0, 0.05) var wind_factor: float = 0.5
## Game hours in which it comes most of the way (63 %) to where it settles;
## under ice this many times as long.
@export_range(1.0, 500.0, 1.0) var settle_hours: float = 40.0
@export_range(1.0, 10.0, 0.1) var frozen_slower: float = 2.0

@export_group("What falls and melts")
## What a unit of rain raises the river at once (it runs off the land), and
## what the melting of a full cover of snow raises it.
@export_range(0.0, 0.05, 0.0001) var rain_rise: float = 0.0026
@export_range(0.0, 0.5, 0.005) var melt_rise: float = 0.065

@export_group("Bounds")
## It never falls or rises further than this (the springs do not run dry;
## the box is not filled).
@export_range(-1.0, 0.0, 0.01) var lowest: float = -0.36
@export_range(0.0, 2.0, 0.01) var highest: float = 0.45
## The water of the tiles is set anew when the level has moved this far.
@export_range(0.001, 0.1, 0.001) var apply_step: float = 0.02
## Ground this little under the surface is not water yet.
@export_range(0.0, 0.1, 0.001) var least_depth: float = 0.008

@export_group("High and low water")
## High water from this level (the river is at its banks' edge), over below that.
@export_range(0.0, 1.0, 0.005) var high_from: float = 0.2
@export_range(0.0, 1.0, 0.005) var high_over: float = 0.12
## Low water from this level down (the banks lie dry), over above that.
@export_range(-1.0, 0.0, 0.005) var low_from: float = -0.15
@export_range(-1.0, 0.0, 0.005) var low_over: float = -0.08
## A flood: at least this many settled tiles (huts, the fire, the stores,
## the fields) under at least this much water.
@export_range(1, 50) var flood_tiles: int = 3
@export_range(0.0, 1.0, 0.005) var flood_depth: float = 0.04

@export_group("The ground beside it")
## How much of the moisture the land holds by itself is there for every
## unit the river stands lower or higher (1 = as made), within bounds.
@export_range(0.0, 10.0, 0.1) var groundwater_per_level: float = 2.4
@export_range(0.0, 1.0, 0.05) var groundwater_least: float = 0.4
@export_range(1.0, 2.0, 0.05) var groundwater_most: float = 1.15
## Soil dries as usual on a day whose warmest hour had this many degrees;
## more on hotter days, less on cooler ones, within bounds.
@export_range(1.0, 40.0, 0.5) var drying_normal_degrees: float = 20.0
@export_range(0.0, 1.0, 0.05) var drying_least: float = 0.3
@export_range(1.0, 4.0, 0.05) var drying_most: float = 1.8

@export_group("The river's run")
## The current is this many times as strong for every unit the river
## stands higher (1 = as made), within bounds.
@export_range(0.0, 20.0, 0.1) var flow_per_level: float = 3.0
@export_range(0.0, 1.0, 0.05) var flow_least: float = 0.25
@export_range(1.0, 5.0, 0.05) var flow_most: float = 2.5
## Springs in the riverbed (where they are comes from the world's seed).
@export_range(0, 12) var spring_count: int = 3

@export_group("Erosion")
## When high water comes: the chance that the river takes a tile of its bank.
@export_range(0.0, 1.0, 0.01) var erosion_chance: float = 0.25
## Never more than this many tiles in a world's life.
@export_range(0, 1000) var erosion_most: int = 40


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, lowest < 0.0 and highest > 0.0, "lowest must be below and highest above where the river was made")
	_check(p, high_over < high_from, "high_over must be below high_from")
	_check(p, low_from < low_over, "low_from must be below low_over")
	_check(p, low_from > lowest and high_from < highest, "high and low water must lie within lowest … highest")
	_check(p, groundwater_least <= 1.0 and groundwater_most >= 1.0, "groundwater_least … groundwater_most must include 1")
	_check(p, drying_least <= 1.0 and drying_most >= 1.0, "drying_least … drying_most must include 1")
	_check(p, flow_least <= 1.0 and flow_most >= 1.0, "flow_least … flow_most must include 1")
	_check(p, normal_rain_per_day > 0.0 and settle_hours > 0.0, "normal_rain_per_day and settle_hours must be more than nothing")
	return p
