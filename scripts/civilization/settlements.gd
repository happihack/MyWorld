class_name Settlements
extends RefCounted
## Every settlement of the world (bible §17, M12.3): the first, by the fire the
## band arrived at, and those founded since by people who set out from it.
## Each has its own fire, homes, stores, job board and planner; people belong
## to one (PersonData.settlement_id), and whatever they do they do as people of
## it (AiContext.enter switches to it).

## Derived tiers (bible §17.1), by how many live there.
enum Tier { CAMP, HAMLET, VILLAGE, TOWN, CITY }
## From how many people each tier begins (Camp: from the first).
const TIER_FROM: Array[int] = [0, 10, 30, 60, 200] # (a town at 60: a box holds a hundred or two in all)
const TIER_NAMES: Array[String] = ["Camp", "Hamlet", "Village", "Town", "City"]

var _list: Array[Settlement] = []
var _by_id: Dictionary = {} # id -> Settlement


func add(settlement: Settlement) -> void:
	if settlement == null or _by_id.has(settlement.id):
		return
	_list.append(settlement)
	_by_id[settlement.id] = settlement


## Takes a settlement out of the world's (it is abandoned, M12.5).
func remove(settlement: Settlement) -> void:
	if settlement == null or not _by_id.has(settlement.id):
		return
	_list.erase(settlement)
	_by_id.erase(settlement.id)
	settlement.unbind()


func clear() -> void:
	for settlement in _list:
		settlement.unbind()
	_list.clear()
	_by_id.clear()


## The first settlement (where the band arrived; null if there is none).
func primary() -> Settlement:
	return _list[0] if not _list.is_empty() else null


func all() -> Array[Settlement]:
	return _list


## Home (M13.5): the largest settlement — the first among equals (null if none).
func home() -> Settlement:
	var best: Settlement = null
	for own in _list:
		if best == null or own.member_count() > best.member_count():
			best = own
	return best


func size() -> int:
	return _list.size()


func get_settlement(id: int) -> Settlement:
	return _by_id.get(id)


## The settlement a person belongs to (the first, for anyone of none).
func of(person: PersonData) -> Settlement:
	if person == null:
		return primary()
	var found: Settlement = _by_id.get(person.settlement_id)
	return found if found != null else primary()


## The settlement whose home (hut) this is (null: none).
func of_home(home_id: int) -> Settlement:
	for settlement in _list:
		if settlement.start_info() != null and settlement.start_info().hut_ids.has(home_id):
			return settlement
	return null


## The settlement whose fire is nearest `tile` (null: none).
func nearest(tile: Vector2i) -> Settlement:
	var best: Settlement = null
	var best_distance := INF
	for settlement in _list:
		var at := settlement.start_info().settlement_tile
		var distance := Vector2(at - tile).length()
		if distance < best_distance:
			best_distance = distance
			best = settlement
	return best


## Every home (hut) of every settlement.
func all_homes() -> Array[int]:
	var out: Array[int] = []
	for settlement in _list:
		out.append_array(settlement.start_info().hut_ids)
	return out


## The fires of all settlements (their tiles).
func fire_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for settlement in _list:
		out.append(settlement.start_info().settlement_tile)
	return out


## Lets time pass for every settlement (its fire, stores, jobs, plans).
func step(now: int) -> void:
	planner_usec = 0
	for settlement in _list:
		if settlement.farming != null:
			settlement.farming.use_start(settlement.start_info())
		settlement.step(now)
		if settlement.planner != null:
			var started := Time.get_ticks_usec()
			settlement.planner.advance_to(now)
			planner_usec += Time.get_ticks_usec() - started


## How long the planners took in the last step (µs; for the profile).
var planner_usec := 0


static func tier_for(people: int) -> Tier:
	var tier := Tier.CAMP
	for i in TIER_FROM.size():
		if people >= TIER_FROM[i]:
			tier = i as Tier
	return tier


static func tier_name(tier: Tier) -> String:
	return TIER_NAMES[tier]


func debug_text() -> String:
	var parts := PackedStringArray()
	for settlement in _list:
		parts.append("%s (%s, %d people)" % [settlement.display_name(), tier_name(settlement.tier()), settlement.member_count()])
	return "settlements: " + ", ".join(parts)
