class_name Chart
extends Control
## A chart (M15, bible §27.1): **lines over time** — dragged to look back,
## zoomed in and out — or **stacked bars** (the ages, by men and women). Its
## colours are told apart by anyone (the Okabe–Ito palette), and every line
## also has its own mark (a circle, a square, a triangle, a diamond), so no
## colour has to be seen to be read.

enum Mode { LINE, BARS }
enum Mark { CIRCLE, SQUARE, TRIANGLE, DIAMOND }

const PALETTE: Array[Color] = [Color("#56B4E9"), Color("#E69F00"), Color("#009E73"), Color("#CC79A7"),
	Color("#F0E442"), Color("#0072B2"), Color("#D55E00")]
const PAD := Vector2(64.0, 30.0)
const MARK_SIZE := 6.0
## Marks on a line no closer than this (pixels).
const MARK_EVERY := 48.0
## The fewest samples a window shows (zoomed in as far as it goes).
const WINDOW_LEAST := 4
## Room for the bars' legend (pixels).
const LEGEND := 18.0

var mode: int = Mode.LINE
var _ticks := PackedInt64Array()
var _lines: Array = [] # [{"name", "values": PackedFloat32Array}]
var _first := 0
var _last := 0
var _labels := PackedStringArray()
var _stacks: Array = [] # per bar: PackedFloat32Array (one value per stack)
var _stack_names := PackedStringArray()
var _drag_from := Vector2.INF
## How many samples there were when last given (the arrays given are shared:
## they may have grown since).
var _count := 0


func _init() -> void:
	custom_minimum_size = Vector2(300.0, 260.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


## Lines over time: the same `ticks` for each of `lines` [{"name", "values"}];
## the whole of it in view.
func set_lines(ticks: PackedInt64Array, lines: Array) -> void:
	mode = Mode.LINE
	_ticks = ticks
	_lines = lines
	_count = ticks.size()
	_first = 0
	_last = maxi(ticks.size() - 1, 0)
	queue_redraw()


## New samples for the same lines: the window stays where it was (and, if it
## showed the latest, keeps showing the latest).
func update_lines(ticks: PackedInt64Array, lines: Array) -> void:
	if mode != Mode.LINE or _count < 2 or ticks.is_empty():
		set_lines(ticks, lines)
		return
	var following := _last >= _count - 1
	var span := _last - _first
	# (What was given only grew, or was let go of and is as it was: either way
	# its first in view is still where it was.)
	var first_tick := _ticks[mini(_first, _ticks.size() - 1)]
	_ticks = ticks
	_lines = lines
	_count = ticks.size()
	var end := maxi(ticks.size() - 1, 0)
	if following:
		_last = end
		_first = maxi(_last - span, 0)
	else:
		_first = clampi(ticks.bsearch(first_tick), 0, end)
		_last = clampi(_first + span, 0, end)
	queue_redraw()


## Stacked bars: one per label, each a stack of values (one per stack name).
func set_bars(labels: PackedStringArray, stacks: Array, stack_names: PackedStringArray) -> void:
	mode = Mode.BARS
	_labels = labels
	_stacks = stacks
	_stack_names = stack_names
	queue_redraw()


## The samples in view (indices, both ends in).
func window() -> Vector2i:
	return Vector2i(_first, _last)


## Closer (factor < 1: fewer samples in view) or further, about the middle.
func zoom_by(factor: float) -> void:
	if _ticks.size() < 2:
		return
	var middle := (_first + _last) * 0.5
	var span := clampf((_last - _first) * factor, float(mini(WINDOW_LEAST, _ticks.size() - 1)), float(_ticks.size() - 1))
	_first = clampi(roundi(middle - span * 0.5), 0, _ticks.size() - 1)
	_last = clampi(_first + roundi(span), 0, _ticks.size() - 1)
	_first = clampi(_last - roundi(span), 0, _ticks.size() - 1)
	queue_redraw()


## Back (negative) or forward in time by `samples`.
func pan_by(samples: int) -> void:
	var span := _last - _first
	_first = clampi(_first + samples, 0, maxi(_ticks.size() - 1 - span, 0))
	_last = _first + span
	queue_redraw()


func _plot() -> Rect2:
	var plot := Rect2(PAD, size - PAD * Vector2(1.4, 2.0))
	if mode == Mode.BARS:
		# (Room above for what the colours are.)
		plot = plot.grow_side(SIDE_TOP, -LEGEND)
	return plot


## The least and the most of what is in view.
func value_range() -> Vector2:
	var least := INF
	var most := -INF
	for line: Dictionary in _lines:
		var values: PackedFloat32Array = line["values"]
		for i in range(_first, mini(_last + 1, values.size())):
			least = minf(least, values[i])
			most = maxf(most, values[i])
	if least == INF:
		return Vector2(0.0, 1.0)
	if most - least < 0.0001:
		return Vector2(least - 0.5, most + 0.5)
	return Vector2(minf(least, 0.0) if least >= 0.0 else least, most)


## Where line `index`'s samples in view are drawn.
func points(index: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if index >= _lines.size() or _ticks.size() < 1:
		return out
	var plot := _plot()
	var range_now := value_range()
	var values: PackedFloat32Array = _lines[index]["values"]
	var span := maxf(_last - _first, 1)
	for i in range(_first, mini(_last + 1, values.size())):
		var x := plot.position.x + plot.size.x * (i - _first) / span
		var share := (values[i] - range_now.x) / (range_now.y - range_now.x)
		out.append(Vector2(x, plot.end.y - plot.size.y * share))
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	var small := UITheme.FONT_SMALL - 6
	var plot := _plot()
	draw_rect(plot, Color(UITheme.INK, 0.06))
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, Color(UITheme.INK, 0.35), 1.0)
	if mode == Mode.BARS:
		_draw_bars(plot, font, small)
		return
	if _ticks.is_empty():
		return
	var range_now := value_range()
	draw_string(font, Vector2(4.0, plot.position.y + small), _short(range_now.y), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 8.0, small, UITheme.INK_DIM)
	draw_string(font, Vector2(4.0, plot.end.y), _short(range_now.x), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 8.0, small, UITheme.INK_DIM)
	var half := plot.size.x * 0.5
	draw_string(font, Vector2(plot.position.x, plot.end.y + small + 6.0), MainMenu.date_of(_ticks[_first]), HORIZONTAL_ALIGNMENT_LEFT, half - 4.0, small, UITheme.INK_DIM)
	draw_string(font, Vector2(plot.end.x - half + 4.0, plot.end.y + small + 6.0), MainMenu.date_of(_ticks[_last]), HORIZONTAL_ALIGNMENT_RIGHT, half - 4.0, small, UITheme.INK_DIM)
	for index in _lines.size():
		var color := PALETTE[index % PALETTE.size()]
		var at := points(index)
		if at.size() > 1:
			draw_polyline(at, color, 2.5, true)
		var last_mark := -INF
		for p in at:
			if p.x - last_mark >= MARK_EVERY:
				_mark(p, index % 4, color)
				last_mark = p.x
		if not at.is_empty():
			_mark(at[-1], index % 4, color)


func _draw_bars(plot: Rect2, font: Font, small: int) -> void:
	if _stacks.is_empty():
		return
	var most := 0.0
	for stack: PackedFloat32Array in _stacks:
		var total := 0.0
		for v in stack:
			total += v
		most = maxf(most, total)
	most = maxf(most, 1.0)
	var width := plot.size.x / _stacks.size()
	for i in _stacks.size():
		var stack: PackedFloat32Array = _stacks[i]
		var bottom := plot.end.y
		for j in stack.size():
			var height := plot.size.y * stack[j] / most
			var color := PALETTE[j % PALETTE.size()]
			draw_rect(Rect2(plot.position.x + width * i + 3.0, bottom - height, width - 6.0, height), color)
			bottom -= height
		if i < _labels.size():
			draw_string(font, Vector2(plot.position.x + width * i, plot.end.y + small + 6.0), _labels[i], HORIZONTAL_ALIGNMENT_CENTER, width, small, UITheme.INK_DIM)
	draw_string(font, Vector2(4.0, plot.position.y + small), str(roundi(most)), HORIZONTAL_ALIGNMENT_LEFT, PAD.x - 8.0, small, UITheme.INK_DIM)
	for j in _stack_names.size():
		var at := Vector2(plot.position.x + 10.0 + j * 160.0, plot.position.y - LEGEND * 0.6)
		_mark(at + Vector2(0.0, -small * 0.35), j % 4, PALETTE[j % PALETTE.size()])
		draw_string(font, at + Vector2(14.0, 0.0), _stack_names[j], HORIZONTAL_ALIGNMENT_LEFT, -1, small, UITheme.INK)


func _mark(at: Vector2, kind: int, color: Color) -> void:
	var r := MARK_SIZE
	match kind:
		Mark.SQUARE:
			draw_rect(Rect2(at - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), color)
		Mark.TRIANGLE:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, r * 0.8), at + Vector2(-r, r * 0.8)]), color)
		Mark.DIAMOND:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)]), color)
		_:
			draw_circle(at, r * 0.85, color)


static func _short(value: float) -> String:
	if absf(value) >= 1000.0:
		return "%.1fk" % (value / 1000.0)
	if absf(value) < 10.0 and absf(value - roundf(value)) > 0.01:
		return "%.1f" % value
	return str(roundi(value))


func _gui_input(event: InputEvent) -> void:
	if mode != Mode.LINE:
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return # (on a phone every touch comes twice: as itself and as a mouse)
	var point := Vector2.INF
	var pressed := false
	var released := false
	if event is InputEventScreenTouch or (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		point = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and _drag_from != Vector2.INF):
		point = event.position
	elif event is InputEventMouseButton and event.pressed:
		# The wheel zooms.
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.8)
		elif (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.25)
		accept_event()
		return
	if point == Vector2.INF:
		return
	accept_event()
	if pressed:
		_drag_from = point
	elif released:
		_drag_from = Vector2.INF
	elif _drag_from != Vector2.INF:
		# Dragged: the time moves with the finger.
		var per_sample := _plot().size.x / maxf(_last - _first, 1)
		var steps := roundi((_drag_from.x - point.x) / per_sample)
		if steps != 0:
			pan_by(steps)
			_drag_from = point
