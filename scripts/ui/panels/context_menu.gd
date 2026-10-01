class_name ContextMenu
extends UIPanel
## The long-press menu (bible §23.1, §26.6): a compact card next to the finger
## naming what was pressed and what can be done with it. Closes when an action
## is chosen or the world is touched.

signal action_chosen(action: StringName)

## Distance kept between the finger and the card, so the hand does not hide it.
const FINGER_GAP := 70.0
const EDGE_MARGIN := 24.0
const MIN_WIDTH := 460.0

@onready var _title: Label = %Title
@onready var _options: VBoxContainer = %Options


func _init() -> void:
	super()
	transient = true


func _ready() -> void:
	# The title lines up with the text of the options below it.
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = UITheme.BUTTON_PAD
	pad.content_margin_right = UITheme.BUTTON_PAD
	_title.add_theme_stylebox_override(&"normal", pad)


## `actions`: [{ "id": StringName, "label": String }, ...] in display order.
func setup(title: String, actions: Array[Dictionary]) -> void:
	_title.text = title
	for child in _options.get_children():
		child.queue_free()
	for action in actions:
		var button := Button.new()
		button.name = String(action["id"]).capitalize().replace(" ", "")
		button.text = action["label"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(MIN_WIDTH, UITheme.TOUCH_TARGET)
		button.pressed.connect(_choose.bind(action["id"]))
		_options.add_child(button)
	reset_size()


## Puts the card next to `anchor` (the finger), inside `view`.
func place_near(anchor: Vector2, view: Rect2) -> void:
	reset_size()
	position = place(anchor, size, view)


func option_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in _options.get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append(child)
	return out


func title_text() -> String:
	return _title.text


## Top-left corner for a card of `card_size` next to `anchor`: above the finger
## if there is room, otherwise below it, otherwise beside it (a wide, low
## screen) — and never off the screen.
static func place(anchor: Vector2, card_size: Vector2, view: Rect2,
		gap: float = FINGER_GAP, margin: float = EDGE_MARGIN) -> Vector2:
	var min_x := view.position.x + margin
	var max_x := maxf(view.end.x - margin - card_size.x, min_x)
	var min_y := view.position.y + margin
	var max_y := maxf(view.end.y - margin - card_size.y, min_y)
	var x := anchor.x - card_size.x * 0.5
	var y := anchor.y - gap - card_size.y
	if y < min_y:
		y = anchor.y + gap
		if y > max_y:
			# No room above or below: beside the finger, on the roomier side.
			y = anchor.y - card_size.y * 0.5
			x = anchor.x + gap
			if x > max_x:
				x = anchor.x - gap - card_size.x
	return Vector2(clampf(x, min_x, max_x), clampf(y, min_y, max_y))


func _choose(action: StringName) -> void:
	if is_closing():
		return
	action_chosen.emit(action)
	close()
