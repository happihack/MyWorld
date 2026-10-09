extends Node
## Boot scene: runs once at startup after the autoloads (Log -> Config ->
## EventBus -> Settings -> SaveManager) are ready, records environment info,
## then hands over to the splash screen (then the main menu, then the world
## chosen there: 2026-10-08).

const SPLASH_SCENE := "res://scenes/main/splash.tscn"


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
	# (The sounds are made once the splash has played: it stuttered beside them.)
	AudioManager.hold_synthesis(true)
	get_tree().change_scene_to_file.call_deferred(SPLASH_SCENE)
