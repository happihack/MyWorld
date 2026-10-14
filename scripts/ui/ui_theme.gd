class_name UITheme
extends RefCounted
## The look of the UI (the owner's direction, 2026-10-09): hand-painted. The
## lid of the box is painted brown and written on in cream; over the world the
## HUD is chalk; the menus and cards are sheets of paper taped on, written in
## ink and pencil. Three hand fonts: Caveat Brush for names and headings,
## Patrick Hand for buttons and entries, Kalam for notes and dates. Built in
## code so there is one place to tune it and no theme file to keep in sync.
##
## Sizes are in canvas units; on a phone 1 dp is about 2.8 units, so the
## smallest touch target (48 dp) is TOUCH_TARGET.

const TOUCH_TARGET := 136.0
## Space between a button's edge and its text.
const BUTTON_PAD := 22.0

# --- the inks ---
## Cream: chalk and paint on the lid, and over the world.
const CHALK := Color(0.949, 0.902, 0.788)
const CHALK_DIM := Color(0.949, 0.902, 0.788, 0.62)
## Ink on paper.
const INK := Color(0.165, 0.114, 0.078)
const INK_DIM := Color(0.165, 0.114, 0.078, 0.62)
## Pencil: notes, dates, the lighter lines on paper.
const PENCIL := Color(0.290, 0.204, 0.094)
const PENCIL_LIGHT := Color(0.420, 0.322, 0.188)
## Red-brown: alerts, the blot by something new, a scrawl.
const RED := Color(0.702, 0.282, 0.173)

# --- the surfaces ---
const PAPER := Color(0.945, 0.902, 0.788)
const PAPER_EDGE := Color(0.922, 0.867, 0.737)
## The ruled lines on paper.
const PAPER_RULE := Color(0.165, 0.114, 0.078, 0.09)
const RULE_EVERY := 78.0
const TAPE := Color(1.0, 0.910, 0.627, 0.55)
const MARKER := Color(1.0, 0.839, 0.353, 0.65)
## The lid: painted brown, darker at the edges; the cut edge of its opening.
const LID := Color(0.369, 0.263, 0.169)
const LID_EDGE := Color(0.247, 0.169, 0.110)
const CUT := Color(0.545, 0.416, 0.271)
const FIREFLY := Color(1.0, 0.914, 0.651)
## Behind chalk over the world, so it reads over bright ground.
const CHALK_FILL := Color(0.165, 0.114, 0.078, 0.45)
const CHALK_FILL_DARK := Color(0.165, 0.114, 0.078, 0.72)

# (Older names, kept for the code that uses them.)
const CARD := CHALK_FILL
const RIM := Color(0.165, 0.114, 0.078, 0.9)
const PRESSED := Color(0.165, 0.114, 0.078, 0.10)
const LINE := Color(0.165, 0.114, 0.078, 0.25)

const FONT_BODY := 44
const FONT_TITLE := 72
const FONT_SMALL := 36
## Section headings in the menu, names on cards.
const FONT_HEADING := 66
## The game's name on the lid.
const FONT_DISPLAY := 132
## Chalk lines: how thick.
const CHALK_WIDTH := 7.0

## Label variations.
const TITLE := &"TitleLabel"
const DIM := &"DimLabel"
const DISPLAY := &"DisplayLabel"
const NOTE := &"NoteLabel"
const CHALK_LABEL := &"ChalkLabel"
const CHALK_SMALL := &"ChalkSmallLabel"

const FONT_DIR := "res://assets/fonts/"

static var _theme: Theme
static var _display: Font
static var _hand: Font
static var _note: Font
static var _note_bold: Font


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Caveat Brush: the name of the game, headings, "Continue".
static func display_font() -> Font:
	if _display == null:
		_display = _load_font("CaveatBrush-Regular.ttf")
	return _display


## Patrick Hand: buttons, entries, labels.
static func hand_font() -> Font:
	if _hand == null:
		_hand = _load_font("PatrickHand-Regular.ttf")
	return _hand


## Kalam: notes, dates, reading text.
static func note_font(bold: bool = false) -> Font:
	if bold:
		if _note_bold == null:
			_note_bold = _load_font("Kalam-Bold.ttf")
		return _note_bold
	if _note == null:
		_note = _load_font("Kalam-Regular.ttf")
	return _note


## A font file of ours; the engine's own if it is missing (a test without the assets).
static func _load_font(file: String) -> Font:
	var path := FONT_DIR + file
	if ResourceLoader.exists(path):
		var font := load(path) as Font
		if font != null:
			return font
	if FileAccess.file_exists(path):
		var dynamic := FontFile.new()
		if dynamic.load_dynamic_font(path) == OK:
			return dynamic
	return ThemeDB.fallback_font


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font = hand_font()
	theme.default_font_size = FONT_BODY

	# A sheet of paper: every panel and card.
	theme.set_stylebox(&"panel", &"PanelContainer", HandDraw.paper_box(7, 22.0))

	# Buttons: bare on the paper, pressed in when pressed.
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
	theme.set_color(&"font_disabled_color", &"Button", INK_DIM)
	for state: StringName in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color",
			&"icon_hover_pressed_color", &"icon_focus_color"]:
		theme.set_color(state, &"Button", INK)
	theme.set_font_size(&"font_size", &"Button", FONT_BODY)
	theme.set_constant(&"h_separation", &"Button", 16)

	theme.set_color(&"font_color", &"Label", INK)
	theme.set_font_size(&"font_size", &"Label", FONT_BODY)
	theme.set_type_variation(TITLE, &"Label")
	theme.set_font(&"font", TITLE, display_font())
	theme.set_color(&"font_color", TITLE, INK)
	theme.set_font_size(&"font_size", TITLE, FONT_TITLE)
	theme.set_type_variation(DIM, &"Label")
	theme.set_font(&"font", DIM, note_font())
	theme.set_color(&"font_color", DIM, INK_DIM)
	theme.set_font_size(&"font_size", DIM, FONT_SMALL)
	theme.set_type_variation(DISPLAY, &"Label")
	theme.set_font(&"font", DISPLAY, display_font())
	theme.set_color(&"font_color", DISPLAY, CHALK)
	theme.set_font_size(&"font_size", DISPLAY, FONT_DISPLAY)
	theme.set_type_variation(NOTE, &"Label")
	theme.set_font(&"font", NOTE, note_font())
	theme.set_color(&"font_color", NOTE, PENCIL)
	theme.set_font_size(&"font_size", NOTE, FONT_BODY - 4)
	theme.set_type_variation(CHALK_LABEL, &"Label")
	theme.set_color(&"font_color", CHALK_LABEL, CHALK)
	theme.set_font_size(&"font_size", CHALK_LABEL, FONT_BODY)
	theme.set_type_variation(CHALK_SMALL, &"Label")
	theme.set_font(&"font", CHALK_SMALL, note_font())
	theme.set_color(&"font_color", CHALK_SMALL, CHALK)
	theme.set_font_size(&"font_size", CHALK_SMALL, FONT_SMALL)

	# Writing in: a pencil box on the paper.
	var field := HandDraw.chalk_box(11, Color(1, 1, 1, 0), INK, 5.0, 18.0)
	field.content_margin_left = BUTTON_PAD
	field.content_margin_right = BUTTON_PAD
	field.content_margin_top = 8.0
	field.content_margin_bottom = 8.0
	theme.set_stylebox(&"normal", &"LineEdit", field)
	theme.set_stylebox(&"focus", &"LineEdit", field)
	theme.set_stylebox(&"read_only", &"LineEdit", field)
	theme.set_color(&"font_color", &"LineEdit", INK)
	theme.set_color(&"font_placeholder_color", &"LineEdit", PENCIL_LIGHT)
	theme.set_color(&"caret_color", &"LineEdit", INK)
	theme.set_font_size(&"font_size", &"LineEdit", FONT_BODY)

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
