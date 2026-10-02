class_name ToolsConfig
extends ConfigBase
## The player's powers over the weather and the water (bible §23.2, M9.5):
## how much rain a held finger makes, what a gust moves, how deep a channel
## is carved — and when each tool shows itself.

@export_group("Rain")
## The cloud's radius (tiles), how high it hangs over the ground (world
## units), and how much rain falls from it in a second (units of rain, as
## the weather counts them: an hour of rain is one).
@export_range(1.0, 12.0, 0.5) var rain_radius: float = 3.0
@export_range(1.0, 12.0, 0.1) var rain_cloud_height: float = 4.0
@export_range(0.05, 5.0, 0.05) var rain_units_per_second: float = 0.6
## The rain reaches the ground in pulses this many seconds apart.
@export_range(0.1, 2.0, 0.05) var rain_pulse_seconds: float = 0.5
## What a unit of it does for the soil under the cloud (moisture, 0 … 255).
@export_range(0.0, 60.0, 0.5) var rain_moisture_per_unit: float = 9.0
## What a unit of it raises the river when it falls on the river — and this
## share of that when it falls on land (it runs off).
@export_range(0.0, 0.05, 0.0005) var rain_river_rise: float = 0.002
@export_range(0.0, 1.0, 0.05) var rain_runoff_share: float = 0.3
## From this much rain in one go it is no longer a gentle thing to do.
@export_range(0.5, 100.0, 0.5) var rain_moderate_units: float = 6.0
## The sky counts as clear (rain from it is uncanny) under this much cloud.
@export_range(0.0, 1.0, 0.05) var clear_sky_below: float = 0.5

@export_group("Wind")
## A swipe shorter than this on the ground (tiles) is no gust.
@export_range(0.1, 8.0, 0.1) var wind_min_swipe: float = 1.0
## How far a gust carries from where the swipe began, and how far to
## either side of its line (tiles).
@export_range(2.0, 32.0, 0.5) var wind_reach: float = 10.0
@export_range(0.5, 8.0, 0.1) var wind_width: float = 2.2
## The speed it gives the lightest things at full strength (tiles a
## second); things as heavy as `wind_light_kg` or heavier do not move.
@export_range(0.5, 14.0, 0.5) var wind_push: float = 6.0
@export_range(0.5, 200.0, 0.5) var wind_light_kg: float = 12.0
## A swipe this many times as fast as the slowest swipe is a gust at full strength.
@export_range(1.0, 10.0, 0.1) var wind_full_speed: float = 3.0
@export_range(0.05, 1.0, 0.05) var wind_least: float = 0.35
## How long the trees bend to it (seconds), and how far (as the weather's wind, 0 … 1).
@export_range(0.2, 6.0, 0.1) var wind_gust_seconds: float = 1.8
@export_range(0.0, 1.5, 0.05) var wind_gust_sway: float = 0.9
## When the weather's own wind blows at least this hard, a gust is nothing strange.
@export_range(0.0, 1.0, 0.05) var wind_ordinary_from: float = 0.5

@export_group("Water")
## How many height levels below the ground as it was made a channel may go,
## and how many tiles one stroke may carve.
@export_range(1, 3) var carve_depth_levels: int = 1
@export_range(1, 200) var carve_most_tiles: int = 24

@export_group("Reveal")
## The water tool shows itself after this many touches of the water.
@export_range(1, 20) var water_touches: int = 3
## A newly shown tool glows for this many seconds.
@export_range(0.0, 30.0, 0.5) var glow_seconds: float = 6.0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, rain_units_per_second > 0.0 and rain_pulse_seconds > 0.0, "rain_units_per_second and rain_pulse_seconds must be more than nothing")
	_check(p, wind_reach > wind_min_swipe, "wind_reach must be more than wind_min_swipe")
	_check(p, wind_least <= 1.0 and wind_full_speed >= 1.0, "wind_least must be at most 1 and wind_full_speed at least 1")
	return p
