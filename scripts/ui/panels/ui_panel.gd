class_name UIPanel
extends PanelContainer
## Base of every panel UIRoot can open (bible §26.6): cards, menus, sheets.
## A panel covers only its own rectangle — touches there belong to the UI, and
## everything around it still reaches the world.

## On a wide screen a card takes no more than this share of its width.
const WIDE_SHARE := 0.44

## Emitted once when the panel closes, for whatever reason.
signal closed

## A transient panel (e.g. the context menu) closes as soon as the world is
## touched; other panels stay until they are closed or replaced.
var transient := false

var _closing := false


func _init() -> void:
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(InputRouter.UI_BLOCKER_GROUP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_READY:
		TouchScroll.enable_all(self) # (every list in every panel scrolls under a finger)


## Where a card goes across the screen: [x, width]. On a phone held
## upright, as wide as `widest` allows with even margins (at least `margin`)
## at both sides — centred (the owner's playtest, 2026-10-05: a card ran off
## the right edge, the margins were uneven). On a wide screen, at the left
## and not across the middle, where the world is looked at.
static func across(view: Vector2, widest: float, margin: float) -> Vector2:
	if view.y > view.x:
		var width := clampf(view.x - 2.0 * margin, minf(200.0, view.x), widest)
		return Vector2((view.x - width) * 0.5, width)
	var wide := clampf(minf(widest, view.x * WIDE_SHARE), minf(200.0, view.x), maxf(view.x - 2.0 * margin, 200.0))
	return Vector2(margin, wide)


## The left edge for a card that came out `width` wide (see across).
static func left_for(view: Vector2, width: float, margin: float) -> float:
	return maxf((view.x - width) * 0.5, 0.0) if view.y > view.x else margin


func is_closing() -> bool:
	return _closing


## Closes the panel. Safe to call more than once.
func close() -> void:
	if _closing:
		return
	_closing = true
	# Gone for input at once, not at the end of the frame.
	remove_from_group(InputRouter.UI_BLOCKER_GROUP)
	hide()
	closed.emit()
	queue_free()
