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

# The weights above as arrays of indices and values (made on first use:
# scoring runs for every activity at every decision).
var _compiled := false
var _need_index := PackedInt32Array()
var _need_weight := PackedFloat32Array()
var _trait_axis := PackedInt32Array()
var _trait_weight := PackedFloat32Array()
var _id_text := ""
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
## of the score. For the reason behind a decision.
func need_parts(needs: PackedFloat32Array) -> Dictionary:
	_compile()
	var parts := {}
	for i in _need_index.size():
		parts[_need_index[i]] = _need_weight[i] * voice(Needs.urgency(needs, _need_index[i]))
	return parts


## The sum of need_parts() (without making a Dictionary).
func need_total(needs: PackedFloat32Array) -> float:
	_compile()
	var total := 0.0
	for i in _need_index.size():
		total += _need_weight[i] * voice(Needs.urgency(needs, _need_index[i]))
	return total


## The same sum from the needs' voices, worked out once by the caller (see
## voices()): scoring eight activities asks for the same six voices.
func need_total_from(spoken: PackedFloat32Array) -> float:
	_compile()
	var total := 0.0
	for i in _need_index.size():
		total += _need_weight[i] * spoken[_need_index[i]]
	return total


## How loudly each need of `needs` speaks (one value per Needs.Need).
static func voices(needs: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(Needs.COUNT)
	for need in Needs.COUNT:
		out[need] = voice(1.0 - needs[need]) if need < needs.size() else 0.0
	return out


## The id as a String (the key of PersonData.activity_log).
func id_text() -> String:
	_compile()
	return _id_text


## Call after changing the weights of a definition that has been used.
func recompile() -> void:
	_compiled = false


func _compile() -> void:
	if _compiled:
		return
	_compiled = true
	_id_text = String(id)
	_need_index = PackedInt32Array()
	_need_weight = PackedFloat32Array()
	for need_name: Variant in need_weights:
		var need := Needs.index_of(StringName(str(need_name)))
		if need >= 0:
			_need_index.append(need)
			_need_weight.append(float(need_weights[need_name]))
	_trait_axis = PackedInt32Array()
	_trait_weight = PackedFloat32Array()
	for axis_name: Variant in trait_weights:
		var axis: int = Traits.Axis.get(str(axis_name), -1)
		if axis >= 0:
			_trait_axis.append(axis)
			_trait_weight.append(float(trait_weights[axis_name]))


## How loudly a need of `urgency` (0 … 1) speaks: 0 … 1.
static func voice(urgency: float) -> float:
	var heard := clampf((urgency - QUIET_BELOW) / (1.0 - QUIET_BELOW), 0.0, 1.0)
	return heard * heard


func trait_part(traits: PackedFloat32Array) -> float:
	_compile()
	var total := 0.0
	for i in _trait_axis.size():
		var axis := _trait_axis[i]
		var lean := Traits.value(traits, axis)
		if axis >= Traits.FIRST_AMOUNT:
			lean = lean * 2.0 - 1.0
		total += lean * _trait_weight[i] * TRAIT_SCALE
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
