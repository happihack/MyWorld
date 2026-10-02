extends TestCase
## The weather (M9.1, bible §10.1): a Markov chain per season, the same in
## the same world; temperature by season, hour, weather and place; wind;
## the record of what fell; drought, heat wave and cold snap found out
## from that record; the fields' rain; saved with the world.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V13_FIXTURE := "res://tests/fixtures/saves/v13_world.sav"
const V13_ID := "w1790920521_22243e94"
const DAY := 1440
## Tick 0 is six in the morning: this is the tick of a day's midnight.
const WET: Array[StringName] = [&"rain", &"heavy_rain", &"snow"]

var session: WorldSession
var weather: WeatherSystem
var clock: GameClock
var climate: ClimateConfig
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	weather = session.weather
	clock = session.clock
	climate = Config.climate


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(config: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([config, knob, config.get(knob)])
	config.set(knob, value)


## The tick at which a calendar day begins (its midnight).
func _midnight(day: int) -> int:
	return day * DAY - roundi(Config.time.start_hour * 60.0)


## A weather of its own, with a clock of its own (no world around it).
func _alone(seed_value: int = 12345) -> WeatherSystem:
	var own := WeatherSystem.new()
	own.bind(GameClock.new(Config.time), climate, seed_value)
	return own


## Lets time pass for the weather (and the settlement's housekeeping), hour by hour.
func _hours(hours: int) -> void:
	for hour in hours:
		clock.tick += 60
		weather.advance_to(clock.tick)
		session.settlement.step(clock.tick)


func test_the_climate_is_sound() -> void:
	assert_eq(climate.validate().size(), 0, str(climate.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	assert_eq(climate.id, &"temperate")
	assert_eq(WeatherSystem.STATES.size(), 8, "the bible's eight")
	for season in 4:
		var rows := climate.table(season)
		for kind in WeatherSystem.STATES:
			assert_true(rows.has(kind), "season %d says what follows %s" % [season, kind])
	# A table with nonsense in it is found out.
	var broken := ClimateConfig.new()
	broken.spring = {&"clear": {&"hail": 1.0}}
	assert_true(broken.validate().size() >= 2)
	for kind in WeatherSystem.STATES:
		assert_true(MemoryText.has("WEATHER_" + String(kind).to_upper()), "a word for %s" % kind)


func test_weather_transitions() -> void:
	# A hundred and fifty years of weather: what followed what, season by season.
	var own := _alone()
	var own_clock := own._clock
	var followed := [{}, {}, {}, {}] # season -> {from -> {to -> times}}
	var changes := [0]
	own.changed.connect(func(_old: StringName, _now: StringName) -> void: changes[0] += 1)
	var step := climate.step_minutes
	var steps := 150 * Config.time.days_per_year() * (DAY / step)
	own_clock.tick = _midnight(0)
	own.advance_to(own_clock.tick)
	for i in steps:
		var from := own.state
		own_clock.tick += step
		var season := Config.time.season_of(own_clock.tick)
		own.advance_to(own_clock.tick)
		var row: Dictionary = followed[season].get(from, {})
		row[own.state] = int(row.get(own.state, 0)) + 1
		followed[season][from] = row
	assert_true(steps >= 28_000, "%d looks at the sky" % steps)
	assert_true(changes[0] > steps / 4 and changes[0] < steps, "it changes, and it stays (%d changes)" % changes[0])
	# Each row of each season's table, where it came up often enough: as often as the table says.
	# (What falls is rain or snow by how cold it is: the two count together.)
	var rows_checked := 0
	for season in 4:
		var table := climate.table(season)
		for from: StringName in followed[season]:
			var seen: Dictionary = followed[season][from]
			var total := 0
			for to: StringName in seen:
				total += int(seen[to])
			if total < 1000:
				continue
			rows_checked += 1
			var row: Dictionary = table[from]
			var weights := 0.0
			for to: Variant in row:
				weights += float(row[to])
			var wet_expected := 0.0
			var wet_seen := 0.0
			for kind in WeatherSystem.STATES:
				var expected := climate.value_for(row, kind) / weights
				var share := float(int(seen.get(kind, 0))) / total
				if WET.has(kind):
					wet_expected += expected
					wet_seen += share
				else:
					assert_near(share, expected, 0.045, "season %d: %s -> %s (%d times)" % [season, from, kind, total])
			assert_near(wet_seen, wet_expected, 0.045, "season %d: %s -> rain or snow" % [season, from])
	assert_true(rows_checked >= 8, "%d rows came up often enough to judge" % rows_checked)
	# The seasons have tables of their own: summer skies stay clear longer than spring's.
	var spring_clear: Dictionary = followed[0][&"clear"]
	var summer_clear: Dictionary = followed[1][&"clear"]
	var spring_share := float(spring_clear[&"clear"]) / _sum(spring_clear)
	var summer_share := float(summer_clear[&"clear"]) / _sum(summer_clear)
	assert_true(summer_share > spring_share + 0.05, "clear stays clear: summer %.2f, spring %.2f" % [summer_share, spring_share])
	# Snow belongs to winter, storms mostly to autumn.
	assert_true(_seen(followed[3], &"snow") > _seen(followed[1], &"snow") * 20 + 100)
	assert_true(_seen(followed[2], &"storm") > _seen(followed[0], &"storm"))


func _sum(row: Dictionary) -> float:
	var total := 0.0
	for to: Variant in row:
		total += float(row[to])
	return total


## How often a kind of weather was arrived at in a season.
func _seen(season_rows: Dictionary, kind: StringName) -> int:
	var times := 0
	for from: Variant in season_rows:
		times += int((season_rows[from] as Dictionary).get(kind, 0))
	return times


func test_the_same_world_has_the_same_weather() -> void:
	var one := _alone(4242)
	var two := _alone(4242)
	var other := _alone(4243)
	var same := 0
	var differs := 0
	for hour in 24 * 60:
		var tick := hour * 60
		one._clock.tick = tick
		one.advance_to(tick) # hour by hour
		if hour % 31 == 0:
			two._clock.tick = tick
			two.advance_to(tick) # in leaps
			assert_eq([two.state, two.since_tick], [one.state, one.since_tick], "at hour %d" % hour)
			assert_near(two.wind_degrees, one.wind_degrees, 0.001)
			assert_near(two.temperature(tick), one.temperature(tick), 0.0001)
			same += 1
		other._clock.tick = tick
		other.advance_to(tick)
		differs += 1 if other.state != one.state else 0
	assert_true(same >= 40)
	assert_true(differs > 24 * 60 / 5, "another world has other weather (%d hours of %d)" % [differs, 24 * 60])
	two._clock.tick = one._clock.tick
	two.advance_to(two._clock.tick)
	for day in 60:
		assert_near(two.rainfall_on(day), one.rainfall_on(day), 0.0001, "the same record, however time was cut up (day %d)" % day)
	# It changes only when it is looked at anew: every three hours, by the calendar.
	var watched := _alone(99)
	var at: Array = []
	for minute in 20 * DAY:
		var was := watched.since_tick
		watched._clock.tick = minute
		watched.advance_to(minute)
		if watched.since_tick != was:
			at.append(watched.since_tick)
	assert_true(at.size() > 20)
	for tick: int in at:
		assert_eq(Config.time.minute_of_day(tick) % climate.step_minutes, 0, "at %d" % tick)
	# A clock set back changes nothing that has been; set far ahead, it is made up for within bounds.
	var state := watched.state
	watched.advance_to(100)
	assert_eq(watched.state, state)
	var done := watched.steps_done
	watched._clock.tick = 5000 * DAY
	watched.advance_to(watched._clock.tick)
	assert_true(watched.steps_done - done <= WeatherSystem.MAX_STEPS_AT_ONCE)
	assert_eq(watched.next_step_tick() > watched._clock.tick, true)


func test_weather_changes_are_announced() -> void:
	var heard: Array = []
	var on_bus := func(old: StringName, now: StringName) -> void: heard.append([old, now])
	EventBus.weather_changed.connect(on_bus)
	weather.hold(WeatherSystem.STORM, clock.tick + 600)
	EventBus.weather_changed.disconnect(on_bus)
	assert_eq(heard, [[&"clear", &"storm"]])
	assert_eq([weather.state, weather.previous, weather.since_tick], [&"storm", &"clear", clock.tick])
	assert_true(weather.is_held() and weather.is_raining() and not weather.is_snowing())
	assert_near(weather.precipitation(), 3.0, 0.001)
	assert_near(weather.cloud_cover(), 1.0, 0.001)
	assert_true(weather.wind().length() <= 1.0)
	# A storm is written down — once a day at most.
	var storm := session.events.latest(Chronicler.TYPE_STORM)
	assert_not_null(storm)
	assert_eq(EventText.text(storm, session.people, session.events), "A storm is breaking")
	weather.hold(WeatherSystem.CLEAR, clock.tick + 60)
	weather.hold(WeatherSystem.STORM, clock.tick + 600)
	assert_eq(session.events.count_of(Chronicler.TYPE_STORM), 1)
	# Held, the chain stands still; let go, it goes on.
	_hours(9)
	assert_eq(weather.state, &"storm")
	assert_true(weather.wind_speed >= 0.0)
	_hours(3)
	assert_false(weather.is_held())
	var seen := {}
	for hour in 24 * 6:
		_hours(1)
		seen[weather.state] = true
	assert_true(seen.size() >= 3, "it goes on by itself (%s)" % str(seen.keys()))
	# The words for it.
	assert_eq(UIText.weather_name(&"heavy_rain"), "Heavy rain")
	assert_eq(UIText.temperature_text(-3.4), "-3°")
	assert_true(weather.debug_text().begins_with("weather: "))
	# Nonsense is not held.
	weather.hold(&"hail", clock.tick + 600)
	assert_true(WeatherSystem.STATES.has(weather.state))
	# The game's clock moves it.
	session.set_process(true)
	var steps := weather.steps_done
	clock.tick += climate.step_minutes * 3
	await wait_frames(2)
	session.set_process(false)
	assert_true(weather.steps_done >= steps + 3)
	assert_near(session.sample_stats()[&"temperature"], weather.temperature(), 0.5)


func test_temperature() -> void:
	var own := _alone()
	own.hold(WeatherSystem.CLOUDY, 1_000_000_000)
	var days := Config.time.days_per_season
	var offset := climate.value_for(climate.state_temperature, &"cloudy")
	# The middle of each season (its mean is the season's at that midnight), and the hours of the day.
	for season in 4:
		var middle := _midnight(season * days + days / 2)
		assert_near(WeatherSystem.base_temperature(middle, climate), climate.season_temperature[season]
			+ climate.daily_swing[season] * cos(-climate.warmest_hour / 24.0 * TAU), 0.01, "season %d" % season)
		# Warmest in the afternoon, coldest twelve hours from it.
		var warmest := middle
		var coldest := middle
		for minute in range(0, 1440, 15):
			if WeatherSystem.base_temperature(middle + minute, climate) > WeatherSystem.base_temperature(warmest, climate):
				warmest = middle + minute
			if WeatherSystem.base_temperature(middle + minute, climate) < WeatherSystem.base_temperature(coldest, climate):
				coldest = middle + minute
		assert_near(Config.time.minute_of_day(warmest) / 60.0, climate.warmest_hour, 1.0, "season %d" % season)
		assert_true(WeatherSystem.base_temperature(warmest, climate) - WeatherSystem.base_temperature(coldest, climate)
			> climate.daily_swing[season] * 1.5)
		# With the weather's own share, and the air's.
		assert_near(own.temperature(warmest), WeatherSystem.base_temperature(warmest, climate) + own.air_mass(warmest) + offset, 0.001)
		assert_true(absf(own.air_mass(warmest)) <= climate.air_mass_degrees + 0.001)
	# Summer is warmer than winter, by day and by night.
	var summer := _midnight(days + days / 2)
	var winter := _midnight(3 * days + days / 2)
	assert_true(WeatherSystem.base_temperature(summer + 900, climate) > WeatherSystem.base_temperature(winter + 900, climate) + 15.0)
	# No jumps: not from minute to minute, not from season to season, not from year to year.
	var last := own.temperature(_midnight(0))
	var biggest := 0.0
	for minute in range(_midnight(0), _midnight(Config.time.days_per_year() + 3), 10):
		var now := own.temperature(minute)
		biggest = maxf(biggest, absf(now - last))
		last = now
	assert_true(biggest < 0.35, "%.3f degrees in ten minutes at most" % biggest)
	# A change of weather is felt over an hour, not at once.
	var change := _alone()
	change._clock.tick = summer + 600
	change.advance_to(change._clock.tick)
	change.hold(WeatherSystem.CLEAR, 1_000_000_000)
	change._clock.tick += 300
	var before := change.temperature()
	change.hold(WeatherSystem.STORM, 1_000_000_000)
	assert_near(change.temperature(), before, 0.01, "not at once")
	var full := climate.value_for(climate.state_temperature, &"storm") - climate.value_for(climate.state_temperature, &"clear")
	var later := change._clock.tick + climate.temperature_blend_minutes
	assert_near(change.temperature(later) - WeatherSystem.base_temperature(later, climate) - change.air_mass(later),
		climate.value_for(climate.state_temperature, &"storm"), 0.001, "after an hour: all of it (%.1f)" % full)
	# Warm and cold air comes and goes over days: it is not the same all year.
	var airs := {}
	for day in 200:
		airs[snappedf(own.air_mass(_midnight(day)), 0.5)] = true
	assert_true(airs.size() >= 8, str(airs.keys()))
	# Colder higher up, and by the water.
	weather.hold(WeatherSystem.CLOUDY, clock.tick + 10_000)
	var home := session.start.settlement_tile
	assert_near(weather.temperature_at(home), weather.temperature() - (climate.water_cooling if _by_water(home) else 0.0), 0.001)
	var high := home
	var wet := home
	for tile in _tiles():
		if session.world.get_height(tile) > session.world.get_height(high) and not _by_water(tile):
			high = tile
		if session.world.get_water(tile) > 0.0:
			wet = tile
	assert_true(session.world.get_height(high) > session.world.get_height(home))
	assert_near(weather.temperature_at(high), weather.temperature()
		- (session.world.get_height(high) - session.world.get_height(home)) * climate.height_lapse, 0.001)
	assert_true(weather.temperature_at(wet) <= weather.temperature()
		- (session.world.get_height(wet) - session.world.get_height(home)) * climate.height_lapse - climate.water_cooling + 0.001)
	assert_near(weather.temperature_at(Vector2i(100_000, 0)), weather.temperature(), 0.001, "nowhere: as at home")


func _tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var bounds := session.world.bounds
	for y in range(bounds.position.y, bounds.end.y, 3):
		for x in range(bounds.position.x, bounds.end.x, 3):
			out.append(Vector2i(x, y))
	return out


func _by_water(tile: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if session.world.bounds.has_point(tile + offset) and session.world.get_water(tile + offset) > 0.0:
			return true
	return false


func test_what_falls_is_snow_when_it_is_cold() -> void:
	var own := _alone(31)
	var days := Config.time.days_per_year()
	var snow_cold := 0
	var rain_warm := 0
	for step in 40 * days * (DAY / climate.step_minutes):
		own._clock.tick = _midnight(0) + step * climate.step_minutes
		own.advance_to(own._clock.tick)
		if own.since_tick != own._clock.tick:
			continue # (not a fresh look)
		var felt := WeatherSystem.base_temperature(own.since_tick, climate) + own.air_mass(own.since_tick) \
			+ climate.value_for(climate.state_temperature, own.state)
		if own.state == &"snow":
			assert_true(felt <= climate.snow_below + 1.0, "snow at %.1f degrees" % felt)
			assert_true(own.is_snowing() and not own.is_raining())
			snow_cold += 1
		elif own.state == &"rain" or own.state == &"heavy_rain":
			assert_true(felt > climate.snow_below - 1.0, "%s at %.1f degrees" % [own.state, felt])
			rain_warm += 1
	assert_true(snow_cold > 50 and rain_warm > 300, "%d snowfalls, %d rains" % [snow_cold, rain_warm])
	assert_near(climate.value_for(climate.precipitation, &"snow"), 0.7, 0.001)
	assert_true(climate.value_for(climate.fog, &"snow") > 0.0, "snow dims the view")


func test_what_fell_is_written_down() -> void:
	var day := Config.time.day_index(clock.tick) + 2
	clock.tick = _midnight(day)
	weather.advance_to(clock.tick)
	# A day of steady rain.
	weather.hold(WeatherSystem.RAIN, _midnight(day + 1))
	clock.tick = _midnight(day) + 720
	assert_near(weather.rainfall_on(day), 12.0, 0.001, "half a day, half the rain")
	clock.tick = _midnight(day + 1)
	assert_near(weather.rainfall_on(day), 24.0, 0.001)
	assert_true(weather.rain_on(day))
	# A clear day; then heavy rain from the evening into the next morning.
	weather.hold(WeatherSystem.CLEAR, _midnight(day + 1) + 18 * 60)
	clock.tick = _midnight(day + 1) + 18 * 60
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.HEAVY_RAIN, _midnight(day + 2) + 6 * 60)
	clock.tick = _midnight(day + 2) + 6 * 60
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.CLEAR, _midnight(day + 5))
	clock.tick = _midnight(day + 3)
	assert_near(weather.rainfall_on(day + 1), 6 * 2.5, 0.001, "what fell before midnight belongs to that day")
	assert_near(weather.rainfall_on(day + 2), 6 * 2.5, 0.001, "what fell after it to the next")
	assert_true(weather.rain_on(day + 1) and weather.rain_on(day + 2))
	clock.tick = _midnight(day + 5)
	assert_near(weather.rainfall_on(day + 3), 0.0, 0.001)
	assert_false(weather.rain_on(day + 3))
	assert_near(weather.rainfall_over(day + 3, 4), 24.0 + 15.0 + 15.0, 0.001)
	# A drizzle of an hour is not a rainy day.
	assert_true(climate.rain_day_from > 1.0 and climate.rain_day_from <= 3.0)
	# A day that is not over is what has fallen so far; a day to come is nothing — and is not run ahead to.
	weather.advance_to(clock.tick)
	var steps := weather.steps_done
	assert_near(weather.rainfall_on(day + 40), 0.0, 0.001)
	assert_eq(weather.steps_done, steps)
	# What is long ago is forgotten.
	weather.release()
	clock.tick = _midnight(day + climate.history_days + 10)
	weather.advance_to(clock.tick)
	assert_near(weather.rainfall_total(day, 1), 0.0, 0.001)
	assert_true(weather._rain.size() <= climate.history_days + 2)


func test_drought_detection() -> void:
	var conditions: Array = []
	weather.condition_changed.connect(func(condition: StringName, active: bool) -> void: conditions.append([condition, active]))
	var first := Config.time.days_per_season + 1 # (early summer)
	clock.tick = _midnight(first) - 3 * DAY
	weather.advance_to(clock.tick)
	# Rain; then a week under a clear sky.
	weather.hold(WeatherSystem.RAIN, _midnight(first))
	clock.tick = _midnight(first)
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.CLEAR, _midnight(first + 30))
	for day in climate.drought_days - 1:
		clock.tick = _midnight(first + day + 1)
		weather.advance_to(clock.tick)
		assert_false(weather.has_condition(WeatherSystem.DROUGHT), "day %d without rain: not yet" % (day + 1))
	conditions.clear()
	clock.tick = _midnight(first + climate.drought_days)
	weather.advance_to(clock.tick)
	assert_true(weather.has_condition(WeatherSystem.DROUGHT), "a week without rain")
	assert_eq(conditions, [[&"drought", true]])
	assert_eq(weather.conditions(), [&"drought"] as Array[StringName])
	assert_true(weather.debug_text().contains("drought"))
	# It is written down, once, for as long as it lasts.
	var drought := session.events.latest(Chronicler.TYPE_DROUGHT)
	assert_not_null(drought)
	assert_eq(session.chronicle.condition_id(WeatherSystem.DROUGHT), drought.id)
	assert_eq(EventText.text(drought, session.people, session.events), "It has hardly rained for days: a drought")
	assert_true(drought.significance >= 0.6)
	clock.tick += DAY * 2
	weather.advance_to(clock.tick)
	assert_eq(session.events.count_of(Chronicler.TYPE_DROUGHT), 1)
	assert_eq(conditions.size(), 1)
	# A shower of an hour does not end it; a day of rain does.
	weather.hold(WeatherSystem.RAIN, clock.tick + 60)
	clock.tick += 60
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.CLEAR, clock.tick + DAY)
	clock.tick = _midnight(Config.time.day_index(clock.tick) + 1)
	weather.advance_to(clock.tick)
	assert_true(weather.has_condition(WeatherSystem.DROUGHT))
	weather.hold(WeatherSystem.RAIN, clock.tick + DAY)
	clock.tick += DAY
	weather.advance_to(clock.tick)
	assert_false(weather.has_condition(WeatherSystem.DROUGHT))
	assert_eq(conditions[-1], [&"drought", false])
	assert_true(drought.effects.has("ended"))
	assert_eq(session.chronicle.condition_id(WeatherSystem.DROUGHT), 0)
	# A dry winter is no drought (nothing grows that could want rain).
	var winter := 3 * Config.time.days_per_season + Config.time.days_per_year()
	clock.tick = _midnight(winter - 8)
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.CLEAR, _midnight(winter + 6))
	for day in range(winter - 7, winter + 6):
		clock.tick = _midnight(day)
		weather.advance_to(clock.tick)
		if Config.time.season_of(clock.tick - 1) == 3 and day > winter:
			assert_false(weather.has_condition(WeatherSystem.DROUGHT), "day %d" % day)
	# A world a few days old has had no drought of a week, however dry its days.
	var young := _alone(5)
	young.hold(WeatherSystem.CLEAR, 1_000_000)
	for day in climate.drought_days - 1:
		young._clock.tick = _midnight(day + 1)
		young.advance_to(young._clock.tick)
		assert_false(young.has_condition(WeatherSystem.DROUGHT))


func test_heat_waves_and_cold_snaps() -> void:
	var conditions: Array = []
	weather.condition_changed.connect(func(condition: StringName, active: bool) -> void: conditions.append([condition, active]))
	# (Without the warm and cold air that comes and goes, and with thresholds a still year reaches.)
	_knob(climate, &"air_mass_degrees", 0.0)
	_knob(climate, &"heat_wave_from", 26.0)
	_knob(climate, &"cold_snap_below", -5.5)
	var days := Config.time.days_per_season
	# Clear skies in the middle of summer: 27 degrees in the afternoon, day after day.
	var summer := days + days / 2 - 1
	clock.tick = _midnight(summer)
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.CLEAR, _midnight(summer + 10))
	clock.tick = _midnight(summer + 1)
	weather.advance_to(clock.tick)
	assert_false(weather.has_condition(WeatherSystem.HEAT_WAVE), "one hot day is a hot day")
	clock.tick = _midnight(summer + climate.heat_wave_days)
	weather.advance_to(clock.tick)
	assert_true(weather.has_condition(WeatherSystem.HEAT_WAVE))
	assert_eq(EventText.text(session.events.latest(Chronicler.TYPE_HEAT_WAVE), session.people, session.events), "A heat wave")
	# Clouds, and it is over.
	weather.hold(WeatherSystem.HEAVY_RAIN, _midnight(summer + 10))
	clock.tick += DAY
	weather.advance_to(clock.tick)
	assert_false(weather.has_condition(WeatherSystem.HEAT_WAVE))
	assert_true(conditions.has([&"heat_wave", true]) and conditions.has([&"heat_wave", false]))
	# Snow in the middle of winter: bitter nights.
	var winter := 3 * days + days / 2 - 1
	clock.tick = _midnight(winter)
	weather.advance_to(clock.tick)
	weather.hold(WeatherSystem.SNOW, _midnight(winter + 10))
	clock.tick = _midnight(winter + climate.cold_snap_days)
	weather.advance_to(clock.tick)
	assert_true(weather.has_condition(WeatherSystem.COLD_SNAP), "coldest %.1f" % float(weather._coldest.get(winter, 0.0)))
	assert_eq(EventText.text(session.events.latest(Chronicler.TYPE_COLD_SNAP), session.people, session.events), "A bitter cold has set in")
	assert_false(weather.has_condition(WeatherSystem.HEAT_WAVE))


func test_weather_effects() -> void:
	# A plot away from the water, in soil that keeps nothing by itself.
	var farming := session.farming
	_knob(Config.farming, &"seep_share", 0.0)
	var tile := Vector2i.ZERO
	var found := false
	for dy in range(-9, 10):
		for dx in range(-9, 10):
			var here := session.start.settlement_tile + Vector2i(dx, dy)
			if not found and farming.suitable(here) and not farming._wet_beside(here):
				tile = here
				found = true
	assert_true(found)
	var chunk := session.world.chunk_at_tile(tile)
	chunk.set_moisture(session.world.index_at_tile(tile), 120)
	var day := Config.time.day_index(clock.tick) + 1
	clock.tick = _midnight(day)
	weather.advance_to(clock.tick)
	session.settlement.step(clock.tick)
	var crop := farming.sow(tile, clock.tick)
	assert_not_null(crop)
	# A day under a clear sky: the soil dries, and the crop drinks. (How much
	# faster on a hot day, and what the river does to it: test_hydrology.)
	farming.drying_source = Callable()
	farming.groundwater_source = Callable()
	weather.hold(WeatherSystem.CLEAR, _midnight(day + 1))
	clock.tick = _midnight(day + 1) + 30
	session.settlement.step(clock.tick)
	var dry := 120 - Config.farming.evaporation_per_day - Config.farming.crop_draw_per_day
	assert_eq(farming.soil(tile), dry, "evaporation lowers it")
	assert_false(farming.rain_on(day))
	# A day of rain: it gets back more than it lost.
	weather.hold(WeatherSystem.RAIN, _midnight(day + 2))
	clock.tick = _midnight(day + 2) + 30
	session.settlement.step(clock.tick)
	assert_true(farming.rain_on(day + 1), "the fields' rain is the weather's")
	assert_eq(farming.soil(tile), dry + Config.farming.rain_moisture - Config.farming.evaporation_per_day - Config.farming.crop_draw_per_day,
		"rain raises it")
	assert_true(farming.soil(tile) > dry)
	# Snow counts (it melts into the ground); fog and wind bring nothing.
	weather.hold(WeatherSystem.FOG, _midnight(day + 3))
	clock.tick = _midnight(day + 3) + 30
	session.settlement.step(clock.tick)
	assert_false(farming.rain_on(day + 2))
	weather.hold(WeatherSystem.SNOW, _midnight(day + 4))
	clock.tick = _midnight(day + 4) + 30
	session.settlement.step(clock.tick)
	assert_true(farming.rain_on(day + 3))
	# Days without rain are the fields' dry spell — from the weather now.
	assert_eq(session.events.count_of(Chronicler.TYPE_DRY_SPELL), 0)
	weather.hold(WeatherSystem.CLEAR, _midnight(day + 20))
	for more in Config.farming.dry_spell_days + 1:
		clock.tick += DAY
		session.settlement.step(clock.tick)
	assert_true(farming.is_dry_spell())
	assert_eq(session.events.count_of(Chronicler.TYPE_DRY_SPELL), 1)
	weather.hold(WeatherSystem.RAIN, clock.tick + 2 * DAY)
	clock.tick += 2 * DAY
	session.settlement.step(clock.tick)
	assert_false(farming.is_dry_spell())


func test_the_weather_is_saved() -> void:
	weather.hold(WeatherSystem.RAIN, clock.tick + 400)
	_hours(30)
	weather.hold(WeatherSystem.CLEAR, clock.tick + climate.drought_days * DAY * 2)
	var later := Config.time.days_per_season + 1
	while Config.time.day_index(clock.tick) < later + climate.drought_days:
		_hours(24)
	assert_true(weather.has_condition(WeatherSystem.DROUGHT))
	assert_true(weather.is_held())
	assert_true(SaveManager.save_world(session, &"test"))
	assert_eq(SaveContainer.read_header(SaveManager.world_dir(session.world_id).path_join("world.sav")).header["save_version"],
		SaveManager.SAVE_VERSION)
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	# As it was: the sky, the wind, the record, the drought.
	assert_eq(s.weather.to_dict(), weather.to_dict())
	assert_eq([s.weather.state, s.weather.since_tick], [weather.state, weather.since_tick])
	assert_true(s.weather.has_condition(WeatherSystem.DROUGHT))
	assert_eq(s.chronicle.condition_id(WeatherSystem.DROUGHT), session.chronicle.condition_id(WeatherSystem.DROUGHT))
	assert_near(s.weather.temperature(), weather.temperature(), 0.0001)
	var today := Config.time.day_index(clock.tick)
	assert_near(s.weather.rainfall_over(today, 20), weather.rainfall_over(today, 20), 0.0001)
	assert_true(s.weather.is_held(), "held as it was")
	# And it goes on the same as it would have without the save.
	weather.release()
	s.weather.release()
	for hour in 24 * 12:
		clock.tick += 60
		weather.advance_to(clock.tick)
		s.clock.tick += 60
		s.weather.advance_to(s.clock.tick)
		assert_eq(s.weather.state, weather.state, "hour %d" % hour)
	assert_eq(s.weather.to_dict(), weather.to_dict())
	s.queue_free()
	# Nonsense in a save is left out; the weather begins anew.
	var fresh := _alone()
	fresh.from_dict({"state": "hail", "since": "x", "rain": {"a": 1, 3: NAN, 4: 2.5}, "conditions": {"flood": 3, "drought": 7}})
	assert_eq(fresh.state, &"clear")
	assert_eq(fresh._rain, {4: 2.5})
	assert_eq(fresh.conditions(), [&"drought"] as Array[StringName])


func test_version_13_save_gets_its_weather() -> void:
	var dir := SaveManager.world_dir(V13_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V13_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 13)
	var loaded := SaveManager.load_world(V13_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["weather"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	# As it was — under a clear sky, from now.
	assert_eq(s.people.size(), 8)
	assert_eq(s.weather.state, &"clear")
	assert_true(s.weather.since_tick <= s.clock.tick and s.weather.since_tick > s.clock.tick - Config.climate.step_minutes)
	assert_near(s.weather.rainfall_over(Config.time.day_index(s.clock.tick), 10), 0.0, 0.001)
	# The weather goes on from there.
	var seen := {}
	for hour in 24 * 8:
		s.clock.tick += 60
		s.weather.advance_to(s.clock.tick)
		seen[s.weather.state] = true
	assert_true(seen.size() >= 3, str(seen.keys()))
	# Saved again: the current version, the old file kept; and read back with its weather.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 14)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 13)
	var again := SaveManager.load_world(V13_ID)
	assert_true(again.ok, again.error)
	var s2: WorldSession = SessionScript.new()
	add_child(s2)
	assert_true(s2.load_from(again.world))
	s2.set_process(false)
	assert_eq(s2.weather.to_dict(), s.weather.to_dict())
	s.queue_free()
	s2.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v13_to_v14({"world": {"world_state": {}}})["world"]["world_state"], {})
	var kept: Dictionary = SaveMigrations._v13_to_v14({"world": {"world_state": {"people": {}, "weather": {"state": "rain"}}}})
	assert_eq(kept["world"]["world_state"]["weather"], {"state": "rain"})
