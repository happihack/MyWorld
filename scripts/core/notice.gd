class_name Notice
extends RefCounted
## Something the player is told as it happens (bible §26.7): a line of text
## about a world event, and where to look.

var id := 0
## The event it tells of (0 = none: a notice made by hand).
var event_id := 0
## What kind of thing it is (an event type): notices of one kind coming
## close together are one.
var kind: StringName = &""
var text := ""
## Where it happened (world X/Z); Vector2.INF = nowhere to show.
var position := Vector2.INF
## How much it matters, 0 … 1.
var priority := 0.0
## How many times it has happened since it was first told.
var count := 1
## When it was offered, and when it was shown (real milliseconds; -1 = not yet).
var offered_msec := 0
var shown_msec := -1

## Milestones (owner: discoveries should grab the eye, and be read): a discovery,
## a new age, a step in understanding the box. Their toast is framed in gold, and
## a card tells of them (MilestoneCard); none is merged, filtered or dropped.
const MILESTONES: Array[StringName] = [&"knowledge_learned", &"era_entered", &"box_research"]


func can_locate() -> bool:
	return position != Vector2.INF


func is_shown() -> bool:
	return shown_msec >= 0


func is_milestone() -> bool:
	return MILESTONES.has(kind)
