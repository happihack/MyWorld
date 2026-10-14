extends TestCase
## FB5: fishing gear (bible §18.2a). Nets are made by a fisher and wear out
## with the fish they take (more slowly where a rack stands); a rack is built
## on the bank once nets are known; a settlement that fishes without boats
## builds a trap at the bank, which fills by itself and is emptied into the
## stores — by a fisher, or in the time away.

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
		session.behavior.step(dt)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		left -= dt


## Someone grown, a fisher now (everyone else standing still).
func _fisher() -> PersonData:
	var fisher: PersonData = null
	for person in session.people.all_people():
		if fisher == null and ctx.stage_of(person) == PersonData.LifeStage.ADULT:
			fisher = person
		else:
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])
	fisher.occupation_id = &"fisher"
	fisher.carrying_amount = 0
	fisher.needs = PackedFloat32Array([0.9, 0.95, 0.9, 0.9, 0.6, 1.0])
	session.settlement.jobs.refresh(session.settlement, session.clock.tick)
	return fisher


## A building put up at once where the planner would put it.
func _build(def_id: StringName, site: Array) -> PropData:
	var own := session.settlement
	var p := session.construction.start(def_id, site[0], session.clock.tick, int(site[1]), own.id)
	assert_false(p.is_empty(), "%s begun" % def_id)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	return session.props.prop_at(site[0])


func test_nets_are_made_and_wear_out() -> void:
	var own := session.settlement
	_fisher()
	assert_eq(FishGear.nets_wanted(own), 0, "not before nets are known")
	own.learn(&"nets", 0, session.clock.tick)
	assert_eq(FishGear.nets_wanted(own), 1, "one for the fisher")
	own.stockpile.add(&"wood", 10)
	assert_true(FishGear.net_to_make(own))
	assert_true(FishGear.make_net(own))
	assert_eq(own.stockpile.amount(FishGear.NETS), 1)
	assert_false(FishGear.net_to_make(own), "one is enough for one fisher")
	assert_true(FishGear.has_nets(own))
	# Fish taken with it wear it out, sooner or later.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fish := 0
	while own.stockpile.amount(FishGear.NETS) > 0 and fish < 2000:
		FishGear.wear_nets(own, 1, rng)
		fish += 1
	assert_true(fish > 3 and fish < 2000, "worn out after %d fish" % fish)
	assert_false(FishGear.has_nets(own), "gone from the stores")


func test_a_rack_keeps_the_nets_longer() -> void:
	var own := session.settlement
	_fisher()
	own.learn(&"nets", 0, session.clock.tick)
	var planner := own.planner
	assert_true(planner.net_rack_wanted(), "nets known and someone fishes")
	assert_true(planner.needs(session.clock.tick).has(&"net_rack"))
	var site: Variant = planner.landing_site()
	assert_not_null(site, "on the bank")
	var rack := _build(&"net_rack", site)
	assert_eq(rack.kind, PropData.Kind.NET_RACK)
	assert_eq(UIText.prop_name(PropData.Kind.NET_RACK), "Net rack")
	assert_false(planner.net_rack_wanted(), "one is enough")
	assert_true(FishGear.has_rack(own))
	# Twice as many fish to wear a net out, on average, with the rack.
	var worn := func(with_rack: bool) -> float:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var total := 0
		for n in 60:
			own.stockpile.add(FishGear.NETS, 1)
			var fish := 0
			while own.stockpile.amount(FishGear.NETS) > 0 and fish < 5000:
				FishGear.wear_nets(own, 1, rng)
				fish += 1
			total += fish
		return float(total) / 60.0 / (FishGear.NET_LIFE * (FishGear.RACK_LIFE_FACTOR if with_rack else 1.0))
	assert_near(worn.call(true), 1.0, 0.35, "with the rack: about twice the net's life")


func test_the_fisher_makes_a_net_when_one_is_wanted() -> void:
	var own := session.settlement
	var fisher := _fisher()
	own.learn(&"nets", 0, session.clock.tick)
	own.stockpile.add(&"wood", 10)
	var steps := Planner.plan(&"work", fisher, ctx)
	assert_eq(steps.size(), 2, "to the fire (no rack yet), and making it")
	assert_eq(str(steps[1]["type"]), "craft")
	assert_eq(str(steps[1]["make"]), "nets")
	behavior.set_plan(fisher, &"work", &"purpose", steps, 2.0)
	var waited := 0.0
	while own.stockpile.amount(FishGear.NETS) == 0 and waited < 400.0:
		_run(1.0)
		waited += 1.0
	assert_eq(own.stockpile.amount(FishGear.NETS), 1, "a net made")
	assert_true(WorkStep.catch_factor(own, false) > 1.0, "and fished with")


func test_a_trap_fills_and_is_emptied() -> void:
	var own := session.settlement
	var fisher := _fisher()
	var planner := own.planner
	assert_true(planner.fish_trap_wanted(), "a fisher, and no boats")
	assert_true(planner.needs(session.clock.tick).has(&"fish_trap"))
	var trap := _build(&"fish_trap", planner.landing_site())
	assert_eq(trap.kind, PropData.Kind.FISH_TRAP)
	assert_false(planner.fish_trap_wanted(), "one is enough")
	assert_true(session.world.get_water(FishGear.trap_water(trap, session.world)) > 0.0, "set in the water before the bank")
	# A day: fish in it, out of the water.
	var before := session.fauna.waters.total()
	assert_eq(FishGear.fill_traps(session.props, session.fauna.waters, session.world, false), FishGear.TRAP_CATCH)
	assert_eq(trap.stock, FishGear.TRAP_CATCH)
	assert_near(session.fauna.waters.total(), before - FishGear.TRAP_CATCH, 0.001, "out of the water")
	assert_eq(FishGear.fill_traps(session.props, session.fauna.waters, session.world, true), 0, "nothing while the water is frozen")
	for i in 10:
		FishGear.fill_traps(session.props, session.fauna.waters, session.world, false)
	assert_eq(trap.stock, FishGear.TRAP_HOLDS, "no more than it holds")
	# The fisher empties it first, into the stores.
	var steps := Planner.plan(&"work", fisher, ctx)
	assert_eq(str(steps[1]["type"]), "boat")
	assert_eq(int(steps[1]["trap"]), trap.id)
	behavior.set_plan(fisher, &"work", &"purpose", steps, 2.0)
	var waited := 0.0
	while own.stockpile.amount(&"fish") == 0 and waited < 400.0:
		_run(1.0)
		waited += 1.0
	assert_true(own.stockpile.amount(&"fish") > 0, "the trap's fish in the stores")
	assert_true(trap.stock < FishGear.TRAP_HOLDS, "taken out of the trap")
	# A landing standing: no trap wanted where there are boats.
	trap.kind = PropData.Kind.WOODSHED
	session.props.changed(trap.id)
	own.learn(&"raft", 0, session.clock.tick)
	_build(&"landing", planner.landing_site())
	assert_false(planner.fish_trap_wanted(), "boats: no trap")


func test_a_trap_is_emptied_in_the_time_away() -> void:
	var own := session.settlement
	_fisher()
	var trap := _build(&"fish_trap", own.planner.landing_site())
	trap.stock = 5
	var before := own.stockpile.amount(&"fish")
	var away := OfflineSimulator.new(session)
	away._fish(own, 1.0)
	assert_eq(trap.stock, 0, "emptied")
	assert_true(own.stockpile.amount(&"fish") >= before + 5, "into the stores")


func test_the_gear_is_saved() -> void:
	var own := session.settlement
	_fisher()
	own.learn(&"nets", 0, session.clock.tick)
	own.stockpile.add(FishGear.NETS, 2)
	var trap := _build(&"fish_trap", own.planner.landing_site())
	trap.stock = 4
	var data := session.props.get_prop(trap.id).to_dict()
	var back := PropData.from_dict(data)
	assert_eq(back.kind, PropData.Kind.FISH_TRAP)
	assert_eq(back.stock, 4, "the fish in the trap")
	assert_eq(own.stockpile.amount(FishGear.NETS), 2)
