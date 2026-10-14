class_name HomeButton
extends Button
## HUD button that returns the camera to the settlement (bible §26.4, spec §7:
## "the camera must never become lost"). A chalk circle with a house drawn in
## it by hand, so it needs no image asset and stays crisp at any UI scale.

## (The colours of the round buttons over the world; the others draw with them too.)
const BACKDROP := UITheme.CHALK_FILL
const BACKDROP_PRESSED := UITheme.CHALK_FILL_DARK
const GLYPH := UITheme.CHALK
const RING := UITheme.CHALK


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	tooltip_text = "Home"
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	draw_round(self, 3, &"home", button_pressed)


## A chalk circle filling `on`, with the icon `id` in it: the round HUD buttons.
static func draw_round(on: Control, seed: int, id: StringName, pressed: bool, ring: Color = RING, ink: Color = GLYPH,
		fill: Color = Color(0, 0, 0, 0)) -> void:
	var center := on.size * 0.5
	var radius := minf(on.size.x, on.size.y) * 0.5 - 7.0
	var backdrop := fill if fill.a > 0.0 else (BACKDROP_PRESSED if pressed else BACKDROP)
	HandDraw.chalk_circle(on, center, radius, ring, UITheme.CHALK_WIDTH, seed, backdrop)
	var u := radius * 0.58
	HandIcons.draw(on, id, Rect2(center - Vector2(u, u), Vector2(u * 2.0, u * 2.0)), ink)
