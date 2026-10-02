class_name WeatherSystem
extends RefCounted
## The weather (bible §10.1): one state for the whole box — clear, cloudy,
## rain, heavy rain, storm, wind, snow, fog — going from one to the next
## as a Markov chain whose table depends on the season (ClimateConfig).
## With it: how warm it is, how the wind blows, how much rain has fallen
## day by day. Long-running **conditions** — drought, heat wave, cold snap —
## are not rolled but found out from that record.
##
## The chain's dice are the world's seed and the number of the step: the
## same world has the same weather on every device, and nothing of the
## dice needs saving. What is saved is where it stands, and its record.
##
## Simulation only: what the sky looks and sounds like is WeatherFx's.

## The weather has changed.
signal changed(old: StringName, now: StringName)
## A condition has begun (or is over): DROUGHT, HEAT_WAVE, COLD_SNAP.
signal condition_changed(condition: StringName, active: bool)

const CLEAR := &"clear"
const CLOUDY := &"cloudy"
const RAIN := &"rain"
const HEAVY_RAIN := &"heavy_rain"
const STORM := &"storm"
const WIND := &"wind"
const SNOW := &"snow"
const FOG := &"fog"
const STATES: Array[StringName] = [CLEAR, CLOUDY, RAIN, HEAVY_RAIN, STORM, WIND, SNOW, FOG]

const DROUGHT := &"drought"
const HEAT_WAVE := &"heat_wave"
const COLD_SNAP := &"cold_snap"
const CONDITIONS: Array[StringName] = [DROUGHT, HEAT_WAVE, COLD_SNAP]

## At most this many steps are made up for at once (a clock set far ahead).
const MAX_STEPS_AT_ONCE := 8 * 60
const _SALT_STATE := 0x5EA7
const _SALT_WIND := 0x71D5
const _SALT_TURN := 0x7A2B
const _SALT_AIR := 0x3C91
const DAY := 1440

var state: StringName = CLEAR
## What it was before (for the change to be felt gradually).
var previous: StringName = CLEAR
## Since when (game tick).
var since_tick := 0
## Where the wind blows to (degrees; 0 = +X, 90 = +Z) and how hard (0 … 1).
var wind_degrees := 20.0
var wind_speed := 0.2
## For the overlay.
var steps_done := 0

var _clock: GameClock
var _config: ClimateConfig
var _seed := 0
var _world: WorldData
var _reference_height := 0
## The number of the last step of the chain that was made (-1: none yet).
var _step := -1
## The weather is held as it is until this tick (-1: it is not).
var _held_until := -1
## What fell on each day (day index -> units), and how warm and how cold it got.
var _rain: Dictionary = {}
var _warmest: Dictionary = {}
var _coldest: Dictionary = {}
## The conditions that are going on: name -> the day they began.
var _conditions: Dictionary = {}


func bind(clock: GameClock, config: ClimateConfig, world_seed: int, world: WorldData = null, reference_height: int = 0) -> void:
	_clock = clock
	_config = config
	_seed = world_seed
	_world = world
	_reference_height = reference_height
	reset()


func reset() -> void:
	state = CLEAR
	previous = CLEAR
	since_tick = 0
	wind_degrees = float(_hash(0, _SALT_TURN) % 360)
	wind_speed = 0.2
	steps_done = 0
	_step = -1
	_held_until = -1
	_rain.clear()
	_warmest.clear()
	_coldest.clear()
	_conditions.clear()


# --- time passes ------------------------------------------------------------------------------------

## Brings the weather up to `tick`: every step of the chain that has come
## due is made. Cheap to call often.
func advance_to(tick: int) -> void:
	if _config == null:
		return
	var step_minutes := _config.step_minutes
	# (Steps are counted by the calendar, so that one of them falls on every midnight.)
	var target := floori(float(_calendar(tick)) / step_minutes)
	if _step < 0:
		# The first look at the sky: it begins here.
		_step = target
		since_tick = target * step_minutes - _offset()
		return
	if target <= _step:
		return # (nothing new — or the clock was set back: what has been stays)
	if target - _step > MAX_STEPS_AT_ONCE:
		_step = target - MAX_STEPS_AT_ONCE
	while _step < target:
		_step += 1
		_do_step(_step)


## Holds the weather at `kind` until `until_tick` (the chain stands still
## meanwhile): what the player's tools do, and tests.
func hold(kind: StringName, until_tick: int) -> void:
	if not STATES.has(kind):
		return
	if _clock != null:
		advance_to(_clock.tick)
	_held_until = until_tick
	# (With the wind that kind of weather has.)
	var strength: Variant = _config.wind_speed.get(kind, _config.wind_speed.get(String(kind))) if _config != null else null
	if typeof(strength) == TYPE_VECTOR2:
		wind_speed = clampf(((strength as Vector2).x + (strength as Vector2).y) * 0.5, 0.0, 1.0)
	_set_state(kind, _clock.tick if _clock != null else since_tick)


## Lets the chain go on from what the weather is now.
func release() -> void:
	_held_until = -1


func is_held() -> bool:
	return _held_until >= 0 and (_clock == null or _clock.tick < _held_until)


# --- what the weather is ----------------------------------------------------------------------------

func is_raining() -> bool:
	return state == RAIN or state == HEAVY_RAIN or state == STORM


func is_snowing() -> bool:
	return state == SNOW


## How much falls in an hour right now (rain or snow; 0 if nothing does).
func precipitation() -> float:
	return _config.value_for(_config.precipitation, state) if _config != null else 0.0


## How much of the sky is covered, 0 … 1.
func cloud_cover() -> float:
	return clampf(_config.value_for(_config.cloud_cover, state), 0.0, 1.0) if _config != null else 0.0


## How foggy it is, 0 … 1.
func fog() -> float:
	return clampf(_config.value_for(_config.fog, state), 0.0, 1.0) if _config != null else 0.0


## The wind: where it blows to (world X/Z), as long as it is strong (0 … 1).
func wind() -> Vector2:
	return Vector2.from_angle(deg_to_rad(wind_degrees)) * wind_speed


## How warm it is (°C) at `tick` (now, if not given), at the settlement.
func temperature(tick: int = -1) -> float:
	if _config == null:
		return 15.0
	if tick < 0:
		tick = _clock.tick if _clock != null else 0
	var felt := _config.value_for(_config.state_temperature, state)
	var was := _config.value_for(_config.state_temperature, previous)
	var blend := clampf(float(tick - since_tick) / _config.temperature_blend_minutes, 0.0, 1.0)
	return base_temperature(tick, _config) + air_mass(tick) + lerpf(was, felt, blend)


## Warmer or colder air than the season has by itself (°C): it comes and
## goes over days — what makes one week of summer hot and the next mild.
## (From the world's seed and the day: the same in the same world.)
func air_mass(tick: int) -> float:
	if _config == null or _config.air_mass_degrees <= 0.0:
		return 0.0
	var position := float(_calendar(tick)) / (DAY * _config.air_mass_days)
	var from := floori(position)
	var share := position - from
	share = share * share * (3.0 - 2.0 * share)
	return lerpf(_air(from), _air(from + 1), share) * _config.air_mass_degrees


func _air(index: int) -> float:
	return float(_hash(index, _SALT_AIR) % 2001) / 1000.0 - 1.0


## How warm it is on a tile: colder higher up, and by the water.
func temperature_at(tile: Vector2i, tick: int = -1) -> float:
	var here := temperature(tick)
	if _world == null or _config == null or not _world.bounds.has_point(tile):
		return here
	here -= (_world.get_height(tile) - _reference_height) * _config.height_lapse
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _world.bounds.has_point(tile + offset) and _world.get_water(tile + offset) > 0.0:
			return here - _config.water_cooling
	return here


## The temperature the season and the hour give by themselves (whatever
## the weather): the season's mean — going over smoothly into the next
## season's — and the day's swing around it.
static func base_temperature(tick: int, config: ClimateConfig) -> float:
	var time := Config.time
	var days := float(time.days_per_season)
	var day_of_year := fposmod(float(tick + roundi(time.start_hour * 60.0)) / DAY, days * 4.0)
	# Half a season before a season's middle it is half way from the last.
	var position := day_of_year / days - 0.5
	var from := posmod(floori(position), 4)
	var share := position - floorf(position)
	var mean := lerpf(config.season_temperature[from], config.season_temperature[(from + 1) % 4], share)
	var swing := lerpf(config.daily_swing[from], config.daily_swing[(from + 1) % 4], share)
	var hour := time.minute_of_day(tick) / 60.0
	return mean + swing * cos((hour - config.warmest_hour) / 24.0 * TAU)


## What has fallen on a day so far (units). A day that is over is made up
## for first, if the weather has not got that far.
func rainfall_on(day: int) -> float:
	_catch_up(day)
	return float(_rain.get(day, 0.0))


## Was (or is) it a rainy day?
func rain_on(day: int) -> bool:
	return rainfall_on(day) >= (_config.rain_day_from if _config != null else 1.0)


## What has fallen over the `days` days up to and including `day`.
func rainfall_over(day: int, days: int) -> float:
	var total := 0.0
	for d in range(day - days + 1, day + 1):
		total += rainfall_on(d)
	return total


func has_condition(condition: StringName) -> bool:
	return _conditions.has(condition)


## The conditions going on now.
func conditions() -> Array[StringName]:
	var out: Array[StringName] = []
	for condition in CONDITIONS:
		if _conditions.has(condition):
			out.append(condition)
	return out


## The tick of the next look at the sky.
func next_step_tick() -> int:
	return (_step + 1) * _config.step_minutes - _offset() if _config != null and _step >= 0 else 0


func debug_text() -> String:
	if _config == null or _clock == null:
		return "weather: none"
	var today := Config.time.day_index(_clock.tick)
	return "weather: %s%s since %s  %.1f°C  wind %.2f to %d°  cover %.2f  rain today %.1f (7 days: %.1f)%s" % [
		state, " (HELD)" if is_held() else "", _hour_text(since_tick), temperature(), wind_speed, roundi(wind_degrees), cloud_cover(),
		float(_rain.get(today, 0.0)), rainfall_over(today, 7),
		"  CONDITIONS: " + ", ".join(conditions()) if not _conditions.is_empty() else ""]


# --- saving -----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"state": String(state), "previous": String(previous), "since": since_tick, "step": _step, "held_until": _held_until,
		"wind_degrees": wind_degrees, "wind_speed": wind_speed,
		"rain": _rain.duplicate(), "warmest": _warmest.duplicate(), "coldest": _coldest.duplicate(),
		"conditions": _strings(_conditions),
	}


## Call after bind().
func from_dict(data: Dictionary) -> void:
	reset()
	if data.is_empty():
		return
	var saved := StringName(str(data.get("state", CLEAR)))
	state = saved if STATES.has(saved) else CLEAR
	var before := StringName(str(data.get("previous", state)))
	previous = before if STATES.has(before) else state
	since_tick = _int(data.get("since"), 0)
	_step = _int(data.get("step"), -1)
	_held_until = _int(data.get("held_until"), -1)
	wind_degrees = _number(data.get("wind_degrees"), wind_degrees)
	wind_speed = clampf(_number(data.get("wind_speed"), wind_speed), 0.0, 1.0)
	_rain = _days(data.get("rain"))
	_warmest = _days(data.get("warmest"))
	_coldest = _days(data.get("coldest"))
	var going: Variant = data.get("conditions")
	if typeof(going) == TYPE_DICTIONARY:
		for condition: Variant in going:
			if CONDITIONS.has(StringName(str(condition))) and typeof((going as Dictionary)[condition]) == TYPE_INT:
				_conditions[StringName(str(condition))] = int(going[condition])


# --- internals --------------------------------------------------------------------------------------

## One look at the sky, at the beginning of step `index`: what fell since
## the last is written down, the day that has ended is judged, and the
## weather goes on to whatever follows.
func _do_step(index: int) -> void:
	var step_minutes := _config.step_minutes
	var calendar := index * step_minutes # minutes since the midnight before the world began
	var now := calendar - _offset() # the game tick
	steps_done += 1
	_note_rain(calendar - step_minutes, calendar)
	_note_temperature(now)
	if posmod(calendar, DAY) < step_minutes:
		_end_day(floori(float(calendar) / DAY) - 1)
	if _held_until >= 0:
		if now < _held_until:
			return
		_held_until = -1
	var season := Config.time.season_of(now)
	var next := _follow(state, season, index)
	# What falls when it is cold is snow; snow in the warm is rain.
	var cold := base_temperature(now, _config) + air_mass(now) + _config.value_for(_config.state_temperature, next) 		<= _config.snow_below
	if cold and (next == RAIN or next == HEAVY_RAIN):
		next = SNOW
	elif not cold and next == SNOW:
		next = RAIN
	# The wind: turning a little, as strong as the weather has it.
	var turn := (float(_hash(index, _SALT_TURN) % 2001) / 1000.0 - 1.0) * _config.wind_turn_degrees
	wind_degrees = fposmod(wind_degrees + turn, 360.0)
	var strength: Variant = _config.wind_speed.get(next, _config.wind_speed.get(String(next)))
	var between := strength as Vector2 if typeof(strength) == TYPE_VECTOR2 else Vector2(0.1, 0.3)
	wind_speed = clampf(lerpf(between.x, between.y, float(_hash(index, _SALT_WIND) % 1001) / 1000.0), 0.0, 1.0)
	_set_state(next, now)


## What follows `from` in a season, by the dice of step `index`.
func _follow(from: StringName, season: int, index: int) -> StringName:
	var rows := _config.table(season)
	var row: Variant = rows.get(from, rows.get(String(from)))
	if typeof(row) != TYPE_DICTIONARY or (row as Dictionary).is_empty():
		return from
	# (In a fixed order, whatever order the file has them in.)
	var total := 0.0
	for kind in STATES:
		total += maxf(_config.value_for(row, kind), 0.0)
	if total <= 0.0:
		return from
	var roll := float(_hash(index, _SALT_STATE) % 1_000_000) / 1_000_000.0 * total
	for kind in STATES:
		roll -= maxf(_config.value_for(row, kind), 0.0)
		if roll < 0.0:
			return kind
	return from


func _set_state(kind: StringName, tick: int) -> void:
	if kind == state:
		return
	previous = state
	state = kind
	since_tick = tick
	changed.emit(previous, state)
	EventBus.weather_changed.emit(previous, state)


## What fell from `from` to `to` (calendar minutes) under the weather as it is.
func _note_rain(from: int, to: int) -> void:
	var rate := precipitation()
	if rate <= 0.0:
		return
	var minute := from
	while minute < to:
		var day := floori(float(minute) / DAY)
		var until := mini(to, (day + 1) * DAY)
		_rain[day] = float(_rain.get(day, 0.0)) + rate * (until - minute) / 60.0
		minute = until


func _note_temperature(tick: int) -> void:
	var day := floori(float(_calendar(tick) - 1) / DAY) # (the look at midnight belongs to the day that ends)
	var now := temperature(tick)
	_warmest[day] = maxf(float(_warmest.get(day, -INF)), now)
	_coldest[day] = minf(float(_coldest.get(day, INF)), now)


## A day is over: are the conditions (still) there? And what is too long
## ago to matter is forgotten.
func _end_day(day: int) -> void:
	@warning_ignore("integer_division")
	var winter := posmod(day, Config.time.days_per_year()) / Config.time.days_per_season == 3
	var dry := not winter and rainfall_total(day, _config.drought_days) < _config.drought_rain_below \
		and _known_days(day, _config.drought_days)
	_set_condition(DROUGHT, dry, day)
	var hot := true
	for d in range(day - _config.heat_wave_days + 1, day + 1):
		hot = hot and float(_warmest.get(d, -INF)) >= _config.heat_wave_from
	_set_condition(HEAT_WAVE, hot, day)
	var cold := true
	for d in range(day - _config.cold_snap_days + 1, day + 1):
		cold = cold and float(_coldest.get(d, INF)) <= _config.cold_snap_below
	_set_condition(COLD_SNAP, cold, day)
	var oldest := day - _config.history_days
	for record: Dictionary in [_rain, _warmest, _coldest]:
		for known: int in record.keys():
			if known < oldest:
				record.erase(known)


## What fell over the `days` days up to `day`, from the record alone.
func rainfall_total(day: int, days: int) -> float:
	var total := 0.0
	for d in range(day - days + 1, day + 1):
		total += float(_rain.get(d, 0.0))
	return total


## Has the weather been watched for all of those days? (A world three days
## old has had no drought of seven.)
func _known_days(day: int, days: int) -> bool:
	return _warmest.has(day - days + 1)


func _set_condition(condition: StringName, active: bool, day: int) -> void:
	if active == _conditions.has(condition):
		return
	if active:
		_conditions[condition] = day
	else:
		_conditions.erase(condition)
	condition_changed.emit(condition, active)


## Makes up for a day that is over, if the weather has not got that far.
func _catch_up(day: int) -> void:
	if _clock == null or _config == null:
		return
	advance_to(mini((day + 1) * DAY - _offset(), _clock.tick))


## Minutes since the midnight before the world began (tick 0 is not midnight).
func _calendar(tick: int) -> int:
	return tick + _offset()


func _offset() -> int:
	return roundi(Config.time.start_hour * 60.0)


func _hash(index: int, salt: int) -> int:
	return absi(HashNoise.hash2(index, _seed & 0xFFFF, salt ^ ((_seed >> 16) & 0xFFFF)))


static func _hour_text(tick: int) -> String:
	var minute := Config.time.minute_of_day(tick)
	return "%02d:%02d" % [minute / 60, minute % 60]


static func _strings(values: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in values:
		out[str(key)] = values[key]
	return out


static func _int(value: Variant, default: int) -> int:
	return int(value) if typeof(value) == TYPE_INT else default


static func _number(value: Variant, default: float) -> float:
	return float(value) if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)) else default


## A record by day from saved data: {day (int): number}.
static func _days(value: Variant) -> Dictionary:
	var out := {}
	if typeof(value) != TYPE_DICTIONARY:
		return out
	for day: Variant in value:
		var amount: Variant = (value as Dictionary)[day]
		if typeof(day) == TYPE_INT and (typeof(amount) == TYPE_FLOAT or typeof(amount) == TYPE_INT) and is_finite(float(amount)):
			out[day] = float(amount)
	return out
