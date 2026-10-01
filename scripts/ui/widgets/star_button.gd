class_name StarButton
extends Button
## "Mark as important": a star, hollow until it is on (bible §26.6). Drawn,
## not typed, so it needs no glyph in the font.

const INK := Color(0.949, 0.902, 0.788, 0.9)
const LIT := Color(1.0, 0.82, 0.36)

var marked := false:
	set(value):
		marked = value
		queue_redraw()


func _init() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(UITheme.TOUCH_TARGET * 0.8, UITheme.TOUCH_TARGET * 0.8)
	tooltip_text = "Mark as important"


func _ready() -> void:
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var outer := minf(size.x, size.y) * 0.30
	if button_pressed:
		draw_circle(center, minf(size.x, size.y) * 0.46, UITheme.PRESSED)
	var points := PackedVector2Array()
	for i in 10:
		var radius := outer if i % 2 == 0 else outer * 0.44
		var angle := -PI * 0.5 + TAU * i / 10.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	if marked:
		draw_colored_polygon(points, LIT)
	else:
		points.append(points[0])
		draw_polyline(points, INK, 3.0, true)
