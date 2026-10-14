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
	HomeButton.draw_round(self, 5, &"stories", button_pressed)
