class_name StatsPanel
extends UIPanel
## The world's numbers (M15, bible §27.1–27.3; begun as VS.2), in tabs —
## **Population** (with health and the ages), **Economy** (with what is built
## and sown), **Society**, **Environment**, **Player** (what the player has done
## and what the world makes of it). Each number as it is now and as a line;
## **a tap opens it**: a chart to look back along — the recent days hour by
## hour, the years day by day, the centuries year by year — and what the
## numbers say about what happened (Insights). Only what the world has gives
## a number; the rest waits (StatsCatalog). For reflection, not score. It
## keeps itself up to date while it is open.

const EDGE_MARGIN := 24.0
const TOP := 40.0
const MAX_WIDTH := 900.0
const REFRESH_INTERVAL_S := 1.0
## Kept clear below (the tools along the bottom).
const BOTTOM := 330.0
## The ages, in brackets of this many years (the last: and older).
const AGE_BRACKET := 10
const AGE_BRACKETS := 8
const RESOLUTIONS: Array[int] = [StatsRecorder.Resolution.HOURLY, StatsRecorder.Resolution.DAILY, StatsRecorder.Resolution.YEARLY]

var _session: WorldSession
var _title: Label
var _span: Label
var _close: Button
var _tabs: HFlowContainer
var _scroll: ScrollContainer
var _body: VBoxContainer
var _values: Dictionary = {} # series -> Label
var _lines: Dictionary = {} # series -> Sparkline
var _tab: StringName = StatsCatalog.POPULATION
var _detail: StringName = &""
var _resolution: int = StatsRecorder.Resolution.HOURLY
var _chart: Chart
var _ages: Chart
## What the page was built from: while it is the same, only the numbers change.
var _built := ""
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
	_tabs = HFlowContainer.new()
	content.add_child(_tabs)
	_span = Label.new()
	_span.theme_type_variation = UITheme.DIM
	_span.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	content.add_child(_span)
	content.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()


func setup(session: WorldSession) -> void:
	_session = session
	_redo()


## Shows a tab (StatsCatalog.TABS).
func set_tab(tab: StringName) -> void:
	_tab = tab
	_detail = &""
	_redo()


func tab() -> StringName:
	return _tab


## Opens one number: its chart, and what it says.
func open_detail(name: StringName) -> void:
	_detail = name
	_resolution = StatsRecorder.Resolution.HOURLY
	_redo()


func close_detail() -> void:
	_detail = &""
	_redo()


func detail() -> StringName:
	return _detail


## How far back the chart looks (StatsRecorder.Resolution).
func set_resolution(resolution: int) -> void:
	_resolution = resolution
	_redo()


func _redo() -> void:
	_shown_samples = -1
	_built = ""
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
	_span.text = span_text(stats.ticks(_resolution if _detail != &"" else StatsRecorder.Resolution.HOURLY))
	var said := _insights()
	var tabs := StatsCatalog.tabs(stats)
	var shown := StatsCatalog.shown(stats, _tab)
	var built := "%s|%s|%d|%s|%s|%s" % [_tab, _detail, _resolution, str(tabs), str(shown), str(said)]
	if built == _built:
		_update()
		return
	_built = built
	_draw_tabs(tabs)
	_tabs.visible = _detail == &"" # (the chart has the room; back is along the top)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_values.clear()
	_lines.clear()
	_chart = null
	_ages = null
	if _detail != &"":
		_draw_detail(_detail, said)
	else:
		_draw_tab(shown, said)
	_settling = 3


func _insights() -> PackedStringArray:
	var stats := _session.stats
	if _detail != &"":
		return Insights.lines(stats, _session.events, [_detail], 5)
	var about := StatsCatalog.shown(stats, _tab)
	if about.is_empty():
		return PackedStringArray() # (nothing of this tab to say anything about)
	return Insights.lines(stats, _session.events, about)


## The same page, newer numbers.
func _update() -> void:
	var stats := _session.stats
	var now := _now()
	for key: StringName in _values:
		(_values[key] as Label).text = value_text(key, float(now.get(key, 0.0)), _session)
		(_lines[key] as Sparkline).set_values(stats.series(key))
	if _chart != null:
		_chart.update_lines(stats.ticks(_resolution), [{"name": _detail, "values": stats.series(_detail, _resolution)}])
	if _ages != null:
		_set_ages(_ages)


func _now() -> Dictionary:
	var now := _session.stats.latest()
	if now.is_empty():
		now = _session.sample_stats() # (before the first hour is written down)
	return now


func _draw_tabs(tabs: Array[StringName]) -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for tab in tabs:
		var chip := Button.new()
		chip.text = MemoryText.translate("STATS_TAB_" + String(tab).to_upper())
		chip.name = "Tab_" + String(tab)
		chip.toggle_mode = true
		chip.button_pressed = tab == _tab
		chip.focus_mode = Control.FOCUS_NONE
		var which := tab
		chip.pressed.connect(func() -> void:
			AudioManager.play_ui(&"ui_tap")
			set_tab(which))
		_tabs.add_child(chip)


func _draw_tab(shown: Array[StringName], said: PackedStringArray) -> void:
	var stats := _session.stats
	var now := _now()
	if _tab == StatsCatalog.PLAYER:
		for row: Array in HistoryCard.counters(_session.history) + HistoryCard.world_counters(_session):
			_add_text("%s: %s" % [row[0], str(row[1])])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 10)
	_body.add_child(grid)
	for key in shown:
		var name := Button.new()
		name.text = StatsCatalog.label(key)
		name.name = "Stat_" + String(key)
		name.flat = true
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.focus_mode = Control.FOCUS_NONE
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var which := key
		name.pressed.connect(func() -> void:
			AudioManager.play_ui(&"ui_tap")
			open_detail(which))
		grid.add_child(name)
		var value := Label.new()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.custom_minimum_size = Vector2(170.0, 0.0)
		value.text = value_text(key, float(now.get(key, 0.0)), _session)
		grid.add_child(value)
		var line := Sparkline.new()
		line.from_zero = key != &"temperature"
		line.set_values(stats.series(key))
		grid.add_child(line)
		_values[key] = value
		_lines[key] = line
	if _tab == StatsCatalog.POPULATION and _session.people.size() > 0:
		_add_heading(MemoryText.translate("STATS_AGES"))
		_ages = Chart.new()
		_ages.custom_minimum_size = Vector2(300.0, 240.0)
		_set_ages(_ages)
		_body.add_child(_ages)
	if not said.is_empty():
		_add_heading(MemoryText.translate("STATS_INSIGHTS"))
		for text in said:
			_add_text(text)


func _set_ages(chart: Chart) -> void:
	var ages := ages_by_sex(_session)
	chart.set_bars(ages[0], ages[1], PackedStringArray([MemoryText.translate("STATS_WOMEN"), MemoryText.translate("STATS_MEN")]))


func _draw_detail(key: StringName, said: PackedStringArray) -> void:
	var stats := _session.stats
	var back := Button.new()
	back.text = "‹ " + StatsCatalog.label(key)
	back.name = "Back"
	back.flat = true
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close_detail)
	_body.add_child(back)
	var value := Label.new()
	value.text = value_text(key, float(_now().get(key, 0.0)), _session)
	value.theme_type_variation = UITheme.TITLE
	_body.add_child(value)
	# How far back: the hours of the recent days, the days of the years, the years.
	var row := HBoxContainer.new()
	_body.add_child(row)
	for resolution in RESOLUTIONS:
		if resolution != StatsRecorder.Resolution.HOURLY and stats.sample_count(resolution) < 2:
			continue
		var chip := Button.new()
		chip.text = MemoryText.translate("STATS_RES_%d" % resolution)
		chip.name = "Res_%d" % resolution
		chip.toggle_mode = true
		chip.button_pressed = resolution == _resolution
		chip.focus_mode = Control.FOCUS_NONE
		var which: int = resolution
		chip.pressed.connect(func() -> void:
			AudioManager.play_ui(&"ui_tap")
			set_resolution(which))
		row.add_child(chip)
	for step: float in [0.5, 2.0]:
		var zoom := Button.new()
		zoom.text = "+" if step < 1.0 else "−"
		zoom.focus_mode = Control.FOCUS_NONE
		zoom.custom_minimum_size = Vector2(UITheme.TOUCH_TARGET, 0.0)
		zoom.pressed.connect(func() -> void:
			if _chart != null:
				_chart.zoom_by(step))
		row.add_child(zoom)
	_chart = Chart.new()
	_chart.custom_minimum_size = Vector2(300.0, clampf(get_viewport_rect().size.y * 0.4, 200.0, 340.0) if is_inside_tree() else 340.0)
	_chart.set_lines(stats.ticks(_resolution), [{"name": key, "values": stats.series(key, _resolution)}])
	_body.add_child(_chart)
	_add_heading(MemoryText.translate("STATS_INSIGHTS"))
	if said.is_empty():
		_add_text(MemoryText.translate("STATS_NO_INSIGHT"))
	for text in said:
		_add_text(text)


## The living by age (brackets of AGE_BRACKET years) and sex:
## [labels, [PackedFloat32Array([women, men]) …]].
static func ages_by_sex(session: WorldSession) -> Array:
	var labels := PackedStringArray()
	var stacks: Array = []
	for i in AGE_BRACKETS:
		labels.append(("%d+" % (i * AGE_BRACKET)) if i == AGE_BRACKETS - 1 else str(i * AGE_BRACKET))
		stacks.append(PackedFloat32Array([0.0, 0.0]))
	var year := Config.time.ticks_per_year()
	for person in session.people.all_people():
		var bracket := clampi(person.age_years(session.clock.tick, year) / AGE_BRACKET, 0, AGE_BRACKETS - 1)
		var stack: PackedFloat32Array = stacks[bracket]
		stack[0 if person.sex == PersonData.Sex.FEMALE else 1] += 1.0
		stacks[bracket] = stack
	return [labels, stacks]


## What a number says, in words: "8", "4 days", "82%", "Clear · 1°".
static func value_text(key: StringName, value: float, session: WorldSession = null) -> String:
	if key == &"temperature" and session != null and session.weather != null:
		return UIText.weather_line(session.weather.state, value)
	return StatsCatalog.text(key, value)


## How far back the lines go: "Over the last 12 days", "Over the last 5 hours",
## "Over the last 30 years".
static func span_text(ticks: PackedInt64Array) -> String:
	if ticks.size() < 2:
		return MemoryText.translate("STATS_SPAN_NONE")
	var minutes := ticks[-1] - ticks[0]
	var day := TimeConfig.MINUTES_PER_DAY
	var year := Config.time.ticks_per_year()
	if minutes >= year * 2:
		return MemoryText.translate("STATS_SPAN_YEARS").format({"count": int(minutes / year)})
	if minutes >= day * 2:
		return MemoryText.translate("STATS_SPAN_DAYS").format({"count": int(minutes / day)})
	return MemoryText.translate("STATS_SPAN_HOURS").format({"count": maxi(int(minutes / 60), 1)})


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UITheme.DIM
	_body.add_child(label)


func _add_text(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	_body.add_child(label)


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
	var tallest := view.y - TOP - BOTTOM
	var rest := get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(_body.get_combined_minimum_size().y, 0.0, maxf(tallest - rest, 120.0))
	custom_minimum_size = Vector2(UIPanel.across(view, MAX_WIDTH, EDGE_MARGIN).y, 0.0)
	reset_size()
	position = Vector2(UIPanel.left_for(view, size.x, EDGE_MARGIN), TOP)


# --- for tests --------------------------------------------------------------------------------------

func value_label(key: StringName) -> Label:
	return _values.get(key)


func sparkline(key: StringName) -> Sparkline:
	return _lines.get(key)


func span_label() -> Label:
	return _span


func chart() -> Chart:
	return _chart


func ages_chart() -> Chart:
	return _ages


## The lines of words on the page (headings, counts, insights).
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _body.get_children():
		if child is Label and not child.is_queued_for_deletion():
			out.append((child as Label).text)
	return out


## The tabs shown, by name (StatsCatalog.TABS).
func tab_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for child in _tabs.get_children():
		if not child.is_queued_for_deletion() and String(child.name).begins_with("Tab_"):
			out.append(StringName(String(child.name).trim_prefix("Tab_")))
	return out


## The numbers on the page that open (their series).
func stat_buttons() -> Dictionary:
	var out := {}
	for button in find_children("Stat_*", "Button", true, false):
		if not button.is_queued_for_deletion():
			out[StringName(String(button.name).trim_prefix("Stat_"))] = button
	return out
