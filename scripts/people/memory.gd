class_name Memory
extends RefCounted
## Something a person remembers (bible §15.2): what happened, where and when,
## what they made of it and how it felt, how much it matters to them, and how
## they came by it — by living it, by seeing it, or by being told.
##
## Plain data, kept in the MemoryStore; a person holds the ids of theirs.

enum OwnerKind { PERSON, FAMILY, CULTURE }
## How the owner came by it. (Saved by number: append, never reorder.)
enum Source { DIRECT, WITNESSED, TOLD, INHERITED, TAUGHT, WRITTEN }

## Kinds of memory (what the texts are keyed by, with `subject`).
const KIND_EXPERIENCE := &"experience"
## Something hard that was lived through (going hungry): no doing of the
## player's, nothing to be interpreted — but remembered, and talked about.
const KIND_HARDSHIP := &"hardship"
## A moment of one's own life (a child born, a partner found, a flood lived
## through, someone lost: M10–M11): remembered, but not news to tell, nor a
## story for bedtime.
const KIND_LIFE := &"life"

var id := 0
var owner_kind: OwnerKind = OwnerKind.PERSON
var owner_id := 0
var kind: StringName = KIND_EXPERIENCE
## What it was about: a stimulus type ("touch", "object_moved", ...).
var subject: StringName = &""
## The stimulus it came from (0 if none, or long gone).
var stimulus_id := 0
var event_id := 0
## When it happened — the last time, if it happened more than once.
var tick := 0
## When it first happened.
var first_tick := 0
## Where (world X/Z).
var location := Vector2.ZERO
## What the owner made of it (ReactionTable interpretation).
var interpretation: StringName = &""
## What they felt: one value per ReactionTable.Emotion.
var emotions := PackedFloat32Array()
## How strong it was (0 … 1).
var intensity := 0.0
## How much it matters to them (0 … 1): what fades and what is kept.
var importance := 0.0
var source: Source = Source.DIRECT
## Who told them (for Source.TOLD), 0 otherwise.
var told_by := 0
## How true to what happened: 1 for what one lived, less with every retelling.
var fidelity := 1.0
## How many times it has happened (the same thing, taken the same way).
var count := 1
## The owner's stage of life when it (last) happened.
var stage: PersonData.LifeStage = PersonData.LifeStage.ADULT
## The tick the owner last told someone of it (-1 = never).
var told_tick := -1
## The text template and what goes into it (see MemoryText).
var text_key := ""
var text_params: Dictionary = {}


## How it felt, in one of the five (0 if they felt nothing of the sort).
func emotion(which: int) -> float:
	return emotions[which] if which >= 0 and which < emotions.size() else 0.0


## Is this the same thing again as `other` (to be remembered as one)?
func same_as(other: Memory) -> bool:
	return owner_kind == other.owner_kind and owner_id == other.owner_id and kind == other.kind \
		and subject == other.subject and interpretation == other.interpretation \
		and (source == Source.TOLD) == (other.source == Source.TOLD) \
		and (source == Source.INHERITED) == (other.source == Source.INHERITED)


## What is at its default is left out (a memory is saved thousands of times
## over the years: every byte counts); from_dict() puts the defaults back.
func to_dict() -> Dictionary:
	var out := {
		"id": id, "owner_id": owner_id, "subject": String(subject), "tick": tick, "location": location,
		"interpretation": String(interpretation), "emotions": emotions.duplicate(), "intensity": intensity,
		"importance": importance, "source": source, "fidelity": fidelity, "stage": stage, "text_key": text_key,
	}
	if owner_kind != OwnerKind.PERSON:
		out["owner_kind"] = owner_kind
	if kind != KIND_EXPERIENCE:
		out["kind"] = String(kind)
	if stimulus_id != 0:
		out["stimulus_id"] = stimulus_id
	if event_id != 0:
		out["event_id"] = event_id
	if first_tick != tick:
		out["first_tick"] = first_tick
	if told_by != 0:
		out["told_by"] = told_by
	if count != 1:
		out["count"] = count
	if told_tick != -1:
		out["told_tick"] = told_tick
	if not text_params.is_empty():
		out["text_params"] = text_params.duplicate(true)
	return out


## Null if the record is unusable.
static func from_dict(data: Dictionary) -> Memory:
	if typeof(data.get("id")) != TYPE_INT or int(data["id"]) <= 0 or typeof(data.get("owner_id")) != TYPE_INT:
		return null
	var memory := Memory.new()
	memory.id = data["id"]
	memory.owner_kind = clampi(int(data.get("owner_kind", 0)), 0, OwnerKind.size() - 1) as OwnerKind
	memory.owner_id = data["owner_id"]
	memory.kind = StringName(str(data.get("kind", KIND_EXPERIENCE)))
	memory.subject = StringName(str(data.get("subject", "")))
	memory.stimulus_id = int(data.get("stimulus_id", 0))
	memory.event_id = int(data.get("event_id", 0))
	memory.tick = int(data.get("tick", 0))
	memory.first_tick = int(data.get("first_tick", memory.tick))
	var where: Variant = data.get("location")
	if typeof(where) == TYPE_VECTOR2 and is_finite((where as Vector2).x) and is_finite((where as Vector2).y):
		memory.location = where
	memory.interpretation = StringName(str(data.get("interpretation", "")))
	var felt: Variant = data.get("emotions")
	memory.emotions = PackedFloat32Array()
	memory.emotions.resize(ReactionTable.EMOTION_COUNT)
	if typeof(felt) == TYPE_PACKED_FLOAT32_ARRAY:
		for i in mini((felt as PackedFloat32Array).size(), ReactionTable.EMOTION_COUNT):
			memory.emotions[i] = _unit(felt[i])
	memory.intensity = _unit(data.get("intensity", 0.0))
	memory.importance = _unit(data.get("importance", 0.0))
	memory.source = clampi(int(data.get("source", 0)), 0, Source.size() - 1) as Source
	memory.told_by = int(data.get("told_by", 0))
	memory.fidelity = _unit(data.get("fidelity", 1.0))
	memory.count = maxi(int(data.get("count", 1)), 1)
	memory.stage = clampi(int(data.get("stage", PersonData.LifeStage.ADULT)), 0, PersonData.LifeStage.size() - 1) as PersonData.LifeStage
	memory.told_tick = int(data.get("told_tick", -1))
	memory.text_key = str(data.get("text_key", ""))
	var params: Variant = data.get("text_params")
	if typeof(params) == TYPE_DICTIONARY:
		memory.text_params = (params as Dictionary).duplicate(true)
	return memory


static func _unit(value: Variant) -> float:
	var number := float(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else 0.0
	return clampf(number, 0.0, 1.0) if is_finite(number) else 0.0
