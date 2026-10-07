class_name Governance
extends RefCounted
## Governance v0 (bible §17.4, M12.5): each settlement of a few people comes
## to be led by the one its people look to most — for the respect and liking
## of their neighbours, their years, having founded it, what they have done,
## and their nature. Once a game day this is weighed again; a leader is
## replaced only by someone clearly more looked to, and otherwise leads until
## they die or leave. Every change of leader is history.
##
## What a leader brings: their people's interpretations lean toward the
## leader's beliefs (a settlement's character follows its leader), and their
## nature tilts the settlement's plans — the ambitious build sooner, the
## cautious keep more food back from trade, the generous less.

## Someone leads a settlement now: `why` &"first", &"died", &"left" or &"replaced"
## (`was`: who led it before, 0: nobody).
signal led(settlement_id: int, leader_id: int, was: int, why: StringName)

var settlements: Settlements
var people: PersonRegistry
var relationships: RelationshipStore
var significance: Significance
var config: GovernanceConfig

var _leaders: Dictionary = {} # settlement id -> person id
var _beliefs: Dictionary = {} # settlement id -> the leader's beliefs (PackedFloat32Array)
var _day := -1_000_000
var _now := 0
## For the soak: changes of leader, by why.
var changes: Dictionary = {}
## Who was overthrown, and may not lead again before: settlement id -> [person id, tick] (M19.1).
var deposed: Dictionary = {}
## How long the overthrown may not lead again (game years).
const DEPOSED_YEARS := 10


func bind(now: int, cfg: GovernanceConfig = null) -> void:
	config = cfg if cfg != null else Config.governance
	_leaders.clear()
	_beliefs.clear()
	_day = Config.time.day_index(now)
	changes.clear()


func leader_of(settlement_id: int) -> int:
	return int(_leaders.get(settlement_id, 0))


## The settlement this person leads (0: none).
func leads(person_id: int) -> int:
	for id: int in _leaders:
		if int(_leaders[id]) == person_id:
			return id
	return 0


## A trait of a settlement's leader as it counts (−1 … +1; 0 without a leader).
func lean(settlement_id: int, axis: int) -> float:
	var leader := people.get_person(leader_of(settlement_id)) if people != null else null
	return ReactionTable.lean(leader.traits, axis) if leader != null else 0.0


## How much the leader of `settlement_id` holds interpretation `index` (0 … 1; 0 without a leader).
func belief(settlement_id: int, index: int) -> float:
	var held: Variant = _beliefs.get(settlement_id)
	return float(held[index]) if held != null and index < (held as PackedFloat32Array).size() else 0.0


## Once a game day: who leads each settlement now.
func advance_to(now: int) -> void:
	if settlements == null or people == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	weigh_all(now)


## Weighs every settlement's leadership now.
func weigh_all(now: int) -> void:
	_now = now
	for own in settlements.all():
		weigh(own)
	for id: int in _leaders.keys():
		if settlements.get_settlement(id) == null:
			_leaders.erase(id)
			_beliefs.erase(id)


## Its people have risen against their leader (M19.1): someone else leads,
## and the one overthrown may not again for years.
func depose(settlement_id: int, now: int) -> void:
	var was := leader_of(settlement_id)
	var own := settlements.get_settlement(settlement_id) if settlements != null else null
	if was == 0 or own == null:
		return
	deposed[settlement_id] = [was, now + DEPOSED_YEARS * Config.time.ticks_per_year()]
	weigh(own, now)


## Weighs who leads `own` now (and records any change).
func weigh(own: Settlement, now: int = -1) -> void:
	if now >= 0:
		_now = now
	var members := own.members()
	var was := leader_of(own.id)
	var current := people.get_person(was) if was != 0 else null
	if members.size() < config.least_people:
		if was != 0:
			_leaders.erase(own.id)
			_beliefs.erase(own.id)
		return
	var best: PersonData = null
	var best_score := -INF
	var scores := {}
	var member_set := _set_of(members)
	for person in members:
		if not _can_lead(person):
			continue
		var score := standing(person, own, members, member_set)
		scores[person.id] = score
		if score > best_score or (score == best_score and best != null and person.id < best.id):
			best_score = score
			best = person
	if best == null:
		return
	var why := &""
	if was == 0:
		why = &"first"
	elif current == null:
		why = &"died"
	elif deposed.has(own.id) and int(deposed[own.id][0]) == was and not scores.has(was):
		why = &"overthrown"
	elif current.settlement_id != own.id or not scores.has(was):
		why = &"left"
	elif best.id != was and best_score > float(scores[was]) + config.challenge_margin:
		why = &"replaced"
	if why == &"":
		_beliefs[own.id] = Interpretation.beliefs_of(current)
		return
	_leaders[own.id] = best.id
	_beliefs[own.id] = Interpretation.beliefs_of(best)
	changes[String(why)] = int(changes.get(String(why), 0)) + 1
	led.emit(own.id, best.id, was, why)


static func _set_of(members: Array[PersonData]) -> Dictionary:
	var out := {}
	for person in members:
		out[person.id] = true
	return out


## How much `person` is looked to in `own` (see GovernanceConfig).
func standing(person: PersonData, own: Settlement, members: Array[PersonData] = [], member_set: Dictionary = {}) -> float:
	if members.is_empty():
		members = own.members()
	if member_set.is_empty():
		member_set = _set_of(members)
	var respect := 0.0
	var liking := 0.0
	var others := members.size() - (1 if member_set.has(person.id) else 0)
	# (What they are to each of the others: only those they know have a record
	# — at most a few dozen — the rest count for nothing. Asking every pair
	# was minutes a day at a few hundred people: M21.)
	if relationships != null:
		var known := relationships.of(person.id)
		for other_id: int in known:
			if other_id != person.id and member_set.has(other_id):
				var record: Relationship = known[other_id]
				respect += record.respect
				liking += record.affinity
	if others > 0:
		respect /= others
		liking /= others
	var years := float(person.age_years(_now, Config.time.ticks_per_year()))
	var prime := clampf(1.0 - absf(years - config.prime_years) / float(config.prime_span), 0.0, 1.0)
	var founder := 1.0 if own.founders.has(person.id) else 0.0
	var deeds := minf(significance.points_of(person.id), config.deeds_most) if significance != null else 0.0
	return respect * config.respect_weight + liking * config.affinity_weight + prime * config.age_weight \
		+ founder * config.founder_weight + deeds * config.deeds_weight \
		+ ReactionTable.lean(person.traits, Traits.Axis.AMBITION) * config.ambition_weight \
		+ ReactionTable.lean(person.traits, Traits.Axis.SOCIABILITY) * config.sociability_weight


## Someone grown (not a child, not someone on their way to new land).
func _can_lead(person: PersonData) -> bool:
	for id: int in deposed:
		var entry: Array = deposed[id]
		if int(entry[0]) == person.id and _now < int(entry[1]):
			return false
	var stage := person.life_stage(_now, Config.time.ticks_per_year(), Config.people)
	return stage == PersonData.LifeStage.ADULT or stage == PersonData.LifeStage.ELDER


func debug_text() -> String:
	var parts := PackedStringArray()
	for own in (settlements.all() if settlements != null else []):
		parts.append("%s: %s" % [own.display_name(), people.name_of(leader_of(own.id)) if leader_of(own.id) != 0 else "nobody"])
	return "leaders: %s  (changes %s)" % [", ".join(parts), changes]


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var leaders := {}
	for id: int in _leaders:
		leaders[str(id)] = _leaders[id]
	var out := {}
	for id: int in deposed:
		out[str(id)] = (deposed[id] as Array).duplicate()
	return {"leaders": leaders, "day": _day, "now": _now, "changes": changes.duplicate(), "deposed": out}


func from_dict(data: Dictionary) -> void:
	_leaders.clear()
	_beliefs.clear()
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	if typeof(data.get("now")) == TYPE_INT:
		_now = data["now"]
	if typeof(data.get("leaders")) == TYPE_DICTIONARY:
		for key: Variant in data["leaders"]:
			var id := int(str(key))
			var leader := int(data["leaders"][key])
			_leaders[id] = leader
			var person := people.get_person(leader) if people != null else null
			if person != null:
				_beliefs[id] = Interpretation.beliefs_of(person)
	deposed.clear()
	if typeof(data.get("deposed")) == TYPE_DICTIONARY:
		for key: Variant in data["deposed"]:
			var entry: Variant = data["deposed"][key]
			if typeof(entry) == TYPE_ARRAY and (entry as Array).size() == 2:
				deposed[int(str(key))] = [int(entry[0]), int(entry[1])]
	changes.clear()
	if typeof(data.get("changes")) == TYPE_DICTIONARY:
		for key: Variant in data["changes"]:
			changes[str(key)] = int(data["changes"][key])
