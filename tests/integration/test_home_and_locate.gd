extends TestCase
## Home & Locate (M13.5): Home goes to the largest settlement; anything can
## be found — people, settlements, buildings, events, discoveries — from a
## search in the menu, and a grave from its card; the camera is never lost.

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


func after_each() -> void:
	ui.close_all_panels()
	get_tree().unload_current_scene() # (its minimap and buttons would stand in later tests' way)
	await wait_frames(2)


func _settle() -> void:
	rig.set_process(false)
	for i in 400:
		rig.advance(1.0 / 60.0)
	rig.set_process(true)


func _near(target: Vector2, within: float = 1.5) -> bool:
	return Vector2(rig.pivot().x, rig.pivot().z).distance_to(target) < within


func test_home_is_the_largest_settlement() -> void:
	var first := session.settlement
	assert_eq(session.settlements.home(), first, "one settlement: it")
	# A second, larger one.
	var info := WorldSetup.StartInfo.new()
	info.settlement_tile = first.start_info().settlement_tile + Vector2i(-6, 12)
	var second := session.add_settlement(info)
	var people := session.people.all_people()
	for i in people.size() - 2:
		people[i].settlement_id = second.id
	assert_eq(session.settlements.home(), second, "the largest")
	main.go_home()
	_settle()
	assert_true(_near(Vector2(info.settlement_tile) + Vector2(0.5, 0.5)), "Home: there")


func test_locate_finds_everything() -> void:
	var rows := MainMenu.locate_rows(session)
	var kinds := {}
	for row: Array in rows:
		kinds[row[0]] = true
	for kind in ["people", "settlements", "buildings", "discoveries"]:
		assert_true(kinds.has(kind), kind)
	# A search: only what matches, any case.
	var someone := session.people.all_people()[0]
	var found := MainMenu.locate_rows(session, someone.given_name.to_upper())
	assert_false(found.is_empty())
	for row: Array in found:
		assert_true(String(row[1]).to_lower().contains(someone.given_name.to_lower()), row[1])
	assert_true(MainMenu.locate_rows(session, "zzqx").is_empty())


func test_the_locate_page() -> void:
	var menu := ui.open_menu()
	var locate: Button = null
	for entry in menu.entries():
		if entry.text == "Locate":
			locate = entry
	assert_not_null(locate, "WORLD → Locate")
	locate.pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_LOCATE)
	assert_true(menu.texts().has("PEOPLE"))
	# A building: the camera goes there.
	var hut := session.props.get_prop(session.start.hut_ids[0])
	var search: LineEdit = null
	for child in menu.find_children("*", "LineEdit", true, false):
		search = child
	assert_not_null(search, "a search box")
	search.text = "Hut"
	search.text_changed.emit("Hut")
	await wait_frames(1)
	assert_false(menu.texts().has("PEOPLE"), "only what matches")
	var row: Button = null
	for entry in menu.entries():
		if entry.text.begins_with("Hut"):
			row = entry
	assert_not_null(row)
	row.pressed.emit()
	await wait_frames(2)
	assert_null(ui.main_menu(), "put away")
	_settle()
	var near_a_hut := false
	for id in session.start.hut_ids:
		if _near(session.props.get_prop(id).position2d(), 2.0):
			near_a_hut = true
	assert_true(near_a_hut, "at a hut (the first was %s)" % hut.position2d())
	# A person: selected, and the camera there.
	menu = ui.open_menu()
	menu.open_page(MainMenu.PAGE_LOCATE)
	await wait_frames(1)
	var someone := session.people.all_people()[0]
	for entry in menu.entries():
		if entry.text.begins_with(someone.full_name()):
			entry.pressed.emit()
			break
	await wait_frames(2)
	assert_not_null(ui.person_card())
	assert_eq(ui.person_card().person_id(), someone.id)


func test_a_grave_can_be_located() -> void:
	var gone := session.people.all_people()[-1]
	session.kill_person(gone.id, Lifecycle.CAUSE_OLD_AGE)
	var record := session.archive.get_record(gone.id)
	assert_true(record.grave_id > 0, "buried")
	var card := ui.open_grave(session, gone.id)
	await wait_frames(2)
	var locate: Button = card.find_child("Locate", true, false)
	assert_not_null(locate, "Locate on the grave's card")
	rig.frame_box(false)
	locate.pressed.emit()
	_settle()
	assert_true(_near(session.props.get_prop(record.grave_id).position2d(), 2.0), "at the grave")


func test_camera_never_lost() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1313
	rig.set_process(false)
	var view := rig.view_size()
	for i in 400:
		match rng.randi_range(0, 6):
			0:
				rig.pan_screen(Vector2(rng.randf_range(0, view.x), rng.randf_range(0, view.y)),
					Vector2(rng.randf_range(-view.x, view.x * 2.0), rng.randf_range(-view.y, view.y * 2.0)))
			1:
				rig.zoom_at(rng.randf_range(0.2, 5.0), Vector2(rng.randf_range(0, view.x), rng.randf_range(0, view.y)))
			2:
				rig.rotate_at(rng.randf_range(-3.0, 3.0), view * 0.5)
			3:
				rig.focus_on(Vector3(rng.randf_range(-500, 500), 0.0, rng.randf_range(-500, 500)), rng.randf_range(-5.0, 400.0), rng.randf() < 0.5)
			4:
				rig.frame_box(rng.randf() < 0.5)
			5:
				main.go_home()
			6:
				# The box unfolds under the camera.
				var b := Rect2(session.world.bounds).grow(16.0 * rng.randi_range(0, 2))
				rig.setup(b, b.grow(2.0), -2.0, 9.0)
		for step in rng.randi_range(1, 20):
			rig.advance(1.0 / 60.0)
		var at := rig.pivot()
		assert_true(is_finite(at.x) and is_finite(at.y) and is_finite(at.z) and is_finite(rig.distance()), "finite (%d)" % i)
		assert_true(rig.distance() >= rig.config.min_distance - 0.01 and rig.distance() <= rig.fit_distance() * 1.5 + 0.01,
			"distance %.1f (%d)" % [rig.distance(), i])
		var ground: Variant = rig.screen_to_ground(view * 0.5)
		assert_not_null(ground, "it looks at the ground (%d)" % i)
	rig.set_process(true)
