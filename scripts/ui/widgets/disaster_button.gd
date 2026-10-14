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
	var ready := rested >= 1.0 or active
	# Ready, or going on: filled in red-brown, so it still shouts. Resting:
	# chalk, the glyph faint, a ring filling clockwise as the world recovers.
	if ready:
		HomeButton.draw_round(self, 7, &"alert", button_pressed or open, UITheme.CHALK, UITheme.CHALK,
			UITheme.RED.darkened(0.15) if button_pressed or open else UITheme.RED)
	else:
		HomeButton.draw_round(self, 7, &"alert", button_pressed or open, HomeButton.RING, Color(HomeButton.GLYPH, 0.5))
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 7.0
		HandDraw.chalk_arc(self, center, radius - 11.0, rested, Color(UITheme.CHALK, 0.9), maxf(radius * 0.06, 2.0), 8)
