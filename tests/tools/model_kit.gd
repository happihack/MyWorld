extends SceneTree
## Writes the Blender reference kit (docs/blender_kit.md):
##   godot --headless --path . -s res://tests/tools/model_kit.gd
## writes docs/blender_kit/*.glb. The work is in model_kit_lib.gd, loaded once
## the autoloads exist (this script is compiled before them).


func _init() -> void:
	await process_frame
	var lib: Script = load("res://tests/tools/model_kit_lib.gd")
	var failed: int = lib.call(&"write_all")
	quit(1 if failed > 0 else 0)
