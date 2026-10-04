class_name Needs
extends RefCounted
## What people need (bible §13.3). A person's needs are a PackedFloat32Array
## with one value per Need: **how well it is met**, 1 = fully, 0 = not at all.
## Needs run down with time (and faster with work); doing the right thing
## fills them again. How urgent a need is — what drives decisions — is
## 1 - value.
##
## The order is part of the save format: append new needs, never reorder.
## (The later needs of §13.3 — warmth, family, curiosity, wealth, status,
## spiritual fulfilment — join as the systems that feed them arrive.)

enum Need { HUNGER, THIRST, SLEEP, SOCIAL, PURPOSE, SAFETY }

const COUNT := 6
const NAMES: Array[StringName] = [&"hunger", &"thirst", &"sleep", &"social", &"purpose", &"safety"]
## A need at or below this is pressing (stress, and a reason to drop other things).
const PRESSING := 0.25

## What someone is doing, as far as their needs are concerned.
enum State { AWAKE, WORKING, SLEEPING }


## Everything met.
static func full() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)
	out.fill(1.0)
	return out


## Needs of someone new to the world: mostly met, each a little differently
## (so that a band does not get hungry all at once).
static func initial(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := full()
	out[Need.HUNGER] = rng.randf_range(0.5, 0.95)
	out[Need.THIRST] = rng.randf_range(0.5, 0.95)
	out[Need.SLEEP] = rng.randf_range(0.9, 1.0) # (a new world opens in the morning: they have slept)
	out[Need.SOCIAL] = rng.randf_range(0.5, 0.95)
	out[Need.PURPOSE] = rng.randf_range(0.4, 0.9)
	return out


## Any array made safe to use: COUNT values within 0 … 1. Values that are
## missing (a person saved before needs existed) are set from `seed_value`,
## the same every time.
static func sanitized(values: PackedFloat32Array, seed_value: int = 0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(COUNT)
	for need in COUNT:
		if need < values.size() and is_finite(values[need]):
			out[need] = clampf(values[need], 0.0, 1.0)
		elif need == Need.SAFETY:
			out[need] = 1.0
		else:
			out[need] = 0.55 + float((seed_value * 2654435761 + need * 40503) & 0xFF) / 255.0 * 0.4
	return out


static func index_of(need_name: StringName) -> int:
	return NAMES.find(need_name)


static func value(needs: PackedFloat32Array, need: int) -> float:
	return needs[need] if need >= 0 and need < needs.size() else 1.0


## 0 = met … 1 = desperate.
static func urgency(needs: PackedFloat32Array, need: int) -> float:
	return 1.0 - value(needs, need)


## Fills a need by `amount` (never past 1).
static func satisfy(needs: PackedFloat32Array, need: int, amount: float) -> void:
	if need >= 0 and need < needs.size():
		needs[need] = clampf(needs[need] + amount, 0.0, 1.0)


## The need that is least met.
static func most_urgent(needs: PackedFloat32Array) -> int:
	var worst := 0
	for need in mini(needs.size(), COUNT):
		if needs[need] < needs[worst]:
			worst = need
	return worst


## Lets `minutes` of game time pass for a person's needs.
static func decay(person: PersonData, minutes: float, config: NeedsConfig, stage: PersonData.LifeStage,
		state: State = State.AWAKE) -> void:
	decay_by(person, minutes, config, factors(person, config, stage), state)


## What a person's needs run down by, apart from the minutes and what they
## are doing: [body, missing company, missing purpose] (worked out once a day
## by the behaviour system: they change only with age).
static func factors(person: PersonData, config: NeedsConfig, stage: PersonData.LifeStage) -> PackedFloat32Array:
	return PackedFloat32Array([config.body_factor(stage),
		1.0 + 0.5 * Traits.value(person.traits, Traits.Axis.SOCIABILITY),
		1.0 + 0.5 * Traits.value(person.traits, Traits.Axis.AMBITION)])


## `decay`, with the person's factors (see `factors`) given.
static func decay_by(person: PersonData, minutes: float, config: NeedsConfig, factor: PackedFloat32Array,
		state: State = State.AWAKE) -> void:
	var needs := person.needs
	if needs.size() < COUNT or minutes <= 0.0:
		return
	var body := factor[0]
	var effort := config.working_factor if state == State.WORKING else (config.sleeping_factor if state == State.SLEEPING else 1.0)
	needs[Need.HUNGER] = maxf(needs[Need.HUNGER] - config.hunger_per_minute * body * effort * minutes, 0.0)
	needs[Need.THIRST] = maxf(needs[Need.THIRST] - config.thirst_per_minute * effort * minutes, 0.0)
	if state != State.SLEEPING:
		needs[Need.SLEEP] = maxf(needs[Need.SLEEP] - config.sleep_per_minute * body
			* (config.working_factor if state == State.WORKING else 1.0) * minutes, 0.0)
		# Company is missed more by the sociable, purpose more by the ambitious.
		needs[Need.SOCIAL] = maxf(needs[Need.SOCIAL] - config.social_per_minute * factor[1] * minutes, 0.0)
		if state != State.WORKING:
			needs[Need.PURPOSE] = maxf(needs[Need.PURPOSE] - config.purpose_per_minute * factor[2] * minutes, 0.0)
	# Nothing threatens anyone yet (M5 on): the feeling of safety comes back.
	needs[Need.SAFETY] = minf(needs[Need.SAFETY] + config.safety_recovery_per_minute * minutes, 1.0)


## How someone feels, 0 … 1: the average of their needs, pulled down by the worst.
static func mood(needs: PackedFloat32Array) -> float:
	if needs.size() < COUNT:
		return 0.5
	var total := 0.0
	var worst := 1.0
	for need in COUNT:
		total += needs[need]
		worst = minf(worst, needs[need])
	return clampf(total / COUNT * 0.7 + worst * 0.3, 0.0, 1.0)


## 0 = at ease … 1 = at the end of their tether: how far the worst need is
## below "pressing".
static func stress(needs: PackedFloat32Array) -> float:
	if needs.size() < COUNT:
		return 0.0
	var worst := 1.0
	for need in COUNT:
		worst = minf(worst, needs[need])
	return clampf((PRESSING * 2.0 - worst) / (PRESSING * 2.0), 0.0, 1.0)
