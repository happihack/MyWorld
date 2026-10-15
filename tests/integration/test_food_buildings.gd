extends TestCase
## Buildings & villagers W1: food that keeps. A smokehouse once meat or fish
## comes in, worked by a cook (the first recipe: meat or fish and a little
## wood → smoked food that keeps a year), on screen and in the time away; a
## seed store that keeps the seed from floods and from being eaten at the
## first empty day; a granary built in place of a storehouse, holding more
## and keeping it longer.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var own: Settlement
var planner: SettlementPlanner


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	own = session.settlement
	planner = own.planner


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _grow_to(people: int) -> void:
	while own.member_count() < people:
		var p := session.spawn_person(own.fire().tile + Vector2i(1, 1))
		p.birth_tick = session.clock.tick - 25 * Config.time.ticks_per_year()


func _build(def_id: StringName) -> PropData:
	var def := session.buildings.get_def(def_id)
	var tile: Variant = planner.site_for(def)
	assert_not_null(tile, "room for a %s" % def_id)
	var p := session.construction.start(def_id, tile, session.clock.tick)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	return session.props.prop_at(tile)


func test_the_smokehouse_and_its_cook() -> void:
	_grow_to(10)
	assert_false(planner.food_building_wanted(&"smokehouse"), "nothing to smoke yet")
	own.note_produced(&"fish", 30)
	assert_true(planner.food_building_wanted(&"smokehouse"), "fish coming in")
	assert_true(planner.needs(session.clock.tick).has(&"smokehouse"))
	var house := _build(&"smokehouse")
	assert_eq(house.kind, PropData.Kind.SMOKEHOUSE)
	assert_eq(UIText.prop_name(PropData.Kind.SMOKEHOUSE), "Smokehouse")
	assert_false(planner.food_building_wanted(&"smokehouse"), "one is enough")
	# Something to smoke: a cook is wanted, and taken up.
	own.stockpile.add(&"fish", 12)
	own.stockpile.add(&"wood", 10)
	var cook_def := session.occupations.get_def(&"cook")
	assert_eq(own.demand_of(cook_def, session.clock.tick)["wanted"], 1)
	var cook := own._staff(cook_def, session.clock.tick)
	assert_not_null(cook, "someone takes up cooking")
	assert_eq(cook.occupation_id, &"cook")
	# The cook's day: to the smokehouse, and a batch smoked.
	var ctx := session.behavior.ctx
	ctx.enter(cook)
	own.jobs.refresh(own, session.clock.tick)
	assert_has(own.jobs.debug_text(), "tools", "the smokehouse's work posted (a craft job)")
	assert_true(own.recipe_wanted())
	var steps := Planner._recipe_work(cook, cook_def, ctx)
	assert_eq(steps.size(), 2, str(steps))
	assert_eq(str(steps[1].get("recipe", "")), "smokehouse")
	var fish := own.stockpile.amount(&"fish")
	var smoked := own.stockpile.amount(&"preserved_food")
	assert_true(Recipes.make(own, session.buildings.get_def(&"smokehouse"), int(steps[1]["step"])))
	assert_eq(own.stockpile.amount(&"fish"), fish - 3)
	assert_eq(own.stockpile.amount(&"preserved_food"), smoked + 3, "smoked food")
	assert_true(session.resources.get_def(&"preserved_food").spoil_days >= 20.0, "that keeps")
	# Away: the cook smokes what there is.
	var away := OfflineSimulator.new(session)
	away._recipes(own, cook_def, 1.0)
	assert_true(own.stockpile.amount(&"preserved_food") > smoked + 3, "smoked in the time away too")
	# Nothing to smoke: no work.
	own.stockpile.take(&"fish", own.stockpile.amount(&"fish"))
	assert_eq(Recipes.work_for(own, cook_def, session.buildings), [])


func test_the_seed_store_keeps_the_seed() -> void:
	_grow_to(10)
	own.learn(&"agriculture", 0, session.clock.tick)
	assert_false(own.has_seed_store())
	_build(&"seed_store")
	assert_true(own.has_seed_store())
	# The stores empty: the seed is not eaten at once …
	for resource: StringName in own.stockpile.amounts().keys():
		own.stockpile.take(resource, own.stockpile.amount(resource))
	own.stockpile.add(&"grain", 6)
	own.stockpile.set_reserve(&"grain", 6)
	own._set_shortage(Settlement.Shortage.EMPTY)
	assert_false(own.seed_eaten, "kept in the seed store")
	# … only once the stores have been empty a long while.
	session.clock.tick += 5 * DAY
	own._empty_since = session.clock.tick - Settlement.SEED_STORE_HOLDS_MINUTES - 1
	own._check_shortage(session.clock.tick)
	assert_true(own.seed_eaten, "eaten at last")


func test_the_granary_is_built_in_place_of_a_storehouse() -> void:
	_grow_to(16)
	own.learn(&"agriculture", 0, session.clock.tick)
	var store := _build(&"storehouse")
	session._apply_storehouses()
	var room_before := own.stockpile.extra_room
	assert_false(planner.food_building_wanted(&"granary"), "no farmers yet")
	var made := 0
	for person in own.members():
		if made < 2 and person.occupation_id != &"child":
			person.occupation_id = &"farmer"
			made += 1
	assert_true(planner.food_building_wanted(&"granary"))
	var p := planner._upgrade(session.buildings.get_def(&"granary"), session.clock.tick)
	assert_false(p.is_empty(), "begun on the storehouse")
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	var granary := session.props.get_prop(store.id)
	assert_eq(granary.kind, PropData.Kind.GRANARY, "the storehouse is a granary now")
	assert_true(own.stockpile.extra_room > room_before, "holding more (%d, was %d)" % [own.stockpile.extra_room, room_before])
	assert_eq(own.places().storehouse(), granary, "and the food is kept there")
	assert_false(planner.food_building_wanted(&"granary"), "one is enough")
	assert_true(CivilizationPhase.holds(CivilizationPhase.Phase.SETTLEMENT, session.settlements, session.props), "still a settlement with its stores")


func test_a_cook_makes_the_meals_go_further() -> void:
	var ctx := session.behavior.ctx
	ctx.enter(own.members()[0])
	for resource: StringName in own.stockpile.amounts().keys():
		own.stockpile.take(resource, own.stockpile.amount(resource))
	own.stockpile.add(&"grain", 10)
	var grain := session.resources.get_def(&"grain").nutrition
	assert_false(own.has_cook())
	assert_near(EatStep.serve(ctx, {"meal": true}), grain, 0.0001, "a meal: the grain's worth")
	own.members()[1].occupation_id = &"cook"
	assert_true(own.has_cook())
	assert_near(EatStep.serve(ctx, {"meal": true}), grain * Settlement.COOKED, 0.0001, "cooked: further")
	assert_near(EatStep.serve(ctx, {}), grain, 0.0001, "a bite between meals: as it is")
