class_name TimelinePanel
extends UIPanel
## The world's history as a timeline (bible §21.4, M11.3): year by year,
## the latest first, through a filter (All · Major · People · Disasters ·
## Yours); a tap on an event looks for it — where it happened, or whom it
## concerned (see TimelineModel.locate). Long histories go a page at a time
## (Pager: the owner's playtest, 2026-10-05), the newest first, and scroll
## lightly: only the rows on screen are made (VirtualList).

## An event was tapped.
signal event_chosen(event_id: int)

const EDGE_MARGIN := 24.0
const TOP := 40.0
const MAX_WIDTH := 900.0
const ROW_HEIGHT := 120.0
## Rows on a page (events and the years between them).
const PAGE_ROWS := 100

var _session: WorldSession
var _filter: StringName = TimelineModel.FILTER_ALL
var _shown_size := -1
var _title: Label
var _close: Button
var _filters: Dictionary = {} # filter -> Button
var _list: VirtualList
var _pager: Pager
var _rows: Array = []
var _empty: Label
var _refresh := 0.0


func _init() -> void:
	super._init()
	var content := VBoxContainer.new()
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title = Label.new()
	_title.text = MemoryText.translate("TIMELINE_TITLE")
	_title.theme_type_variation = UITheme.TITLE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	header.add_child(_close)
	var chips := HFlowContainer.new()
	content.add_child(chips)
	for filter in TimelineModel.FILTERS:
		var chip := Button.new()
		chip.text = MemoryText.translate("TIMELINE_" + String(filter).to_upper())
		chip.toggle_mode = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.6)
		chip.pressed.connect(set_filter.bind(filter))
		chips.add_child(chip)
		_filters[filter] = chip
	content.add_child(HSeparator.new())
	_pager = Pager.new(PAGE_ROWS)
	_pager.describe = _describe_page
	_pager.page_changed.connect(func(_page: int) -> void: _show_page())
	content.add_child(_pager)
	_empty = Label.new()
	_empty.text = MemoryText.translate("TIMELINE_EMPTY")
	_empty.theme_type_variation = UITheme.DIM
	_empty.visible = false
	content.add_child(_empty)
	_list = VirtualList.new()
	_list.row_height = ROW_HEIGHT
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.make_row = _make_row
	content.add_child(_list)


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()


func setup(session: WorldSession) -> void:
	_session = session
	set_filter(_filter)


func filter() -> StringName:
	return _filter


func set_filter(which: StringName) -> void:
	_filter = which
	for key: StringName in _filters:
		(_filters[key] as Button).set_pressed_no_signal(key == which)
	_pager.page = 0
	_shown_size = -1
	refresh()


## Brings the list up to date (cheap when nothing new has happened).
func refresh() -> void:
	if _session == null or not _session.is_active:
		return
	var size_now := _session.events.size() + _session.events.merges
	if size_now == _shown_size:
		return
	_shown_size = size_now
	_rows = TimelineModel.rows(_session.events, _filter)
	_pager.set_total(_rows.size())
	_show_page()
	_empty.visible = _rows.is_empty()


## The rows of the page shown — under the heading of their year, when the
## page begins within one.
func _show_page() -> void:
	var shown := _pager.slice(_rows)
	if not shown.is_empty() and not (shown[0] as Dictionary).has("year"):
		shown.push_front({"year": HistoryText.year_of((shown[0]["event"] as WorldEvent).tick)})
	_list.set_items(shown)


## What a page holds: "Years 40–37 · 2/9".
func _describe_page(from: int, to: int, _total: int) -> String:
	var newest := -1
	var oldest := -1
	for i in range(from, to):
		var row: Dictionary = _rows[i]
		var year := int(row["year"]) if row.has("year") else HistoryText.year_of((row["event"] as WorldEvent).tick)
		if newest < 0:
			newest = year
		oldest = year
	var years := MemoryText.translate("TIMELINE_YEAR").format({"year": newest}) if newest == oldest 		else MemoryText.translate("TIMELINE_PAGE_YEARS").format({"newest": newest, "oldest": oldest})
	return MemoryText.translate("TIMELINE_PAGE").format({"years": years, "page": _pager.page + 1, "pages": _pager.pages()})


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		refresh()


func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size = Vector2(UIPanel.across(view, MAX_WIDTH, EDGE_MARGIN).y, maxf(view.y - TOP - 330.0, 400.0))
	reset_size()
	position = Vector2(UIPanel.left_for(view, size.x, EDGE_MARGIN), TOP)


func _make_row(item: Variant, _index: int) -> Control:
	var row: Dictionary = item
	if row.has("year"):
		var label := Label.new()
		label.text = MemoryText.translate("TIMELINE_YEAR").format({"year": int(row["year"])})
		label.theme_type_variation = UITheme.TITLE
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		return label
	var event: WorldEvent = row["event"]
	var button := Button.new()
	button.text = EventText.text(event, _session.people, _session.events)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.clip_text = true
	button.focus_mode = Control.FOCUS_NONE
	button.flat = event.significance < Config.events.major_from and not event.has_tag("first")
	button.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	var id := event.id
	button.pressed.connect(func() -> void: event_chosen.emit(id))
	return button


# --- for tests --------------------------------------------------------------------------------------

func list() -> VirtualList:
	return _list


func pager() -> Pager:
	return _pager


func filter_button(which: StringName) -> Button:
	return _filters.get(which)
