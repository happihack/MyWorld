class_name UIPanel
extends PanelContainer
## Base of every panel UIRoot can open (bible §26.6): cards, menus, sheets.
## A panel covers only its own rectangle — touches there belong to the UI, and
## everything around it still reaches the world.

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
