class_name DebugOverlay
extends CanvasLayer
## Toggleable performance/debug overlay (bible §31, spec §70, track T1).
##
## Systems add lines with register_section(); each provider is a Callable that
## returns a String and is only called while the overlay is visible.
## Toggle: F3 (desktop) or three-finger tap (device). Available in debug builds,
## or in release once Settings "debug/enabled" is set (hidden 7-tap unlock).

const REFRESH_INTERVAL_S := 0.25
const MB := 1024.0 * 1024.0

@onready var _label: Label = %OverlayLabel
@onready var _panel: Control = %OverlayPanel

var _sections: Dictionary = {} # StringName -> Callable, in registration order
var _last_gesture := "-"
# Running totals of the current two-finger gesture (pinch/drag/twist arrive as
# separate incremental events; one combined line is what a tester can read).
var _multi_scale := 1.0
var _multi_pan := Vector2.ZERO
var _multi_twist := 0.0
var _refresh_timer := 0.0


static func is_available() -> bool:
	return OS.is_debug_build() or bool(Settings.get_value(&"debug/enabled"))


## F4 was pressed (debug builds): the benchmark is wanted (M21.1).
signal benchmark_requested

func _ready() -> void:
	register_section(&"engine", _engine_section)
	register_section(&"input", func() -> String: return "gesture %s" % _last_gesture)
	_set_shown(is_available() and bool(Settings.get_value(&"debug/overlay_visible")))
	Settings.setting_changed.connect(_on_setting_changed)


## Adds (or replaces) a named block of lines. Keep providers cheap.
func register_section(section: StringName, provider: Callable) -> void:
	_sections[section] = provider


func unregister_section(section: StringName) -> void:
	_sections.erase(section)


func toggle() -> void:
	if not is_available():
		return
	var shown := not _panel.visible
	_set_shown(shown)
	Settings.set_value(&"debug/overlay_visible", shown)
	Log.debug(Log.Category.PERFORMANCE, "Debug overlay toggled", {"visible": shown})


func is_shown() -> bool:
	return _panel.visible


## Hook for InputRouter.gesture_recognized.
func on_gesture(gesture: Gesture) -> void:
	if gesture.type == Gesture.Type.THREE_FINGER_TAP:
		toggle()
	match gesture.type:
		Gesture.Type.MULTI_START:
			_multi_scale = 1.0
			_multi_pan = Vector2.ZERO
			_multi_twist = 0.0
			_last_gesture = _multi_summary()
			return
		Gesture.Type.PINCH:
			_multi_scale *= gesture.scale
			_last_gesture = _multi_summary()
			return
		Gesture.Type.TWO_FINGER_DRAG:
			_multi_pan += gesture.delta
			_last_gesture = _multi_summary()
			return
		Gesture.Type.TWIST:
			_multi_twist += gesture.angle
			_last_gesture = _multi_summary()
			return
		Gesture.Type.MULTI_END:
			return # keep the summary on screen
	var text := "%s %s" % [gesture.type_name(), gesture.position.round()]
	match gesture.type:
		Gesture.Type.DRAG_START, Gesture.Type.LONG_PRESS:
			text += " hold %d ms" % gesture.hold_ms
		Gesture.Type.DRAG_END, Gesture.Type.SWIPE:
			text += " v %d" % roundi(gesture.velocity.length())
	_last_gesture = text


func _multi_summary() -> String:
	return "TWO_FINGER pinch x%.2f  drag %s  twist %.0f deg" % [
		_multi_scale, _multi_pan.round(), rad_to_deg(_multi_twist)]


## Rebuilds the text immediately (used by tests and on show).
func refresh() -> void:
	var lines := PackedStringArray()
	for section: StringName in _sections:
		var provider: Callable = _sections[section]
		if not provider.is_valid():
			continue
		lines.append(str(provider.call()))
	_label.text = "\n".join(lines)


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle_overlay"):
		toggle()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F4 \
			and is_available():
		# (F4: the benchmark — also from adb, `input keyevent 134`, M21.1.)
		benchmark_requested.emit()
		get_viewport().set_input_as_handled()


func _set_shown(shown: bool) -> void:
	_panel.visible = shown
	set_process(shown) # zero cost while hidden
	if shown:
		_refresh_timer = 0.0


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"debug/enabled" and not bool(value) and not OS.is_debug_build():
		_set_shown(false)


func _engine_section() -> String:
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := 1000.0 / fps if fps > 0.0 else 0.0
	var lines := PackedStringArray([
		# TIME_PROCESS spans the whole idle step incl. vsync wait, so it is not
		# CPU time. Real CPU/GPU render timings come with the M23 toolkit.
		"FPS %d  frame %.1f ms  process %.1f ms  physics %.1f ms" % [
			fps, frame_ms,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		],
		"draw %d  objs %d  prims %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		],
		"mem %.1f MB (static, debug only)  vram %.1f MB" % [
			Performance.get_monitor(Performance.MEMORY_STATIC) / MB,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / MB,
		],
		"objects %d  nodes %d  %s build" % [
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"debug" if OS.is_debug_build() else "release",
		],
	])
	return "\n".join(lines)
