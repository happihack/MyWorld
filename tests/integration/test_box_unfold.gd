extends TestCase
## The Box Unfolds (M13.2, bible §8.6, D-05): when the civilization presses
## against the walls, a ring of chunks is added — the same land the generator
## would always have made there — and every part of the world grows with it;
## history says so, and the walls are seen to move. A new world can begin in
## a larger box.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var _knobs: Array = []


func test_the_box_unfolds_to_128_at_most() -> void:
	# (The owner, 2026-10-07: worlds are at most 128 × 128.)
	assert_eq(WorldConfig.new().max_world_tiles, 128)
	assert_eq(Config.world.max_world_tiles, 128)


func before_each() -> void:
	SaveManager.attach(null)
	SaveManager.open_next = {}
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	if is_instance_valid(session):
		session.queue_free()
	await wait_frames(1)


func _knob(resource: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([resource, knob, resource.get(knob)])
	resource.set(knob, value)


## Explorers have been everywhere along the walls.
func _explore_the_walls() -> void:
	var cells: Array = session.settlement.places().visited_cells()
	var b := session.world.bounds
	for y in range(b.position.y, b.end.y, Places.VISIT_CELL):
		for x in range(b.position.x, b.end.x, Places.VISIT_CELL):
			cells.append(Places.cell_of(Vector2i(x, y)))
	session.settlement.places().set_visited_cells(cells)


func test_unfold_extends_bounds_and_pathing() -> void:
	var old := session.world.bounds
	assert_eq(old.size, Vector2i(64, 64))
	var people := session.people.size()
	var tick := session.clock.tick
	var beyond := Vector2i(old.position.x - 8, 0)
	assert_false(session.world.is_in_bounds(beyond), "beyond the wall")
	assert_false(session.pathfinder.has_tile(beyond))
	var seen: Array = []
	session.unfolded.connect(func(a: Rect2i, b: Rect2i) -> void: seen.append([a, b]))
	assert_true(session.unfold())
	var grown := session.world.bounds
	assert_eq(grown, old.grow(session.world.chunk_size), "a ring of chunks all round")
	assert_eq(seen, [[old, grown]])
	assert_true(session.is_active)
	assert_eq(session.people.size(), people, "everyone still there")
	assert_eq(session.clock.tick, tick, "no time lost")
	# The new land is the land the generator always makes there.
	var coord := WorldCoords.tile_to_chunk(beyond, session.world.chunk_size)
	var made := session.generator.generate_chunk(coord)
	assert_eq(session.world.get_chunk(coord).height, made.height, "deterministic terrain beyond the old wall")
	var grown_props := 0
	for prop in session.props.props_in_chunk(coord):
		grown_props += 1
	var expected := 0
	for prop in session.generator.generate_props(made):
		if prop.kind != PropData.Kind.ROCK:
			expected += 1
	assert_eq(grown_props, expected, "and what grows on it")
	# People can walk there.
	assert_true(session.pathfinder.has_tile(beyond))
	var fire := session.start.settlement_tile
	var reached := 0
	for y in range(grown.position.y, grown.end.y, 2):
		for x in range(grown.position.x, grown.end.x, 2):
			var tile := Vector2i(x, y)
			if not old.has_point(tile) and session.pathfinder.can_stand(tile) and session.pathfinder.is_reachable(fire, tile):
				reached += 1
	assert_true(reached > 100, "the way leads into the new land (%d tiles of it, sampled)" % reached)
	# History.
	var moved := session.events.of_type(&"edge_moved")
	assert_eq(moved.size(), 1)
	assert_true(moved[0].significance >= Config.events.major_from, "a major event")
	assert_eq(EventText.text(moved[0], session.people, session.events),
		"The Edge Moved: the walls of the world stand further out than they ever did (64 → 96 tiles across)")
	# Saved as it is.
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.world.bounds, grown)
	assert_eq(again.unfolder.count, 1)
	again.queue_free()


func test_when_the_box_unfolds() -> void:
	var u := session.unfolder
	var now := session.clock.tick
	assert_false(u.due(session.world, session.settlements, session.people.size(), now), "nobody at the walls yet")
	_explore_the_walls()
	var push := u.pressure(session.world, session.settlements, session.people.size())
	assert_true(float(push["edge"]) >= 0.99)
	assert_false(bool(push["crowded"]), "eight people in a box of 64")
	assert_eq(u.due(session.world, session.settlements, session.people.size(), now), bool(push["near"]),
		"at the walls, but neither crowded nor settled near one")
	_knob(Config.world, &"unfold_people_per_1000_tiles", 0.5)
	assert_true(u.due(session.world, session.settlements, session.people.size(), now), "crowded, and at the walls")
	u.note(now)
	assert_false(u.due(session.world, session.settlements, session.people.size(), now + DAY), "not again so soon")
	assert_true(u.due(session.world, session.settlements, session.people.size(), now + (Config.world.unfold_rest_days + 1) * DAY))
	_knob(Config.world, &"max_world_tiles", 64)
	assert_false(u.due(session.world, session.settlements, session.people.size(), now + 1000 * DAY), "as large as it may be")
	assert_false(session.unfold())


func test_it_unfolds_by_itself_between_steps() -> void:
	_explore_the_walls()
	_knob(Config.world, &"unfold_people_per_1000_tiles", 0.5)
	session.clock.tick += DAY - Config.time.minute_of_day(session.clock.tick)
	session._on_day_started(Config.time.day_index(session.clock.tick))
	assert_true(session.unfold_pending, "due: done at the next step")
	assert_eq(session.world.bounds.size.x, 64, "not inside the clock's signal")
	assert_true(session.unfold_if_due())
	assert_eq(session.world.bounds.size.x, 96)
	assert_false(session.unfold_pending)


func test_a_new_world_in_a_larger_box() -> void:
	var larger: WorldSession = SessionScript.new()
	add_child(larger)
	larger.create_new(777, 128)
	larger.set_process(false)
	assert_eq(larger.world.bounds.size, Vector2i(128, 128))
	assert_eq(larger.pathfinder.has_tile(Vector2i(-64, -64)), true)
	larger.queue_free()
	assert_eq(MainMenu.NEW_WORLD_SIZES, [64, 128, 256] as Array[int])


func test_the_walls_are_seen_to_move() -> void:
	var view: WorldView = preload("res://scripts/rendering/world_view.gd").new()
	add_child(view)
	var old := session.world.bounds
	session.unfold()
	view.show_world(session.world, session.props, session.start)
	view.animate_unfold(old, 1.0)
	assert_true(view.is_unfolding())
	var first := view.box_frame().bounds
	assert_true(first.size.x < session.world.bounds.size.x, "they begin where they stood (%s)" % first)
	view._process(0.5)
	var middle := view.box_frame().bounds
	assert_true(middle.size.x > first.size.x and middle.size.x < session.world.bounds.size.x, "moving out (%s)" % middle)
	view._process(0.6)
	assert_eq(view.box_frame().bounds, session.world.bounds, "where they stand now")
	assert_false(view.is_unfolding())
	view.queue_free()
	await wait_frames(1)


func test_in_the_game() -> void:
	session.queue_free()
	await wait_frames(2)
	var first := SessionScript.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	var main := get_tree().current_scene
	var live: WorldSession = main.get_node("WorldSession")
	var old := live.world.bounds
	assert_true(live.unfold())
	await wait_frames(8)
	# The world is opened again at its new size, and shown so.
	main = get_tree().current_scene
	live = main.get_node("WorldSession")
	assert_eq(live.world.bounds, old.grow(16))
	assert_eq(main.get("unfolded_from"), old)
	var view: WorldView = main.get_node("WorldView")
	assert_true(view.is_unfolding() or view.box_frame().bounds == live.world.bounds, "the walls move out")
	assert_true(view.camera_rig().is_framed() or view.camera_rig().is_moving(), "the whole box in view")
	await wait_frames(2)
	var said := (main.get_node("UIRoot") as UIRoot).toasts().texts()
	var told := false
	for text in said:
		if text.begins_with("The Edge Moved"):
			told = true
	assert_true(told, "the player is told: %s" % [said])
	get_tree().unload_current_scene()
	await wait_frames(2)
