class_name UIRoot
extends CanvasLayer
## Root of all in-game UI (HUD, cards, menus, toasts; bible §26.4).
## For now: title, version and back-button handling. The panel stack that the
## back button closes first arrives in M2.4.

@onready var _version_label: Label = %VersionLabel

var _session: WorldSession


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	EventBus.back_requested.connect(_on_back_requested)


func bind_session(session: WorldSession) -> void:
	_session = session


func _on_back_requested() -> void:
	# No panels exist yet, so back means "leave the game". Listeners of
	# app_quit_requested (e.g. SaveManager) run synchronously before we quit.
	Log.info(Log.Category.UI, "Back with no open panels: quitting")
	EventBus.app_quit_requested.emit()
	get_tree().quit()
