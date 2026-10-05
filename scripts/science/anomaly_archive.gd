class_name AnomalyArchive
extends RefCounted
## What the civilization knows of the unexplained (M18, bible §20.1): every
## doing of the player's that anyone witnessed is an **anomaly** — what it was,
## where, when (the world's hour, and the player's own: the real hour it
## happened at, which is how the player's schedule may one day show), how many
## saw it, what the sky was doing. **Only what was witnessed** is recorded.
##
## Before a settlement writes, its anomalies are **oral**: kept only as long
## as memory keeps them (ORAL_YEARS); once it writes, they are written down,
## and kept.

## Something was recorded: the anomaly.
signal recorded(anomaly: Dictionary)

## What is not written down is forgotten after this many years.
const ORAL_YEARS := 20
## The most kept (the oldest let go of first).
const MOST := 2000

var settlements: Settlements
var weather: WeatherSystem
## The player's real time: Callable() -> [unix seconds, local hour 0 … 23];
## unset: the system clock. (Tests set it.)
var real_clock := Callable()
## Every anomaly, oldest first: {"id", "type" (stimulus type), "tick", "hour" (the world's), "unix",
##   "real_hour", "position", "witnesses", "settlement", "drought" (bool), "intervention", "written"}.
var anomalies: Array[Dictionary] = []
var _next := 1
var _day := -1_000_000


func bind(all: Settlements, sky: WeatherSystem, now: int) -> void:
	settlements = all
	weather = sky
	_day = Config.time.day_index(now)


## A stimulus has gone out and `witnesses` noticed it: if it was the player's
## doing (or something no less strange) and anyone saw it, it is recorded.
func on_stimulus(stimulus: Stimulus, witnesses: int, now: int) -> Dictionary:
	if stimulus == null or witnesses <= 0 or stimulus.origin != Stimulus.Origin.PLAYER or stimulus.type == Stimulus.TOLD:
		return {}
	var own := _nearest(stimulus.position)
	var real := _real_now()
	var anomaly := {"id": _next, "type": String(stimulus.type), "tick": now,
		"hour": float(Config.time.minute_of_day(now)) / 60.0, "unix": int(real[0]), "real_hour": int(real[1]),
		"position": stimulus.position, "witnesses": witnesses, "settlement": own.id if own != null else 0,
		"drought": weather != null and weather.has_condition(WeatherSystem.DROUGHT), "intervention": stimulus.intervention_id,
		"written": own != null and own.knows_how(&"writing")}
	_next += 1
	anomalies.append(anomaly)
	while anomalies.size() > MOST:
		anomalies.remove_at(0)
	recorded.emit(anomaly)
	return anomaly


func _real_now() -> Array:
	if real_clock.is_valid():
		return real_clock.call()
	return [int(Time.get_unix_time_from_system()), int(Time.get_datetime_dict_from_system()["hour"])]


func _nearest(at: Vector2) -> Settlement:
	if settlements == null:
		return null
	var best: Settlement = null
	var best_distance := INF
	for own in settlements.all():
		var fire := own.fire()
		if fire == null:
			continue
		var distance := fire.position2d().distance_to(at)
		if distance < best_distance:
			best = own
			best_distance = distance
	return best


## What a settlement knows of: its own anomalies still remembered or written.
func of(settlement_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for anomaly in anomalies:
		if int(anomaly["settlement"]) == settlement_id:
			out.append(anomaly)
	return out


## Once a game day: what a writing settlement still remembers is written down;
## what nobody wrote down is forgotten in time.
func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	keep(now)


func keep(now: int) -> void:
	var span := ORAL_YEARS * Config.time.ticks_per_year()
	var writers := {}
	if settlements != null:
		for own in settlements.all():
			writers[own.id] = own.knows_how(&"writing")
	var kept: Array[Dictionary] = []
	for anomaly in anomalies:
		if not bool(anomaly["written"]) and bool(writers.get(int(anomaly["settlement"]), false)):
			anomaly["written"] = true
		if bool(anomaly["written"]) or now - int(anomaly["tick"]) <= span:
			kept.append(anomaly)
	anomalies = kept


func to_dict() -> Dictionary:
	var kept: Array = []
	for anomaly in anomalies:
		kept.append(anomaly.duplicate())
	return {"anomalies": kept, "next": _next, "day": _day}


func from_dict(data: Dictionary) -> void:
	anomalies.clear()
	if typeof(data.get("anomalies")) == TYPE_ARRAY:
		for a: Variant in data["anomalies"]:
			if typeof(a) == TYPE_DICTIONARY and (a as Dictionary).has_all(["id", "type", "tick", "settlement"]):
				anomalies.append((a as Dictionary).duplicate())
	_next = maxi(int(data.get("next", 1)), 1)
	for anomaly in anomalies:
		_next = maxi(_next, int(anomaly["id"]) + 1)
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var written := anomalies.filter(func(a: Dictionary) -> bool: return bool(a["written"])).size()
	return "anomalies: %d (%d written)" % [anomalies.size(), written]
