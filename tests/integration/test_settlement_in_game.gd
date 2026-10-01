extends TestCase
## The settlement in the running game (M7.2): a fire that goes out is seen
## to be out — no flame, no light, no smoke — and is lit again when there
## is wood; the housekeeping runs by itself as the clock does.

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


func test_a_fire_without_wood_is_seen_to_go_out() -> void:
	var settlement := session.settlement
	var fire := settlement.fire()
	var light := view.day_night().fire_light()
	var ambient: AmbientLife = view.get_node("AmbientLife") if view.has_node("AmbientLife") else null
	var chunk := view.chunk_view(WorldCoords.tile_to_chunk(fire.tile, session.world.chunk_size))
	var triangles := func() -> int:
		return chunk.props_mesh().surface_get_array_len(0) / 3
	await wait_frames(2)
	assert_true(settlement.fire_lit())
	assert_true(light.visible, "the fire gives light")
	if ambient != null:
		assert_true(ambient.fire_lit(), "and smoke")
	var burning: int = triangles.call()
	# What the player is told.
	var target := Picker.Result.new()
	target.kind = Picker.Kind.ENTITY
	target.entity_id = fire.id
	target.tile = fire.tile
	var card := ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	assert_eq(card.rows()["Fire"], "Burning")
	# The wood is gone (the player has carried it off), and time passes.
	for pile in session.piles.piles(&"wood"):
		session.loose.move(pile.id, pile.position + Vector2(10.0, 4.0))
	session.clock.tick += 300
	await wait_frames(4)
	assert_false(settlement.fire_lit(), "the world keeps house by itself as the clock runs")
	assert_false(light.visible, "no light")
	if ambient != null:
		assert_false(ambient.fire_lit(), "no smoke (and so no crackle)")
	assert_true(triangles.call() < burning, "no flame (%d → %d)" % [burning, triangles.call()])
	card = ui.open_inspect(session.interactions.inspect(target))
	await wait_frames(2)
	assert_eq(card.title_text(), "Cold fire")
	assert_eq(card.rows()["Fire"], "Gone out — no wood")
	# A game opened on a cold fire shows it cold.
	assert_true(SaveManager.save_world(session, &"test"))
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(5)
	main = get_tree().current_scene
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	main.get_node("UIRoot").quit_action = func() -> void: pass
	main.get_node("UIRoot").hints().set_process(false)
	session.behavior.enabled = false
	session.clock.set_speed(0)
	await wait_frames(2)
	assert_false(session.settlement.fire_lit())
	assert_false(view.day_night().fire_light().visible)
	# Wood is brought: it burns again.
	session.settlement.stockpile.add(&"wood", 5)
	session.clock.tick += 1
	await wait_frames(4)
	assert_true(session.settlement.fire_lit())
	assert_true(view.day_night().fire_light().visible)
	assert_eq(session.settlement.stockpile.amount(&"wood"), 4, "the first piece is on it")
	var fire_again := session.settlement.fire()
	var chunk_again := view.chunk_view(WorldCoords.tile_to_chunk(fire_again.tile, session.world.chunk_size))
	assert_eq(chunk_again.props_mesh().surface_get_array_len(0) / 3, burning, "with its flame")


func test_food_goes_bad_and_jobs_are_posted_as_the_clock_runs() -> void:
	var settlement := session.settlement
	var berries := settlement.stockpile.amount(&"berries")
	assert_true(berries > 8)
	var lost: Array = []
	settlement.spoiled.connect(func(resource: StringName, amount: int) -> void: lost.append([resource, amount]))
	# Past midnight.
	session.clock.tick += 1440
	await wait_frames(3)
	assert_eq(lost.size(), 1)
	assert_eq(lost[0][0], &"berries")
	assert_eq(settlement.stockpile.amount(&"berries"), berries - int(lost[0][1]))
	assert_true(settlement.jobs.last_refresh_tick >= session.clock.tick - Config.settlement.job_check_minutes, "the board is kept up to date")
	assert_true(settlement.jobs.wants(&"wood"), "the fire has burned what there was")
	# The debug overlay has a line for it.
	assert_has(settlement.debug_text(), "people in")
	assert_has(settlement.debug_text(), "jobs:")
