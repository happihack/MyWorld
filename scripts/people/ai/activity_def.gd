class_name ActivityDef
extends Resource
## Something a person can decide to do (bible §13.4): how much each need,
## trait and time of day speaks for it. One file per activity in
## res://data/activities/; the Brain scores them, the Planner turns the
## chosen one into steps.

## Stable id (saved with people; the Planner knows how to plan it).
@export var id: StringName = &""
## What speaks for it when nothing else does.
@export_range(0.0, 2.0, 0.01) var base: float = 0.0
## Needs it answers: Needs name ("hunger", ...) -> weight. A need says
## nothing while it is mostly met (nobody eats because they could), and then
## counts with the square of its urgency: pressing needs shout.
@export var need_weights: Dictionary = {}
## Traits that draw people to it: Traits.Axis name -> weight (negative = the
## opposite end of the axis).
@export var trait_weights: Dictionary = {}
## How fitting it is at each hour of the day (24 factors, hour 0 first; values
## in between are interpolated). Empty = any time. Routines are soft (§13.5):
## a factor, never a rule.
@export var hours: PackedFloat32Array = PackedFloat32Array()
## What must be there for it to be possible: "home", "food", "water", "work",
## "company".
@export var requires: Array[StringName] = []
## Stages of life that do it (empty = everyone).
@export var life_stages: Array[PersonData.LifeStage] = []
## Having just done it speaks against doing it again for this long (game
## minutes; 0 = no such thing).
@export_range(0.0, 2880.0, 5.0) var repeat_after_minutes: float = 0.0

## How much one point on a trait axis is worth, relative to needs.
const TRAIT_SCALE := 0.12
## A need less urgent than this says nothing at all.
const QUIET_BELOW := 0.25


func allows(stage: PersonData.LifeStage) -> bool:
	return life_stages.is_empty() or life_stages.has(stage)


## The factor for a time of day (`hour` 0 … 24, fractions allowed).
func hour_factor(hour: float) -> float:
	if hours.size() != 24:
		return 1.0
	var h := fposmod(hour, 24.0)
	var from := int(h)
	return lerpf(hours[from], hours[(from + 1) % 24], h - from)


## What the needs say (before the time of day): Dictionary need index -> part
## of the score. Used for the score and for the reason.
func need_parts(needs: PackedFloat32Array) -> Dictionary:
	var parts := {}
	for need_name: Variant in need_weights:
		var need := Needs.index_of(StringName(str(need_name)))
		if need >= 0:
			parts[need] = float(need_weights[need_name]) * voice(Needs.urgency(needs, need))
	return parts


## How loudly a need of `urgency` (0 … 1) speaks: 0 … 1.
static func voice(urgency: float) -> float:
	var heard := clampf((urgency - QUIET_BELOW) / (1.0 - QUIET_BELOW), 0.0, 1.0)
	return heard * heard


func trait_part(traits: PackedFloat32Array) -> float:
	var total := 0.0
	for axis_name: Variant in trait_weights:
		var axis: int = Traits.Axis.get(str(axis_name), -1)
		if axis < 0:
			continue
		var lean := Traits.value(traits, axis)
		if Traits.is_amount(axis):
			lean = lean * 2.0 - 1.0
		total += lean * float(trait_weights[axis_name]) * TRAIT_SCALE
	return total


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("activity has no id")
	if not hours.is_empty() and hours.size() != 24:
		problems.append("%s: hours needs 24 values (has %d)" % [id, hours.size()])
	for need_name: Variant in need_weights:
		if Needs.index_of(StringName(str(need_name))) < 0:
			problems.append("%s: unknown need '%s'" % [id, need_name])
	for axis_name: Variant in trait_weights:
		if not Traits.Axis.has(str(axis_name)):
			problems.append("%s: unknown trait axis '%s'" % [id, axis_name])
	return problems
