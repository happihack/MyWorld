class_name WorldEvent
extends RefCounted
## Something that happened in the world and is worth keeping (bible §21.1):
## a lasting record of what it was, when and where, whom it concerned — and
## what brought it about. The causes are given by whoever records it, at
## the moment it is recorded (§21.2): nobody guesses them afterwards.
##
## Plain data, kept in the EventLog.

## Who knows of it (bible: "visibility").
enum Visibility {
	## Anyone in the world may come to know of it.
	WORLD,
	## The people of the settlement it happened in.
	SETTLEMENT,
	## Only those it happened to.
	WITNESSES,
	## Nobody in the box: only the player (what the player did).
	PLAYER,
}

var id := 0
## What kind of thing it was: an EventDef's id ("crop_failure").
var type: StringName = &""
## When it happened — the first time, if it has happened again since and
## was taken together with this (see `count`).
var tick := 0
## When it last happened.
var last_tick := 0
## Where (world X/Z); Vector2.INF = nowhere in particular.
var position := Vector2.INF
var region_id := 0
var settlement_id := 0
## The people it concerned.
var participants := PackedInt64Array()
## The events that brought it about (their ids).
var causes := PackedInt64Array()
## What came of it, as far as whoever recorded it could say (small values).
var effects: Dictionary = {}
## How much it matters, 0 … 1.
var significance := 0.0
var visibility: Visibility = Visibility.SETTLEMENT
## The text template and what goes into it (see EventText).
var text_key := ""
var text_params: Dictionary = {}
var tags := PackedStringArray()
## How many times it happened (the same thing, soon after, for the same reasons).
var count := 1


func has_position() -> bool:
	return position != Vector2.INF


func involves(person_id: int) -> bool:
	return participants.has(person_id)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Was it the first of its kind?
func is_first() -> bool:
	return tags.has("first")


func describe() -> String:
	return "#%d %s @%d%s sig %.2f%s%s" % [id, type, tick, " x%d" % count if count > 1 else "", significance,
		" <- %s" % str(Array(causes)) if not causes.is_empty() else "", " %s" % str(text_params) if not text_params.is_empty() else ""]


## What is at its default is left out (events are kept for the life of a world).
func to_dict() -> Dictionary:
	var out := {"id": id, "type": String(type), "tick": tick, "sig": significance}
	if last_tick != tick:
		out["last"] = last_tick
	if position != Vector2.INF:
		out["at"] = position
	if region_id != 0:
		out["region"] = region_id
	if settlement_id != 0:
		out["settlement"] = settlement_id
	if not participants.is_empty():
		out["who"] = participants
	if not causes.is_empty():
		out["causes"] = causes
	if not effects.is_empty():
		out["effects"] = effects.duplicate(true)
	if visibility != Visibility.SETTLEMENT:
		out["vis"] = visibility
	if text_key != "":
		out["text"] = text_key
	if not text_params.is_empty():
		out["params"] = text_params.duplicate(true)
	if not tags.is_empty():
		out["tags"] = tags
	if count != 1:
		out["count"] = count
	return out


## Null if the record is unusable.
static func from_dict(data: Dictionary) -> WorldEvent:
	if typeof(data.get("id")) != TYPE_INT or int(data["id"]) <= 0 or str(data.get("type", "")) == "" \
			or typeof(data.get("tick")) != TYPE_INT:
		return null
	var event := WorldEvent.new()
	event.id = int(data["id"])
	event.type = StringName(str(data["type"]))
	event.tick = int(data["tick"])
	event.last_tick = int(data["last"]) if typeof(data.get("last")) == TYPE_INT else event.tick
	if typeof(data.get("at")) == TYPE_VECTOR2 and (data["at"] as Vector2).is_finite():
		event.position = data["at"]
	event.region_id = int(data.get("region", 0)) if typeof(data.get("region", 0)) == TYPE_INT else 0
	event.settlement_id = int(data.get("settlement", 0)) if typeof(data.get("settlement", 0)) == TYPE_INT else 0
	event.participants = _ids(data.get("who"))
	event.causes = _ids(data.get("causes"))
	if typeof(data.get("effects")) == TYPE_DICTIONARY:
		event.effects = (data["effects"] as Dictionary).duplicate(true)
	var sig: Variant = data.get("sig", 0.0)
	event.significance = clampf(float(sig), 0.0, 1.0) if typeof(sig) == TYPE_FLOAT or typeof(sig) == TYPE_INT else 0.0
	var vis: Variant = data.get("vis", Visibility.SETTLEMENT)
	event.visibility = clampi(int(vis), 0, Visibility.size() - 1) as Visibility if typeof(vis) == TYPE_INT else Visibility.SETTLEMENT
	event.text_key = str(data.get("text", ""))
	if typeof(data.get("params")) == TYPE_DICTIONARY:
		event.text_params = (data["params"] as Dictionary).duplicate(true)
	var tags_saved: Variant = data.get("tags")
	if typeof(tags_saved) == TYPE_PACKED_STRING_ARRAY:
		event.tags = tags_saved
	elif typeof(tags_saved) == TYPE_ARRAY:
		for tag: Variant in tags_saved:
			event.tags.append(str(tag))
	event.count = maxi(int(data.get("count", 1)), 1) if typeof(data.get("count", 1)) == TYPE_INT else 1
	return event


## Ids from saved data (a packed array, or a plain one): whole numbers above 0.
static func _ids(value: Variant) -> PackedInt64Array:
	var out := PackedInt64Array()
	if typeof(value) == TYPE_PACKED_INT64_ARRAY or typeof(value) == TYPE_PACKED_INT32_ARRAY or typeof(value) == TYPE_ARRAY:
		for id: Variant in value:
			if typeof(id) == TYPE_INT and int(id) > 0 and not out.has(int(id)):
				out.append(int(id))
	return out
