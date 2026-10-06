class_name DisasterCard
extends UIPanel
## The warning before a disaster (the owner's design, 2026-10-05): what it
## will do, and Yes / Cancel. It covers the screen, dimming the world, like
## a milestone (MilestoneCard). While the world still rests after the last,
## it says when the next can be brought down, and only closes.

## Yes: bring it down.
signal confirmed(kind: StringName)

const RED := Color(0.92, 0.32, 0.26)
const DIM := Color(0.0, 0.0, 0.0, 0.55)
const CARD_WIDTH := 820.0

var kind: StringName = &""
var _heading: Label
var _text: Label
var _yes: Button
var _cancel: Button


func _init() -> void:
	super._init()
	name = "DisasterCard"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = DIM
	add_theme_stylebox_override(&"panel", backdrop)
	var middle := CenterContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle)
	var card := PanelContainer.new()
	card.name = "Card"
	var frame := MilestoneCard.style()
	frame.border_color = RED
	frame.shadow_color = Color(RED, 0.4)
	card.add_theme_stylebox_override(&"panel", frame)
	middle.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 26)
	card.add_child(column)
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_color_override(&"font_color", RED)
	_heading.add_theme_font_size_override(&"font_size", UITheme.FONT_TITLE)
	column.add_child(_heading)
	_text = Label.new()
	_text.name = "Text"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override(&"font_size", UITheme.FONT_BODY)
	column.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 24)
	column.add_child(buttons)
	_cancel = Button.new()
	_cancel.name = "Cancel"
	_cancel.text = MemoryText.translate("DISASTER_CANCEL")
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.custom_minimum_size = Vector2(260.0, UITheme.TOUCH_TARGET * 0.8)
	_cancel.pressed.connect(close)
	buttons.add_child(_cancel)
	_yes = Button.new()
	_yes.name = "Yes"
	_yes.text = MemoryText.translate("DISASTER_YES")
	_yes.focus_mode = Control.FOCUS_NONE
	_yes.custom_minimum_size = Vector2(260.0, UITheme.TOUCH_TARGET * 0.8)
	_yes.add_theme_color_override(&"font_color", RED)
	_yes.pressed.connect(func() -> void:
		var which := kind
		close()
		confirmed.emit(which))
	buttons.add_child(_yes)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


## Warns of `which`; `rest_minutes` > 0: the world still rests that long, and
## it cannot be brought down yet.
func setup(which: StringName, rest_minutes: int = 0) -> void:
	kind = which
	var key := String(which).to_upper()
	_heading.text = MemoryText.translate("DISASTER_" + key).to_upper()
	if rest_minutes > 0:
		_text.text = MemoryText.translate("DISASTER_RESTING").format({"time": time_left(rest_minutes)})
		_yes.visible = false
		_cancel.text = MemoryText.translate("DISASTER_OK")
	else:
		_text.text = MemoryText.translate("DISASTER_WARN_" + key)
		_yes.visible = true
		_cancel.text = MemoryText.translate("DISASTER_CANCEL")


## "about 7 hours", "about 40 minutes" (game time).
static func time_left(minutes: int) -> String:
	if minutes >= 90:
		return MemoryText.translate("DISASTER_HOURS").format({"hours": roundi(minutes / 60.0)})
	return MemoryText.translate("DISASTER_MINUTES").format({"minutes": maxi(minutes, 1)})


func _fit() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	_text.custom_minimum_size.x = minf(CARD_WIDTH, view.x * 0.8)


# --- for tests --------------------------------------------------------------------------------------

func heading_text() -> String:
	return _heading.text


func text() -> String:
	return _text.text


func yes_button() -> Button:
	return _yes


func cancel_button() -> Button:
	return _cancel
