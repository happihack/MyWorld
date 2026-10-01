class_name CloseButton
extends Button
## The ✕ of a card. Draws its own cross, so it needs no glyph from the font
## and no image asset.

const SIZE := 120.0


func _init() -> void:
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(SIZE, SIZE)
	tooltip_text = "Close"


func _ready() -> void:
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var arm := minf(size.x, size.y) * 0.16
	if button_pressed:
		draw_circle(center, minf(size.x, size.y) * 0.42, UITheme.PRESSED)
	for direction: Vector2 in [Vector2(1, 1), Vector2(1, -1)]:
		draw_line(center - direction * arm, center + direction * arm, UITheme.INK, 5.0, true)
