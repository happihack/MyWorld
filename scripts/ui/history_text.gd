class_name HistoryText
extends RefCounted
## The player's history in words (bible §27.2): "YEAR 1 · touched first
## inhabitant". The templates are in data/text/history.csv and are looked up
## through the translation server.
##
## The most particular template there is wins:
##   HIST_FIRST_<TYPE>_<SUBJECT>   the first of its kind, of this subject
##   HIST_FIRST_<TYPE>             the first of its kind (with {thing})
##   HIST_<TYPE>_<SUBJECT>
##   HIST_<TYPE>                   (with {thing})


## The game year a tick falls in (the first year is year 1).
static func year_of(tick: int) -> int:
	@warning_ignore("integer_division")
	return maxi(tick, 0) / maxi(Config.time.ticks_per_year(), 1) + 1


## What a history entry (see PlayerHistory.entries) says: "touched first inhabitant".
static func text(entry: Dictionary) -> String:
	var type := str(entry.get("type", "")).to_upper()
	var subject := str(entry.get("subject", "")).to_upper()
	var candidates := PackedStringArray()
	if bool(entry.get("first", false)):
		candidates.append("HIST_FIRST_%s_%s" % [type, subject])
		candidates.append("HIST_FIRST_%s" % type)
	candidates.append("HIST_%s_%s" % [type, subject])
	candidates.append("HIST_%s" % type)
	var thing_key := "HISTTHING_" + subject
	var thing := MemoryText.translate(thing_key if MemoryText.has(thing_key) else "HISTTHING_UNKNOWN")
	for key in candidates:
		if MemoryText.has(key):
			return MemoryText.translate(key).format({"thing": thing})
	return MemoryText.translate("HIST_UNKNOWN").format({"thing": thing})


## A line of the history: "YEAR 1 · touched first inhabitant".
static func line(entry: Dictionary) -> String:
	return MemoryText.translate("HIST_YEAR").format({"year": year_of(int(entry.get("tick", 0))), "text": text(entry)})
