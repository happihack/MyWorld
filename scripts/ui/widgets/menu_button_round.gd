class_name MenuButtonRound
extends Button
## HUD button in the top-left corner (bible §26.4: the ☰): opens the menu
## (MainMenu). Draws its own three lines, like the other round buttons.

const SIZE := 104.0
const EDGE_MARGIN := 24.0
const TOP := 56.0


func _init() -> void:
	name = "MenuButton"
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	tooltip_text = "Menu"
	custom_minimum_size = Vector2(SIZE, SIZE)
	position = Vector2(EDGE_MARGIN, TOP)
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(center, radius, HomeButton.BACKDROP_PRESSED if button_pressed else HomeButton.BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 48, HomeButton.RING, maxf(radius * 0.05, 2.0), true)
	var half := radius * 0.46
	for row in 3:
		var y := (row - 1) * radius * 0.32
		draw_line(center + Vector2(-half, y), center + Vector2(half, y), HomeButton.GLYPH, maxf(radius * 0.11, 3.0), true)
