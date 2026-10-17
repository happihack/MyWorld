class_name SpeedControl
extends VBoxContainer
## The world's clock and how fast it runs, in the top-right corner of the HUD
## (bible §9.2, §26.4): the time of day, the date and the weather, and under
## them a round button showing the speed (‖ ▶ ▶▶ ▶▶▶) — the text at the very
## top, the buttons in a column below (the owner's playtest, 2026-10-05).
##
##   tap          pause / carry on at the speed it had before
##   long press   asks for the selector (Pause / Normal / Fast / Very fast)
##
## Pausing freezes the world, not the UI or the camera.

## The player chose a speed (GameClock.SPEED_*).
signal speed_chosen(index: int)
## The player held the button: show the selector.
signal selector_requested

const BUTTON_SIZE := UITheme.TOUCH_TARGET # (the round buttons under it are as big: the owner, 2026-10-05)
const EDGE_MARGIN := 32.0
const TOP := 56.0
## Room between the weather and the button below it.
const BUTTON_GAP := 16.0
const REFRESH_INTERVAL_S := 0.2
const LIT := Color(1.0, 0.82, 0.36)

var _clock: GameClock
var _button: Button
var _time: Label
var _date: Label
var _sky: Label
var _weather: WeatherSystem
## The speed to go back to from pause.
var _resume_speed := GameClock.SPEED_NORMAL
var _held_msec := -1
var _held_fired := false
var _refresh_timer := 0.0


func _init() -> void:
	name = "SpeedControl"
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override(&"separation", 2)
	anchor_left = 1.0
	anchor_right = 1.0
	offset_right = -EDGE_MARGIN
	offset_top = TOP
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_button = Button.new()
	_button.name = "Speed"
	_button.flat = true
	_button.text = ""
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.tooltip_text = "Speed"
	_button.add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	_button.draw.connect(_draw_button)
	_button.button_down.connect(_on_down)
	_button.button_up.connect(_on_up)
	# Written by hand over the world: the time large, the date and weather in pencil under it.
	_time = _line(UITheme.FONT_TITLE, UITheme.CHALK, UITheme.display_font())
	_time.name = "Time"
	_date = _line(UITheme.FONT_SMALL - 4, UITheme.CHALK, UITheme.note_font())
	_date.name = "Date"
	_sky = _line(UITheme.FONT_SMALL - 4, Color(UITheme.CHALK, 0.85), UITheme.note_font())
	_sky.name = "Weather"
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, BUTTON_GAP)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gap)
	add_child(_button)
	resized.connect(place)


func _ready() -> void:
	get_viewport().size_changed.connect(place)
	place()


## Its corner, with its margins from the screen's safe area (SafeArea): on a
## phone with a notch, below it; held on its side, in from it.
func place() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	var view := viewport.get_visible_rect().size
	var right := EDGE_MARGIN + SafeArea.inset(viewport, SIDE_RIGHT, Vector2(TOP, TOP + size.y))
	var top := TOP + SafeArea.inset(viewport, SIDE_TOP, Vector2(view.x - right - size.x, view.x - right))
	if is_equal_approx(offset_right, -right) and is_equal_approx(offset_top, top):
		return
	offset_right = -right
	offset_top = top


func bind(clock: GameClock, weather: WeatherSystem = null) -> void:
	if _clock != null and _clock.speed_changed.is_connected(_on_speed_changed):
		_clock.speed_changed.disconnect(_on_speed_changed)
	_clock = clock
	_weather = weather
	if clock != null:
		clock.speed_changed.connect(_on_speed_changed)
		if not clock.is_paused():
			_resume_speed = clock.speed_index
	refresh()


func _exit_tree() -> void:
	if _clock != null and _clock.speed_changed.is_connected(_on_speed_changed):
		_clock.speed_changed.disconnect(_on_speed_changed)


func _process(delta: float) -> void:
	# A finger resting on the button: after the long-press time, the selector.
	if _held_msec >= 0 and not _held_fired and Time.get_ticks_msec() - _held_msec >= Config.interaction.long_press_ms:
		hold()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


## Brings the readout up to date with the clock.
func refresh() -> void:
	if _clock == null:
		return
	var time := _clock.format_time()
	if _clock.is_paused():
		time = "%s · %s" % [MemoryText.translate("SPEED_0"), time]
	if _time.text != time:
		_time.text = time
	var date := _clock.format_date(false)
	if _date.text != date:
		_date.text = date
	# The weather, and how warm it is: "Rain · 9°".
	var sky := UIText.weather_line(_weather.state, _weather.temperature()) if _weather != null else ""
	if _sky.text != sky:
		_sky.text = sky
		_sky.visible = sky != ""
	_button.queue_redraw()


## A tap: pause, or carry on at the speed it had before.
func toggle_pause() -> void:
	if _clock == null:
		return
	speed_chosen.emit(_resume_speed if _clock.is_paused() else GameClock.SPEED_PAUSE)


## A long press (also called by tests): ask for the selector; the release
## that follows is not a tap.
func hold() -> void:
	_held_fired = true
	_button.queue_redraw()
	selector_requested.emit()


func speed_button() -> Button:
	return _button


func time_text() -> String:
	return _time.text


func date_text() -> String:
	return _date.text


func weather_text() -> String:
	return _sky.text


## The speed a tap on the paused button goes back to.
func resume_speed() -> int:
	return _resume_speed


# --- internals ----------------------------------------------------------------------------------

func _line(font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	if font != null:
		label.add_theme_font_override(&"font", font)
	# Readable over grass, water and sky alike.
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override(&"shadow_offset_x", 2)
	label.add_theme_constant_override(&"shadow_offset_y", 3)
	label.add_theme_constant_override(&"shadow_outline_size", 6)
	add_child(label)
	return label


func _on_down() -> void:
	_held_msec = Time.get_ticks_msec()
	_held_fired = false
	_button.queue_redraw()


func _on_up() -> void:
	var was_tap := _held_msec >= 0 and not _held_fired
	_held_msec = -1
	_button.queue_redraw()
	if was_tap:
		toggle_pause()


func _on_speed_changed(index: int) -> void:
	if index != GameClock.SPEED_PAUSE:
		_resume_speed = index
	refresh()


func _draw_button() -> void:
	var paused := _clock != null and _clock.is_paused()
	var speed := _clock.speed_index if _clock != null else GameClock.SPEED_NORMAL
	# Paused: the sign to go on, lit. Going: the pause sign; faster, more marks beside it.
	if paused:
		HomeButton.draw_round(_button, 4, &"play", _button.button_pressed, LIT, LIT)
		return
	HomeButton.draw_round(_button, 4, &"pause", _button.button_pressed)
	var count := clampi(speed, 1, 3) - 1
	if count > 0:
		var center := _button.size * 0.5
		var radius := minf(_button.size.x, _button.size.y) * 0.5 - 7.0
		for i in count:
			var at := center + Vector2(radius * 0.55, -radius * 0.55 + i * radius * 0.3)
			_button.draw_circle(at, radius * 0.09, HomeButton.GLYPH)


## The sign for a speed, drawn on `canvas` around `center`: two bars for
## pause, one to three arrowheads for normal, fast and very fast.
static func draw_speed_glyph(canvas: CanvasItem, center: Vector2, unit: float, speed: int, color: Color) -> void:
	if speed <= GameClock.SPEED_PAUSE:
		for side: float in [-1.0, 1.0]:
			canvas.draw_rect(Rect2(center + Vector2(side * unit * 0.42 - unit * 0.2, -unit * 0.72), Vector2(unit * 0.4, unit * 1.44)), color)
		return
	var count := clampi(speed, 1, 3)
	var width := unit * (1.25 if count == 1 else 0.82)
	var total := width * count
	for i in count:
		var left := center.x - total * 0.5 + width * i + (unit * 0.1 if count == 1 else 0.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(left, center.y - unit * 0.78), Vector2(left + width, center.y), Vector2(left, center.y + unit * 0.78)]), color)
