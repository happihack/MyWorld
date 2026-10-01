extends TestCase
## Memory (M5.4, bible §15): what people keep of what happens to them, in
## words, for how long, how it is passed on, and what it does to them.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V5_FIXTURE := "res://tests/fixtures/saves/v5_world.sav"
const V5_ID := "w1790867949_3c2d625b"
const DAY := TimeConfig.MINUTES_PER_DAY

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var store: MemoryStore
var table: ReactionTable
var config: MemoryConfig


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	table = Config.reactions
	config = Config.memory
	session = _open(12345)
	_set_hour(11.0)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _open(seed_value: int) -> WorldSession:
	var s: WorldSession = SessionScript.new()
	add_child(s)
	s.create_new(seed_value)
	_take(s)
	return s


func _take(s: WorldSession) -> void:
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	behavior = s.behavior
	ctx = behavior.ctx
	store = s.memories


func _run(minutes: float, step: float = 0.5, s: WorldSession = null) -> void:
	if s == null:
		s = session
	var left := minutes
	while left > 0.0001:
		var dt := minf(step, left)
		var seconds := dt * Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			s.clock.advance(piece)
			seconds -= piece
		s.behavior.step(dt)
		s.pathfinder.serve(1_000_000)
		s.movement.step(dt)
		left -= dt


func _set_hour(hour: float) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440)


func _of(stage: PersonData.LifeStage) -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == stage:
			return p
	return null


func _adult() -> PersonData:
	return _of(PersonData.LifeStage.ADULT)


## Someone of a given nature, with no convictions, no past and no wants.
func _make(person: PersonData, leanings: Dictionary = {}) -> PersonData:
	person.traits = Traits.neutral()
	for axis: int in leanings:
		person.traits[axis] = leanings[axis]
	person.beliefs = PackedFloat32Array()
	person.knowledge = {}
	person.needs = PackedFloat32Array([0.9, 0.9, 0.9, 0.9, 0.9, 1.0])
	for id in person.memory_ids.duplicate():
		store.forget(person, id)
	return person


func _touch(person: PersonData) -> void:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)


func _stimulus(type: StringName, at: Vector2, strength: float = 0.0, target: int = 0) -> Stimulus:
	var stimulus := Stimulus.new()
	stimulus.type = type
	stimulus.position = at
	stimulus.target_id = target
	table.describe(stimulus, strength)
	return stimulus


## A memory made by hand.
func _memory(subject: StringName, interpretation: StringName, importance: float, tick: int = 0,
		source: Memory.Source = Memory.Source.DIRECT, feelings: Array = [0.0, 0.0, 0.0, 0.0, 0.0]) -> Memory:
	var memory := Memory.new()
	memory.subject = subject
	memory.interpretation = interpretation
	memory.importance = importance
	memory.tick = tick
	memory.first_tick = tick
	memory.source = source
	memory.emotions = PackedFloat32Array(feelings)
	memory.intensity = 0.5
	return memory


func _outcome(stimulus: Stimulus, interpretation: StringName, feelings: Array, direct: bool, salience: float = 1.0) -> Reactions.Outcome:
	var outcome := Reactions.Outcome.new()
	outcome.stimulus = stimulus
	outcome.interpretation = interpretation
	outcome.emotions = PackedFloat32Array(feelings)
	outcome.direct = direct
	outcome.salience = salience
	return outcome


# --- the texts ------------------------------------------------------------------------------------

func test_the_texts_are_there() -> void:
	assert_true(MemoryText.has("MEM_TOUCH_SPIRIT"), "the templates are loaded (data/text/memories.csv)")
	assert_false(MemoryText.has("MEM_NO_SUCH_THING"))
	assert_eq(Config.memory.validate().size(), 0)
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	# Every kind of thing, taken every way, come by every way, has words — and no placeholder is left in them.
	var person := _adult()
	var teller := session.people.all_people()[1]
	for subject in Stimulus.TYPES:
		if subject == Stimulus.TOLD:
			continue
		assert_true(MemoryText.has("MEMWHAT_" + String(subject).to_upper()), "what a %s is called" % subject)
		for interpretation in ReactionTable.INTERPRETATIONS:
			assert_true(MemoryText.has("MEMBELIEF_" + String(interpretation).to_upper()))
			for source: Memory.Source in [Memory.Source.DIRECT, Memory.Source.WITNESSED, Memory.Source.TOLD]:
				for child: bool in [false, true]:
					var memory := _memory(subject, interpretation, 0.5, 0, source)
					memory.told_by = teller.id if source == Memory.Source.TOLD else 0
					memory.text_key = MemoryText.key_for(subject, interpretation, source, child)
					var text := MemoryText.text(memory, session.people)
					assert_true(text.length() > 8, "%s / %s: %s" % [subject, interpretation, text])
					assert_false(text.contains("{") or text.contains("MEM"), text)
					if source == Memory.Source.TOLD:
						assert_has(text, teller.given_name)
	# The particular before the general.
	assert_eq(MemoryText.key_for(Stimulus.TOUCH, ReactionTable.SPIRIT, Memory.Source.DIRECT, false), "MEM_TOUCH_SPIRIT")
	assert_eq(MemoryText.key_for(Stimulus.TOUCH, ReactionTable.SPIRIT, Memory.Source.DIRECT, true), "MEM_TOUCH_SPIRIT_CHILD")
	assert_eq(MemoryText.key_for(Stimulus.TOUCH, ReactionTable.PHYSICS, Memory.Source.DIRECT, true), "MEM_TOUCH_PHYSICS", "no child's version: the grown one")
	assert_eq(MemoryText.key_for(Stimulus.TREE_SHAKEN, ReactionTable.SPIRIT, Memory.Source.WITNESSED, false), "MEM_TREE_SHAKEN")
	assert_eq(MemoryText.key_for(&"something_new", ReactionTable.SPIRIT, Memory.Source.WITNESSED, false), "MEM_SAW")
	assert_eq(MemoryText.key_for(Stimulus.TOUCH, ReactionTable.SPIRIT, Memory.Source.TOLD, false), "MEM_TOLD")
	# The same touch, three ways of having taken it, and a child's.
	var spirit := _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.5)
	assert_eq(MemoryText.text(spirit), "felt the touch of a spirit")
	assert_eq(MemoryText.text(_memory(Stimulus.TOUCH, ReactionTable.DEITY, 0.5)), "was touched by the hand of a god")
	assert_has(MemoryText.text(_memory(Stimulus.TOUCH, ReactionTable.HALLUCINATION, 0.5)), "tiredness")
	var small := _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.5)
	small.text_key = "MEM_TOUCH_SPIRIT_CHILD"
	assert_eq(MemoryText.text(small), "was tickled by a spirit")
	assert_eq(MemoryText.text(_memory(Stimulus.TREE_SHAKEN, ReactionTable.NATURAL, 0.5, 0, Memory.Source.WITNESSED)),
		"saw a tree shaking with no wind — nothing strange in it")
	assert_has(MemoryText.text(_memory(Stimulus.OBJECT_FOUND, ReactionTable.SPIRIT, 0.5, 0, Memory.Source.WITNESSED)),
		"found a stone that was not there the day before")
	# More than once; a line; a sentence.
	spirit.count = 14
	assert_eq(MemoryText.text(spirit), "felt the touch of a spirit (14 times)")
	spirit.count = 1
	spirit.tick = session.clock.tick
	var age := person.age_years(session.clock.tick, Config.time.ticks_per_year())
	assert_eq(MemoryText.line(spirit, person), "Age %d · Felt the touch of a spirit" % age)
	assert_eq(MemoryText.sentence(spirit, person), "At age %d, %s felt the touch of a spirit." % [age, person.given_name])
	# Told by someone who is gone, or by nobody known.
	var heard := _memory(Stimulus.TOUCH, ReactionTable.DEITY, 0.5, 0, Memory.Source.TOLD)
	heard.told_by = teller.id
	assert_eq(MemoryText.text(heard, session.people), "heard from %s of a touch from an unseen hand — a god's doing" % teller.given_name)
	heard.told_by = 999_999
	assert_eq(MemoryText.text(heard, session.people), "heard tell of a touch from an unseen hand — a god's doing")
	assert_eq(MemoryText.capitalized(""), "")


# --- remembering ----------------------------------------------------------------------------------

func test_memory_created_on_touch() -> void:
	var person := _make(_adult(), {Traits.Axis.SPIRITUALITY: 0.6})
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	assert_eq(person.memory_ids.size(), 0)
	var remembered: Array[Memory] = []
	store.remembered.connect(func(memory: Memory) -> void: remembered.append(memory))
	_touch(person)
	assert_eq(person.memory_ids.size(), 1, "one touch, one memory")
	assert_eq(remembered.size(), 1)
	var memory := store.of(person)[0]
	var outcome := behavior.last_outcome(person.id)
	assert_true(memory == remembered[0] and memory == store.get_memory(person.memory_ids[0]))
	assert_true(memory.id > 0)
	assert_eq(memory.owner_kind, Memory.OwnerKind.PERSON)
	assert_eq(memory.owner_id, person.id)
	assert_eq(memory.subject, Stimulus.TOUCH)
	assert_eq(memory.source, Memory.Source.DIRECT)
	assert_eq(memory.interpretation, outcome.interpretation, "what they made of it")
	assert_eq(memory.emotions, outcome.emotions, "how it felt")
	assert_eq(memory.stimulus_id, outcome.stimulus.id, "and what it came from")
	assert_true(memory.stimulus_id > 0)
	assert_eq(memory.tick, session.clock.tick)
	assert_true(memory.location.distance_to(person.world2d()) < 0.01, "where it happened")
	assert_eq(memory.fidelity, 1.0, "they were there")
	assert_eq(memory.count, 1)
	assert_eq(memory.stage, PersonData.LifeStage.ADULT)
	assert_true(memory.importance > 0.35 and memory.importance <= 1.0, "a touch matters (%.2f)" % memory.importance)
	assert_eq(memory.text_key, "MEM_TOUCH_" + String(outcome.interpretation).to_upper())
	assert_eq(store.times(person, Stimulus.TOUCH), 1)
	assert_eq(store.recent(person, 1)[0], memory)
	assert_eq(store.about(person, Stimulus.KNOCK).size(), 0)
	# It is on their card, and the inspector knows.
	var facts := PersonCard.facts(session, person)
	assert_eq(facts["memories"], PackedStringArray([MemoryText.line(memory, person, session.people)]))
	assert_true((facts["memories"] as PackedStringArray)[0].begins_with("Age "))
	assert_has(AiInspector.describe(session, person), "remembers 1; last: ")
	# A child keeps a child's memory of it.
	var child := _make(_of(PersonData.LifeStage.CHILD))
	behavior.set_plan(child, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	_touch(child)
	var young := store.of(child)[0]
	assert_eq(young.stage, PersonData.LifeStage.CHILD)
	if MemoryText.has("MEM_TOUCH_%s_CHILD" % String(young.interpretation).to_upper()):
		assert_true(young.text_key.ends_with("_CHILD"), young.text_key)
	# Looking at someone (Observe) leaves them nothing to remember; neither does a frozen world.
	var other := _make(session.people.all_people()[-1])
	behavior.enabled = false
	_touch(other)
	assert_eq(other.memory_ids.size(), 0)


func test_what_matters_is_what_is_strong_felt_one_s_own_and_new() -> void:
	var person := _make(_adult())
	var touch := _stimulus(Stimulus.TOUCH, person.world2d(), 0.0, person.id)
	var calm := [0.1, 0.1, 0.1, 0.0, 0.0]
	var shaken := [0.9, 0.2, 0.5, 0.0, 0.0]
	var base := MemoryStore.from_outcome(person, _outcome(touch, ReactionTable.SPIRIT, shaken, true), PersonData.LifeStage.ADULT, 0, 100)
	# How it felt.
	assert_true(base.importance > MemoryStore.from_outcome(person, _outcome(touch, ReactionTable.SPIRIT, calm, true),
		PersonData.LifeStage.ADULT, 0, 100).importance + 0.2)
	# How strong it was.
	var faint := _stimulus(Stimulus.GROUND_TOUCHED, person.world2d())
	assert_true(base.importance > MemoryStore.from_outcome(person, _outcome(faint, ReactionTable.SPIRIT, shaken, true),
		PersonData.LifeStage.ADULT, 0, 100).importance)
	# Whether it was theirs: lived, seen, heard.
	var seen := MemoryStore.from_outcome(person, _outcome(touch, ReactionTable.SPIRIT, shaken, false), PersonData.LifeStage.ADULT, 0, 100)
	assert_eq(seen.source, Memory.Source.WITNESSED)
	assert_near(seen.importance, base.importance * config.relevance_witnessed, 0.001)
	var telling := Stimulus.telling(person, Stimulus.TOUCH, ReactionTable.SPIRIT, 0.8, 100)
	var heard := MemoryStore.from_outcome(person, _outcome(telling, ReactionTable.SPIRIT, shaken, false), PersonData.LifeStage.ADULT, 0, 100)
	assert_eq(heard.source, Memory.Source.TOLD)
	assert_eq(heard.subject, Stimulus.TOUCH, "about the touch, not about the telling")
	assert_true(heard.importance < seen.importance)
	# How new it was.
	var tenth := MemoryStore.from_outcome(person, _outcome(touch, ReactionTable.SPIRIT, shaken, true), PersonData.LifeStage.ADULT, 9, 100)
	assert_near(tenth.importance, base.importance / (1.0 + 9.0 * config.novelty_wear), 0.001)
	# What was barely noticed is not kept — unless it happened to them.
	assert_null(MemoryStore.from_outcome(person, _outcome(faint, ReactionTable.NATURAL, calm, false, config.remember_threshold - 0.05),
		PersonData.LifeStage.ADULT, 0, 100))
	assert_not_null(MemoryStore.from_outcome(person, _outcome(faint, ReactionTable.NATURAL, calm, true, 0.01),
		PersonData.LifeStage.ADULT, 0, 100))
	for memory: Memory in [base, seen, heard, tenth]:
		assert_true(memory.importance > 0.0 and memory.importance <= 1.0)


func test_memory_compaction() -> void:
	var person := _make(_adult())
	# The same thing again is one memory that grows, not another memory.
	var first := store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.4, 100, Memory.Source.DIRECT, [0.8, 0, 0, 0, 0]))
	var again := _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.3, 500, Memory.Source.DIRECT, [0.2, 0, 0, 0, 0])
	again.location = Vector2(9, 9)
	var merged := store.remember(person, again)
	assert_true(merged == first, "the same memory")
	assert_eq(person.memory_ids.size(), 1)
	assert_eq(first.count, 2)
	assert_eq(first.tick, 500, "it last happened then")
	assert_eq(first.first_tick, 100, "and first then")
	assert_eq(first.location, Vector2(9, 9), "there")
	assert_near(first.importance, 0.4 + config.repeat_gain * 0.6, 0.001, "it matters more for having happened again")
	assert_true(first.emotions[0] < 0.8 and first.emotions[0] > 0.2, "and feels more like the last time")
	for i in 12:
		store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.3, 600 + i))
	assert_eq(first.count, 14)
	assert_eq(MemoryText.text(first), "felt the touch of a spirit (14 times)")
	assert_true(first.importance <= 1.0)
	assert_eq(store.times(person, Stimulus.TOUCH), 14)
	assert_eq(store.merged, 13)
	# Taken another way, or come by another way, it is another memory.
	store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.DEITY, 0.3, 700))
	store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.3, 710, Memory.Source.TOLD))
	store.remember(person, _memory(Stimulus.KNOCK, ReactionTable.SPIRIT, 0.3, 720, Memory.Source.WITNESSED))
	assert_eq(person.memory_ids.size(), 4)
	assert_eq(store.times(person, Stimulus.TOUCH), 15, "what was only heard does not count as having happened")
	# Seen and lived are the same thing happening.
	store.remember(person, _memory(Stimulus.KNOCK, ReactionTable.SPIRIT, 0.3, 730, Memory.Source.DIRECT))
	assert_eq(person.memory_ids.size(), 4)
	# The most recent is the last in their list, and the first of `recent`.
	assert_eq(store.recent(person, 1)[0].subject, Stimulus.KNOCK)
	assert_eq(store.get_memory(person.memory_ids[-1]).subject, Stimulus.KNOCK)
	store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.3, 800))
	assert_eq(store.get_memory(person.memory_ids[-1]), first, "happened again: recent again")
	# No more than the cap: the least important go, of equals the oldest.
	_make(person)
	var kinds: Array[StringName] = []
	for i in config.max_per_person + 6:
		kinds.append(StringName("thing_%d" % i))
		store.remember(person, _memory(kinds[i], ReactionTable.NATURAL, 0.2 + 0.01 * (i % 7), 1000 + i))
	assert_eq(person.memory_ids.size(), config.max_per_person)
	assert_eq(store.of(person).size(), config.max_per_person)
	assert_eq(store.dropped, 6)
	var least := 1.0
	for memory in store.of(person):
		least = minf(least, memory.importance)
	assert_true(least >= 0.2, "what is left matters at least as much as what went")
	assert_eq(store.about(person, &"thing_0").size(), 0, "the oldest of the least important went first")
	assert_eq(store.about(person, &"thing_6").size(), 1, "what mattered more stayed, old as it is")
	# Something that matters less than everything they hold is not kept at all.
	var forgotten: Array = []
	store.forgotten.connect(func(owner: int, id: int) -> void: forgotten.append([owner, id]))
	var trifle := store.remember(person, _memory(&"trifle", ReactionTable.NATURAL, 0.01, 5000))
	assert_eq(store.about(person, &"trifle").size(), 0)
	assert_null(store.get_memory(trifle.id))
	assert_eq(forgotten, [[person.id, trifle.id]])
	assert_eq(store.compact(person), 0, "nothing more to drop")


func test_memories_fade_and_what_does_not_matter_is_forgotten() -> void:
	var person := _make(_adult())
	var great := store.remember(person, _memory(Stimulus.TREE_UPROOTED, ReactionTable.DEITY, 0.95, 0))
	var middling := store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.4, 0))
	var slight := store.remember(person, _memory(Stimulus.KNOCK, ReactionTable.NATURAL, 0.12, 0))
	# Within a day nothing fades; day by day, everything does — what matters much, hardly.
	assert_eq(store.advance(0), 0)
	assert_eq(store.advance(DAY - 1), 0)
	assert_eq(slight.importance, 0.12)
	store.advance(DAY)
	assert_near(slight.importance, 0.12 - config.daily_fade * (1.05 - 0.12), 0.0001)
	assert_near(great.importance, 0.95 - config.daily_fade * 0.1, 0.0001)
	store.advance(DAY + 5)
	assert_near(great.importance, 0.95 - config.daily_fade * 0.1, 0.0001, "once a day")
	# A few days on the slight one is gone.
	var gone := 0
	for day in range(2, 6):
		gone += store.advance(DAY * day)
	assert_eq(gone, 1)
	assert_eq(store.about(person, Stimulus.KNOCK).size(), 0, "forgotten")
	assert_eq(person.memory_ids.size(), 2)
	assert_false(person.memory_ids.has(slight.id))
	assert_true(middling.importance < 0.4 and middling.importance > 0.2)
	# Days missed are made up for at once.
	var before := middling.importance
	store.advance(DAY * 15)
	assert_true(middling.importance < before - 0.1 or store.get_memory(middling.id) == null)
	# A whole year: what was great is still remembered.
	store.advance(DAY * 40)
	assert_not_null(store.get_memory(great.id), "a tree torn out by a god is not forgotten in a year (%.2f)" % great.importance)
	assert_null(store.get_memory(middling.id))
	# The world's own clock drives it.
	var another := store.remember(person, _memory(Stimulus.KNOCK, ReactionTable.NATURAL, 0.2, session.clock.tick))
	store._faded_day = -1
	_run(2.0)
	var held := another.importance
	session.clock.tick += DAY
	_run(2.0)
	assert_true(another.importance < held, "a day has passed for memories too")


func test_repeated_touch_changes_reaction() -> void:
	var person := _make(_adult(), {Traits.Axis.BRAVERY: -0.7, Traits.Axis.SUSPICION: -0.5})
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(6000.0)])
	# Touched ten times over a day, through the whole pipeline.
	var fears := PackedFloat32Array()
	var joys := PackedFloat32Array()
	var reactions := PackedStringArray()
	for i in 10:
		_touch(person)
		var outcome := behavior.last_outcome(person.id)
		fears.append(outcome.emotions[ReactionTable.Emotion.FEAR])
		joys.append(outcome.emotions[ReactionTable.Emotion.JOY])
		reactions.append(String(outcome.reaction))
		_run(60.0)
	print("    one person touched ten times: %s" % ", ".join(reactions))
	assert_eq(Interpretation.familiarity(person, Stimulus.TOUCH), 10)
	assert_eq(store.times(person, Stimulus.TOUCH), 10, "all of it remembered")
	assert_true(person.memory_ids.size() <= 5, "as a few memories, not ten (%d)" % person.memory_ids.size())
	var counted := 0
	for memory in store.about(person, Stimulus.TOUCH):
		counted += memory.count
		if memory.count > 1:
			assert_has(MemoryText.text(memory), "times)")
	assert_eq(counted, 10)
	# What it does to them changes: the fright goes out of it, they come to like it.
	var early_fear := (fears[0] + fears[1]) * 0.5
	var late_fear := (fears[8] + fears[9]) * 0.5
	assert_true(late_fear < early_fear * 0.75, "less frightening (%.2f -> %.2f)" % [early_fear, late_fear])
	assert_true(joys[9] > joys[0], "the trusting come to like it (%.2f -> %.2f)" % [joys[0], joys[9]])
	# And over many people: the fearful run far less the tenth time than the first.
	var first_runs := 0
	var tenth_runs := 0
	for round in 120:
		_make(person, {Traits.Axis.BRAVERY: -0.7})
		var touch := _stimulus(Stimulus.TOUCH, person.world2d(), 0.0, person.id)
		var perception := {"stimulus": touch, "salience": 1.0, "direct": true, "witnesses": 1}
		if Reactions.respond(person, perception, ctx, table).reaction == ReactionTable.RUN:
			first_runs += 1
		person.knowledge = {"experienced": {"touch": 9}}
		if Reactions.respond(person, perception, ctx, table).reaction == ReactionTable.RUN:
			tenth_runs += 1
	assert_true(tenth_runs < first_runs * 0.7, "%d runs at first, %d the tenth time" % [first_runs, tenth_runs])
	# The memory of each new touch matters less than the one before, taken alone.
	_make(person)
	var touch := _stimulus(Stimulus.TOUCH, person.world2d(), 0.0, person.id)
	var one := MemoryStore.from_outcome(person, _outcome(touch, ReactionTable.SPIRIT, [0.5, 0.5, 0.5, 0, 0], true), PersonData.LifeStage.ADULT, 0, 0)
	var ten := MemoryStore.from_outcome(person, _outcome(touch, ReactionTable.SPIRIT, [0.5, 0.5, 0.5, 0, 0], true), PersonData.LifeStage.ADULT, 9, 0)
	assert_true(ten.importance < one.importance * 0.5)


# --- passing it on --------------------------------------------------------------------------------

func test_gossip_secondhand_fidelity() -> void:
	var everyone := session.people.all_people()
	var first := _make(everyone[0])
	var second := _make(everyone[1])
	var third := _make(everyone[2])
	for p in everyone:
		p.set_flag(PersonData.FLAG_INDOORS, false)
		behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(6000.0)])
	session.people.move(second.id, first.position + Vector2i(1, 0), Vector2(0.5, 0.5), 0.0)
	session.people.move(third.id, first.position + Vector2i(1, 1), Vector2(0.5, 0.5), 0.0)
	# The first was touched and took it for a god's hand.
	var lived := store.remember(first, _memory(Stimulus.TOUCH, ReactionTable.DEITY, 0.8, session.clock.tick, Memory.Source.DIRECT,
		[0.2, 0.3, 0.9, 0.3, 0.0]))
	assert_eq(lived.fidelity, 1.0)
	# They tell the second.
	assert_true(Gossip.share(ctx, first, second) == lived)
	assert_eq(lived.told_tick, session.clock.tick)
	_run(1.0)
	var heard_list := store.about(second, Stimulus.TOUCH)
	assert_eq(heard_list.size(), 1, "the listener remembers being told")
	var heard := heard_list[0]
	assert_eq(heard.source, Memory.Source.TOLD)
	assert_eq(heard.told_by, first.id)
	assert_near(heard.fidelity, config.retelling_fidelity, 0.0001, "a little less true than what was lived")
	assert_true(heard.importance < lived.importance, "and it matters less to them")
	assert_has(MemoryText.text(heard, session.people), "heard from %s of a touch" % first.given_name)
	assert_eq(store.times(second, Stimulus.TOUCH), 0, "it did not happen to them")
	var outcome := behavior.last_outcome(second.id)
	assert_eq(outcome.stimulus.type, Stimulus.TOLD)
	assert_eq(heard.interpretation, outcome.interpretation, "taken their own way")
	# Not told to the same person again, nor again so soon to anyone.
	assert_null(Gossip.share(ctx, first, second))
	assert_null(store.worth_telling(first, third, session.clock.tick), "told only just now")
	assert_not_null(store.worth_telling(first, third, session.clock.tick + config.tell_again_minutes + 1))
	# The second passes it on to the third: less true again.
	heard.importance = 0.6 # (it struck them)
	assert_null(store.worth_telling(second, first, session.clock.tick), "not back to whoever told them")
	assert_true(Gossip.share(ctx, second, third) == heard)
	_run(1.0)
	var third_hand := store.about(third, Stimulus.TOUCH)[0]
	assert_near(third_hand.fidelity, config.retelling_fidelity * config.retelling_fidelity, 0.0001)
	assert_eq(third_hand.told_by, second.id)
	# Told often enough it is no longer worth telling: stories do not go round for ever.
	var worn := _memory(Stimulus.KNOCK, ReactionTable.SPIRIT, 0.9, session.clock.tick, Memory.Source.TOLD)
	worn.fidelity = config.tell_fidelity - 0.01
	worn.told_by = first.id
	store.remember(third, worn)
	third_hand.told_tick = session.clock.tick
	assert_null(store.worth_telling(third, everyone[3], session.clock.tick))
	# Nor what does not matter enough, nor what is long past, nor what the other was there for.
	_make(first)
	_make(second)
	store.remember(first, _memory(Stimulus.KNOCK, ReactionTable.SPIRIT, config.tell_importance - 0.05, session.clock.tick))
	assert_null(store.worth_telling(first, second, session.clock.tick))
	var old := store.remember(first, _memory(Stimulus.WATER_POURED, ReactionTable.DEITY, 0.9, session.clock.tick - (config.tell_recent_days + 1) * DAY))
	assert_null(store.worth_telling(first, second, session.clock.tick))
	old.tick = session.clock.tick
	assert_true(store.worth_telling(first, second, session.clock.tick) == old)
	store.remember(second, _memory(Stimulus.WATER_POURED, ReactionTable.NATURAL, 0.5, session.clock.tick, Memory.Source.WITNESSED))
	assert_null(store.worth_telling(first, second, session.clock.tick), "they saw it themselves")
	# Of several, the one that matters most.
	_make(second)
	var bigger := store.remember(first, _memory(Stimulus.TREE_UPROOTED, ReactionTable.DEITY, 0.95, session.clock.tick))
	assert_true(store.worth_telling(first, second, session.clock.tick) == bigger)


func test_people_talk_of_what_is_on_their_mind() -> void:
	var everyone := session.people.all_people()
	var visitor := _make(everyone[0])
	var host := _make(everyone[1])
	for p in everyone:
		p.set_flag(PersonData.FLAG_INDOORS, false)
		behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(6000.0)])
	session.people.move(host.id, visitor.position + Vector2i(1, 0), Vector2(0.5, 0.5), 0.0)
	var lived := store.remember(visitor, _memory(Stimulus.TREE_UPROOTED, ReactionTable.DEITY, 0.8, session.clock.tick, Memory.Source.WITNESSED,
		[0.6, 0.2, 0.8, 0.0, 0.0]))
	behavior.set_plan(visitor, &"socialize", &"social", [SocializeStep.make(host.id, 20.0)], 1.0)
	_run(SocializeStep.GOSSIP_AFTER - 1.0)
	assert_eq(store.about(host, Stimulus.TREE_UPROOTED).size(), 0, "not the first thing said")
	_run(3.0)
	assert_eq(lived.told_tick >= 0, true, "a little way into the talk, it is told")
	var heard := store.about(host, Stimulus.TREE_UPROOTED)
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].source, Memory.Source.TOLD)
	assert_eq(heard[0].told_by, visitor.id)
	# Once per conversation.
	var count := store.size()
	_run(10.0)
	assert_eq(store.size(), count)
	# Someone with nothing to tell just talks.
	_make(visitor)
	_make(host)
	behavior.set_plan(visitor, &"socialize", &"social", [SocializeStep.make(host.id, 20.0)], 1.0)
	_run(8.0)
	assert_eq(store.size(), count - 2)
	assert_eq(host.memory_ids.size(), 0)
	# Someone who goes to tell of what just happened tells it as they remember it.
	behavior.set_plan(host, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(6000.0)])
	session.movement.stop(visitor.id)
	session.people.move(visitor.id, host.position + Vector2i(1, 0), Vector2(0.5, 0.5), 0.0) # (wherever they had wandered)
	var fresh := store.remember(visitor, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.7, session.clock.tick))
	behavior.set_plan(visitor, BehaviorSystem.ACTIVITY_REACT, ReactionTable.SPIRIT,
		[TellStep.make(host.id, 5.0, Stimulus.TOUCH, ReactionTable.SPIRIT, 0.7)])
	_run(2.0)
	assert_eq(fresh.told_tick, session.clock.tick - 2, "the memory is marked as told")
	assert_near(store.about(host, Stimulus.TOUCH)[0].fidelity, config.retelling_fidelity, 0.0001)


# --- what memories do -----------------------------------------------------------------------------

func test_fear_keeps_people_away_from_where_it_happened() -> void:
	var woodcutter: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"woodcutter":
			woodcutter = p
	assert_not_null(woodcutter)
	_make(woodcutter)
	var places := ctx.places
	assert_true(places.memories == store)
	# Where they work, without a care: any of the nearest few trees.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var seen := {}
	for i in 60:
		seen[places.work_place(woodcutter, &"tree", rng)["id"]] = true
	assert_true(seen.size() >= 2, "several trees to choose from")
	var dreaded: int = seen.keys()[0]
	var tree := session.props.get_prop(dreaded)
	var at := tree.position2d()
	assert_eq(store.fear_at(woodcutter, at), 0.0)
	assert_false(places.feared(woodcutter, tree.tile))
	# Something terrible happened at one of them.
	var fright := store.remember(woodcutter, _memory(Stimulus.TREE_SHAKEN, ReactionTable.SPIRIT, 0.7, session.clock.tick, Memory.Source.WITNESSED,
		[0.9, 0.1, 0.3, 0.0, 0.0]))
	fright.location = at
	assert_true(store.fear_at(woodcutter, at) > 0.6)
	assert_true(store.fear_at(woodcutter, at + Vector2(config.fear_radius * 0.5, 0)) > 0.2, "and around it")
	assert_true(store.fear_at(woodcutter, at + Vector2(config.fear_radius * 0.5, 0)) < store.fear_at(woodcutter, at), "less, further off")
	assert_eq(store.fear_at(woodcutter, at + Vector2(config.fear_radius + 0.1, 0)), 0.0)
	assert_true(places.feared(woodcutter, tree.tile))
	var calm_ones := 0
	for id: int in seen:
		if not places.feared(woodcutter, session.props.get_prop(id).tile):
			calm_ones += 1
	if calm_ones > 0:
		for i in 60:
			var chosen: Dictionary = places.work_place(woodcutter, &"tree", rng)
			assert_false(places.feared(woodcutter, chosen["tile"]), "they do not go back there to work")
			assert_ne(chosen["id"], dreaded)
	# Someone else has no such memory and goes there as before.
	var other := _make(session.people.all_people()[0] if session.people.all_people()[0].id != woodcutter.id else session.people.all_people()[1])
	assert_eq(store.fear_at(other, at), 0.0)
	# A look around goes elsewhere too.
	for i in 40:
		var tile: Variant = places.explore_tile(woodcutter, PersonData.LifeStage.ADULT, rng)
		if tile != null:
			assert_false(places.feared(woodcutter, tile))
	# Only what frightened counts, and only while it matters.
	fright.emotions[ReactionTable.Emotion.FEAR] = config.fear_matters_from - 0.05
	assert_eq(store.fear_at(woodcutter, at), 0.0, "wonder is not dread")
	fright.emotions[ReactionTable.Emotion.FEAR] = 0.9
	fright.importance = 0.05
	assert_true(store.fear_at(woodcutter, at) < 0.15, "fading with the memory")
	store.forget(woodcutter, fright.id)
	assert_eq(store.fear_at(woodcutter, at), 0.0, "forgotten: unafraid")
	# If everywhere is feared they work all the same (there is nowhere else).
	for id: int in seen:
		var dread := store.remember(woodcutter, _memory(StringName("fright_%d" % id), ReactionTable.SPIRIT, 0.9, 0, Memory.Source.WITNESSED, [1.0, 0, 0, 0, 0]))
		dread.location = session.props.get_prop(id).position2d()
	assert_false(places.work_place(woodcutter, &"tree", rng).is_empty())


func test_wonder_draws_people_closer_the_next_time() -> void:
	var person := _make(_adult())
	assert_eq(store.wonder_about(person, Stimulus.OBJECT_MOVED), 0.0, "nothing remembered, nothing either way")
	var at := person.world2d() + Vector2(3.0, 0.0)
	var moved := _stimulus(Stimulus.OBJECT_MOVED, at, 0.5)
	var perception := {"stimulus": moved, "salience": 0.7, "direct": false, "witnesses": 1}
	var plain := 0
	for i in 200:
		person.beliefs = PackedFloat32Array()
		person.knowledge = {}
		if Reactions.respond(person, perception, ctx, table).reaction == ReactionTable.INVESTIGATE:
			plain += 1
	# They remember the like of it with wonder.
	store.remember(person, _memory(Stimulus.OBJECT_MOVED, ReactionTable.UNKNOWN_INTELLIGENCE, 0.7, 0, Memory.Source.WITNESSED,
		[0.05, 0.9, 0.6, 0.2, 0.0]))
	assert_true(store.wonder_about(person, Stimulus.OBJECT_MOVED) > 0.7)
	assert_eq(store.wonder_about(person, Stimulus.KNOCK), 0.0, "about that, not about everything")
	var drawn := 0
	for i in 200:
		person.beliefs = PackedFloat32Array()
		person.knowledge = {}
		if Reactions.respond(person, perception, ctx, table).reaction == ReactionTable.INVESTIGATE:
			drawn += 1
	# ...or with dread.
	_make(person)
	store.remember(person, _memory(Stimulus.OBJECT_MOVED, ReactionTable.SPIRIT, 0.7, 0, Memory.Source.WITNESSED, [0.95, 0.1, 0.1, 0.0, 0.0]))
	assert_true(store.wonder_about(person, Stimulus.OBJECT_MOVED) < -0.7)
	var repelled := 0
	for i in 200:
		person.beliefs = PackedFloat32Array()
		person.knowledge = {}
		if Reactions.respond(person, perception, ctx, table).reaction == ReactionTable.INVESTIGATE:
			repelled += 1
	print("    a closer look, of 200: %d with nothing remembered, %d remembering wonder, %d remembering dread" % [plain, drawn, repelled])
	assert_true(drawn > plain * 1.5 and drawn > plain + 15, "wonder draws closer")
	assert_true(repelled < plain, "dread does not")
	# In the scores themselves.
	var with_wonder := Reactions.reaction_scores(person, ReactionTable.SPIRIT, PackedFloat32Array([0, 0, 0, 0, 0]), {}, 1.0,
		ReactionTable.REACTIONS, table, 0.5)
	var without := Reactions.reaction_scores(person, ReactionTable.SPIRIT, PackedFloat32Array([0, 0, 0, 0, 0]), {}, 1.0,
		ReactionTable.REACTIONS, table)
	assert_near(float(with_wonder[ReactionTable.INVESTIGATE]) - float(without[ReactionTable.INVESTIGATE]), 0.5, 0.0001)
	assert_near(float(with_wonder[ReactionTable.WAVE]) - float(without[ReactionTable.WAVE]), 0.25, 0.0001)
	assert_near(float(with_wonder[ReactionTable.RUN]) - float(without[ReactionTable.RUN]), -0.25, 0.0001)
	assert_near(float(with_wonder[ReactionTable.PRAY]), float(without[ReactionTable.PRAY]), 0.0001)


# --- finding things -------------------------------------------------------------------------------

## A stone the player has put down beside `person` (`minutes_ago` game minutes ago).
func _stone_beside(person: PersonData, minutes_ago: int, offset: Vector2 = Vector2(1.2, 0.3)) -> LooseObject:
	var stone: LooseObject = null
	for object in session.loose.all_objects():
		if object.kind == LooseObject.Kind.ROCK:
			stone = object
			break
	assert_not_null(stone, "a rock in the world")
	stone.position = person.world2d() + offset
	session.loose.touch(stone.id)
	session.spatial.move(stone.id, stone.position)
	stone.placed_by_player = true
	stone.discoverable = true
	stone.moved_count = 1
	stone.moved_tick = session.clock.tick - minutes_ago
	stone.discovered_by = PackedInt64Array()
	return stone


func test_someone_comes_upon_a_stone_that_was_not_there() -> void:
	var person := _make(_adult(), {Traits.Axis.CURIOSITY: 0.7, Traits.Axis.BRAVERY: 0.5})
	for p in session.people.all_people():
		if p.id != person.id:
			p.set_flag(PersonData.FLAG_INDOORS, true) # (nobody else about)
	behavior.set_plan(person, &"idle", &"routine", [RestStep.make(600.0)])
	var stone := _stone_beside(person, 120)
	var reacted: Array = []
	behavior.reacted.connect(func(id: int, reaction: StringName, _i: StringName, stimulus: StringName, direct: bool) -> void:
		reacted.append([id, reaction, stimulus, direct]))
	_run(float(Config.sim.think_ticks_tier3) + 1.0)
	# They looked up, saw it, and made something of it.
	assert_true(Discovery.knows(stone, person.id), "found")
	assert_eq(reacted.size(), 1)
	assert_eq(reacted[0][0], person.id)
	assert_eq(reacted[0][2], Stimulus.OBJECT_FOUND)
	assert_false(reacted[0][3])
	var memories := store.about(person, Stimulus.OBJECT_FOUND)
	assert_eq(memories.size(), 1, "and remember it")
	assert_has(MemoryText.text(memories[0]), "found a stone that was not there the day before")
	assert_true(memories[0].location.distance_to(stone.position) < 0.01)
	var outcome := behavior.last_outcome(person.id)
	assert_eq(outcome.stimulus.object_id, stone.id)
	assert_true(outcome.stimulus.id > 0)
	# Only once: it is there now.
	_run(60.0)
	assert_eq(reacted.size(), 1)
	assert_eq(store.about(person, Stimulus.OBJECT_FOUND)[0].count, 1)
	# Many curious people, many closer looks.
	session.movement.stop(person.id)
	stone.position = person.world2d() + Vector2(1.2, 0.3) # (wherever they have wandered meanwhile)
	session.spatial.move(stone.id, stone.position)
	var looks := 0
	for i in 100:
		_make(person, {Traits.Axis.CURIOSITY: 0.7, Traits.Axis.BRAVERY: 0.5})
		stone.discovered_by = PackedInt64Array()
		ctx.perceptions.clear()
		assert_true(Discovery.look_around(person, ctx))
		var perception: Dictionary = ctx.perceptions[person.id][0]
		if Reactions.respond(person, perception, ctx, table).reaction == ReactionTable.INVESTIGATE:
			looks += 1
	ctx.perceptions.clear()
	assert_true(looks >= 20, "the curious take a closer look (%d of 100)" % looks)


func test_what_is_not_found() -> void:
	var person := _make(_adult())
	behavior.set_plan(person, &"idle", &"routine", [RestStep.make(600.0)])
	# Only just put down: seen to land, if at all — not "found".
	var stone := _stone_beside(person, 0)
	assert_false(Discovery.look_around(person, ctx))
	stone.moved_tick = session.clock.tick - config.find_after_minutes
	# Too far to come upon.
	stone.position = person.world2d() + Vector2(config.find_radius + 1.0, 0)
	session.spatial.move(stone.id, stone.position)
	assert_false(Discovery.look_around(person, ctx))
	stone.position = person.world2d() + Vector2(1.0, 0)
	session.spatial.move(stone.id, stone.position)
	# Not something the player moved; not where the settlement's people pass; in the air.
	stone.placed_by_player = false
	assert_false(Discovery.look_around(person, ctx))
	stone.placed_by_player = true
	stone.discoverable = false
	assert_false(Discovery.look_around(person, ctx))
	stone.discoverable = true
	stone.state = LooseObject.State.HELD
	assert_false(Discovery.look_around(person, ctx))
	stone.state = LooseObject.State.RESTING
	# Already known to them.
	Discovery.note(stone, person.id)
	Discovery.note(stone, person.id)
	assert_eq(stone.discovered_by.size(), 1)
	assert_false(Discovery.look_around(person, ctx))
	assert_eq(ctx.perceptions.size(), 0)
	# Asleep or indoors, nobody looks about.
	stone.discovered_by = PackedInt64Array()
	person.set_flag(PersonData.FLAG_INDOORS, true)
	_run(float(Config.sim.think_ticks_tier3) * 3.0)
	assert_false(Discovery.knows(stone, person.id))
	person.set_flag(PersonData.FLAG_INDOORS, false)
	# Whoever saw it fly does not find it afterwards.
	_make(person)
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	var flew := _stimulus(Stimulus.OBJECT_MOVED, stone.position, 0.5)
	flew.object_id = stone.id
	session.perception.emit(flew)
	_run(1.0)
	assert_true(Discovery.knows(stone, person.id), "they saw it land")
	assert_eq(store.about(person, Stimulus.OBJECT_MOVED).size(), 1)
	_run(120.0)
	assert_eq(store.about(person, Stimulus.OBJECT_FOUND).size(), 0)


func test_a_stone_moved_again_is_found_again() -> void:
	var person := _make(_adult())
	var stone := _stone_beside(person, 500, Vector2(0.8, 0.0))
	Discovery.note(stone, person.id)
	# The player picks it up and puts it down a little further on.
	behavior.enabled = false # (nobody watching: this is about the stone)
	assert_true(session.interactions.grab(stone.id))
	session.interactions.carry(stone.id, stone.position + Vector2(1.0, 0.5), 0.5)
	assert_true(session.interactions.release(stone.id).applied)
	assert_eq(stone.discovered_by.size(), 0, "somewhere new: to be come upon anew")
	assert_eq(stone.moved_tick, session.clock.tick)
	var saved := stone.to_dict()
	assert_eq(saved["moved_tick"], session.clock.tick)
	assert_eq(LooseObject.from_dict(saved).moved_tick, session.clock.tick)
	assert_eq(LooseObject.from_dict({"id": 5, "kind": 1, "position": Vector2(1, 1)}).moved_tick, 0, "older saves: long ago")


# --- saving ---------------------------------------------------------------------------------------

func test_memories_are_kept_across_saves() -> void:
	var person := _make(_adult(), {Traits.Axis.SPIRITUALITY: 0.5})
	var other := _make(session.people.all_people()[-1])
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	_touch(person)
	_touch(person)
	var told := _memory(Stimulus.TREE_UPROOTED, ReactionTable.DEITY, 0.5, 77, Memory.Source.TOLD, [0.1, 0.2, 0.3, 0.4, 0.5])
	told.told_by = person.id
	told.fidelity = 0.72
	told.location = Vector2(3.5, -2.5)
	told.told_tick = 80
	told.text_key = "MEM_TOLD"
	store.remember(other, told)
	var lines := PersonCard.memory_lines_of(session, person, 5)
	var stimuli := ctx.next_stimulus_id
	assert_true(stimuli > 2)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	assert_true(SaveManager.SAVE_VERSION >= 6)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	assert_eq(again.memories.to_dict(), store.to_dict(), "every memory, as it was")
	var back := again.people.get_person(person.id)
	assert_eq(back.memory_ids, person.memory_ids)
	assert_eq(PersonCard.memory_lines_of(again, back, 5), lines, "in the same words")
	var heard := again.memories.of(again.people.get_person(other.id))[0]
	assert_eq(heard.source, Memory.Source.TOLD)
	assert_eq(heard.told_by, person.id)
	assert_near(heard.fidelity, 0.72, 0.0001)
	assert_eq(heard.location, Vector2(3.5, -2.5))
	assert_eq(heard.emotions, PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 0.5]))
	assert_eq(heard.told_tick, 80)
	# Numbers go on where they left off: stimuli and memories.
	assert_eq(again.behavior.ctx.next_stimulus_id, stimuli)
	var next := again.memories.remember(back, _memory(Stimulus.KNOCK, ReactionTable.NATURAL, 0.5, 0))
	assert_true(next.id > heard.id)
	again.queue_free()
	# A new world starts with nothing remembered.
	store.remember(person, _memory(Stimulus.KNOCK, ReactionTable.NATURAL, 0.5, 0))
	session.create_new(777)
	assert_eq(session.memories.size(), 0)
	for p in session.people.all_people():
		assert_eq(p.memory_ids.size(), 0)


func test_broken_memories_do_not_break_the_world() -> void:
	var person := _make(_adult())
	var good := store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.5, 10))
	var data := store.to_dict()
	var records: Array = data["memories"]
	records.append({"id": 0, "owner_id": person.id}) # no id
	records.append({"id": 900, "owner_id": 999_999, "subject": "touch"}) # nobody's
	records.append("nonsense")
	records.append({"id": good.id, "owner_id": person.id}) # twice
	records.append({"id": 901, "owner_id": person.id, "subject": "knock", "importance": NAN, "fidelity": 7.0,
		"emotions": PackedFloat32Array([9.0, NAN]), "source": 99, "count": -3, "location": Vector2(NAN, 0), "stage": 44})
	person.memory_ids.append(555) # an id that leads nowhere
	var skipped := store.from_dict(data)
	assert_eq(skipped, 4)
	assert_eq(store.size(), 2)
	assert_eq(person.memory_ids, PackedInt64Array([good.id, 901]), "their list holds what there is — also what was missing from it")
	var odd := store.get_memory(901)
	assert_eq(odd.importance, 0.0)
	assert_eq(odd.fidelity, 1.0)
	assert_eq(odd.emotions.size(), ReactionTable.EMOTION_COUNT)
	assert_eq(odd.emotions[0], 1.0)
	assert_eq(odd.emotions[1], 0.0)
	assert_eq(odd.source, Memory.Source.WRITTEN)
	assert_eq(odd.count, 1)
	assert_eq(odd.location, Vector2.ZERO)
	assert_ne(MemoryText.text(odd), "")
	assert_eq(store.from_dict({}), 0)
	assert_eq(store.size(), 0)
	assert_eq(person.memory_ids.size(), 0)
	assert_null(Memory.from_dict({}))
	# Someone who leaves the world takes their memories with them.
	store.remember(person, _memory(Stimulus.TOUCH, ReactionTable.SPIRIT, 0.5, 10))
	session.kill_person(person.id)
	assert_eq(store.size(), 0)


func test_version_5_save_migrates_and_its_people_remember() -> void:
	# Written by M5.3 (d74f19e): three people had been touched (one of them
	# three times); two were in the middle of running away. Nobody had memories.
	assert_true(FileAccess.file_exists(V5_FIXTURE), "fixture present")
	var dir := SaveManager.world_dir(V5_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V5_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 5)
	var loaded := SaveManager.load_world(V5_ID)
	assert_true(loaded.ok, loaded.error)
	var state: Dictionary = loaded.world["world_state"]
	assert_eq((state["memories"]["memories"] as Array).size(), 3, "migration: a memory for each who had been touched")
	assert_eq(state["perception"], {"next_stimulus_id": 1})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	_take(s)
	assert_eq(s.clock.tick, 250)
	assert_eq(s.people.size(), 8)
	var thrice := s.people.get_person(7)
	assert_eq(thrice.full_name(), "Fubrudu Skadou")
	assert_eq(Interpretation.familiarity(thrice, Stimulus.TOUCH), 3)
	var memory := s.memories.of(thrice)[0]
	assert_eq(memory.subject, Stimulus.TOUCH)
	assert_eq(memory.count, 3, "touched three times")
	assert_eq(memory.interpretation, ReactionTable.SPIRIT, "taken the way they were most convinced it was")
	assert_eq(memory.source, Memory.Source.DIRECT)
	assert_true(memory.fidelity < 1.0, "vaguer than what is lived with a memory")
	assert_eq(PersonCard.memory_lines_of(s, thrice, 5)[0], "Age %d · Felt the touch of a spirit (3 times)" % thrice.age_years(250, Config.time.ticks_per_year()))
	assert_eq(s.memories.of(s.people.get_person(8))[0].interpretation, ReactionTable.UNKNOWN_INTELLIGENCE)
	assert_eq(s.people.get_person(10).memory_ids.size(), 0, "nobody else remembers anything")
	# Whoever was running goes on running, and life goes on.
	assert_eq(BehaviorSystem.reaction_of(s.people.get_person(8)), ReactionTable.RUN)
	_run(120.0, 0.5, s)
	for p in s.people.all_people():
		assert_ne(BehaviorSystem.activity_of(p), &"", "%s lives" % p.given_name)
	# A fourth touch joins the memory of the three.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = thrice.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = thrice.position
	thrice.set_flag(PersonData.FLAG_INDOORS, false)
	s.interactions.tap(target)
	assert_eq(s.memories.times(thrice, Stimulus.TOUCH), 4)
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 5)
	s.queue_free()


func test_remembering_is_cheap() -> void:
	var everyone := session.people.all_people()
	while session.people.size() < 20:
		session.spawn_person(everyone[0].position)
	# Everyone holds a full head of memories.
	for p in session.people.all_people():
		for i in config.max_per_person:
			var memory := _memory(StringName("thing_%d" % i), ReactionTable.SPIRIT, 0.3 + 0.01 * i, i, Memory.Source.WITNESSED, [0.5, 0.2, 0.1, 0, 0])
			memory.location = p.world2d() + Vector2(i % 5, i % 3)
			store.remember(p, memory)
	assert_eq(store.size(), 20 * config.max_per_person)
	var started := Time.get_ticks_usec()
	var rounds := 200
	for i in rounds:
		var p := session.people.all_people()[i % 20]
		store.fear_at(p, p.world2d())
		store.wonder_about(p, &"thing_3")
	var each := (Time.get_ticks_usec() - started) / 1000.0 / rounds
	started = Time.get_ticks_usec()
	store.fade(1)
	var fading := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var bytes := var_to_bytes(store.to_dict()).size()
	var saving := (Time.get_ticks_usec() - started) / 1000.0
	print("    memory: %d memories; fear + wonder of one person %.3f ms; a day's fading %.2f ms; saved as %d bytes in %.2f ms" % [
		store.size(), each, fading, bytes, saving])
	assert_true(each < 0.5)
	assert_true(fading < 8.0)
