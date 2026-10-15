class_name SettlingOverlay
extends UIPanel
## "The box is settling…" (M20): shown while the time the player was away is
## lived (a frame's worth at a time — OfflineSimulator.step), the days going by
## on it. Across the screen; nothing reaches the world meanwhile.

var _date: Label
var _bar: ProgressBar


func _init() -> void:
	super._init()
	name = "SettlingOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(0.03, 0.04, 0.06, 0.92)
	add_theme_stylebox_override(&"panel", backdrop)
	var middle := CenterContainer.new()
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(middle)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 24)
	column.custom_minimum_size = Vector2(560.0, 0.0)
	middle.add_child(column)
	# (Chalk on the dark, not the cards' ink: ink on it was all but unreadable
	# on the owner's phone, 2026-10-15.)
	var title := Label.new()
	title.name = "Title"
	title.text = "The box is settling…"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = UITheme.TITLE
	title.add_theme_color_override(&"font_color", UITheme.CHALK)
	column.add_child(title)
	_date = Label.new()
	_date.name = "Date"
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date.theme_type_variation = UITheme.CHALK_SMALL
	_date.add_theme_color_override(&"font_color", UITheme.CHALK_DIM)
	column.add_child(_date)
	_bar = ProgressBar.new()
	_bar.name = "Progress"
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, 18.0)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UITheme.CHALK, 0.18)
	track.set_corner_radius_all(9)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UITheme.CHALK
	fill.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override(&"background", track)
	_bar.add_theme_stylebox_override(&"fill", fill)
	column.add_child(_bar)


## How far it is (0 … 1), and the day it has come to.
func show_progress(share: float, date: String) -> void:
	_bar.value = clampf(share, 0.0, 1.0)
	_date.text = date


func progress() -> float:
	return _bar.value
