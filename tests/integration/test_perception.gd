extends TestCase
## The interpretation system (M5.3, bible §14): stimulus → perception →
## interpretation → emotion → reaction, in the generated world. Time is
## stepped by hand.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var table: ReactionTable
var emitted: Array[Stimulus] = []
var reacted: Array = [] # [person id, reaction, interpretation, stimulus, direct]


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	table = Config.reactions
	session = _open(12345)


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
	emitted.clear()
	reacted.clear()
	s.interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void: emitted.append(stimulus))
	behavior.reacted.connect(func(id: int, reaction: StringName, interpretation: StringName, stimulus: StringName, direct: bool) -> void:
		reacted.append([id, reaction, interpretation, stimulus, direct]))


## Lets `minutes` of game time pass, the clock included.
func _run(minutes: float, step: float = 0.5) -> void:
	var left := minutes
	while left > 0.0001:
		var dt := minf(step, left)
		var seconds := dt * Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			session.clock.advance(piece)
			seconds -= piece
		behavior.step(dt)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		left -= dt


func _set_hour(hour: float) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440)


func _of(stage: PersonData.LifeStage) -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == stage:
			return p
	return null


## Someone grown, wide awake, with nothing on their mind and room around them.
func _adult() -> PersonData:
	return _of(PersonData.LifeStage.ADULT)


func _stimulus(type: StringName, at: Vector2, strength: float = 0.0, target: int = 0) -> Stimulus:
	var stimulus := Stimulus.new()
	stimulus.type = type
	stimulus.position = at
	stimulus.target_id = target
	table.describe(stimulus, strength)
	return stimulus


func _touch_of(person: PersonData) -> Stimulus:
	return _stimulus(Stimulus.TOUCH, person.world2d(), 0.0, person.id)


func _perception(stimulus: Stimulus, salience: float = 1.0, direct: bool = true, witnesses: int = 1) -> Dictionary:
	return {"stimulus": stimulus, "salience": salience, "direct": direct, "witnesses": witnesses}


## Makes someone of a given nature out of `person`: `leanings` is axis -> value;
## everything else is middling, and they have no convictions and no past.
func _make(person: PersonData, leanings: Dictionary = {}) -> PersonData:
	person.traits = Traits.neutral()
	for axis: int in leanings:
		person.traits[axis] = leanings[axis]
	person.beliefs = PackedFloat32Array()
	person.knowledge = {}
	person.needs = PackedFloat32Array([0.9, 0.9, 0.9, 0.9, 0.9, 1.0])
	return person


## Touches a person as the player does.
func _touch(person: PersonData) -> void:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)


func _tally(counts: Dictionary) -> String:
	var keys: Array = counts.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(counts[a]) > int(counts[b]))
	var parts := PackedStringArray()
	for key: Variant in keys:
		parts.append("%s %d" % [key, counts[key]])
	return ", ".join(parts)


## What `count` people of random nature (and `leanings` on top) make of and do
## about a stimulus: [interpretations -> count, reactions -> count].
func _sample(person: PersonData, type: StringName, direct: bool, leanings: Dictionary = {}, count: int = 300,
		strength: float = 0.5) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var made := {}
	var did := {}
	for i in count:
		person.traits = Traits.generate(rng)
		for axis: int in leanings:
			person.traits[axis] = leanings[axis]
		person.beliefs = PackedFloat32Array()
		person.knowledge = {}
		var at := person.world2d() if direct else person.world2d() + Vector2(2.5, 0.0)
		var stimulus := _stimulus(type, at, strength, person.id if direct else 0)
		var salience := 1.0 if direct else PerceptionSystem.salience(stimulus, 2.5, 1.0, table)
		var outcome := Reactions.respond(person, _perception(stimulus, salience, direct, 1 if direct else 3), ctx, table)
		made[outcome.interpretation] = int(made.get(outcome.interpretation, 0)) + 1
		did[outcome.reaction] = int(did.get(outcome.reaction, 0)) + 1
	return [made, did]


static func _share(counts: Dictionary, ids: Array, total: int) -> float:
	var sum := 0
	for id: StringName in ids:
		sum += int(counts.get(id, 0))
	return float(sum) / float(total)


# --- the table ------------------------------------------------------------------------------------

func test_the_reaction_table_is_complete() -> void:
	assert_eq(Config.reactions.validate().size(), 0, str(Config.reactions.validate()))
	assert_true(ResourceLoader.exists("res://data/configuration/reactions.tres"))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	for interpretation in ReactionTable.INTERPRETATIONS:
		assert_true(UIText.INTERPRETATION_PHRASES.has(interpretation), "words for %s" % interpretation)
		assert_true(table.interpretation_traits.has(interpretation))
		assert_true(table.interpretation_base.has(interpretation))
	for reaction in ReactionTable.REACTIONS + [ReactionTable.LISTEN]:
		assert_true(UIText.REACTION_PHRASES.has(reaction), "words for %s" % reaction)
		assert_true(table.minutes_for(reaction) >= 1.0)
	for type in Stimulus.TYPES:
		if type != Stimulus.TOLD:
			assert_true(table.stimuli.has(type), "numbers for %s" % type)
	# The order of interpretations is the order of saved convictions; of poses, of saved plans.
	assert_eq(ReactionTable.INTERPRETATIONS.slice(0, 4), [&"natural", &"spirit", &"deity", &"ancestor"] as Array[StringName])
	assert_eq(PersonData.Pose.SLEEP, 4)
	assert_eq(PersonData.Pose.STARTLE, 5)
	assert_eq(PersonData.Pose.SHRUG, 11)
	var broken := ReactionTable.new()
	broken.reactions.erase(&"pray")
	broken.child_emotions = PackedFloat32Array([0.0])
	assert_eq(broken.validate().size(), 2)


# --- stimulus -------------------------------------------------------------------------------------

func test_every_intervention_gives_off_a_stimulus() -> void:
	var interactions := session.interactions
	var person := _adult()
	behavior.enabled = false # (nobody reacts: this is about what is given off)
	_touch(person)
	assert_eq(emitted.size(), 1)
	var touch := emitted[0]
	assert_eq(touch.type, Stimulus.TOUCH)
	assert_eq(touch.target_id, person.id)
	assert_eq(touch.origin, Stimulus.Origin.PLAYER)
	assert_true(touch.anomalous)
	assert_near(touch.intensity, 0.8)
	assert_true(touch.position.distance_to(person.world2d()) < 0.01)
	assert_true(touch.id > 0, "numbered when it goes out")
	assert_eq(touch.intervention_id, session.history.total(), "it knows the intervention it came from")
	assert_eq(touch.tick, session.clock.tick)
	# A tree, the ground, a hut, water.
	var by_subject := {}
	interactions.intervention_applied.connect(func(iv: Intervention) -> void: by_subject[iv.subject] = Stimulus.type_for(iv))
	for prop in session.props.all_props():
		if by_subject.has(StringName(String(PropData.Kind.keys()[prop.kind]).to_lower())):
			continue
		var target := Picker.Result.new()
		target.kind = Picker.Kind.ENTITY
		target.entity_id = prop.id
		target.tile = prop.tile
		interactions.tap(target)
	assert_eq(by_subject.get(&"tree"), Stimulus.TREE_SHAKEN)
	assert_eq(by_subject.get(&"hut"), Stimulus.KNOCK)
	assert_eq(by_subject.get(&"campfire"), Stimulus.KNOCK)
	for small: StringName in [&"rock", &"bush"]:
		if by_subject.has(small):
			assert_eq(by_subject[small], Stimulus.GROUND_TOUCHED)
	var kinds := {}
	for stimulus in emitted:
		kinds[stimulus.type] = stimulus
	assert_true((kinds[Stimulus.TREE_SHAKEN] as Stimulus).weatherlike, "wind does that too")
	assert_true((kinds[Stimulus.TREE_SHAKEN] as Stimulus).radius > (kinds[Stimulus.GROUND_TOUCHED] as Stimulus).radius)
	assert_eq((kinds[Stimulus.TREE_SHAKEN] as Stimulus).target_id, 0, "only a touched person is a target")
	# The other kinds of intervention.
	var iv := Intervention.new()
	iv.applied = true
	for pair: Array in [[Intervention.UPROOT, &"tree", Stimulus.TREE_UPROOTED], [Intervention.GRAB, &"rock", Stimulus.OBJECT_LIFTED],
			[Intervention.MOVE_OBJECT, &"boulder", Stimulus.OBJECT_MOVED], [Intervention.SCOOP_WATER, &"water", Stimulus.WATER_TAKEN],
			[Intervention.POUR_WATER, &"water", Stimulus.WATER_POURED], [Intervention.TOUCH, &"water", Stimulus.WATER_DISTURBED],
			[Intervention.TOUCH, &"ground", Stimulus.GROUND_TOUCHED]]:
		iv.type = pair[0]
		iv.subject = pair[1]
		assert_eq(Stimulus.type_for(iv), pair[2], "%s of %s" % [pair[0], pair[1]])
		assert_not_null(Stimulus.from_intervention(iv, table))
	# More of it is stronger.
	iv.type = Intervention.MOVE_OBJECT
	iv.subject = &"pebble"
	var pebble := Stimulus.from_intervention(iv, table)
	iv.subject = &"boulder"
	var boulder := Stimulus.from_intervention(iv, table)
	assert_true(boulder.intensity > pebble.intensity + 0.2, "a boulder through the air is more than a pebble")
	assert_true(Stimulus.from_intervention(_uproot_iv(), table).large)
	# Nothing given off by what was not done.
	iv.applied = false
	assert_null(Stimulus.from_intervention(iv, table))
	assert_null(Stimulus.from_intervention(null, table))


func _uproot_iv() -> Intervention:
	var iv := Intervention.new()
	iv.applied = true
	iv.type = Intervention.UPROOT
	iv.subject = &"tree"
	return iv


# --- perception -----------------------------------------------------------------------------------

func test_salience_is_strength_nearness_attention_and_strangeness() -> void:
	var shaken := _stimulus(Stimulus.TREE_SHAKEN, Vector2.ZERO)
	var near := PerceptionSystem.salience(shaken, 1.0, 1.0, table)
	var far := PerceptionSystem.salience(shaken, shaken.radius - 0.1, 1.0, table)
	assert_true(near > far and far > 0.0, "nearer stands out more")
	assert_near(PerceptionSystem.salience(shaken, 0.0, 1.0, table), shaken.intensity * table.anomaly_factor)
	assert_near(PerceptionSystem.salience(shaken, shaken.radius, 1.0, table),
		shaken.intensity * table.anomaly_factor * table.edge_proximity)
	assert_near(PerceptionSystem.salience(shaken, 1.0, 0.5, table), near * 0.5, 0.0001, "half the attention, half of it")
	shaken.anomalous = false
	assert_true(PerceptionSystem.salience(shaken, 1.0, 1.0, table) < near, "what is expected stands out less")
	var uprooted := _stimulus(Stimulus.TREE_UPROOTED, Vector2.ZERO)
	assert_eq(PerceptionSystem.salience(uprooted, 0.0, 1.0, table), 1.0, "never more than everything")
	# Attention: by what they are at.
	var person := _adult()
	behavior.enabled = false
	person.pose = PersonData.Pose.IDLE
	person.current_action = {}
	assert_eq(PerceptionSystem.attention(person, ctx, table), 1.0)
	person.pose = PersonData.Pose.WORK
	assert_eq(PerceptionSystem.attention(person, ctx, table), table.attention_working)
	person.pose = PersonData.Pose.SLEEP
	assert_eq(PerceptionSystem.attention(person, ctx, table), table.attention_asleep)
	person.pose = PersonData.Pose.IDLE
	person.set_flag(PersonData.FLAG_INDOORS, true)
	assert_eq(PerceptionSystem.attention(person, ctx, table), table.attention_asleep)
	person.set_flag(PersonData.FLAG_INDOORS, false)
	person.current_action = {"activity": "react"}
	assert_eq(PerceptionSystem.attention(person, ctx, table), table.attention_reacting)
	person.current_action = {}
	session.movement.walk_to(person.id, person.position + Vector2i(3, 0))
	assert_eq(PerceptionSystem.attention(person, ctx, table), table.attention_walking)
	# A sleeper next to a shaken tree sleeps on; an uprooted one right beside them is another matter.
	assert_true(PerceptionSystem.salience(_stimulus(Stimulus.TREE_SHAKEN, Vector2.ZERO), 1.0, table.attention_asleep, table) < table.notice_threshold)
	assert_true(PerceptionSystem.salience(uprooted, 0.5, table.attention_asleep, table) >= table.notice_threshold)


func test_those_near_enough_notice_and_the_rest_do_not() -> void:
	_set_hour(11.0)
	var everyone := session.people.all_people()
	var middle := everyone[0]
	# Everyone stands in a row, two tiles apart, awake and idle.
	for i in everyone.size():
		var p := everyone[i]
		p.set_flag(PersonData.FLAG_INDOORS, false)
		p.pose = PersonData.Pose.IDLE
		p.current_action = {}
		session.people.move(p.id, middle.position + Vector2i(i * 2, 0), Vector2(0.5, 0.5), 0.0)
	var noticed: Array = []
	session.perception.noticed.connect(func(id: int, direct: bool) -> void: noticed.append([id, direct]))
	var shaken := _stimulus(Stimulus.TREE_SHAKEN, middle.world2d())
	var count := session.perception.emit(shaken)
	assert_eq(shaken.id, 1)
	assert_eq(session.perception.emitted, 1)
	assert_true(count >= 3 and count < everyone.size(), "some, not all (%d of %d)" % [count, everyone.size()])
	assert_eq(noticed.size(), count)
	for i in everyone.size():
		var p := everyone[i]
		var distance := p.world2d().distance_to(shaken.position)
		var pending: Array = ctx.perceptions.get(p.id, [])
		if distance > shaken.radius:
			assert_eq(pending.size(), 0, "%d tiles off: out of reach" % (i * 2))
		elif PerceptionSystem.salience(shaken, distance, 1.0, table) >= table.notice_threshold:
			assert_eq(pending.size(), 1, "%d tiles off: noticed" % (i * 2))
			assert_false(pending[0]["direct"])
			assert_eq(pending[0]["witnesses"], count)
			assert_near(pending[0]["salience"], PerceptionSystem.salience(shaken, distance, 1.0, table))
			assert_true(pending[0]["stimulus"] == shaken)
	# Nearer ones took it in more.
	assert_true(float(ctx.perceptions[everyone[0].id][0]["salience"]) > float(ctx.perceptions[everyone[1].id][0]["salience"]))
	# Someone asleep in reach does not notice; someone at work notices less.
	ctx.perceptions.clear()
	everyone[1].pose = PersonData.Pose.SLEEP
	session.perception.emit(_stimulus(Stimulus.TREE_SHAKEN, middle.world2d()))
	assert_false(ctx.perceptions.has(everyone[1].id))
	everyone[1].pose = PersonData.Pose.IDLE
	# A touch is taken in by whoever is touched — always, and only by them.
	ctx.perceptions.clear()
	noticed.clear()
	everyone[2].pose = PersonData.Pose.SLEEP
	assert_eq(session.perception.emit(_touch_of(everyone[2])), 1)
	assert_eq(noticed, [[everyone[2].id, true]], "nobody sees an unseen hand")
	assert_eq(ctx.perceptions.size(), 0, "and what happens to oneself is taken in at once")
	var taken := behavior.last_outcome(everyone[2].id)
	assert_true(taken.direct)
	assert_true(taken.salience >= table.notice_threshold)
	assert_has(session.perception.debug_text(), "touch")
	# Nobody there, nothing given off.
	assert_eq(session.perception.emit(null), 0)
	assert_eq(session.perception.emit(_stimulus(Stimulus.TREE_SHAKEN, Vector2(-500, -500))), 0)


# --- interpretation -------------------------------------------------------------------------------

func test_interpretation_variety() -> void:
	var person := _adult()
	var anyone := _sample(person, Stimulus.TOUCH, true, {}, 100)
	var made: Dictionary = anyone[0]
	print("    100 people touched make of it: %s" % _tally(made))
	assert_true(made.size() >= 4, "at least four different things (%s)" % _tally(made))
	for interpretation: StringName in made:
		assert_true(int(made[interpretation]) < 70, "no single answer for everyone (%s)" % _tally(made))
	# Who they are tilts it.
	var spiritual: Dictionary = _sample(person, Stimulus.TOUCH, true, {Traits.Axis.SPIRITUALITY: 0.8}, 300)[0]
	var skeptics: Dictionary = _sample(person, Stimulus.TOUCH, true, {Traits.Axis.SPIRITUALITY: -0.8}, 300)[0]
	print("    the spiritual: %s\n    the skeptical: %s" % [_tally(spiritual), _tally(skeptics)])
	var holy := [ReactionTable.SPIRIT, ReactionTable.DEITY]
	var plain := [ReactionTable.NATURAL, ReactionTable.HALLUCINATION]
	assert_true(_share(spiritual, holy, 300) > 0.8, "the spiritual see spirits and gods")
	assert_true(_share(skeptics, plain, 300) > 0.45, "skeptics see nothing much")
	assert_true(_share(skeptics, plain, 300) > _share(spiritual, plain, 300) * 4.0)
	assert_true(_share(spiritual, holy, 300) > _share(skeptics, holy, 300) * 2.0)
	# What it was tilts it too.
	var uprooted: Dictionary = _sample(person, Stimulus.TREE_UPROOTED, false)[0]
	var rustled: Dictionary = _sample(person, Stimulus.TREE_SHAKEN, false)[0]
	assert_true(int(uprooted.get(ReactionTable.DEITY, 0)) > int(rustled.get(ReactionTable.DEITY, 0)) * 3, "great things are a god's doing")
	assert_true(int(rustled.get(ReactionTable.NATURAL, 0)) > int(uprooted.get(ReactionTable.NATURAL, 0)), "small ones the wind's")
	assert_true(int(uprooted.get(ReactionTable.HALLUCINATION, 0)) < 15, "nobody imagines a tree torn out")


func test_what_cannot_occur_to_people_does_not() -> void:
	var person := _make(_adult())
	var touch := _touch_of(person)
	var circumstances := Interpretation.features(person, touch, true, 1, ctx, table)
	var scores := Interpretation.scores(person, touch, circumstances, ctx, table)
	for early: StringName in [ReactionTable.NATURAL, ReactionTable.SPIRIT, ReactionTable.DEITY, ReactionTable.HALLUCINATION,
			ReactionTable.UNKNOWN_INTELLIGENCE]:
		assert_true(scores.has(early), "%s can occur to anyone" % early)
	for later: StringName in [ReactionTable.ANCESTOR, ReactionTable.EXPERIMENT, ReactionTable.PHYSICS, ReactionTable.MULTIPLE_ENTITIES]:
		assert_false(scores.has(later), "%s cannot, yet" % later)
	# Knowledge opens them.
	person.knowledge["scientific_method"] = true
	person.knowledge["natural_philosophy"] = true
	scores = Interpretation.scores(person, touch, circumstances, ctx, table)
	assert_true(scores.has(ReactionTable.EXPERIMENT) and scores.has(ReactionTable.PHYSICS))
	assert_false(scores.has(ReactionTable.MULTIPLE_ENTITIES))
	# An ancestor can only be someone who has died.
	assert_false(Interpretation.knows_death(person, ctx))
	var parent: PersonData = null
	for p in session.people.all_people():
		if not p.children.is_empty():
			parent = p
			break
	var child := session.people.get_person(parent.children[0])
	_make(child)
	assert_false(Interpretation.available(child, ReactionTable.ANCESTOR, ctx, table))
	session.kill_person(parent.id)
	assert_true(Interpretation.knows_death(child, ctx))
	assert_true(Interpretation.available(child, ReactionTable.ANCESTOR, ctx, table), "now there is someone it could be")
	var ghosts := 0
	child.traits[Traits.Axis.LOYALTY] = 1.0
	child.traits[Traits.Axis.SPIRITUALITY] = 0.6
	for i in 100:
		child.beliefs = PackedFloat32Array()
		if Interpretation.choose(child, _touch_of(child), Interpretation.features(child, _touch_of(child), true, 1, ctx, table), ctx, table).choice == ReactionTable.ANCESTOR:
			ghosts += 1
	assert_true(ghosts > 5, "and sometimes it is (%d of 100)" % ghosts)


func test_what_speaks_for_an_interpretation() -> void:
	var person := _make(_adult())
	var touch := _touch_of(person)
	var circumstances := Interpretation.features(person, touch, true, 1, ctx, table)
	assert_eq(circumstances[&"direct"], 1.0)
	assert_eq(circumstances[&"alone"], 1.0)
	assert_eq(circumstances[&"local"], 1.0)
	assert_eq(circumstances[&"child"], 0.0)
	assert_eq(circumstances[&"familiar"], 0.0)
	assert_eq(circumstances[&"tired"], 0.0)
	var plain := Interpretation.scores(person, touch, circumstances, ctx, table)
	# Their nature.
	person.traits[Traits.Axis.SPIRITUALITY] = 1.0
	var devout := Interpretation.scores(person, touch, circumstances, ctx, table)
	assert_near(float(devout[ReactionTable.SPIRIT]) - float(plain[ReactionTable.SPIRIT]), 0.7, 0.001)
	assert_true(float(devout[ReactionTable.NATURAL]) < float(plain[ReactionTable.NATURAL]))
	person.traits[Traits.Axis.SPIRITUALITY] = 0.0
	# What they have made of things before (confirmation).
	Interpretation.update_beliefs(person, ReactionTable.DEITY, 1.0, table)
	assert_near(Interpretation.beliefs_of(person)[ReactionTable.INTERPRETATIONS.find(ReactionTable.DEITY)], table.belief_gain)
	var convinced := Interpretation.scores(person, touch, circumstances, ctx, table)
	assert_near(float(convinced[ReactionTable.DEITY]) - float(plain[ReactionTable.DEITY]), table.belief_gain * table.evidence_weight, 0.001)
	assert_eq(Interpretation.conviction(person), ReactionTable.DEITY)
	for i in 30:
		Interpretation.update_beliefs(person, ReactionTable.DEITY, 1.0, table)
	assert_true(Interpretation.beliefs_of(person)[2] > 0.95 and Interpretation.beliefs_of(person)[2] <= 1.0, "never more than certain")
	Interpretation.update_beliefs(person, ReactionTable.NATURAL, 1.0, table)
	assert_true(Interpretation.beliefs_of(person)[2] < 1.0 - table.belief_fade * 0.5, "another experience wears it down a little")
	person.beliefs = PackedFloat32Array()
	assert_eq(Interpretation.conviction(person), &"")
	# What those close to them believe.
	var partnered: PersonData = null
	for p in session.people.all_people():
		if p.partner_id != 0:
			partnered = p
			break
	_make(partnered)
	var partner := _make(session.people.get_person(partnered.partner_id))
	var at := _touch_of(partnered)
	var before := Interpretation.scores(partnered, at, circumstances, ctx, table)
	partner.beliefs = PackedFloat32Array([0, 1.0, 0, 0, 0, 0, 0, 0, 0])
	var after := Interpretation.scores(partnered, at, circumstances, ctx, table)
	assert_true(float(after[ReactionTable.SPIRIT]) > float(before[ReactionTable.SPIRIT]) + 0.05, "my partner believes in spirits")
	assert_near(float(after[ReactionTable.NATURAL]), float(before[ReactionTable.NATURAL]), 0.0001)
	# The circumstances: tired people imagine things; what happens again is someone's doing.
	person.needs[Needs.Need.SLEEP] = 0.05
	var tired := Interpretation.scores(person, touch, Interpretation.features(person, touch, true, 1, ctx, table), ctx, table)
	assert_true(float(tired[ReactionTable.HALLUCINATION]) > float(plain[ReactionTable.HALLUCINATION]) + 0.3)
	person.needs[Needs.Need.SLEEP] = 0.9
	for i in 6:
		Interpretation.note_experience(person, Stimulus.TOUCH)
	assert_eq(Interpretation.familiarity(person, Stimulus.TOUCH), 6)
	assert_eq(Interpretation.familiarity(person, Stimulus.KNOCK), 0)
	var again := Interpretation.scores(person, touch, Interpretation.features(person, touch, true, 1, ctx, table), ctx, table)
	assert_true(float(again[ReactionTable.UNKNOWN_INTELLIGENCE]) > float(plain[ReactionTable.UNKNOWN_INTELLIGENCE]) + 0.3)
	assert_true(float(again[ReactionTable.HALLUCINATION]) < float(plain[ReactionTable.HALLUCINATION]), "one does not imagine the same thing six times")
	# What they are told.
	_make(person)
	var told := Stimulus.telling(partner, Stimulus.TOUCH, ReactionTable.DEITY, 0.8, 0)
	var hearing := Interpretation.features(person, told, false, 2, ctx, table)
	var heard := Interpretation.scores(person, told, hearing, ctx, table)
	told.interpretation = ReactionTable.NATURAL
	var otherwise := Interpretation.scores(person, told, hearing, ctx, table)
	assert_near(float(heard[ReactionTable.DEITY]) - float(otherwise[ReactionTable.DEITY]), table.told_weight, 0.001)
	person.traits[Traits.Axis.SUSPICION] = 1.0
	told.interpretation = ReactionTable.DEITY
	var doubted := Interpretation.scores(person, told, hearing, ctx, table)
	told.interpretation = ReactionTable.NATURAL
	assert_near(float(doubted[ReactionTable.DEITY]) - float(Interpretation.scores(person, told, hearing, ctx, table)[ReactionTable.DEITY]),
		table.told_weight * 0.5, 0.001, "the suspicious take less on trust")


func test_what_people_like_me_believe_comes_from_the_world() -> void:
	var here := table.culture_prior(12345, 1, ReactionTable.SPIRIT)
	assert_eq(table.culture_prior(12345, 1, ReactionTable.SPIRIT), here, "the same every time")
	assert_true(here >= 0.0 and here <= table.culture_prior_spread)
	var differs := 0
	for interpretation in ReactionTable.INTERPRETATIONS:
		if not is_equal_approx(table.culture_prior(12345, 1, interpretation), table.culture_prior(777, 1, interpretation)):
			differs += 1
		assert_true(table.culture_prior(777, 2, interpretation) <= table.culture_prior_spread)
	assert_true(differs >= 7, "another world, other leanings")
	assert_ne(table.culture_prior(12345, 1, ReactionTable.DEITY), table.culture_prior(12345, 2, ReactionTable.DEITY), "another settlement too")
	assert_eq(ctx.world_seed, session.world_seed)
	# Children have weak priors.
	var child := _make(_of(PersonData.LifeStage.CHILD))
	var adult := _make(_adult())
	child.settlement_id = adult.settlement_id
	child.partner_id = 0
	child.parents = PackedInt64Array()
	adult.partner_id = 0
	adult.parents = PackedInt64Array()
	var touch_child := _touch_of(child)
	var touch_adult := _touch_of(adult)
	var of_child := Interpretation.scores(child, touch_child, {&"child": 1.0}, ctx, table)
	var of_adult := Interpretation.scores(adult, touch_adult, {}, ctx, table)
	for interpretation: StringName in of_child:
		if (table.interpretation_context.get(interpretation, {}) as Dictionary).has(&"child"):
			continue # (being a child counts for or against this one in itself)
		var prior := table.culture_prior(ctx.world_seed, adult.settlement_id, interpretation)
		assert_near(float(of_adult[interpretation]) - float(of_child[interpretation]), prior * (1.0 - table.child_prior_factor), 0.001)


func test_the_draw_is_weighted_and_repeatable() -> void:
	var scored := {&"a": 1.0, &"b": 0.8, &"c": -2.0}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var counts := {}
	for i in 1000:
		var id := Interpretation.draw(scored, 0.3, rng)
		counts[id] = int(counts.get(id, 0)) + 1
	assert_true(int(counts[&"a"]) > int(counts[&"b"]) and int(counts[&"b"]) > 200, "the likelier, the more often (%s)" % _tally(counts))
	assert_true(int(counts.get(&"c", 0)) < 5, "what is far behind hardly ever")
	# The same dice, the same answers — however the scores were put together.
	var other_order := {&"c": -2.0, &"b": 0.8, &"a": 1.0}
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 11
	second.seed = 11
	for i in 50:
		assert_eq(Interpretation.draw(scored, 0.3, first), Interpretation.draw(other_order, 0.3, second))
	assert_eq(Interpretation.draw({&"only": 0.0}, 0.3, null), &"only")
	# A cold head always takes the best.
	for i in 20:
		assert_eq(Interpretation.draw(scored, 0.0001, rng), &"a")


# --- emotion --------------------------------------------------------------------------------------

func test_feelings_come_from_what_it_was_who_they_are_and_how_strong() -> void:
	var person := _make(_adult())
	var touch := _touch_of(person)
	var fear := ReactionTable.Emotion.FEAR
	var plain := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 0, false, table)
	assert_eq(plain.size(), ReactionTable.EMOTION_COUNT)
	for value in plain:
		assert_true(value >= 0.0 and value <= 1.0)
	# Who they are.
	person.traits[Traits.Axis.BRAVERY] = -1.0
	var fearful := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 0, false, table)
	person.traits[Traits.Axis.BRAVERY] = 1.0
	var brave := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 0, false, table)
	assert_true(fearful[fear] > plain[fear] + 0.3 and brave[fear] < plain[fear] - 0.3, "%s %s %s" % [fearful[fear], plain[fear], brave[fear]])
	assert_true(brave[ReactionTable.Emotion.JOY] > fearful[ReactionTable.Emotion.JOY], "joy does not live beside fear")
	_make(person)
	# What they make of it.
	var godly := Reactions.emotions(person, ReactionTable.DEITY, touch, 1.0, true, 0, false, table)
	var nothing := Reactions.emotions(person, ReactionTable.NATURAL, touch, 1.0, true, 0, false, table)
	assert_true(godly[ReactionTable.Emotion.AWE] > 0.6 and nothing[ReactionTable.Emotion.AWE] < 0.05)
	assert_true(nothing[fear] < plain[fear])
	# How strong it was, and how much of it they took in.
	var faint := _stimulus(Stimulus.GROUND_TOUCHED, person.world2d())
	assert_true(Reactions.emotions(person, ReactionTable.SPIRIT, faint, 1.0, true, 0, false, table)[fear] < plain[fear])
	assert_true(Reactions.emotions(person, ReactionTable.SPIRIT, touch, 0.2, true, 0, false, table)[fear] < plain[fear] * 0.7)
	# Children wonder and laugh.
	var young := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 0, true, table)
	assert_true(young[ReactionTable.Emotion.JOY] > plain[ReactionTable.Emotion.JOY] + 0.2)
	assert_true(young[ReactionTable.Emotion.CURIOSITY] > plain[ReactionTable.Emotion.CURIOSITY] + 0.2)
	# What is only heard about is felt less.
	var told := Stimulus.telling(person, Stimulus.TOUCH, ReactionTable.SPIRIT, 0.8, 0)
	assert_true(Reactions.emotions(person, ReactionTable.SPIRIT, told, 1.0, false, 0, false, table)[ReactionTable.Emotion.AWE] \
		< plain[ReactionTable.Emotion.AWE] * 0.7)
	assert_near(Reactions.strongest(PackedFloat32Array([0.1, 0.7, 0.3])), 0.7)


func test_repetition_changes_what_is_felt() -> void:
	var person := _make(_adult())
	var touch := _touch_of(person)
	var fear := ReactionTable.Emotion.FEAR
	var awe := ReactionTable.Emotion.AWE
	var first := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 0, false, table)
	var tenth := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 9, false, table)
	assert_true(tenth[fear] < first[fear] * 0.6, "what frightened wears off (%.2f -> %.2f)" % [first[fear], tenth[fear]])
	assert_true(tenth[awe] < first[awe] * 0.6)
	assert_near(tenth[ReactionTable.Emotion.CURIOSITY], first[ReactionTable.Emotion.CURIOSITY], 0.001, "wondering does not")
	# The irritable have had enough; the trusting have come to like it.
	person.traits[Traits.Axis.AGGRESSION] = 0.8
	person.traits[Traits.Axis.SUSPICION] = 0.6
	var annoyed_first := Reactions.emotions(person, ReactionTable.NATURAL, touch, 1.0, true, 0, false, table)
	var annoyed_tenth := Reactions.emotions(person, ReactionTable.NATURAL, touch, 1.0, true, 9, false, table)
	assert_true(annoyed_tenth[ReactionTable.Emotion.ANNOYANCE] > annoyed_first[ReactionTable.Emotion.ANNOYANCE] + 0.4)
	_make(person, {Traits.Axis.SUSPICION: -0.9})
	var liked_first := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 0, false, table)
	var liked_tenth := Reactions.emotions(person, ReactionTable.SPIRIT, touch, 1.0, true, 9, false, table)
	assert_true(liked_tenth[ReactionTable.Emotion.JOY] > liked_first[ReactionTable.Emotion.JOY] + 0.3)
	# ...and it shows in what they do: the fearful run at first, far less later.
	_make(person, {Traits.Axis.BRAVERY: -0.7})
	var early := {}
	var late := {}
	for round in 150:
		person.beliefs = PackedFloat32Array()
		person.knowledge = {}
		var out := Reactions.respond(person, _perception(touch), ctx, table)
		early[out.reaction] = int(early.get(out.reaction, 0)) + 1
		person.knowledge = {"experienced": {"touch": 12}}
		out = Reactions.respond(person, _perception(touch), ctx, table)
		late[out.reaction] = int(late.get(out.reaction, 0)) + 1
	print("    someone fearful, first touch: %s\n    the same, thirteenth: %s" % [_tally(early), _tally(late)])
	assert_true(int(late.get(ReactionTable.RUN, 0)) < int(early.get(ReactionTable.RUN, 0)) * 0.6)


# --- reaction -------------------------------------------------------------------------------------

func test_reaction_mapping() -> void:
	var person := _adult()
	var fearful: Dictionary = _sample(person, Stimulus.TREE_UPROOTED, false, {Traits.Axis.BRAVERY: -0.8}, 300, 1.0)[1]
	print("    the fearful, a tree torn out beside them: %s" % _tally(fearful))
	assert_true(_share(fearful, [ReactionTable.RUN, ReactionTable.FREEZE], 300) > 0.55, "fearful and strong: run or freeze, mostly")
	var brave: Dictionary = _sample(person, Stimulus.TREE_UPROOTED, false, {Traits.Axis.BRAVERY: 0.8}, 300, 1.0)[1]
	assert_true(_share(brave, [ReactionTable.RUN, ReactionTable.FREEZE], 300) < 0.15, "the brave stand")
	# The spiritual pray; skeptics shrug or look; neither does the other's thing much.
	var spiritual: Dictionary = _sample(person, Stimulus.TOUCH, true, {Traits.Axis.SPIRITUALITY: 0.8})[1]
	var skeptics: Dictionary = _sample(person, Stimulus.TOUCH, true, {Traits.Axis.SPIRITUALITY: -0.8})[1]
	print("    touched, the spiritual: %s\n    touched, the skeptical: %s" % [_tally(spiritual), _tally(skeptics)])
	assert_true(_share(spiritual, [ReactionTable.PRAY], 300) > 0.5)
	assert_true(_share(skeptics, [ReactionTable.PRAY], 300) < 0.1)
	assert_true(_share(skeptics, [ReactionTable.DISMISS, ReactionTable.LOOK], 300) > 0.4)
	assert_true(_share(spiritual, [ReactionTable.DISMISS], 300) < 0.05)
	# Curious and unafraid: a closer look.
	var curious: Dictionary = _sample(person, Stimulus.OBJECT_MOVED, false, {Traits.Axis.CURIOSITY: 0.9, Traits.Axis.BRAVERY: 0.8})[1]
	var cautious: Dictionary = _sample(person, Stimulus.OBJECT_MOVED, false, {Traits.Axis.CURIOSITY: -0.9, Traits.Axis.BRAVERY: -0.3})[1]
	assert_true(int(curious.get(ReactionTable.INVESTIGATE, 0)) > int(cautious.get(ReactionTable.INVESTIGATE, 0)) * 3)
	# The irritable cry out more.
	var angry: Dictionary = _sample(person, Stimulus.TOUCH, true, {Traits.Axis.AGGRESSION: 0.9})[1]
	var gentle: Dictionary = _sample(person, Stimulus.TOUCH, true, {Traits.Axis.AGGRESSION: -0.9})[1]
	assert_true(int(angry.get(ReactionTable.YELL, 0)) > int(gentle.get(ReactionTable.YELL, 0)) * 2)
	# Children laugh and wave; they do not kneel.
	var child := _of(PersonData.LifeStage.CHILD)
	var children: Dictionary = _sample(child, Stimulus.TOUCH, true)[1]
	var adults: Dictionary = _sample(person, Stimulus.TOUCH, true)[1]
	print("    touched, children: %s\n    touched, grown people: %s" % [_tally(children), _tally(adults)])
	assert_true(_share(children, [ReactionTable.LAUGH, ReactionTable.WAVE], 300) > _share(adults, [ReactionTable.LAUGH, ReactionTable.WAVE], 300) * 3.0)
	assert_true(_share(children, [ReactionTable.PRAY], 300) < _share(adults, [ReactionTable.PRAY], 300) * 0.5)
	assert_true(adults.size() >= 6, "many different answers to the same touch (%d)" % adults.size())
	# Something small and far off is looked at or shrugged off.
	var faint: Dictionary = _sample(person, Stimulus.GROUND_TOUCHED, false)[1]
	assert_true(_share(faint, [ReactionTable.LOOK, ReactionTable.DISMISS], 300) > 0.75, _tally(faint))
	# What is nothing strange is never prayed to.
	_make(person)
	var scores := Reactions.reaction_scores(person, ReactionTable.NATURAL, PackedFloat32Array([0, 0, 1, 0, 0]), {}, 1.0,
		ReactionTable.REACTIONS, table)
	assert_true(float(scores[ReactionTable.PRAY]) < -5.0)


func test_what_can_be_done_depends_on_where_and_who_is_there() -> void:
	var person := _make(_adult())
	_set_hour(11.0)
	for other in session.people.all_people():
		other.set_flag(PersonData.FLAG_INDOORS, false)
		other.pose = PersonData.Pose.IDLE
	var touch := _touch_of(person)
	var options := Reactions.options_for(person, touch, true, ctx, table)
	assert_false(options.has(ReactionTable.INVESTIGATE), "what happened to oneself is not somewhere to walk to")
	assert_true(options.has(ReactionTable.RUN) and options.has(ReactionTable.TELL))
	var beside := _stimulus(Stimulus.OBJECT_MOVED, person.world2d() + Vector2(3.0, 0.0))
	assert_true(Reactions.options_for(person, beside, false, ctx, table).has(ReactionTable.INVESTIGATE))
	# Away means away from it.
	var flee: Variant = Reactions.flee_tile(person, beside, ctx, table)
	assert_not_null(flee)
	assert_true(Vector2(flee as Vector2i).distance_to(beside.position) > person.world2d().distance_to(beside.position) + 3.0)
	assert_true(session.pathfinder.can_stand(flee))
	assert_not_null(Reactions.flee_tile(person, touch, ctx, table), "from one's own spot: any way")
	assert_eq(Reactions.flee_tile(person, touch, ctx, table), Reactions.flee_tile(person, touch, ctx, table))
	# Whom to tell: the nearest who is up — family first. Nobody up: nobody to tell.
	var listener := Reactions.listener_for(person, ctx, table)
	assert_not_null(listener)
	assert_ne(listener.id, person.id)
	for other in session.people.all_people():
		if other.id != person.id:
			other.set_flag(PersonData.FLAG_INDOORS, true)
	assert_null(Reactions.listener_for(person, ctx, table))
	assert_false(Reactions.options_for(person, touch, true, ctx, table).has(ReactionTable.TELL))
	# A listener listens, prays or waves it away.
	var told := Stimulus.telling(person, Stimulus.TOUCH, ReactionTable.SPIRIT, 0.8, 0)
	assert_eq(Reactions.options_for(person, told, false, ctx, table), [ReactionTable.LOOK, ReactionTable.PRAY, ReactionTable.DISMISS] as Array[StringName])


func test_every_reaction_is_a_plan_that_shows() -> void:
	var person := _make(_adult())
	_set_hour(11.0)
	for other in session.people.all_people():
		other.set_flag(PersonData.FLAG_INDOORS, false)
		other.pose = PersonData.Pose.IDLE
	var beside := _stimulus(Stimulus.OBJECT_MOVED, person.world2d() + Vector2(3.0, 0.0), 0.5)
	var outcome := Reactions.Outcome.new()
	outcome.stimulus = beside
	outcome.interpretation = ReactionTable.SPIRIT
	outcome.emotions = PackedFloat32Array([0.5, 0.5, 0.5, 0.1, 0.0])
	var expected := {
		ReactionTable.LOOK: [[PersonData.Pose.IDLE, "question"]],
		ReactionTable.FREEZE: [[PersonData.Pose.STARTLE, "exclaim"]],
		ReactionTable.YELL: [[PersonData.Pose.YELL, "exclaim"]],
		ReactionTable.LAUGH: [[PersonData.Pose.JUMP, "note"]],
		ReactionTable.WAVE: [[PersonData.Pose.WAVE, "note"]],
		ReactionTable.PRAY: [[PersonData.Pose.STARTLE, "exclaim"], [PersonData.Pose.KNEEL, "pray"]],
		ReactionTable.DISMISS: [[PersonData.Pose.SHRUG, "dots"]],
		ReactionTable.LISTEN: [[PersonData.Pose.TALK, "question"]],
	}
	for reaction: StringName in expected:
		outcome.reaction = reaction
		var steps := Reactions.plan(person, outcome, ctx, table)
		var shown: Array = expected[reaction]
		assert_eq(steps.size(), shown.size(), String(reaction))
		for i in shown.size():
			assert_eq(steps[i]["type"], "react", String(reaction))
			assert_eq(steps[i]["pose"], int(shown[i][0]), String(reaction))
			assert_eq(steps[i]["emote"], shown[i][1], String(reaction))
			assert_eq(steps[i]["look"], beside.position, "turned to it")
			assert_true(PeopleView.EMOTES.has(StringName(steps[i]["emote"])), "a sign for %s" % steps[i]["emote"])
		assert_near(float(steps[-1]["minutes"]), table.minutes_for(reaction))
	# Running: a start, away at a run, a look back.
	outcome.reaction = ReactionTable.RUN
	var run := Reactions.plan(person, outcome, ctx, table)
	assert_eq(run.size(), 3)
	assert_eq(run[1]["type"], "walk_to")
	assert_near(float(run[1]["pace"]), table.run_pace)
	assert_eq(run[1]["emote"], "exclaim")
	assert_eq(run[1]["target"], Reactions.flee_tile(person, beside, ctx, table))
	assert_eq(run[2]["look"], beside.position, "looking back at it")
	# A closer look: over to it, down on one's haunches.
	outcome.reaction = ReactionTable.INVESTIGATE
	var look := Reactions.plan(person, outcome, ctx, table)
	assert_eq(look.size(), 3)
	assert_eq(look[1]["type"], "walk_to")
	assert_true(Vector2(look[1]["target"] as Vector2i).distance_to(Vector2(WorldCoords.world2d_to_tile(beside.position))) < 1.6, "right beside it")
	assert_eq(look[2]["pose"], int(PersonData.Pose.CROUCH))
	# Telling: a start, over to someone, the telling.
	outcome.reaction = ReactionTable.TELL
	var tell := Reactions.plan(person, outcome, ctx, table)
	assert_eq(tell.size(), 3)
	assert_eq(tell[2]["type"], "tell")
	assert_eq(tell[2]["listener"], Reactions.listener_for(person, ctx, table).id)
	assert_eq(tell[2]["about"], "object_moved")
	assert_eq(tell[2]["interpretation"], "spirit")
	# Any reaction can end in going to tell someone.
	outcome.reaction = ReactionTable.PRAY
	outcome.tells = true
	var both := Reactions.plan(person, outcome, ctx, table)
	assert_eq(both.size(), 4)
	assert_eq(both[-1]["type"], "tell")
	# What happens on the spot has nowhere to turn to.
	outcome.tells = false
	outcome.stimulus = _touch_of(person)
	outcome.reaction = ReactionTable.FREEZE
	assert_false(Reactions.plan(person, outcome, ctx, table)[0].has("look"))


# --- the whole of it, in the world ----------------------------------------------------------------

func test_a_touch_is_taken_in_at_once() -> void:
	var person := _make(_adult(), {Traits.Axis.SPIRITUALITY: 0.9, Traits.Axis.BRAVERY: 0.6})
	_set_hour(11.0)
	behavior.set_plan(person, &"idle", &"routine", [RestStep.make(60.0)])
	assert_null(behavior.last_outcome(person.id))
	_touch(person)
	# Before any time passes: they are reacting.
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT)
	var outcome := behavior.last_outcome(person.id)
	assert_not_null(outcome)
	assert_true(outcome.direct)
	assert_eq(outcome.stimulus.type, Stimulus.TOUCH)
	assert_eq(reacted.size(), 1, "and the world is told")
	assert_eq(reacted[0], [person.id, outcome.reaction, outcome.interpretation, Stimulus.TOUCH, true])
	assert_eq(BehaviorSystem.reaction_of(person), outcome.reaction)
	assert_eq(BehaviorSystem.reason_of(person), outcome.interpretation, "why: what they make of it")
	assert_eq(person.current_action["stimulus"], "touch")
	assert_eq((person.current_action["emotions"] as PackedFloat32Array).size(), ReactionTable.EMOTION_COUNT)
	assert_true(person.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	# It shows: a pose and a sign, from the first moment.
	var step := BehaviorSystem.current_step(person)
	assert_eq(person.emote, StringName(step["emote"]))
	assert_eq(int(person.pose), int(step["pose"]))
	assert_ne(person.emote, &"")
	# It is an experience, and it moves what they believe.
	assert_eq(Interpretation.familiarity(person, Stimulus.TOUCH), 1)
	assert_eq(Interpretation.conviction(person), outcome.interpretation)
	assert_false(ctx.perceptions.has(person.id), "taken in, not left lying")
	# The card says what and why.
	var line := PersonCard.activity_line(person)
	assert_eq(line, UIText.reaction_phrase(outcome.reaction, outcome.interpretation))
	assert_has(line, " — thinks ")
	assert_has(AiInspector.describe(session, person), "noticed: touch (direct)")
	assert_has(AiInspector.describe(session, person), "felt: fea ")
	# It runs its course; then life goes on.
	var total := 0.0
	for s: Dictionary in person.current_action["steps"]:
		total += float(s.get("minutes", 8.0))
	_run(total + 30.0)
	assert_ne(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT, "over")
	assert_eq(person.emote, &"", "the sign is gone")
	assert_true(ctx.activities.get_def(BehaviorSystem.activity_of(person)) != null or BehaviorSystem.activity_of(person) == BehaviorSystem.ACTIVITY_REACT \
		or BehaviorSystem.activity_of(person) == BehaviorSystem.ACTIVITY_IDLE, "back to their day (%s)" % BehaviorSystem.activity_of(person))
	assert_true(person.activity_log.has("react"))


func test_reacting_is_not_dropped_for_a_need_but_for_another_touch() -> void:
	var person := _make(_adult(), {Traits.Axis.BRAVERY: 0.9, Traits.Axis.SPIRITUALITY: 0.9})
	_set_hour(11.0)
	_touch(person)
	var first := person.current_action
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT)
	# Starving, parched — still they finish being amazed.
	person.needs = PackedFloat32Array([0.02, 0.02, 0.9, 0.9, 0.9, 1.0])
	_run(1.5)
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT)
	assert_true(is_same(person.current_action, first), "the same reaction")
	# Something lesser beside them while they are at it: not worth starting over.
	var lesser := _stimulus(Stimulus.TREE_SHAKEN, person.world2d() + Vector2(1.0, 0.0))
	session.perception.emit(lesser)
	assert_true(ctx.perceptions.has(person.id), "they notice it")
	_run(1.0)
	assert_true(is_same(person.current_action, first))
	assert_eq(Interpretation.familiarity(person, Stimulus.TREE_SHAKEN), 1, "noticed all the same")
	assert_eq(_reactions_of(person.id), 1)
	# Another touch: they react to that.
	_touch(person)
	assert_false(is_same(person.current_action, first))
	assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT)
	assert_eq(_reactions_of(person.id), 2)
	assert_eq(Interpretation.familiarity(person, Stimulus.TOUCH), 2)
	# Then, hungry as they are, they go and eat.
	_run(40.0)
	assert_true(person.activity_log.has("eat") or person.activity_log.has("drink") or BehaviorSystem.activity_of(person) in [&"eat", &"drink"],
		"the needs get their turn (%s)" % BehaviorSystem.activity_of(person))


func _reactions_of(person_id: int) -> int:
	var count := 0
	for entry: Array in reacted:
		if entry[0] == person_id:
			count += 1
	return count


func test_with_the_people_frozen_nothing_is_made_of_a_touch() -> void:
	var person := _make(_adult())
	behavior.enabled = false
	var before := person.current_action.duplicate(true)
	_touch(person)
	assert_eq(person.current_action, before)
	assert_eq(reacted.size(), 0)
	assert_null(behavior.last_outcome(person.id))
	assert_true(person.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER), "touched they were")
	# Thawed, they do not suddenly react to what happened while the world stood still.
	behavior.enabled = true
	_run(2.0)
	assert_eq(reacted.size(), 0)


func test_people_who_see_something_react_at_their_next_turn() -> void:
	_set_hour(11.0)
	var everyone := session.people.all_people()
	var middle := everyone[0]
	for i in everyone.size():
		var p := _make(everyone[i], {Traits.Axis.CURIOSITY: 0.5})
		p.set_flag(PersonData.FLAG_INDOORS, false)
		session.people.move(p.id, middle.position + Vector2i(i * 2, 0), Vector2(0.5, 0.5), 0.0)
		behavior.set_plan(p, &"idle", &"routine", [RestStep.make(120.0)])
	var prompted: Array = []
	behavior.prompted.connect(func(id: int) -> void: prompted.append(id))
	# A boulder comes down beside the first of them.
	var iv := Intervention.new()
	iv.type = Intervention.MOVE_OBJECT
	iv.subject = &"boulder"
	iv.applied = true
	iv.position = Vector3(middle.world2d().x, 0.0, middle.world2d().y + 1.0)
	var landed := Stimulus.from_intervention(iv, table)
	var count := session.perception.emit(landed)
	assert_true(count >= 3)
	assert_eq(prompted.size(), count, "each of them is given their turn at once")
	assert_eq(reacted.size(), 0, "but nobody has reacted before their turn")
	_run(1.0)
	assert_eq(reacted.size(), count, "now they have")
	var reactions := {}
	for entry: Array in reacted:
		assert_false(entry[4], "none of them was touched")
		assert_eq(entry[3], Stimulus.OBJECT_MOVED)
		reactions[entry[1]] = true
		var who := session.people.get_person(entry[0])
		assert_true(who.world2d().distance_to(landed.position) <= landed.radius + 0.5)
		assert_eq(Interpretation.familiarity(who, Stimulus.OBJECT_MOVED), 1)
	# Those out of reach go on standing about.
	for p in everyone:
		if p.world2d().distance_to(landed.position) > landed.radius + 0.5:
			assert_eq(BehaviorSystem.activity_of(p), &"idle")
	# Whoever stands still turns to where it happened.
	for entry: Array in reacted:
		var who := session.people.get_person(entry[0])
		var step := BehaviorSystem.current_step(who)
		if step.get("type") == "react" and step.has("look") and who.id != middle.id:
			var to := landed.position - who.world2d()
			assert_true(absf(angle_difference(who.facing, to.angle())) < 0.01, "%s looks at it" % who.given_name)
	assert_eq(behavior.reactions, count)


func test_someone_running_runs() -> void:
	var person := _make(_adult())
	_set_hour(11.0)
	var beside := _stimulus(Stimulus.TREE_UPROOTED, person.world2d() + Vector2(1.5, 0.0))
	var outcome := Reactions.Outcome.new()
	outcome.stimulus = beside
	outcome.reaction = ReactionTable.RUN
	outcome.emotions = PackedFloat32Array([1, 0, 0, 0, 0])
	var steps := Reactions.plan(person, outcome, ctx, table)
	var from := person.world2d()
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_REACT, ReactionTable.SPIRIT, steps)
	assert_eq(person.pose, PersonData.Pose.STARTLE, "first the fright")
	assert_eq(person.emote, &"exclaim")
	_run(table.startle_minutes + 0.5)
	assert_true(session.movement.is_walking(person.id), "then away")
	assert_eq(person.emote, &"exclaim", "the fright goes with them")
	var start := person.world2d()
	_run(4.0)
	var covered := person.world2d().distance_to(start)
	var usual := session.movement.speed_of(person, person.position) * 4.0
	assert_true(covered > usual * 1.5 or not session.movement.is_walking(person.id), "faster than a walk (%.1f against %.1f)" % [covered, usual])
	_run(30.0)
	assert_true(person.world2d().distance_to(beside.position) > from.distance_to(beside.position) + 3.0, "well away from it")


func test_telling_someone_passes_it_on() -> void:
	_set_hour(11.0)
	var everyone := session.people.all_people()
	var teller := _make(everyone[0], {Traits.Axis.SOCIABILITY: 0.9})
	var listener := _make(everyone[1], {Traits.Axis.SPIRITUALITY: 0.5})
	for p in everyone:
		p.set_flag(PersonData.FLAG_INDOORS, p.id != teller.id and p.id != listener.id) # only these two are up
		# (Held where they are: someone merely idle would wander off.)
		behavior.set_plan(p, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(300.0)])
	session.people.move(listener.id, teller.position + Vector2i(4, 0), Vector2(0.5, 0.5), 0.0)
	var touch := _touch_of(teller)
	var outcome := Reactions.Outcome.new()
	outcome.stimulus = touch
	outcome.reaction = ReactionTable.TELL
	outcome.interpretation = ReactionTable.DEITY
	outcome.emotions = PackedFloat32Array([0.2, 0.5, 0.9, 0.3, 0.0])
	behavior.set_plan(teller, BehaviorSystem.ACTIVITY_REACT, ReactionTable.DEITY, Reactions.plan(teller, outcome, ctx, table))
	teller.current_action["reaction"] = "tell"
	assert_eq(PersonCard.activity_line(teller), "Going to tell someone — thinks a god reached down")
	var before := Interpretation.beliefs_of(listener).duplicate()
	var company := Needs.value(teller.needs, Needs.Need.SOCIAL)
	_run(30.0)
	# The teller went over and talked.
	assert_true(teller.world2d().distance_to(listener.world2d()) <= TellStep.EARSHOT, "they stood together")
	# The listener heard of it, second hand, and made something of it.
	assert_eq(reacted.size(), 1, "one reaction: the listener's")
	assert_eq(reacted[0][0], listener.id)
	assert_eq(reacted[0][3], Stimulus.TOUCH, "about the touch")
	assert_false(reacted[0][4])
	assert_true(reacted[0][1] in [ReactionTable.LISTEN, ReactionTable.PRAY, ReactionTable.DISMISS], str(reacted[0][1]))
	var heard := behavior.last_outcome(listener.id)
	assert_eq(heard.stimulus.type, Stimulus.TOLD)
	assert_eq(heard.stimulus.told_by, teller.id)
	assert_eq(heard.stimulus.interpretation, ReactionTable.DEITY)
	assert_false(heard.tells, "what is only heard is not carried further (yet)")
	assert_eq(Interpretation.familiarity(listener, Stimulus.TOUCH), 1, "they have heard of such a thing now")
	assert_ne(Interpretation.beliefs_of(listener), before, "and believe a little differently")
	assert_true(Needs.value(teller.needs, Needs.Need.SOCIAL) >= company - 0.05, "telling is company")
	# Told a hundred times, people take the teller's view more often than not.
	var agreed := 0
	for i in 100:
		_make(listener)
		var told := Stimulus.telling(teller, Stimulus.TOUCH, ReactionTable.DEITY, 0.8, 0)
		if Reactions.respond(listener, _perception(told, 0.8, false, 2), ctx, table).interpretation == ReactionTable.DEITY:
			agreed += 1
	assert_true(agreed > 55, "being told sways (%d of 100)" % agreed)
	# Nobody to tell: the telling comes to nothing, quietly.
	behavior.set_plan(teller, BehaviorSystem.ACTIVITY_REACT, ReactionTable.DEITY,
		[TellStep.make(listener.id, 5.0, Stimulus.TOUCH, ReactionTable.DEITY, 0.8)])
	assert_eq(teller.emote, &"speech")
	listener.set_flag(PersonData.FLAG_INDOORS, true)
	_run(2.0)
	assert_ne(BehaviorSystem.current_step(teller).get("type"), "tell")
	assert_eq(teller.emote, &"")


func test_a_reaction_is_kept_across_saves() -> void:
	var person := _make(_adult(), {Traits.Axis.SPIRITUALITY: 0.9, Traits.Axis.BRAVERY: 0.8})
	_set_hour(11.0)
	var touch := _touch_of(person)
	var outcome := Reactions.Outcome.new()
	outcome.stimulus = touch
	outcome.reaction = ReactionTable.PRAY
	outcome.interpretation = ReactionTable.SPIRIT
	outcome.emotions = PackedFloat32Array([0.1, 0.2, 0.9, 0.2, 0.0])
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_REACT, ReactionTable.SPIRIT, Reactions.plan(person, outcome, ctx, table))
	person.current_action["reaction"] = "pray"
	person.current_action["emotions"] = outcome.emotions
	Interpretation.update_beliefs(person, ReactionTable.SPIRIT, 1.0, table)
	Interpretation.note_experience(person, Stimulus.TOUCH)
	_run(table.startle_minutes + 1.0)
	assert_eq(person.pose, PersonData.Pose.KNEEL)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	_take(again)
	var back := again.people.get_person(person.id)
	assert_eq(BehaviorSystem.activity_of(back), BehaviorSystem.ACTIVITY_REACT)
	assert_eq(BehaviorSystem.reaction_of(back), ReactionTable.PRAY)
	assert_eq(PersonCard.activity_line(back), "Praying — thinks a spirit is near")
	assert_eq(back.beliefs, person.beliefs, "what they believe")
	assert_eq(Interpretation.familiarity(back, Stimulus.TOUCH), 1, "and what they have been through")
	assert_eq(back.current_action["emotions"], person.current_action["emotions"])
	assert_eq(back.pose, PersonData.Pose.IDLE, "(poses and signs are not saved...)")
	var s := again
	var left := 1.0
	while left > 0.0:
		s.clock.advance(0.25)
		s.behavior.step(0.5)
		left -= 0.5
	assert_eq(back.pose, PersonData.Pose.KNEEL, "...they come back as the step is taken up again")
	assert_eq(back.emote, &"pray")
	again.queue_free()


func test_perception_is_cheap() -> void:
	_set_hour(11.0)
	var everyone := session.people.all_people()
	var middle := everyone[0]
	while session.people.size() < 20:
		session.spawn_person(middle.position)
	for p in session.people.all_people():
		p.set_flag(PersonData.FLAG_INDOORS, false)
		behavior.set_plan(p, &"idle", &"routine", [RestStep.make(600.0)])
	var started := Time.get_ticks_usec()
	var rounds := 50
	for i in rounds:
		session.perception.emit(_stimulus(Stimulus.TREE_UPROOTED, middle.world2d()))
		behavior.step(1.0)
	var each := (Time.get_ticks_usec() - started) / 1000.0 / rounds
	print("    perception: a stimulus noticed by %d people, interpreted and reacted to: %.3f ms" % [session.perception.last_noticed, each])
	assert_true(session.perception.last_noticed >= 15)
	assert_true(each < 4.0, "%.2f ms" % each)
