class_name VirtualList
extends ScrollContainer
## A long list that only makes the rows on screen (M11.3: a history of
## thousands of events scrolls as lightly as one of ten). Every row is the
## same height; `make_row` builds a row's Control for an item (it is given
## the item and its index), and rows that scroll away are freed.

## How far beyond the visible part rows are kept (rows).
const MARGIN := 4

var row_height := 110.0
## (item: Variant, index: int) -> Control
var make_row: Callable

var _items: Array = []
var _content: Control
var _shown: Dictionary = {} # index -> Control


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _fill())
	resized.connect(_fill)


## Shows `items` (the list starts at the top again).
func set_items(items: Array) -> void:
	_items = items
	for index: int in _shown:
		(_shown[index] as Control).queue_free()
	_shown.clear()
	_content.custom_minimum_size = Vector2(0.0, row_height * items.size())
	scroll_vertical = 0
	_fill()


func item_count() -> int:
	return _items.size()


## The rows made now (for tests: never more than fit on screen, and a few).
func shown_count() -> int:
	return _shown.size()


func row_at(index: int) -> Control:
	return _shown.get(index)


## Scrolls so that the row `index` is at the top.
func scroll_to(index: int) -> void:
	scroll_vertical = int(row_height * clampi(index, 0, maxi(_items.size() - 1, 0)))
	_fill()


func _fill() -> void:
	if not make_row.is_valid():
		return
	var top := float(scroll_vertical)
	var height := maxf(size.y, row_height)
	var first := maxi(floori(top / row_height) - MARGIN, 0)
	var last := mini(ceili((top + height) / row_height) + MARGIN, _items.size() - 1)
	for index: int in _shown.keys():
		if index < first or index > last:
			(_shown[index] as Control).queue_free()
			_shown.erase(index)
	for index in range(first, last + 1):
		if _shown.has(index):
			continue
		var row: Control = make_row.call(_items[index], index)
		if row == null:
			continue
		row.position = Vector2(0.0, row_height * index)
		row.size = Vector2(maxf(size.x - 8.0, 100.0), row_height)
		_content.add_child(row)
		_shown[index] = row
	for index: int in _shown:
		(_shown[index] as Control).size.x = maxf(size.x - 8.0, 100.0)
