class_name Relationship
extends RefCounted
## What two people are to each other (bible §16.1): one record for the pair,
## the same seen from either side. How well they know each other, how they
## feel about each other, how far they trust and respect each other — and
## what that makes them (acquaintances, friends, rivals, enemies). Ties of
## blood and marriage are not kept here: they are on the people themselves
## (parents, children, partner) and asked for through RelationshipStore.kinds.

## Kinds of tie (bits). The social ones are kept on the record; the family
## ones are worked out from the people (see RelationshipStore.kinds).
## Part of the save format: append, never reorder.
enum Kind {
	ACQUAINTANCE = 1 << 0,
	FRIEND = 1 << 1,
	RIVAL = 1 << 2,
	ENEMY = 1 << 3,
	PARTNER = 1 << 4,
	SPOUSE = 1 << 5,
	PARENT = 1 << 6,
	CHILD = 1 << 7,
	SIBLING = 1 << 8,
	EMPLOYER = 1 << 9,
	EMPLOYEE = 1 << 10,
	LEADER = 1 << 11,
	FOLLOWER = 1 << 12,
}
## The kinds kept on the record (what they have made of each other).
const SOCIAL := Kind.ACQUAINTANCE | Kind.FRIEND | Kind.RIVAL | Kind.ENEMY
## Notable shared moments remembered on the record (event ids), at most.
const HISTORY := 4

## How well they know each other, 0 … 1.
var familiarity := 0.0
## How they feel about each other, −1 … +1.
var affinity := 0.0
## How far they trust each other, and how much they look up to each other, −1 … +1.
var trust := 0.0
var respect := 0.0
## How drawn they are to each other, 0 … 1 (the beginning of a partnership: M10.2).
var romance := 0.0
## Kind bits (the social ones).
var kinds := 0
var last_tick := 0
## The latest notable events they shared (oldest first).
var history := PackedInt64Array()


func has_kind(kind: int) -> bool:
	return (kinds & kind) != 0


func note_event(event_id: int) -> void:
	if event_id <= 0 or history.has(event_id):
		return
	history.append(event_id)
	while history.size() > HISTORY:
		history.remove_at(0)


## How much the pair is worth keeping, compared with others (the weakest
## are forgotten first when someone knows too many).
func weight() -> float:
	return familiarity + absf(affinity) + 0.5 * romance + 0.2 * history.size()


func to_dict() -> Dictionary:
	return {"familiarity": familiarity, "affinity": affinity, "trust": trust, "respect": respect, "romance": romance,
		"kinds": kinds, "last": last_tick, "history": history.duplicate()}


## Null if the record is unusable.
static func from_dict(data: Dictionary) -> Relationship:
	var record := Relationship.new()
	for key: String in ["familiarity", "affinity", "trust", "respect", "romance"]:
		var value: Variant = data.get(key, 0.0)
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return null
		if not is_finite(float(value)):
			return null
	record.familiarity = clampf(float(data.get("familiarity", 0.0)), 0.0, 1.0)
	record.affinity = clampf(float(data.get("affinity", 0.0)), -1.0, 1.0)
	record.trust = clampf(float(data.get("trust", 0.0)), -1.0, 1.0)
	record.respect = clampf(float(data.get("respect", 0.0)), -1.0, 1.0)
	record.romance = clampf(float(data.get("romance", 0.0)), 0.0, 1.0)
	record.kinds = int(data.get("kinds", 0)) & SOCIAL if typeof(data.get("kinds", 0)) == TYPE_INT else 0
	record.last_tick = int(data["last"]) if typeof(data.get("last")) == TYPE_INT else 0
	var saved: Variant = data.get("history")
	if typeof(saved) == TYPE_PACKED_INT64_ARRAY:
		for id in saved as PackedInt64Array:
			record.note_event(id)
	return record
