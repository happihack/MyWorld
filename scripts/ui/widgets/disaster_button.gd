class_name DisasterButton
extends Button
## The Disaster button, in the column under the journal (the owner's
## design, 2026-10-05): a warning sign with lightning in it. A tap slides
## out the disasters to choose from (DisasterBar). While one is going on it
## glows red; while the world rests after one, a ring fills as it is ready
## again.

const RED := Color(0.86, 0.22, 0.18)

## 0 … 1: how far the world has rested since the last (1: ready).
var rested := 1.0:
	set(value):
		if not is_equal_approx(rested, value):
			rested = value
			queue_redraw()
## A disaster is going on.
var active := false:
	set(value):
		if active != value:
			active = value
			queue_redraw()
## The disasters are out (the bar is showing).
var open := false:
	set(value):
		if open != value:
			open = value
			queue_redraw()


func _init() -> void:
	name = "DisasterButton"
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	tooltip_text = "Disasters"
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(center, radius, HomeButton.BACKDROP_PRESSED if button_pressed or open else HomeButton.BACKDROP)
	draw_arc(center, radius, 0.0, TAU, 48, RED if active else HomeButton.RING, maxf(radius * (0.09 if active else 0.05), 2.0), true)
	if rested < 1.0 and not active:
		# How far the world has rested: a ring filling clockwise from the top.
		draw_arc(center, radius - 6.0, -PI * 0.5, -PI * 0.5 + TAU * rested, 40, Color(HomeButton.RING, 0.9), maxf(radius * 0.06, 2.0), true)
	var u := radius * 0.5
	var ink := HomeButton.GLYPH if rested >= 1.0 or active else Color(HomeButton.GLYPH, 0.5)
	# A warning sign: a triangle, rounded, lightning inside.
	var top := center + Vector2(0.0, -u * 1.15)
	var left := center + Vector2(-u * 1.2, u * 0.9)
	var right := center + Vector2(u * 1.2, u * 0.9)
	draw_polyline(PackedVector2Array([top, right, left, top]), ink, maxf(u * 0.2, 3.0), true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0.12, -0.6) * u, center + Vector2(-0.32, 0.12) * u,
		center + Vector2(-0.02, 0.08) * u, center + Vector2(-0.16, 0.7) * u, center + Vector2(0.34, -0.06) * u,
		center + Vector2(0.04, -0.02) * u, center + Vector2(0.24, -0.6) * u]), RED if rested >= 1.0 or active else ink)
