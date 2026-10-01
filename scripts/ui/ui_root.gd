class_name UIRoot
extends CanvasLayer
## Root of all in-game UI (HUD, cards, menus, toasts; bible §26.4).
## For now: title, version, the hidden debug unlock and back-button handling.
## The panel stack that the back button closes first arrives in M2.4.

## Tapping the version label this many times within UNLOCK_WINDOW_MS toggles
## Settings "debug/enabled" (makes debug tools reachable in release builds).
const UNLOCK_TAPS := 7
const UNLOCK_WINDOW_MS := 3000

@onready var _version_label: Label = %VersionLabel

var _session: WorldSession
var _unlock_taps: Array[int] = []


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	_version_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_version_label.add_to_group(InputRouter.UI_BLOCKER_GROUP)
	_version_label.gui_input.connect(_on_version_label_input)
	EventBus.back_requested.connect(_on_back_requested)


func bind_session(session: WorldSession) -> void:
	_session = session


func register_unlock_tap(time_ms: int) -> void:
	_unlock_taps.append(time_ms)
	while not _unlock_taps.is_empty() and time_ms - _unlock_taps[0] > UNLOCK_WINDOW_MS:
		_unlock_taps.pop_front()
	if _unlock_taps.size() >= UNLOCK_TAPS:
		_unlock_taps.clear()
		var enabled := not bool(Settings.get_value(&"debug/enabled"))
		Settings.set_value(&"debug/enabled", enabled)
		Log.info(Log.Category.UI, "Debug tools toggled via hidden unlock", {"enabled": enabled})


func _on_version_label_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
		register_unlock_tap(Time.get_ticks_msec())
		_version_label.accept_event()


func _on_back_requested() -> void:
	# No panels exist yet, so back means "leave the game". Listeners of
	# app_quit_requested (e.g. SaveManager) run synchronously before we quit.
	Log.info(Log.Category.UI, "Back with no open panels: quitting")
	EventBus.app_quit_requested.emit()
	get_tree().quit()
