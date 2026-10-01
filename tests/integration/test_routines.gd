extends TestCase
## Routines and sleep (M6.3): the shape of a day per occupation, meals at
## the fire, children tagging along and going to bed, dreams of a touch, and
## the lights of a house going out when everyone in it sleeps.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const ViewScript := preload("res://scripts/rendering/world_view.gd")

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var table: ReactionTable
var _routines: Dictionary = {}


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	table = Config.reactions
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	behavior = session.behavior
	ctx = behavior.ctx


func after_each() -> void:
	for def: OccupationDef in _routines:
		def.set_routine(_routines[def])
	_routines.clear()
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


func _set_hour(hour: float) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440) + 1440


func _of(stage: PersonData.LifeStage) -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == stage:
			return p
	return null


func _adult(occupation: StringName = &"woodcutter") -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


## Someone with a plain nature whose needs are quiet.
func _calm(person: PersonData) -> PersonData:
	person.traits = Traits.neutral()
	person.needs = PackedFloat32Array([0.8, 0.85, 0.8, 0.8, 0.75, 1.0])
	person.activity_log = {}
	person.beliefs = PackedFloat32Array()
	person.knowledge = {}
	return person


func _tally(person: PersonData, times: int = 300) -> Dictionary:
	var out := {}
	for i in times:
		var chosen := Brain.decide(person, ctx).activity
		out[chosen] = int(out.get(chosen, 0)) + 1
	return out


func _put_to_bed(person: PersonData) -> void:
	var home := session.props.get_prop(person.home_building_id)
	session.movement.stop(person.id)
	session.people.move(person.id, home.tile, Vector2(0.5, 0.5), 0.0)
	behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 1.0)


func _touch(person: PersonData) -> void:
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = person.id
	target.entity_kind = SpatialIndex.KIND_PERSON
	target.tile = person.position
	target.direct = true
	session.interactions.tap(target)


# --- the shape of a day ---------------------------------------------------------------------------

func test_a_routine_is_read_from_the_occupation() -> void:
	assert_eq(OccupationDef.parse_entry("07:00 eat"), [7.0, &"eat"])
	assert_eq(OccupationDef.parse_entry(" 19:45 sleep "), [19.75, &"sleep"])
	assert_eq(OccupationDef.parse_entry("06:00 wake"), [6.0, &""], "awake: nothing in particular")
	for bad: String in ["", "eat", "7 eat", "25:00 eat", "07:75 eat", "07:00", "07:00 eat now", "ab:cd eat"]:
		assert_eq(float(OccupationDef.parse_entry(bad)[0]), -1.0, "'%s' is not an entry" % bad)
	var def := OccupationDef.new()
	def.id = &"tester"
	assert_eq(def.scheduled(9.0), &"", "no routine: nothing is due")
	def.set_routine(PackedStringArray(["06:00 wake", "07:00 eat", "08:00 work", "12:00 eat", "13:00 work", "21:00 sleep"]))
	assert_eq(def.validate().size(), 0)
	assert_eq(def.scheduled(6.5), &"")
	assert_eq(def.scheduled(7.0), &"eat")
	assert_eq(def.scheduled(7.99), &"eat")
	assert_eq(def.scheduled(8.0), &"work")
	assert_eq(def.scheduled(12.5), &"eat")
	assert_eq(def.scheduled(20.0), &"work", "each entry holds until the next")
	assert_eq(def.scheduled(23.0), &"sleep")
	assert_eq(def.scheduled(3.0), &"sleep", "the last one holds over midnight")
	assert_eq(def.scheduled(27.0), &"sleep", "hours wrap")
	assert_near(def.hours_into_slot(9.5), 1.5, 0.001)
	assert_near(def.hours_into_slot(2.0), 5.0, 0.001, "since nine the evening before")
	assert_eq(def.slots().size(), 6)
	def.set_routine(PackedStringArray(["08:00 work", "07:00 eat"]))
	assert_eq(def.validate().size(), 1, "out of order")
	def.set_routine(PackedStringArray(["breakfast at seven"]))
	assert_eq(def.validate().size(), 1, "unreadable")
	assert_eq(def.scheduled(9.0), &"", "and ignored")
	# Every occupation in the data has a routine made of things its people can do.
	for id in session.occupations.ids():
		var occupation := session.occupations.get_def(id)
		assert_true(occupation.routine.size() >= 6, "%s has a day" % id)
		assert_eq(occupation.validate().size(), 0, str(occupation.validate()))
		var meals := 0
		var sleeps := false
		for slot: Array in occupation.slots():
			if slot[1] == &"":
				continue
			var activity := session.activities.get_def(slot[1])
			assert_not_null(activity, "%s: '%s' is an activity" % [id, slot[1]])
			for stage in occupation.life_stages:
				assert_true(activity.allows(stage), "%s (%s) can %s" % [id, stage, slot[1]])
			meals += 1 if slot[1] == &"eat" else 0
			sleeps = sleeps or slot[1] == &"sleep"
		assert_eq(meals, 3, "%s: breakfast, lunch and dinner" % id)
		assert_true(sleeps, "%s: and to bed" % id)
	assert_true(UIText.ACTIVITY_NAMES.has(&"tag_along"))


func test_routine_bias() -> void:
	var person := _calm(_adult())
	var def := session.occupations.get_def(person.occupation_id)
	# Eight in the morning: work dominates.
	_set_hour(8.25)
	assert_eq(def.scheduled(session.clock.hour()), &"work")
	var morning := _tally(person)
	assert_true(int(morning.get(&"work", 0)) > 270, "at 08:00 work dominates (%s)" % [morning])
	# Nine in the evening: sleep dominates — tired as people are by then.
	_set_hour(21.0)
	person.needs[Needs.Need.SLEEP] = 0.4
	assert_eq(def.scheduled(21.0), &"sleep")
	var evening := _tally(person)
	assert_true(int(evening.get(&"sleep", 0)) > 285, "at 21:00 sleep dominates (%s)" % [evening])
	assert_eq(int(evening.get(&"work", 0)), 0)
	# Mealtimes bring people to the fire though they are not hungry yet.
	person.needs[Needs.Need.SLEEP] = 0.8
	for hour: float in [7.2, 12.2, 18.7]:
		_set_hour(hour)
		assert_eq(def.scheduled(hour), &"eat")
		var meal := _tally(person)
		assert_true(int(meal.get(&"eat", 0)) > 180, "at %.1f it is time to eat (%s)" % [hour, meal])
		assert_true(int(meal.get(&"eat", 0)) < 290, "soft: not everyone, not every time")
	# ...but not twice: who has eaten since it came due gets on with the day.
	person.activity_log["eat"] = session.clock.tick - 5
	assert_true(int(_tally(person).get(&"eat", 0)) < 10, "eaten already")
	person.activity_log = {}
	# Work, though, is for the whole of its hours: having been at it is no reason to stop.
	_set_hour(10.0)
	var fresh := Brain.score(session.activities.get_def(&"work"), person, ctx)
	person.activity_log["work"] = session.clock.tick - 5
	assert_near(Brain.score(session.activities.get_def(&"work"), person, ctx), fresh, 0.0001)
	person.activity_log = {}
	# The routine's hour is the hour for it, whatever the hour is for people in
	# general: a child's bedtime is early, and it is bedtime all the same.
	var child := _calm(_of(PersonData.LifeStage.CHILD))
	var sleep := session.activities.get_def(&"sleep")
	child.needs[Needs.Need.SLEEP] = 0.4
	person.needs[Needs.Need.SLEEP] = 0.4
	_set_hour(19.75)
	assert_true(sleep.hour_factor(19.75) < 0.35, "early for most")
	assert_eq(session.occupations.get_def(child.occupation_id).scheduled(19.75), &"sleep")
	assert_ne(def.scheduled(19.75), &"sleep")
	assert_true(Brain.score(sleep, child, ctx) > Brain.score(sleep, person, ctx) * 2.5, "the child's bedtime, not yet the woodcutter's")
	assert_true(int(_tally(child).get(&"sleep", 0)) > 285, "the child goes to bed")
	assert_true(int(_tally(person).get(&"sleep", 0)) < 60, "the grown-ups stay up a while")
	person.needs[Needs.Need.SLEEP] = 0.8
	# The push in numbers: what is due counts more, by how calm they are.
	_set_hour(8.25)
	var work := session.activities.get_def(&"work")
	var pushed := Brain.score(work, person, ctx)
	var routine := def.routine
	_routines[def] = routine
	def.set_routine(PackedStringArray())
	var plain := Brain.score(work, person, ctx)
	def.set_routine(routine)
	var loudest := 0.0
	for voice in ActivityDef.voices(person.needs):
		loudest = maxf(loudest, voice)
	var calm := 1.0 - loudest
	assert_near(pushed, plain * (1.0 + (Brain.ROUTINE_FACTOR - 1.0) * calm) + Brain.ROUTINE_PULL * calm, 0.0001)
	assert_true(pushed > plain + 0.2)
	# What is not due gets none.
	assert_near(Brain.score(session.activities.get_def(&"socialize"), person, ctx), _plain_score(&"socialize", person, def), 0.0001)
	# What holds someone at a task is what spoke for it without the push.
	var decision := Brain.decide(person, ctx)
	assert_near(decision.commitment_of(&"work"), plain, 0.0001)
	assert_near(decision.score_of(&"work"), pushed, 0.0001)
	# Soft: a pressing need drowns the routine out.
	person.needs[Needs.Need.THIRST] = 0.02
	assert_eq(Brain.decide(person, ctx).activity, &"drink", "parched at work time: to the water")
	assert_near(Brain.score(work, person, ctx), plain, 0.02, "and the push is all but gone")
	person.needs[Needs.Need.THIRST] = 0.85
	person.needs[Needs.Need.SLEEP] = 0.03
	assert_eq(Brain.decide(person, ctx).activity, &"sleep", "dead tired: bed, whatever the hour says")
	# The ceiling (what could speak for anything at all) covers the push.
	_calm(person)
	for hour: float in [7.2, 8.25, 12.2, 17.5, 21.0, 3.0]:
		_set_hour(hour)
		var scores := Brain.decide(person, ctx).scores
		var loud := 0.0
		for voice in ActivityDef.voices(person.needs):
			loud = maxf(loud, voice)
		for id: StringName in scores:
			assert_true(float(scores[id]) <= session.activities.ceiling(loud) + 0.0001, "%s at %.1f" % [id, hour])


func _plain_score(id: StringName, person: PersonData, def: OccupationDef) -> float:
	var routine := def.routine
	def.set_routine(PackedStringArray())
	var value := Brain.score(session.activities.get_def(id), person, ctx)
	def.set_routine(routine)
	return value


func test_what_is_due_loosens_what_was_begun_idly() -> void:
	var person := _calm(_adult())
	# At work since the morning, begun for no pressing reason; noon comes.
	_set_hour(12.2)
	var tree := ctx.places.work_place(person, &"tree", ctx.rng)
	behavior.set_plan(person, &"work", &"routine", [WorkStep.make(&"tree", tree["id"], tree["tile"], 200.0)], 0.3)
	behavior.think(person)
	assert_eq(BehaviorSystem.activity_of(person), &"eat", "lunch: they put the work down")
	# Someone who went to work because idleness was eating at them works on.
	_calm(person)
	behavior.set_plan(person, &"work", &"purpose", [WorkStep.make(&"tree", tree["id"], tree["tile"], 200.0)], 0.9)
	behavior.think(person)
	assert_eq(BehaviorSystem.activity_of(person), &"work", "driven: lunch can wait")
	# A sleeper is not got up for breakfast.
	_set_hour(7.2)
	_calm(person)
	person.needs[Needs.Need.SLEEP] = 0.5
	_put_to_bed(person)
	person.current_action["score"] = 0.3
	behavior.think(person)
	assert_eq(BehaviorSystem.activity_of(person), &"sleep")


# --- meals ----------------------------------------------------------------------------------------

func test_meals_are_taken_together_at_the_fire() -> void:
	_set_hour(12.2)
	var fire := session.props.get_prop(session.start.campfire_id)
	var spots := {}
	var adults: Array[PersonData] = []
	for p in session.people.all_people():
		_calm(p)
		p.set_flag(PersonData.FLAG_INDOORS, false)
		var spot := ctx.places.meal_spot(p)
		assert_true(Vector2(spot - fire.tile).length() < 1.6, "%s sits by the fire" % p.given_name)
		assert_true(session.pathfinder.can_stand(spot))
		assert_ne(spot, fire.tile, "not in it")
		assert_eq(ctx.places.meal_spot(p), spot, "always their own place")
		spots[spot] = int(spots.get(spot, 0)) + 1
		if ctx.stage_of(p) == PersonData.LifeStage.ADULT:
			adults.append(p)
	assert_true(spots.size() >= mini(session.people.size(), 5), "around it, not all on one spot (%d places for %d)" % [spots.size(), session.people.size()])
	# A meal at mealtime lasts its time, hungry or not.
	var one := adults[0]
	var plan := Planner.plan(&"eat", one, ctx)
	assert_eq(plan[0]["target"], ctx.places.meal_spot(one))
	assert_true(bool(plan[1].get("meal", false)), "the hour for it: a meal")
	_set_hour(15.0)
	assert_false(bool(Planner.plan(&"eat", one, ctx)[1].get("meal", false)), "a bite between meals is not")
	_set_hour(12.2)
	# Everyone comes to lunch.
	for p in session.people.all_people():
		behavior.think(p)
	var at_table := 0
	var most_together := 0
	var company_before := Needs.value(one.needs, Needs.Need.SOCIAL)
	var minutes := 0.0
	while minutes < 60.0:
		_run(1.0)
		minutes += 1.0
		var eating := 0
		for p in session.people.all_people():
			if p.pose == PersonData.Pose.EAT:
				eating += 1
		most_together = maxi(most_together, eating)
	for p in session.people.all_people():
		if p.activity_log.has("eat"):
			at_table += 1
	assert_true(at_table >= session.people.size() - 2, "the band had lunch (%d of %d)" % [at_table, session.people.size()])
	assert_true(most_together >= session.people.size() / 2, "together (%d at once)" % most_together)
	assert_true(Needs.value(one.needs, Needs.Need.SOCIAL) > company_before, "and a meal together is company")
	# Alone it feeds, but it is no company.
	var loner := _calm(adults[1])
	for p in session.people.all_people():
		if p.id != loner.id:
			p.pose = PersonData.Pose.IDLE
			p.set_flag(PersonData.FLAG_INDOORS, true)
	session.movement.stop(loner.id)
	session.people.move(loner.id, ctx.places.meal_spot(loner), Vector2(0.5, 0.5), 0.0)
	loner.needs[Needs.Need.SOCIAL] = 0.5
	loner.needs[Needs.Need.HUNGER] = 0.95
	var step := EatStep.make(fire.tile, true)
	var handler := EatStep.new()
	handler.begin(ctx, loner, step)
	assert_eq(EatStep.company(ctx, loner), 0)
	for i in 10:
		assert_eq(handler.update(ctx, loner, step, 1.0), ActionStep.Status.RUNNING, "a meal is sat through, full or not")
	assert_near(loner.needs[Needs.Need.SOCIAL], 0.5, 0.0001)
	assert_eq(handler.update(ctx, loner, EatStep.make(fire.tile), 1.5), ActionStep.Status.DONE, "a bite ends when one is full")


# --- children -------------------------------------------------------------------------------------

func test_children_tag_along_with_a_parent() -> void:
	_set_hour(10.6)
	var child := _calm(_of(PersonData.LifeStage.CHILD))
	var parents: Array[PersonData] = []
	for id in child.parents:
		var parent := session.people.get_person(id)
		if parent != null:
			parents.append(parent)
			parent.set_flag(PersonData.FLAG_INDOORS, false)
			parent.pose = PersonData.Pose.WORK
	assert_true(parents.size() >= 1, "the child has a parent in the band")
	assert_eq(session.occupations.get_def(child.occupation_id).scheduled(10.6), &"tag_along")
	assert_true(Planner.can(&"parent", child, ctx))
	var near := ctx.places.parent_about(child)
	assert_true(parents.has(near))
	for parent in parents:
		assert_true(near.world2d().distance_to(child.world2d()) <= parent.world2d().distance_to(child.world2d()) + 0.001, "the nearer one")
	# The plan: over to them, and keep them company.
	var plan := Planner.plan(&"tag_along", child, ctx)
	assert_eq(plan.size(), 2)
	assert_eq(plan[0]["type"], "walk_to")
	assert_eq(plan[0]["toward"], near.id, "wherever they go meanwhile")
	assert_eq(plan[1]["type"], "socialize")
	assert_eq(plan[1]["partner"], near.id)
	child.needs[Needs.Need.SOCIAL] = 0.45
	var tally := _tally(child)
	assert_true(int(tally.get(&"tag_along", 0)) > 150, "a child who wants company goes to a parent (%s)" % [tally])
	# They get there.
	session.movement.stop(near.id)
	behavior.set_plan(near, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	session.people.move(child.id, session.pathfinder.standable_near(near.position + Vector2i(5, 0), 1)[0], Vector2(0.5, 0.5), 0.0)
	behavior.set_plan(child, &"tag_along", &"social", Planner.plan(&"tag_along", child, ctx), 1.0)
	var waited := 0.0
	while BehaviorSystem.current_step(child).get("type") == "walk_to" and waited < 60.0:
		_run(0.5)
		waited += 0.5
	assert_true(child.world2d().distance_to(near.world2d()) <= SocializeStep.EARSHOT, "beside them (%.1f)" % child.world2d().distance_to(near.world2d()))
	assert_eq(BehaviorSystem.current_step(child).get("type"), "socialize")
	# No parent up and about: nobody to tag along with. Grown people do not.
	for parent in parents:
		parent.set_flag(PersonData.FLAG_INDOORS, true)
	assert_null(ctx.places.parent_about(child))
	assert_false(Planner.can(&"parent", child, ctx))
	assert_eq(Planner.plan(&"tag_along", child, ctx), [])
	assert_eq(Brain.score(session.activities.get_def(&"tag_along"), child, ctx), -1.0)
	assert_eq(Brain.score(session.activities.get_def(&"tag_along"), _adult(), ctx), -1.0)


func test_bedtime_is_announced_for_children() -> void:
	var abed: Array[int] = []
	behavior.bedtime.connect(func(id: int) -> void: abed.append(id))
	var child := _calm(_of(PersonData.LifeStage.CHILD))
	var adult := _calm(_adult())
	# A nap by day is not bedtime.
	_set_hour(14.0)
	_put_to_bed(child)
	_run(1.0)
	assert_eq(abed.size(), 0)
	# The evening: to bed (early as it is: it is not yet night for the village).
	_set_hour(19.6)
	assert_false(SleepStep.is_night_for(child, 19.6))
	assert_true(SleepStep.is_bedtime_for(child, 19.6))
	child.current_action = {}
	child.set_flag(PersonData.FLAG_INDOORS, false)
	_put_to_bed(child)
	_put_to_bed(adult)
	behavior.announce()
	assert_eq(abed, [child.id], "the child's bedtime, not the grown-up's")
	_run(5.0)
	assert_eq(abed.size(), 1, "once")
	# Taken up again after a load, it is not bedtime again.
	var saved := session.to_dict()
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(saved.duplicate(true)))
	again.set_process(false)
	var later: Array[int] = []
	again.behavior.bedtime.connect(func(id: int) -> void: later.append(id))
	for i in 6:
		again.clock.advance(0.25)
		again.behavior.step(0.5)
	assert_eq(later.size(), 0)
	assert_eq(again.people.get_person(child.id).pose, PersonData.Pose.SLEEP)
	again.queue_free()
	# Children go to bed before their parents.
	var child_def := session.occupations.get_def(child.occupation_id)
	var adult_def := session.occupations.get_def(adult.occupation_id)
	var child_bed := 0.0
	var adult_bed := 0.0
	for slot: Array in child_def.slots():
		if slot[1] == &"sleep":
			child_bed = slot[0]
	for slot: Array in adult_def.slots():
		if slot[1] == &"sleep":
			adult_bed = slot[0]
	assert_true(child_bed < adult_bed, "%.2f before %.2f" % [child_bed, adult_bed])


# --- sleepers -------------------------------------------------------------------------------------

func test_a_touched_sleeper_mostly_dreams_of_it() -> void:
	_set_hour(23.0)
	var person := _calm(_adult())
	var reacted: Array = []
	behavior.reacted.connect(func(id: int, reaction: StringName, _i: StringName, _s: StringName, _d: bool) -> void:
		reacted.append([id, reaction]))
	var dreamt := 0
	var woke := 0
	for i in 60:
		for id in person.memory_ids.duplicate():
			session.memories.forget(person, id)
		_calm(person)
		_put_to_bed(person)
		assert_eq(person.pose, PersonData.Pose.SLEEP)
		_touch(person)
		var outcome := behavior.last_outcome(person.id)
		assert_true(outcome.direct)
		assert_true(outcome.salience <= 0.2, "a sleeper takes in little (%.2f)" % outcome.salience)
		if outcome.interpretation == ReactionTable.DREAM:
			dreamt += 1
			assert_eq(outcome.reaction, ReactionTable.STIR)
			assert_eq(outcome.steps.size(), 0)
			assert_eq(BehaviorSystem.activity_of(person), &"sleep", "they sleep on")
			assert_true(person.has_flag(PersonData.FLAG_INDOORS))
			var memory := session.memories.about(person, Stimulus.TOUCH)[0]
			assert_eq(memory.interpretation, ReactionTable.DREAM)
			assert_eq(MemoryText.text(memory), "dreamt of a warm hand")
			assert_eq(Interpretation.conviction(person), &"", "a dream convinces nobody of anything")
		else:
			woke += 1
			assert_eq(BehaviorSystem.activity_of(person), BehaviorSystem.ACTIVITY_REACT, "startled awake")
			assert_false(person.has_flag(PersonData.FLAG_INDOORS), "and out of the hut")
			assert_ne(person.pose, PersonData.Pose.SLEEP)
	print("    60 sleepers touched: %d dreamt of it, %d woke" % [dreamt, woke])
	assert_true(dreamt > woke * 3 / 2, "mostly a dream (%d of 60)" % dreamt)
	assert_true(woke >= 2, "some start awake (%d)" % woke)
	assert_eq(reacted.size(), woke, "only those who woke are seen to react")
	assert_true(person.has_flag(PersonData.FLAG_TOUCHED_BY_PLAYER))
	# Awake, nobody takes anything for a dream.
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	assert_false(Interpretation.available(person, ReactionTable.DREAM, ctx, table))
	for i in 40:
		_calm(person)
		_touch(person)
		assert_ne(behavior.last_outcome(person.id).interpretation, ReactionTable.DREAM)
		behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(600.0)])
	# The words and the numbers are there for it.
	assert_true(UIText.INTERPRETATION_PHRASES.has(ReactionTable.DREAM))
	assert_true(MemoryText.has("MEM_TOUCH_DREAM") and MemoryText.has("MEM_KNOCK_DREAM") and MemoryText.has("MEMBELIEF_DREAM"))
	assert_eq(Interpretation.beliefs_of(person).size(), ReactionTable.INTERPRETATIONS.size(), "convictions have room for it")
	assert_eq(ReactionTable.INTERPRETATIONS[-1], ReactionTable.DREAM, "appended: saved convictions keep their places")


func test_a_knock_on_the_wall_reaches_those_asleep_behind_it() -> void:
	_set_hour(23.5)
	var everyone := session.people.all_people()
	for p in everyone:
		_calm(p)
		_put_to_bed(p)
	var hut := session.props.get_prop(everyone[0].home_building_id)
	var inside: Array[PersonData] = session.people.living_in(hut.id)
	assert_true(inside.size() >= 1 and inside.size() < everyone.size())
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = hut.id
	target.tile = hut.tile
	session.interactions.tap(target)
	assert_eq(session.perception.last.type, Stimulus.KNOCK)
	assert_eq(session.perception.last.building_id, hut.id)
	assert_eq(session.perception.last_noticed, inside.size(), "those behind this wall, and nobody else")
	_run(1.0)
	var dreamt := 0
	for p in everyone:
		var heard := session.memories.about(p, Stimulus.KNOCK)
		if p.home_building_id == hut.id:
			# (Who woke to something that faint may not keep it; a dream is kept.)
			if not heard.is_empty() and heard[0].interpretation == ReactionTable.DREAM:
				dreamt += 1
				assert_eq(MemoryText.text(heard[0]), "dreamt of someone knocking")
				assert_eq(p.pose, PersonData.Pose.SLEEP)
			elif behavior.last_outcome(p.id) != null:
				assert_ne(behavior.last_outcome(p.id).interpretation, ReactionTable.DREAM)
		else:
			assert_eq(heard.size(), 0, "%s, in another hut, slept through it" % p.given_name)
			assert_eq(p.pose, PersonData.Pose.SLEEP)
	# Over many nights: mostly a dream, now and then someone is woken by it.
	var dreams := 0
	var woken := 0
	for night in 40:
		for p in inside:
			for id in p.memory_ids.duplicate():
				session.memories.forget(p, id)
			_calm(p)
			_put_to_bed(p)
		session.interactions.tap(target)
		_run(1.0)
		for p in inside:
			if behavior.last_outcome(p.id).interpretation == ReactionTable.DREAM:
				dreams += 1
				assert_eq(session.memories.about(p, Stimulus.KNOCK).size(), 1)
			else:
				woken += 1
				assert_eq(BehaviorSystem.activity_of(p), BehaviorSystem.ACTIVITY_REACT)
	print("    %d sleepers knocked at: %d dreamt of it, %d woke" % [dreams + woken, dreams, woken])
	assert_true(dreams > woken * 2, "mostly a dream")
	assert_true(woken >= 1, "but it can wake them")
	# A shaken tree by the hut does not get through a sleeper's sleep.
	for p in everyone:
		_put_to_bed(p)
	var before := session.perception.emitted
	var rustle := Stimulus.new()
	rustle.type = Stimulus.TREE_SHAKEN
	rustle.position = hut.position2d() + Vector2(1.0, 0.0)
	table.describe(rustle)
	assert_eq(session.perception.emit(rustle), 0)
	assert_eq(session.perception.emitted, before + 1)


# --- lights out -----------------------------------------------------------------------------------

func test_a_house_goes_dark_when_everyone_in_it_sleeps() -> void:
	var view: WorldView = ViewScript.new()
	add_child(view)
	view.show_world(session.world, session.props, session.start, session.loose)
	view.show_people(session.people, session.clock, session.occupations)
	var cycle := view.day_night()
	_set_hour(23.0)
	cycle.refresh()
	assert_eq(cycle.state().window_light, 1.0, "night: windows could be lit")
	# Everyone up: every house that has people has a light.
	for p in session.people.all_people():
		p.set_flag(PersonData.FLAG_INDOORS, false)
		p.pose = PersonData.Pose.IDLE
	view.refresh_house_lights()
	var lived_in := 0
	for id in session.start.hut_ids:
		if not session.people.living_in(id).is_empty():
			lived_in += 1
	assert_eq(cycle.dark_houses().size(), session.start.hut_ids.size() - lived_in, "only houses nobody lives in are dark")
	# One household goes to bed.
	var first := session.people.all_people()[0]
	var hut := session.props.get_prop(first.home_building_id)
	var household: Array[PersonData] = session.people.living_in(hut.id)
	for p in household:
		_put_to_bed(p)
	view.refresh_house_lights()
	assert_eq(cycle.dark_houses().size(), session.start.hut_ids.size() - lived_in + 1)
	var dark := cycle.dark_houses()[-1] if cycle.dark_houses().size() == 1 else Vector3.INF
	for at in cycle.dark_houses():
		if Vector2(at.x, at.z).distance_to(hut.position2d()) < 0.01:
			dark = at
	assert_true(Vector2(dark.x, dark.z).distance_to(hut.position2d()) < 0.01, "theirs")
	var material := view.get("_prop_material") as ShaderMaterial
	var slots: Array = material.get_shader_parameter(&"lights_out")
	assert_eq(slots.size(), DayNight.DARK_HOUSES)
	var lit_slots := 0
	for slot: Vector4 in slots:
		if slot.w > 0.0:
			lit_slots += 1
			assert_near(slot.w, DayNight.HOUSE_RADIUS, 0.001)
	assert_eq(lit_slots, cycle.dark_houses().size(), "the shader is told which")
	# One of them gets up: the light is on again.
	behavior.set_plan(household[0], BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(60.0)])
	view.refresh_house_lights()
	assert_eq(cycle.dark_houses().size(), session.start.hut_ids.size() - lived_in)
	# Everyone asleep: the whole settlement is dark — and it happens by itself.
	for p in session.people.all_people():
		_put_to_bed(p)
	await wait_frames(WorldView.HOUSE_LIGHTS_EVERY + 2)
	assert_eq(cycle.dark_houses().size(), session.start.hut_ids.size())
	# The glow of a house reaches no further than the house (two huts are never that close).
	for a in session.start.hut_ids:
		for b in session.start.hut_ids:
			if a != b:
				assert_true(session.props.get_prop(a).position2d().distance_to(session.props.get_prop(b).position2d()) > DayNight.HOUSE_RADIUS * 2.0)
	view.queue_free()


# --- a whole day ----------------------------------------------------------------------------------

func test_the_day_has_a_shape() -> void:
	# From six in the morning, two days; the second is the one looked at.
	session.clock.tick = 0
	var people := session.people.all_people()
	var most_at_meal := {7: 0, 12: 0, 18: 0}
	var abed_at_23 := 0
	var adults_up_at_dusk := 0
	var children_abed_at_dusk := 0
	var up_at_10 := 0
	var working_at_10 := 0
	for minute in 2880:
		_run(1.0)
		if minute < 1440:
			continue
		var hour := session.clock.hour_of_day()
		var eating := 0
		for p in people:
			if p.pose == PersonData.Pose.EAT:
				eating += 1
		for meal: int in most_at_meal:
			if hour >= meal and hour <= meal + 1:
				most_at_meal[meal] = maxi(most_at_meal[meal], eating)
		if hour == 20 and session.clock.minute() == 0:
			for p in people:
				if ctx.stage_of(p) == PersonData.LifeStage.ADULT:
					adults_up_at_dusk += 0 if p.pose == PersonData.Pose.SLEEP else 1
				elif ctx.stage_of(p) == PersonData.LifeStage.CHILD:
					children_abed_at_dusk += 1 if p.pose == PersonData.Pose.SLEEP else 0
		if hour == 23 and session.clock.minute() == 0:
			for p in people:
				abed_at_23 += 1 if p.has_flag(PersonData.FLAG_INDOORS) else 0
		if hour == 10 and session.clock.minute() == 0:
			for p in people:
				up_at_10 += 0 if p.has_flag(PersonData.FLAG_INDOORS) else 1
				working_at_10 += 1 if BehaviorSystem.activity_of(p) == &"work" else 0
	print("    the second day: most at breakfast %d, lunch %d, dinner %d of %d; %d at work at ten; %d abed at eleven" % [
		most_at_meal[7], most_at_meal[12], most_at_meal[18], people.size(), working_at_10, abed_at_23])
	assert_true(most_at_meal[12] >= 4, "lunch is taken together (%d)" % most_at_meal[12])
	assert_true(most_at_meal[18] >= 4, "and so is dinner")
	assert_true(most_at_meal[7] >= 3, "breakfast more loosely (people rise at their own hour)")
	print("    at eight in the evening: %d grown-ups still up, %d children asleep" % [adults_up_at_dusk, children_abed_at_dusk])
	assert_true(adults_up_at_dusk >= 2, "grown-ups are up after dark (%d)" % adults_up_at_dusk)
	assert_true(children_abed_at_dusk >= 1, "children are in bed by then")
	assert_eq(up_at_10, people.size(), "everyone is up at ten")
	assert_true(working_at_10 >= 3, "and most who have work are at it (%d)" % working_at_10)
	assert_eq(abed_at_23, people.size(), "and everyone is in bed at eleven")
