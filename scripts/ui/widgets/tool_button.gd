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
const GLOW := Color(1.0, 0.86, 0.52)

var tool_id: StringName = &""
var selected := false:
	set(value):
		selected = value
		queue_redraw()
## How full what the tool holds is, 0 … 1 (the water tool's bucket); less
## than nothing: it holds nothing to show.
var fill := -1.0:
	set(value):
		if not is_equal_approx(fill, value):
			fill = value
			queue_redraw()
## Seconds of glow left (a tool that has just shown itself).
var _glow_left := 0.0
var _glow_age := 0.0


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
	set_process(false)


## Glows for `seconds` (a soft ring that breathes): look, something new.
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
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(center, radius, BACKDROP_SELECTED if selected else BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 48, RING, maxf(radius * 0.05, 2.0), true)
	if _glow_left > 0.0:
		var breath := 0.55 + 0.45 * sin(_glow_age * 4.0)
		var fade := minf(_glow_left, 1.0)
		draw_arc(center, radius + 5.0, 0.0, TAU, 48, Color(GLOW, 0.75 * breath * fade), maxf(radius * 0.09, 4.0), true)
		draw_circle(center, radius, Color(GLOW, 0.16 * breath * fade))
	if fill >= 0.0:
		# What it holds: an arc round the rim, from the bottom up both sides.
		var half := PI * clampf(fill, 0.0, 1.0)
		if half > 0.01:
			draw_arc(center, radius - 7.0, PI * 0.5 - half, PI * 0.5 + half, 32, Color(0.45, 0.78, 0.95, 0.95), maxf(radius * 0.07, 3.0), true)
	if button_pressed and not selected:
		draw_circle(center, radius, UITheme.PRESSED)
	var ink := GLYPH_SELECTED if selected else GLYPH
	var u := radius * 0.42
	match tool_id:
		HandTool.ID:
			_draw_hand(center, u, ink)
		ObserveTool.ID:
			_draw_eye(center, u, ink)
		RainTool.ID:
			_draw_cloud(center, u, ink)
		WindTool.ID:
			_draw_wind(center, u, ink)
		WaterTool.ID:
			_draw_drop(center, u, ink)
		CallTool.ID:
			_draw_flag(center, u, ink)
		_:
			draw_circle(center, u * 0.5, ink)


## An open hand: a palm, four fingers and a thumb.
func _draw_hand(center: Vector2, u: float, ink: Color) -> void:
	var palm := Rect2(center + Vector2(-u * 0.72, -u * 0.1), Vector2(u * 1.44, u * 0.8))
	draw_rect(palm, ink)
	draw_circle(center + Vector2(0.0, u * 0.7), u * 0.72, ink)
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


## A flag on a pole: "come here".
func _draw_flag(center: Vector2, u: float, ink: Color) -> void:
	var foot := center + Vector2(-u * 0.55, u * 1.2)
	var top := center + Vector2(-u * 0.55, -u * 1.2)
	draw_line(foot, top, ink, maxf(u * 0.2, 3.0), true)
	draw_colored_polygon(PackedVector2Array([
		top,
		top + Vector2(u * 1.5, u * 0.5),
		top + Vector2(0.0, u * 1.0),
	]), ink)
	draw_circle(foot, u * 0.22, ink)


## A cloud with rain falling from it.
func _draw_cloud(center: Vector2, u: float, ink: Color) -> void:
	var base := center + Vector2(0.0, -u * 0.35)
	draw_circle(base + Vector2(-u * 0.62, u * 0.12), u * 0.5, ink)
	draw_circle(base + Vector2(u * 0.05, -u * 0.22), u * 0.68, ink)
	draw_circle(base + Vector2(u * 0.72, u * 0.14), u * 0.48, ink)
	draw_rect(Rect2(base + Vector2(-u * 0.62, u * 0.1), Vector2(u * 1.34, u * 0.52)), ink)
	var width := maxf(u * 0.16, 3.0)
	for n in 3:
		var top := center + Vector2(-u * 0.6 + n * u * 0.6, u * 0.55)
		draw_line(top, top + Vector2(-u * 0.18, u * 0.6), ink, width, true)


## Three lines of wind, the upper two curling at their ends.
func _draw_wind(center: Vector2, u: float, ink: Color) -> void:
	var width := maxf(u * 0.18, 3.0)
	var rows := [[-0.62, 1.0, true], [0.0, 1.3, true], [0.62, 0.8, false]]
	for row: Array in rows:
		var y: float = center.y + u * float(row[0])
		var from := Vector2(center.x - u * 1.25, y)
		var to := Vector2(center.x - u * 1.25 + u * 1.9 * float(row[1]) / 1.3, y)
		draw_line(from, to, ink, width, true)
		if bool(row[2]):
			draw_arc(to + Vector2(0.0, -u * 0.3), u * 0.3, -PI * 0.5, PI * 0.5, 12, ink, width, true)


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
