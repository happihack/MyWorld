extends TestCase
## FB6: ferrying. Where dry land straight across the water from a landing
## cannot be walked to, and the landing has a boat, there is a ferry: the
## way-finder goes over it, and whoever walks that way is taken over in the
## boat (seated in it), which then goes home empty. Land that can be walked
## to has no ferry.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var boats: BoatSystem


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


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## The settlement's landing, built at once, with a raft at it.
func _landing() -> PropData:
	var own := session.settlement
	own.learn(&"raft", 0, session.clock.tick)
	var site: Variant = own.planner.landing_site()
	assert_not_null(site)
	var p := session.construction.start(&"landing", site[0], session.clock.tick, int(site[1]), own.id)
	for resource: StringName in session.construction.still_needed(p):
		session.construction.deliver(p, resource, int(session.construction.still_needed(p)[resource]))
	while not session.construction.work(p, session.people.all_people()[0], 60.0, session.clock.tick):
		pass
	var landing := session.props.prop_at(site[0])
	if boats.boats_of(landing.id).is_empty():
		boats.add_boat(PropData.Boat.RAFT, landing, 0, own.id, session.clock.tick)
	return landing


## The first dry tile straight across the water from the landing (the way
## its jetty points first). [tile, step] — or [] if none.
func _across(landing: PropData) -> Array:
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var at := landing.tile + step
		var span := 0
		while span < BoatSystem.FERRY_SPAN and session.world.get_water(at) > 0.0:
			at += step
			span += 1
		if span > 0 and session.world.get_water(at) <= 0.0 and session.pathfinder.can_stand(at):
			return [at, step]
	return []


## Deep water all round `center` at a distance of two: an island of the
## nine tiles about it.
func _island(center: Vector2i) -> void:
	var deep := (Pathfinder.WADE_DEPTH + 2.0) * session.world.height_step
	var ring: Array[Vector2i] = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if maxi(absi(dx), absi(dy)) == 2:
				var tile := center + Vector2i(dx, dy)
				session.world.set_water(tile, maxf(session.world.get_water(tile), deep))
				ring.append(tile)
	for tile in ring:
		session.pathfinder.mark_dirty(tile)
	session.pathfinder.refresh_dirty()


func _walk(minutes: float) -> void:
	var left := minutes
	while left > 0.0001:
		var dt := minf(0.5, left)
		session.pathfinder.serve(1_000_000)
		session.movement.step(dt)
		left -= dt


func test_no_ferry_to_land_that_can_be_walked_to() -> void:
	var landing := _landing()
	var across := _across(landing)
	if not across.is_empty() and not session.pathfinder.is_reachable(landing.tile, across[0]):
		return # (cut off already in this world: there is nothing to show)
	boats.refresh_ferries()
	assert_eq(session.pathfinder.ferry_count(), 0, "the far bank can be walked to")


func test_a_ferry_to_land_cut_off() -> void:
	var landing := _landing()
	var across := _across(landing)
	assert_false(across.is_empty(), "water before the landing, and land across it")
	# The land across made an island: cut off from everything.
	var center: Vector2i = across[0] + across[1] * 2
	_island(center)
	assert_false(session.pathfinder.is_reachable(landing.tile, center), "cut off on foot")
	boats.refresh_ferries()
	assert_eq(session.pathfinder.ferry_count(), 1, "a ferry from the landing")
	var ends: Array = boats.ferries()[0]
	assert_eq(ends[0], landing.tile)
	assert_true(session.pathfinder.is_reachable(landing.tile, center), "the island reached by the ferry")
	assert_eq(Vector2(ends[1] - center).length() <= 1.5, true, "landing on the island (%s)" % str(ends[1]))
	# Someone walks there: over the ferry, seated in the raft.
	var person := session.people.all_people()[0]
	session.behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, BehaviorSystem.ACTIVITY_CALLED, [RestStep.make(1000000.0)])
	session.people.move(person.id, landing.tile)
	var raft := boats.boats_of(landing.id)[0]
	assert_true(session.movement.walk_to(person.id, center))
	var seen_aboard := false
	var raft_moved := false
	var start := raft.position
	var waited := 0.0
	while session.movement.is_walking(person.id) and waited < 120.0:
		_walk(0.5)
		waited += 0.5
		seen_aboard = seen_aboard or person.aboard == raft.id
		raft_moved = raft_moved or raft.position.distance_to(start) > 0.5
	assert_true(seen_aboard, "seated in the raft on the way over")
	assert_true(raft_moved, "the raft went with them")
	assert_eq(person.position, center, "on the island")
	assert_eq(person.aboard, 0, "ashore")
	# The raft goes home empty.
	waited = 0.0
	while raft.state != BoatData.State.MOORED and waited < 200.0:
		boats.step(0.5 * Config.time.real_seconds_per_game_minute)
		waited += 0.5
	assert_eq(raft.state, BoatData.State.MOORED, "tied up at home again")
	# And back the same way.
	assert_true(session.movement.walk_to(person.id, landing.tile))
	waited = 0.0
	while session.movement.is_walking(person.id) and waited < 120.0:
		_walk(0.5)
		waited += 0.5
	assert_eq(person.position, landing.tile, "home over the ferry")
	# Stopped halfway over: put across, not left on the water.
	assert_true(session.movement.walk_to(person.id, center))
	waited = 0.0
	while person.aboard == 0 and waited < 60.0:
		_walk(0.25)
		waited += 0.25
	assert_ne(person.aboard, 0, "out on the ferry")
	session.movement.stop(person.id)
	assert_eq(person.aboard, 0)
	assert_true(session.pathfinder.can_stand(person.position), "put ashore (%s)" % str(person.position))
	# The boat lost: no ferry.
	for boat in boats.boats_of(landing.id):
		boat.state = BoatData.State.DRIFTING
	boats.refresh_ferries()
	assert_eq(session.pathfinder.ferry_count(), 0, "no boat, no ferry")
	assert_false(session.pathfinder.is_reachable(landing.tile, center))
