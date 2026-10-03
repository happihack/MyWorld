extends TestCase
## Roads & traffic (M12.2, bible §17.3): where people walk is counted; grass
## walked enough is worn to a path (which the pathfinder prefers, so it draws
## more feet), and a path nobody walks grows over; a ford waded often gets a
## bridge, built where it stands, that takes people over dry-shod.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440
const V24_FIXTURE := "res://tests/fixtures/saves/v24_world.sav"
const V24_ID := "w1791033482_16a9dec9"

var session: WorldSession
var traffic: Traffic
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
	traffic = session.traffic
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"newcomer_chance_per_day"]:
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


## Open grass near the fire, with nothing on it, in a row of `length` tiles.
func _grass_row(length: int) -> Array[Vector2i]:
	var fire := session.settlement.fire().tile
	for dy in range(-8, 9):
		for dx in range(-8, 9):
			var row: Array[Vector2i] = []
			for i in length:
				var tile := fire + Vector2i(dx + i, dy)
				if session.world.get_terrain(tile) != ChunkData.Terrain.GRASS or session.props.prop_at(tile) != null \
						or session.world.get_water(tile) > 0.0 or not session.pathfinder.can_stand(tile):
					break
				row.append(tile)
			if row.size() == length:
				return row
	return []


## `steps` steps onto each of `tiles` every day, for `days` days.
func _walk(tiles: Array, steps: int, days: int) -> void:
	for day in days:
		for tile: Vector2i in tiles:
			for i in steps:
				traffic.add(tile)
		session.clock.tick += DAY
		traffic.advance_to(session.clock.tick)


func _a_ford() -> Variant:
	var fire := session.settlement.fire().tile
	var best: Variant = null
	for dy in range(-30, 31):
		for dx in range(-30, 31):
			var tile := fire + Vector2i(dx, dy)
			if traffic.is_ford(tile) and session.props.prop_at(tile) == null and session.pathfinder.can_stand(tile):
				if best == null or Vector2(tile - fire).length() < Vector2(best - fire).length():
					best = tile
	return best


func test_traffic_to_road() -> void:
	var row := _grass_row(3)
	assert_eq(row.size(), 3, "grass to walk on")
	var before := session.pathfinder.weight_at(row[0])
	var worn: Array = []
	traffic.worn.connect(func(tile: Vector2i, path: bool) -> void: worn.append([tile, path]))
	# A little walking leaves no path.
	_walk(row, 1, 10)
	assert_true(traffic.level(row[0]) > 0.0 and traffic.level(row[0]) < Config.construction.path_from)
	assert_eq(session.world.get_terrain(row[0]), ChunkData.Terrain.GRASS, "a few steps a day: no path")
	# Walked every day, again and again: worn to a path.
	_walk(row, 6, 10)
	for tile in row:
		assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.ROAD, "worn to a path")
		assert_true(traffic.is_path(tile))
	assert_eq(worn.size(), 3)
	assert_true(session.pathfinder.weight_at(row[0]) < before, "quicker to walk (%.2f → %.2f)" % [before, session.pathfinder.weight_at(row[0])])
	assert_eq(UIText.terrain_name(ChunkData.Terrain.ROAD), "Path")
	# History notes the first.
	var paths := session.events.of_type(&"path_worn")
	assert_eq(paths.size(), 1, "the first path, not every tile of it")
	assert_eq(EventText.text(paths[0], session.people, session.events), "Feet have worn the first path through the grass")
	# The ground says how much it is walked.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.TILE
	target.tile = row[1]
	var report := session.interactions.inspect(target)
	assert_true(report.path)
	assert_true(report.footfall >= Config.construction.path_gone)
	assert_eq(UIText.footfall_text(report.footfall, report.path).ends_with("a path"), true)


func test_a_path_nobody_walks_grows_over() -> void:
	var row := _grass_row(2)
	_walk(row, 8, 12)
	assert_eq(session.world.get_terrain(row[0]), ChunkData.Terrain.ROAD)
	var days := 0
	while traffic.is_path(row[0]) and days < 60:
		_walk([], 0, 1)
		days += 1
	assert_false(traffic.is_path(row[0]), "grown over in %d days" % days)
	assert_eq(session.world.get_terrain(row[0]), ChunkData.Terrain.GRASS, "grass again")
	assert_true(days > 5, "not at once (%d days)" % days)
	assert_eq(traffic.paths_gone, 2)


func test_only_open_ground_is_worn() -> void:
	var row := _grass_row(3)
	# A field, and a stone lying in the way.
	session.world.set_terrain(row[0], ChunkData.Terrain.FARMLAND)
	var bush := PropData.new()
	bush.id = session.ids.next_id()
	bush.kind = PropData.Kind.BUSH
	bush.tile = row[1]
	session.props.add(bush)
	_walk(row, 10, 12)
	assert_eq(session.world.get_terrain(row[0]), ChunkData.Terrain.FARMLAND, "a field stays a field")
	assert_eq(session.world.get_terrain(row[1]), ChunkData.Terrain.GRASS, "nor under a bush")
	assert_eq(session.world.get_terrain(row[2]), ChunkData.Terrain.ROAD)


func test_a_path_draws_feet() -> void:
	# Two ways between the same two tiles; the worn one is taken.
	var row := _grass_row(5)
	_walk(row, 8, 12)
	var from := row[0]
	var to := row[4]
	var path := session.pathfinder.find_path(from, to)
	for tile in path:
		assert_true(traffic.is_path(tile), "along the path (%s)" % tile)


func test_a_bridge_over_a_busy_ford() -> void:
	var ford: Variant = _a_ford()
	assert_not_null(ford, "a ford near the settlement")
	var planner := session.planner
	_knob(Config.construction, &"homes_spare_least", -1000)
	_knob(Config.construction, &"storage_room_least", -1000)
	_knob(Config.construction, &"spoiled_from", 1_000_000)
	_knob(Config.construction, &"well_from", 1_000_000)
	assert_eq(planner.needs(session.clock.tick), [] as Array[StringName])
	var wading := session.pathfinder.weight_at(ford)
	assert_true(wading > 2.0, "wading is slow (%.2f)" % wading)
	# Waded again and again.
	_walk([ford], 8, 10)
	assert_false(traffic.is_path(ford), "no path is worn in water")
	assert_eq(traffic.ford_for_bridge(), ford)
	assert_eq(planner.needs(session.clock.tick), [&"bridge"] as Array[StringName])
	var p := planner.plan(session.clock.tick)
	assert_eq(str(p.get("def", "")), "bridge")
	var bridge := session.props.prop_at(ford)
	assert_eq([bridge.kind, bridge.variant], [PropData.Kind.BRIDGE, 0], "posts in the ford")
	assert_true(session.pathfinder.can_stand(ford), "people still wade past it meanwhile")
	assert_true(traffic.ford_for_bridge() == null, "one there already")
	var builder := session.people.all_people()[0]
	session.construction.deliver(p, &"wood", 10)
	while not session.construction.work(p, builder, 30.0, session.clock.tick):
		if session.construction.progress(p) >= ConstructionSystem.FRAME_FROM:
			assert_eq(bridge.variant, 1, "beams")
	assert_eq(session.props.prop_at(ford), bridge, "built where it stands")
	assert_eq(bridge.variant, PropData.BRIDGE_DONE)
	assert_true(session.pathfinder.weight_at(ford) < 1.0, "dry-shod over the ford (%.2f)" % session.pathfinder.weight_at(ford))
	assert_eq(EventText.text(session.events.of_type(&"building_built")[0], session.people, session.events),
		"The first bridge stands, built by %s" % builder.given_name)
	assert_eq(UIText.prop_name(PropData.Kind.BRIDGE), "Bridge")
	# Someone on it stands on its deck.
	var view := PeopleView.new()
	view.props = session.props
	view._world = session.world
	builder.position = ford
	assert_near(view.ground_position(builder).y,
		session.world.get_height(ford) * session.world.height_step + PropData.BRIDGE_DECK, 0.001)
	view.free()
	# A flood can wash it away: nothing is left in the ford.
	session.construction.damage(bridge.id, PropData.SOUND, &"flood", session.clock.tick)
	assert_null(session.props.prop_at(ford), "washed away")
	assert_true(session.pathfinder.can_stand(ford))
	var gone := session.events.of_type(&"building_ruined")
	assert_eq(EventText.text(gone[-1], session.people, session.events), "The bridge has been washed away")


func test_paths_are_saved() -> void:
	var row := _grass_row(2)
	_walk(row, 8, 12)
	traffic.add(row[0])
	var level := traffic.level(row[0])
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.world.get_terrain(row[0]), ChunkData.Terrain.ROAD)
	assert_true(again.traffic.is_path(row[0]))
	assert_near(again.traffic.level(row[0]), level + 1.0, 0.01, "with the day's steps")
	assert_eq(again.traffic.path_tiles(), traffic.path_tiles())
	# It grows over in the opened world too (to what it was).
	for day in 60:
		again.clock.tick += DAY
		again.traffic.advance_to(again.clock.tick)
	assert_eq(again.world.get_terrain(row[0]), ChunkData.Terrain.GRASS)
	again.queue_free()


func test_the_band_wears_paths() -> void:
	var minute := Config.time.real_seconds_per_game_minute
	var frame := Config.time.max_frame_delta_s
	for i in 8 * DAY:
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
	assert_true(traffic.paths_worn > 0, "paths worn in eight days: %s" % traffic.debug_text())
	for tile in traffic.path_tiles():
		assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.ROAD)
	var near := 0
	var fire := session.settlement.fire().tile
	for tile in traffic.path_tiles():
		if Vector2(tile - fire).length() < 12.0:
			near += 1
	assert_true(near > 0, "about the settlement")


func test_version_24_save_loads() -> void:
	# Written by M12.1 (44f71fe): before footfall was counted.
	var dir := SaveManager.world_dir(V24_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V24_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 24)
	var loaded := SaveManager.load_world(V24_ID)
	assert_true(loaded.ok, loaded.error)
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.traffic.path_tiles().size(), 0)
	s.movement.traffic.add(s.settlement.fire().tile + Vector2i(2, 0))
	assert_true(SaveManager.save_world(s, &"test"))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	s.queue_free()
	assert_true(SaveManager.SAVE_VERSION >= 25)
	var data := {"world": {"world_state": {"people": []}}}
	assert_eq(SaveMigrations._v24_to_v25(data)["world"]["world_state"]["traffic"], {})
