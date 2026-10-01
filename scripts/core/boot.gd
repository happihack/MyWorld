extends Node
## Boot scene: runs once at startup after the autoloads (Log -> Config ->
## EventBus -> Settings -> SaveManager) are ready, records environment info,
## then hands over to the Main scene (which continues or creates a world).

const MAIN_SCENE := "res://scenes/main/main.tscn"


func _ready() -> void:
	var screen := DisplayServer.screen_get_size()
	Log.info(Log.Category.CORE, "Boot", {
		"version": ProjectSettings.get_setting("application/config/version", "?"),
		"godot": Engine.get_version_info().string,
		"os": OS.get_name(),
		"model": OS.get_model_name(),
		"locale": OS.get_locale(),
		"screen": "%dx%d" % [screen.x, screen.y],
		"dpi": DisplayServer.screen_get_dpi(),
		"debug_build": OS.is_debug_build(),
	})
	if not Config.problems.is_empty():
		Log.warn(Log.Category.CORE, "Starting with config problems", {"problems": Config.problems})
	Log.info(Log.Category.SAVE, "Save root", {
		"path": ProjectSettings.globalize_path(Config.save.save_root),
		"latest_world": SaveManager.find_latest_world_id(),
	})
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)
