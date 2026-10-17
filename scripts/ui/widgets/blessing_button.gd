class_name BlessingButton
extends Button
## The Blessing button, in the column under the Disaster button (the owner
## and Josh, 2026-10-16): a sprig, green where the other is red-brown. A tap
## slides out the blessings to choose from (BlessingBar). While one is
## going on it glows green; while the world rests after the Presence's last
## act — of either hand — a ring fills as it is ready again.

const GREEN := Color(0.33, 0.55, 0.33)

## 0 … 1: how far the world has rested since the last act (1: ready).
var rested := 1.0:
	set(value):
		if not is_equal_approx(rested, value):
			rested = value
			queue_redraw()
## A blessing is going on.
var active := false:
	set(value):
		if active != value:
			active = value
			queue_redraw()
## The blessings are out (the bar is showing).
var open := false:
	set(value):
		if open != value:
			open = value
			queue_redraw()


func _init() -> void:
	name = "BlessingButton"
	flat = true
	focus_mode = Control.FOCUS_NONE
	text = ""
	tooltip_text = "Blessings"
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var ready := rested >= 1.0 or active
	# Ready, or going on: filled in green. Resting: chalk, the glyph faint, a
	# ring filling clockwise as the world takes in the last act.
	if ready:
		HomeButton.draw_round(self, 11, &"bless", button_pressed or open, UITheme.CHALK, UITheme.CHALK,
			GREEN.darkened(0.15) if button_pressed or open else GREEN)
	else:
		HomeButton.draw_round(self, 11, &"bless", button_pressed or open, HomeButton.RING, Color(HomeButton.GLYPH, 0.5))
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.5 - 7.0
		HandDraw.chalk_arc(self, center, radius - 11.0, rested, Color(UITheme.CHALK, 0.9), maxf(radius * 0.06, 2.0), 12)
