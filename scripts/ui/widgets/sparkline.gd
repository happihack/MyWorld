class_name Sparkline
extends Control
## A small line of one number over time (VS.2, bible §27.3): oldest on the
## left, now on the right, the most it has been as the top and nothing (or,
## without `from_zero`, the least it has been) as the bottom; a dot where it
## is now. No axes: it shows which way things go.

## How far below its least and above its most the line keeps from the edges.
const PAD := 6.0
const LINE_WIDTH := 3.0
const DOT := 6.0

var color := UITheme.INK
## The bottom is nothing, not the least it has been: a count that goes from
## 36 to 35 looks like the small change it is (not falling off a cliff).
## For numbers that can go below nothing (a temperature), false.
var from_zero := false
## A line this flat is drawn level through the middle (nothing changed).
var flat_below := 0.0001

var _values := PackedFloat32Array()


func _init() -> void:
	custom_minimum_size = Vector2(240.0, 64.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(values: PackedFloat32Array) -> void:
	_values = values
	queue_redraw()


func values() -> PackedFloat32Array:
	return _values


## Where each value is drawn, in this control's space (for drawing, and tests).
func points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := _values.size()
	if count == 0:
		return out
	var least := INF
	var most := -INF
	for value in _values:
		least = minf(least, value)
		most = maxf(most, value)
	if from_zero:
		least = minf(least, 0.0)
	var span := most - least
	var width := size.x - PAD * 2.0
	var height := size.y - PAD * 2.0
	for i in count:
		var x := PAD + (width * i / float(count - 1) if count > 1 else width)
		var share := (_values[i] - least) / span if span > flat_below else 0.5
		out.append(Vector2(x, PAD + height * (1.0 - share)))
	return out


func _draw() -> void:
	var at := points()
	if at.is_empty():
		return
	var faint := Color(color, 0.18)
	draw_line(Vector2(PAD, size.y - PAD), Vector2(size.x - PAD, size.y - PAD), faint, 1.0)
	if at.size() > 1:
		draw_polyline(at, color, LINE_WIDTH, true)
	draw_circle(at[-1], DOT, color)
