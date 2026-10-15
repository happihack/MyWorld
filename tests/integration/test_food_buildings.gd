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


func test_a_drying_rack_in_a_camp() -> void:
	_grow_to(5)
	own.note_produced(&"fish", 12)
	assert_true(planner.food_building_wanted(&"drying_rack"), "a camp with fish coming in, no smokehouse")
	var rack := _build(&"drying_rack")
	assert_eq(rack.kind, PropData.Kind.DRYING_RACK)
	own.stockpile.add(&"fish", 4)
	var def := session.buildings.get_def(&"drying_rack")
	var step := Recipes.next_step(own, def)
	assert_eq(step, 0, "fish to dry, and no wood wanted")
	assert_true(Recipes.make(own, def, step))
	assert_eq(own.stockpile.amount(&"preserved_food"), 2)
	assert_true(session.occupations.get_def(&"cook").workplaces.has("drying_rack"), "the cook works it too")


func test_an_orchard_bears_after_years_and_is_picked() -> void:
	_grow_to(13)
	own.learn(&"agriculture", 0, session.clock.tick)
	var orchard := _build(&"orchard")
	assert_eq(orchard.kind, PropData.Kind.ORCHARD)
	var day := Config.time.day_index(session.clock.tick) + 1
	own._orchards(day)
	assert_eq(orchard.variant, 0, "young")
	assert_eq(orchard.stock, 0, "no fruit yet")
	# Years later, in summer: fruit.
	var later := day + Settlement.ORCHARD_YEARS * Config.time.days_per_year() + Config.time.days_per_season
	for d in 3:
		own._orchards(later + d)
	assert_true(orchard.stock > 0, "fruit ripe (%d)" % orchard.stock)
	assert_eq(orchard.variant, 2, "bearing")
	# A forager picks it first, and it goes to the stores.
	var forager := own.members()[0]
	forager.carrying_amount = 0
	var ctx := session.behavior.ctx
	ctx.enter(forager)
	var steps := Planner._orchard_work(forager, ctx)
	assert_eq(steps.size(), 4, str(steps))
	assert_eq(str(steps[1].get("resource", "")), "fruit")
	# Away: picked into the stores.
	var away := OfflineSimulator.new(session)
	var before := own.stockpile.amount(&"fruit")
	away._work(own, 1.0, session.clock.tick)
	assert_true(own.stockpile.amount(&"fruit") > before, "picked in the time away")
	assert_eq(orchard.stock, 0)


func test_a_quarry_beside_the_rock() -> void:
	_grow_to(16)
	var site: Variant = planner.rock_site()
	if site == null:
		return # (no rocky ground near this fire: nothing to show)
	var beside := false
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		beside = beside or session.world.get_terrain(site + step) == ChunkData.Terrain.ROCK
	assert_true(beside, "beside rocky ground")
	own.stockpile.take(&"stone", own.stockpile.amount(&"stone"))
	assert_true(planner.food_building_wanted(&"quarry"), "short of stone")
	var p := session.construction.start(&"quarry", site, session.clock.tick)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	var def := session.buildings.get_def(&"quarry")
	var worker := session.occupations.get_def(&"quarry_worker")
	assert_eq(own.demand_of(worker, session.clock.tick)["wanted"], 1, "someone to work it")
	assert_true(Recipes.make(own, def, Recipes.next_step(own, def)))
	assert_eq(own.stockpile.amount(&"stone"), 2, "stone cut")
	own.stockpile.add(&"stone", 40)
	assert_eq(Recipes.next_step(own, def), -1, "enough in store: no more cut (keep)")


func test_herbs_heal_and_the_garden() -> void:
	_grow_to(21)
	own.learn(&"medicine", 0, session.clock.tick)
	session.technology.apply_effects()
	var rack := _build(&"herb_rack")
	var herbalist := session.occupations.get_def(&"herbalist")
	assert_eq(own.demand_of(herbalist, session.clock.tick)["wanted"], 1, "herbs to grow")
	var def := session.buildings.get_def(&"herb_rack")
	assert_true(Recipes.make(own, def, Recipes.next_step(own, def)))
	assert_eq(own.stockpile.amount(&"herbs"), 1)
	# The hurt are treated with them, and heal faster.
	var hurt := own.members()[0]
	Health.injure(hurt, Health.CUT, 0.3, session.clock.tick)
	var tended := Health.recovery(hurt)
	own._treat_with_herbs()
	assert_eq(own.stockpile.amount(&"herbs"), 0, "a bunch used")
	assert_true(Health.recovery(hurt) > tended, "faster with herbs (%.1f, was %.1f)" % [Health.recovery(hurt), tended])
	own._treat_with_herbs()
	assert_eq(Health.recovery(hurt), tended, "none left: as before")
	# The rack grown into a garden.
	assert_true(planner.food_building_wanted(&"herb_garden"))
	var p := planner._upgrade(session.buildings.get_def(&"herb_garden"), session.clock.tick)
	assert_false(p.is_empty())
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	assert_eq(session.props.get_prop(rack.id).kind, PropData.Kind.HERB_GARDEN)


func test_a_storehouse_looks_as_its_people_keep_food() -> void:
	session.construction.style_of = func(_settlement_id: int) -> int: return 1
	var store := _build(&"storehouse")
	assert_eq(store.variant, 1, "a root cellar, as this culture keeps its food")
	session.construction.style_of = func(_settlement_id: int) -> int: return 2
	var second := _build(&"storehouse")
	assert_eq(second.variant, 2, "a storage pit")


func test_a_village_of_farmers_spares_one_to_cook() -> void:
	_grow_to(10)
	own.note_produced(&"fish", 30)
	_build(&"smokehouse")
	own.stockpile.add(&"fish", 12)
	own.stockpile.add(&"wood", 10)
	# Nobody gathers (three are wanted to spare one): all builders, with nothing to build.
	for person in own.members():
		if person.occupation_id != &"child" and person.occupation_id != &"elder":
			person.occupation_id = &"builder"
	var builder_def := session.occupations.get_def(&"builder")
	var builders := own._holding(&"builder")
	assert_true(int(own.demand_of(builder_def, session.clock.tick)["wanted"]) < builders, "more builders than wanted")
	var cook_def := session.occupations.get_def(&"cook")
	var cook := own._staff(cook_def, session.clock.tick)
	assert_not_null(cook, "a spare builder takes up cooking")
	assert_eq(cook.occupation_id, &"cook")
	assert_eq(own._holding(&"builder"), builders - 1)
	assert_null(own._staff(cook_def, session.clock.tick), "one cook is enough")
