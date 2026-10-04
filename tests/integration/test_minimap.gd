extends TestCase
## The minimap and the map (M13.3): the world from above, drawn chunk by
## chunk, the unexplored dimmed, fires, the selected one, recent events
## marked; a tap takes the camera there, a drag scrubs; the map with its
## layers, panned and zoomed.

var main: Node
var ui: UIRoot
var session: WorldSession
var rig: CameraRig


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	SaveManager.open_next = {}
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	session = main.get_node("WorldSession")
	session.clock.set_speed(0)
	rig = (main.get_node("WorldView") as WorldView).camera_rig()
	ui.minimap().map.refresh_all()


func after_each() -> void:
	ui.close_all_panels()
	Settings.reset_to_defaults()
	await wait_frames(2)


func _click(control: Control, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	control._gui_input(event)


func _settle() -> void:
	rig.set_process(false)
	for i in 400:
		rig.advance(1.0 / 60.0)
	rig.set_process(true)


func test_minimap_tap_to_world() -> void:
	var minimap := ui.minimap()
	assert_true(minimap.is_open())
	var fire := session.start.settlement_tile
	var target := Vector2(fire + Vector2i(9, -7)) + Vector2(0.5, 0.5)
	var point := minimap.point_of(target)
	assert_true(minimap.map_rect().has_point(point))
	assert_true(minimap.world_at(point).distance_to(target) < 0.01, "the point and the place agree")
	_click(minimap, point, true)
	_click(minimap, point, false)
	_settle()
	var at := Vector2(rig.pivot().x, rig.pivot().z)
	assert_true(at.distance_to(target) < 1.0, "the camera went there (%s, wanted %s)" % [at, target])


func test_a_drag_scrubs() -> void:
	var minimap := ui.minimap()
	var rect := minimap.map_rect()
	var from := rect.position + rect.size * Vector2(0.3, 0.5)
	var to := rect.position + rect.size * Vector2(0.7, 0.5)
	_click(minimap, from, true)
	var drag := InputEventMouseMotion.new()
	drag.position = to
	minimap._gui_input(drag)
	var at := Vector2(rig.pivot().x, rig.pivot().z)
	assert_true(at.distance_to(minimap.world_at(to)) < 2.0, "the camera follows the finger at once")
	_click(minimap, to, false)


func test_the_map_image() -> void:
	var map := ui.minimap().map
	assert_eq(map.image.get_size(), session.world.bounds.size, "a pixel a tile")
	assert_eq(map.pending(), 0)
	# Water is water-coloured.
	var water := Vector2i.MAX
	for y in range(-32, 32):
		for x in range(-32, 32):
			if water == Vector2i.MAX and session.world.get_water(Vector2i(x, y)) > 0.3:
				water = Vector2i(x, y)
	assert_ne(water, Vector2i.MAX, "water")
	var seen: Array = session.settlement.places().visited_cells()
	seen.append(Places.cell_of(water))
	session.settlement.places().set_visited_cells(seen)
	map.refresh(1_000_000)
	var pixel := map.image.get_pixelv(map.pixel_of(water))
	assert_true(pixel.b > pixel.r and pixel.b > pixel.g, "blue (%s)" % pixel)
	# Unexplored land is dimmed — and brightens once explored.
	var far := Vector2i(-30, -30)
	assert_false(map.is_explored(far))
	var dim := map.tile_color(far)
	var cells: Array = session.settlement.places().visited_cells()
	cells.append(Places.cell_of(far))
	session.settlement.places().set_visited_cells(cells)
	map.refresh(1_000_000)
	assert_true(map.is_explored(far))
	var known := map.image.get_pixelv(map.pixel_of(far))
	assert_true(known.get_luminance() > dim.get_luminance(), "explored: brighter (%s > %s)" % [known, dim])
	# The ground changes: that chunk is drawn again.
	var tile := session.start.settlement_tile + Vector2i(3, 3)
	session.world.set_terrain(tile, ChunkData.Terrain.ASH)
	assert_true(map.pending() > 0)
	map.refresh(1_000_000)
	var drawn := map.image.get_pixelv(map.pixel_of(tile))
	var wanted := map.tile_color(tile)
	assert_true(absf(drawn.r - wanted.r) < 0.01 and absf(drawn.g - wanted.g) < 0.01 and absf(drawn.b - wanted.b) < 0.01,
		"drawn again (%s, %s)" % [drawn, wanted])


func test_marks_and_folding() -> void:
	var minimap := ui.minimap()
	var kinds := {}
	for mark in minimap.markers():
		kinds[mark[0]] = true
	assert_true(kinds.has(&"fire"), "the settlement's fire")
	assert_true(kinds.has(&"ruin"), "the ruin of those before")
	main.select_person(session.people.all_people()[0].id, 2)
	kinds.clear()
	for mark in minimap.markers():
		kinds[mark[0]] = true
	assert_true(kinds.has(&"person"), "the one selected")
	assert_eq(minimap.view_outline().size(), 4, "what the camera shows, outlined")
	# It folds away, and is remembered so.
	minimap.toggle()
	assert_false(minimap.is_open())
	assert_eq(minimap.size, Vector2(Minimap.FOLDED, Minimap.FOLDED))
	assert_false(bool(Settings.get_value(Minimap.SETTING)))
	minimap.toggle()
	assert_true(minimap.is_open())


func test_the_map() -> void:
	var menu := ui.open_menu()
	for entry in menu.entries():
		if entry.text == "Map":
			entry.pressed.emit()
	await wait_frames(2)
	var panel := ui.map_panel()
	assert_not_null(panel, "WORLD → Map")
	var canvas := panel.canvas()
	# Layers: without the water, a river tile shows its ground.
	var water := Vector2i.MAX
	for y in range(-32, 32):
		for x in range(-32, 32):
			if water == Vector2i.MAX and session.world.get_water(Vector2i(x, y)) > 0.3:
				water = Vector2i(x, y)
	var with_water := panel.map.image.get_pixelv(panel.map.pixel_of(water))
	panel.set_layer(&"water", false)
	assert_ne(panel.map.image.get_pixelv(panel.map.pixel_of(water)), with_water, "the water layer off")
	panel.set_layer(&"water", true)
	panel.set_layer(&"settlements", false)
	for mark: Array in panel.markers():
		assert_ne(mark[0], &"fire", "no fires")
	panel.set_layer(&"settlements", true)
	# Zoomed and panned.
	var before := canvas.scale_now()
	panel.zoom_by(2.0)
	assert_near(canvas.scale_now(), before * 2.0, 0.001)
	var centre := canvas.centre
	_click(canvas, Vector2(200, 200), true)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(300, 200)
	canvas._gui_input(drag)
	_click(canvas, Vector2(300, 200), false)
	assert_true(canvas.centre.x < centre.x, "dragged: the map moves with the finger")
	assert_not_null(ui.map_panel(), "a drag is not a tap")
	# A tap takes the camera there.
	var target := Vector2(session.start.settlement_tile + Vector2i(-6, 5)) + Vector2(0.5, 0.5)
	var point := canvas.point_of(target)
	_click(canvas, point, true)
	_click(canvas, point, false)
	await wait_frames(2)
	assert_null(ui.map_panel(), "put away")
	_settle()
	assert_true(Vector2(rig.pivot().x, rig.pivot().z).distance_to(target) < 1.0)


func test_the_map_opens_quickly() -> void:
	var started := Time.get_ticks_usec()
	ui.open_map()
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	print("    the map opened in %.1f ms (64 tiles)" % ms)
	assert_true(ms < 100.0, "%.1f ms" % ms)
