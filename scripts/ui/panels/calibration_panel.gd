class_name CalibrationPanel
extends UIPanel
## Calibrating the motion sensors (bible §23.7): "Place your phone flat."
## → "Hold still." → "Calibration complete." — or, with one button, the
## angle the device is held at now as level. A bubble shows how it lies.
##
## The rules are in Calibration; the readings come from the SensorManager
## as it takes them; what is found is kept by the SensorManager (in the
## settings).

## The panel is closing; `calibrated`: a level was found and is in use.
signal finished(calibrated: bool)

const MAX_WIDTH := 780.0
const EDGE_MARGIN := 40.0
## The bubble is at the rim at this many degrees off flat.
const BUBBLE_DEGREES := 30.0
const REFRESH_INTERVAL_S := 0.25

@onready var _title: Label = %Title
@onready var _step: Label = %Step
@onready var _level: Control = %Level
@onready var _progress: ProgressBar = %Progress
@onready var _use_current: Button = %UseCurrent
@onready var _done: Button = %Done
@onready var _close: Button = %Close

var calibration := Calibration.new()
var _applied := false
var _bubble := Vector2.ZERO
var _has_reading := false
var _refresh_timer := 0.0
var _settling := 3


func _ready() -> void:
	_title.text = MemoryText.translate("CAL_TITLE")
	_use_current.text = MemoryText.translate("MOTION_USE_CURRENT")
	# Nothing shows through it (it lies over the settings it was opened from).
	var card := StyleBoxFlat.new()
	card.bg_color = Color(UITheme.CARD, 1.0)
	card.border_color = UITheme.RIM
	card.set_border_width_all(3)
	card.set_corner_radius_all(30)
	card.set_content_margin_all(22)
	add_theme_stylebox_override(&"panel", card)
	for chip: Button in [_use_current, _done]:
		chip.custom_minimum_size.y = UITheme.TOUCH_TARGET * 0.74
		chip.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		for state: StringName in [&"normal", &"hover"]:
			chip.add_theme_stylebox_override(state, FollowBanner._style(false))
	var trough := StyleBoxFlat.new()
	trough.bg_color = UITheme.LINE
	trough.set_corner_radius_all(11)
	var filled := StyleBoxFlat.new()
	filled.bg_color = StarButton.LIT
	filled.set_corner_radius_all(11)
	_progress.add_theme_stylebox_override(&"background", trough)
	_progress.add_theme_stylebox_override(&"fill", filled)
	_use_current.pressed.connect(use_current_angle)
	_done.pressed.connect(close)
	_close.pressed.connect(close)
	_level.draw.connect(_draw_level)
	closed.connect(func() -> void: finished.emit(_applied))
	SensorManager.sampled.connect(_on_sampled)
	get_viewport().size_changed.connect(layout)
	calibration.begin(true)
	refresh()
	layout()


func _exit_tree() -> void:
	if SensorManager.sampled.is_connected(_on_sampled):
		SensorManager.sampled.disconnect(_on_sampled)


func _process(delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


## "Use current angle as level": no laying flat — hold still as it is held.
func use_current_angle() -> void:
	if calibration.state == Calibration.State.DONE:
		return
	calibration.begin(false)
	refresh()


func is_done() -> bool:
	return calibration.state == Calibration.State.DONE


func step_text() -> String:
	return _step.text


func progress() -> float:
	return _progress.value


func button(which: StringName) -> Button:
	match which:
		&"use_current":
			return _use_current
		&"done":
			return _done
		&"close":
			return _close
	return null


## Brings what is shown up to date with how the calibration stands.
func refresh() -> void:
	if not is_node_ready():
		return
	var key := "CAL_PLACE"
	match calibration.state:
		Calibration.State.HOLD:
			key = "CAL_MOVED" if calibration.moved else "CAL_HOLD"
		Calibration.State.DONE:
			key = "CAL_DONE"
	# Nothing to calibrate with.
	var blocked := ""
	if calibration.state != Calibration.State.DONE and not _has_reading:
		if not bool(Settings.get_value(&"motion/enabled")):
			blocked = "CAL_OFF"
		elif SensorManager.availability == SensorManager.Availability.UNAVAILABLE:
			blocked = "CAL_NO_SENSORS"
	var words := MemoryText.translate(blocked if blocked != "" else key)
	if _step.text != words or _level.visible != (blocked == ""):
		_settling = 3 # (what is shown changes: it is laid out anew)
	_step.text = words
	_progress.value = calibration.progress
	_progress.visible = blocked == ""
	_level.visible = blocked == ""
	_use_current.visible = blocked == "" and calibration.state != Calibration.State.DONE and calibration.wants_flat()
	_done.text = MemoryText.translate("CAL_CLOSE" if calibration.state == Calibration.State.DONE or blocked != "" else "CAL_CANCEL")
	_level.queue_redraw()


## In the middle of the screen, as wide as it allows.
func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - 2.0 * EDGE_MARGIN, 200.0, MAX_WIDTH)
	# (A label that wraps has to be told how wide it is, or it stands as tall as its words.)
	_step.custom_minimum_size.x = custom_minimum_size.x - 60.0
	reset_size()
	position = ((view - size) * 0.5).max(Vector2.ZERO)


func _on_sampled(gravity: Vector3, delta: float) -> void:
	if is_closing() or calibration.state == Calibration.State.DONE:
		return
	if MotionFilter.is_usable(gravity) and gravity.length() > 0.001:
		_has_reading = true
		_bubble = MotionFilter.angles(gravity.normalized(), MotionFilter.FLAT) / BUBBLE_DEGREES
	if calibration.push(gravity, delta) == Calibration.State.DONE:
		_applied = SensorManager.calibrate_to(calibration.result)
		Haptics.medium()
		AudioManager.play_ui(&"ui_tap")
	refresh()


## A bubble level: the ring is "flat", the bubble where the device leans.
func _draw_level() -> void:
	var center := _level.size * 0.5
	var radius := minf(_level.size.x, _level.size.y) * 0.5 - 8.0
	var done := calibration.state == Calibration.State.DONE
	_level.draw_circle(center, radius, Color(1.0, 1.0, 1.0, 0.05))
	_level.draw_arc(center, radius, 0.0, TAU, 64, UITheme.RIM, 3.0, true)
	_level.draw_arc(center, radius * 0.3, 0.0, TAU, 32, UITheme.LINE, 2.0, true)
	_level.draw_line(center - Vector2(radius, 0.0), center + Vector2(radius, 0.0), UITheme.LINE, 2.0)
	_level.draw_line(center - Vector2(0.0, radius), center + Vector2(0.0, radius), UITheme.LINE, 2.0)
	if not _has_reading:
		return
	# (A bubble rises: it goes to the side that is higher.)
	var where := (Vector2(-_bubble.x, _bubble.y)).limit_length(1.0) * (radius - 26.0)
	_level.draw_circle(center + where, 26.0, StarButton.LIT if done or calibration.state == Calibration.State.HOLD else UITheme.INK_DIM)
