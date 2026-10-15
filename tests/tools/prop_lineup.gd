extends SceneTree
## A tool (not a test): draws a lineup of the game's shapes with the real prop
## shader and sun, from the game's angle, and saves it as a picture, for
## judging silhouettes while they are worked on (the ART section of the plan).
## Run in a window (not headless):
##   godot --path . -s res://tests/tools/prop_lineup.gd -- --out=/tmp/lineup.png
##     [--set=nature|buildings|animals|loose|all] [--size=1600x900] [--season=0..1] [--night=0..1]
## The work is in prop_lineup_lib.gd, loaded once the autoloads exist.

var _out := ""
var _set := "all"
var _size := Vector2i(1600, 900)
var _season := 0.0
var _night := 0.0


func _init() -> void:
	_out = ProjectSettings.globalize_path("user://lineup.png")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--set="):
			_set = arg.get_slice("=", 1)
		elif arg.begins_with("--season="):
			_season = float(arg.get_slice("=", 1))
		elif arg.begins_with("--night="):
			_night = float(arg.get_slice("=", 1))
		elif arg.begins_with("--size="):
			var wh := arg.get_slice("=", 1).split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
	await process_frame
	DisplayServer.window_set_size(_size)
	root.size = _size
	var lib: Script = load("res://tests/tools/prop_lineup_lib.gd")
	var scene: Node3D = lib.call(&"build", _set, _season, _night)
	root.add_child(scene)
	for i in 6:
		await process_frame
	var image := root.get_texture().get_image()
	var err := image.save_png(_out)
	print("lineup: ", _out, " ", error_string(err))
	quit(0 if err == OK else 1)
