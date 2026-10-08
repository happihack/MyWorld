class_name Insights
extends RefCounted
## What the numbers say about what happened (M15, bible §27.1): for each of
## the world's notable events, its numbers in the days before and after it are
## compared (the daily averages), and a change large enough is said in words
## — "Food in store fell 34% after the drought of year 12."

## What each kind of event may have changed.
const EFFECTS := {
	&"drought": [&"food", &"grass", &"water"],
	&"flood": [&"water", &"food", &"health"],
	&"storm": [&"wood", &"buildings"],
	&"blizzard": [&"wood", &"buildings"],
	&"cold_snap": [&"health", &"mood"],
	&"heat_wave": [&"mood", &"water"],
	&"food_shortage": [&"population", &"mood", &"health"],
	&"crop_failure": [&"food", &"food_days"],
	&"settlement_founded": [&"population", &"settlements"],
	&"edge_moved": [&"trees", &"wildlife"],
	&"player_intervention": [&"mood", &"fear"],
}
## Days compared on either side of the event.
const DAYS := 6
## Changes smaller than this (a share) are not worth saying.
const WORTH := 0.25
## Days on either side with numbers, at the least.
const LEAST_DAYS := 3


## The insights of the world's history, the largest change first (at most
## `most`); only about `about` if given.
static func lines(stats: StatsRecorder, events: EventLog, about: Array = [], most: int = 3) -> PackedStringArray:
	var found: Array = [] # [|change|, text]
	var days := stats.ticks(StatsRecorder.Resolution.DAILY)
	if days.size() < LEAST_DAYS * 2:
		return PackedStringArray()
	var seen := {}
	for type: StringName in EFFECTS:
		var happened := events.of_type(type)
		for e in happened.slice(maxi(happened.size() - 10, 0)):
			for name: StringName in EFFECTS[type]:
				if not about.is_empty() and not about.has(name):
					continue
				var key := "%s|%s|%d" % [type, name, Config.time.year_of(e.tick)]
				if seen.has(key):
					continue # (one a year for each kind and number)
				var change := change_after(stats, name, e.tick)
				if is_nan(change) or absf(change) < WORTH:
					continue
				seen[key] = true
				found.append([absf(change), _say(name, change, type, e.tick)])
	found.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var out := PackedStringArray()
	for item: Array in found.slice(0, most):
		out.append(item[1])
	return out


## How much a number changed after `tick` (a share of what it was; NAN when
## it cannot be told: too few days on either side, or nothing before).
static func change_after(stats: StatsRecorder, name: StringName, tick: int) -> float:
	var days := stats.ticks(StatsRecorder.Resolution.DAILY)
	var values := stats.series(name, StatsRecorder.Resolution.DAILY)
	var day := Config.time.day_index(tick)
	var before := 0.0
	var after := 0.0
	var n_before := 0
	var n_after := 0
	# (From the first day that may count: found by halves, the days being in order.)
	var midnight := (day - DAYS) * TimeConfig.MINUTES_PER_DAY - roundi(Config.time.start_hour * 60.0)
	for i in range(days.bsearch(midnight), days.size()):
		var d := Config.time.day_index(days[i])
		if d > day + DAYS:
			break
		if d >= day - DAYS and d < day:
			before += values[i]
			n_before += 1
		elif d > day and d <= day + DAYS:
			after += values[i]
			n_after += 1
	if n_before < LEAST_DAYS or n_after < LEAST_DAYS:
		return NAN
	before /= n_before
	after /= n_after
	if absf(before) < 0.0001:
		return NAN
	return (after - before) / absf(before)


static func _say(name: StringName, change: float, type: StringName, tick: int) -> String:
	return MemoryText.translate("INSIGHT_ROSE" if change > 0.0 else "INSIGHT_FELL").format({
		"what": StatsCatalog.label(name), "share": roundi(absf(change) * 100.0),
		"event": MemoryText.translate("INSIGHT_EVENT_" + String(type).to_upper()), "year": Config.time.year_of(tick)})
