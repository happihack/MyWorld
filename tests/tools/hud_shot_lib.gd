extends RefCounted
## The work of hud_shot.gd (loaded once the autoloads exist).


static func shoot(tree: SceneTree, out: String) -> bool:
	Settings.reset_to_defaults()
	Settings.set_value(&"accessibility/reduced_motion", true)
	var first := WorldSession.new()
	tree.root.add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await tree.process_frame
	tree.change_scene_to_file("res://scenes/main/main.tscn")
	for i in 40:
		await tree.process_frame
	var main := tree.current_scene
	var ui: UIRoot = main.get_node("UIRoot")
	var view: WorldView = main.get_node("WorldView")
	var session: WorldSession = main.get_node("WorldSession")
	ui.hints().set_process(false)
	ui.set_speed(GameClock.SPEED_PAUSE)
	for i in 30:
		await tree.process_frame
	ui.show_blessings()
	for i in 6:
		await tree.process_frame
	if not _save(tree, out + "_bar.png"):
		return false
	ui.show_disasters()
	for i in 6:
		await tree.process_frame
	if not _save(tree, out + "_disasters.png"):
		return false
	var card := ui.offer_blessing(BlessingSystem.LIGHTS)
	for i in 6:
		await tree.process_frame
	if not _save(tree, out + "_card.png"):
		return false
	card.close()
	await tree.process_frame
	# The lights at night, at their fullest.
	session.clock.tick += int(fposmod(23.0 - session.clock.hour(), 24.0) * 60.0)
	main.give(BlessingSystem.LIGHTS)
	session.clock.tick += 35
	for i in 10:
		await tree.process_frame
	ui.close_all_panels() # (a milestone may have come up: the first anomaly)
	for i in 6:
		await tree.process_frame
	if not _save(tree, out + "_lights.png"):
		return false
	return true


static func _save(tree: SceneTree, path: String) -> bool:
	var image := tree.root.get_texture().get_image()
	var err := image.save_png(path)
	print("hud shot: ", path, " ", error_string(err))
	return err == OK
