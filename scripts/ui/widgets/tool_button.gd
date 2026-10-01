class_name ToolButton
extends Button
## One tool in the tool bar (bible §23.2). Draws its own glyph, so it needs no
## image asset and stays crisp at any UI scale. The selected tool is lit.

const SIZE := 140.0
const BACKDROP := Color(0.07, 0.09, 0.12, 0.55)
const BACKDROP_SELECTED := Color(0.95, 0.90, 0.79, 0.92)
const GLYPH := Color(0.949, 0.902, 0.788, 0.95)
const GLYPH_SELECTED := Color(0.10, 0.12, 0.16)
const RING := Color(0.784, 0.631, 0.396, 0.9)

var tool_id: StringName = &""
var selected := false:
	set(value):
		selected = value
		queue_redraw()


func _init(id: StringName = &"") -> void:
	tool_id = id
	name = String(id).capitalize().replace(" ", "") if id != &"" else "Tool"
	flat = true
	text = ""
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(SIZE, SIZE)
	tooltip_text = UIText.tool_name(id)
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world


func _ready() -> void:
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(center, radius, BACKDROP_SELECTED if selected else BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 48, RING, maxf(radius * 0.05, 2.0), true)
	if button_pressed and not selected:
		draw_circle(center, radius, UITheme.PRESSED)
	var ink := GLYPH_SELECTED if selected else GLYPH
	var u := radius * 0.42
	match tool_id:
		HandTool.ID:
			_draw_hand(center, u, ink)
		ObserveTool.ID:
			_draw_eye(center, u, ink)
		WaterTool.ID:
			_draw_drop(center, u, ink)
		_:
			draw_circle(center, u * 0.5, ink)


## An open hand: a palm, four fingers and a thumb.
func _draw_hand(center: Vector2, u: float, ink: Color) -> void:
	var palm := Rect2(center + Vector2(-u * 0.72, -u * 0.1), Vector2(u * 1.44, u * 1.2))
	draw_rect(palm, ink)
	draw_circle(center + Vector2(0.0, u * 1.02), u * 0.72, ink)
	var finger_width := u * 0.30
	var lengths: Array[float] = [0.85, 1.1, 1.0, 0.7]
	for i in 4:
		var x := -u * 0.72 + i * (finger_width + u * 0.08)
		var top := -u * 0.1 - u * lengths[i]
		draw_rect(Rect2(center + Vector2(x, top), Vector2(finger_width, u * lengths[i] + 2.0)), ink)
		draw_circle(center + Vector2(x + finger_width * 0.5, top), finger_width * 0.5, ink)
	# Thumb, angled out to the side.
	var base := center + Vector2(u * 0.6, u * 0.55)
	var tip := center + Vector2(u * 1.3, -u * 0.1)
	draw_line(base, tip, ink, finger_width * 1.05, true)
	draw_circle(tip, finger_width * 0.52, ink)


## A drop of water.
func _draw_drop(center: Vector2, u: float, ink: Color) -> void:
	var belly := center + Vector2(0.0, u * 0.35)
	draw_circle(belly, u * 0.72, ink)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -u * 1.25),
		belly + Vector2(u * 0.66, -u * 0.28),
		belly + Vector2(-u * 0.66, -u * 0.28),
	]), ink)


## An eye: an almond outline with a pupil.
func _draw_eye(center: Vector2, u: float, ink: Color) -> void:
	var points := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var f := i / float(steps)
		points.append(center + Vector2(lerpf(-u * 1.35, u * 1.35, f), -sin(PI * f) * u * 0.8))
	for i in range(steps - 1, 0, -1):
		var f := i / float(steps)
		points.append(center + Vector2(lerpf(-u * 1.35, u * 1.35, f), sin(PI * f) * u * 0.8))
	points.append(points[0])
	draw_polyline(points, ink, maxf(u * 0.16, 3.0), true)
	draw_circle(center, u * 0.42, ink)
