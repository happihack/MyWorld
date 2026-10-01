class_name PinList
extends VBoxContainer
## The people the player has marked as important, as a short list of names at
## the edge of the screen (bible §26.6 "Mark Important"): a tap on a name goes
## to that person. Empty — and gone — while nobody is marked.

signal chosen(person_id: int)

const EDGE_MARGIN := 24.0
const TOP := 170.0
## More than this many names and the list would crowd the world.
const MAX_SHOWN := 6

var _shown: Array = [] # [[person id, name], ...]


func _init() -> void:
	name = "PinList"
	theme = UITheme.get_theme()
	position = Vector2(EDGE_MARGIN, TOP)
	add_theme_constant_override(&"separation", 8)
	visible = false


## Shows these people: an Array of [person id, name], in the order given.
func set_people(people: Array) -> void:
	if people == _shown:
		return
	_shown = people.duplicate(true)
	for child in get_children():
		child.queue_free()
	for entry: Array in people.slice(0, MAX_SHOWN):
		var chip := Button.new()
		chip.text = str(entry[1])
		chip.focus_mode = Control.FOCUS_NONE
		chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
		chip.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.72)
		chip.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		chip.add_theme_stylebox_override(&"normal", _chip_style())
		chip.add_theme_stylebox_override(&"hover", _chip_style())
		chip.add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
		chip.pressed.connect(func() -> void: chosen.emit(entry[0]))
		add_child(chip)
	visible = not people.is_empty()


## The ids shown, in order.
func ids() -> Array[int]:
	var out: Array[int] = []
	for entry: Array in _shown.slice(0, MAX_SHOWN):
		out.append(entry[0])
	return out


func chips() -> Array[Button]:
	var out: Array[Button] = []
	for child in get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append(child)
	return out


static func _chip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.12, 0.62)
	style.border_color = StarButton.LIT
	style.border_width_left = 6
	style.set_corner_radius_all(18)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	return style
