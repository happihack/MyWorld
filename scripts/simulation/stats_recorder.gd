class_name StatsRecorder
extends RefCounted
## The world's numbers (bible §27.1), always derived from the simulation:
## written down every game hour (WorldSession.sample_stats), and kept at
## three resolutions (M15) — **every hour** for the recent days, **every day**
## (the day's average) for the years, **every year** (the year's average) for
## the centuries — each a ring of its own, so what is kept stays bounded however
## long the world lives. Saved with the world.

## What is written down (StatsCatalog says what each is and when it is shown).
const SERIES: Array[StringName] = [&"population", &"food", &"water", &"wood", &"stone", &"health", &"mood", &"temperature",
	&"trees", &"grass", &"tools", &"food_days",
	# (M15)
	&"births", &"deaths", &"average_age", &"children", &"adults", &"elders", &"settlements", &"migrants",
	&"nutrition", &"sick", &"trade", &"produced", &"buildings", &"fields",
	&"fear", &"trust", &"conflict", &"friendships",
	&"rainfall", &"forest", &"wildlife", &"soil",
	&"interventions", &"remembered", &"divine", &"natural"]

enum Resolution { HOURLY, DAILY, YEARLY }
## The most kept at each resolution: 40 days of hours (Config.events.max_samples),
## a hundred years of days, two thousand years.
const DAILY_MOST := 2400
const YEARLY_MOST := 2000

## Asked for a sample: returns {series name -> float} (see WorldSession.sample_stats).
var source := Callable()

var _config: EventsConfig
var _rings: Array = [] # Resolution -> {"ticks": PackedInt64Array, "series": {name -> PackedFloat32Array}}
## The day and the year being gathered: {"key": day/year index, "tick", "count", "sums": {name -> float}}.
var _day_bucket: Dictionary = {}
var _year_bucket: Dictionary = {}
var _last_tick := -1_000_000


func _init(config: EventsConfig = null) -> void:
	_config = config
	clear()


func clear() -> void:
	_rings = [_empty_ring(), _empty_ring(), _empty_ring()]
	_day_bucket = {}
	_year_bucket = {}
	_last_tick = -1_000_000


static func _empty_ring() -> Dictionary:
	var series := {}
	for name in SERIES:
		series[name] = PackedFloat32Array()
	return {"ticks": PackedInt64Array(), "series": series}


## Time has come to `now`: takes a sample if one is due. (A clock set far
## ahead gives one sample, not one for every hour skipped: nobody was
## counting.) Returns true if one was taken.
func advance_to(now: int) -> bool:
	var config := _config if _config != null else Config.events
	if now >= _last_tick and now - _last_tick < config.sample_minutes:
		return false
	if not source.is_valid():
		return false
	var values: Variant = source.call()
	if typeof(values) != TYPE_DICTIONARY:
		return false
	add_sample(now, values)
	return true


## Writes a sample down: {series name -> value}; what is missing counts as 0.
## The day's and the year's averages are gathered as it goes, and written
## down when the day (the year) is over.
func add_sample(now: int, values: Dictionary) -> void:
	var config := _config if _config != null else Config.events
	_last_tick = now
	var sample := {}
	for name in SERIES:
		sample[name] = float(values.get(name, values.get(String(name), 0.0)))
	_append(Resolution.HOURLY, now, sample, config.max_samples)
	var day := Config.time.day_index(now)
	if not _day_bucket.is_empty() and int(_day_bucket["key"]) != day:
		_close_day()
	_gather(_day_bucket, day, now, sample)


## The day is over: its average is written down (and gathered into the year's).
func _close_day() -> void:
	var mean := _mean_of(_day_bucket)
	var tick := int(_day_bucket["tick"])
	_append(Resolution.DAILY, tick, mean, DAILY_MOST)
	var year := Config.time.year_of(tick)
	if not _year_bucket.is_empty() and int(_year_bucket["key"]) != year:
		_append(Resolution.YEARLY, int(_year_bucket["tick"]), _mean_of(_year_bucket), YEARLY_MOST)
		_year_bucket = {}
	_gather(_year_bucket, year, tick, mean)
	_day_bucket = {}


static func _gather(bucket: Dictionary, key: int, tick: int, sample: Dictionary) -> void:
	if bucket.is_empty():
		bucket["key"] = key
		bucket["tick"] = tick
		bucket["count"] = 0
		bucket["sums"] = {}
	bucket["count"] = int(bucket["count"]) + 1
	var sums: Dictionary = bucket["sums"]
	for name: StringName in sample:
		sums[name] = float(sums.get(name, 0.0)) + float(sample[name])


static func _mean_of(bucket: Dictionary) -> Dictionary:
	var out := {}
	var count := maxi(int(bucket.get("count", 1)), 1)
	var sums: Dictionary = bucket.get("sums", {})
	for name: StringName in sums:
		out[name] = float(sums[name]) / count
	return out


func _append(resolution: int, tick: int, sample: Dictionary, most: int) -> void:
	var ring: Dictionary = _rings[resolution]
	var ticks_now: PackedInt64Array = ring["ticks"]
	ticks_now.append(tick)
	var series_now: Dictionary = ring["series"]
	for name in SERIES:
		var values: PackedFloat32Array = series_now[name]
		values.append(float(sample.get(name, 0.0)))
		series_now[name] = values
	var over := ticks_now.size() - most
	if over > 0:
		ticks_now = ticks_now.slice(over)
		for name in SERIES:
			series_now[name] = (series_now[name] as PackedFloat32Array).slice(over)
	ring["ticks"] = ticks_now


func sample_count(resolution: int = Resolution.HOURLY) -> int:
	return (_rings[resolution]["ticks"] as PackedInt64Array).size()


## When each sample was taken (game ticks), oldest first.
func ticks(resolution: int = Resolution.HOURLY) -> PackedInt64Array:
	return _rings[resolution]["ticks"]


## One number over time, oldest first (as long as ticks()).
func series(name: StringName, resolution: int = Resolution.HOURLY) -> PackedFloat32Array:
	return (_rings[resolution]["series"] as Dictionary).get(name, PackedFloat32Array())


## The latest sample: {series name -> value} ({} if there is none).
func latest() -> Dictionary:
	var out := {}
	var ring: Dictionary = _rings[Resolution.HOURLY]
	if (ring["ticks"] as PackedInt64Array).is_empty():
		return out
	for name in SERIES:
		out[name] = ((ring["series"] as Dictionary)[name] as PackedFloat32Array)[-1]
	return out


## Has a number ever been other than nothing (at any resolution)?
func has_data(name: StringName) -> bool:
	for resolution in 3:
		for value in series(name, resolution):
			if value != 0.0:
				return true
	return false


## The least and the most a number has been, from `from_tick` on: [min, max]
## ([0, 0] without samples).
func range_of(name: StringName, from_tick: int = -0x7FFFFFFFFFFFFFFF) -> Array:
	var values := series(name)
	var at := ticks()
	var least := INF
	var most := -INF
	for i in at.size():
		if at[i] >= from_tick:
			least = minf(least, values[i])
			most = maxf(most, values[i])
	return [least, most] if least != INF else [0.0, 0.0]


func debug_text() -> String:
	var now := latest()
	if now.is_empty():
		return "stats: no samples yet"
	return "stats (%d h, %d d, %d y): people %d  food %.1f  wood %d  stone %d  water %.0f  health %.2f  mood %.2f  %.0f°C" % [
		sample_count(), sample_count(Resolution.DAILY), sample_count(Resolution.YEARLY), int(now[&"population"]), now[&"food"],
		int(now[&"wood"]), int(now[&"stone"]), now[&"water"], now[&"health"], now[&"mood"], now[&"temperature"]]


func to_dict() -> Dictionary:
	# (The hours under the old keys: a world saved before M15 reads as before.)
	var out := {"ticks": ticks(), "series": _ring_series(Resolution.HOURLY), "last": _last_tick}
	if sample_count(Resolution.DAILY) > 0:
		out["daily"] = {"ticks": ticks(Resolution.DAILY), "series": _ring_series(Resolution.DAILY)}
	if sample_count(Resolution.YEARLY) > 0:
		out["yearly"] = {"ticks": ticks(Resolution.YEARLY), "series": _ring_series(Resolution.YEARLY)}
	if not _day_bucket.is_empty():
		out["day_bucket"] = _bucket_saved(_day_bucket)
	if not _year_bucket.is_empty():
		out["year_bucket"] = _bucket_saved(_year_bucket)
	return out


static func _bucket_saved(bucket: Dictionary) -> Dictionary:
	if bucket.is_empty():
		return {}
	var sums := {}
	for name: StringName in bucket["sums"]:
		sums[String(name)] = float(bucket["sums"][name])
	return {"key": int(bucket["key"]), "tick": int(bucket["tick"]), "count": int(bucket["count"]), "sums": sums}


func _ring_series(resolution: int) -> Dictionary:
	var out := {}
	if sample_count(resolution) == 0:
		return out # (nothing written down: nothing to save)
	for name in SERIES:
		out[String(name)] = series(name, resolution)
	return out


## Restores saved samples. Returns false if they were unusable (and it is empty).
func from_dict(data: Dictionary) -> bool:
	clear()
	if data.is_empty():
		return true
	if not _read_ring(Resolution.HOURLY, data.get("ticks"), data.get("series")):
		return false
	_last_tick = int(data["last"]) if typeof(data.get("last")) == TYPE_INT else (ticks()[-1] if sample_count() > 0 else -1_000_000)
	for entry: Array in [[Resolution.DAILY, "daily"], [Resolution.YEARLY, "yearly"]]:
		var saved: Variant = data.get(entry[1])
		if typeof(saved) == TYPE_DICTIONARY:
			_read_ring(entry[0], (saved as Dictionary).get("ticks"), (saved as Dictionary).get("series"))
	_day_bucket = _bucket_read(data.get("day_bucket"))
	_year_bucket = _bucket_read(data.get("year_bucket"))
	return true


static func _bucket_read(saved: Variant) -> Dictionary:
	if typeof(saved) != TYPE_DICTIONARY or typeof((saved as Dictionary).get("sums")) != TYPE_DICTIONARY:
		return {}
	var sums := {}
	for key: Variant in saved["sums"]:
		sums[StringName(key)] = float(saved["sums"][key])
	return {"key": int(saved.get("key", 0)), "tick": int(saved.get("tick", 0)), "count": int(saved.get("count", 0)), "sums": sums}


func _read_ring(resolution: int, ticks_saved: Variant, series_saved: Variant) -> bool:
	if typeof(ticks_saved) != TYPE_PACKED_INT64_ARRAY or typeof(series_saved) != TYPE_DICTIONARY:
		return false
	var count := (ticks_saved as PackedInt64Array).size()
	var ring := _empty_ring()
	for name in SERIES:
		var values: Variant = (series_saved as Dictionary).get(String(name))
		if typeof(values) == TYPE_PACKED_FLOAT32_ARRAY and (values as PackedFloat32Array).size() == count:
			ring["series"][name] = values
		else:
			# (A number that was not kept yet when this was saved: nothing known of it.)
			var blank := PackedFloat32Array()
			blank.resize(count)
			ring["series"][name] = blank
	ring["ticks"] = ticks_saved
	_rings[resolution] = ring
	return true
