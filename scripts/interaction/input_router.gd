class_name InputRouter
extends Node
## Bridges Godot input events to the GestureRecognizer and re-broadcasts the
## results (bible §23.1). World-facing systems (camera, InteractionManager)
## connect to `gesture_recognized`; they never read raw input.
##
## - Touch events (real, or emulated from the mouse on desktop) drive gestures.
## - Mouse events that Godot emulates from touch are ignored (the touch itself
##   is already handled); GUI Controls still receive them.
## - A touch that starts on a visible Control in the "ui_blocker" group belongs
##   to the UI and never reaches the world.
## - Desktop extras: mouse wheel = pinch at the cursor, right-drag = two-finger drag.

signal gesture_recognized(gesture: Gesture)

const UI_BLOCKER_GROUP := &"ui_blocker"
const DP_REFERENCE_DPI := 160.0
const WHEEL_ZOOM_STEP := 1.1
## Sanity bounds for units_per_dp (a minimized/headless window can report nonsense).
const UNITS_PER_DP_MIN := 0.25
const UNITS_PER_DP_MAX := 8.0

var recognizer: GestureRecognizer

var _ignored_touches: Dictionary = {} # index -> true for touches owned by UI
var _right_drag_last := Vector2.ZERO
var _right_dragging := false


func _ready() -> void:
	recognizer = GestureRecognizer.new(Config.interaction, _compute_units_per_dp())
	Log.debug(Log.Category.UI, "Input scale", {"units_per_dp": recognizer.units_per_dp})
	recognizer.recognized.connect(_on_recognized)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	EventBus.app_paused.connect(_cancel_all)
	EventBus.app_focus_changed.connect(func(has_focus: bool) -> void:
		if not has_focus:
			_cancel_all())


func _process(_delta: float) -> void:
	recognizer.update(Time.get_ticks_msec())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var now := Time.get_ticks_msec()
	if event.pressed:
		if is_over_ui(event.position):
			_ignored_touches[event.index] = true
			return
		recognizer.touch_down(event.index, event.position, now)
	else:
		if _ignored_touches.erase(event.index):
			return
		if event.canceled:
			_cancel_all()
			return
		recognizer.touch_up(event.index, event.position, now)
	get_viewport().set_input_as_handled()


func _handle_drag(event: InputEventScreenDrag) -> void:
	if _ignored_touches.has(event.index):
		return
	recognizer.touch_move(event.index, event.position, Time.get_ticks_msec())
	get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return # emulated from touch; the touch event is the source of truth
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed and not is_over_ui(event.position):
				var g := Gesture.new(Gesture.Type.PINCH)
				g.position = event.position
				g.scale = WHEEL_ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_ZOOM_STEP
				g.touch_count = 2
				g.time_ms = Time.get_ticks_msec()
				_on_recognized(g)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_RIGHT:
			if event.pressed and not is_over_ui(event.position):
				_right_dragging = true
				_right_drag_last = event.position
				get_viewport().set_input_as_handled()
			elif not event.pressed:
				_right_dragging = false


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION or not _right_dragging:
		return
	var g := Gesture.new(Gesture.Type.TWO_FINGER_DRAG)
	g.position = event.position
	g.delta = event.position - _right_drag_last
	g.touch_count = 2
	g.time_ms = Time.get_ticks_msec()
	_right_drag_last = event.position
	_on_recognized(g)
	get_viewport().set_input_as_handled()


## True if `pos` (viewport units) is over a visible UI blocker Control.
func is_over_ui(pos: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group(UI_BLOCKER_GROUP):
		var control := node as Control
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(pos):
			return true
	return false


func _on_recognized(gesture: Gesture) -> void:
	Log.trace(Log.Category.UI, "Gesture", {"type": gesture.type_name(), "pos": gesture.position})
	gesture_recognized.emit(gesture)


func _cancel_all() -> void:
	_ignored_touches.clear()
	_right_dragging = false
	recognizer.cancel_all(Time.get_ticks_msec())


func _on_viewport_size_changed() -> void:
	recognizer.units_per_dp = _compute_units_per_dp()
	recognizer.cancel_all(Time.get_ticks_msec()) # rotation mid-gesture: start clean


## Converts dp thresholds into viewport units. Event positions are in viewport
## (canvas) units, which the canvas_items stretch scales relative to the screen.
func _compute_units_per_dp() -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = DP_REFERENCE_DPI * DisplayServer.screen_get_scale()
	var screen_px_per_dp := dpi / DP_REFERENCE_DPI
	var window_width := float(get_window().size.x)
	var viewport_width := get_viewport().get_visible_rect().size.x
	var screen_px_per_unit := window_width / viewport_width if viewport_width > 0.0 else 1.0
	if screen_px_per_unit <= 0.0:
		screen_px_per_unit = 1.0
	return clampf(screen_px_per_dp / screen_px_per_unit, UNITS_PER_DP_MIN, UNITS_PER_DP_MAX)
