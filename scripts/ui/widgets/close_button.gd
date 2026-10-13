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


## The ink of the cross: dark on paper; a card over the world may ask for chalk.
var ink: Color = UITheme.INK


func _draw() -> void:
	var center := size * 0.5
	var side := minf(size.x, size.y) * 0.44
	if button_pressed:
		draw_colored_polygon(HandDraw.circle_points(center, minf(size.x, size.y) * 0.42, 9, 0.0), UITheme.PRESSED)
	HandIcons.draw(self, &"close", Rect2(center - Vector2(side, side), Vector2(side * 2.0, side * 2.0)), ink)
