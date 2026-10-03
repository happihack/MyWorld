class_name EventText
extends RefCounted
## World events in words (bible §21.1 "text_key, text_params"): "Food is
## running short after the failed crop". The templates are in
## data/text/events.csv and are looked up through the translation server.
##
## The most particular template there is wins — and what an event was
## caused by is part of how it is told:
##   <KEY>_BECAUSE_<CAUSE>_MANY   (it happened several times: with {count})
##   <KEY>_BECAUSE_<CAUSE>        (the kind of one of its causes)
##   <KEY>_FIRST                  (the first of its kind)
##   <KEY>_MANY
##   <KEY>


## What an event says. `people`: to name whom it concerned; `log`: to look
## up what caused it (both may be null).
static func text(event: WorldEvent, people: PersonRegistry = null, log: EventLog = null) -> String:
	if event == null:
		return MemoryText.translate("EVENT_UNKNOWN")
	var base := event.text_key if event.text_key != "" else "EVENT_" + String(event.type).to_upper()
	var many := event.count > 1
	var candidates := PackedStringArray()
	if log != null:
		for cause_id in event.causes:
			var cause := log.get_event(cause_id)
			if cause == null:
				continue
			var because := "%s_BECAUSE_%s" % [base, String(cause.type).to_upper()]
			if many:
				candidates.append(because + "_MANY")
			candidates.append(because)
	# (What kind of thing it was: died of old age, ill of bad water.)
	for which: String in ["cause", "kind"]:
		if str(event.text_params.get(which, "")) != "":
			candidates.append("%s_%s" % [base, str(event.text_params[which]).to_upper()])
	if event.is_first():
		candidates.append(base + "_FIRST")
	if many:
		candidates.append(base + "_MANY")
	candidates.append(base)
	var key := "EVENT_UNKNOWN"
	for candidate in candidates:
		if MemoryText.has(candidate):
			key = candidate
			break
	var out := MemoryText.translate(key).format(params_of(event, people))
	if many and not key.ends_with("_MANY"):
		out = MemoryText.translate("EVENT_TIMES").format({"text": out, "count": event.count})
	return out


## A line for a list: "YEAR 1 · Food is running short".
static func line(event: WorldEvent, people: PersonRegistry = null, log: EventLog = null) -> String:
	return MemoryText.translate("HIST_YEAR").format({"year": HistoryText.year_of(event.tick), "text": text(event, people, log)})


## What goes into an event's template: its own parameters, put into words.
static func params_of(event: WorldEvent, people: PersonRegistry = null) -> Dictionary:
	var params := event.text_params.duplicate()
	params["count"] = event.count
	# (Whoever it concerned, living or dead — and a second and third, for what
	# happened between two, or to a child and its parents.)
	for n: int in mini(event.participants.size(), 3):
		var known := people.name_of(event.participants[n]) if people != null else ""
		params[["name", "other", "third"][n]] = known if known != "" else MemoryText.translate("EVENT_SOMEONE")
	if not params.has("name"):
		params["name"] = MemoryText.translate("EVENT_SOMEONE")
	if params.has("resource"):
		params["resource"] = UIText.resource_name(StringName(str(params["resource"])))
	if params.has("species"):
		params["species"] = UIText.species_name(StringName(str(params["species"]))).to_lower()
	# (What a memory or a myth is about, and what is made of it.)
	if params.has("subject"):
		var what_key := "MEMWHAT_" + str(params["subject"]).to_upper()
		params["what"] = MemoryText.translate(what_key if MemoryText.has(what_key) else "MEMWHAT_UNKNOWN")
	if params.has("interpretation") and str(params["interpretation"]) != "":
		var belief_key := "MEMBELIEF_" + str(params["interpretation"]).to_upper()
		params["belief"] = MemoryText.translate(belief_key if MemoryText.has(belief_key) else "MEMBELIEF_NATURAL")
	if params.has("epithet"):
		var epithet := str(params["epithet"])
		params["epithet"] = MemoryText.translate(epithet if MemoryText.has(epithet) else "EPITHET_UNKNOWN")
	if params.has("building"):
		var key := "BUILDING_" + str(params["building"]).to_upper()
		params["building"] = MemoryText.translate(key) if MemoryText.has(key) else str(params["building"])
	if params.has("occupation"):
		params["occupation"] = UIText.occupation_name(StringName(str(params["occupation"]))).to_lower()
	if event.type == &"player_intervention":
		params["text"] = HistoryText.text({"type": str(params.get("kind", "")), "subject": str(params.get("subject", "")),
			"first": event.is_first()})
	return params
