extends TestCase
## People deciding and doing (M4.4): the brain, plans and their steps, in the
## generated world. Time is stepped by hand.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const YEAR := 1440 * 24

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var changes: Array = [] # [person id, activity]


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
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


## Points the test at a session and stops its own clock.
func _take(s: WorldSession) -> void:
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	behavior = s.behavior
	ctx = behavior.ctx
	changes.clear()
	behavior.activity_changed.connect(func(id: int, activity: StringName) -> void: changes.append([id, activity]))


## Lets `minutes` of game time pass, the clock included.
func _run(minutes: float, step: float = 0.5) -> void:
	var left := minutes
	while left > 0.0001:
		var dt := minf(step, left)
		_advance_clock(dt)
		behavior.step(dt)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		left -= dt


## Moves the clock on by `minutes` of game time (in pieces: the clock never
## takes more than a frame's worth at once).
func _advance_clock(minutes: float) -> void:
	var seconds := minutes * Config.time.real_seconds_per_game_minute
	while seconds > 0.000001:
		var piece := minf(seconds, Config.time.max_frame_delta_s)
		session.clock.advance(piece)
		seconds -= piece


## Sets the clock to `hour` of the day (0 … 24) without anything happening.
func _set_hour(hour: float) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440)


func _adult(occupation: StringName = &"") -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == PersonData.LifeStage.ADULT and (occupation == &"" or p.occupation_id == occupation):
			return p
	return null


func _of(stage: PersonData.LifeStage) -> PersonData:
	for p in session.people.all_people():
		if ctx.stage_of(p) == stage:
			return p
	return null


## Everything met, an even temper: someone with no reason for anything.
func _content(person: PersonData) -> void:
	person.needs = Needs.full()
	person.traits = Traits.neutral()
	person.activity_log = {}


func _activity(person: PersonData) -> StringName:
	return BehaviorSystem.activity_of(person)


func _step_type(person: PersonData) -> String:
	return str(BehaviorSystem.current_step(person).get("type", ""))


func _mine(person: PersonData) -> Array[StringName]:
	var out: Array[StringName] = []
	for change: Array in changes:
		if change[0] == person.id:
			out.append(change[1])
	return out


## Runs until `person` is doing `activity` (or `limit` minutes have passed).
func _until(person: PersonData, activity: StringName, limit: float = 600.0) -> bool:
	var waited := 0.0
	while waited < limit:
		if _activity(person) == activity:
			return true
		_run(1.0)
		waited += 1.0
	return _activity(person) == activity


# --- the data -------------------------------------------------------------------------------------

func test_the_activities_are_defined_in_data() -> void:
	var library := session.activities
	assert_eq(library.problems.size(), 0, str(library.problems))
	assert_eq(library.ids(), [&"drink", &"eat", &"explore", &"go_home", &"play", &"sleep", &"socialize", &"work"] as Array[StringName])
	_set_hour(10.0)
	var person := _adult()
	for id in library.ids():
		var def := library.get_def(id)
		assert_eq(def.validate().size(), 0)
		assert_true(UIText.ACTIVITY_NAMES.has(id), "wording for %s" % id)
		for requirement in def.requires:
			assert_true(Planner.REQUIREMENTS.has(requirement), "%s requires '%s'" % [id, requirement])
		var steps := Planner.plan(id, person, ctx)
		assert_true(steps.size() >= 2, "the planner knows how to %s" % id)
		for step: Dictionary in steps:
			assert_true(behavior._steps.has(str(step["type"])), "a step the system can carry out (%s)" % step["type"])
			assert_eq(bytes_to_var(var_to_bytes(step)), step, "plain data")
	assert_eq(Planner.plan(&"fly", person, ctx).size(), 0)
	assert_eq(UIText.activity_phrase(&"eat", &"hunger"), "Eating — hungry")
	assert_eq(UIText.activity_phrase(&"work", &"routine"), "Working")
	assert_eq(UIText.activity_phrase(&""), "")


# --- the brain ------------------------------------------------------------------------------------

func test_brain_selects_eat_when_hungry() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.HUNGER] = 0.1
	for i in 100:
		var decision := Brain.decide(person, ctx)
		if decision.activity != &"eat":
			fail("a hungry person chose to %s" % decision.activity)
			break
		assert_eq(decision.reason, &"hunger")
	var scores := Brain.decide(person, ctx).scores
	assert_true(scores[&"eat"] > 1.0)
	for id: StringName in scores:
		if id != &"eat":
			assert_true(scores[id] < scores[&"eat"] * 0.5, "%s is far behind (%.2f)" % [id, scores[id]])


func test_each_pressing_need_has_its_answer() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.THIRST] = 0.1
	assert_eq(Brain.decide(person, ctx).activity, &"drink")
	assert_eq(Brain.decide(person, ctx).reason, &"thirst")
	_content(person)
	person.needs[Needs.Need.SLEEP] = 0.05
	assert_eq(Brain.decide(person, ctx).activity, &"sleep", "dead tired: bed, even by day")
	_content(person)
	person.needs[Needs.Need.SOCIAL] = 0.0
	assert_eq(Brain.decide(person, ctx).activity, &"socialize")
	assert_eq(Brain.decide(person, ctx).reason, &"social")
	_content(person)
	person.needs[Needs.Need.SAFETY] = 0.0
	assert_eq(Brain.decide(person, ctx).activity, &"go_home", "frightened people go home")
	_content(person)
	person.needs[Needs.Need.PURPOSE] = 0.0
	assert_eq(Brain.decide(person, ctx).activity, &"work")
	# Two needs at once: the more pressing one wins.
	_content(person)
	person.needs[Needs.Need.HUNGER] = 0.4
	person.needs[Needs.Need.THIRST] = 0.05
	assert_eq(Brain.decide(person, ctx).activity, &"drink")


func test_brain_variety() -> void:
	# Someone with nothing pressing, on an ordinary morning: 1,000 decisions.
	_set_hour(10.0)
	var person := _adult()
	person.traits = Traits.neutral()
	person.activity_log = {}
	person.needs = PackedFloat32Array([0.75, 0.75, 0.8, 0.6, 0.7, 1.0])
	var tally := {}
	for i in 1000:
		var chosen := Brain.decide(person, ctx).activity
		tally[chosen] = int(tally.get(chosen, 0)) + 1
	assert_true(tally.size() >= 2, "not always the same thing (%s)" % [tally])
	var most := 0
	for id: StringName in tally:
		most = maxi(most, tally[id])
	assert_true(most < 950, "nothing is chosen (nearly) every time (%s)" % [tally])
	assert_true(most > 400, "but there is a favourite: no coin tossing either (%s)" % [tally])
	assert_true(tally.size() <= Brain.TOP_CANDIDATES, "only the best few are in the draw")
	assert_false(tally.has(&"sleep"), "nobody rested goes to bed at ten in the morning")
	assert_false(tally.has(&"eat"))


func test_the_dice_are_the_worlds_own() -> void:
	_set_hour(10.0)
	var person := _adult()
	person.needs = PackedFloat32Array([0.75, 0.75, 0.8, 0.6, 0.7, 1.0])
	var state := ctx.rng.state
	var first: Array[StringName] = []
	for i in 40:
		first.append(Brain.decide(person, ctx).activity)
	ctx.rng.state = state
	var again: Array[StringName] = []
	for i in 40:
		again.append(Brain.decide(person, ctx).activity)
	assert_eq(again, first, "the same dice, the same decisions")
	assert_true(session.rng.to_dict()["states"].has("ai"), "the ai has its own stream")


func test_creative_people_are_less_predictable() -> void:
	_set_hour(10.0)
	var person := _adult()
	person.activity_log = {}
	person.needs = PackedFloat32Array([0.75, 0.75, 0.8, 0.6, 0.7, 1.0])
	var favourite := [0, 0]
	for kind in 2:
		person.traits = Traits.neutral()
		person.traits[Traits.Axis.CREATIVITY] = 0.0 if kind == 0 else 1.0
		var tally := {}
		for i in 600:
			var chosen := Brain.decide(person, ctx).activity
			tally[chosen] = int(tally.get(chosen, 0)) + 1
		for id: StringName in tally:
			favourite[kind] = maxi(favourite[kind], tally[id])
	assert_true(Brain.temperature(person) > Brain.TEMPERATURE_MIN)
	assert_true(favourite[0] > favourite[1] + 30, "the plain keep to their favourite (%d of 600) more than the creative (%d)" % favourite)


func test_someone_busy_keeps_at_it_unless_something_presses() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.PURPOSE] = 0.6
	person.needs[Needs.Need.HUNGER] = 0.4 # peckish
	for i in 50:
		assert_eq(Brain.decide(person, ctx, &"work").activity, &"work", "peckish is no reason to down tools")
	# Asked afresh, the same person might well go and eat.
	var would_eat := 0
	for i in 200:
		if Brain.decide(person, ctx).activity == &"eat":
			would_eat += 1
	assert_true(would_eat > 0)
	person.needs[Needs.Need.HUNGER] = 0.15 # starving
	assert_eq(Brain.decide(person, ctx, &"work").activity, &"eat")
	# What is being done but is no longer possible is not kept.
	_content(person)
	person.occupation_id = &""
	assert_ne(Brain.decide(person, ctx, &"work").activity, &"work")


func test_the_hour_bends_decisions_without_ruling_them() -> void:
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.SLEEP] = 0.5
	person.needs[Needs.Need.PURPOSE] = 0.6
	_set_hour(10.0)
	var by_day := Brain.decide(person, ctx)
	_set_hour(23.0)
	var by_night := Brain.decide(person, ctx)
	assert_true(by_day.scores[&"work"] > by_day.scores[&"sleep"], "by day: work")
	assert_true(by_night.scores[&"sleep"] > by_night.scores[&"work"] * 3.0, "at night: bed")
	assert_eq(by_night.activity, &"sleep")
	# A routine is a lean, not a rule: someone starving eats at midnight too.
	person.needs[Needs.Need.SLEEP] = 0.8
	person.needs[Needs.Need.HUNGER] = 0.0
	_set_hour(0.5)
	assert_eq(Brain.decide(person, ctx).activity, &"eat")


func test_what_is_not_possible_is_not_chosen() -> void:
	_set_hour(10.0)
	var child := _of(PersonData.LifeStage.CHILD)
	_content(child)
	child.needs[Needs.Need.PURPOSE] = 0.0
	var decision := Brain.decide(child, ctx)
	assert_eq(decision.scores[&"work"], -1.0, "children have no work to go to")
	assert_ne(decision.activity, &"work")
	# No home: no bed, no going home.
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.SLEEP] = 0.0
	person.home_building_id = 0
	decision = Brain.decide(person, ctx)
	assert_eq(decision.scores[&"sleep"], -1.0)
	assert_eq(decision.scores[&"go_home"], -1.0)
	assert_ne(decision.activity, &"sleep")
	# Barred for now (it has just failed): not that either.
	_content(person)
	person.needs[Needs.Need.THIRST] = 0.0
	assert_ne(Brain.decide(person, ctx, &"", {&"drink": true}).activity, &"drink")
	# Nobody about: nobody to talk to.
	for other in session.people.all_people():
		if other.id != person.id:
			other.set_flag(PersonData.FLAG_INDOORS, true)
	person.needs[Needs.Need.SOCIAL] = 0.0
	assert_eq(Brain.decide(person, ctx).scores[&"socialize"], -1.0)


func test_having_just_done_something_speaks_against_doing_it_again() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	var explore := session.activities.get_def(&"explore")
	var fresh := Brain.score(explore, person, ctx)
	person.activity_log["explore"] = ctx.now()
	var just_done := Brain.score(explore, person, ctx)
	assert_true(just_done < fresh, "%.2f after, %.2f before" % [just_done, fresh])
	person.activity_log["explore"] = ctx.now() - int(explore.repeat_after_minutes) - 1
	assert_near(Brain.score(explore, person, ctx), fresh, 0.0001, "after a while it is as good as new")


func test_traits_show_in_what_people_choose() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	var explore := session.activities.get_def(&"explore")
	var plain := Brain.score(explore, person, ctx)
	person.traits[Traits.Axis.CURIOSITY] = 1.0
	person.traits[Traits.Axis.ADVENTURE] = 1.0
	var keen := Brain.score(explore, person, ctx)
	person.traits[Traits.Axis.CURIOSITY] = -1.0
	person.traits[Traits.Axis.ADVENTURE] = -1.0
	var wary := Brain.score(explore, person, ctx)
	assert_true(keen > plain and plain > wary)
	assert_eq(Brain.reason_for(explore, _keen(person)), &"nature", "the curious explore because they are curious")
	_content(person)
	assert_eq(Brain.reason_for(session.activities.get_def(&"work"), person), &"routine")


func _keen(person: PersonData) -> PersonData:
	person.traits[Traits.Axis.CURIOSITY] = 1.0
	person.traits[Traits.Axis.ADVENTURE] = 1.0
	return person


# --- plans ----------------------------------------------------------------------------------------

func test_plan_hungry_home_food_eat_work() -> void:
	# The bible's example (13.4): hungry at home -> to the food -> eat -> work.
	_set_hour(8.0)
	var person := _adult(&"woodcutter")
	_content(person)
	person.needs[Needs.Need.HUNGER] = 0.15
	person.needs[Needs.Need.PURPOSE] = 0.25
	var home := session.props.get_prop(person.home_building_id)
	var fire := session.props.get_prop(session.start.campfire_id)
	session.people.move(person.id, session.pathfinder.standable_near(home.tile, 1)[0])
	_run_one(person, 0.0) # (only this person lives, for the length of the test)
	assert_eq(_activity(person), &"eat")
	assert_eq(BehaviorSystem.reason_of(person), &"hunger")
	assert_eq(_step_type(person), "walk_to")
	assert_eq(BehaviorSystem.current_step(person)["target"], fire.tile, "to where the food is")
	assert_true(session.movement.is_walking(person.id))
	# FOOD: beside the fire.
	var walked := 0.0
	while _step_type(person) == "walk_to" and walked < 120.0:
		_run_one(person, 0.5)
		walked += 0.5
	assert_eq(_step_type(person), "eat")
	assert_true((person.position - fire.tile).length() < 2.0, "at the fire (%s)" % person.position)
	assert_eq(person.pose, PersonData.Pose.EAT)
	assert_true(Vector2.from_angle(person.facing).dot((Vector2(fire.tile) + Vector2(0.5, 0.5) - person.world2d()).normalized()) > 0.9, "turned to it")
	# EAT: until full.
	var ate := 0.0
	while _activity(person) == &"eat" and ate < 120.0:
		_run_one(person, 0.5)
		ate += 0.5
	assert_near(ate, Config.needs.meal_minutes * 0.85, Config.needs.meal_minutes * 0.2, "a meal's time (%.1f min)" % ate)
	assert_true(person.needs[Needs.Need.HUNGER] > 0.95, "no longer hungry (%.2f)" % person.needs[Needs.Need.HUNGER])
	assert_eq(person.activity_log["eat"], ctx.now())
	# WORK: off to a tree, axe in hand.
	assert_eq(_activity(person), &"work", "fed: now to work")
	var tree := session.props.get_prop(int((person.current_action["steps"] as Array)[1]["target"]))
	assert_eq(tree.kind, PropData.Kind.TREE, "a woodcutter's work is a tree")
	var strokes := []
	behavior.worked.connect(func(id: int, kind: StringName, target: int) -> void: strokes.append([id, kind, target]))
	walked = 0.0
	while _step_type(person) == "walk_to" and walked < 240.0:
		_run_one(person, 0.5)
		walked += 0.5
	assert_eq(_step_type(person), "work")
	assert_true((person.position - tree.tile).length() < 2.0, "at the tree")
	assert_eq(person.pose, PersonData.Pose.WORK)
	var purpose := person.needs[Needs.Need.PURPOSE]
	for i in 40:
		_run_one(person, 0.5)
	assert_true(person.needs[Needs.Need.PURPOSE] > purpose, "work gives purpose")
	assert_eq(strokes.size(), 10, "a stroke every two minutes")
	assert_eq(strokes[0], [person.id, &"tree", tree.id])
	assert_eq(_mine(person), [&"eat", &"work"] as Array[StringName], "HOME -> FOOD -> EAT -> WORK")


## Lets time pass for one person only (the others stand still).
func _run_one(person: PersonData, minutes: float) -> void:
	_advance_clock(minutes)
	behavior._live(person, minutes)
	for stroke: Array in ctx.strokes:
		behavior.worked.emit(stroke[0], stroke[1], stroke[2])
	ctx.strokes.clear()
	session.pathfinder.serve(1_000_000)
	session.movement.step(minutes)


func test_the_thirsty_walk_to_the_water_and_drink() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.THIRST] = 0.1
	behavior.think(person)
	assert_eq(_activity(person), &"drink")
	var water: Vector2i = BehaviorSystem.current_step(person)["target"]
	assert_true(session.world.get_water(water) > 0.0, "the way leads to water")
	var waited := 0.0
	while _activity(person) == &"drink" and waited < 300.0:
		_run_one(person, 0.5)
		waited += 0.5
		if _step_type(person) == "drink":
			assert_true((Vector2(water) + Vector2(0.5, 0.5)).distance_to(person.world2d()) <= DrinkStep.REACH, "at the water's edge")
			assert_true(session.world.get_water(person.position) <= Pathfinder.WADE_DEPTH * session.world.height_step, "not in over their head")
	assert_true(person.needs[Needs.Need.THIRST] > 0.95, "thirst quenched (%.2f)" % person.needs[Needs.Need.THIRST])
	assert_true(person.activity_log.has("drink"))


func test_the_tired_go_home_and_sleep_until_rested() -> void:
	_set_hour(22.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.SLEEP] = 0.2
	behavior.think(person)
	assert_eq(_activity(person), &"sleep")
	var home := session.props.get_prop(person.home_building_id)
	var waited := 0.0
	while _step_type(person) != "sleep" and waited < 120.0:
		_run_one(person, 0.5)
		waited += 0.5
	assert_eq(_step_type(person), "sleep")
	assert_true((person.position - home.tile).length() < 2.0, "at their own hut")
	assert_true(person.has_flag(PersonData.FLAG_INDOORS), "inside")
	assert_eq(person.pose, PersonData.Pose.SLEEP)
	var hunger := person.needs[Needs.Need.HUNGER]
	var slept := 0.0
	while _activity(person) == &"sleep" and slept < 1200.0:
		_run_one(person, 1.0)
		slept += 1.0
	assert_true(person.needs[Needs.Need.SLEEP] >= SleepStep.RESTED - 0.02, "rested (%.2f)" % person.needs[Needs.Need.SLEEP])
	assert_true(slept > 400.0 and slept < 650.0, "a night's sleep (%.0f minutes)" % slept)
	assert_false(person.has_flag(PersonData.FLAG_INDOORS), "up and out")
	assert_ne(person.pose, PersonData.Pose.SLEEP)
	assert_true(hunger - person.needs[Needs.Need.HUNGER] < slept * Config.needs.hunger_per_minute * 0.7, "hunger waited while they slept")
	var hour := session.clock.hour()
	assert_true(hour > 4.0 and hour < 9.5, "up in the morning (%.1f h)" % hour)


func test_a_sleeper_wakes_when_something_presses() -> void:
	_set_hour(23.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.SLEEP] = 0.3
	behavior.think(person)
	var waited := 0.0
	while _step_type(person) != "sleep" and waited < 120.0:
		_run_one(person, 0.5)
		waited += 0.5
	assert_true(person.has_flag(PersonData.FLAG_INDOORS))
	person.needs[Needs.Need.THIRST] = 0.0
	var woke := false
	for i in 40:
		_run_one(person, 0.5)
		if _activity(person) == &"drink":
			woke = true
			assert_false(person.has_flag(PersonData.FLAG_INDOORS), "out of the hut")
			break
	assert_true(woke, "parched: up and to the water (within the quarter hour it takes to notice)")
	# Mild thirst does not get anyone out of bed.
	person.needs[Needs.Need.THIRST] = 1.0
	behavior.set_plan(person, &"sleep", &"sleep", [SleepStep.make()], 1.2)
	person.needs[Needs.Need.THIRST] = 0.45
	for i in 80:
		_run_one(person, 0.5)
	assert_eq(_activity(person), &"sleep")


func test_company_is_good_for_both() -> void:
	_set_hour(18.0)
	var person := _adult()
	_content(person)
	person.needs[Needs.Need.SOCIAL] = 0.1
	behavior.think(person)
	assert_eq(_activity(person), &"socialize")
	var partner := session.people.get_person(int((person.current_action["steps"] as Array)[1]["partner"]))
	assert_not_null(partner)
	assert_ne(partner.id, person.id)
	partner.needs[Needs.Need.SOCIAL] = 0.3
	var waited := 0.0
	while _step_type(person) != "socialize" and _activity(person) == &"socialize" and waited < 120.0:
		_run_one(person, 0.5)
		waited += 0.5
	assert_eq(_step_type(person), "socialize")
	assert_true(person.world2d().distance_to(partner.world2d()) <= SocializeStep.EARSHOT, "standing together")
	assert_ne(person.position, partner.position, "not on top of each other")
	for i in 20:
		_run_one(person, 0.5)
	assert_true(person.needs[Needs.Need.SOCIAL] > 0.25)
	assert_true(partner.needs[Needs.Need.SOCIAL] > 0.3, "the one visited gets something out of it too")
	assert_true(person.needs[Needs.Need.SOCIAL] - 0.1 > partner.needs[Needs.Need.SOCIAL] - 0.3, "the one who came, more")
	assert_true(Vector2.from_angle(person.facing).dot((partner.world2d() - person.world2d()).normalized()) > 0.95, "turned to them")
	assert_true(Vector2.from_angle(partner.facing).dot((person.world2d() - partner.world2d()).normalized()) > 0.95, "and they to the visitor")
	assert_eq(person.pose, PersonData.Pose.TALK)
	# The partner goes to bed: the talk is over.
	partner.set_flag(PersonData.FLAG_INDOORS, true)
	_run_one(person, 0.5)
	assert_ne(_step_type(person), "socialize")


func test_exploring_leads_somewhere_new() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	var home := session.props.get_prop(person.home_building_id)
	assert_eq(ctx.places.visited_count(), 0)
	behavior.set_plan(person, &"explore", &"nature", Planner.plan(&"explore", person, ctx))
	var target: Vector2i = BehaviorSystem.current_step(person)["target"]
	var away := Vector2(target - home.tile).length()
	assert_true(away >= Places.EXPLORE_MIN - 1.0 and away <= Places.EXPLORE_MAX + 1.0, "a walk, not a journey (%.1f tiles)" % away)
	assert_true(session.pathfinder.can_stand(target))
	var waited := 0.0
	while _activity(person) == &"explore" and waited < 400.0:
		_run_one(person, 0.5)
		waited += 0.5
	assert_true(person.activity_log.has("explore"))
	assert_true(ctx.places.was_visited(target), "the band knows the place now")
	# Children stay nearer home.
	var child := _of(PersonData.LifeStage.CHILD)
	var child_home := session.props.get_prop(child.home_building_id)
	for i in 30:
		var near: Variant = ctx.places.explore_tile(child, PersonData.LifeStage.CHILD, ctx.rng)
		if near != null:
			assert_true(Vector2(near - child_home.tile).length() <= Places.EXPLORE_CHILD_MAX + 1.0)


func test_everyone_s_work_is_their_own() -> void:
	_set_hour(10.0)
	var kinds := {&"woodcutter": PropData.Kind.TREE, &"forager": PropData.Kind.BUSH, &"elder": PropData.Kind.CAMPFIRE}
	for occupation: StringName in kinds:
		var person: PersonData = null
		for p in session.people.all_people():
			if p.occupation_id == occupation:
				person = p
		assert_not_null(person, String(occupation))
		var steps := Planner.plan(&"work", person, ctx)
		assert_eq(steps.size(), 2)
		var target := session.props.get_prop(int(steps[1]["target"]))
		assert_eq(target.kind, kinds[occupation], "a %s works at a %s" % [occupation, PropData.Kind.keys()[kinds[occupation]]])
		assert_true(Vector2(target.tile - session.start.settlement_tile).length() <= Places.WORK_RADIUS + 6.0, "near home")
	# Not always the same tree.
	var woodcutter := _adult(&"woodcutter")
	var trees := {}
	for i in 60:
		trees[Planner.plan(&"work", woodcutter, ctx)[1]["target"]] = true
	assert_true(trees.size() >= 3, "%d different trees" % trees.size())
	assert_eq(Planner.plan(&"work", _of(PersonData.LifeStage.CHILD), ctx).size(), 0, "no work for children")


func test_work_ends_when_what_was_worked_at_is_gone() -> void:
	_set_hour(10.0)
	var person := _adult(&"woodcutter")
	_content(person)
	person.needs[Needs.Need.PURPOSE] = 0.0
	behavior.think(person)
	assert_eq(_activity(person), &"work")
	var waited := 0.0
	while _step_type(person) != "work" and waited < 240.0:
		_run_one(person, 0.5)
		waited += 0.5
	var tree_id := int(BehaviorSystem.current_step(person)["target"])
	session.props.remove(tree_id) # the player uproots it under the axe
	_run_one(person, 0.5)
	assert_false(_step_type(person) == "work" and int(BehaviorSystem.current_step(person).get("target", 0)) == tree_id,
		"nobody chops at a tree that is not there")


func test_what_cannot_be_done_is_given_up_for_a_while() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	# A plan that cannot work: water on the far side of the river.
	var river_x := int(session.generator.river_center_x(session.start.settlement_tile.y))
	var side := -1 if session.start.settlement_tile.x > river_x else 1
	var far := Vector2i(river_x + side * 12, session.start.settlement_tile.y)
	behavior.set_plan(person, &"drink", &"thirst", [WalkToStep.make(far), DrinkStep.make(far)])
	person.needs[Needs.Need.THIRST] = 0.0
	for i in 20:
		_run_one(person, 0.5)
	assert_ne(_activity(person), &"drink", "no way there: something else for now")
	assert_ne(_activity(person), &"")
	assert_eq(Brain.decide(person, ctx).activity, &"drink", "(they are still thirsty)")
	assert_true(behavior._barred_now(person.id).has(&"drink"))
	# After a while they try again — and this time find water they can reach.
	session.clock.tick += BehaviorSystem.BARRED_MINUTES + 1
	assert_false(behavior._barred_now(person.id).has(&"drink"))
	behavior.think(person)
	assert_eq(_activity(person), &"drink")


func test_nothing_to_do_means_standing_about_not_spinning() -> void:
	var person := _adult()
	_content(person)
	# Somewhere with nothing: no home, no work, nobody about, nothing known.
	person.home_building_id = 0
	person.occupation_id = &""
	for other in session.people.all_people():
		if other.id != person.id:
			other.set_flag(PersonData.FLAG_INDOORS, true)
	var bar := {}
	for id in session.activities.ids():
		bar[id] = ctx.now() + 500
	behavior._barred[person.id] = bar
	var before := behavior.decisions
	behavior.think(person)
	assert_eq(_activity(person), BehaviorSystem.ACTIVITY_IDLE)
	for i in 40:
		_run_one(person, 0.5)
	assert_eq(_activity(person), BehaviorSystem.ACTIVITY_IDLE)
	assert_true(behavior.decisions - before <= 6, "thinking again only now and then (%d times in 20 minutes)" % (behavior.decisions - before))


func test_a_broken_plan_is_replaced() -> void:
	_set_hour(10.0)
	var person := _adult()
	_content(person)
	for broken: Variant in [{"activity": "eat", "steps": "soup", "index": 0}, {"activity": "eat", "steps": [{"type": "juggle"}], "index": 0},
			{"activity": "eat", "steps": [], "index": 3}, {"steps": [42]}]:
		person.current_action = broken
		_run_one(person, 0.5)
		assert_true(session.activities.get_def(_activity(person)) != null, "a plan the system knows (%s)" % _activity(person))
		assert_ne(_step_type(person), "")


func test_frozen_people_do_not_live() -> void:
	behavior.enabled = false
	var before := session.people.to_dict()
	_run(60.0)
	assert_eq(session.people.to_dict(), before)
	behavior.enabled = true
	_run(1.0)
	assert_ne(session.people.to_dict(), before)


# --- saving ---------------------------------------------------------------------------------------

func _save_and_reload() -> WorldSession:
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	return again


func test_a_world_saved_in_the_middle_of_things_goes_on_from_there() -> void:
	_set_hour(8.0)
	var eater := _adult(&"woodcutter")
	var walker := _adult(&"forager")
	var sleeper := _of(PersonData.LifeStage.ELDER)
	_content(eater)
	eater.needs[Needs.Need.HUNGER] = 0.1
	behavior.think(eater)
	var waited := 0.0
	while _step_type(eater) != "eat" and waited < 120.0:
		_run_one(eater, 0.5)
		waited += 0.5
	for i in 16:
		_run_one(eater, 0.5) # eight minutes into the meal
	_content(walker)
	walker.needs[Needs.Need.THIRST] = 0.1
	behavior.think(walker)
	for i in 6:
		_run_one(walker, 0.5) # on the way to the water
	assert_eq(_step_type(walker), "walk_to")
	behavior.set_plan(sleeper, &"sleep", &"sleep", [SleepStep.make()])
	assert_true(sleeper.has_flag(PersonData.FLAG_INDOORS))
	var meal := float(BehaviorSystem.current_step(eater)["elapsed"])
	var hunger := eater.needs[Needs.Need.HUNGER]
	var walker_at := walker.world2d()
	var water: Vector2i = BehaviorSystem.current_step(walker)["target"]
	var ids := [eater.id, walker.id, sleeper.id]

	var old := session
	session = _save_and_reload()
	old.queue_free()
	_take(session)
	var eater2 := session.people.get_person(ids[0])
	var walker2 := session.people.get_person(ids[1])
	var sleeper2 := session.people.get_person(ids[2])
	assert_eq(_activity(eater2), &"eat")
	assert_eq(BehaviorSystem.reason_of(eater2), &"hunger")
	assert_near(float(BehaviorSystem.current_step(eater2)["elapsed"]), meal, 0.0001, "the meal is where it was")
	assert_near(eater2.needs[Needs.Need.HUNGER], hunger, 0.0001)
	assert_eq(walker2.world2d(), walker_at)
	assert_eq(BehaviorSystem.current_step(walker2)["target"], water)
	assert_true(sleeper2.has_flag(PersonData.FLAG_INDOORS), "still in bed")
	# Time goes on: the meal is finished, the walk is walked, the sleeper sleeps.
	_run_one(eater2, 0.5)
	_run_one(walker2, 0.5)
	_run_one(sleeper2, 0.5)
	assert_eq(eater2.pose, PersonData.Pose.EAT, "eating again at once")
	assert_true(session.movement.is_walking(walker2.id), "walking again at once")
	assert_eq(sleeper2.pose, PersonData.Pose.SLEEP)
	var left := 0.0
	while _activity(eater2) == &"eat" and left < 60.0:
		_run_one(eater2, 0.5)
		left += 0.5
	assert_near(left + meal, Config.needs.meal_minutes * 0.9, 3.0, "the rest of the meal, not a whole new one")
	left = 0.0
	while _activity(walker2) == &"drink" and left < 300.0:
		_run_one(walker2, 0.5)
		left += 0.5
	assert_true(walker2.needs[Needs.Need.THIRST] > 0.9, "the walk ended at the water")


func test_people_saved_before_needs_get_them_on_loading() -> void:
	var data := session.to_dict()
	for record: Dictionary in data["world_state"]["people"]["persons"]:
		record["needs"] = PackedFloat32Array()
		record.erase("activity_log")
		record["current_action"] = {}
	var old := session
	session = SessionScript.new()
	add_child(session)
	assert_true(session.load_from(data))
	old.queue_free()
	_take(session)
	for p in session.people.all_people():
		assert_eq(p.needs.size(), Needs.COUNT, "%s has needs now" % p.given_name)
		assert_true(p.needs[Needs.Need.HUNGER] >= 0.5)
	_run(5.0)
	for p in session.people.all_people():
		assert_ne(_activity(p), &"", "and something to do")


# --- a day in the life ----------------------------------------------------------------------------

func test_a_whole_day_of_the_band() -> void:
	# Twenty-four hours, everyone living at once. Nobody runs out of anything,
	# nobody is stuck, everybody does the things a day is made of.
	_set_hour(6.0)
	var done := {} # person id -> {activity -> times started}
	var abed_at_two := 0
	var lowest := {}
	var started := Time.get_ticks_usec()
	var stepped := 0
	for minute in 1440:
		_run(1.0, 0.5)
		stepped += 2
		for p in session.people.all_people():
			for need in [Needs.Need.HUNGER, Needs.Need.THIRST, Needs.Need.SLEEP]:
				lowest[need] = minf(lowest.get(need, 1.0), p.needs[need])
			if not session.pathfinder.can_stand(p.position):
				fail("%s stands where nobody can stand (%s) at minute %d" % [p.given_name, p.position, minute])
		if minute == 20 * 60: # two in the morning
			for p in session.people.all_people():
				if p.has_flag(PersonData.FLAG_INDOORS):
					abed_at_two += 1
	var per_minute_ms := (Time.get_ticks_usec() - started) / 1000.0 / 1440.0
	for change: Array in changes:
		if not done.has(change[0]):
			done[change[0]] = {}
		done[change[0]][change[1]] = int(done[change[0]].get(change[1], 0)) + 1
	var people := session.people.all_people()
	var summary := PackedStringArray()
	for p in people:
		var mine: Dictionary = done.get(p.id, {})
		var total := 0
		for activity: StringName in mine:
			total += mine[activity]
		summary.append("%s %d" % [p.given_name, total])
		assert_true(mine.get(&"eat", 0) >= 1, "%s ate (%s)" % [p.given_name, mine])
		assert_true(mine.get(&"drink", 0) >= 2, "%s drank (%s)" % [p.given_name, mine])
		assert_true(mine.get(&"sleep", 0) >= 1, "%s slept (%s)" % [p.given_name, mine])
		assert_true(total >= 8, "%s had a day of some variety (%s)" % [p.given_name, mine])
		assert_true(total <= 70, "%s did not dither (%d changes: %s)" % [p.given_name, total, mine])
		assert_false(mine.has(BehaviorSystem.ACTIVITY_IDLE), "%s always had something to do" % p.given_name)
		var def := session.occupations.get_def(p.occupation_id)
		if def.work_target != &"":
			assert_true(mine.get(&"work", 0) >= 1, "%s the %s worked (%s)" % [p.given_name, p.occupation_id, mine])
		else:
			assert_eq(mine.get(&"work", 0), 0)
	assert_true(abed_at_two >= people.size() - 1, "at two in the morning the band is asleep (%d of %d)" % [abed_at_two, people.size()])
	assert_true(lowest[Needs.Need.THIRST] > 0.05, "nobody went thirsty (lowest %.2f)" % lowest[Needs.Need.THIRST])
	assert_true(lowest[Needs.Need.HUNGER] > 0.1, "or hungry (lowest %.2f)" % lowest[Needs.Need.HUNGER])
	assert_true(lowest[Needs.Need.SLEEP] > 0.05, "or sleepless (lowest %.2f)" % lowest[Needs.Need.SLEEP])
	assert_eq(session.movement.blocks, 0, "nobody set out for somewhere they could not get to")
	print("    a day of the band: %.3f ms per game minute for %d people (%d decisions, %d ways found); changes: %s" % [
		per_minute_ms, people.size(), behavior.decisions, session.pathfinder.paths_found, ", ".join(summary)])
	assert_true(per_minute_ms < 1.0)


func test_twenty_people_think_within_the_budget() -> void:
	# The M4 target: 20 people, AI under 0.5 ms per frame on average.
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var template := session.people.all_people()
	while session.people.size() < 20:
		var like: PersonData = template[session.people.size() % template.size()]
		var p := PersonData.from_dict(like.to_dict())
		p.id = session.ids.next_id()
		p.traits = Traits.generate(rng)
		p.needs = Needs.initial(rng)
		p.current_action = {}
		p.position = session.pathfinder.standable_near(like.position + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3)), 1)[0]
		session.people.add(p)
	_set_hour(9.0)
	_run(30.0) # everyone gets going
	# Frames at normal speed: a thirtieth of a game minute each.
	var worst := 0
	var total := 0
	var frames := 3000
	var busiest := 0 # people who lived in one frame
	var lived := 0
	var living := behavior.decisions
	for frame in frames:
		session.clock.advance(1.0 / 60.0)
		behavior.step(session.clock.last_advance_minutes)
		total += behavior.last_step_usec
		worst = maxi(worst, behavior.last_step_usec)
		session.pathfinder.serve(1000)
		session.movement.step(session.clock.last_advance_minutes)
	var average_ms := total / float(frames) / 1000.0
	print("    20 people: AI %.3f ms per frame on average, worst %.2f ms" % [average_ms, worst / 1000.0])
	assert_true(average_ms < 0.5, "%.3f ms" % average_ms)
	assert_true(behavior.decisions > living, "and they did go on living")
	# People live in whole game minutes, and not all in the same frame.
	var counter := BehaviorSystem.new()
	assert_eq(BehaviorSystem.TICK_MINUTES, 1.0)
	var phases := {}
	for p in session.people.all_people():
		phases[snappedf(counter._phase(p.id), 0.1)] = true
	assert_true(phases.size() >= 6, "the band is spread over the tick (%d different tenths)" % phases.size())
