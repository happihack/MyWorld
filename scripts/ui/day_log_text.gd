class_name DayLogText
extends RefCounted
## A person's day in words (see DayLog): "06:30 wakes · 07:00 has breakfast ·
## 08:00 chops wood · 12:40 talks to Jon". The words are in
## data/text/daylog.csv and go through the translation server.

## Meals by the hour they are begun: before this breakfast, before that lunch.
const LUNCH_FROM := 10.0
const DINNER_FROM := 15.0


static func has(key: String) -> bool:
	return String(TranslationServer.translate(key)) != key


static func translate(key: String) -> String:
	return String(TranslationServer.translate(key))


## "07:05"
static func time_of(tick: int, config: TimeConfig = null) -> String:
	if config == null:
		config = Config.time
	var minute := config.minute_of_day(tick)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [minute / 60, minute % 60]


## What an entry says, without its time: "has breakfast", "talks to Jon".
## `people`: to name whoever it was with (may be null).
static func text(entry: Array, people: PersonRegistry = null, config: TimeConfig = null) -> String:
	if config == null:
		config = Config.time
	var kind := str(entry[DayLog.KIND])
	var detail := str(entry[DayLog.DETAIL])
	var other := people.get_person(int(entry[DayLog.OTHER])) if people != null and int(entry[DayLog.OTHER]) != 0 else null
	var who := other.given_name if other != null else translate("DAY_SOMEONE")
	if kind == DayLog.REACT:
		return _reaction(detail, who)
	var key := "DAY_" + kind.to_upper()
	match kind:
		"eat":
			if detail == "meal":
				var hour := config.minute_of_day(int(entry[DayLog.TICK])) / 60.0
				key = "DAY_BREAKFAST" if hour < LUNCH_FROM else ("DAY_LUNCH" if hour < DINNER_FROM else "DAY_DINNER")
			elif detail == "bush":
				key = "DAY_EAT_BUSH"
		"sleep":
			if detail == "nap":
				key = "DAY_NAP"
		"socialize":
			if detail == DayLog.MORE:
				key = "DAY_SOCIALIZE_MORE"
		"work":
			var particular := "DAY_WORK_" + detail.to_upper()
			if detail != "" and has(particular):
				key = particular
	if not has(key):
		return kind.replace("_", " ")
	return translate(key).format({"name": who})


## "07:05 has breakfast"
static func line(entry: Array, people: PersonRegistry = null, config: TimeConfig = null) -> String:
	return translate("DAY_LINE").format({"time": time_of(int(entry[DayLog.TICK]), config), "text": text(entry, people, config)})


## The entries in a row, as they happened: "06:30 wakes · 07:00 has breakfast".
static func timeline(entries: Array, people: PersonRegistry = null, config: TimeConfig = null) -> String:
	var parts := PackedStringArray()
	for entry: Array in entries:
		parts.append(line(entry, people, config))
	return translate("DAY_SEPARATOR").join(parts)


## What the card shows: [title, text] — today's entries ("Today"), or the
## day before's while today has none yet ("Yesterday"); "Nothing yet" for
## someone of whom nothing is known.
static func shown(log: DayLog, person_id: int, now_tick: int, people: PersonRegistry = null, config: TimeConfig = null) -> Array:
	if config == null:
		config = Config.time
	if log == null:
		return [translate("DAY_TODAY"), translate("DAY_NOTHING")]
	var latest := log.latest_day(person_id, now_tick, config)
	var entries: Array = latest[1]
	var title := translate("DAY_TODAY" if int(latest[0]) == config.day_index(now_tick) else "DAY_EARLIER")
	if entries.is_empty():
		return [title, translate("DAY_NOTHING")]
	return [title, timeline(entries, people, config)]


## "feels a touch, runs away" — what they noticed (if there are words for
## it) and what they did about it.
static func _reaction(detail: String, who: String) -> String:
	var reaction := detail.get_slice(":", 0)
	var stimulus := detail.get_slice(":", 1) if detail.contains(":") else ""
	var does_key := "DAY_REACT_" + reaction.to_upper()
	var does := translate(does_key if has(does_key) else "DAY_REACT").format({"name": who})
	var what_key := "DAY_AT_" + stimulus.to_upper()
	if stimulus == "" or not has(what_key):
		return does
	return translate("DAY_REACT_AT").format({"what": translate(what_key), "does": does})
