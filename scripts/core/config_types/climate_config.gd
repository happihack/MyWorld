class_name ClimateConfig
extends ConfigBase
## A climate (bible §10.1): how the weather goes from one state to the
## next in each season (a Markov chain), how warm it is, how the wind
## blows, how much it rains — and when a run of weather counts as a
## drought, a heat wave or a cold snap. One file per climate:
## data/configuration/weather_<climate>.tres.

@export var id: StringName = &"temperate"

@export_group("The chain")
## The weather is looked at anew every so many game minutes.
@export_range(10, 1440) var step_minutes: int = 180
## For each season: what follows what, how likely — {from: {to: weight}}.
## (Weights of a row need not add up to one; a state without a row stays.)
@export var spring: Dictionary = {}
@export var summer: Dictionary = {}
@export var autumn: Dictionary = {}
@export var winter: Dictionary = {}

@export_group("Temperature")
## The mean of a day in the middle of each season (°C; 0 = spring), and
## how far the afternoon is above it and the small hours below.
@export var season_temperature: PackedFloat32Array = PackedFloat32Array([11.0, 21.0, 10.0, -2.0])
@export var daily_swing: PackedFloat32Array = PackedFloat32Array([5.0, 6.0, 4.5, 3.5])
@export_range(0.0, 24.0, 0.25) var warmest_hour: float = 15.0
## What each kind of weather adds (°C).
@export var state_temperature: Dictionary = {
	&"clear": 1.0, &"cloudy": -0.5, &"rain": -2.5, &"heavy_rain": -3.5, &"storm": -4.0, &"wind": -1.5, &"snow": -3.0, &"fog": -1.0, &"blizzard": -6.0,
}
## Warmer and colder air comes and goes over days: by up to this much
## (°C) either way, changing over about this many days.
@export_range(0.0, 15.0, 0.1) var air_mass_degrees: float = 3.5
@export_range(0.5, 30.0, 0.5) var air_mass_days: float = 3.0
## A change of weather is felt over this many game minutes.
@export_range(1, 600) var temperature_blend_minutes: int = 60
## Colder by this much for every level of height above the settlement,
## and by this much on or beside water.
@export_range(0.0, 3.0, 0.05) var height_lapse: float = 0.35
@export_range(0.0, 10.0, 0.1) var water_cooling: float = 1.0
## At or below this what falls is snow.
@export_range(-20.0, 20.0, 0.5) var snow_below: float = 1.0

@export_group("Sky")
## What falls in an hour (units; a day with `rain_day_from` of them is a rainy day).
@export var precipitation: Dictionary = {&"rain": 1.0, &"heavy_rain": 2.5, &"storm": 3.0, &"snow": 0.7, &"blizzard": 1.4}
@export_range(0.0, 100.0, 0.1) var rain_day_from: float = 2.0
## How much of the sky is covered (0 … 1), and how foggy it is.
@export var cloud_cover: Dictionary = {
	&"clear": 0.08, &"cloudy": 0.65, &"rain": 0.85, &"heavy_rain": 1.0, &"storm": 1.0, &"wind": 0.3, &"snow": 0.85, &"fog": 0.55, &"blizzard": 1.0,
}
@export var fog: Dictionary = {&"fog": 1.0, &"rain": 0.12, &"heavy_rain": 0.3, &"storm": 0.3, &"snow": 0.3, &"blizzard": 0.55}
## How hard the wind blows (0 … 1): the least and the most, for each kind of weather.
@export var wind_speed: Dictionary = {
	&"clear": Vector2(0.05, 0.3), &"cloudy": Vector2(0.15, 0.4), &"rain": Vector2(0.2, 0.5), &"heavy_rain": Vector2(0.35, 0.65),
	&"storm": Vector2(0.75, 1.0), &"wind": Vector2(0.6, 0.9), &"snow": Vector2(0.1, 0.45), &"fog": Vector2(0.0, 0.1),
	&"blizzard": Vector2(0.75, 1.0),
}
## The wind turns by up to this many degrees from one look at the weather to the next.
@export_range(0.0, 180.0, 1.0) var wind_turn_degrees: float = 50.0

@export_group("Conditions")
## A drought: less than this much rain in this many days (not in winter).
@export_range(1, 60) var drought_days: int = 7
@export_range(0.0, 100.0, 0.5) var drought_rain_below: float = 2.0
## A heat wave: this many days in a row whose warmest hour was at least
## this warm; a cold snap: whose coldest was at most this cold.
@export_range(1, 30) var heat_wave_days: int = 2
@export_range(-20.0, 60.0, 0.5) var heat_wave_from: float = 27.5
@export_range(1, 30) var cold_snap_days: int = 2
@export_range(-60.0, 20.0, 0.5) var cold_snap_below: float = -8.0
## How many days back the weather is remembered.
@export_range(10, 400) var history_days: int = 40


## The season's table: {from: {to: weight}}.
func table(season: int) -> Dictionary:
	match posmod(season, 4):
		0:
			return spring
		1:
			return summer
		2:
			return autumn
	return winter


func value_for(values: Dictionary, state: StringName, default: float = 0.0) -> float:
	var value: Variant = values.get(state, values.get(String(state), default))
	return float(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else default


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, step_minutes >= 10 and 1440 % step_minutes == 0, "step_minutes must divide a day")
	_check(p, season_temperature.size() == 4 and daily_swing.size() == 4, "temperatures need a value per season")
	for season in 4:
		var rows := table(season)
		_check(p, not rows.is_empty(), "season %d has no weather table" % season)
		for from: Variant in rows:
			_check(p, WeatherSystem.STATES.has(StringName(str(from))), "season %d: unknown weather '%s'" % [season, from])
			var row: Variant = rows[from]
			if typeof(row) != TYPE_DICTIONARY:
				p.append("season %d: the row of '%s' is not a table" % [season, from])
				continue
			var total := 0.0
			for to: Variant in row:
				_check(p, WeatherSystem.STATES.has(StringName(str(to))), "season %d: unknown weather '%s'" % [season, to])
				_check(p, float(row[to]) >= 0.0, "season %d: a negative weight (%s -> %s)" % [season, from, to])
				total += float(row[to])
			_check(p, total > 0.0, "season %d: nothing follows '%s'" % [season, from])
	return p
