class_name Gossip
extends RefCounted
## Passing on what one has experienced (bible §15.3): the listener hears of
## it second hand — a little less true with every retelling — and makes of it
## what *they* make of it.


## Puts before `listener` what `teller` tells them: something of the kind
## `subject`, taken by the teller as `interpretation`. `strength` (0 … 1) is
## how much the teller makes of it; `fidelity` how true to what happened
## their own account still is; `lore` what the story has become so far
## (and in this telling it may change again: see Lore).
static func tell(ctx: AiContext, teller: PersonData, listener: PersonData, subject: StringName, interpretation: StringName,
		strength: float, fidelity: float = 1.0, lore: Dictionary = {}) -> void:
	var told := Lore.retell(lore, teller, interpretation, ctx.stories_rng())
	var telling := Stimulus.telling(teller, subject, told[1], clampf(strength * Lore.force(told[0]), 0.0, 1.0), ctx.now(),
		fidelity, told[0])
	telling.id = ctx.take_stimulus_id()
	if not ctx.perceptions.has(listener.id):
		ctx.perceptions[listener.id] = []
	(ctx.perceptions[listener.id] as Array).append({"stimulus": telling, "salience": telling.intensity,
		"direct": false, "witnesses": 2})
	ctx.nudges.append(listener.id)


## `teller` tells `listener` of the most telling thing they remember, if
## there is one (see MemoryStore.worth_telling). Returns the memory told.
static func share(ctx: AiContext, teller: PersonData, listener: PersonData) -> Memory:
	if ctx.memories == null or teller.memory_ids.is_empty():
		return null
	var memory := ctx.memories.worth_telling(teller, listener, ctx.now())
	if memory == null:
		return null
	memory.told_tick = ctx.now()
	if memory.kind == Memory.KIND_HARDSHIP:
		Hardship.hear(ctx, teller, listener, memory)
		return memory
	tell(ctx, teller, listener, memory.subject, memory.interpretation, clampf(memory.importance + 0.2, 0.3, 0.85), memory.fidelity,
		_lore_of(memory))
	return memory


## What a memory's story has become (its text parameters that are Lore's).
static func _lore_of(memory: Memory) -> Dictionary:
	var out := {}
	for key: String in [Lore.GRAND, Lore.FIRST_DAYS, Lore.PERSONIFIED]:
		if memory.text_params.has(key):
			out[key] = memory.text_params[key]
	return out


## How true `teller`'s own account of something of the kind `subject` is:
## that of their best memory of it (1 if they remember none — it has only
## just happened).
static func fidelity_of(ctx: AiContext, teller: PersonData, subject: StringName, mark_told: bool = false) -> float:
	if ctx.memories == null:
		return 1.0
	var best: Memory = null
	for memory in ctx.memories.about(teller, subject):
		if best == null or memory.fidelity > best.fidelity:
			best = memory
	if best == null:
		return 1.0
	if mark_told:
		best.told_tick = ctx.now()
	return best.fidelity
