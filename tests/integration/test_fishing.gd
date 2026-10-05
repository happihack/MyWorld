extends TestCase
## M19.5: fishing and boats (bible §18.2a). Someone takes up fishing where
## there is water and fish; a fisher fishes from the bank, the catch going
## to the stores and the water's stock down; through the ice it is slower;
## rafts, canoes, nets, plank boats and sail come as discoveries, a landing
## is built on the bank with the boat moored at it, and from it — and with
## nets — the catch is bigger.

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
	session.settlement.jobs.refresh(session.settlement, session.clock.tick) # (fish wanted, now there is a fisher)
	return fisher


func test_someone_takes_up_fishing_where_there_are_fish() -> void:
	var own := session.settlement
	assert_true(session.occupations.has_def(&"fisher"))
	assert_true(own.fish_near(), "the river by the camp, and fish in it")
	assert_eq(own.fisher_count(), 0)
	Config.settlement.fisher_from_gatherers = 2
	var taken := own.ensure_fisher(session.clock.tick)
	Config.settlement.fisher_from_gatherers = SettlementConfig.new().fisher_from_gatherers
	assert_not_null(taken, "one of the gatherers")
	assert_eq(taken.occupation_id, &"fisher")
	assert_eq(own.fisher_count(), 1)
	assert_null(own.ensure_fisher(session.clock.tick), "one is enough to begin with")
	# No fish, no fishing.
	session.fauna.fish = 0.0
	assert_false(own.fish_near())


func test_a_fishers_morning() -> void:
	var fisher := _fisher()
	var steps := Planner.plan(&"work", fisher, ctx)
	assert_eq(steps.size(), 4, "to the bank, fish, to the stores, put it down")
	assert_eq([steps[0]["type"], steps[1]["type"], steps[2]["type"], steps[3]["type"]], ["walk_to", "work", "walk_to", "store"])
	assert_true(bool(steps[1]["fish"]))
	assert_eq(int(steps[1]["landing"]), 0, "from the bank: no landing yet")
	var bank: Vector2i = steps[0]["target"]
	assert_true(session.pathfinder.can_stand(bank) and session.world.get_water(bank) <= 0.0, "a dry bank")
	assert_true(session.world.get_water(steps[1]["at"]) > 0.0, "facing the water")
	var before := session.fauna.fish
	behavior.set_plan(fisher, &"work", &"purpose", steps, 2.0)
	var waited := 0.0
	while int(fisher.current_action.get("index", 0)) < 2 and waited < 400.0:
		_run(1.0)
		waited += 1.0
	assert_eq(fisher.carrying, &"fish")
	assert_true(fisher.carrying_amount >= 2, "a catch: %d (a fish in about twenty minutes)" % fisher.carrying_amount)
	assert_near(session.fauna.fish, before - fisher.carrying_amount, 0.001, "out of the water")
	# … and into the stores.
	waited = 0.0
	while session.settlement.stockpile.amount(&"fish") == 0 and waited < 300.0:
		_run(1.0)
		waited += 1.0
	assert_true(session.settlement.stockpile.amount(&"fish") > 0, "the catch in the stores")


func test_the_catch_by_ice_boat_and_net() -> void:
	var own := session.settlement
	assert_eq(WorkStep.catch_factor(own, false), 1.0, "a line from the bank")
	assert_eq(WorkStep.boat_of(own), PropData.Boat.NONE)
	own.learn(&"raft", 0, session.clock.tick)
	assert_eq(WorkStep.boat_of(own), PropData.Boat.RAFT)
	assert_eq(WorkStep.catch_factor(own, false), 1.0, "a boat helps only those in it")
	assert_true(WorkStep.catch_factor(own, true) > 1.0, "from a raft: more")
	var raft := WorkStep.catch_factor(own, true)
	own.learn(&"canoe", 0, session.clock.tick)
	assert_true(WorkStep.catch_factor(own, true) > raft, "from a canoe: more again")
	own.learn(&"nets", 0, session.clock.tick)
	assert_true(WorkStep.catch_factor(own, false) > 1.0, "nets help even from the bank")
	# The fish run out where they are taken too hard.
	session.fauna.fish = 1.0
	var fisher := _fisher()
	var step := {"effort": 0.0, "at": Vector2i.ZERO}
	assert_false(WorkStep.catch_fish(ctx, fisher, step, 100) and fisher.carrying_amount > 1)
	assert_eq(fisher.carrying_amount, 1, "the last fish")
	assert_true(WorkStep.catch_fish(ctx, fisher, step, 100), "fished out")


func test_boats_are_discoveries_and_the_landing_goes_on_the_bank() -> void:
	var own := session.settlement
	var techs := session.technology
	for id: StringName in [&"raft", &"canoe", &"nets", &"plank_boat", &"sail"]:
		assert_not_null(techs.library.get_def(id), "%s is a technology" % id)
	var raft := techs.library.get_def(&"raft")
	var missing := techs.missing(own, raft)
	assert_true(missing.has("trade:fisher"), "a fisher first: %s" % str(missing))
	assert_true(missing.has("resource:fish"), "and fish brought in")
	assert_eq(MemoryText.translate("TECH_RAFT"), "Rafts")
	# Rafts known and someone fishing: a landing is wanted, on the bank.
	_fisher()
	own.learn(&"toolmaking", 0, session.clock.tick)
	own.learn(&"raft", 0, session.clock.tick)
	var planner := own.planner
	assert_true(planner.landing_wanted())
	assert_true(planner.needs(session.clock.tick).has(&"landing"))
	var site: Variant = planner.landing_site()
	assert_not_null(site)
	var tile: Vector2i = site[0]
	var beside := false
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		beside = beside or session.world.get_water(tile + step) > 0.0
	assert_true(beside and session.world.get_water(tile) <= 0.0, "dry ground at the water's edge")
	# Built: the raft moored at it, and the fishers fish from it.
	var p := session.construction.start(&"landing", tile, session.clock.tick, int(site[1]), own.id)
	assert_false(p.is_empty())
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	var landing := session.props.prop_at(tile)
	assert_eq(landing.kind, PropData.Kind.LANDING)
	assert_eq(UIText.prop_name(PropData.Kind.LANDING), "Landing")
	techs.apply_effects()
	assert_eq(landing.variant, PropData.Boat.RAFT, "a raft at the landing")
	own.learn(&"canoe", 0, session.clock.tick)
	techs.apply_effects()
	assert_eq(landing.variant, PropData.Boat.CANOE, "then a canoe")
	assert_false(planner.landing_wanted(), "one is enough")
	var fisher := session.people.all_people().filter(func(x: PersonData) -> bool: return x.occupation_id == &"fisher")[0] as PersonData
	var spot := ctx.places.fishing_spot(fisher)
	assert_eq(int(spot["landing"]), landing.id, "from the boat at the landing")
