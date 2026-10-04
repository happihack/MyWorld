class_name StatsPanel
extends UIPanel
## The world's numbers (VS.2, a first piece of M15; bible §27.3): how many
## people, how many days the food in store lasts, the water, wood and stone,
## how healthy and how content they are, the weather — each as it is now and
## as a line over the days kept (StatsRecorder: a sample every game hour).
## For reflection, not score. Opened from the menu (WORLD → Statistics); it
## keeps itself up to date while it is open.

const EDGE_MARGIN := 24.0
const TOP := 40.0
const MAX_WIDTH := 900.0
const REFRESH_INTERVAL_S := 1.0

## [series, title key] in the order shown. The weather's line is its temperature.
const ROWS: Array = [
	[&"population", "STATS_POPULATION"],
	[&"food_days", "STATS_FOOD"],
	[&"water", "STATS_WATER"],
	[&"wood", "STATS_WOOD"],
	[&"stone", "STATS_STONE"],
	[&"health", "STATS_HEALTH"],
	[&"mood", "STATS_MOOD"],
	[&"temperature", "STATS_WEATHER"],
]

var _session: WorldSession
var _title: Label
var _span: Label
var _close: Button
var _scroll: ScrollContainer
var _grid: GridContainer
var _values: Dictionary = {} # series -> Label
var _lines: Dictionary = {} # series -> Sparkline
var _shown_samples := -1
var _refresh := 0.0
var _settling := 0


func _init() -> void:
	super._init()
	var content := VBoxContainer.new()
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title = Label.new()
	_title.text = MemoryText.translate("STATS_TITLE")
	_title.theme_type_variation = UITheme.TITLE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	header.add_child(_close)
	_span = Label.new()
	_span.theme_type_variation = UITheme.DIM
	_span.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	content.add_child(_span)
	content.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 18)
	_grid.add_theme_constant_override(&"v_separation", 14)
	_scroll.add_child(_grid)
	for row: Array in ROWS:
		var name := Label.new()
		name.text = MemoryText.translate(row[1])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(name)
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(170.0, 0.0)
		_grid.add_child(value)
		var line := Sparkline.new()
		line.from_zero = row[0] != &"temperature"
		_grid.add_child(line)
		_values[row[0]] = value
		_lines[row[0]] = line


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()


func setup(session: WorldSession) -> void:
	_session = session
	_shown_samples = -1
	refresh()


## Brings the numbers up to date (cheap when no new sample was taken).
func refresh() -> void:
	if _session == null or not _session.is_active:
		return
	var stats := _session.stats
	var count := stats.sample_count()
	if count == _shown_samples:
		return
	_shown_samples = count
	var now := stats.latest()
	if now.is_empty():
		now = _session.sample_stats() # (before the first hour is written down)
	for row: Array in ROWS:
		var key: StringName = row[0]
		(_values[key] as Label).text = value_text(key, float(now.get(key, 0.0)), _session)
		(_lines[key] as Sparkline).set_values(stats.series(key))
	_span.text = span_text(stats.ticks())
	_settling = 3


## What a number says, in words: "8", "4 days", "82%", "Clear · 1°".
static func value_text(key: StringName, value: float, session: WorldSession = null) -> String:
	match key:
		&"food_days":
			return MemoryText.translate("STATS_DAYS").format({"days": snappedf(value, 0.1) if value < 10.0 else roundi(value)})
		&"health", &"mood":
			return "%d%%" % roundi(value * 100.0)
		&"temperature":
			if session != null and session.weather != null:
				return UIText.weather_line(session.weather.state, value)
			return UIText.temperature_text(value)
		_:
			return String.num_int64(roundi(value))


## How far back the lines go: "The last 12 days", "The last 5 hours".
static func span_text(ticks: PackedInt64Array) -> String:
	if ticks.size() < 2:
		return MemoryText.translate("STATS_SPAN_NONE")
	var minutes := ticks[-1] - ticks[0]
	var day := TimeConfig.MINUTES_PER_DAY
	if minutes >= day * 2:
		return MemoryText.translate("STATS_SPAN_DAYS").format({"count": int(minutes / day)})
	return MemoryText.translate("STATS_SPAN_HOURS").format({"count": maxi(int(minutes / 60), 1)})


func _process(delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_INTERVAL_S
		refresh()


func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	var tallest := view.y - TOP - 330.0
	_scroll.custom_minimum_size.y = 0.0
	var rest := get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(_grid.get_combined_minimum_size().y, 0.0, maxf(tallest - rest, 200.0))
	custom_minimum_size = Vector2(clampf(view.x - EDGE_MARGIN * 2.0 - 120.0, 300.0, MAX_WIDTH), 0.0)
	reset_size()
	position = Vector2(EDGE_MARGIN, TOP)


# --- for tests --------------------------------------------------------------------------------------

func value_label(key: StringName) -> Label:
	return _values.get(key)


func sparkline(key: StringName) -> Sparkline:
	return _lines.get(key)


func span_label() -> Label:
	return _span
