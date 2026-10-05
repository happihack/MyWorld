class_name StoryEngine
extends RefCounted
## The stories history tells (M19.2–19.3, bible §21.3): nobody writes them.
##
## Once a game year — and soon after anything momentous — the engine walks the
## web of what caused what (WorldEvent.causes, recorded when each event was)
## and finds **chains**: a drought → a failed harvest → a hungry season → a
## move away → a new settlement. Each is scored by how much its events
## mattered, how long it is, who was in it, and how unlike the stories already
## told it is; the best few that have not been told are **told**: named
## ("the Great Drought", "the War of Ama's camp and Miska") and put in words
## ("The Great Drought of Year 83 caused a hungry season and eventually led to
## the founding of Northwatch."). A story is never told twice (nor one that
## mostly retells another).
##
## **Historians**, once there is writing and someone to look into the past,
## now and then **reinterpret** an old story ("A historian has proposed a new
## explanation for the Great Flood").

signal told(story: Dictionary)
signal reinterpreted(story: Dictionary, historian: int)

## Chains of at least this many events are stories (a cause, what it led to, and more).
const LEAST_EVENTS := 3
## At most this many stories a year, and only above this score.
const PER_YEAR := 3
const LEAST_SCORE := 2.5
## How long a chain may grow (events).
const LONGEST := 8
## A chain sharing this share of its events with one told is a retelling.
const OVERLAP := 0.5
## A story has at least one event that mattered this much (a hungry season the first
## time, a death, a founding, a war — not a quarrel and a fight alone).
const WEIGHTY := 0.75
## The same shape of story (the same kinds of events, in order) is not told again
## within this many years, nor more than this many times.
const SHAPE_YEARS := 20
const SHAPE_MOST := 3
## Something this significant prompts a look soon after (days).
const MOMENTOUS := 0.9
const SOON_DAYS := 2
## A historian reinterprets an old story (the chance a year), of one at least this old (years).
const REINTERPRET_CHANCE := 0.2
const OLD_YEARS := 20
## Event types whose names are the story's (the first that heads a chain names it).
const NAMED: Array[StringName] = [&"drought", &"flood", &"food_shortage", &"crop_failure", &"storm", &"cold_snap", &"heat_wave",
	&"war_begun", &"raid", &"migration", &"settlement_founded", &"high_water", &"person_died", &"myth_formed", &"tradition_formed",
	&"knowledge_learned", &"player_intervention", &"schism", &"revolution"]

var events: EventLog
var people: PersonRegistry
var significance: Significance
## Is there a historian (writing and someone looking into the past)? Callable() -> int (their id; 0: none).
var historian := Callable()
## Every story told: {"id", "events" (ids, the cause first), "type" (of its first), "year", "score",
##   "player" (bool: the player's doing is in it), "told" (tick), "reinterpreted" (bool)}.
var stories: Array[Dictionary] = []
var _told: Dictionary = {} # event id -> story id
var _next := 1
var _year := -1
var _soon := -1 # the day to look again (after something momentous)
## How many were told in the year being told of (PER_YEAR at most, however often it looks).
var _this_year := 0
var _counted_year := -1


func bind(log: EventLog, registry: PersonRegistry, now: int) -> void:
	events = log
	people = registry
	_year = Config.time.year_of(now)


## Something was recorded: if it was momentous, look again soon.
func on_recorded(event: WorldEvent) -> void:
	if event != null and event.significance >= MOMENTOUS and _soon < 0:
		_soon = Config.time.day_index(event.tick) + SOON_DAYS


func advance_to(now: int) -> void:
	var year := Config.time.year_of(now)
	var day := Config.time.day_index(now)
	if _year < 0:
		_year = year
	if year != _year or (_soon >= 0 and day >= _soon):
		_year = year
		_soon = -1
		mine(now)
		reinterpret(now)


# --- finding chains ---------------------------------------------------------------------------------

## Finds, scores and tells the best new stories. Returns those told.
func mine(now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if events == null:
		return out
	var year := Config.time.year_of(now)
	if year != _counted_year:
		_counted_year = year
		_this_year = 0
	var best_back := {} # event id -> [path (end first), score]
	var candidates: Array = []
	for event in events.all_events():
		if event.causes.is_empty():
			continue
		var path: Array = _best_back(event, best_back, 0)[0]
		if path.size() >= LEAST_EVENTS:
			candidates.append(path)
	var scored: Array = [] # [score, chain (cause first)]
	for path: Array in candidates:
		var chain := path.duplicate()
		chain.reverse()
		if _retold(chain) or not _weighty(chain):
			continue
		scored.append([score_of(chain), chain])
	scored.sort_custom(func(x: Array, y: Array) -> bool:
		return float(x[0]) > float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1][-1]) < int(y[1][-1])))
	for entry: Array in scored:
		if _this_year >= PER_YEAR or float(entry[0]) < LEAST_SCORE:
			break
		if _retold(entry[1]) or not _fresh_shape(entry[1], now):
			continue # (an earlier pick took most of it; or the like was told of lately)
		out.append(_tell(entry[1], float(entry[0]), now))
		_this_year += 1
	return out


## The highest-scoring chain back from `event` (end first), memoized: [path, score].
func _best_back(event: WorldEvent, memo: Dictionary, depth: int) -> Array:
	if memo.has(event.id):
		return memo[event.id]
	var best: Array = [[event.id], event.significance]
	if depth < LONGEST - 1:
		for cause_id in event.causes:
			var cause := events.get_event(cause_id)
			if cause == null or cause.tick > event.tick:
				continue
			var back: Array = _best_back(cause, memo, depth + 1)
			var path: Array = [event.id]
			path.append_array(back[0])
			var total := float(back[1]) + event.significance
			if total > float(best[1]) or (total == float(best[1]) and path.size() > (best[0] as Array).size()):
				best = [path, total]
	memo[event.id] = best
	return best


## How good a story a chain makes: what its events mattered, its length, who
## was in it, and how unlike the stories already told it is.
func score_of(chain: Array) -> float:
	var total := 0.0
	var told_types := {}
	for story in stories:
		told_types[str(story["type"])] = true
	var fresh := 0
	var who := {}
	for id: int in chain:
		var event := events.get_event(id)
		if event == null:
			continue
		total += event.significance
		if not told_types.has(String(event.type)):
			fresh += 1
		for person_id in event.participants:
			who[person_id] = true
	var important := 0.0
	if significance != null:
		for person_id: int in who:
			important += minf(significance.points_of(person_id), 1.0)
	return total + 0.3 * chain.size() + 0.25 * fresh + 0.2 * important


## Does something in it matter enough for a story?
func _weighty(chain: Array) -> bool:
	for id: int in chain:
		var event := events.get_event(id)
		if event != null and event.significance >= WEIGHTY:
			return true
	return false


## Its shape: the kinds of its events, in order.
func shape_of(chain: Array) -> String:
	var kinds := PackedStringArray()
	for id: int in chain:
		var event := events.get_event(id)
		kinds.append(String(event.type) if event != null else "?")
	return ">".join(kinds)


## Has the like of it been told lately, or too often?
func _fresh_shape(chain: Array, now: int) -> bool:
	var shape := shape_of(chain)
	var times := 0
	for story in stories:
		if str(story.get("shape", "")) != shape:
			continue
		times += 1
		if Config.time.year_of(now) - Config.time.year_of(int(story["told"])) < SHAPE_YEARS:
			return false
	return times < SHAPE_MOST


## Is most of it told already (or its end)? (A new branch from a cause already
## told of is a new story.)
func _retold(chain: Array) -> bool:
	if _told.has(int(chain[-1])):
		return true
	var shared := 0
	for id: int in chain:
		if _told.has(id):
			shared += 1
	return float(shared) / chain.size() >= OVERLAP


func _tell(chain: Array, score: float, now: int) -> Dictionary:
	var first := events.get_event(int(chain[0]))
	var player := false
	for id: int in chain:
		var event := events.get_event(id)
		player = player or (event != null and event.type == &"player_intervention")
	var story := {"id": _next, "events": chain.duplicate(), "type": String(first.type) if first != null else "", "shape": shape_of(chain),
		"year": Config.time.year_of(first.tick) if first != null else 0, "score": score, "player": player, "told": now,
		"reinterpreted": false}
	_next += 1
	# Its words, as they are now (its events may be forgotten by the log in time).
	story["name"] = name_of(story)
	story["summary"] = summary(story)
	stories.append(story)
	for id: int in chain:
		_told[int(id)] = int(story["id"])
	told.emit(story)
	return story


# --- in words -------------------------------------------------------------------------------------------

## A story's name: what heads it, in its kind's words ("the Great Drought",
## "the War of Ama's camp and Miska").
func name_of(story: Dictionary) -> String:
	if story.has("name"):
		return str(story["name"])
	var first := events.get_event(int(story["events"][0]))
	if first == null:
		return MemoryText.translate("STORY_NAME")
	var key := "STORY_NAME_" + String(first.type).to_upper()
	var params := EventText.params_of(first, people)
	params["great"] = MemoryText.translate("STORY_GREAT") if float(story["score"]) >= 4.5 else ""
	params["season"] = MemoryText.translate("SEASON_%d" % Config.time.season_of(first.tick))
	params["year"] = Config.time.year_of(first.tick)
	var text := MemoryText.translate(key if MemoryText.has(key) else "STORY_NAME_ANY").format(params)
	return text.replace("  ", " ")


## What an event is, as a part of a story ("a hungry season", "the founding of Miska").
func noun_of(event: WorldEvent) -> String:
	var key := "STORY_NOUN_" + String(event.type).to_upper()
	var params := EventText.params_of(event, people)
	if MemoryText.has(key):
		return MemoryText.translate(key).format(params)
	var text := EventText.text(event, people, events)
	# ("The fire has gone out" → "the fire has gone out"; a name keeps its capital.)
	var word := text.get_slice(" ", 0)
	if ["The", "A", "An"].has(word):
		return text.substr(0, 1).to_lower() + text.substr(1)
	return text


## The story in a sentence: "The Great Drought of Year 83 caused a hungry
## season and eventually led to the founding of Northwatch."
func summary(story: Dictionary) -> String:
	if story.has("summary"):
		return str(story["summary"])
	var chain := told_steps(story)
	var parts := PackedStringArray()
	for id: int in chain:
		var event := events.get_event(id)
		parts.append(noun_of(event) if event != null else MemoryText.translate("STORY_SOMETHING"))
	# What heads it by its name ("The Great Drought of Year 83 …"), or — if its kind
	# has none — plainly ("In Year 4, work on a bridge …").
	var first := events.get_event(int(chain[0]))
	var named := first != null and MemoryText.has("STORY_NAME_" + String(first.type).to_upper())
	var params := {"first": MemoryText.capitalized(name_of(story)) if named else parts[0], "year": int(story["year"]),
		"second": parts[1] if parts.size() > 1 else "", "third": parts[2] if parts.size() > 2 else "", "last": parts[-1]}
	var shape := "STORY_THREE" if chain.size() == 3 else ("STORY_TWO" if chain.size() == 2 else "STORY_LONG")
	return MemoryText.translate(shape + ("" if named else "_PLAIN")).format(params)


## The steps of a story worth saying: work begun on a building that was then
## finished is said once ("a new bridge", not "work on a bridge … a new bridge").
func told_steps(story: Dictionary) -> Array:
	var chain: Array = story["events"]
	var out: Array = []
	for n in chain.size():
		var event := events.get_event(int(chain[n]))
		var next := events.get_event(int(chain[n + 1])) if n + 1 < chain.size() else null
		if event != null and next != null and event.type == &"building_begun" and next.type == &"building_built":
			continue
		out.append(chain[n])
	return out


## A line for a list: "YEAR 83 · The Great Drought of Year 83 caused …".
func line(story: Dictionary) -> String:
	return MemoryText.translate("HIST_YEAR").format({"year": int(story["year"]), "text": summary(story)})


# --- historians ------------------------------------------------------------------------------------------

## Now and then a historian takes up an old story and explains it anew.
func reinterpret(now: int) -> void:
	if not historian.is_valid():
		return
	var who := int(historian.call())
	if who == 0:
		return
	var roll := float(posmod(hash([_year, "historian"]), 1000)) / 1000.0
	if roll >= REINTERPRET_CHANCE:
		return
	for story in stories:
		if bool(story["reinterpreted"]) or Config.time.year_of(now) - int(story["year"]) < OLD_YEARS:
			continue
		story["reinterpreted"] = true
		reinterpreted.emit(story, who)
		return


## The stories the player's doing is in (for the Interaction History).
func of_the_player() -> Array[Dictionary]:
	return stories.filter(func(s: Dictionary) -> bool: return bool(s["player"]))


func to_dict() -> Dictionary:
	var kept: Array = []
	for story in stories:
		kept.append(story.duplicate(true))
	return {"stories": kept, "next": _next, "year": _year, "soon": _soon, "this_year": _this_year, "counted": _counted_year}


func from_dict(data: Dictionary) -> void:
	stories.clear()
	_told.clear()
	if typeof(data.get("stories")) == TYPE_ARRAY:
		for s: Variant in data["stories"]:
			if typeof(s) == TYPE_DICTIONARY and (s as Dictionary).has_all(["id", "events", "year"]):
				var story: Dictionary = (s as Dictionary).duplicate(true)
				story["reinterpreted"] = bool(story.get("reinterpreted", false))
				story["player"] = bool(story.get("player", false))
				story["score"] = float(story.get("score", 0.0))
				story["type"] = str(story.get("type", ""))
				stories.append(story)
				for id: Variant in story["events"]:
					_told[int(id)] = int(story["id"])
	_next = maxi(int(data.get("next", 1)), 1)
	for story in stories:
		_next = maxi(_next, int(story["id"]) + 1)
	if typeof(data.get("year")) == TYPE_INT:
		_year = int(data["year"])
	_soon = int(data.get("soon", -1))
	_this_year = int(data.get("this_year", 0))
	_counted_year = int(data.get("counted", -1))


func debug_text() -> String:
	return "stories: %d told (%d of the player's)" % [stories.size(), of_the_player().size()]
