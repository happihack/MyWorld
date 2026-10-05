class_name MythSystem
extends RefCounted
## What becomes of a myth (M17.2, bible §19.4): no religion is given — beliefs
## grow out of what people live through (Interpretation, CulturalMemory). Once
## a myth has formed:
##
## - **the places where it showed itself are sacred** (ChunkData.FLAG_SACRED);
## - **someone speaks for it** — the one of its believers who holds it most
##   and matters most: its founder (an event, so history remembers them as such);
## - **a shrine** is built at its sacred place once enough believe
##   (SettlementPlanner, "shrine");
## - **it travels**: a settlement founded from another takes its myths along;
##   a load carried may bring a myth with it;
## - **it splits**: when a settlement's people hold two myths of the same thing
##   — one takes it for a god's doing, others for a spirit's — and both have many
##   believers, history tells of a schism.

## A myth founded (by `person_id`), carried to another settlement, or split.
signal founded(myth: Dictionary, person_id: int)
signal spread(myth: Dictionary, from_settlement: int)
signal schism(settlement_id: int, subject: StringName, agents: Array)

## A shrine is built once this many believe (and the settlement has this many people).
const SHRINE_BELIEVERS := 4
## Both sides of a schism hold at least this share of the settlement.
const SCHISM_SHARE := 0.25
## A load carried may bring a myth along (the chance).
const SPREAD_PER_LOAD := 0.04

var culture: CulturalMemory
var settlements: Settlements
var people: PersonRegistry
var world: WorldData
var significance: Significance
## Myth id -> the person who spoke for it first (0: nobody).
var founders: Dictionary = {}
## "settlement:subject" -> the tick a schism was told of (told once).
var schisms: Dictionary = {}
var _day := -1_000_000


func bind(memory: CulturalMemory, all: Settlements, registry: PersonRegistry, land: WorldData, now: int) -> void:
	culture = memory
	settlements = all
	people = registry
	world = land
	_day = Config.time.day_index(now)


## A myth has formed (CulturalMemory.myth_formed): its places are sacred, and
## someone speaks for it.
func on_myth(myth: Dictionary) -> void:
	hallow(myth)
	var founder := founder_for(myth)
	founders[int(myth["id"])] = founder.id if founder != null else 0
	if founder != null:
		founded.emit(myth, founder.id)


## Its places are sacred.
func hallow(myth: Dictionary) -> void:
	if world == null:
		return
	for place: Variant in myth.get("places", []):
		if typeof(place) == TYPE_VECTOR2:
			var tile := WorldCoords.world2d_to_tile(place)
			if world.is_in_bounds(tile):
				world.set_flag(tile, ChunkData.FLAG_SACRED, true)


## Who speaks for a myth: of its settlement's people, the one who most takes
## the like of it for its agent's doing — and matters most (significance).
func founder_for(myth: Dictionary) -> PersonData:
	var own := settlements.get_settlement(int(myth["settlement"])) if settlements != null else null
	if own == null:
		return null
	var index := ReactionTable.INTERPRETATIONS.find(StringName(str(myth["agent"])))
	var best: PersonData = null
	var best_score := 0.0
	for person in own.members():
		if index < 0:
			break
		var held := Interpretation.beliefs_of(person)[index]
		var weight := held * (1.0 + (significance.points_of(person.id) if significance != null else 0.0))
		if weight > best_score or (weight == best_score and best != null and person.id < best.id):
			best = person
			best_score = weight
	return best if best_score > 0.0 else null


## Once a game day: schisms.
func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	look_for_schisms(now)


func look_for_schisms(now: int) -> void:
	if culture == null or settlements == null:
		return
	for own in settlements.all():
		var people_there := maxi(own.member_count(), 1)
		var by_subject := {} # subject -> [myth …] with many believers
		for myth in culture.myths():
			if int(myth["settlement"]) != own.id or float(int(myth["believers"])) / people_there < SCHISM_SHARE:
				continue
			var list: Array = by_subject.get(str(myth["subject"]), [])
			list.append(myth)
			by_subject[str(myth["subject"])] = list
		for subject: String in by_subject:
			var list: Array = by_subject[subject]
			var key := "%d:%s" % [own.id, subject]
			if list.size() < 2 or schisms.has(key):
				continue
			schisms[key] = now
			var agents: Array = []
			for myth: Dictionary in list:
				agents.append(str(myth["agent"]))
			agents.sort()
			schism.emit(own.id, StringName(subject), agents)


## The myths of a settlement.
func myths_of(settlement_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if culture != null:
		for myth in culture.myths():
			if int(myth["settlement"]) == settlement_id:
				out.append(myth)
	return out


## The myth of a settlement that most believe (with enough of them for a shrine; {}: none).
func shrine_myth(own: Settlement) -> Dictionary:
	var best := {}
	for myth in myths_of(own.id):
		if int(myth["believers"]) >= SHRINE_BELIEVERS and (best.is_empty() or int(myth["believers"]) > int(best["believers"])):
			best = myth
	return best


## A settlement founded from another takes its myths along (believed anew there).
func on_founded(own: Settlement, journey: Dictionary) -> void:
	for myth in myths_of(int(journey.get("from", 0))):
		_carry(myth, own.id, false)


## A load carried may bring a myth along (TradeSystem.traded).
func on_traded(record: Dictionary) -> void:
	var from := int(record.get("from", 0))
	var to := int(record.get("to", 0))
	for myth in myths_of(from):
		var draw := float(posmod(hash([from, to, int(myth["id"]), int(record.get("units", 0)), _day, "myth"]), 100000)) / 100000.0
		if draw < SPREAD_PER_LOAD:
			_carry(myth, to, true)


func _carry(myth: Dictionary, settlement_id: int, told: bool) -> void:
	if culture == null or not culture.myth_of(settlement_id, StringName(str(myth["subject"])), StringName(str(myth["agent"]))).is_empty():
		return
	var copy := culture.adopt(myth, settlement_id)
	if told:
		spread.emit(copy, int(myth["settlement"]))


func to_dict() -> Dictionary:
	var kept := {}
	for id: int in founders:
		kept[str(id)] = founders[id]
	return {"founders": kept, "schisms": schisms.duplicate(), "day": _day}


func from_dict(data: Dictionary) -> void:
	founders.clear()
	schisms.clear()
	if typeof(data.get("founders")) == TYPE_DICTIONARY:
		for key: Variant in data["founders"]:
			if str(key).is_valid_int():
				founders[int(str(key))] = int(data["founders"][key])
	if typeof(data.get("schisms")) == TYPE_DICTIONARY:
		for key: Variant in data["schisms"]:
			schisms[str(key)] = int(data["schisms"][key])
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var shrines := 0
	if settlements != null:
		for own in settlements.all():
			if own.planner != null:
				shrines += own.planner.standing_near(PropData.Kind.SHRINE).size()
	return "faith: %d myths, %d founders, %d schisms, %d shrines" % [culture.myths().size() if culture != null else 0,
		founders.values().filter(func(id: int) -> bool: return id != 0).size(), schisms.size(), shrines]
