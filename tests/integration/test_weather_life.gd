extends TestCase
## What the weather and the river do to people's lives (M9.6): shelter,
## heat and cold, the fire in the cold, a flood in the settlement and the
## huts rebuilt above it, a drought that costs a harvest — and people making
## what they will of what nature does.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V18_FIXTURE := "res://tests/fixtures/saves/v18_world.sav"
const V18_ID := "w1790978864_934024cb"
const DAY := 1440

var session: WorldSession
var ctx: AiContext
var weather: WeatherSystem
var river: Hydrology
var settlement: Settlement
var world: WorldData
var clock: GameClock
var config: ExposureConfig
var days := 6
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
	weather = session.weather
	river = session.hydrology
	settlement = session.settlement
	world = session.world
	clock = session.clock
	config = Config.exposure
	days = Config.time.days_per_season
	river.enabled = false


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


func _midnight(day: int) -> int:
	return day * DAY - roundi(Config.time.start_hour * 60.0)


## Sets the clock to an hour of a day and brings the weather there, held at a kind.
func _go_to(day: int, hour: float = 12.0, kind: StringName = &"clear") -> void:
	clock.tick = _midnight(day) + roundi(hour * 60.0)
	weather.advance_to(clock.tick)
	weather.hold(kind, clock.tick + 1000 * DAY)


## Makes the weather feel like this to everyone, at this moment of the clock.
func _feel(temperature: float, pull: float = 0.0, reason: StringName = &"") -> void:
	ctx._weather_tick = ctx.now()
	ctx._temperature = temperature
	ctx._shelter_pull = pull
	ctx._shelter_reason = reason


func _grown_up() -> PersonData:
	for person in session.people.all_people():
		if ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			return person
	return session.people.all_people()[0]


func _content(person: PersonData) -> void:
	person.needs = PackedFloat32Array([0.9, 0.9, 0.9, 0.9, 0.9, 0.9])


func test_what_the_weather_asks_of_people() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	# A fine summer's day keeps nobody in.
	_go_to(days + 3, 13.0)
	assert_near(Exposure.pull(weather, clock.tick), 0.0, 0.001)
	assert_eq(Exposure.reason(weather, clock.tick), &"")
	assert_near(ctx.shelter_pull(), 0.0, 0.001)
	# Rain does, a storm more.
	weather.hold(&"rain", clock.tick + 1000 * DAY)
	assert_near(Exposure.pull(weather, clock.tick), config.pull_by_weather[&"rain"], 0.001)
	assert_eq(Exposure.reason(weather, clock.tick), Exposure.RAIN)
	weather.hold(&"storm", clock.tick + 1000 * DAY)
	assert_near(Exposure.pull(weather, clock.tick), 1.0, 0.001)
	assert_eq(Exposure.reason(weather, clock.tick), Exposure.STORM)
	# (What people feel is worked out once for a moment.)
	assert_near(ctx.shelter_pull(), 0.0, 0.001, "the same moment: as it was felt")
	clock.tick += 1
	assert_near(ctx.shelter_pull(), 1.0, 0.001)
	assert_eq(ctx.shelter_reason(), Exposure.STORM)
	assert_near(ctx.temperature(), weather.temperature(clock.tick), 0.001)
	# The cold does too, the more the colder — up to a point.
	assert_near(Exposure.cold_pull(5.0), 0.0, 0.001)
	assert_near(Exposure.cold_pull(config.cold_pull_from - config.cold_pull_span * 0.5), config.cold_pull_most * 0.5, 0.001)
	assert_near(Exposure.cold_pull(-40.0), config.cold_pull_most, 0.001)
	_knob(Config.climate, &"air_mass_degrees", 0.0)
	_go_to(days * 3 + 3, 14.0, &"snow")
	assert_eq(Exposure.reason(weather, clock.tick), Exposure.SNOW)
	_go_to(days * 3 + 3, 14.0, &"clear")
	assert_true(Exposure.reason(weather, clock.tick) == &"" or Exposure.reason(weather, clock.tick) == Exposure.COLD)
	# Heat slows work; the fire burns more in the cold.
	assert_near(Exposure.work_pace(20.0), 1.0, 0.001)
	assert_near(Exposure.work_pace(config.heat_from + config.heat_span * 0.5), 1.0 - config.heat_slow * 0.5, 0.001)
	assert_near(Exposure.work_pace(50.0), 1.0 - config.heat_slow, 0.001)
	assert_near(Exposure.fire_factor(15.0), 1.0, 0.001)
	assert_near(Exposure.fire_factor(config.fire_cold_from - config.fire_cold_span), 1.0 + config.fire_cold_extra, 0.001)


func test_bad_weather_sends_people_home() -> void:
	_go_to(days + 3, 11.0)
	var person := _grown_up()
	_content(person)
	var home: Vector2i = ctx.places.home_tile(person)
	var go_home := ctx.activities.get_def(&"go_home")
	var work := ctx.activities.get_def(&"work")
	var explore := ctx.activities.get_def(&"explore")
	var eat := ctx.activities.get_def(&"eat")
	# A fine day.
	_feel(20.0)
	# (What speaks for each thing, before the hour's push for what their routine has now.)
	var calm: Dictionary = Brain.decide(person, ctx).plain
	var fine := [calm[&"go_home"], calm[&"work"], calm[&"explore"], calm[&"eat"]]
	assert_true(fine[1] > 0.0)
	var plain := Planner.plan(&"go_home", person, ctx)
	assert_eq(plain.size(), 2)
	assert_false((plain[1] as Dictionary).has("shelter"))
	# A storm: home is worth far more, work half as much, a walk hardly anything — a meal as much as ever.
	_feel(14.0, 1.0, Exposure.STORM)
	var stormy: Dictionary = Brain.decide(person, ctx).plain
	assert_near(stormy[&"go_home"], fine[0] + config.shelter_weight, 0.001)
	assert_near(stormy[&"work"], fine[1] * (1.0 - config.work_cut), 0.001)
	assert_near(stormy[&"explore"], fine[2] * (1.0 - config.outdoor_cut), 0.001)
	assert_near(stormy[&"eat"], fine[3], 0.001)
	assert_true(Brain.score(go_home, person, ctx) > Brain.score(work, person, ctx))
	# So they go home — because of the weather.
	var went := 0
	for n in 20:
		var decision := Brain.decide(person, ctx)
		if decision.activity == &"go_home":
			went += 1
			assert_eq(decision.reason, Brain.REASON_WEATHER)
	assert_true(went >= 18, "%d of 20" % went)
	# Going home in a storm is taking shelter: indoors, for a while.
	var steps := Planner.plan(&"go_home", person, ctx)
	assert_eq(steps.size(), 2)
	var rest: Dictionary = steps[1]
	assert_eq(rest["type"], "rest")
	assert_eq(rest["shelter"], "storm")
	assert_true(float(rest["minutes"]) >= config.shelter_minutes.x and float(rest["minutes"]) <= config.shelter_minutes.y)
	# (They stand at its door: the tile beside it.)
	session.people.move(person.id, home + Vector2i(1, 0))
	var resting := RestStep.new()
	resting.begin(ctx, person, rest)
	assert_true(person.has_flag(PersonData.FLAG_INDOORS), "in the hut, out of sight")
	resting.end(ctx, person, rest)
	assert_false(person.has_flag(PersonData.FLAG_INDOORS))
	# (Nobody is "indoors" away from their hut.)
	session.people.move(person.id, home + Vector2i(0, 3))
	resting.begin(ctx, person, rest)
	assert_false(person.has_flag(PersonData.FLAG_INDOORS))
	resting.end(ctx, person, rest)
	# It is in their day.
	session.behavior.set_plan(person, &"go_home", Brain.REASON_WEATHER, steps)
	var entry: Array = ctx.day_log.of(person.id)[-1]
	assert_eq(DayLogText.text(entry, session.people), "takes shelter from the storm")
	for from: StringName in [Exposure.RAIN, Exposure.SNOW, Exposure.COLD]:
		assert_true(DayLogText.has("DAY_SHELTER_" + String(from).to_upper()))
	# Someone starving eats all the same.
	person.needs[Needs.Need.HUNGER] = 0.02
	_feel(14.0, 1.0, Exposure.STORM)
	var eats := 0
	for n in 20:
		if Brain.decide(person, ctx).activity == &"eat":
			eats += 1
	assert_true(eats >= 18, "%d of 20" % eats)
	# Light rain takes a little from work, and sends few home.
	_content(person)
	_feel(15.0, config.pull_by_weather[&"rain"], Exposure.RAIN)
	assert_near(Brain.decide(person, ctx).plain[&"work"], fine[1] * (1.0 - config.work_cut * config.pull_by_weather[&"rain"]), 0.001)


func test_heat_slows_work() -> void:
	_go_to(days + 3, 14.0)
	var person := _grown_up()
	var work := WorkStep.new()
	var step := WorkStep.make(&"play", 0, person.position, 600.0)
	_feel(20.0)
	work.update(ctx, person, step, 10.0)
	assert_near(step["elapsed"], 10.0, 0.001)
	_feel(config.heat_from + config.heat_span)
	work.update(ctx, person, step, 10.0)
	assert_near(step["elapsed"], 10.0 + 10.0 * (1.0 - config.heat_slow), 0.001, "less gets done in the same time")
	# (A stroke of work comes later for it.)
	var cool := WorkStep.make(&"play", 0, person.position, 600.0)
	var hot := WorkStep.make(&"play", 0, person.position, 600.0)
	_feel(20.0)
	for n in 30:
		work.update(ctx, person, cool, 1.0)
	_feel(40.0)
	for n in 30:
		work.update(ctx, person, hot, 1.0)
	assert_true(int(hot["strokes"]) < int(cool["strokes"]), "%d against %d strokes" % [hot["strokes"], cool["strokes"]])


func test_the_cold_gets_into_people() -> void:
	_go_to(days * 3 + 3, 13.0)
	var person := _grown_up()
	var fire := settlement.fire()
	assert_true(settlement.fire_lit())
	session.people.move(person.id, fire.tile + Vector2i(9, 0))
	var bitter := config.deep_cold - 2.0
	# Who is warm: indoors, or by the burning fire — but not indoors in a deep cold with the fire out.
	assert_false(Exposure.is_warm(person, ctx, bitter))
	person.set_flag(PersonData.FLAG_INDOORS, true)
	assert_true(Exposure.is_warm(person, ctx, bitter))
	fire.stock = 0
	assert_false(Exposure.is_warm(person, ctx, bitter), "a cold hut is no shelter from that")
	assert_true(Exposure.is_warm(person, ctx, config.deep_cold + 1.0))
	fire.stock = -1
	person.set_flag(PersonData.FLAG_INDOORS, false)
	session.people.move(person.id, fire.tile + Vector2i(1, 1))
	assert_true(Exposure.is_warm(person, ctx, bitter), "by the fire")
	session.people.move(person.id, fire.tile + Vector2i(9, 0))
	# A chilly day is nothing.
	_feel(config.cold_from + 2.0)
	Exposure.live(person, ctx, 600.0)
	assert_true(Hardship.condition_of(person, Exposure.COLD).is_empty())
	# Out in a bitter cold: it gets into them, and after long enough they are ill.
	var well := person.health
	_feel(bitter)
	Exposure.live(person, ctx, config.cold_sick_after_minutes * 0.5)
	assert_false(Exposure.is_sick(person))
	assert_false(Hardship.condition_of(person, Exposure.COLD).is_empty())
	assert_eq(ctx.ailments.size(), 0)
	Exposure.live(person, ctx, config.cold_sick_after_minutes * 0.5)
	assert_true(Exposure.is_sick(person))
	assert_eq(ctx.ailments, [[person.id, Exposure.COLD, true]])
	assert_near(person.health, well, 0.0001)
	Exposure.live(person, ctx, 720.0)
	assert_true(person.health < well - 0.05, "%.2f" % person.health)
	Exposure.live(person, ctx, 20.0 * DAY)
	assert_near(person.health, minf(Config.needs.sick_health_floor, well), 0.001, "not below the floor")
	# In the warmth it goes out of them, and they get well.
	person.set_flag(PersonData.FLAG_INDOORS, true)
	Exposure.live(person, ctx, 30.0)
	assert_true(Exposure.is_sick(person), "not at once")
	Exposure.live(person, ctx, config.cold_sick_after_minutes)
	assert_false(Exposure.is_sick(person), "warm again: getting well")
	assert_eq(ctx.ailments[-1], [person.id, Exposure.COLD, false])
	Exposure.live(person, ctx, 10.0 * DAY)
	assert_near(person.health, well, 0.001)
	assert_true(Hardship.condition_of(person, Exposure.COLD).is_empty(), "and then it is over")
	person.set_flag(PersonData.FLAG_INDOORS, false)
	ctx.ailments.clear()
	# A short chill passes without illness.
	_feel(bitter)
	Exposure.live(person, ctx, 60.0)
	_feel(5.0)
	Exposure.live(person, ctx, 60.0)
	assert_true(Hardship.condition_of(person, Exposure.COLD).is_empty())
	assert_eq(ctx.ailments.size(), 0)
	# It is written down, with its cause: the bitter cold, or the fire gone out.
	var events := session.events
	weather.condition_changed.emit(WeatherSystem.COLD_SNAP, true)
	session.chronicle.on_fell_ill(person.id, Exposure.COLD)
	var ill := events.latest(Chronicler.TYPE_COLD_SICK)
	assert_not_null(ill)
	assert_eq(Array(ill.causes), [session.chronicle.condition_id(WeatherSystem.COLD_SNAP)])
	assert_eq(EventText.text(ill, session.people, events), "%s has fallen ill in the bitter cold" % person.given_name)
	session.chronicle.on_recovered(person.id, Exposure.COLD)
	var better := events.latest(Chronicler.TYPE_RECOVERED)
	assert_eq(Array(better.causes), [ill.id])
	assert_eq(EventText.text(better, session.people, events), "%s is well again" % person.given_name)
	weather.condition_changed.emit(WeatherSystem.COLD_SNAP, false)
	session.chronicle.on_fire_changed(false)
	clock.tick += 5
	session.chronicle.on_fell_ill(person.id, Exposure.COLD)
	assert_eq(EventText.text(events.latest(Chronicler.TYPE_COLD_SICK), session.people, events),
		"%s has fallen ill in the cold, with the fire out" % person.given_name)
	# And the running game does it: a bitter night out of doors, far from the fire.
	assert_true(session.behavior.has_signal("fell_ill"))
	assert_eq(UIText.ILL_WITH_COLD, "Ill with the cold")


func test_the_fire_burns_more_in_the_cold() -> void:
	_knob(Config.settlement, &"winter_wood_factor", 1.0)
	_knob(Config.settlement, &"winter_food_factor", 1.0)
	_knob(Config.climate, &"air_mass_degrees", 0.0)
	var stock := settlement.stockpile
	# A summer's day and a winter's night: how much more the fire wants.
	_go_to(days + 3, 14.0)
	assert_near(settlement.cold_factor(clock.tick), 1.0, 0.001)
	stock.take(&"wood", 10000)
	settlement.jobs.refresh(settlement, clock.tick)
	var wanted_warm := settlement.jobs.job_for(&"wood").wanted
	_go_to(days * 3 + 3, 4.0)
	var cold := settlement.cold_factor(clock.tick)
	assert_true(cold > 1.2, "%.2f at %.1f degrees" % [cold, weather.temperature(clock.tick)])
	assert_near(cold, Exposure.fire_factor(weather.temperature(clock.tick)), 0.001)
	settlement.jobs.refresh(settlement, clock.tick)
	assert_near(settlement.jobs.job_for(&"wood").wanted, wanted_warm * cold, 0.2, "the woodcutters are asked for more")
	# And it does burn more: three winter days against three of summer.
	var burnt: Array = []
	for day: int in [days * 3 + 2, days * 5 + 2]:
		_go_to(day, 0.0)
		stock.add(&"wood", 5)
		settlement.step(clock.tick) # (the fire is lit, and the days jumped over are behind it)
		stock.take(&"wood", 10000)
		stock.add(&"wood", 60)
		var before := stock.amount(&"wood")
		for hour in 72:
			clock.tick += 60
			weather.advance_to(clock.tick)
			settlement.step(clock.tick)
		burnt.append(before - stock.amount(&"wood"))
		stock.take(&"wood", 10000)
	assert_true(burnt[0] > burnt[1], "%d logs in winter, %d in summer" % [burnt[0], burnt[1]])
	assert_near(burnt[1], Config.settlement.fire_wood_per_day * 3.0, 1.5, "three summer days: as ever")
	assert_near(burnt[0], burnt[1] * settlement.cold_factor(_midnight(days * 3 + 3) + 720), 4.0)


func test_a_flood_in_the_settlement() -> void:
	_go_to(days * 2 + 2, 11.0)
	var events := session.events
	var places := ctx.places
	var person := _grown_up()
	var stock := settlement.stockpile
	var moved: Array = []
	var took: Array = []
	settlement.home_moved.connect(func(hut_id: int, from: Vector2i, to: Vector2i) -> void: moved.append([hut_id, from, to]))
	settlement.flood_took.connect(func(resource: StringName, amount: int) -> void: took.append([resource, amount]))
	var home_before: Vector2i = places.home_tile(person)
	var huts := session.start.hut_ids.size()
	assert_true(huts >= 2)
	stock.add(&"wood", 40)
	stock.add(&"berries", 60)
	var crop := session.farming.sow(session.farming.next_plot(), clock.tick)
	crop.variant = Farming.Stage.GROWING
	crop.growth = 400
	settlement.step(clock.tick)
	assert_true(settlement.fire_lit())
	assert_eq(settlement.pending_moves(), 0)
	assert_null(places.refuge)
	# The river comes over its banks, into the huts.
	river.enabled = true
	river.level = 0.4
	river.step(clock.tick, 0.0)
	assert_true(river.flooded)
	var flood := events.latest(Chronicler.TYPE_FLOOD)
	assert_not_null(flood)
	assert_eq(session.perception.last.type, Stimulus.FLOOD, "everyone sees it")
	clock.tick += 60
	settlement.step(clock.tick)
	# The fire is out (and stays out), because of the flood.
	assert_false(settlement.fire_lit())
	var out := events.latest(Chronicler.TYPE_FIRE_OUT)
	assert_eq(Array(out.causes), [flood.id])
	assert_eq(EventText.text(out, session.people, events), "The flood has put the fire out")
	# How high the water stood is remembered, and which huts it stood in.
	assert_near(settlement.flood_level, river.surface(), 0.001)
	assert_eq(settlement.pending_moves(), huts)
	# Everyone flooded out has somewhere dry to go; they sleep there in the open.
	var refuge: Vector2i = places.refuge
	assert_near(world.get_water(refuge), 0.0, 0.0001)
	assert_true(world.get_height(refuge) > world.get_height(settlement.fire().tile))
	assert_eq(places.home_tile(person), refuge)
	session.people.move(person.id, refuge)
	var sleep := SleepStep.new()
	var asleep := SleepStep.make()
	sleep.begin(ctx, person, asleep)
	assert_false(person.has_flag(PersonData.FLAG_INDOORS), "no roof over them")
	sleep.end(ctx, person, asleep)
	# The crop on the flooded plot has drowned.
	assert_eq(Farming.stage_of(crop), Farming.Stage.FAILED)
	var drowned := events.latest(Chronicler.TYPE_CROP_FAILURE)
	assert_eq(Array(drowned.causes), [flood.id])
	assert_eq(EventText.text(drowned, session.people, events), "A crop has drowned in the flood")
	# Hour by hour the water takes of what lies in store: one event for the flood.
	var food := stock.food_units()
	var wood := stock.amount(&"wood")
	for hour in 8:
		clock.tick += 60
		settlement.step(clock.tick)
	assert_true(stock.food_units() < food, "%d -> %d" % [food, stock.food_units()])
	assert_true(stock.food_units() > food / 3, "not all at once")
	assert_true(stock.amount(&"wood") < wood)
	assert_false(took.is_empty())
	assert_eq(events.count_of(Chronicler.TYPE_STORES_FLOODED), 1)
	var spoiled := events.latest(Chronicler.TYPE_STORES_FLOODED)
	assert_eq(Array(spoiled.causes), [flood.id])
	assert_true(int(spoiled.effects["lost"]) >= food - stock.food_units())
	assert_eq(EventText.text(spoiled, session.people, events), "The flood has got into the stores")
	assert_true(session.chronicle.shortage_causes().has(spoiled.id) and session.chronicle.shortage_causes().has(drowned.id),
		"what a shortage now would be put down to")
	# Nothing is rebuilt while the water stands.
	assert_eq(moved, [])
	# It runs off: the fire is lit again, home is home again.
	river.level = 0.0
	river.step(clock.tick, 0.0)
	assert_false(river.flooded)
	clock.tick += 60
	settlement.step(clock.tick)
	assert_null(places.refuge)
	assert_true(settlement.fire_lit())
	assert_eq(places.home_tile(person), home_before)
	# Without wood for it nothing is rebuilt — and the woodcutters are asked for it.
	clock.tick = _midnight(days * 2 + 4) + 10 * 60
	weather.advance_to(clock.tick)
	stock.take(&"wood", 10000)
	stock.add(&"wood", 2)
	settlement.step(clock.tick)
	assert_eq(moved, [])
	assert_true(settlement.jobs.job_for(&"wood").wanted >= huts * config.move_wood)
	# With wood: a hut a day is rebuilt on ground the water never reached.
	stock.add(&"wood", 60)
	wood = stock.amount(&"wood")
	clock.tick += Config.settlement.job_check_minutes
	settlement.step(clock.tick)
	assert_eq(moved.size(), 1)
	var first: Array = moved[0]
	var hut := session.props.get_prop(first[0])
	assert_eq(hut.tile, first[2])
	assert_ne(first[1], first[2])
	assert_true(world.get_height(hut.tile) * world.height_step > settlement.flood_level, "above the highest water it has seen")
	assert_true(Vector2(hut.tile).distance_to(Vector2(settlement.fire().tile)) <= config.move_radius)
	assert_null(session.props.prop_at(first[1]), "nothing stands where it stood")
	assert_true(stock.amount(&"wood") <= wood - config.move_wood)
	assert_eq(settlement.pending_moves(), huts - 1)
	session.pathfinder.refresh_dirty()
	assert_true(session.pathfinder.is_reachable(settlement.fire().tile + Vector2i(1, 0), hut.tile + Vector2i(0, 1))
		or session.pathfinder.is_reachable(settlement.fire().tile + Vector2i(1, 0), hut.tile + Vector2i(1, 0))
		or session.pathfinder.is_reachable(settlement.fire().tile + Vector2i(1, 0), hut.tile + Vector2i(-1, 0))
		or session.pathfinder.is_reachable(settlement.fire().tile + Vector2i(1, 0), hut.tile + Vector2i(0, -1)), "it can be walked to")
	for member in settlement.members():
		if member.home_building_id == hut.id:
			assert_eq(places.home_tile(member), hut.tile, "whoever lives in it lives there now")
	var rebuilt := events.latest(Chronicler.TYPE_HOME_MOVED)
	assert_not_null(rebuilt)
	assert_eq(Array(rebuilt.causes), [flood.id])
	assert_eq(EventText.text(rebuilt, session.people, events), "After the flood a hut has been rebuilt on higher ground")
	assert_true(events.led_to(flood.id, rebuilt.id))
	# Not a second one the same day.
	clock.tick += Config.settlement.job_check_minutes
	settlement.step(clock.tick)
	assert_eq(moved.size(), 1)
	# It is kept in a save.
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_near(again.settlement.flood_level, settlement.flood_level, 0.0001)
	assert_eq(again.settlement.pending_moves(), huts - 1)
	assert_eq(again.props.get_prop(first[0]).tile, first[2])
	again.queue_free()
	# Day by day the others follow.
	for day in huts + 1:
		clock.tick = _midnight(days * 2 + 5 + day) + 10 * 60
		weather.advance_to(clock.tick)
		stock.add(&"wood", 30)
		settlement.step(clock.tick)
	assert_eq(moved.size(), huts)
	assert_eq(settlement.pending_moves(), 0)
	var sites := {}
	for move: Array in moved:
		assert_true(world.get_height(move[2]) * world.height_step > settlement.flood_level)
		sites[move[2]] = true
	assert_eq(sites.size(), huts, "each on a site of its own")
	# The next flood does not reach them.
	river.level = 0.4
	river.step(clock.tick, 0.0)
	clock.tick += 60
	settlement.step(clock.tick)
	assert_eq(settlement.pending_moves(), 0)
	assert_eq(places.home_tile(person), session.props.get_prop(person.home_building_id).tile, "home is dry")
	assert_false(settlement.is_under_water(places.home_tile(person)))


func test_what_nature_does_is_noticed() -> void:
	_go_to(days + 2, 12.0)
	var perception := session.perception
	var before := perception.emitted
	# A storm breaks: everyone about hears it — nothing uncanny in it.
	weather.hold(&"storm", clock.tick + 1000 * DAY)
	assert_eq(perception.emitted, before + 1)
	var storm := perception.last
	assert_eq(storm.type, Stimulus.THUNDERSTORM)
	assert_eq(storm.origin, Stimulus.Origin.NATURE)
	assert_false(storm.anomalous)
	assert_true(storm.large and storm.weatherlike)
	assert_near(storm.radius, config.natural_radius, 0.001)
	assert_true(storm.position.distance_to(settlement.fire().position2d()) < 0.01)
	# The rain comes back after a drought.
	weather.condition_changed.emit(WeatherSystem.DROUGHT, true)
	assert_eq(perception.emitted, before + 1)
	weather.condition_changed.emit(WeatherSystem.DROUGHT, false)
	assert_eq(perception.last.type, Stimulus.RAIN_RETURNED)
	# Ordinary rain is not announced to everyone every time.
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	weather.hold(&"rain", clock.tick + 1000 * DAY)
	assert_eq(perception.emitted, before + 2)
	# Each has its words.
	for type: StringName in [Stimulus.THUNDERSTORM, Stimulus.RAIN_RETURNED, Stimulus.FLOOD]:
		assert_true(Stimulus.TYPES.has(type))
		assert_true(Config.reactions.stimuli.has(type))
		for prefix: String in ["DAY_AT_", "MEM_", "MEMWHAT_"]:
			var key := prefix + String(type).to_upper()
			assert_ne(TranslationServer.translate(key), StringName(key), key)
	# People make of it what they will: to most a storm is the weather — to
	# someone who already believes, it may well be the hand they believe in.
	var table := Config.reactions
	var plain := _grown_up()
	plain.beliefs = PackedFloat32Array()
	var circumstances := Interpretation.features(plain, storm, false, 5, ctx, table)
	var of_plain := Interpretation.scores(plain, storm, circumstances, ctx, table)
	assert_true(float(of_plain[ReactionTable.NATURAL]) > float(of_plain[ReactionTable.DEITY]), str(of_plain))
	var believer: PersonData = null
	for other in session.people.all_people():
		if other.id != plain.id and ctx.stage_of(other) == PersonData.LifeStage.ADULT:
			believer = other
	assert_not_null(believer)
	var beliefs := Interpretation.beliefs_of(believer).duplicate()
	beliefs[ReactionTable.INTERPRETATIONS.find(ReactionTable.DEITY)] = 1.0
	believer.beliefs = beliefs
	believer.traits[Traits.Axis.SPIRITUALITY] = 1.0
	var of_believer := Interpretation.scores(believer, storm, Interpretation.features(believer, storm, false, 5, ctx, table), ctx, table)
	var lean_plain := float(of_plain[ReactionTable.DEITY]) - float(of_plain[ReactionTable.NATURAL])
	var lean_believer := float(of_believer[ReactionTable.DEITY]) - float(of_believer[ReactionTable.NATURAL])
	assert_true(lean_believer > lean_plain + 0.5, "%.2f against %.2f" % [lean_believer, lean_plain])
	var as_deity := 0
	for n in 200:
		if Interpretation.choose(believer, storm, Interpretation.features(believer, storm, false, 5, ctx, table), ctx, table).choice \
				== ReactionTable.DEITY:
			as_deity += 1
	assert_true(as_deity > 20, "the believer took %d of 200 storms for the deity's doing" % as_deity)


func test_a_drought_costs_a_harvest() -> void:
	# Drought, a low river, withered crops, hunger: each because of the one before.
	var events := session.events
	var farming := session.farming
	_knob(Config.climate, &"air_mass_degrees", 0.0)
	_go_to(4, 8.0)
	river.enabled = true
	river.level = 0.0
	var crops: Array[PropData] = []
	for n in 6:
		var crop := farming.sow(farming.next_plot(), clock.tick)
		if crop != null:
			crop.variant = Farming.Stage.GROWING
			crop.growth = 60
			crops.append(crop)
	assert_true(crops.size() >= 4)
	# (Two weeks without rain, from spring into the autumn of a six-day season.)
	var failed_on := -1
	for day in 13:
		for hour in 24:
			clock.tick += 60
			weather.advance_to(clock.tick)
			for crop in crops:
				crop.tended_tick = clock.tick
			farming.settle(clock.tick)
		for crop in crops:
			if Farming.stage_of(crop) == Farming.Stage.FAILED:
				failed_on = day
		if failed_on >= 0:
			break
	assert_true(failed_on >= 7, "a crop withers, but not in a week without rain (day %d)" % failed_on)
	assert_true(weather.has_condition(WeatherSystem.DROUGHT))
	assert_true(river.low_water, "%.2f" % river.level)
	assert_true(Config.time.season_of(clock.tick) != Seasons.WINTER and not weather.is_frozen(), "(no frost had a hand in it)")
	var drought := events.latest(Chronicler.TYPE_DROUGHT)
	var low := events.latest(Chronicler.TYPE_LOW_WATER)
	var withered := events.latest(Chronicler.TYPE_CROP_FAILURE)
	assert_not_null(drought)
	assert_not_null(low)
	assert_not_null(withered)
	assert_true(Array(withered.causes).has(drought.id), "the withered crop is put down to the drought")
	assert_true(Array(withered.causes).has(low.id) or Array(withered.causes).size() >= 2)
	assert_true(events.led_to(drought.id, withered.id))
	# The stores run out: the shortage is put down to the lost harvest.
	settlement.stockpile.take(&"berries", 10000)
	settlement.stockpile.take(&"grain", 10000)
	settlement.stockpile.take(&"meat", 10000)
	for hour in 8:
		clock.tick += 60
		settlement.step(clock.tick)
	assert_true(settlement.is_short())
	var shortage := events.latest(Chronicler.TYPE_SHORTAGE)
	assert_not_null(shortage)
	assert_true(Array(shortage.causes).has(withered.id))
	assert_true(events.led_to(drought.id, shortage.id), "drought, withered crops, hunger")
	assert_eq(EventText.text(shortage, session.people, events), "Food is running short after the failed crop")


func test_version_18_save_has_seen_no_flood() -> void:
	var dir := SaveManager.world_dir(V18_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V18_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 18)
	var loaded := SaveManager.load_world(V18_ID)
	assert_true(loaded.ok, loaded.error)
	var saved: Dictionary = loaded.world["world_state"]["settlement"]
	assert_eq([saved["flood_level"], saved["moves"]], [0.0, []])
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_near(s.settlement.flood_level, 0.0, 0.0001)
	assert_eq(s.settlement.pending_moves(), 0)
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 19)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 18)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v18_to_v19({"world": {"world_state": {}}})["world"]["world_state"], {})
	assert_eq(SaveMigrations._v18_to_v19({"world": {"world_state": {"settlement": {}}}})["world"]["world_state"]["settlement"], {})
	var kept: Dictionary = SaveMigrations._v18_to_v19({"world": {"world_state": {"settlement": {"day": 3, "flood_level": 1.3}}}})
	assert_eq(kept["world"]["world_state"]["settlement"], {"day": 3, "flood_level": 1.3, "moves": []})
	# Nonsense in a save does no harm.
	settlement.from_dict({"flood_level": "high", "moves": [1, "two", 99999]})
	assert_near(settlement.flood_level, 0.0, 0.0001)
	assert_eq(settlement.pending_moves(), 0)
