class_name RelationshipStore
extends RefCounted
## Everyone's relationships (bible §16.1): a sparse store of pairs — only
## those who know each other at all have a record — and at most so many for
## anyone (the weakest are forgotten first; family never).
##
## Values change through `modify` (what happened between them, with the
## event it happened in); what the values make of the pair (acquaintances,
## friends, rivals, enemies) follows with some give, so that nobody is a
## friend one hour and not the next. Without anything happening, feelings
## cool slowly back to where they started, and people who never meet grow
## strange to each other (`settle`, once a game day).

## The pair is now (or no longer) of this kind; `kind` is one Relationship.Kind bit.
signal kind_changed(a: int, b: int, kind: int, gained: bool)

const DAY := TimeConfig.MINUTES_PER_DAY

var _config: RelationshipsConfig
var _pairs: Dictionary = {} # key (see _key) -> Relationship
var _by_person: Dictionary = {} # person id -> PackedInt64Array of their keys
var _people: PersonRegistry
var _day := -1_000_000
## How often each social act has come about since the world was opened (act -> count; debug, soaks).
var acts: Dictionary = {}


func bind(people: PersonRegistry, config: RelationshipsConfig = null) -> void:
	_people = people
	_config = config if config != null else Config.relationships
	clear()


func clear() -> void:
	_pairs.clear()
	_by_person.clear()
	_day = -1_000_000


# --- what is there ---------------------------------------------------------------------------------

## The record of two people (null: they do not know each other).
func between(a: int, b: int) -> Relationship:
	if a == b:
		return null
	return _pairs.get(_key(a, b))


## The record of two people, made if there is none (null for one person with themselves).
func ensure(a: int, b: int, now: int = 0) -> Relationship:
	if a == b or a <= 0 or b <= 0:
		return null
	var key := _key(a, b)
	var record: Relationship = _pairs.get(key)
	if record != null:
		return record
	record = Relationship.new()
	record.last_tick = now
	_pairs[key] = record
	_index(a, key)
	_index(b, key)
	_keep_within(a)
	_keep_within(b)
	return _pairs.get(key)


## How `a` feels about `b` (0 if they do not know each other).
func affinity(a: int, b: int) -> float:
	var record := between(a, b)
	return record.affinity if record != null else 0.0


func familiarity(a: int, b: int) -> float:
	var record := between(a, b)
	return record.familiarity if record != null else 0.0


## What `b` is to `a`: the kinds on their record, and the family ones from the
## people themselves (PARENT: `b` is `a`'s parent; CHILD: `b` is `a`'s child;
## PARTNER, SIBLING).
func kinds(a: int, b: int) -> int:
	var record := between(a, b)
	var out := record.kinds if record != null else 0
	return out | family(a, b)


## The family tie between two people, as kind bits (0: none).
func family(a: int, b: int) -> int:
	if _people == null or a == b:
		return 0
	var one := _people.get_person(a)
	var other := _people.get_person(b)
	if one == null or other == null:
		return 0
	var out := 0
	if one.parents.has(b):
		out |= Relationship.Kind.PARENT
	if one.children.has(b) or other.parents.has(a):
		out |= Relationship.Kind.CHILD
	if one.partner_id == b:
		out |= Relationship.Kind.PARTNER
	if not one.parents.is_empty():
		for parent in one.parents:
			if other.parents.has(parent):
				out |= Relationship.Kind.SIBLING
				break
	return out


func is_family(a: int, b: int) -> bool:
	return family(a, b) != 0


## Too close in blood to become partners: one is the other's parent or
## grandparent, or they share a parent or a grandparent (brothers and
## sisters, uncles, aunts, nieces, nephews, first cousins). The dead count
## too (through the archive).
func close_kin(a: int, b: int) -> bool:
	if a == b:
		return true
	var mine := _forebears(a)
	var theirs := _forebears(b)
	if mine.has(b) or theirs.has(a):
		return true
	for id: int in mine:
		if theirs.has(id):
			return true
	return false


## Parents and grandparents (ids), living or dead.
func _forebears(id: int) -> Dictionary:
	var out := {}
	var ring: PackedInt64Array = _parents_of(id)
	for parent in ring:
		out[parent] = true
		for grand in _parents_of(parent):
			out[grand] = true
	return out


func _parents_of(id: int) -> PackedInt64Array:
	var person := _people.get_person(id) if _people != null else null
	if person != null:
		return person.parents
	var record := _people.archive.get_record(id) if _people != null and _people.archive != null else null
	return record.parents if record != null else PackedInt64Array()


## Everyone `person` has a record with: id -> Relationship.
func of(person: int) -> Dictionary:
	var out := {}
	for key: int in _by_person.get(person, PackedInt64Array()):
		var record: Relationship = _pairs.get(key)
		if record != null:
			out[_other(key, person)] = record
	return out


## Those of a kind to `person` (a social kind: FRIEND, RIVAL, …), as ids.
func with_kind(person: int, kind: int) -> Array[int]:
	var out: Array[int] = []
	var known := of(person)
	for other: int in known:
		if (known[other] as Relationship).has_kind(kind):
			out.append(other)
	out.sort()
	return out


func count_for(person: int) -> int:
	return (_by_person.get(person, PackedInt64Array()) as PackedInt64Array).size()


## Every pair at once, for the statistics: [pairs, summed affinity, friends,
## feuds] — from the pairs themselves, not person by person (M21: building
## everyone's list of acquaintances every game hour was 30 ms at 1,000 people).
func summary() -> Array:
	var pairs := 0
	var affinity := 0.0
	var friends := 0
	var feuds := 0
	for key: int in _pairs:
		var record: Relationship = _pairs[key]
		pairs += 1
		affinity += record.affinity
		if record.has_kind(Relationship.Kind.FRIEND):
			friends += 1
		if record.has_kind(Relationship.Kind.RIVAL) or record.has_kind(Relationship.Kind.ENEMY):
			feuds += 1
	return [pairs, affinity, friends, feuds]


func size() -> int:
	return _pairs.size()


func debug_text() -> String:
	var friends := 0
	var rivals := 0
	for record: Relationship in _pairs.values():
		if record.has_kind(Relationship.Kind.FRIEND):
			friends += 1
		if record.has_kind(Relationship.Kind.RIVAL):
			rivals += 1
	return "relationships: %d pairs, %d of them friends, %d rivals  (acts %s)" % [_pairs.size(), friends, rivals, acts]


# --- what happens between them ---------------------------------------------------------------------

## Something happened between `a` and `b`: their values move by `deltas`
## (any of "familiarity", "affinity", "trust", "respect", "romance"), and
## `event_id` (if any) is remembered as one of the moments they shared.
## Returns the record (null if there can be none).
func modify(a: int, b: int, deltas: Dictionary, event_id: int = 0, now: int = 0) -> Relationship:
	var record := ensure(a, b, now)
	if record == null:
		return null
	record.familiarity = clampf(record.familiarity + float(deltas.get("familiarity", 0.0)), 0.0, 1.0)
	# (The closer to the end of the scale, the less one more good — or bad — thing moves it.)
	var warmth := float(deltas.get("affinity", 0.0))
	warmth *= (1.0 - record.affinity) if warmth > 0.0 else (1.0 + record.affinity)
	record.affinity = clampf(record.affinity + warmth, -1.0, 1.0)
	record.trust = clampf(record.trust + float(deltas.get("trust", 0.0)), -1.0, 1.0)
	record.respect = clampf(record.respect + float(deltas.get("respect", 0.0)), -1.0, 1.0)
	record.romance = clampf(record.romance + float(deltas.get("romance", 0.0)), 0.0, 1.0)
	record.last_tick = maxi(record.last_tick, now)
	record.note_event(event_id)
	_judge(a, b, record)
	return record


## Once a game day: feelings cool towards where they began (for family a
## little warmth stays), and those who have not met for a while know each
## other less. Pairs with nothing left are forgotten.
func settle(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	var days := mini(today - _day, 30)
	_day = today
	var cool := 1.0 - pow(1.0 - _config.affinity_fade_per_day, days)
	var cool_romance := 1.0 - pow(1.0 - _config.romance_fade_per_day, days)
	for key: int in _pairs.keys():
		var record: Relationship = _pairs[key]
		var a := key >> 32
		var b := key & 0xFFFFFFFF
		var kin := is_family(a, b)
		var rest := _config.family_affinity if kin else 0.0
		record.affinity += (rest - record.affinity) * cool
		record.trust *= 1.0 - cool
		record.romance *= 1.0 - cool_romance
		if now - record.last_tick > _config.strange_after_days * DAY and not kin:
			record.familiarity = maxf(record.familiarity - _config.familiarity_fade_per_day * days, 0.0)
		_judge(a, b, record)
		if record.familiarity <= 0.0 and absf(record.affinity) < 0.02 and not kin:
			_forget(key)


## Drops everything about people who are not in `people` any more (a save
## from before, or someone gone). Returns how many pairs went.
func drop_missing(people: PersonRegistry) -> int:
	var dropped := 0
	for key: int in _pairs.keys():
		if people.get_person(key >> 32) == null or people.get_person(key & 0xFFFFFFFF) == null:
			_forget(key)
			dropped += 1
	return dropped


## Someone has died: what others were to them goes with them (how they are
## remembered is the archive's, and memory's).
func forget_person(person: int) -> void:
	for key: int in (_by_person.get(person, PackedInt64Array()) as PackedInt64Array).duplicate():
		_forget(key)


## A new world (or one from before relationships were kept): family knows
## each other well and likes each other; everyone in the band knows everyone
## a little. (Not over what is already there.)
func seed_from(people: PersonRegistry, now: int) -> void:
	var everyone := people.all_people()
	for i in everyone.size():
		for j in range(i + 1, everyone.size()):
			var a := everyone[i]
			var b := everyone[j]
			if a.settlement_id != b.settlement_id or between(a.id, b.id) != null:
				continue
			var kin := is_family(a.id, b.id) or (a.household_id != 0 and a.household_id == b.household_id)
			modify(a.id, b.id, {
				"familiarity": _config.family_familiarity if kin else _config.band_familiarity,
				"affinity": _config.family_affinity if kin else 0.0,
				"trust": _config.family_affinity if kin else 0.0}, 0, now)


# --- saving -----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var pairs: Array = []
	var keys: Array = _pairs.keys()
	keys.sort()
	for key: int in keys:
		var record: Dictionary = (_pairs[key] as Relationship).to_dict()
		record["a"] = key >> 32
		record["b"] = key & 0xFFFFFFFF
		pairs.append(record)
	return {"pairs": pairs, "day": _day}


## Restores saved pairs, leaving out what cannot be used (a broken record, a
## pair with itself, someone who is not there). Returns how many were left out.
func from_dict(data: Dictionary) -> int:
	clear()
	_day = int(data["day"]) if typeof(data.get("day")) == TYPE_INT else -1_000_000
	var saved: Variant = data.get("pairs")
	if typeof(saved) != TYPE_ARRAY:
		return 0
	var skipped := 0
	for entry: Variant in saved:
		if typeof(entry) != TYPE_DICTIONARY or typeof((entry as Dictionary).get("a")) != TYPE_INT \
				or typeof((entry as Dictionary).get("b")) != TYPE_INT:
			skipped += 1
			continue
		var a: int = entry["a"]
		var b: int = entry["b"]
		var record := Relationship.from_dict(entry)
		if record == null or a == b or a <= 0 or b <= 0 or _pairs.has(_key(a, b)) \
				or (_people != null and (_people.get_person(a) == null or _people.get_person(b) == null)):
			skipped += 1
			continue
		var key := _key(a, b)
		_pairs[key] = record
		_index(a, key)
		_index(b, key)
	for person: int in _by_person.keys():
		_keep_within(person)
	return skipped


# --- internals --------------------------------------------------------------------------------------

## What the values make of the pair, with some give either way.
func _judge(a: int, b: int, record: Relationship) -> void:
	var config := _config
	_set_kind(a, b, record, Relationship.Kind.ACQUAINTANCE,
		record.familiarity >= config.acquaintance_from if not record.has_kind(Relationship.Kind.ACQUAINTANCE) else record.familiarity > config.acquaintance_from * 0.5)
	_set_kind(a, b, record, Relationship.Kind.FRIEND,
		record.affinity >= config.friend_from and record.familiarity >= config.friend_familiarity
		if not record.has_kind(Relationship.Kind.FRIEND) else record.affinity > config.friend_until)
	_set_kind(a, b, record, Relationship.Kind.RIVAL,
		record.affinity <= config.rival_from if not record.has_kind(Relationship.Kind.RIVAL) else record.affinity < config.rival_until)
	_set_kind(a, b, record, Relationship.Kind.ENEMY,
		record.affinity <= config.enemy_from if not record.has_kind(Relationship.Kind.ENEMY) else record.affinity < config.enemy_until)


func _set_kind(a: int, b: int, record: Relationship, kind: int, now_is: bool) -> void:
	if now_is == record.has_kind(kind):
		return
	if now_is:
		record.kinds |= kind
	else:
		record.kinds &= ~kind
	kind_changed.emit(mini(a, b), maxi(a, b), kind, now_is)


## Someone knows too many: the weakest are forgotten (never family, never a partner).
func _keep_within(person: int) -> void:
	var keys: PackedInt64Array = _by_person.get(person, PackedInt64Array())
	var most := _config.most_per_person if _config != null else 30
	while keys.size() > most:
		var weakest := -1
		var weakest_weight := INF
		for key in keys:
			var other := _other(key, person)
			if is_family(person, other):
				continue
			var weight := (_pairs[key] as Relationship).weight()
			if weight < weakest_weight:
				weakest_weight = weight
				weakest = key
		if weakest < 0:
			return
		_forget(weakest)
		keys = _by_person.get(person, PackedInt64Array())


func _forget(key: int) -> void:
	if not _pairs.erase(key):
		return
	for person: int in [key >> 32, key & 0xFFFFFFFF]:
		var keys: PackedInt64Array = _by_person.get(person, PackedInt64Array())
		var at := keys.find(key)
		if at >= 0:
			keys.remove_at(at)
		if keys.is_empty():
			_by_person.erase(person)
		else:
			_by_person[person] = keys


func _index(person: int, key: int) -> void:
	var keys: PackedInt64Array = _by_person.get(person, PackedInt64Array())
	if not keys.has(key):
		keys.append(key)
	_by_person[person] = keys


static func _key(a: int, b: int) -> int:
	return (mini(a, b) << 32) | maxi(a, b)


static func _other(key: int, person: int) -> int:
	var a := key >> 32
	return key & 0xFFFFFFFF if a == person else a
