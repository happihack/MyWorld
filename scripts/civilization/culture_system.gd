class_name CultureSystem
extends RefCounted
## What makes a settlement's people theirs (M17.1, bible §19.1–19.3).
##
## **A profile**, worked out once a year from its people and its history: what
## it values — tradition ↔ innovation (its people's curiosity, what it has
## worked out), self ↔ community (their generosity and company), skepticism ↔
## piety (how much of what happens they take for someone's doing) — and what
## it makes of the Presence (the interpretation most of them hold), its myths,
## its traditions; its look (how it thatches its roofs, the colours it wears).
##
## **Traditions** come of what its people live through again and again, felt
## and taken alike (a cultural memory lived on many days, over seasons): rain
## from a clear sky becomes a rain dance, the player's touches a blessing of
## the young, a great flood a day of high water; the first harvest a harvest
## festival, the first bridge a bridge festival. **The player's doing can
## become a tradition** (and it says so). Each keeps its day in the year: on
## it, at dusk, everyone gathers at the fire (the "celebrate" activity); a rain
## dance is danced when a drought begins. A tradition whose root is forgotten
## for years fades.

signal tradition_formed(tradition: Dictionary)
signal tradition_faded(tradition: Dictionary)
## A festival begins (at dusk on its day, or a ritual when its moment comes).
signal festival(settlement_id: int, tradition: Dictionary)

## What a cultural memory (subject) becomes as a tradition: [name key, kind,
## when ("day": its day of the year, "drought": when a drought begins)].
const FROM_MEMORIES := {
	&"rain_from_clear_sky": ["TRADITION_RAIN_DANCE", "ritual", "drought"],
	&"rain_fell": ["TRADITION_RAIN_DANCE", "ritual", "drought"],
	&"touch": ["TRADITION_BLESSING", "ceremony", "day"],
	&"object_moved": ["TRADITION_OFFERING_STONES", "ceremony", "day"],
	&"object_lifted": ["TRADITION_OFFERING_STONES", "ceremony", "day"],
	&"tree_shaken": ["TRADITION_TREE_SONG", "ceremony", "day"],
	&"sourceless_wind": ["TRADITION_WIND_FESTIVAL", "festival", "day"],
	&"water_poured": ["TRADITION_WATER_GIFT", "ceremony", "day"],
	&"life_flood": ["TRADITION_HIGH_WATER", "remembrance", "day"],
	&"flood": ["TRADITION_HIGH_WATER", "remembrance", "day"],
	&"thunderstorm": ["TRADITION_STORM_VIGIL", "ritual", "day"],
}
## What a first becomes: event type -> [name key, kind, season (its day: the
## first of that season), or -1: the day it happened].
const FROM_FIRSTS := {
	&"first_farm": ["TRADITION_HARVEST", "festival", 2],
	&"building_built:bridge": ["TRADITION_BRIDGE", "festival", -1],
}
## Lived on at least this many days, over at least this many seasons, held by
## at least this share of its people, a cultural memory becomes a tradition.
const LIVED_DAYS := 5
const LIVED_SEASONS := 2
const HELD_SHARE := 0.35
## A tradition whose root has been forgotten this many years fades.
const FADES_AFTER_YEARS := 6
## The festival: from this hour, for this long (hours).
const DUSK := 18.0
const FESTIVAL_HOURS := 3.0
## How many looks there are (roofs, cloth).
const ARCHITECTURES := 3
const PALETTES := 6
## How much what a settlement as a whole believes leans how its people take things (M17.2).
const BELIEF_WEIGHT := 0.6
const SUPERNATURAL: Array[StringName] = [ReactionTable.SPIRIT, ReactionTable.DEITY, ReactionTable.ANCESTOR,
	ReactionTable.UNKNOWN_INTELLIGENCE, ReactionTable.MULTIPLE_ENTITIES]

var settlements: Settlements
var culture: CulturalMemory
var events: EventLog
var world_seed := 0
## Every tradition: {"id", "settlement", "name" (text key), "kind", "when", "day" (of the year, 1 …),
##   "source", "interpretation", "formed", "rooted" (tick its root was last held), "player" (bool),
##   "intervention" (the player's act it goes back to, 0: none), "kept" (times held), "last" (tick last held)}.
var traditions: Array[Dictionary] = []
## Settlement id -> its profile (see profile_of), as last worked out.
var profiles: Dictionary = {}
var _next := 1
var _day := -1_000_000
## The festivals going on: settlement id -> [tradition id, until tick].
var _on: Dictionary = {}


func bind(all: Settlements, memory: CulturalMemory, log: EventLog, seed_value: int, now: int) -> void:
	settlements = all
	culture = memory
	events = log
	world_seed = seed_value
	_day = Config.time.day_index(now)


# --- the profile ------------------------------------------------------------------------------------

## A settlement's profile (worked out now): {"innovation", "collectivism", "piety" (-1 … 1),
## "presence" (the interpretation most hold), "presence_share", "architecture", "palette",
## "traditions" (ids), "myths" (ids)}.
func profile_of(own: Settlement) -> Dictionary:
	var curious := 0.0
	var giving := 0.0
	var count := 0
	var beliefs := PackedFloat32Array()
	beliefs.resize(ReactionTable.INTERPRETATIONS.size())
	for person in own.members():
		count += 1
		curious += ReactionTable.lean(person.traits, Traits.Axis.CURIOSITY)
		giving += (ReactionTable.lean(person.traits, Traits.Axis.GENEROSITY) + ReactionTable.lean(person.traits, Traits.Axis.SOCIABILITY)) * 0.5
		var held := Interpretation.beliefs_of(person)
		for i in beliefs.size():
			beliefs[i] += held[i]
	var per := 1.0 / maxi(count, 1)
	var known := 0
	for key: String in own.knows:
		known += 1
	var supernatural := 0.0
	var all := 0.0
	var best := 0
	for i in beliefs.size():
		all += beliefs[i]
		if SUPERNATURAL.has(ReactionTable.INTERPRETATIONS[i]):
			supernatural += beliefs[i]
		if beliefs[i] > beliefs[best]:
			best = i
	var mine: Array[int] = []
	for tradition in traditions:
		if int(tradition["settlement"]) == own.id:
			mine.append(int(tradition["id"]))
	var myths: Array[int] = []
	if culture != null:
		for myth in culture.myths():
			if int(myth["settlement"]) == own.id:
				myths.append(int(myth["id"]))
	return {
		"innovation": clampf(curious * per * 0.6 + clampf((known - 4) / 10.0, 0.0, 1.0) * 0.4, -1.0, 1.0),
		"collectivism": clampf(giving * per, -1.0, 1.0),
		"piety": clampf((supernatural / all) * 2.0 - 1.0, -1.0, 1.0) if all > 0.0 else 0.0,
		"presence": ReactionTable.INTERPRETATIONS[best] if all > 0.0 else &"",
		"presence_share": beliefs[best] / all if all > 0.0 else 0.0,
		"architecture": architecture_of(own),
		"palette": palette_of(own),
		"traditions": mine,
		"myths": myths,
		"beliefs": _shares(beliefs, all),
	}


static func _shares(beliefs: PackedFloat32Array, all: float) -> PackedFloat32Array:
	var out := beliefs.duplicate()
	for i in out.size():
		out[i] = out[i] / all if all > 0.0 else 0.0
	return out


## The share of a settlement's belief that what happens is the interpretation
## `index`'s (ReactionTable.INTERPRETATIONS) — as last worked out (0: unknown).
func belief_share(settlement_id: int, index: int) -> float:
	var profile: Dictionary = profiles.get(settlement_id, {})
	var shares: Variant = profile.get("beliefs")
	return float(shares[index]) if typeof(shares) == TYPE_PACKED_FLOAT32_ARRAY and index < (shares as PackedFloat32Array).size() else 0.0


## How a settlement thatches its roofs (0 … ARCHITECTURES - 1): its own,
## from its beginning (the first: the band's way).
func architecture_of(own: Settlement) -> int:
	if own == null or own == settlements.primary():
		return 0
	return posmod(hash([world_seed, own.id, "roofs"]), ARCHITECTURES)


## The colours a settlement wears (0 … PALETTES - 1).
func palette_of(own: Settlement) -> int:
	if own == null or own == settlements.primary():
		return 0
	return posmod(hash([world_seed, own.id, "cloth"]), PALETTES)


# --- traditions ---------------------------------------------------------------------------------------

## Once a game day: profiles (yearly), traditions formed and faded, festivals.
func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today != _day:
		_day = today
		each_day(now)
	_festivals(now)


func each_day(now: int) -> void:
	if settlements == null:
		return
	# (Cheap: worked out daily, as belief feeds how things are taken — M17.2.)
	for own in settlements.all():
		profiles[own.id] = profile_of(own)
	look_for_traditions(now)


## What its people live through again and again, felt and taken alike, becomes a tradition.
func look_for_traditions(now: int) -> void:
	if culture == null:
		return
	for own in settlements.all():
		var people := own.member_count()
		for entry in culture.of(own.id):
			var subject := StringName(entry["subject"])
			if not FROM_MEMORIES.has(subject):
				continue
			var interpretation := StringName(entry["interpretation"])
			var existing := tradition_of(own.id, subject)
			if not existing.is_empty():
				existing["rooted"] = now
				continue
			if int(entry["holders"]) < ceili(HELD_SHARE * people) or float(entry["strength"]) < HELD_SHARE:
				continue
			var days := culture.days_lived(own.id, subject, interpretation)
			if days < LIVED_DAYS or culture.seasons_lived(own.id, subject, interpretation) < LIVED_SEASONS:
				continue
			var from: Array = FROM_MEMORIES[subject]
			var first_day := culture.first_day_lived(own.id, subject, interpretation)
			_form(own, String(from[0]), String(from[1]), String(from[2]), String(subject), interpretation,
				posmod(first_day, Config.time.days_per_year()) + 1, now, _player_act(own, subject))
	# Firsts.
	if events != null:
		for key: String in FROM_FIRSTS:
			var parts := key.split(":")
			for e in events.of_type(StringName(parts[0])):
				if parts.size() > 1 and str(e.text_params.get("building", "")) != parts[1]:
					continue
				var own := settlements.get_settlement(e.settlement_id) if e.settlement_id != 0 else settlements.primary()
				if own == null or not tradition_of(own.id, StringName(key)).is_empty():
					continue
				var from: Array = FROM_FIRSTS[key]
				var season := int(from[2])
				var day := Config.time.days_per_season * season + 1 if season >= 0 else Config.time.day_of_year(e.tick)
				_form(own, String(from[0]), String(from[1]), "day", key, &"", day, now, 0)
				break
	# What is no longer remembered fades, in time.
	var gone: Array[Dictionary] = []
	for tradition in traditions:
		var root := StringName(str(tradition["source"]))
		if not FROM_MEMORIES.has(root):
			continue
		var held := false
		for entry in culture.of(int(tradition["settlement"])):
			held = held or StringName(entry["subject"]) == root
		if held:
			tradition["rooted"] = now
		elif now - int(tradition["rooted"]) > FADES_AFTER_YEARS * Config.time.ticks_per_year():
			gone.append(tradition)
	for tradition in gone:
		traditions.erase(tradition)
		tradition_faded.emit(tradition)


func _form(own: Settlement, name_key: String, kind: String, when: String, source: String, interpretation: StringName,
		day: int, now: int, act: int) -> void:
	var tradition := {"id": _next, "settlement": own.id, "name": name_key, "kind": kind, "when": when,
		"day": clampi(day, 1, Config.time.days_per_year()), "source": source, "interpretation": String(interpretation),
		"formed": now, "rooted": now, "player": act != 0, "intervention": act, "kept": 0, "last": -1}
	_next += 1
	traditions.append(tradition)
	tradition_formed.emit(tradition)


## The player's act a settlement's memories of `subject` go back to (the one
## most of them remember; 0: none — it was nature's doing).
func _player_act(own: Settlement, subject: StringName) -> int:
	if culture == null or culture.memory_store() == null:
		return 0
	var counted := {}
	for person in own.members():
		for memory in culture.memory_store().about(person, subject):
			if memory.intervention_id != 0:
				counted[memory.intervention_id] = int(counted.get(memory.intervention_id, 0)) + 1
	var best := 0
	for act: int in counted:
		if best == 0 or int(counted[act]) > int(counted[best]) or (int(counted[act]) == int(counted[best]) and act < best):
			best = act
	return best


func tradition_of(settlement_id: int, source: StringName) -> Dictionary:
	for tradition in traditions:
		if int(tradition["settlement"]) == settlement_id and StringName(str(tradition["source"])) == source:
			return tradition
	return {}


func traditions_of(settlement_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for tradition in traditions:
		if int(tradition["settlement"]) == settlement_id:
			out.append(tradition)
	return out


## A settlement founded from another keeps its traditions (and its look is its own).
func on_founded(own: Settlement, journey: Dictionary) -> void:
	var from := int(journey.get("from", 0))
	for tradition in traditions.duplicate():
		if int(tradition["settlement"]) == from and tradition_of(own.id, StringName(str(tradition["source"]))).is_empty():
			var copy: Dictionary = tradition.duplicate()
			copy["id"] = _next
			_next += 1
			copy["settlement"] = own.id
			copy["kept"] = 0
			copy["last"] = -1
			traditions.append(copy)


func forget_settlement(settlement_id: int) -> void:
	traditions = traditions.filter(func(t: Dictionary) -> bool: return int(t["settlement"]) != settlement_id)
	profiles.erase(settlement_id)
	_on.erase(settlement_id)


# --- festivals ----------------------------------------------------------------------------------------

## At dusk on a tradition's day, its festival; a ritual of the drought when one begins.
func _festivals(now: int) -> void:
	var hour := float(Config.time.minute_of_day(now)) / 60.0
	for id: int in _on.keys():
		if now >= int(_on[id][1]):
			_on.erase(id)
	if hour < DUSK or hour >= DUSK + FESTIVAL_HOURS:
		return
	var today := Config.time.day_of_year(now)
	for tradition in traditions:
		if String(tradition["when"]) != "day" or int(tradition["day"]) != today:
			continue
		_begin(tradition, now)


## A drought begins: those whose ritual it is dance for rain (that evening).
func on_condition(condition: StringName, active: bool, now: int) -> void:
	if not active or condition != WeatherSystem.DROUGHT:
		return
	for tradition in traditions:
		if String(tradition["when"]) == "drought":
			_begin(tradition, now, true)


func _begin(tradition: Dictionary, now: int, any_hour: bool = false) -> void:
	var settlement := int(tradition["settlement"])
	if _on.has(settlement) or (int(tradition["last"]) >= 0 and Config.time.day_index(int(tradition["last"])) == Config.time.day_index(now)):
		return
	var hour := float(Config.time.minute_of_day(now)) / 60.0
	var start := now if not any_hour or hour >= DUSK else now + roundi((DUSK - hour) * 60.0)
	_on[settlement] = [int(tradition["id"]), start + roundi(FESTIVAL_HOURS * 60.0), start]
	tradition["kept"] = int(tradition["kept"]) + 1
	tradition["last"] = now
	festival.emit(settlement, tradition)


## The festival a settlement's people are keeping now ({}: none).
func festival_now(settlement_id: int, now: int) -> Dictionary:
	var on: Variant = _on.get(settlement_id)
	if on == null or now < int(on[2]) or now >= int(on[1]):
		return {}
	for tradition in traditions:
		if int(tradition["id"]) == int(on[0]):
			return tradition
	return {}


# --- saving ----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var kept: Array = []
	for tradition in traditions:
		kept.append(tradition.duplicate())
	return {"traditions": kept, "next": _next, "day": _day}


func from_dict(data: Dictionary) -> void:
	traditions.clear()
	profiles.clear()
	_on.clear()
	if typeof(data.get("traditions")) == TYPE_ARRAY:
		for t: Variant in data["traditions"]:
			if typeof(t) == TYPE_DICTIONARY and (t as Dictionary).has_all(["id", "settlement", "name", "kind", "when", "day", "source"]):
				var tradition: Dictionary = (t as Dictionary).duplicate()
				for key: String in ["formed", "rooted", "intervention", "kept", "last"]:
					tradition[key] = int(tradition.get(key, -1 if key == "last" else 0))
				tradition["player"] = bool(tradition.get("player", false))
				traditions.append(tradition)
	_next = maxi(int(data.get("next", 1)), 1)
	for tradition in traditions:
		_next = maxi(_next, int(tradition["id"]) + 1)
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var parts := PackedStringArray()
	for tradition in traditions:
		parts.append("%d:%s%s(day %d, kept %d)" % [int(tradition["settlement"]), str(tradition["name"]).trim_prefix("TRADITION_").to_lower(),
			"*" if bool(tradition["player"]) else "", int(tradition["day"]), int(tradition["kept"])])
	return "traditions: %s  festivals now %d" % [" ".join(parts) if not parts.is_empty() else "-", _on.size()]
