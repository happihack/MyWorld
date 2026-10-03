class_name Significance
extends RefCounted
## Who matters to the world's history (bible §21.5, M11.2). Nobody is
## important to begin with: significance accrues from the events a person
## takes part in — the first of an event's participants most — weighted by
## how much each event matters (data/events), and more for the firsts among
## them (the first child born, the first touch of the Presence …). Above a
## threshold someone is one of the Important People: spoken of (an event),
## listed in the menu, remembered when they die (HistoricalPerson).
##
## The firsts themselves are the event log's (its ledger of the first of
## each kind); `firsts` lists those worth telling.

## Someone has become one of the Important People (the event that tipped it).
signal became_important(person_id: int, event_id: int)

var _log: EventLog
var _people: PersonRegistry
var _config: SignificanceConfig


func bind(log: EventLog, people: PersonRegistry, config: SignificanceConfig = null) -> void:
	if _log != null:
		if _log.recorded.is_connected(credit):
			_log.recorded.disconnect(credit)
		if _log.happened_again.is_connected(credit_again):
			_log.happened_again.disconnect(credit_again)
	_log = log
	_people = people
	_config = config if config != null else Config.significance
	if _log != null:
		_log.recorded.connect(credit)
		_log.happened_again.connect(credit_again)


## An event happened: those who took part in it gain.
func credit(event: WorldEvent) -> void:
	if event != null:
		_credit(event, event.participants)


## It happened again (taken together with the earlier event): those who took
## part this time gain (being touched by the Presence twenty times …).
func credit_again(event: WorldEvent, participants: PackedInt64Array) -> void:
	_credit(event, participants)


func _credit(event: WorldEvent, participants: PackedInt64Array) -> void:
	if _people == null or participants.is_empty() or _config.not_counted.has(String(event.type)):
		return
	var touched := event.type == &"player_intervention" and str(event.text_params.get("subject", "")) == "person"
	var first := event.tags.has("first") and event.count <= 1
	if not touched and not first and event.significance < _config.least_counted:
		return # (history is made of what stands out)
	for n in participants.size():
		var person := _people.get_person(participants[n])
		if person == null:
			continue
		var gained := _config.presence_touch if touched else event.significance * (_config.principal_share if n == 0 else _config.other_share)
		if not touched:
			# The same kind of thing again counts less each time.
			var deeds: Dictionary = person.knowledge.get("deeds", {})
			var times := int(deeds.get(String(event.type), 0)) + 1
			deeds[String(event.type)] = times
			person.knowledge["deeds"] = deeds
			gained /= 1.0 + _config.repeat_wear * float(times - 1)
		if n == 0 and first:
			gained += _config.first_bonus
		var was := person.significance
		person.significance = was + gained
		if was < _config.important_from and person.significance >= _config.important_from:
			became_important.emit(person.id, event.id)


## Is this person (living or dead) one of the Important People?
func is_important(id: int) -> bool:
	return points_of(id) >= _config.important_from


## How much someone (living or dead) has mattered, in points.
func points_of(id: int) -> float:
	var person := _people.get_person(id) if _people != null else null
	if person != null:
		return person.significance
	var record := _people.archive.get_record(id) if _people != null and _people.archive != null else null
	return record.significance if record != null else 0.0


## The Important People, living and dead, the most significant first: [id, …].
func important_people() -> Array[int]:
	var out: Array[int] = []
	var points := {}
	for person in _people.all_people():
		if person.significance >= _config.important_from:
			out.append(person.id)
			points[person.id] = person.significance
	if _people.archive != null:
		for record in _people.archive.all_records():
			if record.significance >= _config.important_from:
				out.append(record.id)
				points[record.id] = record.significance
	out.sort_custom(func(a: int, b: int) -> bool:
		return float(points[a]) > float(points[b]) if float(points[a]) != float(points[b]) else a < b)
	return out


## What someone is most remembered for: the most significant event they took
## part in, the first of its participants (null: nothing yet).
func best_deed(id: int) -> WorldEvent:
	if _log == null:
		return null
	var best: WorldEvent = null
	for event in _log.all_events():
		if event.participants.is_empty() or event.participants[0] != id or _config.not_counted.has(String(event.type)):
			continue
		var worth := event.significance + (_config.first_bonus if event.tags.has("first") else 0.0)
		var best_worth := best.significance + (_config.first_bonus if best.tags.has("first") else 0.0) if best != null else -1.0
		if worth > best_worth:
			best = event
	return best


## The firsts worth telling (events marked "first"), the earliest first.
func firsts() -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	if _log == null:
		return out
	for id: int in _log.firsts().values():
		var event := _log.get_event(id)
		if event != null and event.tags.has("first"):
			out.append(event)
	out.sort_custom(func(a: WorldEvent, b: WorldEvent) -> bool: return a.tick < b.tick or (a.tick == b.tick and a.id < b.id))
	return out
