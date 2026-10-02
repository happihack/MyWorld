class_name Toast
extends PanelContainer
## One thing the player is told as it happens (bible §26.7): a line of
## text, and — if it happened somewhere — a button that shows where. It
## stays a few seconds and goes; a tap on it sends it away sooner.

## "Show" was pressed.
signal locate_pressed(notice: Notice)
## It has gone (by itself, or sent away).
signal dismissed(notice: Notice)

const FADE_SECONDS := 0.25

@onready var _text: Label = %Text
@onready var _locate: Button = %Locate

var notice: Notice
var _seconds_left := 0.0
var _closing := false
var _tween: Tween


func _init() -> void:
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD
	style.border_color = UITheme.RIM
	style.set_border_width_all(3)
	style.set_corner_radius_all(26)
	style.content_margin_left = 30.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	add_theme_stylebox_override(&"panel", style)


func _ready() -> void:
	_text.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	_locate.text = MemoryText.translate("EVENT_LOCATE")
	_locate.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.72)
	_locate.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	# (A chip, like the banner's: something to press.)
	for state: StringName in [&"normal", &"hover"]:
		_locate.add_theme_stylebox_override(state, FollowBanner._style(false))
	_locate.add_to_group(InputRouter.UI_BLOCKER_GROUP)
	_locate.pressed.connect(func() -> void:
		locate_pressed.emit(notice)
		dismiss())
	modulate.a = 0.0
	_fade_to(1.0)
	if notice != null:
		show_notice(notice, _seconds_left)


## What it says, and for how long (seconds).
func show_notice(what: Notice, seconds: float) -> void:
	notice = what
	_seconds_left = seconds
	if not is_node_ready():
		return
	_text.text = what.text
	_locate.visible = what.can_locate()


func text() -> String:
	return _text.text if is_node_ready() else (notice.text if notice != null else "")


func locate_button() -> Button:
	return _locate


func is_closing() -> bool:
	return _closing


func _process(delta: float) -> void:
	if _closing:
		return
	_seconds_left -= delta
	if _seconds_left <= 0.0:
		dismiss()


func _gui_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	if (press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT) or (touch != null and touch.pressed):
		accept_event()
		dismiss()


## Sends it away (fading). Safe to call more than once.
func dismiss() -> void:
	if _closing:
		return
	_closing = true
	remove_from_group(InputRouter.UI_BLOCKER_GROUP) # gone for input at once
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _locate != null:
		_locate.remove_from_group(InputRouter.UI_BLOCKER_GROUP)
		_locate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dismissed.emit(notice)
	if not is_inside_tree():
		queue_free()
		return
	_fade_to(0.0)
	_tween.tween_callback(queue_free)


func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", alpha, FADE_SECONDS)
