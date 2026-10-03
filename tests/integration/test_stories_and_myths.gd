extends TestCase
## Memory beyond the moment (M11.1, bible §15): a life's own moments
## remembered, stories told at bedtime and passed down the generations,
## stories that change in the telling, what a settlement remembers together,
## and the myths that grow out of it.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V22_FIXTURE := "res://tests/fixtures/saves/v22_world.sav"
const V22_ID := "w1791006963_65e97bec"

var session: WorldSession
var ctx: AiContext
var memories: MemoryStore
var culture: CulturalMemory
var events: EventLog
var config: MemoryConfig
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	ctx = session.behavior.ctx
	memories = session.memories
	culture = session.culture
	events = session.events
	config = Config.memory
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"newcomer_chance_per_day"]:
		_knob(Config.life, knob, 0.0)


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(resource: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([resource, knob, resource.get(knob)])
	resource.set(knob, value)


func _experience(person: PersonData, subject: StringName, interpretation: StringName, importance: float, tick: int) -> Memory:
	var memory := Memory.new()
	memory.subject = subject
	memory.interpretation = interpretation
	memory.tick = tick
	memory.first_tick = tick
	memory.location = person.world2d()
	memory.importance = importance
	memory.intensity = importance
	memory.emotions = PackedFloat32Array([0.1, 0.4, 0.5, 0.3, 0.0])
	memory.source = Memory.Source.DIRECT
	memory.text_key = MemoryText.key_for(subject, interpretation, Memory.Source.DIRECT, false)
	return memories.remember(person, memory)


func _family() -> Dictionary:
	for person in session.people.all_people():
		if not person.children.is_empty() and person.partner_id != 0:
			return {"parent": person, "child": session.people.get_person(person.children[0])}
	return {}


# --- a life's own moments -------------------------------------------------------------------------

func test_life_memories() -> void:
	var family := _family()
	var parent: PersonData = family["parent"]
	var a := session.spawn_person(session.start.settlement_tile)
	var b := session.spawn_person(session.start.settlement_tile)
	a.sex = PersonData.Sex.FEMALE
	b.sex = PersonData.Sex.MALE
	session.lifecycle.partner(a, b, session.clock.tick)
	var found := memories.about(a, &"life_partnered")
	assert_eq(found.size(), 1)
	assert_eq(found[0].kind, Memory.KIND_LIFE)
	assert_eq(MemoryText.text(found[0], session.people), "became %s's partner" % b.given_name)
	# A flood in the settlement: everyone remembers living through it.
	session.lifecycle.remember_all(&"life_flood", session.clock.tick, 0.55)
	for person in session.people.all_people():
		assert_eq(memories.about(person, &"life_flood").size(), 1, person.given_name)
	assert_eq(MemoryText.text(memories.about(parent, &"life_flood")[0], session.people), "lived through the flood")
	# One's own life is not news (nor a bedtime story).
	assert_null(memories.worth_telling(a, b, session.clock.tick))
	assert_null(Stories.story_of(ctx, parent, family["child"]))


# --- stories ----------------------------------------------------------------------------------------

func test_family_memory_transmission() -> void:
	_knob(config, &"bedtime_story_chance", 1.0)
	var family := _family()
	var parent: PersonData = family["parent"]
	var child: PersonData = family["child"]
	parent.position = child.position
	parent.pose = PersonData.Pose.IDLE
	var lived := _experience(parent, Stimulus.TOUCH, ReactionTable.SPIRIT, 0.8, session.clock.tick - 30 * DAY)
	lived.fidelity = 1.0
	# The child goes to bed: the parent tells them of it.
	session.behavior.bedtime.emit(child.id)
	var heard: Memory = null
	for memory in memories.of(child):
		if memory.told_by == parent.id and memory.subject == Stimulus.TOUCH:
			heard = memory
	assert_not_null(heard, "a story at bedtime")
	assert_eq(heard.source, Memory.Source.TOLD)
	assert_eq(heard.first_tick, lived.first_tick, "it happened long before")
	assert_near(heard.fidelity, config.retelling_fidelity, 0.0001, "a little less true than the teller's own")
	assert_true(heard.importance < lived.importance * Lore.force(heard.text_params) + 0.0001)
	assert_true(MemoryText.text(heard, session.people).contains("was told at bedtime by %s of a touch from an unseen hand" % parent.given_name),
		MemoryText.text(heard, session.people))
	assert_eq(DayLogText.text(session.day_log.of(parent.id)[-1], session.people), "tells %s a story" % child.given_name)
	# Not the same story twice.
	assert_null(Stories.story_of(ctx, parent, child))
	# Someone far away tells no stories.
	parent.position = child.position + Vector2i(40, 0)
	assert_false(Stories.tellers_for(ctx, child).has(parent))
	# The child grows up and tells their own child: a little less true again.
	var grandchild := PersonData.new()
	grandchild.id = session.ids.next_id()
	grandchild.parents = PackedInt64Array([child.id])
	grandchild.traits = Traits.neutral()
	grandchild.position = child.position
	grandchild.settlement_id = child.settlement_id
	session.people.add(grandchild)
	child.pose = PersonData.Pose.IDLE
	heard.importance = 0.6
	var again := Stories.tell(ctx, child, grandchild, heard)
	assert_near(again.fidelity, config.retelling_fidelity * config.retelling_fidelity, 0.0001)
	# Each makes of it what they make of it (their own nature).
	var made := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for n in 30:
		var listener := PersonData.new()
		listener.id = session.ids.next_id()
		listener.traits = Traits.generate(rng)
		listener.settlement_id = child.settlement_id
		listener.position = child.position
		session.people.add(listener)
		made[Stories.tell(ctx, parent, listener, lived).interpretation] = true
	assert_true(made.size() >= 2, "not everyone takes it the same way: %s" % str(made.keys()))


func test_a_story_at_bedtime_in_the_running_world() -> void:
	# The parents remember something; the evening comes, the children go to bed.
	for person in session.people.all_people():
		if not person.children.is_empty():
			_experience(person, Stimulus.TREE_SHAKEN, ReactionTable.SPIRIT, 0.7, session.clock.tick)
	var children: Array[PersonData] = []
	for person in session.people.all_people():
		if ctx.stage_of(person) == PersonData.LifeStage.CHILD and not person.parents.is_empty():
			children.append(person)
	assert_false(children.is_empty())
	while session.clock.hour() < 16.0:
		_step(30)
	var told := 0
	for minute in 8 * 60:
		_step(1)
	for child in children:
		for memory in memories.of(child):
			if memory.text_key == "MEM_STORY":
				told += 1
	var bedtimes := PackedStringArray()
	for child in children:
		var said := PackedStringArray()
		for entry: Array in session.day_log.of(child.id):
			said.append(DayLogText.line(entry, session.people))
		bedtimes.append("%s: %s" % [child.given_name, " · ".join(said.slice(-4))])
	assert_true(told >= 1, "a child heard a story at bedtime (%s)" % " | ".join(bedtimes))


func test_grandparents_tell_their_grandchildren() -> void:
	_knob(config, &"bedtime_story_chance", 1.0)
	var family := _family()
	var parent: PersonData = family["parent"]
	var child: PersonData = family["child"]
	var elder := session.spawn_person(child.position, PersonData.LifeStage.ELDER)
	parent.parents = PackedInt64Array([elder.id])
	elder.children.append(parent.id)
	elder.position = child.position
	parent.position = child.position + Vector2i(40, 0) # (away)
	_experience(elder, Stimulus.OBJECT_MOVED, ReactionTable.DEITY, 0.7, session.clock.tick - 300 * DAY)
	assert_true(Stories.tellers_for(ctx, child).has(elder))
	assert_eq(Stories.bedtime(ctx, child), elder)
	assert_false(memories.about(child, Stimulus.OBJECT_MOVED).is_empty())


func test_stories_change_in_the_telling() -> void:
	_knob(config, &"mutate_chance", 1.0)
	var teller := session.people.all_people()[0]
	teller.traits[Traits.Axis.CREATIVITY] = 1.0
	var rng := RandomNumberGenerator.new()
	var seen := {}
	for n in 60:
		rng.seed = n
		var told := Lore.retell({}, teller, ReactionTable.NATURAL, rng)
		var lore: Dictionary = told[0]
		assert_eq(lore.size(), 1, "one change a telling")
		for key: String in lore:
			seen[key] = true
		if bool(lore.get(Lore.PERSONIFIED, false)):
			assert_eq(told[1], ReactionTable.SPIRIT, "what was no one's becomes a spirit's")
	assert_eq(seen.size(), 3, "it grows, moves back to the first days, or becomes someone's doing")
	# Grown twice, in the first days: told with more force, and so remembered.
	var lore := {Lore.GRAND: 2, Lore.FIRST_DAYS: true}
	assert_near(Lore.force(lore), 1.4, 0.0001)
	assert_eq(Lore.wrap("saw a tree shaking", lore), "in the first days, saw a tree shaking — greater than anyone had seen")
	_knob(config, &"mutate_chance", 0.0)
	rng.seed = 1
	assert_eq(Lore.retell(lore, teller, ReactionTable.SPIRIT, rng)[0], lore, "unchanged, now")
	# It travels with the telling into the listener's memory.
	var listener := session.people.all_people()[1]
	Gossip.tell(ctx, teller, listener, Stimulus.TOUCH, ReactionTable.SPIRIT, 0.6, 0.9, lore)
	var perceived: Array = ctx.perceptions[listener.id]
	assert_eq((perceived[-1]["stimulus"] as Stimulus).lore, lore)


# --- a settlement's memory ------------------------------------------------------------------------

func test_cultural_pool_formation() -> void:
	var people := session.people.all_people()
	var now := session.clock.tick
	var held := Stimulus.RAIN_FROM_CLEAR_SKY
	# Two of eight: not yet the settlement's.
	for person in people.slice(0, 2):
		_experience(person, held, ReactionTable.SPIRIT, 0.5, now)
	culture.settle(now)
	assert_eq(culture.size(), 0)
	# Three: the settlement remembers it together.
	_experience(people[2], held, ReactionTable.SPIRIT, 0.5, now)
	culture.settle(now)
	assert_eq(culture.size(), 1)
	var settlement := people[0].settlement_id
	assert_near(culture.weight(settlement, held, ReactionTable.SPIRIT), 3.0 / people.size(), 0.0001)
	var told := events.latest(Chronicler.TYPE_CULTURE)
	assert_not_null(told)
	assert_eq(EventText.text(told, session.people, events),
		"The people here now tell each other of rain falling out of a clear sky — a spirit's doing")
	# It colours how the people take the like of it.
	var newcomer := people[5]
	var rain := Stimulus.natural(held, newcomer.world2d(), now, Config.reactions)
	var features := Interpretation.features(newcomer, rain, false, 3, ctx, Config.reactions)
	var with_pool := float(Interpretation.scores(newcomer, rain, features, ctx, Config.reactions)[ReactionTable.SPIRIT])
	ctx.culture = null
	var without := float(Interpretation.scores(newcomer, rain, features, ctx, Config.reactions)[ReactionTable.SPIRIT])
	ctx.culture = culture
	assert_near(with_pool - without, 3.0 / people.size() * config.pool_weight, 0.0001)
	# Nobody holds it any more: it fades, and is forgotten.
	for person in people.slice(0, 3):
		for memory in memories.about(person, held):
			memories.forget(person, memory.id)
	var faded: Array = []
	culture.faded.connect(func(_s: int, subject: StringName, _i: StringName) -> void: faded.append(subject))
	for n in 20:
		now += DAY
		culture.settle(now)
	assert_eq(culture.size(), 0)
	assert_eq(faded, [held])
	# A flood lived through together counts too.
	session.lifecycle.remember_all(&"life_flood", now, 0.55)
	culture.settle(now)
	assert_true(culture.weight(settlement, &"life_flood", &"") > 0.9)
	assert_eq(EventText.text(events.latest(Chronicler.TYPE_CULTURE), session.people, events), "The people here remember the flood together")


func test_myth_formation() -> void:
	# A spiritual band; rain out of a clear sky in a drought, again and again.
	for person in session.people.all_people():
		person.traits[Traits.Axis.SPIRITUALITY] = 0.95
		person.traits[Traits.Axis.CURIOSITY] = 0.3
		var beliefs := Interpretation.beliefs_of(person)
		beliefs[ReactionTable.INTERPRETATIONS.find(ReactionTable.SPIRIT)] = 0.8
		person.beliefs = beliefs
	var formed: Array = []
	culture.myth_formed.connect(func(myth: Dictionary) -> void: formed.append(myth))
	var fire := session.settlement.fire().position2d()
	var rains := 0
	for event in 8:
		# By day, everyone about.
		while session.clock.hour() < 10.0 or session.clock.hour() > 16.0:
			_step(30)
		session.perception.emit(Stimulus.natural(Stimulus.RAIN_FROM_CLEAR_SKY, fire, session.clock.tick, Config.reactions))
		rains += 1
		_step(60)
		session.clock.tick += DAY - 60
		culture.advance_to(session.clock.tick)
		if not formed.is_empty():
			break
	assert_false(formed.is_empty(), "a myth within %d rains (days lived: %d, culture: %s)" % [rains,
		culture.days_lived(session.people.all_people()[0].settlement_id, Stimulus.RAIN_FROM_CLEAR_SKY, ReactionTable.SPIRIT),
		culture.debug_text()])
	if formed.is_empty():
		return
	var myth: Dictionary = formed[0]
	print("    a myth after %d rains: %s (%s, %s, %d believers) — %s" % [rains, myth["epithet"], myth["agent"], myth["sentiment"],
		int(myth["believers"]), culture.debug_text()])
	assert_eq(myth["subject"], String(Stimulus.RAIN_FROM_CLEAR_SKY))
	assert_true(CulturalMemory.AGENTS.has(StringName(myth["agent"])))
	assert_true(int(myth["believers"]) >= config.pool_holders)
	assert_true(rains >= config.myth_events, "not before it had happened %d times" % config.myth_events)
	var told := events.latest(Chronicler.TYPE_MYTH)
	assert_not_null(told)
	assert_true(EventText.text(told, session.people, events).contains("the Rainbringer"), EventText.text(told, session.people, events))
	assert_eq(Array(told.causes).size(), 1, "it grew out of what they remembered together")
	assert_true(["benevolent", "fearsome", "capricious"].has(str(myth["sentiment"])))
	# Once: no second myth of the same.
	var count := culture.myths().size()
	culture.settle(session.clock.tick + DAY)
	assert_eq(culture.myths().size(), count)


func _step(minutes: int) -> void:
	for i in minutes:
		session.clock.tick += 1
		session.behavior.step(1.0)
		session.pathfinder.serve(1000000)
		session.movement.step(1.0)


# --- saving -------------------------------------------------------------------------------------------

func test_history_persistence() -> void:
	var people := session.people.all_people()
	for person in people.slice(0, 4):
		_experience(person, Stimulus.TOUCH, ReactionTable.DEITY, 0.6, session.clock.tick)
	culture.settle(session.clock.tick)
	assert_eq(culture.size(), 1)
	var told := Memory.new()
	told.subject = Stimulus.TOUCH
	told.interpretation = ReactionTable.SPIRIT
	told.importance = 0.5
	told.source = Memory.Source.TOLD
	told.told_by = people[0].id
	told.text_params = {Lore.FIRST_DAYS: true}
	memories.remember(people[5], told)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.culture.to_dict(), culture.to_dict())
	assert_true(again.behavior.ctx.culture == again.culture)
	var kept := again.memories.about(again.people.get_person(people[5].id), Stimulus.TOUCH)
	assert_true(bool(kept[-1].text_params.get(Lore.FIRST_DAYS, false)), "what the story became is kept")
	again.queue_free()
	# A world of version 22 (M10.4, 5b89cbe: Mutgith (16) died and lies in a grave):
	# it remembers nothing together yet — and will, from what its people remember.
	var dir := SaveManager.world_dir(V22_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V22_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 22)
	var old := SaveManager.load_world(V22_ID)
	assert_true(old.ok, old.error)
	assert_eq(old.world["world_state"]["culture"], {})
	var opened: WorldSession = SessionScript.new()
	add_child(opened)
	assert_true(opened.load_from(old.world))
	opened.set_process(false)
	assert_eq(opened.culture.size(), 0)
	assert_ne(opened.archive.get_record(16).grave_id, 0, "its grave is still there")
	assert_true(SaveManager.save_world(opened, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 22)
	opened.queue_free()
	# Broken records are left out; the step from version 22.
	var store := CulturalMemory.new()
	assert_eq(store.from_dict({"entries": [{"settlement": 1}, "x", {"settlement": 1, "subject": "a", "interpretation": "b", "strength": NAN}],
		"myths": [{"id": 1}]}), 4)
	assert_eq(SaveMigrations._v22_to_v23({"world": {"world_state": {"people": {}}}})["world"]["world_state"]["culture"], {})
	assert_true(SaveManager.SAVE_VERSION >= 23)


func test_the_words_of_a_story() -> void:
	var teller := session.people.all_people()[0]
	var told := Memory.new()
	told.subject = Stimulus.TOUCH
	told.interpretation = ReactionTable.SPIRIT
	told.source = Memory.Source.TOLD
	told.told_by = teller.id
	told.text_key = "MEM_STORY"
	told.text_params = {Lore.FIRST_DAYS: true, Lore.GRAND: 1}
	assert_eq(MemoryText.text(told, session.people),
		"was told at bedtime by %s of a touch from an unseen hand, greater than anyone had seen, in the first days — a spirit's doing" % teller.given_name)
	# One's own memory, grown in one's own telling of it.
	var own := Memory.new()
	own.subject = Stimulus.TREE_SHAKEN
	own.interpretation = ReactionTable.SPIRIT
	own.source = Memory.Source.DIRECT
	own.text_params = {Lore.FIRST_DAYS: true}
	assert_true(MemoryText.text(own, session.people).begins_with("in the first days, "))


func test_what_was_lived_strongly_lasts() -> void:
	var family := _family()
	var parent: PersonData = family["parent"]
	session.lifecycle.remember_life(parent, &"life_partnered", session.clock.tick, 0.7, parent.partner_id)
	var faint := _experience(parent, Stimulus.KNOCK, ReactionTable.NATURAL, 0.5, session.clock.tick)
	faint.intensity = 0.3
	# A year and a half: the faint one is long gone; the strong one is still there.
	memories.fade(36)
	assert_eq(memories.about(parent, Stimulus.KNOCK).size(), 0, "forgotten")
	assert_eq(memories.about(parent, &"life_partnered").size(), 1, "remembered")
	# Ten years on, still.
	memories.fade(240)
	assert_eq(memories.about(parent, &"life_partnered").size(), 1, "for years")
