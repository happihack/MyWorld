class_name EventLog
extends RefCounted
## What has happened in the world (bible §21.1, §21.2, D-14): every event
## worth keeping, each with the events that brought it about. Whoever
## records an event because of another passes that other's id — so the
## chain "dry spell → crop failure → food shortage" is written down as it
## happens and never has to be guessed.
##
## Saved with the world. Bounded: when it is full, old events that matter
## little — and that nothing kept was caused by — make room.

## Something new happened.
signal recorded(event: WorldEvent)
## Something happened again and was taken together with an earlier event
## (see EventDef.merge_minutes).
signal merged(event: WorldEvent)

## What `params` of record() may hold besides what goes into the text.
const PARAM_POSITION := "position"
const PARAM_PARTICIPANTS := "participants"
const PARAM_SETTLEMENT := "settlement"
const PARAM_REGION := "region"
const PARAM_SIGNIFICANCE := "significance"
const PARAM_EFFECTS := "effects"
const PARAM_TAGS := "tags"
const PARAM_TICK := "tick"
const _RESERVED: PackedStringArray = [PARAM_POSITION, PARAM_PARTICIPANTS, PARAM_SETTLEMENT, PARAM_REGION,
	PARAM_SIGNIFICANCE, PARAM_EFFECTS, PARAM_TAGS, PARAM_TICK]

var library: EventLibrary
## For the debug overlay.
var merges := 0
var pruned := 0

var _clock: GameClock
var _config: EventsConfig
var _next_id := 1
var _events: Array[WorldEvent] = [] # oldest first (by id)
var _by_id: Dictionary = {} # id -> WorldEvent
var _by_type: Dictionary = {} # type -> Array of ids, oldest first
## The firsts there have been: "type" or "type:kind" -> event id. Kept for
## ever, so that nothing is "the first" twice once the event itself is gone.
var _firsts: Dictionary = {}


func bind(clock: GameClock, event_library: EventLibrary = null, config: EventsConfig = null) -> void:
	_clock = clock
	if event_library != null:
		library = event_library
	_config = config if config != null else Config.events


func clear() -> void:
	_next_id = 1
	_events.clear()
	_by_id.clear()
	_by_type.clear()
	_firsts.clear()
	merges = 0
	pruned = 0


# --- recording ------------------------------------------------------------------------------------

## Records that something of the kind `type` happened, now. `params` is
## what goes into its text ("resource": "grain", "days": 5) and may also
## hold: "position" (Vector2), "participants" (person ids), "settlement",
## "region", "significance" (in place of the definition's), "effects"
## (Dictionary), "tags" (more of them). `causes`: the events that brought
## it about — their ids, or the events themselves.
## Returns the event (the earlier one, if it was taken together with it).
func record(type: StringName, params: Dictionary = {}, causes: Array = []) -> WorldEvent:
	if type == &"":
		return null
	var def := library.get_def(type) if library != null else null
	if def == null and library != null:
		Log.warn(Log.Category.SIM, "An event of an unknown kind is recorded", {"type": type})
	var now := int(params[PARAM_TICK]) if typeof(params.get(PARAM_TICK)) == TYPE_INT else (_clock.tick if _clock != null else 0)
	var cause_ids := _cause_ids(causes)
	var text_params := {}
	for key: Variant in params:
		if not _RESERVED.has(str(key)):
			text_params[str(key)] = params[key]
	var who := WorldEvent._ids(params.get(PARAM_PARTICIPANTS))
	# The same thing again, soon after, for the same reasons: one event.
	if def != null and def.merge_minutes > 0:
		var earlier := _mergeable(def, text_params, cause_ids, now)
		if earlier != null:
			earlier.count += maxi(int(text_params.get("count", 1)), 1)
			earlier.last_tick = now
			for person_id in who:
				if not earlier.participants.has(person_id):
					earlier.participants.append(person_id)
			merges += 1
			merged.emit(earlier)
			return earlier
	var event := WorldEvent.new()
	event.id = _next_id
	_next_id += 1
	event.type = type
	event.tick = now
	event.last_tick = now
	if typeof(params.get(PARAM_POSITION)) == TYPE_VECTOR2 and (params[PARAM_POSITION] as Vector2).is_finite():
		event.position = params[PARAM_POSITION]
	event.settlement_id = int(params.get(PARAM_SETTLEMENT, 0))
	event.region_id = int(params.get(PARAM_REGION, 0))
	event.participants = who
	event.causes = cause_ids
	if typeof(params.get(PARAM_EFFECTS)) == TYPE_DICTIONARY:
		event.effects = (params[PARAM_EFFECTS] as Dictionary).duplicate(true)
	event.text_params = text_params
	event.count = maxi(int(text_params.get("count", 1)), 1)
	text_params.erase("count")
	if def != null:
		event.significance = def.significance
		event.visibility = def.visibility
		event.text_key = def.key_for_text()
		event.tags = def.tags.duplicate()
		# The first of its kind.
		var first_key := String(type)
		if def.first_by != "":
			first_key += ":" + str(text_params.get(def.first_by, ""))
		if not _firsts.has(first_key):
			_firsts[first_key] = event.id
			if def.first_significance > 0.0:
				event.significance = maxf(event.significance, def.first_significance)
				event.tags.append("first")
	else:
		event.text_key = "EVENT_" + String(type).to_upper()
	if typeof(params.get(PARAM_SIGNIFICANCE)) == TYPE_FLOAT:
		event.significance = clampf(float(params[PARAM_SIGNIFICANCE]), 0.0, 1.0)
	var more: Variant = params.get(PARAM_TAGS)
	if typeof(more) == TYPE_ARRAY or typeof(more) == TYPE_PACKED_STRING_ARRAY:
		for tag: Variant in more:
			if not event.tags.has(str(tag)):
				event.tags.append(str(tag))
	_add(event)
	if _config != null and _events.size() > _config.max_events:
		prune()
	recorded.emit(event)
	if _config != null and event.significance >= _config.major_from:
		EventBus.major_event_occurred.emit(event.id)
	return event


## Notes what came of an event (after the fact: "ended": the tick).
func note_effect(event_id: int, key: String, value: Variant) -> void:
	var event := get_event(event_id)
	if event != null:
		event.effects[key] = value


# --- questions ------------------------------------------------------------------------------------

## The game tick it is now (0 without a clock).
func now() -> int:
	return _clock.tick if _clock != null else 0


func size() -> int:
	return _events.size()


func get_event(id: int) -> WorldEvent:
	return _by_id.get(id)


func has_event(id: int) -> bool:
	return _by_id.has(id)


## Everything, oldest first.
func all_events() -> Array[WorldEvent]:
	return _events


## The latest `count` events, the latest first.
func latest_events(count: int = 10) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	var i := _events.size() - 1
	while i >= 0 and out.size() < count:
		out.append(_events[i])
		i -= 1
	return out


## The events of one kind, oldest first — those from `from_tick` to
## `to_tick`, if given.
func of_type(type: StringName, from_tick: int = -0x7FFFFFFFFFFFFFFF, to_tick: int = 0x7FFFFFFFFFFFFFFF) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for id: int in _by_type.get(type, []):
		var event: WorldEvent = _by_id[id]
		if event.last_tick >= from_tick and event.tick <= to_tick:
			out.append(event)
	return out


## The latest event of a kind (null if there has been none).
func latest(type: StringName) -> WorldEvent:
	var ids: Array = _by_type.get(type, [])
	return _by_id[ids[-1]] if not ids.is_empty() else null


## The id of the latest event of a kind that happened no longer than
## `within_minutes` before `now` (0 if there is none).
func recent_id(type: StringName, within_minutes: int, now: int = -1) -> int:
	var event := latest(type)
	if now < 0:
		now = _clock.tick if _clock != null else 0
	return event.id if event != null and now - event.last_tick <= within_minutes else 0


func count_of(type: StringName) -> int:
	return (_by_type.get(type, []) as Array).size()


## What happened from `from_tick` to `to_tick`, oldest first.
func between(from_tick: int, to_tick: int) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for event in _events:
		if event.last_tick >= from_tick and event.tick <= to_tick:
			out.append(event)
	return out


## What happened within `radius` tiles of a place, oldest first.
func near(at: Vector2, radius: float) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for event in _events:
		if event.has_position() and event.position.distance_to(at) <= radius:
			out.append(event)
	return out


## What concerned a person, oldest first.
func involving(person_id: int) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for event in _events:
		if event.participants.has(person_id):
			out.append(event)
	return out


## Events by several things at once. `filter` may hold: "type", "tag",
## "participant", "from", "to" (ticks), "near" (Vector2) with "radius",
## "min_significance". Oldest first.
func find(filter: Dictionary) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	var pool: Array[WorldEvent] = _events
	if filter.has("type"):
		pool = of_type(StringName(str(filter["type"])))
	var from := int(filter.get("from", -0x7FFFFFFFFFFFFFFF))
	var to := int(filter.get("to", 0x7FFFFFFFFFFFFFFF))
	var least := float(filter.get("min_significance", 0.0))
	var radius := float(filter.get("radius", 0.0))
	for event in pool:
		if event.last_tick < from or event.tick > to or event.significance < least:
			continue
		if filter.has("tag") and not event.tags.has(str(filter["tag"])):
			continue
		if filter.has("participant") and not event.participants.has(int(filter["participant"])):
			continue
		if typeof(filter.get("near")) == TYPE_VECTOR2 \
				and (not event.has_position() or event.position.distance_to(filter["near"]) > radius):
			continue
		out.append(event)
	return out


## Everything that led to an event: its causes, their causes, and so on —
## oldest first, each once (the event itself is not among them).
func chain(event_id: int) -> Array[WorldEvent]:
	var seen := {}
	var open: Array[int] = [event_id]
	while not open.is_empty():
		var event := get_event(open.pop_back())
		if event == null:
			continue
		for cause in event.causes:
			if not seen.has(cause) and _by_id.has(cause):
				seen[cause] = true
				open.append(cause)
	var out: Array[WorldEvent] = []
	var ids: Array = seen.keys()
	ids.sort()
	for id: int in ids:
		out.append(_by_id[id])
	return out


## Did `cause_id` lead to `event_id` (directly or through others)?
func led_to(cause_id: int, event_id: int) -> bool:
	for event in chain(event_id):
		if event.id == cause_id:
			return true
	return false


## What an event brought about directly: the events that name it as a cause.
func consequences(event_id: int) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for event in _events:
		if event.causes.has(event_id):
			out.append(event)
	return out


# --- keeping it within bounds ---------------------------------------------------------------------

## Makes room: the oldest events that matter little, are no firsts, and
## that nothing still kept was caused by, go — until there is a tenth of
## the room free. Returns how many went.
func prune() -> int:
	if _config == null:
		return 0
	var wanted := int(_config.max_events * 0.9)
	if _events.size() <= wanted:
		return 0
	var gone := 0
	for keep_from: float in [_config.keep_significance, 2.0]:
		if _events.size() - gone <= wanted:
			break
		var cited := {}
		for event in _events:
			if event != null:
				for cause in event.causes:
					cited[cause] = true
		for i in _events.size():
			if _events.size() - gone <= wanted:
				break
			var event := _events[i]
			if event == null or event.significance >= keep_from or event.is_first() or cited.has(event.id):
				continue
			_events[i] = null
			gone += 1
	if gone > 0:
		var kept: Array[WorldEvent] = []
		for event in _events:
			if event != null:
				kept.append(event)
		_events = kept
		_reindex()
		pruned += gone
	return gone


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for event in _events:
		list.append(event.to_dict())
	return {"next_id": _next_id, "events": list, "firsts": _firsts.duplicate()}


## Restores a saved log. Returns how many records were unusable (and skipped).
func from_dict(data: Dictionary) -> int:
	clear()
	var skipped := 0
	var saved: Variant = data.get("events")
	if typeof(saved) == TYPE_ARRAY:
		for record: Variant in saved:
			var event := WorldEvent.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
			if event == null or _by_id.has(event.id):
				skipped += 1
				continue
			_events.append(event)
			_by_id[event.id] = event
	_events.sort_custom(func(a: WorldEvent, b: WorldEvent) -> bool: return a.id < b.id)
	_reindex()
	_next_id = maxi(int(data.get("next_id", 1)) if typeof(data.get("next_id", 1)) == TYPE_INT else 1, 1)
	if not _events.is_empty():
		_next_id = maxi(_next_id, _events[-1].id + 1)
	var firsts: Variant = data.get("firsts")
	if typeof(firsts) == TYPE_DICTIONARY:
		for key: Variant in firsts:
			if typeof((firsts as Dictionary)[key]) == TYPE_INT:
				_firsts[str(key)] = int(firsts[key])
	return skipped


func debug_text(count: int = 4) -> String:
	var lines := PackedStringArray(["events: %d (merged %d, pruned %d)" % [_events.size(), merges, pruned]])
	for event in latest_events(count):
		lines.append("  " + event.describe())
	return "\n".join(lines)


# --- internals ------------------------------------------------------------------------------------

func _add(event: WorldEvent) -> void:
	_events.append(event)
	_by_id[event.id] = event
	if not _by_type.has(event.type):
		_by_type[event.type] = []
	(_by_type[event.type] as Array).append(event.id)


func _reindex() -> void:
	_by_id.clear()
	_by_type.clear()
	for event in _events:
		_by_id[event.id] = event
		if not _by_type.has(event.type):
			_by_type[event.type] = []
		(_by_type[event.type] as Array).append(event.id)


## The ids of the causes given (ids or events), each once, in order;
## anything that is not an event of this log is left out.
func _cause_ids(causes: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for cause: Variant in causes:
		var id := 0
		if cause is WorldEvent:
			id = (cause as WorldEvent).id
		elif typeof(cause) == TYPE_INT:
			id = cause
		if id > 0 and _by_id.has(id) and not out.has(id):
			out.append(id)
	out.sort()
	return out


## The latest event of the kind that this one is the same as, happening
## again (see EventDef.merge_minutes), or null.
func _mergeable(def: EventDef, text_params: Dictionary, cause_ids: PackedInt64Array, now: int) -> WorldEvent:
	var earlier := latest(def.id)
	if earlier == null or now - earlier.last_tick > def.merge_minutes or now < earlier.tick or earlier.causes != cause_ids:
		return null
	for key in def.merge_by:
		if earlier.text_params.get(key) != text_params.get(key):
			return null
	return earlier
