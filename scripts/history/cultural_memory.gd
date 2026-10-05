class_name CulturalMemory
extends RefCounted
## What a settlement remembers together (bible §15.1, §15.3), and the myths
## that grow out of it (§15.4, v0).
##
## Once a game day: when enough of a settlement's people hold a memory of
## the same thing, made of it the same way, the settlement remembers it
## together — a cultural memory, as strong as the share of its people who
## hold it; when they no longer do, it fades and is forgotten. What a
## settlement remembers together colours how its people take the like of it
## (see Interpretation).
##
## When a cultural memory takes the like of something to be someone's doing
## (a spirit's, a god's, an ancestor's, an unknown mind's) and its people
## have lived through it on enough days, a myth forms: an epithet ("the
## Rainbringer"; its name comes with the language, M17), what it does, how
## it is felt (benevolent, fearsome, capricious), how many believe, and
## where it showed itself.

signal formed(settlement_id: int, subject: StringName, interpretation: StringName)
signal faded(settlement_id: int, subject: StringName, interpretation: StringName)
signal myth_formed(myth: Dictionary)

## What is someone's doing (and may become a myth).
const AGENTS: Array[StringName] = [&"spirit", &"deity", &"ancestor", &"unknown_intelligence", &"multiple_entities"]
## Days of living through something kept per memory, at most.
const DAYS_KEPT := 64
## Places a myth keeps.
const PLACES_KEPT := 3

var _people: PersonRegistry
var _memories: MemoryStore
var _config: MemoryConfig
var _day := -1_000_000
## key ("settlement:subject:interpretation") -> {"settlement", "subject", "interpretation", "strength",
##   "holders", "formed", "held" (tick last held)}
var _entries: Dictionary = {}
## key -> PackedInt32Array of the days its people lived through it (kept even before it is held).
var _days: Dictionary = {}
var _myths: Array[Dictionary] = []
var _next_myth := 1


func bind(people: PersonRegistry, memories: MemoryStore, now: int, config: MemoryConfig = null) -> void:
	_people = people
	if _memories != null and _memories.remembered.is_connected(note):
		_memories.remembered.disconnect(note)
	_memories = memories
	_config = config if config != null else Config.memory
	_entries.clear()
	_days.clear()
	_myths.clear()
	_next_myth = 1
	_day = Config.time.day_index(now)
	if _memories != null:
		_memories.remembered.connect(note)


# --- what is remembered ---------------------------------------------------------------------------

## The cultural memories of a settlement, the strongest first.
func of(settlement_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries.values():
		if int(entry["settlement"]) == settlement_id:
			out.append(entry)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["strength"]) > float(b["strength"]) if float(a["strength"]) != float(b["strength"]) \
			else _key_of(a) < _key_of(b))
	return out


## How strongly a settlement holds that the like of `subject` is `interpretation` (0: not at all).
func weight(settlement_id: int, subject: StringName, interpretation: StringName) -> float:
	var entry: Variant = _entries.get(_key(settlement_id, subject, interpretation))
	return float((entry as Dictionary)["strength"]) if entry != null else 0.0


func size() -> int:
	return _entries.size()


func myths() -> Array[Dictionary]:
	return _myths


## A myth taken up by a settlement (carried along by founders or with loads,
## M17.2): theirs now, believed anew there. Returns it.
func adopt(myth: Dictionary, settlement_id: int) -> Dictionary:
	var copy: Dictionary = myth.duplicate(true)
	copy["id"] = _next_myth
	_next_myth += 1
	copy["settlement"] = settlement_id
	copy["believers"] = int(myth.get("believers", 0)) if int(myth.get("settlement", 0)) == settlement_id else 0
	copy["from"] = int(myth.get("settlement", 0))
	_myths.append(copy)
	return copy


## The myth of a settlement about `subject` taken as `agent` ({}: none).
func myth_of(settlement_id: int, subject: StringName, agent: StringName) -> Dictionary:
	for myth in _myths:
		if int(myth["settlement"]) == settlement_id and StringName(myth["subject"]) == subject and StringName(myth["agent"]) == agent:
			return myth
	return {}


## On how many days a settlement's people lived through it.
func days_lived(settlement_id: int, subject: StringName, interpretation: StringName) -> int:
	return (_days.get(_key(settlement_id, subject, interpretation), PackedInt32Array()) as PackedInt32Array).size()


## In how many different seasons (of the days kept) its people lived through it (M17.1).
func seasons_lived(settlement_id: int, subject: StringName, interpretation: StringName) -> int:
	var seasons := {}
	for day in _days.get(_key(settlement_id, subject, interpretation), PackedInt32Array()):
		seasons[floori(float(day) / Config.time.days_per_season)] = true
	return seasons.size()


## The first day (of those kept) its people lived through it (-1: never).
func first_day_lived(settlement_id: int, subject: StringName, interpretation: StringName) -> int:
	var days: PackedInt32Array = _days.get(_key(settlement_id, subject, interpretation), PackedInt32Array())
	return days[0] if not days.is_empty() else -1


## What everyone remembers (the store it counts from).
func memory_store() -> MemoryStore:
	return _memories


func debug_text() -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in _entries.values():
		parts.append("%s/%s %.2f(%d)" % [entry["subject"], entry["interpretation"], float(entry["strength"]), int(entry["holders"])])
	parts.sort()
	return "culture: %d memories, %d myths  %s" % [_entries.size(), _myths.size(), " ".join(parts)]


# --- living through things ------------------------------------------------------------------------

## A memory was made (or brought up to date): one lived through (not told of)
## counts as a day the settlement lived through that.
func note(memory: Memory) -> void:
	if memory == null or memory.owner_kind != Memory.OwnerKind.PERSON or not _counts(memory) \
			or (memory.source != Memory.Source.DIRECT and memory.source != Memory.Source.WITNESSED):
		return
	var person := _people.get_person(memory.owner_id) if _people != null else null
	if person == null:
		return
	var key := _key(person.settlement_id, memory.subject, memory.interpretation)
	var days: PackedInt32Array = _days.get(key, PackedInt32Array())
	var day := Config.time.day_index(memory.tick)
	if not days.has(day):
		days.append(day)
		while days.size() > DAYS_KEPT:
			days.remove_at(0)
		_days[key] = days


## Once a game day: who holds what, and what comes of it.
func advance_to(now: int) -> void:
	if _people == null or _memories == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	settle(now)


## Counts who holds what now, forms and fades cultural memories, and forms myths.
func settle(now: int) -> void:
	var members := {} # settlement -> count
	var holders := {} # key -> {person id -> true}
	var felt := {} # key -> PackedFloat32Array (summed emotions)
	var places := {} # key -> Array of Vector2
	var everyone := _people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	for person in everyone:
		members[person.settlement_id] = int(members.get(person.settlement_id, 0)) + 1
		for memory in _memories.of(person):
			if memory.importance < _config.pool_importance or not _counts(memory):
				continue
			var key := _key(person.settlement_id, memory.subject, memory.interpretation)
			var who: Dictionary = holders.get(key, {})
			who[person.id] = true
			holders[key] = who
			var sum: PackedFloat32Array = felt.get(key, PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]))
			for i in mini(sum.size(), memory.emotions.size()):
				sum[i] += memory.emotions[i]
			felt[key] = sum
			var at: Array = places.get(key, [])
			if at.size() < 16:
				at.append(memory.location)
			places[key] = at
	var keys: Array = holders.keys()
	keys.sort()
	for key: String in keys:
		var parts := key.split(":")
		var settlement := int(parts[0])
		var count := (holders[key] as Dictionary).size()
		var everyone_there := int(members.get(settlement, 0))
		if count < maxi(_config.pool_holders, ceili(_config.pool_share * everyone_there)):
			continue
		var share := float(count) / float(maxi(everyone_there, 1))
		var entry: Dictionary = _entries.get(key, {})
		var fresh := entry.is_empty()
		if fresh:
			entry = {"settlement": settlement, "subject": parts[1], "interpretation": parts[2], "strength": 0.0,
				"holders": 0, "formed": now, "held": now}
			_entries[key] = entry
		entry["strength"] = maxf(float(entry["strength"]), share) if fresh else lerpf(float(entry["strength"]), share, 0.5)
		entry["holders"] = count
		entry["held"] = now
		if fresh:
			formed.emit(settlement, StringName(parts[1]), StringName(parts[2]))
		_maybe_myth(entry, key, felt.get(key, PackedFloat32Array()), places.get(key, []), now)
	# What nobody holds any more fades.
	var gone: Array[String] = []
	var entry_keys: Array = _entries.keys()
	entry_keys.sort()
	for key: String in entry_keys:
		var entry: Dictionary = _entries[key]
		if int(entry["held"]) == now:
			continue
		entry["holders"] = (holders.get(key, {}) as Dictionary).size()
		entry["strength"] = float(entry["strength"]) - _config.pool_fade_per_day
		if float(entry["strength"]) < _config.pool_forget:
			gone.append(key)
	for key in gone:
		var entry: Dictionary = _entries[key]
		_entries.erase(key)
		faded.emit(int(entry["settlement"]), StringName(entry["subject"]), StringName(entry["interpretation"]))
	# Believers: those who hold it now.
	for myth in _myths:
		var key := _key(int(myth["settlement"]), StringName(myth["subject"]), StringName(myth["agent"]))
		myth["believers"] = (holders.get(key, {}) as Dictionary).size()


func _maybe_myth(entry: Dictionary, key: String, felt: PackedFloat32Array, at: Array, now: int) -> void:
	var agent := StringName(entry["interpretation"])
	if not AGENTS.has(agent) or float(entry["strength"]) < _config.myth_strength:
		return
	var settlement := int(entry["settlement"])
	var subject := StringName(entry["subject"])
	if not myth_of(settlement, subject, agent).is_empty():
		return
	if days_lived(settlement, subject, agent) < _config.myth_events:
		return
	var places_kept: Array = []
	for place: Vector2 in at:
		var near := false
		for kept: Vector2 in places_kept:
			near = near or kept.distance_to(place) < 4.0
		if not near and places_kept.size() < PLACES_KEPT:
			places_kept.append(place)
	var myth := {"id": _next_myth, "settlement": settlement, "subject": String(subject), "agent": String(agent),
		"epithet": "EPITHET_" + String(subject).to_upper(), "sentiment": sentiment_of(felt),
		"believers": int(entry["holders"]), "formed": now, "days": days_lived(settlement, subject, agent),
		"places": places_kept}
	_next_myth += 1
	_myths.append(myth)
	myth_formed.emit(myth)


## How a myth is felt, from what its believers felt: fearsome (fear), benevolent
## (joy and awe), or capricious (neither, or both).
static func sentiment_of(felt: PackedFloat32Array) -> String:
	if felt.size() < ReactionTable.EMOTION_COUNT:
		return "capricious"
	var fear := felt[ReactionTable.Emotion.FEAR] + felt[ReactionTable.Emotion.ANNOYANCE] * 0.5
	var good := felt[ReactionTable.Emotion.JOY] + felt[ReactionTable.Emotion.AWE]
	if fear > good * 1.3:
		return "fearsome"
	if good > fear * 1.3:
		return "benevolent"
	return "capricious"


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var entries: Array = []
	var keys: Array = _entries.keys()
	keys.sort()
	for key: String in keys:
		entries.append((_entries[key] as Dictionary).duplicate())
	var days := {}
	for key: String in _days:
		days[key] = (_days[key] as PackedInt32Array).duplicate()
	var myths: Array = []
	for myth in _myths:
		myths.append(myth.duplicate(true))
	return {"day": _day, "entries": entries, "days": days, "myths": myths, "next_myth": _next_myth}


## Returns how many saved records were unusable.
func from_dict(data: Dictionary) -> int:
	var skipped := 0
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	if typeof(data.get("entries")) == TYPE_ARRAY:
		for entry: Variant in data["entries"]:
			if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has_all(["settlement", "subject", "interpretation", "strength"]):
				skipped += 1
				continue
			var e: Dictionary = (entry as Dictionary).duplicate()
			var strength := float(e["strength"]) if typeof(e["strength"]) in [TYPE_FLOAT, TYPE_INT] else NAN
			if not is_finite(strength):
				skipped += 1
				continue
			e["strength"] = clampf(strength, 0.0, 1.0)
			e["holders"] = int(e.get("holders", 0))
			e["formed"] = int(e.get("formed", 0))
			e["held"] = int(e.get("held", 0))
			_entries[_key(int(e["settlement"]), StringName(str(e["subject"])), StringName(str(e["interpretation"])))] = e
	if typeof(data.get("days")) == TYPE_DICTIONARY:
		for key: Variant in data["days"]:
			if typeof(data["days"][key]) == TYPE_PACKED_INT32_ARRAY:
				_days[str(key)] = (data["days"][key] as PackedInt32Array).duplicate()
	if typeof(data.get("myths")) == TYPE_ARRAY:
		for myth: Variant in data["myths"]:
			if typeof(myth) != TYPE_DICTIONARY or not (myth as Dictionary).has_all(["id", "settlement", "subject", "agent"]):
				skipped += 1
				continue
			_myths.append((myth as Dictionary).duplicate(true))
	_next_myth = maxi(int(data.get("next_myth", 1)), 1)
	for myth in _myths:
		_next_myth = maxi(_next_myth, int(myth["id"]) + 1)
	return skipped


# --- internals --------------------------------------------------------------------------------------

## What counts for a cultural memory: what was made something of (an
## interpretation), and the floods lived through together.
static func _counts(memory: Memory) -> bool:
	if memory.kind == Memory.KIND_LIFE:
		return memory.subject == &"life_flood"
	return memory.interpretation != &"" and memory.subject != &""


static func _key(settlement_id: int, subject: StringName, interpretation: StringName) -> String:
	return "%d:%s:%s" % [settlement_id, subject, interpretation]


static func _key_of(entry: Dictionary) -> String:
	return _key(int(entry["settlement"]), StringName(entry["subject"]), StringName(entry["interpretation"]))
