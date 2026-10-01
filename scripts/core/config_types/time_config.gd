class_name TimeConfig
extends ConfigBase
## Clock, calendar, speeds and offline progression (bible §9, D-04, D-09).

const MINUTES_PER_DAY := 1440

## Real seconds per game minute at Normal speed (0.5 => a day lasts 12 real minutes).
@export_range(0.05, 10.0, 0.05) var real_seconds_per_game_minute: float = 0.5
@export_range(1, 60) var days_per_season: int = 6
@export_range(1, 12) var seasons_per_year: int = 4
## The hour of the day at which a new world begins (tick 0).
@export_range(0.0, 23.75, 0.25) var start_hour: float = 6.0
## Pause, Normal, Fast, Very Fast.
@export var speed_multipliers: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 4.0, 16.0])
## Longest real frame time the clock will consume at once (prevents a huge
## catch-up burst after a hitch or breakpoint; offline time is handled separately).
@export_range(0.016, 2.0, 0.001) var max_frame_delta_s: float = 0.25
@export_range(0.0, 240.0) var offline_full_rate_hours: float = 24.0
@export_range(0.0, 720.0) var offline_cap_hours: float = 72.0
## Minimum real absence before the "While You Were Gone" summary is shown.
@export_range(0.0, 1440.0) var wywg_min_absence_minutes: float = 10.0


func days_per_year() -> int:
	return days_per_season * seasons_per_year


## Minutes since midnight at `tick`.
func minute_of_day(tick: int) -> int:
	return posmod(tick + roundi(start_hour * 60.0), MINUTES_PER_DAY)


## One tick is one game minute (see GameClock).
func ticks_per_year() -> int:
	return days_per_year() * MINUTES_PER_DAY


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, real_seconds_per_game_minute > 0.0, "real_seconds_per_game_minute must be > 0")
	_check(p, days_per_season >= 1 and seasons_per_year >= 1, "calendar sizes must be >= 1")
	_check(p, speed_multipliers.size() == 4, "speed_multipliers needs 4 entries (pause, normal, fast, very fast)")
	_check(p, speed_multipliers.size() > 0 and speed_multipliers[0] == 0.0, "speed_multipliers[0] must be 0 (pause)")
	_check(p, max_frame_delta_s > 0.0, "max_frame_delta_s must be > 0")
	_check(p, offline_cap_hours >= offline_full_rate_hours, "offline_cap_hours must be >= offline_full_rate_hours")
	return p
