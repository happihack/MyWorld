class_name HomeButton
extends Button
## HUD button that returns the camera to the settlement (bible §26.4, spec §7:
## "the camera must never become lost"). Draws its own house glyph, so it needs
## no image asset and stays crisp at any UI scale.

const BACKDROP := Color(0.07, 0.09, 0.12, 0.55)
const BACKDROP_PRESSED := Color(0.07, 0.09, 0.12, 0.85)
const GLYPH := Color(0.949, 0.902, 0.788, 0.95)
const RING := Color(0.784, 0.631, 0.396, 0.9)


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	tooltip_text = "Home"
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(center, radius, BACKDROP_PRESSED if button_pressed else BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 48, RING, maxf(radius * 0.05, 2.0), true)
	# House: roof triangle, body, doorway. Sized relative to the button.
	var u := radius * 0.46
	var roof := PackedVector2Array([
		center + Vector2(-u * 1.15, -u * 0.05),
		center + Vector2(0.0, -u * 1.05),
		center + Vector2(u * 1.15, -u * 0.05),
	])
	draw_colored_polygon(roof, GLYPH)
	draw_rect(Rect2(center + Vector2(-u * 0.78, -u * 0.05), Vector2(u * 1.56, u * 0.98)), GLYPH)
	draw_rect(Rect2(center + Vector2(-u * 0.22, u * 0.33), Vector2(u * 0.44, u * 0.60)), BACKDROP_PRESSED)
