class_name Health
extends RefCounted
## What hurts people and what ails them, and how they heal (bible §16.2,
## M10.2): injuries (from a fight, a fall, a cut at work) that heal day by
## day, and illness (from bad water, from a crowded roof) that takes health
## until it passes — both sooner for someone who rests. Whether it kills
## them is the Lifecycle's daily question.
##
## Plain data on the person:
##   injuries:   {"kind": String, "severity": 0 … 1, "initial": float, "took": float (health), "since": tick}
##   conditions: {"id": "illness", "kind": String, "since": tick, "well": float (their health before),
##                "fed": bool (it has passed: recovering)}

const ILLNESS := &"illness"
## Kinds of injury.
const FIGHT := &"fight"
const FALL := &"fall"
const CUT := &"cut"
## Kinds of illness.
const BAD_WATER := &"bad_water"
const CROWDING := &"crowding"
## What being ill counts as, for how unwell someone is (0 … 1).
const ILL_WEIGHT := 0.6


## Someone is hurt: an injury of `kind` and `severity` (0 … 1) takes some of
## their health at once (never all of it).
static func injure(person: PersonData, kind: StringName, severity: float, now: int, config: LifeConfig = null) -> void:
	if config == null:
		config = Config.life
	severity = clampf(severity, 0.0, 1.0)
	if severity <= 0.0:
		return
	var took := minf(severity * config.injury_health, maxf(person.health - 0.05, 0.0))
	person.health -= took
	person.injuries.append({"kind": String(kind), "severity": severity, "initial": severity, "took": took, "since": now})


## Someone falls ill (unless they already are). Returns whether they did.
static func fall_ill(person: PersonData, kind: StringName, now: int) -> bool:
	if not illness_of(person).is_empty():
		return false
	person.conditions.append({"id": String(ILLNESS), "kind": String(kind), "since": now, "well": person.health, "fed": false})
	return true


static func illness_of(person: PersonData) -> Dictionary:
	return Hardship.condition_of(person, ILLNESS)


## Ill (and not yet getting better)?
static func is_ill(person: PersonData) -> bool:
	var condition := illness_of(person)
	return not condition.is_empty() and not bool(condition.get("fed", false))


## The worst of their injuries (0: none).
static func worst_injury(person: PersonData) -> float:
	var worst := 0.0
	for injury: Variant in person.injuries:
		if typeof(injury) == TYPE_DICTIONARY:
			worst = maxf(worst, float((injury as Dictionary).get("severity", 0.0)))
	return worst


## How unwell someone is, 0 (not at all) … 1: their worst injury, or being ill.
static func unwell(person: PersonData) -> float:
	if person.injuries.is_empty() and person.conditions.is_empty():
		return 0.0
	return clampf(maxf(worst_injury(person), ILL_WEIGHT if is_ill(person) else 0.0), 0.0, 1.0)


## Resting (asleep, or at home out of the day's doings): they heal faster.
static func is_resting(person: PersonData) -> bool:
	return person.pose == PersonData.Pose.SLEEP or person.has_flag(PersonData.FLAG_INDOORS) \
		or BehaviorSystem.activity_of(person) == &"go_home"


## Lets `minutes` pass for someone's injuries and illness.
static func live(person: PersonData, ctx: AiContext, minutes: float, config: LifeConfig = null) -> void:
	if person.injuries.is_empty() and person.conditions.is_empty():
		return # (nearly everyone, nearly always)
	if config == null:
		config = Config.life
	var day := float(TimeConfig.MINUTES_PER_DAY)
	var rest := config.rest_heals if is_resting(person) else 1.0
	# Injuries heal, and give back the health they took.
	if not person.injuries.is_empty():
		var healed := minutes / day * config.injury_heal_per_day * rest
		for n in range(person.injuries.size() - 1, -1, -1):
			var injury: Variant = person.injuries[n]
			if typeof(injury) != TYPE_DICTIONARY:
				person.injuries.remove_at(n)
				continue
			var was := float((injury as Dictionary).get("severity", 0.0))
			var now_is := maxf(was - healed, 0.0)
			var initial := maxf(float((injury as Dictionary).get("initial", was)), 0.0001)
			var back := float((injury as Dictionary).get("took", 0.0)) * (was - now_is) / initial
			person.health = minf(person.health + back, 1.0)
			injury["severity"] = now_is
			if now_is <= 0.0:
				person.injuries.remove_at(n)
	var condition := illness_of(person)
	if condition.is_empty():
		return
	var needs := Config.needs
	if bool(condition.get("fed", false)):
		# It has passed: their health comes back, and then it is over.
		var well := float(condition.get("well", 1.0))
		person.health = minf(person.health + needs.recover_health_per_day * minutes / day, maxf(well, person.health))
		if person.health >= well - 0.0001:
			person.conditions.erase(condition)
		return
	person.health = maxf(person.health - config.illness_health_per_day * minutes / day,
		minf(config.illness_floor, person.health))
	var passes := 1.0 - pow(1.0 - minf(config.illness_passes_per_day * rest, 1.0), minutes / day)
	if ctx.rng != null and ctx.rng.randf() < passes:
		condition["fed"] = true
		ctx.ailments.append([person.id, ILLNESS, false])


## The water someone drank was bad: they may fall ill of it.
static func drank(person: PersonData, ctx: AiContext, tile: Vector2i, config: LifeConfig = null) -> void:
	if config == null:
		config = Config.life
	if not ctx.bad_water.is_valid() or not bool(ctx.bad_water.call(tile)) or ctx.rng == null:
		return
	if ctx.rng.randf() < config.bad_water_chance and fall_ill(person, BAD_WATER, ctx.now()):
		ctx.ailments.append([person.id, ILLNESS, true])
		if ctx.day_log != null:
			ctx.day_log.note(person.id, ctx.now(), "life", "ill_bad_water")
		if ctx.lifecycle != null:
			ctx.lifecycle.remember_life(person, &"life_ill", ctx.now(), 0.35)
