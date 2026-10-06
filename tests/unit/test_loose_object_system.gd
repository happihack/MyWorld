extends TestCase
## LooseObjectSystem: how loose objects fall, bounce, roll, stop and collide.

const STEP := LooseObjectSystem.STEP_SECONDS

var world: WorldData
var registry: LooseObjectRegistry
var props: PropRegistry
var system: LooseObjectSystem
var ids: IdAllocator
var landings: Array = [] # [id, impact_speed]
var bumps: Array = [] # [id, speed]
var settles: Array = [] # id


func before_each() -> void:
	# Flat 32x32 world at height level 2 (step 0.5 -> ground at y = 1.0).
	world = WorldData.new(Rect2i(-16, -16, 32, 32), 16)
	world.height_step = 0.5
	world.generator = func(coord: Vector2i) -> ChunkData:
		var c := ChunkData.new(coord, 16)
		c.height.fill(2)
		c.mark_pristine()
		return c
	var index := SpatialIndex.new(SpatialIndex.FINE_CELL_TILES) # as in a session
	registry = LooseObjectRegistry.new(16, index)
	props = PropRegistry.new(16, index)
	ids = IdAllocator.new()
	system = LooseObjectSystem.new()
	add_child(system)
	system.set_process(false) # tests step time themselves
	system.bind(world, registry, props)
	landings.clear()
	bumps.clear()
	settles.clear()
	system.landed.connect(func(id: int, speed: float) -> void: landings.append([id, speed]))
	system.bumped.connect(func(id: int, speed: float) -> void: bumps.append([id, speed]))
	system.settled.connect(func(id: int) -> void: settles.append(id))


func after_each() -> void:
	system.queue_free()


func _object(kind: LooseObject.Kind, at: Vector2, height: float = 0.0) -> LooseObject:
	var o := LooseObject.new()
	o.id = ids.next_id()
	o.kind = kind
	o.position = at
	o.height_offset = height
	registry.add(o)
	return o


func _prop(kind: PropData.Kind, tile: Vector2i) -> PropData:
	var p := PropData.new()
	p.id = ids.next_id()
	p.kind = kind
	p.tile = tile
	assert_true(props.add(p))
	return p


## Steps until nothing moves; returns the seconds it took.
func _settle(max_seconds: float = 20.0) -> float:
	var t := 0.0
	while system.moving_count() > 0 and t < max_seconds:
		system.step(STEP)
		t += STEP
	return t


func _world_y(o: LooseObject) -> float:
	return o.world_position(world).y


## A hillside falling toward +X: one level lower per tile from x = 0 to x = 8,
## level ground on both sides. `per_tile` levels of drop per tile.
func _hillside(per_tile: int = 1) -> void:
	world.height_step = 0.4 # as in the game
	for x in range(-16, 16):
		var level := 2 + 8 * per_tile
		if x >= 0:
			level = maxi(2 + (8 - x) * per_tile, 2)
		for z in range(-16, 16):
			world.set_height(Vector2i(x, z), level)


# --- falling and bouncing -------------------------------------------------------------------

func test_a_dropped_object_falls_and_comes_to_rest() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 0.55)
	assert_true(system.drop(rock.id))
	assert_eq(rock.state, LooseObject.State.FALLING)
	assert_true(system.is_moving(rock.id))
	system.step(STEP)
	assert_true(rock.height_offset < 0.55 and rock.height_offset > 0.4, "it has started to fall")
	var seconds := _settle()
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0, "exactly on the ground")
	assert_eq(rock.velocity, Vector3.ZERO)
	assert_eq(rock.position, Vector2(2.5, 2.5), "straight down")
	assert_true(seconds > 0.12 and seconds < 0.7, "quick and weighty (%.2f s)" % seconds)
	assert_eq(landings.size(), 1, "one audible landing; the small bounce after it is silent")
	var expected := sqrt(2.0 * LooseObjectSystem.GRAVITY * 0.55)
	assert_near(landings[0][1], expected, expected * 0.15, "impact speed from the height it fell")
	assert_eq(settles, [rock.id])
	assert_eq(system.moving_count(), 0)


func test_things_bounce_less_each_time_and_by_their_kind() -> void:
	var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(2.5, 2.5), 2.0)
	system.drop(pebble.id)
	var peaks: Array[float] = []
	var rising := false
	var last := pebble.height_offset
	for i in 600:
		system.step(STEP)
		if pebble.height_offset > last:
			rising = true
		elif rising:
			peaks.append(last)
			rising = false
		last = pebble.height_offset
		if not system.is_moving(pebble.id):
			break
	assert_true(peaks.size() >= 2, "it bounces more than once (%s)" % [peaks])
	assert_true(peaks[0] < 2.0 * 0.3, "the first bounce is much lower than the drop (%.2f)" % peaks[0])
	assert_true(peaks[1] < peaks[0], "each bounce lower than the last")
	assert_eq(pebble.state, LooseObject.State.RESTING, "and it stops")
	# A boulder hardly bounces at all.
	var boulder := _object(LooseObject.Kind.BOULDER, Vector2(8.5, 2.5), 2.0)
	system.drop(boulder.id)
	var boulder_peak := 0.0
	var hit := false
	for i in 600:
		system.step(STEP)
		if boulder.height_offset <= 0.0:
			hit = true
		elif hit:
			boulder_peak = maxf(boulder_peak, boulder.height_offset)
		if not system.is_moving(boulder.id):
			break
	assert_true(boulder_peak < peaks[0] * 0.25, "boulder %.3f vs pebble %.3f" % [boulder_peak, peaks[0]])


func test_a_higher_drop_hits_harder() -> void:
	var low := _object(LooseObject.Kind.ROCK, Vector2(1.5, 1.5), 0.3)
	var high := _object(LooseObject.Kind.ROCK, Vector2(6.5, 1.5), 2.0)
	system.drop(low.id)
	system.drop(high.id)
	_settle()
	assert_eq(landings[0][0], low.id, "the lower one lands first")
	var hardest := {low.id: 0.0, high.id: 0.0}
	for landing: Array in landings:
		hardest[landing[0]] = maxf(hardest[landing[0]], landing[1])
	assert_true(hardest[high.id] > hardest[low.id] * 2.0)


func test_motion_does_not_depend_on_the_frame_rate() -> void:
	var results: Array[Vector2] = []
	for frame: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]:
		var rock := _object(LooseObject.Kind.ROCK, Vector2(-8.5, 5.5), 0.6)
		system.drop(rock.id, Vector3(5.0, 0.0, 1.5))
		for i in int(8.0 / frame):
			system.step(frame)
		assert_eq(rock.state, LooseObject.State.RESTING)
		results.append(rock.position)
		registry.remove(rock.id)
	assert_true(results[0].distance_to(results[1]) < 0.02, "30 vs 60 FPS: %s vs %s" % [results[0], results[1]])
	assert_true(results[1].distance_to(results[2]) < 0.02, "60 vs 144 FPS: %s vs %s" % [results[1], results[2]])


func test_a_long_frame_does_not_break_the_fall() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 0.55)
	system.drop(rock.id)
	system.step(5.0) # a hitch: only a few steps are made up
	assert_true(rock.height_offset > 0.0, "it did not jump to the end")
	_settle()
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_near(rock.height_offset, 0.0, 0.0)


# --- rolling, friction, slopes --------------------------------------------------------------

func test_a_thrown_rock_rolls_on_and_stops() -> void:
	# (Thrown hard: on the ground it soon stops — the owner, 2026-10-06: small
	# rocks slid much too far.)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(-6.5, 0.5), 0.5)
	system.drop(rock.id, Vector3(9.0, 0.0, 0.0))
	_settle()
	var travelled := rock.position.x + 6.5
	assert_true(travelled > 1.5 and travelled < 5.0, "it rolls a few tiles, not a field's length (%.2f)" % travelled)
	assert_near(rock.position.y, 0.5, 0.001, "in a straight line")
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(rock.velocity, Vector3.ZERO)
	# Pushed along the ground, a log drags: it stops much sooner than a rock.
	var slid := _object(LooseObject.Kind.ROCK, Vector2(-6.5, -6.5))
	system.push(slid.id, Vector3(5.0, 0.0, 0.0))
	var log := _object(LooseObject.Kind.LOG, Vector2(-6.5, 6.5))
	system.push(log.id, Vector3(5.0, 0.0, 0.0))
	_settle()
	var rock_slid := slid.position.x + 6.5
	assert_true(log.position.x + 6.5 < rock_slid * 0.7, "log %.2f vs rock %.2f" % [log.position.x + 6.5, rock_slid])


func test_a_higher_block_is_a_wall() -> void:
	for z in range(-16, 16):
		world.set_height(Vector2i(4, z), 5)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(1.5, 0.5))
	system.push(rock.id, Vector3(9.0, 0.0, 0.0))
	var furthest := rock.position.x
	var came_back := false
	for i in 600:
		system.step(STEP)
		furthest = maxf(furthest, rock.position.x)
		if rock.velocity.x < -0.1:
			came_back = true
		if not system.is_moving(rock.id):
			break
	assert_true(furthest < 4.0, "never inside the wall (%.3f)" % furthest)
	assert_true(furthest > 3.6, "but it reached it")
	assert_true(came_back, "and bounced back")
	assert_true(bumps.size() >= 1 and bumps[0][1] > 2.0, "the knock is reported (%s)" % [bumps])
	assert_near(rock.height_offset, 0.0, 0.0)


func test_rolling_off_an_edge_drops_to_the_lower_ground() -> void:
	for x in range(3, 16):
		for z in range(-16, 16):
			world.set_height(Vector2i(x, z), 0) # a cliff: two levels down
	var rock := _object(LooseObject.Kind.ROCK, Vector2(0.5, 0.5))
	system.push(rock.id, Vector3(8.0, 0.0, 0.0))
	var lowest_y := INF
	for i in 900:
		system.step(STEP)
		lowest_y = minf(lowest_y, _world_y(rock))
		if not system.is_moving(rock.id):
			break
	assert_true(rock.position.x > 3.0, "it went over the edge (%.2f)" % rock.position.x)
	assert_near(rock.height_offset, 0.0, 0.0, "and lies on the lower ground")
	assert_near(_world_y(rock), 0.0, 0.0001)
	assert_true(lowest_y >= -0.0001, "never below the ground it fell to")
	assert_true(landings.size() >= 1, "it landed audibly")


func test_a_rock_set_rolling_on_a_hillside_ends_at_the_bottom() -> void:
	_hillside(1)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(1.5, 0.5))
	system.push(rock.id, Vector3(1.5, 0.0, 0.0)) # a nudge downhill
	var seconds := _settle(40.0)
	assert_eq(rock.state, LooseObject.State.RESTING, "it stops (after %.1f s)" % seconds)
	assert_true(rock.position.x >= 8.0, "at the bottom of the slope (x = %.2f)" % rock.position.x)
	assert_eq(world.get_height(rock.tile()), 2, "on the level ground")
	assert_near(rock.height_offset, 0.0, 0.0)
	assert_true(landings.size() >= 3, "tumbling down the steps (%d landings)" % landings.size())


func test_a_rock_left_alone_on_a_gentle_slope_stays() -> void:
	_hillside(1)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(3.5, 0.5), 0.5)
	system.drop(rock.id)
	_settle()
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(rock.tile(), Vector2i(3, 0), "one level per tile holds a resting rock")


func test_nothing_rests_on_a_steep_slope() -> void:
	_hillside(2)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(3.5, 0.5), 0.5)
	system.drop(rock.id)
	var seconds := _settle(40.0)
	assert_eq(rock.state, LooseObject.State.RESTING, "it stops (after %.1f s)" % seconds)
	assert_true(rock.position.x >= 8.0, "it slid to the bottom (x = %.2f)" % rock.position.x)


func test_everything_stays_inside_the_box() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(14.5, 14.5), 0.5)
	system.drop(rock.id, Vector3(12.0, 0.0, 9.0))
	var bounds := Rect2(world.bounds)
	for i in 600:
		system.step(STEP)
		assert_true(bounds.has_point(rock.position), "step %d: %s" % [i, rock.position])
		if not system.is_moving(rock.id):
			break
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_true(bumps.size() >= 1, "it hit the wall of the box")


# --- things in the way ------------------------------------------------------------------------

func test_a_rolling_rock_bounces_off_a_hut() -> void:
	var hut := _prop(PropData.Kind.HUT, Vector2i(4, 0))
	var rock := _object(LooseObject.Kind.ROCK, Vector2(0.5, 0.5))
	system.push(rock.id, Vector3(9.0, 0.0, 0.0))
	var closest := INF
	for i in 600:
		system.step(STEP)
		closest = minf(closest, rock.position.distance_to(hut.position2d()))
		if not system.is_moving(rock.id):
			break
	var touching := hut.collision_radius() + rock.radius()
	assert_true(closest >= touching - 0.001, "never inside the hut (%.3f, touching at %.3f)" % [closest, touching])
	assert_true(closest < touching + 0.1, "but it reached the wall")
	assert_true(rock.position.x < hut.position2d().x, "and came back from it")
	assert_true(bumps.size() >= 1)


func test_bushes_give_way_and_things_can_fly_over_low_props() -> void:
	_prop(PropData.Kind.BUSH, Vector2i(3, 0))
	var rock := _object(LooseObject.Kind.ROCK, Vector2(0.5, 0.5))
	system.push(rock.id, Vector3(10.0, 0.0, 0.0))
	_settle()
	assert_true(rock.position.x > 4.0, "straight through the bush (%.2f)" % rock.position.x)
	assert_eq(bumps.size(), 0)
	# Thrown high over the campfire: no knock on the way.
	var fire := _prop(PropData.Kind.CAMPFIRE, Vector2i(3, 6))
	var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(1.5, 6.5), 3.5)
	system.drop(pebble.id, Vector3(6.0, 0.0, 0.0))
	for i in 30:
		system.step(STEP)
	assert_true(pebble.position.x > fire.position2d().x, "it passed over the fire")
	assert_eq(bumps.size(), 0)


func test_dropping_something_into_a_hut_pushes_it_out() -> void:
	var hut := _prop(PropData.Kind.HUT, Vector2i(4, 4))
	var rock := _object(LooseObject.Kind.ROCK, hut.position2d() + Vector2(0.1, 0.05), 0.4)
	system.drop(rock.id)
	_settle()
	assert_true(rock.position.distance_to(hut.position2d()) >= hut.collision_radius() + rock.radius() - 0.001)
	assert_eq(rock.state, LooseObject.State.RESTING)


func test_a_rolling_boulder_knocks_a_pebble_away() -> void:
	var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(3.5, 0.5))
	var boulder := _object(LooseObject.Kind.BOULDER, Vector2(0.5, 0.5))
	system.push(boulder.id, Vector3(4.0, 0.0, 0.0))
	var pebble_top_speed := 0.0
	var boulder_speed_at_hit := 0.0
	for i in 900:
		system.step(STEP)
		if pebble_top_speed == 0.0 and pebble.velocity.x > 0.0:
			boulder_speed_at_hit = boulder.velocity.x
		pebble_top_speed = maxf(pebble_top_speed, pebble.velocity.x)
		if system.moving_count() == 0:
			break
	assert_true(pebble_top_speed > boulder_speed_at_hit, "the pebble shoots off faster than the boulder came (%.2f vs %.2f)" % [pebble_top_speed, boulder_speed_at_hit])
	assert_true(boulder_speed_at_hit > 1.0, "the boulder barely notices (%.2f)" % boulder_speed_at_hit)
	assert_true(pebble.position.x > 3.6, "the pebble moved (%.2f)" % pebble.position.x)
	assert_true(pebble.position.x > boulder.position.x, "and stays ahead of the boulder")
	assert_eq(pebble.state, LooseObject.State.RESTING)
	assert_eq(boulder.state, LooseObject.State.RESTING)
	assert_true(pebble.position.distance_to(boulder.position) >= pebble.radius() + boulder.radius() - 0.001, "they do not end up inside each other")
	assert_has(settles, pebble.id)


func test_a_pebble_bounces_off_a_boulder() -> void:
	var boulder := _object(LooseObject.Kind.BOULDER, Vector2(3.5, 0.5))
	var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(0.5, 0.5))
	system.push(pebble.id, Vector3(8.0, 0.0, 0.0))
	var came_back := false
	for i in 900:
		system.step(STEP)
		if pebble.velocity.x < -0.2:
			came_back = true
		if system.moving_count() == 0:
			break
	assert_true(came_back, "the pebble bounces back")
	assert_near(boulder.position.x, 3.5, 0.02, "the boulder hardly moves (%.3f)" % boulder.position.x)


func test_dropping_one_thing_onto_another_leaves_them_side_by_side() -> void:
	var below := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5))
	var above := _object(LooseObject.Kind.ROCK, Vector2(2.56, 2.52), 0.2)
	system.drop(above.id)
	_settle()
	assert_true(above.position.distance_to(below.position) >= above.radius() + below.radius() - 0.001)
	assert_near(above.height_offset, 0.0, 0.0)
	assert_near(below.height_offset, 0.0, 0.0)
	assert_eq(system.moving_count(), 0)


func test_an_object_in_hand_passes_through_everything() -> void:
	var held := _object(LooseObject.Kind.ROCK, Vector2(3.5, 0.5), 0.1)
	system.hold(held.id)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(0.5, 0.5))
	system.push(rock.id, Vector3(7.0, 0.0, 0.0))
	_settle()
	assert_true(rock.position.x > 4.0, "rolled right through where the held one is")
	assert_eq(held.position, Vector2(3.5, 0.5))
	assert_eq(held.state, LooseObject.State.HELD)
	assert_false(system.push(held.id, Vector3(1, 0, 0)), "and cannot be pushed")


func test_pushed_off_a_ledge_while_resting_it_falls() -> void:
	for x in range(3, 16):
		for z in range(-16, 16):
			world.set_height(Vector2i(x, z), 0)
	# A pebble resting right at the edge; a boulder dropped beside it shoves it over.
	var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(2.93, 0.5))
	var boulder := _object(LooseObject.Kind.BOULDER, Vector2(2.5, 0.5), 0.05)
	system.drop(boulder.id)
	_settle()
	assert_true(pebble.position.x >= 3.0, "over the edge (%.3f)" % pebble.position.x)
	assert_near(_world_y(pebble), 0.0, 0.0001, "and down on the lower ground, not hanging in the air")
	assert_eq(pebble.state, LooseObject.State.RESTING)


# --- holding, pushing, water -------------------------------------------------------------------

func test_a_held_object_stays_put() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 0.5)
	assert_true(system.hold(rock.id))
	assert_eq(rock.state, LooseObject.State.HELD)
	for i in 30:
		system.step(STEP)
	assert_near(rock.height_offset, 0.5, 0.0)
	assert_eq(system.moving_count(), 0)
	# Catching it in mid-air stops it.
	system.drop(rock.id, Vector3(3.0, 0.0, 0.0))
	system.step(STEP)
	system.step(STEP)
	var caught_at := rock.position
	system.hold(rock.id)
	for i in 30:
		system.step(STEP)
	assert_eq(rock.position, caught_at)
	assert_eq(rock.velocity, Vector3.ZERO)
	assert_eq(landings.size(), 0)


func test_resting_objects_are_left_alone() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5))
	_object(LooseObject.Kind.ROCK, Vector2(2.7, 2.5)) # overlapping, as generated rocks can
	var moves := [0]
	registry.object_moved.connect(func(_id: int) -> void: moves[0] += 1)
	for i in 100:
		system.step(STEP)
	assert_eq(moves[0], 0, "no jitter at rest")
	assert_eq(rock.state, LooseObject.State.RESTING)
	assert_eq(system.last_step_usec, 0, "and no work")


func test_push_wakes_a_resting_object() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5))
	assert_true(system.push(rock.id, Vector3(0.0, 0.0, 3.0)))
	assert_eq(rock.state, LooseObject.State.SLIDING)
	_settle()
	assert_true(rock.position.y > 2.8, "it rolled (%.2f)" % rock.position.y)
	assert_false(system.push(999, Vector3.ONE))
	assert_false(system.push(rock.id, Vector3(NAN, 0, 0)), "a broken velocity never gets in")
	assert_false(system.drop(rock.id, Vector3(INF, 0, 0)))
	assert_eq(rock.state, LooseObject.State.RESTING)
	# Absurd speeds are capped.
	system.push(rock.id, Vector3(500.0, 0.0, 0.0))
	assert_true(rock.velocity.length() <= LooseObjectSystem.MAX_SPEED + 0.001)


func test_unknown_and_removed_objects() -> void:
	assert_false(system.hold(999))
	assert_false(system.drop(999))
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 1.0)
	system.drop(rock.id)
	registry.remove(rock.id)
	system.step(STEP)
	assert_eq(system.moving_count(), 0)
	assert_eq(landings.size(), 0)


func test_stone_sinks_slowly_and_wood_floats() -> void:
	for x in range(5, 9):
		for z in range(5, 9):
			world.set_water(Vector2i(x, z), 0.6)
	var rock := _object(LooseObject.Kind.ROCK, Vector2(6.5, 6.5), 1.6)
	var wood := _object(LooseObject.Kind.LOG, Vector2(7.5, 7.5), 1.6)
	system.drop(rock.id)
	system.drop(wood.id)
	var fastest_sink := 0.0
	for i in 900:
		system.step(STEP)
		if rock.height_offset < 0.55:
			fastest_sink = maxf(fastest_sink, -rock.velocity.y)
		if system.moving_count() == 0:
			break
	assert_near(rock.height_offset, 0.0, 0.0, "on the river bed")
	assert_true(fastest_sink <= LooseObjectSystem.SINK_SPEED + 0.001, "water slows the fall (%.2f)" % fastest_sink)
	assert_near(wood.height_offset, 0.6, 0.0001, "on the surface")
	assert_near(system.rest_height(wood), 0.6, 0.0001)
	# On dry land a log lies on the ground like anything else.
	var dry := _object(LooseObject.Kind.LOG, Vector2(1.5, 1.5), 0.5)
	system.drop(dry.id)
	_settle()
	assert_near(dry.height_offset, 0.0, 0.0)


func test_afloat_in_still_water_it_comes_to_rest() -> void:
	# (Profiling, 2026-10-06: fruit afloat in still water over a sloping bed
	# never rested — moving for ever, a cost every frame.)
	system.bind(world, registry, props, func(_tile: Vector2i) -> Vector2: return Vector2.ZERO)
	for x in range(5, 9):
		for z in range(5, 9):
			world.set_height(Vector2i(x, z), 2 if x < 7 else 0) # a bed that falls away steeply under the water
			world.set_water(Vector2i(x, z), 0.8)
	var fruit := _object(LooseObject.Kind.FRUIT, Vector2(6.5, 6.5), 1.6)
	system.drop(fruit.id)
	for i in 900:
		system.step(STEP)
		if system.moving_count() == 0:
			break
	assert_eq(system.moving_count(), 0, "at rest, afloat")
	assert_eq(fruit.state, LooseObject.State.RESTING)
	assert_true(fruit.height_offset > 0.0, "on the surface")


func test_binding_another_world_forgets_what_was_moving() -> void:
	var rock := _object(LooseObject.Kind.ROCK, Vector2(2.5, 2.5), 1.0)
	system.drop(rock.id)
	system.bind(world, LooseObjectRegistry.new(16))
	assert_eq(system.moving_count(), 0)
	system.step(0.1) # nothing to do, nothing breaks


# --- robustness and cost ----------------------------------------------------------------------

func test_a_storm_of_thrown_things_always_settles_sanely() -> void:
	_hillside(1)
	_prop(PropData.Kind.HUT, Vector2i(-6, 2))
	_prop(PropData.Kind.TREE, Vector2i(11, -3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260930
	var thrown: Array[LooseObject] = []
	for i in 60:
		var kind := rng.randi_range(0, LooseObject.Kind.size() - 1) as LooseObject.Kind
		var o := _object(kind, Vector2(rng.randf_range(-14.0, 14.0), rng.randf_range(-14.0, 14.0)), rng.randf_range(0.0, 3.0))
		system.drop(o.id, Vector3(rng.randf_range(-12.0, 12.0), rng.randf_range(-2.0, 6.0), rng.randf_range(-12.0, 12.0)))
		thrown.append(o)
	var seconds := _settle(60.0)
	assert_eq(system.moving_count(), 0, "everything comes to rest (%.1f s)" % seconds)
	var bounds := Rect2(world.bounds)
	for o in thrown:
		assert_true(is_finite(o.position.x) and is_finite(o.position.y) and is_finite(o.height_offset), "finite")
		assert_true(bounds.has_point(o.position), "inside the box: %s" % o.position)
		assert_eq(o.state, LooseObject.State.RESTING)
		assert_near(o.height_offset, 0.0, 0.0001, "on the ground")
		assert_eq(o.velocity, Vector3.ZERO)


func test_the_same_throw_always_ends_the_same_way() -> void:
	_hillside(1)
	var ends: Array[Vector2] = []
	for run in 2:
		var rock := _object(LooseObject.Kind.ROCK, Vector2(-3.5, 1.5), 0.5)
		var pebble := _object(LooseObject.Kind.PEBBLE, Vector2(2.5, 1.6))
		system.drop(rock.id, Vector3(6.0, 0.0, 0.2))
		_settle(40.0)
		ends.append(rock.position)
		ends.append(pebble.position)
		registry.remove(rock.id)
		registry.remove(pebble.id)
	assert_eq(ends[0], ends[2])
	assert_eq(ends[1], ends[3])


func test_cost_with_many_resting_and_some_moving() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		_object(LooseObject.Kind.ROCK, Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-15.0, 15.0)))
	var movers: Array[LooseObject] = []
	for i in 10:
		var o := _object(LooseObject.Kind.ROCK, Vector2(rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0)), 1.0)
		movers.append(o)
	var worst := 0
	var total := 0
	var frames := 0
	for i in 120:
		if i % 20 == 0: # keep ten things in motion
			for o in movers:
				system.drop(o.id, Vector3(rng.randf_range(-8.0, 8.0), 3.0, rng.randf_range(-8.0, 8.0)))
		system.step(STEP)
		worst = maxi(worst, system.last_step_usec)
		total += system.last_step_usec
		frames += 1
	var average_ms := total / float(frames) / 1000.0
	print("    loose physics: 200 resting + 10 moving: %.3f ms per frame on average, worst %.3f ms" % [average_ms, worst / 1000.0])
	assert_true(average_ms < 1.0, "under a millisecond per frame (%.3f ms)" % average_ms)
