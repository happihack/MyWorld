class_name MilestoneCard
extends UIPanel
## A milestone, told so it can be read (owner: discoveries went by in a toast
## too quickly to take in): "Fule has worked out how to keep words in marks".
## It covers the screen, dimming the world, until Continue (or Back) — the
## world goes on behind it. Shown only while the game is in front; what comes
## while it is in the background waits for its return (see UIRoot).

## "Show": the camera goes where it happened.
signal locate_requested(position: Vector2)

const CARD_WIDTH := 820.0
const GOLD := Color(0.98, 0.80, 0.35)
const DIM := Color(0.0, 0.0, 0.0, 0.55)

var notice: Notice
var _heading: Label
var _text: Label
var _continue: Button
var _show: Button


func _init() -> void:
	super._init()
	name = "MilestoneCard"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = DIM
	add_theme_stylebox_override(&"panel", backdrop)
	var middle := CenterContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle)
	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override(&"panel", style())
	middle.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 26)
	card.add_child(column)
	_heading = Label.new()
	_heading.name = "Heading"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_color_override(&"font_color", GOLD)
	_heading.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	column.add_child(_heading)
	_text = Label.new()
	_text.name = "Text"
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override(&"font_size", UITheme.FONT_TITLE)
	column.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 24)
	column.add_child(buttons)
	_show = Button.new()
	_show.name = "Show"
	_show.text = MemoryText.translate("EVENT_LOCATE")
	_show.focus_mode = Control.FOCUS_NONE
	_show.custom_minimum_size = Vector2(240.0, UITheme.TOUCH_TARGET * 0.8)
	_show.pressed.connect(func() -> void:
		if notice != null and notice.can_locate():
			locate_requested.emit(notice.position)
		close())
	buttons.add_child(_show)
	_continue = Button.new()
	_continue.name = "Continue"
	_continue.text = "Continue"
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.custom_minimum_size = Vector2(280.0, UITheme.TOUCH_TARGET * 0.8)
	_continue.pressed.connect(close)
	buttons.add_child(_continue)


func _ready() -> void:
	get_viewport().size_changed.connect(_fit)
	_fit()


## What it tells of.
func setup(what: Notice) -> void:
	notice = what
	_heading.text = heading_for(what.kind).to_upper()
	_text.text = what.text
	_show.visible = what.can_locate()


## "A discovery", "A new age", … by what kind of milestone it is.
static func heading_for(kind: StringName) -> String:
	match kind:
		&"knowledge_learned":
			return "A discovery"
		&"era_entered":
			return "A new age"
		&"box_research":
			return "Understanding the world"
	return "A milestone"


## The card's frame: gold, thick, glowing — it is not just another notice.
static func style() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = UITheme.CARD
	frame.border_color = GOLD
	frame.set_border_width_all(6)
	frame.set_corner_radius_all(30)
	frame.shadow_color = Color(GOLD, 0.45)
	frame.shadow_size = 26
	frame.content_margin_left = 48.0
	frame.content_margin_right = 48.0
	frame.content_margin_top = 40.0
	frame.content_margin_bottom = 40.0
	return frame


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


func continue_button() -> Button:
	return _continue
