extends TestCase
## The day log (M6.4): what everyone has been doing, written down as they
## turn from one thing to the next, and read back as a line of their day —
## and the count of how long the player stays with one person (OBSERVER).

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var log: DayLog
var unlocked: Array[StringName] = []


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
	log = session.day_log
	unlocked.clear()
	EventBus.achievement_unlocked.connect(_on_unlocked)


func after_each() -> void:
	EventBus.achievement_unlocked.disconnect(_on_unlocked)
	session.queue_free()
	await wait_frames(1)


func _on_unlocked(id: StringName) -> void:
	unlocked.append(id)


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


## The tick of an hour of the world's first day (which begins at start_hour).
func _tick_at(hour: float, day: int = 0) -> int:
	return roundi((hour - Config.time.start_hour) * 60.0) + day * 1440


func _set_hour(hour: float) -> void:
	session.clock.tick = _tick_at(hour, 1)


func _adult(occupation: StringName = &"woodcutter") -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


func _child() -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == PersonData.LifeStage.CHILD:
			return p
	return null


func _kinds(person_id: int) -> Array:
	var out: Array = []
	for entry: Array in log.of(person_id):
		out.append(entry[DayLog.KIND])
	return out


func _touch(person: PersonData) -> void:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)


# --- the log itself -------------------------------------------------------------------------------

func test_the_log_keeps_what_someone_turned_to() -> void:
	var book := DayLog.new()
	assert_eq(book.of(5), [])
	assert_true(book.note(5, 100, "eat", "meal"))
	assert_true(book.note(5, 160, "work", "tree"))
	assert_eq(book.of(5), [[100, "eat", "meal", 0], [160, "work", "tree", 0]])
	# Going on with the same thing is not news; the same thing with someone else is.
	assert_false(book.note(5, 200, "work", "tree"))
	assert_true(book.note(5, 300, "socialize", "", 7))
	assert_false(book.note(5, 320, "socialize", "", 7))
	assert_eq(book.of(5)[-1], [300, "socialize", "", 7])
	# From one person to the next is the same talk, with more people in it.
	assert_false(book.note(5, 340, "socialize", "", 8))
	assert_false(book.note(5, 350, "socialize", "", 7))
	assert_eq(book.of(5)[-1], [300, "socialize", DayLog.MORE, 7])
	assert_eq(book.of(5).size(), 3)
	assert_true(book.note(5, 360, "drink"))
	assert_true(book.note(5, 370, "socialize", "", 8), "after something else it is a new talk")
	assert_eq(book.of(5).size(), 5)
	# What was given up within minutes never really happened...
	assert_true(book.note(5, 400, "explore"))
	assert_true(book.note(5, 401, "drink"))
	assert_eq(book.of(5)[-1], [401, "drink", "", 0])
	assert_eq(book.of(5)[-2], [370, "socialize", "", 8], "the minute of exploring is gone")
	# ...and a moment away from something is not a new beginning of it.
	assert_true(book.note(5, 500, "work", "tree"))
	assert_true(book.note(5, 560, "drink"))
	assert_false(book.note(5, 561, "work", "tree"), "back at it: the sip is forgotten, the work goes on")
	assert_eq(book.of(5)[-1], [500, "work", "tree", 0])
	# Moments stand, however brief, and what follows them is told again.
	assert_true(book.note(5, 600, DayLog.REACT, "run:touch"))
	assert_true(book.note(5, 601, "work", "tree"), "at work again after the fright")
	assert_true(book.note(5, 602, DayLog.REACT, "run:touch"), "a second fright is a second entry")
	assert_true(book.note(5, 900, "sleep"))
	assert_true(book.note(5, 1000, DayLog.STIR))
	assert_true(book.note(5, 1001, DayLog.STIR))
	assert_true(book.note(5, 1300, DayLog.WAKE))
	assert_true(book.note(5, 1300, "drink"))
	assert_eq(book.of(5)[-2][DayLog.KIND], DayLog.WAKE, "waking stands though something follows at once")
	# Back to bed for a minute and up again is the same waking.
	var riser := DayLog.new()
	riser.note(2, 1000, DayLog.WAKE)
	riser.note(2, 1000, "sleep")
	assert_false(riser.note(2, 1002, DayLog.WAKE))
	riser.note(2, 1002, "drink")
	assert_eq(riser.of(2), [[1000, DayLog.WAKE, "", 0], [1002, "drink", "", 0]])
	# Nothing for nobody, nothing without a kind.
	assert_false(book.note(0, 10, "eat"))
	assert_false(book.note(5, 10, ""))
	# Each person has their own.
	book.note(6, 50, "play")
	assert_eq(book.people_count(), 2)
	assert_eq(book.of(6), [[50, "play", "", 0]])
	book.forget(6)
	assert_eq(book.of(6), [])
	assert_eq(book.people_count(), 1)
	# A ring: the oldest make room, and nothing older than two days is kept.
	var ring := DayLog.new()
	for i in 60:
		ring.note(1, i * 10, "work" if i % 2 == 0 else "drink")
	assert_eq(ring.of(1).size(), DayLog.MAX_ENTRIES)
	assert_eq(ring.of(1)[-1][DayLog.TICK], 590)
	assert_eq(ring.of(1)[0][DayLog.TICK], 590 - (DayLog.MAX_ENTRIES - 1) * 10)
	ring.note(1, 590 + DayLog.KEEP_MINUTES + 5, "eat")
	assert_eq(ring.of(1).size(), 1, "all of that was long ago")
	assert_eq(ring.entry_count(), 1)


func test_days_are_told_apart() -> void:
	var book := DayLog.new()
	var config := Config.time
	# The first day begins at six: its midnight is 18 hours in.
	book.note(3, _tick_at(6.5), DayLog.WAKE)
	book.note(3, _tick_at(7.0), "eat", "meal")
	book.note(3, _tick_at(21.0), "sleep")
	assert_eq(book.of_day(3, 0, config).size(), 3)
	assert_eq(book.of_day(3, 1, config), [])
	# In the evening: today.
	var latest := book.latest_day(3, _tick_at(22.0), config)
	assert_eq(latest[0], 0)
	assert_eq((latest[1] as Array).size(), 3)
	# In the small hours of the next day there is nothing of today yet: yesterday's is shown.
	latest = book.latest_day(3, _tick_at(3.0, 1), config)
	assert_eq(latest[0], 0, "yesterday")
	assert_eq((latest[1] as Array).size(), 3)
	# Once they are up, the day is today's.
	book.note(3, _tick_at(6.0, 1), DayLog.WAKE)
	latest = book.latest_day(3, _tick_at(6.2, 1), config)
	assert_eq(latest[0], 1)
	assert_eq(latest[1], [[_tick_at(6.0, 1), DayLog.WAKE, "", 0]])
	# Someone of whom nothing is known.
	assert_eq(book.latest_day(99, _tick_at(9.0), config), [0, []])


func test_the_log_is_saved() -> void:
	var book := DayLog.new()
	book.note(5, 100, "eat", "meal")
	book.note(5, 160, "socialize", "", 7)
	book.note(9, 20, DayLog.REACT, "run:touch")
	book.note(11, 5, "play")
	book.forget(11)
	var saved := book.to_dict()
	var again := DayLog.new()
	assert_eq(again.from_dict(saved.duplicate(true)), 0)
	assert_eq(again.of(5), book.of(5))
	assert_eq(again.of(9), [[20, DayLog.REACT, "run:touch", 0]])
	assert_eq(again.people_count(), 2)
	assert_eq(again.to_dict(), saved)
	# It is the same after the save file's own encoding.
	var through: Variant = bytes_to_var(var_to_bytes(saved))
	assert_eq(again.from_dict(through), 0)
	assert_eq(again.of(5), book.of(5))
	# Unusable parts are left out, the rest is kept.
	var broken := {"logs": {5: [[100, "eat", "meal", 0], "nonsense", [90, "work", "", 0], [120, "", "", 0], [130, "drink", "", 0, 1],
		[140, "drink", 3, 0], [150, "play", "", 0]], "x": [[1, "eat", "", 0]], -4: [[1, "eat", "", 0]], 6: "no"}}
	assert_eq(again.from_dict(broken), 8)
	assert_eq(again.of(5), [[100, "eat", "meal", 0], [150, "play", "", 0]], "in order, well-formed")
	assert_eq(again.people_count(), 1)
	assert_eq(again.from_dict({}), 0)
	assert_eq(again.people_count(), 0)
	# With the world: what people did is there after a load.
	_run(240.0)
	var data := session.to_dict()
	assert_true(session.day_log.entry_count() > 10)
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(bytes_to_var(var_to_bytes(data))))
	loaded.set_process(false)
	for p in session.people.all_people():
		assert_eq(loaded.day_log.of(p.id), session.day_log.of(p.id), p.given_name)
	assert_eq(loaded.behavior.ctx.day_log, loaded.day_log, "and it goes on being written")
	loaded.queue_free()
	# A new world starts with empty pages.
	var size := var_to_bytes(session.day_log.to_dict()).size()
	print("    a morning of %d people: %d entries, %d bytes" % [session.people.size(), session.day_log.entry_count(), size])
	assert_true(size < 400 * session.people.size(), "small: %d bytes" % size)
	session.create_new(777)
	session.set_process(false)
	assert_eq(session.day_log.entry_count(), 0)


# --- in words -------------------------------------------------------------------------------------

func test_a_day_in_words() -> void:
	var people := session.people
	var one := _adult()
	var other := _adult(&"forager")
	assert_eq(DayLogText.time_of(_tick_at(6.5)), "06:30")
	assert_eq(DayLogText.time_of(_tick_at(0.25, 1)), "00:15")
	assert_eq(DayLogText.time_of(_tick_at(23.98)), "23:59")
	var words := func(kind: String, detail: String = "", with: int = 0, hour: float = 9.0) -> String:
		return DayLogText.text([_tick_at(hour), kind, detail, with], people)
	assert_eq(words.call(DayLog.WAKE), "wakes")
	assert_eq(words.call("eat"), "eats")
	assert_eq(words.call("eat", "meal", 0, 7.2), "has breakfast")
	assert_eq(words.call("eat", "meal", 0, 12.4), "has lunch")
	assert_eq(words.call("eat", "meal", 0, 18.1), "has dinner")
	assert_eq(words.call("drink"), "drinks")
	assert_eq(words.call("sleep"), "goes to bed")
	assert_eq(words.call("sleep", "nap"), "lies down for a nap")
	assert_eq(words.call("work"), "works")
	assert_eq(words.call("work", "tree"), "chops wood")
	assert_eq(words.call("work", "bush"), "gathers berries")
	assert_eq(words.call("work", "fire"), "tends the fire")
	assert_eq(words.call("work", "something_new"), "works")
	assert_eq(words.call("socialize", "", other.id), "talks to %s" % other.given_name)
	assert_eq(words.call("socialize", "", 987654), "talks to someone", "whoever it was is gone")
	assert_eq(words.call("socialize", DayLog.MORE, other.id), "talks to %s and others" % other.given_name)
	assert_eq(words.call("tag_along", "", other.id), "tags along with %s" % other.given_name)
	assert_eq(words.call(DayLog.STIR), "stirs in their sleep")
	assert_eq(words.call(DayLog.REACT, "run:touch"), "feels a touch, runs away")
	assert_eq(words.call(DayLog.REACT, "pray:tree_uprooted"), "sees a tree torn out, prays")
	assert_eq(words.call(DayLog.REACT, "tell:touch", other.id), "feels a touch, goes to tell %s" % other.given_name)
	assert_eq(words.call(DayLog.REACT, "listen:", other.id), "listens to %s" % other.given_name)
	assert_eq(words.call(DayLog.REACT, "look:something_unheard_of"), "looks about")
	assert_eq(words.call(DayLog.REACT, "somersault:touch"), "feels a touch, is startled")
	assert_eq(words.call("a_new_thing"), "a new thing", "no words yet: at least not a key")
	# There are words for everything people can do, notice and do about it.
	for id in session.activities.ids():
		assert_true(DayLogText.has("DAY_" + String(id).to_upper()), "words for %s" % id)
	for reaction in ReactionTable.REACTIONS + [ReactionTable.LISTEN]:
		assert_true(DayLogText.has("DAY_REACT_" + String(reaction).to_upper()), "words for %s" % reaction)
	for stimulus: StringName in Config.reactions.stimuli:
		assert_true(DayLogText.has("DAY_AT_" + String(stimulus).to_upper()), "words for %s" % stimulus)
	for id in session.occupations.ids():
		var target := session.occupations.get_def(id).work_target
		if target != &"":
			assert_true(DayLogText.has("DAY_WORK_" + String(target).to_upper()), "words for the %s's work" % id)
	# A line, and a day.
	var entries: Array = [[_tick_at(6.5), DayLog.WAKE, "", 0], [_tick_at(7.0), "eat", "meal", 0], [_tick_at(8.0), "work", "tree", 0],
		[_tick_at(12.0), "socialize", "", other.id]]
	assert_eq(DayLogText.line(entries[1], people), "07:00 has breakfast")
	assert_eq(DayLogText.timeline(entries, people),
		"06:30 wakes · 07:00 has breakfast · 08:00 chops wood · 12:00 talks to %s" % other.given_name)
	assert_eq(DayLogText.timeline([], people), "")
	# What the card shows.
	var book := DayLog.new()
	assert_eq(DayLogText.shown(book, one.id, _tick_at(9.0), people), ["Today", "Nothing yet"])
	assert_eq(DayLogText.shown(null, one.id, _tick_at(9.0), people), ["Today", "Nothing yet"])
	for entry: Array in entries:
		book.note(one.id, entry[0], entry[1], entry[2], entry[3])
	assert_eq(DayLogText.shown(book, one.id, _tick_at(13.0), people), ["Today", DayLogText.timeline(entries, people)])
	assert_eq(DayLogText.shown(book, one.id, _tick_at(2.0, 1), people), ["Yesterday", DayLogText.timeline(entries, people)])
	assert_eq(PersonCard.facts(session, one)["today_title"], "Today")
	assert_eq(PersonCard.facts(session, one)["today"], "Nothing yet")


# --- written as people live -----------------------------------------------------------------------

func test_what_people_turn_to_is_written_down() -> void:
	var person := _adult()
	var friend := _adult(&"forager")
	person.needs = PackedFloat32Array([0.8, 0.85, 0.8, 0.8, 0.75, 1.0])
	_set_hour(9.0)
	var now := session.clock.tick
	var tree := ctx.places.work_place(person, &"tree", ctx.rng)
	behavior.set_plan(person, &"work", &"purpose", [WalkToStep.make(tree["tile"], Vector2(0.5, 0.5)), WorkStep.make(&"tree", tree["id"], tree["tile"], 60.0)], 0.9)
	assert_eq(log.of(person.id), [[now, "work", "tree", 0]])
	session.clock.tick += 30
	behavior.set_plan(person, &"socialize", &"social", [WalkToStep.make(friend.position, Vector2(0.5, 0.5)), SocializeStep.make(friend.id, 20.0)], 0.9)
	assert_eq(log.of(person.id)[-1], [now + 30, "socialize", "", friend.id])
	session.clock.tick += 30
	behavior.set_plan(person, &"play", &"nature", [WorkStep.make(&"play", 0, person.position, 20.0)], 0.9)
	assert_eq(log.of(person.id)[-1], [now + 60, "play", "", 0], "the kind of work is for work")
	# A meal, and a bite.
	_set_hour(12.2)
	behavior.set_plan(person, &"eat", &"hunger", Planner.plan(&"eat", person, ctx), 0.9)
	assert_eq(log.of(person.id)[-1], [session.clock.tick, "eat", "meal", 0])
	_set_hour(15.0)
	behavior.set_plan(person, &"eat", &"hunger", Planner.plan(&"eat", person, ctx), 0.9)
	assert_eq(log.of(person.id)[-1], [session.clock.tick, "eat", "", 0])
	# A nap, bed, and going home at night (which is going to bed).
	behavior.set_plan(person, &"explore", &"nature", [RestStep.make(30.0)], 0.9)
	session.clock.tick += 20
	behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 0.9)
	assert_eq(log.of(person.id)[-1], [session.clock.tick, "sleep", "nap", 0])
	assert_eq(person.pose, PersonData.Pose.SLEEP)
	session.clock.tick += 40
	behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 0.9)
	assert_eq(log.of(person.id)[-1][DayLog.DETAIL], "nap", "sleeping on is not written again")
	assert_eq(_kinds(person.id).count(DayLog.WAKE), 0)
	behavior.set_plan(person, &"drink", &"thirst", Planner.plan(&"drink", person, ctx), 0.9)
	assert_eq(log.of(person.id).slice(-2), [[session.clock.tick, DayLog.WAKE, "", 0], [session.clock.tick, "drink", "", 0]], "up again")
	_set_hour(21.5)
	behavior.set_plan(person, &"go_home", &"safety", Planner.plan(&"go_home", person, ctx), 0.9)
	assert_eq(log.of(person.id)[-1], [session.clock.tick, "sleep", "", 0], "home at night: to bed")
	# The debug call is nobody's day.
	var before := log.of(friend.id).size()
	behavior.call_to([friend.id], friend.position)
	assert_eq(log.of(friend.id).size(), before)
	# Someone who leaves the world takes their pages with them.
	assert_true(log.of(person.id).size() > 5)
	session.people.remove(person.id)
	assert_eq(log.of(person.id), [])


func test_what_people_notice_is_part_of_their_day() -> void:
	var person := _adult()
	person.traits = Traits.neutral()
	person.needs = PackedFloat32Array([0.8, 0.85, 0.8, 0.8, 0.75, 1.0])
	_set_hour(10.0)
	behavior.set_plan(person, &"work", &"purpose", [RestStep.make(600.0)], 0.9)
	session.clock.tick += 30
	_touch(person)
	var outcome := behavior.last_outcome(person.id)
	assert_eq(log.of(person.id)[-1], [session.clock.tick, DayLog.REACT, "%s:touch" % outcome.reaction,
		log.of(person.id)[-1][DayLog.OTHER]])
	assert_true(DayLogText.text(log.of(person.id)[-1], session.people).begins_with("feels a touch, "),
		DayLogText.text(log.of(person.id)[-1], session.people))
	if outcome.reaction == ReactionTable.TELL:
		assert_ne(log.of(person.id)[-1][DayLog.OTHER], 0, "whom they go to tell")
	# A sleeper: either a dream (they stir), or awake with a start.
	var stirred := 0
	var startled := 0
	for i in 30:
		behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)]) # (up)
		log.forget(person.id)
		person.beliefs = PackedFloat32Array()
		person.knowledge = {}
		_set_hour(23.0)
		session.movement.stop(person.id)
		session.people.move(person.id, session.props.get_prop(person.home_building_id).tile, Vector2(0.5, 0.5), 0.0)
		behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 1.0)
		session.clock.tick += 60
		_touch(person)
		if behavior.last_outcome(person.id).interpretation == ReactionTable.DREAM:
			stirred += 1
			assert_eq(_kinds(person.id), ["sleep", DayLog.STIR])
			assert_eq(DayLogText.text(log.of(person.id)[-1]), "stirs in their sleep")
		else:
			startled += 1
			assert_eq(_kinds(person.id), ["sleep", DayLog.WAKE, DayLog.REACT], "woken, and what they did")
	assert_true(stirred > 0 and startled > 0, "%d stirred, %d woke" % [stirred, startled])
	# Told about it: who told them is in the listener's day, and whom they told in the teller's.
	var teller := _adult()
	var listener := _adult(&"forager")
	for p: PersonData in [teller, listener]:
		log.forget(p.id)
		session.movement.stop(p.id)
		p.set_flag(PersonData.FLAG_INDOORS, false)
	_set_hour(11.0)
	var fire := session.props.get_prop(session.start.campfire_id).tile
	session.people.move(teller.id, fire + Vector2i(1, 1), Vector2(0.5, 0.5), 0.0)
	session.people.move(listener.id, fire + Vector2i(2, 1), Vector2(0.5, 0.5), 0.0)
	behavior.set_plan(listener, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	behavior.set_plan(teller, BehaviorSystem.ACTIVITY_REACT, ReactionTable.DEITY,
		[TellStep.make(listener.id, 6.0, Stimulus.TOUCH, ReactionTable.DEITY, 0.8)])
	var waited := 0.0
	while log.of(listener.id).is_empty() and waited < 30.0:
		_run(0.5)
		waited += 0.5
	assert_eq(log.of(listener.id).size(), 1, "the listener's day has it")
	var heard: Array = log.of(listener.id)[0]
	assert_eq(heard[DayLog.KIND], DayLog.REACT)
	assert_eq(heard[DayLog.OTHER], teller.id)
	assert_false(str(heard[DayLog.DETAIL]).contains("touch"), "it is not what they saw themselves")
	var text := DayLogText.text(heard, session.people)
	if str(heard[DayLog.DETAIL]).begins_with("listen:"):
		assert_eq(text, "listens to %s" % teller.given_name)
	assert_false(text.contains("{"), text)


func test_a_day_reads_like_a_life() -> void:
	# Two days from the first morning; the second is read.
	session.clock.tick = 0
	_run(2880.0)
	var config := Config.time
	var second := 1
	assert_eq(config.day_index(session.clock.tick), 2, "the third morning")
	var people := session.people.all_people()
	var meals := 0
	var worked := 0
	for p in people:
		var day := log.of_day(p.id, second, config)
		var kinds: Array = []
		for entry: Array in day:
			kinds.append(entry[DayLog.KIND])
		var text := DayLogText.timeline(day, session.people)
		assert_true(day.size() >= 6, "%s did things (%d)" % [p.given_name, day.size()])
		assert_true(day.size() <= DayLog.MAX_ENTRIES - 4, "and the day fits the ring (%d)" % day.size())
		assert_true(kinds.has(DayLog.WAKE), "%s woke: %s" % [p.given_name, text])
		assert_true(kinds.has("eat"), "%s ate: %s" % [p.given_name, text])
		assert_true(kinds.has("sleep"), "%s went to bed: %s" % [p.given_name, text])
		assert_false(text.contains("{") or text.contains("DAY_") or text.contains("_"), text)
		meals += text.count("has ")
		worked += 1 if kinds.has("work") else 0
		# In order, and nothing twice in a row.
		for i in range(1, day.size()):
			assert_true(int(day[i][DayLog.TICK]) >= int(day[i - 1][DayLog.TICK]))
			if not DayLog.MOMENTS.has(str(day[i][DayLog.KIND])):
				assert_ne(day[i].slice(1), day[i - 1].slice(1), "%s: the same twice (%s)" % [p.given_name, text])
		# The first thing of the day is waking up.
		assert_eq(day[0][DayLog.KIND], DayLog.WAKE, "%s begins with %s" % [p.given_name, day[0]])
		assert_eq(kinds.count(DayLog.WAKE) <= 3, true, "once, and after a nap (%s)" % text)
		assert_false(text.contains("wakes · ") and text.contains("wakes · %s wakes" % DayLogText.time_of(int(day[1][DayLog.TICK]))), text)
		assert_eq(log.of(p.id).size() <= DayLog.MAX_ENTRIES, true)
	# (Most meals are at mealtimes; some people eat early or late.)
	assert_true(meals >= people.size() * 3 / 2, "meals all round (%d)" % meals)
	assert_true(worked >= 3, "and work (%d)" % worked)
	var one := _adult()
	print("    %s, %s: %s" % [one.given_name, one.occupation_id, DayLogText.timeline(log.of_day(one.id, second, config), session.people)])
	var child := _child()
	print("    %s, child: %s" % [child.given_name, DayLogText.timeline(log.of_day(child.id, second, config), session.people)])
	# Just after midnight the card still has yesterday to show.
	var shown := DayLogText.shown(log, one.id, session.clock.tick, session.people)
	assert_true(shown[0] == "Today" or shown[0] == "Yesterday")
	assert_ne(shown[1], "Nothing yet")


# --- staying with someone (OBSERVER) --------------------------------------------------------------

func test_a_day_with_one_person_is_counted() -> void:
	var watch := ObserverWatch.new()
	assert_eq(ObserverWatch.WINDOW, 1440, "a game day")
	assert_eq(ObserverWatch.allowed_away(), 144, "a tenth of it")
	assert_false(watch.update(100, 0), "nobody followed: nothing to count")
	assert_eq(watch.progress(100), 0.0)
	# A whole day without looking away.
	assert_false(watch.update(100, 7))
	assert_eq(watch.person_id, 7)
	assert_false(watch.update(800, 7))
	assert_near(watch.progress(820), 0.5, 0.001)
	assert_false(watch.update(1539, 7), "a minute short")
	assert_true(watch.update(1540, 7), "twenty-four hours")
	assert_true(watch.update(1600, 7), "and it stays so")
	# Looking away for a tenth of the day is allowed...
	watch.reset()
	watch.update(0, 7)
	watch.update(300, 0) # away from 300
	watch.update(400, 7) # back: 100 away
	watch.update(900, 0)
	assert_eq(watch.away(940), 140)
	watch.update(944, 7) # 144 away in all
	assert_eq(watch.away(1000), 144)
	assert_false(watch.update(1439, 7))
	assert_true(watch.update(1440, 7), "nine tenths of the day with them")
	# ...a little more is not — until the time away has passed out of the day.
	watch.reset()
	watch.update(0, 7)
	watch.update(300, 0)
	watch.update(445, 7) # 145 away
	assert_false(watch.update(1440, 7), "too long elsewhere")
	assert_true(watch.progress(1440) < 1.0)
	assert_false(watch.update(1740, 7), "still in the last day")
	assert_true(watch.update(1741, 7), "a minute of it has passed out of the day")
	# Away right now counts as it goes.
	watch.reset()
	watch.update(0, 7)
	watch.update(1400, 0)
	assert_false(watch.update(1440, 0) and false)
	assert_eq(watch.away(1440), 40)
	assert_true(watch.update(1440, 0), "forty minutes away at the end is within the tenth")
	watch.reset()
	watch.update(0, 7)
	watch.update(1200, 0)
	assert_false(watch.update(1440, 0), "the last four hours elsewhere")
	# Following someone else starts over.
	watch.reset()
	watch.update(0, 7)
	watch.update(1000, 8)
	assert_eq(watch.person_id, 8)
	assert_eq(watch.since_tick, 1000)
	assert_false(watch.update(1440, 8))
	assert_false(watch.update(2439, 8))
	assert_true(watch.update(2440, 8))
	# Stopping and taking up the same person again is only time away.
	watch.reset()
	watch.update(0, 7)
	watch.update(500, 0)
	watch.update(560, 7)
	assert_eq(watch.person_id, 7)
	assert_eq(watch.since_tick, 0)
	assert_true(watch.update(1440, 7))
	# A whole day elsewhere: they are not being watched any more.
	watch.reset()
	watch.update(0, 7)
	watch.update(100, 0)
	assert_false(watch.update(1539, 0))
	assert_eq(watch.person_id, 7)
	assert_false(watch.update(1540, 0))
	assert_eq(watch.person_id, 0, "forgotten")
	assert_false(watch.update(1600, 7))
	assert_eq(watch.since_tick, 1600, "from the beginning")
	# The clock set back (a test, an older save): from the beginning.
	watch.update(1000, 7)
	assert_eq(watch.since_tick, 1000)
	# Saved and taken up again.
	watch.reset()
	assert_eq(watch.to_dict(), {})
	watch.update(0, 7)
	watch.update(300, 0)
	watch.update(400, 7)
	watch.update(700, 0)
	var again := ObserverWatch.new()
	again.from_dict(bytes_to_var(var_to_bytes(watch.to_dict())))
	assert_eq(again.person_id, 7)
	assert_eq(again.away(760), 160)
	assert_eq(again.to_dict(), watch.to_dict())
	again.from_dict({"person": "x"})
	assert_eq(again.person_id, 0)
	again.from_dict({"person": 7, "since": 5, "gaps": [[9, 3], "x", [10, 20]], "gap_from": "no"})
	assert_eq(again.away(100), 10, "unusable gaps are left out")


func test_staying_with_someone_for_a_day_unlocks_observer() -> void:
	var person := _adult()
	var other := _adult(&"forager")
	var history := session.history
	assert_false(history.has_achievement(PlayerHistory.OBSERVER))
	assert_eq(String(TranslationServer.translate("ACHIEVEMENT_OBSERVER")), "Observer")
	session.clock.tick = 500
	assert_false(session.watch_followed(person.id))
	session.clock.tick += 700
	assert_false(session.watch_followed(person.id))
	# Half a day in, the world is saved and opened again: the count goes on.
	var data: Dictionary = bytes_to_var(var_to_bytes(session.to_dict()))
	assert_eq(data["world_state"]["observer"]["person"], person.id)
	var loaded: WorldSession = SessionScript.new()
	add_child(loaded)
	assert_true(loaded.load_from(data))
	loaded.set_process(false)
	assert_eq(loaded.observer.person_id, person.id)
	assert_eq(loaded.observer.since_tick, 500)
	loaded.clock.tick += 100
	assert_false(loaded.watch_followed(0), "opened with the view on the settlement: time away")
	loaded.clock.tick += 30
	assert_false(loaded.watch_followed(person.id))
	loaded.clock.tick = 500 + 1440
	assert_true(loaded.watch_followed(person.id), "a day with them, the reload included")
	assert_true(loaded.history.has_achievement(PlayerHistory.OBSERVER))
	loaded.queue_free()
	# In this world: someone else for a while, then a full day.
	assert_false(session.watch_followed(other.id), "someone else: from the beginning")
	session.clock.tick += 1439
	assert_false(session.watch_followed(other.id))
	assert_eq(unlocked, [PlayerHistory.OBSERVER], "(the other world's)")
	unlocked.clear()
	session.clock.tick += 1
	assert_true(session.watch_followed(other.id))
	assert_eq(unlocked, [PlayerHistory.OBSERVER], "announced")
	assert_eq(history.achievements()["observer"]["tick"], session.clock.tick)
	# Once.
	session.clock.tick += 2000
	assert_false(session.watch_followed(other.id))
	assert_eq(unlocked.size(), 1)
	# It is in the save, and it is not first contact.
	assert_false(history.has_achievement(PlayerHistory.FIRST_CONTACT))
	var kept := PlayerHistory.new()
	kept.from_dict(bytes_to_var(var_to_bytes(history.to_dict())))
	assert_true(kept.has_achievement(PlayerHistory.OBSERVER))
	assert_eq(kept.take_unlocked().size(), 0)
	# Someone who is not there (any more) is nobody.
	var fresh: WorldSession = SessionScript.new()
	add_child(fresh)
	fresh.create_new(4321)
	fresh.set_process(false)
	assert_false(fresh.watch_followed(987654))
	assert_eq(fresh.observer.person_id, 0)
	fresh.queue_free()
