class_name ToolButton
extends Button
## One tool in the tool bar (bible §23.2): a chalk circle over the world with
## the tool drawn in it by hand (HandIcons). The chosen tool is the other way
## round — filled in, the glyph dark. Needs no image asset and stays crisp at
## any UI scale.

const SIZE := 140.0
const GLOW := Color(1.0, 0.86, 0.52)
## What each tool is drawn as.
const ICONS := {
	HandTool.ID: &"hand",
	ObserveTool.ID: &"look",
	RainTool.ID: &"weather",
	WindTool.ID: &"wind",
	WaterTool.ID: &"water",
}

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
var _seed := 0


func _init(id: StringName = &"") -> void:
	tool_id = id
	_seed = hash(id) % 997
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
	var radius := minf(size.x, size.y) * 0.5 - 7.0
	var width := UITheme.CHALK_WIDTH
	if selected:
		HandDraw.chalk_circle(self, center, radius, Color(0, 0, 0, 0), 0.0, _seed, UITheme.CHALK)
	else:
		HandDraw.chalk_circle(self, center, radius, UITheme.CHALK, width, _seed,
			UITheme.CHALK_FILL_DARK if button_pressed else UITheme.CHALK_FILL)
	if _glow_left > 0.0:
		var breath := 0.55 + 0.45 * sin(_glow_age * 4.0)
		var fade := minf(_glow_left, 1.0)
		HandDraw.chalk_circle(self, center, radius + 7.0, Color(GLOW, 0.75 * breath * fade), width * 0.8, _seed + 1)
		draw_colored_polygon(HandDraw.circle_points(center, radius, _seed, 0.0), Color(GLOW, 0.16 * breath * fade))
	if fill >= 0.0:
		# What it holds: an arc round the rim, from the bottom up both sides.
		var half := PI * clampf(fill, 0.0, 1.0)
		if half > 0.01:
			draw_arc(center, radius - 9.0, PI * 0.5 - half, PI * 0.5 + half, 32, Color(0.45, 0.78, 0.95, 0.95), maxf(radius * 0.07, 3.0), true)
	var ink := UITheme.INK if selected else UITheme.CHALK
	var u := radius * 0.6
	var icon: StringName = ICONS.get(tool_id, &"")
	if HandIcons.has(icon):
		HandIcons.draw(self, icon, Rect2(center - Vector2(u, u), Vector2(u * 2.0, u * 2.0)), ink)
	else:
		draw_circle(center, u * 0.4, ink)
