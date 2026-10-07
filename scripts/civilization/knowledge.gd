class_name Knowledge
extends RefCounted
## What people know (M16.1, bible §18.1): points in ten domains — the land,
## making things, growing food, building, healing, counting, the sky, keeping
## records, living together, and the strange things that happen (Anomaly).
##
## **Knowledge is held by people** (PersonData.knowledge["domains"]): it grows
## with their work, their curiosity, what goes wrong (a failed crop teaches
## farming), what they are taught and what they watch, and with the player's
## doing (what cannot be explained feeds Anomaly). A settlement knows what its
## most knowing member knows, and a little of what each of the others does —
## so **when the one who knew dies without having taught anyone, it is gone**
## (an event says so). Once a settlement can write (M16.2), its records keep
## half of what it knew.
##
## Once a game day, cheap: a pass over the living.

## Much of a domain went with someone who died: settlement, person, domain, share lost.
signal lost(settlement_id: int, person_id: int, domain: int, share: float)

enum Domain { NATURE, CRAFT, AGRICULTURE, CONSTRUCTION, MEDICINE, MATHEMATICS, ASTRONOMY, RECORD, SOCIAL, ANOMALY }
const NAMES: Array[StringName] = [&"nature", &"craft", &"agriculture", &"construction", &"medicine", &"mathematics",
	&"astronomy", &"record", &"social", &"anomaly"]
const COUNT := 10
## Where a person's points are kept.
const KEY := "domains"
## The most anyone knows of a domain (points come slower as it is neared).
const MOST := 100.0
## A settlement knows what its most knowing member knows, and this share of
## what each of the others does.
const OTHERS_SHARE := 0.2

## What a day's work teaches (points at middling skill): occupation -> {domain: points}.
const WORK := {
	&"woodcutter": {Domain.NATURE: 0.35, Domain.CRAFT: 0.25},
	&"forager": {Domain.NATURE: 0.5, Domain.MEDICINE: 0.12},
	&"farmer": {Domain.AGRICULTURE: 0.6, Domain.NATURE: 0.15},
	&"hunter": {Domain.NATURE: 0.45, Domain.CRAFT: 0.1},
	&"builder": {Domain.CONSTRUCTION: 0.6, Domain.CRAFT: 0.2, Domain.MATHEMATICS: 0.05},
	&"toolmaker": {Domain.CRAFT: 0.7},
	&"trader": {Domain.SOCIAL: 0.35, Domain.MATHEMATICS: 0.25, Domain.RECORD: 0.1},
	&"elder": {Domain.SOCIAL: 0.3, Domain.RECORD: 0.25},
}
## The curious look about them: the land, and the sky at night (and elders
## have watched it longest). Points a day at the most curious.
const CURIOUS_NATURE := 0.15
const CURIOUS_SKY := 0.12
const ELDER_SKY := 0.06
## Everyone grown learns a little of living together, every day — and hears
## the old stories told again (keeping records, before there is writing).
const LIVING_TOGETHER := 0.05
const STORIES := 0.03
## A child takes this share a day of what the most knowing of its household
## knows more than it does (by watching).
const WATCHING := 0.015
## A lesson (the TEACH act): the learner takes this share of what the teacher
## knows more than they do, in the teacher's best domain.
const TEACH_SHARE := 0.04
## Someone of a settlement is ill: the grown of their household learn healing.
const NURSING := 0.3
## The player's doing, remembered: Anomaly points for its importance (× this).
const ANOMALY_PER_MEMORY := 2.0
## Something the player moved, come upon: making things (a first flint).
const FOUND_CRAFT := 0.8
## What goes wrong teaches: event type -> [domain, points, to whom ("all", "farmers", "household")].
const LESSONS := {
	&"crop_failure": [Domain.AGRICULTURE, 2.0, "farmers"],
	&"crop_frozen": [Domain.AGRICULTURE, 1.0, "farmers"],
	&"poor_harvest": [Domain.AGRICULTURE, 1.0, "farmers"],
	&"food_shortage": [Domain.NATURE, 0.6, "all"],
	&"flood": [Domain.CONSTRUCTION, 0.8, "all"],
	&"building_damaged": [Domain.CONSTRUCTION, 0.5, "builders"],
	&"food_spoiled": [Domain.CRAFT, 0.4, "all"],
}
## A death that takes at least this share of what a settlement knew of a
## domain, of which it knew at least this much, is told.
const LOSS_WORTH := 0.3
const LOSS_LEAST := 12.0
## What a settlement that writes keeps in its records of what it knows.
const RECORD_KEPT := 0.5

var people: PersonRegistry
var settlements: Settlements
## Does a settlement write (M16.2)? Callable(settlement) -> bool; unset: none does.
var writes := Callable()
## A settlement's records: settlement id -> PackedFloat32Array (what writing has kept).
var records: Dictionary = {}
var _day := -1_000_000
## For the debug overlay and the soak.
var losses := 0


func bind(registry: PersonRegistry, all: Settlements, now: int) -> void:
	people = registry
	settlements = all
	_day = Config.time.day_index(now)


# --- what someone knows -------------------------------------------------------------------------

## A person's points, one per domain (a copy).
static func of(person: PersonData) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)
	var held: Variant = person.knowledge.get(KEY) if person != null else null
	if typeof(held) == TYPE_PACKED_FLOAT32_ARRAY:
		for i in mini((held as PackedFloat32Array).size(), COUNT):
			var value: float = held[i]
			out[i] = clampf(value, 0.0, MOST) if is_finite(value) else 0.0
	return out


static func points(person: PersonData, domain: int) -> float:
	return of(person)[domain]


## Teaches a person `amount` points of a domain (less as they near the most).
## Returns what they gained.
static func add(person: PersonData, domain: int, amount: float) -> float:
	if person == null or amount <= 0.0 or domain < 0 or domain >= COUNT:
		return 0.0
	var held := of(person)
	var gain := amount * (1.0 - held[domain] / MOST)
	held[domain] = minf(held[domain] + gain, MOST)
	person.knowledge[KEY] = held
	return gain


## What a group of people knows of a domain together: the most knowing, and
## a share of each of the others.
static func together(group: Array, domain: int) -> float:
	var best := 0.0
	var sum := 0.0
	for person: PersonData in group:
		var value := points(person, domain)
		best = maxf(best, value)
		sum += value
	return best + (sum - best) * OTHERS_SHARE


## What a settlement knows of a domain (its people's, or its records', the more).
func of_settlement(own: Settlement, domain: int) -> float:
	if own == null:
		return 0.0
	var known := together(own.members(), domain)
	var kept: Variant = records.get(own.id)
	if typeof(kept) == TYPE_PACKED_FLOAT32_ARRAY and domain < (kept as PackedFloat32Array).size():
		known = maxf(known, kept[domain])
	return known


## The one of a settlement who knows a domain best (null: nobody knows anything of it).
static func best_of(own: Settlement, domain: int) -> PersonData:
	var best: PersonData = null
	var most := 0.0
	for person in own.members():
		var value := points(person, domain)
		if value > most or (value == most and best != null and person.id < best.id):
			if value > 0.0:
				best = person
				most = value
	return best


# --- learning -----------------------------------------------------------------------------------

## Once a game day: the day's work, curiosity and watching are learned from.
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
	var year := Config.time.ticks_per_year()
	for own in settlements.all():
		var members := own.members()
		var grown: Array[PersonData] = []
		for person in members:
			var stage := person.life_stage(now, year, Config.people)
			if stage == PersonData.LifeStage.CHILD:
				continue
			grown.append(person)
			_learn_from_the_day(person, stage)
		# Children watch the most knowing of their household.
		for person in members:
			if person.life_stage(now, year, Config.people) == PersonData.LifeStage.CHILD:
				_watch(person, members)
		# The ill are nursed: those who nurse them learn healing.
		for person in members:
			if Hardship.is_sick(person) or Exposure.is_sick(person) or person.health < 0.5:
				for other in grown:
					if other != person and other.household_id == person.household_id and person.household_id != 0:
						add(other, Domain.MEDICINE, NURSING)
		# What is written down is kept.
		if writes.is_valid() and bool(writes.call(own)):
			var kept: PackedFloat32Array = records.get(own.id, PackedFloat32Array())
			kept.resize(COUNT)
			for domain in COUNT:
				kept[domain] = maxf(kept[domain], together(members, domain) * RECORD_KEPT)
			records[own.id] = kept


func _learn_from_the_day(person: PersonData, stage: PersonData.LifeStage) -> void:
	var mind := lerpf(0.7, 1.3, Traits.value(person.traits, Traits.Axis.INTELLIGENCE))
	var work: Dictionary = WORK.get(person.occupation_id, {})
	var skill := float(person.skills.get(String(person.occupation_id), 0.3))
	for domain: int in work:
		add(person, domain, float(work[domain]) * lerpf(0.5, 1.5, skill) * mind)
	var curious := maxf(Traits.value(person.traits, Traits.Axis.CURIOSITY), 0.0)
	add(person, Domain.NATURE, CURIOUS_NATURE * curious * mind)
	add(person, Domain.ASTRONOMY, (CURIOUS_SKY * curious + (ELDER_SKY if stage == PersonData.LifeStage.ELDER else 0.0)) * mind)
	add(person, Domain.SOCIAL, LIVING_TOGETHER * mind)
	add(person, Domain.RECORD, STORIES * mind)
	if stage == PersonData.LifeStage.ELDER and not WORK.has(person.occupation_id):
		for domain: int in WORK[&"elder"]:
			add(person, domain, float(WORK[&"elder"][domain]) * mind)


func _watch(child: PersonData, members: Array[PersonData]) -> void:
	var best := PackedFloat32Array()
	best.resize(COUNT)
	for other in members:
		if other == child or other.household_id != child.household_id or child.household_id == 0:
			continue
		var theirs := of(other)
		for domain in COUNT:
			best[domain] = maxf(best[domain], theirs[domain])
	var mine := of(child)
	for domain in COUNT:
		if best[domain] > mine[domain]:
			mine[domain] += (best[domain] - mine[domain]) * WATCHING
	child.knowledge[KEY] = mine


## A lesson (SocialActs.TEACH): `learner` takes some of what `teacher` knows
## best. Returns the domain taught (-1: nothing to teach).
static func teach(teacher: PersonData, learner: PersonData) -> int:
	var theirs := of(teacher)
	var mine := of(learner)
	var domain := -1
	var gap := 0.0
	for i in COUNT:
		if theirs[i] - mine[i] > gap:
			gap = theirs[i] - mine[i]
			domain = i
	if domain >= 0:
		mine[domain] += gap * TEACH_SHARE
		learner.knowledge[KEY] = mine
	return domain


## Something happened: what goes wrong teaches (LESSONS).
func on_event(event: WorldEvent) -> void:
	if event != null:
		learn_from(event.type, event.settlement_id)


## The lesson of something of `type` that went wrong in a settlement (0: the
## home one) — for what is not written into history (food gone bad).
func learn_from(type: StringName, settlement_id: int) -> void:
	if settlements == null or not LESSONS.has(type):
		return
	var lesson: Array = LESSONS[type]
	var own := settlements.get_settlement(settlement_id) if settlement_id != 0 else settlements.home()
	if own == null:
		return
	for person in own.members():
		var to: String = lesson[2]
		if (to == "farmers" and person.occupation_id != &"farmer") or (to == "builders" and person.occupation_id != &"builder"):
			continue
		add(person, int(lesson[0]), float(lesson[1]))


## Someone remembers something: the player's doing teaches the unexplained;
## something of the player's come upon may be the first flint.
func on_remembered(memory: Memory) -> void:
	if memory == null or people == null or memory.owner_kind != Memory.OwnerKind.PERSON:
		return
	var owner := people.get_person(memory.owner_id)
	if owner == null:
		return
	if memory.intervention_id != 0 and memory.source != Memory.Source.TOLD:
		add(owner, Domain.ANOMALY, memory.importance * ANOMALY_PER_MEMORY)
	if memory.subject == Stimulus.OBJECT_FOUND:
		add(owner, Domain.CRAFT, FOUND_CRAFT)


## Someone is dying (still counted among the living): what only they knew goes
## with them — told, if it was much. (Lifecycle.died, before they are removed.)
func on_dying(person_id: int) -> void:
	if people == null or settlements == null:
		return
	var person := people.get_person(person_id)
	var own := settlements.of(person) if person != null else null
	if own == null:
		return
	var with := own.members()
	var without: Array[PersonData] = []
	for other in with:
		if other.id != person_id:
			without.append(other)
	var worst := -1
	var worst_share := 0.0
	for domain in COUNT:
		var before := of_settlement(own, domain)
		if before < LOSS_LEAST:
			continue
		var after := together(without, domain)
		var kept: Variant = records.get(own.id)
		if typeof(kept) == TYPE_PACKED_FLOAT32_ARRAY:
			after = maxf(after, kept[domain])
		var share := (before - after) / before
		if share >= LOSS_WORTH and share > worst_share:
			worst = domain
			worst_share = share
	if worst >= 0:
		losses += 1
		lost.emit(own.id, person_id, worst, worst_share)


## A settlement is gone: its records with it.
func forget_settlement(settlement_id: int) -> void:
	records.erase(settlement_id)


func to_dict() -> Dictionary:
	var kept := {}
	for id: int in records:
		kept[str(id)] = records[id]
	return {"records": kept, "day": _day}


func from_dict(data: Dictionary) -> void:
	records.clear()
	var kept: Variant = data.get("records")
	if typeof(kept) == TYPE_DICTIONARY:
		for key: Variant in kept:
			var values: Variant = kept[key]
			if str(key).is_valid_int() and typeof(values) == TYPE_PACKED_FLOAT32_ARRAY:
				var clean := PackedFloat32Array()
				clean.resize(COUNT)
				for i in mini((values as PackedFloat32Array).size(), COUNT):
					clean[i] = clampf(values[i], 0.0, MOST) if is_finite(values[i]) else 0.0
				records[int(str(key))] = clean
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var best := PackedStringArray()
	var home := settlements.home() if settlements != null else null
	if home != null:
		for domain in COUNT:
			var value := of_settlement(home, domain)
			if value >= 1.0:
				best.append("%s %d" % [NAMES[domain], roundi(value)])
	return "knowledge: %s  losses %d" % [" ".join(best) if not best.is_empty() else "-", losses]
