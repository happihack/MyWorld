class_name GameClock
extends RefCounted
## The world's simulation clock (bible §9). One tick = one game minute.
##
## Pure data + math so it runs headless (tests, offline progression). The owner
## (WorldSession, later SimulationManager) calls advance() with real frame time
## and runs simulation work for the returned number of ticks.
##
## The calendar (bible §9.1): tick 0 is `TimeConfig.start_hour` on day 1 of
## spring in year 1; days turn at midnight; a year is `seasons_per_year`
## seasons of `days_per_season` days.

signal speed_changed(speed_index: int)
## A new day began (at midnight). `day`: counted from the world's first day (1).
signal day_started(day: int)
## A new season began. `season`: 0 … seasons - 1 (0 = spring).
signal season_changed(season: int, year: int)
signal year_started(year: int)

const SPEED_PAUSE := 0
const SPEED_NORMAL := 1
const SPEED_FAST := 2
const SPEED_VERY_FAST := 3

## Game minutes elapsed since the world was created.
var tick: int = 0
var speed_index: int = SPEED_NORMAL

## Game minutes (fractions included) the last advance() covered: what
## systems that move things evenly step by. 0 while paused.
var last_advance_minutes := 0.0

var _config: TimeConfig
var _accumulator: float = 0.0 # game minutes not yet turned into ticks


func _init(config: TimeConfig) -> void:
	_config = config


## Advances by real elapsed seconds; returns how many ticks elapsed.
func advance(real_delta: float) -> int:
	if real_delta <= 0.0 or is_paused():
		last_advance_minutes = 0.0
		return 0
	var clamped := minf(real_delta, _config.max_frame_delta_s)
	last_advance_minutes = clamped * speed_multiplier() / _config.real_seconds_per_game_minute
	_accumulator += last_advance_minutes
	var ticks := int(_accumulator)
	_accumulator -= ticks
	if ticks > 0:
		var before := tick
		tick += ticks
		_announce(before, tick)
	return ticks


## Jumps to `target` at once (M20: the time the player was away, lived in
## day-steps), telling of the days, seasons and years that began on the way.
func jump_to(target: int) -> void:
	if target <= tick:
		return
	var before := tick
	tick = target
	_accumulator = 0.0
	_announce(before, tick)


## Tells the world about the days, seasons and years that began between two ticks.
func _announce(before: int, after: int) -> void:
	var first := _config.day_index(before) + 1
	var last := _config.day_index(after)
	for index in range(first, last + 1):
		day_started.emit(index + 1)
		# The tick this day began on, for what the calendar says of it.
		var midnight := index * TimeConfig.MINUTES_PER_DAY - roundi(_config.start_hour * 60.0)
		if _config.day_of_season(midnight) == 1:
			season_changed.emit(_config.season_of(midnight), _config.year_of(midnight))
			if _config.season_of(midnight) == 0:
				year_started.emit(_config.year_of(midnight))


func set_speed(index: int) -> void:
	var clamped := clampi(index, 0, _config.speed_multipliers.size() - 1)
	if clamped == speed_index:
		return
	speed_index = clamped
	speed_changed.emit(speed_index)


func speed_multiplier() -> float:
	return _config.speed_multipliers[speed_index]


func is_paused() -> bool:
	return speed_multiplier() <= 0.0


## Fraction (0..1) of the way to the next tick; used to interpolate visuals.
func tick_fraction() -> float:
	return _accumulator


## The time of day, in hours (0 … 24, fractions included).
func hour() -> float:
	return (_config.minute_of_day(tick) + _accumulator) / 60.0


# --- the calendar -------------------------------------------------------------------------------

## The minute of the hour (0 … 59) and the hour of the day (0 … 23).
func minute() -> int:
	return _config.minute_of_day(tick) % 60


func hour_of_day() -> int:
	@warning_ignore("integer_division")
	return _config.minute_of_day(tick) / 60


## Days since the world began, counting its first day as 1.
func day() -> int:
	return _config.day_index(tick) + 1


func day_of_season() -> int:
	return _config.day_of_season(tick)


func day_of_year() -> int:
	return _config.day_of_year(tick)


## 0 … seasons - 1 (0 = spring).
func season() -> int:
	return _config.season_of(tick)


## The first year is year 1.
func year() -> int:
	return _config.year_of(tick)


## "06:30".
func format_time() -> String:
	return "%02d:%02d" % [hour_of_day(), minute()]


## "Year 3 · Spring · Day 4 · 06:30" (without the time: "Year 3 · Spring · Day 4").
func format_date(with_time: bool = true) -> String:
	var date := String(TranslationServer.translate(&"TIME_DATE")).format({
		"year": year(), "season": season_name(season()), "day": day_of_season()})
	if not with_time:
		return date
	return String(TranslationServer.translate(&"TIME_DATE_AND_TIME")).format({"date": date, "time": format_time()})


## What a season is called.
static func season_name(index: int) -> String:
	var key := "SEASON_%d" % index
	var name := String(TranslationServer.translate(key))
	if name == key: # more seasons than names (a config with five): numbered
		return String(TranslationServer.translate(&"SEASON_OTHER")).format({"number": index + 1})
	return name


func to_dict() -> Dictionary:
	return {"tick": tick, "speed_index": speed_index, "accumulator": _accumulator}


func from_dict(data: Dictionary) -> void:
	tick = maxi(0, int(data.get("tick", 0)))
	_accumulator = clampf(float(data.get("accumulator", 0.0)), 0.0, 0.999999)
	var index := int(data.get("speed_index", SPEED_NORMAL))
	speed_index = clampi(index, 0, _config.speed_multipliers.size() - 1)
