class_name UITheme
extends RefCounted
## The look of in-game panels (bible §26, §28): dark, slightly see-through
## cards with a warm rim, cream text. Built in code so there is one place to
## tune it and no theme file to keep in sync.
##
## Sizes are in canvas units; on a phone 1 dp is about 2.8 units, so the
## smallest touch target (48 dp) is TOUCH_TARGET.

const TOUCH_TARGET := 136.0
## Space between a button's edge and its text.
const BUTTON_PAD := 22.0

const INK := Color(0.949, 0.902, 0.788)
const INK_DIM := Color(0.949, 0.902, 0.788, 0.62)
const CARD := Color(0.07, 0.09, 0.12, 0.90)
const RIM := Color(0.784, 0.631, 0.396, 0.75)
const PRESSED := Color(1.0, 1.0, 1.0, 0.13)
const LINE := Color(0.949, 0.902, 0.788, 0.22)

const FONT_BODY := 40
const FONT_TITLE := 50
const FONT_SMALL := 34

## Label variations.
const TITLE := &"TitleLabel"
const DIM := &"DimLabel"

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = FONT_BODY

	var card := StyleBoxFlat.new()
	card.bg_color = CARD
	card.border_color = RIM
	card.set_border_width_all(3)
	card.set_corner_radius_all(30)
	card.set_content_margin_all(22)
	theme.set_stylebox(&"panel", &"PanelContainer", card)

	var idle := StyleBoxFlat.new()
	idle.bg_color = Color(1, 1, 1, 0)
	idle.set_corner_radius_all(20)
	idle.content_margin_left = BUTTON_PAD
	idle.content_margin_right = BUTTON_PAD
	var pressed := idle.duplicate() as StyleBoxFlat
	pressed.bg_color = PRESSED
	for state: StringName in [&"normal", &"hover", &"disabled"]:
		theme.set_stylebox(state, &"Button", idle)
	theme.set_stylebox(&"pressed", &"Button", pressed)
	theme.set_stylebox(&"hover_pressed", &"Button", pressed)
	theme.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_hover_pressed_color", &"font_focus_color"]:
		theme.set_color(state, &"Button", INK)
	theme.set_font_size(&"font_size", &"Button", FONT_BODY)

	theme.set_color(&"font_color", &"Label", INK)
	theme.set_font_size(&"font_size", &"Label", FONT_BODY)
	theme.set_type_variation(TITLE, &"Label")
	theme.set_color(&"font_color", TITLE, INK)
	theme.set_font_size(&"font_size", TITLE, FONT_TITLE)
	theme.set_type_variation(DIM, &"Label")
	theme.set_color(&"font_color", DIM, INK_DIM)
	theme.set_font_size(&"font_size", DIM, FONT_SMALL)

	var line := StyleBoxLine.new()
	line.color = LINE
	line.thickness = 2
	theme.set_stylebox(&"separator", &"HSeparator", line)
	theme.set_constant(&"separation", &"HSeparator", 14)
	theme.set_constant(&"separation", &"VBoxContainer", 6)
	theme.set_constant(&"separation", &"HBoxContainer", 16)
	theme.set_constant(&"h_separation", &"GridContainer", 36)
	theme.set_constant(&"v_separation", &"GridContainer", 10)
	return theme
