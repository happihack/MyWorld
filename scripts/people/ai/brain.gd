class_name Brain
extends RefCounted
## Decides what a person does next (bible §13.4): every activity is scored by
## what their needs, their nature and the hour say for it, and one of the best
## is chosen — by weighted dice, never simply the top one and never blindly
## (§13.2 "controlled randomness"). Someone already doing something keeps at
## it unless something else is clearly more pressing (no flip-flopping).

## Only the best few are in the draw.
const TOP_CANDIDATES := 3
## How much better something else must be before one drops what one is doing.
const HYSTERESIS := 0.25
## How even the draw is: predictable people … creative people.
const TEMPERATURE_MIN := 0.04
const TEMPERATURE_MAX := 0.11
## Having just done something counts against it by up to this much.
const REPEAT_PENALTY := 0.3
## What speaks for something less than this is not worth doing (unless
## nothing else is).
const WORTH_DOING := 0.03


class Decision:
	extends RefCounted
	var activity: StringName = &""
	## Why: the need that spoke loudest for it ("hunger", ...), or &"routine"
	## (the hour, habit) or &"nature" (their traits).
	var reason: StringName = &"routine"
	## Every activity's score (id -> float), -1 for what is not possible. For
	## the inspector.
	var scores: Dictionary = {}

	func score_of(id: StringName) -> float:
		return scores.get(id, -1.0)


## How much speaks for `def` for this person right now; -1 if it is not
## possible for them at all.
static func score(def: ActivityDef, person: PersonData, ctx: AiContext) -> float:
	return _score(def, person, ctx, ctx.stage_of(person), ctx.clock.hour() if ctx.clock != null else 12.0,
		ActivityDef.voices(person.needs), {})


# (The stage of life, the hour, how loudly each need speaks and what is there
# for the person are the same for every activity of one decision: worked out
# once by the caller. `met` remembers the requirements already asked about.)
static func _score(def: ActivityDef, person: PersonData, ctx: AiContext, stage: PersonData.LifeStage, hour: float,
		spoken: PackedFloat32Array, met: Dictionary) -> float:
	if not def.allows(stage):
		return -1.0
	for requirement in def.requires:
		var there: Variant = met.get(requirement)
		if there == null:
			there = Planner.can(requirement, person, ctx)
			met[requirement] = there
		if not there:
			return -1.0
	var total := (def.base + def.trait_part(person.traits) + def.need_total_from(spoken)) * def.hour_factor(hour)
	if def.repeat_after_minutes > 0.0 and person.activity_log.has(def.id_text()):
		var since := float(ctx.now() - int(person.activity_log[def.id_text()]))
		total -= REPEAT_PENALTY * clampf(1.0 - since / def.repeat_after_minutes, 0.0, 1.0)
	return maxf(total, 0.0)


## Chooses. `current` is what the person is doing now (&"" = nothing): it is
## kept unless something beats it by HYSTERESIS — it, or `commitment`, the
## score it was begun with, whichever is higher: a meal does not become less
## worth finishing because the first bites took the edge off the hunger.
## `barred` (a set of ids) is what just turned out not to be possible.
static func decide(person: PersonData, ctx: AiContext, current: StringName = &"", barred: Dictionary = {},
		commitment: float = 0.0) -> Decision:
	var decision := Decision.new()
	var ids: Array[StringName] = []
	var values := PackedFloat32Array()
	var stage := ctx.stage_of(person)
	var hour := ctx.clock.hour() if ctx.clock != null else 12.0
	var spoken := ActivityDef.voices(person.needs)
	var met := {}
	for id in ctx.activities.ids():
		var value := -1.0 if barred.has(id) else _score(ctx.activities.get_def(id), person, ctx, stage, hour, spoken, met)
		decision.scores[id] = value
		if value >= 0.0:
			ids.append(id)
			values.append(value)
	if ids.is_empty():
		return decision
	# Only what is worth doing is in the draw — if anything is.
	var worth_ids: Array[StringName] = []
	var worth := PackedFloat32Array()
	for i in ids.size():
		if values[i] >= WORTH_DOING:
			worth_ids.append(ids[i])
			worth.append(values[i])
	if not worth_ids.is_empty():
		ids = worth_ids
		values = worth
	if current != &"" and decision.score_of(current) >= 0.0:
		# Busy: only what is clearly more pressing is worth dropping it for.
		var bar := maxf(decision.score_of(current), commitment) + HYSTERESIS
		var kept_ids: Array[StringName] = []
		var kept := PackedFloat32Array()
		for i in ids.size():
			if ids[i] != current and values[i] > bar:
				kept_ids.append(ids[i])
				kept.append(values[i])
		if kept_ids.is_empty():
			decision.activity = current
			decision.reason = reason_for(ctx.activities.get_def(current), person)
			return decision
		ids = kept_ids
		values = kept
	decision.activity = _draw(ids, values, temperature(person), ctx.rng)
	decision.reason = reason_for(ctx.activities.get_def(decision.activity), person)
	return decision


## How unpredictable a person is: the creative more than the plain.
static func temperature(person: PersonData) -> float:
	return lerpf(TEMPERATURE_MIN, TEMPERATURE_MAX, Traits.value(person.traits, Traits.Axis.CREATIVITY))


## Why this, for this person: the need that speaks loudest for it, if any
## speaks louder than habit and nature.
static func reason_for(def: ActivityDef, person: PersonData) -> StringName:
	var parts := def.need_parts(person.needs)
	var loudest := -1
	var loudness := 0.0
	for need: int in parts:
		if float(parts[need]) > loudness:
			loudness = parts[need]
			loudest = need
	var nature := def.trait_part(person.traits)
	if loudest >= 0 and loudness >= maxf(def.base, nature) * 0.5 and loudness > 0.02:
		return Needs.NAMES[loudest]
	return &"nature" if nature > def.base else &"routine"


## Weighted draw among the best few: p ∝ exp(score / temperature).
static func _draw(ids: Array[StringName], values: PackedFloat32Array, heat: float, rng: RandomNumberGenerator) -> StringName:
	var order: Array[int] = []
	for i in ids.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return values[a] > values[b] or (values[a] == values[b] and String(ids[a]) < String(ids[b])))
	var top := order.slice(0, mini(order.size(), TOP_CANDIDATES))
	var best := values[top[0]]
	var weights := PackedFloat32Array()
	var total := 0.0
	for i: int in top:
		var weight := exp((values[i] - best) / maxf(heat, 0.001))
		weights.append(weight)
		total += weight
	var roll := (rng.randf() if rng != null else 0.0) * total
	for n in top.size():
		roll -= weights[n]
		if roll <= 0.0:
			return ids[top[n]]
	return ids[top[0]]
