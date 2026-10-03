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
## Routines (bible §13.5) are soft: what a person's routine has for the hour
## counts up to this many times as much, and up to this much on top — unless
## they have already done it since it came due. The push is for people whose
## needs are quiet: the louder their loudest need, the less of it there is
## (nobody starving is kept at work by the hour).
const ROUTINE_FACTOR := 1.25
const ROUTINE_PULL := 0.25
## When something else has come due, what one is at holds one less: the
## score it was begun with no longer counts, and this share of the hysteresis.
const DUE_HYSTERESIS := 0.5
## What is done out of doors (bad weather takes from its worth; from work less).
const OUTDOORS: Array[StringName] = [&"explore", &"play", &"socialize", &"tag_along"]
## What a baby (younger than LifeConfig.infant_years) does: stay with its
## parent, eat, drink, sleep — and nothing else.
const INFANT_DOES: Array[StringName] = [&"tag_along", &"eat", &"drink", &"sleep", &"go_home"]
## ... and how much more it is drawn to its parent than an older child.
const INFANT_FOLLOW := 0.6
## Why someone goes home who goes in out of the weather.
const REASON_WEATHER := &"weather"
## ... who goes home to rest, hurt or ill.
const REASON_UNWELL := &"unwell"
## ...but only if it was begun for no pressing reason (with less than this
## speaking for it): nobody leaves a meal they were starving for because the
## hour says work.
const DUE_RELEASES_BELOW := 0.6


class Decision:
	extends RefCounted
	var activity: StringName = &""
	## Why: the need that spoke loudest for it ("hunger", ...), or &"routine"
	## (the hour, habit) or &"nature" (their traits).
	var reason: StringName = &"routine"
	## Every activity's score (id -> float), -1 for what is not possible. For
	## the inspector.
	var scores: Dictionary = {}
	## What spoke for each activity before the routine's push (id -> float):
	## what a plan is begun with, and held by. (The push is for calm people;
	## it must not hold someone at a thing once a need has grown loud.)
	var plain: Dictionary = {}

	func score_of(id: StringName) -> float:
		return scores.get(id, -1.0)

	## What the activity is begun with (its score without the routine's push).
	func commitment_of(id: StringName) -> float:
		return plain.get(id, scores.get(id, -1.0))


## How much speaks for `def` for this person right now; -1 if it is not
## possible for them at all.
static func score(def: ActivityDef, person: PersonData, ctx: AiContext) -> float:
	var hour := ctx.clock.hour() if ctx.clock != null else 12.0
	var due := due_now(person, ctx, hour)
	return _score(def, person, ctx, ctx.stage_of(person), hour, ActivityDef.voices(person.needs), {}, due[0], due[1])


## What the person's routine has for `hour`: [activity id (&"" = nothing),
## the tick it came due].
static func due_now(person: PersonData, ctx: AiContext, hour: float) -> Array:
	var occupation := ctx.occupations.get_def(person.occupation_id) if ctx.occupations != null else null
	if occupation == null:
		return [&"", 0]
	var planned := occupation.scheduled(hour)
	if planned == &"":
		return [&"", 0]
	return [planned, ctx.now() - int(occupation.hours_into_slot(hour) * 60.0)]


# (The stage of life, the hour, how loudly each need speaks and what is there
# for the person are the same for every activity of one decision: worked out
# once by the caller. `met` remembers the requirements already asked about.)
static func _score(def: ActivityDef, person: PersonData, ctx: AiContext, stage: PersonData.LifeStage, hour: float,
		spoken: PackedFloat32Array, met: Dictionary, due: StringName = &"", due_since: int = 0,
		plain: Dictionary = {}) -> float:
	if not def.allows(stage):
		return -1.0
	var infant := stage == PersonData.LifeStage.CHILD \
		and person.age_years(ctx.now(), Config.time.ticks_per_year()) < Config.life.infant_years
	if infant and not INFANT_DOES.has(def.id):
		return -1.0
	for requirement in def.requires:
		var there: Variant = met.get(requirement)
		if there == null:
			there = Planner.can(requirement, person, ctx)
			met[requirement] = there
		if not there:
			return -1.0
	# What their routine has for this hour gets a push, for as long as it is
	# the hour for it — but a thing one does not do again at once (a meal)
	# only until it has been done. And it is the hour for it, whatever the
	# hour is for people in general (a child's bedtime is early).
	var pushed := due == def.id and (def.repeat_after_minutes <= 0.0
		or int(person.activity_log.get(def.id_text(), -1000000000)) < due_since)
	var timely := def.hour_factor(hour)
	if pushed:
		timely = maxf(timely, 1.0)
	var total := (def.base + def.trait_part(person.traits) + def.need_total_from(spoken)) * timely
	# Work is worth what there is to do: more with something pressing on the
	# job board, less with nothing on it for them.
	if def.id == &"work" and ctx.settlement != null and ctx.occupations != null:
		var trade := ctx.occupations.get_def(person.occupation_id)
		if trade != null:
			total *= ctx.settlement.jobs.work_factor(trade.work_target, trade.helps_with)
	# The weather: it drives people home, and takes from what is done out of doors.
	var pull := ctx.shelter_pull()
	if pull > 0.0:
		if def.id == &"go_home":
			total += Config.exposure.shelter_weight * pull
		elif def.id == &"work":
			total *= 1.0 - Config.exposure.work_cut * pull
		elif OUTDOORS.has(def.id):
			total *= 1.0 - Config.exposure.outdoor_cut * pull
	# Someone hurt or ill goes home to rest, and does less.
	var unwell := Health.unwell(person)
	if unwell > 0.0:
		if def.id == &"go_home":
			total += Config.life.unwell_rest_weight * unwell
		elif def.id == &"work" or OUTDOORS.has(def.id):
			total *= 1.0 - Config.life.unwell_work_cut * unwell
	# A baby keeps to its parent, wherever they are.
	if infant and def.id == &"tag_along":
		total += INFANT_FOLLOW
	if def.repeat_after_minutes > 0.0 and person.activity_log.has(def.id_text()):
		var since := float(ctx.now() - int(person.activity_log[def.id_text()]))
		total -= REPEAT_PENALTY * clampf(1.0 - since / def.repeat_after_minutes, 0.0, 1.0)
	total = maxf(total, 0.0)
	plain[def.id] = total
	if pushed:
		var loudest := 0.0
		for voice in spoken:
			loudest = maxf(loudest, voice)
		var calm := 1.0 - loudest
		total = total * (1.0 + (ROUTINE_FACTOR - 1.0) * calm) + ROUTINE_PULL * calm
	return total


## Chooses. `current` is what the person is doing now (&"" = nothing): it is
## kept unless something beats it by HYSTERESIS — it, or `commitment`, the
## score it was begun with, whichever is higher: a meal does not become less
## worth finishing because the first bites took the edge off the hunger.
## `barred` (a set of ids) is what just turned out not to be possible.
## `reluctance`: how much more than usual it takes to drop the step they are
## at (a sleeper is not woken by a little thirst — nor by breakfast).
static func decide(person: PersonData, ctx: AiContext, current: StringName = &"", barred: Dictionary = {},
		commitment: float = 0.0, reluctance: float = 0.0) -> Decision:
	var decision := Decision.new()
	var ids: Array[StringName] = []
	var values := PackedFloat32Array()
	var stage := ctx.stage_of(person)
	var hour := ctx.clock.hour() if ctx.clock != null else 12.0
	var spoken := ActivityDef.voices(person.needs)
	var met := {}
	var due := due_now(person, ctx, hour)
	for id in ctx.activities.ids():
		var value := -1.0 if barred.has(id) else _score(ctx.activities.get_def(id), person, ctx, stage, hour, spoken, met,
			due[0], due[1], decision.plain)
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
		var bar := maxf(decision.score_of(current), commitment) + reluctance + HYSTERESIS
		# Something else has come due (and has not been done yet): what they
		# are at lets go of them more easily — the routine's other half.
		if due[0] != &"" and due[0] != current and commitment < DUE_RELEASES_BELOW 				and int(person.activity_log.get(String(due[0]), -1000000000)) < int(due[1]):
			bar = decision.score_of(current) + reluctance + HYSTERESIS * DUE_HYSTERESIS
		var kept_ids: Array[StringName] = []
		var kept := PackedFloat32Array()
		for i in ids.size():
			if ids[i] != current and values[i] > bar:
				kept_ids.append(ids[i])
				kept.append(values[i])
		if kept_ids.is_empty():
			decision.activity = current
			decision.reason = _reason(ctx.activities.get_def(current), person, ctx)
			return decision
		ids = kept_ids
		values = kept
	decision.activity = _draw(ids, values, temperature(person), ctx.rng)
	decision.reason = _reason(ctx.activities.get_def(decision.activity), person, ctx)
	return decision


## Why this, now: the weather, for someone going in out of it; otherwise
## what `reason_for` says.
static func _reason(def: ActivityDef, person: PersonData, ctx: AiContext) -> StringName:
	if def != null and def.id == &"go_home" and ctx.shelter_reason() != &"" \
			and Needs.urgency(person.needs, Needs.Need.SAFETY) < 0.5:
		return REASON_WEATHER
	if def != null and def.id == &"go_home" and Health.unwell(person) >= 0.3:
		return REASON_UNWELL
	return reason_for(def, person)


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
