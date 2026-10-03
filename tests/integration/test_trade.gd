extends TestCase
## Trade & specialization (M12.4, bible §17.3): what a settlement brings in
## makes it known for something, and its young lean toward that trade; skill
## and tools make work go faster; traders carry surpluses to the settlement
## that lacks them and bring back what home lacks; toolmaking is worked out,
## a workshop built, tools made — and counted.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V26_FIXTURE := "res://tests/fixtures/saves/v26_world.sav"
const V26_ID := "w1791051332_6425f516"

var session: WorldSession
var trade: TradeSystem
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
	trade = session.trade
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"starve_chance_per_day", &"illness_death_per_day", &"injury_death_per_day", &"newcomer_chance_per_day"]:
		_knob(Config.life, knob, 0.0)


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


## A second settlement, founded by a group from the first (the walk skipped).
func _second() -> Settlement:
	var first := session.settlement
	var fire := first.fire().tile
	for dy in range(-28, 29, 2):
		for dx in range(-28, 29, 2):
			first.places().mark_visited(fire + Vector2i(dx, dy))
	while first.member_count() < 14:
		var a := session.spawn_person(fire + Vector2i(1, 1))
		var b := session.spawn_person(fire + Vector2i(1, 1))
		a.sex = PersonData.Sex.MALE
		b.sex = PersonData.Sex.FEMALE
		session.households.form_couple(a, b, session.clock.tick, session.ids.next_id())
	var journey := session.migration.depart(first, session.clock.tick)
	assert_false(journey.is_empty())
	return session.migration.found(journey, session.clock.tick)


## The world runs for `minutes` game minutes, as in the soak.
func _run(minutes: int) -> void:
	var minute := Config.time.real_seconds_per_game_minute
	var frame := Config.time.max_frame_delta_s
	for i in minutes:
		var seconds := minute
		while seconds > 0.000001:
			var piece := minf(seconds, frame)
			session.clock.advance(piece)
			seconds -= piece
		session.behavior.step(1.0)
		session.pathfinder.serve(1000000)
		session.movement.step(1.0)
		if session.nodes.due(session.clock.tick):
			session.nodes.settle(session.clock.tick)


func test_a_settlement_becomes_known_for_what_it_brings_in() -> void:
	var first := session.settlement
	assert_eq(first.specialty(), &"", "nothing yet")
	first.note_produced(&"wood", 60)
	first.note_produced(&"berries", 20)
	assert_eq(first.specialty(), &"wood")
	assert_eq(first.specialty_trade(), &"woodcutter")
	first.note_produced(&"berries", 60)
	assert_eq(first.specialty(), &"berries", "now berries are the greater part")
	# It fades, day by day.
	var before := float(first.produced["berries"])
	first._each_day(10)
	assert_near(float(first.produced["berries"]), before * Config.trade.produced_kept_per_day, 0.001)
	# The young lean toward it.
	var library := session.occupations
	var rng := RandomNumberGenerator.new()
	var plain := 0
	var leaning := 0
	for i in 400:
		rng.seed = i
		if library.choose(PersonData.LifeStage.ADULT, Traits.neutral(), rng) == &"forager":
			plain += 1
		rng.seed = i
		if library.choose(PersonData.LifeStage.ADULT, Traits.neutral(), rng, {}, &"forager", Config.trade.specialty_pull) == &"forager":
			leaning += 1
	assert_true(leaning > plain * 1.3, "more become foragers where foraging is what it does (%d against %d)" % [leaning, plain])
	# What its people bring in is counted.
	var person := first.members()[0]
	person.carrying = &"stone"
	person.carrying_amount = 3
	session.behavior.ctx.enter(person)
	session.behavior.ctx.put_down(person)
	assert_near(float(first.produced["stone"]), 3.0, 0.001)


func test_settlements_are_known_for_what_sets_them_apart() -> void:
	var own := _second()
	var first := session.settlement
	first.produced.clear()
	own.produced.clear()
	# Both bring in berries above all; the camp brings in far more wood.
	first.note_produced(&"berries", 70)
	first.note_produced(&"wood", 10)
	own.note_produced(&"berries", 50)
	own.note_produced(&"wood", 40)
	assert_eq(first.specialty(), &"berries", "berries set the first apart")
	assert_eq(own.specialty(), &"wood", "wood sets the camp apart")
	assert_eq(own.specialty_trade(), &"woodcutter")


func test_skill_and_tools_make_work_faster() -> void:
	var ctx := session.behavior.ctx
	var person := session.settlement.members()[0]
	ctx.enter(person)
	var tree: PropData = null
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and session.nodes.available(prop) > 6:
			tree = prop
			break
	assert_not_null(tree)
	var units_for := func(skill: float, tools: int) -> int:
		person.skills[String(person.occupation_id)] = skill
		person.carrying = &""
		person.carrying_amount = 0
		var stores := session.settlement.stockpile
		stores.take(&"tools", stores.amount(&"tools"))
		stores.add(&"tools", tools)
		session.settlement._refresh_tools()
		var step := WorkStep.make(&"tree", tree.id, tree.tile, 60.0)
		WorkStep.gather(ctx, person, step, tree, 5)
		return person.carrying_amount * 1000 + int(float(step["effort"]) * 10.0)
	var green: int = units_for.call(0.0, 0)
	var skilled: int = units_for.call(1.0, 0)
	var equipped: int = units_for.call(1.0, 20)
	assert_true(skilled > green, "the skilled get further (%d > %d)" % [skilled, green])
	assert_true(equipped > skilled, "with tools further still (%d > %d)" % [equipped, skilled])
	assert_true(session.settlement.tool_level() > 0.0)
	# Gathering makes one better at it.
	person.skills[String(person.occupation_id)] = 0.2
	person.carrying = &""
	person.carrying_amount = 0
	var step := WorkStep.make(&"tree", tree.id, tree.tile, 60.0)
	WorkStep.gather(ctx, person, step, tree, 40)
	assert_true(float(person.skills[String(person.occupation_id)]) > 0.2, "better at it")


func test_trade_moves_surplus() -> void:
	var own := _second()
	var first := session.settlement
	# The first has wood to spare; the new camp has none, and food enough.
	first.stockpile.add(&"wood", 40)
	own.stockpile.take(&"wood", own.stockpile.amount(&"wood"))
	own.stockpile.add(&"berries", 60)
	trade.plan_offers()
	var offer := trade.offer_for(first.id)
	assert_eq(str(offer.get("out", "")), "wood", "the first offers its wood: %s" % offer)
	assert_eq(int(offer["to"]), own.id)
	assert_true(int(offer["units"]) >= Config.trade.least_load)
	var wood_there := own.stockpile.amount(&"wood")
	var wood_here := first.stockpile.amount(&"wood")
	# Somebody takes up the trade, and carries it, on foot.
	var trader := first.ensure_trader(session.clock.tick)
	assert_not_null(trader, "a trader")
	assert_eq(trader.occupation_id, &"trader")
	var steps := Planner._trade_work(trader, _entered(trader))
	assert_false(steps.is_empty())
	var left := trade.offer_for(first.id)
	assert_true(left.is_empty() or int(left["units"]) < int(offer["units"]), "a load of it claimed; the rest for the next run")
	session.behavior.set_plan(trader, &"work", &"trade", steps)
	var minutes := 0
	while trade.trips == 0 and minutes < DAY:
		_run(10)
		minutes += 10
	assert_true(trade.trips >= 1, "delivered after %d minutes" % minutes)
	assert_true(own.stockpile.amount(&"wood") > wood_there, "the new camp has wood now")
	assert_true(first.stockpile.amount(&"wood") < wood_here)
	assert_eq(trade.balance_of(first.id)[0], "wood", "the first sends wood")
	assert_eq(trade.balance_of(own.id)[1], "wood", "the camp gets wood")
	var routes := session.events.of_type(&"trade_route")
	assert_eq(routes.size(), 1)
	assert_has(EventText.text(routes[0], session.people, session.events), "the first trade")
	assert_has(trade.debug_text(), "wood")
	# Nothing to trade with nobody to trade with.
	var lone := TradeSystem.new()
	lone.bind(session.clock.tick, Config.trade)
	assert_false(lone.has_offer(first.id))


func test_toolmaking_a_workshop_and_tools() -> void:
	var first := session.settlement
	_knob(Config.trade, &"toolmaking_chance", 1.0)
	_knob(Config.trade, &"workshop_from", 1)
	assert_false(first.knows_how(&"toolmaking"))
	assert_false(first.planner.workshop_wanted(), "not before toolmaking is known")
	var skilled := first.members()[0]
	skilled.skills[String(skilled.occupation_id)] = 0.9
	first._each_day(5)
	assert_true(first.knows_how(&"toolmaking"))
	var learned := session.events.of_type(&"knowledge_learned")
	assert_eq(EventText.text(learned[0], session.people, session.events),
		"%s has worked out how to make good tools" % skilled.given_name)
	# A workshop, then.
	assert_true(first.planner.workshop_wanted())
	_knob(Config.construction, &"homes_spare_least", -1000)
	_knob(Config.construction, &"storage_room_least", -1000)
	_knob(Config.construction, &"spoiled_from", 1_000_000)
	_knob(Config.construction, &"well_from", 1_000_000)
	var p := first.planner.plan(session.clock.tick)
	assert_eq(str(p.get("def", "")), "workshop")
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, skilled, 60.0, session.clock.tick):
		pass
	assert_not_null(first.workshop())
	# Someone makes tools there, of wood and stone.
	first.stockpile.add(&"wood", 10)
	first.stockpile.take(&"stone", first.stockpile.amount(&"stone"))
	assert_true(first.tools_wanted())
	var maker := first.ensure_toolmaker(session.clock.tick)
	assert_not_null(maker)
	assert_eq(maker.occupation_id, &"toolmaker")
	# No stone in store: they fetch a stone lying about for it.
	var fetching := Planner._craft_work(maker, _entered(maker))
	assert_eq([fetching[1]["type"], fetching[3]["type"]], ["quarry", "store"])
	first.stockpile.add(&"stone", 10)
	var steps := Planner._craft_work(maker, _entered(maker))
	assert_eq(steps[1]["type"], "craft")
	var stone := first.stockpile.amount(&"stone")
	assert_true(first.make_tool(maker))
	assert_eq(first.stockpile.amount(&"tools"), 1)
	assert_eq(first.stockpile.amount(&"stone"), stone - Config.trade.tool_stone)
	assert_eq(first.tools_made, 1)
	assert_true(first.tool_level() > 0.0)
	assert_eq(session.sample_stats()[&"tools"], 1.0, "the first tools statistic")
	first.wear_tool()
	assert_eq(first.stockpile.amount(&"tools"), 0)
	# A settlement founded from here knows it too.
	var own := _second()
	assert_true(own.knows_how(&"toolmaking"))


func test_trade_and_knowledge_are_saved() -> void:
	var own := _second()
	var first := session.settlement
	first.note_produced(&"grain", 50)
	first.learn(&"toolmaking", first.members()[0].id, session.clock.tick)
	trade.delivered(first.id, own.id, &"wood", 6, first.members()[0].id)
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.trade.trips, 1)
	assert_eq(again.trade.balance_of(first.id), ["wood", ""])
	assert_true(again.settlement.knows_how(&"toolmaking"))
	assert_near(float(again.settlement.produced["grain"]), 50.0, 0.01)
	assert_eq(again.settlements.all()[1].trade, again.trade)
	again.queue_free()


func test_version_26_save_loads() -> void:
	# Written by M12.3 (ecfdf1b): before trade.
	var dir := SaveManager.world_dir(V26_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V26_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 26)
	var loaded := SaveManager.load_world(V26_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.trade.trips, 0)
	assert_eq(s.settlement.knows.size(), 0)
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	s.queue_free()
	assert_true(SaveManager.SAVE_VERSION >= 27)
	var data := {"world": {"world_state": {"people": []}}}
	assert_eq(SaveMigrations._v26_to_v27(data)["world"]["world_state"]["trade"], {})


func _entered(person: PersonData) -> AiContext:
	var ctx := session.behavior.ctx
	ctx.enter(person)
	return ctx
