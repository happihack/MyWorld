class_name JournalButton
extends Button
## HUD button that opens the player's history (bible §27.2) — until the menu
## it will live in exists. Draws its own open-book glyph, like the Home button
## below it.

const SIZE := 140.0


func _init() -> void:
	name = "JournalButton"
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	tooltip_text = "Your history"
	custom_minimum_size = Vector2(SIZE, SIZE)
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(center, radius, HomeButton.BACKDROP_PRESSED if button_pressed else HomeButton.BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 48, HomeButton.RING, maxf(radius * 0.05, 2.0), true)
	# An open book: two pages leaning away from the spine, a few lines on each.
	var u := radius * 0.5
	for side: float in [-1.0, 1.0]:
		var page := PackedVector2Array([
			center + Vector2(0.0, -u * 0.62),
			center + Vector2(side * u * 1.12, -u * 0.86),
			center + Vector2(side * u * 1.12, u * 0.62),
			center + Vector2(0.0, u * 0.86),
		])
		draw_colored_polygon(page, HomeButton.GLYPH)
		for row in 3:
			var y := -u * 0.34 + row * u * 0.36
			draw_line(center + Vector2(side * u * 0.22, y + u * 0.02), center + Vector2(side * u * 0.9, y - u * 0.13),
				HomeButton.BACKDROP_PRESSED, maxf(u * 0.09, 2.0), true)
	draw_line(center + Vector2(0.0, -u * 0.62), center + Vector2(0.0, u * 0.86), HomeButton.BACKDROP_PRESSED, maxf(u * 0.08, 2.0), true)
