class_name WhileYouWereGone
extends UIPanel
## WHILE YOU WERE GONE (bible §26.8, M20): what happened in the box while the
## player was away — the counts, and one thing to go and look at.
##
##   WHILE YOU WERE GONE · 9 days have passed
##   12 births · 4 deaths · 1 new settlement · 2 discoveries
##   1 storm · 3 buildings completed · 1 unusual observation
##   "Something strange happened near the eastern mountains."   [ Locate ]
##
## Across the screen, the world dimmed behind it, until Continue (or Back).
## A count is tappable: the timeline, where it all is.

## Locate: the camera goes where the hook happened.
signal locate_requested(position: Vector2)
## A count was tapped: the timeline.
signal timeline_requested

const CARD_WIDTH := 820.0

var summary: Dictionary = {}
var _days: Label
var _counts: VBoxContainer
var _hook: Label
var _locate: Button
var _continue: Button


func _init() -> void:
	super._init()
	name = "WhileYouWereGone"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = MilestoneCard.DIM
	add_theme_stylebox_override(&"panel", backdrop)
	var middle := CenterContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle)
	var card := PanelContainer.new()
	card.name = "Card"
	var frame := MilestoneCard.style()
	frame.border_color = UITheme.RIM
	frame.shadow_color = Color(UITheme.RIM, 0.3)
	card.add_theme_stylebox_override(&"panel", frame)
	middle.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 22)
	card.add_child(column)
	var title := Label.new()
	title.text = "WHILE YOU WERE GONE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override(&"font_color", MilestoneCard.GOLD)
	title.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	column.add_child(title)
	_days = Label.new()
	_days.name = "Days"
	_days.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_days.theme_type_variation = UITheme.DIM
	column.add_child(_days)
	_counts = VBoxContainer.new()
	_counts.name = "Counts"
	_counts.add_theme_constant_override(&"separation", 6)
	column.add_child(_counts)
	_hook = Label.new()
	_hook.name = "Hook"
	_hook.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hook.add_theme_font_size_override(&"font_size", UITheme.FONT_TITLE)
	column.add_child(_hook)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 24)
	column.add_child(buttons)
	_locate = Button.new()
	_locate.name = "Locate"
	_locate.text = MemoryText.translate("LOCATE")
	_locate.focus_mode = Control.FOCUS_NONE
	_locate.custom_minimum_size = Vector2(240.0, UITheme.TOUCH_TARGET * 0.8)
	_locate.pressed.connect(func() -> void:
		var hook: Dictionary = summary.get("hook", {})
		if hook.has("position"):
			locate_requested.emit(hook["position"])
		close())
	buttons.add_child(_locate)
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


func setup(what: Dictionary) -> void:
	summary = what
	var days := int(what.get("days", 0))
	_days.text = "A day has passed in the box" if days <= 1 else "%d days have passed in the box" % days
	for child in _counts.get_children():
		child.queue_free()
	for line in lines(what.get("counts", {})):
		var button := Button.new()
		button.text = line
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override(&"font_size", UITheme.FONT_BODY)
		button.pressed.connect(func() -> void:
			timeline_requested.emit()
			close())
		_counts.add_child(button)
	var hook: Dictionary = what.get("hook", {})
	_hook.text = "“%s”" % hook["text"] if hook.has("text") else "All was quiet."
	_locate.visible = hook.has("position") and hook["position"] != Vector2.INF


## The counts in words, two lines at most, only what there was some of:
## "12 births · 4 deaths · 1 new settlement · 2 discoveries".
static func lines(counts: Dictionary) -> PackedStringArray:
	var first: Array = [] # (Arrays, not packed ones: these are filled through the table below)
	var second: Array = []
	for entry: Array in [["births", "birth", "births", first], ["deaths", "death", "deaths", first],
			["settlements", "new settlement", "new settlements", first], ["discoveries", "discovery", "discoveries", first],
			["storms", "storm", "storms", second], ["buildings", "building completed", "buildings completed", second],
			["observations", "unusual observation", "unusual observations", second]]:
		var n := int(counts.get(entry[0], 0))
		if n > 0:
			(entry[3] as Array).append("%d %s" % [n, entry[1] if n == 1 else entry[2]])
	var out := PackedStringArray()
	for part: Array in [first, second]:
		if not part.is_empty():
			out.append(" · ".join(PackedStringArray(part)))
	return out


## Is there anything to tell? (A quiet hour away needs no card.)
static func worth_telling(what: Dictionary) -> bool:
	return not lines(what.get("counts", {})).is_empty() or not (what.get("hook", {}) as Dictionary).is_empty()


func _fit() -> void:
	if not is_inside_tree():
		return
	_hook.custom_minimum_size.x = minf(CARD_WIDTH, get_viewport_rect().size.x * 0.8)


# --- for tests --------------------------------------------------------------------------------------

func count_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _counts.get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append((child as Button).text)
	return out


func hook_text() -> String:
	return _hook.text


func locate_button() -> Button:
	return _locate
