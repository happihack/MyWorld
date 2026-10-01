class_name FollowBanner
extends VBoxContainer
## What the camera is up to with people, at the top of the screen:
##   "Following Mara ✕" while the camera follows someone (bible §26.6);
##   "Resume following Mara ✕" once the view has been taken elsewhere;
##   "Find Mara" while the selected person is out of sight.
## Each is there only while it has something to say.

## The banner's text was tapped (while following: show them; paused: resume).
signal follow_pressed
## Its ✕: stop following.
signal stop_pressed
## "Find …" was tapped.
signal locate_pressed

const TOP := 56.0
const HEIGHT := UITheme.TOUCH_TARGET * 0.72

var _banner: HBoxContainer
var _follow: Button
var _stop: CloseButton
var _locate: Button
var _follow_name := ""
var _paused := false
var _locate_name := ""


func _init() -> void:
	name = "FollowBanner"
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 10)
	# As wide as the screen (and letting touches through); what it shows sits in the middle.
	anchor_left = 0.0
	anchor_right = 1.0
	offset_top = TOP
	_banner = HBoxContainer.new()
	_banner.name = "Banner"
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner.add_theme_constant_override(&"separation", 6)
	add_child(_banner)
	_follow = _chip(_banner, "Follow")
	_follow.pressed.connect(func() -> void: follow_pressed.emit())
	_stop = CloseButton.new()
	_stop.name = "Stop"
	_stop.flat = false # (a chip like the others, with the cross on it)
	_stop.custom_minimum_size = Vector2(HEIGHT, HEIGHT)
	_stop.tooltip_text = "Stop following"
	_stop.add_to_group(InputRouter.UI_BLOCKER_GROUP)
	_stop.pressed.connect(func() -> void: stop_pressed.emit())
	_banner.add_child(_stop)
	_locate = _chip(self, "Locate")
	_locate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_locate.pressed.connect(func() -> void: locate_pressed.emit())
	_banner.visible = false
	_locate.visible = false


## Shows who is followed ("" = nobody), and whether the camera is with them.
func set_following(person_name: String, paused: bool = false) -> void:
	if person_name == _follow_name and paused == _paused:
		return
	_follow_name = person_name
	_paused = paused
	_banner.visible = person_name != ""
	_follow.text = ("Resume following %s" if paused else "Following %s") % person_name
	_follow.add_theme_stylebox_override(&"normal", _style(not paused))
	_follow.add_theme_stylebox_override(&"hover", _style(not paused))
	_stop.add_theme_stylebox_override(&"normal", _style(false))
	_stop.add_theme_stylebox_override(&"hover", _style(false))


## Offers to find someone who is out of sight ("" = nobody to find).
func set_locate(person_name: String) -> void:
	if person_name == _locate_name:
		return
	_locate_name = person_name
	_locate.visible = person_name != ""
	_locate.text = "Find %s" % person_name


func follow_text() -> String:
	return _follow.text if _banner.visible else ""


func locate_text() -> String:
	return _locate.text if _locate.visible else ""


func is_paused() -> bool:
	return _banner.visible and _paused


## One of the buttons: &"follow", &"stop", &"locate" (for tests).
func button(which: StringName) -> Button:
	match which:
		&"follow":
			return _follow
		&"stop":
			return _stop
		&"locate":
			return _locate
	return null


## The bottom of whatever is shown (the top of what is free below), in the
## canvas's units; TOP if nothing is.
func bottom() -> float:
	if _locate.visible:
		return _locate.get_global_rect().end.y
	if _banner.visible:
		return _banner.get_global_rect().end.y
	return TOP


func _chip(parent: Control, chip_name: String) -> Button:
	var chip := Button.new()
	chip.name = chip_name
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = Vector2(0.0, HEIGHT)
	chip.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	chip.add_theme_stylebox_override(&"normal", _style(false))
	chip.add_theme_stylebox_override(&"hover", _style(false))
	chip.add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	parent.add_child(chip)
	return chip


## A chip; lit (a bright rim) while what it says is going on.
static func _style(lit: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.12, 0.78)
	style.border_color = StarButton.LIT if lit else UITheme.RIM
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(HEIGHT * 0.5))
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	return style
