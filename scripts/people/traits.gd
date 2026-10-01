class_name Traits
extends RefCounted
## Personality as numbers (bible §13.2): one value per axis.
##
## The first nine axes are bipolar, -1 … +1 (CURIOSITY -1 is cautious, +1 is
## curious). The last three are amounts, 0 … 1. A person's traits are a
## PackedFloat32Array of COUNT values, indexed by Axis.
##
## The axis order is part of the save format: append new axes, never reorder.

enum Axis {
	CURIOSITY,    ## cautious ↔ curious
	BRAVERY,      ## fearful ↔ brave
	GENEROSITY,   ## selfish ↔ generous
	SOCIABILITY,  ## introverted ↔ social
	AMBITION,     ## lazy ↔ ambitious
	SPIRITUALITY, ## skeptical ↔ spiritual
	AGGRESSION,   ## peaceful ↔ aggressive
	SUSPICION,    ## trusting ↔ suspicious
	ADVENTURE,    ## homebound ↔ adventurous
	INTELLIGENCE, ## 0 … 1
	CREATIVITY,   ## 0 … 1
	LOYALTY,      ## 0 … 1
}

const COUNT := 12
## Axes from here on are amounts (0 … 1), not opposites.
const FIRST_AMOUNT := Axis.INTELLIGENCE

## Word ids for the two ends of each axis (wording lives in UIText). Amounts
## have a word for "much" only: nobody is described by what they lack.
const LOW_WORDS: Array[StringName] = [
	&"cautious", &"fearful", &"selfish", &"introverted", &"lazy", &"skeptical",
	&"peaceful", &"trusting", &"homebound", &"", &"", &"",
]
const HIGH_WORDS: Array[StringName] = [
	&"curious", &"brave", &"generous", &"social", &"ambitious", &"spiritual",
	&"aggressive", &"suspicious", &"adventurous", &"intelligent", &"creative", &"loyal",
]

## A trait weaker than this is not worth a word.
const NOTABLE := 0.3
## How far generated traits spread: most people are middling in most things,
## and nearly everyone stands out in something.
const SPREAD := 1.6
## How far a child's trait may fall from the mean of its parents (wide enough
## that families do not all drift to the middle over the generations).
const INHERIT_NOISE := 1.0


static func is_amount(axis: int) -> bool:
	return axis >= FIRST_AMOUNT


## The traits of someone unremarkable in every way.
static func neutral() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)
	for axis in COUNT:
		out[axis] = 0.5 if is_amount(axis) else 0.0
	return out


## Random traits for a new person (use the world's "people" stream).
static func generate(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)
	for axis in COUNT:
		out[axis] = _from_lean(axis, _bell(rng) * SPREAD)
	return out


## A child's traits: between its parents, with a will of its own (bible §13.2).
static func inherit(mother: PackedFloat32Array, father: PackedFloat32Array, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var a := sanitized(mother)
	var b := sanitized(father)
	var out := PackedFloat32Array()
	out.resize(COUNT)
	for axis in COUNT:
		var mean := (_lean(axis, a[axis]) + _lean(axis, b[axis])) * 0.5
		out[axis] = _from_lean(axis, mean + _bell(rng) * INHERIT_NOISE)
	return out


## Any array made safe to use: COUNT values, each within its axis's range.
static func sanitized(values: PackedFloat32Array) -> PackedFloat32Array:
	var out := neutral()
	for axis in mini(values.size(), COUNT):
		var value := values[axis]
		if is_finite(value):
			out[axis] = clampf(value, 0.0, 1.0) if is_amount(axis) else clampf(value, -1.0, 1.0)
	return out


static func value(traits: PackedFloat32Array, axis: int) -> float:
	if axis < 0 or axis >= traits.size():
		return 0.5 if is_amount(axis) else 0.0
	return traits[axis]


## How much a trait stands out, 0 … 1 (for amounts: only having much counts).
static func strength(traits: PackedFloat32Array, axis: int) -> float:
	var v := value(traits, axis)
	return maxf((v - 0.5) * 2.0, 0.0) if is_amount(axis) else absf(v)


## The word id for where a person stands on an axis ("" if not worth a word).
static func word(traits: PackedFloat32Array, axis: int) -> StringName:
	if axis < 0 or axis >= COUNT or strength(traits, axis) < NOTABLE:
		return &""
	if is_amount(axis) or value(traits, axis) > 0.0:
		return HIGH_WORDS[axis]
	return LOW_WORDS[axis]


## Word ids for a person's `n` most pronounced traits, strongest first. Fewer
## (or none) if they are not that pronounced.
static func describe_top(traits: PackedFloat32Array, n: int = 3) -> PackedStringArray:
	var axes: Array[int] = []
	for axis in COUNT:
		if strength(traits, axis) >= NOTABLE:
			axes.append(axis)
	axes.sort_custom(func(a: int, b: int) -> bool:
		var sa := strength(traits, a)
		var sb := strength(traits, b)
		return sa > sb or (sa == sb and a < b))
	var out := PackedStringArray()
	for axis in axes:
		if out.size() >= n:
			break
		out.append(String(word(traits, axis)))
	return out


## -1 … +1, bell-shaped around 0.
static func _bell(rng: RandomNumberGenerator) -> float:
	return (rng.randf() + rng.randf() + rng.randf()) * (2.0 / 3.0) - 1.0


# Amounts are stored 0 … 1 but generated and inherited like the other axes.
static func _lean(axis: int, stored: float) -> float:
	return stored * 2.0 - 1.0 if is_amount(axis) else stored


static func _from_lean(axis: int, lean: float) -> float:
	var clamped := clampf(lean, -1.0, 1.0)
	return (clamped + 1.0) * 0.5 if is_amount(axis) else clamped
