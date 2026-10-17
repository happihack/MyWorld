class_name MenuButtonRound
extends Button
## HUD button in the top-left corner (bible §26.4: the ☰): opens the menu
## (MainMenu). Draws its own three lines, like the other round buttons.

const SIZE := 104.0
const EDGE_MARGIN := 24.0
const TOP := 56.0

var _glow_left := 0.0
var _glow_age := 0.0


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
	set_process(false)


func _ready() -> void:
	get_viewport().size_changed.connect(place)
	place()


## Its corner, with its margins from the screen's safe area (SafeArea): on a
## phone with a notch, below it.
func place() -> void:
	var viewport := get_viewport()
	var left := EDGE_MARGIN + SafeArea.inset(viewport, SIDE_LEFT, Vector2(TOP, TOP + SIZE))
	var top := TOP + SafeArea.inset(viewport, SIDE_TOP, Vector2(left, left + SIZE))
	position = Vector2(left, top)


## Glows softly for `seconds` (a ring that breathes; VS.4: once, at the
## first event — there is something to read in here).
func glow(seconds: float) -> void:
	_glow_left = maxf(seconds, 0.0)
	_glow_age = 0.0
	set_process(_glow_left > 0.0)
	queue_redraw()


func is_glowing() -> bool:
	return _glow_left > 0.0


func _process(delta: float) -> void:
	_glow_left = maxf(_glow_left - delta, 0.0)
	_glow_age += delta
	if _glow_left <= 0.0:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	HomeButton.draw_round(self, 1, &"menu", button_pressed)
	if _glow_left > 0.0:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 7.0
		var breath := 0.55 + 0.45 * sin(_glow_age * 3.0)
		var fade := minf(_glow_left, 1.0)
		HandDraw.chalk_circle(self, center, radius + 7.0, Color(ToolButton.GLOW, 0.7 * breath * fade), UITheme.CHALK_WIDTH * 0.8, 2)
