class_name ConstructionConfig
extends ConfigBase
## Building (bible §17.2, M12.1): when the settlement plans what, where it
## builds, how building goes, and what wears buildings down.

@export_group("Materials")
## How far from a site builders go for stones lying about (tiles), when
## the stores have none.
@export_range(2.0, 64.0) var stone_reach: float = 24.0

@export_group("The planner")
## A home is planned when this few places are left under the roofs (or
## someone has none).
@export_range(0, 20) var homes_spare_least: int = 1
## A storehouse when the stores have room for fewer units of food than this,
## or this much has gone bad in the last few days (and there is none yet, or
## not enough).
@export_range(0, 1000) var storage_room_least: int = 8
## A settlement of this many keeps a storehouse whatever its stores — builds
## its first, and builds again one that fell (the 200-year soaks, 2026-10-09).
@export_range(1, 1000) var first_store_from: int = 6
@export_range(0, 1000) var spoiled_from: int = 12
@export_range(1, 30) var spoiled_days: int = 3
## A well when the nearest water to drink is farther than this from the fire (tiles).
@export_range(1.0, 200.0, 0.5) var well_from: float = 14.0
## Where to build: this far from the fire (tiles), at least this far from
## any other building, and from any grave.
@export_range(1, 20) var site_nearest: int = 3
@export_range(2, 40) var site_farthest: int = 11
@export_range(0, 5) var site_spacing: int = 1
@export_range(0, 20) var site_grave_distance: int = 3
## How much each counts against a site: tiles from the fire, unevenness of the
## ground (height levels between its highest and lowest neighbour).
@export_range(0.0, 10.0, 0.05) var site_distance_cost: float = 1.0
@export_range(0.0, 10.0, 0.05) var site_unevenness_cost: float = 3.0

@export_group("Building")
## How pressing building is on the job board (homes when the roofs are full: more).
@export_range(0.0, 1.0, 0.01) var build_priority: float = 0.45
@export_range(0.0, 1.0, 0.01) var homes_priority: float = 0.7
## Strokes of building a builder gives a game minute, × (0.5 + their skill).
@export_range(0.05, 10.0, 0.05) var strokes_per_minute: float = 1.0
## A builder grows this much better at it with each finished building.
@export_range(0.0, 1.0, 0.01) var skill_per_building: float = 0.05

@export_group("Wear")
## What a flood takes from a building standing in it (of 1000), and a storm a day.
@export_range(0, 1000) var flood_damage: int = 300
@export_range(0, 1000) var storm_damage: int = 40
## Below this a building is repaired: this share of its work, and of its materials.
@export_range(0, 1000) var repair_below: int = 700
## The builders mend a building once it is worn below this (not only when it is
## damaged — the owner saw weathered buildings left so); a home nobody lives in is left to fall.
@export_range(0, 1000) var repair_from: int = 950
@export_range(0.0, 1.0, 0.01) var repair_labor_share: float = 0.5
@export_range(0.0, 1.0, 0.01) var repair_material_share: float = 0.25
## A home nobody has lived in for this many days begins to fall apart, this
## much a day; at nothing it is a ruin (a game year is 24 days: two years
## empty, and two more it falls in).
@export_range(0, 1000) var empty_home_days: int = 48
@export_range(0, 1000) var decay_per_day: int = 20

@export_group("Paths and bridges")
## Of what a tile has been walked, this much is remembered the next day
## (the rest fades: a path nobody walks grows over).
@export_range(0.5, 0.999, 0.001) var footfall_kept_per_day: float = 0.9
## Grass walked this much (remembered footfall: about a tenth of it is one
## day's steps, kept up) is worn to a path; a path walked less than
## `path_gone` grows over.
@export_range(1.0, 1000.0) var path_from: float = 30.0
@export_range(0.0, 1000.0) var path_gone: float = 8.0
## A bridge across (Crossing): land this near the fire (tiles, each way)
## that cannot be reached on foot — at least `cut_off_least` tiles of it —
## calls for one, over at most `crossing_span_most` tiles of water, once the
## settlement is `crossing_from_people` strong.
@export_range(4, 64) var crossing_reach: int = 24
@export_range(1, 10000) var cut_off_least: int = 12
@export_range(1, 32) var crossing_span_most: int = 8
@export_range(1, 100) var crossing_from_people: int = 6

@export_group("Storage")
## Food kept in a storehouse goes bad this much as fast.
@export_range(0.0, 1.0, 0.01) var storehouse_spoil_factor: float = 0.5


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, site_nearest < site_farthest, "site_nearest must be below site_farthest")
	_check(p, path_gone < path_from, "path_gone must be below path_from")
	return p
