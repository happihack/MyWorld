class_name Hardship
extends RefCounted
## What going hungry does to a person (M7.5): after long enough with an
## empty belly they are weak with it — sick: their health goes down (and
## with it how fast they walk) — and it comes back once they are fed. In a
## shortage, whoever is hungry remembers it, and talks of it.
##
## The state is plain data on the person, in PersonData.conditions:
##   {"id": "hunger", "since": tick, "sick": bool, "well": float (their
##    health before), "fed": bool (eating again: recovering)}

const HUNGER := &"hunger"
## How much a memory of going hungry matters, and how strong it is.
const MEMORY_IMPORTANCE := 0.55
const MEMORY_INTENSITY := 0.6
## What is left of it when it is only heard of.
const HEARD_SHARE := 0.7


## The person's condition of this kind ({} if they do not have it).
static func condition_of(person: PersonData, id: StringName = HUNGER) -> Dictionary:
	for condition: Variant in person.conditions:
		if typeof(condition) == TYPE_DICTIONARY and str((condition as Dictionary).get("id", "")) == String(id):
			return condition
	return {}


## Is the person weak with hunger?
static func is_sick(person: PersonData) -> bool:
	var condition := condition_of(person)
	return bool(condition.get("sick", false)) and not bool(condition.get("fed", false))


## Lets `minutes` pass for what hunger does to a person.
static func live(person: PersonData, ctx: AiContext, minutes: float, config: NeedsConfig = null) -> void:
	if config == null:
		config = Config.needs
	var hunger := Needs.value(person.needs, Needs.Need.HUNGER)
	var condition := condition_of(person)
	if condition.is_empty():
		if hunger >= config.hunger_talk_below:
			return # (nearly everyone, nearly always)
		if hunger < config.hungry_below:
			person.conditions.append({"id": String(HUNGER), "since": ctx.now(), "sick": false, "well": person.health, "fed": false})
		_remember(person, ctx)
		return
	var day := float(TimeConfig.MINUTES_PER_DAY)
	if bool(condition.get("fed", false)):
		# Eating again: their health comes back, and then it is over.
		if hunger < config.hungry_below:
			condition["fed"] = false
			condition["since"] = ctx.now()
			condition["sick"] = false
			return
		var well := float(condition.get("well", 1.0))
		person.health = minf(person.health + config.recover_health_per_day * Health.recovery(person) * minutes / day, maxf(well, person.health))
		if person.health >= well - 0.0001:
			person.conditions.erase(condition)
		return
	if hunger >= config.fed_from:
		var was_sick := bool(condition.get("sick", false))
		if not was_sick:
			person.conditions.erase(condition)
			return
		condition["fed"] = true
		ctx.ailments.append([person.id, HUNGER, false])
		return
	if not bool(condition.get("sick", false)):
		if ctx.now() - int(condition.get("since", ctx.now())) >= config.hunger_sick_after_minutes:
			condition["sick"] = true
			ctx.ailments.append([person.id, HUNGER, true])
		_remember(person, ctx)
		return
	person.health = maxf(person.health - config.sick_health_per_day * minutes / day, minf(config.sick_health_floor, person.health))


## `teller` tells `listener` of having gone hungry: the listener now knows
## of it, second hand.
static func hear(ctx: AiContext, teller: PersonData, listener: PersonData, memory: Memory) -> Memory:
	if ctx.memories == null:
		return null
	var heard := Memory.new()
	heard.kind = Memory.KIND_HARDSHIP
	heard.subject = memory.subject
	heard.tick = ctx.now()
	heard.first_tick = ctx.now()
	heard.location = memory.location
	heard.emotions = memory.emotions.duplicate()
	for i in heard.emotions.size():
		heard.emotions[i] *= HEARD_SHARE
	heard.intensity = memory.intensity * HEARD_SHARE
	heard.importance = memory.importance * HEARD_SHARE
	heard.source = Memory.Source.TOLD
	heard.told_by = teller.id
	heard.fidelity = clampf(memory.fidelity * Config.memory.retelling_fidelity, 0.0, 1.0)
	heard.stage = ctx.stage_of(listener)
	heard.text_key = "MEM_HUNGER_TOLD"
	return ctx.memories.remember(listener, heard)


## In a shortage, a hungry person remembers going hungry — once a day.
static func _remember(person: PersonData, ctx: AiContext) -> void:
	if ctx.memories == null or ctx.settlement == null or not ctx.settlement.is_short():
		return
	var today := Config.time.day_index(ctx.now())
	for known in ctx.memories.about(person, HUNGER):
		if known.source != Memory.Source.TOLD and Config.time.day_index(known.tick) == today:
			return
	var memory := Memory.new()
	memory.kind = Memory.KIND_HARDSHIP
	memory.subject = HUNGER
	memory.tick = ctx.now()
	memory.first_tick = ctx.now()
	memory.location = ctx.settlement.fire().position2d() if ctx.settlement.fire() != null else person.world2d()
	memory.emotions = PackedFloat32Array([0.45, 0.0, 0.0, 0.0, 0.35])
	memory.intensity = MEMORY_INTENSITY
	memory.importance = MEMORY_IMPORTANCE
	memory.source = Memory.Source.DIRECT
	memory.stage = ctx.stage_of(person)
	memory.text_key = "MEM_HUNGER_CHILD" if memory.stage == PersonData.LifeStage.CHILD else "MEM_HUNGER"
	ctx.memories.remember(person, memory)
