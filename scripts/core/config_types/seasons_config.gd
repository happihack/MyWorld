class_name SeasonsConfig
extends ConfigBase
## What the seasons do to the world (bible §10.2): the colour of what
## grows, leaves falling, snow lying, water freezing.
##
## Values "by season" have four entries (0 = spring) and stand for the
## middle of each season; in between they go over into one another.

@export_group("What grows")
## What leaves turn towards, and how far (0 = as the palette has them).
@export var foliage: PackedColorArray = PackedColorArray([
	Color(0.50, 0.78, 0.30), Color(0.30, 0.56, 0.24), Color(0.82, 0.54, 0.20), Color(0.46, 0.40, 0.30)])
@export var foliage_strength: PackedFloat32Array = PackedFloat32Array([0.30, 0.0, 0.72, 0.55])
## Some trees turn another colour (autumn is not one orange).
@export var foliage_other: PackedColorArray = PackedColorArray([
	Color(0.58, 0.80, 0.36), Color(0.30, 0.56, 0.24), Color(0.72, 0.34, 0.16), Color(0.40, 0.36, 0.30)])
## The same for the green of the ground.
@export var ground: PackedColorArray = PackedColorArray([
	Color(0.47, 0.74, 0.30), Color(0.40, 0.66, 0.28), Color(0.70, 0.62, 0.30), Color(0.56, 0.54, 0.40)])
@export var ground_strength: PackedFloat32Array = PackedFloat32Array([0.30, 0.0, 0.50, 0.60])
## How much of the leaves of trees that shed them is gone (0 … 1).
@export var bare: PackedFloat32Array = PackedFloat32Array([0.10, 0.0, 0.30, 0.85])
## How many leaves are in the air (0 … 1).
@export var leaf_fall: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.55, 0.05])
@export var leaf_color: Color = Color(0.85, 0.46, 0.14, 0.9)

@export_group("Snow")
## How much snow an hour of snowfall lays (1 = everything white), what an
## hour melts for every degree above freezing, and what an hour of rain takes.
@export_range(0.0, 1.0, 0.005) var snow_per_hour: float = 0.07
@export_range(0.0, 1.0, 0.001) var melt_per_degree_hour: float = 0.002
@export_range(0.0, 1.0, 0.005) var rain_melt_per_hour: float = 0.03
@export var snow_color: Color = Color(0.84, 0.88, 0.94)

@export_group("Frost")
## The ground's frost (0 … 1): what an hour adds for every degree below
## freezing, and takes for every degree above.
@export_range(0.0, 1.0, 0.001) var freeze_per_degree_hour: float = 0.012
@export_range(0.0, 1.0, 0.001) var thaw_per_degree_hour: float = 0.004
## Frozen from this much frost; thawed again below that much.
@export_range(0.0, 1.0, 0.01) var frozen_from: float = 0.6
@export_range(0.0, 1.0, 0.01) var thawed_below: float = 0.3
## Water no deeper than this (world units) freezes over, and carries.
@export_range(0.0, 5.0, 0.01) var ice_depth: float = 0.3
@export var ice_color: Color = Color(0.80, 0.89, 0.95)

@export_group("Life")
## Below the first temperature (°C) no bird sings and no cricket chirps;
## from the second they do as ever.
@export_range(-30.0, 40.0, 0.5) var birds_from: float = -2.0
@export_range(-30.0, 40.0, 0.5) var birds_full: float = 8.0
@export_range(-30.0, 40.0, 0.5) var crickets_from: float = 6.0
@export_range(-30.0, 40.0, 0.5) var crickets_full: float = 14.0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	for values: Variant in [foliage, foliage_strength, foliage_other, ground, ground_strength, bare, leaf_fall]:
		_check(p, values.size() == 4, "values by season need four entries")
	_check(p, thawed_below < frozen_from, "thawed_below must be less than frozen_from")
	return p
