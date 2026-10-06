class_name ToastStack
extends VBoxContainer
## The toasts on screen (bible §26.7): what the NotificationManager posts,
## one under the other at the top of the screen — between the marked
## people on the left and the clock on the right, below the follow banner.
## The newest is at the bottom; more than a few and the oldest goes.

## "Show" was pressed on a toast: look at this place (world X/Z).
signal locate_requested(position: Vector2)

const TOAST := preload("res://scenes/ui/toast.tscn")
const TOP := 176.0
const EDGE_MARGIN := 24.0
const GAP := 16.0
const MIN_WIDTH := 420.0
const MAX_WIDTH := 760.0

## What it keeps clear of (any may be null).
var _left: Control
var _right: Control
## What stands under the clock on the right (Home, the journal).
var _under_right: Array = []
var _above: FollowBanner
var _config: EventsConfig


func _init() -> void:
	name = "Toasts"
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE # only the toasts take touches
	add_theme_constant_override(&"separation", 10)


func _ready() -> void:
	NotificationManager.posted.connect(show_notice)
	NotificationManager.updated.connect(update_notice)
	NotificationManager.cleared.connect(clear)
	get_viewport().size_changed.connect(place)
	place()


## The controls it must not cover: what is on its left, on its right, and
## the banner above it.
func keep_clear_of(left: Control, right: Control, above: FollowBanner, under_right: Array = []) -> void:
	_left = left
	_right = right
	_under_right = under_right
	_above = above
	place()


func _process(_delta: float) -> void:
	if get_child_count() > 0:
		place()


## Shows a notice as a toast.
func show_notice(notice: Notice) -> Toast:
	if notice == null:
		return null
	var config := _config if _config != null else Config.events
	var toast: Toast = TOAST.instantiate()
	toast.show_notice(notice, config.toast_seconds)
	toast.locate_pressed.connect(func(what: Notice) -> void:
		if what != null and what.can_locate():
			locate_requested.emit(what.position))
	add_child(toast)
	# No more than a few at once: the oldest makes room.
	var open := toasts()
	while open.size() > config.max_toasts:
		(open.pop_front() as Toast).dismiss()
	place()
	return toast


## A notice on screen has changed (it happened again): its toast says so,
## and stays a while longer.
func update_notice(notice: Notice) -> void:
	var config := _config if _config != null else Config.events
	for toast in toasts():
		if toast.notice == notice:
			toast.show_notice(notice, config.toast_seconds)
			return


## Takes everything off the screen.
func clear() -> void:
	for toast in toasts():
		toast.dismiss()


## The toasts on screen (not those on their way out), oldest first.
func toasts() -> Array[Toast]:
	var out: Array[Toast] = []
	for child in get_children():
		var toast := child as Toast
		if toast != null and not toast.is_closing() and not toast.is_queued_for_deletion():
			out.append(toast)
	return out


func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for toast in toasts():
		out.append(toast.text())
	return out


## Between what is on the left and what is on the right, below the banner.
func place() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var left := EDGE_MARGIN
	if _left != null and is_instance_valid(_left) and _left.visible:
		left = maxf(left, _left.get_global_rect().end.x + GAP)
	var right := view.x - EDGE_MARGIN
	var column_end := -1.0 # the bottom of the right-hand column
	for control: Variant in [_right] + _under_right:
		if control is Control and is_instance_valid(control) and (control as Control).visible:
			right = minf(right, (control as Control).get_global_rect().position.x - GAP)
			column_end = maxf(column_end, (control as Control).get_global_rect().end.y)
	var top := TOP
	if _above != null and is_instance_valid(_above):
		top = maxf(top, _above.bottom() + GAP)
	var width := clampf(right - left, minf(MIN_WIDTH, view.x - 2.0 * EDGE_MARGIN), MAX_WIDTH)
	# (Not room enough between them: under the right-hand column rather than over it.)
	if right - left < width and column_end >= 0.0:
		top = maxf(top, column_end + GAP)
		left = maxf(view.x - EDGE_MARGIN - width, EDGE_MARGIN)
	else:
		left += (right - left - width) * 0.5
	custom_minimum_size.x = width
	size.x = width
	position = Vector2(left, top)
