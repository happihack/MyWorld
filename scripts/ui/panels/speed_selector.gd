class_name SpeedSelector
extends UIPanel
## The four speeds to choose from (bible §9.2), opened by holding the speed
## button: Pause, Normal, Fast, Very fast — each with its sign, the current
## one marked. Touching the world puts it away.

signal chosen(index: int)

const ROW_HEIGHT := UITheme.TOUCH_TARGET * 0.86
const WIDTH := 420.0
const EDGE_MARGIN := 32.0

var _rows: Array[Button] = []
var _current := -1


func _init() -> void:
	super()
	name = "SpeedSelector"
	transient = true
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 0)
	add_child(list)
	for index in 4:
		var row := Button.new()
		row.name = "Speed%d" % index
		row.text = "           " + MemoryText.translate("SPEED_%d" % index) # (room for the sign, drawn below)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(WIDTH, ROW_HEIGHT)
		row.pressed.connect(_on_row_pressed.bind(index))
		row.draw.connect(_draw_row.bind(row, index))
		list.add_child(row)
		_rows.append(row)


## Marks the speed the world runs at now.
func set_current(index: int) -> void:
	_current = index
	for row in _rows:
		row.queue_redraw()


func current() -> int:
	return _current


func row(index: int) -> Button:
	return _rows[index] if index >= 0 and index < _rows.size() else null


## Puts the selector under `below` (the speed button), inside the screen.
func place_under(below: Rect2) -> void:
	reset_size()
	var view := get_viewport_rect().size
	position = Vector2(clampf(below.end.x - size.x, EDGE_MARGIN, maxf(view.x - EDGE_MARGIN - size.x, EDGE_MARGIN)),
		minf(below.end.y + 16.0, maxf(view.y - size.y - EDGE_MARGIN, 0.0)))


func _on_row_pressed(index: int) -> void:
	chosen.emit(index)
	close()


func _draw_row(row: Button, index: int) -> void:
	var here := index == _current
	var center := Vector2(ROW_HEIGHT * 0.5 + 6.0, row.size.y * 0.5)
	if here:
		row.draw_arc(center, ROW_HEIGHT * 0.36, 0.0, TAU, 32, SpeedControl.LIT, 3.0, true)
	SpeedControl.draw_speed_glyph(row, center, ROW_HEIGHT * 0.2, index, SpeedControl.LIT if here else UITheme.INK)
