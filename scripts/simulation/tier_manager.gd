class_name TierManager
extends RefCounted
## Who is simulated how closely (bible §31.6). Version 0:
##   4  Player Focus — whoever the player has selected or follows
##   3  Active       — everyone else, up to a cap
##   2  Regional     — whoever is beyond the cap, furthest from where the
##                     player looks (coarser steps; never loses time)
##   1  Abstract     — beyond that too, the furthest of all: an hour at a
##                     time (M21; never loses time either)
## Tier 0 (dormant, per day) is not used: nobody is that far yet.
##
## A person's tier is PersonData.sim_tier (runtime only). Their state is the
## same in every tier, so they can move between tiers at any time.

const FOCUS := 4
const ACTIVE := 3
const REGIONAL := 2
const ABSTRACT := 1
const DORMANT := 0

## The tiers changed (someone came into focus, or left it).
signal changed

## Where the player is looking (world XZ): people nearest to it keep tier 3
## when there are more than the cap allows.
var interest := Vector2.ZERO
## Use the low-end cap.
var low_end := false

var _people: PersonRegistry
var _focus: Array[int] = [] # most recent last
var _stale := true


func bind(people: PersonRegistry) -> void:
	unbind()
	_people = people
	if people != null:
		people.person_added.connect(_on_membership_changed)
		people.person_removed.connect(_on_person_removed)
	_stale = true
	refresh()


func unbind() -> void:
	if _people != null:
		_people.person_added.disconnect(_on_membership_changed)
		_people.person_removed.disconnect(_on_person_removed)
	_people = null
	_focus.clear()


## Puts a person in the player's focus (tier 4). The focus holds a few
## people at most; the one focused longest ago gives way.
func focus(person_id: int) -> bool:
	if _people == null or not _people.has_person(person_id):
		return false
	_focus.erase(person_id)
	_focus.append(person_id)
	while _focus.size() > Config.sim.tier4_cap:
		_focus.pop_front()
	_stale = true
	refresh()
	return true


## Takes a person out of focus (or everyone, with -1).
func unfocus(person_id: int = -1) -> void:
	if person_id < 0:
		_focus.clear()
	else:
		_focus.erase(person_id)
	_stale = true
	refresh()


func is_focused(person_id: int) -> bool:
	return _focus.has(person_id)


func focused() -> Array[int]:
	return _focus.duplicate()


## Tells the manager where the player is looking. Tiers follow only when the
## cap is in play (otherwise where one looks changes nothing).
func look_at(point: Vector2) -> void:
	if point.distance_squared_to(interest) < 4.0:
		return
	interest = point
	if _people != null and _people.size() > Config.sim.tier3_cap(low_end):
		_stale = true


## Brings everyone's tier up to date. Cheap when nothing changed.
func refresh() -> void:
	if not _stale or _people == null:
		return
	_stale = false
	var cap := Config.sim.tier3_cap(low_end)
	var regional := Config.sim.tier2_cap(low_end)
	var others: Array[PersonData] = []
	for person in _people.all_people():
		if _focus.has(person.id):
			person.sim_tier = FOCUS
		else:
			others.append(person)
	if others.size() > cap:
		var from := interest
		others.sort_custom(func(a: PersonData, b: PersonData) -> bool:
			var da := a.world2d().distance_squared_to(from)
			var db := b.world2d().distance_squared_to(from)
			return da < db or (da == db and a.id < b.id))
	for i in others.size():
		others[i].sim_tier = ACTIVE if i < cap else (REGIONAL if i < cap + regional else ABSTRACT)
	changed.emit()


## How many people are in each tier: tier -> count.
func counts() -> Dictionary:
	var out := {}
	if _people != null:
		for person in _people.all_people():
			out[person.sim_tier] = int(out.get(person.sim_tier, 0)) + 1
	return out


func _on_membership_changed(_id: int) -> void:
	_stale = true


func _on_person_removed(id: int) -> void:
	_focus.erase(id)
	_stale = true
