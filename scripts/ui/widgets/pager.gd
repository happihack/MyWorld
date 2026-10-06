class_name Pager
extends HBoxContainer
## A long list a page at a time (the owner's playtest, 2026-10-05: lists
## such as the timeline grow ridiculously long over the centuries):
##
##   «  ‹   26–50 of 312   ›  »
##
## The list shows `range_of()`; the bar is hidden while everything fits on
## one page. `describe` may say what a page holds instead of the numbers
## (the timeline: its years).

## Another page was chosen.
signal page_changed(page: int)

## Rows on a page of a menu or card list.
const PAGE := 25

var page := 0
var page_size := PAGE
var total := 0
## (from: int, to: int, total: int) -> String; unset: "26–50 of 312".
var describe: Callable

var _first: Button
var _prev: Button
var _label: Label
var _next: Button
var _last: Button


func _init(size: int = PAGE) -> void:
	name = "Pager"
	page_size = maxi(size, 1)
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override(&"separation", 8)
	_first = _button("«", func() -> void: go(0))
	_prev = _button("‹", func() -> void: go(page - 1))
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.theme_type_variation = UITheme.DIM
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_next = _button("›", func() -> void: go(page + 1))
	_last = _button("»", func() -> void: go(pages() - 1))
	_refresh()


## How many there are to page through (the page is kept where it was, as far as there is one).
func set_total(count: int) -> void:
	total = maxi(count, 0)
	page = clampi(page, 0, pages() - 1)
	_refresh()


func pages() -> int:
	return maxi(ceili(total / float(page_size)), 1)


## The rows on the page shown: [from, to) as Vector2i(from, to).
func range_of() -> Vector2i:
	var from := page * page_size
	return Vector2i(from, mini(from + page_size, total))


## What of `items` is on the page shown.
func slice(items: Array) -> Array:
	var shown := range_of()
	return items.slice(shown.x, shown.y)


## Shows page `which` (within the pages there are).
func go(which: int) -> void:
	var to := clampi(which, 0, pages() - 1)
	if to == page:
		return
	page = to
	_refresh()
	page_changed.emit(page)


func text() -> String:
	return _label.text


func _refresh() -> void:
	visible = pages() > 1
	var shown := range_of()
	_label.text = describe.call(shown.x, shown.y, total) if describe.is_valid() \
		else MemoryText.translate("PAGER_RANGE").format({"from": shown.x + 1, "to": shown.y, "total": total})
	_first.disabled = page == 0
	_prev.disabled = page == 0
	_next.disabled = page >= pages() - 1
	_last.disabled = page >= pages() - 1


func _button(glyph: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = glyph
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(UITheme.TOUCH_TARGET * 0.85, UITheme.TOUCH_TARGET * 0.7)
	button.pressed.connect(pressed)
	add_child(button)
	return button
