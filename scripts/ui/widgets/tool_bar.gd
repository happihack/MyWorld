class_name ToolBar
extends HBoxContainer
## The player's tools (bible §23.2, §26.4): a compact row at the bottom of the
## screen. Only tools that exist are shown — the bar grows as the player's
## powers do.

signal tool_selected(id: StringName)

## Distance of the bar's bottom edge from the bottom of the screen (the same
## row as the Home button).
const BOTTOM_MARGIN := 144.0
const GAP := 24

var _buttons: Dictionary = {} # id -> ToolButton
var _current: StringName = &""


func _init() -> void:
	add_theme_constant_override(&"separation", GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE # only the buttons take touches


func _ready() -> void:
	get_viewport().size_changed.connect(place)
	place()


## Shows one button per tool id, in order.
func set_tools(ids: Array[StringName]) -> void:
	for button: ToolButton in _buttons.values():
		button.queue_free()
	_buttons.clear()
	for id in ids:
		var button := ToolButton.new(id)
		button.selected = id == _current
		button.pressed.connect(_on_pressed.bind(id))
		add_child(button)
		_buttons[id] = button
	place()


## Lights the button of the active tool.
func set_current(id: StringName) -> void:
	_current = id
	for key: StringName in _buttons:
		(_buttons[key] as ToolButton).selected = key == id


func current() -> StringName:
	return _current


func button(id: StringName) -> ToolButton:
	return _buttons.get(id)


func tool_ids() -> Array:
	return _buttons.keys()


## Centred at the bottom of the screen.
func place() -> void:
	if not is_inside_tree():
		return
	reset_size()
	var view := get_viewport_rect().size
	position = Vector2((view.x - size.x) * 0.5, view.y - BOTTOM_MARGIN - size.y)


func _on_pressed(id: StringName) -> void:
	tool_selected.emit(id)
