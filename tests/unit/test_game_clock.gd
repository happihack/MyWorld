extends TestCase

var clock: GameClock


func before_each() -> void:
	clock = GameClock.new(Config.time)


func test_half_second_is_one_tick_at_normal() -> void:
	assert_eq(clock.advance(0.25), 0)
	assert_eq(clock.advance(0.25), 1)
	assert_eq(clock.tick, 1)


func test_partial_ticks_accumulate() -> void:
	clock.advance(0.1)
	assert_near(clock.tick_fraction(), 0.2)


func test_large_delta_is_clamped() -> void:
	assert_eq(clock.advance(10.0), 0)
	assert_near(clock.tick_fraction(), 0.5) # 0.25 s max -> half a tick


func test_pause_and_speeds() -> void:
	var seen := []
	clock.speed_changed.connect(func(i: int) -> void: seen.append(i))
	clock.set_speed(GameClock.SPEED_PAUSE)
	assert_true(clock.is_paused())
	assert_eq(clock.advance(0.25), 0)
	clock.set_speed(GameClock.SPEED_FAST)
	assert_eq(clock.advance(0.25), 2)
	clock.set_speed(99)
	assert_eq(clock.speed_index, GameClock.SPEED_VERY_FAST)
	clock.set_speed(GameClock.SPEED_VERY_FAST) # no change -> no signal
	assert_eq(seen, [0, 2, 3])


func test_roundtrip() -> void:
	clock.set_speed(GameClock.SPEED_FAST)
	clock.advance(0.2)
	var copy := GameClock.new(Config.time)
	copy.from_dict(clock.to_dict())
	assert_eq(copy.tick, clock.tick)
	assert_eq(copy.speed_index, clock.speed_index)
	assert_near(copy.tick_fraction(), clock.tick_fraction())


func test_corrupt_data_sanitized() -> void:
	clock.from_dict({"tick": -5, "speed_index": 42, "accumulator": 7.0})
	assert_eq(clock.tick, 0)
	assert_eq(clock.speed_index, GameClock.SPEED_VERY_FAST)
	assert_true(clock.tick_fraction() < 1.0)


# --- the calendar (M6.1) --------------------------------------------------------------------------

func test_clock_calendar() -> void:
	var config := Config.time
	var day := TimeConfig.MINUTES_PER_DAY
	var start := roundi(config.start_hour * 60.0)
	# The world begins at the start hour on day 1 of spring in year 1.
	assert_eq(clock.hour_of_day(), int(config.start_hour))
	assert_eq(clock.minute(), 0)
	assert_eq(clock.day(), 1)
	assert_eq(clock.day_of_season(), 1)
	assert_eq(clock.day_of_year(), 1)
	assert_eq(clock.season(), 0)
	assert_eq(clock.year(), 1)
	assert_eq(clock.format_time(), "%02d:00" % int(config.start_hour))
	assert_eq(clock.format_date(), "Year 1 · Spring · Day 1 · %02d:00" % int(config.start_hour))
	assert_eq(clock.format_date(false), "Year 1 · Spring · Day 1")
	# Minutes roll into hours...
	clock.tick = 59
	assert_eq(clock.minute(), 59)
	assert_eq(clock.hour_of_day(), int(config.start_hour))
	clock.tick = 60
	assert_eq(clock.minute(), 0)
	assert_eq(clock.hour_of_day(), int(config.start_hour) + 1)
	clock.tick = 90
	assert_eq(clock.format_time(), "%02d:30" % (int(config.start_hour) + 1))
	assert_near(clock.hour(), config.start_hour + 1.5, 0.001)
	# ...hours into days, at midnight...
	clock.tick = day - start - 1
	assert_eq(clock.format_time(), "23:59")
	assert_eq(clock.day(), 1)
	clock.tick = day - start
	assert_eq(clock.format_time(), "00:00")
	assert_eq(clock.day(), 2)
	assert_eq(clock.day_of_season(), 2)
	# ...days into seasons...
	clock.tick = config.days_per_season * day - start - 1
	assert_eq(clock.season(), 0)
	assert_eq(clock.day_of_season(), config.days_per_season)
	clock.tick += 1
	assert_eq(clock.season(), 1)
	assert_eq(clock.day_of_season(), 1)
	assert_eq(clock.format_date(false), "Year 1 · Summer · Day 1")
	assert_eq(clock.day_of_year(), config.days_per_season + 1)
	# ...seasons into years.
	clock.tick = config.ticks_per_year() - start - 1
	assert_eq(clock.year(), 1)
	assert_eq(clock.season(), config.seasons_per_year - 1)
	assert_eq(clock.day_of_year(), config.days_per_year())
	assert_eq(clock.format_date(), "Year 1 · Winter · Day %d · 23:59" % config.days_per_season)
	clock.tick += 1
	assert_eq(clock.year(), 2)
	assert_eq(clock.season(), 0)
	assert_eq(clock.day_of_season(), 1)
	assert_eq(clock.day(), config.days_per_year() + 1)
	assert_eq(clock.format_date(), "Year 2 · Spring · Day 1 · 00:00")
	clock.tick = config.ticks_per_year() * 30 + 5 * day + 90
	assert_eq(clock.year(), 31)
	assert_eq(clock.format_date(), "Year 31 · Spring · Day 6 · %02d:30" % (int(config.start_hour) + 1))
	# The four seasons have names; a calendar with more numbers the rest.
	assert_eq(GameClock.season_name(0), "Spring")
	assert_eq(GameClock.season_name(1), "Summer")
	assert_eq(GameClock.season_name(2), "Autumn")
	assert_eq(GameClock.season_name(3), "Winter")
	assert_eq(GameClock.season_name(4), "Season 5")
	# Another calendar: the numbers follow the configuration.
	var other := TimeConfig.new()
	other.days_per_season = 3
	other.seasons_per_year = 2
	other.start_hour = 0.0
	var short := GameClock.new(other)
	short.tick = 3 * day
	assert_eq(short.season(), 1)
	short.tick = 6 * day
	assert_eq(short.year(), 2)
	assert_eq(short.format_date(), "Year 2 · Spring · Day 1 · 00:00")
	# The speed multipliers (bible §9.2): 0, 1, 4, 16 — in ticks per real half second.
	var fresh := GameClock.new(config)
	var expected := [0, 1, 4, 16]
	for speed in 4:
		fresh.set_speed(speed)
		assert_eq(fresh.speed_multiplier(), float(expected[speed]))
		var ticks := 0
		for i in 2:
			ticks += fresh.advance(0.25)
		assert_eq(ticks, expected[speed], "speed %d" % speed)


func test_days_seasons_and_years_are_announced() -> void:
	var config := Config.time
	var day := TimeConfig.MINUTES_PER_DAY
	var start := roundi(config.start_hour * 60.0)
	var days: Array = []
	var seasons: Array = []
	var years: Array = []
	clock.day_started.connect(func(d: int) -> void: days.append(d))
	clock.season_changed.connect(func(season: int, year: int) -> void: seasons.append([season, year]))
	clock.year_started.connect(func(year: int) -> void: years.append(year))
	clock.set_speed(GameClock.SPEED_VERY_FAST)
	# Up to a minute before the first midnight: nothing.
	clock.tick = day - start - 2
	clock.advance(0.03)
	assert_eq(days.size(), 0)
	# Over midnight: the second day, once.
	clock.tick = day - start - 1
	clock.advance(0.25)
	assert_eq(days, [2])
	clock.advance(0.25)
	assert_eq(days, [2])
	assert_eq(seasons.size(), 0)
	# Into the second season.
	clock.tick = config.days_per_season * day - start - 1
	clock.advance(0.25)
	assert_eq(days, [2, config.days_per_season + 1])
	assert_eq(seasons, [[1, 1]])
	assert_eq(years.size(), 0)
	# Into the second year: a day, a season (spring again) and a year.
	clock.tick = config.ticks_per_year() - start - 1
	clock.advance(0.25)
	assert_eq(days[-1], config.days_per_year() + 1)
	assert_eq(seasons[-1], [0, 2])
	assert_eq(years, [2])
	# Paused, nothing begins.
	clock.set_speed(GameClock.SPEED_PAUSE)
	clock.tick = 2 * config.ticks_per_year() - start - 1
	clock.advance(0.25)
	assert_eq(years, [2])


func test_the_calendar_of_a_tick() -> void:
	var config := Config.time
	var start := roundi(config.start_hour * 60.0)
	assert_eq(config.day_index(0), 0)
	assert_eq(config.day_index(TimeConfig.MINUTES_PER_DAY - start), 1)
	assert_eq(config.year_of(0), 1)
	assert_eq(config.year_of(config.ticks_per_year() - start), 2)
	assert_eq(config.season_of(0), 0)
	assert_eq(config.day_of_season(0), 1)
	assert_eq(config.day_of_year(config.ticks_per_year() - start - 1), config.days_per_year())
	# Before the world began (people are born then): the calendar runs backwards without a break.
	assert_eq(config.day_index(-start - 1), -1)
	assert_eq(config.year_of(-start - 1), 0)
	assert_eq(config.season_of(-start - 1), config.seasons_per_year - 1)
	assert_eq(config.day_of_season(-start - 1), config.days_per_season)
