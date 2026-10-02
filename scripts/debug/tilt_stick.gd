class_name TiltStick
extends VBoxContainer
## Debug: a stick on the screen that stands in for tilting the device, and
## four buttons that stand in for shaking it (for emulators and desktops —
## see VirtualSensors). Lives on the debug overlay's layer, at the right
## edge of the screen, and is only there while the overlay is shown.
##
## Push the stick up and the top edge of the box goes down, as if the
## device were tilted away; let go and it comes back level.

const PAD_SIZE := 230.0
const KNOB_RADIUS := 34.0
const EDGE_MARGIN := 16.0
const BUTTON_HEIGHT := 72.0
const FONT_SIZE := 22
const SHAKE_LABELS: PackedStringArray = ["L", "M", "S", "X"]

var _pad: Control
var _knob := Vector2.ZERO # -1 … 1, the screen's way (y down)
var _held := false
var _buttons: Array[Button] = []


func _init() -> void:
	name = "TiltStick"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 8)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_right = -EDGE_MARGIN
	offset_left = -EDGE_MARGIN - PAD_SIZE
	offset_top = -PAD_SIZE * 0.5 - 60.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pad = Control.new()
	_pad.name = "Pad"
	_pad.custom_minimum_size = Vector2(PAD_SIZE, PAD_SIZE)
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	_pad.draw.connect(_draw_pad)
	_pad.gui_input.connect(_on_pad_input)
	add_child(_pad)
	var row := HBoxContainer.new()
	row.name = "Shakes"
	row.add_theme_constant_override(&"separation", 6)
	add_child(row)
	for shake_class in SHAKE_LABELS.size():
		var button := Button.new()
		button.name = "Shake%d" % shake_class
		button.text = SHAKE_LABELS[shake_class]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", FONT_SIZE)
		button.tooltip_text = "Shake: %s" % ShakeDetector.class_name_of(shake_class)
		button.add_to_group(InputRouter.UI_BLOCKER_GROUP)
		button.pressed.connect(func() -> void: SensorManager.virtual_shake(shake_class))
		row.add_child(button)
		_buttons.append(button)


func _exit_tree() -> void:
	release()


## Where the stick is held: -1 … 1, x to the right, y up (as the tilt has it).
func stick() -> Vector2:
	return Vector2(_knob.x, -_knob.y)


## Holds the stick at a point of the pad (its own coordinates).
func hold_at(point: Vector2) -> void:
	var reach := PAD_SIZE * 0.5 - KNOB_RADIUS
	_knob = ((point - Vector2(PAD_SIZE, PAD_SIZE) * 0.5) / reach).limit_length(1.0)
	_held = true
	SensorManager.set_virtual_stick(stick())
	_pad.queue_redraw()


func release() -> void:
	if not _held and _knob == Vector2.ZERO:
		return
	_held = false
	_knob = Vector2.ZERO
	SensorManager.set_virtual_stick(Vector2.ZERO)
	if _pad != null:
		_pad.queue_redraw()


func is_held() -> bool:
	return _held


func shake_button(shake_class: int) -> Button:
	return _buttons[shake_class] if shake_class >= 0 and shake_class < _buttons.size() else null


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()


func _on_pad_input(event: InputEvent) -> void:
	# (On Android every touch arrives twice — as a touch and as an emulated
	# mouse; both say the same, so both may be listened to.)
	var press := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	var move := event as InputEventMouseMotion
	var drag := event as InputEventScreenDrag
	if press != null and press.button_index == MOUSE_BUTTON_LEFT:
		if press.pressed:
			hold_at(press.position)
		else:
			release()
		_pad.accept_event()
	elif touch != null:
		if touch.pressed:
			hold_at(touch.position)
		else:
			release()
		_pad.accept_event()
	elif move != null and _held:
		hold_at(move.position)
		_pad.accept_event()
	elif drag != null and _held:
		hold_at(drag.position)
		_pad.accept_event()


func _draw_pad() -> void:
	var center := Vector2(PAD_SIZE, PAD_SIZE) * 0.5
	var reach := PAD_SIZE * 0.5 - KNOB_RADIUS
	_pad.draw_circle(center, PAD_SIZE * 0.5, Color(0.0, 0.0, 0.0, 0.5))
	_pad.draw_arc(center, PAD_SIZE * 0.5 - 2.0, 0.0, TAU, 48, Color(0.85, 1.0, 0.85, 0.7), 2.0, true)
	_pad.draw_line(center - Vector2(reach, 0.0), center + Vector2(reach, 0.0), Color(0.85, 1.0, 0.85, 0.25), 2.0)
	_pad.draw_line(center - Vector2(0.0, reach), center + Vector2(0.0, reach), Color(0.85, 1.0, 0.85, 0.25), 2.0)
	_pad.draw_circle(center + _knob * reach, KNOB_RADIUS, Color(0.85, 1.0, 0.85, 0.9 if _held else 0.55))
