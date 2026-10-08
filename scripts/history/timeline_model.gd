class_name TimelineModel
extends RefCounted
## The world's history as the timeline shows it (bible §21.4, M11.3): its
## events grouped by year, the latest first, through a filter — and for each
## event, where to look: where it happened, or (if it happened nowhere in
## particular, or the place is gone) whom it concerned — the living, the
## graves of the dead, or their living descendants.

const FILTER_ALL := &"all"
## What matters (EventsConfig.major_from and up).
const FILTER_MAJOR := &"major"
## What happened to and between people.
const FILTER_PEOPLE := &"people"
## What the world did to them: floods, droughts, hunger, storms, fire.
const FILTER_DISASTERS := &"disasters"
## What the player did.
const FILTER_PLAYER := &"player"
const FILTERS: Array[StringName] = [FILTER_ALL, FILTER_MAJOR, FILTER_PEOPLE, FILTER_DISASTERS, FILTER_PLAYER]
const DISASTERS: Array[StringName] = [&"flood", &"drought", &"storm", &"blizzard", &"cold_snap", &"heat_wave", &"food_shortage",
	&"stores_empty", &"crop_failure", &"crop_frozen", &"poor_harvest", &"fire_out", &"stores_flooded", &"home_moved",
	&"high_water", &"seed_grain_eaten", &"earthquake", &"eclipse", &"tornado", &"blood_water", &"meteor_storm"]

## How to find what an event concerned: where to look, and how it was found.
enum Found { NOWHERE, PLACE, PERSON, GRAVE, DESCENDANT }


class Target:
	extends RefCounted
	var found: Found = Found.NOWHERE
	var position := Vector2.INF
	## The person it led to (a living person, or whose grave it is).
	var person_id := 0


## The timeline's rows, the latest year first, each year's latest event first:
## [{"year": int} | {"event": WorldEvent}, …].
static func rows(log: EventLog, filter: StringName = FILTER_ALL) -> Array:
	var out: Array = []
	if log == null:
		return out
	var shown: Array[WorldEvent] = []
	for event in log.all_events():
		if passes(event, filter):
			shown.append(event)
	shown.sort_custom(func(a: WorldEvent, b: WorldEvent) -> bool: return a.tick > b.tick or (a.tick == b.tick and a.id > b.id))
	var year := -1
	for event in shown:
		var of := HistoryText.year_of(event.tick)
		if of != year:
			year = of
			out.append({"year": year})
		out.append({"event": event})
	return out


## Does an event go through a filter?
static func passes(event: WorldEvent, filter: StringName) -> bool:
	match filter:
		FILTER_MAJOR:
			return event.significance >= Config.events.major_from or event.has_tag("first")
		FILTER_PEOPLE:
			return event.has_tag("people") or event.has_tag("family") or event.has_tag("relationships")
		FILTER_DISASTERS:
			return DISASTERS.has(event.type)
		FILTER_PLAYER:
			return event.type == &"player_intervention"
	return true


## Where to look for an event: the place it happened; else whom it concerned
## — someone living, the grave of someone dead, or a living descendant of theirs.
static func locate(session: WorldSession, event: WorldEvent) -> Target:
	var target := Target.new()
	if event == null:
		return target
	if event.has_position() and _in_world(session, event.position):
		target.found = Found.PLACE
		target.position = event.position
		return target
	for id in event.participants:
		var person := session.people.get_person(id)
		if person != null:
			target.found = Found.PERSON
			target.person_id = id
			target.position = person.world2d()
			return target
	for id in event.participants:
		var record := session.archive.get_record(id)
		if record != null and record.grave_id != 0 and session.props.get_prop(record.grave_id) != null:
			target.found = Found.GRAVE
			target.person_id = id
			target.position = Vector2(record.grave_tile) + Vector2(0.5, 0.5)
			return target
	for id in event.participants:
		var heir := _living_descendant(session, id)
		if heir != null:
			target.found = Found.DESCENDANT
			target.person_id = heir.id
			target.position = heir.world2d()
			return target
	return target


## A living descendant of someone (the nearest generation first, the eldest first).
static func _living_descendant(session: WorldSession, id: int) -> PersonData:
	var ring: Array[int] = [id]
	var seen := {id: true}
	for generation in 8:
		var next: Array[int] = []
		for parent in ring:
			for child in FamilyTree.children_of(session, parent):
				if seen.has(child):
					continue
				seen[child] = true
				var living := session.people.get_person(child)
				if living != null:
					return living
				next.append(child)
		if next.is_empty():
			return null
		ring = next
	return null


static func _in_world(session: WorldSession, at: Vector2) -> bool:
	return at.is_finite() and session.world != null and session.world.is_in_bounds(Vector2i(floori(at.x), floori(at.y)))
