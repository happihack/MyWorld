extends TestCase
## People walking (M4.3): in the real generated world, along found ways.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const YEAR := 1440 * 24

var session: WorldSession
var finder: Pathfinder
var movement: MovementSystem
var arrived: Array[int] = []
var blocked: Array[int] = []


func before_each() -> void:
	SaveManager.attach(null)
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false) # the tests step time themselves
	session.loose_system.set_process(false)
	session.water.set_process(false)
	finder = session.pathfinder
	movement = session.movement
	arrived.clear()
	blocked.clear()
	movement.arrived.connect(func(id: int) -> void: arrived.append(id))
	movement.blocked.connect(func(id: int) -> void: blocked.append(id))


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _home() -> Vector2i:
	return session.start.settlement_tile


func _adult() -> PersonData:
	for p in session.people.all_people():
		if p.life_stage(session.clock.tick, YEAR, Config.people) == PersonData.LifeStage.ADULT:
			return p
	return null


func _of(stage: PersonData.LifeStage) -> PersonData:
	for p in session.people.all_people():
		if p.life_stage(session.clock.tick, YEAR, Config.people) == stage:
			return p
	return null


## Lets the pathfinder answer and time pass, `minutes` of game time in steps.
func _run(minutes: float, step: float = 0.25) -> void:
	var left := minutes
	while left > 0.0001:
		finder.serve(1_000_000)
		movement.step(minf(step, left))
		left -= step


## A dry open tile `distance` tiles from the settlement, reachable from it.
func _open_tile(distance: int) -> Vector2i:
	for offset: Vector2i in [Vector2i(distance, 0), Vector2i(0, distance), Vector2i(-distance, 0), Vector2i(0, -distance),
			Vector2i(distance, distance), Vector2i(-distance, distance)]:
		var tile := _home() + offset
		if finder.can_stand(tile) and finder.weight_at(tile) < 1.5 and session.props.prop_at(tile) == null \
				and finder.is_reachable(_home() + Vector2i(0, 1), tile):
			return tile
	return _home() + Vector2i(0, 1)


## The far side of the river from the settlement.
func _across_the_river() -> Vector2i:
	var z := _home().y
	var river_x := session.generator.river_center_x(z)
	var side := -1 if _home().x > river_x else 1
	for d in range(6, 30):
		var tile := Vector2i(int(river_x) + side * d, z)
		if finder.can_stand(tile) and session.world.get_water(tile) == 0.0:
			return tile
	return Vector2i.ZERO


# --- the graph of the real world ------------------------------------------------------------------

func test_the_real_world_is_walkable_where_it_should_be() -> void:
	assert_true(finder.is_bound())
	var bounds := session.world.bounds
	var standable := 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var tile := Vector2i(x, y)
			if finder.can_stand(tile):
				standable += 1
				assert_true(WorldSetup.is_walkable(session.world, tile))
	assert_true(standable > bounds.get_area() / 2, "most of the box can be walked (%d tiles)" % standable)
	for hut_id in session.start.hut_ids:
		assert_false(finder.can_stand(session.props.get_prop(hut_id).tile), "nobody walks through a hut")
	assert_false(finder.can_stand(_home()), "or through the fire")
	# Everyone can reach the fire, their own door, and each other.
	var people := session.people.all_people()
	for p in people:
		assert_true(finder.can_stand(p.position), "%s stands on walkable ground" % p.given_name)
		assert_true(finder.is_reachable(p.position, _home()))
		assert_true(finder.is_reachable(p.position, session.props.get_prop(p.home_building_id).tile))
		assert_true(finder.is_reachable(p.position, people[0].position))


func test_the_river_cannot_be_crossed_on_foot() -> void:
	var far := _across_the_river()
	assert_ne(far, Vector2i.ZERO)
	assert_eq(finder.find_path(_home() + Vector2i(0, 1), far).size(), 0, "deep water all the way")
	# But the bank can be reached (for a drink).
	var river := Vector2i(int(session.generator.river_center_x(_home().y)), _home().y)
	var to_water := finder.find_path(_home() + Vector2i(0, 1), river)
	assert_true(to_water.size() > 1, "to the water's edge")
	assert_true((to_water[-1] - river).length() <= 4.5)


func test_building_the_graph_and_finding_ways_is_fast_enough() -> void:
	var started := Time.get_ticks_usec()
	finder.rebuild()
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	# Long ways from the settlement to tiles all over the near side of the box.
	var from := _home() + Vector2i(0, 1)
	var targets: Array[Vector2i] = []
	var bounds := session.world.bounds
	for y in range(bounds.position.y + 2, bounds.end.y - 2, 5):
		for x in range(bounds.position.x + 2, bounds.end.x - 2, 5):
			targets.append(Vector2i(x, y))
	started = Time.get_ticks_usec()
	var found := 0
	var longest := 0
	for target in targets:
		var path := finder.find_path(from, target)
		if not path.is_empty():
			found += 1
			longest = maxi(longest, path.size())
	var per_path_ms := (Time.get_ticks_usec() - started) / 1000.0 / targets.size()
	print("    pathfinder: graph built in %.1f ms; %d ways (%d found, longest %d tiles) at %.3f ms each" % [
		build_ms, targets.size(), found, longest, per_path_ms])
	assert_true(found > targets.size() / 4)
	assert_true(per_path_ms < 1.0, "%.3f ms per path" % per_path_ms)
	assert_true(build_ms < 250.0, "%.1f ms to build" % build_ms)


# --- walking --------------------------------------------------------------------------------------

func test_a_person_walks_to_where_they_are_sent() -> void:
	var person := _adult()
	var from := person.world2d()
	var target := _open_tile(6)
	assert_true(movement.walk_to(person.id, target, Vector2(0.25, 0.75)))
	assert_true(movement.is_walking(person.id))
	assert_true(movement.is_waiting(person.id), "first the way has to be found")
	assert_eq(movement.target_of(person.id), target)
	movement.step(1.0)
	assert_eq(person.world2d(), from, "nobody sets off before they know the way")
	finder.serve(1_000_000)
	assert_false(movement.is_waiting(person.id))
	var way := movement.remaining_path(person.id)
	assert_eq(way[-1], target)
	movement.step(1.0)
	var moved := person.world2d().distance_to(from)
	assert_true(moved > 0.2 and moved < 0.6, "about a minute's walk (%.2f tiles)" % moved)
	assert_eq(session.spatial.get_position(person.id), person.world2d(), "the index knows where they are")
	_run(60.0)
	assert_eq(arrived, [person.id] as Array[int])
	assert_false(movement.is_walking(person.id))
	assert_eq(person.position, target)
	assert_true(person.sub_tile_offset.is_equal_approx(Vector2(0.25, 0.75)), "to the very spot (%s)" % person.sub_tile_offset)
	assert_eq(movement.walking_count(), 0)
	assert_eq(blocked.size(), 0)
	# Already there: arrives at once.
	movement.walk_to(person.id, target, Vector2(0.25, 0.75))
	_run(0.5)
	assert_eq(arrived.size(), 2)


func test_walking_takes_as_long_as_the_way_is_hard() -> void:
	var person := _adult()
	person.health = 1.0
	var target := _open_tile(8)
	var path := finder.find_path(person.position, target)
	# Each tile centre to the next, at the speed of the tile walked into.
	var expected := 0.0
	var at := person.world2d()
	for i in range(1, path.size()):
		var goal := Vector2(path[i]) + Vector2(0.5, 0.5)
		expected += at.distance_to(goal) / movement.speed_of(person, path[i])
		at = goal
	movement.walk_to(person.id, target)
	finder.serve(1_000_000)
	var taken := 0.0
	while movement.is_walking(person.id) and taken < 500.0:
		movement.step(0.05)
		taken += 0.05
	assert_near(taken, expected, 0.06, "%.2f minutes for %d tiles" % [taken, path.size()])


func test_the_size_of_the_time_step_does_not_matter() -> void:
	var person := _adult()
	var start_tile := person.position
	var start_offset := person.sub_tile_offset
	var target := _open_tile(7)
	var places: Array[Vector2] = []
	for step: float in [0.05, 0.5, 3.0]:
		session.people.move(person.id, start_tile, start_offset)
		movement.walk_to(person.id, target)
		finder.serve(1_000_000)
		var elapsed := 0.0
		while elapsed < 9.0 - 0.0001:
			movement.step(step)
			elapsed += step
		places.append(person.world2d())
		movement.stop(person.id)
	assert_true(places[0].distance_to(places[1]) < 0.001, "%s vs %s" % [places[0], places[1]])
	assert_true(places[0].distance_to(places[2]) < 0.001, "%s vs %s" % [places[0], places[2]])
	assert_true(places[0].distance_to(Vector2(start_tile) + start_offset) > 2.0, "and they did walk")


func test_a_walker_faces_the_way_they_go() -> void:
	var person := _adult()
	var target := _open_tile(6)
	movement.walk_to(person.id, target)
	finder.serve(1_000_000)
	var before := person.world2d()
	movement.step(1.0)
	var heading := (person.world2d() - before).normalized()
	assert_true(Vector2.from_angle(person.facing).dot(heading) > 0.99)


func test_the_young_the_old_and_the_sick_walk_slower() -> void:
	var adult := _adult()
	var child := _of(PersonData.LifeStage.CHILD)
	var elder := _of(PersonData.LifeStage.ELDER)
	adult.health = 1.0
	child.health = 1.0
	elder.health = 1.0
	var open := _open_tile(5)
	var full := movement.speed_of(adult, open)
	assert_near(full, Config.people.walk_tiles_per_minute * finder.speed_factor(open), 0.0001)
	assert_near(movement.speed_of(child, open), full * Config.people.walk_factor_child, 0.0001)
	assert_near(movement.speed_of(elder, open), full * Config.people.walk_factor_elder, 0.0001)
	adult.health = 0.0
	assert_near(movement.speed_of(adult, open), full * 0.5, 0.0001, "even the very sick still move")
	adult.health = 1.0
	# Through a tree it is slower than across the open.
	var tree: PropData = null
	for p in session.props.all_props():
		if p.kind == PropData.Kind.TREE and session.world.get_water(p.tile) == 0.0:
			tree = p
			break
	assert_true(movement.speed_of(adult, tree.tile) < full * 0.5)


func test_nobody_walks_through_what_cannot_be_walked() -> void:
	var person := _adult()
	var hut := session.props.get_prop(session.start.hut_ids[1])
	# To the far side of a hut: around it.
	var beyond := hut.tile + (hut.tile - _home()).sign() * 2
	if not finder.can_stand(beyond):
		beyond = finder.standable_near(beyond, 1)[0]
	movement.walk_to(person.id, beyond)
	var steps := 0
	while movement.is_walking(person.id) and steps < 2000:
		_run(0.25)
		steps += 1
		assert_true(finder.can_stand(person.position), "on walkable ground all the way (%s)" % person.position)
		assert_null(session.props.prop_at(person.position) if session.props.prop_at(person.position) != null
			and session.props.prop_at(person.position).kind == PropData.Kind.HUT else null, "never inside a hut")
		assert_ne(person.position, _home(), "never in the fire")
	assert_eq(arrived, [person.id] as Array[int])
	# Sent to the hut itself: to its side.
	movement.walk_to(person.id, hut.tile)
	_run(60.0)
	assert_eq(arrived.size(), 2)
	var beside := person.position - hut.tile
	assert_eq(maxi(absi(beside.x), absi(beside.y)), 1, "beside the hut")


func test_no_way_is_reported_and_nobody_moves() -> void:
	var person := _adult()
	var from := person.world2d()
	var far := _across_the_river()
	assert_true(movement.walk_to(person.id, far), "they may be asked")
	_run(5.0)
	assert_eq(blocked, [person.id] as Array[int], "but there is no way")
	assert_eq(arrived.size(), 0)
	assert_false(movement.is_walking(person.id))
	assert_eq(person.world2d(), from)
	# Nonsense is refused outright.
	assert_false(movement.walk_to(person.id, Vector2i(500, 500)))
	assert_false(movement.walk_to(999_999, _home()))
	assert_eq(movement.walking_count(), 0)


func test_stopping_and_changing_one_s_mind() -> void:
	var person := _adult()
	var first := _open_tile(8)
	var second := _open_tile(4)
	movement.walk_to(person.id, first)
	_run(3.0)
	movement.walk_to(person.id, second)
	assert_eq(movement.target_of(person.id), second)
	_run(80.0)
	assert_eq(arrived, [person.id] as Array[int], "one journey, one arrival")
	assert_eq(person.position, second)
	movement.walk_to(person.id, first)
	_run(2.0)
	var where := person.world2d()
	movement.stop(person.id)
	_run(5.0)
	assert_eq(person.world2d(), where, "stopped means stopped")
	assert_eq(arrived.size(), 1)
	assert_null(movement.target_of(person.id))
	assert_eq(movement.remaining_path(person.id).size(), 0)
	# Stopped before the way was known: the answer is ignored.
	movement.walk_to(person.id, first)
	movement.stop(person.id)
	assert_eq(finder.queue_size(), 0, "the question is withdrawn")
	_run(5.0)
	assert_eq(person.world2d(), where)


func test_a_way_that_closes_is_found_again() -> void:
	var person := _adult()
	var target := _open_tile(8)
	movement.walk_to(person.id, target)
	_run(2.0)
	var way := movement.remaining_path(person.id)
	assert_true(way.size() > 4)
	# A hut appears in the way.
	var in_the_way := way[2]
	var hut := PropData.new()
	hut.id = session.ids.next_id()
	hut.kind = PropData.Kind.HUT
	hut.tile = in_the_way
	session.props.add(hut)
	var steps := 0
	while movement.is_walking(person.id) and steps < 2000:
		_run(0.25)
		steps += 1
		assert_ne(person.position, in_the_way, "around, not through")
	assert_eq(arrived, [person.id] as Array[int])
	assert_eq(person.position, target)


func test_a_way_that_closes_for_good_ends_the_walk() -> void:
	var person := _adult()
	var target := _open_tile(8)
	movement.walk_to(person.id, target)
	_run(2.0)
	# Deep water all around the place they are going to.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if maxi(absi(dx), absi(dy)) == 2:
				session.world.set_water(target + Vector2i(dx, dy), 1.0)
				finder.mark_dirty(target + Vector2i(dx, dy))
	_run(120.0)
	assert_eq(blocked, [person.id] as Array[int])
	assert_eq(arrived.size(), 0)
	assert_true(session.world.get_water(person.position) < 0.2, "they stopped on this side of the water")


func test_everyone_can_be_called_together() -> void:
	var ids: Array[int] = []
	for p in session.people.all_people():
		ids.append(p.id)
	var spot := _open_tile(7)
	assert_eq(movement.gather(ids, spot), ids.size())
	assert_eq(movement.walking_count(), ids.size())
	assert_eq(finder.queue_size(), ids.size())
	_run(200.0, 0.5)
	assert_eq(arrived.size(), ids.size(), "everyone got there")
	var places := {}
	for p in session.people.all_people():
		assert_false(places.has(p.position), "each on a tile of their own")
		places[p.position] = true
		assert_true((p.position - spot).length() <= 3.0, "close around the spot")
		assert_true(finder.can_stand(p.position))


func test_someone_who_leaves_the_world_stops_walking() -> void:
	var person := _adult()
	movement.walk_to(person.id, _open_tile(8))
	_run(1.0)
	session.people.remove(person.id)
	assert_false(movement.is_walking(person.id))
	_run(5.0) # nothing to crash on
	assert_eq(arrived.size(), 0)


func test_many_walkers_are_cheap_and_served_within_the_budget() -> void:
	# 20 people (the M4 target), all sent somewhere at once.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	while session.people.size() < 20:
		var p := PersonData.new()
		p.id = session.ids.next_id()
		p.birth_tick = -30 * YEAR
		p.position = finder.standable_near(_home() + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4)), 1)[0]
		session.people.add(p)
	var spots: Array[Vector2i] = [_open_tile(8), _open_tile(6), _open_tile(5), _open_tile(7)]
	var i := 0
	for p in session.people.all_people():
		movement.walk_to(p.id, finder.standable_near(spots[i % spots.size()] + Vector2i(i % 3, i % 2), 1)[0])
		i += 1
	assert_eq(finder.queue_size(), 20)
	# One millisecond per frame: how many frames until everyone knows the way?
	var frames := 0
	var worst := 0
	while finder.queue_size() > 0 and frames < 100:
		finder.serve(1000)
		worst = maxi(worst, finder.last_serve_usec)
		frames += 1
	assert_eq(finder.queue_size(), 0)
	var started := Time.get_ticks_usec()
	for frame in 200:
		movement.step(1.0 / 30.0)
	var per_frame_ms := (Time.get_ticks_usec() - started) / 200.0 / 1000.0
	print("    movement: 20 ways served in %d frames (worst %.2f ms); 20 walkers %.3f ms per frame" % [frames, worst / 1000.0, per_frame_ms])
	assert_true(frames <= 20, "%d frames" % frames)
	assert_true(per_frame_ms < 0.5, "%.3f ms per frame" % per_frame_ms)


# --- in the running session -----------------------------------------------------------------------

func test_the_session_walks_people_as_time_passes() -> void:
	var person := _adult()
	var from := person.world2d()
	var target := _open_tile(5)
	session.set_process(true)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	movement.walk_to(person.id, target)
	await wait_real_ms(400)
	assert_true(person.world2d().distance_to(from) > 0.5, "time passes, people walk (%.2f tiles)" % person.world2d().distance_to(from))
	# Paused: nobody moves.
	session.clock.set_speed(GameClock.SPEED_PAUSE)
	await wait_frames(2)
	var where := person.world2d()
	await wait_real_ms(200)
	assert_eq(person.world2d(), where, "the world stands still when paused")
	assert_eq(session.clock.last_advance_minutes, 0.0)
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	await wait_real_ms(2500)
	assert_eq(arrived, [person.id] as Array[int])
	# Closing the world stops everyone.
	movement.walk_to(person.id, _open_tile(8))
	session.shutdown()
	assert_eq(movement.walking_count(), 0)


func test_a_new_world_in_the_same_session_has_its_own_ways() -> void:
	var person := _adult()
	movement.walk_to(person.id, _open_tile(6))
	var old_home := _home()
	session.create_new(777)
	session.set_process(false)
	assert_eq(movement.walking_count(), 0, "nobody from the old world is still walking")
	assert_eq(finder.queue_size(), 0)
	assert_true(_home() != old_home)
	assert_false(finder.can_stand(_home()), "the graph is the new world's (its fire, its huts)")
	var someone := _adult()
	movement.walk_to(someone.id, _open_tile(4))
	_run(60.0)
	assert_eq(arrived, [someone.id] as Array[int])
