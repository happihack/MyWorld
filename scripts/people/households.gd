class_name Households
extends RefCounted
## The households of a world (bible §16.2, M10.2): who lives together under
## which roof. A household is its members (everyone whose household_id it
## is) and its home (kept here, and on each member as home_building_id). A
## couple founds a household of its own; children left without a grown-up,
## and an elder left alone, are taken in by family.
##
## Record: {"home": hut id, "founded": tick}. (One settlement store feeds
## everyone for now: a household keeps no stock of its own.)

var _records: Dictionary = {} # household id -> {"home": int, "founded": int}
var _people: PersonRegistry
var _start: WorldSetup.StartInfo
var _config: LifeConfig


func bind(people: PersonRegistry, start: WorldSetup.StartInfo, config: LifeConfig = null) -> void:
	_people = people
	_start = start
	_config = config if config != null else Config.life
	_records.clear()


func size() -> int:
	return _records.size()


func ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _records:
		out.append(id)
	out.sort()
	return out


func has_household(id: int) -> bool:
	return _records.has(id)


## Who lives in a household (in order of id).
func members(id: int) -> Array[PersonData]:
	var out := _people.in_household(id) if _people != null else ([] as Array[PersonData])
	out.sort_custom(func(a: PersonData, b: PersonData) -> bool: return a.id < b.id)
	return out


func home_of(id: int) -> int:
	return int((_records.get(id, {}) as Dictionary).get("home", 0))


## The homes of the settlement (the huts).
func homes() -> Array[int]:
	return _start.hut_ids if _start != null else ([] as Array[int])


## How many more fit under a roof before it is crowded (negative: crowded).
func room(home: int) -> int:
	return _config.home_room - (_people.living_in(home).size() if _people != null else 0)


## Every household anyone belongs to has a record (a new world, or one from
## before households were kept: its home is where most of them live).
func ensure_records(now: int) -> void:
	var homes_by: Dictionary = {} # household id -> {home -> count}
	for person in _people.all_people():
		if person.household_id <= 0:
			continue
		var counts: Dictionary = homes_by.get(person.household_id, {})
		counts[person.home_building_id] = int(counts.get(person.home_building_id, 0)) + 1
		homes_by[person.household_id] = counts
	for id: int in homes_by:
		if _records.has(id):
			continue
		var best := 0
		var most := -1
		var counts: Dictionary = homes_by[id]
		for home: int in counts:
			if int(counts[home]) > most or (int(counts[home]) == most and home < best):
				most = counts[home]
				best = home
		_records[id] = {"home": best, "founded": now}
	# (Households nobody belongs to any more are gone.)
	for id: int in _records.keys():
		if not homes_by.has(id):
			_records.erase(id)


## Two people have become partners: they found a household of their own —
## unless one of them lives alone, whom the other joins — under the roof with
## the most room. Children of theirs whose other parent is not with them come
## along. Returns the household.
func form_couple(a: PersonData, b: PersonData, now: int, new_id: int) -> int:
	for pair: Array in [[a, b], [b, a]]:
		var alone: PersonData = pair[0]
		var other: PersonData = pair[1]
		if alone.household_id > 0 and _records.has(alone.household_id) and members(alone.household_id).size() == 1:
			_move_in(other, alone.household_id, now)
			return alone.household_id
	var leaving := [a.id, b.id]
	var along: Array[PersonData] = []
	for parent: PersonData in [a, b]:
		for id in parent.children:
			var child := _people.get_person(id)
			if child == null or child.household_id != parent.household_id or _is_grown(child, now):
				continue
			var other_parent_there := false
			for p in child.parents:
				var them := _people.get_person(p)
				if p != parent.id and them != null and them.household_id == child.household_id and p != a.id and p != b.id:
					other_parent_there = true
			if not other_parent_there:
				along.append(child)
				leaving.append(child.id)
	var home := roomiest_home(leaving)
	_records[new_id] = {"home": home, "founded": now}
	var old: Array[int] = [a.household_id, b.household_id]
	for person: PersonData in [a, b] + along:
		person.household_id = new_id
		person.home_building_id = home
	for id in old:
		_forget_if_empty(id)
	return new_id


## A new home stands (M12.1): a household without a roof (theirs has fallen)
## moves in — or else the household of the most crowded home that more than
## one household shares (or of a home over-full).
## Returns the household that moved (0: nobody needed to).
func take_new_home(home: int) -> int:
	var best := mover(home)
	if best == 0:
		return 0
	_records[best]["home"] = home
	for person in members(best):
		person.home_building_id = home
	return best


## The household that would move to another home (not `except`): one without
## a roof, else one of the most crowded home that more than one household
## shares (or that is over-full); `full_only`: only from a home with no room
## left (where nobody more can be born). 0: none.
func mover(except: int = 0, full_only: bool = false) -> int:
	var best := 0
	var least_room := 1_000_000
	var ids := _records.keys()
	ids.sort()
	for id: int in ids:
		var at := home_of(id)
		if at == except or members(id).is_empty():
			continue
		if at == 0 or not homes().has(at):
			return id
		var sharing := 0
		for other: int in _records:
			if home_of(other) == at and not members(other).is_empty():
				sharing += 1
		var free := room(at)
		if (sharing > 1 or free < 0) and free < least_room and (not full_only or free <= 0):
			least_room = free
			best = id
	return best


## Crowded households move into the homes that stand empty. Returns how many moved.
func settle_empty_homes() -> int:
	var moved := 0
	for home in homes():
		if _people != null and _people.living_in(home).is_empty() and take_new_home(home) != 0:
			moved += 1
	return moved


## A home has fallen (M12.1): its household moves in where there is most
## room (if there is any). Returns how many households moved.
func rehouse() -> int:
	var moved := 0
	var ids := _records.keys()
	ids.sort()
	for id: int in ids:
		var at := home_of(id)
		if (at != 0 and homes().has(at)) or members(id).is_empty():
			continue
		var home := roomiest_home()
		if home == 0 or room(home) < members(id).size():
			continue
		_records[id]["home"] = home
		for person in members(id):
			person.home_building_id = home
		moved += 1
	return moved


## The home with the most room, not counting `leaving` (ids) among those who
## live there now (the first of them, by id; 0 if there are no homes).
func roomiest_home(leaving: Array = []) -> int:
	var best := 0
	var most := -1_000_000
	var sorted := homes().duplicate()
	sorted.sort()
	for home: int in sorted:
		var living := 0
		for person in _people.living_in(home):
			if not leaving.has(person.id):
				living += 1
		var free := _config.home_room - living
		if free > most:
			most = free
			best = home
	return best


## Someone of a household has died: if only children are left, they are taken
## in by family (or whoever has most room); an elder left alone moves in with
## a child of theirs. The household is gone once nobody is left in it.
## Returns who took them in: [[person id, household id], …].
func after_death(household_id: int, now: int) -> Array:
	var moved: Array = []
	if household_id <= 0:
		return moved
	var left := members(household_id)
	if left.is_empty():
		_records.erase(household_id)
		return moved
	var grown := 0
	for person in left:
		if _is_grown(person, now):
			grown += 1
	if grown == 0:
		var into := _kin_household(left, household_id, now)
		if into == 0:
			into = _roomiest_household(household_id)
		if into != 0:
			for person in left:
				_move_in(person, into, now)
				moved.append([person.id, into])
	elif left.size() == 1 and _stage(left[0], now) == PersonData.LifeStage.ELDER:
		var elder := left[0]
		for id in elder.children:
			var child := _people.get_person(id)
			if child != null and child.household_id != household_id and _is_grown(child, now) and child.household_id > 0:
				_move_in(elder, child.household_id, now)
				moved.append([elder.id, child.household_id])
				break
	_forget_if_empty(household_id)
	return moved


func to_dict() -> Dictionary:
	var out: Array = []
	for id in ids():
		out.append({"id": id, "home": home_of(id), "founded": int(_records[id].get("founded", 0))})
	return {"households": out}


## Returns how many saved records were unusable.
func from_dict(data: Dictionary) -> int:
	_records.clear()
	var saved: Variant = data.get("households")
	if typeof(saved) != TYPE_ARRAY:
		return 0
	var skipped := 0
	for entry: Variant in saved:
		if typeof(entry) != TYPE_DICTIONARY or typeof((entry as Dictionary).get("id")) != TYPE_INT \
				or int(entry["id"]) <= 0 or _records.has(int(entry["id"])):
			skipped += 1
			continue
		_records[int(entry["id"])] = {"home": maxi(int(entry.get("home", 0)), 0), "founded": int(entry.get("founded", 0))}
	return skipped


# --- internals --------------------------------------------------------------------------------------

func _move_in(person: PersonData, household_id: int, _now: int) -> void:
	var was := person.household_id
	person.household_id = household_id
	person.home_building_id = home_of(household_id)
	if was != household_id:
		_forget_if_empty(was)


func _forget_if_empty(id: int) -> void:
	if id > 0 and _records.has(id) and members(id).is_empty():
		_records.erase(id)


## A household of family of theirs: grandparents, grown brothers and
## sisters, their parents' brothers and sisters — the nearest kin first (0: none).
func _kin_household(children: Array[PersonData], except: int, now: int) -> int:
	var rings: Array = [[], [], []]
	for child in children:
		for parent_id in child.parents:
			for grand in _parents_of(parent_id):
				rings[0].append(grand)
			for sibling in _children_of_parents_of(parent_id):
				if sibling != parent_id:
					rings[2].append(sibling)
		for sibling in _children_of_parents_of(child.id):
			rings[1].append(sibling)
	for ring: Array in rings:
		ring.sort()
		for id: int in ring:
			var kin := _people.get_person(id)
			if kin != null and kin.household_id > 0 and kin.household_id != except and _is_grown(kin, now) \
					and _records.has(kin.household_id):
				return kin.household_id
	return 0


func _roomiest_household(except: int) -> int:
	var best := 0
	var most := -1_000_000
	for id in ids():
		if id == except:
			continue
		var free := room(home_of(id))
		if free > most:
			most = free
			best = id
	return best


## A person's parents' ids (living or not).
func _parents_of(id: int) -> PackedInt64Array:
	var person := _people.get_person(id)
	if person != null:
		return person.parents
	var record := _people.archive.get_record(id) if _people.archive != null else null
	return record.parents if record != null else PackedInt64Array()


## Everyone who shares a parent with `id` (themselves included).
func _children_of_parents_of(id: int) -> Array[int]:
	var out: Array[int] = []
	for parent_id in _parents_of(id):
		var parent := _people.get_person(parent_id)
		var children := parent.children if parent != null else PackedInt64Array()
		if parent == null and _people.archive != null and _people.archive.get_record(parent_id) != null:
			children = _people.archive.get_record(parent_id).children
		for child in children:
			if not out.has(child):
				out.append(child)
	return out


func _stage(person: PersonData, now: int) -> PersonData.LifeStage:
	return person.life_stage(now, Config.time.ticks_per_year(), Config.people)


func _is_grown(person: PersonData, now: int) -> bool:
	var stage := _stage(person, now)
	return stage == PersonData.LifeStage.ADULT or stage == PersonData.LifeStage.ELDER
