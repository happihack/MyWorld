class_name CemeteryCard
extends UIPanel
## A cemetery, read: whose it is, how many lie there, and each of them — the
## last laid first, with their years and what they died of. Each can be read
## in turn (their grave card).
##
## A card in the bottom-left corner, like the others; its list scrolls.

## Someone laid here was picked (to read their grave).
signal person_chosen(person_id: int)
## The cemetery is to be looked at.
signal locate_requested(position: Vector2)

const MAX_WIDTH := 1016.0
const EDGE_MARGIN := 32.0
const BOTTOM_MARGIN := 308.0
const LIST_MAX_HEIGHT := 760.0
const LIST_MIN_HEIGHT := 150.0

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List
@onready var _close: Button = %Close

var _session: WorldSession
var _cemetery_id := 0
var _settling := 0


func _ready() -> void:
	_close.pressed.connect(close)
	get_viewport().size_changed.connect(layout)
	refresh()


func setup(session: WorldSession, cemetery_id: int) -> void:
	_session = session
	_cemetery_id = cemetery_id
	if is_node_ready():
		refresh()


func cemetery_id() -> int:
	return _cemetery_id


func _process(_delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()


func refresh() -> void:
	if _session == null or not is_node_ready() or is_closing():
		return
	var said := facts(_session, _cemetery_id)
	if said.is_empty():
		return
	_title.text = said["title"]
	_subtitle.text = said["count"]
	for child in _list.get_children():
		child.queue_free()
	_add_locate()
	for row: Array in said["dead"]:
		var button := Button.new()
		button.text = "%s\n%s" % [row[1], row[2]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.9)
		button.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		var id: int = row[0]
		button.pressed.connect(func() -> void: person_chosen.emit(id))
		_list.add_child(button)
	if (said["dead"] as Array).is_empty():
		var label := Label.new()
		label.text = MemoryText.translate("CEMETERY_EMPTY")
		label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		_list.add_child(label)
	_settling = 3
	layout()


func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = UIPanel.across(view, MAX_WIDTH, EDGE_MARGIN).y
	_scroll.custom_minimum_size.y = 0.0
	var rest := get_combined_minimum_size().y
	var room := minf(view.y - BOTTOM_MARGIN - EDGE_MARGIN - rest, LIST_MAX_HEIGHT)
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 0.0, maxf(room, LIST_MIN_HEIGHT))
	reset_size()
	position = Vector2(UIPanel.left_for(view, size.x, EDGE_MARGIN), view.y - BOTTOM_MARGIN - size.y)


# --- what is said ---------------------------------------------------------------------------------

## What the card says of a cemetery, as plain values ({} if it is not one):
##   title, count: String; dead: Array of [person id, name, "years · cause"],
##   the last laid first.
static func facts(session: WorldSession, cemetery_id: int) -> Dictionary:
	var cemetery := session.props.get_prop(cemetery_id)
	if cemetery == null or cemetery.kind != PropData.Kind.CEMETERY:
		return {}
	var settlement := session.settlements.nearest(cemetery.tile)
	var title := MemoryText.translate("CEMETERY_OF").format({"place": settlement.display_name()}) if settlement != null \
		else MemoryText.translate("CEMETERY")
	var laid := session.archive.all_buried_in(cemetery_id)
	var dead: Array = []
	for i in range(laid.size() - 1, -1, -1):
		var record := laid[i]
		dead.append([record.id, record.full_name(), "%s · %s" % [GraveCard.years_line(record), GraveCard.cause_line(record)]])
	var count := MemoryText.translate("CEMETERY_ONE") if laid.size() == 1 \
		else MemoryText.translate("CEMETERY_COUNT").format({"count": laid.size()})
	return {"title": title, "count": count, "dead": dead}


func _add_locate() -> void:
	var cemetery := _session.props.get_prop(_cemetery_id)
	if cemetery == null:
		return
	var locate := Button.new()
	locate.text = MemoryText.translate("LOCATE")
	locate.name = "Locate"
	locate.focus_mode = Control.FOCUS_NONE
	locate.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
	var at := cemetery.position2d()
	locate.pressed.connect(func() -> void: locate_requested.emit(at))
	_list.add_child(locate)


# --- for tests --------------------------------------------------------------------------------------

func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


## The buttons for the dead, in order (not Locate).
func dead_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.name != "Locate":
			out.append(child)
	return out
