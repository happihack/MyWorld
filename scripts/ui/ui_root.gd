class_name UIRoot
extends CanvasLayer
## Root of all in-game UI (HUD, cards, menus, toasts; bible §26.4).
## For now: title, version and back-button handling. The panel stack that the
## back button closes first arrives in M2.4.

@onready var _version_label: Label = %VersionLabel
@onready var _gesture_label: Label = %GestureDebugLabel

var _session: WorldSession


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	# Proves touch works on devices; replaced by the debug overlay in M0.5.
	_gesture_label.visible = OS.is_debug_build()
	EventBus.back_requested.connect(_on_back_requested)


func bind_session(session: WorldSession) -> void:
	_session = session


func show_gesture(gesture: Gesture) -> void:
	if not _gesture_label.visible:
		return
	var text := "gesture: %s  pos %s" % [gesture.type_name(), gesture.position.round()]
	match gesture.type:
		Gesture.Type.DRAG_START, Gesture.Type.LONG_PRESS:
			text += "  hold %d ms" % gesture.hold_ms
		Gesture.Type.DRAG_END, Gesture.Type.SWIPE:
			text += "  v %d" % roundi(gesture.velocity.length())
		Gesture.Type.PINCH:
			text += "  x%.3f" % gesture.scale
		Gesture.Type.TWIST:
			text += "  %.1f deg" % rad_to_deg(gesture.angle)
	_gesture_label.text = text


func _on_back_requested() -> void:
	# No panels exist yet, so back means "leave the game". Listeners of
	# app_quit_requested (e.g. SaveManager) run synchronously before we quit.
	Log.info(Log.Category.UI, "Back with no open panels: quitting")
	EventBus.app_quit_requested.emit()
	get_tree().quit()
