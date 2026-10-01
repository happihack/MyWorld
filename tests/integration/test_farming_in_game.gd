extends TestCase
## Fields in the running game (M7.3): a plot is drawn as tilled ground with
## its crop on it and changes as the crop does; the farmer carries a hoe;
## the inspect card says how a crop is doing.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	Haptics.vibrate_action = func(_ms: int, _amplitude: float) -> void: pass
	SaveManager.attach(null)
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
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false
	session.clock.set_speed(0)


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _look_at(xz: Vector2, distance: float = 10.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)
	await wait_frames(3)


func test_a_plot_is_seen_and_changes_with_its_crop() -> void:
	var farming := session.farming
	var tile: Vector2i = farming.next_plot()
	await _look_at(Places.middle_of(tile))
	var coord := WorldCoords.tile_to_chunk(tile, session.world.chunk_size)
	var chunk := view.chunk_view(coord)
	var triangles := func() -> int:
		return chunk.props_mesh().surface_get_array_len(0) / 3
	var bare: int = triangles.call()
	var terrain_before := chunk.terrain_mesh()
	# Sown: tilled earth with furrows.
	var crop := farming.sow(tile, session.clock.tick)
	await wait_frames(4)
	assert_eq(session.world.get_terrain(tile), ChunkData.Terrain.FARMLAND)
	assert_true(triangles.call() > bare, "furrows on it (%d → %d)" % [bare, triangles.call()])
	assert_ne(chunk.terrain_mesh(), terrain_before, "the ground is drawn anew (tilled)")
	var sown: int = triangles.call()
	# Grown: plants stand on it.
	crop.growth = 700
	crop.variant = Farming.Stage.GROWING
	session.props.changed(crop.id)
	await wait_frames(4)
	assert_true(triangles.call() > sown + 50, "grain stands on it (%d → %d)" % [sown, triangles.call()])
	# The card.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = crop.id
	target.tile = crop.tile
	var card := ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	assert_eq(card.title_text(), "Growing grain")
	assert_eq(card.rows()["Crop"], "70% grown")
	assert_true(card.rows().has("Soil"))
	assert_false(card.rows().has("Holds"), "nothing to reap yet")
	# Ripe: what it holds.
	crop.growth = 1000
	crop.variant = Farming.Stage.RIPE
	crop.stock = 6
	session.props.changed(crop.id)
	card = ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	assert_eq(card.title_text(), "Ripe grain")
	assert_eq(card.rows()["Crop"], "Ready to reap")
	assert_eq(card.rows()["Holds"], "6 of 6 grain")
	# It grows by itself as the clock runs.
	crop.growth = 300
	crop.variant = Farming.Stage.SPROUT
	crop.stock = -1
	crop.stock_tick = session.clock.tick
	session.world.chunk_at_tile(tile).set_moisture(session.world.index_at_tile(tile), 220)
	session.clock.tick += 300
	await wait_frames(3)
	assert_true(crop.growth > 300, "the world lets it grow (%d)" % crop.growth)


func test_the_farmer_carries_a_hoe() -> void:
	var farmer: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"farmer":
			farmer = p
	assert_not_null(farmer)
	farmer.set_flag(PersonData.FLAG_INDOORS, false)
	await _look_at(farmer.world2d(), 8.0)
	var body := view.people_view().view_of(farmer.id)
	assert_not_null(body)
	assert_eq(body.accessory, &"hoe")
	assert_eq(body.accessory_mesh(), PersonMeshLibrary.accessory(&"hoe"))
	main.select_person(farmer.id)
	await wait_frames(3)
	ui.person_card().set_state(PersonCard.State.HALF)
	ui.person_card().refresh()
	assert_has(ui.person_card().about_text(), "Farmer")
	# Someone who takes it up later is given one too.
	var other: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"woodcutter":
			other = p
	other.set_flag(PersonData.FLAG_INDOORS, false)
	await _look_at(other.world2d(), 8.0)
	var other_body := view.people_view().view_of(other.id)
	assert_eq(other_body.accessory, &"axe")
	other.occupation_id = &"farmer"
	await wait_frames(PeopleView.DRESS_CHECK_FRAMES + 2)
	assert_eq(other_body.accessory, &"hoe")
