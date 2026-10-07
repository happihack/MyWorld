extends TestCase
## The on-device benchmark (M21.1): Settings → Debug → Run benchmark — the
## camera goes its fixed way, every part is measured and written down, the
## camera comes back, and nothing in the world changes.

var main: Node
var ui: UIRoot
var session: WorldSession
const OUT := "user://test_benchmark.txt"


func before_each() -> void:
	AudioManager.ensure_sounds()
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
	session = main.get_node("WorldSession")
	session.clock.set_speed(0)
	if FileAccess.file_exists(OUT):
		DirAccess.remove_absolute(OUT)


func after_each() -> void:
	ui.close_all_panels()
	Settings.reset_to_defaults()
	await wait_frames(2)


func test_the_benchmark_measures_and_leaves_the_world_as_it_was() -> void:
	Settings.set_value(&"debug/enabled", true)
	var menu := ui.open_menu()
	await wait_frames(1)
	menu.open_page(&"debug")
	await wait_frames(1)
	assert_true(menu.texts().has("Run benchmark (1 minute)"), "on the Debug page")
	var rig: CameraRig = main.world_view.camera_rig()
	var before_pivot := rig.pivot()
	var people := session.people.size()
	var tick := session.clock.tick
	var bench: Benchmark = main.run_benchmark()
	bench.time_scale = 0.04
	bench.file_path = OUT
	var summary := [""]
	bench.finished.connect(func(text: String) -> void: summary[0] = text)
	assert_eq(main.run_benchmark(), bench, "one at a time")
	for i in 600:
		await wait_frames(1)
		if summary[0] != "":
			break
	assert_true(String(summary[0]).contains("FPS"), "told: %s" % summary[0])
	var written := FileAccess.get_file_as_string(OUT)
	for part in ["box", "fire", "around", "across", "all"]:
		assert_true(written.contains(part), "%s measured" % part)
	assert_true(written.contains("people %d" % people))
	await wait_frames(90)
	assert_true(rig.pivot().distance_to(before_pivot) < 1.0, "the camera back where it was")
	assert_eq(session.people.size(), people)
	assert_eq(session.clock.tick, tick, "the world did not move on (paused)")
