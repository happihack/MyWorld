extends SceneTree
## Writes tests/fixtures/saves/v<SAVE_VERSION>_world.sav: a world in today's
## save format, a few game days old (M22's policy: every save format the game
## has written has a fixture, opened by test_migration_chain_all_fixtures).
## Run it once, when SAVE_VERSION goes up — never over an existing fixture.
##
##   godot --headless --path . -s res://tests/soak/make_save_fixture.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var config: Node = root.get_node("Config")
	root.get_node("Settings").call("use_path", "user://make_fixture/settings.cfg")
	config.save.save_root = "user://make_fixture/saves"
	DirAccess.make_dir_recursive_absolute(config.save.save_root)
	var saves: Node = root.get_node("SaveManager")
	var version: int = saves.get("SAVE_VERSION")
	var to := "res://tests/fixtures/saves/v%d_world.sav" % version
	if FileAccess.file_exists(to):
		print("FIXTURE %s is there already: fixtures are never written over" % to)
		quit(1)
		return
	var s: Node = load("res://scripts/simulation/world_session.gd").new()
	root.add_child(s)
	s.create_new(28000 + version)
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	var simulator: GDScript = load("res://scripts/simulation/offline_simulator.gd")
	simulator.new(s).run(5 * 1440) # (a few days lived: stores, buildings, events)
	if not saves.call("save_world", s, &"fixture"):
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(saves.call("world_dir", s.world_id).path_join("world.sav"))
	var file := FileAccess.open(to, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	print("FIXTURE %s (%d bytes) world %s" % [to, bytes.size(), s.world_id])
	quit(0)
