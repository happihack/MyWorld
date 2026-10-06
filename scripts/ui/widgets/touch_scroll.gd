class_name TouchScroll
extends RefCounted
## Lists that scroll under a finger (the owner's playtest, 2026-10-05: the
## timeline would not scroll; the person card's list would). A drag that
## begins on a button stops at the button, so the list never sees it: every
## button, row and label in a list lets what it is given through to the list
## as well (a tap is still a tap), and a tap that wobbles a little is not
## taken for a drag.


## Makes `scroll` scroll under a finger, and whatever is put into it later.
static func enable(scroll: ScrollContainer) -> void:
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = int(UITheme.TOUCH_TARGET * 0.15)
	_watch(scroll)


## Every list in `root` (a panel), as `enable`.
static func enable_all(root: Node) -> void:
	for scroll in root.find_children("*", "ScrollContainer", true, false):
		enable(scroll as ScrollContainer)


static func _watch(node: Node) -> void:
	if not node.child_entered_tree.is_connected(_let_through):
		node.child_entered_tree.connect(_let_through)
	for child in node.get_children():
		_let_through(child)


static func _let_through(node: Node) -> void:
	# (Not the scroll bars, and not what is dragged itself — a slider.)
	if node is Range or node is LineEdit or node is TextEdit:
		return
	var control := node as Control
	if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	_watch(node)
