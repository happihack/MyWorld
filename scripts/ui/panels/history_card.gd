class_name HistoryCard
extends UIPanel
## What the player has done to this world (bible §27.2, §27.3): a few counts
## — "for reflection, not score" — and the acts worth remembering, year by
## year, the latest first: "YEAR 1 · touched first inhabitant".
##
## A card in the bottom-left corner, like the others; its list scrolls. It
## keeps itself up to date while it is open.

const MAX_WIDTH := 852.0
const EDGE_MARGIN := 32.0
## Room kept free on the right for the round buttons.
const RESERVED_RIGHT := 196.0
## Room kept free below: the card sits above the tool bar's row.
const BOTTOM_MARGIN := 308.0
## The list is no taller than this (it scrolls), and the card never leaves the screen.
const LIST_MAX_HEIGHT := 760.0
const LIST_MIN_HEIGHT := 150.0
## More entries than this are not listed (the latest are).
const MAX_SHOWN := 80
const REFRESH_INTERVAL_S := 0.5

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _counts: GridContainer = %Counts
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List
@onready var _close: Button = %Close

var _session: WorldSession
var _shown_total := -1
var _shown_entries := -1
var _refresh_timer := 0.0
var _settling := 0


func _ready() -> void:
	_close.pressed.connect(close)
	get_viewport().size_changed.connect(layout)
	refresh()


func setup(session: WorldSession) -> void:
	_session = session
	_shown_total = -1
	if is_node_ready():
		refresh()


func _process(delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


## Brings the card up to date with the history (cheap if nothing happened).
func refresh() -> void:
	if _session == null or not is_node_ready() or is_closing() or not _session.is_active:
		return
	var history := _session.history
	_subtitle.text = MemoryText.translate("HIST_NOW").format({"year": HistoryText.year_of(_session.clock.tick)})
	if history.total() == _shown_total and history.entry_count() == _shown_entries:
		return
	_shown_total = history.total()
	_shown_entries = history.entry_count()
	for child in _counts.get_children():
		child.queue_free()
	for row: Array in counters(history):
		var name_label := Label.new()
		name_label.text = row[0]
		name_label.theme_type_variation = UITheme.DIM
		_counts.add_child(name_label)
		var value_label := Label.new()
		value_label.text = str(row[1])
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_counts.add_child(value_label)
	for child in _list.get_children():
		child.queue_free()
	var lines := lines_of(history, MAX_SHOWN)
	if lines.is_empty():
		lines = PackedStringArray([MemoryText.translate("HIST_NONE")])
	for text in lines:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		_list.add_child(label)
	_settling = 3
	layout()


## Sits in the bottom-left corner, as wide as the screen allows, with a list
## that takes the room there is.
func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - EDGE_MARGIN - RESERVED_RIGHT, 200.0, MAX_WIDTH)
	_scroll.custom_minimum_size.y = 0.0
	var rest := get_combined_minimum_size().y
	var room := minf(view.y - BOTTOM_MARGIN - EDGE_MARGIN - rest, LIST_MAX_HEIGHT)
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 0.0, maxf(room, LIST_MIN_HEIGHT))
	reset_size()
	position = Vector2(EDGE_MARGIN, view.y - BOTTOM_MARGIN - size.y)


# --- what is shown --------------------------------------------------------------------------------

## The counts on the card: [[label, value], ...].
static func counters(history: PlayerHistory) -> Array:
	var stats := history.stats()
	return [
		[MemoryText.translate("HISTSTAT_TOTAL"), int(stats["total_interactions"])],
		[MemoryText.translate("HISTSTAT_PEOPLE"), int(stats["people_touched"])],
		[MemoryText.translate("HISTSTAT_OBJECTS"), int(stats["objects_moved"])],
	]


## The history's lines, the latest first (at most `count`). The same thing
## done several times running in one year is one line: "moved a boulder (12 times)".
static func lines_of(history: PlayerHistory, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	var entries := history.entries()
	var i := entries.size() - 1
	while i >= 0 and out.size() < count:
		var text := HistoryText.text(entries[i])
		var year := HistoryText.year_of(int(entries[i].get("tick", 0)))
		var times := 1
		while i - times >= 0 and HistoryText.year_of(int(entries[i - times].get("tick", 0))) == year 				and HistoryText.text(entries[i - times]) == text:
			times += 1
		if times > 1:
			text = MemoryText.translate("MEM_TIMES").format({"text": text, "count": times})
		out.append(MemoryText.translate("HIST_YEAR").format({"year": year, "text": text}))
		i -= times
	return out


# --- for tests ------------------------------------------------------------------------------------

func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


## The counts shown, as label -> value (text).
func count_rows() -> Dictionary:
	var out := {}
	var cells: Array[Label] = []
	for child in _counts.get_children():
		if child is Label and not child.is_queued_for_deletion():
			cells.append(child)
	for i in range(0, cells.size() - 1, 2):
		out[cells[i].text] = cells[i + 1].text
	return out


## The lines shown, the latest first.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _list.get_children():
		if child is Label and not child.is_queued_for_deletion():
			out.append((child as Label).text)
	return out
