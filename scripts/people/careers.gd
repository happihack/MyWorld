class_name Careers
extends RefCounted
## Careers (buildings & villagers F3): how good someone is at their trade,
## apprentices, and elders who keep their trade.
##
## Levels are bands over the skill there already is (0 … 1): no second skill
## system. A master has fewer accidents and teaches more. An adolescent is
## taken on by someone of a trade the settlement can use — their parent's,
## if it is one — follows them at their work, and grows into it: grown, the
## trade is theirs. A mentor who dies or leaves the trade is replaced by
## another of it, or the training waits.

enum Level { NOVICE, TRAINED, SKILLED, EXPERT, MASTER }
## Where each level begins (TRAINED, SKILLED, EXPERT, MASTER).
const FROM: Array[float] = [0.2, 0.45, 0.7, 0.9]
const NAMES: Array[StringName] = [&"novice", &"trained", &"skilled", &"expert", &"master"]
## How much less often an expert and a master come to harm at their work.
const ACCIDENTS := {Level.EXPERT: 0.75, Level.MASTER: 0.5}
## How much more a lesson from an expert and a master teaches.
const TEACHES := {Level.EXPERT: 1.5, Level.MASTER: 2.0}
## Skill an apprentice gains in a day with their mentor (an adolescence of
## four years: about 0.4 — trained, nearly, when they come of age).
const APPRENTICE_PER_DAY := 0.004
## The least a mentor must be (skill in the trade).
const MENTOR_FROM := 0.2


static func level(skill: float) -> Level:
	var at := Level.NOVICE
	for i in FROM.size():
		if skill >= FROM[i]:
			at = (i + 1) as Level
	return at


## How good `person` is at their own trade.
static func level_of(person: PersonData) -> Level:
	return level(skill_of(person, person.occupation_id))


static func skill_of(person: PersonData, trade: StringName) -> float:
	return float(person.skills.get(String(trade), 0.0))


static func accident_factor(person: PersonData) -> float:
	return float(ACCIDENTS.get(level_of(person), 1.0))


static func teach_factor(person: PersonData) -> float:
	return float(TEACHES.get(level_of(person), 1.0))


## Trades an apprentice of `own` may be taken into: one gathered at (a work
## target, not staffed) — or a staffed one the settlement is short of.
static func open_trades(own: Settlement, occupations: OccupationLibrary, now: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if own == null or occupations == null:
		return out
	for id in occupations.ids():
		var def := occupations.get_def(id)
		if def.placeholder or def.work_target == &"" or not def.allows(PersonData.LifeStage.ADULT):
			continue
		# (Woodcutting is gathered at too: staffed only so that there is always some.)
		if def.staffing_order == 0 or def.demand == &"wood":
			out.append(id)
			continue
		var demand := own.demand_of(def, now)
		if not demand.is_empty() and int(demand["have"]) < int(demand["wanted"]):
			out.append(id)
	return out


## The one of `own` best to teach `trade`: the most skilled at it (at least
## MENTOR_FROM), grown, not `besides` (null: nobody).
static func mentor_for(own: Settlement, trade: StringName, now: int, besides: int = 0) -> PersonData:
	var best: PersonData = null
	for person in own.members():
		if person.id == besides or person.occupation_id != trade or skill_of(person, trade) < MENTOR_FROM:
			continue
		var stage := person.life_stage(now, Config.time.ticks_per_year(), Config.people)
		if stage != PersonData.LifeStage.ADULT and stage != PersonData.LifeStage.ELDER:
			continue
		if best == null or skill_of(person, trade) > skill_of(best, trade) \
				or (skill_of(person, trade) == skill_of(best, trade) and person.id < best.id):
			best = person
	return best


## Takes `person` on as an apprentice: their parent's trade if it is open,
## else the open trade that suits them best (that has someone to teach it).
## Returns the mentor (null: nobody to learn from).
static func take_on(person: PersonData, own: Settlement, occupations: OccupationLibrary, people: PersonRegistry,
		now: int) -> PersonData:
	var open := open_trades(own, occupations, now)
	if open.is_empty():
		return null
	var choices: Array[StringName] = []
	for parent_id in person.parents:
		var parent := people.get_person(parent_id) if people != null else null
		if parent != null and open.has(parent.occupation_id) and not choices.has(parent.occupation_id):
			choices.append(parent.occupation_id)
	var rest := open.duplicate()
	rest.sort_custom(func(a: StringName, b: StringName) -> bool:
		var fa := occupations.get_def(a).affinity(person.traits)
		var fb := occupations.get_def(b).affinity(person.traits)
		return fa > fb or (fa == fb and String(a) < String(b)))
	for trade in rest:
		if not choices.has(trade):
			choices.append(trade)
	for trade in choices:
		var mentor := mentor_for(own, trade, now, person.id)
		if mentor != null:
			person.mentor_id = mentor.id
			person.apprentice_trade = trade
			return mentor
	return null
