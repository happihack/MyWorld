extends TestCase
## Animals in the running game (M7.4): drawn in batches by species, as dots
## for each group from far away; they can be touched and looked at; and
## they live as the clock runs.

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


func test_animals_are_drawn_in_batches_and_as_dots_from_afar() -> void:
	var animals := session.animals
	var beasts := view.animals_view()
	var deer := animals.of_species(&"deer")
	assert_true(deer.size() >= 5)
	await _look_at(deer[0].position, 10.0)
	assert_true(beasts.bodies_shown())
	assert_eq(beasts.shown_count(&"deer"), animals.count(&"deer"), "every deer in one batch")
	assert_eq(beasts.shown_count(&"rabbit"), animals.count(&"rabbit"))
	assert_eq(beasts.shown_count(&"fox"), animals.count(&"fox"))
	assert_eq(beasts.batch_count(), 3, "one batch for each kind")
	assert_eq(beasts.marker_count(), 0)
	# Each stands where it is, on the ground.
	for animal in deer:
		var at := beasts.shown_position(animal.id)
		assert_true(Vector2(at.x, at.z).distance_to(animal.position) < 0.05)
		assert_near(at.y, session.world.get_height(animal.tile()) * session.world.height_step, 0.001)
	# It follows the animal smoothly when the animal moves.
	var mover := deer[0]
	var from := beasts.shown_position(mover.id)
	animals.move(mover.id, mover.position + Vector2(1.5, 0.0))
	beasts.refresh(0.05)
	var part := beasts.shown_position(mover.id)
	assert_true(part.x > from.x and part.x < mover.position.x, "on its way, not there in one jump")
	for i in 200:
		beasts.refresh(0.05)
	assert_near(beasts.shown_position(mover.id).x, mover.position.x, 0.02)
	# From far away: a dot for each group.
	rig.frame_box(false)
	for i in 240:
		rig.advance(1.0 / 60.0)
	await wait_frames(3)
	assert_false(beasts.bodies_shown(), "too small to draw one by one (a tile is %.1f on screen)" % beasts.tile_on_screen)
	assert_eq(beasts.shown_count(&"deer"), 0)
	var groups := {}
	for animal in animals.all_animals():
		groups[animal.group] = true
	assert_eq(beasts.marker_count(), groups.size(), "one dot a group")
	# One that dies is gone from the picture.
	await _look_at(deer[1].position, 10.0)
	session.fauna.hunted(deer[1].id)
	await wait_frames(2)
	assert_eq(beasts.shown_count(&"deer"), animals.count(&"deer"))
	assert_eq(beasts.shown_position(deer[1].id), Vector3.INF)


func test_an_animal_can_be_touched_and_looked_at() -> void:
	var animals := session.animals
	var deer := animals.of_species(&"deer")[0]
	for p in session.people.all_people():
		p.set_flag(PersonData.FLAG_INDOORS, true)
	await _look_at(deer.position, 9.0)
	var at := view.animals_view().shown_position(deer.id)
	var screen := rig.world_to_screen(at + Vector3(0.0, 0.3, 0.0))
	# Under the finger: the animal (before the ground it stands on).
	var picked := view.pick(screen, 40.0)
	assert_eq(picked.kind, Picker.Kind.ENTITY)
	assert_eq(picked.entity_kind, SpatialIndex.KIND_ANIMAL)
	assert_true(session.animals.has_animal(picked.entity_id), "an animal")
	var touched := session.animals.get_animal(picked.entity_id)
	# Looked at.
	var card := ui.open_inspect(session.interactions.inspect(picked))
	await wait_frames(2)
	assert_eq(card.title_text(), UIText.species_name(touched.species))
	assert_true(card.rows().has("Doing") and card.rows().has("Age"))
	assert_eq(card.rows()["In the box"], str(animals.count(touched.species)))
	# Touched: it bolts.
	var response := session.interactions.tap(picked)
	assert_eq(response.animal_id, touched.id)
	assert_eq(touched.state, AnimalData.State.FLEE)
	# And it runs as the clock does.
	var from := touched.position
	session.clock.tick += 5
	await wait_frames(3)
	assert_true(touched.position.distance_to(from) > 2.0, "the world lets it run (%.1f)" % touched.position.distance_to(from))


func test_the_hunter_carries_a_spear() -> void:
	var hunter: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"hunter":
			hunter = p
	assert_not_null(hunter)
	hunter.set_flag(PersonData.FLAG_INDOORS, false)
	await _look_at(hunter.world2d(), 8.0)
	var body := view.people_view().view_of(hunter.id)
	assert_not_null(body)
	assert_eq(body.accessory, &"spear")
	assert_eq(body.accessory_mesh(), PersonMeshLibrary.accessory(&"spear"))
