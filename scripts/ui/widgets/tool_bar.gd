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
## Room kept free at either side of the screen (the Home button stands in
## the same row): with many tools the buttons get smaller rather than run
## under it — but never smaller than a finger.
const SIDE_RESERVE := 150.0
const SMALLEST := 96.0

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
		remove_child(button) # (at once: a button on its way out must not take room in the row)
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


## A tool has just shown itself: its button glows for a while.
func glow(id: StringName, seconds: float) -> void:
	var shown: ToolButton = _buttons.get(id)
	if shown != null:
		shown.glow(seconds)


func button(id: StringName) -> ToolButton:
	return _buttons.get(id)


func tool_ids() -> Array:
	return _buttons.keys()


## Centred at the bottom of the screen.
func place() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var count := _buttons.size()
	if count > 0:
		var room := view.x - 2.0 * SIDE_RESERVE - (count - 1) * GAP
		var side := clampf(floorf(room / count), SMALLEST, ToolButton.SIZE)
		for button: ToolButton in _buttons.values():
			button.custom_minimum_size = Vector2(side, side)
			button.size = Vector2(side, side)
	reset_size()
	position = Vector2((view.x - size.x) * 0.5, view.y - BOTTOM_MARGIN - size.y)


func _on_pressed(id: StringName) -> void:
	tool_selected.emit(id)
