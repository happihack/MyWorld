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


## A specialist is taken up only once the call for it has lasted (F2 step 2):
## not at once, but a day on.
func _staff_after_a_day(def: OccupationDef) -> PersonData:
	assert_null(own._staff(def, session.clock.tick), "not for a passing need")
	session.clock.tick += Settlement.SPLIT_DAYS * DAY
	return own._staff(def, session.clock.tick)


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
	var cook := _staff_after_a_day(cook_def)
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
	var cook := _staff_after_a_day(cook_def)
	assert_not_null(cook, "a spare builder takes up cooking")
	assert_eq(cook.occupation_id, &"cook")
	assert_eq(own._holding(&"builder"), builders - 1)
	assert_null(own._staff(cook_def, session.clock.tick), "one cook is enough")


func test_a_cook_with_no_call_goes_back_to_foraging() -> void:
	# F2 step 2: a specialist split off its family by demand, merged back when
	# there has been no call for it for a season — both told.
	_grow_to(10)
	own.note_produced(&"fish", 30)
	_build(&"smokehouse")
	own.stockpile.add(&"fish", 12)
	own.stockpile.add(&"wood", 10)
	var cook_def := session.occupations.get_def(&"cook")
	assert_eq(cook_def.merges_into, &"forager")
	var cook := _staff_after_a_day(cook_def)
	assert_not_null(cook)
	assert_eq(session.events.count_of(&"trade_split"), 1, "the first cook: a trade of its own")
	assert_has(EventText.text(session.events.latest(&"trade_split"), session.people, session.events), "cook")
	# No more meat or fish coming in: no call for a cook.
	own.produced.clear()
	assert_eq(int(own.demand_of(cook_def, session.clock.tick)["wanted"]), 0)
	own._merge_back(cook_def, session.clock.tick)
	assert_eq(cook.occupation_id, &"cook", "not at once")
	# (Kept across a save: how long it has gone without a call.)
	var saved := own.to_dict()
	assert_true((saved["idle_since"] as Dictionary).has("cook"))
	own.from_dict(saved)
	session.clock.tick += (Settlement.MERGE_DAYS - 1) * DAY
	own._merge_back(cook_def, session.clock.tick)
	assert_eq(cook.occupation_id, &"cook", "nor in a few days")
	session.clock.tick += DAY
	own._merge_back(cook_def, session.clock.tick)
	assert_eq(cook.occupation_id, &"forager", "a season without a call: back to foraging")
	assert_eq(session.events.count_of(&"trade_merged"), 1)
	var told := EventText.text(session.events.latest(&"trade_merged"), session.people, session.events)
	assert_has(told, "forager")
	assert_has(told, "cook")
	# Trades with nowhere to go back to keep their people.
	assert_eq(session.occupations.get_def(&"farmer").merges_into, &"")


func test_a_world_saved_before_the_foundation_loads() -> void:
	# F7: version 28, written before careers, building records and staffing's
	# memory: it loads, with those empty, and is saved as the current version.
	var fixture := "res://tests/fixtures/saves/v28_world.sav"
	var header := SaveContainer.read_header(fixture)
	assert_eq(int(header.header["save_version"]), 28)
	var world_id := str(header.header.get("world_id", ""))
	DirAccess.make_dir_recursive_absolute(SaveManager.world_dir(world_id))
	var copy := FileAccess.open(SaveManager.world_dir(world_id).path_join(SaveManager.SAVE_FILE), FileAccess.WRITE)
	copy.store_buffer(FileAccess.get_file_as_bytes(fixture))
	copy.close()
	var loaded := SaveManager.load_world(world_id)
	assert_true(loaded.ok, loaded.error)
	var old: WorldSession = SessionScript.new()
	add_child(old)
	assert_true(old.load_from(loaded.world))
	old.set_process(false)
	for person in old.people.all_people():
		assert_eq(person.mentor_id, 0, "nobody's apprentice")
		assert_true(old.occupations.has_def(person.occupation_id), "%s: a trade that still is" % person.occupation_id)
	assert_eq(old.settlement._idle_since, {})
	assert_eq(old.settlement._wanted_since, {})
	assert_eq(SaveManager.SAVE_VERSION, 29)
	assert_true(SaveManager.save_world(old, &"test"))
	assert_eq(int(SaveContainer.read_header(SaveManager.world_dir(world_id).path_join(SaveManager.SAVE_FILE)).header["save_version"]), 29)
	old.queue_free()
	await wait_frames(1)


func test_food_is_laid_in_for_the_winter() -> void:
	# (The owner, 2026-10-15: two days' food, doubled as winter came, went into
	# a winter of six, and every winter ended in rationing.)
	_grow_to(10)
	own.produced.clear()
	var need := own.food_need_per_day()
	var year := Config.time.ticks_per_year()
	var winter_days := Config.time.days_per_season
	var start := (session.clock.tick / year + 1) * year # (the start of a year: spring)
	assert_eq(own.winter_food_wanted(start), 0.0, "in spring, nothing laid in")
	var winter_from := start + (Config.time.seasons_per_year - 1) * winter_days * DAY
	var eve := winter_from - DAY
	var wanted := own.winter_food_wanted(eve)
	assert_true(wanted >= need * (winter_days + 1), "on its eve: all of the winter (%.1f days)" % (wanted / need))
	# What still comes in counts — but not in the winter, when nothing grows.
	own.produced["berries"] = need * 2.0 / 0.65 / (1.0 - Config.trade.produced_kept_per_day)
	# (A day of gathering before it, and the first days of spring after it.)
	assert_near(own.winter_food_wanted(eve), wanted - own.food_coming_in_per_day() * (1 + Settlement.SPRING_GAP_DAYS), 0.01,
		"the days of gathering around it: a little less")
	assert_true(own.winter_food_wanted(eve) > need * winter_days * 0.6)
	own.produced.clear()
	# And it is to last into the spring, before anything is ripe (the r7 round:
	# spring was the leanest time of all).
	var last_day := winter_from + (winter_days - 1) * DAY
	assert_true(own.winter_food_wanted(last_day) >= need * (1 + Settlement.SPRING_GAP_DAYS),
		"on winter's last day: the first days of spring too")
	# The job board asks for it: with five days of food, more is wanted on winter's eve.
	for resource in [&"berries", &"fish", &"meat", &"mushrooms", &"roots", &"nuts", &"fruit", &"preserved_food"]:
		own.stockpile.take(resource, own.stockpile.amount(resource))
	own.stockpile.set_reserve(&"grain", 0)
	own.stockpile.take(&"grain", own.stockpile.amount(&"grain"))
	own.stockpile.add(&"grain", ceili(need * 5.0))
	own.jobs.refresh(own, start)
	assert_false(own.jobs.wants(&"berries"), "five days in spring: enough")
	own.jobs.refresh(own, eve)
	assert_true(own.jobs.wants(&"berries"), "five days on winter's eve: not enough")


func test_bare_bushes_bring_a_farmer() -> void:
	# (The owner, 2026-10-16: a village known for berries never farmed, and
	# picked its bushes bare.)
	_grow_to(10)
	for person in own.members():
		if person.occupation_id == &"farmer":
			person.occupation_id = &"forager"
	for resource in [&"berries", &"grain", &"fish", &"meat"]:
		own.stockpile.add(resource, 200)
	var farmer_def := session.occupations.get_def(&"farmer")
	var year := Config.time.ticks_per_year()
	var winter := (session.clock.tick / year + 1) * year + (Config.time.seasons_per_year - 1) * Config.time.days_per_season * DAY + DAY
	assert_false(own.is_short())
	assert_false(session.farming.sowing_time(winter))
	own.forage_low = false
	assert_eq(int(own.demand_of(farmer_def, winter)["wanted"]), 0, "no farmer until the sowing")
	assert_eq(own.farmers_wanted(), 1)
	own.forage_low = true
	assert_eq(int(own.demand_of(farmer_def, winter)["wanted"]), 2, "the bushes bare: one more, and at once")
	assert_eq(own.farmers_wanted(), 2)
	own.forage_low = false


func test_berries_are_dried_for_the_winter() -> void:
	_grow_to(10)
	own.note_produced(&"fish", 30)
	_build(&"smokehouse")
	assert_false(planner.food_building_wanted(&"drying_rack"), "a smokehouse, and no berries to speak of")
	own.note_produced(&"berries", SettlementPlanner.DRY_FROM)
	assert_true(planner.food_building_wanted(&"drying_rack"), "berries enough to dry: a drying rack beside it")
	var rack := session.buildings.get_def(&"drying_rack")
	_build(&"drying_rack")
	for resource in [&"fish", &"meat"]:
		own.stockpile.take(resource, own.stockpile.amount(resource))
	own.stockpile.add(&"berries", 10)
	var step := Recipes.next_step(own, rack)
	assert_eq(rack.recipe[step]["in"].keys(), [&"berries"])
	var smoked := own.stockpile.amount(&"preserved_food")
	var berries := own.stockpile.amount(&"berries")
	assert_true(Recipes.make(own, rack, step))
	assert_eq(own.stockpile.amount(&"preserved_food"), smoked + 1, "two berries dried: food that keeps")
	assert_eq(own.stockpile.amount(&"berries"), berries - 2)
	# (Dried while there are fewer than its keep in store.)
	own.stockpile.add(&"preserved_food", int(rack.recipe[step]["keep"]))
	assert_eq(Recipes.next_step(own, rack), -1, "enough dried: the berries are eaten fresh")
	# A cook for it.
	assert_eq(int(own.demand_of(session.occupations.get_def(&"cook"), session.clock.tick)["wanted"]), 1)
