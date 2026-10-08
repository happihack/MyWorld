extends TestCase
## FB2: boats as things (bible §18.2a). A settlement with a landing has its
## boats built there by a builder from wood — better kinds taking the place
## of older ones — worn and mended, torn loose by a storm to drift with the
## current until they run aground, fetched back from near or lost from far;
## laid up in the ice; saved with the world; and an older world's landings
## each given the boat they showed.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var boats: BoatSystem
var own: Settlement
var _lived := 0


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	boats = session.boats
	own = session.settlement
	_lived = 0


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## A landing built on the bank (rafts known), and a builder.
func _landing() -> PropData:
	var fisher: PersonData = null
	var builder: PersonData = null
	for person in own.members():
		if session.behavior.ctx.stage_of(person) != PersonData.LifeStage.ADULT:
			continue
		if fisher == null:
			fisher = person
		elif builder == null:
			builder = person
	fisher.occupation_id = &"fisher"
	builder.occupation_id = &"builder"
	own.learn(&"toolmaking", 0, session.clock.tick)
	own.learn(&"raft", 0, session.clock.tick)
	var site: Variant = own.planner.landing_site()
	assert_not_null(site, "a landing site")
	var tile: Vector2i = site[0]
	var p := session.construction.start(&"landing", tile, session.clock.tick, int(site[1]), own.id)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	return session.props.prop_at(tile)


## Lives the boats' days (only theirs): `days` more.
func _days(days: int) -> void:
	if _lived < session.clock.tick:
		_lived = session.clock.tick
	for day in days:
		_lived += DAY
		boats.advance_to(_lived)


func test_a_boat_is_built_at_the_landing() -> void:
	var landing := _landing()
	assert_eq(boats.size(), 0, "no boat until one is made")
	own.stockpile.add(&"wood", 40)
	var wood := own.stockpile.amount(&"wood")
	var built := []
	boats.boat_built.connect(func(boat: BoatData) -> void: built.append(boat.kind))
	_days(1)
	assert_eq(own.stockpile.amount(&"wood"), wood - int(BoatData.WOOD[PropData.Boat.RAFT]), "the wood for a raft")
	_days(BoatSystem.BUILD_DAYS[PropData.Boat.RAFT] + 1)
	assert_eq(boats.size(), 1, "a raft")
	var raft := boats.all_boats()[0]
	assert_eq(raft.kind, PropData.Boat.RAFT)
	assert_eq(raft.landing_id, landing.id)
	assert_eq(raft.state, BoatData.State.MOORED)
	assert_true(raft.position.distance_to(landing.position2d()) < 1.0, "moored at the landing")
	assert_true(session.world.get_water(raft.tile()) > 0.0, "on the water beside it, not on its dry tile")
	assert_eq(built, [PropData.Boat.RAFT], "the settlement's first raft is told")
	_days(10)
	assert_eq(boats.size(), BoatSystem.room_at_landing(own), "as many as the landing holds (a camp: one)")


func test_with_no_builder_the_fisher_makes_one() -> void:
	_landing()
	for person in own.members():
		if person.occupation_id == &"builder":
			person.occupation_id = &"forager"
	own.stockpile.add(&"wood", 40)
	_days(BoatSystem.BUILD_DAYS[PropData.Boat.RAFT] + 2)
	assert_eq(boats.size(), 1, "a raft, of the fisher's own making")
	# Nobody to make one: none.
	boats.remove(boats.all_boats()[0].id)
	for person in own.members():
		if person.occupation_id == &"fisher":
			person.occupation_id = &"forager"
	_days(BoatSystem.BUILD_DAYS[PropData.Boat.RAFT] + 2)
	assert_eq(boats.size(), 0)


func test_a_better_boat_takes_the_place_of_an_older_one() -> void:
	var landing := _landing()
	boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	own.learn(&"canoe", 0, session.clock.tick)
	own.stockpile.add(&"wood", 40)
	_days(BoatSystem.BUILD_DAYS[PropData.Boat.CANOE] + 2)
	assert_eq(boats.size(), 1)
	assert_eq(boats.all_boats()[0].kind, PropData.Boat.CANOE, "the canoe in the raft's place")
	_days(6)
	assert_eq(boats.all_boats()[0].kind, PropData.Boat.CANOE, "and nothing more to build")


func test_wear_and_mending() -> void:
	var landing := _landing()
	var raft := boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	_days(10)
	assert_near(raft.condition, 1.0 - 10 * BoatSystem.WEAR_PER_DAY, 0.0001, "worn a little each day")
	raft.condition = BoatSystem.MEND_BELOW - 0.05
	own.stockpile.add(&"wood", 5)
	var wood := own.stockpile.amount(&"wood")
	_days(1)
	assert_true(raft.condition > BoatSystem.MEND_BELOW, "mended by the builder")
	assert_eq(own.stockpile.amount(&"wood"), wood - BoatSystem.MEND_WOOD)
	# Without wood to mend it, it falls apart in the end.
	own.stockpile.take(&"wood", own.stockpile.amount(&"wood"))
	raft.condition = 0.002
	var lost := []
	boats.boat_lost.connect(func(boat: BoatData, why: StringName) -> void: lost.append(why))
	_days(1)
	assert_eq(boats.size(), 0)
	assert_eq(lost, [&"fell_apart"])


func test_a_storm_tears_a_boat_loose_and_it_drifts_until_aground() -> void:
	var landing := _landing()
	var raft := boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	var moored := raft.position
	session.weather.state = WeatherSystem.STORM
	var waited := 0
	while raft.state == BoatData.State.MOORED and waited < 200:
		_days(1)
		waited += 1
	session.weather.state = WeatherSystem.CLEAR
	assert_ne(raft.state, BoatData.State.MOORED, "torn loose in the end (%d days)" % waited)
	# Drifting with the current, it comes to rest somewhere it was not tied up.
	raft.state = BoatData.State.DRIFTING
	raft.position = moored
	for i in 8000:
		if raft.state != BoatData.State.DRIFTING:
			break
		boats.step(BoatSystem.DRIFT_STEP)
	assert_eq(raft.state, BoatData.State.AGROUND, "aground")
	# Near its landing: fetched back the next day; far off: lost, and told.
	raft.position = landing.position2d() + Vector2(3.0, 0.0)
	_days(1)
	assert_eq(raft.state, BoatData.State.MOORED, "fetched back")
	assert_true(raft.position.distance_to(moored) < 0.01, "to its place")
	var lost := []
	boats.boat_lost.connect(func(boat: BoatData, why: StringName) -> void: lost.append(why))
	raft.state = BoatData.State.AGROUND
	raft.position = landing.position2d() + Vector2(BoatSystem.RECOVER_REACH + 5.0, 0.0)
	_days(1)
	assert_eq(lost, [&"carried_off"])
	assert_eq(boats.size(), 0)


func test_the_current_carries_a_drifting_boat() -> void:
	var landing := _landing()
	var raft := boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	# Somewhere on the river where the water runs.
	var flowing: Variant = null
	for tile in session.pathfinder.shore_tiles():
		if session.world.get_water(tile) > raft.draught() * 2.0 and session.water.current_at(tile).length() > 0.05:
			flowing = tile
			break
	if flowing == null:
		return # (a world without running water: nothing to show)
	raft.position = Vector2(flowing) + Vector2(0.5, 0.5)
	raft.state = BoatData.State.DRIFTING
	var flow: Vector2 = session.water.current_at(flowing)
	var from := raft.position
	for i in 10:
		boats.step(BoatSystem.DRIFT_STEP)
	if raft.state == BoatData.State.DRIFTING:
		assert_true((raft.position - from).dot(flow) > 0.0, "downstream")


func test_iced_in_they_are_laid_up() -> void:
	var landing := _landing()
	var raft := boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	var frozen := [true]
	boats.is_frozen = func() -> bool: return frozen[0]
	_days(1)
	assert_eq(raft.state, BoatData.State.LAID_UP)
	frozen[0] = false
	_days(1)
	assert_eq(raft.state, BoatData.State.MOORED, "out again with the thaw")


func test_saved_and_restored() -> void:
	var landing := _landing()
	var raft := boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	raft.condition = 0.7
	raft.trips = 3
	var again := BoatSystem.new()
	again.bind(session.world, session.props, session.ids, session.clock.tick)
	assert_eq(again.from_dict(boats.to_dict()), 0)
	assert_eq(again.size(), 1)
	var back := again.get_boat(raft.id)
	assert_eq(back.kind, PropData.Boat.RAFT)
	assert_eq(back.landing_id, landing.id)
	assert_near(back.condition, 0.7, 0.0001)
	assert_eq(back.trips, 3)
	assert_eq(back.position, raft.position)
	assert_eq(again.from_dict({"boats": [{"id": "x"}, {"id": raft.id + 1, "x": NAN}]}), 2, "bad records skipped")


func test_an_older_worlds_landings_get_their_boats() -> void:
	var landing := _landing()
	landing.variant = PropData.Boat.CANOE
	assert_eq(boats.adopt_landings(session.clock.tick), 1)
	assert_eq(boats.all_boats()[0].kind, PropData.Boat.CANOE, "the boat it showed")
	assert_eq(boats.adopt_landings(session.clock.tick), 0, "once")


func test_boats_are_drawn() -> void:
	var landing := _landing()
	var view := BoatsView.new()
	add_child(view)
	view.show_boats(session.world, boats)
	var raft := boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	assert_eq(view.boat_count(), 1)
	var at := view.boat_transform(raft.id).origin
	assert_near(at.x, raft.position.x, 0.001)
	assert_near(at.z, raft.position.y, 0.001)
	# Moved by the simulation in a step, it glides there — not in one jump.
	var from := view.boat_transform(raft.id).origin
	raft.position += Vector2(0.6, 0.0)
	view._process(0.05)
	var part := view.boat_transform(raft.id).origin
	assert_true(part.x > from.x + 0.001 and part.x < raft.position.x - 0.1, "on its way (%.2f of %.2f → %.2f)" % [part.x, from.x, raft.position.x])
	for i in 60:
		view._process(0.05)
	assert_near(view.boat_transform(raft.id).origin.x, raft.position.x, 0.01, "and there")
	# Someone aboard sits on it as drawn, seated (no legs, no walking).
	var rower := session.people.all_people()[0]
	assert_true(boats.board(raft, rower.id))
	rower.aboard = raft.id
	var seat: Variant = view.seat_for(rower)
	assert_not_null(seat)
	assert_near((seat[0] as Vector3).x, view.boat_transform(raft.id).origin.x, 0.2)
	rower.aboard = 0
	boats.remove(raft.id)
	assert_eq(view.boat_count(), 0)
	view.queue_free()

