class_name MotionSettingsPanel
extends UIPanel
## The motion settings (bible §23.7, §30): motion controls on or off, how
## sensitive tilt, shake and rotation are, reduced motion, tilting with
## two fingers, and what counts as level (calibrate, use the current
## angle, forget).
##
## Every row is a setting (see Settings): changed here it is changed
## everywhere, at once.

## "Calibrate" was pressed: the calibration screen is wanted.
signal calibrate_requested

const MAX_WIDTH := 860.0
const EDGE_MARGIN := 32.0
const ROW_HEIGHT := UITheme.TOUCH_TARGET * 0.74
const STEP := 0.1
const SENSITIVITY_MIN := 0.5
const SENSITIVITY_MAX := 2.0
const REFRESH_INTERVAL_S := 0.5

const TOGGLES: Array = [
	[&"motion/enabled", "MOTION_ENABLED"],
	[&"motion/touch_tilt", "MOTION_TOUCH_TILT"],
	[&"accessibility/reduced_motion", "MOTION_REDUCED"],
]
const SLIDERS: Array = [
	[&"motion/tilt_sensitivity", "MOTION_TILT"],
	[&"motion/shake_sensitivity", "MOTION_SHAKE"],
	[&"motion/rotation_sensitivity", "MOTION_ROTATION"],
]

var _toggles: Dictionary = {} # setting key -> Button
var _values: Dictionary = {} # setting key -> Label
var _steppers: Dictionary = {} # setting key -> [less: Button, more: Button]
var _sensors: Label
var _level: Label
var _calibrate: Button
var _use_current: Button
var _forget: Button
var _close: CloseButton
var _refresh_timer := 0.0
var _settling := 0


func _init() -> void:
	super()
	name = "MotionSettings"
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = MemoryText.translate("MOTION_TITLE")
	title.theme_type_variation = UITheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	header.add_child(_close)
	_sensors = Label.new()
	_sensors.name = "Sensors"
	_sensors.theme_type_variation = UITheme.DIM
	_sensors.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_sensors)
	content.add_child(HSeparator.new())
	for entry: Array in TOGGLES:
		content.add_child(_toggle_row(entry[0], entry[1]))
	content.add_child(HSeparator.new())
	for entry: Array in SLIDERS:
		content.add_child(_slider_row(entry[0], entry[1]))
	content.add_child(HSeparator.new())
	# What counts as level.
	var level_row := HBoxContainer.new()
	content.add_child(level_row)
	level_row.add_child(_row_label(MemoryText.translate("MOTION_LEVEL")))
	_level = Label.new()
	_level.name = "Level"
	_level.theme_type_variation = UITheme.DIM
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_row.add_child(_level)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 12)
	content.add_child(buttons)
	_calibrate = _chip("Calibrate", MemoryText.translate("MOTION_CALIBRATE"))
	_calibrate.pressed.connect(func() -> void: calibrate_requested.emit())
	buttons.add_child(_calibrate)
	_forget = _chip("Forget", MemoryText.translate("MOTION_FORGET"))
	_forget.pressed.connect(func() -> void:
		SensorManager.clear_calibration()
		refresh())
	buttons.add_child(_forget)
	_use_current = _chip("UseCurrent", MemoryText.translate("MOTION_USE_CURRENT"))
	_use_current.pressed.connect(func() -> void:
		SensorManager.calibrate_to_current()
		refresh())
	content.add_child(_use_current)


func _ready() -> void:
	Settings.setting_changed.connect(_on_setting_changed)
	SensorManager.availability_changed.connect(_on_availability_changed)
	get_viewport().size_changed.connect(layout)
	refresh()
	layout()


func _exit_tree() -> void:
	if Settings.setting_changed.is_connected(_on_setting_changed):
		Settings.setting_changed.disconnect(_on_setting_changed)
	if SensorManager.availability_changed.is_connected(_on_availability_changed):
		SensorManager.availability_changed.disconnect(_on_availability_changed)


func _process(delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


## Brings every row up to date with the settings and the sensors.
func refresh() -> void:
	var no_sensors: bool = SensorManager.availability == SensorManager.Availability.UNAVAILABLE
	var enabled := bool(Settings.get_value(&"motion/enabled"))
	for key: StringName in _toggles:
		var on := bool(Settings.get_value(key))
		var toggle: Button = _toggles[key]
		toggle.disabled = false
		# Without sensors the box is tilted with two fingers whatever the switch says.
		if key == &"motion/touch_tilt" and no_sensors and enabled:
			on = true
			toggle.disabled = true
		_show_toggle(toggle, on)
	for key: StringName in _values:
		var value := float(Settings.get_value(key))
		(_values[key] as Label).text = "%d %%" % roundi(value * 100.0)
		(_steppers[key][0] as Button).disabled = value <= SENSITIVITY_MIN + 0.001
		(_steppers[key][1] as Button).disabled = value >= SENSITIVITY_MAX - 0.001
	var sensors_key := "MOTION_SENSORS_UNKNOWN"
	if not enabled:
		sensors_key = "MOTION_SENSORS_OFF"
	elif no_sensors:
		sensors_key = "MOTION_SENSORS_NO"
	elif SensorManager.availability == SensorManager.Availability.AVAILABLE:
		sensors_key = "MOTION_SENSORS_YES"
	if _sensors.text != MemoryText.translate(sensors_key):
		_sensors.text = MemoryText.translate(sensors_key)
		_settling = 3 # (it may take more lines, or fewer)
	var calibrated: bool = SensorManager.is_calibrated()
	_level.text = MemoryText.translate("MOTION_LEVEL_CALIBRATED" if calibrated else "MOTION_LEVEL_HELD")
	_forget.visible = calibrated
	var usable := enabled and not no_sensors
	_calibrate.disabled = not usable
	_use_current.disabled = not usable


## In the middle of the screen, as wide as it allows.
func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - 2.0 * EDGE_MARGIN, 200.0, MAX_WIDTH)
	# (A label that wraps has to be told how wide it is, or it stands as tall as its words.)
	_sensors.custom_minimum_size.x = custom_minimum_size.x - 60.0
	reset_size()
	position = ((view - size) * 0.5).max(Vector2.ZERO)


# --- for whoever presses (and tests) ----------------------------------------------------------------

func toggle(key: StringName) -> Button:
	return _toggles.get(key)


## The buttons that make a sensitivity less (-1) or more (+1).
func stepper(key: StringName, direction: int) -> Button:
	var pair: Array = _steppers.get(key, [])
	return pair[0 if direction < 0 else 1] if pair.size() == 2 else null


func value_text(key: StringName) -> String:
	return (_values[key] as Label).text if _values.has(key) else ""


func sensors_text() -> String:
	return _sensors.text


func level_text() -> String:
	return _level.text


func button(which: StringName) -> Button:
	match which:
		&"calibrate":
			return _calibrate
		&"use_current":
			return _use_current
		&"forget":
			return _forget
		&"close":
			return _close
	return null


# --- internals --------------------------------------------------------------------------------------

func _row_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _chip(chip_name: String, text: String) -> Button:
	var chip := Button.new()
	chip.name = chip_name
	chip.text = text
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	for state: StringName in [&"normal", &"hover", &"disabled"]:
		chip.add_theme_stylebox_override(state, FollowBanner._style(false))
	chip.add_theme_color_override(&"font_disabled_color", UITheme.INK_DIM)
	return chip


func _toggle_row(key: StringName, text_key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label(MemoryText.translate(text_key)))
	var toggle := _chip("Toggle_" + String(key).replace("/", "_"), "")
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.custom_minimum_size = Vector2(170.0, ROW_HEIGHT)
	toggle.pressed.connect(func() -> void:
		Settings.set_value(key, not bool(Settings.get_value(key)))
		AudioManager.play_ui(&"ui_tap")
		refresh())
	row.add_child(toggle)
	_toggles[key] = toggle
	return row


func _show_toggle(toggle: Button, on: bool) -> void:
	toggle.text = MemoryText.translate("MOTION_ON" if on else "MOTION_OFF")
	for state: StringName in [&"normal", &"hover", &"disabled"]:
		toggle.add_theme_stylebox_override(state, FollowBanner._style(on))


func _slider_row(key: StringName, text_key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label(MemoryText.translate(text_key)))
	var less := _chip("Less_" + String(key).replace("/", "_"), "-")
	var more := _chip("More_" + String(key).replace("/", "_"), "+")
	var value := Label.new()
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(130.0, 0.0)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for stepper_button: Button in [less, more]:
		stepper_button.size_flags_horizontal = Control.SIZE_SHRINK_END
		stepper_button.custom_minimum_size = Vector2(ROW_HEIGHT, ROW_HEIGHT)
		stepper_button.add_theme_font_size_override(&"font_size", UITheme.FONT_BODY)
	less.pressed.connect(_step.bind(key, -STEP))
	more.pressed.connect(_step.bind(key, STEP))
	row.add_child(less)
	row.add_child(value)
	row.add_child(more)
	_values[key] = value
	_steppers[key] = [less, more]
	return row


func _step(key: StringName, by: float) -> void:
	var value := snappedf(clampf(float(Settings.get_value(key)) + by, SENSITIVITY_MIN, SENSITIVITY_MAX), STEP)
	Settings.set_value(key, value)
	AudioManager.play_ui(&"ui_tap")
	refresh()


func _on_setting_changed(_key: StringName, _value: Variant) -> void:
	refresh()


func _on_availability_changed(_available: bool) -> void:
	refresh()
