extends TestCase
## Bridges across (M12 follow-up, at the owner's word): land near the fire cut
## off by water calls for a crossing, planned bank to bank and built tile by
## tile from the near bank — over deep water too — until it reaches the far
## side; then the far side can be walked to, and no more is wanted.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var planner: SettlementPlanner
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
	planner = session.planner
	# Nothing else called for: only the crossing.
	_knob(Config.construction, &"homes_spare_least", -1000)
	_knob(Config.construction, &"storage_room_least", -1000)
	_knob(Config.construction, &"spoiled_from", 1_000_000)
	_knob(Config.construction, &"well_from", 1_000_000)


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


## The next day (the crossing is worked out once a day).
func _next_day() -> void:
	session.clock.tick += DAY


## Builds a project to the end (the wood brought, the strokes worked).
func _build(p: Dictionary) -> PropData:
	var builder := session.people.all_people()[0]
	session.construction.deliver(p, &"wood", 10)
	var guard := 0
	while not session.construction.work(p, builder, 30.0, session.clock.tick) and guard < 200:
		guard += 1
	return session.props.prop_at(p["tile"])


func test_a_crossing_bank_to_bank() -> void:
	var fire := session.start.settlement_tile
	var across := planner.crossing(session.clock.tick)
	assert_false(across.is_empty(), "the river cuts off land near the fire")
	var tiles: Array = across["tiles"]
	assert_true(tiles.size() >= 2 and tiles.size() <= Config.construction.crossing_span_most, "%d tiles" % tiles.size())
	var axis := Crossing.axis_of(int(across["turn"]))
	var step: Vector2i = tiles[1] - tiles[0]
	assert_eq(absi(step.x) + absi(step.y), 1, "straight across")
	assert_eq(Vector2i(absi(step.x), absi(step.y)), axis, "turned along its way")
	var near_bank: Vector2i = tiles[0] - step
	var far_bank: Vector2i = tiles[-1] + step
	assert_true(session.pathfinder.is_reachable(fire, near_bank), "from land they can walk to")
	assert_false(session.pathfinder.is_reachable(fire, far_bank), "to land they cannot")
	var deep := 0
	for tile: Vector2i in tiles:
		assert_true(session.world.get_water(tile) > Pathfinder.WET_DEPTH, "water all the way")
		if session.world.get_water(tile) > Pathfinder.WADE_DEPTH * session.world.height_step:
			deep += 1
	assert_true(deep > 0, "over deep water too (%d deep)" % deep)
	assert_has(planner.needs(session.clock.tick), &"bridge")
	# Tile by tile, the near bank first; one at a time.
	for i in tiles.size():
		var p := planner.plan(session.clock.tick)
		assert_eq(str(p.get("def", "")), "bridge", "segment %d" % i)
		assert_eq(p["tile"], tiles[i], "the next tile out")
		assert_true(planner.plan(session.clock.tick).is_empty(), "one at a time")
		# The builder works it from the bank or from the deck laid before.
		assert_true(session.pathfinder.can_stand(tiles[i] - step), "somewhere to stand beside segment %d" % i)
		var bridge := _build(p)
		assert_eq(bridge.variant, PropData.BRIDGE_DONE)
		assert_true(session.pathfinder.can_stand(tiles[i]), "its deck can be stood on")
		_next_day()
	# Across: the far side can be walked to, and no more is wanted.
	assert_true(session.pathfinder.is_reachable(fire, far_bank), "over the bridge")
	var path := session.pathfinder.find_path(fire, far_bank)
	for tile: Vector2i in tiles:
		assert_true(path.has(tile), "the way leads over it")
	assert_true(planner.crossing(session.clock.tick).is_empty(), "nothing more cut off")
	assert_false(planner.needs(session.clock.tick).has(&"bridge"))
	# Level with the higher bank: someone on it stands on the deck.
	var middle: PropData = session.props.prop_at(tiles[tiles.size() / 2])
	var banks := maxi(session.world.get_height(near_bank), session.world.get_height(far_bank))
	assert_eq(Crossing.deck_level(session.world, session.props, middle), maxi(banks, session.world.get_height(middle.tile)))
	var view := PeopleView.new()
	view.props = session.props
	view._world = session.world
	var walker := session.people.all_people()[0]
	walker.position = middle.tile
	assert_near(view.ground_position(walker).y, Crossing.deck_y(session.world, session.props, middle), 0.001)
	assert_true(view.ground_position(walker).y > (session.world.get_height(middle.tile) * session.world.height_step
		+ session.world.get_water(middle.tile)), "above the water")
	view.free()
	# Drawn with posts down to the bed.
	var placed := PropMesher.placements(session.world, session.props, WorldCoords.tile_to_chunk(middle.tile, session.world.chunk_size),
		PropMeshLibrary.new())
	assert_true(placed.size() >= 5, "the deck and its posts")


func test_a_one_tile_bridge_is_carried_on() -> void:
	var across := planner.crossing(session.clock.tick)
	var tiles: Array = across["tiles"]
	# An old bridge (M12.2) stands on the first tile of the way over.
	var p := session.construction.start(&"bridge", tiles[0], session.clock.tick, int(across["turn"]), session.settlement.id)
	_build(p)
	_next_day()
	var again := planner.crossing(session.clock.tick)
	assert_eq(again["tiles"], tiles, "the same way over, carried on")
	var next := planner.plan(session.clock.tick)
	assert_eq(next["tile"], tiles[1], "from where it stopped")


func test_a_crossing_needs_land_cut_off_and_a_short_way() -> void:
	_knob(Config.construction, &"crossing_span_most", 1)
	assert_true(planner.crossing(session.clock.tick).is_empty(), "too wide to bridge")
	_knob(Config.construction, &"crossing_span_most", 8)
	_knob(Config.construction, &"cut_off_least", 1_000_000)
	_next_day()
	assert_true(planner.crossing(session.clock.tick).is_empty(), "not enough land cut off to want it")
	_knob(Config.construction, &"cut_off_least", 12)
	_knob(Config.construction, &"crossing_from_people", 1000)
	_next_day()
	assert_true(planner.crossing(session.clock.tick).is_empty(), "too few to take it on")


func test_only_water_up_to_the_deck_harms_it() -> void:
	var across := planner.crossing(session.clock.tick)
	var tiles: Array = across["tiles"]
	var deepest: Vector2i = tiles[0]
	for tile: Vector2i in tiles:
		if session.world.get_water(tile) > session.world.get_water(deepest):
			deepest = tile
	var p := session.construction.start(&"bridge", deepest, session.clock.tick, int(across["turn"]), session.settlement.id)
	var bridge := _build(p)
	assert_false(Crossing.flooded(session.world, session.props, bridge), "the river under it is no flood")
	var deck := Crossing.deck_y(session.world, session.props, bridge)
	var bed := session.world.get_height(deepest) * session.world.height_step
	session.world.set_water(deepest, deck - bed + 0.05)
	assert_true(Crossing.flooded(session.world, session.props, bridge), "water over the deck")
	# Worn through, it is washed away: nothing is left standing.
	session.construction.damage(bridge.id, PropData.SOUND, &"flood", session.clock.tick)
	assert_null(session.props.prop_at(deepest), "washed away")
	var gone := session.events.of_type(&"building_ruined")
	assert_eq(EventText.text(gone[-1], session.people, session.events), "The bridge has been washed away")


func test_four_stubs_in_a_row_make_one_crossing() -> void:
	# As on the owner's phone: four one-tile bridges side by side along a bank.
	var across := planner.crossing(session.clock.tick)
	var tiles: Array = across["tiles"]
	var turn := int(across["turn"])
	var axis := Crossing.axis_of(turn)
	var side := Vector2i(axis.y, axis.x) # (along the bank)
	var stubs: Array[Vector2i] = []
	for i in range(-1, 3):
		var tile: Vector2i = tiles[0] + side * i
		if session.world.get_water(tile) > Pathfinder.WET_DEPTH and session.props.prop_at(tile) == null:
			_build(session.construction.start(&"bridge", tile, session.clock.tick, turn, session.settlement.id))
			stubs.append(tile)
	assert_true(stubs.size() >= 2, "stubs along the bank (%d)" % stubs.size())
	# One of them is carried across, segment by segment.
	var built := 0
	for day in 20:
		_next_day()
		var p := planner.plan(session.clock.tick)
		if p.is_empty():
			break
		_build(p)
		built += 1
	assert_true(built >= 2, "carried on (%d segments)" % built)
	_next_day()
	assert_true(planner.crossing(session.clock.tick).is_empty(), "then no more: the others stay as they are")
	# (No land is cut off any more: the far side is walked to over the one carried across.)
	var decks := 0
	for prop in session.props.all_props():
		if Crossing.deck_at(session.props, prop.tile) != null:
			decks += 1
	assert_eq(decks, stubs.size() + built, "the stubs and the one crossing, nothing more")
