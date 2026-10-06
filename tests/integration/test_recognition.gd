extends TestCase
## VS.5: "that person remembers what I did" — someone who knows one of the
## player's acts, met by another, knows it again: a sign, a line on the card,
## a memory that goes back to the first — and the juice of the key moments.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	behavior = session.behavior
	ctx = behavior.ctx


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


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


func _set_hour(hour: float, day: int = 1) -> void:
	session.clock.tick = roundi((hour - Config.time.start_hour) * 60.0) + day * 1440


func _adult() -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == PersonData.LifeStage.ADULT:
			return p
	return null


func _touch(person: PersonData) -> void:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)


func _touch_memory(person: PersonData) -> Memory:
	var known := session.memories.about(person, Stimulus.TOUCH)
	return known[0] if not known.is_empty() else null


func test_someone_knows_a_touch_again() -> void:
	_set_hour(10.0)
	var person := _adult()
	_touch(person)
	_run(1.0)
	var first := behavior.last_outcome(person.id)
	assert_not_null(first)
	assert_null(first.recalled, "nothing of the player's known before")
	assert_false(BehaviorSystem.recognizes(person))
	var memory := _touch_memory(person)
	assert_not_null(memory)
	assert_eq(memory.recalls_tick, -1)
	var first_tick := memory.tick
	# Hours later, the same again.
	_set_hour(15.0)
	_touch(person)
	_run(0.5)
	var again := behavior.last_outcome(person.id)
	assert_ne(again, first)
	assert_not_null(again.recalled, "they know it")
	assert_eq(again.steps[0]["emote"], String(Reactions.RECOGNIZE_EMOTE), "the sign of it first")
	assert_eq(person.emote, Reactions.RECOGNIZE_EMOTE)
	assert_true(BehaviorSystem.recognizes(person))
	assert_true(PersonCard.activity_line(person).begins_with(UIText.REMEMBERS_THIS), "on the card")
	# Going back to the first time: one memory, twice — or, taken another way
	# this time (what it is made of is drawn by chance), a memory of its own
	# that recalls the first.
	var touches := session.memories.about(person, Stimulus.TOUCH)
	memory = touches[0]
	for m in touches:
		if m.tick > memory.tick:
			memory = m
	assert_eq(memory.recalls_tick, first_tick)
	assert_eq(memory.recalls_subject, Stimulus.TOUCH)
	var words := MemoryText.text(memory, session.people)
	if touches.size() == 1:
		assert_eq(memory.count, 2)
		assert_has(words, "(2 times) — just as ")
	else:
		assert_eq(touches.size(), 2, "a second way of taking it")
		assert_has(words, "just as ")
	assert_has(words, "earlier that day")
	assert_has(PersonCard.memory_lines_of(session, person, 1)[0], "just as")
	# Again at once: more of the same, not a recognition each time.
	_run(20.0)
	_touch(person)
	_run(0.5)
	assert_null(behavior.last_outcome(person.id).recalled)


func test_rain_brings_back_a_touch() -> void:
	_set_hour(10.0)
	var person := _adult()
	_touch(person)
	_run(40.0) # (and done reacting to it)
	assert_ne(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT)
	_set_hour(11.0, 30) # (a season on)
	session.memories.advance(session.clock.tick) # (the days between fade first)
	assert_not_null(_touch_memory(person), "still remembered")
	session.weather.hold(&"clear", session.clock.tick + 10_000)
	var iv := session.interactions.rain(person.world2d(), 0.0, Intervention.PHASE_BEGIN)
	assert_true(iv.applied)
	assert_true(bool(iv.params.get("clear_sky", false)))
	_run(3.0)
	var outcome := behavior.last_outcome(person.id)
	assert_not_null(outcome)
	assert_eq(outcome.stimulus.type, Stimulus.RAIN_FROM_CLEAR_SKY)
	assert_not_null(outcome.recalled)
	assert_eq(outcome.recalled.subject, Stimulus.TOUCH)
	var rained := session.memories.about(person, Stimulus.RAIN_FROM_CLEAR_SKY)
	assert_eq(rained.size(), 1)
	var words := MemoryText.text(rained[0], session.people)
	assert_has(words, "and thought of a touch from an unseen hand")
	assert_has(words, "by the fire, last spring") # (day 30: the next year)
	# Nature's rain is not the player's: nothing to know again.
	var nature := Stimulus.natural(Stimulus.RAIN_RETURNED, person.world2d(), session.clock.tick, Config.reactions)
	assert_null(Recognition.recalled(person, nature, session.memories))
	# Saved with it (and a memory from before VS.5 brings back nothing).
	var saved := Memory.from_dict(bytes_to_var(var_to_bytes(rained[0].to_dict())))
	assert_eq(saved.recalls_tick, rained[0].recalls_tick)
	assert_eq(saved.recalls_subject, Stimulus.TOUCH)
	assert_eq(saved.recalls_where, rained[0].recalls_where)
	var old := rained[0].to_dict()
	old.erase("recalls")
	assert_eq(Memory.from_dict(old).recalls_tick, -1)


func test_where_and_when_in_words() -> void:
	var fire := session.settlement.fire()
	var by_fire := Vector2(fire.tile) + Vector2(1.5, 0.5)
	assert_eq(Recognition.where_key(by_fire, session.world, session.props, session.settlements), Recognition.WHERE_FIRE)
	var wet := Vector2i(-1, -1)
	var b := session.world.bounds
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			if wet == Vector2i(-1, -1) and session.world.get_water(Vector2i(x, y)) > 0.3 and Vector2(Vector2i(x, y) - fire.tile).length() > 8.0:
				wet = Vector2i(x, y)
	assert_ne(wet, Vector2i(-1, -1), "the world has water")
	assert_eq(Recognition.where_key(Vector2(wet) + Vector2(0.5, 0.5), session.world, session.props, session.settlements),
		Recognition.WHERE_WATER)
	var day := TimeConfig.MINUTES_PER_DAY
	var season := Config.time.days_per_season * day
	var year := Config.time.ticks_per_year()
	assert_eq(Recognition.when_text(0, 60), "earlier that day")
	assert_eq(Recognition.when_text(0, day * 2), "earlier that spring")
	assert_eq(Recognition.when_text(0, season + day), "that spring")
	assert_eq(Recognition.when_text(season, year + 10), "last summer")
	assert_eq(Recognition.when_text(0, year * 3 + 10), "3 years before")


func test_the_juice_of_the_key_moments() -> void:
	# A touched person gives under the finger and springs back.
	var view: PersonView = load("res://scenes/people/person_view.tscn").instantiate()
	add_child(view)
	view.setup(StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new())
	view.poke(1.0)
	view.advance(0.08, view.position, 0.0)
	assert_true(absf(view.squash()) > 0.01, "squashed")
	for i in 10:
		view.advance(0.08, view.position, 0.0)
	assert_eq(view.squash(), 0.0, "and back")
	view.queue_free()
	# The view jolts when something heavy comes down, and settles.
	var rig := CameraRig.new()
	add_child(rig)
	rig.bump(1.0)
	rig.advance(0.05)
	assert_true(absf(rig.bump_offset()) > 0.0)
	rig.advance(1.0)
	assert_eq(rig.bump_offset(), 0.0)
	rig.queue_free()
	# Something heavy sends a ring of dust out; a pebble does not.
	var effects := WorldEffects.new()
	add_child(effects)
	effects.play_landing(Vector3.ZERO, ChunkData.Terrain.DIRT, false, 0.3, 1.0)
	assert_eq(effects.active_ring_count(), 0)
	effects.play_landing(Vector3.ZERO, ChunkData.Terrain.DIRT, false, 0.4, 0.2)
	assert_eq(effects.active_ring_count(), 1)
	var motes := effects.burst_count(WorldEffects.Burst.MOTES)
	effects.play_first_touch(Vector3.ZERO, 1.0)
	assert_eq(effects.burst_count(WorldEffects.Burst.MOTES), motes + 1)
	assert_eq(int(effects.played[WorldEffects.FIRST_TOUCH]), 1)
	effects.queue_free()
	# The chime of something known again.
	var chime := SoundSynth.samples_for(&"chime")
	assert_near(SoundSynth.seconds_of(chime), 1.1, 0.01)
	assert_true(SoundSynth.peak(chime) > 0.3 and SoundSynth.peak(chime) <= 1.0)
	assert_true(PeopleView.EMOTES.has(Reactions.RECOGNIZE_EMOTE))


func test_how_it_felt_leans_the_reaction() -> void:
	var glad := Memory.new()
	glad.emotions.resize(ReactionTable.EMOTION_COUNT)
	glad.emotions[ReactionTable.Emotion.JOY] = 1.0
	var scores := {ReactionTable.WAVE: 0.0, ReactionTable.RUN: 0.0, ReactionTable.LOOK: 0.0}
	Reactions._lean_on(scores, glad)
	assert_near(scores[ReactionTable.WAVE], Reactions.RECALL_LEAN, 0.001, "the glad wave")
	assert_eq(scores[ReactionTable.RUN], 0.0)
	assert_eq(scores[ReactionTable.LOOK], 0.0)
	assert_false(scores.has(ReactionTable.PRAY), "only what is open to them")
	var afraid := Memory.new()
	afraid.emotions.resize(ReactionTable.EMOTION_COUNT)
	afraid.emotions[ReactionTable.Emotion.FEAR] = 0.5
	Reactions._lean_on(scores, afraid)
	assert_near(scores[ReactionTable.RUN], Reactions.RECALL_LEAN * 0.5, 0.001, "the frightened run")
