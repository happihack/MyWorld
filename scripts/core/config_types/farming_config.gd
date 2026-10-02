class_name FarmingConfig
extends ConfigBase
## Fields and crops (bible §10.4, §11): how grain grows, what the soil does
## from day to day, and how much field a farmer keeps.

@export_group("Fields")
## Plots (tiles) of field one farmer keeps.
@export_range(1, 64) var plots_per_farmer: int = 8
## Fields lie between this many and this many tiles from the fire.
@export_range(1, 32) var site_min_distance: int = 3
@export_range(2, 64) var site_max_distance: int = 9
## Seasons (0 = spring) in which people sow.
@export var sowing_seasons: PackedInt32Array = PackedInt32Array([0, 1])
## Nothing is sown that could not ripen before winter: counted with this
## share of the growing days there are left (below 1: a little hope).
@export_range(0.1, 2.0, 0.05) var ripen_margin: float = 1.0
## A harvested plot lies fallow this many days before it is sown again.
@export_range(0.0, 60.0, 0.5) var fallow_days: float = 1.0

@export_group("Growth")
## Game days from sowing to ripe grain, in good soil and a growing season.
@export_range(0.5, 120.0, 0.5) var grow_days: float = 14.0
## How well things grow in each season (0 = spring): nothing grows in winter.
@export var season_growth: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 0.6, 0.0])
## Soil moisture (0 … 255) below which a crop stands still and wilts, and
## from which it grows as well as it can (in between: in proportion).
@export_range(0, 255) var wilt_below: int = 70
@export_range(0, 255) var good_from: int = 130
## Days of dry soil that kill a healthy crop, and days of moist soil in
## which a wilted one recovers.
@export_range(0.25, 60.0, 0.25) var wilt_days: float = 3.0
@export_range(0.25, 60.0, 0.25) var recover_days: float = 4.0
## A crop looks dry (and yields less) below this much vigour (0 … 1000).
@export_range(0, 1000) var looks_dry_below: int = 500
## How much faster a crop grows that has been tended in the last day.
@export_range(0.0, 2.0, 0.01) var tend_bonus: float = 0.25
## A crop wants tending again after this many game minutes.
@export_range(60, 14400) var tend_every_minutes: int = 1440
## Growth is worked out this often, in game minutes.
@export_range(1, 1440) var settle_minutes: int = 60

@export_group("Harvest")
## Units of grain a plot yields in fertile soil with a healthy crop.
@export_range(1, 100) var yield_units: int = 6
## What a harvest takes out of the soil's fertility (0 … 255), what a day
## of lying fallow gives back, and the least a plot is worn down to.
@export_range(0, 255) var fertility_cost: int = 18
@export_range(0, 255) var fallow_gain_per_day: int = 2
@export_range(0, 255) var fertility_floor: int = 30

@export_group("Soil")
## Placeholder for the weather to come (M9): the chance of rain on a day, by
## season, and what a day of rain gives a field's soil.
@export var rain_chance: PackedFloat32Array = PackedFloat32Array([0.45, 0.3, 0.5, 0.4])
@export_range(0, 255) var rain_moisture: int = 45
## What a day takes: drying out, and what a growing crop drinks.
@export_range(0, 255) var evaporation_per_day: int = 14
@export_range(0, 255) var crop_draw_per_day: int = 10
## Ground water: a field's soil comes back towards what the land there
## holds by itself (wet by the river, dry far from it), this share a day.
@export_range(0.0, 1.0, 0.01) var seep_share: float = 0.25

@export_group("Seed")
## Units of grain a plot is sown with. They are kept back from what is
## eaten (see Stockpile.set_reserve) — unless hunger has the settlement eat
## its seed.
@export_range(0, 20) var seed_per_plot: int = 1
## What a plot sown without seed kept for it (with what could be gleaned)
## yields, relative to a proper sowing.
@export_range(0.0, 1.0, 0.01) var thin_yield: float = 0.5

@export_group("Dry spells")
## This many days without rain in a row are a dry spell.
@export_range(1, 60) var dry_spell_days: int = 5

@export_group("Work")
## Game minutes of work to till and sow a plot, to tend one, to clear a
## failed crop.
@export_range(1.0, 600.0, 1.0) var sow_minutes: float = 40.0
@export_range(1.0, 600.0, 1.0) var tend_minutes: float = 20.0
@export_range(1.0, 600.0, 1.0) var clear_minutes: float = 20.0


func season_factor(season: int) -> float:
	return season_growth[season] if season >= 0 and season < season_growth.size() else 0.0


func sows_in(season: int) -> bool:
	return sowing_seasons.has(season)


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, wilt_below < good_from, "wilt_below must be less than good_from")
	_check(p, site_min_distance < site_max_distance, "site_min_distance must be less than site_max_distance")
	_check(p, grow_days > 0.0 and wilt_days > 0.0 and recover_days > 0.0, "grow_days, wilt_days and recover_days must be more than nothing")
	_check(p, season_growth.size() >= 1, "season_growth needs a value per season")
	_check(p, rain_chance.size() >= 1, "rain_chance needs a value per season")
	return p
