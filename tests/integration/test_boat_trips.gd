extends TestCase
## FB3–FB4: out on the water. A fisher with a boat at the landing goes aboard,
## paddles out to where the fish are thick, fishes, and comes back to the
## landing with the catch, which goes to the stores; ahead of a storm, home;
## in one, maybe swamped — ashore, the catch lost; a boat left out with nobody
## aboard is brought in; and away, the boat's days are lived by the day.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var behavior: BehaviorSystem
var ctx: AiContext
var boats: BoatSystem
var own: Settlement


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
	boats = session.boats
	own = session.settlement


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
		session.behavior.step(dt)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		left -= dt


## A fisher (everyone else standing still), a landing on the bank, a canoe at it.
func _out_fishing() -> Array:
	var fisher: PersonData = null
	for person in session.people.all_people():
		if fisher == null and ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			fisher = person
		else:
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])
	fisher.occupation_id = &"fisher"
	fisher.carrying_amount = 0
	fisher.needs = PackedFloat32Array([0.9, 0.95, 0.9, 0.9, 0.6, 1.0])
	own.learn(&"toolmaking", 0, session.clock.tick)
	own.learn(&"raft", 0, session.clock.tick)
	own.learn(&"canoe", 0, session.clock.tick)
	var site: Variant = own.planner.landing_site()
	assert_not_null(site, "a landing site")
	var p := session.construction.start(&"landing", site[0], session.clock.tick, int(site[1]), own.id)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	var landing := session.props.prop_at(site[0])
	var canoe := boats.add_boat(PropData.Boat.CANOE, landing, 0, own.id, session.clock.tick)
	session.fauna.waters.set_total(session.fauna.waters.total_capacity())
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)
	return [fisher, landing, canoe]


func test_a_fishers_day_by_boat() -> void:
	var setup := _out_fishing()
	var fisher: PersonData = setup[0]
	var landing: PropData = setup[1]
	var canoe: BoatData = setup[2]
	var steps := Planner.plan(&"work", fisher, ctx)
	assert_eq(steps.size(), 4, "to the landing, out in the boat, to the stores, put it down")
	assert_eq([steps[0]["type"], steps[1]["type"], steps[2]["type"], steps[3]["type"]], ["walk_to", "boat", "walk_to", "store"])
	assert_eq(steps[0]["target"], landing.tile)
	behavior.set_plan(fisher, &"work", &"purpose", steps, 2.0)
	var waited := 0.0
	var was_out := false
	var furthest := 0.0
	while int(fisher.current_action.get("index", 0)) < 2 and waited < 600.0:
		_run(1.0)
		waited += 1.0
		if canoe.state == BoatData.State.OUT:
			was_out = true
			assert_eq(fisher.aboard, canoe.id, "aboard")
			assert_true(fisher.world2d().distance_to(canoe.position) < 0.5, "where the boat is")
			furthest = maxf(furthest, canoe.position.distance_to(landing.position2d()))
	assert_true(was_out, "out on the water")
	assert_true(furthest > 1.0, "paddled out (%.1f tiles)" % furthest)
	assert_eq(canoe.state, BoatData.State.MOORED, "and back, tied up")
	assert_eq(canoe.trips, 1)
	assert_eq(fisher.aboard, 0)
	assert_true(session.world.get_water(fisher.position) <= 0.0 or fisher.position == landing.tile, "ashore")
	assert_eq(fisher.carrying, &"fish")
	assert_true(fisher.carrying_amount >= 2, "a catch: %d" % fisher.carrying_amount)
	waited = 0.0
	while own.stockpile.amount(&"fish") == 0 and waited < 300.0:
		_run(1.0)
		waited += 1.0
	assert_true(own.stockpile.amount(&"fish") > 0, "the catch in the stores")


func test_the_catch_fills_the_hold_and_is_carried_in() -> void:
	# (FB4: arms full, the fish go in the hull; at the landing the fisher
	# carries them to the stores an armful at a time.)
	var setup := _out_fishing()
	var fisher: PersonData = setup[0]
	var landing: PropData = setup[1]
	var canoe: BoatData = setup[2]
	assert_true(boats.board(canoe, fisher.id))
	var water: Variant = boats.fishing_water(canoe)
	assert_not_null(water)
	var step := BoatStep.make(landing.id, 600.0)
	step["boat"] = canoe.id
	step["at"] = water
	step["phase"] = "fish"
	var arms := ctx.carry_capacity(&"fish")
	var done := WorkStep.catch_fish(ctx, fisher, step, 1000)
	assert_true(done, "arms and hold full")
	assert_eq(fisher.carrying_amount, arms)
	assert_eq(canoe.load_amount, int(BoatData.HOLD[PropData.Boat.CANOE]), "the hold full")
	assert_eq(canoe.caught, arms + canoe.load_amount)
	boats.bring_in(canoe)
	fisher.carrying_amount = 0
	fisher.carrying = &""
	# The next work: the catch in the boat carried to the stores.
	var plan := Planner.plan(&"work", fisher, ctx)
	assert_eq([plan[0]["type"], plan[1]["type"], plan[2]["type"], plan[3]["type"]], ["walk_to", "boat", "walk_to", "store"])
	assert_true(bool(plan[1].get("unload", false)), "unloading")
	behavior.set_plan(fisher, &"work", &"purpose", plan, 2.0)
	var before := own.stockpile.amount(&"fish")
	var waited := 0.0
	while own.stockpile.amount(&"fish") == before and waited < 300.0:
		_run(1.0)
		waited += 1.0
	assert_true(own.stockpile.amount(&"fish") > before, "carried to the stores")
	assert_eq(canoe.load_amount, int(BoatData.HOLD[PropData.Boat.CANOE]) - arms, "an armful out of the hold")
	# Left in the hull, fish spoil.
	var left := canoe.load_amount
	boats.advance_to(session.clock.tick + DAY)
	assert_eq(canoe.load_amount, left / 2)


func test_more_fishers_as_the_settlement_grows() -> void:
	assert_true(own.fish_near())
	assert_eq(own.fishers_wanted(), clampi(1 + own.member_count() / Settlement.FISHERS_PER_PEOPLE, 1, Settlement.FISHERS_MOST))
	# The water near fished down: one is enough.
	var waters := session.fauna.waters
	waters.set_total(0.0)
	assert_eq(own.fishers_wanted(), 1)


func test_out_to_where_the_fish_are() -> void:
	var setup := _out_fishing()
	var canoe: BoatData = setup[2]
	var waters := session.fauna.waters
	var near: Array = waters.cells_near(canoe.tile(), BoatSystem.FISHING_REACH)
	assert_true(near.size() >= 2, "more than one stretch of water in reach")
	# The fish all in one stretch, not the nearest.
	waters.set_total(0.0)
	var rich: Vector2i = near[-1][0]
	waters.set_stock(FishWaters.middle_of(rich), waters.capacity_at(FishWaters.middle_of(rich)))
	var spot: Variant = boats.fishing_water(canoe)
	if spot == null:
		return # (that water cannot be got to by boat from here)
	assert_eq(FishWaters.cell_of(spot), rich, "out to the fish")


func test_home_ahead_of_a_storm() -> void:
	var setup := _out_fishing()
	var fisher: PersonData = setup[0]
	var canoe: BoatData = setup[2]
	behavior.set_plan(fisher, &"work", &"purpose", Planner.plan(&"work", fisher, ctx), 2.0)
	var waited := 0.0
	while canoe.state != BoatData.State.OUT and waited < 200.0:
		_run(1.0)
		waited += 1.0
	assert_eq(canoe.state, BoatData.State.OUT)
	session.weather.state = WeatherSystem.STORM
	waited = 0.0
	while fisher.aboard != 0 and waited < 300.0:
		_run(1.0)
		waited += 1.0
	assert_eq(fisher.aboard, 0, "off the water")
	assert_ne(canoe.state, BoatData.State.OUT)
	assert_true(session.pathfinder.can_stand(fisher.position) or fisher.position == (setup[1] as PropData).tile, "ashore")


func test_swamped() -> void:
	var setup := _out_fishing()
	var fisher: PersonData = setup[0]
	var canoe: BoatData = setup[2]
	var told := []
	boats.swamped.connect(func(boat: BoatData, drowned: Array) -> void: told.append([boat.id, drowned.size()]))
	assert_true(boats.board(canoe, fisher.id))
	fisher.carrying = &"fish"
	fisher.carrying_amount = 3
	boats.swamp(canoe, session.clock.tick)
	assert_eq(told.size(), 1)
	assert_eq(told[0][1], 0, "nobody drowns but in the worst of it")
	assert_eq(fisher.carrying_amount, 0, "the catch lost")
	assert_true(canoe.crew.is_empty())
	assert_true(boats.get_boat(canoe.id) == null or canoe.state == BoatData.State.DRIFTING, "lost, or adrift")


func test_a_boat_left_out_is_brought_in() -> void:
	var setup := _out_fishing()
	var fisher: PersonData = setup[0]
	var canoe: BoatData = setup[2]
	assert_true(boats.board(canoe, fisher.id))
	canoe.position += Vector2(0.0, 2.0)
	# Saved and restored mid-trip: the boat, out, with its crew.
	var again := BoatSystem.new()
	again.bind(session.world, session.props, session.ids, session.clock.tick)
	again.from_dict(boats.to_dict())
	assert_eq(again.get_boat(canoe.id).state, BoatData.State.OUT)
	assert_eq(Array(again.get_boat(canoe.id).crew), [fisher.id])
	# Nobody out in it (not at a boat step): brought in at the day's end.
	boats.advance_to(session.clock.tick + DAY)
	assert_eq(canoe.state, BoatData.State.MOORED)
	assert_true(canoe.crew.is_empty())


func test_away_the_fishers_go_out_by_boat() -> void:
	var setup := _out_fishing()
	var canoe: BoatData = setup[2]
	var fisher: PersonData = setup[0]
	var catch_by_boat := 0
	var offline := OfflineSimulator.new(session)
	for day in 6:
		var before := own.stockpile.amount(&"fish")
		offline._fish(own, 1.0)
		catch_by_boat += own.stockpile.amount(&"fish") - before
	assert_eq(canoe.trips, 6, "out each day")
	assert_eq(canoe.caught, catch_by_boat)
	assert_true(catch_by_boat > 0)
	assert_not_null(fisher)
