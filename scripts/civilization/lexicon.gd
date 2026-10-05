class_name Lexicon
extends RefCounted
## Words (M17.3, bible §19.5): no natural language — a registry of **concepts**
## (what people meet: the unseen hand, rain from a clear sky, the flood, the
## river, the hills, the Edge, their own place …) and, for each settlement, the
## **words** its people have for them, in the sounds of their speech
## (Phonology).
##
## - A concept gets a word when it is **met often enough to need one** (the
##   days its people live with it, counted in its pool).
## - Words are **inherited** — a settlement founded from another speaks as it
##   did — **borrowed** with the loads carried (a word they had no word for),
##   and **drift**: once settlements have been apart for years, the words they
##   share change a sound now and then, each its own way.
## - Shown **with glosses**: "Velun (the Rainbringer)".
## - When a settlement has a word for its own place, it **takes it as its
##   name** ("the first camp came to be called Tiravel").

## A word was coined, or a settlement renamed.
signal coined(settlement_id: int, concept: StringName, word: String)
signal renamed(settlement_id: int, old_name: String, new_name: String)

## The concepts, and what each is met as: concept -> [what counts it, gloss key].
## What counts: a memory subject ("subject:<id>"), a myth of it ("myth:<subject>"),
## the place itself ("home"), the world's walls ("edge"), a region kind ("region:<kind>").
const CONCEPTS := {
	&"presence": ["presence", "CONCEPT_PRESENCE"],
	&"touch": ["subject:touch", "CONCEPT_TOUCH"],
	&"rain_from_clear_sky": ["subject:rain_from_clear_sky", "CONCEPT_RAIN_FROM_CLEAR_SKY"],
	&"object_moved": ["subject:object_moved", "CONCEPT_OBJECT_MOVED"],
	&"sourceless_wind": ["subject:sourceless_wind", "CONCEPT_SOURCELESS_WIND"],
	&"flood": ["subject:life_flood", "CONCEPT_FLOOD"],
	&"rainbringer": ["myth:rain_from_clear_sky", "EPITHET_RAIN_FROM_CLEAR_SKY"],
	&"unseen_hand": ["myth:touch", "EPITHET_TOUCH"],
	&"mover": ["myth:object_moved", "EPITHET_OBJECT_MOVED"],
	&"windcaller": ["myth:sourceless_wind", "EPITHET_SOURCELESS_WIND"],
	&"home": ["home", "CONCEPT_HOME"],
	&"edge": ["edge", "CONCEPT_EDGE"],
	&"river": ["region:water", "CONCEPT_RIVER"],
	&"hills": ["region:hills", "CONCEPT_HILLS"],
	&"valley": ["region:lowland", "CONCEPT_VALLEY"],
}
## Met on this many people-days (counted daily), a concept gets a word.
const COIN_AT := 40.0
## A load carried may bring a word along (the chance, for each concept they lack one for).
const BORROW_PER_LOAD := 0.05
## After this many years apart, a shared word may change a sound each year (the chance).
const DRIFT_AFTER_YEARS := 10
const DRIFT_CHANCE := 0.04
const VOWELS := "aeiou"

var settlements: Settlements
var culture: CulturalMemory
var world_seed := 0
## Has the box's Edge been found (FogOfKnowledge.edge_reached)? Callable() -> bool.
var edge_known := Callable()
## Which kinds of region the settlement's people have come to: Callable(settlement) -> Array[String].
var regions_of := Callable()
## Settlement id -> {"words": {concept -> {"word", "coined", "from"}}, "use": {concept -> float},
##   "parent": settlement id it was founded from (0: none), "apart": tick it was founded, "language": seed}.
var tongues: Dictionary = {}
var _day := -1_000_000


func bind(all: Settlements, memory: CulturalMemory, seed_value: int, now: int) -> void:
	settlements = all
	culture = memory
	world_seed = seed_value
	_day = Config.time.day_index(now)


func _tongue(settlement_id: int) -> Dictionary:
	if not tongues.has(settlement_id):
		tongues[settlement_id] = {"words": {}, "use": {}, "parent": 0, "apart": 0,
			"language": RngStreams.derive_seed(world_seed, &"culture:%d" % WorldSession.FIRST_CULTURE_ID)}
	return tongues[settlement_id]


## A settlement's word for a concept ("": none yet).
func word(settlement_id: int, concept: StringName) -> String:
	var entry: Variant = (_tongue(settlement_id)["words"] as Dictionary).get(concept)
	return str((entry as Dictionary)["word"]) if entry != null else ""


## The concept in words, with its gloss: "Velun (the Rainbringer)" — or the
## gloss alone, if they have no word for it.
func gloss(settlement_id: int, concept: StringName) -> String:
	var meaning := MemoryText.translate(str(CONCEPTS[concept][1])) if CONCEPTS.has(concept) else String(concept)
	var said := word(settlement_id, concept)
	return MemoryText.translate("WORD_GLOSS").format({"word": said, "gloss": meaning}) if said != "" else meaning


## The concept a myth's epithet stands for (&"": none).
static func concept_of_myth(subject: StringName) -> StringName:
	for concept: StringName in CONCEPTS:
		if str(CONCEPTS[concept][0]) == "myth:" + String(subject):
			return concept
	return &""


# --- coining --------------------------------------------------------------------------------------

## Once a game day: what is met is counted; what is met enough gets a word;
## words drift (yearly).
func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	each_day(now)


func each_day(now: int) -> void:
	if settlements == null:
		return
	for own in settlements.all():
		var tongue := _tongue(own.id)
		var use: Dictionary = tongue["use"]
		var met := _met(own)
		for concept: StringName in met:
			use[concept] = float(use.get(concept, 0.0)) + float(met[concept])
			if float(use[concept]) >= COIN_AT and word(own.id, concept) == "":
				coin(own, concept, now)
		if Config.time.day_of_year(now) == 1:
			drift(own, now)


## How much each concept was met today by a settlement's people (people-days).
func _met(own: Settlement) -> Dictionary:
	var out := {}
	var people := own.member_count()
	if culture != null:
		for entry in culture.of(own.id):
			var subject := String(entry["subject"])
			for concept: StringName in CONCEPTS:
				if str(CONCEPTS[concept][0]) == "subject:" + subject:
					out[concept] = float(out.get(concept, 0.0)) + float(int(entry["holders"]))
			# Whatever is someone's doing is the Presence, to them.
			if CultureSystem.SUPERNATURAL.has(StringName(entry["interpretation"])):
				out[&"presence"] = float(out.get(&"presence", 0.0)) + float(int(entry["holders"])) * 0.5
		for myth in culture.myths():
			if int(myth["settlement"]) != own.id:
				continue
			var concept := concept_of_myth(StringName(str(myth["subject"])))
			if concept != &"":
				out[concept] = float(out.get(concept, 0.0)) + float(maxi(int(myth["believers"]), 1))
	# Their own place: everyone, every day (it gets a name in time).
	out[&"home"] = float(people) * 0.15
	if edge_known.is_valid() and bool(edge_known.call()):
		out[&"edge"] = float(people) * 0.3
	if regions_of.is_valid():
		for kind: String in regions_of.call(own):
			for concept: StringName in CONCEPTS:
				if str(CONCEPTS[concept][0]) == "region:" + kind:
					out[concept] = float(out.get(concept, 0.0)) + float(people) * 0.2
	return out


## A settlement makes a word for a concept, in its sounds.
func coin(own: Settlement, concept: StringName, now: int) -> String:
	var tongue := _tongue(own.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, own.id, String(concept), "word"])
	var speech := NameGenerator.new(Phonology.from_seed(int(tongue["language"])))
	var made := ""
	for attempt in 12:
		made = speech.word(rng, 2 if rng.randf() < 0.7 else 3).capitalize()
		if NameGenerator.is_acceptable(made) and not _taken(own.id, made):
			break
	(tongue["words"] as Dictionary)[concept] = {"word": made, "coined": now, "from": 0}
	coined.emit(own.id, concept, made)
	if concept == &"home":
		_rename(own, made)
	return made


func _taken(settlement_id: int, said: String) -> bool:
	for entry: Dictionary in (_tongue(settlement_id)["words"] as Dictionary).values():
		if str(entry["word"]) == said:
			return true
	return false


func _rename(own: Settlement, new_name: String) -> void:
	var old := own.display_name()
	if old == new_name:
		return
	own.settlement_name = new_name
	renamed.emit(own.id, old, new_name)


# --- inheriting, borrowing, drifting ----------------------------------------------------------------

## A settlement founded from another speaks as it did: its words, its sounds —
## but its own name for its own place, in time.
func on_founded(own: Settlement, journey: Dictionary) -> void:
	var from := int(journey.get("from", 0))
	var parent := _tongue(from)
	var tongue := _tongue(own.id)
	tongue["language"] = parent["language"]
	tongue["parent"] = from
	tongue["apart"] = int(journey.get("tick", 0)) if journey.has("tick") else _day * TimeConfig.MINUTES_PER_DAY
	for concept: StringName in (parent["words"] as Dictionary):
		if concept == &"home":
			continue
		var entry: Dictionary = (parent["words"] as Dictionary)[concept]
		(tongue["words"] as Dictionary)[concept] = {"word": entry["word"], "coined": entry["coined"], "from": from}


## A load carried may bring a word along — for what the receivers met, but had no word for.
func on_traded(record: Dictionary) -> void:
	var from := int(record.get("from", 0))
	var to := int(record.get("to", 0))
	var theirs: Dictionary = _tongue(from)["words"]
	var ours := _tongue(to)
	for concept: StringName in theirs:
		if concept == &"home" or word(to, concept) != "" or float((ours["use"] as Dictionary).get(concept, 0.0)) <= 0.0:
			continue
		var draw := float(posmod(hash([from, to, String(concept), int(record.get("units", 0)), _day, "borrow"]), 100000)) / 100000.0
		if draw < BORROW_PER_LOAD:
			(ours["words"] as Dictionary)[concept] = {"word": (theirs[concept] as Dictionary)["word"], "coined": _day * TimeConfig.MINUTES_PER_DAY, "from": from}
			coined.emit(to, concept, str((theirs[concept] as Dictionary)["word"]))


## Words a settlement shares with others change, once they have been apart for long.
func drift(own: Settlement, now: int) -> void:
	var tongue := _tongue(own.id)
	if int(tongue["parent"]) == 0 or now - int(tongue["apart"]) < DRIFT_AFTER_YEARS * Config.time.ticks_per_year():
		return
	var year := Config.time.year_of(now)
	for concept: StringName in (tongue["words"] as Dictionary):
		var entry: Dictionary = (tongue["words"] as Dictionary)[concept]
		if int(entry["from"]) == 0:
			continue
		var draw := float(posmod(hash([own.id, String(concept), year, "drift"]), 100000)) / 100000.0
		if draw < DRIFT_CHANCE:
			entry["word"] = shifted(str(entry["word"]), hash([own.id, String(concept), year]))


## A word with one of its vowels changed (deterministic for `salt`).
static func shifted(said: String, salt: int) -> String:
	var spots: Array[int] = []
	for i in said.length():
		if VOWELS.contains(said[i].to_lower()):
			spots.append(i)
	if spots.is_empty():
		return said
	var at: int = spots[posmod(salt, spots.size())]
	var was := said[at].to_lower()
	var now := VOWELS[(VOWELS.find(was) + 1 + posmod(salt >> 4, VOWELS.length() - 1)) % VOWELS.length()]
	var out := said.substr(0, at) + (now.to_upper() if at == 0 else now) + said.substr(at + 1)
	return out


## How alike two settlements' words are: for the concepts both have words
## for, how alike they sound, on average (1: one language; -1: nothing to compare).
func kinship(a: int, b: int) -> float:
	var both := 0
	var alike := 0.0
	for concept: StringName in (_tongue(a)["words"] as Dictionary):
		if word(b, concept) == "":
			continue
		both += 1
		alike += likeness(word(a, concept), word(b, concept))
	return alike / both if both > 0 else -1.0


## How alike two words are, 0 … 1 (1: the same; by the letters that must change).
static func likeness(x: String, y: String) -> float:
	x = x.to_lower()
	y = y.to_lower()
	var longest := maxi(x.length(), y.length())
	if longest == 0:
		return 1.0
	var row := PackedInt32Array()
	for j in y.length() + 1:
		row.append(j)
	for i in range(1, x.length() + 1):
		var previous := row[0]
		row[0] = i
		for j in range(1, y.length() + 1):
			var keep := row[j]
			row[j] = mini(mini(row[j] + 1, row[j - 1] + 1), previous + (0 if x[i - 1] == y[j - 1] else 1))
			previous = keep
	return 1.0 - float(row[y.length()]) / longest


func forget_settlement(settlement_id: int) -> void:
	tongues.erase(settlement_id)


func to_dict() -> Dictionary:
	var kept := {}
	for id: int in tongues:
		var tongue: Dictionary = tongues[id]
		var words := {}
		for concept: StringName in (tongue["words"] as Dictionary):
			words[String(concept)] = (tongue["words"][concept] as Dictionary).duplicate()
		var use := {}
		for concept: StringName in (tongue["use"] as Dictionary):
			use[String(concept)] = float(tongue["use"][concept])
		kept[str(id)] = {"words": words, "use": use, "parent": tongue["parent"], "apart": tongue["apart"], "language": tongue["language"]}
	return {"tongues": kept, "day": _day}


func from_dict(data: Dictionary) -> void:
	tongues.clear()
	if typeof(data.get("tongues")) == TYPE_DICTIONARY:
		for key: Variant in data["tongues"]:
			var saved: Variant = data["tongues"][key]
			if not str(key).is_valid_int() or typeof(saved) != TYPE_DICTIONARY:
				continue
			var tongue := _tongue(int(str(key)))
			if typeof(saved.get("words")) == TYPE_DICTIONARY:
				for concept: Variant in saved["words"]:
					var entry: Variant = saved["words"][concept]
					if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("word"):
						(tongue["words"] as Dictionary)[StringName(str(concept))] = {"word": str(entry["word"]),
							"coined": int(entry.get("coined", 0)), "from": int(entry.get("from", 0))}
			if typeof(saved.get("use")) == TYPE_DICTIONARY:
				for concept: Variant in saved["use"]:
					(tongue["use"] as Dictionary)[StringName(str(concept))] = float(saved["use"][concept])
			tongue["parent"] = int(saved.get("parent", 0))
			tongue["apart"] = int(saved.get("apart", 0))
			tongue["language"] = int(saved.get("language", tongue["language"]))
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var parts := PackedStringArray()
	for id: int in tongues:
		var words: Dictionary = tongues[id]["words"]
		var said := PackedStringArray()
		for concept: StringName in words:
			said.append("%s=%s" % [concept, (words[concept] as Dictionary)["word"]])
		parts.append("%d: %s" % [id, ", ".join(said) if not said.is_empty() else "-"])
	return "words: %s" % "  |  ".join(parts)
