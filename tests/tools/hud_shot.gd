extends SceneTree
## A tool (not a test): opens the game on a fresh world in a window the shape
## of a phone and saves pictures of the HUD — the blessings out, their card,
## the lights in the sky — for judging the look without a phone to hand.
## Run in a window (not headless):
##   godot --path . -s res://tests/tools/hud_shot.gd -- --out=/tmp/hud [--size=540x960]
## Writes <out>_bar.png, <out>_card.png, <out>_lights.png.
## The work is in hud_shot_lib.gd, loaded once the autoloads exist.

var _out := ""
var _size := Vector2i(540, 960)


func _init() -> void:
	_out = ProjectSettings.globalize_path("user://hud")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--size="):
			var wh := arg.get_slice("=", 1).split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
	await process_frame
	DisplayServer.window_set_size(_size)
	root.size = _size
	var lib: Script = load("res://tests/tools/hud_shot_lib.gd")
	var ok: bool = await lib.call(&"shoot", self, _out)
	quit(0 if ok else 1)
