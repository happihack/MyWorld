extends TestCase
## Resources in the running game (M7.1): what people carry is seen in their
## arms, piles lie where they were put and grow, a felled tree is drawn as a
## stump, and the inspect card says what things hold.

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


func _adult(occupation: StringName = &"woodcutter") -> PersonData:
	for p in session.people.all_people():
		if p.occupation_id == occupation:
			return p
	return null


func _look_at(xz: Vector2, distance: float = 12.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)
	await wait_frames(3)


func test_what_someone_carries_is_seen_in_their_arms() -> void:
	var person := _adult()
	person.set_flag(PersonData.FLAG_INDOORS, false)
	await _look_at(person.world2d())
	var body := view.people_view().view_of(person.id)
	assert_not_null(body, "in sight")
	assert_eq(body.load_shown(), &"")
	var load := body.get_node("Load") as MeshInstance3D
	assert_false(load.visible)
	# Wood in their arms.
	person.carrying = &"wood"
	person.carrying_amount = 2
	await wait_frames(2)
	assert_eq(body.load_shown(), &"wood")
	assert_true(load.visible)
	assert_eq(load.mesh, PersonMeshLibrary.load_mesh(&"wood"))
	assert_eq(load.material_override, (body.get_node("Accessory") as MeshInstance3D).material_override, "drawn like what they carry anyway")
	# Something else looks different; nothing is nothing.
	person.carrying = &"berries"
	await wait_frames(2)
	assert_eq(body.load_shown(), &"berries")
	assert_ne(load.mesh, PersonMeshLibrary.load_mesh(&"wood"))
	person.carrying = &""
	person.carrying_amount = 0
	await wait_frames(2)
	assert_eq(body.load_shown(), &"")
	assert_false(load.visible)
	# Every resource can be carried in sight; the load sits on the body, not at the feet.
	assert_null(PersonMeshLibrary.load_mesh(&""))
	for resource in session.resources.ids():
		var mesh := PersonMeshLibrary.load_mesh(resource)
		assert_not_null(mesh, String(resource))
		var box := mesh.get_aabb()
		assert_true(box.position.y > 0.3 and box.end.y < 0.85, "%s is held between hip and head (%.2f … %.2f)" % [resource, box.position.y, box.end.y])
		assert_eq(PersonMeshLibrary.load_mesh(resource), mesh, "made once")
	# The card says it.
	person.carrying = &"wood"
	person.carrying_amount = 2
	main.select_person(person.id)
	await wait_frames(3)
	assert_true(ui.person_card().activity_text().ends_with(" · carrying 2 wood"), ui.person_card().activity_text())


func test_piles_lie_in_the_world_and_grow() -> void:
	var at := session.storage_place(&"wood")
	await _look_at(at)
	for begun in session.piles.piles(&"wood"):
		session.loose.remove(begun.id) # (what the settlement began with)
	await wait_frames(2)
	var loose := view.loose_view()
	var before := loose.object_count()
	var pile := session.loose.get_object(session.piles.add(&"wood", 2, at)[0])
	await wait_frames(3)
	assert_eq(loose.object_count(), before + 1)
	assert_true(loose.is_shown(pile.id))
	var small := loose.object_transform(pile.id).basis.get_scale().x
	assert_near(small, pile.scale(), 0.001)
	assert_true(loose.object_transform(pile.id).origin.distance_to(pile.world_position(session.world)) < 0.001)
	session.piles.add(&"wood", 12, at)
	await wait_frames(3)
	assert_true(loose.object_transform(pile.id).basis.get_scale().x > small * 1.3, "the heap has grown")
	session.piles.take(&"wood", 100, at, 3.0)
	await wait_frames(3)
	assert_false(loose.is_shown(pile.id), "and is gone when the last of it is taken")
	assert_eq(loose.object_count(), before)
	# The inspect card of a pile.
	var berries := session.loose.get_object(session.piles.add(&"grain", 7, session.storage_place(&"grain"))[0])
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = berries.id
	target.tile = berries.tile()
	var card := ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	assert_eq(card.title_text(), "A pile of grain")
	assert_eq(card.rows()["Holds"], "7 grain")
	# For the debug overlay: what is in store, here and anywhere.
	assert_has(session.piles.debug_text(session.storage_place(&"grain"), 4.0), "grain 7/7")
	assert_has(session.piles.debug_text(Vector2(-500.0, -500.0), 1.0), "grain 0/7")
	assert_has(session.nodes.debug_text(), "nodes: 0 regrowing")


func test_a_felled_tree_is_drawn_as_a_stump() -> void:
	var cutter := _adult()
	var tree: PropData = null
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and (tree == null
				or (prop.tile - session.start.settlement_tile).length_squared() < (tree.tile - session.start.settlement_tile).length_squared()):
			tree = prop
	await _look_at(tree.position2d())
	var coord := WorldCoords.tile_to_chunk(tree.tile, session.world.chunk_size)
	var chunk := view.chunk_view(coord)
	assert_not_null(chunk)
	var triangles := func() -> int:
		return chunk.props_mesh().surface_get_array_len(0) / 3
	var whole: int = triangles.call()
	var fallen: Array = []
	session.nodes.depleted.connect(func(id: int) -> void: fallen.append(id))
	var effects_before := int(view.effects().played.get(InteractionResponse.TREE_UPROOT, 0))
	# The last of its wood is taken.
	assert_true(session.nodes.take(tree.id, 1000, session.clock.tick) > 0)
	await wait_frames(4)
	assert_eq(fallen, [tree.id])
	assert_true(triangles.call() < whole, "its chunk is drawn again, with a stump (%d → %d)" % [whole, triangles.call()])
	assert_true(int(view.effects().played.get(InteractionResponse.TREE_UPROOT, 0)) > effects_before, "and it is seen to come down")
	# The inspect card says what it is now.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = tree.id
	target.tile = tree.tile
	var card := ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	assert_eq(card.title_text(), "Tree stump")
	assert_eq(card.rows()["Holds"], "No wood left")
	# A whole tree says how much it holds.
	var other: PropData = null
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			other = prop
			break
	target.entity_id = other.id
	target.tile = other.tile
	card = ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	var full := session.nodes.capacity(other)
	assert_eq(card.rows()["Holds"], "%d of %d wood" % [full, full])
	# Days later it has grown back, and is drawn whole again without anyone asking.
	# (Wood enough for the fire meanwhile: it is in the same chunk.)
	for i in 12:
		session.piles.add(&"wood", 16, session.storage_place(&"wood"))
	session.clock.set_speed(0)
	session.clock.tick += 26 * 1440
	await wait_frames(4)
	assert_eq(tree.stock, -1, "the world lets it grow as time passes")
	assert_eq(triangles.call(), whole)
	assert_false(cutter == null)
