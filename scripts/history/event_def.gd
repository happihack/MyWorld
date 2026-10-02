class_name EventDef
extends Resource
## A kind of world event (bible §21.1): how much it matters, who knows of
## it, and how it is told. Defined in res://data/events/*.tres; found
## through EventLibrary.

@export var id: StringName = &""
## How much such an event matters, 0 … 1 (what is kept, told, announced).
@export_range(0.0, 1.0, 0.01) var significance: float = 0.3
## The first of its kind matters this much (0 = no more than the others).
@export_range(0.0, 1.0, 0.01) var first_significance: float = 0.0
## What tells kinds apart for "the first": the name of one of the event's
## parameters ("resource": the first meat and the first grain are both
## firsts). Empty: the first event of this type.
@export var first_by: String = ""
@export var visibility: WorldEvent.Visibility = WorldEvent.Visibility.SETTLEMENT
## The same thing happening again within this many game minutes, for the
## same reasons, is one event that happened several times (0 = never).
@export_range(0, 100000) var merge_minutes: int = 0
## ...if these parameters are the same too.
@export var merge_by: PackedStringArray = PackedStringArray()
@export var tags: PackedStringArray = PackedStringArray()
## The text template (see EventText); empty = "EVENT_<ID>".
@export var text_key: String = ""
## May the player be told of it as it happens (if it matters enough)?
@export var toast: bool = true


func key_for_text() -> String:
	return text_key if text_key != "" else "EVENT_" + String(id).to_upper()


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("an event without an id")
	if first_significance > 0.0 and first_significance < significance:
		problems.append("%s: the first of a kind cannot matter less than the others" % id)
	return problems
