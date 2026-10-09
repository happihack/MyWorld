extends SceneTree
## A probe (not a test): starts the game as it starts (boot → splash) in a
## window, with saves and settings of its own, and notes every frame that
## took long while the splash plays — and which frame of the mascot it was on.
## Run (not headless): -s res://tests/tools/probe_splash.gd


func _init() -> void:
	await process_frame
	var dir := "C:/tmp/wiab_probe_splash"
	DirAccess.make_dir_recursive_absolute(dir.path_join("saves"))
	root.get_node("Config").save.save_root = dir.path_join("saves")
	root.get_node("Settings").use_path(dir.path_join("settings.cfg"))
	change_scene_to_file("res://scenes/main/boot.tscn")
	var last := Time.get_ticks_usec()
	var started := last
	var slow := 0
	while (Time.get_ticks_usec() - started) < 8_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		var took := (now - last) / 1000.0
		last = now
		var scene := current_scene
		var frame := -1
		if scene != null and scene.has_method("mascot_frame"):
			frame = scene.mascot_frame()
		if took > 34.0:
			slow += 1
			print("PROBE %.2f s: a frame of %.0f ms (scene %s, mascot frame %d)" % [(now - started) / 1e6, took,
				scene.name if scene != null else "-", frame])
		if scene != null and scene.name == "Title":
			break
	print("PROBE done: %d slow frames" % slow)
	quit()
