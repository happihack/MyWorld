class_name NeedBar
extends Control
## How well a need is met, as a bar (bible §26.6 "needs bars"). Full is calm;
## as it empties it warms, so that what is pressing is seen at a glance —
## and by its length, not by its colour alone (§28.3).

const HEIGHT := 22.0
const TRACK := Color(0.949, 0.902, 0.788, 0.16)
const FULL := Color(0.62, 0.80, 0.62)
const LOW := Color(0.93, 0.68, 0.30)
const EMPTY := Color(0.90, 0.38, 0.30)

var value := 1.0:
	set(new_value):
		var clamped := clampf(new_value, 0.0, 1.0)
		if not is_equal_approx(clamped, value):
			value = clamped
			queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(120.0, HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The colour of the bar for a value (0 … 1).
static func color_for(level: float) -> Color:
	if level >= 0.5:
		return LOW.lerp(FULL, (level - 0.5) * 2.0)
	return EMPTY.lerp(LOW, level * 2.0)


## Drawn by hand on the paper: a wobbly outline, pencil hatching as far as the
## value goes — in ink while the need is met, in red once it presses.
func _draw() -> void:
	var seed := int(get_index()) + 60
	var width := maxf(size.x * value, 6.0 if value > 0.0 else 0.0)
	if width > 0.0:
		var pencil := UITheme.INK if value >= 0.5 else UITheme.RED
		HandDraw.draw_hatch(self, Rect2(3.0, 3.0, width - 3.0, size.y - 6.0), Color(pencil, 0.85), 9.0, 2.6)
	draw_style_box(HandDraw.chalk_box(seed, Color(0, 0, 0, 0), UITheme.INK, 3.0, size.y * 0.6), Rect2(Vector2.ZERO, size))
