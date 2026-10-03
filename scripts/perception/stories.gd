class_name Stories
extends RefCounted
## Family stories (bible §15.3): when a child goes to bed, a parent or a
## grandparent nearby tells them a story — the most important thing they
## remember that the child has not heard from them — and the child keeps it
## as they make of it themselves (their own nature reinterprets it), a little
## less true than the teller's account, and perhaps grown in the telling
## (Lore). So what one generation lived through becomes what the next one
## knows: "Grandmother Mara was touched by the Presence at the river."


## A child has gone to bed: perhaps a story. Returns the teller (null: none).
static func bedtime(ctx: AiContext, child: PersonData, config: MemoryConfig = null) -> PersonData:
	if config == null:
		config = Config.memory
	if ctx.memories == null or child == null or ctx.stories_rng() == null or ctx.stories_rng().randf() >= config.bedtime_story_chance:
		return null
	var best_teller: PersonData = null
	var best_story: Memory = null
	var best_weight := -1.0
	for teller in tellers_for(ctx, child, config):
		var story := story_of(ctx, teller, child, config)
		if story == null:
			continue
		var weight := story.importance + (config.elder_story_bonus if _is_grandparent(teller, child) else 0.0)
		if weight > best_weight or (weight == best_weight and teller.id < best_teller.id):
			best_weight = weight
			best_teller = teller
			best_story = story
	if best_teller == null:
		return null
	tell(ctx, best_teller, child, best_story, config)
	return best_teller


## Who may tell a child a story: their parents and grandparents, awake, near
## them or under the same roof.
static func tellers_for(ctx: AiContext, child: PersonData, config: MemoryConfig = null) -> Array[PersonData]:
	if config == null:
		config = Config.memory
	var ids: Array[int] = []
	for parent_id in child.parents:
		ids.append(parent_id)
		var parent := ctx.people.get_person(parent_id)
		var record := ctx.people.archive.get_record(parent_id) if parent == null and ctx.people.archive != null else null
		var grand := parent.parents if parent != null else (record.parents if record != null else PackedInt64Array())
		for grand_id in grand:
			ids.append(grand_id)
	var out: Array[PersonData] = []
	for id in ids:
		var teller := ctx.people.get_person(id)
		if teller == null or out.has(teller) or teller.pose == PersonData.Pose.SLEEP:
			continue
		var near := teller.world2d().distance_to(child.world2d()) <= config.story_reach
		var same_roof := teller.home_building_id != 0 and teller.home_building_id == child.home_building_id \
			and teller.has_flag(PersonData.FLAG_INDOORS)
		if near or same_roof:
			out.append(teller)
	return out


## The story `teller` would tell `child`: the most important thing they
## remember that is worth a story and that the child has not heard from them.
static func story_of(ctx: AiContext, teller: PersonData, child: PersonData, config: MemoryConfig = null) -> Memory:
	if config == null:
		config = Config.memory
	var heard := {}
	for memory in ctx.memories.of(child):
		if memory.told_by == teller.id:
			heard[memory.subject] = true
	var best: Memory = null
	for memory in ctx.memories.of(teller):
		if memory.importance < config.story_importance or memory.fidelity < config.tell_fidelity or heard.has(memory.subject):
			continue
		if memory.kind != Memory.KIND_EXPERIENCE or memory.subject == &"":
			continue # (hardship is talked of by day; a life's own moments are not stories)
		if memory.text_key.begins_with("MEM_CHILD_BORN") or memory.text_key.begins_with("MEM_MOURNED") \
				or memory.text_key.begins_with("MEM_LIFE_"):
			continue
		if best == null or memory.importance > best.importance or (memory.importance == best.importance and memory.id < best.id):
			best = memory
	return best


## `teller` tells `child` the story of `story`: the child remembers it as
## they make of it, a little less true, perhaps grown in the telling.
static func tell(ctx: AiContext, teller: PersonData, child: PersonData, story: Memory, config: MemoryConfig = null) -> Memory:
	if config == null:
		config = Config.memory
	var told := Lore.retell(Gossip._lore_of(story), teller, story.interpretation, ctx.stories_rng(), config)
	var lore: Dictionary = told[0]
	var telling := Stimulus.telling(teller, story.subject, told[1], clampf(story.intensity * Lore.force(lore), 0.0, 1.0),
		ctx.now(), story.fidelity, lore)
	telling.id = ctx.take_stimulus_id()
	# What the child makes of it (awake still, if only just).
	var table := Config.reactions
	var circumstances := Interpretation.features(child, telling, false, 2, ctx, table)
	circumstances[&"asleep"] = 0.0
	var scores := Interpretation.scores(child, telling, circumstances, ctx, table)
	var heat := table.interpretation_temperature * lerpf(0.7, 1.4, Traits.value(child.traits, Traits.Axis.CREATIVITY))
	var made: StringName = Interpretation.draw(scores, heat, ctx.stories_rng()) if not scores.is_empty() else story.interpretation
	var memory := Memory.new()
	memory.kind = story.kind
	memory.subject = story.subject
	memory.stimulus_id = telling.id
	memory.tick = ctx.now()
	memory.first_tick = story.first_tick
	memory.location = story.location
	memory.interpretation = made
	memory.emotions = story.emotions.duplicate()
	for i in memory.emotions.size():
		memory.emotions[i] *= config.story_share
	memory.intensity = telling.intensity * config.story_share
	memory.importance = clampf(story.importance * config.story_share * Lore.force(lore), 0.0, 1.0)
	memory.source = Memory.Source.TOLD
	memory.told_by = teller.id
	memory.fidelity = clampf(story.fidelity * config.retelling_fidelity, 0.0, 1.0)
	memory.stage = ctx.stage_of(child)
	memory.text_key = "MEM_STORY"
	memory.text_params = lore.duplicate()
	var kept := ctx.memories.remember(child, memory)
	Interpretation.update_beliefs(child, made, config.story_belief_weight, table)
	story.told_tick = ctx.now()
	if ctx.day_log != null:
		ctx.day_log.note(teller.id, ctx.now(), "life", "tells_story", child.id)
		ctx.day_log.note(child.id, ctx.now(), "life", "hears_story", teller.id)
	return kept


static func _is_grandparent(teller: PersonData, child: PersonData) -> bool:
	return not child.parents.has(teller.id)
