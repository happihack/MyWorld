class_name StatsRecorder
extends RefCounted
## The world's numbers, written down every game hour (bible §27.3; feeds
## the statistics panel to come): how many people, what is in store, how
## they are. A ring of samples: when it is full the oldest go. Saved with
## the world.

const SERIES: Array[StringName] = [&"population", &"food", &"water", &"wood", &"stone", &"health", &"mood"]

## Asked for a sample: returns {series name -> float} (see WorldSession.sample_stats).
var source := Callable()

var _config: EventsConfig
var _ticks := PackedInt64Array()
var _series: Dictionary = {} # name -> PackedFloat32Array, as long as _ticks
var _last_tick := -1_000_000


func _init(config: EventsConfig = null) -> void:
	_config = config
	clear()


func clear() -> void:
	_ticks = PackedInt64Array()
	_series.clear()
	for name in SERIES:
		_series[name] = PackedFloat32Array()
	_last_tick = -1_000_000


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
func add_sample(now: int, values: Dictionary) -> void:
	var config := _config if _config != null else Config.events
	_last_tick = now
	_ticks.append(now)
	for name in SERIES:
		var series: PackedFloat32Array = _series[name]
		series.append(float(values.get(name, values.get(String(name), 0.0))))
		_series[name] = series
	var over := _ticks.size() - config.max_samples
	if over > 0:
		_ticks = _ticks.slice(over)
		for name in SERIES:
			_series[name] = (_series[name] as PackedFloat32Array).slice(over)


func sample_count() -> int:
	return _ticks.size()


## When each sample was taken (game ticks), oldest first.
func ticks() -> PackedInt64Array:
	return _ticks


## One number over time, oldest first (as long as ticks()).
func series(name: StringName) -> PackedFloat32Array:
	return _series.get(name, PackedFloat32Array())


## The latest sample: {series name -> value} ({} if there is none).
func latest() -> Dictionary:
	var out := {}
	if _ticks.is_empty():
		return out
	for name in SERIES:
		out[name] = (_series[name] as PackedFloat32Array)[-1]
	return out


## The least and the most a number has been, from `from_tick` on: [min, max]
## ([0, 0] without samples).
func range_of(name: StringName, from_tick: int = -0x7FFFFFFFFFFFFFFF) -> Array:
	var values := series(name)
	var least := INF
	var most := -INF
	for i in _ticks.size():
		if _ticks[i] >= from_tick:
			least = minf(least, values[i])
			most = maxf(most, values[i])
	return [least, most] if least != INF else [0.0, 0.0]


func debug_text() -> String:
	var now := latest()
	if now.is_empty():
		return "stats: no samples yet"
	return "stats (%d samples): people %d  food %.1f  wood %d  stone %d  water %.0f  health %.2f  mood %.2f" % [
		_ticks.size(), int(now[&"population"]), now[&"food"], int(now[&"wood"]), int(now[&"stone"]), now[&"water"],
		now[&"health"], now[&"mood"]]


func to_dict() -> Dictionary:
	var series_saved := {}
	for name in SERIES:
		series_saved[String(name)] = _series[name]
	return {"ticks": _ticks, "series": series_saved, "last": _last_tick}


## Restores saved samples. Returns false if they were unusable (and it is empty).
func from_dict(data: Dictionary) -> bool:
	clear()
	var ticks_saved: Variant = data.get("ticks")
	var series_saved: Variant = data.get("series")
	if typeof(ticks_saved) != TYPE_PACKED_INT64_ARRAY or typeof(series_saved) != TYPE_DICTIONARY:
		return data.is_empty()
	var count := (ticks_saved as PackedInt64Array).size()
	for name in SERIES:
		var values: Variant = (series_saved as Dictionary).get(String(name))
		if typeof(values) == TYPE_PACKED_FLOAT32_ARRAY and (values as PackedFloat32Array).size() == count:
			_series[name] = values
		else:
			# (A number that was not kept yet when this was saved: nothing known of it.)
			var blank := PackedFloat32Array()
			blank.resize(count)
			_series[name] = blank
	_ticks = ticks_saved
	_last_tick = int(data["last"]) if typeof(data.get("last")) == TYPE_INT else (_ticks[-1] if count > 0 else -1_000_000)
	return true
