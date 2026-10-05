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
## What came of the acts is looked at again every this many refreshes, and
## for this many of the latest lines.
const CONSEQUENCES_EVERY := 10
const CONSEQUENCES_SHOWN := 20

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
var _consequence_timer := 0


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
	# (What came of the acts changes as the world goes on: looked at again now and then.)
	_consequence_timer -= 1
	if history.total() == _shown_total and history.entry_count() == _shown_entries and _consequence_timer > 0:
		return
	_consequence_timer = CONSEQUENCES_EVERY
	_shown_total = history.total()
	_shown_entries = history.entry_count()
	for child in _counts.get_children():
		child.queue_free()
	for row: Array in counters(history) + world_counters(_session):
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
	# Where it led, in the end: the stories the player's doing is in (M19.3).
	if _session.stories != null:
		var theirs := _session.stories.of_the_player()
		if not theirs.is_empty():
			var heading := Label.new()
			heading.text = MemoryText.translate("HIST_STORIES")
			heading.theme_type_variation = UITheme.DIM
			_list.add_child(heading)
			for n in range(theirs.size() - 1, maxi(theirs.size() - 4, -1), -1):
				var told := Label.new()
				told.text = _session.stories.line(theirs[n])
				told.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				told.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
				_list.add_child(told)
	var groups := groups_of(history, MAX_SHOWN)
	if groups.is_empty():
		var none := Label.new()
		none.text = MemoryText.translate("HIST_NONE")
		_list.add_child(none)
	for n in groups.size():
		var label := Label.new()
		label.text = groups[n]["line"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		_list.add_child(label)
		# What came of it (the latest acts: looking further back costs more than it tells).
		if n < CONSEQUENCES_SHOWN:
			for text in PlayerConsequences.lines(_session, groups[n]["ids"]):
				var came := Label.new()
				came.text = text
				came.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				came.theme_type_variation = UITheme.DIM
				came.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
				_list.add_child(came)
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

## The counts on the card: [[label, value], ...] — what was done (the rest
## only once there is any of it: the card grows with what the player does).
static func counters(history: PlayerHistory) -> Array:
	var stats := history.stats()
	var out: Array = [
		[MemoryText.translate("HISTSTAT_TOTAL"), int(stats["total_interactions"])],
		[MemoryText.translate("HISTSTAT_PEOPLE"), int(stats["people_touched"])],
		[MemoryText.translate("HISTSTAT_OBJECTS"), int(stats["objects_moved"])],
	]
	for key: String in ["rain_made", "gusts", "ground_carved", "trees_uprooted"]:
		if int(stats.get(key, 0)) > 0:
			out.append([MemoryText.translate("HISTSTAT_" + key.to_upper()), int(stats[key])])
	return out


## What the world makes of it (bible §27.3): who remembers the player's acts,
## the generations witnessed, the myths — once there is any of it.
static func world_counters(session: WorldSession) -> Array:
	var out: Array = []
	if session == null:
		return out
	var remember := PlayerConsequences.people_who_remember(session)
	if remember > 0:
		out.append([MemoryText.translate("HISTSTAT_REMEMBER"), remember])
	var generations := generations_witnessed(session)
	if generations > 1:
		out.append([MemoryText.translate("HISTSTAT_GENERATIONS"), generations])
	if session.culture != null and not session.culture.myths().is_empty():
		out.append([MemoryText.translate("HISTSTAT_MYTHS"), session.culture.myths().size()])
	return out


## How many generations the player has seen: the longest line of those born
## since the world began, and the band it began with.
static func generations_witnessed(session: WorldSession) -> int:
	var depth := {}
	var deepest := 1
	var everyone: Array = []
	for record in session.archive.all_records():
		everyone.append([record.id, record.birth_tick, record.parents])
	for person in session.people.all_people():
		everyone.append([person.id, person.birth_tick, person.parents])
	everyone.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) < int(b[1]) or (a[1] == b[1] and a[0] < b[0]))
	for entry: Array in everyone:
		var mine := 1
		if int(entry[1]) >= 0: # (born in the world: a generation more than their parents)
			for parent: int in entry[2]:
				mine = maxi(mine, int(depth.get(parent, 1)) + 1)
		depth[entry[0]] = mine
		deepest = maxi(deepest, mine)
	return deepest


## The history's lines, the latest first (at most `count`). The same thing
## done several times running in one year is one line: "moved a boulder (12 times)".
static func lines_of(history: PlayerHistory, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for group: Dictionary in groups_of(history, count):
		out.append(group["line"])
	return out


## The same, with the acts each line stands for: [{"line": String, "ids": Array}, …].
static func groups_of(history: PlayerHistory, count: int) -> Array:
	var out: Array = []
	var entries := history.entries()
	var i := entries.size() - 1
	while i >= 0 and out.size() < count:
		var text := HistoryText.text(entries[i])
		var year := HistoryText.year_of(int(entries[i].get("tick", 0)))
		var times := 1
		var ids: Array = [int(entries[i].get("id", 0))]
		while i - times >= 0 and HistoryText.year_of(int(entries[i - times].get("tick", 0))) == year \
				and HistoryText.text(entries[i - times]) == text:
			ids.append(int(entries[i - times].get("id", 0)))
			times += 1
		if times > 1:
			text = MemoryText.translate("MEM_TIMES").format({"text": text, "count": times})
		out.append({"line": MemoryText.translate("HIST_YEAR").format({"year": year, "text": text}), "ids": ids})
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
